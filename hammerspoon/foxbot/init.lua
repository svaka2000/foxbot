--- Foxbot — a fox who watches your Claude Code sessions.
---
--- Claude Code's hooks append events to ~/.claude/foxbot/inbox.jsonl. This
--- module tails that file, keeps track of what is running and what is blocked
--- on you, puts notes on screen, and writes finished turns to a ledger so the
--- numbers survive a restart.
---
--- The control panel is drawn rather than an AppKit menu, because a system menu
--- can't carry a live status header, real switches, a strip of today's numbers,
--- or the fox's own colours — and those are most of what makes it useful.

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
local Board    = require("foxbot.menu")

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


-- Which event kinds are allowed to put something on screen, per chatter level.
-- `busy` and `end` appear nowhere on purpose.
local SPEAKS_UP = {
  needed = { ask = true, idle = true, nudge = true, error = true },
  normal = { ask = true, idle = true, nudge = true, error = true, done = true },
  chatty = { ask = true, idle = true, nudge = true, error = true, done = true,
             step = true },
}
local CHATTY_LEVELS = { "needed", "normal", "chatty" }
local CHATTY_LABEL = {
  needed = "only when needed",
  normal = "normal",
  chatty = "chatty",
}
local CHATTY_NOTE = {
  needed = "questions and failures only",
  normal = "and when a turn finishes",
  chatty = "and what he's doing as he does it",
}

-- What counts as being away.
local AWAY_STEPS = { 0, 900, 1800 }
local AWAY_LABEL = { [0] = "locked or asleep", [900] = "15 min idle", [1800] = "30 min idle" }

local settings, fox, panel, board, bar, watcher, keys
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

--- What he settles into when nothing momentary is happening.
---
--- Everything fed in here is a real signal: what's running, how long the
--- longest turn has been going, whether anything is blocked on you, whether
--- you're at the machine, the time of day, and how much work has gone through
--- today. Mood.settle decides the order.
local moodAt, moodWas = 0, "resting"

local function restingMood()
  -- Recomputed at most every few seconds: this walks the ledger, and it is now
  -- called on a timer rather than only when something happens. `moodAt` is
  -- reset whenever an event lands, so it is never stale when it matters.
  local now = os.time()
  if now - moodAt < 3 then return moodWas end

  local longest = 0
  for _, row in ipairs(sessions:list()) do
    longest = math.max(longest, row.elapsed or 0)
  end

  local hour = tonumber(os.date("%H"))
  local today = Stats.summarise(ledger.rows, Stats.startOfDay())

  moodAt, moodWas = now, Mood.settle({
    waiting = sessions:waitingCount(),
    running = sessions:count(),
    longestRun = longest,
    away = away and away:isAway() or false,
    nightTime = Hush.within(hour, settings.sleepFrom or 23, settings.sleepTo or 6),
    workedToday = today.seconds,
  })
  return moodWas
end


local function refeel(kind)
  if not fox then return end
  moodAt = 0                              -- something happened; recompute
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

--- Is this event worth putting on screen at all?
local function worthSaying(kind)
  local allowed = SPEAKS_UP[settings.chatty] or SPEAKS_UP.normal
  return allowed[kind] == true
end

--- Put a note on screen for a finished / asking event.
local function announce(event, elapsed)
  remember(event)

  -- Everything is still tracked, counted and remembered. This only decides
  -- whether it interrupts.
  if not worthSaying(event.kind) then return end

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
  if not worthSaying("step") then return end
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
    -- You've just walked back to the machine; don't make you watch a summary
    -- of what you missed type itself out.
    instant = true,
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

  -- Every twenty-five turns in a day, he's pleased with himself. Briefly.
  if kind == "done" then
    local today = Stats.summarise(ledger.rows, Stats.startOfDay())
    if today.turns > 0 and today.turns % 25 == 0 then
      fox:feel("cheering", restingMood())
    end
  end

  M.paintBar()
  announce(event, elapsed)
