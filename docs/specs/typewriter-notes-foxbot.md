# Typewriter notes (foxbot)

# Typewriter reveal for panel notes

## 0. The one idea that makes it flawless

**Never render a prefix. Always render the whole string, and make the unrevealed tail transparent.**

`measureNote` keeps measuring the full text, exactly as today. Every frame draws the *same complete string* into the *same frame it was measured for*, with a `color = {…, alpha = 0}` attribute applied to the characters past the cursor. Consequences, all of them load-bearing:

- **The note cannot resize.** `plan.width`, `plan.height`, every `frame` is computed once from full text at `say()` time and never touched again. Zero new geometry.
- **Revealed text cannot reflow.** With a prefix render, greedy word-wrap moves the partially-typed word: `"the quick brown fo"` fits on line 1, `"the quick brown foxes"` does not, so `fo…` visibly jumps down a line mid-word. With a whole-string render, line breaks are decided on frame 1 and every glyph fades in at its final position. This is the entire reason for the alpha trick — word-granular reveal also avoids the jump but reads chunky, and space-padding does not avoid it at all.
- **Nothing below the note moves.** The stack column, the eviction-by-height loop, `self.spots` hit rects and `Panel:place` all operate on full-size plans from frame 1.

Cost: the bubble is at its final size with empty space below it while it fills in. That is the correct, standard look, and it is the only jitter-free option.

---

## 1. New module: `hammerspoon/foxbot/typing.lua`

Pure arithmetic on strings. **Requires nothing** — no `hs`, no `Palette`. 100% unit-testable under bare `lua`.

```lua
Typing.CPS   = 45     -- characters per second, natural rate
Typing.MAX   = 3.5    -- seconds; hard ceiling for any one note
Typing.SHARE = 0.25   -- …and never more than this fraction of the note's own linger
Typing.GAP   = 6      -- cost units of silence between pieces (133ms at CPS)
```

### 1.1 Cost table

Reveal speed is expressed as a **cost in character-equivalents** per character, so punctuation pauses are one monotone number line instead of a second timing system.

| character | cost | pause added at 45cps |
|---|---|---|
| `.` `!` `?` **when closing** | 9 | +178 ms |
| `,` `;` `:` | 4 | +67 ms |
| `—` (U+2014), `–` (U+2013) | 4 | +67 ms |
| `\n` | 12 | +244 ms |
| everything else | 1 | — |

**"Closing"** means: after the `.`/`!`/`?`, skipping any run of `”` `’` `"` `'` `)` `]`, the next character is a space, a newline, or end-of-string. So `finished.”` pauses, `3.5` and `e.g.` do not.

### 1.2 UTF-8 (mandatory — hints and lines contain `·` `“ ” — `)

All counting is in **characters**, all slicing is on **byte offsets that are guaranteed to sit on a character boundary**. Revealing half a multi-byte sequence paints a mojibake glyph for a frame.

