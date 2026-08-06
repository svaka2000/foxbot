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
local Pages    = require("foxbot.pages")
local Teach    = require("foxbot.teach")
local Timer    = require("foxbot.timer")
local Lore     = require("foxbot.lore")
local Drift    = require("foxbot.drift")
local Remote   = require("foxbot.remote")
local Wallet   = require("foxbot.wallet")
local Shop     = require("foxbot.shop")

local M = {}

local HOME = os.getenv("HOME")
local DEN = HOME .. "/.claude/foxbot"
local INBOX = DEN .. "/inbox.jsonl"
local LEDGER = DEN .. "/ledger.jsonl"
local WALLET = DEN .. "/wallet.json"

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

local settings, fox, panel, board, bar, watcher, keys, teach, clock
local lore, drift, purse
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

function M.setSkin(id)
  settings.skin = Palette.use(id)
  Settings.save(settings)
  panel:clear()
  if fox then fox:paintBadge() end
end

function M.setCoat(id)
  settings.coat = id
  Settings.save(settings)
  -- The sprite set is loaded once at start, so this needs a reload. Delayed a
  -- moment so that whatever note said "yours" is actually readable first.
  hs.timer.doAfter(2.5, function() hs.reload() end)
end

--- What he's called. Bought from the shop; until then he's Foxbot.
function M.name()
  local given = settings.nickname
  return (given and given ~= "") and given or "foxbot"
end

function M.rename()
  local ok, pressed, given = pcall(hs.dialog.textPrompt,
    "What should he be called?",
    "It shows up wherever his name does.",
    M.name(), "Save", "Cancel")
  if not ok then return end

  -- textPrompt returns the button AND the text, and it returns the text
  -- whichever button you pressed. Discarding the button meant Cancel renamed
  -- him anyway.
  if pressed ~= "Save" then return end

  given = (given or ""):gsub("^%s+", ""):gsub("%s+$", "")
  -- Counted in characters, not bytes: "Reynard the Magnificent" is 23 either
  -- way, but a name in Japanese would be rejected at eight.
  local length = utf8.len(given) or 0
  -- A blank name would leave rows reading "Hide ". Empty means "back to
  -- Foxbot" rather than "no name".
  settings.nickname = (given ~= "" and length <= 24) and given or ""
  Settings.save(settings)
end

--- Buy something from the shop, and put it on straight away.
---
--- Equipping immediately rather than leaving it in an inventory is deliberate:
--- the thing you just spent three days earning should be visible the instant
--- you pay for it, not two menus later.
function M.buy(id)
  local function refuse(why)
    panel:anchorTo(fox:frame(), fox:screen())
    panel:say({ title = "Couldn't buy that", body = why,
                instant = true, hold = 10 })
  end

  if not purse then return refuse("His wallet isn't open yet.") end

  local item = Shop.find(id, (function()
    local have = {}
    for _, coat in ipairs(Coats.all(Mood.order)) do have[coat.id] = true end
    return have
  end)())
  if not item then return refuse("That isn't on the shelf any more.") end

  local bought, why = purse:buy(id, item.price)
  if not bought then
    return refuse(why == "unsaved"
      and "His wallet couldn't be written to, so nothing was taken."
      or "You can't afford that yet.")
  end

  -- Equipping runs other people's code paths -- a palette, a sound map, a
  -- reload. If any of it throws after the debit, you have paid for something
  -- you did not get, so the purchase is undone rather than left half done.
  local equipped = pcall(Shop.equip, id, {
    palette = function(name) M.setSkin(name) end,
    sounds = function(map)
      local chimes = settings.chimes or {}
      for kind, sound in pairs(map) do chimes[kind] = sound end
      settings.chimes = chimes
      Settings.save(settings)
    end,
    coat = function(name) M.setCoat(name) end,
    rename = function() M.rename() end,
  })

  if not equipped then
    purse.balance = purse.balance + item.price
    purse.owned[id] = nil
    purse:save()
    return refuse("Something went wrong putting it on. You've been refunded.")
  end

  fox:feel("pleased", restingMood())
  fox:startle()
  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = item.label,
    body = "Yours. " .. purse.balance .. " donuts left.",
    instant = true,
    hold = 12,
  })
  M.paintBar()
