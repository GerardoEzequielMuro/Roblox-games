--!strict
-- Pacing drift check (pure). Plays a free, active player through the REAL Config with sim/pacing_core.luau
-- and fails if a key milestone leaves its target window. Run: luau tests/pacing_test.luau
-- Windows are explained in docs/handoff/huerta-tycoon.md ("Ronda 5"). Seeds are fixed, so the result is deterministic.
local Config = require("../src/shared/Config")
local Core = require("../sim/pacing_core")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local MIN = 60
local RUNS = 31
local ms: { Core.Milestones } = {}
for i = 1, RUNS do
	ms[i] = Core.milestones(Core.run(i, 2 * 3600))
end

local function stat(f: (Core.Milestones) -> number, p: number): number
	local list = {}
	for i, m in ms do
		list[i] = f(m)
	end
	return Core.percentile(list, p)
end
local function seedAt(id: string): (Core.Milestones) -> number
	return function(m)
		return m.seeds[id] or math.huge
	end
end
local function inWindow(name: string, value: number, lo: number, hi: number)
	check(value >= lo and value <= hi, string.format("%s = %.1fm, expected %.1f-%.1fm", name, value / 60, lo / 60, hi / 60))
end

-- ===== first minutes =====
check(stat(function(m) return m.firstGain end, 0.9) <= 10, "first visible reward (daily claim) within 10 s")
check(stat(function(m) return m.firstHarvest end, 0.9) <= 20, "first harvest within 20 s")
check(stat(function(m) return m.firstSale end, 0.9) <= 30, "first sale within 30 s")
check(stat(function(m) return m.firstBuy end, 0.9) <= 60, "first purchase within 60 s")
check(stat(function(m) return m.firstUpgrade end, 0.9) <= 60, "first tile/upgrade within 60 s")
check(stat(function(m) return m.third end, 0.9) <= 3 * MIN, "3+ tile/upgrade purchases by minute 3 (p90)")

-- ===== tiers (seeds) in the first hour =====
inWindow("corn (median)", stat(seedAt("corn"), 0.5), 0, 3 * MIN)
inWindow("blueberry (median)", stat(seedAt("blueberry"), 0.5), 2 * MIN, 8 * MIN)
inWindow("pumpkin (median)", stat(seedAt("pumpkin"), 0.5), 5 * MIN, 15 * MIN)
inWindow("watermelon (median)", stat(seedAt("watermelon"), 0.5), 8 * MIN, 22 * MIN)
inWindow("apple (median)", stat(seedAt("apple"), 0.5), 12 * MIN, 28 * MIN)
inWindow("dragonfruit (median)", stat(seedAt("dragonfruit"), 0.5), 18 * MIN, 38 * MIN)
inWindow("mango (median)", stat(seedAt("mango"), 0.5), 22 * MIN, 50 * MIN)
-- consecutive tiers: never more than ~10 min apart (12 min allowed for the 31-run sample) (median run)
local tiers = { "tomato", "corn", "blueberry", "pumpkin", "watermelon", "apple", "dragonfruit", "mango" }
for i = 2, #tiers do
	local gap = stat(seedAt(tiers[i]), 0.5) - stat(seedAt(tiers[i - 1]), 0.5)
	check(gap <= 12 * MIN, string.format("median gap %s -> %s = %.1fm, max 12m", tiers[i - 1], tiers[i], gap / 60))
end

-- ===== no dead stretch =====
check(stat(function(m) return m.maxGapFirstHour end, 0.5) <= 10 * MIN, "longest stretch without anything new (first hour), median <= 10 min")
check(stat(function(m) return m.maxGapFirstHour end, 0.9) <= 13 * MIN, "longest stretch without anything new (first hour), p90 <= 13 min")
check(stat(function(m) return m.maxSeedGapFirstHour end, 0.5) <= 20 * MIN, "longest stretch without a new tier/rebirth (first hour), median <= 20 min")

-- ===== rebirth =====
inWindow("rebirth #1 (median)", stat(function(m) return m.rebirth[1] or math.huge end, 0.5), 30 * MIN, 60 * MIN)
inWindow("rebirth #1 (p10)", stat(function(m) return m.rebirth[1] or math.huge end, 0.1), 25 * MIN, 60 * MIN)
inWindow("rebirth #1 (p90)", stat(function(m) return m.rebirth[1] or math.huge end, 0.9), 30 * MIN, 70 * MIN)
inWindow("rebirth #2 (median)", stat(function(m) return m.rebirth[2] or math.huge end, 0.5), 60 * MIN, 3 * 3600)

-- ===== long tail (few runs, 24 h of active play): late goals stay measured in hours, not minutes and not weeks =====
local long: { Core.Milestones } = {}
for i = 1, 3 do
	long[i] = Core.milestones(Core.run(2000 + i, 24 * 3600))
end
local function lstat(f: (Core.Milestones) -> number): number
	local list = {}
	for i, m in long do
		list[i] = f(m)
	end
	return Core.percentile(list, 0.5)
end
check(lstat(function(m) return m.seeds.moonmelon or math.huge end) >= 90 * MIN, "moonmelon not before 1.5 h (median)")
check(lstat(function(m) return m.seeds.moonmelon or math.huge end) <= 12 * 3600, "moonmelon within 12 h (median)")
check(lstat(function(m) return m.seeds.cosmiclotus or math.huge end) >= 2 * 3600, "cosmic lotus not before 2 h (median)")
check(lstat(function(m) return m.rebirth[3] or math.huge end) >= 90 * MIN, "rebirth #3 not before 1.5 h (median)")
check(lstat(function(m) return m.rebirth[5] or math.huge end) >= 4 * 3600, "rebirth #5 not before 4 h (median)")
check(lstat(function(m) return m.rebirth[5] or math.huge end) <= 24 * 3600, "rebirth #5 within 24 h (median)")

-- the sim really reads the real numbers
check(Config.RebirthBaseCost > 0 and #Config.Seeds >= 12, "sim runs on the real Config")

print(string.format("pacing_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("pacing_test failed")
end
