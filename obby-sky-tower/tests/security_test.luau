--!strict
-- Pure-Luau tests for Shared/Security (validators, payload shape, rate limiter, cooldowns,
-- teleport plausibility, profile sanitiser). Run from the project root:
--   luau tests/security_test.luau
local Security = require("../src/shared/Security")
local Layout = require("../src/shared/Layout")

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

-- finite / int -----------------------------------------------------------------------------------
check(Security.finite(1) and Security.finite(-3.5) and Security.finite(0), "finite accepts numbers")
check(not Security.finite(NAN) and not Security.finite(INF) and not Security.finite(-INF), "finite rejects NaN / inf")
check(not Security.finite("1") and not Security.finite(nil) and not Security.finite({}) and not Security.finite(true), "finite rejects non-numbers")
check(Security.int(5, 1, 10) == 5, "int ok")
check(Security.int(1, 1, 10) == 1 and Security.int(10, 1, 10) == 10, "int bounds inclusive")
check(Security.int(0, 1, 10) == nil and Security.int(11, 1, 10) == nil, "int out of range")
check(Security.int(2.5, 1, 10) == nil, "int fraction")
check(Security.int(NAN, 1, 10) == nil and Security.int(INF, 1, math.huge) == nil, "int NaN / inf")
check(Security.int("5", 1, 10) == nil and Security.int(nil, 1, 10) == nil, "int type")
check(Security.int(-1e308, 0, 10) == nil, "int huge negative")

-- str / oneOf -------------------------------------------------------------------------------------
check(Security.str("abc", 5) == "abc", "str ok")
check(Security.str("abcdef", 5) == nil, "str too long")
check(Security.str(string.rep("x", 1e6)) == nil, "str huge default cap")
check(Security.str(5) == nil and Security.str({}) == nil and Security.str(nil) == nil, "str type")
check(Security.oneOf("a", { "a", "b" }) == "a" and Security.oneOf("c", { "a", "b" }) == nil, "oneOf")
check(Security.oneOf(1, { "1" }) == nil, "oneOf type")

-- payload shape -----------------------------------------------------------------------------------
check(Security.payloadOk(nil), "payload nil ok")
check(Security.payloadOk({}), "payload empty ok")
check(Security.payloadOk({ id = "trail_fire" }), "payload string ok")
check(Security.payloadOk({ n = 10, value = true, key = "speedCoil" }), "payload mixed ok")
check(not Security.payloadOk(5) and not Security.payloadOk("x") and not Security.payloadOk(true), "payload scalar rejected")
check(not Security.payloadOk({ n = NAN }), "payload NaN")
check(not Security.payloadOk({ n = INF }) and not Security.payloadOk({ n = -INF }), "payload inf")
check(not Security.payloadOk({ id = string.rep("a", 129) }), "payload long string")
check(Security.payloadOk({ id = string.rep("a", 128) }), "payload string at cap")
check(not Security.payloadOk({ id = { "nested" } }), "payload nested table")
local cyc: any = {}
cyc.self = cyc
check(not Security.payloadOk(cyc), "payload cycle")
check(not Security.payloadOk({ f = function() end }), "payload function")
check(not Security.payloadOk({ [1] = "a" }), "payload numeric key")
local many: any = {}
for i = 1, 20 do
	many["k" .. i] = i
end
check(not Security.payloadOk(many), "payload too many keys")
check(not Security.payloadOk({ [string.rep("k", 100)] = 1 }), "payload long key")

-- token bucket ------------------------------------------------------------------------------------
do
	local b = Security.newBucket(8, 16, 100)
	local ok = 0
	for _ = 1, 40 do
		if Security.take(b, 100) then
			ok += 1
		end
	end
	check(ok == 16, "burst of 16 then refused, got " .. ok)
	check(not Security.take(b, 100.05), "still empty 0.05 s later")
	check(Security.take(b, 100.2), "refills 8/s (1.6 tokens after 0.2 s)")
	check(Security.take(b, 100.2) == false, "only one token was available")
	-- long idle never goes above the burst
	local n = 0
	for _ = 1, 40 do
		if Security.take(b, 10000) then
			n += 1
		end
	end
	check(n == 16, "refill is capped at burst, got " .. n)
	-- a clock going backwards must not mint tokens
	local b2 = Security.newBucket(1, 1, 50)
	check(Security.take(b2, 50), "b2 first")
	check(not Security.take(b2, 10), "b2 backwards time refused")
	-- sustained rate: 10 s of calls at 100/s lets through about rate*10 + burst
	local b3 = Security.newBucket(8, 16, 0)
	local passed = 0
	for i = 0, 1000 do
		if Security.take(b3, i * 0.01) then
			passed += 1
		end
	end
	check(passed >= 80 and passed <= 100, "sustained rate bounded, got " .. passed)
	check(Security.take(Security.newBucket(1, 5, 0), 0, 5) and not Security.take(Security.newBucket(1, 5, 0), 0, 6), "cost parameter")
