--- Foxbot — a fox who watches your Claude Code sessions.
---
--- Claude Code's hooks append events to ~/.claude/foxbot/inbox.jsonl. This
--- module tails that file, keeps track of what is running and what is blocked
--- on you, puts notes on screen, and writes finished turns to a ledger so the
--- numbers survive a restart.
---
--- Menus are macOS's own. Drawing a custom menu means also drawing a shield to
--- catch clicks outside it, keyboard handling, and scroll — all to end up with
--- something that looks less like the rest of the system. The native menu is
--- fewer moving parts and behaves the way people expect.

local Settings = require("foxbot.settings")
local Palette  = require("foxbot.palette")
local Sprite   = require("foxbot.sprite")
local Panel    = require("foxbot.panel")
local Voice    = require("foxbot.voice")
local Chime    = require("foxbot.chime")
local Coats    = require("foxbot.coats")
local Mood     = require("foxbot.mood")
local Hush     = require("foxbot.hush")
local Focus    = require("foxbot.focus")
local Sessions = require("foxbot.sessions")
local History  = require("foxbot.history")
local Stats    = require("foxbot.stats")
local Away     = require("foxbot.away")

local M = {}

local HOME = os.getenv("HOME")
local DEN = HOME .. "/.claude/foxbot"
local INBOX = DEN .. "/inbox.jsonl"
local LEDGER = DEN .. "/ledger.jsonl"

local REPEAT_GUARD = 5      -- seconds; ignore an identical event twice over
local RECALL = 12           -- how many sessions the menu remembers
local TOGGLE_KEY = { { "ctrl", "alt", "cmd" }, "f" }
local REPORT_KEY = { { "ctrl", "alt", "cmd" }, "t" }

local DEFAULT_CHIMES = {
  done = "Hero", ask = "Ping", idle = "Submarine",
  ["end"] = "Bottle", busy = Chime.SILENT, error = "Basso",
  nudge = "Submarine",
}

local CHIME_EVENTS = {
  { kind = "done",  label = "Turn finished" },
  { kind = "ask",   label = "Asking you something" },
  { kind = "nudge", label = "Still waiting on you" },
  { kind = "busy",  label = "Turn started" },
  { kind = "error", label = "Something broke" },
  { kind = "end",   label = "Session closed" },
}

-- How much of a finished turn to show.
local DETAIL = {
  { id = "name",  label = "Name only",  note = "one line" },
  { id = "brief", label = "Brief",      note = "three lines" },
  { id = "full",  label = "Everything", note = "up to six" },
}
local DETAIL_LINES = { name = nil, brief = 3, full = 6 }

-- What counts as being away.
local AWAY_STEPS = { 0, 900, 1800 }
local AWAY_LABEL = { [0] = "locked or asleep", [900] = "15 min idle", [1800] = "30 min idle" }

local settings, fox, panel, bar, watcher, keys
local sessions, ledger, away
local readTo = 0
local lastSeen = {}
local recent = {}

-- ------------------------------------------------------------------- inbox

local function fileSize(path)
  local attrs = hs.fs.attributes(path)
  return attrs and attrs.size or 0
end

