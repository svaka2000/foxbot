--- What the fox is feeling, and how that reads on screen.
---
--- One drawing, five states. Shipping five sprites would mean five things to
--- keep in sync and re-draw for every skin; a coloured badge plus a change in
--- how he moves carries the same information and stays true for any sprite
--- somebody drops in.

local Palette = require("foxbot.palette")

local Mood = {}

-- `badge` names a colour in the active palette. `motion` is how he moves:
-- `rise` is how far he floats, `period` how long a full breath takes, and
-- `sway` a small horizontal drift that makes idle look alive rather than
-- mechanical.
Mood.all = {
  resting = {
    label = "Resting", badge = nil,
    motion = { rise = 3, period = 2.8, sway = 0.6 },
  },
  running = {
    label = "Working", badge = "running", pulse = true,
    motion = { rise = 5, period = 1.1, sway = 0 },
  },
  asking = {
    label = "Waiting on you", badge = "asking", pulse = true,
    motion = { rise = 4, period = 1.7, sway = 1.4 },
    linger = 30,
  },
  settled = {
    label = "Just finished", badge = "settled",
    motion = { rise = 3, period = 2.4, sway = 0.6 },
    linger = 6,
  },
  broken = {
    label = "Something broke", badge = "broken", pulse = true,
    motion = { rise = 6, period = 0.9, sway = 2.2 },
    linger = 20,
  },
}

Mood.order = { "resting", "running", "asking", "settled", "broken" }

function Mood.get(name)
  return Mood.all[name] or Mood.all.resting
end

--- The badge colour for a mood, in whatever palette is current.
function Mood.colour(name)
  local mood = Mood.get(name)
  if not mood.badge then return nil end
  return Palette.colours()[mood.badge]
end

-- Which event kind puts him into which mood.
local FROM_KIND = {
  busy  = "running",
  done  = "settled",
  ask   = "asking",
  idle  = "asking",     -- "still waiting" is a question wearing a hat
  nudge = "asking",
  error = "broken",
  ["end"] = "resting",
}

function Mood.fromKind(kind)
  return FROM_KIND[kind] or "settled"
end

return Mood
