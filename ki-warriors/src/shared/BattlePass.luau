--!strict
-- Battle pass maths (pure): which season is live, tiers from XP, what can be claimed. The
-- server stores one record per season: { xp, premium, free = {["3"]=true}, paid = {...} }.
local Config: any = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local BattlePass = {}

export type Record = { xp: number, premium: boolean, free: { [string]: boolean }, paid: { [string]: boolean } }

function BattlePass.newRecord(): Record
	return { xp = 0, premium = false, free = {}, paid = {} }
end

-- The season running at `now` (nil before the first / after the last one), and the next one.
function BattlePass.active(now: number): (any?, any?)
	local nextSeason = nil
	for _, season in Config.BattlePass.seasons do
		if now >= season.startsAt and now < season.endsAt then
			return season, nil
		end
		if season.startsAt > now and (nextSeason == nil or season.startsAt < nextSeason.startsAt) then
			nextSeason = season
		end
	end
	return nil, nextSeason
end

function BattlePass.tier(xp: number): number
	return math.clamp(math.floor(xp / Config.BattlePass.xpPerTier), 0, Config.BattlePass.tiers)
end

-- XP still missing for the next tier (0 when maxed) and the fraction inside the current tier.
function BattlePass.progress(xp: number): (number, number)
	local per = Config.BattlePass.xpPerTier
	if BattlePass.tier(xp) >= Config.BattlePass.tiers then
		return 0, 1
	end
	local inside = xp % per
	return per - inside, inside / per
end

function BattlePass.addXp(rec: Record, amount: number): number
	if amount ~= amount or amount <= 0 then
		return rec.xp
	end
	local cap = Config.BattlePass.xpPerTier * Config.BattlePass.tiers
	rec.xp = math.min(cap, rec.xp + math.floor(amount))
	return rec.xp
end

function BattlePass.reward(seasonId: string, track: string, tier: number): any?
	local r = Config.BattlePass.rewards[seasonId]
	return r and r[track][tier]
end

-- Can this tier of this track be claimed right now? Returns ok, reason.
function BattlePass.canClaim(rec: Record, seasonId: string, track: string, tier: number): (boolean, string?)
	if track ~= "free" and track ~= "premium" then
		return false, "bad"
	end
	if type(tier) ~= "number" or tier % 1 ~= 0 or tier < 1 or tier > Config.BattlePass.tiers then
		return false, "bad"
	end
	if BattlePass.tier(rec.xp) < tier then
		return false, "locked"
	end
	if track == "premium" and not rec.premium then
		return false, "premium"
	end
	local claimed = if track == "free" then rec.free else rec.paid
	if claimed[tostring(tier)] then
		return false, "claimed"
	end
	return true, nil
end

function BattlePass.markClaimed(rec: Record, track: string, tier: number)
	local claimed = if track == "free" then rec.free else rec.paid
	claimed[tostring(tier)] = true
end

-- Number of rewards waiting (for the menu badge).
function BattlePass.claimableCount(rec: Record, seasonId: string): number
	local n = 0
	for tier = 1, BattlePass.tier(rec.xp) do
		if BattlePass.canClaim(rec, seasonId, "free", tier) then
			n += 1
		end
		if BattlePass.canClaim(rec, seasonId, "premium", tier) then
			n += 1
		end
	end
	return n
end

return BattlePass
