--- Tests for donuts.
---
--- The earning rule is the part worth testing hardest. It is the one piece of
--- this project that could, if got wrong, actively encourage you to waste
--- money — so the cap and the ceiling are asserted from both sides.

local t = require("tests.support")
local check, ok = t.check, t.ok

local Wallet = require("foxbot.wallet")
local Shop = require("foxbot.shop")
local Palette = require("foxbot.palette")

local PATH = "/tmp/foxbot-wallet-test.json"
local function fresh()
  os.remove(PATH)
  return Wallet.new(PATH):load()
end

-- --------------------------------------------------------- what a turn earns

do
  check("a tiny turn is still worth one", Wallet.forTurn(200), 1)
  check("nothing at all is worth one", Wallet.forTurn(0), 1)
  check("8k earns the first bonus", Wallet.forTurn(8000), 2)
  check("24k", Wallet.forTurn(24000), 4)
  check("40k", Wallet.forTurn(40000), 6)

  -- The whole point of the rule: past the cap, a bigger turn earns nothing
  -- extra, so there is never a reason to inflate one.
  check("200k earns no more than 40k", Wallet.forTurn(200000), Wallet.forTurn(40000))
  check("and neither does two million", Wallet.forTurn(2000000), 6)

  -- Small tight turns must beat one enormous one for the same tokens, or the
  -- incentive points the wrong way.
  local asFive = 5 * Wallet.forTurn(8000)
  ok("five small turns beat one big one", asFive > Wallet.forTurn(40000))

  -- Nonsense in, no crash out. Token counts come from a parsed transcript.
  check("a negative count is floored", Wallet.forTurn(-5000), 1)
  check("a missing count is floored", Wallet.forTurn(nil), 1)
end

-- ----------------------------------------------------------- the daily limit

do
  local w = fresh()
  local day = 1000

  local given = 0
  for _ = 1, 40 do given = given + w:earn(6, day) end
  check("the day stops at the ceiling", w.day.earned, Wallet.A_DAY)
  check("and credits no more than that", given, Wallet.A_DAY)
  check("so the balance matches", w.balance, Wallet.A_DAY)

  -- Leaving something running overnight must be worth nothing.
  check("nothing more today", w:earn(10, day), 0)

  -- ...and roll over by itself, without a scheduled job, so a machine asleep
  -- at midnight still resets.
  check("tomorrow starts again", w:earn(10, day + 86400), 10)
end

-- --------------------------------------------------------------- the bonuses

do
  local w = fresh()
  local day = 1000

  local given, why = w:credit({ tokens = 8000, at = day + 60 }, day)
  check("the first turn of the day gets the bonus", why.first, Wallet.FIRST_TURN)
  check("on top of the turn", given, 2 + Wallet.FIRST_TURN)

  local _, why2 = w:credit({ tokens = 8000, at = day + 120 }, day)
  check("the second doesn't", why2.first, nil)

  -- Answering quickly is rewarded; asking is not.
  local _, quick = w:credit({ tokens = 1000, at = day + 300, askedAt = day + 250 }, day)
  check("a quick answer is worth something", quick.quick, Wallet.QUICK_ANSWER)

  local _, slow = w:credit({ tokens = 1000, at = day + 900, askedAt = day + 300 }, day)
  check("a slow one isn't", slow.quick, nil)

  check("a finished focus block pays", w:finishedFocus(day), Wallet.FOCUS_BLOCK)

  -- The streak rides with the first turn of a day, not on its own.
  local w2 = fresh()
  local _, day1 = w2:credit({ tokens = 0, at = 1000, streak = 1 }, 1000)
  check("one day is not a streak", day1.streak, nil)

  local w3 = fresh()
  local _, day4 = w3:credit({ tokens = 0, at = 1000, streak = 4 }, 1000)
  check("four days pays four", day4.streak, 4)

  local w4 = fresh()
  local _, huge = w4:credit({ tokens = 0, at = 1000, streak = 90 }, 1000)
  check("and it is capped at a week", huge.streak, Wallet.STREAK_CAP)

  -- Only on the day's first turn: otherwise a busy day pays the streak
  -- forty times over.
  local _, second = w4:credit({ tokens = 0, at = 1100, streak = 90 }, 1000)
  check("and only once a day", second.streak, nil)

  check("a streak pays a little", w:streakBonus(3, day), 3)
  check("and is capped at a week", w:streakBonus(400, day + 86400), Wallet.STREAK_CAP)
  check("no streak, nothing", w:streakBonus(0, day + 172800), 0)
end

-- ------------------------------------------------------------------ spending

do
  local w = fresh()
  w:earn(60, 1000)

  ok("can't buy what you can't afford", not w:buy("palette.sakura", 150))
  check("and nothing was taken", w.balance, 60)

  w:earn(60, 1000 + 86400)
  w:earn(60, 1000 + 172800)
  check("saved up", w.balance, 180)

  ok("buys it", w:buy("palette.sakura", 150))
  check("and pays for it", w.balance, 30)
  ok("and owns it", w:owns("palette.sakura"))

  -- A double click must not charge twice.
  ok("can't buy it again", not w:buy("palette.sakura", 150))
  check("and wasn't charged again", w.balance, 30)
end

-- ------------------------------------------------- surviving a restart

