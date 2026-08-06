--- Tests for the one file that talks to the network.
---
--- Only the pure parts are exercised here — the parsing, the tidying, the
--- disclosure string. The HTTP itself is not mocked and not called: the tests
--- must pass with no key and no connection, which is also the state every
--- contributor and CI runner is in.

local t = require("tests.support")
local check, ok = t.check, t.ok

local Remote = require("foxbot.remote")

-- -------------------------------------------------------------- the switch

do
  -- With no key file, nothing is available. This is the state of a fresh
  -- install and of CI, and it must be the quiet one.
  local real = Remote.KEY_FILE
  Remote.KEY_FILE = "/tmp/foxbot-no-such-key-" .. tostring(os.time())
  ok("no key means unavailable", not Remote.available())
  check("and no key at all", Remote.key(), nil)

  -- A file that exists but is blank is not a key either — that is what you get
  -- from `touch`, and treating it as one would mean every request 401s.
  local blank = "/tmp/foxbot-blank-key"
  local f = io.open(blank, "w") f:write("\n  \n") f:close()
  Remote.KEY_FILE = blank
  ok("a blank file is not a key", not Remote.available())

  -- A real one is read with its trailing newline stripped, which every editor
  -- and every `echo >` will put there.
  f = io.open(blank, "w") f:write("gsk_example\n") f:close()
  check("a key is read without its newline", Remote.key(), "gsk_example")
  ok("and is then available", Remote.available())

  os.remove(blank)
  Remote.KEY_FILE = real
end

-- ------------------------------------------------------------- what it sends

do
  -- Extensions only, most common first, capped. No names, no paths.
  local files = {
    "/p/a.lua", "/p/b.lua", "/p/c.lua",
    "/p/x.py", "/p/y.py",
    "/p/one.md",
    "/p/z.sh",
    "/p/w.json",
    "/p/v.toml",
  }
  local langs = Remote.languages("/p", function() return files end)
  check("the commonest language is first", langs[1], "lua")
  check("then the next", langs[2], "py")
  ok("and it is capped", #langs <= 4)

  local sent = Remote.describe(langs)
  ok("the disclosure names the extensions", sent:find("lua", 1, true) ~= nil)
  -- The whole point: nothing identifying is in there.
  ok("and contains no path", sent:find("/p", 1, true) == nil)
  ok("and no file name", sent:find("one", 1, true) == nil)

  check("an empty folder sends nothing",
        Remote.describe(Remote.languages("/p", function() return {} end)),
        "nothing — no languages detected")
  check("and no folder sends nothing", #Remote.languages(nil), 0)
end

do
  -- Same folder, same description, every time: a disclosure that changed
  -- between the menu and the request would not be a disclosure.
  local files = { "/p/a.lua", "/p/b.py", "/p/c.rs", "/p/d.go" }
  local first = Remote.describe(Remote.languages("/p", function() return files end))
  local again = Remote.describe(Remote.languages("/p", function() return files end))
  check("the description is stable", again, first)
end

do
  -- Walking a folder forks `find`, and the menu row that shows the disclosure
  -- is rebuilt on every hover. Without a cache, moving the mouse down that page
  -- forks a subprocess per frame.
  Remote.forget()
  local walks = 0
  local function counting()
    walks = walks + 1
    return { "/p/a.lua" }
  end

  -- An injected lister is a test, and must neither read nor write the cache,
  -- or one test would poison the next.
  Remote.languages("/p", counting)
  Remote.languages("/p", counting)
  check("an injected lister always runs", walks, 2)
end

do
  -- This used to build a shell command with io.popen and Lua's %q, which
  -- quotes for Lua, not for a shell -- and inside double quotes a shell still
  -- expands $(...) and backticks. You can be handed a directory name by
  -- cloning a repository, so that was a way to run a command.
  --
  -- There is no shell any more. This asserts the source rather than the
  -- behaviour, because a test that proved the behaviour would have to run the
  -- injected command to find out.
  -- Comments only, stripped out: the docstring in remote.lua explains what it
  -- used to do, and naming io.popen in prose is not calling it.
  local code = {}
  for line in io.lines("hammerspoon/foxbot/remote.lua") do
    if not line:match("^%s*%-%-") then code[#code + 1] = line end
  end
  local text = table.concat(code, "\n")

  ok("nothing here opens a shell", not text:find("io.popen", 1, true))
  ok("and nothing here runs a command", not text:find("os.execute", 1, true))

  -- The walk still has to stop somewhere, or a home directory takes minutes.
  ok("the walk is bounded", (Remote.MAX_FILES or 0) > 0 and (Remote.MAX_DEPTH or 0) > 0)

  -- A hostile folder name is now just a string.
  local nasty = "/tmp/$(touch /tmp/foxbot-pwned)"
  local langs = Remote.languages(nasty, function(path)
    check("the path arrives unmangled", path, nasty)
    return { path .. "/a.lua" }
  end)
  check("and still yields a language", langs[1], "lua")
  local pwned = io.open("/tmp/foxbot-pwned", "r")
  ok("and nothing was executed", pwned == nil)
  if pwned then pwned:close() os.remove("/tmp/foxbot-pwned") end
end

-- ------------------------------------------------------------------ tidying

do
  local cases = {
    { "Sure! Use git reflog.",                    "Use git reflog." },
    { "Here's a tip: use git reflog.",            "use git reflog." },
    { "  Use **git reflog**.  ",                  "Use git reflog." },
    { "- Use git reflog.",                        "Use git reflog." },
    { "\"Use git reflog.\"",                      "Use git reflog." },
    { "Use git reflog.",                          "Use git reflog." },
    -- Several sentences: keep the first, because the bubble is one line.
    { "Use git reflog. It records where HEAD has been.", "Use git reflog." },
  }
  local wrong = {}
  for _, case in ipairs(cases) do
    local got = Remote.tidy(case[1])
    if got ~= case[2] then
      wrong[#wrong + 1] = string.format("%q -> %q, wanted %q", case[1], got, case[2])
    end
  end
  check("it arrives as one plain sentence", #wrong, 0)
  if #wrong > 0 then for _, s in ipairs(wrong) do print("     " .. s) end end
end

return true
