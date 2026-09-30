--!strict
-- Season pass: points from finished matches, the free and premium reward tracks, claims and
-- the two Robux products that feed it (premium track, one-tier skip). Everything is fixed and
-- visible before buying; points never depend on anything bought; nothing reaches a match.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Progression = require(ReplicatedStorage.Shared.Progression)
local SeasonPass = require(ReplicatedStorage.Shared.SeasonPass)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Rewards = require(script.Parent.Rewards)
local M = Locale.m

local SeasonService = {}

-- The player's pass for the current season (a new month starts a fresh one).
function SeasonService.current(p: Data.Profile): SeasonPass.State
	local sp = SeasonPass.sync(p.sp, Progression.season(os.time()))
	p.sp = sp
	return sp
end

-- Called after each finished match. Returns the points earned.
function SeasonService.onMatch(player: Player, place: number, n: number, humans: number): number
	local p = Data.get(player)
	if not p then
		return 0
	end
	local sp = SeasonService.current(p)
	local tierBefore = SeasonPass.tier(sp.points)
	local added = SeasonPass.addPoints(sp, SeasonPass.matchPoints(place, n, humans))
	if SeasonPass.tier(sp.points) > tierBefore then
		Remotes.notify(player, M("season.tier_up", { n = SeasonPass.tier(sp.points) }), "success")
	end
	State.dirty(player)
	return added
end

-- Product grants (called from Monetization.grantProduct; the receipt is already idempotent).
function SeasonService.grantPremium(player: Player): boolean
	local p = Data.get(player)
	if not p then
		return false
	end
	local sp = SeasonService.current(p)
	if sp.premium then
		State.addCoins(player, Config.SeasonPass.duplicatePremiumCoins)
	else
		sp.premium = true
	end
	State.dirty(player)
	return true
end

function SeasonService.grantTier(player: Player): boolean
	local p = Data.get(player)
	if not p then
		return false
	end
	local sp = SeasonService.current(p)
	if not SeasonPass.skipTier(sp) then
		State.addCoins(player, Config.SeasonPass.maxTierSkipCoins)
	else
		Remotes.notify(player, M("season.tier_up", { n = SeasonPass.tier(sp.points) }), "success")
	end
	State.dirty(player)
	return true
end

-- Claims one reward. Marks it claimed first so it can never be paid twice.
function SeasonService.claim(player: Player, track: string, tier: number): (boolean, Locale.Message?)
	local p = Data.get(player)
	if not p then
		return false, M("msg.error")
	end
	local sp = SeasonService.current(p)
	if not SeasonPass.canClaim(sp, track, tier) then
		return false, M("season.cannot_claim")
	end
	local reward = SeasonPass.reward(track, tier)
	if not reward then
		return false, M("season.cannot_claim")
	end
	sp.claimed[SeasonPass.key(track, tier)] = true
	local message = Rewards.grant(player, reward :: any)
	State.dirty(player)
	return true, message
end

function SeasonService.claimAll(player: Player): (boolean, Locale.Message?)
	local p = Data.get(player)
	if not p then
		return false, M("msg.error")
	end
	local sp = SeasonService.current(p)
	local list = SeasonPass.claimables(sp)
	if #list == 0 then
		return false, M("season.cannot_claim")
	end
	for _, c in list do
		SeasonService.claim(player, c.track, c.tier)
	end
	return true, M("season.claimed_n", { n = #list })
end

function SeasonService.snapshot(p: Data.Profile): { [string]: any }
	local sp = SeasonService.current(p)
	local tier, into, need = SeasonPass.progress(sp.points)
	return {
		points = sp.points,
		tier = tier,
		into = into,
		need = need,
		premium = sp.premium,
		claimed = sp.claimed,
		endsAt = Progression.seasonEndsAt(os.time()),
		claimable = #SeasonPass.claimables(sp),
	}
end

function SeasonService.init()
	State.extras.season = function(_player, p)
		return SeasonService.snapshot(p)
	end
	Remotes.handle("ClaimSeason", function(player, payload)
		if type(payload.track) ~= "string" or type(payload.tier) ~= "number" then
			return false, M("msg.bad_request")
		end
		return SeasonService.claim(player, payload.track, payload.tier)
	end)
	Remotes.handle("ClaimSeasonAll", function(player)
		return SeasonService.claimAll(player)
	end)
end

return SeasonService
