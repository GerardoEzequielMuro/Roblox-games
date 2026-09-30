--!strict
-- Pure-Luau test for the Robux price list and the rules built on it (Shared/Pricing).
--   luau tests/pricing_test.luau
-- The prices are the ones recommended in docs/research/top-juegos-y-precios.md section 4.2 (obby).
local Pricing = require("../src/shared/Pricing")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end
local function eq(a: any, b: any, msg: string)
	check(a == b, ("%s: expected %s, got %s"):format(msg, tostring(b), tostring(a)))
end
local P, S = Pricing.Products, Pricing.Passes

-- the recommended price list ---------------------------------------------------------------------
eq(P.SkipStage, 19, "skip levels 1-300")
eq(P.SkipStageHigh, 29, "skip levels 301-1000")
eq(P.Skip10, 149, "skip x10")
eq(P.DoubleJump5, 9, "double jump 5 min (first impulse buy)")
eq(P.Coins500, 49, "coins 500")
eq(P.Coins2500, 199, "coins 2500")
eq(P.Coins7000, 499, "coins 7000")
eq(P.StarterPack, 59, "starter pack")
check(S.SpeedCoil >= 79 and S.SpeedCoil <= 99, "speed coil 79-99")
check(S.GravityCoil >= 65 and S.GravityCoil <= 79, "gravity coil 65-79")
eq(S.Fusion, 139, "fusion")
check(S.InfiniteRevives >= 149 and S.InfiniteRevives <= 199, "infinite revives 149-199")
eq(S.DoubleCoins, 195, "2x coins")
eq(S.VIP, 299, "VIP")

-- every price is a positive whole number of Robux (AdSkip = 0 is "not sold") -------------------------
for key, price in P do
	check(price == math.floor(price) and price >= 0, "whole price " .. key)
	check(price > 0 or key == "AdSkip", "only AdSkip is free: " .. key)
end
for key, price in S do
	check(price == math.floor(price) and price > 0, "whole pass price " .. key)
end

-- the ladder makes sense ------------------------------------------------------------------------------
check(P.SkipStage < P.SkipStageHigh, "deeper levels cost more per skip")
check(P.Skip10 < 10 * P.SkipStage, "x10 is cheaper than ten single skips (low band)")
check(P.Skip10 < 10 * P.SkipStageHigh, "x10 is cheaper than ten single skips (high band)")
check(P.Skip10 >= 0.5 * 10 * P.SkipStage, "x10 is not a giveaway (discount at most 50% of the low band)")
check(S.Fusion < S.SpeedCoil + S.GravityCoil, "fusion is cheaper than both coils")
check(S.Fusion > math.max(S.SpeedCoil, S.GravityCoil), "fusion costs more than either coil alone")
check(P.DoubleJump5 < S.DoubleJump, "5 minutes of double jump is cheaper than the pass")
check(P.DoubleJump5 < P.SkipStage, "the first purchase is the cheapest item")
-- coin ladder: every bigger pack gives strictly more coins per Robux
local ladder = { "Coins500", "Coins2500", "Coins7000" }
for i = 2, #ladder do
	check(Pricing.coinsPerRobux(ladder[i]) > Pricing.coinsPerRobux(ladder[i - 1]), "bonus grows: " .. ladder[i])
	check(P[ladder[i]] > P[ladder[i - 1]], "price grows: " .. ladder[i])
end
local base = Pricing.coinsPerRobux("Coins500")
check(Pricing.coinsPerRobux("Coins7000") / base <= 1.6, "top pack bonus stays under +60%")

-- skip bands ---------------------------------------------------------------------------------------------
eq(Pricing.skipKey(0), "SkipStage", "from the lobby")
eq(Pricing.skipKey(299), "SkipStage", "landing on 300 is the cheap band")
eq(Pricing.skipKey(300), "SkipStageHigh", "landing on 301 is the dear band")
eq(Pricing.skipKey(999), "SkipStageHigh", "last stage")
local ids = { SkipStage = 11, SkipStageHigh = 22 }
eq(Pricing.skipProductId(ids, 10), 11, "cheap id")
eq(Pricing.skipProductId(ids, 500), 22, "dear id")
eq(Pricing.skipProductId({ SkipStage = 11, SkipStageHigh = 0 }, 500), 11, "dear id missing: cheap one still sells")
eq(Pricing.skipProductId({ SkipStage = 0, SkipStageHigh = 22 }, 10), 22, "cheap id missing: dear one still sells")
eq(Pricing.skipProductId({ SkipStage = 0, SkipStageHigh = 0 }, 10), 0, "nothing created: not on sale")

-- starter pack: the crossed-out value is what the same things cost separately ---------------------------
local value = Pricing.starterValue(5, 500)
eq(value, 5 * P.SkipStage + P.Coins500, "value = 5 skips + the 500-coin pack at list price")
eq(value, 144, "value today")
check(value > P.StarterPack, "the pack really is cheaper than buying its parts")
check(value <= 4 * P.StarterPack, "anchor at most 4x the price (research: 3-4x)")
eq(Pricing.discountPct(value, P.StarterPack), 59, "honest discount badge")
eq(Pricing.discountPct(100, 100), 0, "no discount when price equals value")
eq(Pricing.discountPct(100, 150), 0, "never negative")
eq(Pricing.discountPct(0, 10), 0, "no value, no badge")
eq(Pricing.discountPct(200, 100), 50, "half")
check(Pricing.starterValue(3, 123) > 3 * P.SkipStage, "coins with no matching pack are still counted")

print(("pricing_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("pricing_test failed")
end
print("pricing test PASSED")
