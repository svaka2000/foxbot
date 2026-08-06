# Drawing the shop

Prompts for everything in [DONUTS.md](DONUTS.md) that needs art.

Same pipeline as the fox: one 3×3 sheet per animal, sliced by
`tools/slice_sheet.py`. Hats are single small images.

---

## A new animal

Each one is the [main sheet prompt](SHEET-PROMPT.md) with the character swapped.
**Attach `foxbot.png` as the reference anyway** — not so it copies the fox, but
so it matches his pixel scale, outline weight, framing and palette discipline.

Paste the whole sheet prompt, then replace its opening paragraph with one of
these, and its palette block with the one given.

### Tabby — 400

```text
Attached is a pixel-art fox sprite from my desktop app. I need a sheet for a
DIFFERENT character in EXACTLY the same style, scale, framing and outline
weight — but it is a small grey tabby cat, not a fox.

The cat: rounder head than the fox, small triangular ears set wide, dark
tabby stripes on the forehead and back, a white chest and paws, and a
permanently unimpressed half-lidded expression even when pleased.

ONLY these seven colours:
  #2A2530  outline and eyes
  #17141C  darkest accent
  #8C8F99  fur
  #6E717A  fur in shadow
  #A8ABB5  fur highlight
  #F2F0EC  white chest and paws
  #D6D3CC  white in shadow
```

### Corgi — 400

```text
…it is a corgi puppy, not a fox.

The corgi: broad low body, very short legs, enormous upright rounded ears, a
white blaze up the muzzle, white chest and paws, and a mouth that is open and
delighted in almost every pose. Absurdly pleased to be here.

ONLY these seven colours:
  #2E2028  outline and eyes
  #191119  darkest accent
  #D98A3D  fur
  #B36A26  fur in shadow
  #E8A85C  fur highlight
  #FBF1DE  white blaze, chest and paws
  #E5D3B4  white in shadow
```

### Raccoon — 550

```text
…it is a raccoon, not a fox.

The raccoon: a bold black mask across the eyes, small rounded ears, a
grey-brown body, and a thick ringed tail visible in most poses. Nocturnal and
faintly suspicious — even the happy poses look like it is about to take
something.

ONLY these seven colours:
  #241F2B  outline, mask and eyes
  #14111A  darkest accent
  #7C7688  fur
  #5C5768  fur in shadow
  #968FA3  fur highlight
  #E8E4DC  muzzle and ring highlights
  #C4BFB4  the same in shadow
```

### Axolotl — 550

```text
…it is an axolotl, not a fox.

The axolotl: pale pink, wide flat head, tiny black dot eyes set far apart,
six feathery external gills fanning out from behind the head, tiny stubby
arms, and a permanent gentle smile. Slightly damp-looking. Very calm.

ONLY these seven colours:
  #3A2430  outline and eyes
  #1F1420  darkest accent
  #F2A8C0  body
  #D9819F  body in shadow
  #FBC4D6  body highlight
  #FFE9F0  belly and gill tips
  #E8C3D2  the same in shadow
```

### Crow — 700

```text
…it is a crow, not a fox.

The crow: glossy black, a heavy straight beak, a single bright eye visible
from the front, feathers that read as a few chunky blocks rather than many
small ones, and a head tilt in most poses. Far too clever. In the celebrating
pose it is holding something small and shiny.

ONLY these seven colours:
  #1A1622  outline
  #0D0B12  darkest accent
  #34304A  feathers
  #262238  feathers in shadow
  #4A4666  feather highlight
  #E8B84C  beak, feet and eye
  #C4952F  the same in shadow
```

### Ghost fox — 900

```text
…it is the SAME fox as the reference, but a ghost.

Keep his exact shape, ears, muzzle and proportions. Render him translucent
and cold: pale blue-white instead of orange, a soft glow instead of a hard
outline, and the lower body fading out into wisps rather than ending in paws.
Eyes are pale and empty. Friendly, not frightening.

ONLY these seven colours:
  #2A3350  outline
  #1A2138  darkest accent
  #7FA8D9  body
  #5E82AD  body in shadow
  #A6C8EE  body highlight
  #E8F4FF  brightest wisps and eyes
  #C2DCF2  the same in shadow
```

