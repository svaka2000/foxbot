# Donuts

A currency the fox earns while you work, spent on things that change how he
looks and nothing else.

**Built.** `wallet.lua` earns and holds, `shop.lua` is the shelf, and the shop
lives behind *the stats strip → Shop*. This document is the design it was built
from; where the two could drift, `tests/wallet.lua` is the arbiter.

---

## The problem with the obvious version

"More tokens, more donuts" is the obvious rule and it is the wrong one. It pays
you to burn tokens, and burning tokens is the one behaviour a tool like this
should never encourage. Left alone it would reward padding prompts, re-running
work, and leaving sessions churning — the exact opposite of what the rest of
Foxbot is for.

So the earning rule has three parts, and only one of them is tokens.

### 1. Turns, not tokens — with tokens as a small multiplier

```
donuts for a turn = 1 + floor(min(output_tokens, 40_000) / 8_000)
```

| a turn that produced | donuts |
|---|---|
| 2k tokens | 1 |
| 8k | 2 |
| 24k | 4 |
| 40k | 6 |
| 200k | 6 — capped |

A turn is worth at least one donut regardless of size, and the token bonus is
**capped at 40k**. Past that point a bigger turn earns nothing extra, so there
is no reason to inflate one. Small, tight turns earn more per token than one
enormous one, which is the incentive you actually want.

### 2. A daily ceiling

**60 donuts a day.** A heavy day of real work reaches roughly 35–45. The
ceiling exists so that leaving something running overnight is worth nothing,
and so the shop can be priced against a knowable maximum.

### 3. Bonuses for the things worth encouraging

| | donuts | why |
|---|---|---|
| First turn of the day | +3 | showing up |
| Finishing a focus block | +5 | the one behaviour worth paying for |
| Answering a blocked question within 2 min | +2 | unblocking yourself quickly |
| Each day of an unbroken streak, capped at 7 | +1 each | coming back |

Note what is **not** rewarded: session count (trivially farmable — open ten
terminals), wall-clock time (rewards leaving it idle), or context size
(rewards stuffing the window).

### The honest limitation

Any of this can be gamed by someone who wants to. The point is that the
*default* incentives point the right way — you cannot accidentally end up
wasting tokens because the fox nudged you into it, and the fastest way to a
new sprite is to do a normal day's work and take your breaks.

---

## The rule about what donuts buy

**Cosmetics only. Never behaviour.**

Nothing in the shop may change what Foxbot *does* — not a sound that tells you
something new, not a stat you can't otherwise see, not a shorter cooldown.
Putting function behind a grind turns a tool into a game that occasionally
helps you work, and makes every future feature a pricing question.

Sound *packs* are the edge case and they stay in: swapping which noise plays is
decoration. Adding a noise for an event that had none would not be.

---

## The shop

Prices assume ~40 donuts on a good day, so a first sprite lands in 3–4 days and
the whole shop is several months of use.

### Sprites — a different animal entirely

Each needs a full ten-mood set, so these are the expensive tier — and each is
**only on the shelf once its drawing exists**. A shop listing something it
cannot hand over is worse than a shop with four things in it, so the aisle
reads whatever is in `assets/` and stocks itself. Import a sheet with
`tools/slice_sheet.py` (prompts in [SHOP-SPRITES.md](SHOP-SPRITES.md)) and the
animal appears by itself, at the price below.

| item | price | what it is |
|---|---|---|
| **Tabby** | 400 | a small grey cat, unimpressed by everything |
| **Corgi** | 400 | absurdly pleased to be here |
| **Raccoon** | 550 | nocturnal, suspicious, keeps finding things |
| **Axolotl** | 550 | pink, permanently smiling, slightly damp |
| **Crow** | 700 | far too clever, collects shiny things |
| **Ghost fox** | 900 | the same fox, translucent and blue |

### Coats — the same fox, different colouring

Cheap because they re-tint an existing sprite set rather than needing new art.

