--!strict
-- Pure tests for Shared/Goals (next-goal chip, Instant Grow (1) target). Run: luau tests/goals_test.luau
local Goals = require("../src/shared/Goals")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- ===== nextGoal =====
do
	local c: { Goals.Candidate } = {
		{ kind = "tile", cost = 100 },
		{ kind = "seed", id = "tomato", cost = 40 },
		{ kind = "upgrade", id = "Backpack", cost = 300 },
		{ kind = "rebirth", cost = 1000000 },
	}
	local g = Goals.nextGoal(25, c)
	check(g ~= nil and g.kind == "seed" and g.id == "tomato", "new player: the closest goal is the tomato seed")
	check(g ~= nil and g.remaining == 15 and math.abs(g.fraction - 25 / 40) < 1e-9, "remaining 15, bar at 62.5%")
	g = Goals.nextGoal(40, c)
	check(g ~= nil and g.kind == "tile" and g.remaining == 60, "once the seed is affordable the tile is next")
	g = Goals.nextGoal(99999999, c)
	check(g == nil, "everything affordable: no goal shown")
	check(Goals.nextGoal(0, {}) == nil, "empty list: no goal")
	g = Goals.nextGoal(0, { { kind = "tile", cost = 50 }, { kind = "seed", cost = 50 } })
	check(g ~= nil and g.kind == "seed", "ties resolve by kind name, always the same one")
	g = Goals.nextGoal(-5, { { kind = "tile", cost = 10 } })
	check(g ~= nil and g.fraction == 0, "fraction never below 0")
	g = Goals.nextGoal(10, { { kind = "tile", cost = 10 } })
	check(g == nil, "exactly affordable counts as reached")
	-- the shown goal only ever gets closer while earning
	local last = math.huge
	local mono = true
	for cash = 0, 99, 3 do
		local n = Goals.nextGoal(cash, { { kind = "tile", cost = 100 } })
		if n and n.remaining > last then
			mono = false
		end
		if n then
			last = n.remaining
		end
	end
	check(mono, "remaining shrinks as cash grows")
end

-- ===== slowest =====
do
	check(Goals.slowest({}) == nil, "nothing growing: nil")
	check(Goals.slowest({ { tile = 2, remaining = 0 } }) == nil, "remaining 0 is not growing")
	check(Goals.slowest({ { tile = 1, remaining = 10 }, { tile = 2, remaining = 50 }, { tile = 3, remaining = 20 } }) == 2, "picks the most time left")
	check(Goals.slowest({ { tile = 4, remaining = 50 }, { tile = 2, remaining = 50 } }) == 2, "tie: lowest tile")
end

print(string.format("goals_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("goals_test failed")
end
