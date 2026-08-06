--- Tests for the one thing the panel must never do: become unopenable.
---
--- Everything else in Foxbot is a convenience. The panel is how you reach
--- Hide, Quit, and every setting — so if it stops opening, the only way back
--- is to know that reloading Hammerspoon fixes it, which nobody does.
---
--- It became unopenable for a specific reason. `open()` creates the canvas,
--- then paints every row into it, then shows it. Anything in the painting can
--- throw. When it did, the canvas existed but had never been shown, `isOpen()`
--- (which only asked whether the canvas existed) said yes, and so every
--- subsequent click took the "already open — close it" branch and returned.
--- Clicking did nothing, forever, and nothing was printed anywhere anyone
--- would see it.

local t = require("tests.support")
local check, ok = t.check, t.ok

local Menu = require("foxbot.menu")

-- ---------------------------------------------------------------- a fake OS

--- A canvas that records what was done to it. `isShowing` is deliberately a
--- liar by default: the real one returned true for a canvas that was not on
--- screen, which is why `shown` is tracked separately.
local function fakeCanvas(store)
  local canvas = { shown = false }
  local noop = function() return canvas end
  return setmetatable(canvas, {
    __index = function(_, key)
      if key == "show" then
        return function(self) self.shown = true store.shows = store.shows + 1 end
      elseif key == "hide" then
        return function(self) self.shown = false end
      elseif key == "isShowing" then
        return function() return true end          -- the lie
      elseif key == "delete" then
        return function() store.deletes = store.deletes + 1 end
      elseif key == "topLeft" then
        return function() return { x = 0, y = 0 } end
      elseif key == "replaceElements" then
        return function() end
      end
      return noop
    end,
    __newindex = function(tbl, key, value) rawset(tbl, key, value) end,
  })
end

local store = { shows = 0, deletes = 0 }

-- Everything this file stubs is put back at the end: it replaces chunks of the
-- fake OS the other test files share, and a test that quietly breaks the next
-- one is worse than no test.
local saved = { canvas = hs.canvas, styledtext = hs.styledtext,
                screen = hs.screen, mouse = hs.mouse }

hs.canvas = setmetatable({
  new = function() return fakeCanvas(store) end,
  windowLevels = { floating = 3 },
  windowBehaviors = { canJoinAllSpaces = 1, stationary = 2 },
}, { __index = function() return function() end end })

hs.styledtext = {
  new = function(str)
    if type(str) ~= "string" then
      error("styledtext.new got " .. type(str) .. ", not a string", 2)
    end
    return str
  end,
}

hs.screen = {
  mainScreen = function()
    return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end }
  end,
}
hs.mouse = { getCurrentScreen = function() return hs.screen.mainScreen() end }

local POINT = { x = 400, y = 300 }
local SCREEN = hs.screen.mainScreen()

local GOOD = {
  { kind = "label", title = "Hello" },
  { kind = "row", title = "Hide foxbot" },
  { kind = "row", title = "Quit foxbot" },
}

-- A row whose title is missing. styledtext throws on it, exactly as the real
-- one does — this stands in for any future page with a hole in it.
local BAD = {
  { kind = "label", title = "Hello" },
  { kind = "row" },
}

-- ------------------------------------------------------------- opening well

do
  local board = Menu.new()
  ok("a fresh panel is not open", not board:isOpen())
  ok("and not visible", not board:visible())

  board:open(GOOD, POINT, SCREEN)
  ok("opening it opens it", board:isOpen())
  ok("and it is visible", board:visible())

  board:close()
  ok("closing closes it", not board:isOpen())
  ok("and it is not visible", not board:visible())
end

-- --------------------------------------------------- opening badly, and after

do
  local board = Menu.new()

  local built = pcall(function() board:open(BAD, POINT, SCREEN) end)
  ok("a page with a hole in it throws", not built)

  -- This is the whole point. The canvas exists, and isShowing() lies and says
  -- it is on screen — but it was never shown, so this must still say no.
  ok("the half-built panel is not considered visible", not board:visible())

  -- ...which is what lets the next click through. The old code asked isOpen()
  -- alone, got yes, and closed instead of opening.
  local shouldToggleClosed = board:isOpen() and board:visible()
  ok("so the next click reopens rather than toggling closed", not shouldToggleClosed)

  -- And it does in fact recover, rather than needing Hammerspoon reloaded.
  board:close()
  board:open(GOOD, POINT, SCREEN)
  ok("the panel comes back", board:isOpen() and board:visible())
end

-- ------------------------------------------------------------ opening twice

do
  local board = Menu.new()
  board:open(GOOD, POINT, SCREEN)
  board:open(GOOD, POINT, SCREEN)
  ok("opening an open panel leaves one open", board:isOpen())
  ok("and visible", board:visible())
  board:close()
  ok("and one close is enough", not board:isOpen())
end

hs.canvas, hs.styledtext = saved.canvas, saved.styledtext
hs.screen, hs.mouse = saved.screen, saved.mouse

return true
