--- A focus timer.
---
--- Twenty-five minutes of work, five of rest, and the fox keeps the clock. He
--- already knows whether you are actually working, so this is less of a bolt-on
--- than it looks: a session running during a focus block is the thing the block
--- was for, and a block that ends while you are mid-turn shouldn't interrupt it.
---
--- Deliberately not a to-do list, not a tracker, not a streak to protect. It
--- counts down and it tells you once.

local Timer = {}
Timer.__index = Timer

Timer.WORK = "work"
Timer.REST = "rest"

-- The usual pomodoro numbers, and a long rest every fourth block.
Timer.DEFAULT_WORK = 25 * 60
Timer.DEFAULT_REST = 5 * 60
Timer.LONG_REST = 15 * 60
Timer.LONG_EVERY = 4

--- @param deps { settings, save, now, onFinish(kind, next) }
function Timer.new(deps)
  deps = deps or {}
  local self = setmetatable({}, Timer)
  self.settings = deps.settings or {}
  self.save = deps.save or function() end
  self.now = deps.now or os.time
  self.onFinish = deps.onFinish or function() end
  return self
end

function Timer:running()
  local s = self.settings
  return (s.focusKind ~= nil and s.focusKind ~= "")
     and (s.focusUntil or 0) > self.now()
end

function Timer:kind()
  return self:running() and self.settings.focusKind or nil
end

--- Seconds remaining, or nil.
function Timer:left()
  if not self:running() then return nil end
  return (self.settings.focusUntil or 0) - self.now()
end

--- "24:38" — deliberately mm:ss, because a countdown you can't read to the
--- second isn't a countdown.
function Timer:clock()
  local left = self:left()
  if not left then return nil end
  return string.format("%d:%02d", math.floor(left / 60), left % 60)
end

function Timer:lengthFor(kind)
  local s = self.settings
  if kind == Timer.REST then
    local done = (s.focusDone or 0)
    if done > 0 and done % Timer.LONG_EVERY == 0 then return Timer.LONG_REST end
    return s.breakFor or Timer.DEFAULT_REST
  end
  return s.focusFor or Timer.DEFAULT_WORK
end

function Timer:start(kind)
  kind = kind or Timer.WORK
  self.settings.focusKind = kind
  self.settings.focusUntil = self.now() + self:lengthFor(kind)
  self.save(self.settings)
  return self.settings.focusUntil
end

function Timer:stop()
  self.settings.focusKind = ""
  self.settings.focusUntil = 0
  self.save(self.settings)
end

--- Add another five minutes to whatever is running.
function Timer:extend(seconds)
  if not self:running() then return end
  self.settings.focusUntil = (self.settings.focusUntil or self.now()) + (seconds or 300)
  self.save(self.settings)
end

--- Called from the poll. Returns the kind that just ended, if one did.
---
--- A finished block does NOT roll straight into the next one. Starting a rest
--- you didn't ask for is how these things end up nagging; it offers, and waits.
function Timer:tick()
  local s = self.settings
  if s.focusKind == nil or s.focusKind == "" then return nil end
  if (s.focusUntil or 0) > self.now() then return nil end

  local ended = s.focusKind
  if ended == Timer.WORK then
    s.focusDone = (s.focusDone or 0) + 1
  end
  s.focusKind = ""
  s.focusUntil = 0
  self.save(s)

  local suggest = (ended == Timer.WORK) and Timer.REST or Timer.WORK
  self.onFinish(ended, suggest)
  return ended, suggest
end

--- How many work blocks today. Reset lazily rather than on a schedule, so a
--- machine that was asleep at midnight still rolls over correctly.
function Timer:doneToday(startOfDay)
  local s = self.settings
  if (s.focusDay or 0) < startOfDay then
    s.focusDay = startOfDay
    s.focusDone = 0
    self.save(s)
  end
  return s.focusDone or 0
end

return Timer
