--- The notes the fox puts on screen.
---
--- Everything lives in a *single* canvas: notes are laid out as a column inside
--- it and the whole thing is redrawn whenever the set changes. One window means
--- one z-order, one place to hit-test clicks, and no chance of the stack
--- getting out of step with itself when several notes expire at once.
---
--- Each note is a plain table:
---   { title, body, lines = {...}, stamp, chips = {{label, act}}, hold, onOpen,
---     instant }
---
--- Text types itself out. The trick that makes that safe is measuring at the
--- FULL text and revealing a prefix of it: the bubble is its final size from the
--- first frame, so nothing reflows, resizes or jumps while it types.

local Palette = require("foxbot.palette")
local Bubble  = require("foxbot.bubble")

local Panel = {}
Panel.__index = Panel

local FADE = 0.16
local CROSS = { pad = 4, box = 16, reach = 26, shift = 15 }
local MOST_AT_ONCE = 2
local TICK = 1 / 30

function Panel.new()
  return setmetatable({ notes = {}, spots = {}, hot = nil, typeOut = true }, Panel)
end

--- Whether notes reveal themselves letter by letter. The panel is told; it
--- never reads settings itself.
function Panel:types(on)
  self.typeOut = on ~= false
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

--- Work out a note's size and where everything inside it goes, once, at the
--- note's FULL text. Typing then reveals a prefix into the same boxes.
local function measureNote(note)
  local detailed = (note.lines and #note.lines > 0) or (note.chips and #note.chips > 0)
  local wide = detailed and Palette.noteWide or Palette.noteWidth
  local pad = Bubble.padding() + 6
  local inner = wide - pad * 2

  local plan = { inner = inner, pad = pad, lines = {}, chips = {} }

  local titleW, titleH = measure(note.title or "", Palette.head, inner - CROSS.shift)
  local bodyW,  bodyH  = measure(note.body  or "", Palette.body, inner)
  plan.titleH, plan.bodyH = titleH, bodyH

  local y = pad + titleH + 5 + bodyH + 6

  for _, line in ipairs(note.lines or {}) do
    local text = "·  " .. line
    local _, h = measure(text, Palette.body, inner)
    plan.lines[#plan.lines + 1] = { text = text, y = y, h = h }
    y = y + h + 4
  end
  if #plan.lines > 0 then y = y + 4 end

  if note.chips and #note.chips > 0 then
    local x = pad
    for index, chip in ipairs(note.chips) do
      local w = measure(chip.label, Palette.small, inner) + 20
      plan.chips[#plan.chips + 1] =
        { label = chip.label, act = chip.act, index = index, x = x, y = y, w = w }
      x = x + w + Palette.chipGap
    end
    y = y + Palette.chipHeight + 4
  end

  -- Short notes shrink to their text; detailed ones keep the wider column so
  -- the lines have somewhere to breathe.
  local naturalW = math.max(titleW + CROSS.shift, bodyW) + pad * 2
  local width = detailed and wide or math.min(wide, naturalW)

  -- Round out to whole bubble cells, so the art never lands on a half unit.
  local cols, rows, w, h = Bubble.fit(width, y + pad - 4, true)
  plan.cols, plan.rows, plan.width, plan.height = cols, rows, w, h
  return plan
end

--- Everything that types, in order, as one string per segment.
local function segments(note)
  local out = {}
  if note.body and note.body ~= "" then
    out[#out + 1] = { kind = "body", text = note.body }
  end
  for index, line in ipairs((note.plan or {}).lines or {}) do
    out[#out + 1] = { kind = "line", index = index, text = line.text }
  end
  return out
end

--- How much of `text` to show, given a budget of characters, and how much
--- budget is left afterwards.
local function reveal(text, budget)
  if budget >= utf8.len(text or "") then return text, budget - utf8.len(text or "") end
  if budget <= 0 then return "", 0 end
  local offset = utf8.offset(text, budget + 1)
  return text:sub(1, (offset or 1) - 1), 0
end

function Panel:render()
  if #self.notes == 0 then
    self:teardown()
    return
  end

  local c = Palette.colours()
  local ink = { edge = c.bubbleEdge, fill = c.bubbleFill, shadow = c.bubbleShadow }

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

  for _, note in ipairs(self.notes) do
    local plan = note.plan
    local left = 0
    local pad = plan.pad

    -- The bubble itself: sixteen rectangles, whatever the size.
    for _, element in ipairs(Bubble.elements(left, top, plan.cols, plan.rows,
                                             note.tail or "left", ink)) do
      add(element)
    end

    local crossHot = (self.hot and self.hot.note == note and self.hot.cross)
    add({
      type = "text",
      text = styled("✕", Palette.tiny, crossHot and c.bubbleEdge or c.bubbleFaint),
      frame = { x = left + pad, y = top + pad - 2, w = CROSS.box, h = CROSS.box },
    })

    add({
      type = "text",
      text = styled(note.title or "", Palette.head, c.bubbleEdge),
      frame = { x = left + pad + CROSS.shift, y = top + pad,
                w = plan.inner - CROSS.shift, h = plan.titleH },
    })

    if note.stamp and note.stamp ~= "" then
      add({
        type = "text",
        text = styled(note.stamp, Palette.small, c.bubbleFaint, "right"),
        frame = { x = left + plan.width - pad - 130, y = top + pad + 1,
                  w = 130, h = 16 },
      })
    end

    -- Body and lines, revealed up to the typed budget.
    local budget = note.typed or math.huge
    for _, seg in ipairs(segments(note)) do
      local shown, spare = reveal(seg.text, budget)
      budget = spare
      if shown ~= "" then
        if seg.kind == "body" then
          add({
            type = "text",
            text = styled(shown, Palette.body, c.bubbleInk),
            frame = { x = left + pad, y = top + pad + plan.titleH + 5,
                      w = plan.inner, h = plan.bodyH },
          })
        else
          local line = plan.lines[seg.index]
          add({
            type = "text",
            text = styled(shown, Palette.body, c.bubbleInk),
            frame = { x = left + pad, y = top + line.y, w = plan.inner, h = line.h },
          })
        end
      end
      if budget <= 0 then break end
    end

    -- Buttons only once he's finished speaking.
    if not note.typing then
      for _, chip in ipairs(plan.chips) do
        local lit = (self.hot and self.hot.note == note and self.hot.chip == chip.index)
        add({
          type = "rectangle", action = "strokeAndFill",
          roundedRectRadii = { xRadius = 3, yRadius = 3 },
          fillColor = lit and c.bubbleGlow or { alpha = 0 },
          strokeColor = lit and c.bubbleEdge or c.bubbleFaint, strokeWidth = 1,
          frame = { x = left + chip.x, y = top + chip.y,
                    w = chip.w, h = Palette.chipHeight },
        })
        add({
          type = "text",
          text = styled(chip.label, Palette.small,
                        lit and c.bubbleEdge or c.bubbleFaint, "center"),
          frame = { x = left + chip.x, y = top + chip.y + 6, w = chip.w, h = 18 },
        })
      end
    end

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

-- ----------------------------------------------------------------- typing

local function totalChars(note)
  local n = 0
  for _, seg in ipairs(segments(note)) do n = n + (utf8.len(seg.text) or #seg.text) end
  return n
end

--- Give a note the rest of its text at once, and start its dismiss timer.
function Panel:finishTyping(note)
  note.typed = note.total
  note.typing = false
  if not note.expires then
    note.expires = hs.timer.doAfter(note.hold or Palette.linger, function()
      self:dismiss(note)
    end)
  end
end

function Panel:startTyping()
  if self.typer then return end
  self.typer = hs.timer.doEvery(TICK, function()
    local any = false
    for _, note in ipairs(self.notes) do
      if note.typing then
        note.typed = math.min(note.total, (note.typed or 0) + Palette.typeRate * TICK)
        if note.typed >= note.total then
          self:finishTyping(note)
        else
          any = true
        end
      end
    end
    self:render()
    if not any then
      self.typer:stop()
      self.typer = nil
    end
  end)
end

-- -------------------------------------------------------------------- notes

function Panel:say(note)
  note.plan = measureNote(note)
  note.total = totalChars(note)

  -- A catch-up summary shouldn't make you sit through it typing, and neither
  -- should anything with nothing to type.
  if note.instant or note.total == 0 or not self.typeOut or Palette.typeRate <= 0 then
    note.typed, note.typing = note.total, false
    note.expires = hs.timer.doAfter(note.hold or Palette.linger, function()
      self:dismiss(note)
    end)
  else
    -- The dismiss timer deliberately does NOT start yet: a long note would
    -- otherwise fade out halfway through its own sentence.
    note.typed, note.typing = 0, true
  end

  self.notes[#self.notes + 1] = note

  -- Two on screen is a stack; three is a wall.
  while #self.notes > MOST_AT_ONCE do self:drop(self.notes[1], "evicted") end

  -- And never let the column grow past the screen either.
  local limit = (self.screen and self.screen.h or 900) - 60
  local total = 0
  for _, held in ipairs(self.notes) do
    total = total + held.plan.height + Palette.leading
  end
  while #self.notes > 1 and total > limit do
    local oldest = self.notes[1]
    total = total - oldest.plan.height - Palette.leading
    self:drop(oldest, "evicted")
  end

  self:render()
  if note.typing then self:startTyping() end
  return note
end

--- `why` is one of: "expired" (its own timer), "evicted" (pushed out by newer
--- notes), "cleared" (the panel was emptied), "cross" (dismissed), "answered"
--- (a button or the body was clicked). The tutorial cares about the difference
--- between being ignored and being answered.
function Panel:drop(note, why)
  for index, held in ipairs(self.notes) do
    if held == note then
      table.remove(self.notes, index)
      break
    end
  end
  if note.expires then note.expires:stop() note.expires = nil end
  note.typing = false
  if self.hot and self.hot.note == note then self.hot = nil end
  if note.onGone then note.onGone(why or "expired") end
end

function Panel:dismiss(note, why)
  self:drop(note, why)
  self:render()
end

function Panel:clear()
  for _, note in ipairs({ table.unpack(self.notes) }) do self:drop(note, "cleared") end
  self.notes = {}
  if self.typer then self.typer:stop() self.typer = nil end
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
  -- The tail points back towards the fox.
  self.tail = (self.anchor and self.screen
               and (frame.x + frame.w / 2) > (self.screen.x + self.screen.w / 2))
              and "right" or "left"
  for _, note in ipairs(self.notes) do note.tail = self.tail end
  if #self.notes > 0 then self:render() end
end

function Panel:count()
  return #self.notes
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

      -- Impatience is a request for the rest of the sentence, not a dismissal.
      -- Clicking mid-type finishes it; clicking again does what you meant.
      if note.typing then
        self:finishTyping(note)
        self:render()
        return
      end

      self:dismiss(note, found.cross and "cross" or "answered")
      if found.act then
        found.act()
      elseif not found.cross and note.onOpen then
        note.onOpen()
      end
      return
    end

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

return Panel
