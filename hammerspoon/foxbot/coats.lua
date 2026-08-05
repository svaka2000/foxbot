--- Which drawing the fox is wearing.
---
--- A coat is a base image plus, optionally, one per mood:
---
---   foxbot.png            the default, always needed
---   foxbot-sleeping.png   worn when it's the small hours and nothing is running
---   foxbot-asking.png     worn while something is blocked on you
---   …
---
--- Only base images are offered in the menu; the variants attach themselves to
--- whichever coat they are named after. Any that don't exist simply aren't used
--- — a coat with one drawing works exactly as well, he just expresses the mood
--- through the badge and how he moves instead.

local Coats = {}

Coats.folder = hs.configdir .. "/foxbot/assets"
Coats.default = "foxbot"

local USABLE = { png = true, gif = true, jpg = true, jpeg = true, tiff = true }

--- Everything in the folder, as { name -> path }.
local function contents()
  local found = {}
  hs.fs.mkdir(Coats.folder)

  -- hs.fs.dir hands back an iterator plus its state, so the for loop has to
  -- drive it directly rather than it being stashed in a local first.
  local ok = pcall(function()
    for name in hs.fs.dir(Coats.folder) do
      local ext = name:match("%.([^.]+)$")
      if ext and USABLE[ext:lower()] and name:sub(1, 1) ~= "." then
        found[name:gsub("%.[^.]+$", "")] = Coats.folder .. "/" .. name
      end
    end
  end)
  if not ok then return {} end
  return found
end

--- Base coats only — anything with a `-mood` suffix belongs to one of these.
--- @param moods table list of mood names, so "my-fox-sleeping" splits correctly
function Coats.all(moods)
  local files = contents()
  local suffixes = {}
  for _, mood in ipairs(moods or {}) do suffixes[mood] = true end

  local out = {}
  for name, path in pairs(files) do
    local stem, tail = name:match("^(.-)%-([^-]+)$")
    local isVariant = stem and tail and suffixes[tail] and files[stem]
    if not isVariant then
      out[#out + 1] = { id = name, label = name, path = path }
    end
  end

  table.sort(out, function(a, b)
    if a.id == Coats.default then return true end
    if b.id == Coats.default then return false end
    return a.label < b.label
  end)

  for _, coat in ipairs(out) do
    if coat.id == Coats.default then coat.label = "Foxbot" end
  end
  return out
end

--- The file for a coat in a given mood, falling back sensibly:
--- the mood's own drawing, then the coat's default, then the bundled fox.
function Coats.path(id, mood)
  local files = contents()
  id = (id and id ~= "") and id or Coats.default

  if mood and files[id .. "-" .. mood] then
    return files[id .. "-" .. mood]
  end
  if files[id] then return files[id] end
  if files[Coats.default] then return files[Coats.default] end
  return Coats.folder .. "/" .. Coats.default .. ".png"
end

--- Which moods this coat actually has a drawing for.
function Coats.moods(id, moods)
  local files = contents()
  id = (id and id ~= "") and id or Coats.default

  local out = {}
  for _, mood in ipairs(moods or {}) do
    if files[id .. "-" .. mood] then out[#out + 1] = mood end
  end
  return out
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
