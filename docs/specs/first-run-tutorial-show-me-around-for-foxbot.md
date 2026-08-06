# First-run tutorial ("show me around") for Foxbot

# Foxbot first-run tutorial — `foxbot.teach`

A six-card guided tour, drawn entirely with the existing speech-bubble panel, the
existing drawn menu, and the fox himself. **It contains no timers of its own and
no step advances on elapsed time.** Every step is completed by an action the code
actually observes; when it can't safely draw, it parks and the existing 3-second
pulse retries it.

---

## 0. Design invariants

| Invariant | How it is held |
|---|---|
| No macOS permission | Only `hs.canvas` + the panel/menu already in use. No eventtap start, no AppleScript, no network. |
| Never advances on a guess | The only clocks involved are (a) the shared `M.pulse` 3s timer, used *only* to retry a blocked re-show and to notice the menu closed, and (b) the bubble's own `hold` expiry, which counts as "ignored", never as "done". |
| Anti-annoyance ≥ live notes | Never starts while a turn is running, while something is blocked on you, while away, while presenting, during quiet hours, or while ≥1 real note is on screen. Yields to a question the instant one arrives. Plays no chime, ever. |
| Schema-driven settings | Two new SCHEMA entries. No second list. |
| Unit-testable | `Teach.new(deps)` takes plain function tables for panel/fox/board/world; the real `hs` is never touched inside `teach.lua` except `Palette` constants. |

---

## 1. Settings (exact)

Two entries added to `SCHEMA` in `hammerspoon/foxbot/settings.lua`, in a new
block after `prepared`:

```lua
  -- the guided tour
  taught      = 0,   -- tour version seen through to an ending (0 = never)
  taughtTries = 0,   -- auto-starts that never reached an ending
```

Both are numbers. Nothing else is persisted — deliberately not the step (see §7.2).

> **Trap, and it is the exact class of trap listed in the constraints:** `0` is
> **truthy** in Lua. `if settings.taught then` is *always* true and would disable
> the tour for everyone on first launch. Every read must be
> `(settings.taught or 0) >= Teach.VERSION` and `(settings.taughtTries or 0) >= Teach.MAX_STARTS`.
> Add a test named exactly `"zero taught is not truthy-skipped"` so it can't come back.

Derived `KEYS` picks both up automatically; the existing test
`"no declared setting loads as nil"` covers the round-trip for free.

## 1b. Palette token (not a setting)

`hammerspoon/foxbot/palette.lua`, in the metrics block beside `lingerLong`:

```lua
Palette.lingerTeach = 600  -- a tour bubble waits ten minutes for you
```

---

## 2. New module: `hammerspoon/foxbot/teach.lua`

### 2.1 Constants

```lua
Teach.VERSION    = 1    -- bump to re-run the tour for existing installs
Teach.MAX_STARTS = 3    -- unfinished auto-starts before we stop offering
Teach.MAX_EXPIRY = 2    -- bubbles that timed out unread before we give up
Teach.order      = { "hello", "drag", "click", "board", "signals", "quiet" }
Teach.cards      = { ... }   -- see §3; card ids are the six above plus "boardAgain"
```

### 2.2 Constructor

```lua
--- @param deps table  every field optional; defaults are inert so a test can
---   build one with two stubs.
--- {
---   settings = table,                                  -- the live settings table
---   save     = function(settings)                      -- default: no-op
---   panel    = { say = function(note) -> note,
---                count = function() -> n,
---                dismiss = function(note, why) },
---   fox      = { hidden = function() -> bool,
---                startle = function() },
---   board    = { isOpen = function() -> bool },
---   anchor   = function()                              -- re-anchor the panel to the fox
---   openMenu = function()                              -- opens the control panel
---   mayShow  = function() -> bool                      -- Hush: presenting / quiet hours
---   isAway   = function() -> bool,
---   waiting  = function() -> n,                        -- sessions:waitingCount()
---   running  = function() -> n,                        -- sessions:count()
---   voice    = function() -> string,                   -- settings.voice, for the sample note
--- }
function Teach.new(deps) -> teach
```

`deps.panel` / `deps.fox` / `deps.board` are **tables of functions, not the
objects**. init.lua wraps the real ones (`say = function(n) return panel:say(n) end`).
That is the seam that makes the whole module testable under `tests/support.lua`.

### 2.3 Public surface

```lua
function Teach:tick()                  -- called once per M.pulse (every 3s)
function Teach:begin(manual)           -- start at card "hello"; manual=true skips the try counter
function Teach:saw(signal) -> bool     -- an observed user action: "dragged" | "menu.open"
function Teach:standDown()             -- a real question landed; get off the screen
function Teach:menuRows() -> table     -- rows to splice into home(); {} unless step == "board"
function Teach:stop(why) -> string     -- why = "finished" | "dismissed" | "ignored"
function Teach:stepName() -> string?    -- current step id, or nil
function Teach:running() -> bool       -- state == "running" or "waiting"
```

### 2.4 Internals

```lua
function Teach:show(id, opts)          -- opts = { skipped = bool }
function Teach:build(id, opts) -> note -- the panel note table
function Teach:advance()               -- next in Teach.order, or stop("finished")
function Teach:jump(step, skipped)     -- satisfied out of order
function Teach:gone(why)               -- the note left the panel; why from §5
function Teach:canShow() -> bool
function Teach:canStart() -> bool
function Teach:sample()                -- the "this is what a real one looks like" note
function Teach:farewell()              -- one plain 12s note after "finished"
```

