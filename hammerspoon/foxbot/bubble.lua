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
Bubble.unit = 2
Bubble.border = 2        -- units
Bubble.chamfer = 2       -- units the corners step in
Bubble.shadow = 1        -- units, offset down-right
-- The tail comes off the SIDE, vertically centred, and tapers to a point.
-- It used to hang off the bottom corner as a small staircase, which stopped
-- well short of the fox and read as belonging to nothing.
Bubble.tailReach = 5     -- units it sticks out sideways
Bubble.tailHalf  = 4     -- half its height where it meets the body
Bubble.tailSlope = 1     -- rows lost per column out; higher = stubbier

-- ------------------------------------------------------------------- shape

--- A chamfered rectangle with a tapering tail off one side.
---
--- The tail is vertically centred and points outwards, so a bubble sitting
--- beside the fox aims straight at him. `cols` includes the tail's reach.
local function silhouette(cols, rows, tailSide)
  local grid = {}
  local reach = tailSide and Bubble.tailReach or 0
  local body = cols - reach

  for y = 1, rows do
    grid[y] = {}
    for x = 1, cols do grid[y][x] = EMPTY end
  end

  -- Which columns the body occupies; the tail takes the rest of one side.
  local from = (tailSide == "left") and (reach + 1) or 1
  local to = (tailSide == "left") and cols or body

  for y = 1, rows do
    -- Cut the corners on the diagonal: this is what reads as pixel art rather
    -- than as a rounded rectangle.
    local fromEdge = math.min(y - 1, rows - y)
    local cut = math.max(0, Bubble.chamfer - fromEdge)
    for x = from + cut, to - cut do grid[y][x] = BODY end
  end

  return grid
end

--- Stamp the tail on after the body has been outlined.
---
--- Drawn explicitly rather than derived: it tapers to a point, and eroding two
--- cells off something that thin leaves no interior, which is how it ended up
--- looking like a hollow arrowhead. Here the two diagonal edges are one cell
--- of border and everything between them is fill, so it reads solid at any
--- size.
local function stampTail(grid, cols, rows, tailSide)
  if not tailSide then return grid end

  local reach = Bubble.tailReach
  local body = cols - reach
  local middle = math.floor(rows / 2) + 1

  for i = 0, reach - 1 do
    local half = math.floor(Bubble.tailHalf - i * Bubble.tailSlope)
    local x = (tailSide == "left") and (reach - i) or (body + i + 1)
    if x < 1 or x > cols then break end
    if half < 0 then break end

    local top, bottom = middle - half, middle + half
    for y = top, bottom do
      if y >= 1 and y <= rows then
        -- One cell of border along each diagonal flank, fill between.
        grid[y][x] = (y == top or y == bottom) and EDGE or BODY
      end
    end

    -- Cap the tip so the point is closed.
    if half == 0 then grid[middle][x] = EDGE end
  end

  -- Open the body's wall where the tail joins it, or they read as two shapes
  -- pushed together rather than one.
  local seam = (tailSide == "left") and (reach + 1) or body
  for offset = 0, Bubble.border - 1 do
    local x = (tailSide == "left") and (seam + offset) or (seam - offset)
    if x >= 1 and x <= cols then
      local half = Bubble.tailHalf - 1
      for y = middle - half, middle + half do
        if y >= 1 and y <= rows and grid[y][x] ~= EMPTY then grid[y][x] = BODY end
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
  stampTail(grid, cols, rows, tailSide)
  local rects = mesh(grid, cols, rows)

  cache[key] = rects
  return rects
end

--- How many cells wide/tall a bubble needs to be to hold `w` x `h` points,
--- and the exact size in points it will occupy.
function Bubble.fit(w, h, withTail)
  local unit = Bubble.unit
  local cols = math.ceil(w / unit) + (withTail and Bubble.tailReach or 0)
  local rows = math.max(math.ceil(h / unit), Bubble.tailHalf * 2 + 8)
  return cols, rows, cols * unit, rows * unit
end

--- The inner area a bubble of this size can hold text in, in points.
function Bubble.padding()
  return (Bubble.border + Bubble.chamfer) * Bubble.unit
end

--- How much of the width the tail eats, in points.
function Bubble.reach()
  return Bubble.tailReach * Bubble.unit
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
