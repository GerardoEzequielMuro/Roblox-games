-- Progression pacing report for a free player (run from the repo root):
--   luau sim/pacing_sim.luau            
--   luau sim/pacing_sim.luau -a 12 5     (hours, seeds)
--   luau sim/pacing_sim.luau -a 8 3 events|tiers|trace   [nodaily]   (extra listing of run 1)
local Model = require("./pacing_model")

local args = { ... }
local HOURS = tonumber(args[1]) or 8
local SEEDS = tonumber(args[2]) or 3
local EVENTS_UNTIL = 1500

local function hm(s: number): string
	if s < 600 then
		return string.format("%4.0fs", s)
	end
	return string.format("%dh %02dm %02ds", s // 3600, (s % 3600) // 60, s % 60)
end

local function report(title: string, opts: any?)
	local m, runs = Model.median(SEEDS, HOURS, opts)
	print(string.format("== %s (%d seeds x %d h, median) ==", title, SEEDS, HOURS))
	local rows = {
		{ "first reward (tutorial 40 stardust / daily)", "firstGain", "< 10 s" },
		{ "first planet cracked", "firstPlanet", "" },
		{ "first Stardust sold", "firstStardust", "" },
		{ "first purchase", "firstPurchase", "< 60 s" },
		{ "upgrades bought by minute 3", "upgradesBy3min", ">= 3", true },
		{ "tier events in the first hour", "tiers1h", "", true },
		{ "longest wait for a new tier, first hour", "maxTierGap1h", "< 10 min" },
		{ "  ...same, worst seed", "worstTierGap1h", "< 10 min" },
		{ "galaxy 2 (Verdant)", "zone2", "5-15 min" },
		{ "galaxy 3 (Frost)", "zone3", "" },
		{ "first rebirth", "rebirth1", "30-60 min" },
		{ "galaxy 4 (Ember)", "zone4", "" },
		{ "galaxy 5 (Storm)", "zone5", "" },
		{ "galaxy 6 (Void)", "zone6", "hours" },
		{ "rebirth 2", "rebirth2", "" },
		{ "rebirth 3", "rebirth3", "" },
		{ "rebirth 4", "rebirth4", "" },
		{ "rebirth 5", "rebirth5", "" },
		{ "rebirth 6", "rebirth6", "" },
		{ "rebirth 7", "rebirth7", "" },
		{ "rebirths at the end of the run", "endRebirths", "", true },
	}
	for _, r in rows do
		local v = m[r[2]]
		local text = if v == nil then "not reached" elseif r[4] then string.format("%d", v) elseif v >= HOURS * 3600 and r[2]:find("^[zr]") then string.format("> %d h", HOURS) else hm(v)
		print(string.format("  %-46s %-12s %s", r[1], text, r[3]))
	end
	local first = runs[1]
	if #first.gaps > 0 then
		print("  waits over 10 min between tier events (run 1):")
		for _, g in first.gaps do
			print(string.format("    %s -> %s  (%s)", hm(g.from), hm(g.to), g.what))
		end
	end
	return runs
end

local runs = report("free player, claims the daily reward")
local runsNoDaily = report("free player, no daily reward (worst case)", { daily = false })
if args[4] == "nodaily" then
	runs = runsNoDaily
end
if args[3] == "events" then
	print("-- events, run 1, first 25 min --")
	for _, e in runs[1].events do
		if e.t <= EVENTS_UNTIL then
			print(string.format("  %s  %-8s %s", hm(e.t), e.kind, e.what))
		end
	end
end
if args[3] == "trace" then
	print("-- trace, run 1 (every 3 min) --")
	for i, r in runs[1].trace do
		if i % 3 == 0 then
			print(string.format("  %s sd=%.3g inc=%.3g/s zone=%d tool=%d power=%d dmg=%.3g gateLeft=%.3g", hm(r.t), r.stardust, r.income, r.zone, r.tool, r.power, r.damage, r.gateLeft))
		end
	end
end
if args[3] == "tiers" then
	print("-- tier events (tool / galaxy / first capsule / rebirth), run 1 --")
	for _, e in runs[1].events do
		if e.kind == "tier" then
			print(string.format("  %s  %s", hm(e.t), e.what))
		end
	end
end