### 2.5 Fields

`state` (`"idle" | "running" | "waiting" | "done"`), `step` (id in `Teach.order`
or nil), `card` (card id or nil), `note` (the live panel note or nil), `ticks`,
`expiries`, `wasOpen`.

---

## 3. The cards — exact copy

All cards carry `lines` and/or `chips`, so `measureNote`'s `detailed` flag is
true and every bubble renders at **`Palette.noteWide` = 440 px**. Inner width
412 px; body wraps at ~52 Menlo chars at 12 pt. `stamp` is drawn right-aligned
in a 130 px box starting at x = 440 − 14 − 130 = **296**, so **titles must stay
under 26 characters** or they collide with the step counter. All eight titles
below are ≤ 21.

Every card gets `hold = Palette.lingerTeach` (600) and
`onGone = function(_, why) self:gone(why) end`.
`onOpen` is **the first chip's `act`** (spelled out with if/else — see §8),
so clicking the bubble body always means "carry on".

---

### Card 1 — `hello`   (step `hello`)

```
title  "hello"
stamp  "1 of 6"
body   "I watch your Claude Code sessions and say something when one finishes,
        breaks, or gets stuck waiting on you."
lines  · six steps, about a minute
       · the ✕ up in the corner ends the tour for good
chips  [ start ]  [ no thanks ]
```
`start` → `advance()`  ·  `no thanks` → `stop("dismissed")`

### Card 2 — `drag`   (step `drag`)

```
title  "put me somewhere"
stamp  "2 of 6"
body   "Click and hold anywhere on me and drag. I stay where you drop me —
        including on a second screen, and my notes come with me."
lines  · where you put me survives a restart
chips  [ he's fine there ]  [ stop the tour ]
```
`he's fine there` → `advance()` · `stop the tour` → `stop("dismissed")`
**Also advanced by a real drag** — see §4.

### Card 3 — `click`   (step `click`)

```
title  "one click opens me"
stamp  "3 of 6"
body   "A single click brings up my control panel. Everything I do is in there;
        none of it is buried in a system menu."
lines  · ⌃⌥⌘T opens it from the keyboard
       · ⌃⌥⌘F hides and shows me
chips  [ open it for me ]  [ stop the tour ]
```
`open it for me` → `deps.openMenu()` (which itself fires `saw("menu.open")`)
**Also advanced by clicking the fox, the menu-bar icon, or ⌃⌥⌘T.**
The two key hints match `TOGGLE_KEY` / `REPORT_KEY` in init.lua exactly.

### Card 4 — `board`   (step `board`) — posted the instant the panel opens

```
title  "this is the panel"
stamp  "4 of 6"
body   "The top line is what I'm doing right now. Under it, today's turns, time
        and tokens. Everything below that is a switch you own."
lines  · carry on from the orange row at the top of the panel
chips  (none)
```

The drawn menu puts a full-screen invisible sheet at `floating + 1`, above the
panel's `floating` canvas — **while the menu is open the bubble is visible but
not clickable**, so chips and the ✕ would be a lie. The controls for this step
live *in the menu itself*: `Teach:menuRows()` splices two rows plus a separator
at the very top of `home()` (§6.1).

### Card 4b — `boardAgain`   (step `board`) — recovery, see §7.4

```
title  "still on step 4"
stamp  "4 of 6"
body   "The panel closed before you got to the orange row. Open it again and
        it'll be waiting at the top."
lines  · nothing was lost — you're still on step four
chips  [ open the panel ]  [ stop the tour ]
```

### Card 5 — `signals`   (step `signals`)

```
title  "how I tell you things"
stamp  "5 of 6"
body   "The dot on my shoulder and the count in the menu bar are the whole
        status. Blue is working, amber is waiting on you, green just finished."
lines  · 3 in the menu bar — three turns running
       · ?2 — two sessions blocked on a question
       · a question gets asked again at 1m, 5m, 15m until you answer
chips  [ next ]  [ show me one ]  [ stop the tour ]
```
`next` → `advance()` · `show me one` → `sample()` then re-`show("signals")`
Chip widths at 10.5 pt Menlo: 45 + 89 + 102 + 12 gaps = 248 px, inside 412.
`?2` matches `M.paintBar`'s `"?" .. blocked` exactly. `1m, 5m, 15m` matches
`Sessions.NUDGE_AFTER = { 60, 300, 900 }`.

**`Teach:sample()`** posts an ordinary panel note and touches nothing else — no
`handle()`, no `sessions:wait`, no ledger row (unlike the existing `M.demo`,
which does append to the ledger and would pollute the user's very first day of
stats):

```
title  "payments-api"
body   Voice.line(deps.voice(), "done")        -- e.g. "finished."
lines  · Split the payment handler into charge, refund and webhook modules
       · 17 tests passing, 2 skipped
       · a real one carries terminal / folder / copy buttons down here
stamp  "2m 14s · 37.0k"
hold   Palette.linger   (12s)
```
No chips — a dead button is worse than a sentence describing it.

