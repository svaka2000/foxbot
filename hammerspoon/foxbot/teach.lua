--- Showing someone around, once.
---
--- A new install is a fox on the edge of the screen and no explanation. This
--- walks through the four things you can't guess: he's draggable, he's
--- clickable, the ring means something, and he can be told to be quiet.
---
--- The whole module takes its dependencies as plain tables of functions, so it
--- can be driven entirely from a test with no canvas, no timers and no `hs`.
---
--- Robustness is the point, so the rules are:
---   * An observed action satisfies its own step wherever you are. Drag him
---     during the first card and the drag card is skipped, not repeated at you.
---   * A real question always wins. If a session needs you mid-tour he stands
---     down and picks up afterwards.
---   * Nothing is ever assumed from a timer. Every step advances because
---     something actually happened.
---   * It gives up. Three unfinished starts, or two cards that expired unread,
---     and it stops offering rather than greeting you forever.

local Teach = {}
Teach.__index = Teach

Teach.VERSION = 1        -- bump to show a new tour to existing installs
Teach.MAX_STARTS = 3     -- unfinished auto-starts before it stops offering
Teach.MAX_EXPIRY = 2     -- cards that timed out unread before it gives up
Teach.SETTLE_TICKS = 2   -- how many polls to wait before greeting anyone

Teach.order = { "hello", "drag", "click", "signals", "quiet" }

local SKIPPED = "(you already found that one)"

Teach.cards = {
  hello = {
    title = "hello",
    body = "I watch your Claude Code sessions and tell you when one finishes"
        .. " — or gets stuck waiting on you.\n\nMind if I show you around?"
        .. " It takes about thirty seconds.",
    chips = { { id = "start", label = "go on then" },
              { id = "stop", label = "no thanks" } },
    hold = 45,
  },
  drag = {
    title = "first thing",
    body = "You can pick me up. Click and hold anywhere on me and put me"
        .. " wherever suits — I'll stay there, and I'll remember.",
    chips = { { id = "next", label = "he's fine there" },
              { id = "stop", label = "stop the tour" } },
    hold = 60,
  },
  click = {
    title = "second thing",
    body = "Click me — one click, no holding — and my control panel opens."
        .. " Everything lives in there.",
    chips = { { id = "open", label = "open it for me" },
              { id = "stop", label = "stop the tour" } },
    hold = 60,
  },
  signals = {
    title = "what the colours mean",
    body = "The dot on my shoulder is the short version:",
    lines = {
      "blue — a session is working",
      "amber — one is waiting on YOU, and I'll keep saying so",
      "green — one just finished",
    },
    chips = { { id = "sample", label = "show me one" },
              { id = "next", label = "got it" } },
    hold = 60,
  },
  quiet = {
    title = "last thing",
    body = "If I'm ever too much: open the panel and hit Silent, or Paused"
        .. " for half an hour. There's a dial in Settings for how much I say"
        .. " at all.\n\nThat's everything.",
    chips = { { id = "finish", label = "thanks" } },
    hold = 60,
  },
  farewell = {
    title = "foxbot",
    body = "I'll get out of your way. Open the panel any time — there's a"
        .. " 'show me around again' in there if you want this back.",
    hold = 12,
  },
}

--- @param deps table  every field optional; the defaults are inert so a test
---   can build one with two stubs.
function Teach.new(deps)
  deps = deps or {}
  local self = setmetatable({}, Teach)

  self.settings = deps.settings or {}
  self.save = deps.save or function() end
  self.panel = deps.panel or {}
  self.fox = deps.fox or {}
  self.board = deps.board or {}
  self.openMenu = deps.openMenu or function() end
  self.mayShow = deps.mayShow or function() return true end
  self.isAway = deps.isAway or function() return false end
  self.waiting = deps.waiting or function() return 0 end
  self.sample = deps.sample or function() end

  self.state = "idle"
  self.step = nil
  self.ticks = 0
  self.expiries = 0
  self.done = {}          -- steps satisfied by watching rather than telling
  return self
end

function Teach:running()
  return self.state == "running" or self.state == "waiting"
end

function Teach:stepName()
  return self:running() and self.step or nil
end

--- Is now a reasonable moment to put a tutorial card on screen?
function Teach:canShow()
  if self.fox.hidden and self.fox.hidden() then return false end
  if self.isAway() then return false end
  if self.waiting() > 0 then return false end     -- a real question outranks us
  if not self.mayShow() then return false end     -- presenting, quiet hours
  return true
end

function Teach:canStart()
  if not self:canShow() then return false end
  if self.board.isOpen and self.board.isOpen() then return false end
  if self.panel.count and self.panel.count() > 0 then return false end
  return true
end

-- ------------------------------------------------------------------- cards

