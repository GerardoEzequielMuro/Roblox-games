--!strict
-- Daily quests: 3 per UTC day (Shared/Quests), progress from gameplay hooks, Crystal rewards
-- and a Quantum Capsule for finishing all three. Progress is pushed with the small "Quests"
-- event (throttled) instead of full state snapshots, because hits update it many times a second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Rewards = require(script.Parent.Rewards)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local QuestService = {}

local dirty: { [Player]: boolean } = {}
local lastPush: { [Player]: number } = {}
local PUSH_INTERVAL = 2

-- Makes sure the profile holds today's quests (fresh list at the first access of a new day).
function QuestService.ensure(player: Player, forcedKinds: { string }?): Data.Profile?
	local p = Data.get(player)
	if not p then
		return nil
	end
	local day = Quests.today(os.time())
	if p.quests.day ~= day or forcedKinds then
		local list = Quests.forDay(day, State.maxZone(p))
		if forcedKinds then
			local byKind = {}
			for _, def in Config.QuestPool do
				byKind[def.kind] = def
			end
			list = {}
			for _, kind in forcedKinds do
				local def = byKind[kind]
				if def then
					table.insert(list, { kind = kind, target = def.targetByZone[math.min(State.maxZone(p), #def.targetByZone)], crystals = def.crystals })
				end
			end
		end
		p.quests = { day = day, list = list, progress = {}, claimed = {}, bonusClaimed = false }
		for i in list do
			p.quests.progress[i] = 0
			p.quests.claimed[i] = false
		end
		dirty[player] = true
	end
	return p
end

function QuestService.snapshot(player: Player): { [string]: any }?
	local p = QuestService.ensure(player)
	if not p then
		return nil
	end
	local list = {}
	for i, q in p.quests.list do
		table.insert(list, { kind = q.kind, target = q.target, crystals = q.crystals, progress = math.min(p.quests.progress[i] or 0, q.target), claimed = p.quests.claimed[i] == true })
	end
	return { list = list, bonusClaimed = p.quests.bonusClaimed, bonus = Config.QuestBonus, resetsAt = Quests.resetsAt(os.time()), serverTime = os.time() }
end

function QuestService.add(player: Player, kind: string, amount: number)
	local p = QuestService.ensure(player)
	if not p or amount <= 0 then
		return
	end
	for i, q in p.quests.list do
		if q.kind == kind and not p.quests.claimed[i] then
			local before = p.quests.progress[i] or 0
			if before < q.target then
				p.quests.progress[i] = math.min(q.target, before + amount)
				dirty[player] = true
			end
		end
	end
end

function QuestService.init()
	State.extras.quests = function(player)
		return QuestService.snapshot(player)
	end

	Hooks.on("opened", function(player: Player, results: { any })
		QuestService.add(player, "capsules", #results)
	end)
	Hooks.on("hits", function(player: Player, n: number)
		QuestService.add(player, "hits", n)
	end)
	Hooks.on("planetBroken", function(player: Player, kind: string)
		QuestService.add(player, "planets", 1)
		if kind == "titan" then
			QuestService.add(player, "titan", 1)
		end
	end)
	Hooks.on("buff", function(player: Player)
		QuestService.add(player, "buffs", 1)
	end)
	Hooks.on("fused", function(player: Player)
		QuestService.add(player, "fuse", 1)
	end)
	Hooks.on("arenaKo", function(player: Player)
		QuestService.add(player, "arena", 1)
	end)
	Hooks.on("sold", function(player: Player)
		QuestService.add(player, "sell", 1)
	end)

	Remotes.handle("ClaimQuest", function(player, payload)
		local p = QuestService.ensure(player)
		local i = payload.i
		if not p or type(i) ~= "number" or not p.quests.list[i] then
			return false, M("msg.unknown_quest")
		end
		local q = p.quests.list[i]
		if p.quests.claimed[i] then
			return false, M("msg.already_claimed")
		end
		if (p.quests.progress[i] or 0) < q.target then
			return false, M("msg.not_ready")
		end
		p.quests.claimed[i] = true
		dirty[player] = true
		return true, Rewards.grant(player, { kind = "crystals", amount = q.crystals })
	end)

	Remotes.handle("ClaimQuestBonus", function(player)
		local p = QuestService.ensure(player)
		if not p then
			return false, M("msg.error")
		end
		if p.quests.bonusClaimed then
			return false, M("msg.already_claimed")
		end
		for i in p.quests.list do
			if not p.quests.claimed[i] then
				return false, M("msg.quests_first")
			end
		end
		p.quests.bonusClaimed = true
		dirty[player] = true
		return true, Rewards.grant(player, Config.QuestBonus :: any)
	end)

	-- play-time quests + day rollover + throttled progress pushes
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.5)
			acc += 0.5
			local minute = acc >= 60
			if minute then
				acc -= 60
			end
			for _, player in Players:GetPlayers() do
				if State.ready[player] then
					if minute then
						QuestService.add(player, "minutes", 1)
					end
					QuestService.ensure(player)
					-- progress pushes: at most one every PUSH_INTERVAL per player
					local now = os.clock()
					if dirty[player] and now - (lastPush[player] or 0) >= PUSH_INTERVAL then
						dirty[player] = nil
						lastPush[player] = now
						Remotes.fire("Quests", player, QuestService.snapshot(player))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastPush[player] = nil
	end)
end

return QuestService