### Card 6 — `quiet`   (step `quiet`)

```
title  "and how to shut me up"
stamp  "6 of 6"
body   "I'd rather be quiet than clever. Every interruption I make has a switch,
        and several are already on your side."
lines  · live notes: one per 2 minutes, four a turn, never over a question
       · silent while you're screen sharing, always
       · away or asleep, I hold it all and hand back one summary
chips  [ finish ]
```
`finish` → `advance()` → last step → `stop("finished")` → `farewell()`.
Height ≈ 270 px, so it clears the bottom of a 800 px screen when anchored to a
centred fox.

### Farewell (a plain note, not a tour card — no `onGone`, no step)

```
title  "that's the lot"
body   "I'll keep out of the way now. “Show me around again” is at the bottom
        of my panel if you want this back."
hold   Palette.linger  (12s)
```
No lines, no chips → `detailed` is false → the note shrinks to its text.

---

## 4. The state machine

### States

| state | meaning |
|---|---|
| `idle` | never started; `tick()` is watching for a safe moment |
| `running` | a card is on screen |
| `waiting` | a step is live but its bubble is *not* on screen; `tick()` will re-show it |
| `done` | over. `taught` is persisted. Only `begin(true)` can leave this state. |

### Transitions

| from | trigger | to | posts |
|---|---|---|---|
| `idle` | `tick()` with `ticks ≥ 2` and `canStart()` and `(taught or 0) < VERSION` and `(taughtTries or 0) < MAX_STARTS` | `running` @ `hello` | card 1 (and `taughtTries += 1`, saved) |
| `idle` | `tick()` with `(taught or 0) >= VERSION` | `done` | — |
| `idle` | `tick()` with `(taughtTries or 0) >= MAX_STARTS` | `done` via `stop("ignored")` | — |
| `hello` | chip `start` / body click | `drag` | card 2 |
| `hello` \| `drag` | `saw("dragged")` | `click` (skips step 2) | card 3, `skipped` line |
| `drag` | chip `he's fine there` / body | `click` | card 3 |
| `hello` \| `drag` \| `click` | `saw("menu.open")` | `board`, `wasOpen = true` | card 4 (+ menu rows) |
| `click` | chip `open it for me` | → `openMenu()` → `saw("menu.open")` | card 4 |
| `board` | menu row `Tour · carry on` | `signals` | card 5 |
| `board` | `tick()` sees `wasOpen and not board.isOpen()` | `board` (same step) | card 4b |
| `board` | `saw("menu.open")` again (from card 4b) | `board` | card 4 |
| `signals` | chip `next` / body | `quiet` | card 6 |
| `signals` | chip `show me one` | `signals` (no move) | sample note, then card 5 again |
| `quiet` | chip `finish` / body | `done` via `stop("finished")` | farewell |
| any | ✕ on the bubble (`gone("cross")`) | `done` via `stop("dismissed")` | — |
| any | chip `no thanks` / `stop the tour`, or menu row `Tour · stop showing me this` | `done` via `stop("dismissed")` | — |
| `running` | `gone("expired")` × `MAX_EXPIRY` | `done` via `stop("ignored")` | — |
| `running` | `gone("expired" \| "evicted" \| "cleared" \| "yielded")` under the cap | `waiting` (step kept) | — |
| `waiting` | `tick()` with `canShow()` | `running` (same card) | the same card again |
| `running` | `standDown()` — a real question arrived | `waiting` | — |
| `done` | menu row `Show me around again` → `begin(true)` | `running` @ `hello` | card 1 |

### The out-of-order rule

**An observed action satisfies its own step wherever you are in the tour.** If
you drag him during card 1, step `drag` is already done — don't teach it. The
next card is posted with `opts.skipped = true`, which prepends one line:

```
· (you'd already done that one)
```

so the jump from "1 of 6" to "3 of 6" reads as intentional rather than as a bug.

### `tick()` — exact order

```
ticks += 1
if state == "done" then return
if state == "idle" then
   if ticks < 2 then return                      -- ~6s after load; politeness, not correctness
   if (taught or 0) >= VERSION       then state = "done"; return
   if (taughtTries or 0) >= MAX_STARTS then stop("ignored"); return
   if not canStart()                 then return -- try again in 3s, forever
   taughtTries += 1; save(settings); begin(false); return
end
if step == "board" then                          -- menu-close detection, poll (§7.4)
   local open = board.isOpen()
   if wasOpen and not open then wasOpen = false; show("boardAgain")
   elseif open then wasOpen = true end
end
if state == "waiting" and canShow() then show(step) end
```

### The two gates

```lua
function Teach:canShow()          -- may a tour bubble go on screen right now?
  if self.fox.hidden()   then return false end   -- nothing to point at
  if not self.mayShow()  then return false end   -- presenting, or quiet hours
  if self.isAway()       then return false end   -- nobody is reading
  if self.waiting() > 0  then return false end   -- something is blocked on you
  if self.panel.count() >= 2 then return false end -- real notes are stacking
  return true
end

function Teach:canStart()         -- may the tour begin at all?
  if not self:canShow()   then return false end
  if self.running() > 0   then return false end  -- a turn is mid-flight
  if self.panel.count() > 0 then return false end
  return true
end
```

