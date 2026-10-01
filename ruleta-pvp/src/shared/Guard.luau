--!strict
-- Pure input validation, rate limiting and anti-farm helpers for the server. No Roblox APIs
-- and no clocks (callers pass `now`), so tests/security_test.luau drives all of it.
--   * validators: numbers without NaN/inf, bounded integers, capped strings, whitelists
--   * token buckets and per-key cooldowns
--   * sanitize(): scrubs NaN/inf out of a table before it is saved
--   * RepeatLimiter: the same group of players farming each other over and over
local Guard = {}

---------------------------------------------------------------------------
-- Validators
---------------------------------------------------------------------------
function Guard.isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A whole number inside [min, max].
function Guard.isInt(v: any, min: number, max: number): boolean
	return Guard.isNumber(v) and v % 1 == 0 and v >= min and v <= max
end

-- A string of 1..maxLen characters (0..maxLen when allowEmpty).
function Guard.isString(v: any, maxLen: number, allowEmpty: boolean?): boolean
	if type(v) ~= "string" then
		return false
	end
	local n = #v
	return n <= maxLen and (n > 0 or allowEmpty == true)
end

-- A user id: positive whole number, below 2^53.
function Guard.isUserId(v: any): boolean
	return Guard.isInt(v, 1, 2 ^ 53)
end

function Guard.oneOf(v: any, set: { [any]: any }): boolean
	return (type(v) == "string" or type(v) == "number") and set[v] ~= nil
end

-- A plain array (no holes, no string keys) of at most maxLen entries.
function Guard.isList(v: any, maxLen: number): boolean
	if type(v) ~= "table" then
		return false
	end
	local n = 0
	for k in v do
		if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then
			return false
		end
		n += 1
		if n > maxLen then
			return false
		end
	end
	return n == #v
end

---------------------------------------------------------------------------
-- Token bucket: `rate` tokens per second, at most `burst` stored.
---------------------------------------------------------------------------
export type Bucket = { tokens: number, t: number, rate: number, burst: number }

function Guard.newBucket(rate: number, burst: number, now: number): Bucket
	return { tokens = burst, t = now, rate = rate, burst = burst }
end

local function refill(b: Bucket, now: number)
	local dt = now - b.t
	if dt > 0 then
		b.tokens = math.min(b.burst, b.tokens + dt * b.rate)
	end
	b.t = math.max(b.t, now)
end

-- Takes `cost` tokens if there are enough.
function Guard.take(b: Bucket, now: number, cost: number?): boolean
	refill(b, now)
	local c = cost or 1
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end

-- Takes up to `want` whole tokens and returns how many were granted (for batched events).
function Guard.takeUpTo(b: Bucket, now: number, want: number): number
	refill(b, now)
	if not Guard.isNumber(want) or want < 1 then
		return 0
	end
	local got = math.min(math.floor(want), math.floor(b.tokens))
	if got < 1 then
		return 0
	end
	b.tokens -= got
	return got
end

---------------------------------------------------------------------------
-- Per-key cooldowns: key -> last time. ready() records the use when it says yes.
---------------------------------------------------------------------------
function Guard.cooldownReady(last: { [string]: number }, key: string, now: number, interval: number): boolean
	local prev = last[key]
	if prev and now - prev < interval then
		return false
	end
	last[key] = now
	return true
end

---------------------------------------------------------------------------
-- Failure lockout: `limit` failures inside `window` seconds lock the key for `lockFor`.
---------------------------------------------------------------------------
export type Strikes = { count: number, first: number, lockedUntil: number }

function Guard.newStrikes(): Strikes
	return { count = 0, first = 0, lockedUntil = 0 }
end

function Guard.isLocked(s: Strikes, now: number): boolean
	return now < s.lockedUntil
end

function Guard.strike(s: Strikes, now: number, limit: number, window: number, lockFor: number)
	if s.count == 0 or now - s.first > window then
		s.count, s.first = 0, now
	end
	s.count += 1
	if s.count >= limit then
		s.lockedUntil = now + lockFor
		s.count = 0
	end
end

---------------------------------------------------------------------------
-- Sanitize a table in place before it is saved: NaN / +-inf numbers become 0 (or are
-- clamped to +-1e15), functions / userdata / threads / cyclic references are dropped, depth
-- and size are bounded. Returns how many values were changed.
---------------------------------------------------------------------------
local BIG = 1e15

function Guard.sanitize(root: any, maxDepth: number?): number
	local limit = maxDepth or 8
	local fixed = 0
	local seen: { [any]: boolean } = {}
	local function walk(t: any, depth: number)
		seen[t] = true
		local drop: { any } = {}
		for k, v in t do
			local kt = type(k)
			if kt ~= "string" and kt ~= "number" then
				table.insert(drop, k)
			elseif kt == "number" and not Guard.isNumber(k) then
				table.insert(drop, k)
			else
				local vt = type(v)
				if vt == "number" then
					if v ~= v then
						t[k] = 0
						fixed += 1
					elseif v == math.huge or v > BIG then
						t[k] = BIG
						fixed += 1
					elseif v == -math.huge or v < -BIG then
						t[k] = -BIG
						fixed += 1
					end
				elseif vt == "table" then
					if seen[v] or depth >= limit then
						table.insert(drop, k)
					else
						walk(v, depth + 1)
					end
				elseif vt ~= "string" and vt ~= "boolean" then
					table.insert(drop, k)
				end
			end
		end
		for _, k in drop do
			t[k] = nil
			fixed += 1
		end
		seen[t] = nil -- shared (non cyclic) sub-tables are fine
	end
	if type(root) == "table" then
		walk(root, 1)
	end
	return fixed
end

---------------------------------------------------------------------------
-- RepeatLimiter: the same group of human players finishing matches together again and
-- again (two accounts feeding each other duels / private games). The first `perHour` /
-- `perDay` matches of a group count in full; the rest are "repeat" matches the caller pays
-- as practice.
---------------------------------------------------------------------------
export type RepeatLimiter = { perHour: number, perDay: number, log: { [string]: { number } } }

function Guard.newRepeatLimiter(perHour: number, perDay: number): RepeatLimiter
	return { perHour = perHour, perDay = perDay, log = {} }
end

-- Stable key for a set of user ids (order does not matter).
function Guard.groupKey(ids: { number }): string
	local sorted = table.clone(ids)
	table.sort(sorted)
	local parts = {}
	for _, id in sorted do
		table.insert(parts, tostring(math.floor(id)))
	end
	return table.concat(parts, "-")
end

-- Records a finished match of `key` at `now` and returns true when it still counts in full.
function Guard.countMatch(rl: RepeatLimiter, key: string, now: number): boolean
	local list = rl.log[key]
	if not list then
		list = {}
		rl.log[key] = list
	end
	-- forget what is older than a day
	while #list > 0 and now - list[1] >= 86400 do
		table.remove(list, 1)
	end
	local hour = 0
	for _, t in list do
		if now - t < 3600 then
			hour += 1
		end
	end
	local full = hour < rl.perHour and #list < rl.perDay
	-- only matches that counted are logged, so the window slides: a group that keeps
	-- playing gets its next full-pay match as soon as an old one is an hour old
	if full then
		table.insert(list, now)
	end
	return full
end

function Guard.prune(rl: RepeatLimiter, now: number)
	for key, list in rl.log do
		while #list > 0 and now - list[1] >= 86400 do
			table.remove(list, 1)
		end
		if #list == 0 then
			rl.log[key] = nil
		end
	end
end

return Guard
