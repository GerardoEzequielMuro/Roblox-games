-- Pacing guard: fails when the economy drifts out of the target windows of a free player.
-- Run from the repo root:  luau tests/pacing_test.luau   (the numbers come from sim/pacing_sim.luau)
local Model = require("../sim/PacingModel")

local checks, fails = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local R = Model.study(24, 60)
local DAY = 86400
local function med(k: string): number
	local r = R[k]
	assert(r and r.median, "metric never reached: " .. k)
	return r.median :: number
end
local function p90(k: string): number
	local r = R[k]
	assert(r and r.p90, "metric never reached: " .. k)
	return r.p90 :: number
end

-- first minutes
check("first coin from the Power Core in < 10 s", p90("firstCoreCoin") < 10, p90("firstCoreCoin"))
check("first match paid within 6 min (median)", med("match1") < 6 * 60, med("match1"))
check("a first cosmetic (tutorial title) right after match 1", med("firstCosmetic") <= med("match1") + 1)
check("first coin purchase by match 3 (slowest 10%)", p90("firstPurchaseMatch") <= 3, p90("firstPurchaseMatch"))
check("3rd purchase within 30 min (median)", med("purchase3") < 30 * 60, med("purchase3"))
check("level 2 within 10 min (median)", med("level2") < 10 * 60, med("level2"))
check("Auto Charge (level 5) within 30 min (median)", med("level5") < 30 * 60, med("level5"))
check("level 10 within the first 2 h of play, day 1 (median)", med("level10") < 2 * 3600, med("level10"))

-- no dead stretches in the first hour (a match is ~3.5 min: 10 min = 3 matches; allow the granularity)
check("first 10 min: a new thing at least every 10 min (p90)", p90("gapAny600") <= 600, p90("gapAny600"))
check("first hour: longest stretch without anything new <= 12 min (median)", med("gapAny60") <= 12 * 60, med("gapAny60"))
check("first hour: longest stretch without anything new <= 17 min (p90)", p90("gapAny60") <= 17 * 60, p90("gapAny60"))

-- days / weeks
local tier30Day = med("tier30") / DAY + 1
check("season pass completable in 3-4 weeks by a 25 min/day player (median)", tier30Day >= 18 and tier30Day <= 31, tier30Day)
check("...and the slowest 10% still finish inside the month", p90("tier30") / DAY + 1 <= 31, p90("tier30") / DAY + 1)
check("season tier 1 within 30 min", med("tier1") < 30 * 60, med("tier1"))
local shopDay = med("shopDone") / DAY + 1
check("the coin shop lasts 2-5 weeks for a 25 min/day player", shopDay >= 14 and shopDay <= 35, shopDay)
check("level keeps moving for weeks: not maxed at day 30", med("level_d30") < 100 and med("level_d30") > med("level_d7"))
check("cosmetics keep coming after day 7", med("owned_d30") > med("owned_d7"))

print(string.format("%d checks, %d failures", checks, fails))
if fails > 0 then
	error("PACING TEST FAILED")
end
print("PACING TEST PASSED")
