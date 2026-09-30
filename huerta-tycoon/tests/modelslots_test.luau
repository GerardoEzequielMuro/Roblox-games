--!strict
-- Pure tests for the model-slot math (src/shared/ModelFit.luau). Run: luau tests/modelslots_test.luau
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

-- scale: tightest axis wins, proportions kept
check(near(ModelFit.scaleFactor(10, 10, 10, 5, 20, 20), 0.5), "width limits the scale")
check(near(ModelFit.scaleFactor(2, 4, 2, 10, 10, 10), 2.5), "height limits the scale (grows small models)")
check(near(ModelFit.scaleFactor(0, 4, 0, 10, 8, 10), 2), "flat axes are ignored")
check(ModelFit.scaleFactor(0, 0, 0, 1, 1, 1) == 1, "degenerate size returns 1")
check(ModelFit.scaleFactor(4, 4, 4, 0, 0, 0) == 1, "degenerate target returns 1")

-- variants
local lib = { tree = true, tree_1 = true, tree_2 = true, rock_1 = true, bush_2 = true }
local has = function(n: string): boolean
	return lib[n] == true
end
check(#ModelFit.variantNames("tree", has) == 3, "tree + tree_1 + tree_2")
check(ModelFit.variantNames("tree", has)[1] == "tree", "base name first")
check(#ModelFit.variantNames("rock", has) == 1 and ModelFit.variantNames("rock", has)[1] == "rock_1", "variants without base")
check(#ModelFit.variantNames("bush", has) == 0, "a gap at _1 ends the list")
check(ModelFit.choose("bench", has, 3, 4) == nil, "empty slot picks nothing")
check(ModelFit.pickVariant(0, 1, 1) == 0, "no variants -> 0")
local seen: { [number]: boolean } = {}
for x = 0, 40 do
	for z = 0, 40 do
		local v = ModelFit.pickVariant(3, x * 7, z * 11)
		check(v >= 1 and v <= 3, "variant in range")
		seen[v] = true
	end
end
check(seen[1] and seen[2] and seen[3], "all variants get used across a forest")
check(ModelFit.pickVariant(3, 12.2, -40.1) == ModelFit.pickVariant(3, 12.2, -40.1), "picker is deterministic")
local y = ModelFit.yaw(10, 20)
check(y >= 0 and y < math.pi * 2, "yaw in [0, 2pi)")

-- budget
check(ModelFit.withinBudget(100, 300, 0, 6000), "normal model fits")
check(not ModelFit.withinBudget(301, 300, 0, 6000), "over the slot cap -> fallback")
check(not ModelFit.withinBudget(100, 300, 5950, 6000), "over the world total -> fallback")
check(not ModelFit.withinBudget(0, 300, 0, 6000), "empty model -> fallback")

print(string.format("modelslots_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("modelslots_test failed")
end