function Teach:build(id, opts)
  local card = Teach.cards[id]
  if not card then return nil end

  local body = card.body
  if opts and opts.skipped then body = SKIPPED .. "\n\n" .. body end

  local chips = {}
  for _, chip in ipairs(card.chips or {}) do
    chips[#chips + 1] = {
      label = chip.label,
      act = function() self:chose(chip.id) end,
    }
  end

  return {
    title = card.title,
    body = body,
    lines = card.lines,
    chips = chips,
    hold = card.hold,
    teaching = id,
    -- Clicking the body of a tutorial card means "yes, next" rather than
    -- "take me to a terminal".
    onOpen = function() self:chose("next") end,
    onGone = function(why) self:gone(why) end,
  }
end

function Teach:show(id, opts)
  if not self:canShow() then
    self.state = "waiting"
    self.step = id
    return
  end
  local note = self:build(id, opts)
  if not note then return end

  self.state = "running"
  self.step = id
  self.card = self.panel.say and self.panel.say(note) or nil
  if self.fox.startle then self.fox.startle() end
end

-- ---------------------------------------------------------------- progress

local function indexOf(id)
  for i, name in ipairs(Teach.order) do
    if name == id then return i end
  end
  return nil
end

--- The next step that hasn't already been satisfied by watching.
function Teach:nextStep(after)
  local at = indexOf(after) or 0
  for i = at + 1, #Teach.order do
    local id = Teach.order[i]
    if not self.done[id] then return id end
  end
  return nil
end

function Teach:advance(skipped)
  local next_ = self:nextStep(self.step)
  if not next_ then return self:stop("finished") end
  self:show(next_, { skipped = skipped })
end

--- Something the user actually did. Satisfies that step wherever we are.
function Teach:saw(signal)
  local step = ({ dragged = "drag", ["menu.open"] = "click" })[signal]
  if not step then return false end

  local first = not self.done[step]
  self.done[step] = true
  if not self:running() then return false end

  -- Only jump the queue if they've just proved the step we were on, or one
  -- still ahead of us.
  local here, theirs = indexOf(self.step), indexOf(step)
  if here and theirs and theirs >= here then
    self:advance(first and step ~= self.step)
    return true
  end
  return false
end

function Teach:chose(id)
  if not self:running() then return end

  if id == "stop" then return self:stop("dismissed") end
  if id == "finish" then return self:stop("finished") end

  if id == "open" then
    self.openMenu()
    self.done.click = true
    return self:advance()
  end

  if id == "sample" then
    self.sample()
    return                                   -- stay on this card
  end

  self:advance()
end

--- The card left the screen without being answered.
function Teach:gone(why)
  if not self:running() then return end
  if why == "answered" then return end

  if why == "cross" then return self:stop("dismissed") end

  self.expiries = self.expiries + 1
  if self.expiries >= Teach.MAX_EXPIRY then return self:stop("ignored") end

  -- Hold the step and try again when the moment is better.
  self.state = "waiting"
end

--- A real question arrived. Get off the screen.
function Teach:standDown()
  if self.state == "running" then self.state = "waiting" end
end

-- ------------------------------------------------------------------ driving

--- Called once per poll.
function Teach:tick()
  if self.state == "done" then return end

  if self.state == "waiting" then
    if self:canShow() and self:canStart() then self:show(self.step) end
    return
  end

  if self.state ~= "idle" then return end

  if (self.settings.taught or 0) >= Teach.VERSION then
    self.state = "done"
    return
  end
  if (self.settings.taughtTries or 0) >= Teach.MAX_STARTS then
    return self:stop("ignored")
  end

  -- Let things settle before greeting anyone: Hammerspoon has only just
  -- started and the screen may still be assembling itself.
  self.ticks = self.ticks + 1
  if self.ticks < Teach.SETTLE_TICKS then return end
  if not self:canStart() then return end

  self:begin(false)
end

function Teach:begin(manual)
  if not manual then
    self.settings.taughtTries = (self.settings.taughtTries or 0) + 1
    self.save(self.settings)
  else
    -- Asked for deliberately: forget the history and run it properly.
    self.done = {}
    self.expiries = 0
  end
  self.state = "running"
  self:show("hello")
end

function Teach:stop(why)
  self.state = "done"
  self.step = nil

  -- "Finished" and "dismissed" are both decisions — don't ask again. Being
  -- ignored is not a decision, so that one only burns a try.
  if why ~= "ignored" then
    self.settings.taught = Teach.VERSION
    self.save(self.settings)
  end

  if why == "finished" and self.panel.say then
    self.panel.say(self:build("farewell"))
  end
  return why
end

--- Rows to splice into the control panel while the tour is running.
function Teach:menuRows()
  if not self:running() then return {} end
  return {
    { kind = "sep" },
    { kind = "row", title = "Tour · carry on", tone = "settled",
      act = function() self:chose("next") end },
    { kind = "row", title = "Tour · stop showing me this", tone = "faded",
      act = function() self:stop("dismissed") end },
  }
end

return Teach
