--- The notes the fox puts on screen.
---
--- Everything lives in a *single* canvas: notes are laid out as a column inside
--- it and the whole thing is redrawn whenever the set changes. One window means
--- one z-order, one place to hit-test clicks, and no chance of the stack
--- getting out of step with itself when several notes expire at once.
---
--- Each note is a plain table:
---   { title, body, lines = {...}, stamp, chips = {{label, act}}, hold, onOpen }

local Palette = require("foxbot.palette")

local Panel = {}
Panel.__index = Panel

local FADE = 0.16
local CROSS = { pad = 11, box = 16, reach = 26, shift = 15 }
local MOST_AT_ONCE = 2

function Panel.new()
  return setmetatable({ notes = {}, spots = {}, hot = nil }, Panel)
end

-- ------------------------------------------------------------------ drawing

local function styled(text, size, colour, align)
  return hs.styledtext.new(text, {
    font = { name = Palette.face, size = size },
    color = colour,
    paragraphStyle = {
      lineBreak = "wordWrap",
      lineSpacing = 2,
      alignment = align or "left",
    },
  })
end

Panel.styled = styled

--- How tall `text` wraps to at `width`.
local function measure(text, size, width)
  local box = hs.drawing.getTextDrawingSize(
    styled(text, size, { white = 1 }), { w = width })
  return math.ceil(box.w), math.ceil(box.h)
end

