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

-- Adds pass XP (multiplied by the catch-up bonus while behind the season pace unless `flat`).
-- Returns the XP actually added.
function Season.addXp(player: Player, amount: number, flat: boolean?): number
	local p = Data.get(player)
	local now = os.time()
	local season = BattlePass.active(now)
	if not p or not season or amount <= 0 then
		return 0
	end
	local rec = record(p, season.id)
	local before = BattlePass.tier(rec.xp)
	local xpBefore = rec.xp
	if not flat then
		amount = BattlePass.boosted(amount, BattlePass.catchUpMult(rec.xp, season, now))
	end
	BattlePass.addXp(rec, amount)
	if BattlePass.tier(rec.xp) > before then
		Remotes.notify(player, M("msg.bp_tier", { n = BattlePass.tier(rec.xp) }), "success")
	end
	State.dirty(player)
	return rec.xp - xpBefore
end

-- Weekly challenge progress (only while a season runs: the XP has nowhere to go otherwise).
local function weeklyProgress(player: Player, id: string, n: number)
	local p = Data.get(player)
	local now = os.time()
	if not p or not BattlePass.active(now) then
		return
	end
	local w = BattlePass.rollWeekly(p.bpWeekly, now)
	p.bpWeekly = w :: any
	local xp = if id == "days" then BattlePass.weeklyTouchDay(w, BattlePass.dayIndex(now)) else BattlePass.weeklyAdd(w, id, n)
	if xp then
		local got = Season.addXp(player, xp)
		Remotes.notify(player, M("msg.bp_weekly", { n = got }), "success")
	end
	State.dirty(player)
end

-- Daily first win: the first enemy defeated (or arena win) of each UTC day.
local function firstWin(player: Player)
	local p = Data.get(player)
	local now = os.time()
	if not p or not BattlePass.active(now) then
		return
	end
	local today = BattlePass.dayIndex(now)
	if p.bpFirstWin == today then
		return
	end
	p.bpFirstWin = today
	local got = Season.addXp(player, Config.BattlePass.firstWinXp)
	Remotes.notify(player, M("msg.bp_firstwin", { n = got }), "success")
	weeklyProgress(player, "days", 1)
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
	local w = BattlePass.rollWeekly(p.bpWeekly, now)
	p.bpWeekly = w :: any
	local weekly = {}
	for _, c in Config.BattlePass.weekly do
		table.insert(weekly, { id = c.id, target = c.target, xp = c.xp, have = w.prog[c.id] or 0, done = w.done[c.id] == true })
	end
	return {
		weekly = weekly,
		weekResetIn = BattlePass.weekResetIn(now),
		firstWinReady = p.bpFirstWin ~= BattlePass.dayIndex(now),
		firstWinXp = Config.BattlePass.firstWinXp,
		catchUp = BattlePass.catchUpMult(rec.xp, season, now),
		expectedTier = BattlePass.expectedTier(season, now),
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
		if def.boss then
			weeklyProgress(player, "bosses", 1)
		end
		firstWin(player)
	end)
	Hooks.on("arenaWin", function(player: Player)
		Season.addXp(player, X.arenaWin)
		firstWin(player)
	end)
	Hooks.on("relic", function(player: Player)
		Season.addXp(player, X.relic)
	end)
	Hooks.on("questClaimed", function(player: Player, kind: string)
		Season.addXp(player, if kind == "bonus" then X.questBonus else X.questClaim)
		if kind ~= "bonus" then
			weeklyProgress(player, "quests", 1)
		end
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
					weeklyProgress(player, "days", 1) -- being online counts as a day even without a fight
				end
			end
		end
	end)
end

return Season
