-- Ki Warriors pacing simulation: prints the milestone table of a free player.
--   luau sim/pacing_sim.luau
-- (export PATH=/tmp/tools:$PATH). Logic lives in sim/pacing_core.luau; tests/pacing_check.luau
-- fails when a milestone leaves its target window.
local Core = require("./pacing_core")
local Config = require("../src/shared/Config")

local SEEDS = 5

local function mins(s: number?): string
	if s == nil then
		return "    never"
	end
	if s < 120 then
		return string.format("%6.0f s ", s)
	elseif s < 7200 then
		return string.format("%6.1f min", s / 60)
	end
	return string.format("%6.1f h  ", s / 3600)
end

local function day(d: number?): string
	return if d == nil then "" else string.format("day %5.1f", d)
end

local active = Core.runSeeds(SEEDS, Core.schedules.active, 112)
local casual = Core.runSeeds(SEEDS, Core.schedules.casual, 112)

print("KI WARRIORS PACING (free player, median of " .. SEEDS .. " seeds)")
print("active = 100 min first session, then 2 x 35 min a day | casual = 60 min, then 25 min a day")
print("")
print(string.format("%-34s %-10s %-10s | %-10s", "milestone", "active", "", "casual"))

local function row(label: string, key: string)
	local a = Core.medianOf(active, function(st)
		return Core.firstPlay(st, key)
	end)
	local ad = Core.medianOf(active, function(st)
		return Core.firstDay(st, key)
	end)
	local c = Core.medianOf(casual, function(st)
		return Core.firstPlay(st, key)
	end)
	print(string.format("%-34s %s %-9s | %s", label, mins(a), day(ad), mins(c)))
end

print("-- first minutes")
print(string.format("%-34s %s", "first gain (first rep)", mins(Core.medianOf(active, function(st)
	return Core.firstPlay(st, "gain")
end))))
for _, n in { 1, 3 } do
	print(string.format("%-34s %s", "purchase #" .. n, mins(Core.medianOf(active, function(st)
		return Core.purchaseTime(st, n)
	end))))
end
print("-- forms (power)")
for _, f in Config.Forms do
	if not f.special then
		row(string.format("form %-10s (%s)", f.id, require("../src/shared/Format").abbrev(f.reqPower)), "form:" .. f.id)
	end
end
print("-- planets / chapters")
for i, pl in Config.Planets do
	if i > 1 then
		row(string.format("planet %d %-10s", i, pl.id), "planet:" .. pl.id)
	end
	row(string.format("  chapter: boss of %s", pl.id), "chapter:" .. pl.boss.npc)
end
print("-- training zones")
for _, pl in Config.Planets do
	for _, z in pl.zones do
		row(string.format("zone %-14s x%s", z.id, require("../src/shared/Format").abbrev(z.mult)), "zone:" .. z.id)
	end
end
print("-- ascensions")
for n = 1, 6 do
	row("ascension " .. n, "ascend:" .. n)
end
print("-- gear / techniques")
for t = 2, #Config.Gear do
	row("gear tier " .. t, "gear:tier" .. t)
end
for _, t in Config.Techniques do
	if not t.special then
		row("technique " .. t.id, "technique:" .. t.id)
	end
end

print("")
print("-- dead stretches in the first 60 minutes (active, per seed)")
for seed, st in active do
	local all, at1 = Core.maxGap(st, 3600, false)
	local major, at2 = Core.maxGap(st, 3600, true)
	print(string.format("seed %d: longest gap without anything new %4.1f min (from min %4.1f) | without a form/planet/zone/chapter/technique/ascension %4.1f min (from min %4.1f)", seed, all / 60, at1 / 60, major / 60, at2 / 60))
end

print("-- same, first 2 hours of play (active, per seed)")
for seed, st in active do
	local all, at1 = Core.maxGap(st, 7200, false)
	print(string.format("seed %d: longest gap without anything new %4.1f min (from min %4.1f)", seed, all / 60, at1 / 60))
end

print("")
print("-- battle pass (free track, XP 90/tier, 30 tiers, 56-day seasons; joined at season start)")
for _, name in { "active", "casual" } do
	local runs = if name == "active" then active else casual
	for _, id in { "s1", "s2" } do
		local days = {}
		local xp = {}
		local finished = true
		for _, st in runs do
			local d = st.bpLog[id]
			if d == nil then
				finished = false
			else
				table.insert(days, d - (if id == "s2" then 56 else 0))
			end
			table.insert(xp, (st.bp[id] and st.bp[id].xp or 0))
		end
		local finishedText = if finished then string.format("tier 30 on day %d of 56", Core.median(days) :: number) else string.format("not finished (%d/%d XP at the median)", Core.median(xp) :: number, Config.BattlePass.xpPerTier * Config.BattlePass.tiers)
		print(string.format("%-7s %s: %s", name, id, finishedText))
	end
end

print("-- battle pass s1, active player: when each tier arrives (median)")
local line = ""
for _, tier in { 1, 3, 5, 10, 15, 20, 25, 30 } do
	local d = Core.medianOf(active, function(st)
		local rec = st.bpTier.s1 and st.bpTier.s1[tier]
		return rec and rec.t / 86400 or nil
	end)
	line ..= string.format("tier %d: day %.1f | ", tier, d or -1)
end
print(line)
