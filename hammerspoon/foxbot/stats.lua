--- What today actually looked like: how many turns ran, how long Claude spent
--- working, and which project ate it all.
---
--- Everything is derived from the history log, so there is no second source of
--- truth to keep in sync.

local Stats = {}

local function startOfDay(when)
  local t = os.date("*t", when or os.time())
  t.hour, t.min, t.sec = 0, 0, 0
  return os.time(t)
end

Stats.startOfDay = startOfDay

--- Totals for the window starting at `since`.
function Stats.summarise(rows, since)
  local out = {
    turns = 0,
    seconds = 0,
    tokens = 0,        -- assistant output tokens
    subTokens = 0,     -- subagent output tokens
    peakContext = 0,
    projects = {},     -- folder -> { turns, seconds, tokens }
    longest = nil,
    sessions = {},     -- distinct session ids
  }

  for _, row in ipairs(rows) do
    if since and row.ts < since then break end
    out.turns = out.turns + 1

    local elapsed = tonumber(row.elapsed) or 0
    out.seconds = out.seconds + elapsed

    local tokens = tonumber(row.tokens) or 0
    out.tokens = out.tokens + tokens
    out.subTokens = out.subTokens + (tonumber(row.subTokens) or 0)
    out.peakContext = math.max(out.peakContext, tonumber(row.context) or 0)

    local folder = row.folder or row.session or "—"
    local bucket = out.projects[folder]
      or { turns = 0, seconds = 0, tokens = 0, folder = folder }
    bucket.turns = bucket.turns + 1
    bucket.seconds = bucket.seconds + elapsed
    bucket.tokens = bucket.tokens + tokens
    out.projects[folder] = bucket

    if not out.longest or elapsed > (out.longest.elapsed or 0) then
      out.longest = { session = row.session, folder = folder, elapsed = elapsed }
    end

    local id = row.session_id or row.session
    if id then out.sessions[id] = true end
  end

  local distinct = 0
  for _ in pairs(out.sessions) do distinct = distinct + 1 end
  out.distinct = distinct
  return out
end

--- Projects sorted by time spent, biggest first.
function Stats.ranked(summary, limit)
  local rows = {}
  for _, bucket in pairs(summary.projects) do rows[#rows + 1] = bucket end
  table.sort(rows, function(a, b)
    if a.seconds == b.seconds then return a.turns > b.turns end
    return a.seconds > b.seconds
  end)
  if limit and #rows > limit then
    for i = #rows, limit + 1, -1 do table.remove(rows, i) end
  end
  return rows
end

--- Turn counts for the last `days` days, oldest first — a tiny sparkline.
function Stats.daily(rows, days)
  days = days or 7
  local buckets, order = {}, {}

  for offset = days - 1, 0, -1 do
    local day = startOfDay(os.time() - offset * 86400)
    buckets[day] = { day = day, turns = 0, seconds = 0 }
    order[#order + 1] = day
  end

  for _, row in ipairs(rows) do
    local day = startOfDay(row.ts)
    local bucket = buckets[day]
    if bucket then
      bucket.turns = bucket.turns + 1
      bucket.seconds = bucket.seconds + (tonumber(row.elapsed) or 0)
    end
  end

  local out = {}
  for _, day in ipairs(order) do out[#out + 1] = buckets[day] end
  return out
end

--- Consecutive days ending today that had at least one turn.
function Stats.streak(rows)
  local days = {}
  for _, row in ipairs(rows) do days[startOfDay(row.ts)] = true end

  local streak, cursor = 0, startOfDay()
  -- Yesterday still counts if today has not started yet.
  if not days[cursor] then cursor = cursor - 86400 end
  while days[cursor] do
    streak = streak + 1
    cursor = cursor - 86400
  end
  return streak
end

--- "37.0k" / "1.2M" / "840" — token counts, short enough for a card stamp.
function Stats.tokens(n)
  n = tonumber(n) or 0
  if n <= 0 then return nil end
  if n < 1000 then return tostring(math.floor(n)) end
  if n < 1000000 then return string.format("%.1fk", n / 1000) end
  return string.format("%.1fM", n / 1000000)
end

--- "2h 14m" / "8m" / "45s" — for headline totals rather than card titles.
function Stats.human(seconds)
  seconds = math.floor(seconds or 0)
  if seconds <= 0 then return "0m" end
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  return string.format("%dh %02dm", math.floor(seconds / 3600),
                       math.floor((seconds % 3600) / 60))
end

return Stats
