# Blocky pixel-art speech bubbles for foxbot notes

## 0. What this replaces

`panel.lua:131-136` draws each note as one `hs.canvas` rectangle with
`roundedRectRadii = {12, 12}`, `action = "strokeAndFill"`, `strokeWidth = 1`.
That is deleted. In its place, every note is drawn as a **grid of axis-aligned
filled rectangles on a whole-point pixel grid**: a rust chamfered 2-unit border,
an opaque cream interior, a stepped tail on the bottom edge nearest the fox, and
a hard grey drop shadow one unit down-right.

The whole geometry moves into a new **pure** module, `hammerspoon/foxbot/bubble.lua`,
which requires nothing (not `hs`, not `Palette`), takes numbers, and returns a
flat list of rectangles tagged with a *tone name*. `panel.lua` maps tone → colour
and offsets by the note's position. That split is the entire reason this is
testable under plain `lua` with zero stubs.

---

## 1. The pixel grid, and why nothing is fractional

**`P` = the pixel unit, in points. `Palette.pixel = 4`.** Integer, always.

`hs.canvas` coordinates are points. A macOS backing store is 1× or 2× device
pixels per point — both integers. So:

> If the canvas frame origin is an integer point, and every rectangle's
> `x, y, w, h` is an integer, then every rectangle edge lands exactly on a
> device-pixel boundary and Core Graphics does no anti-aliasing. Break either
> half and every edge in the bubble goes soft.

Three concrete rules follow, and all three are currently violated:

1. **`action = "fill"`, never `"strokeAndFill"`.** A 1-point stroke straddles
   the path by 0.5 points on each side — a guaranteed half-pixel seam on every
   edge. This is the single biggest reason the current notes look mushy. No
   element in the new bubble has a stroke.
2. **`Panel:place` must return integer `x` and `y`.** Today it computes
   `fox.y + fox.h / 2 - height + Palette.foxWidth / 4`; `fox.h` is
   `math.floor(96 * ratio)` and can be odd, so `fox.h / 2` is routinely `x.5`,
   which puts the *entire panel* on a half-point origin. Fix:
   ```lua
   return { x = math.floor(x), y = math.floor(y), w = width, h = height }
   ```
3. **Every note's `plan.width`, `plan.height`, and its `top` offset must be
   multiples of `P`.** Guaranteed by `Bubble.size()` (§3) plus
   `Palette.leading = 12` (= 3P) and `top` starting at 0.

**No two rectangles of the same tone may overlap.** This is a hard invariant,
not a preference. Every tone is allowed to be translucent (`shade` is), and two
overlapping translucent rects composite twice, producing a visible darker patch
right down the middle of the bubble. The constructions in §2 are all built
overlap-free for exactly this reason. A unit test enforces it (§8, test 4).

*(Rejected alternative: the elegant "cross" construction — the whole chamfered
silhouette is the union of `{0, P, W, H-2P}` and `{P, 0, W-2P, H}`, just two
rects. It is beautiful and it is wrong here: those two rects overlap over ~95%
of the bubble, so it only works if every tone is fully opaque. That rules out a
translucent drop shadow and a translucent chip fill. Rejected.)*

Opacity requirements, stated once:

| tone | may be translucent? | why |
|---|---|---|
| `shade` | **yes** | shadow rects are pairwise disjoint by construction |
| `line` | yes | border rects are pairwise disjoint by construction |
| `paper` | **NO — must be alpha 1** | the tail mouth (§2.5) deliberately over-paints the bottom border to open the bubble into the tail. A translucent paper would let the rust show through the mouth. |

---

## 2. The exact rectangle list

All coordinates are **note-local**: origin at the bubble's top-left corner,
`(0, 0)`. `W` = note width, `H` = note height, both multiples of `P`.
Border thickness is `2P` throughout.

### 2.1 Shadow — tone `shade`, 3 rects

The classic pixel-art hard shadow is *"the silhouette translated (+P, +P), minus
the silhouette"*. Because the silhouette is a chamfered rectangle, that
difference has a closed form — three disjoint bars, no subtraction needed at
runtime:

| id | x | y | w | h |
|---|---|---|---|---|
| `S1` right bar | `W` | `2P` | `P` | `H - 3P` |
| `S2` corner step | `W - P` | `H - P` | `2P` | `P` |
| `S3` bottom bar | `2P` | `H` | `W - 2P` | `P` |

