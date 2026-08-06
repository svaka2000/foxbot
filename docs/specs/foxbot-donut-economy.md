# Foxbot Donut Economy

# The Donut Economy

## 0. Position — what donuts are, and what they must never become

Donuts are **a slow trophy for showing up**, denominated in a unit the fox can already see. Tokens are the *measuring stick*, not the *thing being rewarded*. Three rules follow, and every number below exists to serve them:

1. **Burning tokens must be a bad way to earn.** The curve is concave and hard-capped, so the marginal donut from extra tokens falls to zero long before a heavy day ends. On a realistic normal day, **more than half the income comes from bonuses that have nothing to do with volume.**
2. **Nothing that Foxbot already does for free may go behind donuts.** No anti-annoyance control, no stat, no mute, no existing coat or palette. Ever.
3. **The economy must be ignorable.** It ships on, but silent: a row in the menu and nothing else. It never touches the menu bar, never chimes, and produces at most **one note per day**, opt-in, default off.

---

## 1. Modules and files

| File | Role |
|---|---|
| `hammerspoon/foxbot/donuts.lua` | **NEW.** The wallet: load/save, the earning arithmetic, spending. No canvas, no timers. Pure enough to unit-test end to end under the `hs` stub. |
| `hammerspoon/foxbot/shop.lua` | **NEW.** The item table (data) plus affordability / season / slot logic (pure functions). Split from `donuts.lua` because the item list will churn and the arithmetic must not. |
| `hammerspoon/foxbot/settings.lua` | 7 new SCHEMA entries. Nothing else. |
| `hammerspoon/foxbot/init.lua` | `purse` global, credit call in `handle()`, `settle` in the pulse, `purseRow()`, `shopPage()`, `shelfPage()`, `earningPage()`, one home() row. |
| `hammerspoon/foxbot/menu.lua` | One new row kind: `purse`. |
| `hammerspoon/foxbot/palette.lua` | `Palette.unlock(ids)`, two metrics tokens, 5 new skins. |
| `hammerspoon/foxbot/coats.lua` | `Coats.all(moods, allowed)` — optional 2nd arg, permissive when nil (keeps existing tests green). `Coats.fit` hat-box table. |
| `hammerspoon/foxbot/sprite.lua` | Two appended canvas elements (hat at [3], toy at [4]). Badge stays at [2]. |
| `hammerspoon/foxbot/sessions.lua` | `Sessions:answered` gains a second return value (`had, since`). |
| `bin/foxbot` | `foxbot donuts` — read-only. |
| `tests/run.lua` | ~45 new assertions. |
| `~/.claude/foxbot/wallet.json` | **NEW runtime file.** The balance and inventory. |

---

## 2. The earning curve

### 2.1 The shape of the calculation

Do **not** award per turn from a rate. Award the **difference between what the day is now worth and what has already been paid**:

```
earnedToday = math.floor( math.min( dayValue(day), DAY_CAP ) )
award       = earnedToday - day.paid
day.paid    = earnedToday
```

This single decision buys four things at once:

* **The wallet only ever stores integers.** The fractional part lives implicitly in `day.tokens` / `day.seconds` / `day.turns`, which are exact integers. No float drift, ever.
* **Idempotence.** Counting a row twice would have to double the day totals, which the dedupe map prevents; and out-of-order arrival cannot double-pay.
* **The cap is one `math.min`.**
* **`dayValue` is a pure function of one table** — the entire economy is testable without touching disk.

### 2.2 The three work streams

Each is a **cumulative tiered function of the day's total**, evaluated by one shared helper:

```lua
function Donuts.tier(total, tiers)
  local out, floorAt = 0, 0
  for _, tier in ipairs(tiers) do
    local ceiling, rate = tier[1], tier[2]
    if total <= floorAt then break end
    out = out + (math.min(total, ceiling) - floorAt) * rate
    floorAt = ceiling
  end
  return out
end
```

**Tokens** — on `tokens + subTokens`, summed for the day:

| Band | Rate | Band pays |
|---|---|---|
| 0 – 100k | 0.05 / 1k | 5.0 |
| 100k – 300k | 0.025 / 1k | 5.0 |
| 300k – 600k | 0.010 / 1k | 3.0 |
| 600k+ | 0 | 0 |

**Ceiling: 13 donuts/day.** The first 100k tokens pay **five times** what the last 300k pay.

```lua
Donuts.TOKEN_TIERS = { {100000, 0.05/1000}, {300000, 0.025/1000}, {600000, 0.010/1000} }
```

**Time** — on `elapsed`, each turn clamped to `ELAPSED_CAP = 900`s first:

| Band | Rate | Band pays |
|---|---|---|
| 0 – 60 min | 0.10 / min | 6.0 |
| 60 – 180 min | 0.05 / min | 6.0 |
| 180 – 360 min | 0.02 / min | 3.6 |
| 360 min+ | 0 | 0 |

**Ceiling: 15.6 donuts/day.**

```lua
Donuts.TIME_TIERS = { {3600, 0.10/60}, {10800, 0.05/60}, {21600, 0.02/60} }
```

**Turns** — only *qualifying* turns (§3):

| Band | Rate | Band pays |
|---|---|---|
| turns 1 – 20 | 0.25 each | 5.0 |
| turns 21 – 60 | 0.10 each | 4.0 |
| turn 61+ | 0 | 0 |

**Ceiling: 9 donuts/day.**

```lua
Donuts.TURN_TIERS = { {20, 0.25}, {60, 0.10} }
```

### 2.3 Bonuses — the majority of the income

| Bonus | Amount | Cap/day | When |
|---|---|---|---|
| **Morning** | 4 | once | The first qualifying turn of a new calendar day. |
| **Streak** | 1 × `min(streak, 10)` | 10 | Same moment as Morning. Streak is stored **in the wallet**, never recomputed from the ledger. |
| **Focus stretch** | 4 | 3 (12) | A closed stretch: ≥3 turns in one folder, ≥25 min wall clock, no gap >20 min. |
| **Quick answer** | 1 | 4 | A blocked session answered within 60 s of first blocking. |

