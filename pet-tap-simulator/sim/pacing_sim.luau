--!nocheck
-- Pacing simulator: prints the milestone timeline of a free, active player.
-- Run from the project root:  luau sim/pacing_sim.luau [-a seeds [week]]
--   luau sim/pacing_sim.luau               -> 9 seeds, first 4 h of continuous play
--   luau sim/pacing_sim.luau -a 5 week     -> 5 seeds, 7 days of 2 sessions per day (long tail)
-- Times are ACTIVE PLAY time (median over seeds) unless a day is shown.
local Core = require("./pacing_core")
local Config = require("../src/shared/Config")

local args = { ... }
local SEEDS = tonumber(args[1]) or 9
local WEEK = args[2] == "week"

local function fmt(sec: number?): string
	if not sec then
		return "   never"
	end
	sec = math.floor(sec)
	if sec < 60 then
		return string.format("    %2ds ", sec)
	end
	return string.format("%2dh %02dm %02ds", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local sessions = if WEEK then Core.week() else Core.firstSession(240)
local agg = Core.aggregate(SEEDS, sessions)
local function row(label: string, key: string, target: string?)
	local reached = agg.reached[key]
	local extra = if WEEK and agg.dayMed[key] then string.format("  day %d", agg.dayMed[key] + 1) else ""
	print(string.format("  %-34s %s  (%d/%d)%s%s", label, fmt(agg.med[key]), reached or 0, agg.seeds, extra, if target then "   target " .. target else ""))
end

print(string.format("=== Tap Pets Simulator pacing sim: free player, %d seeds, %s ===", SEEDS, if WEEK then "7 days, 2 sessions/day" else "240 min continuous"))
print("First minutes")
print(string.format("  %-34s %s   target < 10 s", "first visible gain (first tap)", fmt(agg.med.firstGain)))
row("first purchase (first egg)", "firstEgg", "< 60 s")
row("first gem upgrade", "upgrade1", "< 3 min")
print(string.format("  %-34s %d (of which gem upgrades: %d)   target >= 3", "purchases by minute 3 (eggs+upgrades)", agg.purchasesBy3, agg.upgradesBy3))
print("Tiers (eggs become affordable / zones / rebirth), times = when the player can first afford it")
for _, egg in Config.Eggs do
	if not egg.exclusive then
		row(string.format("egg %-8s (%s, %s taps)", egg.id, "z" .. egg.zone, tostring(egg.price)), "egg:" .. egg.id)
	end
end
for z = 2, #Config.Zones do
	row(string.format("zone %d %s", z, Config.Zones[z].name), "zone" .. z)
end
for r = 1, 8 do
	row("rebirth #" .. r, "rebirth" .. r, if r == 1 then "30-60 min" else nil)
end
print(string.format("  longest gap between new tiers (eggs/zones/rebirth), first hour: median %s, worst seed %s   target <= 15 min", fmt(agg.gapMedian), fmt(agg.gapWorst)))
print(string.format("  longest stretch with NOTHING new (tier, gift, quest, upgrade), first hour: median %s, worst seed %s   target <= 10 min", fmt(agg.rewardGapMedian), fmt(agg.rewardGapWorst)))
print(string.format("  rebirths by end of run (median): %d", agg.rebirthsMedian))
