--!nonstrict
-- Prints the pacing timeline of a free player. Run from the repo root:
--   luau sim/pacing_sim.luau
local Model = require("./PacingModel")

local runs, days = 40, 90
local R = Model.study(runs, days)

local function fmtT(s: number?): string
	if s == nil then
		return "never"
	end
	if s < 120 then
		return string.format("%.0fs", s)
	elseif s < 7200 then
		return string.format("%.1f min", s / 60)
	end
	-- absolute seconds since install: show the day too
	local day = math.floor(s / 86400)
	local inDay = s - day * 86400
	if day == 0 then
		return string.format("%.1f min", s / 60)
	end
	return string.format("day %d +%.0f min", day + 1, inDay / 60)
end

local function row(label: string, key: string, target: string)
	local r = R[key]
	local med = if r then fmtT(r.median) else "n/a"
	local p90 = if r then fmtT(r.p90) else "n/a"
	print(string.format("  %-44s %-20s %-18s %s", label, med, p90, target))
end
local function num(label: string, key: string, target: string, fmt: string?)
	local r = R[key]
	local med = if r and r.median then string.format(fmt or "%.0f", r.median) else "n/a"
	local p90 = if r and r.p90 then string.format(fmt or "%.0f", r.p90) else "n/a"
	print(string.format("  %-44s %-20s %-18s %s", label, med, p90, target))
end

print(string.format("Spin Showdown pacing: %d free players, %d days, %d min first session (first hour is what counts) then %d min/day", runs, days, Model.PARAMS.firstSessionMin, Model.PARAMS.dailyMin))
print(string.format("  %-44s %-20s %-18s %s", "milestone", "median", "p90 (slow)", "target"))
row("first coin (Power Core, by hand)", "firstCoreCoin", "< 10 s")
row("first match finished (paid)", "match1", "< 6 min")
row("first cosmetic owned (tutorial title)", "firstCosmetic", "match 1")
row("first PURCHASE (cheapest: 300 coins)", "firstPurchase", "2-3 matches")
num("  ...match number of that purchase", "firstPurchaseMatch", "2-3")
row("3rd purchase", "purchase3", "< 30 min")
row("level 2", "level2", "< 10 min")
row("level 5 (Auto Charge unlocks)", "level5", "< 30 min")
row("level 10", "level10", "< 2 h")
row("league silver (100 trophies)", "leaguesilver", "~1 h")
row("league gold (250 trophies)", "leaguegold", "days")
row("season tier 1", "tier1", "< 30 min")
row("season tier 10", "tier10", "days")
row("season tier 30 (pass done)", "tier30", "day 18-31")
num("season pass completed on day (of 60)", "seasonDay", "day 18-31")
row("every coin cosmetic owned", "shopDone", "day 14-35")
num("longest gap, first 10 min, any beat (s)", "gapAny600", "< 600")
num("longest gap, first hour, any beat (s)", "gapAny60", "<= 720, p90 1020")
num("longest gap, first hour, item/level/tier (s)", "gapItem60", "(info)")
num("matches played in the first session (75 min)", "matchesDay0", "")
num("level at day 7", "level_d7", "")
num("level at day 30", "level_d30", "")
num("cosmetics owned at day 7 (of total)", "owned_d7", "")
num("cosmetics owned at day 30", "owned_d30", "")
num("cosmetics owned at day 90", "owned_d90", "")
num("total cosmetics in the game", "ownedTotal", "")

-- One player's first hour, beat by beat (seed 3), so gaps are visible.
print("")
print("First hour of one simulated player (seed 3):")
local one = Model.run(3, 2)
for _, b in one.beats do
	if b.t <= 3600 then
		print(string.format("  %5.1f min  %-8s %s", b.t / 60, b.kind, b.what))
	end
end
