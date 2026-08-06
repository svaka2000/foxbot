--- Test suite for the parts of the pet where a bug would be silent.
---
---   cd clawde && lua tests/run.lua
---
--- Anything that draws to the screen is deliberately out of scope; this covers
--- session pairing, duration maths, stats aggregation, history retention,
--- quiet-hour windows, and the settings round-trip that the original pet got
--- wrong (dropping unknown keys on save).

package.path = "hammerspoon/?.lua;hammerspoon/?/init.lua;" .. package.path

local t = require("tests.support")
local check, ok = t.check, t.ok

local Sessions = require("foxbot.sessions")
local Stats    = require("foxbot.stats")
local History  = require("foxbot.history")
local Hush     = require("foxbot.hush")
local Settings = require("foxbot.settings")

print("foxbot tests")

-- ------------------------------------------------------------------ sessions

do
  local s = Sessions.new()
  check("no sessions to start", s:count(), 0)
  ok("not busy to start", not s:isBusy())

  s:begin({ session_id = "a", session = "alpha", ts = 1000, folder = "alpha" })
  check("one active after begin", s:count(), 1)
  ok("busy after begin", s:isBusy())

  -- A second turn on the same session must not double-count.
  s:begin({ session_id = "a", session = "alpha", ts = 1005, folder = "alpha" })
  check("same session does not double-count", s:count(), 1)

  s:begin({ session_id = "b", session = "beta", ts = 1010, folder = "beta" })
  check("two distinct sessions", s:count(), 2)

  local elapsed = s:finish({ session_id = "a", ts = 1120 })
  check("elapsed measured from the latest begin", elapsed, 115)
  check("one left running", s:count(), 1)

  -- Finishing something we never saw start must not invent a duration.
  check("unknown finish returns nil", s:finish({ session_id = "zzz", ts = 1200 }), nil)

  -- Clock skew must never produce a negative duration.
  s:begin({ session_id = "c", ts = 5000 })
  check("negative elapsed clamps to zero", s:finish({ session_id = "c", ts = 4000 }), 0)

  -- Sessions that never report back get retired rather than pinning the pet
  -- into "working" forever.
  local stale = Sessions.new()
  stale:begin({ session_id = "old", ts = 1000 })
  check("nothing swept while fresh", stale:sweep(1000 + 60), 0)
  check("swept once past the window", stale:sweep(1000 + 31 * 60), 1)
  check("gone after sweep", stale:count(), 0)

  -- Falls back to the display name when there is no id.
  local noid = Sessions.new()
  noid:begin({ session_id = "", session = "named-only", ts = 1 })
  check("keys off session name when id is blank", noid:count(), 1)
end

-- ------------------------------------------------------------------- waiting

