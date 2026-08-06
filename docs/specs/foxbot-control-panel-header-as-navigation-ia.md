# Foxbot control panel: header-as-navigation IA

> **Measured baseline.** The current `home()` (`init.lua:805-855`) is **29 entries, 903px tall**. `Menu:open`/`Menu:fill` clamp `y` to the screen but never shrink or scroll (`menu.lua:251-253, 291-292`), so on a 1440×900 Mac — usable frame ~859px — **"Reload" and "Quit foxbot" are drawn off the bottom edge and cannot be clicked.** The redesign below brings home to **9 entries, 280px** and caps every other page at 720px.

---

# 1. The top-level split (justification)

A user opens this panel for one of three reasons, in steeply descending order of frequency: **to see what's happening**, **to make it stop**, and **to change how it behaves**. So the *header becomes the navigation* — the status line and the stats strip are already the two answers to "what's running" and "how's my day", and making those two most-read rows tappable turns them into the two doors nobody has to hunt for, while the one control anybody reaches for in irritation (a single graded switch: **Everything → Silent → Paused**) sits directly beneath them. Everything else is configuration, which you only ever go looking for deliberately, so it lives behind exactly one door called **Settings** and is *flat* inside it — depth is what loses people, not length on a page you chose to open.

```
┌──────────────────────────────────┐
│ ● 2 sessions need you         ›  │   status  → Now        tap
│    blocked 4m 12s                │
│ ──────────────────────────────── │
│    17        2h 14m      184k  › │   stats   → The den    tap
│   TURNS      WORKED     TOKENS   │
│ ──────────────────────────────── │
│  ╭──────────────────────────────╮│
│  │ Everything │ Silent │ Paused ││   segment (3 targets)
│  ╰──────────────────────────────╯│
│        notes and sounds          │
│ ──────────────────────────────── │
│  Settings                     ›  │   into    → Settings
│ ──────────────────────────────── │
│  Hide foxbot            [⌃⌥⌘F]   │   row
└──────────────────────────────────┘
              280px
```

---

# 2. The home page — exact rows

`Pages:home()` returns exactly this. 9 entries, 5 interactive rows, 7 tap targets, **280px**.

| # | kind | title / content | value | note | target |
|---|---|---|---|---|---|
| 1 | `status` | `statusRow()` unchanged text + mood dot | — | existing `detail` | `page = function() return self:now() end` |
| 2 | `sep` | | | | |
| 3 | `stats` | turns · worked · tokens | — | — | `page = function() return self:den() end` |
| 4 | `sep` | | | | |
| 5 | `segment` | `Everything · Silent · Paused` | `on = Pages.level(settings, now)` | note of the **selected** option | `act = function(id) ctx.act.setLevel(id) end` |
| 6 | `sep` | | | | |
| 7 | `into` | `Settings` | `nil` | — | `page = function() return self:settings() end` |
| 8 | `sep` | | | | |
| 9 | `row` | `Hide foxbot` / `Show foxbot` | — | — | `keys = "⌃⌥⌘F"`, `act = ctx.act.toggleFox` |

