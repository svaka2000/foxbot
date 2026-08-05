--- Knowing when you are not at the machine.
---
--- Coming back to eleven stacked cards from twenty minutes ago is worse than
--- coming back to none: they cover the screen, they are all stale, and the one
--- that mattered scrolled off the top. While you are away the pet buffers
--- everything and hands it back as a single digest.
---
--- Lock and sleep are the signals that matter, because they are exact: the
--- screen is off, you are definitely not reading it.
---
--- Input idle time is deliberately NOT used by default. It cannot tell "sat
--- here watching a long turn scroll past" from "left the building", and getting
--- that wrong is the bad direction — the pet goes quiet exactly when you are
--- watching it work. Set `threshold` above zero to opt into it anyway; fifteen
--- minutes of genuinely zero input is a reasonable bar if you want it.

local Away = {}
Away.__index = Away

function Away.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Away)

  -- 0 (the default) means lock and sleep only.
  self.threshold = opts.threshold or 0
  self.onReturn = opts.onReturn
  self.buffer = {}
  self.locked = false
  self.away = false
  self.since = nil

  -- Lock and sleep are unambiguous: you are definitely not looking.
  self.watcher = hs.caffeinate.watcher.new(function(event)
    local w = hs.caffeinate.watcher
    if event == w.screensDidLock or event == w.systemWillSleep
       or event == w.screensaverDidStart or event == w.screensDidSleep then
      self.locked = true
      self:enter()
    elseif event == w.screensDidUnlock or event == w.systemDidWake
           or event == w.screensaverDidStop or event == w.screensDidWake then
      self.locked = false
      self:leave()
    end
  end)
  self.watcher:start()

  return self
end

function Away:idle()
  local ok, seconds = pcall(hs.host.idleTime)
  return ok and seconds or 0
end

function Away:enter()
  if self.away then return end
  self.away = true
  self.since = os.time()
end

function Away:leave()
  if not self.away then return end
  self.away = false

  local buffered, since = self.buffer, self.since
  self.buffer, self.since = {}, nil

  if self.onReturn and #buffered > 0 then
    self.onReturn(buffered, since)
  end
end

--- Called from the main poll. Returns true when you are currently away.
function Away:check()
  if self.locked then
    self:enter()
    return true
  end

  if self.threshold > 0 and self:idle() >= self.threshold then
    self:enter()
    return true
  end

  -- Unlocked, and not idle enough to count: hand back whatever piled up.
  self:leave()
  return false
end

function Away:isAway()
  return self.away
end

--- Hold onto an event rather than putting it on screen right now.
function Away:hold(event)
  self.buffer[#self.buffer + 1] = event
  -- A pathological run of events shouldn't grow without bound; the digest
  -- reports the true count separately, so trimming here is safe.
  while #self.buffer > 200 do table.remove(self.buffer, 1) end
end

function Away:count()
  return #self.buffer
end

function Away:stop()
  if self.watcher then self.watcher:stop() end
end

return Away
