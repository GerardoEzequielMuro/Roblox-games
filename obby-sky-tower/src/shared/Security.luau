--!strict
-- Anti-exploit helpers (pure Luau, unit-tested in tests/security_test.luau). Every client is an
-- exploiter who can send any value to any remote: these are the checks the server runs on them.
--   * type guards: finite numbers, integers in a range, strings with a length cap
--   * payload shape check for Request(action, payload)
--   * token bucket + per-key cooldowns (time is passed in, so they are testable)
--   * movement plausibility (checkpoint teleports, ranked run floor)
--   * profile sanitiser (never save NaN / inf / negative currency)
local Security = {}

Security.MAX_ACTION_LEN = 32
Security.MAX_STRING_LEN = 128
Security.MAX_PAYLOAD_KEYS = 8

-- Fastest a character can plausibly cover the straight line between two checkpoint pads in a
-- single hop (bounce pads, falling, a dash), in studs/s. Walk speed is 16 (24 with the coil).
Security.HOP_MAX_SPEED = 45
-- Lower bound for a RANKED run (no coils / power-ups / skips): total pad-to-pad distance divided
-- by this speed is the least time a legit climb can take; a faster time was teleported.
Security.RANKED_MAX_SPEED = 30

function Security.finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- `v` as an integer in [lo, hi], or nil (wrong type, NaN, inf, fraction, out of range).
function Security.int(v: any, lo: number, hi: number): number?
	if not Security.finite(v) then
		return nil
	end
	local n = v :: number
	if n ~= math.floor(n) or n < lo or n > hi then
		return nil
	end
	return n
end

-- `v` as a string of at most `maxLen` bytes, or nil.
function Security.str(v: any, maxLen: number?): string?
	if type(v) ~= "string" or #v > (maxLen or Security.MAX_STRING_LEN) then
		return nil
	end
	return v
end

-- `v` if it is one of the whitelisted strings, else nil.
function Security.oneOf(v: any, list: { string }): string?
	if type(v) ~= "string" then
		return nil
	end
	return if table.find(list, v) then v else nil
end

-- A Request payload must be nil or a flat table: string keys, values that are finite numbers,
-- booleans or short strings (no nested tables, no functions, no NaN / inf, no huge strings).
function Security.payloadOk(payload: any): boolean
	if payload == nil then
		return true
	end
	if type(payload) ~= "table" then
		return false
	end
	local n = 0
	for k, v in payload :: { [any]: any } do
		n += 1
		if n > Security.MAX_PAYLOAD_KEYS or type(k) ~= "string" or #k > Security.MAX_ACTION_LEN then
			return false
		end
		local t = type(v)
		if t == "number" then
			if not Security.finite(v) then
				return false
			end
		elseif t == "string" then
			if #v > Security.MAX_STRING_LEN then
				return false
			end
		elseif t ~= "boolean" then
			return false
		end
	end
	return true
end

-- Token bucket -------------------------------------------------------------------------------------
export type Bucket = { tokens: number, t: number, rate: number, burst: number }

function Security.newBucket(rate: number, burst: number, now: number): Bucket
	return { tokens = burst, t = now, rate = rate, burst = burst }
end

-- Takes `cost` tokens at time `now`. False = over the limit (nothing taken).
function Security.take(b: Bucket, now: number, cost: number?): boolean
	local dt = math.max(0, now - b.t) -- a clock that goes backwards never refills
	b.tokens = math.min(b.burst, b.tokens + dt * b.rate)
	b.t = now
	local c = cost or 1
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end

-- Per-key minimum interval --------------------------------------------------------------------------
export type Cooldowns = { [string]: number }

-- True (and records `now`) when at least `interval` seconds passed since the last accepted call.
function Security.cooldownOk(cd: Cooldowns, key: string, now: number, interval: number): boolean
	local last = cd[key]
	if last ~= nil and now - last < interval then
		return false
	end
	cd[key] = now
	return true
end

-- Movement plausibility --------------------------------------------------------------------------------
-- Seconds needed to cover `dist` studs at `speed` studs/s.
function Security.travelSeconds(dist: number, speed: number): number
	if not Security.finite(dist) or dist <= 0 or speed <= 0 then
		return 0
	end
	return dist / speed
end

-- Could a character have gone from the last known position to a pad `dist` studs away in `elapsed`
-- seconds? (Teleporting exploiters fail; walkers, fallers and bouncers pass.)
function Security.hopPlausible(dist: number, elapsed: number): boolean
	return elapsed >= Security.travelSeconds(dist, Security.HOP_MAX_SPEED)
end

-- Least milliseconds a ranked run covering `totalDist` studs of pad-to-pad distance can take.
function Security.rankedFloorMs(totalDist: number): number
	return math.floor(Security.travelSeconds(totalDist, Security.RANKED_MAX_SPEED) * 1000)
end

function Security.rankedPlausible(ms: number, totalDist: number): boolean
	return Security.finite(ms) and ms > 0 and ms >= Security.rankedFloorMs(totalDist)
end

-- Profile sanitiser ----------------------------------------------------------------------------------
-- Numbers that can never be negative or absurd. Everything else only has NaN / inf removed.
local NON_NEGATIVE = {
	"coins", "totalCoins", "freeSkips", "wins", "stage", "best", "runTop", "bestRunMs", "playTime",
	"referralRewards", "boostEndsAt", "notifAskedAt", "savedAt", "firstJoin", "referredBy",
}
local MAX_CURRENCY = 1e12

-- Fixes `p` in place (deep, depth-limited, cycle-safe). Returns how many values were repaired.
function Security.sanitizeProfile(p: any): number
	if type(p) ~= "table" then
		return 0
	end
	local fixed = 0
	local seen: { [any]: boolean } = {}
	local function walk(t: any, depth: number)
		if seen[t] or depth > 6 then
			return
		end
		seen[t] = true
		for k, v in t :: { [any]: any } do
			local tv = type(v)
			if tv == "number" then
				if not Security.finite(v) then
					t[k] = 0
					fixed += 1
				end
			elseif tv == "table" then
				walk(v, depth + 1)
			end
		end
	end
	walk(p, 0)
	for _, k in NON_NEGATIVE do
		local v = (p :: any)[k]
		if type(v) == "number" and (v < 0 or v > MAX_CURRENCY) then
			(p :: any)[k] = math.clamp(v, 0, MAX_CURRENCY)
			fixed += 1
		end
	end
	return fixed
end

return Security
