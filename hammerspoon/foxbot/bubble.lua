--- The blocky speech bubble.
---
--- Notes are drawn as a chamfered pixel-art bubble with a stepped tail and a
--- hard offset shadow, at whatever size the text needs.
---
--- Getting that right by placing a dozen rectangles by hand and hoping they
--- meet is how you end up with hairline seams at some sizes and overlaps at
--- others. Instead the silhouette is built as a grid of cells, the border is
--- *derived* from it by eroding the edge, and the result is merged back into
--- as few rectangles as possible. Any silhouette gets a correct, gapless
--- outline for free — including the tail — and the merge keeps it to sixteen
--- rectangles whether the bubble is small or enormous.

local Bubble = {}

local EMPTY, BODY, EDGE = 0, 1, 2

Bubble.EMPTY, Bubble.BODY, Bubble.EDGE = EMPTY, BODY, EDGE

-- One "pixel" of the art, in points. Everything is a whole number of these, so
-- adjacent rectangles always share an exact edge and never leave a seam.
Bubble.unit = 3
Bubble.border = 2        -- units
Bubble.chamfer = 2       -- units the corners step in
Bubble.shadow = 1        -- units, offset down-right
Bubble.tailDepth = 4     -- units tall
Bubble.tailWidth = 5     -- units wide where it meets the bubble
Bubble.tailInset = 3     -- units from the near edge

-- ------------------------------------------------------------------- shape

--- A chamfered rectangle, plus a tail stepping down to a point.
local function silhouette(cols, rows, tailSide)
  local grid = {}
  local body = rows - (tailSide and Bubble.tailDepth or 0)

  for y = 1, rows do
    grid[y] = {}
    for x = 1, cols do grid[y][x] = EMPTY end
  end

  for y = 1, body do
    -- Cut the corners on the diagonal: this is what reads as pixel art rather
    -- than as a rounded rectangle.
    local fromEdge = math.min(y - 1, body - y)
    local cut = math.max(0, Bubble.chamfer - fromEdge)
    for x = 1 + cut, cols - cut do grid[y][x] = BODY end
  end

  if tailSide then
    for i = 0, Bubble.tailDepth - 1 do
      local y = body + i + 1
      if y <= rows then
        -- Each row loses a cell, so the outer edge walks diagonally to a point.
        local run = math.max(1, Bubble.tailWidth - i)
        local from
        if tailSide == "left" then
          from = 1 + Bubble.tailInset
        else
          from = cols - Bubble.tailInset - run + 1
        end
        for x = from, math.min(cols, from + run - 1) do
          if x >= 1 then grid[y][x] = BODY end
        end
      end
    end
  end

  return grid
end

--- Mark the outer `thickness` cells as border by eroding the edge that often.
local function outline(grid, cols, rows, thickness)
  for _ = 1, thickness do
    local edge = {}
    for y = 1, rows do
      for x = 1, cols do
        if grid[y][x] == BODY then
          local surrounded =
            (y > 1    and grid[y - 1][x] == BODY) and
            (y < rows and grid[y + 1][x] == BODY) and
            (x > 1    and grid[y][x - 1] == BODY) and
            (x < cols and grid[y][x + 1] == BODY)
          if not surrounded then edge[#edge + 1] = { x, y } end
        end
      end
    end
    for _, at in ipairs(edge) do grid[at[2]][at[1]] = EDGE end
  end
  return grid
end

--- Merge cells into as few rectangles as possible.
---
--- Encoding row by row is correct but emits one rectangle per row, which for a
--- note-sized bubble is a couple of hundred canvas elements. Growing each run
--- downwards while it stays uniform collapses the flat expanses; the result is
--- sixteen rectangles at any size.
local function mesh(grid, cols, rows)
  local taken = {}
  for y = 1, rows do taken[y] = {} end

  local out = {}
  for y = 1, rows do
    for x = 1, cols do
      local kind = grid[y][x]
      if kind ~= EMPTY and not taken[y][x] then
        local w = 0
        while x + w <= cols and grid[y][x + w] == kind and not taken[y][x + w] do
          w = w + 1
        end

        local h = 1
        local growing = true
        while growing and y + h <= rows do
          for i = 0, w - 1 do
            if grid[y + h][x + i] ~= kind or taken[y + h][x + i] then
              growing = false
              break
            end
          end
          if growing then h = h + 1 end
        end

        for yy = y, y + h - 1 do
          for xx = x, x + w - 1 do taken[yy][xx] = true end
        end
        out[#out + 1] = { x = x - 1, y = y - 1, w = w, h = h, kind = kind }
      end
    end
  end
  return out
end

-- The shape only depends on its size and which way the tail points, and notes
-- reuse a handful of sizes. Building it costs a pass over every cell, and the
-- panel redraws on every hover, so the result is kept.
local cache = {}

--- Cells and rectangles for a bubble `cols` x `rows` cells.
--- @return table rects, number bodyRows  (rows excluding the tail)
function Bubble.shape(cols, rows, tailSide)
  local key = cols .. "x" .. rows .. (tailSide or "none")
  if cache[key] then return cache[key] end

  local grid = silhouette(cols, rows, tailSide)
  outline(grid, cols, rows, Bubble.border)
  local rects = mesh(grid, cols, rows)

  cache[key] = rects
  return rects
end

--- How many cells wide/tall a bubble needs to be to hold `w` x `h` points,
--- and the exact size in points it will occupy.
function Bubble.fit(w, h, withTail)
  local unit = Bubble.unit
  local cols = math.ceil(w / unit)
  local rows = math.ceil(h / unit) + (withTail and Bubble.tailDepth or 0)
  return cols, rows, cols * unit, rows * unit
end

--- The inner area a bubble of this size can hold text in, in points.
function Bubble.padding()
  return (Bubble.border + Bubble.chamfer) * Bubble.unit
end

--- Build the canvas elements for one bubble.
--- @param x,y  top-left in canvas points
--- @param cols,rows  size in cells (from Bubble.fit)
--- @param colours { edge, fill, shadow }
function Bubble.elements(x, y, cols, rows, tailSide, colours)
  local unit = Bubble.unit
  local rects = Bubble.shape(cols, rows, tailSide)
  local out = {}

  -- The silhouette again, offset, underneath everything — a hard pixel shadow
  -- rather than a soft blur, to match the rest of the drawing.
  local drop = Bubble.shadow * unit
  for _, r in ipairs(rects) do
    out[#out + 1] = {
      type = "rectangle", action = "fill", fillColor = colours.shadow,
      frame = { x = x + r.x * unit + drop, y = y + r.y * unit + drop,
                w = r.w * unit, h = r.h * unit },
    }
  end

  for _, r in ipairs(rects) do
    out[#out + 1] = {
      type = "rectangle", action = "fill",
      fillColor = (r.kind == EDGE) and colours.edge or colours.fill,
      frame = { x = x + r.x * unit, y = y + r.y * unit,
                w = r.w * unit, h = r.h * unit },
    }
  end

  return out
end

return Bubble
