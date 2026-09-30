--!strict
-- Daily quests: 3 per UTC day (Shared/Quests), progress from gameplay hooks, gem rewards and a
-- gem bonus for finishing all three. Progress is pushed with the small "Quests" event
-- (throttled) instead of full state snapshots.
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
		local planet = State.bestPlanet(p)
		local list = Quests.forDay(day, planet)
		if forcedKinds then
			local byKind = {}
			for _, def in Config.QuestPool do
				byKind[def.kind] = def
			end
			list = {}
			for _, kind in forcedKinds do
				local def = byKind[kind]
				if def then
					table.insert(list, { kind = kind, target = def.targetByPlanet[math.min(planet, #def.targetByPlanet)], gems = def.gems })
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
		table.insert(list, { kind = q.kind, target = q.target, gems = q.gems, progress = math.min(p.quests.progress[i] or 0, q.target), claimed = p.quests.claimed[i] == true })
	end
	return { list = list, bonusClaimed = p.quests.bonusClaimed, bonus = Config.QuestBonusGems, resetsAt = Quests.resetsAt(os.time()), serverTime = os.time() }
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

-- Test hook: replace today's list with the given kinds.
function QuestService.force(player: Player, kinds: { string }): any
	QuestService.ensure(player, kinds)
	State.dirty(player)
	return QuestService.snapshot(player)
end

function QuestService.onJoin(player: Player)
	QuestService.ensure(player)
end

function QuestService.init()
	State.extras.quests = function(player)
		return QuestService.snapshot(player)
	end

	Hooks.on("reps", function(player: Player, n: number)
		QuestService.add(player, "reps", n)
	end)
	Hooks.on("npcKilled", function(player: Player, _id: string, def: any)
		QuestService.add(player, if def.boss then "boss" else "defeat", 1)
	end)
	Hooks.on("blast", function(player: Player)
		QuestService.add(player, "blasts", 1)
	end)
	Hooks.on("relic", function(player: Player)
		QuestService.add(player, "relic", 1)
	end)
	Hooks.on("arenaWin", function(player: Player)
		QuestService.add(player, "arena", 1)
	end)

	Remotes.handle("ClaimQuest", function(player, payload)
		local p = QuestService.ensure(player)
		local i = payload.i
		if not p or type(i) ~= "number" or not p.quests.list[i] then
			return false, M("msg.bad_request")
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
		State.dirty(player)
		return true, Rewards.grant(player, { kind = "gems", amount = q.gems })
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
		State.dirty(player)
		return true, Rewards.grant(player, { kind = "gems", amount = Config.QuestBonusGems })
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
					local now = os.clock()
					if dirty[player] and now - (lastPush[player] or 0) >= PUSH_INTERVAL then
						dirty[player] = nil
						lastPush[player] = now
						Remotes.fire("Quests", player, { daily = QuestService.snapshot(player) })
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
