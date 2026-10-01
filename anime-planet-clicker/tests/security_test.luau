-- Pure tests for the anti-exploit helpers (run from the repo root): luau tests/security_test.luau
local S = require("../src/shared/Security")

local total, fails = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local NAN, INF = 0 / 0, math.huge

-- validators
check("finite 1", S.isFinite(1))
check("finite nan", not S.isFinite(NAN))
check("finite inf", not S.isFinite(INF))
check("finite -inf", not S.isFinite(-INF))
check("finite string", not S.isFinite("1"))
check("finite nil", not S.isFinite(nil))
check("int 5", S.isInt(5, 1, 10))
check("int 5.5", not S.isInt(5.5))
check("int range lo", not S.isInt(0, 1, 10))
check("int range hi", not S.isInt(11, 1, 10))
check("int nan", not S.isInt(NAN))
check("int inf", not S.isInt(INF, 1, 10))
check("int huge default", not S.isInt(1e300))
check("string ok", S.isString("abc", 5))
check("string too long", not S.isString(string.rep("a", 6), 5))
check("string wrong type", not S.isString(5))
check("oneOf yes", S.oneOf("a", { "a", "b" }))
check("oneOf no", not S.oneOf("c", { "a", "b" }))
check("clamp nan", S.clampNumber(NAN, 0, 10, 3) == 3)
check("clamp inf", S.clampNumber(INF, 0, 10, 3) == 3)
check("clamp hi", S.clampNumber(50, 0, 10, 3) == 10)
check("clamp lo", S.clampNumber(-5, 0, 10, 3) == 0)

-- token bucket
do
	local b = S.newBucket(10, 20, 0)
	local granted = 0
	for _ = 1, 100 do
		if S.take(b, 0) then
			granted += 1
		end
	end
	check("bucket burst", granted == 20, granted)
	check("bucket refill 0.5s", S.take(b, 0.5) and S.take(b, 0.5) and S.take(b, 0.5) and S.take(b, 0.5) and S.take(b, 0.5) and not S.take(b, 0.5))
	-- one minute at the sustained rate: no more than rate * 60 + burst accepted
	local b2 = S.newBucket(10, 20, 0)
	local total2 = 0
	for i = 0, 6000 do
		local t = i * 0.01
		total2 += S.takeUpTo(b2, t, 1000)
	end
	check("bucket sustained cap", total2 <= 10 * 60 + 20 and total2 >= 10 * 60, total2)
	local b3 = S.newBucket(10, 20, 100)
	S.take(b3, 100, 20)
	check("bucket backwards clock", not S.take(b3, 50))
	check("bucket backwards clock keeps t", b3.t == 100)
	check("takeUpTo partial", S.takeUpTo(S.newBucket(1, 3.7, 0), 0, 10) == 3)
	check("takeUpTo none", S.takeUpTo(S.newBucket(1, 3, 0), 0, 0) == 0)
	local b4 = S.newBucket(1, 5, 0)
end

-- guard (cooldown + exclusive)
do
	local g = S.newGuard()
	check("guard first", S.enter(g, "a", 0, 1, false))
	check("guard too soon", not S.enter(g, "a", 0.5, 1, false))
	check("guard later", S.enter(g, "a", 1.2, 1, false))
	check("guard other action", S.enter(g, "b", 1.2, 1, false))
	check("guard exclusive first", S.enter(g, "x", 0, nil, true))
	check("guard exclusive busy", not S.enter(g, "x", 10, nil, true))
	S.leave(g, "x")
	check("guard exclusive freed", S.enter(g, "x", 20, nil, true))
	check("guard no interval", S.enter(g, "free", 0) and S.enter(g, "free", 0))
end

-- payload shape
do
	check("payload ok", S.payloadOk({ uid = "p1", n = 3, list = { "a", "b" } }))
	check("payload nan", not S.payloadOk({ n = NAN }))
	check("payload inf", not S.payloadOk({ n = { INF } }))
	check("payload long string", not S.payloadOk({ code = string.rep("x", 500) }))
	local big = {}
	for i = 1, 5000 do
		big[i] = "x"
	end
	check("payload too many nodes", not S.payloadOk({ uids = big }))
	local cyc: any = {}
	cyc.self = cyc
	check("payload cycle", not S.payloadOk(cyc))
	check("payload metatable", not S.payloadOk(setmetatable({}, { __index = function() end })))
	check("payload function", not S.payloadOk({ f = function() end }))
	check("payload deep", not S.payloadOk({ a = { b = { c = { d = { e = { f = 1 } } } } } }))
	local shared = { 1 }
	check("payload shared subtable ok", S.payloadOk({ a = shared, b = shared }))
	check("payload empty", S.payloadOk({}))
end

-- sanitize
do
	local src: any = { a = NAN, b = INF, c = -INF, d = 5, e = { f = NAN, g = "s", h = true }, fn = function() end, list = { 1, NAN, 3 } }
	local out, fixed = S.sanitize(src)
	check("sanitize nan", out.a == 0)
	check("sanitize inf", out.b == 1e300 and out.c == -1e300)
	check("sanitize keeps", out.d == 5 and out.e.g == "s" and out.e.h == true)
	check("sanitize nested nan", out.e.f == 0)
	check("sanitize function dropped", out.fn == nil)
	check("sanitize list", out.list[1] == 1 and out.list[2] == 0 and out.list[3] == 3)
	check("sanitize count", fixed == 6, fixed)
	check("sanitize is a copy", out ~= src and out.e ~= src.e)
	check("sanitize source untouched", src.a ~= src.a)
	local cyc: any = { x = 1 }
	cyc.me = cyc
	local out2 = S.sanitize(cyc)
	check("sanitize cycle", out2.x == 1 and out2.me == nil)
	local clean: any = { s = 1e308, n = -3.5, t = { 1, 2 } }
	local out3, f3 = S.sanitize(clean)
	check("sanitize clean data unchanged", f3 == 0 and out3.s == 1e308 and out3.n == -3.5 and #out3.t == 2)
	check("sanitize finite check", (function()
		local o = S.sanitize({ a = NAN, b = { INF } })
		return S.payloadOk(o)
	end)())
end

-- migrate
do
	local calls = {}
	local migrations: { [number]: (any) -> () } = {
		[1] = function(p)
			table.insert(calls, "1>2")
			p.newField = true
		end,
		[2] = function(_p)
			table.insert(calls, "2>3")
		end,
	}
	local p: any = { version = 1 }
	check("migrate 1->3", S.migrate(p, 3, migrations) == "ok" and p.version == 3 and p.newField == true and #calls == 2)
	local q: any = { version = 3 }
	calls = {}
	check("migrate current is a no-op", S.migrate(q, 3, migrations) == "ok" and #calls == 0)
	local n: any = { version = 9 }
	check("migrate newer refused", S.migrate(n, 3, migrations) == "newer" and n.version == 9)
	local bad: any = { version = NAN }
	check("migrate nan version", S.migrate(bad, 1, {}) == "ok" and bad.version == 1)
	local none: any = {}
	check("migrate missing version", S.migrate(none, 2, {}) == "ok" and none.version == 2)
end

-- backoff
check("backoff 1", S.backoff(1) == 1)
check("backoff 3", S.backoff(3) == 4)
check("backoff cap", S.backoff(20) == 16)
check("backoff base", S.backoff(2, 1.5, 8) == 3)
check("backoff attempt 0", S.backoff(0) == 1)

print(string.format("security_test: %d checks, %d failed", total, fails))
if fails > 0 then
	error("security tests failed")
end
