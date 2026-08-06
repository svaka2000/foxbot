--- Colour and metrics, in one place.
---
--- The palette is pulled off the fox himself — burnt orange, cream, dark plum —
--- so the notes he puts on screen look like they belong to him rather than to
--- whatever theme the terminal happens to be using.

local Palette = {}

--- Colours are written as hex because that is how they come out of the sprite,
--- and converted once at load. Hammerspoon wants 0-1 floats.
local function rgb(hex, alpha)
  return {
    red   = tonumber(hex:sub(1, 2), 16) / 255,
    green = tonumber(hex:sub(3, 4), 16) / 255,
    blue  = tonumber(hex:sub(5, 6), 16) / 255,
    alpha = alpha or 1,
  }
end

Palette.rgb = rgb

-- The fox's own colours.
local FUR    = "F2560A"
local EMBER  = "C63F06"
local CREAM  = "FBE3B8"
local PLUM   = "2E1F2E"

local skins = {
  dusk = {
    label   = "Dusk",
    panel   = rgb(PLUM, 0.97),
    edge    = rgb(FUR, 0.34),
    ink     = rgb(CREAM),
    faded   = rgb("A6968F"),
    fur     = rgb(FUR),
    glow    = rgb(FUR, 0.18),
    hair    = rgb(CREAM, 0.10),
    running = rgb("4FA8E8"),
    settled = rgb("62C077"),
    asking  = rgb("F0B429"),
    broken  = rgb("E2564F"),
    bubbleEdge   = rgb("C05F3B"),
    bubbleFill   = rgb("FDFBF7"),
    bubbleShadow = rgb("A7A6A7"),
    bubbleInk    = rgb("1A1520"),
    bubbleFaint  = rgb("7A7480"),
    bubbleGlow   = rgb("C05F3B", 0.14),
  },
  daylight = {
    label   = "Daylight",
    panel   = rgb("FDF8F1", 0.99),
    edge    = rgb(EMBER, 0.38),
    ink     = rgb("21181F"),
    faded   = rgb("6B5F5A"),
    fur     = rgb(EMBER),
    glow    = rgb(EMBER, 0.14),
    hair    = rgb(PLUM, 0.12),
    running = rgb("1F63B8"),
    settled = rgb("2A7D43"),
    asking  = rgb("A8730B"),
    broken  = rgb("B33A34"),
    bubbleEdge   = rgb("B4552F"),
    bubbleFill   = rgb("FFFFFF"),
    bubbleShadow = rgb("9C9B9C"),
    bubbleInk    = rgb("14101A"),
    bubbleFaint  = rgb("6E6874"),
    bubbleGlow   = rgb("B4552F", 0.12),
  },
  burrow = {
    -- Flattened out, for when a projector is watching.
    label   = "Burrow",
    panel   = rgb("1A171B", 0.93),
    edge    = rgb("FFFFFF", 0.12),
    ink     = rgb("DCD6D2"),
    faded   = rgb("8B8580"),
    fur     = rgb("BFB8B2"),
    glow    = rgb("FFFFFF", 0.07),
    hair    = rgb("FFFFFF", 0.06),
    running = rgb("9AA6B2"),
    settled = rgb("9AB2A0"),
    asking  = rgb("B8AC91"),
    broken  = rgb("B89A98"),
    bubbleEdge   = rgb("8A8288"),
    bubbleFill   = rgb("EFEDEA"),
    bubbleShadow = rgb("9A989A"),
    bubbleInk    = rgb("22202A"),
    bubbleFaint  = rgb("7C7A82"),
    bubbleGlow   = rgb("8A8288", 0.1),
  },

  -- ------------------------------------------------------------------ locked
  --
  -- These are the shop's. They are defined here with the others rather than
  -- somewhere separate, because a palette that lives in a different file
  -- inevitably drifts a key behind and renders with a nil colour — and nothing
  -- says "bought a broken thing" like a note with no text in it.

  terminal = {
    -- Black and phosphor.
    label   = "Terminal",
    panel   = rgb("050A05", 0.97),
    edge    = rgb("3CE86B", 0.3),
    ink     = rgb("8FF0A8"),
    faded   = rgb("4E8A5C"),
    fur     = rgb("3CE86B"),
    glow    = rgb("3CE86B", 0.14),
    hair    = rgb("3CE86B", 0.08),
    running = rgb("62D8E8"),
    settled = rgb("3CE86B"),
    asking  = rgb("E8D23C"),
    broken  = rgb("E85C4A"),
    bubbleEdge   = rgb("3CE86B"),
    bubbleFill   = rgb("06120A"),
    bubbleShadow = rgb("041006"),
    bubbleInk    = rgb("A8F5BC"),
    bubbleFaint  = rgb("5E9C6C"),
    bubbleGlow   = rgb("3CE86B", 0.16),
  },
  blueprint = {
    -- White on drafting blue.
    label   = "Blueprint",
    panel   = rgb("0E3A6B", 0.97),
    edge    = rgb("FFFFFF", 0.34),
    ink     = rgb("EAF2FB"),
    faded   = rgb("9DBAD8"),
    fur     = rgb("FFFFFF"),
    glow    = rgb("FFFFFF", 0.14),
    hair    = rgb("FFFFFF", 0.1),
    running = rgb("7FD4FF"),
    settled = rgb("8FE8B4"),
    asking  = rgb("FFD98A"),
    broken  = rgb("FF9C8F"),
    bubbleEdge   = rgb("EAF2FB"),
    bubbleFill   = rgb("124680"),
    bubbleShadow = rgb("092B50"),
    bubbleInk    = rgb("F4F9FF"),
    bubbleFaint  = rgb("A6C4E2"),
    bubbleGlow   = rgb("FFFFFF", 0.14),
  },
  sakura = {
    -- Pale pink paper.
    label   = "Sakura",
    panel   = rgb("FFF2F5", 0.99),
    edge    = rgb("D46A88", 0.34),
    ink     = rgb("4A2A36"),
    faded   = rgb("A8828E"),
    fur     = rgb("D46A88"),
    glow    = rgb("D46A88", 0.14),
    hair    = rgb("4A2A36", 0.1),
    running = rgb("6E8FC4"),
    settled = rgb("6BA87E"),
    asking  = rgb("C4902E"),
    broken  = rgb("C4565A"),
    bubbleEdge   = rgb("D46A88"),
    bubbleFill   = rgb("FFFAFB"),
    bubbleShadow = rgb("E0C2CC"),
    bubbleInk    = rgb("3E2029"),
    bubbleFaint  = rgb("9C7682"),
    bubbleGlow   = rgb("D46A88", 0.13),
  },
  midnight = {
    -- Deep blue, low contrast, for late.
    label   = "Midnight",
    panel   = rgb("0B1020", 0.97),
    edge    = rgb("5A6FA8", 0.3),
    ink     = rgb("C2CCE8"),
    faded   = rgb("6E7896"),
    fur     = rgb("7C8FD4"),
    glow    = rgb("7C8FD4", 0.13),
    hair    = rgb("FFFFFF", 0.05),
    running = rgb("6FA8D4"),
    settled = rgb("6FB48C"),
    asking  = rgb("C4A45E"),
    broken  = rgb("C4706E"),
    bubbleEdge   = rgb("5A6FA8"),
    bubbleFill   = rgb("141A2E"),
    bubbleShadow = rgb("080C18"),
    bubbleInk    = rgb("D2DAF0"),
    bubbleFaint  = rgb("7A84A2"),
    bubbleGlow   = rgb("7C8FD4", 0.14),
  },
}

