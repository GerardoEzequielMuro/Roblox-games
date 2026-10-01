--!strict
-- Pure anti-exploit helpers (no Roblox services, so tests/security_test.luau runs them with
-- plain luau): argument validators, token buckets, per-action cooldowns, payload shape check,
-- profile sanitizer for saving, profile version migration and retry backoff.
local Security = {}

---------------------------------------------------------------------------
-- Validators (every client value is untrusted: wrong type, NaN, inf, huge)
---------------------------------------------------------------------------
function Security.isFinite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Integer in [min, max] (floats with a fraction, NaN and inf are rejected).
function Security.isInt(n: any, min: number?, max: number?): boolean
	if not Security.isFinite(n) or n ~= math.floor(n) then
		return false
	end
	return n >= (min or -2 ^ 53) and n <= (max or 2 ^ 53)
end

function Security.isString(s: any, maxLen: number?): boolean
	return type(s) == "string" and #s <= (maxLen or 64)
end

function Security.oneOf(v: any, set: { any }): boolean
	return table.find(set, v) ~= nil
end

-- A finite number clamped into [min, max]; `fallback` for anything else.
function Security.clampNumber(n: any, min: number, max: number, fallback: number): number
	if not Security.isFinite(n) then
		return fallback
	end
	return math.clamp(n, min, max)
end

---------------------------------------------------------------------------
-- Token bucket: `rate` tokens per second, at most `burst` stored.
---------------------------------------------------------------------------
export type Bucket = { rate: number, burst: number, tokens: number, t: number }

function Security.newBucket(rate: number, burst: number, now: number): Bucket
	return { rate = rate, burst = burst, tokens = burst, t = now }
end

-- Takes `cost` tokens when available. Time going backwards never refills.
function Security.take(b: Bucket, now: number, cost: number?): boolean
	local c = cost or 1
	local dt = math.max(0, now - b.t)
	b.tokens = math.min(b.burst, b.tokens + dt * b.rate)
	b.t = math.max(b.t, now)
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end

-- Takes up to `want` whole tokens and returns how many were granted (hit batches).
function Security.takeUpTo(b: Bucket, now: number, want: number): number
	local dt = math.max(0, now - b.t)
	b.tokens = math.min(b.burst, b.tokens + dt * b.rate)
	b.t = math.max(b.t, now)
	local n = math.min(want, math.floor(b.tokens))
	if n <= 0 then
		return 0
	end
	b.tokens -= n
	return n
end

---------------------------------------------------------------------------
-- Per-player, per-action guard: minimum interval between calls and optional "one at a time"
-- for handlers that yield (web calls), so two parallel calls cannot both pass the same check.
---------------------------------------------------------------------------
export type Guard = { last: { [string]: number }, busy: { [string]: boolean } }

function Security.newGuard(): Guard
	return { last = {}, busy = {} }
end

-- Returns true and marks the action as started when allowed.
function Security.enter(g: Guard, action: string, now: number, interval: number?, exclusive: boolean?): boolean
	if exclusive and g.busy[action] then
		return false
	end
	local last = g.last[action]
	if interval and last and now - last < interval then
		return false
	end
	g.last[action] = now
	if exclusive then
		g.busy[action] = true
	end
	return true
end

function Security.leave(g: Guard, action: string)
	g.busy[action] = nil
end

---------------------------------------------------------------------------
-- Payload shape: depth, node count, string length and number sanity, so a handler never
-- iterates a million entries or reads NaN / inf.
---------------------------------------------------------------------------
function Security.payloadOk(v: any, maxNodes: number?, maxDepth: number?, maxString: number?): boolean
	local nodes, limit, depthMax, strMax = 0, maxNodes or 1000, maxDepth or 4, maxString or 200
	local seen: { [any]: boolean } = {}
	local function walk(x: any, depth: number): boolean
		nodes += 1
		if nodes > limit then
			return false
		end
		local t = type(x)
		if t == "number" then
			return x == x and x > -math.huge and x < math.huge
		elseif t == "string" then
			return #x <= strMax
		elseif t == "boolean" or t == "nil" then
			return true
		elseif t == "table" then
			if depth > depthMax or seen[x] or getmetatable(x) ~= nil then
				return false
			end
			seen[x] = true
			for k, val in x :: any do
				if not walk(k, depth + 1) or not walk(val, depth + 1) then
					return false
				end
			end
			seen[x] = nil
			return true
		end
		return false -- functions, userdata, Instances, vectors...
	end
	return walk(v, 0)
end

---------------------------------------------------------------------------
-- Saving: a clean deep copy that DataStore will accept (NaN / inf make UpdateAsync throw,
-- which would lose the whole save). NaN -> 0, +-inf -> +-1e300, functions / userdata dropped,
-- cycles and absurd depth cut. Returns the copy and how many values it had to fix.
---------------------------------------------------------------------------
local BIG = 1e300

function Security.sanitize(v: any): (any, number)
	local fixed = 0
	local function copy(x: any, depth: number, path: { [any]: boolean }): any
		local t = type(x)
		if t == "number" then
			if x ~= x then
				fixed += 1
				return 0
			elseif x == math.huge then
				fixed += 1
				return BIG
			elseif x == -math.huge then
				fixed += 1
				return -BIG
			end
			return x
		elseif t == "string" or t == "boolean" then
			return x
		elseif t == "table" then
			if depth > 12 or path[x] then
				fixed += 1
				return nil
			end
			path[x] = true
			local out = {}
			for k, val in x do
				local kt = type(k)
				if kt == "string" or (kt == "number" and k == k and k > -math.huge and k < math.huge) then
					local c = copy(val, depth + 1, path)
					if c ~= nil then
						out[k] = c
					end
				else
					fixed += 1
				end
			end
			path[x] = nil
			return out
		end
		if x ~= nil then
			fixed += 1
		end
		return nil
	end
	return copy(v, 0, {}), fixed
end

---------------------------------------------------------------------------
-- Versioning: migrations[n] upgrades a version n profile to n + 1, in place.
-- Returns "ok", or "newer" when the save comes from a newer build (never overwrite it).
---------------------------------------------------------------------------
function Security.migrate(p: any, current: number, migrations: { [number]: (any) -> () }): string
	local v = p.version
	if type(v) ~= "number" or v ~= v or v < 1 then
		v = 1
	end
	v = math.floor(v)
	if v > current then
		return "newer"
	end
	while v < current do
		local step = migrations[v]
		if step then
			step(p)
		end
		v += 1
	end
	p.version = current
	return "ok"
end

-- Seconds to wait before retry number `attempt` (1-based): 1, 2, 4, 8... capped.
function Security.backoff(attempt: number, base: number?, cap: number?): number
	return math.min(cap or 16, (base or 1) * 2 ^ (math.max(1, attempt) - 1))
end

return Security