end

--- Show one thing he knows.
local function tellNote(item, volunteered)
  -- Asking for one is a request, and a request is answered even at "only when
  -- needed". Volunteering is interrupting, and M.tellMe gated that before it
  -- got as far as here.
  local silence = Hush.check(settings)

  if not silence and volunteered then Chime.play(chimeFor("nudge")) end
  fox:feel("pleased", restingMood())
  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = item.title,
    body = item.text,
    chips = {
      { label = "another", act = function() M.tellMe(false) end },
    },
  })
end

--- Tell you something. Asked for from the menu, or volunteered once a day.
---
--- The shipped pack is the answer. The hosted model is an optional garnish on
--- top of it, and it is arranged so that every possible failure — no key, the
--- switch off, no network, a retired model, a reply that came back as three
--- paragraphs of markdown — lands on the pack rather than on an error. There
--- is nothing to go wrong from where you are sitting.
function M.tellMe(volunteered)
  -- Checked here, not in tellNote. A volunteered tip that is going to be
  -- suppressed must not send a request on the way to being suppressed --
  -- being hushed should mean nothing happens, not that it happens quietly.
  if volunteered then
    local _, show = Hush.check(settings)
    if not show or fox:hidden() then return end
  end

  local function fromPack()
    local item = lore and lore:pick()
    if item then tellNote(item, volunteered) end
  end

  if not settings.fresh or not Remote.available() then return fromPack() end

  local folder = (recent[1] or {}).cwd
  local languages = Remote.languages(folder)
  if #languages == 0 then return fromPack() end

  Remote.tip(languages, function(text)
    if not text then return fromPack() end
    tellNote({ tag = "fresh", text = text,
               title = "About " .. languages[1] }, volunteered)
  end)
end