Iterate with the 5.1-through-5.5-safe pattern (do **not** depend on `utf8`, the test runner may be older than Hammerspoon's Lua):

```lua
for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do … end
```

and record `offsets[i]` = byte index of the **last byte** of character *i*. "Reveal *i* characters" = "bytes 1 .. offsets[i] are visible".

### 1.3 API

```lua
--- Per-character reveal cost of one string.
--- @return chars   number          how many characters (not bytes)
--- @return offsets table<int,int>  offsets[i] = last byte index of character i
--- @return costs   table<int,int>  costs[i] = cumulative cost after i characters
function Typing.costs(text)

--- Build the reveal plan for one note.
--- @param pieces table  ordered array of { what = "body"|"line", at = int|nil, text = string }
--- @param hold   number the note's linger in seconds (Palette.linger / lingerStep / lingerLong)
--- @return plan|nil     nil when there is nothing to type
function Typing.plan(pieces, hold)

--- Seconds this note is allowed to take.
--- @return number  math.min(Typing.MAX, hold * Typing.SHARE)
function Typing.ceiling(hold)

--- How much of each slot is visible.
--- @param elapsed number seconds since typing began
--- @return revealed table<int,int>  slot index -> characters visible
--- @return done     boolean
function Typing.at(plan, elapsed)

--- Everything, for the skip path.
--- @return revealed table<int,int>
function Typing.whole(plan)
```

`plan` shape:

```lua
{
  slots = {
    { what = "body", at = nil, text = "…",
      chars = 42, offsets = {…}, costs = {…},
      cost = 58,        -- costs[chars]
      begin = 0 },      -- cumulative cost of everything before this slot
    { what = "line", at = 1, text = "·  …", …, begin = 64 },  -- 58 + GAP
    …
  },
  total   = 224,        -- cost units, gaps included
  cps     = 64.0,       -- effective, after the ceiling squeeze
  seconds = 3.5,        -- total / cps
  shown   = {},         -- slot -> characters last painted   (owned by Panel)
  began   = 0,          -- absolute seconds                  (owned by Panel)
}
```

### 1.4 The squeeze — this is what stops a long note vanishing mid-sentence

```lua
local ceiling = Typing.ceiling(hold)               -- min(3.5, hold * 0.25)
plan.cps = math.max(Typing.CPS, plan.total / ceiling)
plan.seconds = plan.total / plan.cps
```

Short notes run at the natural 45cps. Long notes speed up so the whole note always lands inside the ceiling. The ceiling is tied to the note's own linger, so an ambient progress note (`lingerStep = 7`) gets 1.75s and a normal turn note (`linger = 12`) gets 3.0s — no new setting, and importance and animation budget stay in proportion automatically.

Worked numbers:

| note | cost | effective cps | seconds |
|---|---|---|---|
| `"payments-api finished."` (hold 12) | 30 | 45 | **0.67** |
| brief `done`, body + 3 bullets (hold 12) | ~224 | 64 | **3.00** (ceiling) |
| `M.demoLines()`, 6 long bullets (hold 12) | ~470 | 157 | **3.00** (ceiling) |
| ambient step, hint + 2 lines (hold 7) | ~150 | 86 | **1.75** (ceiling) |

157cps is still ~9 words/sec — unmistakably progressive, not a pop.

### 1.5 `Typing.at` implementation note

Per slot, binary-search `slot.costs` for the largest `i` with `costs[i] <= budget`, where `budget = elapsed * plan.cps - slot.begin`. Clamp: `budget <= 0` → 0, `budget >= slot.cost` → `slot.chars`. **Stateless** — no cursor to fall out of sync, safe to call from anywhere, and per-frame cost is `O(#slots · log chars)` regardless of note length.

`done` is `elapsed * plan.cps >= plan.total`.

---

## 2. `panel.lua` — exact changes

### Change 1 — requires and constants (top of file)

```lua
local Palette = require("foxbot.palette")
local Typing  = require("foxbot.typing")            -- NEW

local TYPE_FPS   = 24     -- the typer's tick; 1.9 chars/frame at the natural rate
local TYPE_STACK = 3      -- don't animate into a crowd
```

Monotonic clock helper (immune to NTP steps, unlike `secondsSinceEpoch`):

```lua
local function now() return hs.timer.absoluteTime() / 1e9 end
```

### Change 2 — `veiled()`, next to `styled()`

```lua
--- The whole string, laid out in full, with everything past `chars` made
--- invisible. Drawing the complete text every frame is the point: the line
--- breaks are settled on the first frame, so a word that has appeared never
--- moves again. A prefix render reflows the half-typed word onto the next line
--- and back, which is the jitter this exists to avoid.
---
--- Falls back to a prefix render if styledtext refuses the range — a slightly
--- jumpy typewriter beats an error taking the whole panel down.
local function veiled(slot, chars, size, colour)
  local whole = styled(slot.text, size, colour)
  if chars >= slot.chars then return whole end

  local from
  if chars > 0 then from = slot.offsets[chars] + 1 else from = 1 end

  local clear = { red = colour.red, green = colour.green,
                  blue = colour.blue, alpha = 0 }
  local ok, veil = pcall(function()
    return whole:setStyle({ color = clear }, from, #slot.text)
  end)
  if ok and veil then return veil end
  return styled(slot.text:sub(1, from - 1), size, colour)
end
```

`from` is spelled out with `if/else`, not `chars > 0 and slot.offsets[chars] or 0` — house rule.

### Change 3 — `measureNote` emits **one** ordered list of drawable/typable pieces

`plan.lines` and `plan.bodyH` are replaced by `plan.pieces`. This is the schema-driven rule applied to layout: the render loop and `Typing.plan` read the *same array*, so the drawn order and the reveal order cannot drift.

```lua
  plan.pieces = {}
  local function piece(what, at, text, x, y, w, h, tone)
    plan.pieces[#plan.pieces + 1] =
      { what = what, at = at, text = text,
        x = x, y = y, w = w, h = h, size = Palette.body, tone = tone }
  end

  local titleW, titleH = measure(note.title or "", Palette.head, inner - CROSS.shift)
  plan.titleH = titleH

  local bodyH = 0
  if note.body and note.body ~= "" then
    local bodyW
    bodyW, bodyH = measure(note.body, Palette.body, inner)
    plan.bodyW = bodyW
    piece("body", nil, note.body,
          Palette.pad, Palette.pad + titleH + 5, inner, bodyH, "faded")
  end

  local y = Palette.pad + titleH + 5 + bodyH + 6

  for index, line in ipairs(note.lines or {}) do
    local text = "·  " .. line
    local _, h = measure(text, Palette.body, inner)
    piece("line", index, text, Palette.pad, y, inner, h, "ink")
    y = y + h + 4
  end
  if #(note.lines or {}) > 0 then y = y + 4 end
```

Everything else in `measureNote` (chips, narrow-note shrink, `plan.height = y + Palette.pad - 4`) is unchanged. The narrow-shrink line uses `plan.bodyW` (0 when there is no body) instead of the old local.

Geometry is **byte-identical to today**: note width 340 / 440, `inner = width - 28`, title at `x = 29, y = 14`, body at `x = 14, y = 14 + titleH + 5`, lines stacked `+h+4` then `+4`, chips `h = 26 / gap 6`, height `y + 10`.

### Change 4 — `add()` returns its index

```lua
  local function add(e) elements[#elements + 1] = e return #elements end
```

### Change 5 — the render loop draws body+lines from `plan.pieces`

Replace the body `add({...})` block **and** the `for _, line in ipairs(plan.lines)` block with one loop:

```lua
    note.slots = {}
    for index, part in ipairs(plan.pieces) do
      local colour = (part.tone == "ink") and colours.ink or colours.faded
      local text
      if note.type then
        text = veiled(note.type.slots[index], note.type.shown[index] or 0,
                      part.size, colour)
      else
        text = styled(part.text, part.size, colour)
      end
      note.slots[index] = add({
        type = "text", text = text,
        frame = { x = left + part.x, y = top + part.y, w = part.w, h = part.h },
      })
    end
```

`plan.pieces[i]` and `note.type.slots[i]` are index-aligned by construction — `Typing.plan` is handed `plan.pieces` verbatim.

Render is **idempotent with respect to typing**: it draws whatever `shown` currently says. Hover re-renders, anchor moves and screen changes therefore cannot restart, freeze or skip an animation. `render()` may draw one frame (≤42 ms) stale; imperceptible.

### Change 6 — the typer

```lua
--- The one note currently typing, if any.
function Panel:typingNote()
  for _, note in ipairs(self.notes) do
    if note.type then return note end
  end
  return nil
end

--- Should this note type at all?
function Panel:shouldType(note)
  if note.instant == true then return false end
  if self.typing == false then return false end
  if #self.notes > TYPE_STACK then return false end
  return true
end

--- The switch, told to the panel rather than read from settings — the panel is
--- a view and does not know about settings. Turning it off mid-animation
--- completes the note rather than freezing it half-written.
function Panel:types(on)
  self.typing = (on ~= false)
  if not self.typing then
    local note = self:typingNote()
    if note then self:finishTyping(note) end
  end
end

--- @return boolean  false when there was nothing to type
function Panel:startTyping(note)
  local plan = Typing.plan(note.plan.pieces, note.hold or Palette.linger)
  if not plan then return false end

  plan.began = now()
  plan.shown = {}
  note.type = plan
  note.typed = false

  if not self.typer then
    self.typer = hs.timer.doEvery(1 / TYPE_FPS, function() self:tick() end)
  end
  return true
end

function Panel:tick()
  local note = self:typingNote()
  if not note or not self.canvas then self:stopTyper() return end

  local revealed, done = Typing.at(note.type, now() - note.type.began)
  self:paintTyping(note, revealed)
  if done then self:finishTyping(note) end
end

--- Write only the slots whose visible character count actually changed. Reveal
--- is sequential, so in the steady state this is exactly one element per frame.
function Panel:paintTyping(note, revealed)
  if not self.canvas or not note.slots or not note.type then return end
  local colours = Palette.colours()

  for index, chars in ipairs(revealed) do
    if note.type.shown[index] ~= chars then
      note.type.shown[index] = chars
      local element = note.slots[index]
      local part = note.plan.pieces[index]
      if element and part then
        local colour = (part.tone == "ink") and colours.ink or colours.faded
        self.canvas[element].text =
          veiled(note.type.slots[index], chars, part.size, colour)
      end
    end
  end
end

function Panel:finishTyping(note)
  if not note.type then return end
  self:paintTyping(note, Typing.whole(note.type))
  note.type = nil
  note.typed = true
  self:stopTyper()
  self:arm(note)
end

function Panel:stopTyper()
  if self:typingNote() then return end
  if self.typer then self.typer:stop() self.typer = nil end
end
```

Colours are looked up **fresh** in `paintTyping`, never cached on the slot, so a skin change can never leave half a note in the old palette.

### Change 7 — `arm()`: the only place `expires` is ever created

```lua
--- Start the note's clock. A note that is still typing has not been read yet,
--- so its life begins when the last character lands, not when the bubble
--- appeared. Created in exactly one place so the two paths cannot drift.
function Panel:arm(note)
  if note.expires then note.expires:stop() end
  note.expires = hs.timer.doAfter(note.hold or Palette.linger, function()
    self:dismiss(note)
  end)
end
```

### Change 8 — `Panel:say`

```lua
function Panel:say(note)
  note.plan = measureNote(note)

  -- One at a time. Two bubbles typing over each other is unreadable, and the
  -- older one is the one you had already started reading — it snaps to full
  -- and gets a fresh linger rather than being raced.
  local busy = self:typingNote()
  if busy then self:finishTyping(busy) end

  self.notes[#self.notes + 1] = note

  --- …eviction-by-height loop unchanged…

  if self:shouldType(note) and self:startTyping(note) then
    -- typing; arm() runs when the last character lands
  else
    note.typed = true
    self:arm(note)
  end

  self:render()
  return note
end
```

`startTyping` must run **before** `render`, because render reads `note.type`. `note.slots` is filled by `render` and only consumed later by `tick`, so there is no ordering hazard — `render` and `tick` are both on the main Lua thread and never interleave.

### Change 9 — `drop` / `teardown`

```lua
function Panel:drop(note)
  --- …existing removal…
  if note.expires then note.expires:stop() note.expires = nil end
  note.type = nil                     -- NEW
  self:stopTyper()                    -- NEW
  if self.hot and self.hot.note == note then self.hot = nil end
end
```

`teardown()` gains `self:stopTyper()` before hiding the canvas. `clear()` needs nothing — it goes through `drop`.

### Change 10 — click to skip

```lua
    if event == "mouseDown" then
      if not found then return end
      local note = found.note

      -- A click on a note that is still typing means "show me the rest", not
      -- "throw it away": you reacted to a bubble appearing, you have not read
      -- it. Destroying unread content on that click is the exact failure this
      -- product exists to avoid. The cross and the chips are deliberate aims
      -- at small targets and still act at once.
      if note.type and not found.cross and not found.act then
        self:finishTyping(note)
        return
      end

      self:dismiss(note)
      if found.act then
        found.act()
      elseif not found.cross and note.onOpen then
        note.onOpen()
      end
      return
    end
```

`found.cross` is a real boolean (can be `false`), `found.act` is a function or nil — both tested with `not`, no `and`/`or` collapse. Hovering does **not** skip; only a click.

### Change 11 — header comment

Extend the note shape doc:

```lua
--- { title, body, lines = {...}, stamp, chips = {{label, act}}, hold, onOpen,
---   instant }   -- instant = true skips the typewriter entirely
```

---

## 3. `settings.lua` — one line

Add to `SCHEMA`, in the appearance group next to `detail`:

```lua
  typing      = true,        -- reveal note text letter by letter
```

Nothing else. `KEYS` is derived; there is no second list.

---

## 4. `init.lua` — four small edits

**(a) Menu row.** In `home()`, Appearance block, immediately after the `Detail` row:

```lua
    { kind = "toggle", title = "Type notes out", on = settings.typing,
      note = "letter by letter · never more than 3½ seconds",
      act = function()
        Settings.toggle(settings, "typing")
        panel:types(settings.typing)
        M.demoLines()
      end },
```

Demoing on change matches `voicePage` / `detailPage`.

**(b) Wire it at start.** In `start()`, right after `panel = Panel.new()`:

```lua
  panel:types(settings.typing)
```

**(c) Two callers opt out.** Add `instant = true` to:

- `catchUp()`'s `panel:say{...}` — **required**: you have been away, the digest is the point, it must be on screen whole. It also carries `hold = Palette.lingerLong` and up to 6 lines, i.e. the longest note the fox ever draws.
- `chase()`'s `panel:say{...}` — a nudge about something already overdue. Typing "you are still blocked" out slowly is the definition of annoying.

`announce()` and `ambient()` are untouched, so ordinary notes type.

**(d) `M.state()`** gains one field, for the CLI and tests:

```lua
    typing = panel:typingNote() ~= nil,
```

---

## 5. Decisions, stated

| question | answer | why |
|---|---|---|
| Does the **title** type? | **No.** Instant. | The title is the session name — which project this is. That is exactly the fact you want at a glance; making the bubble anonymous for 400 ms is backwards. Same reason a chat app shows the sender immediately. |
| The **stamp** (`4m 12s · 37.0k`)? | **No.** Instant. | Metadata, top-right, not prose. |
| The **✕**, the card, the border? | Instant. | Chrome. |
| The **chips**? | **No.** Instant, at full strength, clickable throughout. | They are affordances, not content. A half-typed note whose `terminal` button you can already hit is strictly better than one you have to wait for. Also keeps element bookkeeping to text slots only. |
| **Reveal order** | body → line 1 → line 2 → … → line N | Matches reading order and the drawn order, because both come from `plan.pieces`. A body containing `"\n“hint”"` gets the newline's 12-unit pause for free, so it already reads line-by-line before the bullets start. |
| Gap **between** pieces | `Typing.GAP = 6` cost units (133 ms at natural rate, scales with the squeeze) | This is what makes it read "line by line" rather than as one long stream. |
| **Multiple notes typing** | Never. Exactly one, always the newest. A new note snaps the older one to full and re-arms its linger. | Two animating bubbles are unreadable, and in a burst you want the newest animated and everything else already complete. |
| **Stack limit** | No typing when the note would be the 4th or later on screen (`TYPE_STACK = 3`) | Three bubbles up means you are behind. Catch up instantly. |
| **Dismiss timer** | Created only in `arm()`, called from `finishTyping()` on the typing path and from `say()` on the instant path. | Single creation site = the "vanishes mid-sentence" bug is structurally impossible, not merely fixed. |
| Total dwell | `type_time + linger`, bounded at `1.25 × linger` and `linger + 3.5s` | Typing time is capped at 25% of the note's own linger. A `done` note goes from 12s to at most 15s; an ambient step note from 7s to at most 8.75s. |
| Click mid-type | First click completes; second click behaves normally. ✕ and chips always act at once. | The visual-novel / chat-UI convention, and it never destroys unread content. |
| Hover mid-type | No effect on typing. | Less state, no benefit. |

---

## 6. Redraw strategy — why this is cheap

| | today | with typing |
|---|---|---|
| at rest | 0 timers in `Panel` | **0 timers** — the typer only exists while a note is typing, and `stopTyper()` kills it the frame the last note finishes |
| per animation frame | n/a | **1** `Typing.at` (binary searches) + **1** `styledtext` build + **1** `canvas[i].text = …` assignment |
| `replaceElements` calls | on every change | **unchanged** — the typer never calls `render()` |

The five mechanisms that get it there:

1. **One timer for the whole panel**, at 24 Hz, created lazily and destroyed eagerly. (`sprite.lua` already runs a 30 Hz canvas timer, so this is well inside the machine's existing budget.)
2. **`render()` is never called from the typer.** Per-element mutation via `self.canvas[i].text`, the same pattern `sprite.lua` uses for `canvas[1].image` and `canvas[2].fillColor`.
3. **Only dirty slots are written.** `note.type.shown[i]` gates the assignment. Reveal is sequential, so at most one slot changes per frame; finished and not-yet-started slots are written once at their transition and then skipped.
4. **Only one note types**, so the worst case is 1 element per frame, not `#notes × #slots`.
5. **The cut is derived from a monotonic clock**, `elapsed * cps`, never accumulated per tick. Hammerspoon timers are not real-time; a dropped or late tick must not slow the animation or desync it. It also means a `render()` triggered by hover mid-frame draws a consistent state.

---

## 7. Constraint audit

1. **No macOS permissions.** Uses `hs.timer.doEvery`, `hs.timer.absoluteTime`, `hs.canvas` element assignment, `hs.styledtext:setStyle`. No `eventtap:start`, no Accessibility, no Screen Recording, no Automation.
2. **No network.** Pure local string arithmetic.
3. **AppleScript bridge** untouched.
4. **Anti-annoyance.** Creates no new interruption — it never causes a note that was not already going to appear, and adds no sound. It sits *downstream* of every existing gate: `Hush.check` (quiet hours, presenting), `sessions:isWaiting()`, `away:isAway()`, per-project mute, the 2-min / 4-per-turn ambient limiter. Extra dwell is bounded at 25% of the note's own linger. The away digest and the overdue nudge never type. Never more than one note animates, never into a stack of more than three, and one switch turns it off.
5. **Schema-driven settings.** Exactly one new `SCHEMA` entry (`typing = true`). No second list.
6. **Lua falsy traps.** Every branch whose value can be `false` or `nil` is spelled out with `if/else`: `veiled`'s `from`, `Panel:types`'s `(on ~= false)`, `shouldType`'s three guards, `startTyping`'s boolean return consumed by `if … and … then/else`, and the mouseDown skip test (`found.cross` can legitimately be `false`).
7. **Unit-testable.** `typing.lua` requires nothing and is fully testable as-is. `panel.lua`'s state machine is testable with a modest stub addition (§8).

---

## 8. Tests

### 8.1 `tests/support.lua` — stub additions

```lua
-- monotonic clock, drivable
local clock = 0
_G.hs.timer.absoluteTime = function() return clock * 1e9 end
function support.setClock(seconds) clock = seconds end

-- timers you can fire by hand
_G.hs.timer.doAfter = function(after, fn)
  local h = { after = after, fn = fn, live = true }
  h.stop = function(self) self.live = false end
  support.pending[#support.pending + 1] = h
  return h
end
_G.hs.timer.doEvery = function(every, fn)
  local h = { every = every, fn = fn, live = true }
  h.stop = function(self) self.live = false end
  support.ticker = h
  return h
end
function support.tick(n)            -- run the repeating timer n times
  for _ = 1, (n or 1) do
    if support.ticker and support.ticker.live then support.ticker.fn() end
  end
end

-- styledtext: carry the text and the veil range so assertions can read them
_G.hs.styledtext = {
  new = function(text) return { text = text, veil = nil,
    setStyle = function(self, _, from, to)
      return { text = self.text, veil = { from = from, to = to } }
    end } end,
}
_G.hs.drawing = { getTextDrawingSize = function(s, box)
  local n = #(type(s) == "table" and s.text or s)
  return { w = box.w, h = 16 * math.max(1, math.ceil(n / 40)) }
end }

-- canvas: record element assignments
_G.hs.canvas = {
  windowLevels = { floating = 1 },
  windowBehaviors = { canJoinAllSpaces = 1, stationary = 2 },
  new = function(frame)
    local c = { frame_ = frame, els = {} }
    setmetatable(c, { __index = function(t, k)
      if type(k) == "number" then t.els[k] = t.els[k] or {} return t.els[k] end
      return rawget(t, k) end })
    function c:level() end        function c:behavior() end
    function c:clickActivating() end
    function c:canvasMouseEvents() end
    function c:mouseCallback(fn) self.onMouse = fn end
    function c:show() end          function c:hide() end
    function c:delete() end        function c:frame(f) self.frame_ = f end
    function c:replaceElements(...) self.els = { ... } end
    return c
  end,
}
_G.hs.screen = { mainScreen = function()
  return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end,
  allScreens = function() return {} end }
```

### 8.2 `tests/run.lua` — new blocks

**`Typing` (pure, ~24 checks)**

- `costs("abc")` → chars 3, total 3
- `costs("hi.")` → total 11 (2 + 9, closing at end of string)
- `costs("hi. there")` → 8 plain + 9 = 17
- `costs("3.5 apples")` → the `.` is **not** closing, total 10
- `costs("e.g. x")` → first `.` costs 1, second costs 9 → total 14
- `costs('done.”')` → the `.` **is** closing through the quote → 5 + 9 = 14
- `costs("a, b; c: d")` → three 4s
- `costs("a\nb")` → 14
- `costs("·  a")` → 4 characters, **not** 6 bytes  ← the UTF-8 guard
- `costs("—")` → chars 1, offsets[1] == 3, total 4  ← multi-byte offset lands on a boundary
- `costs("“x”")` → offsets strictly increasing, offsets[3] == #text
- `plan(pieces, 12).cps == 45` for a short note; `.seconds < 3`
- `plan(pieces, 12).seconds == 3.0` for a 224-cost note (ceiling)
- `plan(pieces, 7).seconds == 1.75` (ceiling tracks the shorter linger)
- `plan(pieces, 30).seconds == 3.5` (`MAX` still caps it)
- `plan({}, 12)` → nil
- `plan({{what="body",text=""}}, 12)` → nil
- `at(plan, 0)` → all zeros, done false
- `at(plan, plan.seconds)` → done true, every slot at `chars`
- `at(plan, plan.seconds * 10)` → identical to `whole(plan)` (clamped, no overrun)
- monotonic: for `t` in 0..seconds step 0.02, no slot's count ever decreases
- slot 2 stays at 0 until `elapsed >= (slot2.begin) / cps` (the GAP is respected)
- `whole(plan)[i] == plan.slots[i].chars` for all i

**`Panel` (with the stub canvas, ~14 checks)**

- a typing note has **no** `expires` while typing (`support.pending` gains nothing)
- after `support.tick()` past `plan.seconds`, `note.typed == true` and `expires` exists exactly once
- `note.hold` is honoured: `expires.after == 7` for an ambient note
- a second `say()` snaps the first: `notes[1].type == nil`, `notes[1].expires` exists
- `instant = true` → never types, `expires` armed inside `say()`
- `types(false)` mid-animation → `typingNote() == nil`, note complete, armed
- `shouldType` false when the note would be the 4th
- mouseDown on the body of a typing note → still in `self.notes`, `type == nil`
- mouseDown on the ✕ (localX ≤ 26, localY ≤ 26) of a typing note → removed from `self.notes`
- mouseDown on a chip of a typing note → `act` fired, note removed
- `drop()` mid-type stops the ticker (`support.ticker.live == false`)
- geometry is stable: capture `note.plan.height` at `say()`, tick to completion, assert unchanged
- `render()` mid-type does not reset `note.type.began`
- the veil range: at 3 characters of a 10-char slot, the element's `text.veil.from == offsets[3] + 1`

Target: **187 → ~225 unit tests**, `tests/hook.sh` unchanged (no hook-side change).

---

## 9. README

Under the interruption/appearance list: *"**Type notes out** — notes write themselves in, letter by letter, with a beat between lines. Capped at 3.5 seconds and at a quarter of the note's own life, so nothing is ever still typing when it should be gone. The catch-up digest and overdue nudges appear whole. Click a note to skip to the end. Off with one switch."*


## Settings

- typing (boolean, default true) — hammerspoon/foxbot/settings.lua SCHEMA; reveal note body and bullet lines letter by letter. Surfaced as the menu row "Type notes out" under Appearance, immediately after "Detail". Panel is told via panel:types(settings.typing); it never reads Settings itself.

## Risks

- hs.styledtext:setStyle argument convention (1-based byte start + end vs start + length) is the single API assumption in the whole design. Mitigated by confining it to `veiled()` and wrapping it in pcall with a prefix-render fallback — a slightly jumpy typewriter instead of an error that takes the panel down. Verify against the live Hammerspoon build before merging.
- UTF-8: hints and bullet lines contain ·, “, ”, — . Slicing on a byte index mid-sequence paints a mojibake glyph for one frame. Handled by counting characters and storing per-character byte offsets (gmatch pattern, not the utf8 library, so the test runner's Lua version does not matter), but this is the most likely place for a subtle regression.
- A transparent tail still occupies its glyph advance — that IS the mechanism, but it also means the bubble is at full height with visible empty space below the text while it types. This is unavoidable given "must not resize", and is the standard look, but it will read as odd on a 6-bullet note for the first ~1 second.
- Total dwell grows: a done note goes from 12s to up to 15s on screen, an ambient step note from 7s to 8.75s. Bounded by the min(3.5s, hold * 0.25) ceiling, but it is a real increase in the fox's presence and is the one place this feature spends the anti-annoyance budget.
- Replacing plan.lines / plan.bodyH with plan.pieces touches the render loop, the narrow-note shrink calculation (which used bodyW) and anything else reading plan.lines. Grep confirms plan.lines is read only at panel.lua:169 and plan.bodyH only at :166, so the blast radius is small — but the pieces list is now load-bearing for BOTH drawing and reveal order, so a bug there desynchronises the animation from the layout.
- note.slots (slot index -> canvas element index) is written by render() and read by tick(). Safe only because both run on Hammerspoon's main Lua thread and never interleave. If any future change moves rendering off that thread or introduces a coroutine, tick() would write into stale element indices.
- The 24Hz typer is a second always-possible timer alongside sprite.lua's 30Hz animation loop. It is created lazily and stopped eagerly, so it costs nothing at rest — but stopTyper() must be reached on every exit path (finishTyping, drop, clear, teardown, types(false), tick with no canvas) or a timer leaks and burns CPU forever.
- Snapping an older note to full and re-arming its linger from that instant means a note can live noticeably longer than Palette.linger if notes arrive in a tight burst. Bounded by the eviction-by-height loop, but worth watching.
- Typing changes nothing about the hook bridge, the rate limiter or any gate — but it does make an interruption more visually salient for its first few seconds. If it reads as attention-grabbing in practice, the honest fix is lowering Typing.SHARE from 0.25, not adding another setting.