`canShow()` is only ever consulted while our own bubble is *off* screen, so
`panel.count()` is a count of real notes.

---

## 5. Panel change: a dismissal reason

The tour must tell "you clicked ✕" (stop) apart from "a real note pushed me out"
(yield). Today both arrive as a silent `Panel:drop`. Four small edits to
`hammerspoon/foxbot/panel.lua`:

```lua
function Panel:drop(note, why)
  for index, held in ipairs(self.notes) do
    if held == note then table.remove(self.notes, index) break end
  end
  if note.expires then note.expires:stop() note.expires = nil end
  if self.hot and self.hot.note == note then self.hot = nil end

  -- Cleared first, so a callback that posts another note can't re-enter this.
  local gone = note.onGone
  if gone then
    note.onGone = nil
    gone(note, why or "gone")
  end
end

function Panel:dismiss(note, why) self:drop(note, why) self:render() end
```

Call sites, each passing its reason:

| site | reason |
|---|---|
| `Panel:say` expiry timer | `"expired"` |
| `Panel:say` overflow eviction loop | `"evicted"` |
| `Panel:clear` | `"cleared"` |
| `Panel:wire` mouseDown | `"chip"` / `"cross"` / `"body"` |
| `Teach:standDown` / `Teach:stop` | `"yielded"` |

In `Panel:wire`'s `mouseDown`, spelled out rather than chained (`found.cross`
is a genuine `false`, so `found.cross and "cross" or "body"` is a landmine
waiting for the next reason to be added):

```lua
local why = "body"
if found.act then why = "chip"
elseif found.cross then why = "cross" end
self:dismiss(note, why)
```

`Teach:gone(why)`:

```lua
self.note = nil
if why == "cross"                    then self:stop("dismissed") return end
if why == "chip" or why == "body"    then return end   -- the act/onOpen decides
if why == "expired" then
  self.expiries = self.expiries + 1
  if self.expiries >= Teach.MAX_EXPIRY then self:stop("ignored") return end
end
self.state = "waiting"                                  -- tick() will re-show
```

**`menu.lua` is not modified at all.**

---

## 6. init.lua hook points (exact)

| # | Where | Change |
|---|---|---|
| 1 | after `local Board = require("foxbot.menu")` (line 26) | `local Teach = require("foxbot.teach")` |
| 2 | `local settings, fox, panel, board, bar, watcher, keys` (line 67) | add `teach` |
| 3 | `handle()`, in `if kind == "ask" or kind == "idle" then` after `sessions:wait(event)` (line 397) | `if teach then teach:standDown() end` |
| 4 | `home()` (line 805) | splice `Teach:menuRows()` (§6.1) + add the re-run row (§6.2) |
| 5 | `M.openMenu` (line 859), **after** the `board:isOpen()` early-return and **before** `board:open(home(), …)` | `if teach then teach:saw("menu.open") end` |
| 6 | `start()`, sprite `onMoved` (line 995) | `if teach then teach:saw("dragged") end` |
| 7 | `start()`, after `away = Away.new{…}` (line 1012) | construct `teach` (§6.3) |
| 8 | `M.pulse` (line 1027), after `away:check()` | `teach:tick()` |
| 9 | `M.state()` (line 909) | `teaching = teach and teach:stepName() or "off"` |
| 10 | controls section | `M.teach()` and `M.forgetTutorial()` (§6.4) |

**Ordering at #5 is load-bearing** and needs a comment: `saw("menu.open")` must
run before `home()` is evaluated, because it is what flips the step to `board`,
which is what makes `menuRows()` non-empty.

### 6.1 The step-4 menu rows

```lua
function Teach:menuRows()
  if self.state == "done" or self.step ~= "board" then return {} end
  return {
    { kind = "row", title = "Tour · carry on", note = "step 4 of 6", tone = "fur",
      act = function() self:advance() end },
    { kind = "row", title = "Tour · stop showing me this", tone = "faded",
      act = function() self:stop("dismissed") end },
    { kind = "sep" },
  }
end
```

`tone = "fur"` resolves through `Menu:paint`'s `ink = c[row.tone] or ink` to the
fox's burnt orange in every skin — which is why card 4 says "the orange row".
Height added: 32 + 15 (note) + 32 + 11 = **90 px, present only during step 4**.

In `home()`:

```lua
function home()
  local rows = {}
  for _, row in ipairs(teach:menuRows()) do rows[#rows + 1] = row end
  rows[#rows + 1] = statusRow()
  ... existing rows unchanged ...
  return rows
end
```

`menuRows()` returns `{}`, never nil, so the loop is unconditional.

### 6.2 The permanent re-run row

In `home()`'s bottom command block, immediately before `Show me a note`:

```lua
{ kind = "row", title = "Show me around again",
  note = "the first-run tour, six steps",
  act = function() M.teach() end },
```

`kind = "row"` closes the panel then runs `act`, which is exactly what we want:
the tour's first bubble should land on a clear screen. Height added: 32 + 15 = **47 px, permanent** (see Risks).

### 6.3 Construction

