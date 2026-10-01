--!strict
-- Pure rules for the "minutes since joining" gifts. The claims and the time played today are
-- persisted in the profile (profile.gifts) and reset on a new UTC day, so leaving and rejoining
-- the same day can neither re-claim a gift nor restart its timer.
local GiftClock = {}

export type Gifts = { day: number, played: number, claimed: { [string]: boolean } }

GiftClock.DAY_SECONDS = 86400

function GiftClock.dayKey(now: number): number
	return math.floor(now / GiftClock.DAY_SECONDS)
end

function GiftClock.default(): Gifts
	return { day = 0, played = 0, claimed = {} }
end

-- Safe values for old saves (no field) or corrupt ones. Mutates and returns a valid table.
function GiftClock.sanitize(g: any): Gifts
	if type(g) ~= "table" then
		return GiftClock.default()
	end
	local day = tonumber(g.day)
	local played = tonumber(g.played)
	g.day = if day and day == day and day >= 0 and day < math.huge then math.floor(day) else 0
	g.played = if played and played == played and played >= 0 and played < math.huge then played else 0
	local claimed: { [string]: boolean } = {}
	if type(g.claimed) == "table" then
		for k, v in g.claimed do
			if v == true and tonumber(k) then
				claimed[tostring(math.floor(tonumber(k) :: number))] = true
			end
		end
	end
	g.claimed = claimed
	return g :: Gifts
end

-- Starts a new day when the UTC day changed. Returns true when it reset.
function GiftClock.roll(g: Gifts, now: number): boolean
	local key = GiftClock.dayKey(now)
	if g.day ~= key then
		g.day = key
		g.played = 0
		g.claimed = {}
		return true
	end
	return false
end

function GiftClock.isClaimed(g: Gifts, index: number): boolean
	return g.claimed[tostring(index)] == true
end

function GiftClock.markClaimed(g: Gifts, index: number)
	g.claimed[tostring(index)] = true
end

-- Gift indexes claimed today, ascending (what the snapshot sends to the client).
function GiftClock.claimedList(g: Gifts): { number }
	local list = {}
	for k in g.claimed do
		table.insert(list, tonumber(k) :: number)
	end
	table.sort(list)
	return list
end

-- True when a gift of `minutes` is available after `elapsed` seconds played today (1 s of slack).
function GiftClock.ready(elapsed: number, minutes: number): boolean
	return elapsed + 1 >= minutes * 60
end

return GiftClock