-- What the settings page offers. Locked palettes join this once bought, rather
-- than being listed greyed out — the shop is where you find out they exist, and
-- a settings page full of things you can't pick is just noise.
Palette.order = { "dusk", "daylight", "burrow" }
Palette.LOCKED = { "terminal", "blueprint", "sakura", "midnight" }
Palette.skin = "dusk"

--- Is this a palette at all? unlock() answering "no" is ambiguous: it also
--- says no to one that is already in the list.
function Palette.exists(name)
  return skins[name] ~= nil
end

--- Add a bought palette to the list you can choose from.
function Palette.unlock(name)
  if not skins[name] then return false end
  for _, have in ipairs(Palette.order) do
    if have == name then return false end
  end
  Palette.order[#Palette.order + 1] = name
  return true
end

function Palette.colours()
  return skins[Palette.skin] or skins.dusk
end

function Palette.label(name)
  return (skins[name] or skins.dusk).label
end

function Palette.use(name)
  if skins[name] then Palette.skin = name end
  return Palette.skin
end

function Palette.next()
  local at = 1
  for i, name in ipairs(Palette.order) do
    if name == Palette.skin then at = i break end
  end
  return Palette.use(Palette.order[(at % #Palette.order) + 1])
end

-- ------------------------------------------------------------------ metrics

Palette.foxWidth = 96      -- how wide he sits on screen

Palette.badge    = 13      -- the status dot on his shoulder
Palette.badgeGap = 3

-- Note widths. Ceilings, not targets — a note shrinks to its text.
Palette.noteMin    = 150
Palette.noteWidth  = 230   -- a plain note
Palette.noteWide   = 290   -- one carrying detail lines
Palette.pad        = 14
Palette.gutter     = 12    -- fox to panel
Palette.leading    = 8     -- note to note
Palette.typeRate   = 55    -- characters a second when he speaks
Palette.linger     = 12    -- seconds a note stays up
Palette.lingerStep = 7     -- ambient progress notes go sooner
Palette.lingerLong = 30    -- the welcome-back summary earns longer

Palette.chipHeight = 22    -- the little action buttons
Palette.chipGap    = 6

Palette.barHeight  = 6     -- report bars

Palette.face   = "Menlo"   -- monospace, to match where the sessions live
Palette.head   = 12
Palette.body   = 11.5
Palette.menu   = 12.5
Palette.small  = 10.5
Palette.tiny   = 12        -- the dismiss cross

return Palette
