--!strict
-- Play-time gifts, persisted per UTC day (pure: no Roblox services). The profile keeps {day, played, claimed}:
-- a rejoin on the same day keeps the claims and continues the timer; a new UTC day resets both.
local Gifts = {}

export type GiftState = { day: number, played: number, claimed: { [number]: boolean } }

function Gifts.dayKey(now: number): number
	return math.floor(now / 86400)
end

-- Normalizes a saved record (nil / garbage / old save) for `now`.
function Gifts.roll(rec: any, now: number): GiftState
	local today = Gifts.dayKey(now)
	if type(rec) ~= "table" or rec.day ~= today or type(rec.claimed) ~= "table" then
		return { day = today, played = 0, claimed = {} }
	end
	local claimed: { [number]: boolean } = {}
	for k, v in rec.claimed do
		if type(k) == "number" and v == true then
			claimed[k] = true
		end
	end
	local played = if type(rec.played) == "number" and rec.played == rec.played then math.clamp(rec.played, 0, 86400) else 0
	return { day = today, played = played, claimed = claimed }
end

-- Seconds played today for a clock reading `elapsedNow` and the clock value at which today's play time started.
function Gifts.playedAt(startClock: number, nowClock: number): number
	return math.clamp(nowClock - startClock, 0, 86400)
end

-- Clock value to store as the start so that (nowClock - start) == seconds already played today.
function Gifts.startFor(rec: GiftState, nowClock: number): number
	return nowClock - rec.played
end

return Gifts