**Bonus ceiling: 30 donuts/day.**

The stretch bonus is the load-bearing one: it pays for *sustained attention on one project*, which no amount of token-burning can fake and which is the opposite of thrash.

### 2.4 The cap and the worked examples

```lua
Donuts.DAY_CAP = 50     -- theoretical max of the streams is 67.6; the cap bites
Donuts.WELCOME = 20     -- granted once, on first wallet creation
```

| Day | Turns | Tokens | Claude worked | Streak | Stretches | Tokens | Time | Turns | Bonus | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|
| Light | 10 | 80k | 40 min | 2 | 1 | 4.0 | 4.0 | 2.5 | 10 | **20** |
| Normal | 35 | 250k | 2h 30m | 5 | 2 | 8.75 | 10.5 | 6.5 | 19 | **44** |
| Heavy | 80 | 600k | 5h | 10 | 3 | 13.0 | 14.4 | 9.0 | 30 | **50** (capped from 66) |

**Read the last two rows.** Tripling token spend and doubling turn count over a normal day buys **14% more donuts**. That is the perverse incentive killed on purpose, and it is visible to the user on the *How donuts work* page.

On the normal day, **43% of income is bonuses** — money for showing up, keeping a streak, and staying on one thing.

### 2.5 Sizing check

~250 donuts/week, ~1,000/month. Cheapest sprite is 120 → **reachable on day 3–4**. Cheapest item overall is the 30-donut snack → **buyable on day one** (with the 20-donut welcome grant, immediately). Full shop is 4,560 donuts → **~18 weeks** to own everything, with a permanent 30-donut repeatable sink so the counter never becomes meaningless.

---

## 3. Anti-abuse

Take this seriously, but be honest about the threat model: this is a solitaire economy on your own machine. **The wallet file is plain JSON and is not defended against being edited — a checksum would be theatre and should not be written.** What *is* defended is everything that could happen by accident, by a loop, or by a mildly perverse incentive.

