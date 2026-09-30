-- Pure checks for the paid-random-items rules and the progressive HUD (run with luau from
-- the game folder):  luau tests/policy_hud.luau
local Config = require("../src/shared/Config")
local Formulas = require("../src/shared/Formulas")
local HudUnlock = require("../src/shared/HudUnlock")

local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

---------------------------------------------------------------------------
-- Paid random items
---------------------------------------------------------------------------
-- Every Robux product that ends in a random result (an egg, a pack with an egg) or changes
-- the odds (luck) is flagged, and so are Taps (eggs are bought with Taps).
for _, p in Config.Products do
	local random = p.kind == "egg" or p.kind == "starter" or p.kind == "luck" or p.kind == "taps"
	check("product flagged: " .. p.key, Formulas.isPaidRandomProduct(p.key) == random, p.kind)
	-- products that hatch something name the egg whose odds are shown before buying
	local hatches = p.kind == "egg" or p.kind == "starter"
	check("product odds source: " .. p.key, (Formulas.productEgg(p.key) ~= nil) == hatches)
end
check("starter pack really contains an egg", Config.StarterPack.eggs > 0 and Formulas.isPaidRandomProduct("StarterPack"))
for _, p in Config.Products do
	if p.kind == "gems" then
		check("gems are not a random item: " .. p.key, not Formulas.isPaidRandomProduct(p.key))
	end
end
check("unknown product is not flagged / has no egg", not Formulas.isPaidRandomProduct("Nope") and Formulas.productEgg("Nope") == nil)

-- Luck and golden passes are paid probability modifiers; utility passes are not.
for _, pass in Config.Passes do
	local modifier = pass.key == "Lucky" or pass.key == "SuperLucky" or pass.key == "VIP" or pass.key == "MagicEggs"
	check("pass flagged: " .. pass.key, Formulas.isPaidRandomPass(pass.key) == modifier)
end

-- Super Lucky is a paid probability modifier: its effect is numeric, it changes the odds every
-- egg panel shows (still summing to 100%), and it is flagged so restricted players cannot buy it.
check("Super Lucky flagged as paid random", Formulas.isPaidRandomPass("SuperLucky") and Config.PaidRandomPasses.SuperLucky == true)
do
	local base = Formulas.luck(0, {}, false, 1)
	local lucky = Formulas.luck(0, { Lucky = true }, false, 1)
	local super = Formulas.luck(0, { SuperLucky = true }, false, 1)
	local both = Formulas.luck(0, { Lucky = true, SuperLucky = true }, false, 1)
	check("Super Lucky adds its documented luck", math.abs(super - (base + Config.PassEffects.SuperLuckyLuck)) < 1e-9, super)
	check("Super Lucky is stronger than Lucky and they stack", super > lucky and math.abs(both - (base + Config.PassEffects.LuckyLuck + Config.PassEffects.SuperLuckyLuck)) < 1e-9, both)
	for _, egg in Config.Eggs do
		local units = 0
		for _, o in Formulas.displayOdds(egg.id, both) do
			units += o.units
		end
		check("odds with Lucky + Super Lucky still sum to 100% (" .. egg.id .. ")", units == 1000000, units)
	end
	-- the rare-and-above odds go up, never below what the player saw without the pass
	local b, a = Formulas.odds("basic", base), Formulas.odds("basic", super)
	check("Super Lucky raises Rare+ odds of the Basic egg", a[3].chance > b[3].chance and a[1].chance < b[1].chance)
end

-- Every egg (Taps eggs are paid too) shows numeric odds that add up to exactly 100%.
for _, egg in Config.Eggs do
	for _, luck in { 1, 1.6, 4 } do
		local units, allPct = 0, true
		for _, o in Formulas.displayOdds(egg.id, luck) do
			units += o.units
			if not o.text:find("%", 1, true) or o.units <= 0 then
				allPct = false
			end
		end
		check(string.format("odds sum to 100%% (%s, luck %.1f)", egg.id, luck), units == 1000000, units)
		check(string.format("every outcome is a positive %% (%s, luck %.1f)", egg.id, luck), allPct)
	end