```lua
teach = Teach.new({
  settings = settings,
  save     = Settings.save,
  panel = {
    say     = function(note) return panel:say(note) end,
    count   = function() return panel:count() end,
    dismiss = function(note, why) panel:dismiss(note, why) end,
  },
  fox   = { hidden = function() return fox:hidden() end,
            startle = function() fox:startle() end },
  board = { isOpen = function() return board:isOpen() end },
  anchor   = function() panel:anchorTo(fox:frame(), fox:screen()) end,
  openMenu = function() M.openMenu() end,
  mayShow  = function()
    local _, show = Hush.check(settings)   -- presenting, and quiet hours
    return show
  end,
  isAway  = function() return away and away:isAway() or false end,
  waiting = function() return sessions:waitingCount() end,
  running = function() return sessions:count() end,
  voice   = function() return settings.voice end,
})
```

### 6.4 Two controls

```lua
--- Run the tour now, from the menu. Does not touch `taught`: abandoning a
--- deliberate re-run must not cause an automatic one later.
function M.teach()
  teach:begin(true)
end

--- Put the install back to "never toured" and run it. For testing, from
--- Hammerspoon's own Console — which is in-process, so this needs no
--- AppleScript bridge and no permission.
function M.forgetTutorial()
  settings.taught, settings.taughtTries = 0, 0
  Settings.save(settings)
  teach:begin(true)
  return "tour reset"
end
```

---

## 7. The robustness questions, answered

### 7.1 It runs exactly once — which setting, and when is it marked done

`settings.taught`. It is written **once, at every possible ending**, inside
`Teach:stop(why)` — which is the single exit from the state machine:

```lua
function Teach:stop(why)
  if self.note then
    local note = self.note
    self.note = nil
    self.panel.dismiss(note, "yielded")   -- onGone was cleared in drop; no re-entry
  end
  self.state, self.step, self.card, self.wasOpen = "done", nil, nil, false
  self.settings.taught = Teach.VERSION
  self.save(self.settings)
  if why == "finished" then self:farewell() end
  return why
end
```

Three endings, all of which mark it done: `"finished"` (card 6), `"dismissed"`
(✕, any `stop the tour` chip, `no thanks`, or the menu row), `"ignored"` (two
expiries, or `MAX_STARTS` unfinished starts). There is no path that ends the
tour without persisting, and `Settings.save` is derived from the schema, so the
key cannot be silently dropped — that is the bug this project's settings module
exists to prevent, and it is the same bug that would make a tutorial re-run
forever.

`Teach.VERSION` being a number rather than a boolean means a future v2 tour can
re-run for existing users by bumping one constant.

### 7.2 Quit halfway through → **restart, capped at three**

Not resume. Two reasons, both concrete:

1. Step 4's card is only true while the control panel is open. Resuming there
   after a relaunch would post "this is the panel" over a closed panel. Every
   resume scheme needs a per-step "safe resume point" table; restarting needs
   none.
2. Steps 1–2 take fifteen seconds. Re-reading them is cheaper than the class of
   bug that a persisted step index invites.

The nagging that restart-forever would cause is bounded by `taughtTries`, which
is incremented **at the moment the tour actually begins** (not when eligibility
is checked — so a launch where you happened to be in a Zoom call costs nothing).
On the fourth launch `tick()` sees `taughtTries >= MAX_STARTS`, calls
`stop("ignored")`, and the tour is done for good. Worst case a user who never
engages sees card 1 three times, total.

### 7.3 They drag him mid-tutorial

Nothing special happens — the tour has no opinion about where he is, `Panel:anchorTo`
is already called from `onMoved`, and the bubble follows him. If the current step
is `hello` or `drag`, the drag *satisfies step 2* via `Sprite:release` →
`onMoved` → `saw("dragged")` → jump to `click` with the `(you'd already done
that one)` line. Note this is the sprite's own drag poll reporting
`travelled >= CLICK_SLOP` — a click is not a drag, and the tutorial inherits that
distinction for free.

If they drag during steps 3–6, `saw("dragged")` returns false and nothing moves.

### 7.4 They click the menu mid-tutorial

Three cases, all handled:

- **Opening it early** (steps 1–3): `M.openMenu` fires `saw("menu.open")`, which
  jumps straight to step `board` — because the truthful card at that moment is
  the one about the panel that is now open. The tour rows appear in the same
  `home()` build.
- **Closing it during step 4 without using the tour row** (clicking the
  background sheet, pressing the fox again, or clicking any other row):
  `tick()` polls `board.isOpen()`. `wasOpen` was set true synchronously inside
  `saw("menu.open")`, so a close is always detected even if no tick landed while
  it was open. Within 3 s the recovery card `boardAgain` appears with an
  `open the panel` chip. **This is why polling is used instead of a
  `Menu.onClosed` hook**: `Menu:open` calls `self:close()` first, and
  `row.act()` runs *after* `close()` — a callback would fire spuriously and
  would need a token-guarded deferral to avoid a flash of the stale card. The
  poll has no ordering hazard at all, and 3 s of latency on a recovery path is
  invisible.
- **Using some other row** (e.g. toggling Live progress notes): allowed and
  unremarkable. The row closes the panel, the recovery card comes back, the step
  is unchanged.

### 7.5 Skippable at every step

| card | how to stop |
|---|---|
| hello | ✕, or `no thanks` |
| drag, click, boardAgain, signals | ✕, or `stop the tour` |
| board | `Tour · stop showing me this` in the panel (✕ and chips are behind the sheet, so the escape is where the clicks actually land) |
| quiet | ✕, or just `finish` |

