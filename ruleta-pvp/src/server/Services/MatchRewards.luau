--!strict
-- Pays a player for a finished match. The reward depends on placement only and is paid by
-- the system: nobody puts anything in before the match and nobody takes anything from the
-- losers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Cosmetics = require(script.Parent.Cosmetics)
local QuestService = require(script.Parent.QuestService)
local LiveEventService = require(script.Parent.LiveEventService)
local Leaderboard = require(script.Parent.Leaderboard)
local Social = require(script.Parent.Social)

local MatchRewards = {}

export type Info = {
	mode: string,
	place: number,
	n: number,
	humans: number,
	stats: { zaps: number, elims: number, cards: number, spins: number, taken: number },
	tutorial: boolean,
	tableId: string,
}

function MatchRewards.pay(player: Player, info: Info): { [string]: any }?
	local p = Data.get(player)
	if not p then
		return nil
	end
	local won = info.place == 1
	local event = LiveEventService.effects(info.mode)
	local streakBefore = p.streak
	local r = Progression.matchRewards(info.mode, info.place, info.n, {
		coin = State.coinMult(player) * event.coinMult,
		xp = State.xpMult(player) * event.xpMult,
		streak = if won then streakBefore else 0,
		humans = info.humans,
	})
	local levelBefore = p.level
	p.matches += 1
	p.elims += info.stats.elims
	if won then
		p.wins += 1
		p.streak += 1
		p.bestStreak = math.max(p.bestStreak, p.streak)
		local week = Leaderboard.week(os.time())
		if p.weekly.week ~= week then
			p.weekly = { week = week, wins = 0 }
		end
		p.weekly.wins += 1
	else
		p.streak = 0
	end
	State.addCoins(player, r.coins)
	State.addXp(player, r.xp)
	State.addTrophies(player, r.trophies)

	QuestService.add(player, "play", 1)
	if won then
		QuestService.add(player, "win", 1)
	end
	if info.place <= 3 and info.n >= 4 then
		QuestService.add(player, "top3", 1)
	end
	QuestService.add(player, "zaps", info.stats.zaps)
	QuestService.add(player, "cards", info.stats.cards)
	QuestService.add(player, "elims", info.stats.elims)
	QuestService.add(player, "spins", info.stats.spins)
	if info.mode == "chaos" or info.mode == "teams" then
		QuestService.add(player, info.mode, 1)
	end

	local tutorialReward = false
	if not p.tutorialDone then
		p.tutorialDone = true
		tutorialReward = true
		State.addCoins(player, Config.Tutorial.coins)
		Cosmetics.grant(player, Config.Tutorial.item)
	end
	Social.onMatchFinished(player)
	if won then
		Social.maybeAskNotifications(player)
	end
	State.progressed(player)
	State.dirty(player)

	local result = {
		table = info.tableId,
		mode = info.mode,
		place = info.place,
		n = info.n,
		won = won,
		coins = r.coins,
		xp = r.xp,
		trophies = r.trophies,
		streak = p.streak,
		level = p.level,
		levelUp = p.level > levelBefore,
		stats = info.stats,
		tutorial = tutorialReward,
		tutorialCoins = if tutorialReward then Config.Tutorial.coins else 0,
		eventCoin = event.coinMult,
		eventXp = event.xpMult,
	}
	Remotes.fire("Result", player, result)
	return result
end

return MatchRewards
