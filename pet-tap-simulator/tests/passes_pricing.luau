-- Pure checks for the Robux catalogue and the pass logic added in round 2 (run from the game
-- folder):  luau tests/passes_pricing.luau
local Config = require("../src/shared/Config")
local Formulas = require("../src/shared/Formulas")

local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

---------------------------------------------------------------------------
-- Prices: the research guide (docs/research/top-juegos-y-precios.md, section 4.3)
---------------------------------------------------------------------------
local PASS_PRICES = { AutoTap = 149, DoubleTaps = 449, TripleHatch = 199, OctoHatch = 699, AutoHatch = 249, AutoRebirth = 199, Lucky = 249, SuperLucky = 699, MagicEggs = 599, PetSlots = 249, PetSlots2 = 649, Storage = 99, VIP = 299 }
for key, price in PASS_PRICES do
	local pass = Config.PassByKey[key]
	check("pass exists: " .. key, pass ~= nil)
	if pass then
		check("pass price: " .. key, pass.price == price, pass.price)
	end
end
for _, pass in Config.Passes do
	check("pass has a price in the guide: " .. pass.key, PASS_PRICES[pass.key] ~= nil)
	check("pass price is a whole number of Robux: " .. pass.key, pass.price >= 1 and pass.price == math.floor(pass.price))
	check("pass id is 0 until the owner creates it: " .. pass.key, pass.id == 0)
end
for _, product in Config.Products do
	check("product price is a whole number: " .. product.key, product.price >= 1 and product.price == math.floor(product.price))
	check("product id is 0 until the owner creates it: " .. product.key, product.id == 0)
end

-- Ladders go up in price and in what they give
check("x8 costs more than x3", Config.PassByKey.OctoHatch.price > Config.PassByKey.TripleHatch.price)
check("+6 slots costs more than +3", Config.PassByKey.PetSlots2.price > Config.PassByKey.PetSlots.price and Config.PassEffects.ExtraSlots2 > Config.PassEffects.ExtraSlots)
check("Super Lucky costs more than Lucky and gives more", Config.PassByKey.SuperLucky.price > Config.PassByKey.Lucky.price and Config.PassEffects.SuperLuckyLuck > Config.PassEffects.LuckyLuck)
check("Magic Eggs is no longer the cheapest luck item", Config.PassByKey.MagicEggs.price > Config.PassByKey.Lucky.price)

