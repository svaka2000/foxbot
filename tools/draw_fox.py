#!/usr/bin/env python3
"""Draw the fox.

The sprite is authored here as a grid rather than painted in an editor, so it
is diffable, tweakable a pixel at a time, and comes out with real transparency
and an exact palette every time.

    python3 tools/draw_fox.py            -> hammerspoon/foxbot/assets/foxbot.png
    python3 tools/draw_fox.py --scale 8  -> smaller file, same drawing
"""

import argparse
import os

from PIL import Image

# .  transparent      K  outline        O  fur
# D  fur, shaded      C  cream          W  highlight
PALETTE = {
    "K": (46, 31, 46, 255),
    "O": (242, 86, 10, 255),
    "D": (198, 63, 6, 255),
    "C": (251, 227, 184, 255),
    "W": (255, 255, 255, 255),
    ".": (0, 0, 0, 0),
}

# 18 wide. Ears grow out of the skull rather than floating beside it, the
# outline never breaks, and there is no tail — from the front a sitting fox
# doesn't have one to show, and a stray diagonal off the side just reads as a
# rendering fault at 96 pixels.
FOX = [
    "..KK..........KK..",
    "..KOK........KOK..",
    "..KOOK......KOOK..",
    "..KOCOK....KOCOK..",
    "..KOCOKKKKKKOCOK..",
    "..KOOOOOOOOOOOOK..",
    ".KOOOOOOOOOOOOOOK.",
    ".KOOKKOOOOOOKKOOK.",
    ".KOOKKOOOOOOKKOOK.",
    ".KOOOOOOKKOOOOOOK.",
    ".KOCCCCCKKCCCCCOK.",
    ".KOCCCCCCCCCCCCOK.",
    "..KOCCCCCCCCCCOK..",
    "..KKOOOOOOOOOOKK..",
    "...KOOOOOOOOOOK...",
    "..KOOOOOOOOOOOOK..",
    ".KOOOOCCCCCCOOOOK.",
    ".KOOOOCCCCCCOOOOK.",
    ".KOOOOOOOOOOOOOOK.",
    ".KKCCKKOOOOKKCCKK.",
    "..KCCK......KCCK..",
    "...KK........KK...",
]

# Catchlights, so the eyes read as eyes rather than as two dark holes.
GLINTS = ((4, 7), (12, 7))


def draw(scale):
    height = len(FOX)
    width = max(len(row) for row in FOX)

    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = image.load()

    for y, row in enumerate(FOX):
        for x, mark in enumerate(row):
            colour = PALETTE.get(mark)
            if colour and colour[3]:
                pixels[x, y] = colour

    for x, y in GLINTS:
        pixels[x, y] = PALETTE["W"]

    # Nearest-neighbour, or the pixels turn to mush.
    return image.resize((width * scale, height * scale), Image.NEAREST)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", type=int, default=14)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = args.out or os.path.join(here, "hammerspoon", "foxbot", "assets", "classic.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    image = draw(args.scale)
    image.save(out)
    print("%s  %dx%d" % (out, image.width, image.height))


if __name__ == "__main__":
    main()
