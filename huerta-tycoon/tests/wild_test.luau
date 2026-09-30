--!strict
-- Pure-Luau unit tests for the Wild Patch. Run from the project root: tools/luau.exe tests/wild_test.luau
local Wild = require("../src/shared/Wild")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- clock
do
	check(Wild.cycle(0) == 0 and Wild.cycle(3599) == 0 and Wild.cycle(3600) == 1, "one cycle per hour")
	check(Wild.nextAt(3600) == 7200 and Wild.nextAt(3601) == 7200 and Wild.nextAt(7199) == 7200, "next regrow is the top of the next hour")
	local now = 1790000000
	check(Wild.nextAt(now) > now and Wild.nextAt(now) - now <= 3600, "regrow is always within the hour")
end

-- contents
do
	local pool: { [string]: boolean } = {}
	for _, e in Wild.Pool do
		pool[e.id] = true
	end
	local a = Wild.nodes(497222)
	local b = Wild.nodes(497222)
	check(#a == Wild.NODES, "six nodes")
	local same = true
	for i = 1, #a do
		same = same and a[i] == b[i]
		check(pool[a[i]] == true, "node seed comes from the pool: " .. tostring(a[i]))
	end
	check(same, "same cycle = same patch on every server")
	-- across many cycles: patches change, and the pool is roughly honoured
	local counts: { [string]: number } = {}
	local changed, total = 0, 0
	local prev = table.concat(Wild.nodes(500000), ",")
	for c = 500001, 502000 do
		local n = Wild.nodes(c)
		local key = table.concat(n, ",")
		if key ~= prev then
			changed += 1
		end
		prev = key
		for _, id in n do
			counts[id] = (counts[id] or 0) + 1
			total += 1
		end
	end
	check(changed > 1900, "the patch changes from hour to hour (" .. changed .. "/2000)")
	local weightSum = 0
	for _, e in Wild.Pool do
		weightSum += e.weight
	end
	for _, e in Wild.Pool do
		local got = (counts[e.id] or 0) / total
		local want = e.weight / weightSum
		check(math.abs(got - want) < 0.03, string.format("%s appears %.1f%% of the time (pool says %.1f%%)", e.id, got * 100, want * 100))
	end
	check((counts.moonmelon or 0) > 0, "the jackpot seed does show up")
end

-- picking
do
	local cycle = 497222
	check(Wild.canClaim(nil, cycle, 1) and Wild.left(nil, cycle) == 6, "fresh player: everything to pick")
	local saved = Wild.claim(nil, cycle, 3)
	check(not Wild.canClaim(saved, cycle, 3), "a node can be picked once per cycle")
	check(Wild.canClaim(saved, cycle, 4) and Wild.left(saved, cycle) == 5, "the other nodes stay available")
	saved = Wild.claim(saved, cycle, 4)
	check(Wild.left(saved, cycle) == 4 and saved.claimed["3"] and saved.claimed["4"], "picks accumulate")
	check(Wild.canClaim(saved, cycle + 1, 3) and Wild.left(saved, cycle + 1) == 6, "the next hour resets the patch")
	local fresh = Wild.claim(saved, cycle + 1, 1)
	check(fresh.cycle == cycle + 1 and fresh.claimed["3"] == nil and fresh.claimed["1"], "old picks are dropped when the cycle changes")
	check(not Wild.canClaim(saved, cycle, 0) and not Wild.canClaim(saved, cycle, 7) and not Wild.canClaim(saved, cycle, 1.5) and not Wild.canClaim(saved, cycle, "1") and not Wild.canClaim(saved, cycle, nil), "bad node index")
	check(Wild.left({ cycle = cycle, claimed = "x" }, cycle) == 6 and Wild.left("junk", cycle) == 6, "garbage saves are treated as empty")
end

print(string.format("wild_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("wild_test failed")
end
