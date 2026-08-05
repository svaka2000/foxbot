--- Which drawing the fox is wearing.
---
--- Any image in the assets folder shows up in the menu. The bundled fox is just
--- the default, and deleting whichever one you picked falls back to him rather
--- than leaving an empty square on your desktop.

local Coats = {}

Coats.folder = hs.configdir .. "/foxbot/assets"
Coats.default = "foxbot"

local USABLE = { png = true, gif = true, jpg = true, jpeg = true, tiff = true }

--- Everything usable in the folder — the default first, then alphabetical.
function Coats.all()
  local found = {}
  hs.fs.mkdir(Coats.folder)

  -- hs.fs.dir returns an iterator plus its state, so the for loop has to drive
  -- it directly rather than it being stashed in a local first.
  local ok = pcall(function()
    for name in hs.fs.dir(Coats.folder) do
      local ext = name:match("%.([^.]+)$")
      if ext and USABLE[ext:lower()] and name:sub(1, 1) ~= "." then
        local id = name:gsub("%.[^.]+$", "")
        found[#found + 1] = { id = id, label = id, path = Coats.folder .. "/" .. name }
      end
    end
  end)
  if not ok then return {} end

  table.sort(found, function(a, b)
    if a.id == Coats.default then return true end
    if b.id == Coats.default then return false end
    return a.label < b.label
  end)

  for _, coat in ipairs(found) do
    if coat.id == Coats.default then coat.label = "Foxbot" end
  end
  return found
end

--- Resolve a saved choice to a file, falling back if it has since been deleted.
function Coats.path(id)
  local fallback = Coats.folder .. "/" .. Coats.default .. ".png"
  if not id or id == "" then return fallback end
  for _, coat in ipairs(Coats.all()) do
    if coat.id == id then return coat.path end
  end
  return fallback
end

function Coats.label(id)
  if not id or id == Coats.default then return "Foxbot" end
  return id
end

function Coats.reveal()
  hs.fs.mkdir(Coats.folder)
  hs.execute(("open %q"):format(Coats.folder))
end

return Coats
