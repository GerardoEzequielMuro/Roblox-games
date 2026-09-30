-- Model slots: fit/scale math, variant collection and picker, budget rule (Shared/ModelFit). Pure.
local ModelFit = require("../src/shared/ModelFit")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- fitScale: limited by the tightest axis, keeps proportions
check("fit: height limits", near(ModelFit.fitScale({ 2, 10, 2 }, { 9, 15, 9 }), 1.5))
check("fit: width limits", near(ModelFit.fitScale({ 10, 2, 2 }, { 5, 15, 9 }), 0.5))
check("fit: scales up small models", near(ModelFit.fitScale({ 1, 1, 1 }, { 4, 8, 6 }), 4))
check("fit: exact", near(ModelFit.fitScale({ 4, 8, 6 }, { 4, 8, 6 }), 1))
check("fit: flat axis ignored", near(ModelFit.fitScale({ 4, 0, 4 }, { 8, 8, 8 }), 2))
check("fit: degenerate -> 1", ModelFit.fitScale({ 0, 0, 0 }, { 8, 8, 8 }) == 1)
check("fit: zero target ignored", near(ModelFit.fitScale({ 2, 2, 2 }, { 0, 4, 6 }), 2))
check("fit: result always fits", (function()
	local size, target = { 3.3, 7.1, 2.2 }, { 9, 15.5, 9 }
	local k = ModelFit.fitScale(size, target)
	for i = 1, 3 do
		if size[i] * k > target[i] + 1e-6 then
			return false
		end
	end
	return true
end)())

-- collectVariants: base first, then numeric order; junk ignored
local v = ModelFit.collectVariants({ "tree_2", "rock", "tree", "tree_10", "tree_1", "tree_old", "tree2", "trees_1", "tree_" }, "tree")
check("variants order", table.concat(v, ",") == "tree,tree_1,tree_2,tree_10", table.concat(v, ","))
check("variants without base", table.concat(ModelFit.collectVariants({ "rock_1", "rock_3" }, "rock"), ",") == "rock_1,rock_3")
check("variants none", #ModelFit.collectVariants({ "rock" }, "tree") == 0)
check("variants empty library", #ModelFit.collectVariants({}, "tree") == 0)
check("slot name is not a prefix match", #ModelFit.collectVariants({ "pine_1" }, "pin") == 0)

-- pickVariant: in range, deterministic, spreads
check("pick: single", ModelFit.pickVariant(1, 5, 0, 9) == 1 and ModelFit.pickVariant(0, 5, 0, 9) == 1)
local counts = { 0, 0, 0 }
local inRange, stable = true, true
for i = 1, 600 do
	local x, z = (i * 37) % 500 - 250, (i * 91) % 500 - 250
	local a = ModelFit.pickVariant(3, x, 0, z)
	if a < 1 or a > 3 or a ~= math.floor(a) then
		inRange = false
	end
	if a ~= ModelFit.pickVariant(3, x + 1e-7, 0, z - 1e-7) then
		stable = false
	end
	counts[a] += 1
end
check("pick: in range", inRange)
check("pick: stable against float noise", stable)
check("pick: all variants used, none hogs", counts[1] > 100 and counts[2] > 100 and counts[3] > 100, table.concat(counts, "/"))

-- budget
check("budget: under cap", ModelFit.withinBudget(300, 300, nil))
check("budget: over cap", not ModelFit.withinBudget(301, 300, nil))
check("budget: world budget left", ModelFit.withinBudget(50, 300, 50) and not ModelFit.withinBudget(51, 300, 50))
check("budget: nothing left", not ModelFit.withinBudget(1, 300, 0))

if fails == 0 then
	print("MODEL FIT CHECKS PASSED")
else
	print(fails .. " FAILED")
	os.exit(1)
end