Plus the global escapes, which all end it: hiding him (⌃⌥⌘F → `panel:clear()` →
`gone("cleared")` → `waiting`; `canShow()` stays false while hidden, so it never
comes back until he does), and simply walking away twice (`MAX_EXPIRY`).

### 7.6 It must not fire during a real session's events

Four layers:

1. **It won't start** while anything is running or waiting, while any note is on
   screen, while away, presenting, in quiet hours, or while he's hidden
   (`canStart`). On a machine that is already busy, the tour waits — possibly
   for hours — and costs nothing, because `taughtTries` is only spent on an
   actual start.
2. **It gets out of the way** the moment a question lands: `handle()`'s
   `ask`/`idle` branch calls `teach:standDown()` *before* `announce()` posts the
   question's note, so the question is alone on screen.
3. **It never suppresses real work.** Real notes post normally throughout. If the
   column overflows, the tour bubble is the oldest and is evicted first — which
   is exactly right, and arrives as `gone("evicted")` → `waiting`.
4. **It never competes for space.** `canShow()` refuses to re-post while ≥ 2 real
   notes are up, so a busy stretch parks the tour rather than fighting it.

It also never plays a chime — `Chime.play` is not called anywhere in `teach.lua`.

### 7.7 Re-runnable

`Show me around again` in `home()` → `M.teach()` → `Teach:begin(true)`, which
works from `done` and does not touch `taughtTries`. Discoverable next to the
existing `Show me a note` / `Show me a question` demo rows.

### 7.8 No timing luck

`teach.lua` creates **zero timers**. The full inventory of anything clock-shaped:

| clock | what it may do | what it may never do |
|---|---|---|
| `M.pulse` (3 s, already exists) | start the tour when it's safe; re-show a parked card; notice the menu closed | advance a step |
| `Palette.lingerTeach` (600 s, the note's own expiry) | count toward `MAX_EXPIRY` | advance a step |
| `ticks >= 2` before the first start | delay the first bubble to ~6 s after load | anything else — it is politeness, and every other precondition is re-checked at the same instant |

Every forward transition in §4 is caused by a mouse event that the panel or the
menu actually dispatched into a hit-tested rect, or by `Sprite:release` reporting
a real drag distance.

---

## 8. Lua traps specific to this feature

Each one is the shape that has already bitten this codebase three times.

```lua
-- WRONG: 0 is truthy. This disables the tour for literally everyone.
if settings.taught then return end
-- RIGHT
if (settings.taught or 0) >= Teach.VERSION then return end

-- WRONG: collapses to nil when the card genuinely has no chips, but also
-- collapses if a chip is ever given a falsy act.
local onOpen = chips[1] and chips[1].act or nil
-- RIGHT
local onOpen = nil
if chips[1] then onOpen = chips[1].act end

-- WRONG: found.cross is a real `false`, so this silently reports "body" today
-- and will silently mis-report the next reason someone adds.
self:dismiss(note, found.cross and "cross" or "body")
-- RIGHT: the if/else in §5.

-- WRONG: opts may be nil, and skipped may legitimately be false.
local skipped = opts and opts.skipped or true
-- RIGHT
local skipped = false
if opts and opts.skipped == true then skipped = true end
```

Also: `canShow()` and `saw()` must `return true` / `return false` explicitly,
never the value of an `and` chain, so a caller can safely write `if not x`.
`menuRows()` returns `{}`, never nil.

---

## 9. Testing

### 9.1 Unit tests — `tests/run.lua`, new `-- ------ teaching` block

A harness with no Hammerspoon in it:

```lua
local Teach = require("foxbot.teach")

local function harness(over)
  over = over or {}
  local w = {
    notes = {}, menuOpen = false, hidden = false, away = false,
    mayShow = true, waiting = 0, running = 0, opened = 0, saves = 0,
  }
  local settings = Settings.load()
  local teach = Teach.new({
    settings = settings,
    save     = function() w.saves = w.saves + 1 end,
    panel = {
      say   = function(note) w.notes[#w.notes + 1] = note return note end,
      count = function() return #w.notes end,
      dismiss = function(note, why)
        for i, n in ipairs(w.notes) do
          if n == note then table.remove(w.notes, i) break end
        end
        local gone = note.onGone
        if gone then note.onGone = nil gone(note, why) end
      end,
    },
    fox      = { hidden = function() return w.hidden end, startle = function() end },
    board    = { isOpen = function() return w.menuOpen end },
    anchor   = function() end,
    openMenu = function() w.opened = w.opened + 1 w.menuOpen = true teach:saw("menu.open") end,
    mayShow  = function() return w.mayShow end,
    isAway   = function() return w.away end,
    waiting  = function() return w.waiting end,
    running  = function() return w.running end,
    voice    = function() return "plain" end,
  })
  for k, v in pairs(over) do w[k] = v end
  return teach, w, settings
end

local function last(w) return w.notes[#w.notes] end
local function chip(w, label)                     -- click a chip the way Panel does
  local note = last(w)
  for _, c in ipairs(note.chips or {}) do
    if c.label == label then
      w.panelDismiss = nil
      -- Panel dismisses first, then runs the act.
      local gone = note.onGone
      for i, n in ipairs(w.notes) do if n == note then table.remove(w.notes, i) break end end
      if gone then note.onGone = nil gone(note, "chip") end
      c.act()
      return true
    end
  end
  return false
end
```

Checks (name → assertion):

**Starting**
1. `"nothing on screen before the first tick"` — `#w.notes` → `0`
2. `"nothing on the very first tick"` — `teach:tick()`; `#w.notes` → `0`
3. `"starts on the second tick"` — `tick()` ×2; `teach:stepName()` → `"hello"`
4. `"a try is spent when it starts"` — `settings.taughtTries` → `1`
5. `"and the try is persisted"` — `w.saves >= 1` → `true`
6. `"a running turn holds it back"` — `w.running = 1`; ×3 ticks; `stepName()` → `nil`
7. `"a blocked question holds it back"` — `w.waiting = 1`; → `nil`
8. `"a hidden fox holds it back"` — `w.hidden = true`; → `nil`
9. `"quiet hours hold it back"` — `w.mayShow = false`; → `nil`
10. `"being away holds it back"` — `w.away = true`; → `nil`
11. `"a real note on screen holds it back"` — pre-push one note; → `nil`
12. `"a held-back start spends no try"` — `settings.taughtTries` → `0`
13. `"it starts as soon as things go quiet"` — hold back, then clear, tick → `"hello"`
14. `"zero taught is not truthy-skipped"` — fresh settings, `taught` is `0`, tour starts
15. `"a finished tour never starts again"` — `settings.taught = 1`; ×3 ticks → `nil`
16. `"three unfinished starts is enough"` — `taughtTries = 3`; tick; `settings.taught` → `1`

**Walking it**
17. `"start moves to the drag step"` — `chip(w,"start")`; `stepName()` → `"drag"`
18. `"every card is under the stamp collision width"` — for all cards, `#title <= 26` → `true`
19. `"every card carries a step counter"` — every card's `stamp` matches `"%d of 6"` → `true`
20. `"a real drag satisfies step two"` — at `hello`, `teach:saw("dragged")`; → `"click"`
21. `"and says so"` — the new note's first line → `"(you'd already done that one)"`
22. `"opening the panel early jumps to step four"` — at `hello`, `saw("menu.open")`; → `"board"`
23. `"step four puts rows in the menu"` — `#teach:menuRows()` → `3`
24. `"no rows at any other step"` — at `signals`, `#teach:menuRows()` → `0`
25. `"the carry-on row advances"` — `menuRows()[1].act()`; → `"signals"`
26. `"the stop row ends it"` — `menuRows()[2].act()`; `teach:stepName()` → `nil`
27. `"show-me-one posts a sample and stays put"` — `chip(w,"show me one")`; `stepName()` → `"signals"`, `#w.notes` → `2`
28. `"the sample never touches the ledger"` — the sample note has no `session_id` field and `handle` was never called (harness has no `handle`) → structural
29. `"finish ends the tour"` — at `quiet`, `chip(w,"finish")`; `stepName()` → `nil`
30. `"finishing is persisted"` — `settings.taught` → `Teach.VERSION`
31. `"and a farewell is left behind"` — `last(w).title` → `"that's the lot"`