`S1` spans `y ∈ [2P, H-P)`, `S2` picks up `y ∈ [H-P, H)` two cells wide (the
step at the bottom-right chamfer), `S3` is `y ∈ [H, H+P)` starting at `2P` (the
bottom-left corner of the shadow is one cell short — that is correct, it is the
chamfer). Pairwise disjoint.

### 2.2 Border — tone `line`, 10 rects

Six bars forming a chamfered ring, plus four single cells that thicken the
*inner* corner (without them the four inner chamfer cells are transparent holes):

| id | x | y | w | h |
|---|---|---|---|---|
| `B1` top cap | `P` | `0` | `W - 2P` | `P` |
| `B2` top full | `0` | `P` | `W` | `P` |
| `B3` left | `0` | `2P` | `2P` | `H - 4P` |
| `B4` right | `W - 2P` | `2P` | `2P` | `H - 4P` |
| `B5` bottom full | `0` | `H - 2P` | `W` | `P` |
| `B6` bottom cap | `P` | `H - P` | `W - 2P` | `P` |
| `B7` inner ⌜ | `2P` | `2P` | `P` | `P` |
| `B8` inner ⌝ | `W - 3P` | `2P` | `P` | `P` |
| `B9` inner ⌞ | `2P` | `H - 3P` | `P` | `P` |
| `B10` inner ⌟ | `W - 3P` | `H - 3P` | `P` | `P` |

Pairwise disjoint (`B1`/`B6` are `y`-bands of their own; `B2`/`B5` likewise;
`B3`/`B4`/`B7`–`B10` occupy disjoint `x` ranges within `y ∈ [2P, H-2P)`).

### 2.3 Interior — tone `paper`, 3 rects

| id | x | y | w | h |
|---|---|---|---|---|
| `I1` top cap | `3P` | `2P` | `W - 6P` | `P` |
| `I2` body | `2P` | `3P` | `W - 4P` | `H - 6P` |
| `I3` bottom cap | `3P` | `H - 3P` | `W - 6P` | `P` |

Three disjoint `y`-bands. Together with `B7`–`B10` they tile
`y ∈ [2P, H-2P)` exactly, edge to edge, no gaps and no overlaps.

### 2.4 The tail — tone `line`, 6 rects

The tail is a **table**, not a formula, so it can be redrawn by editing six
numbers. Rows are in **pixel units**, one row per unit of depth below the
bubble's bottom edge. `dx` is the row's left edge relative to the tail root;
`w` is its width.

```lua
-- foxbot/bubble.lua
Bubble.ROOT = 5           -- tail root, in pixel units from the near edge

-- Left-pointing tail. Row k sits k units below the bubble's bottom edge.
-- The left edge marches one unit left per row, the right edge two, so it
-- narrows to a single-unit point.
Bubble.TAIL = {
  { dx =  0, w = 6 },
  { dx = -1, w = 5 },
  { dx = -2, w = 4 },
  { dx = -3, w = 3 },
  { dx = -4, w = 2 },
  { dx = -5, w = 1 },     -- the point
}
```

With `ROOT = 5`, the tail's absolute span is `x ∈ [0, 11P)` and
`y ∈ [H, H + 6P)`. The tip lands flush with the bubble's left edge (`x = 0`) —
deliberate, and worth keeping if the table is ever retuned. At `P = 4` that is
44 pt wide and 24 pt deep.

Rect for row `k` (left variant):
`{ x = (ROOT + TAIL[k].dx) * P, y = H + (k-1) * P, w = TAIL[k].w * P, h = P }`

### 2.5 The tail mouth — tone `paper`, 2 rects

The bubble must be *open* into the tail; otherwise a rust line runs across the
top of the tail's interior. `paper` is opaque, so the mouth simply over-paints
the bottom border:

```lua
Bubble.MOUTH = {
  { dx = 2, w = 2 },      -- row 0, but drawn tall enough to punch the border
  { dx = 1, w = 1 },      -- row 1
}
```