| item | price | what it is |
|---|---|---|
| **Arctic** | 150 | white and pale blue |
| **Melanistic** | 150 | near-black with amber eyes |
| **Fennec** | 200 | sand-coloured, enormous ears |
| **Nine-tails** | 350 | more tails than strictly necessary |

### Hats — drawn over any sprite

A separate small image anchored to the head, so one hat works on every animal.

| item | price | what it is |
|---|---|---|
| **Tiny beanie** | 80 | |
| **Party hat** | 80 | |
| **Headphones** | 120 | worn during focus blocks |
| **Reading glasses** | 120 | appear when he's concentrating |
| **Crown** | 250 | for a 30-day streak, but buyable |
| **Tiny hard hat** | 150 | worn when something breaks |

### Palettes — for the panel and the notes

| item | price | what it is |
|---|---|---|
| **Terminal** | 120 | black and phosphor |
| **Blueprint** | 120 | white on drafting blue |
| **Sakura** | 150 | pale pink paper |
| **Midnight** | 150 | deep blue, low contrast |

### Sound packs

| item | price | what it is |
|---|---|---|
| **Woodland** | 100 | birds, twigs, soft |
| **Arcade** | 100 | 8-bit blips |
| **Library** | 100 | paper, pencil, a distant clock |

### Toys and nonsense — the fun tier

Things that do nothing except exist.

| item | price | what it is |
|---|---|---|
| **A ball** | 60 | he bats it about while idle |
| **A donut** | 60 | he eats it once a day. It's yours. You bought it. |
| **A tiny laptop** | 200 | he types on it while a session runs |
| **A nameplate** | 100 | call him something other than Foxbot |
| **A cardboard box** | 180 | he sits in it. Sometimes he doesn't come out. |
| **Seasonal set** | 300 | a wreath in December, a pumpkin in October |

---

## Where it lives

`~/.claude/foxbot/wallet.json`:

```json
{
  "balance": 1240,
  "earnedTotal": 3180,
  "owned": { "coat.arctic": true, "hat.beanie": true },
  "day": { "on": 1785964800, "earned": 38 },
  "lastTurn": 1785999999
}
```

**The balance is stored, never derived.** The ledger keeps 30 days; a balance
recomputed from it would silently delete everything you'd earned the moment a
turn aged out. The wallet is its own file with its own lifetime, and
`uninstall.sh` leaves it alone unless you pass `--all`.

`day.on` is the start-of-day the accumulator belongs to, so the daily ceiling
resets lazily the same way the focus-block count does — correct across a
machine that was asleep at midnight.

## Where it shows

- The stats strip gains a fourth figure, the balance — but only once you have
  earned something. A "donuts: 0" on a fresh install is an advertisement for a
  feature, not a statistic.
- **The den** gains a `Shop` row, showing the balance as its value.
- The shop is one page per aisle, each row an item with its price, greyed when
  it can't be afforded and marked `owned` when it is. Prices show on everything,
  including what you can't afford yet: a shop that hides the price until you can
  pay it has something to hide.
- Buying equips immediately rather than filling an inventory. What you spent
  three days earning should be visible the instant you pay for it.
- Earning is silent. A note saying "you got 4 donuts" after every turn is
  precisely the sort of thing this project spent a week removing.

## What is actually on the shelf today

Everything that needs no drawing: four palettes, three sound packs, and a
nameplate. That is deliberate, not a shortfall — see the sprites note above.

| aisle | in stock now |
|---|---|
| Palettes | Terminal, Blueprint, Sakura, Midnight |
| Sound packs | Woodland, Arcade, Library |
| Animals | whatever is in `assets/` |
| Odds and ends | a nameplate |

## What needs drawing

Every sprite needs ten moods, which is one 3×3 sheet plus the base — the same
pipeline as [SHEET-PROMPT.md](SHEET-PROMPT.md), swapping the animal.

Hats are simpler: one small image each, transparent, anchored to a head box
defined per sprite.

Prompts for both are in [SHOP-SPRITES.md](SHOP-SPRITES.md).
