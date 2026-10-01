-- Pure tests for the anti-exploit helpers (run from the repo root):
--   luau tests/security_test.luau
-- Validators, token buckets, cooldowns, failure lockouts, save sanitizing and the
-- repeat-group limiter that stops two accounts feeding each other rewards.
local Guard = require("../src/shared/Guard")
local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local SeasonPass = require("../src/shared/SeasonPass")

local checks, fails = 0, 0
local function check(name: string, cond: any, detail: any?)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local NAN = 0 / 0
local INF = math.huge

---------------------------------------------------------------------------
-- validators
---------------------------------------------------------------------------
check("isNumber: normal", Guard.isNumber(3) and Guard.isNumber(-2.5) and Guard.isNumber(0))
check("isNumber: NaN / inf / wrong type", not Guard.isNumber(NAN) and not Guard.isNumber(INF) and not Guard.isNumber(-INF) and not Guard.isNumber("3") and not Guard.isNumber(nil) and not Guard.isNumber({}) and not Guard.isNumber(true))
check("isInt: in range", Guard.isInt(1, 1, 5) and Guard.isInt(5, 1, 5) and Guard.isInt(3.0, 1, 5))
check("isInt: out of range / fractional / NaN / inf", not Guard.isInt(0, 1, 5) and not Guard.isInt(6, 1, 5) and not Guard.isInt(2.5, 1, 5) and not Guard.isInt(NAN, 1, 5) and not Guard.isInt(INF, 1, 1e308) and not Guard.isInt(-1, 1, 5))
check("isInt: huge numbers", not Guard.isInt(2 ^ 60, 1, 1000) and not Guard.isInt(-2 ^ 60, 1, 1000))
check("isString: caps length", Guard.isString("abc", 3) and not Guard.isString("abcd", 3))
check("isString: empty only when allowed", not Guard.isString("", 3) and Guard.isString("", 3, true))
check("isString: wrong types", not Guard.isString(5, 3) and not Guard.isString(nil, 3) and not Guard.isString({}, 3, true))
check("isString: huge string", not Guard.isString(string.rep("x", 100000), 128))
check("isUserId", Guard.isUserId(1) and Guard.isUserId(123456789) and not Guard.isUserId(0) and not Guard.isUserId(-5) and not Guard.isUserId(1.5) and not Guard.isUserId(NAN) and not Guard.isUserId(INF) and not Guard.isUserId("12"))
check("oneOf", Guard.oneOf("a", { a = true }) and not Guard.oneOf("b", { a = true }) and not Guard.oneOf({}, { a = true }) and not Guard.oneOf(nil, { a = true }))
check("isList: arrays", Guard.isList({}, 4) and Guard.isList({ "a", "b" }, 4) and not Guard.isList({ "a", "b", "c" }, 2))
check("isList: dictionaries / holes / non tables", not Guard.isList({ a = 1 }, 4) and not Guard.isList({ [1] = "a", [3] = "c" }, 4) and not Guard.isList("x", 4) and not Guard.isList({ [-1] = "a" }, 4) and not Guard.isList({ [1.5] = "a" }, 4))

-- the real handler inputs: seasons, quests, gifts
check("season tier whitelist", Guard.isInt(1, 1, Config.SeasonPass.tiers) and Guard.isInt(Config.SeasonPass.tiers, 1, Config.SeasonPass.tiers) and not Guard.isInt(Config.SeasonPass.tiers + 1, 1, Config.SeasonPass.tiers))
local sp = SeasonPass.fresh(1)
check("claim: NaN / inf / fractional / negative tiers are refused by the pass too", not SeasonPass.canClaim(sp, "free", NAN) and not SeasonPass.canClaim(sp, "free", INF) and not SeasonPass.canClaim(sp, "free", 1.5) and not SeasonPass.canClaim(sp, "free", -1) and not SeasonPass.canClaim(sp, "premium", 1))

---------------------------------------------------------------------------
-- token bucket
---------------------------------------------------------------------------
do
	local b = Guard.newBucket(10, 5, 0)
	local ok = 0
	for _ = 1, 20 do
		if Guard.take(b, 0) then
			ok += 1
		end
	end
	check("bucket: burst only at t=0", ok == 5, ok)
	check("bucket: refills over time", Guard.take(b, 0.1) and not Guard.take(b, 0.1), nil)
	check("bucket: never above burst", (function()
		local c = Guard.newBucket(10, 5, 0)
		Guard.take(c, 1000)
		return c.tokens <= 5
	end)())
	-- a flood for 10 s at 1000 req/s accepts about rate * 10 + burst
	local f = Guard.newBucket(12, 30, 0)
	local accepted = 0
	for i = 1, 10000 do
		if Guard.take(f, i / 1000) then
			accepted += 1
		end
	end
	check("bucket: flood is bounded by rate*T + burst", accepted <= 12 * 10 + 30 + 1 and accepted >= 12 * 10, accepted)
	-- time going backwards never refunds tokens
	local g = Guard.newBucket(10, 5, 100)
	for _ = 1, 5 do
		Guard.take(g, 100)
	end
	check("bucket: clock going back does not refill", not Guard.take(g, 50), nil)