| id | x | y | w | h | note |
|---|---|---|---|---|---|
| `M1` | `(ROOT+2)P` = `7P` | `H - 2P` | `2P` | `3P` | cuts through `B5` and `B6`, continues into tail row 0 |
| `M2` | `(ROOT+1)P` = `6P` | `H + P` | `P` | `P` | tail row 1 |

Check: tail row 0 spans `[5P, 11P)`, mouth `[7P, 9P)` — two cells of rust each
side ✓. Tail row 1 spans `[4P, 9P)`, mouth `[6P, 7P)` — two cells each side ✓.
Rows 2–5 are solid rust and taper to the nib, which is exactly how a pixel-art
tail terminates.

### 2.6 Tail shadow — tone `shade`, 6 rects

Naïve translation, **no trimming**:
`{ x = row.x + P, y = row.y + P, w = row.w, h = P }` for each of the 6 tail rows.

This is safe and it is worth stating why, because the obvious worry is
double-composite:
- Each tail-shadow rect occupies a distinct one-unit `y` band, so no two of them
  can overlap.
- They start at `y = H + P`; the body shadow's lowest rect `S3` ends at `y = H + P`.
  Disjoint.
- `S1` (`x ∈ [W, W+P)`) never meets the tail in either variant.
- Where a shadow rect falls under the opaque tail itself, it is simply invisible —
  the tail is drawn later. Costs a few hidden pixels, saves a subtraction pass.

### 2.7 Draw order

`hs.canvas` paints in array order. Per note:

```
1. shade  : S1 S2 S3                       (3)
2. shade  : tail shadow rows 0..5          (6)
3. line   : B1..B10                        (10)
4. line   : tail rows 0..5                 (6)
5. paper  : I1 I2 I3                       (3)
6. paper  : M1 M2                          (2)
7. text/chips, unchanged apart from colours
```

**30 rects for the tailed note, 16 for every other.** The tail's top edge abuts
the bubble's bottom edge at exactly `y = H` — same tone, integer grid line, so
they fuse with no seam. That is the payoff for rule 1 in §1.

---

## 3. `hammerspoon/foxbot/bubble.lua` — the API

```lua
--- A speech bubble drawn the way a pixel artist would draw it: everything is
--- an axis-aligned rectangle on a whole-point grid, so every edge lands on a
--- device pixel instead of between two of them.
---
--- No rectangle here overlaps another of the same tone, which is what lets the
--- drop shadow be translucent. Colours are named rather than supplied, so this
--- module needs neither `hs` nor the palette and can be tested under plain lua.

local Bubble = {}

Bubble.MIN = { w = 14, h = 8 }   -- pixel units; below this the chamfers collide
Bubble.ROOT = 5
Bubble.TAIL = { ... }            -- §2.4
Bubble.MOUTH = { ... }           -- §2.5

--- Round `v` up onto the pixel grid.
--- @return integer
function Bubble.snap(v, pixel) end

--- Snap a measured note up onto the grid and past the minimum the chamfered
--- corners need. Panel calls this instead of rolling its own rounding, so the
--- precondition `Bubble.plan` relies on can never be violated.
--- @return w, h   (points, multiples of `pixel`, at least Bubble.MIN)
function Bubble.size(w, h, pixel) end

--- @param opts table
---   w, h    bubble size in points; must already have been through Bubble.size
---   pixel   the pixel unit, in points (integer ≥ 2)
---   fill    draw the interior (default true; chips pass false)
---   shadow  draw the drop shadow (default true; chips pass false)
---   tail    "left" | "right" | nil    which side the tail hangs from
--- @return list of { tone = "shade"|"line"|"paper", x = n, y = n, w = n, h = n }
---         in paint order (§2.7)
function Bubble.plan(opts) end

--- How far past the w × h box the drawing reaches, so the caller can size a
--- canvas. Without a tail: P, P. With one: P right, (#TAIL + 1) * P below.
--- @return right, bottom   (points)
function Bubble.reach(opts) end

--- The tail's bounding box in bubble coordinates, or nil. Panel uses it so a
--- click on the tail counts as a click on the note.
--- @return { x, y, w, h } | nil
function Bubble.tailBox(opts) end
```

### 3.1 Mirroring, and the order it must happen in

```lua
--- Reflect a run about the bubble's vertical centreline.
local function mirror(x, w, width) return width - x - w end
```

`tail = "right"` mirrors **the tail rows and the mouth rows only**, and it does
so **before** the shadow is derived from them.

