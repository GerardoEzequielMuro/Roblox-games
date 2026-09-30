--!strict
-- Pure-Luau unit tests for the auto-farm rules. Run from the project root: tools/luau.exe tests/autofarm_test.luau
local AutoFarm = require("../src/shared/AutoFarm")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local RULES: AutoFarm.Rules = {
	upgradeId = "Farmhand",
	passKey = "AutoHarvest",
	levelFor = { harvest = 1, plant = 2, sell = 3 },
	interval = { 5, 4, 3 },
	batch = { 2, 3, 4 },
	passInterval = 1,
	passBatch = 30,
	sellAtFill = 1,
}

-- unlocks
do
	local a = AutoFarm.allowed(RULES, 0, false)
	check(not a.harvest and not a.plant and not a.sell, "nothing unlocked at level 0")
	a = AutoFarm.allowed(RULES, 1, false)
	check(a.harvest and not a.plant and not a.sell, "level 1 = harvest only")
	a = AutoFarm.allowed(RULES, 2, false)
	check(a.harvest and a.plant and not a.sell, "level 2 = harvest + plant")
	a = AutoFarm.allowed(RULES, 3, false)
	check(a.harvest and a.plant and a.sell, "level 3 = everything")
	a = AutoFarm.allowed(RULES, 0, true)
	check(a.harvest and a.plant and a.sell, "the pass unlocks everything at level 0")
	check(AutoFarm.requiredLevel(RULES, "plant") == 2 and AutoFarm.requiredLevel(RULES, "nope") == math.huge, "requiredLevel")
	check(AutoFarm.isMode("harvest") and AutoFarm.isMode("sell") and not AutoFarm.isMode("steal") and not AutoFarm.isMode(nil) and not AutoFarm.isMode(1), "isMode")
end

-- effective = wanted AND unlocked
do
	local all = { harvest = true, plant = true, sell = true }
	local e = AutoFarm.effective(RULES, all, 1, false)
	check(e.harvest and not e.plant and not e.sell, "a locked mode never runs even if switched on")
	e = AutoFarm.effective(RULES, { harvest = false, plant = true, sell = false }, 3, false)
	check(not e.harvest and e.plant and not e.sell, "an unlocked mode runs only when switched on")
	check(not AutoFarm.any(AutoFarm.effective(RULES, all, 0, false)), "any() is false when nothing runs")
	check(AutoFarm.any(AutoFarm.effective(RULES, all, 0, true)), "any() is true with the pass")
end

-- pace
do
	check(AutoFarm.interval(RULES, 1, false) == 5 and AutoFarm.interval(RULES, 3, false) == 3, "interval by level")
	check(AutoFarm.interval(RULES, 99, false) == 3 and AutoFarm.interval(RULES, 0, false) == 5, "interval clamps the level")
	check(AutoFarm.interval(RULES, 1, true) == 1, "pass interval")
	check(AutoFarm.batch(RULES, 1, false) == 2 and AutoFarm.batch(RULES, 3, false) == 4 and AutoFarm.batch(RULES, 1, true) == 30, "batch by level / pass")
	check(not AutoFarm.due(100, 104.9, 5), "not due before the interval")
	check(AutoFarm.due(100, 105, 5), "due exactly at the interval")
	check(AutoFarm.due(0, 1000, 5), "due when it never ran")
	-- a free player can never beat the pass: max tiles per second
	local best = 0
	for level = 1, 3 do
		best = math.max(best, AutoFarm.batch(RULES, level, false) / AutoFarm.interval(RULES, level, false))
	end
	check(best < AutoFarm.batch(RULES, 0, true) / AutoFarm.interval(RULES, 0, true), "the pass is strictly faster than any upgrade level")
	check(best <= 2, "free auto-farm stays under 2 tiles per second")
end

-- selling
do
	check(not AutoFarm.shouldSell(0, 25, RULES), "never sell an empty basket")
	check(not AutoFarm.shouldSell(24, 25, RULES), "not yet full")
	check(AutoFarm.shouldSell(25, 25, RULES) and AutoFarm.shouldSell(40, 25, RULES), "sell when full")
	check(AutoFarm.shouldSell(1, 0, RULES), "a zero cap can't lock selling")
end

-- saved toggles
do
	local t = AutoFarm.sanitize(nil)
	check(t.harvest == true and t.plant == false and t.sell == false and t.seed == "", "defaults: harvest on, the rest off")
	t = AutoFarm.sanitize({ harvest = false, plant = true, sell = true, seed = "corn" })
	check(t.harvest == false and t.plant and t.sell and t.seed == "corn", "saved values survive")
	t = AutoFarm.sanitize({ harvest = "yes", plant = 1, seed = 5 })
	check(t.harvest == true and t.plant == false and t.seed == "", "garbage falls back to defaults")
	t = AutoFarm.sanitize("x")
	check(t.harvest == true and t.seed == "", "non-table falls back to defaults")
end

print(string.format("autofarm_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("autofarm_test failed")
end
