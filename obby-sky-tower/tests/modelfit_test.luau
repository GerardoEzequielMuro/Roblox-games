--!strict
-- Pure tests for Shared/ModelFit (model slots). Run: luau tests/modelfit_test.luau
local ModelFit = require("../src/shared/ModelFit")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- fitScale: the limiting axis wins, proportions kept
check(near(ModelFit.fitScale({ 2, 4, 2 }, { 10, 10, 10 }), 2.5), "tall model limited by Y")
check(near(ModelFit.fitScale({ 4, 2, 2 }, { 8, 100, 100 }), 2), "wide model limited by X")
check(near(ModelFit.fitScale({ 10, 10, 10 }, { 5, 5, 5 }), 0.5), "shrinks big models")
check(near(ModelFit.fitScale({ 0, 4, 0 }, { 1, 8, 1 }), 2), "flat axes ignored")
check(ModelFit.fitScale({ 0, 0, 0 }, { 1, 1, 1 }) == 1, "degenerate model -> 1")
check(ModelFit.fitScale({ 1, 1, 1 }, { 0, 0, 0 }) == 1, "degenerate target -> 1")

-- pickVariant: in range, deterministic, spreads
check(ModelFit.pickVariant(1, 5, 5) == 1 and ModelFit.pickVariant(0, 5, 5) == 1, "single variant")
local seen: { [number]: number } = {}
for x = -40, 40 do
	for z = -40, 40 do
		local v = ModelFit.pickVariant(3, x * 3.7, z * 2.3)
		check(v >= 1 and v <= 3, "variant in range")
		check(v == ModelFit.pickVariant(3, x * 3.7, z * 2.3), "deterministic")
		seen[v] = (seen[v] or 0) + 1
	end
end
for v = 1, 3 do
	check((seen[v] or 0) > 81 * 81 / 3 * 0.8, "variant " .. v .. " gets a fair share")
end
check(ModelFit.pickVariant(3, 10.2, 7.9) == ModelFit.pickVariant(3, 10.4, 8.1), "same stud -> same variant")

-- variantNames
local has = { tree = true, tree_1 = true, tree_3 = true, rock_2 = true }
local t = ModelFit.variantNames("tree", has)
check(#t == 3 and t[1] == "tree" and t[2] == "tree_1" and t[3] == "tree_3", "tree variants")
local r = ModelFit.variantNames("rock", has)
check(#r == 1 and r[1] == "rock_2", "variants without the base name")
check(#ModelFit.variantNames("cloud", has) == 0, "missing slot -> none")

-- budget
check(ModelFit.withinBudget(100, 300, 0, 1500), "small model ok")
check(not ModelFit.withinBudget(301, 300, 0, 1500), "over the slot cap")
check(not ModelFit.withinBudget(100, 300, 1450, 1500), "over the total budget")
check(not ModelFit.withinBudget(0, 300, 0, 1500), "empty model rejected")

print(("modelfit_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("failed")
end
