-- Pure checks for ModelSlots' math (fit scale, variant picker, part budget):
--   luau tests/model_slots.luau
local M = require("../src/server/World/ModelSlotsMath")
local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- fitScale: tightest axis wins, proportions kept
check("fit: tall model limited by height", near(M.fitScale(2, 10, 2, 14, 16, 14), 1.6))
check("fit: wide model limited by width", near(M.fitScale(20, 4, 10, 10, 16, 10), 0.5))
check("fit: scale up", near(M.fitScale(1, 1, 1, 5, 7, 9), 5))
check("fit: exact", near(M.fitScale(3, 3, 3, 3, 3, 3), 1))
check("fit: zero-size axis ignored", near(M.fitScale(0, 4, 2, 10, 8, 10), 2))
check("fit: all zero -> 1", near(M.fitScale(0, 0, 0, 5, 5, 5), 1))
local k = M.fitScale(7, 3, 5, 14, 16, 14)
check("fit: result fits the box", 7 * k <= 14 + 1e-6 and 3 * k <= 16 + 1e-6 and 5 * k <= 14 + 1e-6)

-- variant picker: deterministic, in range, spreads
check("pick: one variant is always 1", M.pickVariant(1, 12.5, -40) == 1)
check("pick: zero count is 1", M.pickVariant(0, 1, 1) == 1)
local counts = { 0, 0, 0 }
local allIn, stable = true, true
for i = 1, 300 do
	local x, z = (i * 7.3) % 200 - 100, (i * 13.7) % 400
	local v = M.pickVariant(3, x, z)
	if v < 1 or v > 3 then
		allIn = false
	end
	if v ~= M.pickVariant(3, x, z) then
		stable = false
	end
	counts[v] += 1
end
check("pick: always in 1..3", allIn)
check("pick: deterministic", stable)
check("pick: every variant is used", counts[1] > 30 and counts[2] > 30 and counts[3] > 30, table.concat(counts, ","))
check("pick: negative coords are valid", M.pickVariant(4, -123.25, -77.5) >= 1)

-- names
local names = M.variantNames("tree", 3)
check("names: base then numbered", #names == 4 and names[1] == "tree" and names[2] == "tree_1" and names[4] == "tree_3")

-- budget
check("budget: within", M.withinBudget(100, 300, 0, 1500))
check("budget: over per-slot cap", not M.withinBudget(301, 300, 0, 1500))
check("budget: at cap is ok", M.withinBudget(300, 300, 0, 1500))
check("budget: over world total", not M.withinBudget(200, 300, 1400, 1500))
check("budget: empty model rejected", not M.withinBudget(0, 300, 0, 1500))

print(string.format("model_slots: %d checks, %d failures", total, fails))
if fails > 0 then
	error("model_slots failed")
end