**Segment option notes (always shown, they are the row's self-description):**

| id | label | note |
|---|---|---|
| `everything` | `Everything` | `notes and sounds` |
| `silent` | `Silent` | `notes still show, no sound` |
| `paused` | `Paused` | `quiet until 14:32 · tap again for longer` |

**Row 6 is the reserved timer slot.** When the focus timer ships it is inserted at index 6 as a plain `row` — home becomes 10 entries / **312px** and *nothing else moves*. See §7.

Wiring in `init.lua`:

```lua
local pages = Pages.new(ctx)
function M.openMenu(at)
  if panel then panel:anchorTo(fox:frame(), fox:screen()) end
  if board:isOpen() then board:close() return end
  board:open(pages:home(), at or hs.mouse.absolutePosition(), fox:screen())
  board:showing(function() return pages:home() end)
end
```

---

# 3. Every sub-page, exact row lists

Depth is measured from home. Max depth is **3**, and only two leaves reach it.

### 3.1 `Pages:now()` — depth 1 (from the status row) — 237px empty, 669px worst case

| # | kind | content |
|---|---|---|
| 1 | `status` | same header, **no `page`** (you are here) |
| 2 | `sep` | |
| — | *if `sessions:blocked()` is non-empty:* | |
| 3 | `label` | `Waiting on you` |
| 4…n | `row` | `row.session`, `tone = "asking"`, `value = Sessions.duration(row.elapsed)`, `note = (row.hint ~= "" and row.hint) or nil`, `act = focusTerminal(row.tty, row.app)` — **cap 5** (`Pages.CAP.blocked`) |
| n+1 | `sep` | |
| — | *always:* | |
| n+2 | `label` | `Running` |
| n+3… | `row` | `row.session`, `tone = "running"`, `value = duration`, `act = focusTerminal` — **cap 6** (`Pages.CAP.running`) |
| — | *if none:* `row` `Nothing right now`, `tone = "faded"`, no `act` | |
| — | *if capped:* `row` `…and N more`, `tone = "faded"`, no `act` | |
| p | `sep` | |
| p+1 | `into` | `Earlier sessions`, `value = tostring(#recent)`, `page = function() return self:earlier() end` |
| p+2 | `sep` | |
| p+3 | `back` | `‹  Back` |

*Why "Earlier sessions" lives here, not in the den:* every row in it does the same verb as the rows above it — jump to that terminal. The den is about numbers.

### 3.2 `Pages:den()` — depth 1 (from the stats strip) — 417px

| # | kind | content |
|---|---|---|
| 1 | `stats` | today's three figures, **no `page`** |
| 2 | `sep` | |
| 3 | `label` | `Where it went` |
| 4…8 | `row` | `bucket.folder`, `value = Stats.human(bucket.seconds) .. "  " .. (Stats.tokens(bucket.tokens) or "")` — `Stats.ranked(today, Pages.CAP.where)` = 5 |
| — | *if none:* `row` `Nothing today yet`, `tone = "faded"` | |
| 9 | `sep` | |
| 10 | `label` | `Longer view` |
| 11 | `row` | `This week`, `value = week.turns .. " turns · " .. Stats.human(week.seconds)` |
| 12 | `row` | `Streak`, `tone = "settled"`, `value = streak .. " days"` — **only when `streak > 1`** |
| — | *reserved:* `into` `Shop`, `value = purse()`, index 13 — see §7 | |
| 13 | `sep` | |
| 14 | `back` | |

### 3.3 `Pages:earlier()` — depth 2 — 483px at cap

Content identical to today's `recentPage` (`init.lua:554`). Changes: heading becomes `Earlier sessions`; the merged in-memory + ledger list is capped at `Pages.CAP.earlier = 12`; empty state `row` `Nothing yet`, `tone = "faded"`.

### 3.4 `Pages:settings()` — depth 1 — **670px** (50px of headroom under `MAX_PAGE`)

Flat and grouped. This is the one page allowed to be long, because you only reach it on purpose.

| # | kind | title | value | note | target |
|---|---|---|---|---|---|
| 1 | `label` | `Interruptions` | | | |
| 2 | `toggle` | `Live progress notes` | `on = settings.notes` | `one every 2 min at most, four a turn` | `toggle("notes")` |
| 3 | `toggle` | `Chase unanswered questions` | `on = settings.remind` | `again at 1m, 5m, 15m` | `toggle("remind")` |
| 4 | `toggle` | `Note when a turn starts` | `on = settings.noteStarts` | — | `toggle("noteStarts")` |
| 5 | `into` | `Quiet hours` | `settings.hush and Hush.window(settings) or "off"` | — | `self:hush()` |
| 6 | `into` | `When you're away` | `AWAY_LABEL[settings.awayAfter or 0]` | — | `self:away()` |
| 7 | `into` | `Per project` | `"2 muted"` / `"none"` | — | `self:projects()` |
| — | *reserved:* `into` `Focus timer` at index 8 — see §7 | | | | |
| 8 | `sep` | | | | |
| 9 | `label` | `Notes` | | | |
| 10 | `into` | `Voice` | `Voice.get(settings.voice).label` | — | `self:voice()` |
| 11 | `into` | `Detail` | `settings.detail or "brief"` | — | `self:detail()` |
| 12 | `into` | `Sounds` | `#CHIME_EVENTS .. " events"` | — | `self:sounds()` |
| 13 | `sep` | | | | |
| 14 | `label` | `Look` | | | |
| 15 | `into` | `Sprite` | `Coats.label(settings.coat)` | — | `self:sprite()` |
| 16 | `segment` | — | `on = Palette.skin`, options from `Palette.order` (`Dusk · Daylight · Burrow`) | note = `"the panel and the notes"` | `act = ctx.act.setSkin` |
| 17 | `sep` | | | | |
| 18 | `label` | `Foxbot` | | | |
| 19 | `into` | `About & help` | — | — | `self:about()` |
| 20 | `row` | `Quit foxbot` | — | — | `tone = "broken"`, `act = ctx.act.quit` |
| 21 | `sep` | | | | |
| 22 | `back` | | | | |

*Quit stays at depth 2* (home → Settings → Quit) because quitting is a real user intent. *Reload* moves to About — it's a recovery action, not a daily one.

*Colours becomes a `segment`* because a tap-to-cycle row hides its own options; with exactly 3 skins a segmented control shows all of them and costs 46px instead of 32.

### 3.5 `Pages:hush()` — depth 2 — 401px

Content as today (`init.lua:661`), except the four hour rows become `stepper` kind. Tap-to-increment needs 23 taps to go back one hour; a stepper needs one.

| # | kind | title | value | note |
|---|---|---|---|---|
| 1 | `label` | `Quiet hours` | | |
| 2 | `toggle` | `Keep quiet overnight` | `on = settings.hush` | `he keeps tracking, he just stops interrupting` |
| 3 | `stepper` | `Starts` | `%02d:00` of `settings.hushFrom` | — |
| 4 | `stepper` | `Ends` | `%02d:00` of `settings.hushTo` | — |
| 5 | `toggle` | `Silence only` | `on = settings.hushSoftly` | `notes still appear, they just make no sound` |
| 6 | `sep` | | | |
| 7 | `label` | `When he sleeps` | | |
| 8 | `stepper` | `Curls up at` | `%02d:00` of `settings.sleepFrom` | — |
| 9 | `stepper` | `Wakes at` | `%02d:00` of `settings.sleepTo` | — |
| 10 | `sep` | | | |
| 11 | `row` | `Always silent while screen sharing` | — | `tone = "faded"`, no `act` |
| 12 | `sep` | | | |
| 13 | `back` | | | |

Stepper act: `act = function(delta) ctx.act.stepHour("hushFrom", delta) end` where `stepHour` does `settings[key] = (settings[key] + delta) % 24; Settings.save(settings)`.

### 3.6 `Pages:away()` — depth 2 — 309px

Unchanged from `awayPage()` (`init.lua:702`) except it now ends `sep, back` as today. No edits needed beyond the move.

### 3.7 `Pages:projects()` — depth 2 — 515px at cap

Unchanged from `projectsPage()` (`init.lua:724`), plus: folder list capped at `Pages.CAP.projects = 12` with a trailing `row` `…and N more`, `tone = "faded"`, no `act`.

### 3.8 `Pages:voice()` (428px), `Pages:detail()` (240px)

Unchanged from `voicePage()` / `detailPage()`.

### 3.9 `Pages:sounds()` (338px) → `Pages:soundPick(event)` (547px at cap) — depth 2 → **3**

Unchanged from `soundsPage()` / `soundPickPage()`. `Chime.choices()` capped at `Pages.CAP.sounds = 14`.

### 3.10 `Pages:sprite()` (494px at cap) → `Pages:wardrobe()` (466px) — depth 2 → **3**

Unchanged from `coatPage()` / `wardrobePage()`. `Coats.all()` capped at `Pages.CAP.coats = 10`.

### 3.11 `Pages:about()` — depth 2 — 339px

| # | kind | title | note / value |
|---|---|---|---|
| 1 | `label` | `Try it` | |
| 2 | `row` | `Show me a note` | `act = ctx.act.demoNote` |
| 3 | `row` | `Show me a question` | `act = ctx.act.demoAsk` |
| 4 | `sep` | | |
| 5 | `label` | `Foxbot` | |
| 6 | `row` | `Show me around` | **reserved for the tutorial**, `act = ctx.act.tour` |
| 7 | `row` | `Open his den` | `note = "~/.claude/foxbot"`, `act = ctx.act.revealDen` |
| 8 | `row` | `Reload` | `act = ctx.act.reload` |
| 9 | `sep` | | |
| 10 | `row` | `Foxbot` | `value = "v0.1"`, `tone = "faded"`, no `act` |
| 11 | `sep` | | |
| 12 | `back` | | |

---

# 4. What gets demoted, and where

| Old home row (init.lua) | New home | Depth |
|---|---|---|
| `status` | home 1, now tappable | 0 |
| `stats` | home 3, now tappable | 0 |
| `into Sessions` | **deleted** — folded into the status row | 1 |
| `into Today` | **deleted** — folded into the stats strip | 1 |
| `into Recent` | `now()` → `Earlier sessions` | 2 |
| `label INTERRUPTIONS` | `settings()` group 1 | — |
| `toggle Live progress notes` | `settings()` 2 | 1 |
| `toggle Chase unanswered questions` | `settings()` 3 | 1 |
| `toggle Note when a turn starts` | `settings()` 4 | 1 |
| `toggle Mute everything` | **home segment, `Silent`** | 0 |
| `into Quiet hours` | `settings()` 5 | 2 |
| `into When you're away` | `settings()` 6 | 2 |
| `into Per project` | `settings()` 7 | 2 |
| `label APPEARANCE` | split into `Notes` + `Look` groups | — |
| `into Voice` | `settings()` 10 | 2 |
| `into Detail` | `settings()` 11 | 2 |
| `into Sounds` | `settings()` 12 | 2 |
| `into Sprite` | `settings()` 15 | 2 |
| `row Colours` | `settings()` 16, now a `segment` | 1 |
| `row Show/Hide foxbot` | home 9 | 0 |
| `row Show me a note` | `about()` 2 | 3 |
| `row Show me a question` | `about()` 3 | 3 |
| `row Reload` | `about()` 8 | 3 |
| `row Quit foxbot` | `settings()` 20 | 2 |

**The Settings area is organised as three labelled groups on one flat page**, not as four category doors. Once you have tapped "Settings" you have declared intent to configure, and a grouped scannable list at depth 2 beats a tidy 4-row hub that pushes every leaf to depth 3. Nesting is what loses people; the length of a page you chose to open is not.

---

# 5. New row kinds

Two, plus a modification to two existing ones. Both new kinds have ≥2 call sites at ship and a third when the timer lands.

## 5.1 `segment` — horizontal segmented control

```lua
{
  kind    = "segment",
  options = { { id = "everything", label = "Everything", note = "notes and sounds" },
              { id = "silent",     label = "Silent",     note = "notes still show, no sound" },
              { id = "paused",     label = "Paused",     note = "quiet until 14:32 · tap again for longer" } },
  on      = "everything",                       -- an option id
  act     = function(id) ... end,               -- receives the tapped option's id
}
```

**Height `H.segment = 46`** (5 track-top + 26 track + 15 note).
**Geometry** at `W = 302`, `INSET = 10`:

| element | frame |
|---|---|
| track | `{ x = INSET + 4, y = y + 5, w = W - (INSET + 4) * 2, h = 26 }` = `{14, y+5, 274, 26}`, `roundedRectRadii = {13, 13}`, `fillColor = c.hair` |
| slot width | `sw = 274 / #options` (91.33 for 3) |
| selected pill | `{ x = 14 + sw * (i - 1) + 2, y = y + 7, w = sw - 4, h = 22 }`, radii `{11,11}`, `fillColor = c.fur` |
| label | `{ x = 14 + sw * (i - 1), y = y + 11, w = sw, h = 16 }`, `text(label, Palette.small + 0.5, selected and c.panel or c.faded, "center")` |
| note | `{ x = INSET, y = y + 31, w = W - INSET * 2, h = 15 }`, `text(note, Palette.small - 0.5, c.faded, "center")` — note of the **selected** option |

**Hit zones** — pushed into the hit record so `x` resolves them:
```lua
zones[i] = { x0 = 14 + sw * (i - 1), x1 = 14 + sw * i, value = options[i].id }
```
A click in the 14px gutter either side hits no zone and does nothing.
No per-segment hover; the whole row takes the standard `c.glow` background.

Call sites at ship: home row 5 (interruption level), settings row 16 (colours). Later: timer length.

## 5.2 `stepper` — labelled `−  value  +`

```lua
{ kind = "stepper", title = "Starts", value = "22:00",
  act = function(delta) ... end }        -- delta is -1 or 1
```

**Height `H.stepper = 32`.** Right edge `rightEdge = W - INSET - 8 = 284`.

| element | frame |
|---|---|
| `+` box | `{ x = 260, y = rowMid - 11, w = 24, h = 22 }`, radii `{6,6}`, `fillColor = c.hair` |
| `+` glyph | same box, `y = rowMid - 9, h = 18`, `text("+", Palette.menu, c.ink, "center")` |
| value | `{ x = 202, y = rowMid - 8, w = 58, h = 16 }`, `text(value, Palette.small, c.faded, "center")` |
| `−` box | `{ x = 178, y = rowMid - 11, w = 24, h = 22 }`, radii `{6,6}`, `fillColor = c.hair` |
| `−` glyph | as `+` |
| title | `{ x = INSET + 8, y = rowMid - 9, w = 160, h = 18 }` |

**Hit zones:** `{ { x0 = 178, x1 = 202, value = -1 }, { x0 = 260, x1 = 284, value = 1 } }`. The title area and the value itself are inert.

Call sites at ship: `hush()` ×4. Later: timer length + break length.

Press-and-hold to repeat is explicitly out of scope.

## 5.3 `status` and `stats` become tappable (modification, not a new kind)

Both accept an optional `page`. When present:

- **`status`**: chevron `text("›", Palette.head + 3, hot and c.fur or c.faded, "right")` at `{ x = W - INSET - 20, y = y + 15, w = 12, h = 22 }`. The existing title frame width shrinks by 20 → `w = W - INSET * 2 - 26 - 20`.
- **`stats`**: `slot = (W - INSET * 2 - 20) / #row.items` (84.6 instead of 91.3 for three); chevron at `{ x = W - INSET - 16, y = y + 12, w = 12, h = 22 }`.

## 5.4 Required `menu.lua` changes

```lua
-- new heights
local H = { status = 52, stats = 46, label = 26, sep = 11,
            row = 32, toggle = 32, choice = 32, into = 32, back = 34,
            segment = 46, stepper = 32 }

-- hoisted out of the `else` branch so status/stats/segment/stepper get them too.
-- Guarded on exactly the same condition as today, so sep and label stay inert.
local function targets(row, kind)
  return row.act ~= nil or row.page ~= nil or kind == "back"
end
-- at the top of the per-row loop:
if hot and targets(row, kind) then add(glow rect at { x = INSET-4, y = y, w = W-(INSET-4)*2, h = h-2 }) end
-- at the bottom of the per-row loop:
if targets(row, kind) then
  self.hits[#self.hits+1] = { index = index, y = y, h = h - 2, row = row, zones = zones }
end
```

```lua
--- Which x-range inside a row was hit. Only segment and stepper publish zones.
function Menu:zoneAt(hit, x)
  for _, zone in ipairs(hit.zones or {}) do
    if x >= zone.x0 and x < zone.x1 then return zone end
  end
  return nil
end
```

The callback binds the x it currently discards:

```lua
self.canvas:mouseCallback(function(_, event, _, mx, my)   -- was (_, event, _, _, my)
```

Which rows keep the panel open becomes a named table, so the timer can join it later without editing a boolean expression:

```lua
local KEEPS_OPEN = { toggle = true, choice = true, segment = true, stepper = true }
```

mouseUp dispatch, with the falsy-collapse trap spelled out (constraint 6):

```lua
if event == "mouseUp" then
  if not hit then return end
  local row = hit.row

  if row.kind == "back" then self:ascend() return end
  if row.page then
    self:descend(row.page, self.pageNow or function() return rows end)
    return
  end

  if KEEPS_OPEN[row.kind] then
    -- A zoned row passes the tapped zone's value; an unzoned one passes nil.
    -- Spelled out, not `hit.zones and zone.value or nil`: a zone value of
    -- false or nil collapses that idiom, exactly as `cond and false or nil` does.
    local payload = nil
    if hit.zones then
      local zone = self:zoneAt(hit, mx)
      if not zone then return end          -- gutter click: do nothing
      payload = zone.value
    end
    row.act(payload)

    -- Same reason: `rebuild and rebuild() or rows` silently falls back to
    -- `rows` if a builder ever returns nil.
    local rebuild = self.pageNow
    if rebuild then self:fill(rebuild()) else self:fill(rows) end
    return
  end

  self:close()
  row.act()
  return
end
```

New exports so pages can be measured under the test stub without a canvas:

```lua
Menu.W         = W
Menu.H         = H
Menu.NOTE_EXTRA = NOTE_EXTRA
Menu.heightOf  = heightOf     -- was a file-local
Menu.measure   = measure      -- was a file-local; call as Menu.measure(rows), with a dot
Menu.MAX_HOME  = 400          -- home must never exceed this
Menu.MAX_PAGE  = 720          -- any page must never exceed this
```

---

# 6. Making it testable: `foxbot/pages.lua`

The page builders are today ~410 lines of closures inside `init.lua` (lines 442–856) that capture module-level `settings`, `sessions`, `ledger`, `fox`, `recent`. Nothing in them can be exercised by `tests/run.lua`. Extract them.

```lua
--- foxbot/pages.lua
--- Every page is a pure function of a context table. Nothing here touches a
--- canvas, a timer, or the filesystem directly, so the whole tree can be built
--- and measured under the test stub.
local Pages = {}
Pages.__index = Pages

Pages.CAP = { blocked = 5, running = 6, earlier = 12,
              projects = 12, sounds = 14, coats = 10, where = 5 }

Pages.PAUSE_STEPS = { 1800, 3600, 10800, 28800 }   -- 30m, 1h, 3h, 8h

function Pages.new(ctx) end          -- ctx shape below

function Pages:home() end
function Pages:now() end
function Pages:den() end
function Pages:earlier() end
function Pages:settings() end
function Pages:hush() end
function Pages:away() end
function Pages:projects() end
function Pages:voice() end
function Pages:detail() end
function Pages:sounds() end
function Pages:soundPick(event) end  -- returns a zero-arg builder
function Pages:sprite() end
function Pages:wardrobe() end
function Pages:about() end

-- Pure, exported for tests.
function Pages.level(settings, now) end       -- "everything" | "silent" | "paused"
function Pages.nextPause(settings, now) end   -- seconds for the next Paused tap
function Pages.backAt(settings) end           -- "14:32" or nil
```

**`ctx` shape** — the only seam between pages and the world:

```lua
{
  settings = <the live settings table, mutated in place, never replaced>,
  sessions = <Sessions instance>,
  ledger   = <History instance>,
  recent   = <array of events, newest first>,
  hidden   = function() return fox:hidden() end,
  purse    = function() return 0 end,          -- reserved: donut balance
  now      = function() return os.time() end,  -- injectable clock

  act = {
    focusTerminal = function(tty, app) end,
    reveal        = function(path) end,
    setLevel      = function(id) end,          -- "everything"|"silent"|"paused"
    setAway       = function(seconds) end,
    setSkin       = function(name) end,
    setVoice      = function(name) end,
    setDetail     = function(id) end,
    setChime      = function(kind, id) end,
    setCoat       = function(id) end,
    muteProject   = function(folder, on) end,
    stepHour      = function(key, delta) end,  -- "hushFrom"|"hushTo"|"sleepFrom"|"sleepTo"
    toggle        = function(key) end,         -- any boolean SCHEMA key
    revealSounds  = function() end,
    revealCoats   = function() end,
    revealDen     = function() end,
    toggleFox     = function() end,
    demoNote      = function() end,
    demoAsk       = function() end,
    tour          = function() end,            -- reserved: tutorial
    reload        = function() end,
    quit          = function() end,
  },
}
```

**`row.page` must be a zero-arg closure**, never a method reference — `Menu:descend` calls `page()` with no receiver:

```lua
{ kind = "into", title = "Voice", page = function() return self:voice() end }
```

`init.lua` shrinks from 1046 to ~640 lines; `pages.lua` is ~430.

---

# 7. How the timer, the shop and the tutorial slot in

None of them changes the home skeleton. All four future features were budgeted for before the numbers above were fixed.

## Focus timer

- **Home**: index 6, the reserved slot between the segment and its `sep`. Kind `row` at first (a dedicated `timer` kind with a countdown ring can replace it later at the same index and the same 32–46px).
  - idle: `{ kind = "row", title = "Start a focus block", value = focusLabel(settings), act = ctx.act.startFocus }`
  - running: `{ kind = "row", title = "Focus", tone = "running", value = "18:42", note = "then a 5 min break", act = ctx.act.stopFocus }`
  - Home: **9 → 10 entries, 280 → 312px.**
- **Settings**: one `into` `Focus timer` at index 8, inside the existing `Interruptions` group. Settings: **670 → 702px**, still under `MAX_PAGE = 720`.
- **`Pages:focus()`** (depth 2) uses `stepper` for length and break, and a `choice` list reusing `Pages:soundPick` for the end chime. No new kinds.
- SCHEMA: `focusFor = 1500`, `breakFor = 300`, `focusUntil = 0`, `focusChime = "Hero"`. Four entries, one list.
- Nudges/fun facts are an interruption source, so they get a `toggle` in the same `Interruptions` group. Anti-annoyance budget: they route through `Hush.check` like every other note, and inherit the pause/silent/quiet-hours gates for free.

## Donuts + shop

- **Home does not change at all.** `statsRow` gains a 4th item `{ label = "donuts", value = tostring(purse()) }`. Slot width goes `274/3 = 91.3` → `274/4 = 68.5`; a 5-character value at `Palette.head` (13pt Menlo, ~7.8px/char) is 39px, so it fits with 29px to spare.
- **Den**: one `into` `Shop`, `value = tostring(purse())`, at index 13. Den: **417 → 449px.**
- `Pages:shop()` is a depth-2 leaf. If it needs a grid it gets its own `tile` kind then — a leaf-only kind with zero effect on any other page.
- SCHEMA: `donuts = 0`, `owned = {}`.

## First-run tutorial

- `about()` row 6 `Show me around` already exists as a reserved row.
- First launch: `settings.toured == false` → the fox shows one note with a `show me` chip (the panel's existing chip mechanism), which calls `ctx.act.tour`. It is one note, once, ever — comfortably inside the anti-annoyance budget.
- SCHEMA: `toured = false`.

---

# 8. The one new setting, and the pause mechanic

## SCHEMA

```lua
-- Added
pauseUntil = 0,     -- epoch seconds; interruptions fully off until then. 0 = not paused.

-- Removed
showRunning = true, -- declared at settings.lua:38, referenced nowhere in the codebase
```

That is the whole settings change. Everything else in the redesign is a re-arrangement of rows that read settings that already exist.

## Level, derived — never stored

```lua
--- Which of the three interruption levels is in force.
--- Spelled out rather than chained and/or: `settings.quiet` is a boolean that
--- is false half the time, and `cond and "silent" or "everything"` reads fine
--- right up until someone adds a level whose value is false.
function Pages.level(settings, now)
  if Hush.paused(settings, now) > 0 then return "paused" end
  if settings.quiet then return "silent" end
  return "everything"
end
```

`ctx.act.setLevel(id)`:

| id | effect |
|---|---|
| `everything` | `settings.quiet = false`; `settings.pauseUntil = 0` |
| `silent` | `settings.quiet = true`; `settings.pauseUntil = 0` |
| `paused` | `settings.pauseUntil = now + Pages.nextPause(settings, now)` — **`quiet` is left alone**, so unpausing returns you to whichever of Everything/Silent you came from |

Then `Settings.save(settings)`.

## Step derivation — no second setting needed

```lua
--- The duration the next tap on "Paused" should use. Derived from how much
--- pause is left, so the ladder survives a restart without persisting an index.
function Pages.nextPause(settings, now)
  local left = Hush.paused(settings, now)
  if left <= 0 then return Pages.PAUSE_STEPS[1] end
  for i, step in ipairs(Pages.PAUSE_STEPS) do
    if left <= step then return Pages.PAUSE_STEPS[i + 1] or step end
  end
  return Pages.PAUSE_STEPS[#Pages.PAUSE_STEPS]
end
```

Tapping `Paused` repeatedly walks 30m → 1h → 3h → 8h and then sticks. Selecting either other segment clears it.

## `hush.lua`

```lua
--- Seconds of explicit pause still to run, or 0.
function Hush.paused(settings, now)
  local until_ = tonumber(settings.pauseUntil) or 0
  now = now or os.time()
  -- A clock jumped backwards, or a stored value from a restored backup, would
  -- otherwise pin him silent for months. Anything beyond the longest step the
  -- UI can produce is treated as garbage.
  if until_ > now + 28800 then return 0 end
  if until_ <= now then return 0 end
  return until_ - now
end

--- "14:32", or nil when not paused.
function Hush.backAt(settings)
  local until_ = tonumber(settings.pauseUntil) or 0
  if until_ <= 0 then return nil end
  return os.date("%H:%M", until_)
end
```

`Hush.check` gains an optional third argument and a first branch:

```lua
--- @param when  the event's timestamp — quiet hours are about the event's clock
--- @param now   wall clock — a pause is about whether you'll take an
---              interruption *this second*, not about when the event happened
function Hush.check(settings, when, now)
  if Hush.paused(settings, now or os.time()) > 0 then return true, false, "paused" end
  if settings.quiet then return true, true, "muted" end
  local presenting = Hush.presenting()
  if presenting then return true, false, presenting end
  if settings.hush then ... end          -- unchanged, still keyed off `when`
  return false, true, nil
end
```

The pause check goes first deliberately: it is a single integer compare, whereas `Hush.presenting()` walks eight bundle ids through `hs.application.get` on **every** event.

Because `announce`, `ambient`, and `chase` all already route through `Hush.check`, pause covers them for free — including the hidden-fox `hs.notify` path at `init.lua:219`.

## The one gap pause exposes

`catchUp` (`init.lua:314`) calls `Chime.play` and `panel:say` **without** consulting `Hush`. Add the guard at the top:

```lua
local function catchUp(held, since)
  if fox:hidden() then return end
  local silence, show = Hush.check(settings)
  if not show then return end
  ...
  if not silence then Chime.play(chimeFor(blocked > 0 and "ask" or "done")) end
```

## Menu bar

`M.paintBar`, in the idle branch only:

```lua
local back = Hush.backAt(settings)
if back then
  bar:setTooltip("Foxbot — paused until " .. back)
else
  bar:setTooltip("Foxbot — " .. Mood.get(restingMood()).label:lower())
end
```

Spelled out, not `back and (...) or (...)` — `back` is nil-or-string here, which happens to be safe, but the house rule at `settings.lua:88` and `settings.lua:141` exists because this exact shape has bitten three times.

---

# 9. Tests

Add `tests/pages.lua`, required from `tests/run.lua`. Roughly 45 new checks on top of the existing 187. No stub changes needed — `pages.lua` only requires modules already exercised (`Palette`, `Mood`, `Voice`, `Chime`, `Coats`, `Stats`, `Sessions`, `History`, `Hush`, `Settings`), and `Chime.folder` / `Coats.folder` already resolve against the stub's `hs.configdir`.

**Geometry invariants** — these are the tests that make the 903px bug impossible to reintroduce:

```lua
check("home is nine entries", #p:home(), 9)
ok("home fits anywhere",   Menu.measure(p:home()) <= Menu.MAX_HOME)
ok("home leaves timer room", Menu.measure(p:home()) + Menu.H.row <= Menu.MAX_HOME)
for name, page in pairs(everyPage) do
  ok(name .. " fits a small screen", Menu.measure(page()) <= Menu.MAX_PAGE)
end
```

Run each growable page against a **worst-case fixture**, not an empty one: 40 ledger folders, 30 sound files, 25 sessions, 20 coats. Assert the caps bite and the height still holds.

**Structure invariants:**

```lua
check("no page is deeper than three", maxDepth(p), 3)
ok("every `into` row carries a page",        everyIntoHasPage(p))
ok("every sub-page ends in a back row",      everyPageEndsBack(p))
ok("no home row is a dead end",              everyHomeRowTargets(p))
ok("sep and label never carry act or page",  furnitureIsInert(p))
ok("every segment's `on` matches an option", segmentsResolve(p))
```

**Level and pause:**

```lua
check("nothing set is everything", Pages.level({}, 1000), "everything")
check("quiet is silent",           Pages.level({ quiet = true }, 1000), "silent")
check("a live pause wins",         Pages.level({ quiet = true, pauseUntil = 2000 }, 1000), "paused")
check("an expired pause is inert", Pages.level({ pauseUntil = 999 }, 1000), "everything")
check("unpausing returns to silent", Pages.level({ quiet = true, pauseUntil = 999 }, 1000), "silent")
check("first tap is thirty minutes", Pages.nextPause({}, 1000), 1800)
check("second tap is an hour",       Pages.nextPause({ pauseUntil = 1000 + 1500 }, 1000), 3600)
check("third is three hours",        Pages.nextPause({ pauseUntil = 1000 + 3000 }, 1000), 10800)
check("the ladder tops out",         Pages.nextPause({ pauseUntil = 1000 + 28000 }, 1000), 28800)
```

**Hush — the four-way truth table, because getting the branch order wrong mutes him forever:**

```lua
check("pause silences",            (Hush.check({ pauseUntil = 2000 }, 1000, 1000)), true)
check("pause hides the note",      select(2, Hush.check({ pauseUntil = 2000 }, 1000, 1000)), false)
check("pause names itself",        select(3, Hush.check({ pauseUntil = 2000 }, 1000, 1000)), "paused")
check("an expired pause shows",    select(2, Hush.check({ pauseUntil = 999 }, 1000, 1000)), true)
check("no pause key is inert",     select(2, Hush.check({}, 1000, 1000)), true)
check("muted still shows",         select(2, Hush.check({ quiet = true }, 1000, 1000)), true)
check("a nonsense pauseUntil is inert", Hush.paused({ pauseUntil = "banana" }, 1000), 0)
check("a far-future pause is clamped",  Hush.paused({ pauseUntil = 1e12 }, 1000), 0)
```

**Schema:** the existing loop at `tests/run.lua:295-334` already covers `pauseUntil` automatically the moment it is declared — that is the point of the derived key list. Add one named check anyway, since a zero default is the same shape of trap as a false one:

```lua
check("pauseUntil defaults to zero, not nil", Settings.load().pauseUntil, 0)
```

---

# 10. Height ledger (all verified by calculation)

| page | entries | height | vs `MAX_PAGE` 720 |
|---|---|---|---|
| **home** | 9 | **280** | 440 spare |
| home + timer | 10 | 312 | 408 spare |
| now (empty) | 8 | 237 | |
| now (worst: 5 blocked + 6 running) | 20 | 669 | 51 spare |
| den | 14 | 417 | |
| den + shop | 15 | 449 | |
| **settings** | 22 | **670** | 50 spare — reserved for the timer row |
| settings + timer | 23 | 702 | 18 spare |
| hush | 13 | 401 | |
| away | 9 | 309 | |
| projects (cap 12) | 16 | 515 | |
| voice (7) | 10 | 428 | |
| detail | 6 | 240 | |
| sounds | 10 | 338 | |
| soundPick (cap 14) | 17 | 547 | |
| sprite (cap 10) | 15 | 494 | |
| wardrobe (10) | 14 | 466 | |
| earlier (cap 12) | 15 | 483 | |
| about | 12 | 339 | |

Smallest realistic `hs.screen:frame().h` is ~875 (1440×900 minus menu bar), leaving 859 usable after the 8px margins `Menu:open` applies. `MAX_PAGE = 720` keeps 139px of margin on the tallest page.

**Home goes from 903px to 280px — a 69% reduction — and from 29 entries to 9.**

---

# 11. Constraint check

| Constraint | How this satisfies it |
|---|---|
| 1. No macOS permissions | Nothing added touches `hs.eventtap:start`, Accessibility, Screen Recording or Automation. `segment`/`stepper` hit-test the x coordinate the canvas mouse callback **already delivers** (`menu.lua:318` binds five params and discards the fourth today). |
| 2. No network | Nothing added performs I/O beyond `hs.settings` and the existing `hs.fs.dir` reads. |
| 3. AppleScript bridge off | Untouched. `prepare()` (`init.lua:971`) is unchanged. |
| 4. Anti-annoyance | Strictly improved. `pauseUntil` is a **new suppression**, never a new interruption, and it is checked *first* so it outranks every other gate. The one gap pause exposes — `catchUp` bypassing `Hush` — is closed as part of this work. No new notification source ships here. |
| 5. Schema-driven settings | One `SCHEMA` entry added (`pauseUntil = 0`), one dead one removed (`showRunning`). `KEYS` stays derived; no second list anywhere. The future features name their entries in §7 and add nothing else. |
| 6. Falsy-collapse traps | Three named sites: `Pages.level` (spelled out if/else), the mouseUp payload resolution (§5.4), and the `paintBar` tooltip (§8). The existing `self:fill(rebuild and rebuild() or rows)` at `menu.lua:339` is rewritten to the spelled-out form in the same pass. |
| 7. Unit-testable | The whole point of `pages.lua`. Page builders become pure functions of an injected context and are measured with the exported `Menu.measure`, under the existing stub, with no canvas. ~45 new checks. |


## Settings

- pauseUntil = 0  — epoch seconds; all interruptions suppressed until then, 0 means not paused. The only setting this redesign introduces.
- REMOVED: showRunning (declared at settings.lua:38, referenced nowhere in the codebase — dead)
- RESERVED, not added now — focus timer: focusFor = 1500, breakFor = 300, focusUntil = 0, focusChime = "Hero"
- RESERVED, not added now — donuts/shop: donuts = 0, owned = {}
- RESERVED, not added now — tutorial: toured = false

## Risks

- MEASURED BUG, fixed as a side effect: the current home page is 903px but the usable frame on a 1440x900 Mac is 859px, and Menu:fill/Menu:open clamp y without shrinking or scrolling — so 'Reload' and 'Quit foxbot' are currently drawn off the bottom edge and are unclickable on small displays. If the new MAX_HOME/MAX_PAGE height assertions are not added to the test suite, this regresses the first time someone appends a row.
- segment and stepper need the x coordinate. menu.lua:318 currently binds five callback params and discards the fourth (`function(_, event, _, _, my)`); it must become `(_, event, _, mx, my)`. Verified this is the only canvas mouseCallback in menu.lua, and panel.lua/sprite.lua bind their own independently — but confirm on device that the fourth param really is x before relying on zone hit-testing.
- Making status and stats tappable requires hoisting the hot-glow rect and the hit registration out of the `else` branch in Menu:paint. If the hoist drops the `row.act or row.page or kind == "back"` guard, `sep` and `label` become clickable no-ops that still light up on hover — visually broken and confusing. Keep the guard verbatim.
- Hush.check gaining a pause branch changes behaviour for announce(), ambient(), chase(), and the hidden-fox hs.notify path all at once. A wrong branch order or a sign error mutes the fox permanently and silently — the exact failure the product cannot survive. Test the four-way truth table (paused/muted/presenting/quiet-hours) before shipping.
- pauseUntil is an absolute timestamp. A restored settings backup, a clock jump, or a machine that slept across a DST change can leave it far in the future, pinning him silent for weeks with no visible cause. Hush.paused must clamp anything beyond now + 28800 (the longest step the UI can produce) back to 0, and that clamp needs its own test.
- Pages.new(ctx) closes over the settings table. init.lua must mutate that table in place and never rebind it to a fresh Settings.load() result, or every menu row silently reads stale values. Today hs.reload() sidesteps this; the coat picker's reload path is the one place to check.
- row.page must be a zero-arg closure (`function() return self:voice() end`), not a method reference — Menu:descend calls page() with no receiver, so passing pages.voice loses self and errors at click time, only on the sub-page, only when tapped.
- Growable pages (projects, sounds, earlier, sprite) still exceed MAX_PAGE if the caps in Pages.CAP are not actually applied. The height assertions must run against worst-case fixtures (40 ledger folders, 30 sound files, 25 sessions, 20 coats), not the empty default, or they pass while proving nothing.
- Quit foxbot moves from home (1 tap) to Settings (2 taps) and Reload moves to About (3 taps). README.md and docs/ reference the menu layout and need updating in the same commit, or the install instructions describe a panel that no longer exists.
- Removing showRunning from SCHEMA drops a key that existing users have persisted. Settings.load ignores unknown stored keys and Settings.save writes only derived KEYS, so it is cleaned up on the next save with no migration — but it is still a persisted-data change and should be called out in the commit message.