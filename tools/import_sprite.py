#!/usr/bin/env python3
"""Turn an image into a sprite the fox can wear.

    python3 tools/import_sprite.py ~/Downloads/whatever.png --name foxbot

Image generators hand back "pixel art" that isn't: rendered at high resolution
with soft, anti-aliased edges and tens of thousands of colours, plus a faint
halo where the background was keyed out. Scaled down to 96 points that reads as
mush. This crops to the artwork, throws away the halo, snaps every pixel to a
small palette, and writes it at the size it will actually be drawn — so the
edges stay hard.
"""

import argparse
import os

from PIL import Image

# The fox's palette. Everything gets snapped to its nearest member, which is
# what turns a smooth gradient back into a hard edge.
INK = [
    (40, 30, 52),      # outline
    (22, 17, 48),      # eyes, deepest shadow
    (252, 89, 0),      # fur
    (216, 66, 2),      # fur, shaded
    (250, 130, 40),    # fur, lit
    (254, 237, 182),   # cream
    (247, 202, 122),   # cream, shaded
]

# 96 points wide on screen; twice that so it stays sharp on a Retina display.
TARGET_WIDTH = 192


def nearest(colour):
    r, g, b = colour
    return min(INK, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)


def snap(image):
    """Quantise to the palette, leaving transparent pixels alone."""
    out = image.copy()
    pixels = out.load()
    cache = {}
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            key = (r, g, b)
            if key not in cache:
                cache[key] = nearest(key)
            pixels[x, y] = cache[key] + (255,)
    return out


def convert(path, width=TARGET_WIDTH, cutoff=140):
    image = Image.open(path).convert("RGBA")

    # A keyed-out background leaves a soft fringe. Anything not solidly opaque
    # is fringe, not artwork.
    alpha = image.getchannel("A").point(lambda v: 255 if v >= cutoff else 0)
    image.putalpha(alpha)

    box = image.getbbox()
    if not box:
        raise SystemExit("that image is entirely transparent")
    image = image.crop(box)

    height = max(1, round(image.height * width / image.width))
    image = image.resize((width, height), Image.BOX)

    # Averaging on the way down softens the edges again, so re-threshold and
    # re-snap afterwards rather than before.
    alpha = image.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    image.putalpha(alpha)
    return snap(image)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("--name", default="foxbot")
    parser.add_argument("--width", type=int, default=TARGET_WIDTH)
    parser.add_argument("--cutoff", type=int, default=140)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = args.out or os.path.join(here, "hammerspoon", "foxbot", "assets",
                                   args.name + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    sprite = convert(args.source, args.width, args.cutoff)
    sprite.save(out)

    colours = len(sprite.getcolors(maxcolors=65536) or [])
    print("%s  %dx%d  %d colours" % (out, sprite.width, sprite.height, colours))


if __name__ == "__main__":
    main()