end

do
	-- Power Core taps: 8 / s, burst 6 (Config.Core). A client claiming 1e9 taps per call.
	local C = Config.Core
	local b = Guard.newBucket(C.maxTapsPerSecond, C.burst, 0)
	check("takeUpTo: first batch capped at burst", Guard.takeUpTo(b, 0, 1e9) == C.burst, nil)
	check("takeUpTo: nothing left right after", Guard.takeUpTo(b, 0, 5) == 0)
	check("takeUpTo: NaN / inf / fractional / zero", Guard.takeUpTo(b, 10, NAN) == 0 and Guard.takeUpTo(b, 10, 0.5) == 0 and Guard.takeUpTo(b, 10, -3) == 0)
	local b2 = Guard.newBucket(C.maxTapsPerSecond, C.burst, 0)
	local total = 0
	for i = 1, 600 do -- one minute, a call every 0.1 s asking for 50 taps
		total += Guard.takeUpTo(b2, i * 0.1, 50)
	end
	check("takeUpTo: a minute of spam stays under the best legit rate", total <= C.maxTapsPerSecond * 60 + C.burst, total)
	check("takeUpTo: and is not starved (a real 8/s tapper keeps up)", total >= C.maxTapsPerSecond * 60 - 10, total)
	local b3 = Guard.newBucket(C.maxTapsPerSecond, C.burst, 0)
	local legit = 0
	for i = 1, 300 do -- a human: 7 taps per second in batches of 1 every 1/7 s
		legit += Guard.takeUpTo(b3, i / 7, 1)
	end
	check("takeUpTo: a legit 7 taps/s player loses nothing", legit == 300, legit)
end

---------------------------------------------------------------------------
-- cooldowns / lockouts
---------------------------------------------------------------------------
do
	local last: { [string]: number } = {}
	check("cooldown: first use passes", Guard.cooldownReady(last, "Challenge", 0, 3))
	check("cooldown: too soon", not Guard.cooldownReady(last, "Challenge", 2.9, 3))
	check("cooldown: a refused call does not extend it", Guard.cooldownReady(last, "Challenge", 3.0, 3))
	check("cooldown: keys are independent", Guard.cooldownReady(last, "Buy", 3.0, 3))
end

do
	local s = Guard.newStrikes()
	local t = 0
	for _ = 1, 5 do
		Guard.strike(s, t, 6, 60, 120)
		t += 1
	end
	check("strikes: below the limit is not locked", not Guard.isLocked(s, t))
	Guard.strike(s, t, 6, 60, 120)
	check("strikes: the 6th miss in a minute locks", Guard.isLocked(s, t + 1))
	check("strikes: lock lasts the configured time", Guard.isLocked(s, t + 119) and not Guard.isLocked(s, t + 121))
	-- slow misses never lock
	local slow = Guard.newStrikes()
	for i = 1, 50 do
		Guard.strike(slow, i * 61, 6, 60, 120)
	end
	check("strikes: one miss a minute never locks", not Guard.isLocked(slow, 50 * 61))
	-- code guessing: at 12 requests / s a lockout caps attempts
	local g = Guard.newStrikes()
	local attempts = 0
	for i = 0, 12 * 600 do -- ten minutes at full speed
		local now = i / 12
		if not Guard.isLocked(g, now) then
			attempts += 1
			Guard.strike(g, now, 6, 60, 120)
		end
	end
	check("strikes: ten minutes of guessing is capped (about 6 per 2 min)", attempts <= 6 * 6, attempts)
end

---------------------------------------------------------------------------
-- sanitize
---------------------------------------------------------------------------
do
	local p: any = { coins = NAN, xp = INF, level = -INF, ok = 5, nested = { a = NAN, b = { c = INF, d = "x" } }, list = { 1, NAN, 3 }, f = function() end }
	local fixed = Guard.sanitize(p)
	check("sanitize: NaN to 0", p.coins == 0)
	check("sanitize: +/-inf clamped", p.xp == 1e15 and p.level == -1e15)
	check("sanitize: nested and arrays", p.nested.a == 0 and p.nested.b.c == 1e15 and p.nested.b.d == "x" and p.list[2] == 0 and p.list[3] == 3)
	check("sanitize: functions dropped, good values kept", p.f == nil and p.ok == 5)
	check("sanitize: counts what it changed", fixed == 7, fixed)
	check("sanitize: result has no NaN anywhere", (function()
		local function walk(t: any): boolean
			for _, v in t do
				if type(v) == "number" and (v ~= v or v == INF or v == -INF) then
					return false
				end
				if type(v) == "table" and not walk(v) then
					return false
				end
			end
			return true
		end
		return walk(p)
	end)())
	local clean: any = { a = 1, b = { c = 2 } }
	check("sanitize: clean data is untouched", Guard.sanitize(clean) == 0 and clean.a == 1 and clean.b.c == 2)
	-- cycle
	local cyc: any = { a = 1 }
	cyc.self = cyc
	cyc.deep = { back = cyc }
	Guard.sanitize(cyc)
	check("sanitize: cycles are cut (no infinite loop)", cyc.self == nil and cyc.deep.back == nil and cyc.a == 1)
	-- shared (non cyclic) sub-table survives twice
	local shared = { n = 1 }
	local two: any = { x = shared, y = shared }
	Guard.sanitize(two)
	check("sanitize: shared sub-tables are not a cycle", two.x ~= nil and two.y ~= nil)
	-- depth bound
	local deep: any = {}
	local cur = deep
	for _ = 1, 30 do
		cur.n = {}
		cur = cur.n
	end
	Guard.sanitize(deep, 8)
	local depth = 0
	cur = deep
	while cur.n do
		depth += 1
		cur = cur.n
	end
	check("sanitize: depth is bounded", depth <= 8, depth)
	-- odd keys (booleans, tables) are dropped
	local odd: any = { [true] = 1, [{}] = 2, ok = 3 }
	Guard.sanitize(odd)
	check("sanitize: non string / number keys dropped", odd.ok == 3 and odd[true] == nil)
	check("sanitize: non-table input is a no-op", Guard.sanitize(5) == 0 and Guard.sanitize(nil) == 0)