---

## Coats — recolouring the fox you have

These do not need a new sheet. Run the existing fox sheet through the importer
with a different palette:

```bash
python3 tools/import_sprite.py ~/Downloads/FoxEmos.png --name arctic
```

…after editing `INK` in `tools/import_sprite.py` to the coat's palette. Same
drawing, different animal-in-a-different-climate.

| coat | outline | fur | shadow | highlight | cream | cream shadow |
|---|---|---|---|---|---|---|
| **Arctic** | `#26303F` | `#DCE9F5` | `#B4C6D9` | `#F2F8FF` | `#FFFFFF` | `#D5E2EE` |
| **Melanistic** | `#141018` | `#3A3040` | `#26202C` | `#4E4256` | `#E8A93C` | `#C4882A` |
| **Fennec** | `#3A2E22` | `#E8C88A` | `#C9A566` | `#F5DEAC` | `#FFF6E4` | `#E4D2B4` |
| **Nine-tails** | `#2E1F2E` | `#F2560A` | `#C63F06` | `#FA8228` | `#FBE3B8` | `#F7CA7A` |

Nine-tails keeps the fox palette but needs its own sheet — the tails have to be
drawn. Use the main sheet prompt with: *"…the same fox, but with nine tails
fanned out behind him in every pose, each one tipped in cream."*

---

## Hats

One image each, not a sheet. They are drawn over whichever sprite is equipped,
so they must work on a fox, a cat, a corgi and a crow.

```text
A single pixel-art hat, drawn in the same chunky pixel style as the attached
sprite: hard edges, no anti-aliasing, a thick dark outline all the way round.

THE HAT: <one line from the table below>

- Nothing but the hat. No head, no character, no stand, no shadow.
- Fully transparent background.
- Drawn straight-on, front view, as it would sit on a head roughly 40 pixels
  wide — so its widest point should be about 44 pixels, slightly wider than
  the head it sits on.
- Leave the bottom edge flat and open, as though it has been cut off where it
  meets the skull.
- No more than six colours.
- It must read clearly at 40 pixels wide.
```

| hat | the one line |
|---|---|
| Tiny beanie | a small ribbed knitted beanie with a folded brim and a bobble on top |
| Party hat | a striped conical party hat with a small pom-pom at the tip |
| Headphones | over-ear headphones, the band arcing across the top and one cup each side |
| Reading glasses | round wire-frame reading glasses, lenses clear, sitting low |
| Crown | a small five-point gold crown with three round jewels |
| Tiny hard hat | a yellow construction hard hat with a front brim and a centre ridge |

Import each with:

```bash
python3 tools/import_sprite.py ~/Downloads/hat.png --name hat-beanie --width 88
```

---

## Toys

Same rules as hats — one small object, transparent, no character.

| toy | prompt line |
|---|---|
| Ball | a small striped rubber ball, side view |
| Donut | a pink-iced donut with sprinkles, side view |
| Tiny laptop | a small open laptop seen from a low front angle, screen faintly lit |
| Cardboard box | an open cardboard box seen from the front, flaps out, big enough to sit in |
| Wreath | a green holly wreath with a red bow |
| Pumpkin | a small carved pumpkin with a lit face |

---

## Checking a sheet before you commit to it

```bash
python3 tools/slice_sheet.py ~/Downloads/sheet.png --dry-run
```

Nine cells with sensible sizes means it's good. Then:

```bash
python3 tools/slice_sheet.py ~/Downloads/sheet.png --coat tabby \
  --base ~/Downloads/tabby-base.png
cp hammerspoon/foxbot/assets/*.png ~/.hammerspoon/foxbot/assets/
```

`--base` matters: it refits the default sprite to the sheet's scale, so the
resting pose doesn't change size relative to the other nine.