end

-- ------------------------------------------------------------------- menus

local home        -- forward declaration; sub-pages link back to it
local chatterPage

local function backRow()
  return { kind = "back", title = "‹  Back" }
end

--- The header: what he is doing, in a sentence, with a dot the right colour.
local function statusRow()
  local waiting, running = sessions:waitingCount(), sessions:count()
  local mood = restingMood()

  local title, detail
  if waiting > 0 then
    title = waiting == 1 and "1 session needs you" or (waiting .. " sessions need you")
    local first = sessions:blocked()[1]
    detail = first and ("blocked " .. (Sessions.duration(first.elapsed) or "")) or nil
  elseif running > 0 then
    title = running == 1 and "1 session running" or (running .. " sessions running")
    local longest = sessions:list()[1]
    detail = longest and (longest.session .. " · " .. (Sessions.duration(longest.elapsed) or "")) or nil
  else
    title = "Nothing running"
    detail = Mood.get(mood).label:lower()
  end

  return { kind = "status", title = title, detail = detail,
           tone = Mood.get(mood).badge }
end

--- Today, in three figures.
local function statsRow()
  local today = Stats.summarise(ledger.rows, Stats.startOfDay())
  return {
    kind = "stats",
    items = {
      { label = "turns",  value = tostring(today.turns) },
      { label = "worked", value = Stats.human(today.seconds) },
      { label = "tokens", value = Stats.tokens(today.tokens + today.subTokens) or "—" },
    },
  }
end

