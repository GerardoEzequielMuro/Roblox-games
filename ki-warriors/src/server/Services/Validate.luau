--!strict
-- Round 7: pure input validation + rate limiting helpers (no Roblox APIs, so tests/security_test.luau
-- can run them under plain Luau). Every remote handler funnels untrusted values through here.
local Validate = {}

---------------------------------------------------------------------------
-- Scalars
---------------------------------------------------------------------------
-- A real, finite number (rejects NaN, +inf, -inf and every non-number type).
function Validate.finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Finite number inside [min, max], or nil.
function Validate.number(v: any, min: number, max: number): number?
	if Validate.finite(v) and v >= min and v <= max then
		return v
	end
	return nil
end

-- Whole number inside [min, max], or nil.
function Validate.int(v: any, min: number, max: number): number?
	if Validate.finite(v) and v % 1 == 0 and v >= min and v <= max then
		return v
	end
	return nil
end

-- String of at most maxLen bytes, or nil.
function Validate.str(v: any, maxLen: number): string?
	if type(v) == "string" and #v <= maxLen then
		return v
	end
	return nil
end

-- String that is a key of `set` (a whitelist), or nil.
function Validate.enum(v: any, set: { [string]: any }): string?
	if type(v) == "string" and #v <= 64 and set[v] ~= nil then
		return v
	end
	return nil
end

-- A Vector3-like triple must be finite on every axis (works on tables { x, y, z } for tests).
function Validate.finiteVec(x: any, y: any, z: any): boolean
	return Validate.finite(x) and Validate.finite(y) and Validate.finite(z)
end

---------------------------------------------------------------------------
-- Remote payloads: every payload in this game is a flat table of primitives.
---------------------------------------------------------------------------
Validate.MAX_PAYLOAD_KEYS = 12
Validate.MAX_KEY_LEN = 32
Validate.MAX_STRING_LEN = 64

-- True when `payload` is a flat table, at most 12 entries, string keys <= 32 bytes, values are
-- finite numbers, booleans or strings <= 64 bytes (no nested tables, no functions, no NaN/inf).
function Validate.payload(payload: any): boolean
	if type(payload) ~= "table" then
		return false
	end
	if getmetatable(payload) ~= nil then
		return false
	end
	local n = 0
	for k, v in payload do
		n += 1
		if n > Validate.MAX_PAYLOAD_KEYS or type(k) ~= "string" or #k > Validate.MAX_KEY_LEN then
			return false
		end
		local t = type(v)
		if t == "number" then
			if not Validate.finite(v) then
				return false
			end
		elseif t == "string" then
			if #v > Validate.MAX_STRING_LEN then
				return false
			end
		elseif t ~= "boolean" then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Token bucket: rate per second, burst capacity. Time is passed in (os.clock()).
---------------------------------------------------------------------------
export type Bucket = { tokens: number, t: number, rate: number, burst: number }

function Validate.newBucket(rate: number, burst: number, now: number): Bucket
	return { tokens = burst, t = now, rate = rate, burst = burst }
end

-- Takes `cost` tokens; false when the bucket is empty. A clock that goes backwards never refunds.
function Validate.take(b: Bucket, now: number, cost: number?): boolean
	local dt = math.max(0, now - b.t)
	b.tokens = math.min(b.burst, b.tokens + dt * b.rate)
	b.t = math.max(b.t, now)
	local c = cost or 1
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end

-- Minimum seconds between two uses of the same key. Returns true (and stamps) when allowed.
function Validate.cooldown(last: { [string]: number }, key: string, now: number, seconds: number): boolean
	local prev = last[key]
	if prev ~= nil and now - prev < seconds then
		return false
	end
	last[key] = now
	return true
end

---------------------------------------------------------------------------
-- Movement budget (anti speed hack). Bucket of studs that refills at maxSpeed * slack per
-- second; every checked step spends the distance travelled. A burst capacity absorbs dashes,
-- knockback and latency spikes, so only sustained speed above the best legit setup trips it.
---------------------------------------------------------------------------
export type MoveBudget = { studs: number }

function Validate.newMoveBudget(capacity: number): MoveBudget
	return { studs = capacity }
end

-- Returns true while the player is within budget. `dist` is the distance moved this step (use
-- horizontal + upward only; falling is free), `dt` the seconds since the last step.
function Validate.moveStep(m: MoveBudget, dist: number, dt: number, maxSpeed: number, slack: number, capacity: number): boolean
	if not Validate.finite(dist) or not Validate.finite(dt) then
		return false
	end
	m.studs = math.min(capacity, m.studs + maxSpeed * slack * math.max(0, dt))
	m.studs -= math.max(0, dist)
	if m.studs < 0 then
		m.studs = capacity -- caller teleports the player back; start the next window clean
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Save safety: never write NaN / inf. Replaces them in place (with 0) and returns how many.
---------------------------------------------------------------------------
function Validate.sanitize(value: any, depth: number?): number
	local d = depth or 0
	if type(value) ~= "table" or d > 12 then
		return 0
	end
	local fixed = 0
	local t = value :: { [any]: any }
	for k, v in t do
		if type(v) == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				t[k] = 0
				fixed += 1
			end
		elseif type(v) == "table" then
			fixed += Validate.sanitize(v, d + 1)
		end
	end
	return fixed
end

-- True when the table (recursively) holds no NaN / inf.
function Validate.clean(value: any, depth: number?): boolean
	local d = depth or 0
	if type(value) == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	end
	if type(value) ~= "table" or d > 12 then
		return true
	end
	for _, v in value :: { [any]: any } do
		if not Validate.clean(v, d + 1) then
			return false
		end
	end
	return true
end

return Validate
