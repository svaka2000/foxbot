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
    parser.add_argument("--base", default=None,
                        help="the coat's default sprite, refitted to match the "
                             "sheet so he doesn't change size when resting")
    parser.add_argument("--dry-run", action="store_true",
                        help="report what it found without writing anything")
    args = parser.parse_args()

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = args.outdir or os.path.join(here, "hammerspoon", "foxbot", "assets")

    sheet = prepare(args.sheet, args.cutoff)
    print("  sheet %dx%d" % sheet.size)

    # Crop every pose to its own content first, but don't scale anything yet.
    poses = []
    for box, mood in zip(cells(sheet.getchannel("A")), MOODS):
        cell = sheet.crop(box)
        trimmed = cell.getbbox()
        if not trimmed:
            print("  %-9s EMPTY — skipped" % mood)
            continue
        poses.append((mood, cell.crop(trimmed)))

    if not poses:
        raise SystemExit("nothing found in that sheet")

    # One scale for all of them, and one canvas.
    #
    # Scaling each pose to fill the same width independently would enlarge
    # whichever was drawn smallest, so he'd change size every time his mood
    # changed. Instead: one factor taken from the widest pose, applied to all,
    # then everything padded to a shared box and sat on a shared floor. His feet
    # stay on the same line and only the pose changes, which is the whole point.
    widest = max(pose.width for _, pose in poses)
    tallest = max(pose.height for _, pose in poses)
    scale = args.width / widest
    canvas = (args.width, max(1, round(tallest * scale)))
    print("  scaling everything by %.3f -> a shared %dx%d frame" % (scale, *canvas))

    written = 0
    for mood, pose in poses:
        size = (max(1, round(pose.width * scale)), max(1, round(pose.height * scale)))
        pose = pose.resize(size, Image.BOX)

        alpha = pose.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        pose.putalpha(alpha)
        pose = snap(pose)

        framed = Image.new("RGBA", canvas, (0, 0, 0, 0))
        framed.alpha_composite(pose, ((canvas[0] - pose.width) // 2,
                                      canvas[1] - pose.height))

        name = "%s-%s.png" % (args.coat, mood)
        if args.dry_run:
            print("  %-9s drawn %dx%d in a %dx%d frame  (would write %s)"
                  % (mood, pose.width, pose.height, *canvas, name))
            continue

        os.makedirs(outdir, exist_ok=True)
        framed.save(os.path.join(outdir, name))
        print("  %-9s drawn %dx%d in a %dx%d frame  -> %s"
              % (mood, pose.width, pose.height, *canvas, name))
        written += 1

    # The default sprite was made separately, so it is drawn at its own scale.
    # Left alone it would be the one pose that changes size — and it's the one
    # he spends most of his time in. Refit it to the sheet's typical sitting
    # width so resting matches everything else.
    if args.base:
        base = Image.open(args.base).convert("RGBA")
        if base.getchannel("A").getextrema()[0] == 255:
            base, _ = key_out(base)
        alpha = base.getchannel("A").point(lambda v: 255 if v >= args.cutoff else 0)
        base.putalpha(alpha)
        base = base.crop(base.getbbox())

        # Median rather than mean: the outliers here are a pose with its paws
        # thrown wide and one curled up asleep, and neither is how he usually
        # sits.
        widths = sorted(round(p.width * scale) for _, p in poses)
        typical = widths[len(widths) // 2]

        fitted = max(1, round(base.height * typical / base.width))
        base = base.resize((typical, fitted), Image.BOX)
        alpha = base.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        base.putalpha(alpha)
        base = snap(base)

        framed = Image.new("RGBA", canvas, (0, 0, 0, 0))
        framed.alpha_composite(base, ((canvas[0] - base.width) // 2,
                                      canvas[1] - base.height))
        name = "%s.png" % args.coat
        if args.dry_run:
            print("  %-9s drawn %dx%d in a %dx%d frame  (would rewrite %s)"
                  % ("resting", base.width, base.height, *canvas, name))
        else:
            framed.save(os.path.join(outdir, name))
            print("  %-9s drawn %dx%d in a %dx%d frame  -> %s"
                  % ("resting", base.width, base.height, *canvas, name))
            written += 1

    if not args.dry_run:
        print("\n%d sprites written to %s" % (written, outdir))
        print("Copy them across and reload:")
        print("  cp %s/*.png ~/.hammerspoon/foxbot/assets/" % outdir)


if __name__ == "__main__":
    main()
