--- Just enough of Hammerspoon's `hs` global to exercise the pure-logic modules
--- under plain `lua`. Anything that draws is out of scope here; this covers the
--- parts where a bug is silent — session pairing, stats maths, retention.

local support = {}

-- ------------------------------------------------------------------ tiny json

local function encode(value)
  local t = type(value)
  if t == "nil" then return "null" end
  if t == "number" then
    return (value % 1 == 0) and string.format("%d", value) or tostring(value)
  end
  if t == "boolean" then return tostring(value) end
  if t == "string" then
    return '"' .. value:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' end
      if c == "\\" then return "\\\\" end
      if c == "\n" then return "\\n" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  end

  -- Array or object?
  local isArray, n = true, 0
  for k in pairs(value) do
    n = n + 1
    if type(k) ~= "number" then isArray = false end
  end
  if n == 0 then return "{}" end

  local parts = {}
  if isArray then
    for _, item in ipairs(value) do parts[#parts + 1] = encode(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for k, v in pairs(value) do
    parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(v)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function skipWhite(s, i)
  while i <= #s and s:sub(i, i):match("%s") do i = i + 1 end
  return i
end

local decodeValue

local function decodeString(s, i)
  local out = {}
  i = i + 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then return table.concat(out), i + 1 end
    if c == "\\" then
      local nxt = s:sub(i + 1, i + 1)
      if nxt == "n" then out[#out + 1] = "\n"
      elseif nxt == "u" then
        out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16) % 256)
        i = i + 4
      else out[#out + 1] = nxt end
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out), i
end

function decodeValue(s, i)
  i = skipWhite(s, i)
  local c = s:sub(i, i)

  if c == '"' then return decodeString(s, i) end

  if c == "{" then
    local obj = {}
    i = skipWhite(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      local key, value
      key, i = decodeString(s, skipWhite(s, i))
      i = skipWhite(s, i)
      i = i + 1                                  -- ':'
      value, i = decodeValue(s, i)
      obj[key] = value
      i = skipWhite(s, i)
      if s:sub(i, i) == "," then i = i + 1 else return obj, i + 1 end
    end
  end

  if c == "[" then
    local arr = {}
    i = skipWhite(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local value
      value, i = decodeValue(s, i)
      arr[#arr + 1] = value
      i = skipWhite(s, i)
      if s:sub(i, i) == "," then i = i + 1 else return arr, i + 1 end
    end
  end

  if s:sub(i, i + 3) == "true"  then return true,  i + 4 end
  if s:sub(i, i + 4) == "false" then return false, i + 5 end
  if s:sub(i, i + 3) == "null"  then return nil,   i + 4 end

  local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
  return tonumber(num), i + #num
end

-- ------------------------------------------------------------------ hs stub

local settings = {}

_G.hs = {
  json = {
    encode = encode,
    decode = function(s) local v = decodeValue(s, 1) return v end,
  },
  settings = {
    get = function(key) return settings[key] end,
    set = function(key, value) settings[key] = value end,
  },
  fs = {
    mkdir = function() return true end,
    -- Drivable directory listing: support.setFiles{...} decides what is there.
    dir = function()
      local names, i = support.files or {}, 0
      return function()
        i = i + 1
        return names[i]
      end
    end,
    attributes = function(path)
      local f = io.open(path, "r")
      if not f then return nil end
      local size = f:seek("end")
      f:close()
      return { size = size }
    end,
  },
  configdir = "/tmp/foxbot-test",
  alert = { show = function() end },
  timer = { doEvery = function() return { stop = function() end } end,
            doAfter = function() return { stop = function() end } end },
  application = { get = function() return nil end },
  notify = { new = function() return { send = function() end } end },
  pasteboard = { setContents = function() end },
}

-- Idle time and the lock/sleep notifications, both drivable from a test.
local idle = 0
_G.hs.host = { idleTime = function() return idle end }
_G.hs.caffeinate = {
  watcher = {
    screensDidLock = "screensDidLock",
    screensDidUnlock = "screensDidUnlock",
    systemWillSleep = "systemWillSleep",
    systemDidWake = "systemDidWake",
    screensaverDidStart = "screensaverDidStart",
    screensaverDidStop = "screensaverDidStop",
    screensDidSleep = "screensDidSleep",
    screensDidWake = "screensDidWake",
    new = function(fn)
      local w = { fn = fn }
      function w:start() return self end
      function w:stop() return self end
      _G.__lastWatcher = w
      return w
    end,
  },
}

function support.setIdle(seconds) idle = seconds end
function support.setFiles(names) support.files = names end
function support.fire(event) _G.__lastWatcher.fn(event) end

support.settings = settings
support.encode = encode

-- ------------------------------------------------------------------- runner

local passed, failed = 0, 0
local failures = {}

function support.check(name, got, want)
  if got == want then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = string.format("%s\n     got:  %s\n     want: %s",
                                            name, tostring(got), tostring(want))
  end
end

function support.ok(name, condition)
  support.check(name, condition and true or false, true)
end

function support.report()
  print(string.format("\n  %d passed, %d failed", passed, failed))
  for _, f in ipairs(failures) do print("\n  FAIL " .. f) end
  return failed == 0
end

return support
