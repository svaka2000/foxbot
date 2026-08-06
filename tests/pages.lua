--- Menu page tests.
---
--- These exist because of a specific, invisible bug: the old home page was 29
--- rows and 903 points tall, the menu clamps its position to the screen but
--- never shrinks or scrolls, and so on a 1440x900 Mac "Reload" and "Quit" were
--- drawn past the bottom edge and could not be clicked at all. Nothing errored.
--- Nothing looked wrong unless you counted pixels.
---
--- So every page is measured here, against a context stuffed with worst-case
--- data, and asserted to fit.

local t = require("tests.support")
local check, ok = t.check, t.ok

local Pages = require("foxbot.pages")
local Menu = require("foxbot.menu")
local Settings = require("foxbot.settings")

-- ------------------------------------------------------------ a fake world

--- A context with more of everything than anyone really has: enough blocked
--- sessions, running sessions, projects and history to push every list page to
--- its cap.
local function crowded(overrides)
  local settings = Settings.load()
  for key, value in pairs(overrides or {}) do settings[key] = value end

  local blocked, running, ledgerRows = {}, {}, {}
  for i = 1, 9 do
    blocked[i] = { id = "b" .. i, session = "a-fairly-long-session-name-" .. i,
                   elapsed = 600 + i, hint = "which database should I use?",
                   tty = "", app = "" }
    running[i] = { id = "r" .. i, session = "another-long-session-name-" .. i,
                   elapsed = 120 + i, tty = "", app = "" }
  end
  for i = 1, 40 do
    ledgerRows[i] = { ts = os.time() - i * 60, session = "session-" .. i,
                      session_id = "s" .. i, folder = "project-number-" .. i,
                      cwd = "/tmp/p" .. i, elapsed = 90, tokens = 5000 }
  end

  local Stats = require("foxbot.stats")
  local Sessions = require("foxbot.sessions")

  return {
    settings = settings,
    sessions = {
      waitingCount = function() return #blocked end,
      count = function() return #running end,
      blocked = function() return blocked end,
      list = function() return running end,
    },
    ledger = { rows = ledgerRows, recent = function(_, n)
      local out = {}
      for i = 1, math.min(n or 12, #ledgerRows) do out[i] = ledgerRows[i] end
      return out
    end },
    recent = function()
      local out = {}
      for i = 1, 12 do
        out[i] = { session = "recent-session-" .. i, ts = os.time(),
                   session_id = "r" .. i, tty = "", app = "" }
      end
      return out
    end,
    fox = { hidden = function() return false end },
    keyOf = function(e) return e.session_id or e.session end,
    restingMood = function() return "running" end,
    chimeFor = function() return "Hero" end,
    frontApp = function() return "Discord" end,
    isBreak = function() return true end,
    remote = function() return { ready = false, sends = "nothing" } end,

    Settings = Settings,
    Sessions = Sessions,
    Stats = Stats,
    Voice = require("foxbot.voice"),
    Chime = require("foxbot.chime"),
    Coats = require("foxbot.coats"),
    Mood = require("foxbot.mood"),
    Hush = require("foxbot.hush"),
    Palette = require("foxbot.palette"),

    chatty = { LEVELS = { "needed", "normal", "chatty" },
               LABEL = { needed = "only when needed", normal = "normal",
                         chatty = "chatty" },
               NOTE = { needed = "a", normal = "b", chatty = "c" } },
    awaySteps = { 0, 900, 1800 },
    awayLabel = { [0] = "locked or asleep", [900] = "15 min idle",
                  [1800] = "30 min idle" },
    detailOptions = { { id = "name", label = "Name only", note = "one line" },
                      { id = "brief", label = "Brief", note = "three" },
                      { id = "full", label = "Everything", note = "six" } },
    chimeEvents = { { kind = "done", label = "Turn finished" },
                    { kind = "ask", label = "Asking you something" } },

    Timer = require("foxbot.timer"),
    clock = function()
      return require("foxbot.timer").new({ settings = settings,
                                           now = function() return 1000 end })
    end,

    act = setmetatable({}, { __index = function() return function() end end }),
  }
end

t.setFiles({ "foxbot.png", "foxbot-sleeping.png" })

local ctx = crowded()
local pages = Pages.new(ctx)

-- -------------------------------------------------------------- every page

local PAGES = {
  { "home", Pages.MAX_HOME },
  { "now", Pages.MAX_PAGE },
  { "den", Pages.MAX_PAGE },
  { "earlier", Pages.MAX_PAGE },
  { "settings", Pages.MAX_PAGE },
  { "chatter", Pages.MAX_PAGE },
  { "hush", Pages.MAX_PAGE },
  { "away", Pages.MAX_PAGE },
  { "projects", Pages.MAX_PAGE },
  { "voice", Pages.MAX_PAGE },
  { "detail", Pages.MAX_PAGE },
  { "sounds", Pages.MAX_PAGE },
  { "sprite", Pages.MAX_PAGE },
  { "wardrobe", Pages.MAX_PAGE },
  { "about", Pages.MAX_PAGE },
  { "focus", Pages.MAX_PAGE },
  { "attention", Pages.MAX_PAGE },
  { "notes", Pages.MAX_PAGE },
}

local tall = {}
for _, spec in ipairs(PAGES) do
  local name, limit = spec[1], spec[2]
  local rows = pages[name](pages)
  ok(name .. " returns rows", type(rows) == "table" and #rows > 0)

  local height = Menu.measure(rows)
  if height > limit then
    tall[#tall + 1] = string.format("%s is %dpx (limit %d)", name, height, limit)
  end
end
check("no page is taller than it may be", #tall, 0)
if #tall > 0 then for _, s in ipairs(tall) do print("     " .. s) end end

-- The home page in particular has to stay short: it is the one people open
-- without meaning to.
check("home is short", #pages:home() <= 10, true)
ok("home is under its limit", Menu.measure(pages:home()) <= Pages.MAX_HOME)

-- ------------------------------------------------------- every row is sane

local kinds = {}
local bad = {}
for _, spec in ipairs(PAGES) do
  for _, row in ipairs(pages[spec[1]](pages)) do
    local kind = row.kind or "row"
    kinds[kind] = (kinds[kind] or 0) + 1
    -- Anything drawn with a title must have one, or styledtext throws.
    if kind ~= "sep" and kind ~= "stats" and kind ~= "segment" and not row.title then
      bad[#bad + 1] = spec[1] .. "/" .. kind
    end
    if kind == "segment" and (not row.options or not row.act) then
      bad[#bad + 1] = spec[1] .. "/segment missing options or act"
    end
    if kind == "into" and not row.page then
      bad[#bad + 1] = spec[1] .. "/into with no page"
    end
  end
end
check("every row is well formed", #bad, 0)
if #bad > 0 then for _, s in ipairs(bad) do print("     " .. s) end end
ok("the segment control is used", (kinds.segment or 0) >= 1)
ok("every page can be left", (kinds.back or 0) >= 15)

-- ------------------------------------------------------------ list capping

do
  local now = pages:now()
  local sessionRows = 0
  for _, row in ipairs(now) do
    if (row.kind or "row") == "row" and row.act then sessionRows = sessionRows + 1 end
  end
  ok("the running page caps its lists",
     sessionRows <= Pages.CAP.blocked + Pages.CAP.running)

  local overflow = false
  for _, row in ipairs(now) do
    if row.title and row.title:find("more", 1, true) then overflow = true end
  end
  ok("and says how many it hid", overflow)
end

-- --------------------------------------------------------- the pause ladder

do
  local s = Settings.load()
  s.quiet, s.pauseUntil = false, 0
  check("plain is everything", Pages.level(s, 1000), "everything")

  s.quiet = true
  check("muted is silent", Pages.level(s, 1000), "silent")

  s.pauseUntil = 2000
  check("paused outranks silent", Pages.level(s, 1000), "paused")
  check("and expires by itself", Pages.level(s, 3000), "silent")

  local Hush = require("foxbot.hush")
  s.quiet, s.pauseUntil = false, 2000
  local silence, show = Hush.check(s, 1000)
  check("paused silences", silence, true)
  check("paused hides too", show, false)
  ok("paused says when it's back", (Hush.backIn(s, 1000) or ""):find("back in") ~= nil)

  s.pauseUntil = 0
  local silence2 = Hush.check(s, 1000)
  check("and lets go afterwards", silence2, false)
end

return true
