--- The fox himself: drawn, animated, dragged, and remembered where you put him.
---
--- Motion is a small state machine rather than a fixed animation. Every frame
--- asks the current mood how it moves and where in the cycle we are; one-off
--- gestures (the startle when something lands) push an easing curve onto the
--- front of that and drain away. Adding a mood is a table entry, not new code.

local Palette = require("foxbot.palette")
local Mood    = require("foxbot.mood")
local Coats   = require("foxbot.coats")

local Sprite = {}
Sprite.__index = Sprite

local FPS = 30
local CLICK_SLOP = 4        -- movement under this was a click, not a drag
local BREATH = 1.4          -- seconds per pulse of the badge

--- Ease-out-back: overshoots then settles. Used for the startle hop so it
--- reads as a reaction rather than a bounce.
local function easeOutBack(t)
  local c1, c3 = 1.70158, 2.70158
  local p = t - 1
  return 1 + c3 * p * p * p + c1 * p * p
end

--- @param opts { settings, onTap, onMoved }
function Sprite.new(opts)
  local self = setmetatable({}, Sprite)

  self.settings = opts.settings
  self.onTap = opts.onTap
  self.onMoved = opts.onMoved

  self.mood = "resting"
  self.until_ = nil
  self.after = "resting"
  self.phase = 0
  self.gesture = nil

  self.art = {}                 -- mood -> loaded image, kept so swaps are free
  self.worn = nil

  local file = Coats.path(self.settings.coat, "resting")
  local image = hs.image.imageFromPath(file)
  if not image then
    hs.alert.show("foxbot: no sprite at " .. tostring(file))
    return nil
  end
  self.art.resting = image
  self.worn = "resting"

  local size = image:size()
  self.w = Palette.foxWidth
  self.h = math.floor(Palette.foxWidth * (size.h / size.w) + 0.5)

  local homeX, homeY = self:home()
  self.x = self.settings.x or homeX
  self.y = self.settings.y or homeY

  self.canvas = hs.canvas.new({ x = self.x, y = self.y, w = self.w, h = self.h })
  self.canvas:level(hs.canvas.windowLevels.floating)
  self.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                     | hs.canvas.windowBehaviors.stationary)
  self.canvas:clickActivating(false)

  self.canvas:replaceElements({
    type = "image",
    image = image,
    imageScaling = "scaleProportionally",
    imageAlignment = "center",
    frame = { x = 0, y = 0, w = self.w, h = self.h },
  }, {
    -- The badge. Always present so its index never shifts; drawn fully clear
    -- when the mood has no colour.
    type = "circle",
    action = "strokeAndFill",
    center = { x = self.w - Palette.badge / 2 - Palette.badgeGap,
               y = self.h - Palette.badge / 2 - Palette.badgeGap },
    radius = Palette.badge / 2,
    fillColor = { alpha = 0 },
    strokeColor = { alpha = 0 },
    strokeWidth = 2,
  })

  self:listen()
  self:animate()

  if not self.settings.hidden then self.canvas:show() end
  return self
end

--- Right-hand edge, vertically centred, on a fresh install.
function Sprite:home()
  local frame = hs.screen.mainScreen():frame()
  return frame.x + frame.w - Palette.foxWidth - 28,
         frame.y + math.floor(frame.h / 2)
end

--- Where he sits, ignoring the animation offset.
function Sprite:frame()
  return { x = self.x, y = self.y, w = self.w, h = self.h }
end

--- Which screen he is on. Notes and menus measure against this, not the main
--- screen, so dragging him to a second monitor takes his bubbles with him.
function Sprite:screen()
  local mid = { x = self.x + self.w / 2, y = self.y + self.h / 2 }
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:frame()
    if mid.x >= f.x and mid.x < f.x + f.w and mid.y >= f.y and mid.y < f.y + f.h then
      return screen
    end
  end
  return hs.screen.mainScreen()
end

-- --------------------------------------------------------------------- mood

--- Put on whichever drawing this mood asks for.
---
--- A coat only has to provide the default; anything missing falls back to it,
--- and the mood still reads through the badge and the motion. Images are loaded
--- once and kept, so changing mood is just swapping a reference.
function Sprite:wear(mood)
  local wanted = Mood.art(mood)
  if wanted == self.worn then return end

  local image = self.art[wanted]
  if image == nil then
    image = hs.image.imageFromPath(Coats.path(self.settings.coat, wanted)) or false
    self.art[wanted] = image
  end
  if not image then return end

  self.worn = wanted
  if self.canvas then self.canvas[1].image = image end
end

--- Move to `name`. Moods with a `linger` fall back to `after` when it runs out.
function Sprite:feel(name, after)
  local mood = Mood.get(name)
  self.mood = name
  self.after = after or "resting"
  self.until_ = mood.linger and (os.time() + mood.linger) or nil
  self:wear(name)
  self:paintBadge()
end

