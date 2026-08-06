--- Donuts: what he earns while you work, and what you've unlocked with them.
---
--- The design, and the reasoning behind the earning rule, is in
--- [docs/DONUTS.md](../../docs/DONUTS.md). The short version of the important
--- part: "more tokens, more donuts" is the obvious rule and it is the wrong
--- one, because it pays you to burn tokens, which is the single behaviour a
--- tool like this must never encourage. So the unit is the **turn**, tokens are
--- a small multiplier, and the multiplier is capped — past 40k a bigger turn
--- earns nothing extra, so there is no reason to inflate one.
---
--- ## The balance is stored, never derived
---
--- It would be tidier to recompute it from the ledger. It would also silently
--- delete everything you had earned the moment a turn aged out of the 30-day
--- retention window. The wallet is its own file with its own lifetime, and
--- `uninstall.sh` leaves it alone.

local Wallet = {}
Wallet.__index = Wallet

-- Earning.
Wallet.PER_TURN     = 1
Wallet.TOKEN_STEP   = 8000     -- one more donut per this many output tokens
Wallet.TOKEN_CAP    = 40000    -- past here, a bigger turn is worth no more
Wallet.A_DAY        = 60       -- ceiling, so leaving it running overnight pays nothing

-- Bonuses.
Wallet.FIRST_TURN   = 3
Wallet.FOCUS_BLOCK  = 5
Wallet.QUICK_ANSWER = 2
Wallet.QUICK_WITHIN = 120      -- seconds
Wallet.STREAK_CAP   = 7

function Wallet.new(path)
  local self = setmetatable({}, Wallet)
  self.path = path
  self.balance = 0
  self.earnedTotal = 0
  self.owned = {}
  self.day = { on = 0, earned = 0 }
  self.lastTurn = 0
  return self
end

function Wallet:load()
  local file = io.open(self.path, "r")
  if not file then return self end
  local text = file:read("*a") or ""
  file:close()

  local ok, saved = pcall(hs.json.decode, text)
  if not ok or type(saved) ~= "table" then return self end

  -- Read defensively. This file is the only record of something you spent
  -- weeks earning, and a half-written one after a crash must not zero it.
  self.balance     = tonumber(saved.balance) or 0
  self.earnedTotal = tonumber(saved.earnedTotal) or self.balance
  -- Rebuilt rather than adopted. `{}` encodes as a JSON array, so a wallet
  -- that has never bought anything decodes back as one -- and anything else
  -- malformed decodes as an array of whatever it was. Shop.restore() calls
  -- id:match() on every key, which throws on a number.
  self.owned = {}
  if type(saved.owned) == "table" then
    for id, held in pairs(saved.owned) do
      if type(id) == "string" and held == true then self.owned[id] = true end
    end
  end
  self.lastTurn    = tonumber(saved.lastTurn) or 0
  if type(saved.day) == "table" then
    self.day = { on = tonumber(saved.day.on) or 0,
                 earned = tonumber(saved.day.earned) or 0 }
  end
  return self
end

--- Written to a temporary file and renamed over the real one.
---
--- `io.open(path, "w")` truncates before it writes, so a crash mid-write
--- leaves a half a JSON object where someone's balance used to be. load()
--- survives that, but surviving it and never causing it are different
--- promises. rename() on the same filesystem is atomic: either the old file
--- is there or the new one is.
function Wallet:save()
  local temp = self.path .. ".tmp"
  local file = io.open(temp, "w")
  if not file then return false end

  local ok = pcall(function()
    file:write(hs.json.encode({
      balance = self.balance, earnedTotal = self.earnedTotal,
      owned = self.owned, day = self.day, lastTurn = self.lastTurn,
    }))
  end)
  local closed = file:close()

  if not ok or not closed then
    os.remove(temp)
    return false
  end
  if not os.rename(temp, self.path) then
    os.remove(temp)
    return false
  end
  return true
end

-- ------------------------------------------------------------------ earning

