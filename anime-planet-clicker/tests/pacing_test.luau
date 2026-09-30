-- Pacing guard (run from the repo root): luau tests/pacing_test.luau
-- Plays a free player with sim/pacing_model.luau (real Config + Formulas, fixed seeds, so it is
-- deterministic) and fails when a progression milestone drifts out of its target window.
-- If a Config change is intentional, re-run `luau sim/pacing_sim.luau -a 6 3`, check the table
-- and move the window here together with the numbers.
local Model = require("../sim/pacing_model")

local total, fails = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end
local MIN = 60
local H = 3600
local function between(name: string, v: number?, lo: number, hi: number)
	check(name, v ~= nil and v >= lo and v <= hi, if v then string.format("%.0f s (window %d-%d s)", v, lo, hi) else "not reached")
end

-- 3 seeds x 6 h (median): the whole curve
local m = Model.median(3, 6)
-- the first minutes
check("first reward in under 10 s", m.firstGain ~= nil and m.firstGain < 10, m.firstGain)
check("first Stardust sold in under 30 s", m.firstStardust ~= nil and m.firstStardust < 30, m.firstStardust)
check("first purchase in under 60 s", m.firstPurchase ~= nil and m.firstPurchase < 60, m.firstPurchase)
check("3 or more upgrades by minute 3", m.upgradesBy3min >= 3, m.upgradesBy3min)
-- a new tier about every 5-15 min during the first hour
check("10 or more tier events in the first hour", m.tiers1h >= 10, m.tiers1h)
check("no dead stretch over 10 min in the first hour (median seed)", m.maxTierGap1h <= 10 * MIN, m.maxTierGap1h)
check("no dead stretch over 15 min in the first hour (worst seed)", m.worstTierGap1h <= 15 * MIN, m.worstTierGap1h)
between("galaxy 2 in 2-15 min", m.zone2, 2 * MIN, 15 * MIN)
between("galaxy 3 in 10-30 min", m.zone3, 10 * MIN, 30 * MIN)
between("first rebirth in 30-60 min", m.rebirth1, 30 * MIN, 60 * MIN)
between("galaxy 4 in 25-75 min", m.zone4, 25 * MIN, 75 * MIN)
-- long tail: late galaxies are measured in hours
between("galaxy 5 in 1-4 h", m.zone5, 1 * H, 4 * H)
between("galaxy 6 in 2.5-8 h", m.zone6, 2.5 * H, 8 * H)
between("rebirth 2 in 40 min-2 h", m.rebirth2, 40 * MIN, 2 * H)
check("rebirth 6 is at least 3 h away", m.rebirth6 == nil or m.rebirth6 >= 3 * H, m.rebirth6)
check("rebirth 7 is not reachable in 6 h (goals for days)", m.endRebirths <= 6, m.endRebirths)

-- same first hour without the daily reward (pessimistic): the early beats still hold
local w = Model.median(3, 1.2, { daily = false })
check("no daily: first purchase in under 60 s", w.firstPurchase ~= nil and w.firstPurchase < 60, w.firstPurchase)
check("no daily: 3 or more upgrades by minute 3", w.upgradesBy3min >= 3, w.upgradesBy3min)
between("no daily: galaxy 2 in 2-15 min", w.zone2, 2 * MIN, 15 * MIN)
between("no daily: galaxy 3 in 10-30 min", w.zone3, 10 * MIN, 30 * MIN)
check("no daily: dead stretch at most 18 min in the first hour", w.maxTierGap1h <= 18 * MIN, w.maxTierGap1h)

print(string.format("PACING: %d checks, %d failures", total, fails))
if fails > 0 then
	error("pacing drifted")
end
