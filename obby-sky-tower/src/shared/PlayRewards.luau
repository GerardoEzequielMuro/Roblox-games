--!strict
-- Play-time rewards that survive leaving and rejoining. PURE Luau.
-- The profile keeps { day = UTC day key, secs = seconds played that day, claimed = { ["1"] = true } }.
-- A new UTC day wipes both the counter and the claims; a rejoin on the same day keeps them, so a
-- reward can be claimed once per day and the timer continues where it was.
local PlayRewards = {}

export type Play = { day: number, secs: number, claimed: { [string]: boolean } }

local DAY = 86400
local MAX_SECS = DAY -- cannot play more than a day in a day

function PlayRewards.dayKey(now: number): number
	return math.floor(now / DAY)
end

function PlayRewards.default(): Play
	return { day = 0, secs = 0, claimed = {} }
end

-- Repairs a loaded value in place (old saves have none; corrupted entries are reset).
function PlayRewards.sanitize(p: any): Play
	if type(p) ~= "table" then
		return PlayRewards.default()
	end
	local day = tonumber(p.day)
	local secs = tonumber(p.secs)
	p.day = if day and day == day and day >= 0 and day < math.huge then math.floor(day) else 0
	p.secs = if secs and secs == secs then math.clamp(secs, 0, MAX_SECS) else 0
	if type(p.claimed) ~= "table" then
		p.claimed = {}
	end
	local clean: { [string]: boolean } = {}
	for k, v in p.claimed :: { [any]: any } do
		if v == true and tonumber(k) then
			clean[tostring(math.floor(tonumber(k) :: number))] = true
		end
	end
	p.claimed = clean
	return p :: Play
end

-- Adds `dt` seconds of play at time `now` (os.time()); a new UTC day resets counter and claims first.
function PlayRewards.tick(play: Play, now: number, dt: number)
	local day = PlayRewards.dayKey(now)
	if day ~= play.day then
		play.day = day
		play.secs = 0
		play.claimed = {}
	end
	if dt > 0 and dt == dt and dt < math.huge then
		play.secs = math.min(play.secs + dt, MAX_SECS)
	end
end

function PlayRewards.isClaimed(play: Play, idx: number): boolean
	return play.claimed[tostring(idx)] == true
end

-- Claims reward `idx` (needs `minutes` of play today). Returns ok, reason ("claimed" | "early").
function PlayRewards.claim(play: Play, idx: number, minutes: number): (boolean, string?)
	if PlayRewards.isClaimed(play, idx) then
		return false, "claimed"
	end
	if play.secs < minutes * 60 then
		return false, "early"
	end
	play.claimed[tostring(idx)] = true
	return true, nil
end

-- Claimed indices as a list (for the State push).
function PlayRewards.list(play: Play): { number }
	local out = {}
	for k in play.claimed do
		table.insert(out, tonumber(k) :: number)
	end
	table.sort(out)
	return out
end

return PlayRewards