--- What one turn is worth.
---
--- At least one donut however small it was, plus one per 8k output tokens, and
--- the token part stops counting at 40k. Small tight turns earn more per token
--- than one enormous one, which is the incentive worth having.
function Wallet.forTurn(tokens)
  tokens = math.max(0, tonumber(tokens) or 0)
  return Wallet.PER_TURN
       + math.floor(math.min(tokens, Wallet.TOKEN_CAP) / Wallet.TOKEN_STEP)
end

--- How much of today's allowance is left. Reset lazily rather than on a
--- schedule, so a machine asleep at midnight still rolls over correctly.
function Wallet:roomToday(startOfDay)
  if (self.day.on or 0) < startOfDay then
    self.day = { on = startOfDay, earned = 0 }
  end
  return math.max(0, Wallet.A_DAY - (self.day.earned or 0))
end

--- Credit some donuts, clipped to what's left of today's ceiling.
--- @return number actually credited
function Wallet:earn(amount, startOfDay)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  local room = self:roomToday(startOfDay)
  local given = math.min(amount, room)

  if given > 0 then
    self.balance = self.balance + given
    self.earnedTotal = self.earnedTotal + given
    self.day.earned = (self.day.earned or 0) + given
  end
  -- Saved even when nothing was credited: the day may have just rolled over,
  -- and losing that means the ceiling resets again on the next turn.
  --
  -- A failed save is deliberately NOT rolled back here, unlike in buy(). Buying
  -- has a paired side effect -- you own a thing -- so memory and disk have to
  -- agree or you get the item without the cost. Earning has none: keeping the
  -- donuts in memory means a full disk costs you them at the next restart
  -- rather than immediately, and there is nothing to be inconsistent with.
  self:save()
  return given
end

--- Everything a finished turn is worth, bonuses included.
---
--- @param turn { tokens, at, askedAt }
--- @param startOfDay number
--- @return number credited, table why
function Wallet:credit(turn, startOfDay)
  local why = {}
  local total = Wallet.forTurn(turn.tokens)
  why.turn = total

  -- Showing up. The streak rides along with it rather than being credited
  -- separately: both are "you came back today", and paying them in one go is
  -- what keeps them from being clipped differently by the daily ceiling.
  if (self.lastTurn or 0) < startOfDay then
    total = total + Wallet.FIRST_TURN
    why.first = Wallet.FIRST_TURN

    local streak = math.min(math.max(0, turn.streak or 0), Wallet.STREAK_CAP)
    -- A one-day "streak" is just today. It starts paying on the second.
    if streak > 1 then
      total = total + streak
      why.streak = streak
    end
  end

  -- Unblocking yourself quickly. `askedAt` is when he started waiting on you;
  -- rewarding the gap rewards answering, not the asking.
  if turn.askedAt and turn.at then
    local gap = turn.at - turn.askedAt
    -- A negative gap means the clocks disagree, not that you answered before
    -- being asked. Without the lower bound that reads as instant.
    if gap >= 0 and gap <= Wallet.QUICK_WITHIN then
      total = total + Wallet.QUICK_ANSWER
      why.quick = Wallet.QUICK_ANSWER
    end
  end

  self.lastTurn = turn.at or os.time()
  local given = self:earn(total, startOfDay)
  why.capped = given < total
  return given, why
end

--- The one behaviour worth paying for outright.
function Wallet:finishedFocus(startOfDay)
  return self:earn(Wallet.FOCUS_BLOCK, startOfDay)
end

-- ------------------------------------------------------------------ spending

function Wallet:owns(id)
  return self.owned[id] == true
end

function Wallet:canAfford(price)
  return self.balance >= (price or 0)
end

--- Buy something. Returns false if it's already owned or unaffordable, so the
--- caller never has to check twice — and so a double click can't charge twice.
function Wallet:buy(id, price)
  if self:owns(id) then return false, "owned" end
  if not self:canAfford(price) then return false, "poor" end

  self.balance = self.balance - price
  self.owned[id] = true

  -- If it could not be written down it did not happen. Otherwise you own it
  -- until the next restart, at which point the donuts come back and the thing
  -- you bought does not.
  if not self:save() then
    self.balance = self.balance + price
    self.owned[id] = nil
    return false, "unsaved"
  end
  return true
end

return Wallet
