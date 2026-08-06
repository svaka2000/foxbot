--- Noticing you've wandered off.
---
--- ## What this can and cannot see
---
--- macOS gives any app the *identity* of the frontmost application for free.
--- It does not give out window titles without Screen Recording permission —
--- and Screen Recording is a permission that, once granted, lets the holder
--- read everything on your display, including other people's messages and
--- anything in a password field.
---
--- So this knows you are in Discord. It cannot know which channel, and it will
--- never ask for the permission that would tell it. The practical consequence
--- is that a browser is opaque: "Google Chrome" could be documentation or it
--- could be Twitter, and rather than guess, browsers are simply not counted
--- unless you say so yourself.
---
--- ## When it actually speaks
---
--- Nagging someone for being on their phone is the single most annoying thing
--- a program can do, and this project has already spent a week removing noise.
--- So a nudge needs *all* of:
---
---   * you turned it on;
---   * the app is one you marked as a break;
---   * you've been in it continuously, not just passed through;
---   * and something is actually waiting — a focus block you started, or a
---     session sitting blocked on a question.
---
--- That last one is the important one. Being on Discord at 9pm with nothing
--- running is not a problem, and a tool that treats it as one is a tool you
--- turn off. He only speaks when you had told him you were doing something
--- else.

local Drift = {}
Drift.__index = Drift

-- Apps that are unambiguously not work. Browsers are deliberately absent: see
-- above. Nothing here is guessed from a category — each is an app whose whole
-- purpose is leisure.
Drift.BREAKS = {
  ["Discord"] = true,
  ["TikTok"] = true,
  ["Netflix"] = true,
  ["Twitch"] = true,
  ["Steam"] = true,
  ["Reddit"] = true,
  ["Instagram"] = true,
  ["YouTube"] = true,
}

-- His own windows aren't a signal either way, and counting them would mean
-- opening the menu reset the clock you were being measured against.
Drift.IGNORED = { ["Hammerspoon"] = true }

Drift.GAP = 45 * 60        -- at most one nudge in this long
Drift.MOST_A_DAY = 3

--- @param deps { settings, save, now, frontmost }
function Drift.new(deps)
  deps = deps or {}
  local self = setmetatable({}, Drift)
  self.settings = deps.settings or {}
  self.save = deps.save or function() end
  self.now = deps.now or os.time
  self.frontmost = deps.frontmost or function() return nil end
  self.app = nil
  self.since = nil
  return self
end

--- Which apps count as a break: the built-in list, plus anything you've added,
--- minus anything you've removed. Stored as an override map rather than a
--- rewritten list so that a later release can add to the defaults without
--- clobbering your choices.
function Drift:isBreak(app)
  if not app then return false end
  local override = (self.settings.driftApps or {})[app]
  if override ~= nil then return override == true end
  return Drift.BREAKS[app] == true
end

function Drift:mark(app, counts)
  if not app or app == "" then return end
  local apps = self.settings.driftApps or {}
  -- Store the decision either way. Recording only the additions would mean a
  -- default-on app could never be turned off.
  apps[app] = counts and true or false
  self.settings.driftApps = apps
  self.save(self.settings)
end

--- Called from the poll. Returns the app in front, remembering how long it has
--- been there.
function Drift:sample(at)
  at = at or self.now()
  local app = self.frontmost()

  -- Ignoring an app means holding the previous one, not clearing it.
  if app and Drift.IGNORED[app] then return self.app end

  if app ~= self.app then
    self.app = app
    self.since = at
  end
  return self.app
end

--- How long the current app has been in front, in seconds.
function Drift:elapsed(at)
  if not self.since then return 0 end
  return (at or self.now()) - self.since
end

--- How many nudges today, resetting lazily so a machine asleep at midnight
--- still rolls over correctly.
function Drift:spokenToday(startOfDay)
  local s = self.settings
  if (s.driftDay or 0) < startOfDay then
    s.driftDay = startOfDay
    s.driftCount = 0
    self.save(s)
  end
  return s.driftCount or 0
end

--- Should he say something? Returns a table describing why, or nil.
---
--- @param at number
--- @param startOfDay number
--- @param world { focus: string|nil, blocked: number }
function Drift:should(at, startOfDay, world)
  local s = self.settings
  if not s.drift then return nil end
  if not self:isBreak(self.app) then return nil end

  local been = self:elapsed(at)
  if been < (s.driftAfter or 300) then return nil end

  -- Something has to actually be waiting.
  world = world or {}
  local waiting = (world.focus == "work") or ((world.blocked or 0) > 0)
  if not waiting then return nil end

  if (at - (s.driftAt or 0)) < Drift.GAP then return nil end
  if self:spokenToday(startOfDay) >= Drift.MOST_A_DAY then return nil end

  return { app = self.app, been = been,
           focus = world.focus, blocked = world.blocked or 0 }
end

function Drift:spoke(at)
  local s = self.settings
  s.driftAt = at
  s.driftCount = (s.driftCount or 0) + 1
  self.save(s)
end

return Drift
