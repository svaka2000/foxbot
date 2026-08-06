--- Live session tracking: who is working right now, and for how long.
---
--- Claude Code fires UserPromptSubmit when you send a turn and Stop when the
--- turn finishes. Pairing those gives two things the original pet had no way to
--- know: whether anything is running at this moment, and how long the last piece
--- of work actually took.

local Sessions = {}
Sessions.__index = Sessions

-- A session that goes busy and never reports back — the terminal was closed,
-- the machine slept, Claude crashed — would otherwise sit "working" forever.
local STALE_AFTER = 30 * 60      -- seconds
local ABANDON_AFTER = 6 * 3600   -- give up nudging about an ignored question

-- How long a question can sit unanswered before the pet says it again, and
-- again after that. A bubble fades in twelve seconds; if you were in another
-- window when it landed, nothing else will ever tell you Claude is blocked.
local NUDGE_AFTER = { 60, 300, 900 }
local NUDGE_EVERY = 900   -- and every fifteen minutes from then on

Sessions.NUDGE_AFTER = NUDGE_AFTER
Sessions.NUDGE_EVERY = NUDGE_EVERY

function Sessions.new()
  return setmetatable({ active = {}, finished = {}, waiting = {} }, Sessions)
end

local function key(event)
  return (event.session_id ~= "" and event.session_id) or event.session
end

Sessions.key = key

--- A turn started.
function Sessions:begin(event)
  local id = key(event)
  if not id then return end

  self.active[id] = {
    id = id,
    session = event.session,
    cwd = event.cwd,
    folder = event.folder,
    tty = event.tty,
    app = event.app,
    started = event.ts or os.time(),
  }
end

--- A turn finished. Returns elapsed seconds when we saw the matching start.
function Sessions:finish(event)
  local id = key(event)
  if not id then return nil end

  local row = self.active[id]
  self.active[id] = nil
  if not row then return nil end

  local elapsed = (event.ts or os.time()) - row.started
  if elapsed < 0 then elapsed = 0 end

  row.ended = event.ts or os.time()
  row.elapsed = elapsed
  self.finished[id] = row
  return elapsed
end

-- ------------------------------------------------------------------ waiting

--- A session put a question on screen and is now blocked on you.
function Sessions:wait(event)
  local id = key(event)
  if not id then return end

  local existing = self.waiting[id]
  -- A second question replaces the first, but the clock keeps running from
  -- when you were *first* blocked — that is the number that matters.
  self.waiting[id] = {
    id = id,
    session = event.session,
    folder = event.folder,
    cwd = event.cwd,
    tty = event.tty,
    app = event.app,
    hint = event.hint,
    since = existing and existing.since or (event.ts or os.time()),
    nudges = existing and existing.nudges or 0,
  }
end

--- When this session first became blocked on you, or nil.
---
--- Read before `finish` clears the row: the donut bonus is for answering
--- quickly, and by the time the turn has finished there is nothing left to
--- measure the gap against.
function Sessions:askedAt(id)
  local row = self.waiting[id]
  return row and row.since or nil
end

--- You dealt with it (or the session moved on by itself).
function Sessions:answered(event)
  local id = type(event) == "table" and key(event) or event
  if not id then return false end
  local had = self.waiting[id] ~= nil
  self.waiting[id] = nil
  return had
end

function Sessions:waitingCount()
  local n = 0
  for _ in pairs(self.waiting) do n = n + 1 end
  return n
end

function Sessions:isWaiting()
  return next(self.waiting) ~= nil
end

--- Questions that have gone unanswered long enough to say again.
--- Returns rows and bumps their nudge counter, so each one only fires once.
function Sessions:overdue(now)
  now = now or os.time()
  local due = {}

  for _, row in pairs(self.waiting) do
    local elapsed = now - row.since
    local step = NUDGE_AFTER[row.nudges + 1]
    if not step then
      -- Past the listed steps: every NUDGE_EVERY from the last one.
      local last = NUDGE_AFTER[#NUDGE_AFTER]
      step = last + NUDGE_EVERY * (row.nudges + 1 - #NUDGE_AFTER)
    end

    if elapsed >= step then
      row.nudges = row.nudges + 1
      due[#due + 1] = {
        id = row.id, session = row.session, folder = row.folder,
        cwd = row.cwd, tty = row.tty, app = row.app, hint = row.hint,
        since = row.since, elapsed = elapsed, nudges = row.nudges,
      }
    end
  end

  return due
end

--- Waiting sessions, longest-blocked first.
function Sessions:blocked(now)
  now = now or os.time()
  local rows = {}
  for _, row in pairs(self.waiting) do
    rows[#rows + 1] = {
      id = row.id, session = row.session, folder = row.folder,
      cwd = row.cwd, tty = row.tty, app = row.app, hint = row.hint,
      elapsed = now - row.since,
    }
  end
  table.sort(rows, function(a, b) return a.elapsed > b.elapsed end)
  return rows
end

--- Drop anything that has been "running" — or blocked — implausibly long.
function Sessions:sweep(now)
  now = now or os.time()
  local dropped = 0

  for id, row in pairs(self.active) do
    if (now - row.started) > STALE_AFTER then
      self.active[id] = nil
      dropped = dropped + 1
    end
  end

  -- A question you have ignored for half a day is one you are never going to
  -- answer; the terminal is almost certainly gone. Stop nagging.
  for id, row in pairs(self.waiting) do
    if (now - row.since) > ABANDON_AFTER then
      self.waiting[id] = nil
      dropped = dropped + 1
    end
  end

  return dropped
end

function Sessions:count()
  local n = 0
  for _ in pairs(self.active) do n = n + 1 end
  return n
end

function Sessions:isBusy()
  return next(self.active) ~= nil
end

--- Active sessions, longest-running first.
function Sessions:list(now)
  now = now or os.time()
  local rows = {}
  for _, row in pairs(self.active) do
    rows[#rows + 1] = {
      id = row.id,
      session = row.session,
      folder = row.folder,
      cwd = row.cwd,
      tty = row.tty,
      app = row.app,
      started = row.started,
      elapsed = now - row.started,
    }
  end
  table.sort(rows, function(a, b) return a.elapsed > b.elapsed end)
  return rows
end

--- "4m 12s" / "38s" / "1h 03m" — short enough for a card title.
function Sessions.duration(seconds)
  if not seconds or seconds < 0 then return nil end
  if seconds < 60 then return string.format("%ds", seconds) end
  if seconds < 3600 then
    return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
  end
  return string.format("%dh %02dm", math.floor(seconds / 3600),
                       math.floor((seconds % 3600) / 60))
end

return Sessions