**Ending and interruption**
32. `"the cross ends it"` — `last(w).onGone(nil,"cross")`; `settings.taught` → `1`
33. `"eviction only parks it"` — `onGone(nil,"evicted")`; `settings.taught` → `0`
34. `"and it comes back on the next tick"` — `tick()`; `#w.notes` → `1`
35. `"it will not come back over a question"` — `w.waiting = 1`; evict; tick; `#w.notes` → `0`
36. `"nor while presenting"` — `w.mayShow = false`; evict; tick; `#w.notes` → `0`
37. `"two timeouts is enough"` — `onGone(nil,"expired")` ×2; `settings.taught` → `1`
38. `"a question pulls it off screen"` — `teach:standDown()`; `#w.notes` → `0`, `stepName()` unchanged
39. `"a closed panel is noticed"` — at `board`, `w.menuOpen = false`; `tick()`; `last(w).title` → `"still on step 4"`
40. `"and re-opening restores step four"` — `chip(w,"open the panel")`; `last(w).title` → `"this is the panel"`
41. `"the menu re-run works after it's over"` — `stop`, then `teach:begin(true)`; `stepName()` → `"hello"`
42. `"a manual re-run spends no try"` — `settings.taughtTries` unchanged
43. `"onGone is only ever called once"` — a counter incremented in `onGone`; drop twice → `1`

**Shape**
44. `"every card has a title, body and stamp"` — loop `Teach.cards`
45. `"every chip has a label and an act"` — loop
46. `"every step in order has a card"` — loop `Teach.order`
47. `"every card's step is a real step"` — loop cards, check membership in `Teach.order`

CI needs no change: `luac5.4 -p` picks up `teach.lua` from the `hammerspoon/foxbot/*.lua`
glob, and the network / AppleScript greps still pass (the module makes no calls
of either kind).

### 9.2 Resetting for repeated manual testing

**The tour only, keeping everything else** — Hammerspoon Console (hammer icon →
Console; in-process, so no AppleScript bridge and no permission):

```lua
foxbot.forgetTutorial()   -- clears taught + taughtTries and runs it now
```

