--- The fox's control panel.
---
--- Built on the same primitives as the notes: one canvas, a laid-out column,
--- redrawn whenever anything changes, clicks traced back through the rects that
--- layout produced. Nothing here is an AppKit menu, so it can carry a live
--- status header, real toggle switches, a strip of today's numbers, and the
--- fox's own palette — none of which a system menu can express.
---
--- Row kinds:
---   status  a headline with a coloured dot        stats  three small figures
---   label   a small-caps section heading          sep    a hairline
---   row     an action, optionally with a value and a keyboard hint
---   toggle  a switch                              choice a radio dot
---   into    opens a sub-page in place             back   returns from one

local Palette = require("foxbot.palette")

local Menu = {}
Menu.__index = Menu

local FADE = 0.10
local W = 302                 -- panel width
local PAD = 14                -- outer padding
local INSET = 10              -- row inset from the panel edge
local RADIUS = 14

local H = {                   -- row heights
  status = 52, stats = 46, label = 26, sep = 11,
  row = 32, toggle = 32, choice = 32, into = 32, back = 34,
  segment = 50, stepper = 32,
}
local NOTE_EXTRA = 15         -- extra height when a row carries a note

function Menu.new()
  return setmetatable({ rows = {}, hot = nil, trail = {} }, Menu)
end

local function text(str, size, colour, align, weight)
  return hs.styledtext.new(str, {
    font = { name = weight == "bold" and (Palette.face .. "-Bold") or Palette.face,
             size = size },
    color = colour,
    paragraphStyle = { lineBreak = "truncateTail", alignment = align or "left" },
  })
end

local function heightOf(row)
  local base = H[row.kind] or H.row
  if row.note then base = base + NOTE_EXTRA end
  return base
end

-- -------------------------------------------------------------------- paint

