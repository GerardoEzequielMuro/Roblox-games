-- Pure tests for the anti-exploit helpers (run from the repo root of this game):
--   export PATH=/tmp/tools:$PATH; luau tests/security_test.luau
local Guard = require("../src/server/Services/Guard")

local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local NAN = 0 / 0
local INF = math.huge

-- num / int ---------------------------------------------------------------
check("num accepts 1", Guard.num(1))
check("num accepts 0 and negatives", Guard.num(0) and Guard.num(-5.5))
check("num rejects NaN", not Guard.num(NAN))
check("num rejects inf", not Guard.num(INF) and not Guard.num(-INF))
check("num rejects string/table/bool/nil", not Guard.num("1") and not Guard.num({}) and not Guard.num(true) and not Guard.num(nil))
check("int accepts range ends", Guard.int(1, 1, 5) and Guard.int(5, 1, 5))
check("int rejects out of range", not Guard.int(0, 1, 5) and not Guard.int(6, 1, 5) and not Guard.int(-1, 0, 5))
check("int rejects fractions", not Guard.int(1.5, 1, 5) and not Guard.int(2.0000001, 1, 5))
check("int rejects NaN/inf", not Guard.int(NAN, 0, 5) and not Guard.int(INF, 0, 1e300) and not Guard.int(-INF, -1e300, 0))
check("int rejects numeric string", not Guard.int("3", 1, 5))

-- str / uid / oneOf ------------------------------------------------------
check("str ok", Guard.str("abc", 5))
check("str rejects empty by default", not Guard.str("", 5))
check("str allows empty when asked", Guard.str("", 5, true))
check("str rejects too long", not Guard.str(string.rep("a", 6), 5))
check("str rejects 1 MB", not Guard.str(string.rep("x", 1000000), 30))
check("str rejects non-strings", not Guard.str(5, 5) and not Guard.str({}, 5) and not Guard.str(nil, 5))
check("uid accepts p1 / p12345", Guard.uid("p1") and Guard.uid("p12345"))
check("uid rejects junk", not Guard.uid("") and not Guard.uid("p") and not Guard.uid("x1") and not Guard.uid("p1 ") and not Guard.uid("p1\n") and not Guard.uid("p-1"))
check("uid rejects long", not Guard.uid("p" .. string.rep("1", 20)))
check("uid rejects non-string", not Guard.uid(1) and not Guard.uid({}) and not Guard.uid(nil))
local set = { a = true, [2] = true }
check("oneOf member", Guard.oneOf("a", set) and Guard.oneOf(2, set))
check("oneOf non-member", not Guard.oneOf("b", set) and not Guard.oneOf(3, set) and not Guard.oneOf(NAN, set) and not Guard.oneOf({}, set) and not Guard.oneOf(nil, set))

-- tables ------------------------------------------------------------------
check("smallTable ok", Guard.smallTable({ 1, 2, 3 }, 3))
check("smallTable too big", not Guard.smallTable({ 1, 2, 3, 4 }, 3))
local big = {}
for i = 1, 100000 do
	big[i] = i
end
check("smallTable rejects huge", not Guard.smallTable(big, 256))
check("smallTable rejects non-table", not Guard.smallTable("x", 3) and not Guard.smallTable(nil, 3))
check("array ok", Guard.array({ "a", "b" }, 5) and Guard.array({}, 5))
check("array rejects holes", not Guard.array({ [1] = "a", [3] = "c" }, 5))
check("array rejects string keys", not Guard.array({ a = 1 }, 5) and not Guard.array({ "x", y = 2 }, 5))
check("array rejects too long", not Guard.array({ 1, 2, 3 }, 2) and not Guard.array(big, 400))
check("array rejects non-table", not Guard.array("abc", 5))
local cyc: any = {}
cyc[1] = cyc
check("array with cycle is just a 1-entry table", Guard.array(cyc, 5))

-- limiter -----------------------------------------------------------------
do
	local l = Guard.limiter(2, 4) -- 2/s, burst 4
	check("burst of 4 allowed", Guard.take(l, "a", 0, 4) == 4)
	check("5th denied at t=0", not Guard.allow(l, "a", 0))
	check("refills 2/s", Guard.take(l, "a", 1, 10) == 2)
	check("per-key isolation", Guard.allow(l, "b", 1))
	check("never above burst", Guard.take(l, "a", 100, 100) == 4)
	check("negative/NaN/zero want gives nothing", Guard.take(l, "c", 0, -3) == 0 and Guard.take(l, "c", 0, NAN) == 0 and Guard.take(l, "c", 0, 0) == 0 and Guard.take(l, "c", 0, 0.5) == 0)
	check("inf want is refused outright", Guard.take(l, "d", 0, INF) == 0 and Guard.take(l, "d", 0, 4) == 4)
	check("clock going backwards does not mint tokens", Guard.take(l, "e", 10, 4) == 4 and Guard.take(l, "e", 5, 1) == 0)
	check("count tracks keys", Guard.count(l) == 5, Guard.count(l))
	Guard.forget(l, "a")
	Guard.forget(l, "b")
	Guard.forget(l, "c")
	Guard.forget(l, "d")
	Guard.forget(l, "e")
	check("forget frees every key", Guard.count(l) == 0)
