--!strict
-- Profile hygiene before it touches the DataStore (pure, unit-tested): no NaN/inf ever gets saved, schema
-- migrations are explicit, and retry delays are computed in one place.
local ProfileGuard = {}

ProfileGuard.CURRENT_VERSION = 2

local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end
ProfileGuard.isFinite = finite

-- Walks `t` and removes every non-finite number (map entries are dropped, array entries removed). At the top
-- level (depth 0) a key that has a number default gets that default instead. Cycle-safe and depth-limited.
-- Returns how many values were fixed.
local function walk(t: any, depth: number, defaults: any, seen: { [any]: boolean }): number
	if depth > 8 or seen[t] then
		return 0
	end
	seen[t] = true
	local fixed = 0
	local badKeys: { any } = {}
	for k, v in t do
		if type(v) == "number" then
			if not finite(v) then
				table.insert(badKeys, k)
			end
		elseif type(v) == "table" then
			fixed += walk(v, depth + 1, nil, seen)
		end
	end
	-- remove array holes from the back so indexes stay valid
	table.sort(badKeys, function(a: any, b: any)
		if type(a) == "number" and type(b) == "number" then
			return a > b
		end
		return tostring(a) < tostring(b)
	end)
	for _, k in badKeys do
		fixed += 1
		local def = if depth == 0 and defaults then defaults[k] else nil
		if type(k) == "number" and #t > 0 and k <= #t then
			table.remove(t, k)
		elseif type(def) == "number" then
			t[k] = def
		else
			t[k] = nil
		end
	end
	return fixed
end

function ProfileGuard.sanitize(profile: any, defaults: any?): number
	return walk(profile, 0, defaults, {})
end

-- true when the table holds no NaN/inf anywhere (read-only check).
function ProfileGuard.isClean(t: any, depth: number?, seen: { [any]: boolean }?): boolean
	local d = depth or 0
	local sn = seen or {}
	if d > 8 or sn[t] then
		return true
	end
	sn[t] = true
	for _, v in t do
		if type(v) == "number" and not finite(v) then
			return false
		elseif type(v) == "table" and not ProfileGuard.isClean(v, d + 1, sn) then
			return false
		end
	end
	return true
end

-- Numeric profile fields that can never be negative.
local NON_NEGATIVE = { "cash", "totalEarned", "rebirths", "tilesOwned", "playTime", "referralRewards" }

-- Migration steps: steps[v] upgrades a profile from version v to v + 1.
ProfileGuard.steps = {
	-- v1 -> v2: profiles written before the exploit audit may carry negative counters or non-table containers
	[1] = function(p: any)
		for _, k in NON_NEGATIVE do
			if type(p[k]) == "number" and p[k] < 0 then
				p[k] = 0
			end
		end
		if type(p.purchases) ~= "table" then
			p.purchases = {}
		end
	end,
} :: { [number]: (any) -> () }

-- Brings a profile to CURRENT_VERSION. A profile from a NEWER version is left alone (never downgraded).
-- Returns the final version.
function ProfileGuard.migrate(p: any): number
	local v = p.version
	if type(v) ~= "number" or not finite(v) or v < 1 then
		v = 1
	end
	v = math.floor(v)
	while v < ProfileGuard.CURRENT_VERSION do
		local step = ProfileGuard.steps[v]
		if step then
			step(p)
		end
		v += 1
		p.version = v
	end
	if type(p.version) ~= "number" or p.version < v then
		p.version = v
	end
	return p.version
end

-- Seconds to wait before retry number `attempt` (1-based): exponential with a cap.
function ProfileGuard.backoff(attempt: number, base: number, cap: number): number
	return math.min(cap, base * 2 ^ math.max(0, attempt - 1))
end

return ProfileGuard