--- Notice you've been somewhere else for a while with something still waiting.
---
--- Phrased as an observation rather than an instruction. "You've been in
--- Discord for twelve minutes" is a fact he can see; "get back to work" is a
--- judgement he has no standing to make, and it is the reason most tools like
--- this get turned off within a day.
local function noticeDrift(why)
  local silence, show = Hush.check(settings)
  if not show or fox:hidden() then return end

  local been = Sessions.duration(why.been) or "a while"
  local waiting = (why.blocked > 0)
    and (why.blocked == 1 and "one session is waiting on you"
                          or (why.blocked .. " sessions are waiting on you"))
    or "your focus block is still running"

  if not silence then Chime.play(chimeFor("nudge")) end
  fox:feel("asking", restingMood())
  panel:anchorTo(fox:frame(), fox:screen())
  panel:say({
    title = why.app,
    body = been .. " here, and " .. waiting .. ".",
    chips = {
      { label = "on purpose", act = function()
          -- Not a snooze: you're telling him this app was never a break.
          drift:mark(why.app, false)
        end },
      { label = "thanks", act = function() end },
    },
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
    -- A real question outranks a tutorial card.
    if teach then teach:standDown() end
  else
    sessions:answered(event)
  end

  local elapsed
  -- Read before finish() clears the waiting row: the quick-answer bonus needs
  -- to know when he *started* waiting, and finishing the turn forgets it.
  local askedAt = sessions:askedAt(keyOf(event))
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

    -- Donuts. Only for a turn that finished -- an error is not work you get
    -- paid for, and paying for one would reward leaving something broken.
    if purse and kind == "done" then
      purse:credit({
        tokens = (event.tokens or 0) + (event.subTokens or 0),
        at = event.ts or now,
        askedAt = askedAt,
        -- Read after the append above, so today is already counted.
        streak = Stats.streak(ledger.rows),
      }, Stats.startOfDay())
    end
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
--
-- The pages themselves live in pages.lua, as pure functions of the context
-- assembled here. This file used to carry all fifteen of them and had grown
-- past a thousand lines because of it.

local pages     -- built in start(), once settings and the ledger exist

local function buildPages()
  return Pages.new({
    settings = settings,
    sessions = sessions,
    ledger = ledger,
    recent = function() return recent end,
    fox = fox,
    keyOf = keyOf,
    restingMood = restingMood,
    chimeFor = chimeFor,

    Settings = Settings, Sessions = Sessions, Stats = Stats, Voice = Voice,
    Chime = Chime, Coats = Coats, Mood = Mood, Hush = Hush, Palette = Palette,

    chatty = { LEVELS = CHATTY_LEVELS, LABEL = CHATTY_LABEL, NOTE = CHATTY_NOTE },
    awaySteps = AWAY_STEPS,
    awayLabel = AWAY_LABEL,
    detailOptions = DETAIL,
    chimeEvents = CHIME_EVENTS,

    -- Every action the menu can take. Pages never do anything themselves.
    tourRows = function() return teach and teach:menuRows() or {} end,
    clock = function() return clock end,
    Timer = Timer,

    -- The app you were in before you opened the menu — his own window is
    -- ignored by the sampler, so this is still whatever you were actually
    -- doing.
    frontApp = function() return drift and drift.app or nil end,
    isBreak = function(app) return drift and drift:isBreak(app) or false end,

    wallet = function() return purse end,
    name = function() return M.name() end,
    shopAisles = function()
      local have = {}
      for _, coat in ipairs(Coats.all(Mood.order)) do
        have[coat.id] = true
      end
      return Shop.aisles(have)
    end,

    remote = function()
      -- No key means the row says so instead of what it would send, so there
      -- is nothing to walk a folder for. Which is almost everyone, almost
      -- always.
      if not Remote.available() then return { ready = false } end
      local folder = (recent[1] or {}).cwd
      return { ready = true, sends = Remote.describe(Remote.languages(folder)) }
    end,

    act = {
      toggle = function(name)
        Settings.toggle(settings, name)
        if name == "typing" then panel:types(settings.typing) end
      end,
      bump = function(name, wrap)
        settings[name] = ((settings[name] or 0) + 1) % wrap
        Settings.save(settings)
      end,
      setLevel = function(id) M.setLevel(id) end,
      stepDrift = function()
        -- 3, 5, 10, 15, 30 and round. Below three minutes it fires on a
        -- glance at a message, which is exactly the behaviour that makes
        -- these things insufferable.
        local steps = { 180, 300, 600, 900, 1800 }
        Settings.cycle(settings, "driftAfter", steps)
      end,
      markBreak = function(app)
        if drift then drift:mark(app, not drift:isBreak(app)) end
      end,
      tellMe = function() M.tellMe(false) end,
      buy = function(id) M.buy(id) end,
      startFocus = function(kind)
        clock:start(kind)
        M.paintBar()
      end,
      stopFocus = function()
        clock:stop()
        M.paintBar()
      end,
      extendFocus = function() clock:extend(300) M.paintBar() end,
      setChatty = function(id)
        settings.chatty = id
        Settings.save(settings)
      end,
      setSkin = function(id) M.setSkin(id) end,
      setVoice = function(name)
        settings.voice = name
        Settings.save(settings)
        M.demo()
      end,
      setDetail = function(id)
        settings.detail = id
        Settings.save(settings)
        M.demoLines()
      end,
      setAway = function(seconds) M.setAway(seconds) end,
      setChime = function(kind, id)
        settings.chimes = settings.chimes or {}
        settings.chimes[kind] = id
        Settings.save(settings)
        Chime.play(id)
      end,
      setCoat = function(id) M.setCoat(id) end,
      muteProject = function(folder, on)
        -- `false` clears the rule; see Settings.setProject.
        Settings.setProject(settings, folder, { mute = on })
      end,
      focus = function(tty, app) Focus.terminal(tty, app) end,
      reveal = function(cwd) Focus.reveal(cwd) end,
      revealSounds = function() Chime.reveal() end,
      revealCoats = function() Coats.reveal() end,
      toggleFox = function() M.toggle() end,
      demo = function() M.demo() end,
      demoAsk = function() M.demoAsk() end,
      tour = function() M.tour() end,
      reload = function() hs.reload() end,
      quit = function() hs.application.get("Hammerspoon"):kill() end,
    },
  })
end


function M.openMenu(at)
  if panel then panel:anchorTo(fox:frame(), fox:screen()) end
  if board:isOpen() then board:close() return end
  if teach then teach:saw("menu.open") end
  local home = function() return pages:home() end
  board:open(home(), at or hs.mouse.absolutePosition(), fox:screen())
  board:showing(home)
end

--- The three-way switch on the home page: everything, silent, or paused.
function M.setLevel(id)
  if id == "paused" then
    settings.pauseUntil = os.time() + Pages.PAUSE_FOR
  elseif id == "silent" then
    settings.pauseUntil = 0
    settings.quiet = true
  else
    settings.pauseUntil = 0
    settings.quiet = false
  end
  Settings.save(settings)
  M.paintBar()
end

--- The menu bar carries the live count, so status is readable with the fox
--- hidden. Something blocked on you outranks something merely running.
function M.paintBar()
  if not bar then return end
  local live, blocked = sessions:count(), sessions:waitingCount()

  -- A running block owns the menu bar: it's the one number you glance at.
  if clock and clock:running() then
    bar:setTitle(clock:clock())
    bar:setTooltip((clock:kind() == Timer.WORK and "focusing" or "on a break")
                   .. " — " .. (clock:clock() or ""))
    return
  end

  -- Paused is worth saying in the tooltip, so a silent fox never looks broken.
  local backIn = Hush.backIn(settings)
  if backIn then
    bar:setTitle("zz")
    bar:setTooltip("Foxbot — paused, " .. backIn)
    return
  end

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

--- Show someone around. Also reachable from the panel, for anyone who wants it
--- again or who waved it away the first time.
function M.tour()
  if not teach then return end
  panel:anchorTo(fox:frame(), fox:screen())
  teach:begin(true)
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

  -- Before the palette is applied. A bought palette is only in Palette.order
  -- once Shop.restore has put it there, and the saved skin may well be one --
  -- so restoring after applying leaves the settings page unable to show you
  -- the palette you are currently looking at.
  hs.fs.mkdir(DEN)
  purse = Wallet.new(WALLET):load()
  Shop.restore(purse.owned)

  Palette.use(settings.skin or "dusk")
  prepare()
  readTo = fileSize(INBOX)      -- only ever announce things that happen live

  sessions = Sessions.new()
  ledger = History.new(LEDGER, settings.keepDays):load()

  fox = Sprite.new({
    settings = settings,
    onTap = function() M.openMenu() end,
    onMoved = function()
      Settings.save(settings)
      panel:anchorTo(fox:frame(), fox:screen())
      if teach then teach:saw("dragged") end
    end,
  })
  if not fox then return end


  panel = Panel.new()
  panel:types(settings.typing)
  board = Board.new()
  clock = Timer.new({
    settings = settings,
    save = function(current) Settings.save(current) end,
    onFinish = function(ended, suggest)
      -- One note, one sound, and an offer. It never starts the next block by
      -- itself; a break you didn't ask for is the beginning of nagging.
      Chime.play(chimeFor("done"))
      fox:startle()
      panel:anchorTo(fox:frame(), fox:screen())
      panel:say({
        title = ended == Timer.WORK and "that's twenty-five" or "break's over",
        body = ended == Timer.WORK
               and "Nicely done. Take five?"
               or "Ready when you are.",
        instant = true,
        hold = 25,
        chips = {
          { label = suggest == Timer.REST and "take a break" or "start a block",
            act = function() clock:start(suggest) M.paintBar() end },
          { label = "not now", act = function() end },
        },
      })
      M.paintBar()

      -- The one behaviour worth paying for outright.
      if purse and ended == Timer.WORK then
        purse:finishedFocus(Stats.startOfDay())
      end

      -- The end of a work block is the one moment in the day he's certain you
      -- are stopping anyway, which makes it the only place worth volunteering
      -- something unprompted. Once a day, and never during the block itself.
      if settings.lore ~= false and ended == Timer.WORK and lore then
        local day = Stats.startOfDay()
        if not lore:offeredToday(day) then
          hs.timer.doAfter(2, function()
            -- Marked inside the callback and after the gate, so a tip that
            -- never appears does not use up the day's one offer.
            local _, show = Hush.check(settings)
            if not show or fox:hidden() then return end
            lore:markOffered(os.time())
            M.tellMe(true)
          end)
        end
      end
    end,
  })

  teach = Teach.new({
    settings = settings,
    save = function(current) Settings.save(current) end,
    panel = {
      say = function(note) return panel:say(note) end,
      count = function() return panel:count() end,
    },
    fox = {
      hidden = function() return fox:hidden() end,
      startle = function() fox:startle() end,
    },
    board = { isOpen = function() return board:isOpen() end },
    openMenu = function() M.openMenu() end,
    mayShow = function()
      local _, show = Hush.check(settings)
      return show
    end,
    isAway = function() return away and away:isAway() or false end,
    waiting = function() return sessions:waitingCount() end,
    sample = function() M.demo() end,
  })

  -- After everything it closes over exists.
  pages = buildPages()
  panel:anchorTo(fox:frame(), fox:screen())

  bar = hs.menubar.new()
  local icon = hs.image.imageFromPath(Coats.path(settings.coat))
  if icon then bar:setIcon(icon:setSize({ w = 20, h = 16 }), false) end
  bar:setClickCallback(function() M.openMenu() end)
  M.paintBar()

  away = Away.new({ threshold = settings.awayAfter, onReturn = catchUp })

  lore = Lore.new({
    settings = settings,
    save = function(current) Settings.save(current) end,
  })

  drift = Drift.new({
    settings = settings,
    save = function(current) Settings.save(current) end,
    frontmost = function()
      -- Identity only. The window *title* would say whether Chrome is on the
      -- docs or on Twitter, and it is behind Screen Recording, which also
      -- hands over every other window on the display. Not worth it.
      local app = hs.application.frontmostApplication()
      return app and app:name() or nil
    end,
  })

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

    if teach then teach:tick() end

    -- Where you are. Sampled every poll rather than on an app-switch watcher,
    -- because what matters is how long you have been somewhere, not that you
    -- went there.
    if drift then
      drift:sample()
      -- Never while he's meant to be leaving you alone, and never while you're
      -- away — a nudge nobody is there to read is one waiting to annoy you the
      -- moment you sit down.
      if not (away and away:isAway()) then
        local why = drift:should(os.time(), Stats.startOfDay(), {
          focus = clock and clock:kind() or nil,
          blocked = sessions:waitingCount(),
        })
        if why then
          -- Consumed whether or not it is shown. Otherwise hiding him, or
          -- quiet hours, leaves `should` true on every poll for hours, and the
          -- moment either lifts you get a nudge about something you have long
          -- since dealt with.
          drift:spoke(os.time())
          noticeDrift(why)
        end
      end
    end
    if clock then
      if clock:tick() then M.paintBar() end
      if clock:running() then M.paintBar() end
    end

    if sessions:sweep() > 0 then
      refeel()
      M.paintBar()
    end
  end)
end

start()

return M