**A genuine first run**, including forgetting his position:

```lua
hs.settings.clear("foxbot.settings")
hs.reload()
```

or from a shell:

```bash
defaults delete org.hammerspoon.Hammerspoon foxbot.settings
osascript -e 'quit app "Hammerspoon"'; open -a Hammerspoon   # or just relaunch it
```

**Inspecting state mid-tour**, Console:

```lua
foxbot.state().teaching      -- "hello" | "drag" | … | "off"
hs.settings.get("foxbot.settings").taughtTries
```

### 9.3 Manual QA script (twelve minutes)

1. `hs.settings.clear("foxbot.settings")`, reload. Fox appears right-edge centre;
   ~6 s later card 1 appears to his left at 440 px wide. **No sound.**
2. Click the bubble body (not a chip) → card 2. Body click == first chip.
3. Drag him to the left edge → card 3, with `(you'd already done that one)`.
   Bubble flips to his right side automatically.
4. Press ⌃⌥⌘T → card 4 appears, panel opens, orange `Tour · carry on` at the top.
5. Click the grey background instead → within 3 s, `still on step 4`.
6. `open the panel` → `this is the panel` again, rows intact.
7. `Tour · carry on` → card 5. `show me one` → a payments-api note appears above,
   card 5 re-posts below it, step counter still `5 of 6`.
8. `finish` on card 6 → `that's the lot`, gone in 12 s.
9. Reload Hammerspoon → **no tour**.
10. Panel → `Show me around again` → card 1 back.
11. Press ✕ → gone. Reload → still gone.
12. `foxbot.forgetTutorial()`, then at card 3 send a real Claude Code prompt →
    the tour bubble stays; when the turn asks a question, the tour bubble
    vanishes and the question is alone; answer it, wait 3 s → the tour card
    comes back at step 3.
13. `foxbot.forgetTutorial()`, then quit Hammerspoon at card 2 three times in a
    row → on the fourth launch nothing appears, and
    `hs.settings.get("foxbot.settings").taught` is `1`.
14. Start a Zoom call, then `hs.settings.clear(…)` + reload → no tour while the
    meeting window is up; end the call → the tour starts within 3 s.


## Settings

- taught = 0  (number; the Teach.VERSION the user has seen the tour through to an ending. 0 means never. Read ONLY as `(settings.taught or 0) >= Teach.VERSION` — 0 is truthy in Lua.)
- taughtTries = 0  (number; auto-starts that never reached an ending. Incremented at the moment the tour actually begins, never when eligibility is merely checked. At Teach.MAX_STARTS = 3 the tour marks itself done and stops offering.)

## Risks

- home() is ALREADY too tall for small screens: summing Menu's H table over the current 29 rows gives 903 px, and hs.screen frame height on a 1440x900 Air is ~875. The permanent 'Show me around again' row (+47 with its note) pushes it to 950, and step 4's injected block adds a further 90 transiently. Menu:open and Menu:fill clamp only the y origin, never the height, so the bottom rows (Reload / Quit foxbot) fall off the screen. Fix, one line in both: self.height = math.min(measure(rows), screen.h - 16). Worth doing in the same change; the tutorial makes an existing bug visible rather than causing it.
- Panel:drop gains a second argument. Every existing call site must be updated to pass its reason (expiry, eviction, clear, mouseDown). A missed one silently passes nil, which Teach:gone treats as 'gone' -> yields and retries. Harmless, but a missed 'cross' would mean the X no longer ends the tour — cover it with test 32.
- note.onGone re-entrancy: a callback that posts another note while inside Panel:drop would mutate self.notes mid-iteration. Mitigated by clearing note.onGone before invoking it and by dropping from the list before the call; test 43 pins it.
- The step-4 card is posted from inside M.openMenu, before board:open. If that ordering is ever reversed, home() is built while the step is still 'click', menuRows() returns {}, and the user is told to click an orange row that does not exist. Needs a comment at the call site and is caught by test 22 only if the test drives openMenu rather than saw() directly — drive openMenu.
- Card copy hard-codes product facts that live elsewhere: '?2' (M.paintBar), '1m, 5m, 15m' (Sessions.NUDGE_AFTER), 'one per 2 minutes, four a turn' (GAP/BUDGET in hooks/foxbot.sh), 'ctrl-opt-cmd-T / F' (TOGGLE_KEY/REPORT_KEY). Any of these changing makes the tutorial lie. Add a comment above Teach.cards listing the four sources.
- Titles longer than 26 characters collide with the right-aligned stamp box (which starts at x=296 in a 440px note); nothing errors, the text just overlaps. Test 18 asserts the bound.
- A user whose machine is permanently busy (a long-running session at every launch) never sees the tour and never spends a try — correct, but it means the tour can first appear weeks after install, which will read as a bug in an issue report. Mention it in the README.
- Teach:sample() duplicates the shape of a real finished-turn note. If the real note layout changes (extra field, different stamp format) the sample drifts and starts teaching something untrue. Keep sample() directly above announce() in review checklists, or build both through one helper later.
- MAX_EXPIRY = 2 means a user who starts the tour and then leaves the machine for 20 minutes without locking it (so Away never trips) comes back to a tour that has marked itself done. Defensible, but it is the one path where the tour ends without the user acting.