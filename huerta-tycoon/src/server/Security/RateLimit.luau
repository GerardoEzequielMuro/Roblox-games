--!strict
-- Per-player rate limiting (pure: the caller passes the clock, so it is unit-tested without Roblox).
local RateLimit = {}

-- ===== token bucket =====
export type Bucket = { tokens: number, t: number }

function RateLimit.newBucket(burst: number, now: number): Bucket
	return { tokens = burst, t = now }
end

-- Refills at `rate` tokens/second up to `burst`, then takes `cost`. false = over the limit.
function RateLimit.take(b: Bucket, now: number, rate: number, burst: number, cost: number?): boolean
	local dt = math.max(0, now - b.t) -- a clock that goes backwards must not mint tokens
	b.tokens = math.min(burst, b.tokens + dt * rate)
	b.t = now
	local c = cost or 1
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end

-- ===== per-key cooldowns (one table per player: { [action]: lastTime }) =====
export type Cooldowns = { [string]: number }

-- true (and records the call) when `interval` seconds have passed since the last accepted call of `key`.
function RateLimit.ready(cd: Cooldowns, key: string, now: number, interval: number): boolean
	local last = cd[key]
	if last and now - last < interval then
		return false
	end
	cd[key] = now
	return true
end

-- ===== strikes: N failures inside a window lock the key for a while (code brute force, etc.) =====
export type Strikes = { fails: { number }, lockedUntil: number }

function RateLimit.newStrikes(): Strikes
	return { fails = {}, lockedUntil = 0 }
end

function RateLimit.locked(st: Strikes, now: number): boolean
	return now < st.lockedUntil
end

-- Records a failure; returns true when this one triggered a lock.
function RateLimit.strike(st: Strikes, now: number, maxFails: number, window: number, lockFor: number): boolean
	local fails = st.fails
	table.insert(fails, now)
	while #fails > 0 and now - fails[1] > window do
		table.remove(fails, 1)
	end
	if #fails >= maxFails then
		st.lockedUntil = now + lockFor
		table.clear(fails)
		return true
	end
	return false
end

return RateLimit
