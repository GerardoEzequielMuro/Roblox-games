--!strict
-- Pure-Luau unit tests for the published chances. Run from the project root: tools/luau.exe tests/odds_test.luau
local Odds = require("../src/shared/Odds")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local function sum(rows: { Odds.Row }): number
	local s = 0
	for _, r in rows do
		s += r.pct
	end
	return s
end

-- ===== percentages always add up to exactly 100 =====
do
	local p = Odds.percentages({ 1, 1, 1 }, 1)
	check(math.abs(p[1] + p[2] + p[3] - 100) < 1e-9, "thirds add up to 100 (got " .. (p[1] + p[2] + p[3]) .. ")")
	check(p[1] == 33.4 and p[2] == 33.3 and p[3] == 33.3, "largest remainder goes to the first")
	p = Odds.percentages({ 0, 5 }, 1)
	check(p[1] == 0 and p[2] == 100, "zero weight = 0%")
	p = Odds.percentages({ 0, 0 }, 1)
	check(p[1] == 0 and p[2] == 0, "no weights = no chances")
	p = Odds.percentages({ 0.001, 0.05, 0.949 }, 2)
	check(math.abs(p[1] + p[2] + p[3] - 100) < 1e-9 and p[1] == 0.1 and p[2] == 5, "two decimals")
end

-- ===== Lucky Seed Pack =====
do
	local rows = Odds.luckyTable()
	check(#rows == 6, "six possible seeds")
	check(math.abs(sum(rows) - 100) < 1e-9, "lucky pack chances add up to 100")
	local ids: { [string]: number } = {}
	for _, r in rows do
		check(r.pct > 0, "every listed seed can actually drop: " .. r.id)
		ids[r.id] = r.pct
	end
	check(ids.pumpkin == 30 and ids.watermelon == 25 and ids.apple == 18 and ids.dragonfruit == 14 and ids.mango == 9 and ids.starfruit == 4, "published numbers")
	-- the roll matches the published table (sweep r evenly through [0, 1))
	local counts: { [string]: number } = {}
	local N = 100000
	for i = 0, N - 1 do
		local id = Odds.rollLucky(i / N)
		counts[id] = (counts[id] or 0) + 1
	end
	for _, r in rows do
		local got = (counts[r.id] or 0) / N * 100
		check(math.abs(got - r.pct) < 0.01, string.format("roll frequency of %s: %.3f%% vs published %.1f%%", r.id, got, r.pct))
	end
	check(Odds.rollLucky(0) == "pumpkin" and Odds.rollLucky(0.9999999) == "starfruit", "edges of the roll")
	check(Odds.rollLucky(1) == "starfruit" and Odds.rollLucky(-1) == "pumpkin" and Odds.rollLucky(5) == "starfruit", "out-of-range r still gives a seed (no empty outcome)")
	check(Odds.LuckyPerPack == 3, "3 seeds per pack")
end

-- ===== mutations =====
local MUTS: { Odds.Mutation } = {
	{ id = "Rainbow", baseChance = 0.001 },
	{ id = "Shocked", baseChance = 0.05, weather = "Thunderstorm" },
	{ id = "Golden", baseChance = 0.01 },
	{ id = "Frozen", baseChance = 0.2, weather = "Snow" },
	{ id = "Wet", baseChance = 0.25, weather = "Rain" },
}
local function ctx(luck: number, weather: string?, golden: number?, event: number?): Odds.Ctx
	return { luck = luck, weather = weather, goldenMult = golden or 1, eventMult = event or 1 }
end
local function pct(rows: { Odds.Row }, id: string): number
	for _, r in rows do
		if r.id == id then
			return r.pct
		end
	end
	return -1
end
do
	local clear = Odds.mutationTable(MUTS, ctx(1, nil))
	check(#clear == 6 and clear[6].id == "Normal", "Normal is listed as an outcome")
	check(math.abs(sum(clear) - 100) < 1e-9, "clear-sky chances add up to 100")
	check(pct(clear, "Rainbow") == 0.1 and pct(clear, "Golden") == 1 and pct(clear, "Shocked") == 0 and pct(clear, "Frozen") == 0 and pct(clear, "Wet") == 0, "clear sky: only Rainbow and Golden")
	check(math.abs(pct(clear, "Normal") - 98.9) < 0.011, "clear sky: Normal ~98.9%")

	local rain = Odds.mutationTable(MUTS, ctx(1, "Rain"))
	check(math.abs(sum(rain) - 100) < 1e-9 and pct(rain, "Wet") > 24 and pct(rain, "Wet") < 25 and pct(rain, "Frozen") == 0, "rain adds Wet (after the rarer rolls)")

	local lucky = Odds.mutationTable(MUTS, ctx(2, nil))
	check(pct(lucky, "Rainbow") == 0.2 and pct(lucky, "Golden") > pct(clear, "Golden") and pct(lucky, "Normal") < pct(clear, "Normal"), "luck x2 doubles the rare chances and the table updates")
	check(math.abs(sum(lucky) - 100) < 1e-9, "luck x2 still adds up to 100")

	local golden = Odds.mutationTable(MUTS, ctx(1, "GoldenHour", 5))
	check(math.abs(pct(golden, "Golden") - 5) < 0.02, "Golden Hour x5")
	local festival = Odds.mutationTable(MUTS, ctx(1, "GoldenHour", 5, 3))
	check(math.abs(sum(festival) - 100) < 1e-9 and pct(festival, "Golden") > 14, "event x3 on top of Golden Hour")

	local absurd = Odds.mutationTable(MUTS, ctx(100000, "Rain"))
	check(math.abs(sum(absurd) - 100) < 1e-9 and pct(absurd, "Rainbow") == 100 and pct(absurd, "Normal") == 0, "chances are clamped: never above 100, never negative")
	for _, r in absurd do
		check(r.pct >= 0 and r.pct <= 100, "clamped row " .. r.id)
	end

	-- the single-roll chance used by the server
	check(Odds.mutationChance(MUTS[2], ctx(1, "Rain")) == 0, "wrong weather = 0")
	check(Odds.mutationChance(MUTS[2], ctx(1, "Thunderstorm")) == 0.05, "right weather = base chance")
	check(Odds.mutationChance(MUTS[1], { luck = 1, weather = "Rain", goldenMult = 1, eventMult = 1, exposure = true }) == 0, "exposure roll skips non-weather mutations")
	check(math.abs(Odds.mutationChance(MUTS[5], { luck = 1, weather = "Rain", goldenMult = 1, eventMult = 1, exposure = true }) - 0.25 / 6) < 1e-12, "exposure roll is 1/6 of the normal chance")
end

-- ===== policy gate =====
do
	check(Odds.canOffer("LuckyPack", true) and not Odds.canOffer("LuckyPack", false), "Lucky Seed Pack hidden where paid random items are restricted")
	check(Odds.canOffer("SuperLuck", true) and not Odds.canOffer("SuperLuck", false), "luck boost pass hidden too (it changes the chances)")
	check(Odds.canOffer("DoubleCash", false) and Odds.canOffer("StarterPack", false) and Odds.canOffer("CashSmall", false), "non-random items are never hidden")
end

print(string.format("odds_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("odds_test failed")
end
