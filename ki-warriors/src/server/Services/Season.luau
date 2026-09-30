--!strict
-- Battle pass (seasons): a free track and a premium track (Robux product per season), XP
-- from playing (daily quests, bosses, world boss, arena wins, time played), tier skips.
-- No random rewards. The season has a real start and end (Config.BattlePass.seasons) and
-- the clock is shown in the pass window. Claims are validated here (Shared/BattlePass).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BattlePass = require(ReplicatedStorage.Shared.BattlePass)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Rewards = require(script.Parent.Rewards)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local Season = {}

local function record(p: Data.Profile, id: string): BattlePass.Record
	local rec = p.bp[id]
	if not rec then
		rec = BattlePass.newRecord()
		p.bp[id] = rec
	end
	return rec :: any
end

function Season.addXp(player: Player, amount: number)
	local p = Data.get(player)
	local season = BattlePass.active(os.time())
	if not p or not season or amount <= 0 then
		return
	end
	local rec = record(p, season.id)
	local before = BattlePass.tier(rec.xp)
	BattlePass.addXp(rec, amount)
	if BattlePass.tier(rec.xp) > before then
		Remotes.notify(player, M("msg.bp_tier", { n = BattlePass.tier(rec.xp) }), "success")
	end
	State.dirty(player)
end

-- Product receipts: the premium track of a season (even if it just ended: the player paid).
function Season.grantPremium(player: Player, seasonId: string): boolean
	local p = Data.get(player)
	if not p or not Config.BattlePass.SeasonById[seasonId] then
		return false
	end
	record(p, seasonId).premium = true
	State.dirty(player)
	return true
end

-- Tier skip: one tier of the running season. With no season running it pays back Gems.
function Season.skipTier(player: Player): boolean
	local p = Data.get(player)
	if not p then
		return false
	end
	local season = BattlePass.active(os.time())
	if not season then
		State.addGems(player, Config.BattlePass.skipRefundGems)
		return true
	end
	local rec = record(p, season.id)
	BattlePass.addXp(rec, Config.BattlePass.xpPerTier - (rec.xp % Config.BattlePass.xpPerTier))
	State.dirty(player)
	return true
end

-- Test hook: make season s1 run from now (the real one starts 2026-10-01).
function Season.forceActive(_player: Player): boolean
	local season = Config.BattlePass.SeasonById.s1
	season.startsAt = os.time() - 60
	season.endsAt = os.time() + season.days * 86400
	return true
end

local function snapshot(_player: Player, p: Data.Profile): any
	local now = os.time()
	local season, upcoming = BattlePass.active(now)
	if not season then
		return { none = true, nextId = if upcoming then upcoming.id else nil, nextAt = if upcoming then upcoming.startsAt else nil, serverTime = now }
	end
	local rec = p.bp[season.id] or BattlePass.newRecord()
	local missing, frac = BattlePass.progress(rec.xp)
	return {
		id = season.id,
		endsAt = season.endsAt,
		xp = rec.xp,
		tier = BattlePass.tier(rec.xp),
		missing = missing,
		frac = frac,
		premium = rec.premium,
		free = rec.free,
		paid = rec.paid,
		claimable = BattlePass.claimableCount(rec, season.id),
		serverTime = now,
	}
end

function Season.init()
	State.extras.season = snapshot

	local X = Config.BattlePass.xp
	Hooks.on("npcKilled", function(player: Player, _id: string, def: any)
		Season.addXp(player, if def.world then X.worldBoss elseif def.boss then X.bossKill else 0)
	end)
	Hooks.on("arenaWin", function(player: Player)
		Season.addXp(player, X.arenaWin)
	end)
	Hooks.on("relic", function(player: Player)
		Season.addXp(player, X.relic)
	end)
	Hooks.on("questClaimed", function(player: Player, kind: string)
		Season.addXp(player, if kind == "bonus" then X.questBonus else X.questClaim)
	end)

	local function claim(player: Player, track: string, tier: number): (boolean, any)
		local p = Data.get(player)
		local season = BattlePass.active(os.time())
		if not p or not season then
			return false, M("msg.bp_no_season")
		end
		local rec = record(p, season.id)
		local ok, why = BattlePass.canClaim(rec, season.id, track, tier)
		if not ok then
			if why == "premium" then
				return false, M("msg.bp_need_premium")
			elseif why == "claimed" then
				return false, M("msg.already_claimed")
			elseif why == "locked" then
				return false, M("msg.not_ready")
			end
			return false, M("msg.bad_request")
		end
		local reward = BattlePass.reward(season.id, track, tier)
		if not reward then
			return false, M("msg.bad_request")
		end
		BattlePass.markClaimed(rec, track, tier)
		local text = Rewards.grant(player, reward)
		State.dirty(player)
		return true, text
	end

	Remotes.handle("ClaimPass", function(player, payload)
		local track, tier = payload.track, payload.tier
		if type(track) ~= "string" or type(tier) ~= "number" then
			return false, M("msg.bad_request")
		end
		return claim(player, track, tier)
	end)

	Remotes.handle("ClaimPassAll", function(player)
		local p = Data.get(player)
		local season = BattlePass.active(os.time())
		if not p or not season then
			return false, M("msg.bp_no_season")
		end
		local n = 0
		for tier = 1, Config.BattlePass.tiers do
			for _, track in { "free", "premium" } do
				local ok = claim(player, track, tier)
				if ok then
					n += 1
				end
			end
		end
		if n == 0 then
			return false, M("msg.nothing_to_claim")
		end
		return true, M("msg.bp_claimed", { n = n })
	end)

	-- time played: every 5 minutes online
	task.spawn(function()
		while true do
			task.wait(300)
			for _, player in Players:GetPlayers() do
				if State.ready[player] then
					Season.addXp(player, X.minutes)
				end
			end
		end
	end)
end

return Season