The shadow is **never mirrored.** The light source is fixed at the top-left for
the whole UI — the body shadow is down-right regardless of which way the tail
points, so mirroring the tail's shadow would light one bubble from the other
side. The consequence is real and expected, not a bug: a right-pointing tail
leans *into* the shadow direction, so each row's shadow lands on the row below
and is hidden; only a thin sliver on the tail's left edge and the tip's shadow
remain visible. A left-pointing tail casts a full staircase. That asymmetry is
what a hard directional light actually does, and any artist would draw it the
same way.

Implementation order inside `plan`:
```lua
local rows = tailRows(opts)                 -- left variant, absolute points
if opts.tail == "right" then
  for _, r in ipairs(rows) do r.x = mirror(r.x, r.w, opts.w) end
end
local shadowRows = shift(rows, pixel)       -- always (+P, +P)
```

Sanity check of the mirror at `ROOT = 5`: left tip is `x = 0, w = P`; mirrored
it is `x = W - P, w = P` — flush with the right edge, symmetric. Left root row 0
is `[5P, 11P)`; mirrored `[W-11P, W-5P)`.

### 3.2 Which side

`Panel:place` already computes which side of the fox the panel landed on. Store
the *tail* side there, spelled out rather than folded into an `and/or` — a
`false` or `nil` in either branch of that idiom collapses, and this codebase has
been bitten three times:

```lua
local leftOfFox = (fox.x + fox.w / 2) > (screen.x + screen.w / 2)
-- leftOfFox means the panel sits to the LEFT of the fox, so the fox is to the
-- right of the panel and the tail must point that way.
if leftOfFox then
  self.tailSide = "right"
else
  self.tailSide = "left"
end
```

Only the **last** note in the column — the newest, the one nearest the fox —
gets a tail. Every other note gets `tail = nil`.

---

## 4. One corner at pixel resolution

Top-left corner, six by six cells, each cell `P × P`:

```
         c0    c1    c2    c3    c4    c5        x = 0, P, 2P, 3P, 4P, 5P
       ┌─────┬─────┬─────┬─────┬─────┬─────┐
  r0   │  ·  │  █  │  █  │  █  │  █  │  █  │   y = 0     · = clear
       ├─────┼─────┼─────┼─────┼─────┼─────┤             █ = line  (rust)
  r1   │  █  │  █  │  █  │  █  │  █  │  █  │   y = P     ░ = paper (cream)
       ├─────┼─────┼─────┼─────┼─────┼─────┤
  r2   │  █  │  █  │  █  │  ░  │  ░  │  ░  │   y = 2P
       ├─────┼─────┼─────┼─────┼─────┼─────┤
  r3   │  █  │  █  │  ░  │  ░  │  ░  │  ░  │   y = 3P
       ├─────┼─────┼─────┼─────┼─────┼─────┤
  r4   │  █  │  █  │  ░  │  ░  │  ░  │  ░  │
       ├─────┼─────┼─────┼─────┼─────┼─────┤
  r5   │  █  │  █  │  ░  │  ░  │  ░  │  ░  │
       └─────┴─────┴─────┴─────┴─────┴─────┘

  which rect paints each cell:
  r0:  ·    B1   B1   B1   B1   B1
  r1:  B2   B2   B2   B2   B2   B2
  r2:  B3   B3   B7   I1   I1   I1
  r3:  B3   B3   I2   I2   I2   I2
```

Read it as: the outer corner pixel `(c0, r0)` is missing — that is the chamfer.
Border thickness measured straight down column `c5` is two cells (`r0`, `r1`) ✓;
straight across row `r5` it is two cells (`c0`, `c1`) ✓. On the diagonal it runs
`(c1,r1) → (c2,r2)`, i.e. the border thickens slightly at the corner, which is
exactly how a hand-drawn pixel border behaves.

The tail, in the same notation, hanging off the bottom-left (`ROOT = 5`, so cell
column 5 is the root; `▓` is the paper mouth):