end

-- The Robux egg is shown with luck 1 on the store / offer card: that is only honest if luck
-- cannot change its odds (every entry is Rare+, so luck scales all weights equally).
local magic = Formulas.productEgg("MagicEgg1") :: string
check("Robux egg found", magic ~= nil and Formulas.EggById[magic] ~= nil and Formulas.EggById[magic].exclusive == true)
do
	local a, b = Formulas.displayOdds(magic, 1), Formulas.displayOdds(magic, 3.2)
	local same = #a == #b
	for i in a do
		if not b[i] or a[i].units ~= b[i].units then
			same = false
		end
	end
	check("Robux egg odds do not depend on the buyer's luck", same)
end
check("starter pack and magic eggs show the same egg", Formulas.productEgg("StarterPack") == magic and Formulas.productEgg("MagicEgg3") == magic)

---------------------------------------------------------------------------
-- Progressive HUD
---------------------------------------------------------------------------
local function count(set: { [string]: boolean }): number
	local n = 0
	for _, v in set do
		if v then
			n += 1
		end
	end
	return n
end
local fresh = HudUnlock.visible({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = 0, rebirthCost = Config.RebirthBaseCost })
-- the dock's TAP button is always there too, so 3 + TAP = 4 buttons at the start
check("new player: only Rewards, Pets and Store", count(fresh) == 3 and fresh.Rewards and fresh.Pets and fresh.Store, count(fresh))
check("new player: no auto chips", not fresh.AutoTap and not fresh.AutoHatch and not fresh.AutoEquip and not fresh.AutoRebirth)
local one = HudUnlock.visible({ totalHatched = 1, zones = { 1 }, rebirths = 0, taps = 0 })
check("first egg: upgrades, quests and auto tap", one.Upgrades and one.Quests and one.AutoTap and not one.Teleport)
local five = HudUnlock.visible({ totalHatched = 5, zones = { 1 }, rebirths = 0, taps = 0 })
check("5 eggs: teleport (the objective points at the next zone)", five.Teleport and five.Index and five.AutoHatch and not five.Rebirth)
local rich = HudUnlock.visible({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = Config.RebirthBaseCost, rebirthCost = Config.RebirthBaseCost })
check("rebirth shows as soon as it is affordable", rich.Rebirth and not rich.AutoRebirth)
local reborn = HudUnlock.visible({ totalHatched = 0, zones = { 1 }, rebirths = 1, taps = 0 })
check("after a rebirth (Taps reset) everything stays, auto rebirth unlocks", count(reborn) == #HudUnlock.NAMES and reborn.AutoRebirth, count(reborn))

-- growing a single player never hides a button
local prev = fresh
local steps = {
	{ totalHatched = 1, zones = { 1 }, rebirths = 0, taps = 10 },
	{ totalHatched = 3, zones = { 1 }, rebirths = 0, taps = 0 },
	{ totalHatched = 9, zones = { 1, 2 }, rebirths = 0, taps = 5000 },
	{ totalHatched = 30, zones = { 1, 2, 3 }, rebirths = 0, taps = 0 },
	{ totalHatched = 80, zones = { 1, 2, 3, 4, 5 }, rebirths = 1, taps = 0 },
}
for i, st in steps do
	local now = HudUnlock.visible(st)
	local lost = {}
	for name, v in prev do
		if v and not now[name] then
			table.insert(lost, name)
		end
	end
	check("step " .. i .. " keeps every button", #lost == 0, table.concat(lost, ","))
	prev = now
end
-- every name returned is one the HUD builds
local known = {}
for _, n in HudUnlock.NAMES do
	known[n] = true
end
for name in reborn do
	check("known HUD name " .. name, known[name] == true)
end

print(string.format("%d policy/HUD checks, %d failures -> %s", total, fails, if fails == 0 then "POLICY/HUD CHECKS PASSED" else "FAILED"))