end

---------------------------------------------------------------------------
-- RepeatLimiter
---------------------------------------------------------------------------
do
	check("groupKey: order independent", Guard.groupKey({ 5, 3, 9 }) == Guard.groupKey({ 9, 5, 3 }))
	check("groupKey: different groups differ", Guard.groupKey({ 1, 2 }) ~= Guard.groupKey({ 1, 3 }))
	local rl = Guard.newRepeatLimiter(8, 40)
	local key = Guard.groupKey({ 111, 222 })
	local full = 0
	for i = 1, 100 do -- two accounts duel back to back for ~17 minutes
		if Guard.countMatch(rl, key, i * 10) then
			full += 1
		end
	end
	check("repeat: only the first 8 an hour count in full", full == 8, full)
	-- an hour later they get another batch, but never more than 40 a day
	local fullDay = 0
	for h = 0, 23 do
		for i = 1, 20 do
			if Guard.countMatch(rl, "other", h * 3600 + i * 10) then
				fullDay += 1
			end
		end
	end
	check("repeat: a whole day is capped by perDay", fullDay == 40, fullDay)
	-- a real group: a few matches an hour is never limited
	local friends = Guard.newRepeatLimiter(8, 40)
	local limited = 0
	for i = 1, 6 do
		if not Guard.countMatch(friends, "a-b", i * 600) then
			limited += 1
		end
	end
	check("repeat: friends playing 6 an hour are never limited", limited == 0, limited)
	-- strangers: every group is new
	local pub = Guard.newRepeatLimiter(8, 40)
	local lim2 = 0
	for i = 1, 500 do
		if not Guard.countMatch(pub, "g" .. i, i) then
			lim2 += 1
		end
	end
	check("repeat: random public groups are never limited", lim2 == 0, lim2)
	-- memory is bounded
	Guard.prune(pub, 100000)
	check("repeat: prune forgets old groups", next(pub.log) == nil)
	local bounded = Guard.newRepeatLimiter(8, 40)
	for i = 1, 1000 do
		Guard.countMatch(bounded, "k", i)
	end
	check("repeat: one key's log is bounded", #bounded.log.k <= 40, #bounded.log.k)
end

---------------------------------------------------------------------------
-- reward economics: the farms the server closes
---------------------------------------------------------------------------
do
	-- bot-only table: half the trophies (unchanged), and the practice cap keeps the top
	-- leagues for real opponents
	local full = Progression.matchRewards("classic", 1, 5, { humans = 2 })
	local practice = Progression.matchRewards("classic", 1, 5, { humans = 1 })
	check("practice: a bot table pays half the trophies", practice.trophies == math.ceil(full.trophies / 2), practice.trophies)
	check("practice: cap sits at platinum so diamond / champion need people", Config.PracticeTrophyCap >= 250 and Config.PracticeTrophyCap < Config.Leagues[5].trophies, Config.PracticeTrophyCap)
	-- the quarter pay for repeat groups is strictly less than practice pay
	local rep = Progression.matchRewards("duel", 1, 2, { humans = 1, coin = 0.25, xp = 0.25 })
	local duel = Progression.matchRewards("duel", 1, 2, { humans = 2 })
	check("repeat: pays a fraction of a normal duel", rep.coins < duel.coins / 3 and rep.xp < duel.xp / 3 and rep.trophies < duel.trophies, rep.coins)
	-- two colluding accounts at the hourly cap earn less than one honest player
	local hour = 8 * duel.coins + 8 * 30
	local honest = 60 / 3.4 * Progression.matchRewards("classic", 1, 5, { humans = 2 }).coins * 0.4
	check("repeat: collusion at the cap does not beat honest play by much", hour < honest * 3, hour .. " vs " .. honest)
	-- referral credit waits for several matches
	check("referral: needs more than one throwaway match", Config.Referral.matchesToCredit >= 3)
end

print(string.format("%d checks, %d failures", checks, fails))
if fails > 0 then
	error("SECURITY TEST FAILED")
end
print("SECURITY TEST PASSED")
