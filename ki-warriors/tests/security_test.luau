-- Round 7: validators, rate limiters, movement budget and save sanitizing (pure).
-- Run with: luau tests/security_test.luau
local Validate = require("../src/server/Services/Validate")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

local NAN = 0 / 0
local INF = math.huge

-- scalars -------------------------------------------------------------------------------
check("finite ok", Validate.finite(1) and Validate.finite(-5.5) and Validate.finite(0))
check("finite rejects NaN/inf/types", not Validate.finite(NAN) and not Validate.finite(INF) and not Validate.finite(-INF) and not Validate.finite("1") and not Validate.finite(nil) and not Validate.finite({}) and not Validate.finite(true))
check("number range", Validate.number(5, 1, 10) == 5 and Validate.number(0, 1, 10) == nil and Validate.number(11, 1, 10) == nil and Validate.number(NAN, 1, 10) == nil and Validate.number(INF, 1, 1e300) == nil)
check("int ok", Validate.int(3, 1, 8) == 3 and Validate.int(1, 1, 8) == 1 and Validate.int(8, 1, 8) == 8)
check("int rejects floats", Validate.int(2.5, 1, 8) == nil and Validate.int(1e-9, 0, 8) == nil)
check("int rejects out of range", Validate.int(0, 1, 8) == nil and Validate.int(9, 1, 8) == nil and Validate.int(-1, 0, 8) == nil)
check("int rejects NaN/inf/huge", Validate.int(NAN, 0, 8) == nil and Validate.int(INF, 0, 8) == nil and Validate.int(-INF, 0, 8) == nil and Validate.int(2 ^ 60, 0, 8) == nil)
check("int rejects non-numbers", Validate.int("3", 1, 8) == nil and Validate.int(nil, 1, 8) == nil and Validate.int({}, 1, 8) == nil)
check("str cap", Validate.str("abc", 5) == "abc" and Validate.str("abcdef", 5) == nil and Validate.str(string.rep("x", 100000), 30) == nil and Validate.str(5, 5) == nil)
local set = { free = true, premium = true }
check("enum whitelist", Validate.enum("free", set) == "free" and Validate.enum("gold", set) == nil and Validate.enum(1, set) == nil and Validate.enum(string.rep("a", 500), set) == nil and Validate.enum("__index", set) == nil)
check("finiteVec", Validate.finiteVec(1, 2, 3) and not Validate.finiteVec(1, NAN, 3) and not Validate.finiteVec(INF, 0, 0) and not Validate.finiteVec(1, 2, "3"))

-- payload -------------------------------------------------------------------------------
check("payload flat ok", Validate.payload({ id = "vigor_seed", tier = 3, paid = true }))
check("payload empty ok", Validate.payload({}))
check("payload rejects non-table", not Validate.payload("x") and not Validate.payload(5) and not Validate.payload(nil) and not Validate.payload(true))
check("payload rejects nested", not Validate.payload({ a = { b = 1 } }))
check("payload rejects NaN/inf", not Validate.payload({ n = NAN }) and not Validate.payload({ n = INF }) and not Validate.payload({ n = -INF }))
check("payload rejects long string", not Validate.payload({ s = string.rep("a", 65) }) and Validate.payload({ s = string.rep("a", 64) }))
check("payload rejects array/number keys", not Validate.payload({ 1, 2, 3 }) and not Validate.payload({ [5] = "x" }))
check("payload rejects long key", not Validate.payload({ [string.rep("k", 33)] = 1 }))
check("payload rejects functions", not Validate.payload({ f = function() end }))
local big = {}
for i = 1, 13 do
	big["k" .. i] = i
end
check("payload rejects too many keys", not Validate.payload(big))
check("payload rejects metatables", not Validate.payload(setmetatable({}, { __index = function() return 1 end })))
local cyc: any = {}
cyc.self = cyc
check("payload rejects cycles", not Validate.payload(cyc))

-- token bucket --------------------------------------------------------------------------
do
	local b = Validate.newBucket(10, 5, 100)
	local ok = 0
	for _ = 1, 20 do
		if Validate.take(b, 100) then
			ok += 1
		end
	end
	check("bucket burst is the cap", ok == 5, ok)
	check("bucket empty rejects", not Validate.take(b, 100))
	check("bucket refills at rate", Validate.take(b, 100.15) and not Validate.take(b, 100.15))
	-- sustained: 1000 calls over 10 s at 10/s -> about burst + 100
	local b2 = Validate.newBucket(10, 5, 0)
	local allowed = 0
	for i = 0, 999 do
		if Validate.take(b2, i * 0.01) then
			allowed += 1
		end
	end
	check("bucket sustained rate", allowed >= 100 and allowed <= 106, allowed)
	-- a backwards clock never refunds tokens
	local b3 = Validate.newBucket(10, 2, 50)
	Validate.take(b3, 50)
	Validate.take(b3, 50)
	check("bucket backwards clock", not Validate.take(b3, 10))
	-- never exceeds burst after a long idle
	local b4 = Validate.newBucket(10, 3, 0)
	Validate.take(b4, 0)
	local n4 = 0
	for _ = 1, 10 do
		if Validate.take(b4, 1e6) then
			n4 += 1
		end
	end
	check("bucket idle capped at burst", n4 == 3, n4)
	check("bucket cost", Validate.take(Validate.newBucket(1, 5, 0), 0, 5) and not Validate.take(Validate.newBucket(1, 5, 0), 0, 6))