```
 ... │  █  │  █  │  █  │  █  │  █  │  █  │  █  │  █  │  █  │  █  │  █  │ ...   y = H-2P   B5
 ... │  █  │  █  │  █  │  █  │  █  │  █  │  █  │  ▓  │  ▓  │  █  │  █  │ ...   y = H-P    B6 + M1
     ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
     │  ·  │  ·  │  ·  │  ·  │  ·  │  █  │  █  │  ▓  │  ▓  │  █  │  █  │       y = H      row 0
     │  ·  │  ·  │  ·  │  ·  │  █  │  █  │  ▓  │  █  │  █  │  ·  │  ·  │       y = H+P    row 1
     │  ·  │  ·  │  ·  │  █  │  █  │  █  │  █  │  ·  │  ·  │  ·  │  ·  │       y = H+2P   row 2
     │  ·  │  ·  │  █  │  █  │  █  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │       y = H+3P   row 3
     │  ·  │  █  │  █  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │       y = H+4P   row 4
     │  █  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │  ·  │       y = H+5P   row 5 (the point)
     └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
      c0    c1    c2    c3    c4    c5    c6    c7    c8    c9    c10
```

---

## 5. Palette changes

### 5.1 New metrics

```lua
Palette.pixel     = 4      -- the pixel unit, in points. INTEGER. 3 and 5 also work.
Palette.pixelChip = 2      -- chips are drawn at half scale
Palette.pad       = 16     -- was 14. 4P: two clear cells inside the 2P border.
Palette.leading   = 12     -- was 8. 3P: clears the P-tall drop shadow.
```

`Palette.noteWidth = 340` and `noteWide = 440` stay — both are already multiples
of 4. `chipHeight = 26` and `chipGap = 6` stay — both multiples of 2.

### 5.2 New colour tokens (five per skin)

The bubble interior is cream, so the note's text can no longer use `ink` /
`faded`, which are picked for a dark panel. Five new tokens, added to each entry
in `skins`:

| token | role | rule |
|---|---|---|
| `paper` | bubble interior | **alpha must be 1** |
| `line` | bubble border and tail | rust / terracotta |
| `shade` | hard drop shadow | translucent is fine; hard-*edged* is what matters, not opaque |
| `mark` | primary text on paper | |
| `mute` | secondary text on paper | |

```lua
dusk = {
  ...
  paper = rgb(CREAM),                -- FBE3B8, alpha 1
  line  = rgb(EMBER),                -- C63F06 — reads better on cream than F2560A
  shade = rgb(PLUM, 0.50),
  mark  = rgb(PLUM),
  mute  = rgb("7A6A63"),
},
daylight = {
  ...
  paper = rgb("FDF8F1"),
  line  = rgb(EMBER),
  shade = rgb(PLUM, 0.30),
  mark  = rgb("21181F"),
  mute  = rgb("6B5F5A"),
},
burrow = {
  ...
  paper = rgb("E8E4E0"),
  line  = rgb("6E6560"),
  shade = rgb("000000", 0.25),
  mark  = rgb("21181F"),
  mute  = rgb("6B6560"),
},
```

`panel.lua` builds the tone map once per render:

```lua
local tones = { shade = colours.shade, line = colours.line, paper = colours.paper }
```

---

## 6. `panel.lua` — exactly what changes

### 6.1 `CROSS`

```lua
local CROSS = { pad = 16, box = 16, reach = 28, shift = 16 }   -- was 11/16/26/15
```
`pad = 11` would put the dismiss ✕ on top of the 8-point border. `4P` puts it in
the same gutter as the text; `reach = 7P` keeps the click target generous.

### 6.2 `measureNote`

Three edits:

```lua
-- (a) the narrow-note shrink, snapped and floored onto the grid
if not detailed then
  width = math.min(width, math.max(titleW + CROSS.shift, bodyW) + Palette.pad * 2)
end
-- (b) drop the trailing "- 4" fudge; the padding is real now
plan.width, plan.height =
  Bubble.size(width, y + Palette.pad, Palette.pixel)
plan.inner = plan.width - Palette.pad * 2
```

`plan.inner` must be recomputed *after* the snap, since `plan.width` can move up
by up to `P - 1` points. (The current code computes `inner` from the unsnapped
width at line 52 and never revisits it — carrying that bug forward would put the
text one to three points wider than its column.)

### 6.3 `render`