| Attack | Defence | Constant |
|---|---|---|
| **Burn tokens to win** | Concave tiers, zero marginal rate past 600k, DAY_CAP. Past 300k you burn ~100k tokens — real money — for one donut. The fox pays less per token than the token costs, by orders of magnitude, always. | `TOKEN_TIERS`, `DAY_CAP` |
| **Spam trivial turns** | A turn only counts toward the *turn stream* if `tokens + subTokens >= 250` **and** `elapsed >= 2` **and** ≥10 s since the last counted turn *in that session*. Tokens/time still accrue (they're already tiny); only the flat per-turn money is gated. | `MIN_TURN_TOKENS = 250`, `MIN_TURN_SECONDS = 2`, `TURN_GAP = 10` |
| **Double-credit from a replayed/coalesced event** | `day.seen["<session_id>@<ts>"] = true`. A row already seen credits **nothing at all**. Cleared on day roll; wholesale-cleared if it exceeds 500 keys. | — |
| **Forged inbox lines** | Credit is taken only from rows that reached `ledger:append` — i.e. after `REPEAT_GUARD` and the kind filter. Plus: reject any row whose `ts` is >300 s in the future or >86400 s in the past. | `FUTURE_SLACK`, `PAST_SLACK` |
| **Clock rollback to re-farm Morning/Streak** | A new day is recognised **only when the date string is strictly greater** than `day.date` (lexicographic on `%Y-%m-%d`). Going backwards does nothing — no reset, no re-award. Also refuse to credit rows older than `wallet.lastTs - 3600`. | `Donuts.newer(a, b)` |
| **Fake long-running session for the time stream** | `elapsed` comes from real `busy`→`done` pairing; `Sessions:sweep` retires anything past 30 min anyway; and each turn contributes at most 900 s. | `ELAPSED_CAP = 900` |
| **Hand-edited / corrupt wallet crashing the fox** | Loader validates shape: coerce types, clamp `balance` to `[0, 1e9]`, drop inventory ids not in `Shop.by`, drop `day` entirely if `date` isn't a plausible string. Never throws. | — |
| **Wallet from a newer version** | If `v > Donuts.VERSION`, load read-only (`self.readOnly = true`, `save()` is a no-op) so a downgrade cannot destroy a newer wallet. | `Donuts.VERSION = 1` |
| **Selling / refunding** | There isn't any. Owned is a set; buying something owned is a no-op. No sinks to game. | — |

**The framing is also a defence.** The fox never says "3 donuts for 60k tokens." It says "day 5 · 44 donuts." The only place tokens are connected to donuts is the *How donuts work* page, which explicitly tells you that burning tokens is a bad way to earn.

---

## 4. Persistence

### 4.1 The invariant that matters most

> **The balance is never derived from the ledger.**

`ledger.jsonl` prunes at `keepDays = 30` and rewrites itself on load. If the balance were `sum(ledger) × rate − spent`, then on day 31 the prune would silently delete a day of earnings and the user would go backwards — or negative, with purchases implicitly revoked. `History` must never be imported by `donuts.lua`, and `donuts.lua` must never read `ledger.rows`. The wallet is a **running total that only moves forward on credit and backward on purchase**. The streak and the stretch detector both live in the wallet for exactly this reason.

There is one test whose entire job is to assert this: prune the ledger to zero rows, reload, balance unchanged.

### 4.2 File

`~/.claude/foxbot/wallet.json` — a single JSON **object** (not jsonl; this is state, not a log), mode `0600`.

**Write protocol:**
1. If the existing file parses, copy it to `wallet.bak.json`. (This file can represent four months of use; one cheap backup is warranted.)
2. Write to `wallet.tmp.json`.
3. `os.rename` over `wallet.json` — atomic on the same filesystem, so a crash mid-write cannot leave you broke.

### 4.3 Schema (v1)

```jsonc
{
  "v": 1,
  "balance": 137,                    // integer, always
  "earned": 402,                     // lifetime, for the plant and the flex
  "spent": 265,
  "since": 1754438400,               // first ever credit — also the "birthday" for season.party
  "lastTs": 1754612345,              // newest row ts credited; backstop against backfill

  "streak": { "days": 5, "last": "2026-08-06" },

  "day": {
    "date": "2026-08-06",
    "tokens": 251203,                // tokens + subTokens
    "seconds": 9042,                 // sum of per-turn min(elapsed, 900)
    "turns": 35,                     // qualifying turns only
    "paid": 44,                      // integer donuts already handed over today
    "bonus": 19,                     // bonus donuts included in dayValue
    "stretches": 2, "answers": 4,
    "morning": false,                // NOTE: a false-defaulting boolean. See §11.
    "told": false,                   // the once-a-day milestone note has fired
    "seen": { "abc-123@1754612300": true },
    "beat": { "abc-123": 1754612300 }
  },

  "stretch": { "folder": "foxbot", "from": 1754610000, "turns": 4, "last": 1754612345 },

  "own":  { "coat.vixen": 1754500000, "toy.ball": 1754400000 },
  "treats": 3                        // lifetime donuts fed to him; pure flavour
}
```

### 4.4 Two stores, one home each

* **Ownership lives in the wallet** (`own`).
* **Equipment lives in Settings** (`coat`, `skin`, `hat`, `toy`, `soundPack`, `nameplate`, `flair`), because Settings is already the schema-driven home for "what does he look like", `sprite.lua` already reads `settings.coat`, and equipment should survive the wallet being deleted.

The seam is reconciled once at start:

```lua
Shop.reconcile(wallet, settings)   -- clears any equipped id you don't own, back to defaults
```

This does **not** violate the "never two lists" rule — that rule is about the settings schema and its derived save list, which stays intact. It's one home per concern.

### 4.5 Uninstall

`uninstall.sh` must **not** silently delete `wallet.json`. Print the path, say what it holds, and require `--purge` to remove it.

---

## 5. The shop

31 items. Every price is a multiple of 10 and sits on the ladder **30 / 60 / 90 / 120 / 160 / 180 / 200 / 220 / 260 / 420 / 800**.

### Sprites — `kind = "coat"`, slot `coat`, one worn

| id | Label | Price | Note | Type |
|---|---|---|---|---|
| `coat.vixen` | Vixen | **120** | silver arctic fox | cosmetic |
| `coat.tanuki` | Tanuki | **180** | round, dark mask | cosmetic |
| `coat.corgi` | Corgi | **180** | short legs, big grin | cosmetic |
| `coat.midnight` | Midnight | **220** | black cat, gold eyes | cosmetic |
| `coat.axolotl` | Axolotl | **260** | pink, frilled | cosmetic |
| `coat.mecha` | Mecha-fox | **420** | chrome plating, LED eye | cosmetic |

`foxbot` stays free and first in the list, always. Subtotal **1,380**.

### Colours — `kind = "skin"`, slot `skin`, one worn

| id | Label | Price | Note | Type |
|---|---|---|---|---|
| `skin.ember` | Ember | **60** | hot orange on near-black | cosmetic |
| `skin.moss` | Moss | **60** | green on parchment | cosmetic |
| `skin.frost` | Frost | **90** | pale blue, high contrast | cosmetic |
| `skin.paper` | Paper | **90** | warm cream, ink black, editorial | cosmetic |
| `skin.terminal` | Terminal | **120** | phosphor green; panel font goes to Menlo-Bold | cosmetic |

`dusk`, `daylight`, `burrow` stay free. Subtotal **420**. **Zero art required** — these are entries in `skins` plus `Palette.unlock`.

### Hats — `kind = "hat"`, slot `hat`, one worn

| id | Label | Price | Type |
|---|---|---|---|
| `hat.beanie` | Beanie | **60** | cosmetic |
| `hat.crown` | Paper crown | **90** | cosmetic |
| `hat.scarf` | Scarf | **90** | cosmetic |
| `hat.glasses` | Tiny spectacles | **120** | cosmetic |
| `hat.headphones` | Headphones | **120** | cosmetic |
| `hat.hardhat` | Hard hat | **160** | cosmetic |

Subtotal **640**. A "Bare-headed" `choice` row sits at the top of the shelf to unequip.

### Sounds — `kind = "sound"`, slot `sound`, one worn

A pack is a **table remapping `DEFAULT_CHIMES`**, not a bundle of audio — three of the four ship as zero bytes.

| id | Label | Price | Mapping | Type |
|---|---|---|---|---|
| `sound.hush` | Whisper | **90** | Tink / Pop / Purr — the quietest stock sounds | cosmetic |
| `sound.arcade` | Arcade | **120** | Funk / Blow / Frog / Morse | cosmetic |
| `sound.glass` | Concierge | **120** | Glass / Bottle / Sosumi | cosmetic |
| `sound.fox` | Fox | **200** | six real vocalisations — the only pack needing audio (6 × ~30 KB `.caf`) | cosmetic |

Subtotal **530**. A pack **only supplies defaults**; any per-event sound you set by hand in **Sounds** still wins. Selecting a pack never overwrites a choice you made.

### Toys and treats — `kind = "toy" | "treat" | "name" | "flair"`

| id | Label | Price | Behaviour | Type |
|---|---|---|---|---|
| `snack.donut` | A donut for him | **30** | **Repeatable.** He eats it: `cheering` for 20 s, `wallet.treats + 1`. Once per day (`settings.treatAt`). The permanent sink. | idle flavour |
| `toy.ball` | Yarn ball | **90** | After 5 min `resting` with nothing running, he bats it. | idle flavour |
| `toy.moth` | A moth | **120** | Occasionally flutters past; his badge tracks it. | idle flavour |
| `toy.plant` | A little plant | **160** | Sits beside him. Grows one leaf per 100 lifetime `earned`, capped at 8. A trophy that isn't a number. | idle flavour |
| `name.plate` | Nameplate | **60** | Sets `settings.nameplate`; shown under him and as the menu header subtitle. | cosmetic |
| `fx.sparkles` | Sparkles | **90** | Three pixels twinkle for 3 s when a turn lands. **Never during quiet hours, never while presenting, never when hidden, never when something is blocked on you.** | idle flavour |

Subtotal **520** (excluding the repeatable).

### Seasonal — `kind = "season"`, slot `hat`

Purchasable only inside a window; **once owned, kept and wearable forever**.

| id | Label | Price | Window |
|---|---|---|---|
| `season.pumpkin` | Pumpkin hat | **90** | October |
| `season.santa` | Santa hat | **90** | December |
| `season.party` | Party hat | **90** | ±3 days around `wallet.since` — your Foxbot birthday |

Subtotal **270**. The shop states the window plainly (`"October only"`) and **never counts down and never sends a note about it.** No manufactured urgency.

### End game

| id | Label | Price | Type |
|---|---|---|---|
| `flair.plaque` | Gold plaque | **800** | A thin gold rule across the top of the panel and his nameplate engraved. | cosmetic |

**Grand total: 4,560 donuts.**

---

## 6. Cosmetic vs behaviour — the opinion

**Hard rule: donuts buy appearance and delight. They never buy behaviour.**

Concretely, none of these may ever be an item, at any price: mute, quiet hours, per-project mute, away handling, live progress notes, chase-unanswered, detail level, voice, stats, the ledger, the CLI, extra moods, faster or richer notes.

Three reasons, in order of weight:

1. **A pet that withholds the mute button until you burn tokens is malware.** Anti-annoyance is the product. Charging for it inverts the product.
2. **A paywalled behaviour re-opens the perverse incentive through the back door.** The moment a *useful* thing costs donuts, the concave curve stops being a fair-play mechanism and becomes a friction the user is motivated to overcome — by spending tokens. Everything in §2 is wasted.
3. **It keeps the feature safely optional.** With cosmetics only, `donuts = false` costs you nothing but sparkle. That's what makes it honest to ship on by default.

**The one grey area, and where the line goes.** Toys and the snack change what he *does* — he bats a ball, he eats. That is idle flavour, and the line is:

> Flavour may change what he does when **nothing is happening**. It may never change what he says when **something is**.

So the ball is fine (it only appears after 5 minutes of `resting`), and sparkles are fine *only because* they're suppressed whenever a note would have been suppressed. If a toy ever wanted to fire during a turn, it would be a behaviour change and would be rejected.

**Corollary: never take away something that is free today.** `foxbot` coat and all three existing palettes remain free and unlocked forever. The shop only ever *adds*.

---

## 7. UI

### 7.1 One new row kind: `purse`

Justified on the same grounds as the existing `status` and `stats` rows — a system menu cannot draw a currency. Everything else reuses `into` / `choice` / `row`.

In `menu.lua`:

```lua
H.purse = 40
```

Paint (all coordinates match the existing conventions: `INSET = 10`, `W = 302`):

| Element | Geometry |
|---|---|
| donut body | `circle`, `strokeAndFill`, `fillColor = c.fur`, `strokeColor = c.edge`, `strokeWidth = 1`, `center = { x = INSET + 16, y = y + 20 }`, `radius = 9` |
| donut hole | `circle`, `fill`, `fillColor = c.panel`, same centre, `radius = 3.5` |
| sprinkles ×3 | `rectangle`, `fill`, `fillColor = c.ink`, `w = 2, h = 2` at `(INSET+12, y+15)`, `(INSET+19, y+17)`, `(INSET+14, y+24)` |
| balance | `text(n .. (n == 1 and " donut" or " donuts"), Palette.head + 1, c.ink, nil, "bold")`, frame `{ x = INSET + 34, y = y + 4, w = 170, h = 20 }` |
| today | `text("+" .. today .. " today", Palette.small, c.faded)`, frame `{ x = INSET + 34, y = y + 22, w = 170, h = 14 }` |
| chevron | only when `row.page` — `text("›", Palette.head + 3, hot and c.fur or c.faded, "right")` at `{ x = W - INSET - 20, y = y + 8, w = 12, h = 22 }` |
| hover | reuse the standard `c.glow` rounded rect, `frame = { x = INSET - 4, y = y, w = W - (INSET-4)*2, h = H.purse - 2 }` |

Hit-registered exactly like the other kinds: push `{ index, y, h = h - 2, row }` when `row.page` is set.

### 7.2 `home()` — the exact change

Insert **one row** after `statsRow()`, before the `sep`, and only when the economy is on:

```lua
statusRow(),
{ kind = "sep" },
statsRow(),
-- NEW: emitted only when settings.donuts
{ kind = "purse", balance = purse:balance(), today = purse:today().earned, page = shopPage },
{ kind = "sep" },
{ kind = "into", title = "Sessions", ... },
...
```

That is the **only** entry point to the shop. No second row under Appearance, no menu bar badge.

> ⚠️ `home()` is currently ~24 rows ≈ 800 pt. `Menu:fill` clamps to the screen but does **not** scroll. +40 pt is close to the limit on a 13" display. If it overflows, fold *Show me a note* / *Show me a question* / *Reload* into a single `into "Try it"` sub-page — do **not** drop the purse row.

### 7.3 `shopPage()` — an index, not a list

A flat shop would be ~35 rows ≈ 1,400 pt and would render off-screen. Paginate by shelf, using the existing `descend`/`ascend` machinery:

```
{ kind = "purse",  balance = N, today = M }            -- header, no page, not clickable
{ kind = "sep" }
{ kind = "into", title = "Sprites",         value = "1/6", page = shelfPage("coat")   }
{ kind = "into", title = "Colours",         value = "2/5", page = shelfPage("skin")   }
{ kind = "into", title = "Hats",            value = "0/6", page = shelfPage("hat")    }
{ kind = "into", title = "Sounds",          value = "1/4", page = shelfPage("sound")  }
{ kind = "into", title = "Toys and treats", value = "2/5", page = shelfPage("toy")    }
{ kind = "into", title = "Seasonal",        value = "0/3", page = shelfPage("season") }
{ kind = "sep" }
{ kind = "row",  title = "Feed him a donut", value = "30", note = <see below>, act = feed }
{ kind = "into", title = "How donuts work",  page = earningPage }
{ kind = "sep" }
{ kind = "toggle", title = "Keep the counter", on = settings.donuts,
  note = "cosmetics only — nothing he tells you is behind it" }
{ kind = "sep" }
backRow()
```

13 rows ≈ 480 pt. Fits everywhere.

*Feed him a donut* note text, spelled out as if/else (never `cond and a or b` — `""` and `nil` are both plausible branch values here):
- can't afford → `"30 donuts"`, `tone = "faded"`
- already fed today → `"he's had one today"`, `tone = "faded"`
- otherwise → `"he'll be pleased with himself"`

### 7.4 `shelfPage(kind)` — the shelf

```
{ kind = "label", title = Shop.kindLabel(kind) }
-- for hat/skin/coat/sound/toy only, a way back to nothing:
{ kind = "choice", title = "Bare-headed", on = settings.hat == "", act = unequip }
-- then one row per item, from Shop.state(item, wallet, settings, now):
  "worn"   -> { kind = "choice", title = label, on = true,  note = "worn" }
  "owned"  -> { kind = "choice", title = label, on = false, note = "owned", act = equip }
  "buy"    -> { kind = "row", title = label, value = tostring(price), note = item.note, act = buy }
  "short"  -> { kind = "row", title = label, value = tostring(price), tone = "faded",
                note = (price - balance) .. " more to go" }
  "closed" -> { kind = "row", title = label, value = tostring(price), tone = "faded",
                note = detail }              -- e.g. "October only"
{ kind = "sep" }
backRow()
```

Max 9 rows ≈ 340 pt. `choice` and `toggle` keep the panel open and redraw in place — which is exactly right for equipping, and `Menu:descend` already carries `pageNow` down and back up so a purchase redraws the shelf with the new balance.

Buying is a `row`, so the panel **closes** on purchase — deliberate. It's a small ceremony, and it stops double-taps.

### 7.5 `earningPage()` — the conscience, made visible

```
{ kind = "label", title = "Today" }
{ kind = "stats", items = { { label = "earned", value = "44" },
                            { label = "turns",  value = "35" },
                            { label = "streak", value = "5d" } } }
{ kind = "sep" }
{ kind = "label", title = "Where today's came from" }
{ kind = "row", title = "Showing up",       value = "4"  }
{ kind = "row", title = "5-day streak",     value = "5"  }
{ kind = "row", title = "Turns finished",   value = "6"  }
{ kind = "row", title = "Time worked",      value = "10" }
{ kind = "row", title = "Tokens",           value = "8"  }
{ kind = "row", title = "Focus stretches",  value = "8"  }
{ kind = "sep" }
{ kind = "row", title = "Tokens are worth less as they pile up", tone = "faded",
  note = "the first 100k of a day pays five times what the last does" }
{ kind = "row", title = "Most of it is for showing up", tone = "faded",
  note = "burning tokens is a bad way to earn — that's on purpose" }
{ kind = "sep" }
{ kind = "toggle", title = "Let him mention it", on = settings.donutNotes,
  note = "once a day at most, never while something needs you" }
{ kind = "sep" }
backRow()
```

If the cap bit today, scale the six stream figures proportionally so they sum to the displayed total, and change the first faded row's title to `"Capped at 50 for the day"`.

### 7.6 The one interruption — held to the §4 standard

`M.maybeMilestone()` may fire **at most once per calendar day**, and only when **all** of:

- `settings.donuts` **and** `settings.donutNotes` (default: `true` / **`false`**)
- `purse.day.told == false`
- the balance just crossed the price of an item that was previously unaffordable
- `Hush.check(settings)` returns `show == true`
- `sessions:isWaiting() == false`
- `away:isAway() == false`
- `fox:hidden() == false`

The note itself: **no chime** (`Chime.SILENT`), **no `fox:startle()`**, `hold = Palette.lingerStep` (7 s), body `"you can afford " .. item.label`, one chip `{ label = "shop", act = M.openShop }`. Then `purse.day.told = true`.

Existing live-progress notes are 4 per turn, one per 2 min. This is **one per day**. Comfortably stricter.

**The menu bar is off limits.** `M.paintBar` never mentions donuts. It carries "something is blocked on you," and nothing may compete with that.

### 7.7 CLI

```
foxbot donuts     balance, today's breakdown by stream, streak, what you own
```

Reads `wallet.json` only. The CLI's contract — *"Never writes anything"* — is preserved: buying from the terminal is **not** offered.

---

## 8. Wiring into `init.lua`

**Start**, after `ledger`:

```lua
purse = Donuts.new(DEN .. "/wallet.json"):load()
Palette.unlock(Shop.ownedIds("skin", purse))
Shop.reconcile(purse, settings)
Palette.use(settings.skin or "dusk")     -- must come AFTER unlock
```

**In `handle()`**, immediately after the existing `ledger:append({ ... })` — reuse the same row table:

```lua
if settings.donuts then
  purse:roll(now)
  local got = purse:credit(row, now) + purse:watchStretch(row, now)
  if got > 0 then M.maybeMilestone() end
end
```

`Donuts:roll` is called **only from the credit path**, never on the timer — so a machine left running overnight does not silently accrue a Morning bonus for a day nobody worked.

**In the pulse** (`M.pulse`, every 3 s), one line:

```lua
if settings.donuts then purse:settle(os.time()) end   -- closes a stretch once the 20-min gap passes
```

**Quick-answer bonus** — `Sessions:answered` gains a second return:

```lua
function Sessions:answered(event)  -- -> had, since
```
Existing tests (`ok("answered reports it had one", fresh:answered("b"))`) still pass; an extra return value is invisible to them. Then in `handle()` and in the `chase` dismiss chip:

```lua
local had, since = sessions:answered(event)
if had and since and (now - since) <= 60 then purse:bonus("answer", now) end
```

---

## 9. Settings — 7 new SCHEMA entries

```lua
  donuts      = true,     -- the counter and the shop exist at all
  donutNotes  = false,    -- may he ever mention it (once a day, at most)
  hat         = "",       -- equipped accessory id; "" = bare-headed
  toy         = "",       -- equipped toy id; "" = none
  soundPack   = "",       -- equipped chime pack; "" = the built-in map
  nameplate   = "",       -- what you called him; "" = "Foxbot"
  flair       = {},       -- id -> true; the non-exclusive extras (sparkles, plaque)
  treatAt     = 0,        -- ts of the last snack, for the once-a-day cooldown
```

That's 8 — `treatAt` is internal but persisted, so it is declared like everything else. One entry each, no second list; `Settings.keys` derives itself as it already does.

---

## 10. Function signatures

### `donuts.lua`

```lua
local Donuts = {}
Donuts.__index = Donuts

Donuts.VERSION          = 1
Donuts.DAY_CAP          = 50
Donuts.WELCOME          = 20
Donuts.TOKEN_TIERS      = { {100000, 0.05/1000}, {300000, 0.025/1000}, {600000, 0.010/1000} }
Donuts.TIME_TIERS       = { {3600, 0.10/60},     {10800, 0.05/60},     {21600, 0.02/60}     }
Donuts.TURN_TIERS       = { {20, 0.25},          {60, 0.10}                                 }
Donuts.MIN_TURN_TOKENS  = 250
Donuts.MIN_TURN_SECONDS = 2
Donuts.TURN_GAP         = 10
Donuts.ELAPSED_CAP      = 900
Donuts.FUTURE_SLACK     = 300
Donuts.PAST_SLACK       = 86400
Donuts.MORNING          = 4
Donuts.STREAK_EACH      = 1
Donuts.STREAK_CAP       = 10
Donuts.STRETCH          = 4
Donuts.STRETCH_CAP      = 3
Donuts.ANSWER           = 1
Donuts.ANSWER_CAP       = 4
Donuts.STRETCH_MIN_TURNS   = 3
Donuts.STRETCH_MIN_SECONDS = 25 * 60
Donuts.STRETCH_GAP         = 20 * 60
Donuts.SEEN_CAP         = 500

-- pure arithmetic — no self, no io, no hs
function Donuts.tier(total, tiers)          --> number
function Donuts.dayValue(day)               --> number (uncapped)
function Donuts.capped(value)               --> number
function Donuts.dayKey(when)                --> "2026-08-06"
function Donuts.newer(a, b)                 --> boolean; strictly a > b, false when nil/equal
function Donuts.blank(now)                  --> the v1 table

-- io
function Donuts.new(path)                   --> wallet (unloaded)
function Donuts:load()                      --> self; missing/corrupt -> blank + WELCOME
function Donuts:save()                      --> nil; no-op when self.readOnly

-- earning
function Donuts:roll(now)                   --> awarded  (morning + streak, on a strictly newer date)
function Donuts:credit(row, now)            --> awarded  (row = the ledger row table)
function Donuts:bonus(kind, now)            --> awarded  ("stretch" | "answer")
function Donuts:watchStretch(row, now)      --> awarded
function Donuts:settle(now)                 --> awarded  (closes an open stretch past the gap)

-- spending / reading
function Donuts:balance()                   --> integer
function Donuts:can(price)                  --> boolean
function Donuts:owns(id)                    --> boolean
function Donuts:buy(id, price, now)         --> ok, reason   ("owned"|"poor")
function Donuts:consume(id, price, now)     --> ok, reason   ("poor"|"soon")
function Donuts:inventory()                 --> { id -> ts }
function Donuts:today(now)                  --> { earned, tokens, time, turns, bonus,
                                            --    turnsCount, streak, capped }  (zeros on a new day)
function Donuts:lifetime()                  --> { earned, spent, since, treats }
```

`Donuts:today` recomputes the per-stream split from the day totals so the breakdown always agrees with the headline, and scales proportionally when `capped` is true.

### `shop.lua`

```lua
local Shop = {}

Shop.SLOTS = { "coat", "skin", "hat", "sound", "toy" }
-- item = { id, kind, slot, label, price, note, art, season, repeatable, chimes, skin }
Shop.items = { ... }                        -- array, display order
Shop.by    = { }                            -- id -> item, built once at load

function Shop.get(id)                                --> item | nil
function Shop.shelf(kind)                            --> array
function Shop.kinds()                                --> { { key, label }, ... }
function Shop.kindLabel(kind)                        --> string
function Shop.inSeason(item, when)                   --> boolean, why   (why is nil when open)
function Shop.state(item, wallet, settings, when)    --> "worn"|"owned"|"buy"|"short"|"closed", detail
function Shop.equip(item, settings)                  --> boolean        (writes ONE settings key + save)
function Shop.unequip(slot, settings)                --> boolean
function Shop.worn(slot, settings)                   --> id | ""
function Shop.owned(kind, wallet)                    --> ownedCount, total
function Shop.ownedIds(kind, wallet)                 --> array of ids
function Shop.affordable(wallet, settings, when)     --> integer
function Shop.cheapestUnowned(wallet, settings, when)--> item | nil
function Shop.reconcile(wallet, settings)            --> integer (things unequipped)
function Shop.chimes(settings)                       --> table  (pack map, or {} for built-in)
```

`Shop.chimes` is read by `init.lua`'s `chimeFor`, layered **under** `settings.chimes` so a hand-picked sound always wins:

```lua
local function chimeFor(kind)
  return (settings.chimes or {})[kind]
      or Shop.chimes(settings)[kind]
      or DEFAULT_CHIMES[kind]
      or DEFAULT_CHIMES.done
end
```

### Supporting changes

```lua
function Palette.unlock(ids)                 -- filters Palette.order to free + owned
function Coats.all(moods, allowed)           -- allowed: set of permitted ids; nil = everything
Coats.fit = { foxbot = {x=.18,y=.02,w=.64,h=.34}, tanuki = {...}, ... }   -- hat box, fractions of the sprite frame
function Sprite:wearHat(path)                -- canvas[3]; nil clears
function Sprite:carry(path)                  -- canvas[4]; nil clears
function Sessions:answered(event)            -- now returns had, since
```

---

## 11. Lua traps to spell out

The `cond and X or Y` collapse has bitten this codebase three times. New places it will bite:

1. **`settings.donuts` defaults to `true` — the trap reverses.** `settings.donuts or true` can *never* be false, so the switch would be un-turn-off-able. Write `if settings.donuts == false then return end`, or read it plainly.
2. **`Donuts.newer(a, b)`** — `a and (a > b) or false` collapses to `false` when `a > b` is false *and* when `a` is nil, hiding the nil case. Spell out:
   ```lua
   function Donuts.newer(a, b)
     if type(a) ~= "string" then return false end
     if type(b) ~= "string" then return true end
     if a > b then return true else return false end
   end
   ```
3. **`Shop.inSeason` returns `(bool, why)`** where `why` is legitimately `nil` for a non-seasonal item. `item.season and check(item) or true` returns `true` when `check` returns `false`. If/else it.
4. **`Shop.state` returns `(state, detail)`** where `detail` is legitimately `nil`. Never `owned and nil or detail`.
5. **The wallet loader must use the Settings.load shape**, not `or`:
   ```lua
   local value = stored[name]
   if value ~= nil then out[name] = value else out[name] = default end
   ```
   `day.morning`, `day.told` and `wallet.readOnly` are all false-defaulting booleans — the exact shape of the `prepared` bug.
6. **`Shop.worn(slot, settings)` returns `""` for "nothing equipped", never `nil`** — because `settings.hat or "none"` would turn a deliberate `""` into `""` (fine) but `settings.hat == false` (from a corrupt file) into `"none"` silently. Coerce on load instead.
7. **Sprite canvas indices.** `sprite.lua` says *"Always present so its index never shifts"* about the badge at `[2]`. **Append** the hat at `[3]` and the toy at `[4]`. Inserting either before the badge breaks `paintBadge` silently.

---

## 12. Tests (~45 new assertions in `tests/run.lua`)

All run under the existing `hs` stub — `donuts.lua` and `shop.lua` need only `hs.json`, `io` and `os`.

**Tiers (8)** — `tier(0)` is 0 · exact band boundaries · `tier(250000, TOKEN_TIERS) == 8.75` · `tier(9000, TIME_TIERS) == 10.5` · `tier(35, TURN_TIERS) == 6.5` · past the last ceiling adds nothing · a total below the first ceiling · negative total is 0.

**Day value and cap (5)** — the three worked examples from §2.4 land on 20 / 44 / 50 · the heavy day is capped from 66.4 · `today().capped` is true only then.

**The delta model (5)** — two credits of the same size pay the same total as one credit of the sum · `paid` never exceeds `floor(dayValue)` · an award of 0 is possible and harmless · the fraction carries across turns (three 0.4-donut turns eventually pay 1) · **balance is always an integer after any sequence of credits**.

**Idempotence and abuse (10)** — the same `session_id@ts` credits nothing the second time · a turn under 250 tokens adds tokens/time but not to `day.turns` · two turns 5 s apart in one session count once toward turns · a `ts` 400 s in the future is rejected · a `ts` two days old is rejected · a rolled-back clock does not reset the day · a rolled-back clock does not re-award Morning · Morning fires exactly once per date · the streak advances only on a strictly newer date · `seen` clears on day roll.

**The prune invariant (2)** — **credit 200 donuts, prune the ledger to zero rows, reload both: balance is still 200** · `donuts.lua` does not `require` `foxbot.history` (grep assertion).

**Persistence (6)** — round-trip through `hs.json` loses nothing · a missing file yields blank + `WELCOME` · malformed JSON yields blank without throwing · a negative stored balance clamps to 0 · an inventory id not in `Shop.by` is dropped · `v = 99` loads read-only and `save()` is a no-op.

**Stretches (4)** — 3 turns in one folder over 25 min then a 21-min gap pays 4 · 2 turns does not · switching folder closes the old stretch · the fourth stretch of a day pays nothing.

**Shop (7)** — `state` returns `worn`/`owned`/`buy`/`short`/`closed` for the five setups · buying twice is a no-op and does not debit · buying what you can't afford returns `false, "poor"` · a seasonal item out of window is `closed` and cannot be bought · a seasonal item already owned is wearable out of window · `reconcile` clears a coat you don't own · `Shop.chimes` never overrides `settings.chimes`.

**Settings (2)** — the existing "no declared setting loads as nil" and "keys match the schema" loops must still pass with the 8 new entries · `donuts` survives being set to `false` and reloaded as `false` (the reversed-default trap).

---

## 13. Build order

1. `donuts.lua` + its tests. Nothing else. The arithmetic is the whole feature.
2. `shop.lua` with **palettes and the snack only** — zero art, and the loop is fully playable.
3. The `purse` row + `shopPage` / `shelfPage` / `earningPage`.
4. Wire `credit` into `handle()`, `settle` into the pulse. Ship it. **The economy is complete at this point** — everything after is content.
5. Stretch + quick-answer bonuses.
6. Hats (art), then coats (art), then toys, then sounds, then seasonal.
7. `foxbot donuts` in the CLI.
8. The milestone note — **last**, because it's the only thing that can annoy anyone.

---

## 14. Art required

| Asset | Count | Pipeline |
|---|---|---|
| Coats | 6 × (one 3×3 mood sheet + one base) = **12 generations** | `tools/slice_sheet.py` then `tools/import_sprite.py` — both already exist and already do exactly this. |
| Hats | **9 PNGs** (6 + 3 seasonal), transparent, authored to fill `Coats.fit[coat]` — a fractional box of the sprite frame, so one hat fits every coat. |
| Toys | **~7 PNGs** — yarn ball (1), moth (2 frames), plant (4 growth stages) |
| Snack | **3 PNGs** — donut whole / bitten / crumbs |
| Sparkles, donut glyph, plaque | **0** — drawn with canvas primitives |
| Palettes | **0** — table entries |
| Sound packs | **6 `.caf` clips** for `sound.fox` only; the other three packs are pure remaps of stock macOS sounds and ship as zero bytes |

`docs/SPRITES.md` needs a **per-species style contract**. The existing one is fox-specific ("same ear shape", "the exact palette"); each coat needs its own MUST-NOT-CHANGE block and its own seven-colour palette, with the nine mood blocks reused verbatim underneath. That's a one-page addition per coat, and the `WHAT TO CHANGE` sections are already written.

A coat is **sellable with only its base drawing** — `Coats.path` already falls back, and the mood still reads through the badge and the motion. Ship each coat with base + the four highest-value moods (`asking`, `running`, `settled`, `sleeping`) and fill the rest in later; nothing breaks and nothing needs re-pricing.


## Settings

- donuts = true  — the counter and the shop exist at all (NOTE: the only true-defaulting new boolean; `settings.donuts or true` can never be false)
- donutNotes = false  — may he ever mention donuts in a note; at most once a day
- hat = ""  — equipped accessory id; "" means bare-headed
- toy = ""  — equipped toy id; "" means none
- soundPack = ""  — equipped chime pack id; "" means the built-in DEFAULT_CHIMES map
- nameplate = ""  — what you called him; "" renders as "Foxbot"
- flair = {}  — id -> true; the non-exclusive extras (fx.sparkles, flair.plaque)
- treatAt = 0  — ts of the last snack fed, for the once-a-day cooldown

## Risks

- THE BIG ONE: someone 'simplifies' the balance to `sum(ledger) * rate - spent`. The ledger prunes at keepDays=30 and rewrites itself on load, so on day 31 the user silently loses a day of earnings, or goes negative with purchases implicitly revoked. Mitigation: donuts.lua must never require foxbot.history, and one test prunes the ledger to zero rows and asserts the balance is unchanged.
- home() is already ~24 rows / ~800pt and Menu:fill clamps to the screen rather than scrolling. Adding the 40pt purse row is close to the ceiling on a 13" display. If it overflows, fold the three demo/reload rows into an `into "Try it"` sub-page — do not drop the purse row.
- sprite.lua hard-codes canvas[1] = image and canvas[2] = badge, with a comment saying the badge index must never shift. Inserting a hat before the badge breaks paintBadge silently — the badge just stops appearing, with no error. Hat must be appended at [3], toy at [4].
- The reversed default trap: `donuts` is the first new boolean that defaults to TRUE. Any code written as `settings.donuts or true` makes the switch impossible to turn off, and it will look like it works in every test that leaves it on.
- Seasonal items create implicit 'buy now or wait a year' pressure, which is a dark pattern in a product whose core value is not being annoying. Mitigated by: never advertising them in a note, never showing a countdown, and keeping them forever once owned — but the temptation to add a countdown badge will recur and must be refused.
- The economy attaches a reward to a meter that measures the user's own money. Even with the concave curve, the framing can make spending feel good. Mitigation is the earningPage saying out loud that burning tokens is a bad way to earn, plus never printing a per-turn donuts-per-token figure anywhere.
- Sound packs could quietly overwrite a per-event sound the user picked by hand. Shop.chimes must layer strictly UNDER settings.chimes in chimeFor(), never over it.
- Wallet corruption or a mid-write crash would wipe months of inventory. Mitigated by tmp-file + os.rename plus a .bak copy, but the loader must also never throw on a malformed file — a broken wallet must degrade to a blank one, not stop the fox from starting.
- uninstall.sh deleting wallet.json without asking would silently destroy four months of accumulated inventory. It must print the path and require an explicit --purge.
- Coats.all() is called with zero and one argument by several existing tests. The new `allowed` filter must be an optional second argument that is permissive when nil, or the suite breaks.
- hs.json round-trips an empty Lua table as `{}` vs `[]` ambiguously; `own`, `flair`, `day.seen` and `day.beat` are all maps that start empty. The loader must coerce a decoded array back to a map rather than assuming a table shape.
- Clock and DST: os.date('%Y-%m-%d') is local time, so a DST transition produces a 23h or 25h day. Harmless for caps, but the strictly-greater date comparison means a westward timezone change can freeze the day for up to a day — acceptable, and preferable to the alternative of letting a clock change re-award bonuses.
- Six coats x ten moods is 60 drawings, which is by far the largest cost in the plan and the thing most likely to stall the feature. Mitigated by coats being sellable with only a base drawing, and by shipping palettes (zero art) first so the loop is playable before any generation happens.