do
  local s = Sessions.new()
  ok("nothing waiting to start", not s:isWaiting())

  s:wait({ session_id = "a", session = "alpha", ts = 1000, hint = "which db?" })
  check("one question waiting", s:waitingCount(), 1)
  ok("is waiting", s:isWaiting())

  -- A second question replaces the first, but the clock keeps running from
  -- when you were first blocked.
  s:wait({ session_id = "a", session = "alpha", ts = 1200, hint = "which host?" })
  check("still one row", s:waitingCount(), 1)
  check("blocked time runs from the first question", s:blocked(1300)[1].elapsed, 300)

  -- Nudges escalate: 60s, 300s, 900s, then every 900s.
  local fresh = Sessions.new()
  fresh:wait({ session_id = "b", session = "beta", ts = 0 })
  check("nothing due immediately", #fresh:overdue(30), 0)
  check("first nudge at 60s", #fresh:overdue(60), 1)
  check("does not repeat the same nudge", #fresh:overdue(120), 0)
  check("second nudge at 300s", #fresh:overdue(300), 1)
  check("third nudge at 900s", #fresh:overdue(900), 1)
  check("nothing between steps", #fresh:overdue(1000), 0)
  check("fourth nudge 15m later", #fresh:overdue(1800), 1)
  check("fifth another 15m on", #fresh:overdue(2700), 1)

  -- Answering stops it dead.
  ok("answered reports it had one", fresh:answered("b"))
  check("nothing waiting after answering", fresh:waitingCount(), 0)
  check("no nudges once answered", #fresh:overdue(99999), 0)
  ok("answering twice is harmless", not fresh:answered("b"))

  -- A question ignored for six hours is abandoned rather than nagged forever.
  local old = Sessions.new()
  old:wait({ session_id = "c", session = "gamma", ts = 0 })
  check("kept while plausible", old:sweep(3600), 0)
  check("abandoned after six hours", old:sweep(7 * 3600), 1)
  check("gone", old:waitingCount(), 0)

  -- Blocked rows sort longest-first.
  local many = Sessions.new()
  many:wait({ session_id = "x", session = "x", ts = 500 })
  many:wait({ session_id = "y", session = "y", ts = 100 })
  check("longest blocked first", many:blocked(1000)[1].session, "y")
end

-- ----------------------------------------------------------------- durations

check("seconds",        Sessions.duration(45),    "45s")
check("minutes",        Sessions.duration(252),   "4m 12s")
check("exact minute",   Sessions.duration(60),    "1m 00s")
check("hours",          Sessions.duration(3780),  "1h 03m")
check("zero",           Sessions.duration(0),     "0s")
check("nil stays nil",  Sessions.duration(nil),   nil)
check("negative is nil", Sessions.duration(-5),   nil)

check("human 0",   Stats.human(0),    "0m")
check("human 45s", Stats.human(45),   "45s")
check("human 8m",  Stats.human(500),  "8m")
check("human 2h",  Stats.human(8040), "2h 14m")

check("tokens under 1k",  Stats.tokens(840),     "840")
check("tokens thousands", Stats.tokens(37029),   "37.0k")
check("tokens millions",  Stats.tokens(1234567), "1.2M")
check("tokens zero is nil", Stats.tokens(0),     nil)
check("tokens nil is nil",  Stats.tokens(nil),   nil)

-- -------------------------------------------------------------------- stats

do
  local now = os.time()
  local rows = {
    { ts = now - 100,  elapsed = 60,  folder = "app",  session = "s1", session_id = "1",
      tokens = 1000, subTokens = 200, context = 50000 },
    { ts = now - 200,  elapsed = 120, folder = "app",  session = "s1", session_id = "1",
      tokens = 2000, context = 90000 },
    { ts = now - 300,  elapsed = 30,  folder = "site", session = "s2", session_id = "2",
      tokens = 500,  context = 10000 },
    -- Three days ago: inside history, outside today.
    { ts = now - 3 * 86400, elapsed = 999, folder = "old", session = "s3", session_id = "3",
      tokens = 9999, context = 999999 },
  }

  local today = Stats.summarise(rows, Stats.startOfDay())
  check("today counts only today's turns", today.turns, 3)
  check("today sums only today's seconds", today.seconds, 210)
  check("distinct sessions today", today.distinct, 2)
  check("busiest project", Stats.ranked(today)[1].folder, "app")
  check("busiest project seconds", Stats.ranked(today)[1].seconds, 180)
  check("longest single turn", today.longest.elapsed, 120)

  -- Tokens aggregate the same way time does, and stay inside the window.
  check("today's output tokens", today.tokens, 3500)
  check("subagent tokens counted apart", today.subTokens, 200)
  check("peak context is a max not a sum", today.peakContext, 90000)
  check("tokens per project", Stats.ranked(today)[1].tokens, 3000)
  check("yesterday's tokens excluded", today.tokens < 9999, true)

  check("ranked respects the limit", #Stats.ranked(today, 1), 1)

  local all = Stats.summarise(rows)
  check("no window means everything", all.turns, 4)

  local daily = Stats.daily(rows, 7)
  check("seven day buckets", #daily, 7)
  check("last bucket is today", daily[7].turns, 3)
  check("three days back", daily[4].turns, 1)

  -- Streak: today plus yesterday, with a gap before that.
  local streakRows = {
    { ts = now,                elapsed = 1 },
    { ts = now - 86400,        elapsed = 1 },
    { ts = now - 5 * 86400,    elapsed = 1 },
  }
  check("streak stops at the gap", Stats.streak(streakRows), 2)
  check("empty history has no streak", Stats.streak({}), 0)
end

-- ------------------------------------------------------------------- history

do
  local path = os.tmpname()
  os.remove(path)

  local h = History.new(path, 30)
  h:append({ ts = os.time(),      kind = "done", session = "one", session_id = "1",
             folder = "app", elapsed = 10 })
  h:append({ ts = os.time() + 1,  kind = "done", session = "two", session_id = "2",
             folder = "app", elapsed = 20 })
  check("two rows in memory", #h.rows, 2)
  check("newest first", h.rows[1].session, "two")

  -- Reload from disk and the rows must come back in the same order.
  local reloaded = History.new(path, 30):load()
  check("survives a reload", #reloaded.rows, 2)
  check("order preserved across reload", reloaded.rows[1].session, "two")
  check("fields preserved", reloaded.rows[1].elapsed, 20)

  -- Anything past the retention window is dropped on load.
  local old = History.new(path, 30)
  old:append({ ts = os.time() - 40 * 86400, kind = "done", session = "ancient",
               session_id = "9", folder = "old", elapsed = 5 })
  local pruned = History.new(path, 30):load()
  check("expired rows pruned on load", #pruned.rows, 2)

  -- The prune must actually rewrite the file, not just filter in memory.
  local lines = 0
  for _ in io.lines(path) do lines = lines + 1 end
  check("prune rewrote the file", lines, 2)

  -- recent() collapses repeats of the same session.
  local dupes = History.new(os.tmpname(), 30)
  dupes.rows = {
    { ts = 3, session = "a", session_id = "1" },
    { ts = 2, session = "a", session_id = "1" },
    { ts = 1, session = "b", session_id = "2" },
  }
  check("recent collapses one row per session", #dupes:recent(), 2)
  check("recent keeps the newest", dupes:recent()[1].ts, 3)
  check("recent honours the limit", #dupes:recent(1), 1)

  os.remove(path)
end

-- --------------------------------------------------------------------- quiet

check("inside a normal window",  Hush.within(13, 9, 17),  true)
check("before a normal window",  Hush.within(8,  9, 17),  false)
check("end is exclusive",        Hush.within(17, 9, 17),  false)
check("start is inclusive",      Hush.within(9,  9, 17),  true)
-- The common case: 22:00 through to 08:00, wrapping midnight.
check("late night wraps",        Hush.within(23, 22, 8),  true)
check("small hours wrap",        Hush.within(3,  22, 8),  true)
check("morning is outside",      Hush.within(9,  22, 8),  false)
check("boundary hour wraps in",  Hush.within(22, 22, 8),  true)
check("boundary hour wraps out", Hush.within(8,  22, 8),  false)
check("empty window is never on", Hush.within(5, 5, 5),   false)

do
  -- Muted wins over everything.
  local silence, card = Hush.check({ quiet = true }, os.time())
  check("muted silences", silence, true)
  check("muted still shows the card", card, true)

  -- Quiet hours off means nothing is suppressed.
  local s2, c2 = Hush.check({ quiet = false, hush = false }, os.time())
  check("quiet off lets sound through", s2, false)
  check("quiet off shows the card", c2, true)
end

-- --------------------------------------------------------------------- state

do
  -- The bug this whole module exists to avoid: `configured` used to be written
  -- to a table that dropped unknown keys, so the pet re-applied Hammerspoon's
  -- preferences on every launch and kept turning launch-at-login back on.
  local s = Settings.load()
  check("prepared defaults off", s.prepared, false)

  s.prepared = true
  s.x, s.y = 120, 340
  s.voice = "steward"
  Settings.save(s)

  local again = Settings.load()
  check("prepared survives a save", again.prepared, true)
  check("x survives a save", again.x, 120)
  check("y survives a save", again.y, 340)
  check("voice survives a save", again.voice, "steward")
  check("defaults still fill in", again.detail, "brief")

  -- Per-project rules round-trip and clean up after themselves.
  Settings.setProject(again, "my-app", { mute = true })
  check("project rule set", Settings.project(Settings.load(), "my-app").mute, true)

  -- Clearing uses `false`, not nil — nil would vanish from the patch table
  -- before setProject ever saw it, leaving the rule stuck on.
  Settings.setProject(again, "my-app", { mute = false })
  check("cleared project rule removed", Settings.load().perProject["my-app"], nil)
  check("toggling back on works", (function()
    Settings.setProject(again, "my-app", { mute = true })
    return Settings.project(Settings.load(), "my-app").mute
  end)(), true)
  check("unknown project is empty", next(Settings.project(again, "nope")), nil)
  check("nil folder is safe", next(Settings.project(again, nil)), nil)
end

do
  -- Every setting declared in the schema has to survive a load, including the
  -- ones that default to false. `cond and default or nil` collapses those to
  -- nil, which silently turned half the switches off.
  t.settings["foxbot.settings"] = nil
  local fresh = Settings.load()

  local missing, wrong = {}, {}
  for name, default in pairs(Settings.schema) do
    if default ~= Settings.NONE then
      if fresh[name] == nil then
        missing[#missing + 1] = name
      elseif type(default) ~= "table" and fresh[name] ~= default then
        wrong[#wrong + 1] = name
      end
    end
  end
  check("no declared setting loads as nil", #missing, 0)
  check("every default loads as itself", #wrong, 0)

  -- The specific shape of the bug, named so it can't come back quietly.
  check("false defaults stay false, not nil", fresh.prepared, false)
  check("and so do the rest", fresh.hush, false)

  -- The save list is derived from the schema, so the two can never drift.
  check("keys match the schema", #Settings.keys, (function()
    local n = 0
    for _ in pairs(Settings.schema) do n = n + 1 end
    return n
  end)())

  -- A round trip must not lose anything either.
  Settings.save(fresh)
  local again2 = Settings.load()
  local lost = {}
  for _, name in ipairs(Settings.keys) do
    if fresh[name] ~= nil and again2[name] == nil then lost[#lost + 1] = name end
  end
  check("nothing is dropped on save", #lost, 0)
end

-- --------------------------------------------------------------------- skins

do
  local Coats = require("foxbot.coats")

  t.setFiles({ "foxbot.png", "cat.png", "axolotl.PNG", "notes.txt", ".DS_Store",
               "dog.gif" })
  local all = Coats.all()
  check("only images are offered", #all, 4)
  check("the bundled sprite comes first", all[1].id, "foxbot")
  check("and is named rather than filenamed", all[1].label, "Foxbot")
  check("the rest are alphabetical", all[2].id, "axolotl")
  check("case-insensitive extensions", all[2].path:sub(-4), ".PNG")
  check("gifs count too", all[4].id, "dog")

  -- Compare filenames rather than a fixed suffix length, so the assertion
  -- doesn't quietly depend on how long the default sprite happens to be named.
  local function filename(path) return path:match("([^/]+)$") end

  check("a known coat resolves to its file", filename(Coats.path("cat")), "cat.png")

  -- Deleting the png you had picked must not leave him with no sprite at all.
  t.setFiles({ "foxbot.png" })
  check("a deleted coat falls back", filename(Coats.path("cat")), "foxbot.png")
  check("nil falls back", filename(Coats.path(nil)), "foxbot.png")
  check("empty falls back", filename(Coats.path("")), "foxbot.png")

  check("default label", Coats.label("foxbot"), "Foxbot")
  check("default label for nil", Coats.label(nil), "Foxbot")
  check("custom label", Coats.label("cat"), "cat")

  -- An unreadable assets folder must return empty rather than throwing.
  local realDir = hs.fs.dir
  hs.fs.dir = function() error("boom") end
  check("unreadable folder is empty, not fatal", #Coats.all(), 0)
  hs.fs.dir = realDir
  t.setFiles({ "foxbot.png" })
end

-- --------------------------------------------------------------------- moods

do
  local Mood = require("foxbot.mood")

  -- Order of precedence. Something blocked on you beats everything.
  check("blocked outranks running",
        Mood.settle({ waiting = 1, running = 3, longestRun = 9999 }), "asking")
  check("blocked outranks the clock",
        Mood.settle({ waiting = 1, nightTime = true, away = true }), "asking")

  -- A long turn is the more interesting fact than a fresh one.
  check("a fresh turn is just running",
        Mood.settle({ running = 1, longestRun = 30 }), "running")
  check("a long turn is focused",
        Mood.settle({ running = 1, longestRun = Mood.DEEP_AFTER }), "focused")
  check("running outranks being away",
        Mood.settle({ running = 1, away = true }), "running")
  check("running outranks the hour",
        Mood.settle({ running = 1, nightTime = true }), "running")

  -- Ambient states, only when nothing is happening.
  check("away means dozing", Mood.settle({ away = true }), "dozing")
  check("away outranks night",
        Mood.settle({ away = true, nightTime = true }), "dozing")
  check("night means asleep", Mood.settle({ nightTime = true }), "sleeping")
  check("a long day shows",
        Mood.settle({ workedToday = Mood.LONG_DAY }), "weary")
  check("a short day doesn't",
        Mood.settle({ workedToday = 60 }), "resting")
  check("night beats tiredness",
        Mood.settle({ nightTime = true, workedToday = Mood.LONG_DAY }), "sleeping")
  check("nothing at all is resting", Mood.settle({}), "resting")
  check("no context is safe", Mood.settle(nil), "resting")

  -- Every mood has to be complete enough to actually render.
  local broken = {}
  for _, name in ipairs(Mood.order) do
    local mood = Mood.get(name)
    if not (mood.label and mood.motion and mood.motion.period and mood.art) then
      broken[#broken + 1] = name
    end
    if mood.badge and not Mood.colour(name) then broken[#broken + 1] = name end
  end
  check("every mood is renderable", #broken, 0)
  check("all ten are listed", #Mood.order, 10)

  -- Whatever settle can return must be a mood that exists.
  local reachable = { "asking", "running", "focused", "dozing", "sleeping",
                      "weary", "resting", "cheering" }
  local missing = 0
  for _, name in ipairs(reachable) do
    if not Mood.all[name] then missing = missing + 1 end
  end
  check("settle only returns real moods", missing, 0)

  check("an unknown kind still gives a mood", Mood.fromKind("nonsense"), "settled")
  check("art falls back", Mood.art("nonsense"), "resting")
end

-- ------------------------------------------------------------ settling moods

do
  -- Sprite.settle is the bit that keeps him in step with reality. Exercised on
  -- a bare table rather than a real sprite, since it only touches these fields
  -- and building the real thing needs a canvas.
  local Sprite = require("foxbot.sprite")

  local function fake(mood, until_)
    local it = setmetatable({
      mood = mood or "resting", until_ = until_, after = "resting",
      wore = nil,
    }, Sprite)
    it.wear = function(self, name) self.wore = name end
    it.paintBadge = function() end
    return it
  end

  -- The bug this exists to catch: with no temporary mood in play it used to
  -- return immediately, so ambient states never arrived. Nothing *happens* at
  -- 2am — if he only re-checked after a reaction wore off, he'd stay wide awake.
  local idle = fake("resting")
  idle:settle(function() return "sleeping" end)
  check("ambient moods arrive with no event", idle.mood, "sleeping")
  check("and he changes drawing for it", idle.wore, "sleeping")

  -- A reaction that hasn't run out yet is left alone.
  local reacting = fake("settled", os.time() + 60)
  reacting:settle(function() return "sleeping" end)
  check("a live reaction is not interrupted", reacting.mood, "settled")
  check("and no drawing swap", reacting.wore, nil)

  -- Once it expires, reality wins.
  local expired = fake("settled", os.time() - 1)
  expired:settle(function() return "running" end)
  check("an expired reaction gives way", expired.mood, "running")
  check("the timer is cleared", expired.until_, nil)

  -- Settling to what he already is must not churn the canvas every tick.
  local same = fake("sleeping")
  same:settle(function() return "sleeping" end)
  check("no needless redraw", same.wore, nil)

  -- No resolver at all falls back rather than erroring.
  local bare = fake("settled", os.time() - 1)
  bare.after = "weary"
  bare:settle(nil)
  check("falls back without a resolver", bare.mood, "weary")
end

-- --------------------------------------------------------------- coat variants

do
  local Coats = require("foxbot.coats")
  local Mood = require("foxbot.mood")

  t.setFiles({ "foxbot.png", "foxbot-sleeping.png", "foxbot-asking.png",
               "vixen.png", "vixen-broken.png", "notes.txt" })

  -- Mood drawings belong to their coat; they are not coats themselves.
  local coats = Coats.all(Mood.order)
  check("variants aren't offered as coats", #coats, 2)
  check("the default comes first", coats[1].id, "foxbot")
  check("and is named", coats[1].label, "Foxbot")
  check("the other coat is there", coats[2].id, "vixen")

  local function filename(path) return path:match("([^/]+)$") end

  check("a mood with art wears it",
        filename(Coats.path("foxbot", "sleeping")), "foxbot-sleeping.png")
  check("a mood without art falls back to the coat",
        filename(Coats.path("foxbot", "cheering")), "foxbot.png")
  check("no mood asked for means the coat",
        filename(Coats.path("foxbot", nil)), "foxbot.png")
  check("another coat keeps its own variants",
        filename(Coats.path("vixen", "broken")), "vixen-broken.png")
  check("and falls back to itself, not the default",
        filename(Coats.path("vixen", "sleeping")), "vixen.png")
  check("an unknown coat falls back to the default",
        filename(Coats.path("ghost", "sleeping")), "foxbot.png")

  local have = Coats.moods("foxbot", Mood.order)
  table.sort(have)
  check("it knows which moods are drawn", #have, 2)
  check("and which they are", table.concat(have, ","), "asking,sleeping")
  check("a coat with one variant", #Coats.moods("vixen", Mood.order), 1)

  -- A coat whose name contains a hyphen must not be mistaken for a variant.
  t.setFiles({ "foxbot.png", "red-panda.png", "red-panda-sleeping.png" })
  local hyphened = Coats.all(Mood.order)
  check("a hyphenated coat name survives", #hyphened, 2)
  check("and its variant still attaches",
        filename(Coats.path("red-panda", "sleeping")), "red-panda-sleeping.png")

  t.setFiles({ "foxbot.png" })
end

-- ---------------------------------------------------------------------- away

do
  local Away = require("foxbot.away")

  local returned, sinceSeen = nil, nil
  local a = Away.new({
    threshold = 300,
    onReturn = function(buffer, since) returned, sinceSeen = buffer, since end,
  })

  t.setIdle(0)
  ok("present while there is input", not a:check())
  ok("not away initially", not a:isAway())

  -- Walking off without locking: idle time alone should be enough.
  t.setIdle(400)
  ok("idle past the threshold counts as away", a:check())
  a:hold({ session = "one" })
  a:hold({ session = "two" })
  check("events are held, not shown", a:count(), 2)
  ok("nothing handed back while still away", returned == nil)

  -- Coming back.
  t.setIdle(0)
  ok("input again means present", not a:check())
  ok("buffer handed back on return", returned ~= nil)
  check("everything held is handed back", #returned, 2)
  check("buffer cleared after handover", a:count(), 0)
  ok("digest knows when you left", sinceSeen ~= nil)

  -- Locking is exact, and beats a zero idle time.
  returned = nil
  t.setIdle(0)
  t.fire("screensDidLock")
  ok("lock means away even with no idle", a:check())
  a:hold({ session = "three" })
  t.fire("screensDidUnlock")
  ok("unlock hands the buffer back", returned ~= nil)
  check("locked buffer handed back", #returned, 1)

  -- Sleep and wake behave the same way.
  returned = nil
  t.fire("systemWillSleep")
  ok("sleep counts as away", a:isAway())
  a:hold({ session = "four" })
  t.fire("systemDidWake")
  check("wake hands back", #returned, 1)

  -- Returning with nothing held must not fire an empty digest.
  returned = nil
  t.setIdle(400); a:check()
  t.setIdle(0);   a:check()
  ok("no digest when nothing happened", returned == nil)

  -- The buffer is bounded, so a runaway loop can't grow it forever.
  t.setIdle(400); a:check()
  for i = 1, 260 do a:hold({ session = "n" .. i }) end
  check("buffer is capped", a:count(), 200)
  t.setIdle(0)

  -- The default: lock and sleep only. Sitting watching a long turn without
  -- touching anything must NOT count as being away, or the pet goes quiet
  -- exactly when you are looking at it.
  local strict = Away.new({ onReturn = function() end })
  check("threshold defaults to lock-only", strict.threshold, 0)
  t.setIdle(99999)
  ok("huge idle is not away by default", not strict:check())
  t.fire("screensDidLock")
  ok("lock still counts with idle disabled", strict:check())
  t.fire("screensDidUnlock")
  ok("unlock returns even with idle huge", not strict:check())
  t.setIdle(0)
end


require("tests.pages")
require("tests.teach")
require("tests.lore")
require("tests.remote")
require("tests.wallet")
require("tests.menu")

os.exit(t.report() and 0 or 1)
