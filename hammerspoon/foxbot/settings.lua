--- Persisted settings, driven by a schema.
---
--- Every setting is declared once, here, with its default. The list of keys
--- that get written to disk is *derived* from that declaration rather than
--- maintained alongside it — which makes an entire class of bug impossible.
---
--- (The project this one was inspired by kept the defaults and the save-list as
--- two separate tables. A key present in one and missing from the other was
--- silently dropped on every save, so its "run this once" flag never stuck and
--- it re-applied Hammerspoon's preferences on every single launch, quietly
--- turning launch-at-login back on for people who had turned it off. Deriving
--- one from the other is the fix.)

local Settings = {}

local STORE = "foxbot.settings"

-- name -> default. `nil` is not expressible as a default in a Lua table
-- constructor, so anything genuinely optional is declared with a NONE marker.
local NONE = setmetatable({}, { __tostring = function() return "none" end })
Settings.NONE = NONE

local SCHEMA = {
  -- where he sits; NONE until you drag him somewhere
  x = NONE,
  y = NONE,

  hidden      = false,
  quiet       = false,       -- no sound at all
  skin        = "dusk",      -- palette
  coat        = "foxbot",    -- which sprite png
  voice       = "plain",
  detail      = "brief",     -- how much of a finished turn to show
  chimes      = {},          -- event -> sound id
  prepared    = false,       -- have Hammerspoon's own prefs been set once

  -- live awareness

  -- How much he speaks up. One dial rather than a row of toggles, because the
  -- toggles were individually reasonable and collectively deafening — 46 events
  -- in an hour, 22 of them announcing that a session had closed.
  --   "needed" — only when something is blocked on you, or broke
  --   "normal" — the above, plus finished turns
  --   "chatty" — the above, plus live progress notes
  -- Turn-starts and session-closes produce no note at any level: the ring and
  -- the menu bar already carry that, and "a session closed" is the least
  -- actionable thing he could interrupt you with.
  chatty      = "normal",

  -- Everything hushed until this moment. 0 means not paused. This is the
  -- "make it stop" button on the home page, and it expires by itself so you
  -- can't silence him in a huff and forget.
  pauseUntil  = 0,

  -- Notes reveal themselves letter by letter.
  typing      = true,

  -- being left alone
  hush        = false,
  hushFrom    = 22,
  hushTo      = 8,
  hushSoftly  = false,       -- silence but still show

  -- When he curls up. Separate from quiet hours: you might want him silent
  -- overnight but still awake, or asleep without muting anything.
  sleepFrom   = 23,
  sleepTo     = 6,

  -- coming back
  catchUp     = true,        -- hold notes while away, hand back one summary
  awayAfter   = 0,           -- 0 = locked/asleep only; else seconds idle

  -- unanswered questions
  remind      = true,

  -- The focus timer. `focusKind` is "" when nothing is running rather than
  -- nil, because a nil default can't be expressed in a table constructor.
  focusFor    = 25 * 60,
  breakFor    = 5 * 60,
  focusKind   = "",
  focusUntil  = 0,
  focusDone   = 0,
  focusDay    = 0,

  -- The tour. `taught` is the Teach.VERSION seen through to an ending, so a
  -- future tour can be shown again by bumping it. Read as a number, never as a
  -- boolean — 0 is truthy in Lua.
  taught      = 0,
  taughtTries = 0,

  -- Noticing you've wandered off. Off by default: a tool that starts
  -- commenting on what apps you open, uninvited, is a tool you uninstall.
  drift       = false,
  driftAfter  = 5 * 60,
  driftApps   = {},          -- app -> true/false, overriding Drift.BREAKS
  driftAt     = 0,
  driftDay    = 0,
  driftCount  = 0,

  -- Teaching you something. `loreSeen` is the indices already drawn from the
  -- pack this cycle, so nothing repeats until all of it has been seen.
  lore        = true,
  loreSeen    = {},
  loreOn      = 0,           -- start-of-day he last volunteered one

  -- Optional: ask a hosted model for a tip about the languages in the project
  -- you're in. Off unless you turn it on AND have put a key on disk, because
  -- it is the one thing here that leaves the machine. See remote.lua.
  fresh       = false,

  -- What he's called. Bought from the shop; "" means Foxbot.
  nickname    = "",

  perProject  = {},          -- folder -> { mute = true, voice = "..." }
  keepDays    = 30,
}

-- Derived, not maintained by hand.
local KEYS = {}
for name in pairs(SCHEMA) do KEYS[#KEYS + 1] = name end
table.sort(KEYS)

Settings.schema = SCHEMA
Settings.keys = KEYS

local function clone(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = clone(v) end
  return out
end

function Settings.load()
  local stored = hs.settings.get(STORE)
  if type(stored) ~= "table" then stored = {} end

  local out = {}
  for _, name in ipairs(KEYS) do
    local value = stored[name]
    if value ~= nil then
      out[name] = value
    else
      -- Spelled out rather than `cond and fallback or nil`: for every setting
      -- that defaults to false, that idiom collapses to nil, because `false` is
      -- itself falsy. Half the switches in here default to false.
      local fallback = SCHEMA[name]
      if fallback ~= NONE then out[name] = clone(fallback) end
    end
  end
  return out
end

function Settings.save(current)
  local out = {}
  for _, name in ipairs(KEYS) do out[name] = current[name] end
  hs.settings.set(STORE, out)
end

--- Flip a boolean and persist it in one go — most menu rows do exactly this.
function Settings.toggle(current, name)
  current[name] = not current[name]
  Settings.save(current)
  return current[name]
end

--- Step a setting through a list of allowed values.
function Settings.cycle(current, name, choices)
  local at = 1
  for i, value in ipairs(choices) do
    if current[name] == value then at = i break end
  end
  current[name] = choices[(at % #choices) + 1]
  Settings.save(current)
  return current[name]
end

-- ------------------------------------------------------------- per project

function Settings.project(current, folder)
  if not folder or folder == "" then return {} end
  return (current.perProject or {})[folder] or {}
end

--- Patch one project's rules. `false` clears a key rather than storing false:
--- a nil inside a table constructor is simply not a key, so `{ mute = nil }`
--- would arrive here as an empty patch and quietly do nothing.
function Settings.setProject(current, folder, patch)
  if not folder or folder == "" then return end
  current.perProject = current.perProject or {}

  local row = current.perProject[folder] or {}
  for key, value in pairs(patch) do
    -- Spelled out, not `cond and nil or value`: that idiom can never yield nil,
    -- because nil is falsy and the `or` branch always wins. It would store
    -- `false` here instead of clearing the key, and the rule would stick.
    if value == false then
      row[key] = nil
    else
      row[key] = value
    end
  end

  local bare = true
  for _ in pairs(row) do bare = false break end
  current.perProject[folder] = (not bare) and row or nil

  Settings.save(current)
end

return Settings