Sizing:
```lua
local width, height = 0, 0
for _, note in ipairs(self.notes) do
  width  = math.max(width, note.plan.width)
  height = height + note.plan.height + Palette.leading
end
height = height - Palette.leading

-- Room for the shadow, and for the tail on the last note.
local right, bottom = Bubble.reach({ pixel = Palette.pixel, tail = "left" })
local frame = self:place(width + right, height + bottom)
```

`Bubble.reach` with a tail returns `(P, 7P)` = `(4, 28)`. Feeding the *total*
drawing height into `place()` is what keeps the tail off the fox: `place` puts
the bottom of what it is given at roughly the fox's shoulder, so the tail tip
now lands where the bubble's bottom edge used to. No change to `place`'s
arithmetic beyond §1 rule 2.

Per-note body, replacing lines 131–136:
```lua
local shape = settings and settings.bubble or "pixel"    -- see §7
if shape == "soft" then
  add({ type = "rectangle", action = "strokeAndFill",
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
        fillColor = colours.panel, strokeColor = colours.edge, strokeWidth = 1,
        frame = { x = left, y = top, w = plan.width, h = plan.height } })
else
  local tail = nil
  if note == self.notes[#self.notes] then tail = self.tailSide end
  for _, part in ipairs(Bubble.plan({
        w = plan.width, h = plan.height, pixel = Palette.pixel, tail = tail })) do
    add({ type = "rectangle", action = "fill",
          fillColor = tones[part.tone],
          frame = { x = left + part.x, y = top + part.y, w = part.w, h = part.h } })
  end
end
```

`tail` is assigned with an `if`, not `note == last and self.tailSide or nil` —
`self.tailSide` is a string here so that idiom happens to survive, but the house
rule is to spell it out and this is precisely the shape that has bitten before.

Text colours inside the `pixel` branch:

| element | was | becomes |
|---|---|---|
| ✕ cross, hot | `colours.fur` | `colours.line` |
| ✕ cross, cold | `colours.faded` | `colours.mute` |
| title | `colours.fur` | `colours.line` |
| stamp | `colours.faded` | `colours.mute` |
| body | `colours.faded` | `colours.mute` |
| detail lines | `colours.ink` | `colours.mark` |
| chip label, hot / cold | `fur` / `faded` | `line` / `mute` |

### 6.4 Chips

Chips become small pixel bubbles at half scale. Replace the rounded chip rect
(lines 180–187) with:

```lua
local chipW = Bubble.snap(chip.w, Palette.pixelChip)
for _, part in ipairs(Bubble.plan({
      w = chipW, h = Palette.chipHeight, pixel = Palette.pixelChip,
      fill = lit, shadow = false, tail = nil })) do
  local tone = colours.hair
  if part.tone == "line" and lit then tone = colours.line end
  if part.tone == "paper" then tone = colours.glow end
  add({ type = "rectangle", action = "fill", fillColor = tone,
        frame = { x = left + chip.x, y = top + chip.y, ... } })
end
```

`chip.w` is snapped to `pixelChip` in `measureNote` too, so the layout and the
draw agree. `shadow = false` — chips sit on paper, not on the desktop, and a
shadow there is noise. `fill = false` when cold means the border rects are the
only output (10 rects), and the note's paper shows through, matching today's
transparent chip. `glow` is translucent, which is fine: the interior's three
rects are disjoint `y` bands.

Chip minimum: `Bubble.MIN` at `pixel = 2` is `28 × 16`; `chipHeight = 26` and
the narrowest label chip is ~40. Satisfied.

### 6.5 Hit testing

`spots` gains an optional tail box:

```lua
self.spots[#self.spots + 1] = {
  note = note, x = left, y = top, w = plan.width, h = plan.height,
  tail = tailBox,           -- nil for every note but the last
}
```
where `tailBox` is `Bubble.tailBox({...})` offset by `left, top` — or `nil`.
Again, spelled out:
```lua
local box = Bubble.tailBox({ w = plan.width, h = plan.height,
                             pixel = Palette.pixel, tail = tail })
local tailBox = nil
if box then
  tailBox = { x = left + box.x, y = top + box.y, w = box.w, h = box.h }
end
```

`Panel:at` gets one extra clause at the end of its loop, after the body test
fails, so clicking the tail dismisses the note like clicking its body:

