--- What donuts buy.
---
--- ## Cosmetics only. Never behaviour.
---
--- Nothing in here may change what Foxbot *does* — not a note you'd otherwise
--- not get, not a stat you can't otherwise see, not a shorter cooldown, not a
--- setting held back. Putting function behind a grind turns a tool into a game
--- that occasionally helps you work, and makes every future feature a pricing
--- question instead of a design one.
---
--- Sound packs are the edge case and they stay in: swapping *which* noise plays
--- is decoration. Adding a noise to an event that had none would not be.
---
--- ## The shelf only holds what it can hand over
---
--- Every item declares whether it can actually be delivered right now, and the
--- shop hides the ones that can't. Sprites need their drawings to exist — the
--- prompts for making them are in [docs/SHOP-SPRITES.md](../../docs/SHOP-SPRITES.md),
--- and the moment a sheet is imported the animal appears on the shelf by
--- itself. A shop listing something it cannot give you is worse than a shop
--- with four things in it.

local Palette = require("foxbot.palette")

local Shop = {}

-- Prices assume a good day is around 40 donuts, so the first thing lands in a
-- few days and the whole shelf is a long while.
local PALETTE_PRICE = { terminal = 120, blueprint = 120, sakura = 150, midnight = 150 }

--- Swapping which sound plays for which event. Decoration, not function: every
--- event that makes a noise already made one.
Shop.PACKS = {
  woodland = { label = "Woodland", price = 100, note = "soft, wooden, outdoors",
               sounds = { done = "Blow", ask = "Morse", nudge = "Morse",
                          error = "Basso", idle = "Bottle" } },
  arcade   = { label = "Arcade", price = 100, note = "blips",
               sounds = { done = "Glass", ask = "Ping", nudge = "Ping",
                          error = "Funk", idle = "Pop" } },
  library  = { label = "Library", price = 100, note = "quiet, papery",
               sounds = { done = "Tink", ask = "Purr", nudge = "Purr",
                          error = "Sosumi", idle = "Tink" } },
}

-- ---------------------------------------------------------------- the shelf

local function paletteItems()
  local out = {}
  for _, name in ipairs(Palette.LOCKED) do
    out[#out + 1] = {
      id = "palette." .. name,
      label = Palette.label(name),
      price = PALETTE_PRICE[name] or 150,
      note = "the panel and the notes",
      ready = true,
    }
  end
  return out
end

local function packItems()
  local out = {}
  local order = { "woodland", "arcade", "library" }
  for _, id in ipairs(order) do
    local pack = Shop.PACKS[id]
    out[#out + 1] = { id = "pack." .. id, label = pack.label,
                      price = pack.price, note = pack.note, ready = true }
  end
  return out
end

--- Animals. Priced from docs/DONUTS.md, but only offered once the drawing for
--- one exists in the assets folder — `have` is the set of installed coats.
local ANIMALS = {
  { coat = "tabby",   label = "Tabby",     price = 400, note = "unimpressed by everything" },
  { coat = "corgi",   label = "Corgi",     price = 400, note = "absurdly pleased to be here" },
  { coat = "raccoon", label = "Raccoon",   price = 550, note = "keeps finding things" },
  { coat = "axolotl", label = "Axolotl",   price = 550, note = "permanently smiling" },
  { coat = "crow",    label = "Crow",      price = 700, note = "far too clever" },
  { coat = "ghost",   label = "Ghost fox", price = 900, note = "the same fox, translucent" },
  { coat = "arctic",  label = "Arctic",    price = 150, note = "white and pale blue" },
  { coat = "melanistic", label = "Melanistic", price = 150, note = "near-black, amber eyes" },
  { coat = "fennec",  label = "Fennec",    price = 200, note = "sand, enormous ears" },
  { coat = "ninetails", label = "Nine-tails", price = 350, note = "more tails than needed" },
}

local function spriteItems(have)
  have = have or {}
  local out = {}
  for _, animal in ipairs(ANIMALS) do
    if have[animal.coat] then
      out[#out + 1] = { id = "coat." .. animal.coat, label = animal.label,
                        price = animal.price, note = animal.note,
                        coat = animal.coat, ready = true }
    end
  end
  return out
end

--- The odds and ends that need no drawing.
local function oddItems()
  return {
    { id = "name", label = "A nameplate", price = 100,
      note = "call him something other than Foxbot", ready = true },
  }
end

--- The whole shelf, by aisle.
--- @param have table set of installed coat ids, from Coats.all()
function Shop.aisles(have)
  return {
    { id = "palettes", label = "Palettes", items = paletteItems() },
    { id = "sounds",   label = "Sound packs", items = packItems() },
    { id = "sprites",  label = "Animals", items = spriteItems(have) },
    { id = "odds",     label = "Odds and ends", items = oddItems() },
  }
end

--- Flat list of everything for sale, for counting and lookups.
function Shop.everything(have)
  local out = {}
  for _, aisle in ipairs(Shop.aisles(have)) do
    for _, item in ipairs(aisle.items) do out[#out + 1] = item end
  end
  return out
end

function Shop.find(id, have)
  for _, item in ipairs(Shop.everything(have)) do
    if item.id == id then return item end
  end
  return nil
end

--- Turn a bought id into whatever it actually does. Kept here rather than in
--- the menu so that "what does owning this mean" has exactly one answer.
---
--- @param apply { palette(name), sounds(map), coat(name), rename() }
function Shop.equip(id, apply)
  local kind, rest = id:match("^(%a+)%.(.+)$")

  if kind == "palette" then
    -- unlock() returns false both for "already listed" and for "no such
    -- palette", so ask whether it exists rather than whether it was added.
    if not Palette.exists(rest) then return false end
    Palette.unlock(rest)
    if apply.palette then apply.palette(rest) end
    return true
  elseif kind == "pack" then
    local pack = Shop.PACKS[rest]
    if pack and apply.sounds then apply.sounds(pack.sounds) end
    return pack ~= nil
  elseif kind == "coat" then
    if apply.coat then apply.coat(rest) end
    return true
  elseif id == "name" then
    if apply.rename then apply.rename() end
    return true
  end
  return false
end

--- Re-apply everything owned at startup, so a bought palette is still in the
--- list after a restart. Buying grants; this is what makes it stick.
function Shop.restore(owned)
  for id in pairs(owned or {}) do
    local name = id:match("^palette%.(.+)$")
    if name then Palette.unlock(name) end
  end
end

return Shop