--- Work out a note's size and the position of everything inside it, once.
--- Doing this up front means render and hit-testing read the same numbers.
local function measureNote(note)
  local detailed = (note.lines and #note.lines > 0) or (note.chips and #note.chips > 0)
  local width = detailed and Palette.noteWide or Palette.noteWidth
  local inner = width - Palette.pad * 2

  local plan = { width = width, inner = inner, lines = {}, chips = {} }

  local titleW, titleH = measure(note.title or "", Palette.head, inner - CROSS.shift)
  local bodyW,  bodyH  = measure(note.body  or "", Palette.body, inner)
  plan.titleH, plan.bodyH = titleH, bodyH

  local y = Palette.pad + titleH + 5 + bodyH + 6

  for _, line in ipairs(note.lines or {}) do
    local text = "·  " .. line
    local _, h = measure(text, Palette.body, inner)
    plan.lines[#plan.lines + 1] = { text = text, y = y, h = h }
    y = y + h + 4
  end
  if #plan.lines > 0 then y = y + 4 end

  if note.chips and #note.chips > 0 then
    local x = Palette.pad
    for index, chip in ipairs(note.chips) do
      local w = measure(chip.label, Palette.small, inner) + 20
      plan.chips[#plan.chips + 1] =
        { label = chip.label, act = chip.act, index = index, x = x, y = y, w = w }
      x = x + w + Palette.chipGap
    end
    y = y + Palette.chipHeight + 4
  end

  -- Narrow notes shrink to their text; detailed ones keep the wider column so
  -- the bullet lines have somewhere to breathe.
  if not detailed then
    plan.width = math.min(width,
      math.max(titleW + CROSS.shift, bodyW) + Palette.pad * 2)
  end
  plan.height = y + Palette.pad - 4
  return plan
end

--- Rebuild the canvas from scratch. Cheap enough at this size, and it removes
--- every "the elements drifted out of sync with the model" bug.
function Panel:render()
  if #self.notes == 0 then
    self:teardown()
    return
  end

  local colours = Palette.colours()

  local width, height = 0, 0
  for _, note in ipairs(self.notes) do
    width = math.max(width, note.plan.width)
    height = height + note.plan.height + Palette.leading
  end
  height = height - Palette.leading

  local frame = self:place(width, height)
  if not self.canvas then
    self.canvas = hs.canvas.new(frame)
    self.canvas:level(hs.canvas.windowLevels.floating)
    self.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                       | hs.canvas.windowBehaviors.stationary)
    self.canvas:clickActivating(false)
    self:wire()
    self.canvas:show(FADE)
  else
    self.canvas:frame(frame)
  end

  local elements = {}
  local function add(e) elements[#elements + 1] = e end

  self.spots = {}
  local top = 0

  -- Oldest at the top of the column, newest nearest the fox.
  for _, note in ipairs(self.notes) do
    local plan = note.plan
    local left = 0                       -- notes are left-aligned in the panel

    add({
      type = "rectangle", action = "strokeAndFill",
      roundedRectRadii = { xRadius = 12, yRadius = 12 },
      fillColor = colours.panel, strokeColor = colours.edge, strokeWidth = 1,
      frame = { x = left, y = top, w = plan.width, h = plan.height },
    })

    local crossHot = (self.hot and self.hot.note == note and self.hot.cross)
    add({
      type = "text",
      text = styled("✕", Palette.tiny, crossHot and colours.fur or colours.faded),
      frame = { x = left + CROSS.pad, y = top + CROSS.pad,
                w = CROSS.box, h = CROSS.box },
    })

    add({
      type = "text",
      text = styled(note.title or "", Palette.head, colours.fur),
      frame = { x = left + Palette.pad + CROSS.shift, y = top + Palette.pad,
                w = plan.inner - CROSS.shift, h = plan.titleH },
    })

    if note.stamp and note.stamp ~= "" then
      add({
        type = "text",
        text = styled(note.stamp, Palette.small, colours.faded, "right"),
        frame = { x = left + plan.width - Palette.pad - 130,
                  y = top + Palette.pad + 1, w = 130, h = 16 },
      })
    end

    add({
      type = "text",
      text = styled(note.body or "", Palette.body, colours.faded),
      frame = { x = left + Palette.pad, y = top + Palette.pad + plan.titleH + 5,
                w = plan.inner, h = plan.bodyH },
    })

    for _, line in ipairs(plan.lines) do
      add({
        type = "text",
        text = styled(line.text, Palette.body, colours.ink),
        frame = { x = left + Palette.pad, y = top + line.y,
                  w = plan.inner, h = line.h },
      })
    end

    for _, chip in ipairs(plan.chips) do
      local lit = (self.hot and self.hot.note == note and self.hot.chip == chip.index)
      add({
        type = "rectangle", action = "strokeAndFill",
        roundedRectRadii = { xRadius = 6, yRadius = 6 },
        fillColor = lit and colours.glow or { alpha = 0 },
        strokeColor = lit and colours.fur or colours.hair, strokeWidth = 1,
        frame = { x = left + chip.x, y = top + chip.y,
                  w = chip.w, h = Palette.chipHeight },
      })
      add({
        type = "text",
        text = styled(chip.label, Palette.small,
                      lit and colours.fur or colours.faded, "center"),
        frame = { x = left + chip.x, y = top + chip.y + 6, w = chip.w, h = 18 },
      })
    end

    -- Remember where this note landed so a click can be traced back to it.
    self.spots[#self.spots + 1] =
      { note = note, x = left, y = top, w = plan.width, h = plan.height }

    top = top + plan.height + Palette.leading
  end

  self.canvas:replaceElements(table.unpack(elements))
end

--- Where the panel sits: beside the fox, on whichever side has room, clamped to
--- the screen he is actually on.
function Panel:place(width, height)
  local fox = self.anchor or { x = 0, y = 0, w = Palette.foxWidth, h = 80 }
  local screen = self.screen or hs.screen.mainScreen():frame()

  local leftOfFox = (fox.x + fox.w / 2) > (screen.x + screen.w / 2)
  local x = leftOfFox and (fox.x - width - Palette.gutter)
                      or (fox.x + fox.w + Palette.gutter)
  local y = fox.y + fox.h / 2 - height + Palette.foxWidth / 4

  x = math.max(screen.x + 8, math.min(x, screen.x + screen.w - width - 8))
  y = math.max(screen.y + 8, math.min(y, screen.y + screen.h - height - 8))
  return { x = x, y = y, w = width, h = height }
end

-- ------------------------------------------------------------------ pointer

function Panel:at(x, y)
  for _, spot in ipairs(self.spots) do
    if x >= spot.x and x <= spot.x + spot.w
       and y >= spot.y and y <= spot.y + spot.h then
      local localX, localY = x - spot.x, y - spot.y

      for _, chip in ipairs(spot.note.plan.chips) do
        if localX >= chip.x and localX <= chip.x + chip.w
           and localY >= chip.y and localY <= chip.y + Palette.chipHeight then
          return { note = spot.note, chip = chip.index, act = chip.act }
        end
      end

      local cross = localX <= CROSS.reach and localY <= CROSS.reach
      return { note = spot.note, cross = cross }
    end
  end
  return nil
end

function Panel:wire()
  self.canvas:canvasMouseEvents(true, false, true, true)
  self.canvas:mouseCallback(function(_, event, _, x, y)
    if event == "mouseExit" then
      if self.hot then self.hot = nil self:render() end
      return
    end

    local found = self:at(x, y)

    if event == "mouseDown" then
      if not found then return end
      local note = found.note
      self:dismiss(note)
      if found.act then
        found.act()
      elseif not found.cross and note.onOpen then
        note.onOpen()
      end
      return
    end

    -- Hover: only redraw when the highlight actually moves.
    local before = self.hot
    local same = before and found
      and before.note == found.note
      and before.chip == found.chip
      and before.cross == found.cross
    if not same then
      self.hot = found
      self:render()
    end
  end)
end

-- -------------------------------------------------------------------- notes

function Panel:say(note)
  note.plan = measureNote(note)
  note.expires = hs.timer.doAfter(note.hold or Palette.linger, function()
    self:dismiss(note)
  end)

  self.notes[#self.notes + 1] = note

  -- Two on screen is a stack; three is a wall. Whatever the screen could fit,
  -- the oldest goes as soon as there are more than a couple.
  while #self.notes > MOST_AT_ONCE do self:drop(self.notes[1]) end

  -- And never let the column grow past the screen either; the oldest goes first.
  local limit = (self.screen and self.screen.h or 900) - 60
  local total = 0
  for _, held in ipairs(self.notes) do
    total = total + held.plan.height + Palette.leading
  end
  while #self.notes > 1 and total > limit do
    local oldest = self.notes[1]
    total = total - oldest.plan.height - Palette.leading
    self:drop(oldest)
  end

  self:render()
  return note
end

function Panel:drop(note)
  for index, held in ipairs(self.notes) do
    if held == note then
      table.remove(self.notes, index)
      break
    end
  end
  if note.expires then note.expires:stop() note.expires = nil end
  if self.hot and self.hot.note == note then self.hot = nil end
end

function Panel:dismiss(note)
  self:drop(note)
  self:render()
end

function Panel:clear()
  for _, note in ipairs({ table.unpack(self.notes) }) do self:drop(note) end
  self.notes = {}
  self:teardown()
end

function Panel:teardown()
  if not self.canvas then return end
  local canvas = self.canvas
  self.canvas = nil
  self.spots = {}
  canvas:hide(FADE)
  hs.timer.doAfter(FADE + 0.05, function() canvas:delete() end)
end

--- Tell the panel where the fox is, and which screen that is.
function Panel:anchorTo(frame, screen)
  self.anchor = frame
  self.screen = screen and screen:frame() or nil
  if #self.notes > 0 then self:render() end
end

function Panel:count()
  return #self.notes
end

return Panel
