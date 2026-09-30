--!strict
-- Daily quests: the same 3 for everyone per UTC day (Quests.forDay), progress from the
-- match results and the Power Core, claims and the all-three bonus.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local M = Locale.m

local QuestService = {}

-- Rolls the day's quests when the day changed. `kinds` forces a list (tests / showcase).
function QuestService.ensure(player: Player, kinds: { string }?)
	local p = Data.get(player)
	if not p then
		return
	end
	local today = Quests.today(os.time())
	if p.quests.day == today and not kinds then
		return
	end
	local list = Quests.forDay(today)
	if kinds then
		list = {}
		for _, kind in kinds do
			for _, def in Config.QuestPool do
				if def.kind == kind then
					table.insert(list, { kind = def.kind, target = def.target, coins = def.coins, xp = def.xp })
				end
			end
		end
	end
	local progress, claimed = {}, {}
	for i = 1, #list do
		progress[i] = 0
		claimed[i] = false
	end
	p.quests = { day = today, list = list, progress = progress, claimed = claimed, bonusClaimed = false }
	State.dirty(player)
end

function QuestService.add(player: Player, kind: string, amount: number)
	local p = Data.get(player)
	if not p or amount <= 0 then
		return
	end
	QuestService.ensure(player)
	for i, q in p.quests.list do
		if q.kind == kind and p.quests.progress[i] < q.target then
			p.quests.progress[i] = math.min(q.target, p.quests.progress[i] + amount)
			State.dirty(player)
		end
	end
end

function QuestService.init()
	State.extras.quests = function(_player, p)
		return { day = p.quests.day, list = p.quests.list, progress = p.quests.progress, claimed = p.quests.claimed, bonusClaimed = p.quests.bonusClaimed, resetsAt = Quests.resetsAt(os.time()), bonus = Config.QuestBonus }
	end

	Remotes.handle("ClaimQuest", function(player, payload)
		local p = Data.get(player)
		local i = payload.index
		if not p or type(i) ~= "number" then
			return false, M("msg.bad_request")
		end
		QuestService.ensure(player)
		local q = p.quests.list[i]
		if not q then
			return false, M("msg.bad_request")
		end
		if p.quests.claimed[i] then
			return false, M("msg.already_claimed")
		end
		if p.quests.progress[i] < q.target then
			return false, M("msg.quest_not_done")
		end
		p.quests.claimed[i] = true
		State.addCoins(player, q.coins)
		State.addXp(player, q.xp)
		State.dirty(player)
		return true, M("reward.coins_xp", { n = q.coins, xp = q.xp })
	end)

	Remotes.handle("ClaimQuestBonus", function(player)
		local p = Data.get(player)
		if not p then
			return false, M("msg.error")
		end
		QuestService.ensure(player)
		if p.quests.bonusClaimed then
			return false, M("msg.already_claimed")
		end
		for i in p.quests.list do
			if not p.quests.claimed[i] then
				return false, M("msg.quest_not_done")
			end
		end
		p.quests.bonusClaimed = true
		State.addCoins(player, Config.QuestBonus.coins)
		State.addXp(player, Config.QuestBonus.xp)
		State.dirty(player)
		return true, M("reward.coins_xp", { n = Config.QuestBonus.coins, xp = Config.QuestBonus.xp })
	end)
end

return QuestService