```lua
if spot.tail
   and x >= spot.tail.x and x <= spot.tail.x + spot.tail.w
   and y >= spot.tail.y and y <= spot.tail.y + spot.tail.h then
  return { note = spot.note }
end
```

### 6.6 `Panel:say` — the screen-fit trim

The loop at lines 290–299 sums `plan.height + Palette.leading` against
`screen.h - 60`. It must now also account for the drawing that hangs below the
last bubble:

```lua
local _, bottom = Bubble.reach({ pixel = Palette.pixel, tail = "left" })
local limit = (self.screen and self.screen.h or 900) - 60 - bottom
```

---

## 7. Settings — exactly one new key

```lua
-- foxbot/settings.lua, inside SCHEMA
bubble = "pixel",          -- "pixel" | "soft" — note shape
```

That is the whole change. `KEYS` is derived from `SCHEMA`, so the save list
follows automatically; no second list is touched, per the module's own contract.

One menu row in `home()` under the `Appearance` label, immediately after
`Colours` (`init.lua:844`), cycling like `Colours` does:

```lua
{ kind = "row", title = "Note shape",
  value = shapeLabel(settings.bubble),
  act = function()
    Settings.cycle(settings, "bubble", { "pixel", "soft" })
    if panel then panel:render() end
  end },
```

with, near the other small helpers:

```lua
--- Spelled out rather than `cond and a or b`: cheap here, and the one-line
--- idiom is exactly the shape that has silently collapsed three times in this
--- codebase when a branch value turned out to be false or nil.
local function shapeLabel(name)
  if name == "soft" then return "rounded" end
  return "pixel"
end
```

`panel:render()` is a full rebuild by design, so flipping the setting redraws
whatever is on screen immediately.

Note `soft` mode must also keep today's *colours* — the tone swap in §6.3 lives
inside the `pixel` branch, so `soft` continues to use `panel` / `edge` / `ink` /
`faded` and looks byte-for-byte like the current build.

---

## 8. Tests

`bubble.lua` requires nothing, so `tests/run.lua` gets a new section with no new
stubs. Target: **+26 checks** (187 → 213).

Helpers to add at the top of the section:

```lua
--- Paint a plan onto a cell grid, one character per pixel unit, so a whole
--- bubble can be asserted against a picture instead of a pile of numbers.
local function raster(parts, w, h, pixel, bleedRight, bleedDown) ... end
--- true if two rects share any area.
local function hits(a, b) ... end
```

| # | check |
|---|---|
| 1 | `#Bubble.plan{w=200,h=100,pixel=4}` is 16 with no tail |
| 2 | `#Bubble.plan{...,tail="left"}` is 30 |
| 3 | every rect's `x, y, w, h` is an integer multiple of `pixel` |
| 4 | **no two rects of the same tone overlap** — O(n²) over each tone group, with and without a tail, both variants. The load-bearing invariant. |
| 5 | every rect has `w > 0` and `h > 0` (catches a negative `W - 6P` on a tiny bubble) |
| 6 | rasterise `w=8P, h=7P, pixel=P` and compare against a literal ASCII fixture in the test file — the killer test; catches every off-by-one in §2 at a glance |
| 7 | the `line` + `paper` silhouette of `tail="right"` is the exact horizontal mirror of `tail="left"` |
| 8 | the `shade` cells of `"right"` are **not** mirrored — the light stays top-left |
| 9 | the tail's last row is exactly one cell wide |
| 10 | left-variant tail tip starts at `x = 0`; right-variant tip ends at `x = W` |
| 11 | `Bubble.reach` returns `(P, P)` without a tail, `(P, 7P)` with |
| 12 | `Bubble.tailBox` contains every `line` rect whose `y >= h`; is `nil` without a tail |
| 13 | every `shade` rect satisfies `x >= P or y >= P` (shadow never leaks up-left of the body) |
| 14 | `fill = false` emits zero `paper` rects and the same 10 `line` rects |
| 15 | `shadow = false` emits zero `shade` rects |
| 16 | `Bubble.size(341, 63, 4)` → `344, 64`; `Bubble.size(10, 10, 4)` → `56, 32` (clamped to `MIN`) |
| 17 | `Bubble.snap(v, P)` is idempotent for any already-snapped `v` |
| 18 | mouth rects lie inside the tail's row-0 and row-1 spans with ≥ 2 cells of `line` on each side (asserted for both variants) |
| 19 | settings round-trip: `Settings.load()` after `Settings.save{bubble="soft"}` returns `"soft"`; a fresh load returns `"pixel"` |

