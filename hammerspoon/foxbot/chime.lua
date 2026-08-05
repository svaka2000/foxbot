--- Sounds.
---
--- macOS ships a set of short system sounds that read as notifications; those
--- are the menu. Anything you drop into the sounds folder joins them.

local Chime = {}

Chime.folder = hs.configdir .. "/foxbot/sounds"

-- Not every system sound suits an alert — these are the ones that do.
local STOCK = {
  "Hero", "Glass", "Ping", "Pop", "Purr", "Tink",
  "Submarine", "Bottle", "Blow", "Frog", "Funk", "Morse", "Sosumi", "Basso",
}

local PLAYABLE = {
  mp3 = true, m4a = true, wav = true, aiff = true,
  aif = true, mp4 = true, caf = true, aac = true,
}

Chime.SILENT = "silent"

local function ownFiles()
  local found = {}
  hs.fs.mkdir(Chime.folder)

  -- hs.fs.dir hands back an iterator plus its state, so it has to be driven by
  -- the for loop directly rather than stashed in a local first.
  local ok = pcall(function()
    for name in hs.fs.dir(Chime.folder) do
      local ext = name:match("%.([^.]+)$")
      if ext and PLAYABLE[ext:lower()] and name:sub(1, 1) ~= "." then
        found[#found + 1] = {
          id = "own:" .. name,
          label = name:gsub("%.[^.]+$", ""),
          own = true,
        }
      end
    end
  end)
  if not ok then return {} end

  table.sort(found, function(a, b) return a.label < b.label end)
  return found
end

--- Everything you can pick, stock first.
function Chime.choices()
  local out = {}
  for _, name in ipairs(STOCK) do
    out[#out + 1] = { id = name, label = name, stock = true }
  end
  for _, own in ipairs(ownFiles()) do out[#out + 1] = own end
  out[#out + 1] = { id = Chime.SILENT, label = "Silent", silent = true }
  return out
end

function Chime.label(id)
  if not id or id == Chime.SILENT then return "Silent" end
  if id:sub(1, 4) == "own:" then
    return id:sub(5):gsub("%.[^.]+$", "")
  end
  return id
end

local loaded = {}

local function resolve(id)
  if not id or id == Chime.SILENT then return nil end
  if loaded[id] ~= nil then return loaded[id] or nil end

  local sound
  if id:sub(1, 4) == "own:" then
    local path = Chime.folder .. "/" .. id:sub(5)
    if hs.fs.attributes(path) then sound = hs.sound.getByFile(path) end
  else
    sound = hs.sound.getByName(id)
  end

  loaded[id] = sound or false
  return sound
end

function Chime.play(id)
  local sound = resolve(id)
  if not sound then return false end
  -- Restart rather than overlap, for when two events land together.
  sound:stop()
  sound:play()
  return true
end

function Chime.reveal()
  hs.fs.mkdir(Chime.folder)
  hs.execute(("open %q"):format(Chime.folder))
end

return Chime
