--!strict
-- Season pass maths (pure; unit-tested with luau.exe). The pass state of a player is
-- { season, points, premium, claimed }. Points come only from finished matches and are never
-- multiplied by anything that can be bought. Premium only unlocks the premium reward track.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local SeasonPass = {}

export type Reward = { kind: string, amount: number, item: string? }
export type State = { season: number, points: number, premium: boolean, claimed: { [string]: boolean } }

function SeasonPass.fresh(season: number): State
	return { season = season, points = 0, premium = false, claimed = {} }
end

-- The pass resets every season (the state of an old season is dropped).
function SeasonPass.sync(sp: State?, season: number): State
	if sp == nil or sp.season ~= season then
		return SeasonPass.fresh(season)
	end
	return sp
end

function SeasonPass.maxPoints(): number
	return Config.SeasonPass.tiers * Config.SeasonPass.pointsPerTier
end

-- Highest tier reached (0..tiers).
function SeasonPass.tier(points: number): number
	return math.clamp(points // Config.SeasonPass.pointsPerTier, 0, Config.SeasonPass.tiers)
end

-- tier reached, points into the next tier, points the next tier needs (full bar at the last tier).
function SeasonPass.progress(points: number): (number, number, number)
	local per = Config.SeasonPass.pointsPerTier
	local tier = SeasonPass.tier(points)
	if tier >= Config.SeasonPass.tiers then
		return tier, per, per
	end
	return tier, points - tier * per, per
end

-- Points a finished match pays. Depends on placement only.
function SeasonPass.matchPoints(place: number, n: number, humans: number): number
	local cfg = Config.SeasonPass.points
	local pts = cfg.base
	if place == 1 then
		pts += cfg.win
	elseif place <= 3 and n >= cfg.minPlayersForTop3 then
		pts += cfg.top3
	end
	if humans <= 1 then
		pts = pts // cfg.practiceDivisor
	end
	return pts
end

-- Adds points (capped at the last tier). Returns the points actually added.
function SeasonPass.addPoints(sp: State, n: number): number
	if n ~= n or n <= 0 then
		return 0
	end
	local before = sp.points
	sp.points = math.min(SeasonPass.maxPoints(), sp.points + math.floor(n))
	return sp.points - before
end

-- A tier skip: jumps to the start of the next tier. False at the last tier.
function SeasonPass.skipTier(sp: State): boolean
	local tier = SeasonPass.tier(sp.points)
	if tier >= Config.SeasonPass.tiers then
		return false
	end
	sp.points = (tier + 1) * Config.SeasonPass.pointsPerTier
	return true
end

function SeasonPass.key(track: string, tier: number): string
	return (if track == "premium" then "p" else "f") .. tier
end

function SeasonPass.reward(track: string, tier: number): Reward?
	if track == "premium" then
		return Config.SeasonPass.premium[tier]
	elseif track == "free" then
		return Config.SeasonPass.free[tier]
	end
	return nil
end

function SeasonPass.canClaim(sp: State, track: string, tier: number): boolean
	if type(tier) ~= "number" or tier ~= tier or tier % 1 ~= 0 or tier < 1 or tier > Config.SeasonPass.tiers then
		return false
	end
	if track ~= "free" and track ~= "premium" then
		return false
	end
	if track == "premium" and not sp.premium then
		return false
	end
	return tier <= SeasonPass.tier(sp.points) and not sp.claimed[SeasonPass.key(track, tier)]
end

-- Every (track, tier) that can be claimed right now, in tier order.
function SeasonPass.claimables(sp: State): { { track: string, tier: number } }
	local out = {}
	for tier = 1, SeasonPass.tier(sp.points) do
		for _, track in { "free", "premium" } do
			if SeasonPass.canClaim(sp, track, tier) then
				table.insert(out, { track = track, tier = tier })
			end
		end
	end
	return out
end

return SeasonPass