Optionally (a ~15-line addition to `tests/support.lua`) stub
`hs.styledtext.new` as an identity table and `hs.drawing.getTextDrawingSize` as
`{ w = #text * 7, h = 16 * lines }`, which makes `measureNote` importable and
buys two more checks: *"a measured note's width and height are always multiples
of `Palette.pixel`"* and *"never below `Bubble.MIN`"*. Worth doing — those are
the two preconditions `Bubble.plan` trusts.

`tests/hook.sh` is untouched: no new events, no hook change.

---

## 9. Summary of the numbers

| quantity | value |
|---|---|
| pixel unit `P` | 4 pt (`Palette.pixel`) |
| chip pixel unit | 2 pt (`Palette.pixelChip`) |
| border thickness | `2P` = 8 pt |
| corner chamfer | 1 unit, outer and inner |
| shadow offset | `+P, +P` (down-right), bottom and right edges only |
| text inset | `Palette.pad` = 16 pt (`4P`) |
| note-to-note gap | `Palette.leading` = 12 pt (`3P`) |
| tail root | 5 units = 20 pt from the near edge |
| tail | 6 rows, 11 units wide (44 pt) × 6 deep (24 pt) |
| tail mouth | 2 units (8 pt) |
| reach past the bubble box | 4 pt right; 4 pt down, or 28 pt with a tail |
| minimum bubble | 14 × 8 units = 56 × 32 pt |
| rects per note | 16, or 30 for the tailed one |
| rects per chip | 10 cold, 13 hot |


## Settings

- bubble = "pixel"  (values: "pixel" | "soft"; one entry in settings.lua SCHEMA, save list stays derived)

## Risks

- Translucent-tone double-composite: if anyone later replaces the 10-rect border ring or the 3-rect interior with the tempting 2-rect 'cross' union, overlapping rects will composite twice and paint a visible darker patch through the middle of every bubble. Test 4 (no two rects of the same tone overlap) is the guard and must not be deleted.
- paper alpha: the tail mouth over-paints the bottom border to open the bubble into the tail. If a skin ships `paper` at alpha < 1, the rust border shows through the mouth as a bar across the tail. Needs an assertion or a comment at the skins table; nothing in the type system enforces it.
- Half-point origins: Panel:place currently returns fractional y whenever fox.h is odd (fox.h/2). Forgetting the math.floor makes every edge in every bubble anti-aliased, and it will look like the geometry is wrong rather than the placement.
- Visual shock: dusk goes from a dark plum panel to a cream bubble with rust border. It is what the reference asks for, but it is a large change for existing users. `bubble = "soft"` is the escape hatch, and the tone swap must stay inside the `pixel` branch so `soft` is byte-identical to today.
- measureNote's plan.inner is currently derived from the unsnapped width at line 52 and never recomputed. If it is not moved after Bubble.size(), text columns run 1-3 pt wider than the box they sit in and wrap one word early or late.
- Element count roughly 2.5x: ~16 rects per note (30 for the tailed one) plus 10-13 per chip, so a full six-note column goes from ~50 elements to ~130. hs.canvas replaceElements is one call and the menu already emits ~60, so this should be fine, but a very long detail-line note with several chips is the case to eyeball.
- Right-facing tail casts almost no visible shadow (its rows lean into the light direction, so each row's shadow lands on the row below). This is geometrically correct for a fixed top-left light and must not be 'fixed' by mirroring the shadow offset, which would light one bubble from the wrong side.
- Screen-edge clamping in Panel:place can push the panel away from the fox; the tail then points at nothing in particular. Cosmetic only, and only in the corner cases where the panel was already being clamped.
- Non-integer display scaling ('More Space' modes): the canvas backing store is still an integer scale and the whole framebuffer is downsampled afterwards, so the bubble degrades exactly like every other UI element. Not fixable from here; worth a line in the module comment so nobody hunts it.
- Palette.leading 8 -> 12 makes a stacked column taller, so the oldest-note-drops-first loop in Panel:say trims one note sooner on short screens. Accounted for by also subtracting Bubble.reach's bottom from `limit`.