end

-- cooldown ------------------------------------------------------------------------------
do
	local last = {}
	check("cooldown first use", Validate.cooldown(last, "Travel", 10, 1.5))
	check("cooldown blocks", not Validate.cooldown(last, "Travel", 11, 1.5))
	check("cooldown rejection does not extend", Validate.cooldown(last, "Travel", 11.6, 1.5))
	check("cooldown independent keys", Validate.cooldown(last, "Wish", 11.6, 2))
end

-- movement budget -----------------------------------------------------------------------
do
	local maxSpeed, slack = 122, 1.4
	local capacity = maxSpeed * 1.5 + 26 * 2 + 90
	-- legit: boosted flight for 60 s sampled every 0.5 s, plus a dash each 1.1 s
	local m = Validate.newMoveBudget(capacity)
	local bad = 0
	for i = 1, 120 do
		local dist = maxSpeed * 0.5 + (if i % 2 == 0 then 26 else 0)
		if not Validate.moveStep(m, dist, 0.5, maxSpeed, slack, capacity) then
			bad += 1
		end
	end
	check("legit boosted flight + dashes never trips", bad == 0, bad)
	-- latency jitter: 3 steps worth in one, then nothing
	local mj = Validate.newMoveBudget(capacity)
	check("latency spike tolerated", Validate.moveStep(mj, maxSpeed * 1.2, 0.5, maxSpeed, slack, capacity) and Validate.moveStep(mj, 0, 0.5, maxSpeed, slack, capacity))
	-- speed hack: 2x flight speed sustained
	local mh = Validate.newMoveBudget(capacity)
	local tripped = 0
	for _ = 1, 20 do
		if not Validate.moveStep(mh, maxSpeed * 2 * 0.5, 0.5, maxSpeed, slack, capacity) then
			tripped += 1
		end
	end
	check("2x speed sustained trips quickly", tripped >= 1)
	local mh2 = Validate.newMoveBudget(capacity)
	local firstTrip = 0
	for i = 1, 40 do
		if not Validate.moveStep(mh2, maxSpeed * 2 * 0.5, 0.5, maxSpeed, slack, capacity) then
			firstTrip = i
			break
		end
	end
	check("2x speed trips within 6 s", firstTrip > 0 and firstTrip <= 12, firstTrip)
	-- 1.2x for a long time stays inside the slack
	local mo = Validate.newMoveBudget(capacity)
	local trips12 = 0
	for _ = 1, 200 do
		if not Validate.moveStep(mo, maxSpeed * 1.2 * 0.5, 0.5, maxSpeed, slack, capacity) then
			trips12 += 1
		end
	end
	check("1.2x within slack", trips12 == 0, trips12)
	-- teleport-sized single step
	local mt = Validate.newMoveBudget(capacity)
	check("teleport trips", not Validate.moveStep(mt, 5000, 0.5, maxSpeed, slack, capacity))
	check("budget refilled after a trip", Validate.moveStep(mt, 10, 0.5, maxSpeed, slack, capacity))
	check("NaN distance trips", not Validate.moveStep(Validate.newMoveBudget(capacity), NAN, 0.5, maxSpeed, slack, capacity))
	check("negative dt cannot refill", not Validate.moveStep(Validate.newMoveBudget(10), 100, -50, maxSpeed, slack, 10))
end

-- save sanitizing -----------------------------------------------------------------------
do
	local p: any = { sparks = NAN, gems = 5, stats = { strength = INF, ki = -INF, speed = 12 }, list = { 1, NAN, 3 }, name = "x" }
	check("clean detects", not Validate.clean(p))
	local fixed = Validate.sanitize(p)
	check("sanitize count", fixed == 4, fixed)
	check("sanitize values", p.sparks == 0 and p.stats.strength == 0 and p.stats.ki == 0 and p.list[2] == 0 and p.gems == 5 and p.stats.speed == 12 and p.name == "x")
	check("clean after", Validate.clean(p))
	check("sanitize idempotent", Validate.sanitize(p) == 0)
	-- deep / cyclic tables terminate
	local c: any = { a = 1 }
	c.me = c
	check("sanitize survives cycles", Validate.sanitize(c) == 0)
	check("clean survives cycles", Validate.clean(c))
end

if fails == 0 then
	print("SECURITY CHECKS PASSED")
else
	print(fails .. " FAILED")
	error("security checks failed")
end