--- Keep him in step with whatever is true now. `resolve` says what that is.
---
--- This has to run even when no temporary mood is in play, or the ambient
--- states never arrive: nothing *happens* at two in the morning, so if he only
--- re-checked when a reaction wore off he would sit there wide awake until the
--- next event. Call it on a timer, not every frame — `resolve` reads the ledger.
function Sprite:settle(resolve)
  if self.until_ then
    if os.time() < self.until_ then return end
    self.until_ = nil                     -- the reaction has run its course
  end

  local want = (resolve and resolve()) or self.after or "resting"
  if want == self.mood then return end

  self.mood = want
  self:wear(want)
  self:paintBadge()
end

function Sprite:paintBadge()
  if not self.canvas then return end
  local colour = Mood.colour(self.mood)

  if not colour then
    self.canvas[2].fillColor = { alpha = 0 }
    self.canvas[2].strokeColor = { alpha = 0 }
    return
  end

  self.canvas[2].fillColor = {
    red = colour.red, green = colour.green, blue = colour.blue,
    alpha = self.badgeAlpha or 1,
  }
  self.canvas[2].strokeColor = { red = 0, green = 0, blue = 0, alpha = 0.35 }
end

-- ---------------------------------------------------------------- animation

--- A one-off gesture, layered on top of whatever he is doing.
function Sprite:startle()
  if self.settings.hidden then return end
  self.gesture = { t = 0, span = 0.45, height = 12 }
end

function Sprite:animate()
  local step = 1 / FPS

  self.timer = hs.timer.doEvery(step, function()
    if self.dragging or self.settings.hidden then return end

    local mood = Mood.get(self.mood)
    local motion = mood.motion
    self.phase = self.phase + step

    -- Steady state: a slow float, with a touch of drift so he reads as alive.
    local turn = (self.phase / motion.period) * 2 * math.pi
    local dy = math.sin(turn) * motion.rise
    local dx = (motion.sway > 0) and math.cos(turn * 0.5) * motion.sway or 0

    -- Gesture on top, easing out and draining away.
    if self.gesture then
      self.gesture.t = self.gesture.t + step
      local done = self.gesture.t / self.gesture.span
      if done >= 1 then
        self.gesture = nil
      else
        -- Up fast, back down slower.
        local lift = (done < 0.4)
          and easeOutBack(done / 0.4)
          or (1 - (done - 0.4) / 0.6)
        dy = dy - lift * self.gesture.height
      end
    end

    self.canvas:topLeft({ x = self.x + dx, y = self.y + dy })

    -- Breathe the badge on the moods that want your attention.
    if mood.pulse and mood.badge then
      local swell = math.sin((self.phase / BREATH) * 2 * math.pi)
      self.badgeAlpha = 0.55 + 0.45 * ((swell + 1) / 2)
      self:paintBadge()
    elseif self.badgeAlpha ~= 1 then
      self.badgeAlpha = 1
      self:paintBadge()
    end

    if self.onFrame then self.onFrame() end
  end)
end

-- ------------------------------------------------------------------ pointer

function Sprite:listen()
  self.canvas:canvasMouseEvents(true, true, false, false)
  self.canvas:mouseCallback(function(_, event)
    if event == "mouseDown" then self:grab() end
  end)
end

--- Click-and-hold dragging.
--- The mouse is polled rather than tapped: hs.eventtap needs Accessibility, and
--- refusing to need any macOS permission is worth more than the elegance.
function Sprite:grab()
  local from = hs.mouse.absolutePosition()
  local startX, startY = self.x, self.y
  local travelled = 0
  self.dragging = true

  if self.drag then self.drag:stop() end

  self.drag = hs.timer.doEvery(1 / 60, function()
    local buttons = hs.eventtap.checkMouseButtons()
    if not (buttons.left or buttons[1]) then
      self:release(travelled)
      return
    end

    local now = hs.mouse.absolutePosition()
    local dx, dy = now.x - from.x, now.y - from.y
    travelled = math.max(travelled, math.abs(dx) + math.abs(dy))
    self.x, self.y = self:keepOnScreen(startX + dx, startY + dy)
    self.canvas:topLeft({ x = self.x, y = self.y })
  end)
end

function Sprite:release(travelled)
  self.dragging = false
  if self.drag then self.drag:stop() self.drag = nil end

  if travelled < CLICK_SLOP then
    if self.onTap then self.onTap() end
    return
  end

  self.settings.x, self.settings.y = self.x, self.y
  if self.onMoved then self.onMoved(self.x, self.y) end
end

--- Keep him fully on whichever screen he was dropped nearest.
function Sprite:keepOnScreen(x, y)
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = screen:frame()
  return math.max(f.x, math.min(x, f.x + f.w - self.w)),
         math.max(f.y, math.min(y, f.y + f.h - self.h))
end

-- ------------------------------------------------------------------ showing

function Sprite:show()
  self.settings.hidden = false
  self.canvas:show()
end

function Sprite:hide()
  self.settings.hidden = true
  self.canvas:hide()
end

function Sprite:hidden()
  return self.settings.hidden
end

function Sprite:destroy()
  if self.timer then self.timer:stop() end
  if self.drag then self.drag:stop() end
  if self.canvas then self.canvas:delete() end
end

return Sprite
