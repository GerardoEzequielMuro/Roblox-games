-- Progression pacing guard (pure). Runs the free-player simulator (sim/pacing_core.luau, which
-- reuses the real Config / Formulas / Quests / BattlePass) and fails when a key milestone drifts
-- out of its target window. Run with: luau tests/pacing_check.luau   (about 5 s)
-- Targets and the reasoning live in docs/handoff/ki-warriors.md ("Ronda 5").
local Core = require("../sim/pacing_core")
local Config = require("../src/shared/Config")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

local MIN, HOUR = 60, 3600
local function window(name: string, value: number?, lo: number, hi: number, unit: number, unitName: string)
	if value == nil then
		check(name .. " never happens", false)
		return
	end
	check(string.format("%s = %.1f %s, expected %.1f..%.1f", name, value / unit, unitName, lo / unit, hi / unit), value >= lo and value <= hi)
end

-- structure ---------------------------------------------------------------------------
-- every new planet must offer a better training zone than the best one of the previous planet,
-- otherwise travelling feels like nothing
local prevB = 0
for i, pl in Config.Planets do
	local a, b = pl.zones[1].mult, pl.zones[2].mult
	check("planet " .. i .. " zone A beats the previous zone B", a > prevB or i == 1, a .. " vs " .. prevB)
	check("planet " .. i .. " zone B beats zone A", b > a)
	prevB = b
end
-- the ascension requirement grows about as fast as the planets (one ascension per planet tier)
check("ascension growth close to the planet spacing", Config.Rebirth.growth >= 30 and Config.Rebirth.growth <= 50, Config.Rebirth.growth)

-- simulation --------------------------------------------------------------------------
local SEEDS = 3
local runs = Core.runSeeds(SEEDS, Core.schedules.active, 112)
local function med(fn: (any) -> number?): number?
	return Core.medianOf(runs, fn)
end
local function first(key: string): number?
	return med(function(st)
		return Core.firstPlay(st, key)
	end)
end

-- first minutes: reward < 10 s, first purchase < 60 s, 3+ purchases by minute 3
for seed, st in runs do
	check("seed " .. seed .. ": first gain under 10 s", (Core.firstPlay(st, "gain") or 1e9) <= 10)
	check("seed " .. seed .. ": first purchase under 60 s", (Core.purchaseTime(st, 1) or 1e9) <= 60, Core.purchaseTime(st, 1))
	check("seed " .. seed .. ": 3 purchases by minute 3", (Core.purchaseTime(st, 3) or 1e9) <= 3 * MIN, Core.purchaseTime(st, 3))
	check("seed " .. seed .. ": first form before minute 3", (Core.firstPlay(st, "form:kindled") or 1e9) <= 3 * MIN)
end

-- tiers of the first hour (median of the seeds)
window("form blazing", first("form:blazing"), 4 * MIN, 14 * MIN, MIN, "min")
window("form tempest", first("form:tempest"), 15 * MIN, 40 * MIN, MIN, "min")
window("form eclipse", first("form:eclipse"), 35 * MIN, 70 * MIN, MIN, "min")
window("planet 2", first("planet:" .. Config.Planets[2].id), 4 * MIN, 12 * MIN, MIN, "min")
window("planet 3", first("planet:" .. Config.Planets[3].id), 8 * MIN, 22 * MIN, MIN, "min")
window("planet 4", first("planet:" .. Config.Planets[4].id), 25 * MIN, 50 * MIN, MIN, "min")
window("first ascension (median)", first("ascend:1"), 30 * MIN, 60 * MIN, MIN, "min")
for seed, st in runs do
	window("first ascension, seed " .. seed, Core.firstPlay(st, "ascend:1"), 25 * MIN, 65 * MIN, MIN, "min")
end

-- dead stretches in the first hour
local function newThings(st): number
	local n = 0
	for _, e in st.events do
		if e.play <= HOUR and (e.kind == "form" or e.kind == "planet" or e.kind == "zone" or e.kind == "chapter" or e.kind == "technique" or e.kind == "ascend") then
			n += 1
		end
	end
	return n
end
local gaps = {}
for seed, st in runs do
	local all = Core.maxGap(st, HOUR, false)
	table.insert(gaps, all)
	check("seed " .. seed .. ": never more than 11 min without something new", all <= 11 * MIN, all / MIN)
	check("seed " .. seed .. ": at least 12 tier events in the first hour", newThings(st) >= 12, newThings(st))
end
check("median seed: never more than 10 min without something new", (Core.median(gaps) :: number) <= 10 * MIN, (Core.median(gaps) :: number) / MIN)

-- long tail: measured in hours of play (days of calendar)
window("planet 5", first("planet:" .. Config.Planets[5].id), 50 * MIN, 150 * MIN, HOUR, "h")
window("planet 6", first("planet:" .. Config.Planets[6].id), 1.5 * HOUR, 5 * HOUR, HOUR, "h")
window("planet 7", first("planet:" .. Config.Planets[7].id), 3 * HOUR, 9 * HOUR, HOUR, "h")
window("planet 8", first("planet:" .. Config.Planets[8].id), 6 * HOUR, 16 * HOUR, HOUR, "h")
window("planet 9", first("planet:" .. Config.Planets[9].id), 11 * HOUR, 30 * HOUR, HOUR, "h")
window("planet 10", first("planet:" .. Config.Planets[10].id), 20 * HOUR, 60 * HOUR, HOUR, "h")
window("form primordial (3 ascensions)", first("form:primordial"), 8 * HOUR, 30 * HOUR, HOUR, "h")
window("ascension 3", first("ascend:3"), 1.5 * HOUR, 6 * HOUR, HOUR, "h")

-- battle passes: an active free player finishes each season, but not in the first two weeks
for _, id in { "s1", "s2" } do
	local season = Config.BattlePass.SeasonById[id]
	for seed, st in runs do
		local d = st.bpLog[id]
		local rel = if d then d - (if id == "s2" then 56 else 0) else nil
		check(string.format("battle pass %s finishes within the season (seed %d, day %s of %d)", id, seed, tostring(rel), season.days), rel ~= nil and rel < season.days)
		check(string.format("battle pass %s is not finished in under 14 days (seed %d)", id, seed), rel == nil or rel >= 14, rel)
		check(string.format("battle pass %s: active player done in under 5 weeks (seed %d)", id, seed), rel ~= nil and rel <= 35, rel)
	end
end

if fails == 0 then
	local function m(key: string): string
		return string.format("%.0f", (first(key) or 0) / MIN)
	end
	print(string.format("PACING CHECKS PASSED (planet 2/3/4 at %s/%s/%s min, first ascension %s min, %d seeds)", m("planet:" .. Config.Planets[2].id), m("planet:" .. Config.Planets[3].id), m("planet:" .. Config.Planets[4].id), m("ascend:1"), SEEDS))
else
	print(fails .. " PACING CHECK FAILURES")
end