end
do
	-- the tap bucket math: 12/s + 6 burst, an exploiter sending 1000/s gets ~12/s
	local l = Guard.limiter(12, 18)
	local accepted = 0
	for step = 0, 99 do -- 10 s, 10 batches per second of 100 taps each
		accepted += Guard.take(l, "p", step * 0.1, 100)
	end
	check("exploit tap flood capped near 12/s", accepted <= 12 * 10 + 18 and accepted >= 12 * 10, accepted)
	local legit = Guard.limiter(12, 18)
	local got = 0
	for step = 0, 39 do -- 10 s at 8 taps/s in 0.25 s batches (2 each)
		got += Guard.take(legit, "p", step * 0.25, 2)
	end
	check("legit 8 taps/s fully accepted", got == 80, got)
end
do
	-- request-per-action limiter: 0.5/s, burst 3 (codes): the 4th attempt in a burst is refused
	local l = Guard.limiter(0.5, 3)
	local ok = 0
	for _ = 1, 10 do
		if Guard.allow(l, "p", 0) then
			ok += 1
		end
	end
	check("code brute force limited to the burst", ok == 3, ok)
	check("one more after 2 s", Guard.allow(l, "p", 2))
end

-- scrub / clamp / types -----------------------------------------------------
do
	local t: any = { a = 1, b = NAN, c = { d = INF, e = { f = -INF, g = 5 } }, s = "x" }
	t.self = t -- cycle
	local fixed = Guard.scrub(t)
	check("scrub fixes 3 values", fixed == 3, fixed)
	check("scrub zeroes them", t.b == 0 and t.c.d == 0 and t.c.e.f == 0)
	check("scrub keeps the rest", t.a == 1 and t.c.e.g == 5 and t.s == "x")
	check("scrub terminates on cycles", true)
	check("scrub ignores non-table", Guard.scrub(5) == 0 and Guard.scrub(nil) == 0)
	local deep: any = {}
	local cur = deep
	for _ = 1, 50 do
		cur.n = {}
		cur = cur.n
	end
	check("scrub depth-capped", Guard.scrub(deep) == 0)
	local clean = { x = 1, y = { z = 2 } }
	check("scrub leaves clean data alone", Guard.scrub(clean) == 0 and clean.x == 1 and clean.y.z == 2)
end
do
	local p = { taps = -5, gems = 10, dice = -0.1, s = "x" }
	check("clampNonNegative fixes negatives", Guard.clampNonNegative(p, { "taps", "gems", "dice", "s", "missing" }) == 2)
	check("clampNonNegative result", p.taps == 0 and p.gems == 10 and p.dice == 0)
end
do
	local def = { a = 1, b = { x = 1 }, c = "s", d = true }
	local p: any = { a = "oops", b = "no", c = "ok", d = { 1 }, e = 9 }
	local fixed = Guard.fixTypes(p, def, Guard.deepCopy)
	check("fixTypes counts", fixed == 3, fixed)
	check("fixTypes restores defaults", p.a == 1 and type(p.b) == "table" and p.b.x == 1 and p.d == true)
	check("fixTypes keeps good + unknown", p.c == "ok" and p.e == 9)
	check("fixTypes copies, not aliases", p.b ~= def.b)
	check("deepCopy copies nested", (function()
		local o = { a = { b = { c = 1 } } }
		local c = Guard.deepCopy(o)
		c.a.b.c = 2
		return o.a.b.c == 1
	end)())
end

-- migrate -------------------------------------------------------------------
do
	local log = {}
	local steps = {
		[1] = function(p: any)
			p.addedInV2 = true
			table.insert(log, 1)
		end,
		[2] = function(p: any)
			p.addedInV3 = true
			table.insert(log, 2)
		end,
	}
	local p: any = { version = 1 }
	check("migrate 1 -> 3", Guard.migrate(p, steps, 3) == 3 and p.version == 3 and p.addedInV2 and p.addedInV3 and #log == 2)
	local q: any = { version = 3 }
	check("migrate current is a no-op", Guard.migrate(q, steps, 3) == 3 and q.addedInV2 == nil)
	local newer: any = { version = 9 }
	check("migrate leaves newer data alone", Guard.migrate(newer, steps, 3) == 9 and newer.version == 9 and newer.addedInV2 == nil)
	local bad: any = { version = "x" }
	check("migrate treats a bad version as 1", Guard.migrate(bad, {}, 1) == 1 and bad.version == 1)
	local missing: any = {}
	check("migrate treats missing version as 1", Guard.migrate(missing, {}, 1) == 1 and missing.version == 1)
	local nan: any = { version = NAN }
	check("migrate NaN version", Guard.migrate(nan, {}, 2) == 2)
end

-- backoff -------------------------------------------------------------------
check("backoff grows", Guard.backoff(1, 1, 8) == 1 and Guard.backoff(2, 1, 8) == 2 and Guard.backoff(3, 1, 8) == 4)
check("backoff capped", Guard.backoff(10, 1, 8) == 8)

print(string.format("security_test: %d/%d passed", total - fails, total))
if fails > 0 then
	error("security_test failed")
end
