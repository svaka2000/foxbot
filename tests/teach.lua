--- The first-run tour.
---
--- Every rule here is about not being annoying, so every rule gets a test:
--- it runs once, it gives up rather than nagging, an observed action skips its
--- own lesson, a real question outranks it, and there is no path that leaves it
--- looping forever.

local t = require("tests.support")
local check, ok = t.check, t.ok

local Teach = require("foxbot.teach")

--- A tour wired to stubs, plus the world it can see.
local function world(over)
  over = over or {}
  local w = {
    said = {},                 -- every note it posted
    saved = 0,
    settings = over.settings or { taught = 0, taughtTries = 0 },
    hidden = false, away = false, waiting = 0, menuOpen = false,
    notes = 0, may = true, opened = 0, samples = 0,
  }

  w.teach = Teach.new({
    settings = w.settings,
    save = function() w.saved = w.saved + 1 end,
    panel = {
      say = function(note) w.said[#w.said + 1] = note return note end,
      count = function() return w.notes end,
    },
    fox = { hidden = function() return w.hidden end, startle = function() end },
    board = { isOpen = function() return w.menuOpen end },
    openMenu = function() w.opened = w.opened + 1 end,
    mayShow = function() return w.may end,
    isAway = function() return w.away end,
    waiting = function() return w.waiting end,
    sample = function() w.samples = w.samples + 1 end,
  })

  --- Poll until it starts, or give up.
  function w:settle(times)
    for _ = 1, times or 4 do self.teach:tick() end
  end
  function w:last() return self.said[#self.said] end
  function w:press(label)
    local note = self:last()
    for _, chip in ipairs(note and note.chips or {}) do
      if chip.label:find(label, 1, true) then chip.act() return true end
    end
    return false
  end
  return w
end

-- --------------------------------------------------------------- it starts

do
  local w = world()
  w.teach:tick()
  check("it doesn't pounce on the first tick", #w.said, 0)

  w:settle(2)
  check("it greets you once things settle", #w.said, 1)
  check("with the hello card", w:last().title, "hello")
  check("and counts the attempt", w.settings.taughtTries, 1)
  ok("it is running", w.teach:running())
end

-- ------------------------------------------------------------- it runs once

do
  local w = world({ settings = { taught = Teach.VERSION, taughtTries = 0 } })
  w:settle(6)
  check("someone who has seen it is left alone", #w.said, 0)
  ok("and it is done, not idling", not w.teach:running())
end

do
  -- taught = 0 is the never-seen value, and 0 is TRUTHY in Lua. Reading it as
  -- a boolean would silently skip the tour for everybody.
  local w = world({ settings = { taught = 0, taughtTries = 0 } })
  w:settle(3)
  ok("taught = 0 still means never seen", #w.said > 0)
end

-- --------------------------------------------------------- it gives up

do
  local w = world({ settings = { taught = 0, taughtTries = Teach.MAX_STARTS } })
  w:settle(5)
  check("after enough unfinished starts it stops offering", #w.said, 0)
  ok("without marking itself as seen", (w.settings.taught or 0) < Teach.VERSION)
end

do
  local w = world()
  w:settle(3)
  for _ = 1, Teach.MAX_EXPIRY do
    local note = w:last()
    w.teach:gone("expired")
    if w.teach:running() then w.teach:tick() end
  end
  ok("cards that time out unread end the tour", not w.teach:running())
end

-- ------------------------------------------------- an action skips its lesson

do
  local w = world()
  w:settle(3)
  check("on hello", w.teach:stepName(), "hello")

  -- Dragging him during the first card means the drag lesson is pointless.
  w.teach:saw("dragged")
  check("dragging skips the drag card", w.teach:stepName(), "click")
  ok("and says so", (w:last().body or ""):find("already found") ~= nil)

  w.teach:saw("menu.open")
  check("opening the menu skips that one too", w.teach:stepName(), "signals")
end

do
  -- Doing a LATER lesson early banks it, but doesn't skip the ones in between
  -- — you still haven't been shown those. It just never gets taught twice.
  local w = world()
  w:settle(3)
  w.teach:saw("menu.open")
  check("it carries on with what you haven't seen", w.teach:stepName(), "drag")

  ok("moving on from drag", w:press("fine there"))
  check("skips the lesson you already did", w.teach:stepName(), "signals")

  -- And doing it again changes nothing.
  w.teach:saw("menu.open")
  check("a repeat of a banked action is inert", w.teach:stepName(), "signals")
end

-- ---------------------------------------------------- a question outranks it

do
  local w = world()
  w:settle(3)
  ok("running before the question", w.teach.state == "running")

  w.waiting = 1
  w.teach:standDown()
  check("it steps aside", w.teach.state, "waiting")

  w.teach:tick()
  check("and stays aside while you're blocked", w.teach.state, "waiting")

  w.waiting = 0
  w.teach:tick()
  check("then picks up where it left off", w.teach.state, "running")
  check("on the same card", w.teach:stepName(), "hello")
end

do
  -- It should never appear over a screen share, while away, or when hidden.
  for _, hide in ipairs({ "hidden", "away" }) do
    local w = world()
    w[hide] = true
    w:settle(5)
    check("it stays quiet when " .. hide, #w.said, 0)
  end

  local w = world()
  w.may = false
  w:settle(5)
  check("it stays quiet while presenting", #w.said, 0)

  local busy = world()
  busy.notes = 2
  busy:settle(5)
  check("it waits for the screen to be clear", #busy.said, 0)
end

-- ------------------------------------------------------------ walking it

do
  local w = world()
  w:settle(3)
  ok("hello has a way out", w:press("no thanks"))
  ok("declining ends it", not w.teach:running())
  ok("and it does not come back", (w.settings.taught or 0) >= Teach.VERSION)
end

do
  local w = world()
  w:settle(3)

  ok("start", w:press("go on"))
  check("to drag", w.teach:stepName(), "drag")
  ok("next", w:press("fine there"))
  check("to click", w.teach:stepName(), "click")

  ok("open it for me", w:press("open it"))
  check("opened the panel", w.opened, 1)
  check("to signals", w.teach:stepName(), "signals")

  ok("a sample can be requested", w:press("show me one"))
  check("which shows one", w.samples, 1)
  check("without moving on", w.teach:stepName(), "signals")

  ok("got it", w:press("got it"))
  check("to the last card", w.teach:stepName(), "quiet")

  ok("thanks", w:press("thanks"))
  ok("finished", not w.teach:running())
  ok("marked as seen", (w.settings.taught or 0) >= Teach.VERSION)
  check("and says goodbye", w:last().title, "foxbot")
end

do
  -- The cross means "go away", not "next".
  local w = world()
  w:settle(3)
  w.teach:gone("cross")
  ok("the cross ends it", not w.teach:running())
  ok("for good", (w.settings.taught or 0) >= Teach.VERSION)
end

-- ------------------------------------------------------------- asking again

do
  local w = world({ settings = { taught = Teach.VERSION, taughtTries = 9 } })
  w:settle(4)
  check("it stays away on its own", #w.said, 0)

  w.teach:begin(true)
  ok("but comes back when asked", w.teach:running())
  check("from the beginning", w.teach:stepName(), "hello")
  check("without burning another try", w.settings.taughtTries, 9)
end

-- -------------------------------------------------------------- menu rows

do
  local w = world()
  check("no tour rows when it isn't running", #w.teach:menuRows(), 0)
  w:settle(3)
  ok("rows appear while it runs", #w.teach:menuRows() > 0)

  for _, row in ipairs(w.teach:menuRows()) do
    if row.title and row.title:find("stop showing") then row.act() end
  end
  ok("and one of them calls it off", not w.teach:running())
end

-- Every card the order references must exist and be answerable.
do
  local missing = {}
  for _, id in ipairs(Teach.order) do
    local card = Teach.cards[id]
    if not card or not card.title or not card.body then
      missing[#missing + 1] = id
    elseif id ~= "quiet" and not card.chips then
      missing[#missing + 1] = id .. " (no way forward)"
    end
  end
  check("every step has a card", #missing, 0)
  ok("and a farewell exists", Teach.cards.farewell ~= nil)
end

return true
