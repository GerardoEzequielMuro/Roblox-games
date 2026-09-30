--!strict
-- Pricing / monetization config checks (pure). Run: luau tests/pricing_test.luau
-- Config falls back to a stub Color3 when it runs outside Roblox.
local Config = require("../src/shared/Config")
local Odds = require("../src/shared/Odds")
local Goals = require("../src/shared/Goals")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local function price(list: { any }, key: string): number?
	for _, it in list do
		if it.key == key then
			return it.priceHint
		end
	end
	return nil
end

-- ===== recommended prices (docs/research/top-juegos-y-precios.md 4.1) =====
check(price(Config.GamePasses, "DoubleCash") == 349, "2x Cash 349")
check(price(Config.GamePasses, "DoubleGrow") == 399, "2x Grow Speed 399")
check(price(Config.GamePasses, "AutoHarvest") == 199, "Auto Harvest 199")
check(price(Config.GamePasses, "VIP") == 399, "VIP 399")
check(price(Config.GamePasses, "SuperLuck") == 299, "Super Luck 299")
check(price(Config.GamePasses, "BigBasket") == 99 and price(Config.GamePasses, "SellAnywhere") == 149, "Big Basket 99, Sell Anywhere 149")
check(price(Config.DevProducts, "InstantGrowOne") == 9, "Instant Grow (1) is the 9 R$ impulse buy")
check(price(Config.DevProducts, "InstantGrow") == 79 and price(Config.DevProducts, "Restock") == 39, "Instant Grow 79, Restock 39")
check(price(Config.DevProducts, "LuckyPack") == 99, "Lucky Seed Pack 99")
check(price(Config.DevProducts, "CashSmall") == 49 and price(Config.DevProducts, "CashLarge") == 199, "cash ladder 49 / 199 ...")
check(price(Config.DevProducts, "CashMedium") == 499 and price(Config.DevProducts, "CashHuge") == 999, "... 499 / 999")

-- ===== structure =====
do
	local keys: { [string]: boolean } = {}
	local dup = false
	for _, list in { Config.GamePasses, Config.DevProducts, Config.AdProducts } do
		for _, it in list do
			if keys[it.key] then
				dup = true
			end
			keys[it.key] = true
			check(it.priceHint >= 0 and it.priceHint == math.floor(it.priceHint), it.key .. ": whole-Robux price")
		end
	end
	check(not dup, "no duplicate product keys")
end

-- ===== cash pack ladder: more minutes per Robux as the pack grows, never less =====
do
	local order = { "CashSmall", "CashLarge", "CashMedium", "CashHuge" }
	local last = 0
	local mono, complete = true, true
	for _, key in order do
		local r = price(Config.DevProducts, key)
		local m, f, share = Config.CashPackMinutes[key], Config.CashPackFloor[key], Config.CashPackCashShare[key]
		if not (r and m and f and share) then
			complete = false
			continue
		end
		local perRobux = m / r
		if perRobux < last then
			mono = false
		end
		last = perRobux
	end
	check(complete, "every cash pack has minutes, floor and cash share")
	check(mono, "bigger cash packs never give fewer minutes per Robux")
	local small = Config.CashPackMinutes.CashSmall / (price(Config.DevProducts, "CashSmall") :: number)
	local huge = Config.CashPackMinutes.CashHuge / (price(Config.DevProducts, "CashHuge") :: number)
	check(huge / small >= 1.4 and huge / small <= 1.7, "the 999 pack is about +40..+70% vs the smallest")
	check(Config.CashPackFloor.CashHuge > Config.CashPackFloor.CashMedium and Config.CashPackFloor.CashMedium > Config.CashPackFloor.CashLarge, "floors grow with the pack")
end

-- ===== honest anchors: a crossed-out price must be above the real one =====
check(Config.StarterPackListPrice > (price(Config.DevProducts, "StarterPack") :: number), "starter anchor is above its price")
check(Config.StarterPackWindow == 86400, "starter offer window is the real per-player 24 h")

-- ===== policy: paid random items are flagged; the new products are not random =====
check(Odds.RandomItems.LuckyPack and Odds.RandomItems.SuperLuck, "Lucky Pack and Super Luck stay behind the odds/policy gate")
for _, key in { "InstantGrowOne", "CashMedium", "CashHuge", "DoubleGrow", "InstantGrow" } do
	check(not Odds.RandomItems[key], key .. " has fixed contents (not a paid random item)")
end

-- ===== every store item has text in every language =====
do
	local LANGS = { "en", "es", "pt", "fr", "de", "id", "tr", "ru", "ja", "ko", "th", "vi" }
	local missing = 0
	for _, code in LANGS do
		local t = require("../src/shared/Locales/" .. code) :: { [string]: string }
		for _, it in Config.GamePasses do
			if not t["pass." .. it.key .. ".name"] or not t["pass." .. it.key .. ".desc"] then
				missing += 1
				print("missing pass text", code, it.key)
			end
		end
		for _, it in Config.DevProducts do
			if not t["product." .. it.key .. ".name"] or not t["product." .. it.key .. ".desc"] then
				missing += 1
				print("missing product text", code, it.key)
			end
		end
		for _, k in { "msg.instantGrowOne", "msg.instantGrowOneNone", "msg.tutorialGift", "goal.tile", "goal.seed", "goal.upgrade", "goal.rebirth" } do
			if not t[k] then
				missing += 1
				print("missing key", code, k)
			end
		end
	end
	check(missing == 0, "12 languages have every pass/product/goal text")
end

-- ===== first minute: the welcome gift is small but real, and the goal chip has something to show at once =====
check(Config.TutorialGift.cash > 0 and Config.TutorialGift.seeds.tomato > 0, "tutorial gift gives cash and seeds")
do
	local cands: { Goals.Candidate } = { { kind = "tile", cost = Config.TileBaseCost } }
	for _, seed in Config.Seeds do
		table.insert(cands, { kind = "seed", id = seed.id, cost = seed.price })
	end
	local g = Goals.nextGoal(Config.StartingCash, cands)
	check(g ~= nil and g.remaining <= Config.TileBaseCost, "a brand-new player sees a goal within reach")
	local g2 = Goals.nextGoal(Config.StartingCash + Config.TutorialGift.cash, cands)
	check(g2 ~= nil, "after the welcome gift there is still a next goal")
end

print(string.format("pricing_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("pricing_test failed")
end
