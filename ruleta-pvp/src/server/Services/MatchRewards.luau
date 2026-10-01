--!strict
-- Pays a player for a finished match. The reward depends on placement only and is paid by
-- the system: nobody puts anything in before the match and nobody takes anything from the
-- losers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Guard = require(ReplicatedStorage.Shared.Guard)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Cosmetics = require(script.Parent.Cosmetics)
local QuestService = require(script.Parent.QuestService)
local LiveEventService = require(script.Parent.LiveEventService)
local Leaderboard = require(script.Parent.Leaderboard)
local Social = require(script.Parent.Social)
local SeasonService = require(script.Parent.SeasonService)

local MatchRewards = {}

export type Info = {
	mode: string,
	place: number,
	n: number,
	humans: number,
	stats: { zaps: number, elims: number, cards: number, spins: number, taken: number },
	tutorial: boolean,
	tableId: string,
	repeatGroup: boolean?, -- same humans have already played each other a lot lately
}

-- The same group of humans playing each other over and over (two accounts feeding wins):
-- the first matches of the hour / day count in full, the rest pay as practice.
local REPEAT_PER_HOUR = 8
local REPEAT_PER_DAY = 40
local REPEAT_COIN_XP = 0.25
local repeats = Guard.newRepeatLimiter(REPEAT_PER_HOUR, REPEAT_PER_DAY)

-- Records one finished match of this group. True = it counts in full.
function MatchRewards.countGroup(userIds: { number }): boolean
	return Guard.countMatch(repeats, Guard.groupKey(userIds), os.time())
end

task.spawn(function()
	while true do
		task.wait(600)
		Guard.prune(repeats, os.time())
	end
end)

function MatchRewards.pay(player: Player, info: Info): { [string]: any }?
	local p = Data.get(player)
	if not p then
		return nil
	end
	local won = info.place == 1
	local event = LiveEventService.effects(info.mode)
	local streakBefore = p.streak
	local repeatGroup = info.repeatGroup == true
	local practice = info.humans <= 1 or repeatGroup
	local r = Progression.matchRewards(info.mode, info.place, info.n, {
		coin = State.coinMult(player) * event.coinMult * (if repeatGroup then REPEAT_COIN_XP else 1),
		xp = State.xpMult(player) * event.xpMult * (if repeatGroup then REPEAT_COIN_XP else 1),
		streak = if won then streakBefore else 0,
		humans = if repeatGroup then 1 else info.humans,
	})
	-- Bot tables are practice: they stop pushing trophies once past the cap, so the top
	-- leagues need real opponents.
	if practice then
		r.trophies = math.clamp(Config.PracticeTrophyCap - p.trophies, 0, r.trophies)
	end
	local levelBefore = p.level
	p.matches += 1
	p.elims += info.stats.elims
	if won then
		p.wins += 1
		p.streak += 1
		p.bestStreak = math.max(p.bestStreak, p.streak)
		-- the boards only count wins against other people
		if not practice then
			p.pvpWins += 1
			local week = Leaderboard.week(os.time())
			if p.weekly.week ~= week then
				p.weekly = { week = week, wins = 0 }
			end
			p.weekly.wins += 1
		end
	else
		p.streak = 0
	end
	State.addCoins(player, r.coins)
	State.addXp(player, r.xp)
	State.addTrophies(player, r.trophies)

	local seasonPoints = SeasonService.onMatch(player, info.place, info.n, if repeatGroup then 1 else info.humans)
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
		seasonPoints = seasonPoints,
	}
	Remotes.fire("Result", player, result)
	return result
end

return MatchRewards
