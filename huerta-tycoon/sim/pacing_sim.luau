--!strict
-- Crop Kingdom pacing simulator: prints a milestone table for a free, active player.
-- Run: luau sim/pacing_sim.luau        (from huerta-tycoon/)
local Config = require("../src/shared/Config")
local Core = require("./pacing_core")

local RUNS = 101
local HOUR = 4 * 3600
local LONG_RUNS = 9
local LONG = 48 * 3600

local function fmt(sec: number): string
	if sec == math.huge then
		return "never"
	elseif sec < 120 then
		return string.format("%ds", sec)
	elseif sec < 7200 then
		return string.format("%.1fm", sec / 60)
	end
	return string.format("%.1fh", sec / 3600)
end

local function row(name: string, values: { number })
	print(string.format("%-28s p10 %-8s median %-8s p90 %-8s", name, fmt(Core.percentile(values, 0.1)), fmt(Core.percentile(values, 0.5)), fmt(Core.percentile(values, 0.9))))
end

local runs: { Core.S } = {}
local ms: { Core.Milestones } = {}
for i = 1, RUNS do
	local s = Core.run(i, HOUR)
	runs[i] = s
	ms[i] = Core.milestones(s)
end

local function col(f: (Core.Milestones) -> number): { number }
	local out = {}
	for i, m in ms do
		out[i] = f(m)
	end
	return out
end

print(string.format("== Crop Kingdom pacing: free active player, %d runs x %s ==", RUNS, fmt(HOUR)))
row("first cash (daily reward)", col(function(m) return m.firstGain end))
row("first harvest", col(function(m) return m.firstHarvest end))
row("first sale", col(function(m) return m.firstSale end))
row("first purchase", col(function(m) return m.firstBuy end))
row("first tile/upgrade", col(function(m) return m.firstUpgrade end))
row("3rd tile/upgrade", col(function(m) return m.third end))
for _, n in { 8, 10, 15, 20, 30 } do
	row("tile #" .. n, col(function(m) return m.tiles[n] or math.huge end))
end
for i, seed in Config.Seeds do
	if i > 1 then
		row("first " .. seed.id, col(function(m) return m.seeds[seed.id] or math.huge end))
	end
end
for lv = 1, 3 do
	row("Farmhand Lv" .. lv, col(function(m) return m.farmhand[lv] or math.huge end))
end
for n = 1, 3 do
	row("rebirth #" .. n, col(function(m) return m.rebirth[n] or math.huge end))
end
row("longest gap w/o new (1st h)", col(function(m) return m.maxGapFirstHour end))
row("longest gap new seed (1st h)", col(function(m) return m.maxSeedGapFirstHour end))

print("")
print(string.format("== long tail: %d runs x %s of active play ==", LONG_RUNS, fmt(LONG)))
local long: { Core.Milestones } = {}
for i = 1, LONG_RUNS do
	long[i] = Core.milestones(Core.run(1000 + i, LONG))
end
local function lcol(f: (Core.Milestones) -> number): { number }
	local out = {}
	for i, m in long do
		out[i] = f(m)
	end
	return out
end
for _, id in { "dragonfruit", "mango", "starfruit", "moonmelon", "cosmiclotus" } do
	row("first " .. id, lcol(function(m) return m.seeds[id] or math.huge end))
end
for n = 1, 6 do
	row("rebirth #" .. n, lcol(function(m) return m.rebirth[n] or math.huge end))
end
