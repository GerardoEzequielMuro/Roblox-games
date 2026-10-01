--!strict
-- Pure tests for the anti-exploit helpers. Run from the project root: luau tests/security_test.luau
local Validate = require("../src/server/Security/Validate")
local RateLimit = require("../src/server/Security/RateLimit")
local ProfileGuard = require("../src/server/Security/ProfileGuard")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local NAN = 0 / 0
local INF = math.huge

-- ===== Validate =====
check(Validate.finite(1) and Validate.finite(-5.5) and Validate.finite(0), "finite accepts numbers")
check(not Validate.finite(NAN) and not Validate.finite(INF) and not Validate.finite(-INF), "finite rejects NaN/inf")
check(not Validate.finite("5") and not Validate.finite(nil) and not Validate.finite({}) and not Validate.finite(true), "finite rejects non-numbers")

check(Validate.integer(5, 1, 10) == 5, "integer ok")
check(Validate.integer(1, 1, 10) == 1 and Validate.integer(10, 1, 10) == 10, "integer bounds inclusive")
check(Validate.integer(0, 1, 10) == nil and Validate.integer(11, 1, 10) == nil, "integer out of range")
check(Validate.integer(2.5, 1, 10) == nil, "integer rejects fractions")
check(Validate.integer(NAN, 1, 10) == nil and Validate.integer(INF, 1, 10) == nil and Validate.integer(-INF, 1, 10) == nil, "integer rejects NaN/inf")
check(Validate.integer("3", 1, 10) == nil and Validate.integer({}, 1, 10) == nil and Validate.integer(nil, 1, 10) == nil, "integer rejects strings/tables/nil")
check(Validate.integer(1e300, 1, 10) == nil, "integer rejects huge")

check(Validate.str("abc", 5) == "abc" and Validate.str("", 5) == "", "str ok")
check(Validate.str(string.rep("x", 1000), 48) == nil, "str caps length")
check(Validate.str(5, 5) == nil and Validate.str(nil, 5) == nil and Validate.str({}, 5) == nil, "str rejects non-strings")

local set = { corn = true, tomato = true }
check(Validate.key("corn", set) == "corn", "key whitelist ok")
check(Validate.key("wheat", set) == nil, "key whitelist rejects unknown")
check(Validate.key(string.rep("a", 500), set) == nil, "key rejects long strings")
check(Validate.key(1, set) == nil and Validate.key({}, set) == nil and Validate.key(nil, set) == nil, "key rejects non-strings")
check(Validate.key("__index", set) == nil, "key does not match metatable-ish names")

check(Validate.clampAmount(5, 1, 50, 1) == 5, "clampAmount passes normal")
check(Validate.clampAmount(5.9, 1, 50, 1) == 5, "clampAmount floors")
check(Validate.clampAmount(NAN, 1, 50, 1) == 1, "clampAmount NaN -> fallback")
check(Validate.clampAmount(INF, 1, 50, 1) == 1 and Validate.clampAmount(-INF, 1, 50, 1) == 1, "clampAmount inf -> fallback")
check(Validate.clampAmount(1e30, 1, 50, 1) == 50 and Validate.clampAmount(-7, 1, 50, 1) == 1, "clampAmount clamps")
check(Validate.clampAmount("9", 1, 50, 1) == 1 and Validate.clampAmount({}, 1, 50, 1) == 1, "clampAmount non-number -> fallback")

check(Validate.bool(true) == true and Validate.bool(false) == false and Validate.bool(1) == nil and Validate.bool("true") == nil, "bool strict")
check(Validate.code(" gro wbig ") == "GROWBIG", "code normalises")
check(Validate.code(string.rep("A", 41)) == nil and Validate.code(5) == nil and Validate.code("   ") == nil, "code rejects bad")
check(Validate.payload(nil) and Validate.payload({}) and not Validate.payload("x") and not Validate.payload(5), "payload must be nil or table")

-- ===== RateLimit: token bucket =====
do
	local b = RateLimit.newBucket(40, 0)
	local ok = 0
	for _ = 1, 100 do
		if RateLimit.take(b, 0, 20, 40) then
			ok += 1
		end
	end
	check(ok == 40, "burst of 40 at t=0 allows exactly 40, got " .. ok)
	check(not RateLimit.take(b, 0.01, 20, 40), "empty bucket refuses")
	check(RateLimit.take(b, 0.06, 20, 40), "refills at the sustained rate")
	-- sustained: one call every 0.05 s is exactly the rate
	local b2 = RateLimit.newBucket(40, 0)
	local refused = 0
	for i = 1, 400 do
		if not RateLimit.take(b2, i * 0.05, 20, 40) then
			refused += 1
		end
	end
	check(refused == 0, "a client at the sustained rate is never refused")
	-- flood at 1000/s for 10 s: at most burst + rate * time pass
	local b3 = RateLimit.newBucket(40, 0)
	local passed = 0
	for i = 1, 10000 do
		if RateLimit.take(b3, i * 0.001, 20, 40) then
			passed += 1
		end
	end
	check(passed <= 40 + 20 * 10 + 1, "flood is capped at burst + rate*time, got " .. passed)
	-- a clock going backwards must not mint tokens
	local b4 = RateLimit.newBucket(1, 100)
	check(RateLimit.take(b4, 100, 20, 40, 1), "first take")
	check(not RateLimit.take(b4, 50, 20, 40, 1), "backwards clock gives nothing")
	check(b4.tokens >= 0, "tokens never negative")
end

