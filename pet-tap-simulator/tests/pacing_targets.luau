-- Pacing guard: runs the free-player pacing sim (sim/pacing_core.luau, which uses the real Config
-- and Formulas) and fails if a key milestone leaves its target window. Run from the project root:
--   luau tests/pacing_targets.luau
-- If you retune Config on purpose, re-run `luau sim/pacing_sim.luau`, check the table, and move the
-- windows below only with a reason (they encode the design: hook in the first minutes, a new tier
-- every 5-15 min in the first hour, first rebirth at 30-60 min, the rest spread over days).
local Core = require("../sim/pacing_core")

local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local MIN = 60
local function window(agg: any, key: string, lo: number, hi: number)
	local t = agg.med[key]
	check(string.format("%s in [%s, %s] min", key, tostring(lo), tostring(hi)), t ~= nil and t >= lo * MIN and t <= hi * MIN, t and string.format("%.1f min", t / MIN) or "never")
end

-- first session, 100 minutes of continuous play
local a = Core.aggregate(7, Core.firstSession(100))
check("first visible gain < 10 s", (a.med.firstGain or 99) < 10, a.med.firstGain)
check("first purchase (egg) < 60 s", (a.med.firstEgg or 1e9) < 60, a.med.firstEgg)
check("first gem upgrade by minute 3", (a.med.upgrade1 or 1e9) <= 3 * MIN, a.med.upgrade1)
check("3+ purchases by minute 3", a.purchasesBy3 >= 3, a.purchasesBy3)
check("3+ gem upgrades by minute 3", a.upgradesBy3 >= 3, a.upgradesBy3)
window(a, "zone2", 3, 8)
window(a, "zone3", 9, 20)
window(a, "zone4", 20, 40)
window(a, "rebirth1", 30, 60)
window(a, "rebirth2", 40, 80)
window(a, "zone5", 60, 150) -- the last zone is an hours-scale goal, not a first-session one
check("tier gap in the first hour (median seed) <= 16 min", a.gapMedian <= 16 * MIN, a.gapMedian / MIN)
check("no stretch > 10.5 min without anything new (tier, gift, quest, upgrade), worst seed", a.rewardGapWorst <= 10.5 * MIN, a.rewardGapWorst / MIN)

-- long tail: a week of two sessions a day
local w = Core.aggregate(3, Core.week())
check("rebirth #5 is not day 1", w.dayMed.rebirth5 ~= nil and w.dayMed.rebirth5 >= 1, w.dayMed.rebirth5)
check("rebirth #7 takes more than 3 days of play", w.med.rebirth7 == nil or w.dayMed.rebirth7 >= 3, w.dayMed.rebirth7)
check("player still has rebirths to chase after a week (4..9 done)", w.rebirthsMedian >= 4 and w.rebirthsMedian <= 9, w.rebirthsMedian)

print(string.format("%d pacing checks, %d failures -> %s", total, fails, if fails == 0 then "PACING TARGETS PASSED" else "FAILED"))
if fails > 0 then
	error("pacing targets failed")
end
