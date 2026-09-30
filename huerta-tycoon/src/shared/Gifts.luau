--!strict
-- Session play-time gifts: pure math (no Roblox services), shared by server and client.
local Gifts = {}

export type GiftView = { minutes: number, ready: boolean, claimed: boolean }

-- ready = the time has been reached and it hasn't been claimed yet. Returns the views and how many are ready.
function Gifts.ready(gifts: { any }, sessionStart: number, now: number, claimed: { [number]: boolean }): ({ GiftView }, number)
	local out: { GiftView } = {}
	local n = 0
	local elapsed = now - sessionStart
	for i, g in gifts do
		local isClaimed = claimed[i] == true
		local reached = elapsed >= g.minutes * 60
		local ready = reached and not isClaimed
		if ready then
			n += 1
		end
		table.insert(out, { minutes = g.minutes, ready = ready, claimed = isClaimed })
	end
	return out, n
end

-- Can gift #index be claimed now? Returns (ok, reason) with reason in {"bad", "claimed", "early"}.
function Gifts.canClaim(gifts: { any }, index: any, sessionStart: number, now: number, claimed: { [number]: boolean }): (boolean, string?)
	if type(index) ~= "number" or index ~= math.floor(index) or not gifts[index] then
		return false, "bad"
	end
	if claimed[index] then
		return false, "claimed"
	end
	if now - sessionStart < gifts[index].minutes * 60 then
		return false, "early"
	end
	return true, nil
end

-- Seconds until gift #index is ready (0 when ready).
function Gifts.secondsLeft(gift: any, sessionStart: number, now: number): number
	return math.max(0, math.ceil(sessionStart + gift.minutes * 60 - now))
end

-- "N minutes of your recent earnings" with a per-minute floor.
function Gifts.cashFor(minutes: number, earnRatePerMinute: number, floorPerMinute: number): number
	return math.max(math.floor(floorPerMinute * minutes), math.floor(earnRatePerMinute * minutes))
end

return Gifts