do
  local w = fresh()
  w:earn(50, 1000)
  w:buy("pack.arcade", 100)          -- unaffordable; must not persist a purchase
  w:save()

  local again = Wallet.new(PATH):load()
  check("the balance came back", again.balance, 50)
  ok("and the failed purchase didn't", not again:owns("pack.arcade"))

  again:earn(60, 1000 + 86400)
  again:buy("pack.arcade", 100)
  again:save()

  local third = Wallet.new(PATH):load()
  ok("a real purchase persists", third:owns("pack.arcade"))
  check("with the right balance", third.balance, 10)

  -- The balance is stored, not derived: this is the bug the file format exists
  -- to avoid, where old turns ageing out would silently zero what you'd earned.
  check("earned total is kept separately", third.earnedTotal, 110)
end

do
  -- A half-written file after a crash must not zero someone's balance.
  local f = io.open(PATH, "w") f:write('{"balance": 421, "ow') f:close()
  local w = Wallet.new(PATH):load()
  check("a truncated file loses nothing it can't read", w.balance, 0)
  ok("and doesn't crash", true)

  f = io.open(PATH, "w") f:write('{"balance": "many", "owned": 7}') f:close()
  w = Wallet.new(PATH):load()
  check("nor does a nonsense one", w.balance, 0)
  check("and owned is still a table", type(w.owned), "table")
end

-- ---------------------------------------------------------------- the shelf

do
  local aisles = Shop.aisles({})
  ok("there are aisles", #aisles >= 3)

  local everything = Shop.everything({})
  ok("with things on the shelf", #everything >= 7)

  local unready = 0
  for _, item in ipairs(everything) do
    if not item.ready then unready = unready + 1 end
    -- Every item has to be buyable: an id, a price and a name.
    if not (item.id and item.price and item.label) then unready = unready + 1 end
  end
  check("everything on the shelf can be handed over", unready, 0)

  -- Animals need their drawings. With none installed, none are offered.
  local animals = 0
  for _, aisle in ipairs(aisles) do
    if aisle.id == "sprites" then animals = #aisle.items end
  end
  check("no animals without their drawings", animals, 0)

  -- Import one, and it appears by itself.
  local withCat = Shop.aisles({ tabby = true })
  local found = nil
  for _, aisle in ipairs(withCat) do
    if aisle.id == "sprites" then found = aisle.items[1] end
  end
  ok("importing a sheet stocks it", found ~= nil)
  check("under the right id", found and found.id, "coat.tabby")
end

do
  -- Cosmetics only. If an id ever appears that isn't one of these kinds, it is
  -- either art or it is a behaviour change that shouldn't be for sale.
  local allowed = { palette = true, pack = true, coat = true }
  local wrong = {}
  for _, item in ipairs(Shop.everything({ tabby = true })) do
    local kind = item.id:match("^(%a+)%.") or item.id
    if not allowed[kind] and item.id ~= "name" then wrong[#wrong + 1] = item.id end
  end
  check("nothing for sale changes behaviour", #wrong, 0)
  if #wrong > 0 then for _, s in ipairs(wrong) do print("     " .. s) end end
end

-- --------------------------------------------------------------- equipping

do
  local applied = {}
  local apply = {
    palette = function(name) applied.palette = name end,
    sounds  = function(map) applied.sounds = map end,
    coat    = function(name) applied.coat = name end,
    rename  = function() applied.renamed = true end,
  }

  ok("a palette equips", Shop.equip("palette.sakura", apply))
  check("by name", applied.palette, "sakura")
  -- ...and joins the list you can pick from, or you bought a thing you can't
  -- select.
  local listed = false
  for _, name in ipairs(Palette.order) do
    if name == "sakura" then listed = true end
  end
  ok("and becomes selectable", listed)

  ok("a sound pack equips", Shop.equip("pack.arcade", apply))
  check("with its mapping", applied.sounds.done, "Glass")

  ok("a coat equips", Shop.equip("coat.tabby", apply))
  check("by name", applied.coat, "tabby")

  ok("the nameplate equips", Shop.equip("name", apply))
  ok("nonsense doesn't", not Shop.equip("nope.nothing", apply))
end

do
  -- Every locked palette must actually render. A bought palette missing a
  -- colour key draws a note with nothing in it, which is the worst possible
  -- outcome for something you spent three days earning.
  local missing = {}
  local was = Palette.skin
  local base = {}
  Palette.use("dusk")
  for key in pairs(Palette.colours()) do base[#base + 1] = key end

  for _, name in ipairs(Palette.LOCKED) do
    Palette.use(name)
    local colours = Palette.colours()
    ok(name .. " exists", colours.label ~= nil)
    for _, key in ipairs(base) do
      if colours[key] == nil then missing[#missing + 1] = name .. "." .. key end
    end
  end
  Palette.use(was)
  check("every locked palette is complete", #missing, 0)
  if #missing > 0 then for _, s in ipairs(missing) do print("     " .. s) end end
end

-- --------------------------------------------------- the CLI says the same

do
  -- The CLI prints "today: 7 of 60" from its own constant, because it reads
  -- the wallet file rather than running any of this. Two copies of a number
  -- is exactly how a tool ends up confidently reporting the wrong ceiling.
  local file = io.open("bin/foxbot", "r")
  if file then
    local text = file:read("*a") file:close()
    local stated = tonumber(text:match("A_DAY%s*=%s*(%d+)"))
    check("the CLI knows the same daily ceiling", stated, Wallet.A_DAY)
  else
    ok("the CLI is where it was expected", false)
  end
end

os.remove(PATH)
return true