-- Gems: every bigger pack gives more Gems per Robux (and the ladder starts at 49)
do
	local packs = {}
	for _, p in Config.Products do
		if p.kind == "gems" then
			table.insert(packs, p)
		end
	end
	table.sort(packs, function(a, b)
		return a.price < b.price
	end)
	check("gems ladder starts at 49", packs[1].price == 49)
	check("gems ladder has 4 steps", #packs == 4, #packs)
	local prevRate = 0
	for i, p in packs do
		local rate = p.amount / p.price
		check("gems per Robux grows with the pack: " .. p.key, rate > prevRate, rate)
		prevRate = rate
		if i > 1 then
			check("bigger gems pack costs more and gives more: " .. p.key, p.price > packs[i - 1].price and p.amount > packs[i - 1].amount)
		end
	end
	check("gems ladder prices match the guide", packs[2].price == 249 and packs[3].price == 499 and packs[4].price == 999, packs[3].price)
end

-- The Starter Pack's crossed-out price is honest: buying its parts one by one costs at least that.
do
	local sp = Config.StarterPack
	local egg = Config.ProductByKey.MagicEgg1.price
	local luckPacks = math.ceil(sp.luckMinutes / Config.ProductByKey.SuperLuck.amount)
	local luck = luckPacks * Config.ProductByKey.SuperLuck.price
	local gemPack = Config.ProductByKey.GemsSmall
	local gems = math.ceil(sp.gems / gemPack.amount) * gemPack.price
	check("Starter Pack list price is not above the parts' store price", sp.fullPrice <= egg + luck + gems, egg + luck + gems)
	check("Starter Pack is really cheaper than its list price", Config.ProductByKey.StarterPack.price < sp.fullPrice)
end

---------------------------------------------------------------------------
-- Pass logic
---------------------------------------------------------------------------
check("max hatch: none / x3 / x8 / x8 alone", Formulas.maxHatch({}) == 1 and Formulas.maxHatch({ TripleHatch = true }) == 3 and Formulas.maxHatch({ OctoHatch = true }) == 8 and Formulas.maxHatch({ TripleHatch = true, OctoHatch = true }) == 8)
check("only 1 / 3 / 8 are valid hatch sizes", Formulas.validHatchCount(1) and Formulas.validHatchCount(3) and Formulas.validHatchCount(8) and not Formulas.validHatchCount(0) and not Formulas.validHatchCount(2) and not Formulas.validHatchCount(9) and not Formulas.validHatchCount(-3) and not Formulas.validHatchCount(1e9) and not Formulas.validHatchCount("3") and not Formulas.validHatchCount(nil) and not Formulas.validHatchCount(3.5) and not Formulas.validHatchCount(0 / 0))
check("hatch size -> pass", Formulas.hatchPass(3) == "TripleHatch" and Formulas.hatchPass(8) == "OctoHatch" and Formulas.hatchPass(1) == nil)
do
	local owned = Formulas.applyIncluded({ OctoHatch = true })
	check("x8 Hatch includes x3 Hatch", owned.TripleHatch == true and owned.OctoHatch == true)
	local none = Formulas.applyIncluded({ Lucky = true })
	check("nothing else is included", none.TripleHatch == nil and none.OctoHatch == nil)
end

check("pet slots stack: base / +3 / +6 / both", Formulas.maxEquip(0, {}) == 3 and Formulas.maxEquip(0, { PetSlots = true }) == 6 and Formulas.maxEquip(0, { PetSlots2 = true }) == 9 and Formulas.maxEquip(0, { PetSlots = true, PetSlots2 = true }) == 12)
check("gem upgrade slots add on top", Formulas.maxEquip(3, { PetSlots = true, PetSlots2 = true }) == 15)
check("storage: 150 / 200", Formulas.maxInventory({}) == Config.MaxInventory and Formulas.maxInventory({ Storage = true }) == Config.MaxInventory + Config.PassEffects.ExtraStorage)

-- Auto Rebirth: free after 3 manual rebirths, the pass opens it after the first
check("auto rebirth locked at 0 rebirths even with the pass", not Formulas.autoRebirthUnlocked(0, {}) and not Formulas.autoRebirthUnlocked(0, { AutoRebirth = true }))
check("auto rebirth: pass opens it after 1, free needs more", Formulas.autoRebirthUnlocked(1, { AutoRebirth = true }) and not Formulas.autoRebirthUnlocked(1, {}) and not Formulas.autoRebirthUnlocked(Config.AutoRebirthMinRebirths - 1, {}) and Formulas.autoRebirthUnlocked(Config.AutoRebirthMinRebirths, {}))

-- Auto Hatch picks the biggest affordable size that fits
check("auto hatch: x8 when owned, rich and roomy", Formulas.autoHatchCount(8, 1e9, 100, 50) == 8)
check("auto hatch: falls to x3 when x8 is not affordable", Formulas.autoHatchCount(8, 350, 100, 50) == 3)
check("auto hatch: falls to x3 when x8 does not fit", Formulas.autoHatchCount(8, 1e9, 100, 5) == 3)
check("auto hatch: x1 when nothing bigger fits / is owned", Formulas.autoHatchCount(8, 1e9, 100, 2) == 1 and Formulas.autoHatchCount(1, 1e9, 100, 50) == 1 and Formulas.autoHatchCount(3, 1e9, 100, 50) == 3)

print(string.format("%d pricing/pass checks, %d failures -> %s", total, fails, if fails == 0 then "PASSED" else "FAILED"))
if fails > 0 then
	error("passes_pricing failed")
end