--- Everything appended since we last looked.
local function drain()
  local size = fileSize(INBOX)
  if size < readTo then
    -- Truncated or rotated: pick up at the new end rather than replaying the
    -- whole file, which would fire a burst of notes for dead sessions.
    readTo = size
    return {}
  end
  if size == readTo then return {} end

  local file = io.open(INBOX, "r")
  if not file then return {} end
  file:seek("set", readTo)
  local chunk = file:read("*a") or ""
  readTo = file:seek()
  file:close()

  local events = {}
  for line in chunk:gmatch("[^\n]+") do
    local ok, event = pcall(hs.json.decode, line)
    if ok and type(event) == "table" and event.session then
      events[#events + 1] = event
    end
  end
  return events
end

-- ------------------------------------------------------------------ notes

local function chimeFor(kind)
  return (settings.chimes or {})[kind] or DEFAULT_CHIMES[kind] or DEFAULT_CHIMES.done
end

local function voiceFor(event)
  local rule = Settings.project(settings, event.folder)
  return rule.voice or settings.voice
end

local function keyOf(event)
  return (event.session_id ~= "" and event.session_id) or event.session
end

--- Where the fox settles once a temporary mood runs out. A question outranks
--- work in progress: something is blocked on you, and it should stay obvious.
local function restingMood()
  if sessions:isWaiting() then return "asking" end
  return sessions:isBusy() and "running" or "resting"
end

local function refeel(kind)
  if not fox then return end
  fox:feel(kind and Mood.fromKind(kind) or restingMood(), restingMood())
end

local function remember(event)
  local key = keyOf(event)
  for index, held in ipairs(recent) do
    if keyOf(held) == key then table.remove(recent, index) break end
  end
  table.insert(recent, 1, event)
  while #recent > RECALL do table.remove(recent) end
end

--- The little buttons along the bottom of a note.
local function chipsFor(event)
  local chips = {}

  if event.tty and event.tty ~= "" then
    chips[#chips + 1] = { label = "terminal",
      act = function() Focus.terminal(event.tty, event.app) end }
  end
  if event.cwd and event.cwd ~= "" then
    chips[#chips + 1] = { label = "folder", act = function() Focus.reveal(event.cwd) end }
    chips[#chips + 1] = { label = "editor", act = function() Focus.editor(event.cwd) end }
  end
  if event.lines and #event.lines > 0 then
    chips[#chips + 1] = { label = "copy", act = function()
      local out = { event.session }
      for _, line in ipairs(event.lines) do out[#out + 1] = "- " .. line end
      hs.pasteboard.setContents(table.concat(out, "\n"))
      hs.alert.show("copied", 0.6)
    end }
  end

  return chips
end

--- Put a note on screen for a finished / asking / closed event.
local function announce(event, elapsed)
  remember(event)

  local rule = Settings.project(settings, event.folder)
  local silence, show = Hush.check(settings, event.ts)
  if rule.mute then silence, show = true, false end

  -- Nobody is looking: hold it for the catch-up rather than stacking notes
  -- that will all be stale by the time you get back.
  if settings.catchUp and away and away:isAway() and event.kind ~= "busy" then
    event.elapsed = elapsed
    away:hold(event)
    return
  end

  if not silence then Chime.play(chimeFor(event.kind)) end
  if not show then return end

  -- Hidden means the sprite is gone, not that you stop being told.
  if fox:hidden() then
    if not silence then
      hs.notify.new({
        title = event.session,
        subTitle = Voice.line(voiceFor(event), event.kind),
        informativeText = (event.hint ~= "" and event.hint) or nil,
        withdrawAfter = 10,
      }):send()
    end
    return
  end

  local body = Voice.line(voiceFor(event), event.kind)
  if event.hint and event.hint ~= "" then
    body = body .. "\n“" .. event.hint .. "”"
  end

  local wanted = (event.kind == "ask") and 6 or DETAIL_LINES[settings.detail]
  local lines = nil
  if wanted and event.lines and #event.lines > 0 then
    lines = {}
    for index, line in ipairs(event.lines) do
      if index > wanted then break end
      lines[#lines + 1] = line
    end
  end

  local stamp = {}
  if elapsed then stamp[#stamp + 1] = Sessions.duration(elapsed) end
  local spent = Stats.tokens((event.tokens or 0) + (event.subTokens or 0))
  if spent then stamp[#stamp + 1] = spent end

  fox:startle()
  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = event.session,
    body = body,
    lines = lines,
    stamp = (#stamp > 0) and table.concat(stamp, " · ") or nil,
    chips = chipsFor(event),
    onOpen = function() Focus.terminal(event.tty, event.app) end,
  })
end

--- An ambient note about what just got applied to the project. The quietest
--- thing he does: no sound, no startle, gone sooner, no buttons.
local function ambient(event)
  if not settings.notes then return end
  -- Something is already blocked on you; a progress note on top is noise at
  -- the exact moment you least want it.
  if sessions:isWaiting() then return end
  if settings.catchUp and away and away:isAway() then return end
  if Settings.project(settings, event.folder).mute then return end

  local _, show = Hush.check(settings, event.ts)
  if not show or fox:hidden() then return end

  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = event.session,
    body = event.hint or "",
    lines = event.lines,
    hold = Palette.lingerStep,
    onOpen = function() Focus.terminal(event.tty, event.app) end,
  })
end

--- Say it again about a question that has gone unanswered.
local function chase(row)
  local silence, show = Hush.check(settings)
  if Settings.project(settings, row.folder).mute then return end
  if settings.catchUp and away and away:isAway() then return end

  if not silence then Chime.play(chimeFor("nudge")) end
  if not show or fox:hidden() then return end

  fox:feel("asking", restingMood())
  fox:startle()
  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = row.session,
    body = Voice.line(settings.voice, "nudge")
           .. ((row.hint and row.hint ~= "") and ("\n“" .. row.hint .. "”") or ""),
    stamp = "blocked " .. (Sessions.duration(row.elapsed) or ""),
    chips = {
      { label = "terminal", act = function() Focus.terminal(row.tty, row.app) end },
      { label = "dismiss",  act = function()
          sessions:answered(row.id)
          refeel()
          M.paintBar()
        end },
    },
    onOpen = function() Focus.terminal(row.tty, row.app) end,
  })
end

--- One note covering everything that happened while you were away.
local function catchUp(held, since)
  if fox:hidden() then return end

  local turns, seconds, tokens, blocked = 0, 0, 0, 0
  local order, rows = {}, {}

  for _, event in ipairs(held) do
    if event.kind == "done" then
      turns = turns + 1
      seconds = seconds + (event.elapsed or 0)
      tokens = tokens + (event.tokens or 0) + (event.subTokens or 0)
    elseif event.kind == "ask" or event.kind == "idle" then
      blocked = blocked + 1
    end

    local key = keyOf(event)
    if not rows[key] then order[#order + 1] = key end
    local row = rows[key] or { session = event.session, turns = 0, seconds = 0 }
    if event.kind == "done" then
      row.turns = row.turns + 1
      row.seconds = row.seconds + (event.elapsed or 0)
    end
    row.waiting = row.waiting or (event.kind == "ask" or event.kind == "idle")
    row.event = event
    rows[key] = row
  end

  local lines = {}
  for _, key in ipairs(order) do
    local row = rows[key]
    local bits = { row.session }
    if row.turns > 0 then
      bits[#bits + 1] = row.turns .. (row.turns == 1 and " turn" or " turns")
    end
    if row.seconds > 0 then bits[#bits + 1] = Sessions.duration(row.seconds) end
    if row.waiting then bits[#bits + 1] = "waiting on you" end
    lines[#lines + 1] = table.concat(bits, " · ")
    if #lines >= 6 then break end
  end

  local headline = turns .. (turns == 1 and " turn" or " turns") .. " finished"
  if blocked > 0 then headline = headline .. ", " .. blocked .. " waiting on you" end

  local stamp = {}
  if since then stamp[#stamp + 1] = "away " .. (Sessions.duration(os.time() - since) or "") end
  local spent = Stats.tokens(tokens)
  if spent then stamp[#stamp + 1] = spent end

  Chime.play(chimeFor(blocked > 0 and "ask" or "done"))
  fox:startle()
  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = "while you were out",
    body = headline .. (seconds > 0 and ("\n" .. Sessions.duration(seconds) .. " of work") or ""),
    lines = lines,
    stamp = (#stamp > 0) and table.concat(stamp, " · ") or nil,
    hold = Palette.lingerLong,
    chips = { { label = "clear", act = function() panel:clear() end } },
  })
end

-- ------------------------------------------------------------------ events

local function handle(event)
  local kind = event.kind or "done"

  -- Progress notes are ambient: they never touch the mood, the tracker, the
  -- ledger or the recent list. They appear and they go.
  if kind == "step" then
    ambient(event)
    return
  end

  if kind == "busy" then
    sessions:begin(event)
    sessions:answered(event)          -- work restarting means it got answered
    refeel("busy")
    M.paintBar()
    if settings.noteStarts then announce(event) end
    return
  end

  if kind == "ask" or kind == "idle" then
    sessions:wait(event)
  else
    sessions:answered(event)
  end

  local elapsed
  if kind == "done" or kind == "end" or kind == "error" then
    elapsed = sessions:finish(event)
  end

  local guard = keyOf(event) .. "/" .. kind
  local now = os.time()
  if lastSeen[guard] and (now - lastSeen[guard]) < REPEAT_GUARD then return end
  lastSeen[guard] = now

  if kind == "done" or kind == "error" then
    ledger:append({
      ts = event.ts or now,
      kind = kind,
      session = event.session,
      session_id = event.session_id,
      folder = event.folder,
      cwd = event.cwd,
      elapsed = elapsed or 0,
      tokens = event.tokens or 0,
      subTokens = event.subTokens or 0,
      context = event.context or 0,
      model = event.model,
    })
  end

  refeel(kind)
  M.paintBar()
  announce(event, elapsed)
end

-- ------------------------------------------------------------------- menus

local function tick(on) return on and "✓ " or "   " end

local function runningMenu()
  local items = {}
  local blocked = sessions:blocked()

  if #blocked > 0 then
    items[#items + 1] = { title = "Waiting on you", disabled = true }
    for _, row in ipairs(blocked) do
      items[#items + 1] = {
        title = "   " .. row.session .. "   " .. (Sessions.duration(row.elapsed) or ""),
        fn = function() Focus.terminal(row.tty, row.app) end,
      }
    end
    items[#items + 1] = { title = "-" }
  end

  local live = sessions:list()
  items[#items + 1] = { title = "Running now", disabled = true }
  if #live == 0 then
    items[#items + 1] = { title = "   nothing", disabled = true }
  end
  for _, row in ipairs(live) do
    items[#items + 1] = {
      title = "   " .. row.session .. "   " .. (Sessions.duration(row.elapsed) or ""),
      fn = function() Focus.terminal(row.tty, row.app) end,
    }
  end
  return items
end

local function reportMenu()
  local since = Stats.startOfDay()
  local today = Stats.summarise(ledger.rows, since)
  local week = Stats.summarise(ledger.rows, Stats.startOfDay(os.time() - 6 * 86400))
  local streak = Stats.streak(ledger.rows)

  local items = {
    { title = "Today", disabled = true },
    { title = "   " .. today.turns .. " turns", disabled = true },
    { title = "   " .. Stats.human(today.seconds) .. " working", disabled = true },
  }
  local spent = Stats.tokens(today.tokens + today.subTokens)
  if spent then items[#items + 1] = { title = "   " .. spent .. " tokens", disabled = true } end
  if streak > 1 then
    items[#items + 1] = { title = "   " .. streak .. " day streak", disabled = true }
  end

  local ranked = Stats.ranked(today, 5)
  if #ranked > 0 then
    items[#items + 1] = { title = "-" }
    items[#items + 1] = { title = "Where it went", disabled = true }
    for _, bucket in ipairs(ranked) do
      items[#items + 1] = {
        title = string.format("   %-18s %s", bucket.folder, Stats.human(bucket.seconds)),
        disabled = true,
      }
    end
  end

  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "This week", disabled = true }
  items[#items + 1] = { title = "   " .. week.turns .. " turns · "
                        .. Stats.human(week.seconds), disabled = true }
  return items
end

local function recentMenu()
  local items, seen = {}, {}

  for _, event in ipairs(recent) do
    seen[keyOf(event)] = true
    items[#items + 1] = {
      title = os.date("%H:%M", event.ts) .. "  " .. event.session,
      fn = function() Focus.terminal(event.tty, event.app) end,
    }
  end
  for _, row in ipairs(ledger:recent(RECALL)) do
    local key = row.session_id or row.session
    if not seen[key] then
      seen[key] = true
      items[#items + 1] = {
        title = os.date("%H:%M", row.ts) .. "  " .. row.session,
        fn = function() Focus.reveal(row.cwd) end,
      }
    end
  end

  if #items == 0 then items[1] = { title = "nothing yet", disabled = true } end
  return items
end

local function voiceMenu()
  local items = {}
  for _, name in ipairs(Voice.order) do
    local voice = Voice.get(name)
    items[#items + 1] = {
      title = voice.label .. "  —  " .. Voice.sample(name, "done"),
      checked = settings.voice == name,
      fn = function()
        settings.voice = name
        Settings.save(settings)
        M.demo()
      end,
    }
  end
  return items
end

local function detailMenu()
  local items = {}
  for _, option in ipairs(DETAIL) do
    items[#items + 1] = {
      title = option.label .. "  (" .. option.note .. ")",
      checked = settings.detail == option.id,
      fn = function()
        settings.detail = option.id
        Settings.save(settings)
        M.demoLines()
      end,
    }
  end
  return items
end

local function chimeMenu()
  local items = {}
  for _, event in ipairs(CHIME_EVENTS) do
    local picks = {}
    for _, choice in ipairs(Chime.choices()) do
      picks[#picks + 1] = {
        title = choice.label,
        checked = chimeFor(event.kind) == choice.id,
        fn = function()
          settings.chimes = settings.chimes or {}
          settings.chimes[event.kind] = choice.id
          Settings.save(settings)
          Chime.play(choice.id)
        end,
      }
    end
    items[#items + 1] = {
      title = event.label .. "   " .. Chime.label(chimeFor(event.kind)),
      menu = picks,
    }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Add your own…", fn = function() Chime.reveal() end }
  return items
end

local function coatMenu()
  local items = {}
  for _, coat in ipairs(Coats.all()) do
    items[#items + 1] = {
      title = coat.label,
      checked = (settings.coat or Coats.default) == coat.id,
      fn = function()
        settings.coat = coat.id
        Settings.save(settings)
        hs.reload()          -- the sprite is built once, at load
      end,
    }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Add your own…", fn = function() Coats.reveal() end }
  return items
end

local function projectMenu()
  local seen, folders = {}, {}
  for _, row in ipairs(ledger:recent(40)) do
    if row.folder and row.folder ~= "" and not seen[row.folder] then
      seen[row.folder] = true
      folders[#folders + 1] = row.folder
    end
  end
  for folder in pairs(settings.perProject or {}) do
    if not seen[folder] then seen[folder] = true folders[#folders + 1] = folder end
  end
  table.sort(folders)

  local items = {}
  for _, folder in ipairs(folders) do
    local rule = Settings.project(settings, folder)
    items[#items + 1] = {
      title = folder,
      checked = rule.mute == true,
      fn = function()
        -- `false` clears the rule; see Settings.setProject.
        Settings.setProject(settings, folder, { mute = not rule.mute })
      end,
    }
  end
  if #items == 0 then items[1] = { title = "no projects yet", disabled = true } end
  return items
end

local function hushMenu()
  return {
    { title = "Quiet hours", checked = settings.hush,
      fn = function() Settings.toggle(settings, "hush") end },
    { title = "   from " .. string.format("%02d:00", settings.hushFrom or 22),
      fn = function()
        settings.hushFrom = ((settings.hushFrom or 22) + 1) % 24
        Settings.save(settings)
      end },
    { title = "   until " .. string.format("%02d:00", settings.hushTo or 8),
      fn = function()
        settings.hushTo = ((settings.hushTo or 8) + 1) % 24
        Settings.save(settings)
      end },
    { title = "   silence only, still show notes", checked = settings.hushSoftly,
      fn = function() Settings.toggle(settings, "hushSoftly") end },
    { title = "-" },
    { title = "Also silent while screen sharing", disabled = true },
  }
end

local function awayMenu()
  return {
    { title = "Hold notes while I'm away", checked = settings.catchUp,
      fn = function() Settings.toggle(settings, "catchUp") end },
    { title = "-" },
    { title = "Away means…", disabled = true },
    { title = "   " .. AWAY_LABEL[0], checked = (settings.awayAfter or 0) == 0,
      fn = function() M.setAway(0) end },
    { title = "   " .. AWAY_LABEL[900], checked = settings.awayAfter == 900,
      fn = function() M.setAway(900) end },
    { title = "   " .. AWAY_LABEL[1800], checked = settings.awayAfter == 1800,
      fn = function() M.setAway(1800) end },
  }
end

--- The one menu, used by the menu bar item and by clicking the fox.
local function menu()
  local live, blocked = sessions:count(), sessions:waitingCount()

  local headline = "Nothing running"
  if blocked > 0 then
    headline = blocked .. (blocked == 1 and " waiting on you" or " waiting on you")
  elseif live > 0 then
    headline = live .. (live == 1 and " session running" or " sessions running")
  end

  return {
    { title = headline, menu = runningMenu() },
    { title = "Today  ⌃⌥⌘T", menu = reportMenu() },
    { title = "Recent sessions", menu = recentMenu() },
    { title = "-" },

    { title = fox:hidden() and "Show foxbot  ⌃⌥⌘F" or "Hide foxbot  ⌃⌥⌘F",
      fn = function() M.toggle() end },
    { title = "Mute everything", checked = settings.quiet,
      fn = function() Settings.toggle(settings, "quiet") end },
    { title = "Live progress notes", checked = settings.notes,
      fn = function() Settings.toggle(settings, "notes") end },
    { title = "Remind me about questions", checked = settings.remind,
      fn = function() Settings.toggle(settings, "remind") end },
    { title = "Show a note when a turn starts", checked = settings.noteStarts,
      fn = function() Settings.toggle(settings, "noteStarts") end },
    { title = "-" },

    { title = "Voice   " .. Voice.get(settings.voice).label, menu = voiceMenu() },
    { title = "Detail   " .. (settings.detail or "brief"), menu = detailMenu() },
    { title = "Sounds", menu = chimeMenu() },
    { title = "Quiet hours   " .. (settings.hush and Hush.window(settings) or "off"),
      menu = hushMenu() },
    { title = "When I'm away", menu = awayMenu() },
    { title = "Per project", menu = projectMenu() },
    { title = "Colours   " .. Palette.label(Palette.skin),
      fn = function() M.nextSkin() end },
    { title = "Sprite   " .. Coats.label(settings.coat), menu = coatMenu() },
    { title = "-" },

    { title = "Show me a note", fn = function() M.demo() end },
    { title = "Show me a question", fn = function() M.demoAsk() end },
    { title = "Reload", fn = function() hs.reload() end },
    { title = "Quit foxbot", fn = function() hs.application.get("Hammerspoon"):kill() end },
  }
end

--- The menu bar title carries the live count so status is readable even with
--- the fox hidden. Something blocked on you outranks something merely running.
function M.paintBar()
  if not bar then return end
  local live, blocked = sessions:count(), sessions:waitingCount()

  if blocked > 0 then
    bar:setTitle("?" .. blocked)
    bar:setTooltip(blocked .. " waiting on you")
  elseif live > 0 then
    bar:setTitle(tostring(live))
    bar:setTooltip(live .. " running")
  else
    bar:setTitle("")
    bar:setTooltip("Foxbot — nothing running")
  end
end

-- ----------------------------------------------------------------- controls

function M.toggle()
  if fox:hidden() then fox:show() else panel:clear() fox:hide() end
  Settings.save(settings)
end

function M.nextSkin()
  settings.skin = Palette.next()
  Settings.save(settings)
  panel:clear()
  fox:paintBadge()
  return settings.skin
end

function M.setAway(seconds)
  settings.awayAfter = seconds
  Settings.save(settings)
  if away then away.threshold = seconds end
end

function M.showReport()
  if bar then bar:popupMenu(hs.mouse.absolutePosition()) end
end

function M.state()
  local names = {}
  for _, event in ipairs(recent) do names[#names + 1] = event.session end
  return {
    hidden = fox:hidden(),
    mood = fox.mood,
    running = sessions:count(),
    waiting = sessions:waitingCount(),
    quiet = settings.quiet,
    hush = settings.hush and Hush.window(settings) or "off",
    presenting = Hush.presenting() or false,
    away = away and away:isAway() or false,
    held = away and away:count() or 0,
    notes = panel:count(),
    ledger = #ledger.rows,
    editor = Focus.editorLabel(),
    at = { x = fox.x, y = fox.y },
    recent = names,
  }
end

-- -------------------------------------------------------------------- demos

function M.demo(name)
  name = name or "foxbot"
  handle({ ts = os.time(), kind = "done", session = name,
           session_id = "demo-" .. name, folder = name, cwd = HOME, tty = "" })
end

function M.demoLines()
  handle({
    ts = os.time(), kind = "done", session = "payments-api",
    session_id = "demo-lines-" .. os.time(), folder = "payments-api",
    cwd = HOME, tty = "",
    lines = {
      "Split the payment handler into charge, refund and webhook modules",
      "Added retry with backoff around the provider call",
      "17 tests passing, 2 skipped pending sandbox credentials",
      "Left to do: decide whether refunds are idempotent by request id",
      "Dev server still up on localhost:3000",
      "Nothing committed yet",
    },
  })
end

function M.demoAsk()
  handle({
    ts = os.time(), kind = "ask", session = "landing-page",
    session_id = "demo-ask-" .. os.time(), folder = "landing-page",
    cwd = HOME, tty = "",
    hint = "Which stack should I build it in?  (1 of 3)",
    lines = { "Next.js + Tailwind (recommended)", "Vite + React",
              "One HTML file", "then: Brand", "then: Deploy target" },
  })
end

-- -------------------------------------------------------------------- start

--- Set Hammerspoon's own preferences once, so nothing needs clicking and no
--- scripting bridge is left switched on. `prepared` is a real persisted key —
--- if it were dropped on save this would re-run on every launch and keep
--- turning launch-at-login back on for people who had turned it off.
local function prepare()
  if settings.prepared then return end
  hs.autoLaunch(true)
  hs.dockIcon(false)
  hs.menuIcon(true)
  settings.prepared = true
  Settings.save(settings)
end

local function start()
  settings = Settings.load()
  Palette.use(settings.skin or "dusk")
  prepare()

  hs.fs.mkdir(DEN)
  readTo = fileSize(INBOX)      -- only ever announce things that happen live

  sessions = Sessions.new()
  ledger = History.new(LEDGER, settings.keepDays):load()

  fox = Sprite.new({
    settings = settings,
    onTap = function()
      if bar then bar:popupMenu(hs.mouse.absolutePosition()) end
    end,
    onMoved = function()
      Settings.save(settings)
      panel:anchorTo(fox:frame(), fox:screen())
    end,
  })
  if not fox then return end

  fox.onFrame = function() fox:settle(restingMood) end

  panel = Panel.new()
  panel:anchorTo(fox:frame(), fox:screen())

  bar = hs.menubar.new()
  local icon = hs.image.imageFromPath(Coats.path(settings.coat))
  if icon then bar:setIcon(icon:setSize({ w = 20, h = 16 }), false) end
  bar:setMenu(menu)
  M.paintBar()

  away = Away.new({ threshold = settings.awayAfter, onReturn = catchUp })

  watcher = hs.pathwatcher.new(DEN, function()
    for _, event in ipairs(drain()) do handle(event) end
  end):start()

  keys = {
    hs.hotkey.bind(TOGGLE_KEY[1], TOGGLE_KEY[2], function() M.toggle() end),
    hs.hotkey.bind(REPORT_KEY[1], REPORT_KEY[2], function() M.showReport() end),
  }

  -- Safety net for a coalesced filesystem event, plus the housekeeping that
  -- retires sessions which never reported finishing.
  M.pulse = hs.timer.doEvery(3, function()
    for _, event in ipairs(drain()) do handle(event) end
    away:check()

    if settings.remind then
      for _, row in ipairs(sessions:overdue()) do chase(row) end
    end

    if sessions:sweep() > 0 then
      refeel()
      M.paintBar()
    end
  end)
end

start()

return M
