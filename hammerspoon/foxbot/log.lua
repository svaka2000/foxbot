--- A small on-disk log, for the failures nobody is watching the console for.
---
--- Hammerspoon prints Lua errors to its own console window. That is fine while
--- you are looking at it and useless afterwards — a callback that threw at
--- 4am, in a window nobody had open, leaves no trace at all. And a callback
--- that throws is exactly how a desktop toy goes quiet: the click arrives, the
--- handler dies halfway, nothing appears, and there is nothing to read.
---
--- So the click paths run through `Log.guard`, which catches, records with a
--- stack trace, and lets the caller decide what to do instead of dying.

local Log = {}

Log.path = os.getenv("HOME") .. "/.claude/foxbot/debug.log"
Log.MAX = 64 * 1024      -- bytes; rotated, never grows without bound

local function rotate()
  local file = io.open(Log.path, "r")
  if not file then return end
  local size = file:seek("end")
  file:close()
  if size < Log.MAX then return end
  os.remove(Log.path .. ".1")
  os.rename(Log.path, Log.path .. ".1")
end

--- One line. Never throws — a logger that can break the thing it is logging
--- about is worse than no logger.
function Log.say(tag, message)
  pcall(function()
    rotate()
    local file = io.open(Log.path, "a")
    if not file then return end
    file:write(string.format("%s  %-10s %s\n",
                             os.date("%Y-%m-%d %H:%M:%S"), tag, message or ""))
    file:close()
  end)
end

--- Run `fn`, and if it throws, record it with a stack trace rather than
--- letting it vanish into a console nobody has open.
--- @return boolean ok, any result
function Log.guard(tag, fn, ...)
  local ok, result = xpcall(fn, function(err)
    return tostring(err) .. "\n" .. debug.traceback("", 2)
  end, ...)

  if not ok then
    Log.say(tag .. "!", result)
  end
  return ok, result
end

return Log
