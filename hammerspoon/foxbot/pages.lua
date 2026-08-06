--- Every page of the control panel.
---
--- Pulled out of init.lua, which had grown to a thousand lines with the page
--- builders making up half of it. These are pure functions of an injected
--- context: they read state and return rows, they never reach for a global and
--- never perform an action themselves. That makes the whole menu testable
--- without a canvas.
---
--- The shape of it: you open this panel for one of three reasons, in steeply
--- descending order of frequency — to see what's happening, to make it stop,
--- and to change how it behaves. So the two most-read rows ARE the navigation
--- (the status line opens what's running, the stats strip opens the numbers),
--- the one control you reach for in irritation sits right under them, and
--- everything else is configuration behind a single door.

local Pages = {}
Pages.__index = Pages

-- Nothing may render past the bottom of a laptop screen. The old home page was
-- 903px on a 1440x900 Mac, so Reload and Quit were drawn off the edge and could
-- not be clicked at all.
Pages.MAX_HOME = 380
Pages.MAX_PAGE = 720

-- How many rows a list page will show before it says "and N more".
Pages.CAP = { blocked = 5, running = 6, earlier = 12, where = 5, projects = 12 }

Pages.PAUSE_FOR = 30 * 60      -- how long "Paused" lasts

local LEVELS = { "everything", "silent", "paused" }
local LEVEL_LABEL = { everything = "Everything", silent = "Silent", paused = "Paused" }
local LEVEL_NOTE = {
  everything = "notes and sounds",
  silent = "notes, but no sound",
  paused = "nothing at all for half an hour",
}

Pages.LEVELS, Pages.LEVEL_LABEL, Pages.LEVEL_NOTE = LEVELS, LEVEL_LABEL, LEVEL_NOTE

--- Which of the three the user is currently in.
function Pages.level(settings, now)
  now = now or os.time()
  if (settings.pauseUntil or 0) > now then return "paused" end
  if settings.quiet then return "silent" end
  return "everything"
end

function Pages.new(ctx)
  return setmetatable({ ctx = ctx }, Pages)
end

local function sep() return { kind = "sep" } end
local function back() return { kind = "back", title = "‹  Back" } end

-- ------------------------------------------------------------------ header

--- The status line. Doubles as the door to what's running.
function Pages:statusRow(tappable)
  local c = self.ctx
  local waiting, running = c.sessions:waitingCount(), c.sessions:count()
  local mood = c.restingMood()

  local title, detail
  if waiting > 0 then
    title = waiting == 1 and "1 session needs you" or (waiting .. " sessions need you")
    local first = c.sessions:blocked()[1]
    detail = first and ("blocked " .. (c.Sessions.duration(first.elapsed) or "")) or nil
  elseif running > 0 then
    title = running == 1 and "1 session running" or (running .. " sessions running")
    local longest = c.sessions:list()[1]
    detail = longest and (longest.session .. " · "
                          .. (c.Sessions.duration(longest.elapsed) or "")) or nil
  else
    title = "Nothing running"
    detail = c.Mood.get(mood).label:lower()
  end

  local row = { kind = "status", title = title, detail = detail,
                tone = c.Mood.get(mood).badge }
  if tappable then row.page = function() return self:now() end end
  return row
end

--- Today in three figures. Doubles as the door to the numbers.
function Pages:statsRow(tappable)
  local c = self.ctx
  local today = c.Stats.summarise(c.ledger.rows, c.Stats.startOfDay())
  local row = {
    kind = "stats",
    items = {
      { label = "turns",  value = tostring(today.turns) },
      { label = "worked", value = c.Stats.human(today.seconds) },
      { label = "tokens", value = c.Stats.tokens(today.tokens + today.subTokens) or "—" },
    },
  }
  if tappable then row.page = function() return self:den() end end
  return row
end

-- -------------------------------------------------------------------- home

function Pages:home()
  local c = self.ctx
  local level = Pages.level(c.settings)

  local rows = {
    self:statusRow(true),
    sep(),
    self:statsRow(true),
    sep(),
    {
      kind = "segment",
      options = LEVELS,
      labels = LEVEL_LABEL,
      on = level,
      note = LEVEL_NOTE[level],
      act = function(id) c.act.setLevel(id) end,
    },
    sep(),
    self:focusRow(),
    { kind = "into", title = "Settings", page = function() return self:settings() end },
    sep(),
    { kind = "row",
      title = c.fox:hidden() and "Show foxbot" or "Hide foxbot",
      keys = "⌃⌥⌘F", act = c.act.toggleFox },
  }

  -- While the tour is running it gets its own two rows here, so the panel
  -- itself can carry it forward or call it off.
  for _, row in ipairs(c.tourRows and c.tourRows() or {}) do
    rows[#rows + 1] = row
  end
  return rows
end

--- The focus timer, as one row that changes shape depending on what it's doing.
function Pages:focusRow()
  local c = self.ctx
  local clock = c.clock and c.clock()
  if not clock then
    return { kind = "row", title = "Focus timer", tone = "faded" }
  end

  if clock:running() then
    return { kind = "into",
      title = clock:kind() == c.Timer.WORK and "Focusing" or "On a break",
      value = clock:clock(),
      page = function() return self:focus() end }
  end

  local done = clock:doneToday(c.Stats.startOfDay())
  return { kind = "row", title = "Start a focus block",
    value = done > 0 and (done .. " today") or nil,
    act = function() c.act.startFocus(c.Timer.WORK) end }
end

function Pages:focus()
  local c = self.ctx
  local clock = c.clock()
  return {
    { kind = "label",
      title = clock:kind() == c.Timer.WORK and "Focusing" or "On a break" },
    { kind = "row", title = "Left", value = clock:clock() },
    { kind = "row", title = "Give it five more",
      act = function() c.act.extendFocus() end },
    { kind = "row", title = "Stop", tone = "broken",
      act = function() c.act.stopFocus() end },
    sep(),
    { kind = "row", tone = "faded",
      title = "Blocks today: " .. clock:doneToday(c.Stats.startOfDay()) },
    sep(),
    back(),
  }
end

-- --------------------------------------------------------------- what's on

function Pages:now()
  local c = self.ctx
  local rows = { self:statusRow(false), sep() }

  local blocked = c.sessions:blocked()
  if #blocked > 0 then
    rows[#rows + 1] = { kind = "label", title = "Waiting on you" }
    for i, row in ipairs(blocked) do
      if i > Pages.CAP.blocked then
        rows[#rows + 1] = { kind = "row", tone = "faded",
          title = "…and " .. (#blocked - Pages.CAP.blocked) .. " more" }
        break
      end
      rows[#rows + 1] = {
        kind = "row", title = row.session, tone = "asking",
        value = c.Sessions.duration(row.elapsed),
        -- Only the one that has been waiting longest shows what it's asking.
        -- A note on every row is fifteen points each, and with a full house
        -- that pushed this page past the bottom of a laptop screen.
        note = (i == 1 and row.hint and row.hint ~= "") and row.hint or nil,
        act = function() c.act.focus(row.tty, row.app) end,
      }
    end
    rows[#rows + 1] = sep()
  end

  local live = c.sessions:list()
  rows[#rows + 1] = { kind = "label", title = "Running" }
  if #live == 0 then
    rows[#rows + 1] = { kind = "row", title = "Nothing right now", tone = "faded" }
  end
  for i, row in ipairs(live) do
    if i > Pages.CAP.running then
      rows[#rows + 1] = { kind = "row", tone = "faded",
        title = "…and " .. (#live - Pages.CAP.running) .. " more" }
      break
    end
    rows[#rows + 1] = {
      kind = "row", title = row.session, tone = "running",
      value = c.Sessions.duration(row.elapsed),
      act = function() c.act.focus(row.tty, row.app) end,
    }
  end

  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "into", title = "Earlier sessions",
                      value = tostring(#c.recent()),
                      page = function() return self:earlier() end }
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:den()
  local c = self.ctx
  local today = c.Stats.summarise(c.ledger.rows, c.Stats.startOfDay())
  local week = c.Stats.summarise(c.ledger.rows,
                                 c.Stats.startOfDay(os.time() - 6 * 86400))
  local streak = c.Stats.streak(c.ledger.rows)

  local rows = { self:statsRow(false), sep(), { kind = "label", title = "Where it went" } }

  local ranked = c.Stats.ranked(today, Pages.CAP.where)
  if #ranked == 0 then
    rows[#rows + 1] = { kind = "row", title = "Nothing today yet", tone = "faded" }
  end
  for _, bucket in ipairs(ranked) do
    local spent = c.Stats.tokens(bucket.tokens)
    rows[#rows + 1] = {
      kind = "row", title = bucket.folder,
      value = c.Stats.human(bucket.seconds) .. (spent and ("  " .. spent) or ""),
    }
  end

  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "label", title = "Longer view" }
  rows[#rows + 1] = { kind = "row", title = "This week",
    value = week.turns .. " turns · " .. c.Stats.human(week.seconds) }
  if streak > 1 then
    rows[#rows + 1] = { kind = "row", title = "Streak", tone = "settled",
                        value = streak .. " days" }
  end

  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:earlier()
  local c = self.ctx
  local rows = { { kind = "label", title = "Earlier sessions" } }
  local seen, shown = {}, 0

  for _, event in ipairs(c.recent()) do
    seen[c.keyOf(event)] = true
    shown = shown + 1
    rows[#rows + 1] = {
      kind = "row", title = event.session, value = os.date("%H:%M", event.ts),
      act = function() c.act.focus(event.tty, event.app) end,
    }
    if shown >= Pages.CAP.earlier then break end
  end

  if shown < Pages.CAP.earlier then
    for _, row in ipairs(c.ledger:recent(Pages.CAP.earlier)) do
      local key = row.session_id or row.session
      if not seen[key] then
        seen[key] = true
        shown = shown + 1
        rows[#rows + 1] = {
          kind = "row", title = row.session, value = os.date("%H:%M", row.ts),
          act = function() c.act.reveal(row.cwd) end,
        }
        if shown >= Pages.CAP.earlier then break end
      end
    end
  end

  if shown == 0 then
    rows[#rows + 1] = { kind = "row", title = "Nothing yet", tone = "faded" }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

-- ---------------------------------------------------------------- settings

function Pages:settings()
  local c = self.ctx
  local s = c.settings

  local muted = 0
  for _ in pairs(s.perProject or {}) do muted = muted + 1 end

  return {
    { kind = "label", title = "Interruptions" },
    { kind = "into", title = "How much he speaks up",
      value = c.chatty.LABEL[s.chatty or "normal"],
      page = function() return self:chatter() end },
    { kind = "toggle", title = "Chase unanswered questions", on = s.remind,
      note = "again at 1m, 5m, 15m",
      act = function() c.act.toggle("remind") end },
    { kind = "into", title = "Quiet hours",
      value = s.hush and c.Hush.window(s) or "off",
      page = function() return self:hush() end },
    { kind = "into", title = "When you're away",
      value = c.awayLabel[s.awayAfter or 0],
      page = function() return self:away() end },
    { kind = "into", title = "Per project",
      value = muted > 0 and (muted .. " muted") or "none",
      page = function() return self:projects() end },
    { kind = "into", title = "Attention",
      value = s.drift and "watching" or "off",
      page = function() return self:attention() end },
    sep(),

    { kind = "into", title = "Notes",
      value = c.Voice.get(s.voice).label .. ", " .. (s.detail or "brief"),
      page = function() return self:notes() end },
    sep(),

    { kind = "label", title = "Look" },
    { kind = "into", title = "Sprite", value = c.Coats.label(s.coat),
      page = function() return self:sprite() end },
    { kind = "segment",
      options = c.Palette.order,
      labels = c.Palette.label,
      on = c.Palette.skin,
      note = "the panel and the notes",
      act = function(id) c.act.setSkin(id) end },
    sep(),

    { kind = "label", title = "Foxbot" },
    { kind = "into", title = "About & help", page = function() return self:about() end },
    { kind = "row", title = "Quit foxbot", tone = "broken", act = c.act.quit },
    sep(),
    back(),
  }
end

function Pages:chatter()
  local c = self.ctx
  local rows = { { kind = "label", title = "How much he speaks up" } }
  for _, level in ipairs(c.chatty.LEVELS) do
    rows[#rows + 1] = {
      kind = "choice", title = c.chatty.LABEL[level],
      on = (c.settings.chatty or "normal") == level,
      note = c.chatty.NOTE[level],
      act = function() c.act.setChatty(level) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "row", tone = "faded",
    title = "A turn starting or a session closing" }
  rows[#rows + 1] = { kind = "row", tone = "faded",
    title = "never makes a note, at any setting" }
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:hush()
  local c, s = self.ctx, self.ctx.settings
  return {
    { kind = "label", title = "Quiet hours" },
    { kind = "toggle", title = "Keep quiet overnight", on = s.hush,
      note = "he keeps tracking, he just stops interrupting",
      act = function() c.act.toggle("hush") end },
    { kind = "stepper", title = "Starts", value = string.format("%02d:00", s.hushFrom or 22),
      act = function() c.act.bump("hushFrom", 24) end },
    { kind = "stepper", title = "Ends", value = string.format("%02d:00", s.hushTo or 8),
      act = function() c.act.bump("hushTo", 24) end },
    { kind = "toggle", title = "Silence only", on = s.hushSoftly,
      note = "notes still appear, they just make no sound",
      act = function() c.act.toggle("hushSoftly") end },
    sep(),
    { kind = "label", title = "When he sleeps" },
    { kind = "stepper", title = "Curls up at",
      value = string.format("%02d:00", s.sleepFrom or 23),
      act = function() c.act.bump("sleepFrom", 24) end },
    { kind = "stepper", title = "Wakes at",
      value = string.format("%02d:00", s.sleepTo or 6),
      act = function() c.act.bump("sleepTo", 24) end },
    sep(),
    { kind = "row", tone = "faded", title = "Always silent while screen sharing" },
    sep(),
    back(),
  }
end

function Pages:away()
  local c, s = self.ctx, self.ctx.settings
  local current = s.awayAfter or 0
  local rows = {
    { kind = "label", title = "When you're not here" },
    { kind = "toggle", title = "Hold notes until I'm back", on = s.catchUp,
      note = "one summary instead of a stack of stale ones",
      act = function() c.act.toggle("catchUp") end },
    sep(),
    { kind = "label", title = "Away means" },
  }
  for _, seconds in ipairs(c.awaySteps) do
    rows[#rows + 1] = {
      kind = "choice", title = c.awayLabel[seconds], on = current == seconds,
      note = seconds == 0 and "exact — the screen is off, you're not reading"
             or (seconds == 1800 and "a guess — watching a long turn looks like idling"
                 or nil),
      act = function() c.act.setAway(seconds) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

--- How a note reads and sounds.
---
--- These were four rows on the settings page until settings grew past the
--- height it is allowed to be. They belong together anyway: all four are about
--- the note itself rather than about when one appears.
function Pages:notes()
  local c, s = self.ctx, self.ctx.settings
  return {
    { kind = "label", title = "Notes" },
    { kind = "into", title = "Voice", value = c.Voice.get(s.voice).label,
      page = function() return self:voice() end },
    { kind = "into", title = "Detail", value = s.detail or "brief",
      page = function() return self:detail() end },
    { kind = "toggle", title = "Type them out", on = s.typing ~= false,
      note = "letter by letter, click to skip",
      act = function() c.act.toggle("typing") end },
    { kind = "into", title = "Sounds", page = function() return self:sounds() end },
    sep(),
    back(),
  }
end

--- Noticing you've drifted, and teaching you things.
---
--- Both live here because they're the two places he speaks without an event
--- having happened, and anyone who dislikes one probably wants to find the
--- other quickly.
function Pages:attention()
  local c, s = self.ctx, self.ctx.settings
  local minutes = math.floor((s.driftAfter or 300) / 60)
  local app = c.frontApp and c.frontApp() or nil

  local rows = {
    { kind = "label", title = "When you wander off" },
    { kind = "toggle", title = "Say something", on = s.drift,
      note = "only if a block is running or a session is blocked",
      act = function() c.act.toggle("drift") end },
    { kind = "stepper", title = "After", value = minutes .. " min",
      act = function() c.act.stepDrift() end },
  }

  -- The list of what counts as a break is editable without typing: whatever
  -- you were in before you opened this menu is offered as a row. Asking
  -- someone to enter a bundle identifier would mean nobody ever changed it.
  if app then
    rows[#rows + 1] = sep()
    rows[#rows + 1] = { kind = "label", title = "Counts as a break" }
    rows[#rows + 1] = {
      kind = "toggle", title = app, on = c.isBreak and c.isBreak(app) or false,
      note = "he can see which app, never what's in it",
      act = function() c.act.markBreak(app) end,
    }
  end

  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "label", title = "Telling you things" }
  rows[#rows + 1] = {
    kind = "toggle", title = "One a day, after a focus block", on = s.lore ~= false,
    note = "shipped with him — nothing is fetched",
    act = function() c.act.toggle("lore") end,
  }
  rows[#rows + 1] = {
    kind = "row", title = "Tell me something now",
    act = function() c.act.tellMe() end,
  }

  -- The only switch in the whole panel that causes anything to leave the
  -- machine, so it says what it sends rather than making you go and read the
  -- source to find out.
  local remote = c.remote and c.remote() or nil
  if remote then
    rows[#rows + 1] = {
      kind = "toggle", title = "Fresh tips", on = s.fresh,
      note = remote.ready and remote.sends or "needs a key in ~/.claude/foxbot/groq.key",
      act = function() c.act.toggle("fresh") end,
    }
  end

  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:projects()
  local c, s = self.ctx, self.ctx.settings
  local seen, folders = {}, {}

  for _, row in ipairs(c.ledger:recent(40)) do
    if row.folder and row.folder ~= "" and not seen[row.folder] then
      seen[row.folder] = true
      folders[#folders + 1] = row.folder
    end
  end
  for folder in pairs(s.perProject or {}) do
    if not seen[folder] then seen[folder] = true folders[#folders + 1] = folder end
  end
  table.sort(folders)

  local rows = { { kind = "label", title = "Mute a noisy project" } }
  if #folders == 0 then
    rows[#rows + 1] = { kind = "row", title = "No projects yet", tone = "faded" }
  end
  for i, folder in ipairs(folders) do
    if i > Pages.CAP.projects then
      rows[#rows + 1] = { kind = "row", tone = "faded",
        title = "…and " .. (#folders - Pages.CAP.projects) .. " more" }
      break
    end
    local rule = c.Settings.project(s, folder)
    rows[#rows + 1] = {
      kind = "toggle", title = folder, on = rule.mute == true,
      act = function() c.act.muteProject(folder, not rule.mute) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:voice()
  local c = self.ctx
  local rows = { { kind = "label", title = "How he says it" } }
  for _, name in ipairs(c.Voice.order) do
    local voice = c.Voice.get(name)
    rows[#rows + 1] = {
      kind = "choice", title = voice.label, on = c.settings.voice == name,
      note = "“" .. c.Voice.sample(name, "done") .. "”",
      act = function() c.act.setVoice(name) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:detail()
  local c = self.ctx
  local rows = { { kind = "label", title = "How much of a finished turn" } }
  for _, option in ipairs(c.detailOptions) do
    rows[#rows + 1] = {
      kind = "choice", title = option.label, on = c.settings.detail == option.id,
      note = option.note,
      act = function() c.act.setDetail(option.id) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:sounds()
  local c = self.ctx
  local rows = { { kind = "label", title = "A sound per event" } }
  for _, event in ipairs(c.chimeEvents) do
    rows[#rows + 1] = {
      kind = "into", title = event.label, value = c.Chime.label(c.chimeFor(event.kind)),
      page = function() return self:soundPick(event) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "row", title = "Add your own…",
    note = "drop audio in the folder, then reload", act = c.act.revealSounds }
  rows[#rows + 1] = back()
  return rows
end

function Pages:soundPick(event)
  local c = self.ctx
  local rows = { { kind = "label", title = event.label } }
  for _, choice in ipairs(c.Chime.choices()) do
    rows[#rows + 1] = {
      kind = "choice", title = choice.label,
      on = c.chimeFor(event.kind) == choice.id,
      act = function() c.act.setChime(event.kind, choice.id) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:sprite()
  local c = self.ctx
  local rows = { { kind = "label", title = "Sprite" } }
  for _, coat in ipairs(c.Coats.all(c.Mood.order)) do
    rows[#rows + 1] = {
      kind = "choice", title = coat.label,
      on = (c.settings.coat or c.Coats.default) == coat.id,
      act = function() c.act.setCoat(coat.id) end,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "into", title = "Moods with their own art",
    value = #c.Coats.moods(c.settings.coat, c.Mood.order) .. "/" .. #c.Mood.order,
    page = function() return self:wardrobe() end }
  rows[#rows + 1] = { kind = "row", title = "Add your own…", act = c.act.revealCoats }
  rows[#rows + 1] = sep()
  rows[#rows + 1] = back()
  return rows
end

function Pages:wardrobe()
  local c = self.ctx
  local has = {}
  for _, mood in ipairs(c.Coats.moods(c.settings.coat, c.Mood.order)) do has[mood] = true end

  local rows = { { kind = "label",
                   title = "Drawings for " .. c.Coats.label(c.settings.coat) } }
  for _, mood in ipairs(c.Mood.order) do
    local art = c.Mood.art(mood)
    rows[#rows + 1] = {
      kind = "row", title = c.Mood.get(mood).label,
      value = has[art] and "own art" or "default",
      tone = has[art] and "settled" or nil,
    }
  end
  rows[#rows + 1] = sep()
  rows[#rows + 1] = { kind = "row", title = "Add drawings…",
    note = "name them " .. (c.settings.coat or "foxbot") .. "-sleeping.png, and so on",
    act = c.act.revealCoats }
  rows[#rows + 1] = back()
  return rows
end

function Pages:about()
  local c = self.ctx
  return {
    { kind = "label", title = "Foxbot" },
    { kind = "row", title = "Show me a note", act = c.act.demo },
    { kind = "row", title = "Show me a question", act = c.act.demoAsk },
    { kind = "row", title = "Show me around again", act = c.act.tour },
    sep(),
    { kind = "row", title = "Today's numbers", keys = "⌃⌥⌘T" },
    { kind = "row", title = "Hide and show", keys = "⌃⌥⌘F" },
    sep(),
    { kind = "row", title = "Reload", act = c.act.reload },
    sep(),
    back(),
  }
end

return Pages
