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
}

Palette.order = { "dusk", "daylight", "burrow" }
Palette.skin = "dusk"

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
