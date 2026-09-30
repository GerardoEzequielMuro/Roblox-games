-- Pure tests for the model slot maths (run from the repo root): luau tests/model_slots.luau
local ModelFit = require("../src/shared/ModelFit")

local checks, fails = 0, 0
local function check(name: string, cond: any, detail: any?)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end
local function near(a: number?, b: number): boolean
	return a ~= nil and math.abs(a - b) < 1e-6
end

-- fit: uniform, limited by the tightest axis
check("fit tall", near(ModelFit.fitScale(2, 10, 2, 4, 5, 4), 0.5))
check("fit wide", near(ModelFit.fitScale(10, 2, 2, 5, 8, 8), 0.5))
check("fit upscale", near(ModelFit.fitScale(1, 1, 1, 3, 6, 9), 3))
check("fit exact", near(ModelFit.fitScale(4, 5, 6, 4, 5, 6), 1))
check("fit degenerate src", ModelFit.fitScale(0, 1, 1, 1, 1, 1) == nil)
check("fit degenerate target", ModelFit.fitScale(1, 1, 1, 0, 1, 1) == nil)

-- variant names
check("idx base", ModelFit.variantIndex("tree", "tree") == 0)
check("idx 3", ModelFit.variantIndex("tree_3", "tree") == 3)
check("idx other slot", ModelFit.variantIndex("rock_1", "tree") == nil)
check("idx suffix text", ModelFit.variantIndex("tree_big", "tree") == nil)
check("idx empty suffix", ModelFit.variantIndex("tree_", "tree") == nil)
check("idx prefix only", ModelFit.variantIndex("trees", "tree") == nil)
local v = ModelFit.variantNames({ "tree_10", "rock", "tree_2", "tree", "tree_1", "tree_2", "treehouse" }, "tree")
check("variants sorted", table.concat(v, ",") == "tree,tree_1,tree_2,tree_10", table.concat(v, ","))
check("variants none", #ModelFit.variantNames({ "rock" }, "tree") == 0)

-- pick: deterministic, in range, varies across positions
check("pick single", ModelFit.pickIndex(1, 5, 5) == 1)
check("pick stable", ModelFit.pickIndex(3, 12.5, -40) == ModelFit.pickIndex(3, 12.5, -40))
local seen: { [number]: number } = {}
local inRange = true
for i = 1, 200 do
	local p = ModelFit.pickIndex(3, i * 7.3, -i * 4.1)
	seen[p] = (seen[p] or 0) + 1
	if p < 1 or p > 3 then
		inRange = false
	end
end
check("pick in range", inRange)
check("pick uses all variants", seen[1] ~= nil and seen[2] ~= nil and seen[3] ~= nil)
check("pick negative coords", ModelFit.pickIndex(4, -300.2, -99.9) >= 1)

-- budget
check("budget ok", ModelFit.withinBudget(100, 300, 0, 1000))
check("budget per slot", not ModelFit.withinBudget(301, 300, 0, 1000))
check("budget total", not ModelFit.withinBudget(200, 300, 850, 1000))
check("budget total edge", ModelFit.withinBudget(150, 300, 850, 1000))

print(("model_slots: %d checks, %d failures"):format(checks, fails))
if fails > 0 then
	error("MODEL SLOTS FAILED")
end
print("MODEL SLOTS PASSED")