function Menu:paint()
  local c = Palette.colours()
  local canvas = self.canvas
  if not canvas then return end

  local parts = {}
  local function add(e) parts[#parts + 1] = e end

  -- The card itself.
  add({
    type = "rectangle", action = "strokeAndFill",
    roundedRectRadii = { xRadius = RADIUS, yRadius = RADIUS },
    fillColor = c.panel, strokeColor = c.edge, strokeWidth = 1,
    frame = { x = 0, y = 0, w = W, h = self.height },
  })

  self.hits = {}
  local y = PAD

  -- The status line and the stats strip double as navigation. A row carrying a
  -- page gets a chevron, a hover wash and a hit target, drawn underneath its
  -- own content so it reads as one thing.
  local index          -- set by the loop below; captured here
  local function door(row, top, height, hot)
    if not row.page then return end
    self.hits[#self.hits + 1] = { index = index, y = top, h = height - 2, row = row }
    if hot then
      add({
        type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = 8, yRadius = 8 },
        fillColor = c.glow,
        frame = { x = INSET - 4, y = top - 2, w = W - (INSET - 4) * 2, h = height },
      })
    end
    add({
      type = "text",
      text = text("›", Palette.head + 3, hot and c.fur or c.faded, "right"),
      frame = { x = W - INSET - 12, y = top + height / 2 - 13, w = 12, h = 22 },
    })
  end

  for _index, row in ipairs(self.rows) do
    index = _index
    local h = heightOf(row)
    local kind = row.kind or "row"
    local hot = (self.hot == index)

    if kind == "sep" then
      add({
        type = "rectangle", action = "fill", fillColor = c.hair,
        frame = { x = INSET + 6, y = y + 5, w = W - (INSET + 6) * 2, h = 1 },
      })

    elseif kind == "label" then
      add({
        type = "text",
        text = text(row.title:upper(), Palette.small - 0.5, c.faded),
        frame = { x = INSET + 8, y = y + 8, w = W - INSET * 2, h = 16 },
      })

    elseif kind == "status" then
      door(row, y, h, hot)
      -- A dot the colour of whatever he's feeling, then the headline.
      local dot = c[row.tone or "faded"] or c.faded
      add({
        type = "circle", action = "fill", fillColor = dot,
        center = { x = INSET + 14, y = y + 17 }, radius = 5,
      }, {
        type = "text",
        text = text(row.title, Palette.head + 1.5, c.ink, nil, "bold"),
        frame = { x = INSET + 26, y = y + 7, w = W - INSET * 2 - 26, h = 20 },
      })
      if row.detail then
        add({
          type = "text",
          text = text(row.detail, Palette.small, c.faded),
          frame = { x = INSET + 26, y = y + 27, w = W - INSET * 2 - 26, h = 16 },
        })
      end

    elseif kind == "stats" then
      door(row, y, h, hot)
      -- Three figures across, value over label.
      local slot = (W - INSET * 2) / #row.items
      for i, item in ipairs(row.items) do
        local x = INSET + slot * (i - 1)
        add({
          type = "text",
          text = text(item.value, Palette.head, c.fur, "center", "bold"),
          frame = { x = x, y = y + 2, w = slot, h = 20 },
        }, {
          type = "text",
          text = text(item.label:upper(), Palette.small - 1.5, c.faded, "center"),
          frame = { x = x, y = y + 22, w = slot, h = 14 },
        })
      end

    elseif kind == "segment" then
      -- A row of equal zones with the chosen one filled. One tap target per
      -- option rather than a list you have to open.
      local zoneW = (W - INSET * 2) / #row.options
      add({
        type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = 7, yRadius = 7 },
        fillColor = c.hair,
        frame = { x = INSET, y = y + 2, w = W - INSET * 2, h = 26 },
      })
      for i, id in ipairs(row.options) do
        local chosen = (row.on == id)
        local zx = INSET + zoneW * (i - 1)
        if chosen then
          add({
            type = "rectangle", action = "fill",
            roundedRectRadii = { xRadius = 6, yRadius = 6 },
            fillColor = c.fur,
            frame = { x = zx + 2, y = y + 4, w = zoneW - 4, h = 22 },
          })
        end
        local label = row.labels and (type(row.labels) == "function"
                        and row.labels(id) or row.labels[id]) or id
        add({
          type = "text",
          text = text(label, Palette.small, chosen and c.panel or c.faded, "center"),
          frame = { x = zx, y = y + 9, w = zoneW, h = 16 },
        })
      end
      if row.note then
        add({
          type = "text",
          text = text(row.note, Palette.small - 0.5, c.faded, "center"),
          frame = { x = INSET, y = y + 31, w = W - INSET * 2, h = 16 },
        })
      end
      self.hits[#self.hits + 1] =
        { index = index, y = y, h = h - 2, row = row, zones = row.options, zoneW = zoneW }

    else
      if hot then
        add({
          type = "rectangle", action = "fill",
          roundedRectRadii = { xRadius = 8, yRadius = 8 },
          fillColor = c.glow,
          frame = { x = INSET - 4, y = y, w = W - (INSET - 4) * 2, h = h - 2 },
        })
      end

      local ink = hot and c.fur or c.ink
      if row.tone then ink = c[row.tone] or ink end

      local titleX = INSET + 8
      local titleW = W - titleX - INSET - 8

      -- A radio dot sits before the label so choices line up down the page.
      if kind == "choice" then
        add({
          type = "circle",
          action = row.on and "fill" or "stroke",
          fillColor = c.fur, strokeColor = c.hair, strokeWidth = 1.5,
          center = { x = titleX + 5, y = y + h / 2 - (row.note and NOTE_EXTRA / 2 or 0) },
          radius = 4.5,
        })
        titleX = titleX + 18
        titleW = titleW - 18
      end

      local rowMid = y + (h - (row.note and NOTE_EXTRA or 0)) / 2

      -- Right-hand furniture: a switch, a chevron, a value, a key hint.
      local rightEdge = W - INSET - 8

      if kind == "toggle" then
        local tw, th = 30, 17
        local tx, ty = rightEdge - tw, rowMid - th / 2
        add({
          type = "rectangle", action = "fill",
          roundedRectRadii = { xRadius = th / 2, yRadius = th / 2 },
          fillColor = row.on and c.fur or c.hair,
          frame = { x = tx, y = ty, w = tw, h = th },
        }, {
          type = "circle", action = "fill", fillColor = c.panel,
          center = { x = row.on and (tx + tw - th / 2) or (tx + th / 2), y = ty + th / 2 },
          radius = th / 2 - 2.5,
        })
        titleW = titleW - tw - 10

      elseif kind == "stepper" then
        add({
          type = "text",
          text = text("＋", Palette.small, hot and c.fur or c.faded, "right"),
          frame = { x = rightEdge - 14, y = rowMid - 8, w = 14, h = 16 },
        })
        titleW = titleW - 20
        rightEdge = rightEdge - 20

      elseif kind == "into" then
        add({
          type = "text",
          text = text("›", Palette.head + 3, hot and c.fur or c.faded, "right"),
          frame = { x = rightEdge - 12, y = rowMid - 12, w = 12, h = 22 },
        })
        titleW = titleW - 18
        rightEdge = rightEdge - 18
      end

      if row.keys then
        -- A key hint, set in a soft cap so it reads as a shortcut not a value.
        local kw = #row.keys * 7 + 12
        add({
          type = "rectangle", action = "fill",
          roundedRectRadii = { xRadius = 5, yRadius = 5 },
          fillColor = c.hair,
          frame = { x = rightEdge - kw, y = rowMid - 9, w = kw, h = 18 },
        }, {
          type = "text",
          text = text(row.keys, Palette.small - 1, c.faded, "center"),
          frame = { x = rightEdge - kw, y = rowMid - 7, w = kw, h = 16 },
        })
        titleW = titleW - kw - 10
        rightEdge = rightEdge - kw - 10

      elseif row.value then
        add({
          type = "text",
          text = text(row.value, Palette.small, c.faded, "right"),
          frame = { x = rightEdge - 130, y = rowMid - 8, w = 130, h = 16 },
        })
        titleW = titleW - 100
      end

      add({
        type = "text",
        text = text(row.title, Palette.menu or Palette.body + 0.5, ink),
        frame = { x = titleX, y = rowMid - 9, w = math.max(40, titleW), h = 18 },
      })

      if row.note then
        add({
          type = "text",
          text = text(row.note, Palette.small - 0.5, c.faded),
          frame = { x = titleX, y = y + h - NOTE_EXTRA - 2,
                    w = W - titleX - INSET, h = 16 },
        })
      end

      if row.act or row.page or kind == "back" then
        self.hits[#self.hits + 1] = { index = index, y = y, h = h - 2, row = row }
      end
    end

    y = y + h
  end

  canvas:replaceElements(table.unpack(parts))
end

-- ------------------------------------------------------------------ layout

local function measure(rows)
  local total = PAD * 2
  for _, row in ipairs(rows) do total = total + heightOf(row) end
  return total
end

-- Exposed so the page tests can assert nothing renders past the screen edge.
Menu.measure = measure
Menu.heightOf = heightOf
Menu.W = W

function Menu:fill(rows)
  self.rows = rows
  self.hot = nil
  self.height = measure(rows)

  local screen = self.screen or hs.screen.mainScreen():frame()
  local top = self.canvas:topLeft()
  local y = math.max(screen.y + 8,
                     math.min(top.y, screen.y + screen.h - self.height - 8))
  self.canvas:frame({ x = top.x, y = y, w = W, h = self.height })
  self:paint()
end

--- Open a sub-page, remembering how to get back. `pageNow` is what a toggle
--- re-runs to redraw in place, so it has to follow you down and back up.
function Menu:descend(page, backTo)
  table.insert(self.trail, backTo)
  self.pageNow = page
  self:fill(page())
end

function Menu:ascend()
  local back = table.remove(self.trail)
  if not back then return end
  self.pageNow = back
  self:fill(back())
end

function Menu:rowAt(y)
  for _, hit in ipairs(self.hits or {}) do
    if y >= hit.y and y < hit.y + hit.h then return hit end
  end
  return nil
end

function Menu:open(rows, point, screen)
  self:close()
  self.trail = {}

  local target = screen or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local frame = target:frame()
  self.screen = frame
  self.height = measure(rows)
  self.rows = rows

  local x = math.max(frame.x + 8,
                     math.min(point.x - W / 2, frame.x + frame.w - W - 8))
  local y = math.max(frame.y + 8,
                     math.min(point.y - 20, frame.y + frame.h - self.height - 8))

  -- A transparent sheet behind it, so a click anywhere else closes the panel
  -- without needing an event tap (and therefore without needing permission).
  self.sheet = hs.canvas.new(frame)
  self.sheet:level(hs.canvas.windowLevels.floating + 1)
  self.sheet:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                    | hs.canvas.windowBehaviors.stationary)
  self.sheet:clickActivating(false)
  self.sheet[1] = {
    type = "rectangle", action = "fill",
    fillColor = { white = 0, alpha = 0.001 },
    frame = { x = 0, y = 0, w = frame.w, h = frame.h },
  }
  self.sheet:canvasMouseEvents(true, false, false, false)
  self.sheet:mouseCallback(function() self:close() end)
  self.sheet:show()

  self.canvas = hs.canvas.new({ x = x, y = y, w = W, h = self.height })
  self.canvas:level(hs.canvas.windowLevels.floating + 2)
  self.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                     | hs.canvas.windowBehaviors.stationary)
  self.canvas:clickActivating(false)
  self:paint()

  self.canvas:canvasMouseEvents(true, true, true, true)
  self.canvas:mouseCallback(function(_, event, _, mx, my)
    if event == "mouseExit" then
      if self.hot then self.hot = nil self:paint() end
      return
    end

    local hit = self:rowAt(my)

    if event == "mouseUp" then
      if not hit then return end
      local row = hit.row
      if row.kind == "segment" then
        -- Which zone was tapped.
        local i = math.floor((mx - INSET) / hit.zoneW) + 1
        local id = hit.zones[math.max(1, math.min(#hit.zones, i))]
        row.act(id)
        local rebuild = self.pageNow
        self:fill(rebuild and rebuild() or rows)
      elseif row.kind == "back" then
        self:ascend()
      elseif row.page then
        self:descend(row.page, self.pageNow or function() return rows end)
      else
        -- Toggles and choices keep the panel open so you can see the change;
        -- anything else is a command, and closes it.
        if row.kind == "toggle" or row.kind == "choice" or row.kind == "stepper" then
          row.act()
          local rebuild = self.pageNow
          self:fill(rebuild and rebuild() or rows)
        else
          self:close()
          row.act()
        end
      end
      return
    end

    local index = hit and hit.index or nil
    if index ~= self.hot then
      self.hot = index
      self:paint()
    end
  end)

  self.canvas:show(FADE)
end

--- Remember how to rebuild the page currently showing, so a toggle can redraw
--- it without closing.
function Menu:showing(builder)
  self.pageNow = builder
end

function Menu:close()
  if self.canvas then
    local canvas = self.canvas
    self.canvas = nil
    canvas:hide(FADE)
    hs.timer.doAfter(FADE + 0.05, function() canvas:delete() end)
  end
  if self.sheet then
    self.sheet:delete()
    self.sheet = nil
  end
  self.trail = {}
end

function Menu:isOpen()
  return self.canvas ~= nil
end

return Menu
