--- Finished sessions, kept on disk so they survive a reload or a reboot.
---
--- The original pet held eight entries in memory and lost every one of them the
--- moment Hammerspoon restarted. This writes one JSON line per finished turn and
--- prunes anything past the retention window on load.

local History = {}
History.__index = History

local MAX_ROWS = 2000   -- plenty for a month; keeps the menu build cheap

function History.new(path, days)
  local self = setmetatable({}, History)
  self.path = path
  self.days = days or 30
  self.rows = {}        -- newest first
  return self
end

local function decode(line)
  local ok, row = pcall(hs.json.decode, line)
  if ok and type(row) == "table" and row.ts then return row end
  return nil
end

--- Read the log, dropping anything older than the retention window.
function History:load()
  self.rows = {}

  local file = io.open(self.path, "r")
  if not file then return self end

  local cutoff = os.time() - (self.days * 86400)
  local kept, total = {}, 0
  for line in file:lines() do
    total = total + 1
    local row = decode(line)
    if row and row.ts >= cutoff then kept[#kept + 1] = row end
  end
  file:close()

  -- File is append-ordered, so the tail is newest.
  for i = #kept, math.max(1, #kept - MAX_ROWS + 1), -1 do
    self.rows[#self.rows + 1] = kept[i]
  end

  -- Rewrite only when the prune actually dropped something, so a normal launch
  -- does no writes at all.
  if #kept < total then self:rewrite(kept) end
  return self
end

function History:rewrite(rows)
  local file = io.open(self.path, "w")
  if not file then return end
  for _, row in ipairs(rows) do
    file:write(hs.json.encode(row), "\n")
  end
  file:close()
end

--- Record one finished turn.
function History:append(row)
  table.insert(self.rows, 1, row)
  while #self.rows > MAX_ROWS do table.remove(self.rows) end

  local file = io.open(self.path, "a")
  if not file then return end
  file:write(hs.json.encode(row), "\n")
  file:close()
end

--- Newest-first rows, optionally only those at or after `since`.
function History:since(since)
  if not since then return self.rows end
  local out = {}
  for _, row in ipairs(self.rows) do
    if row.ts >= since then out[#out + 1] = row else break end
  end
  return out
end

--- Collapse to one row per session, newest first — what the menu lists.
function History:recent(limit)
  local seen, out = {}, {}
  for _, row in ipairs(self.rows) do
    local id = row.session_id or row.session
    if id and not seen[id] then
      seen[id] = true
      out[#out + 1] = row
      if limit and #out >= limit then break end
    end
  end
  return out
end

function History:clear()
  self.rows = {}
  os.remove(self.path)
end

return History
