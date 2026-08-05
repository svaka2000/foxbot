#!/usr/bin/env python3
"""Cut a 3x3 sprite sheet into Foxbot's mood drawings.

    python3 tools/slice_sheet.py ~/Downloads/sheet.png
    python3 tools/slice_sheet.py ~/Downloads/sheet.png --coat vixen --dry-run

Expects the nine poses in reading order:

    running   focused   asking
    settled   cheering  broken
    weary     dozing    sleeping

Cells are found by looking for the empty gutters between them rather than by
assuming exact thirds, because image models never quite lay a grid out evenly.
Anything floating beside a pose — a "z", a question mark, a sparkle — stays with
it, which is the reason this splits on gutters instead of on connected blobs.

Each cell then goes through the same clean-up as tools/import_sprite.py.
"""

import argparse
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_sprite import key_out, snap, TARGET_WIDTH   # noqa: E402

MOODS = [
    "running", "focused", "asking",
    "settled", "cheering", "broken",
    "weary", "dozing", "sleeping",
]


def bands(counts, want, floor):
    """Split a projection into `want` runs of content separated by gaps.

    `counts` is how much ink sits in each column (or row). A gutter is a stretch
    where that stays at or below `floor`.
    """
    runs, start = [], None
    for i, value in enumerate(counts):
        if value > floor and start is None:
            start = i
        elif value <= floor and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(counts)))

    if len(runs) == want:
        return runs

    # Too many runs means a pose broke into pieces across a thin gap; merge the
    # closest neighbours until the count is right.
    while len(runs) > want:
        gaps = [(runs[i + 1][0] - runs[i][1], i) for i in range(len(runs) - 1)]
        _, at = min(gaps)
        runs[at] = (runs[at][0], runs[at + 1][1])
        del runs[at + 1]

    return runs if len(runs) == want else None


def even(total, want):
    step = total / want
    return [(round(i * step), round((i + 1) * step)) for i in range(want)]


def cells(mask, rows=3, columns=3, tolerance=0.004):
    w, h = mask.size
    pixels = mask.load()

    down = [0] * w
    across = [0] * h
    for y in range(h):
        for x in range(w):
            if pixels[x, y]:
                down[x] += 1
                across[y] += 1

    xs = bands(down, columns, max(1, int(h * tolerance)))
    ys = bands(across, rows, max(1, int(w * tolerance)))

    if xs is None:
        print("  ! couldn't find %d columns — falling back to even thirds" % columns)
        xs = even(w, columns)
    if ys is None:
        print("  ! couldn't find %d rows — falling back to even thirds" % rows)
        ys = even(h, rows)

    return [(x0, y0, x1, y1) for (y0, y1) in ys for (x0, x1) in xs]


def prepare(sheet, cutoff=140):
    image = Image.open(sheet).convert("RGBA")
    if image.getchannel("A").getextrema()[0] == 255:
        image, keyed = key_out(image)
        if keyed:
            print("  keyed out a flat #%02X%02X%02X background" % keyed)
        else:
            print("  ! no transparency and no flat background — nothing to cut")
    alpha = image.getchannel("A").point(lambda v: 255 if v >= cutoff else 0)
    image.putalpha(alpha)
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sheet")
    parser.add_argument("--coat", default="foxbot")
    parser.add_argument("--width", type=int, default=TARGET_WIDTH)
    parser.add_argument("--cutoff", type=int, default=140)
    parser.add_argument("--outdir", default=None)
    parser.add_argument("--dry-run", action="store_true",
                        help="report what it found without writing anything")
    args = parser.parse_args()

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = args.outdir or os.path.join(here, "hammerspoon", "foxbot", "assets")

    sheet = prepare(args.sheet, args.cutoff)
    print("  sheet %dx%d" % sheet.size)

    written = 0
    for box, mood in zip(cells(sheet.getchannel("A")), MOODS):
        cell = sheet.crop(box)
        trimmed = cell.getbbox()
        if not trimmed:
            print("  %-9s EMPTY — skipped" % mood)
            continue
        cell = cell.crop(trimmed)

        height = max(1, round(cell.height * args.width / cell.width))
        cell = cell.resize((args.width, height), Image.BOX)
        alpha = cell.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        cell.putalpha(alpha)
        cell = snap(cell)

        name = "%s-%s.png" % (args.coat, mood)
        if args.dry_run:
            print("  %-9s %dx%d  (would write %s)" % (mood, cell.width, cell.height, name))
            continue

        os.makedirs(outdir, exist_ok=True)
        cell.save(os.path.join(outdir, name))
        print("  %-9s %dx%d  -> %s" % (mood, cell.width, cell.height, name))
        written += 1

    if not args.dry_run:
        print("\n%d sprites written to %s" % (written, outdir))
        print("Copy them across and reload:")
        print("  cp %s/*.png ~/.hammerspoon/foxbot/assets/" % outdir)


if __name__ == "__main__":
    main()
