--- Tests for the teaching pack and the off-task detector.

local t = require("tests.support")
local check, ok = t.check, t.ok

local Lore = require("foxbot.lore")
local Drift = require("foxbot.drift")

-- --------------------------------------------------------------- the pack

do
  ok("the pack is worth having", #Lore.PACK >= 40)

  local seen, dupes, long, untagged = {}, 0, 0, 0
  for _, item in ipairs(Lore.PACK) do
    if seen[item.text] then dupes = dupes + 1 end
    seen[item.text] = true
    -- A "fact" that fills the bubble is an interruption, not a gift.
    if #item.text > 160 then long = long + 1 end
    if not Lore.TITLES[item.tag] then untagged = untagged + 1 end
  end
  check("nothing is in there twice", dupes, 0)
  check("everything is short enough to read at a glance", long, 0)
  check("every entry has a title for its tag", untagged, 0)

  -- A pack that is all fun facts and no craft is a novelty; the point is that
  -- most of what he tells you is usable.
  local byTag = {}
  for _, item in ipairs(Lore.PACK) do byTag[item.tag] = (byTag[item.tag] or 0) + 1 end
  ok("it covers more than one topic", (function()
    local n = 0
    for _ in pairs(byTag) do n = n + 1 end
    return n >= 5
  end)())
  ok("most of it is practical",
     (#Lore.PACK - (byTag.world or 0)) > (byTag.world or 0))
end

-- ------------------------------------------------------- drawing the bag

do
  -- A tiny pack so exhaustion is cheap to prove.
  local pack = {}
  for i = 1, 5 do pack[i] = { tag = "git", text = "fact " .. i } end

  local store = { loreSeen = {} }
  local lore = Lore.new({ settings = store, pack = pack,
                          save = function() end,
                          -- Deterministic: always take the first still in the
                          -- bag, which is the worst case for repeat detection.
                          random = function() return 1 end })

  local drawn = {}
  for _ = 1, 5 do drawn[#drawn + 1] = lore:pick().text end

  local seen = {}
  local repeats = 0
  for _, text in ipairs(drawn) do
    if seen[text] then repeats = repeats + 1 end
    seen[text] = true
  end
  check("a full cycle repeats nothing", repeats, 0)
  check("and covers the whole pack", #drawn, 5)

  -- The sixth has to come from somewhere: the bag refills.
  local sixth = lore:pick()
  ok("the bag refills when it empties", sixth ~= nil)
  check("and starts a fresh cycle", #store.loreSeen, 1)
end

do
  -- Adding to the pack later must not strand the new entries. Storing the
  -- *seen* set rather than the unseen one is what makes this work.
  local pack = { { tag = "git", text = "one" }, { tag = "git", text = "two" } }
  local store = { loreSeen = { 1, 2 } }
  local lore = Lore.new({ settings = store, pack = pack, save = function() end,
                          random = function() return 1 end })

  pack[3] = { tag = "git", text = "three" }
  check("a newly added entry is reachable", lore:pick().text, "three")
end

do
  local store = {}
  local lore = Lore.new({ settings = store, save = function() end })
  ok("nothing offered yet", not lore:offeredToday(1000))
  lore:markOffered(1500)
  ok("offered today", lore:offeredToday(1000))
  ok("but not tomorrow", not lore:offeredToday(2000))
end

-- ------------------------------------------------------------- drifting

local function drifter(overrides, app)
  local store = { drift = true, driftAfter = 300, driftApps = {},
                  driftAt = 0, driftDay = 0, driftCount = 0 }
  for k, v in pairs(overrides or {}) do store[k] = v end
  local at = { now = 10000 }
  local d = Drift.new({
    settings = store, save = function() end,
    now = function() return at.now end,
    frontmost = function() return app.name end,
  })
  return d, store, at
end

do
  local app = { name = "Discord" }
  local d = drifter(nil, app)

  d:sample(1000)
  check("it notices what's in front", d.app, "Discord")
  check("and starts a clock", d:elapsed(1000), 0)
  check("which runs", d:elapsed(1400), 400)

  -- Switching resets the clock: passing through an app is not being in it.
  app.name = "Terminal"
  d:sample(1400)
  check("switching away resets it", d:elapsed(1400), 0)

  -- His own window must not reset it, or opening the menu would clear the
  -- very measurement the menu is about to show you.
  app.name = "Discord"
  d:sample(1500)
  app.name = "Hammerspoon"
  d:sample(1600)
  check("his own window is ignored", d.app, "Discord")
  check("and doesn't reset the clock", d:elapsed(1900), 400)
end

do
  local app = { name = "Discord" }
  local d, store, at = drifter(nil, app)
  at.now = 10000
  d:sample(10000)

  -- Nothing waiting: he says nothing, however long you're there.
  ok("silent when nothing is waiting",
     d:should(20000, 0, { blocked = 0 }) == nil)

  -- Blocked question, but you only just got there.
  ok("silent before the threshold",
     d:should(10100, 0, { blocked = 1 }) == nil)

  local why = d:should(20000, 0, { blocked = 1 })
  ok("speaks up when something is blocked", why ~= nil)
  check("and says which app", why.app, "Discord")

  ok("a running focus block counts too",
     d:should(20000, 0, { focus = "work" }) ~= nil)
  ok("but a rest block does not",
     d:should(20000, 0, { focus = "rest" }) == nil)

  -- Rate limits.
  d:spoke(20000)
  ok("won't say it again straight away",
     d:should(20500, 0, { blocked = 1 }) == nil)
  ok("but will later", d:should(20000 + Drift.GAP + 1, 0, { blocked = 1 }) ~= nil)

  store.driftCount = Drift.MOST_A_DAY
  ok("and stops after a few in one day",
     d:should(90000, 0, { blocked = 1 }) == nil)
  ok("resetting the next day",
     d:should(90000, 80000, { blocked = 1 }) ~= nil)
end

do
  local app = { name = "Discord" }
  local d = drifter({ drift = false }, app)
  d:sample(1000)
  ok("off means off", d:should(20000, 0, { blocked = 5 }) == nil)
end

do
  -- A browser could be documentation or it could be Twitter, and this cannot
  -- tell without a permission it declines to ask for. So it stays out.
  local app = { name = "Google Chrome" }
  local d = drifter(nil, app)
  d:sample(1000)
  ok("browsers aren't assumed to be a break", not d:isBreak("Google Chrome"))
  ok("so they never trigger it", d:should(20000, 0, { blocked = 1 }) == nil)

  -- Until you say so yourself.
  d:mark("Google Chrome", true)
  ok("unless you say so", d:isBreak("Google Chrome"))
  ok("and then it does", d:should(20000, 0, { blocked = 1 }) ~= nil)
end

do
  -- Turning off a default-on app has to stick. Recording only the additions
  -- would make the built-in list impossible to opt out of.
  local d = drifter(nil, { name = "Discord" })
  ok("Discord counts by default", d:isBreak("Discord"))
  d:mark("Discord", false)
  ok("and can be turned off", not d:isBreak("Discord"))
end

return true
