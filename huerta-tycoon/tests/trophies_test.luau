--!strict
-- Pure-Luau unit tests for crop sizes and the trophy shelf. Run: tools/luau.exe tests/trophies_test.luau
local Trophies = require("../src/shared/Trophies")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- sizes
do
	check(Trophies.rollSize(0) == "Giant" and Trophies.rollSize(0.0199) == "Giant", "first 2% = Giant")
	check(Trophies.rollSize(0.02) == "Big" and Trophies.rollSize(0.0999) == "Big", "next 8% = Big")
	check(Trophies.rollSize(0.1) == nil and Trophies.rollSize(0.999) == nil, "the rest is normal size")
	local counts = { Giant = 0, Big = 0, Normal = 0 }
	local N = 100000
	for i = 0, N - 1 do
		local s = Trophies.rollSize(i / N) or "Normal"
		counts[s] += 1
	end
	local sum = 0
	for _, row in Trophies.sizeTable() do
		sum += row.pct
		check(math.abs(counts[row.id] / N * 100 - row.pct) < 0.01, "roll frequency matches the published chance: " .. row.id)
	end
	check(math.abs(sum - 100) < 1e-9, "size chances add up to 100")
	check(Trophies.valueMult("Giant") == 3 and Trophies.valueMult("Big") == 1.5 and Trophies.valueMult(nil) == 1 and Trophies.valueMult("Huge") == 1, "value multipliers")
	check(Trophies.scale("Giant") > Trophies.scale("Big") and Trophies.scale("Big") > 1 and Trophies.scale(nil) == 1, "bigger crops look bigger")
end

-- basket keys
do
	check(Trophies.key("carrot", nil, nil) == "carrot|", "plain key is unchanged (old saves)")
	check(Trophies.key("pumpkin", "Golden", nil) == "pumpkin|Golden", "mutated key is unchanged (old saves)")
	check(Trophies.key("pumpkin", "Golden", "Giant") == "pumpkin|Golden|Giant" and Trophies.key("corn", nil, "Big") == "corn||Big", "sized keys")
	check(Trophies.key("corn", nil, "Huge") == "corn|", "unknown size is ignored")
	local a, b, c = Trophies.split("pumpkin|Golden|Giant")
	check(a == "pumpkin" and b == "Golden" and c == "Giant", "split full key")
	a, b, c = Trophies.split("corn||Big")
	check(a == "corn" and b == nil and c == "Big", "split sized plain key")
	a, b, c = Trophies.split("carrot|")
	check(a == "carrot" and b == nil and c == nil, "split old plain key")
	a, b, c = Trophies.split("tomato|Wet")
	check(a == "tomato" and b == "Wet" and c == nil, "split old mutated key")
	a, b, c = Trophies.split("carrot")
	check(a == "carrot" and b == nil and c == nil, "split bare id")
	a, b, c = Trophies.split("corn||Huge")
	check(a == "corn" and c == nil, "split drops an unknown size")
end

-- trophies
do
	check(not Trophies.eligible(nil, nil) and Trophies.eligible("Wet", nil) and Trophies.eligible(nil, "Big") and not Trophies.eligible(nil, "Huge"), "only special crops are eligible")
	check(Trophies.canExhibit(0, nil, nil) == "plain" and Trophies.canExhibit(0, "Wet", nil) == "ok" and Trophies.canExhibit(3, "Wet", nil) == "full" and Trophies.canExhibit(2, nil, "Giant") == "ok", "canExhibit")
	check(Trophies.luckOf("Big", nil) == 0.05 and Trophies.luckOf("Giant", nil) == 0.15 and Trophies.luckOf(nil, nil) == 0, "size luck")
	check(Trophies.luckOf(nil, 2) == 0.02 and Trophies.luckOf(nil, 10) == 0.1 and Trophies.luckOf(nil, 40) == 0.25, "mutation luck, clamped")
	check(Trophies.luckOf("Giant", 40) == 0.4, "giant rainbow = +40%")
	local mult = { Wet = 2, Golden = 10, Rainbow = 40 }
	local function of(id: string): number?
		return mult[id]
	end
	local list: { any } = { { seed = "a", mut = "Wet" }, { seed = "b", size = "Giant" }, { seed = "c", mut = "Rainbow", size = "Giant" }, { seed = "d", mut = "Rainbow", size = "Giant" } }
	check(Trophies.totalLuck(list :: any, of) == 0.57, "total luck counts only the 3 pedestals (got " .. Trophies.totalLuck(list :: any, of) .. ")")
	check(Trophies.totalLuck({}, of) == 0, "empty shelf = no luck")
	check(Trophies.SLOTS * Trophies.luckOf("Giant", 40) <= 1.2 + 1e-9, "the shelf can at most add +120% luck")
end

print(string.format("trophies_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("trophies_test failed")
end