local function runningPage()
  local rows = { statusRow(), { kind = "sep" } }

  local blocked = sessions:blocked()
  if #blocked > 0 then
    rows[#rows + 1] = { kind = "label", title = "Waiting on you" }
    for _, row in ipairs(blocked) do
      rows[#rows + 1] = {
        kind = "row", title = row.session, tone = "asking",
        value = Sessions.duration(row.elapsed),
        note = (row.hint ~= "" and row.hint) or nil,
        act = function() Focus.terminal(row.tty, row.app) end,
      }
    end
    rows[#rows + 1] = { kind = "sep" }
  end

  local live = sessions:list()
  rows[#rows + 1] = { kind = "label", title = "Running" }
  if #live == 0 then
    rows[#rows + 1] = { kind = "row", title = "Nothing right now", tone = "faded" }
  end
  for _, row in ipairs(live) do
    rows[#rows + 1] = {
      kind = "row", title = row.session, tone = "running",
      value = Sessions.duration(row.elapsed),
      act = function() Focus.terminal(row.tty, row.app) end,
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

local function reportPage()
  local today = Stats.summarise(ledger.rows, Stats.startOfDay())
  local week = Stats.summarise(ledger.rows, Stats.startOfDay(os.time() - 6 * 86400))
  local streak = Stats.streak(ledger.rows)

  local rows = { statsRow(), { kind = "sep" }, { kind = "label", title = "Where it went" } }

  local ranked = Stats.ranked(today, 5)
  if #ranked == 0 then
    rows[#rows + 1] = { kind = "row", title = "Nothing today yet", tone = "faded" }
  end
  for _, bucket in ipairs(ranked) do
    rows[#rows + 1] = {
      kind = "row", title = bucket.folder,
      value = Stats.human(bucket.seconds) ..
              (Stats.tokens(bucket.tokens) and ("  " .. Stats.tokens(bucket.tokens)) or ""),
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { kind = "label", title = "Longer view" }
  rows[#rows + 1] = { kind = "row", title = "This week",
                      value = week.turns .. " turns · " .. Stats.human(week.seconds) }
  if streak > 1 then
    rows[#rows + 1] = { kind = "row", title = "Streak", tone = "settled",
                        value = streak .. " days" }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

local function recentPage()
  local rows = { { kind = "label", title = "Recent sessions" } }
  local seen = {}

  for _, event in ipairs(recent) do
    seen[keyOf(event)] = true
    rows[#rows + 1] = {
      kind = "row", title = event.session, value = os.date("%H:%M", event.ts),
      act = function() Focus.terminal(event.tty, event.app) end,
    }
  end
  for _, row in ipairs(ledger:recent(RECALL)) do
    local key = row.session_id or row.session
    if not seen[key] then
      seen[key] = true
      rows[#rows + 1] = {
        kind = "row", title = row.session, value = os.date("%H:%M", row.ts),
        act = function() Focus.reveal(row.cwd) end,
      }
    end
  end
  if #rows == 1 then
    rows[#rows + 1] = { kind = "row", title = "Nothing yet", tone = "faded" }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

local function voicePage()
  local rows = { { kind = "label", title = "How he says it" } }
  for _, name in ipairs(Voice.order) do
    local voice = Voice.get(name)
    rows[#rows + 1] = {
      kind = "choice", title = voice.label, on = settings.voice == name,
      note = "“" .. Voice.sample(name, "done") .. "”",
      act = function()
        settings.voice = name
        Settings.save(settings)
        M.demo()
      end,
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

local function detailPage()
  local rows = { { kind = "label", title = "How much of a finished turn" } }
  for _, option in ipairs(DETAIL) do
    rows[#rows + 1] = {
      kind = "choice", title = option.label, on = settings.detail == option.id,
      note = option.note,
      act = function()
        settings.detail = option.id
        Settings.save(settings)
        M.demoLines()
      end,
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

local function soundPickPage(event)
  return function()
    local rows = { { kind = "label", title = event.label } }
    for _, choice in ipairs(Chime.choices()) do
      rows[#rows + 1] = {
        kind = "choice", title = choice.label,
        on = chimeFor(event.kind) == choice.id,
        act = function()
          settings.chimes = settings.chimes or {}
          settings.chimes[event.kind] = choice.id
          Settings.save(settings)
          Chime.play(choice.id)
        end,
      }
    end
    rows[#rows + 1] = { kind = "sep" }
    rows[#rows + 1] = backRow()
    return rows
  end
end

local function soundsPage()
  local rows = { { kind = "label", title = "A sound per event" } }
  for _, event in ipairs(CHIME_EVENTS) do
    rows[#rows + 1] = {
      kind = "into", title = event.label,
      value = Chime.label(chimeFor(event.kind)),
      page = soundPickPage(event),
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = {
    kind = "row", title = "Add your own…",
    note = "drop audio in the folder, then reload",
    act = function() Chime.reveal() end,
  }
  rows[#rows + 1] = backRow()
  return rows
end

--- One dial for how much he interrupts.
function chatterPage()
  local rows = { { kind = "label", title = "How much he speaks up" } }
  for _, level in ipairs(CHATTY_LEVELS) do
    rows[#rows + 1] = {
      kind = "choice", title = CHATTY_LABEL[level],
      on = (settings.chatty or "normal") == level,
      note = CHATTY_NOTE[level],
      act = function()
        settings.chatty = level
        Settings.save(settings)
      end,
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { kind = "row", tone = "faded",
    title = "He never announces a turn starting" }
  rows[#rows + 1] = { kind = "row", tone = "faded",
    title = "or a session closing, at any setting" }
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

local function hushPage()
  local rows = {
    { kind = "label", title = "Quiet hours" },
    { kind = "toggle", title = "Keep quiet overnight", on = settings.hush,
      note = "he keeps tracking, he just stops interrupting",
      act = function() Settings.toggle(settings, "hush") end },
    { kind = "row", title = "Starts", value = string.format("%02d:00", settings.hushFrom or 22),
      act = function()
        settings.hushFrom = ((settings.hushFrom or 22) + 1) % 24
        Settings.save(settings)
      end },
    { kind = "row", title = "Ends", value = string.format("%02d:00", settings.hushTo or 8),
      act = function()
        settings.hushTo = ((settings.hushTo or 8) + 1) % 24
        Settings.save(settings)
      end },
    { kind = "toggle", title = "Silence only", on = settings.hushSoftly,
      note = "notes still appear, they just make no sound",
      act = function() Settings.toggle(settings, "hushSoftly") end },
    { kind = "sep" },
    { kind = "label", title = "When he sleeps" },
    { kind = "row", title = "Curls up at",
      value = string.format("%02d:00", settings.sleepFrom or 23),
      act = function()
        settings.sleepFrom = ((settings.sleepFrom or 23) + 1) % 24
        Settings.save(settings)
      end },
    { kind = "row", title = "Wakes at",
      value = string.format("%02d:00", settings.sleepTo or 6),
      act = function()
        settings.sleepTo = ((settings.sleepTo or 6) + 1) % 24
        Settings.save(settings)
      end },
    { kind = "sep" },
    { kind = "row", title = "Always silent while screen sharing", tone = "faded" },
    { kind = "sep" },
    backRow(),
  }
  return rows
end

local function awayPage()
  local current = settings.awayAfter or 0
  return {
    { kind = "label", title = "When you're not here" },
    { kind = "toggle", title = "Hold notes until I'm back", on = settings.catchUp,
      note = "one summary instead of a stack of stale ones",
      act = function() Settings.toggle(settings, "catchUp") end },
    { kind = "sep" },
    { kind = "label", title = "Away means" },
    { kind = "choice", title = AWAY_LABEL[0], on = current == 0,
      note = "exact — the screen is off, you're definitely not reading",
      act = function() M.setAway(0) end },
    { kind = "choice", title = AWAY_LABEL[900], on = current == 900,
      act = function() M.setAway(900) end },
    { kind = "choice", title = AWAY_LABEL[1800], on = current == 1800,
      note = "a guess — watching a long turn looks like idling",
      act = function() M.setAway(1800) end },
    { kind = "sep" },
    backRow(),
  }
end

local function projectsPage()
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

  local rows = { { kind = "label", title = "Mute a noisy project" } }
  if #folders == 0 then
    rows[#rows + 1] = { kind = "row", title = "No projects yet", tone = "faded" }
  end
  for _, folder in ipairs(folders) do
    local rule = Settings.project(settings, folder)
    rows[#rows + 1] = {
      kind = "toggle", title = folder, on = rule.mute == true,
      -- `false` clears the rule; see Settings.setProject.
      act = function() Settings.setProject(settings, folder, { mute = not rule.mute }) end,
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

--- Which moods the chosen coat actually has a drawing for.
local function wardrobePage()
  local has = {}
  for _, mood in ipairs(Coats.moods(settings.coat, Mood.order)) do has[mood] = true end

  local rows = {
    { kind = "label", title = "Drawings for " .. Coats.label(settings.coat) },
  }
  for _, mood in ipairs(Mood.order) do
    local art = Mood.art(mood)
    rows[#rows + 1] = {
      kind = "row", title = Mood.get(mood).label,
      value = has[art] and "own art" or "default",
      tone = has[art] and "settled" or nil,
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = {
    kind = "row", title = "Add drawings…",
    note = "name them " .. (settings.coat or "foxbot") .. "-sleeping.png, and so on",
    act = function() Coats.reveal() end,
  }
  rows[#rows + 1] = backRow()
  return rows
end

local function coatPage()
  local rows = { { kind = "label", title = "Sprite" } }
  for _, coat in ipairs(Coats.all(Mood.order)) do
    rows[#rows + 1] = {
      kind = "choice", title = coat.label,
      on = (settings.coat or Coats.default) == coat.id,
      act = function()
        settings.coat = coat.id
        Settings.save(settings)
        hs.reload()          -- the sprite set is loaded once, at start
      end,
    }
  end
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { kind = "into", title = "Moods with their own art",
                      value = #Coats.moods(settings.coat, Mood.order) .. "/" .. #Mood.order,
                      page = wardrobePage }
  rows[#rows + 1] = { kind = "row", title = "Add your own…",
                      act = function() Coats.reveal() end }
  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = backRow()
  return rows
end

--- The page you land on.
function home()
  return {
    statusRow(),
    { kind = "sep" },
    statsRow(),
    { kind = "sep" },

    { kind = "into", title = "Sessions", page = runningPage,
      value = sessions:count() > 0 and tostring(sessions:count()) or nil },
    { kind = "into", title = "Today", page = reportPage },
    { kind = "into", title = "Recent", page = recentPage },
    { kind = "sep" },

    { kind = "label", title = "Interruptions" },
    { kind = "into", title = "How much he speaks up", page = chatterPage,
      value = CHATTY_LABEL[settings.chatty or "normal"] },
    { kind = "toggle", title = "Chase unanswered questions", on = settings.remind,
      note = "again at 1m, 5m, 15m",
      act = function() Settings.toggle(settings, "remind") end },
    { kind = "toggle", title = "Mute everything", on = settings.quiet,
      act = function() Settings.toggle(settings, "quiet") end },
    { kind = "into", title = "Quiet hours", page = hushPage,
      value = settings.hush and Hush.window(settings) or "off" },
    { kind = "into", title = "When you're away", page = awayPage,
      value = AWAY_LABEL[settings.awayAfter or 0] },
    { kind = "into", title = "Per project", page = projectsPage },
    { kind = "sep" },

    { kind = "label", title = "Appearance" },
    { kind = "into", title = "Voice", page = voicePage,
      value = Voice.get(settings.voice).label },
    { kind = "into", title = "Detail", page = detailPage,
      value = (settings.detail or "brief") },
    { kind = "into", title = "Sounds", page = soundsPage },
    { kind = "into", title = "Sprite", page = coatPage,
      value = Coats.label(settings.coat) },
    { kind = "row", title = "Colours", value = Palette.label(Palette.skin),
      act = function() M.nextSkin() end },
    { kind = "sep" },

    { kind = "row", title = fox:hidden() and "Show foxbot" or "Hide foxbot",
      keys = "⌃⌥⌘F", act = function() M.toggle() end },
    { kind = "row", title = "Show me a note", act = function() M.demo() end },
    { kind = "row", title = "Show me a question", act = function() M.demoAsk() end },
    { kind = "row", title = "Reload", act = function() hs.reload() end },
    { kind = "row", title = "Quit foxbot", tone = "broken",
      act = function() hs.application.get("Hammerspoon"):kill() end },
  }
end

--- Open the panel wherever it was asked for.
function M.openMenu(at)
  if panel then panel:anchorTo(fox:frame(), fox:screen()) end
  if board:isOpen() then board:close() return end
  board:open(home(), at or hs.mouse.absolutePosition(), fox:screen())
  board:showing(home)
end

--- The menu bar carries the live count, so status is readable with the fox
--- hidden. Something blocked on you outranks something merely running.
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
    bar:setTooltip("Foxbot — " .. Mood.get(restingMood()).label:lower())
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
  M.openMenu({ x = fox.x, y = fox.y })
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
    onTap = function() M.openMenu() end,
    onMoved = function()
      Settings.save(settings)
      panel:anchorTo(fox:frame(), fox:screen())
    end,
  })
  if not fox then return end


  board = Board.new()
  panel = Panel.new()
  panel:anchorTo(fox:frame(), fox:screen())

  bar = hs.menubar.new()
  local icon = hs.image.imageFromPath(Coats.path(settings.coat))
  if icon then bar:setIcon(icon:setSize({ w = 20, h = 16 }), false) end
  bar:setClickCallback(function() M.openMenu() end)
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

    -- Ambient moods — asleep, dozing, worn out — arrive because time passes,
    -- not because anything happened, so he has to be asked.
    fox:settle(restingMood)

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
