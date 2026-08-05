--- What the fox is feeling.
---
--- Ten states, every one driven by something real: whether a turn is running,
--- how long it has been running, whether anything is blocked on you, what time
--- it is, whether you are at the machine, and how much work has gone through
--- today. Nothing here is decorative — if he looks tired it is because you have
--- had a long day, and if he is asleep it is because it is the middle of the
--- night and nothing is running.
---
--- Each state can have its own drawing (`<coat>-<state>.png`). Where one is
--- missing he wears the default and expresses the state through the badge and
--- how he moves instead, so a half-finished sprite set still works.

local Palette = require("foxbot.palette")

local Mood = {}

-- `badge` names a colour in the current palette. `motion` is how he moves:
-- `rise` how far he floats, `period` how long a breath takes, `sway` a little
-- horizontal drift so idle reads as alive rather than frozen.
Mood.all = {
  resting = {
    label = "Resting", art = "resting",
    motion = { rise = 3, period = 2.8, sway = 0.6 },
  },
  running = {
    label = "Working", badge = "running", pulse = true, art = "running",
    motion = { rise = 5, period = 1.1, sway = 0 },
  },
  focused = {
    -- A turn that has been going a while. Slower and steadier than `running`:
    -- settled into it rather than darting about.
    label = "Deep in it", badge = "running", pulse = true, art = "focused",
    motion = { rise = 2, period = 2.2, sway = 0 },
  },
  asking = {
    label = "Waiting on you", badge = "asking", pulse = true, art = "asking",
    motion = { rise = 4, period = 1.7, sway = 1.4 },
    linger = 30,
  },
  settled = {
    label = "Just finished", badge = "settled", art = "settled",
    motion = { rise = 3, period = 2.4, sway = 0.6 },
    linger = 6,
  },
  cheering = {
    label = "Pleased with itself", badge = "settled", art = "cheering",
    motion = { rise = 7, period = 0.8, sway = 1.0 },
    linger = 8,
  },
  broken = {
    label = "Something broke", badge = "broken", pulse = true, art = "broken",
    motion = { rise = 6, period = 0.9, sway = 2.2 },
    linger = 20,
  },
  weary = {
    -- Hours of work behind you and nothing running. Barely moves.
    label = "Long day", art = "weary",
    motion = { rise = 1.5, period = 3.6, sway = 0.3 },
  },
  dozing = {
    -- You're away from the machine.
    label = "Dozing", art = "dozing",
    motion = { rise = 1.5, period = 4.0, sway = 0 },
  },
  sleeping = {
    -- Small hours, nothing running. The one state that is about the clock.
    label = "Asleep", art = "sleeping",
    motion = { rise = 1, period = 5.0, sway = 0 },
  },
}

Mood.order = {
  "resting", "running", "focused", "asking", "settled",
  "cheering", "broken", "weary", "dozing", "sleeping",
}

-- How long a turn has to run before it stops being "started" and becomes
-- "getting on with it".
Mood.DEEP_AFTER = 5 * 60
-- How much work in a day before he starts looking like he has done a day's work.
Mood.LONG_DAY = 3 * 3600

function Mood.get(name)
  return Mood.all[name] or Mood.all.resting
end

--- The badge colour for a mood, in whatever palette is current.
function Mood.colour(name)
  local mood = Mood.get(name)
  if not mood.badge then return nil end
  return Palette.colours()[mood.badge]
end

--- Which drawing this mood asks for. Sprites are optional; missing ones fall
--- back to the default coat.
function Mood.art(name)
  return Mood.get(name).art or "resting"
end

-- Which event kind pushes him into which mood, for the momentary reactions.
local FROM_KIND = {
  busy  = "running",
  done  = "settled",
  ask   = "asking",
  idle  = "asking",       -- "still waiting" is a question wearing a hat
  nudge = "asking",
  error = "broken",
  ["end"] = "resting",
}

function Mood.fromKind(kind)
  return FROM_KIND[kind] or "settled"
end

--- What he should settle into once a momentary reaction wears off.
---
--- Ordered by what you would most want to see. Something blocked on you beats
--- something merely running, because it needs you; a long-running turn beats a
--- fresh one, because that is the more interesting fact; and the ambient states
--- — asleep, dozing, weary — only get a look in when nothing is happening.
---
--- @param now table {
---   waiting = n, running = n, longestRun = seconds,
---   away = bool, nightTime = bool, workedToday = seconds, celebrate = bool }
function Mood.settle(now)
  now = now or {}

  if (now.waiting or 0) > 0 then return "asking" end

  if (now.running or 0) > 0 then
    if (now.longestRun or 0) >= Mood.DEEP_AFTER then return "focused" end
    return "running"
  end

  if now.celebrate then return "cheering" end
  if now.away then return "dozing" end
  if now.nightTime then return "sleeping" end
  if (now.workedToday or 0) >= Mood.LONG_DAY then return "weary" end

  return "resting"
end

return Mood