end

-- cooldowns ---------------------------------------------------------------------------------------
do
	local cd: Security.Cooldowns = {}
	check(Security.cooldownOk(cd, "BuyPet", 10, 0.3), "cooldown first call")
	check(not Security.cooldownOk(cd, "BuyPet", 10.1, 0.3), "cooldown blocks 0.1 s later")
	check(Security.cooldownOk(cd, "BuyTrail", 10.1, 0.3), "cooldown is per key")
	check(Security.cooldownOk(cd, "BuyPet", 10.31, 0.3), "cooldown passes after interval")
	check(not Security.cooldownOk(cd, "BuyPet", 10.4, 0.3), "a refused call does not extend... and a new accepted one restarts")
end

-- movement plausibility ---------------------------------------------------------------------------
check(Security.travelSeconds(90, 45) == 2, "travelSeconds")
check(Security.travelSeconds(NAN, 45) == 0 and Security.travelSeconds(-5, 45) == 0 and Security.travelSeconds(5, 0) == 0, "travelSeconds degenerate")
check(Security.hopPlausible(30, 1.5), "walking 30 studs in 1.5 s is plausible")
check(not Security.hopPlausible(60, 0.8), "60 studs in 0.8 s is a teleport")
check(not Security.hopPlausible(2400, 1), "a whole tower away in 1 s is a teleport")
check(Security.hopPlausible(0, 0), "same spot, no time needed")
do
	local map = (Layout :: any).generate(nil, 1)
	local total, maxHop = 0, 0
	for i = 1, Layout.STAGES do
		local a, b = map.pads[i - 1], map.pads[i]
		local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
		total += d
		maxHop = math.max(maxHop, d)
		-- a walker at the normal 16 studs/s (unassisted) is always plausible hop by hop
		check(Security.hopPlausible(d, d / 16), "walker plausible on hop " .. i)
	end
	check(total > 3000, "tower 1 is a long climb (" .. math.floor(total) .. " studs)")
	local floorMs = Security.rankedFloorMs(total)
	check(floorMs > 60000, "ranked floor is over a minute (" .. floorMs .. " ms)")
	check(Security.rankedPlausible(math.floor(total / 16 * 1000), total), "a 16 studs/s walk is ranked")
	check(not Security.rankedPlausible(math.floor(floorMs * 0.5), total), "half the floor is not ranked")
	check(not Security.rankedPlausible(NAN, total) and not Security.rankedPlausible(-5, total) and not Security.rankedPlausible(0, total), "bad ms is not ranked")
	print(("tower 1: %d studs of pad-to-pad, longest hop %.1f, ranked floor %.0f s"):format(total, maxHop, floorMs / 1000))
end

-- profile sanitiser -------------------------------------------------------------------------------
do
	local p: any = { coins = NAN, totalCoins = INF, freeSkips = -5, wins = 3, stage = 10, nested = { a = NAN, b = { c = -INF } }, ok = 1.5, best = 1e18 }
	local fixed = Security.sanitizeProfile(p)
	check(p.coins == 0 and p.totalCoins == 0, "NaN / inf currency zeroed")
	check(p.freeSkips == 0, "negative currency clamped")
	check(p.wins == 3 and p.stage == 10 and p.ok == 1.5, "legit values untouched")
	check(p.nested.a == 0 and p.nested.b.c == 0, "nested NaN / inf zeroed")
	check(p.best == 1e12, "absurd value capped")
	check(fixed >= 6, "reports repairs, got " .. fixed)
	local cycle: any = { coins = 5 }
	cycle.me = cycle
	check(Security.sanitizeProfile(cycle) == 0 and cycle.coins == 5, "cycle-safe")
	local deep: any = {}
	local cur = deep
	for _ = 1, 50 do
		cur.n = {}
		cur = cur.n
	end
	check(Security.sanitizeProfile(deep) == 0, "depth-limited")
	check(Security.sanitizeProfile(nil) == 0 and Security.sanitizeProfile(5) == 0, "non-table input")
	local clean: any = { coins = 1234.5, wins = 0, boosts = { speed = 1700000000 }, pocket = { x = 1, y = 2, z = 3 } }
	check(Security.sanitizeProfile(clean) == 0 and clean.coins == 1234.5, "a clean profile is not changed")
end

print(("security_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("security tests failed")
end
