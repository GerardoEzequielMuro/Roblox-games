--!strict
-- World boss event: the Astral Titan lands in the crater on planet 1 on a UTC schedule (every
-- 30 minutes, identical in every server), scaled to the strongest player. Everyone who helped
-- is paid by contribution tier. Its hits take a fraction of the HP bar, so new and veteran
-- players can fight it together.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Npcs = require(script.Parent.Npcs)
local Rewards = require(script.Parent.Rewards)
local M = Locale.m

local W = Config.WorldBoss
local WorldBoss = {}

local site = Vector3.zero
local boss: any = nil
local endsAt = 0
local lastCycle = -1
local forced = false

local function nextSpawn(now: number): number
	return (now // W.every + 1) * W.every
end

-- Which event boss a half hour gets (same in every server).
function WorldBoss.pick(cycle: number): string
	local list = W.rotation
	return list[cycle % #list + 1]
end
local currentId = W.npc

local function payload(): { [string]: any }
	local now = os.time()
	return {
		npc = if boss then currentId else WorldBoss.pick(now // W.every + 1),
		active = boss ~= nil,
		endsAt = endsAt,
		nextAt = nextSpawn(now),
		serverTime = now,
		id = if boss then boss.f.id else 0,
		site = site,
	}
end

local function broadcast()
	Remotes.fireAll("WorldBoss", payload())
end

local function remove()
	if boss then
		local b = boss
		boss = nil
		Npcs.destroy(b)
	end
end

local function pay(npc: any)
	local contributions: { [Player]: number } = npc.f.contributions or {}
	local total = 0
	for _, d in contributions do
		total += d
	end
	for player, d in contributions do
		local p = Data.get(player)
		if p and player.Parent and total > 0 then
			local share = d / total
			for _, tier in W.tiers do
				if share >= tier.min then
					State.addGems(player, tier.gems)
					Rewards.grant(player, { kind = "sparks", amount = tier.sparkMinutes })
					p.bossKills[currentId] = (p.bossKills[currentId] or 0) + 1
					p.kills += 1
					Remotes.notify(player, M("msg.worldboss_reward", { pct = math.floor(share * 100 + 0.5), n = tier.gems }), "success")
					Hooks.fire("npcKilled", player, currentId, Config.Npcs[currentId])
					State.dirty(player)
					break
				end
			end
		end
	end
end

function WorldBoss.spawn(seconds: number?, id: string?)
	remove()
	currentId = id or WorldBoss.pick(os.time() // W.every)
	local best = 0
	local count = 0
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p and State.ready[player] then
			count += 1
			best = math.max(best, Formulas.meleeDamage(p.stats.strength, 0))
		end
	end
	local hp = Formulas.worldBossHp(best, count)
	local npc = Npcs.create(currentId, Config.WorldBossSite.planet, site, 8, hp)
	npc.persistent = true
	npc.onDeath = function(n)
		pay(n)
		Remotes.fireAll("Toast", { key = "toast.worldboss_down", args = { boss = { key = "npc." .. currentId } }, color = { 120, 255, 230 } })
		task.defer(function()
			if boss == n then
				boss = nil
				forced = false
				Npcs.destroy(n)
				broadcast()
			end
		end)
	end
	Npcs.spawn(npc)
	boss = npc
	endsAt = os.time() + (seconds or W.duration)
	Remotes.fireAll("Toast", { key = "toast.worldboss_spawn", args = { boss = { key = "npc." .. currentId } }, color = { 120, 255, 230 } })
	Remotes.fireAll("Fx", "worldBoss", { p = site })
	broadcast()
end

-- Test / admin.
function WorldBoss.force(_player: Player?, arg: any): any
	forced = true
	local seconds = if type(arg) == "table" then arg.seconds else arg
	WorldBoss.spawn(seconds or 120, if type(arg) == "table" then arg.id else W.npc)
	return if boss then { id = boss.f.id, hp = boss.f.maxHp, pos = boss.pos, npc = currentId } else nil
end

function WorldBoss.info(_player: Player?): any
	return if boss then { id = boss.f.id, hp = boss.f.hp, maxHp = boss.f.maxHp, pos = boss.pos, alive = boss.f.alive } else nil
end

function WorldBoss.onReady(player: Player)
	Remotes.fire("WorldBoss", player, payload())
end

function WorldBoss.init(world: { [string]: any })
	site = world.worldBossCenter or Vector3.zero
	State.extras.worldBoss = function()
		return payload()
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			local cycle = now // W.every
			if boss then
				if now >= endsAt then
					remove()
					forced = false
					Remotes.fireAll("Toast", { key = "toast.worldboss_gone", args = { boss = { key = "npc." .. currentId } }, color = { 120, 140, 200 } })
					broadcast()
				end
			elseif not forced and cycle ~= lastCycle and lastCycle ~= -1 and #Players:GetPlayers() > 0 then
				-- a new half hour just started
				WorldBoss.spawn(W.duration)
			end
			lastCycle = cycle
		end
	end)
end

return WorldBoss
