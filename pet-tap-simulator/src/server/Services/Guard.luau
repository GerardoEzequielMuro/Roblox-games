--!strict
-- Pure validation / rate-limit helpers for everything a client can send (no Roblox APIs, so
-- tests/security_test.luau runs it with plain luau). Every remote handler goes through these:
-- assume the caller can send any type, NaN, inf, negatives, huge strings and huge tables.
local Guard = {}

-- Finite number (rejects NaN, +-inf and non-numbers).
function Guard.num(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Integer in [min, max] (rejects fractions, NaN, inf, non-numbers).
function Guard.int(x: any, min: number, max: number): boolean
	return Guard.num(x) and x == math.floor(x) and x >= min and x <= max
end

-- String of 1..maxLen bytes (empty allowed with allowEmpty).
function Guard.str(x: any, maxLen: number, allowEmpty: boolean?): boolean
	if type(x) ~= "string" then
		return false
	end
	local n = #x
	return n <= maxLen and (n > 0 or allowEmpty == true)
end

-- Inventory ids look like "p123": short, no control characters.
function Guard.uid(x: any): boolean
	return type(x) == "string" and #x >= 2 and #x <= 12 and string.find(x, "^p%d+$") ~= nil
end

-- Member of a whitelist set { [value] = true }.
function Guard.oneOf(x: any, set: { [any]: any }): boolean
	return (type(x) == "string" or type(x) == "number") and x == x and set[x] ~= nil
end

-- Table with at most maxKeys entries (stops counting early, so a huge table costs O(maxKeys)).
function Guard.smallTable(t: any, maxKeys: number): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for _ in t do
		n += 1
		if n > maxKeys then
			return false
		end
	end
	return true
end

-- Array (1..n, no holes, no other keys) with at most maxLen entries.
function Guard.array(t: any, maxLen: number): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in t do
		n += 1
		if n > maxLen or type(k) ~= "number" or k ~= n then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Token bucket: rate tokens per second, burst capacity. One bucket per key (player).
---------------------------------------------------------------------------
export type Limiter = {
	rate: number,
	burst: number,
	buckets: { [any]: { tokens: number, t: number } },
}

function Guard.limiter(rate: number, burst: number): Limiter
	return { rate = rate, burst = burst, buckets = {} }
end

-- Takes up to `want` tokens (default 1, whole numbers only); returns how many were granted.
function Guard.take(l: Limiter, key: any, now: number, want: number?): number
	local b = l.buckets[key]
	if not b then
		b = { tokens = l.burst, t = now }
		l.buckets[key] = b
	end
	local dt = now - b.t
	if dt < 0 then
		dt = 0 -- clock never runs backwards for us
	end
	b.tokens = math.min(l.burst, b.tokens + dt * l.rate)
	b.t = now
	local w = want or 1
	if not Guard.num(w) or w < 1 then
		return 0
	end
	local granted = math.min(math.floor(w), math.floor(b.tokens))
	if granted <= 0 then
		return 0
	end
	b.tokens -= granted
	return granted
end

function Guard.allow(l: Limiter, key: any, now: number): boolean
	return Guard.take(l, key, now, 1) >= 1
end

function Guard.forget(l: Limiter, key: any)
	l.buckets[key] = nil
end

function Guard.count(l: Limiter): number
	local n = 0
	for _ in l.buckets do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------
-- Save safety
---------------------------------------------------------------------------
-- Replaces NaN / +-inf anywhere in a (cycle-safe, depth-capped) table by 0. Returns how many were fixed.
function Guard.scrub(t: any, depth: number?, seen: { [any]: boolean }?): number
	local d = depth or 0
	local s = seen or {}
	if type(t) ~= "table" or d > 12 or s[t] then
		return 0
	end
	s[t] = true
	local fixed = 0
	for k, v in t do
		if type(v) == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				t[k] = 0
				fixed += 1
			end
		elseif type(v) == "table" then
			fixed += Guard.scrub(v, d + 1, s)
		end
	end
	return fixed
end

-- Currency-like top-level numbers can never be negative.
function Guard.clampNonNegative(t: { [string]: any }, keys: { string }): number
	local fixed = 0
	for _, k in keys do
		local v = t[k]
		if type(v) == "number" and v < 0 then
			t[k] = 0
			fixed += 1
		end
	end
	return fixed
end

-- Makes every key of `def` have the same type in `p` (wrong type -> the default's value, via copy()).
function Guard.fixTypes(p: { [string]: any }, def: { [string]: any }, copy: (any) -> any): number
	local fixed = 0
	for k, v in def do
		if p[k] ~= nil and type(p[k]) ~= type(v) then
			p[k] = copy(v)
			fixed += 1
		end
	end
	return fixed
end

function Guard.deepCopy(v: any, depth: number?): any
	if type(v) ~= "table" or (depth or 0) > 12 then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = Guard.deepCopy(x, (depth or 0) + 1)
	end
	return out
end

-- Runs migration steps { [fromVersion] = function(profile) } until `current`. A profile from a
-- NEWER version (rolled-back server) is left alone. Returns the version it ends at.
function Guard.migrate(p: { [string]: any }, steps: { [number]: (any) -> () }, current: number): number
	local v = p.version
	if not Guard.int(v, 0, 1e6) then
		v = 1
	end
	while v < current do
		local step = steps[v]
		if step then
			step(p)
		end
		v += 1
	end
	if v > current then
		return v
	end
	p.version = current
	return current
end

-- Backoff delay for retry number `attempt` (1-based): base * 2^(attempt-1), capped.
function Guard.backoff(attempt: number, base: number, cap: number): number
	return math.min(cap, base * 2 ^ (attempt - 1))
end

return Guard