-- ===== RateLimit: cooldowns =====
do
	local cd: RateLimit.Cooldowns = {}
	check(RateLimit.ready(cd, "Hello", 10, 1), "first call passes")
	check(not RateLimit.ready(cd, "Hello", 10.5, 1), "second call inside the gap is refused")
	check(RateLimit.ready(cd, "Other", 10.5, 1), "other actions are independent")
	check(RateLimit.ready(cd, "Hello", 11, 1), "passes after the gap")
	check(not RateLimit.ready(cd, "Hello", 11.2, 1), "a refused call does not move the window")
	check(RateLimit.ready(cd, "Hello", 12, 1), "window measured from the last ACCEPTED call")
end

-- ===== RateLimit: strikes (code brute force) =====
do
	local st = RateLimit.newStrikes()
	local locked = false
	for i = 1, 5 do
		locked = RateLimit.strike(st, i, 6, 60, 120)
	end
	check(not locked and not RateLimit.locked(st, 6), "5 misses do not lock")
	check(RateLimit.strike(st, 6, 6, 60, 120), "6th miss locks")
	check(RateLimit.locked(st, 7) and RateLimit.locked(st, 125), "locked for the whole lock time")
	check(not RateLimit.locked(st, 127), "unlocks afterwards")
	-- misses spread over more than the window never lock
	local slow = RateLimit.newStrikes()
	local any = false
	for i = 1, 30 do
		if RateLimit.strike(slow, i * 20, 6, 60, 120) then
			any = true
		end
	end
	check(not any, "slow, spaced misses (a typo now and then) never lock")
end

-- ===== ProfileGuard.sanitize =====
do
	local defaults = { cash = 100, totalEarned = 0 }
	local p: any = {
		cash = NAN,
		totalEarned = INF,
		rebirths = -INF,
		seeds = { corn = 3, tomato = NAN, apple = INF },
		backpack = { ["corn|"] = 2 },
		list = { 1, NAN, 3, INF, 5 },
		nested = { a = { b = NAN, c = 7 } },
	}
	local fixed = ProfileGuard.sanitize(p, defaults)
	check(fixed == 8, "counts every repair, got " .. fixed)
	check(p.cash == 100 and p.totalEarned == 0, "top-level numbers fall back to their default")
	check(p.rebirths == nil, "top-level without default is dropped")
	check(p.seeds.corn == 3 and p.seeds.tomato == nil and p.seeds.apple == nil, "map entries with NaN/inf are dropped")
	check(#p.list == 3 and p.list[1] == 1 and p.list[2] == 3 and p.list[3] == 5, "array entries are removed, order kept")
	check(p.nested.a.b == nil and p.nested.a.c == 7, "nested tables are cleaned")
	check(ProfileGuard.isClean(p), "result is clean")
	check(not ProfileGuard.isClean({ x = { y = NAN } }), "isClean sees nested NaN")
	check(ProfileGuard.sanitize({ a = 1, b = { 2, 3 } }, nil) == 0, "clean data is untouched")

	-- cycles must not hang
	local c: any = { x = 1 }
	c.self = c
	check(ProfileGuard.sanitize(c, nil) == 0, "cycles are survived")
	check(ProfileGuard.isClean(c), "isClean survives cycles")

	-- very deep nesting is bounded
	local deep: any = {}
	local cur = deep
	for _ = 1, 50 do
		cur.n = {}
		cur = cur.n
	end
	check(ProfileGuard.sanitize(deep, nil) == 0, "deep nesting is bounded")
end

-- ===== ProfileGuard.migrate =====
do
	local old: any = { version = 1, cash = -50, rebirths = -2, purchases = "garbage" }
	local v = ProfileGuard.migrate(old)
	check(v == ProfileGuard.CURRENT_VERSION and old.version == ProfileGuard.CURRENT_VERSION, "v1 migrates to current")
	check(old.cash == 0 and old.rebirths == 0, "negative counters are zeroed")
	check(type(old.purchases) == "table", "purchases is a table again")

	local nov: any = { cash = 5 }
	check(ProfileGuard.migrate(nov) == ProfileGuard.CURRENT_VERSION and nov.cash == 5, "missing version is treated as 1")

	local future: any = { version = ProfileGuard.CURRENT_VERSION + 3, cash = -1 }
	check(ProfileGuard.migrate(future) == ProfileGuard.CURRENT_VERSION + 3 and future.cash == -1, "newer profiles are never downgraded or touched")

	local bad: any = { version = NAN }
	check(ProfileGuard.migrate(bad) == ProfileGuard.CURRENT_VERSION, "NaN version is treated as 1")
	local again: any = { version = ProfileGuard.CURRENT_VERSION, cash = 9 }
	ProfileGuard.migrate(again)
	check(again.cash == 9, "current version is idempotent")
end

-- ===== ProfileGuard.backoff =====
check(ProfileGuard.backoff(1, 2, 12) == 2 and ProfileGuard.backoff(2, 2, 12) == 4 and ProfileGuard.backoff(3, 2, 12) == 8, "backoff doubles")
check(ProfileGuard.backoff(4, 2, 12) == 12 and ProfileGuard.backoff(40, 2, 12) == 12, "backoff is capped")
check(ProfileGuard.backoff(0, 1, 8) == 1, "attempt 0 behaves like 1")

-- ===== Shop amount regression: NaN must never reach the cash math =====
do
	local price, left, cash = 25, 10, 1000
	local function buy(rawAmount: any): number
		local amount = Validate.clampAmount(rawAmount, 1, 50, 1)
		amount = math.min(amount, left, math.floor(cash / price))
		return amount
	end
	check(buy(NAN) == 1, "NaN amount buys 1 (used to make cash NaN)")
	check(buy(INF) == 1 and buy(-5) == 1 and buy("x") == 1 and buy(5) == 5 and buy(1e9) == 10, "amounts are bounded by stock and cash")
end

print(string.format("security_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("security tests failed")
end
