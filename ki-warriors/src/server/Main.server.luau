--!strict
-- Ki Warriors: server bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local Services = script.Parent.Services
local WorldBuilder = require(script.Parent.World.WorldBuilder)
local Data = require(Services.Data)
local Remotes = require(Services.Remotes)
local State = require(Services.State)
local Fighters = require(Services.Fighters)
local Combat = require(Services.Combat)
local Training = require(Services.Training)
local Npcs = require(Services.Npcs)
local Auto = require(Services.Auto)
local Progression = require(Services.Progression)

local world = WorldBuilder.build()

State.start()
Fighters.init()
Combat.init()
Training.init()
Npcs.init()
Auto.init()
Progression.init()
-- Optional services (added round by round); each one exposes init(world).
for _, name in { "Arena", "Rewards", "Story", "QuestService", "Relics", "Auras", "WorldBoss", "LiveEventService", "Items", "Cosmetics", "Season", "Monetization", "Leaderboard", "Offline", "Social", "Guard" } do
	local module = Services:FindFirstChild(name)
	if module then
		local service = (require :: any)(module)
		service.init(world)
	end
end
Data.startAutosave()

Remotes.handle("GetState", function(player)
	if not State.ready[player] then
		return false, "loading"
	end
	return true, State.snapshot(player)
end)

-- Language preference ("" = follow the Roblox account locale).
Remotes.handle("SetLanguage", function(player, payload)
	local p = Data.get(player)
	local code = payload.lang
	if not p or type(code) ~= "string" or (code ~= "" and not Locale.Supported[code]) then
		return false, Locale.m("msg.unknown_language")
	end
	p.lang = code
	State.dirty(player)
	return true
end)

local function optional(name: string): any
	local module = Services:FindFirstChild(name)
	return if module then (require :: any)(module) else nil
end

local function onCharacter(player: Player, char: Model)
	local f = Fighters.addPlayer(player)
	Fighters.bindCharacter(f, char)
	local p = Data.get(player)
	if p and State.ready[player] then
		char:SetAttribute("Race", p.race)
		char:SetAttribute("Aura", p.auraEquipped)
		char:SetAttribute("Rebirths", p.rebirths)
		char:SetAttribute("VIP", State.owns(player, "VIP"))
		char:SetAttribute("Skin", p.skin)
		char:SetAttribute("Mount", p.mount)
		Training.applyMovement(player)
		Progression.placeOnSpawn(player)
	end
end

local function onPlayerAdded(player: Player)
	State.init(player)
	Fighters.addPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	Data.load(player)
	if not player.Parent then
		Data.release(player)
		return
	end
	local Monetization = optional("Monetization")
	if Monetization then
		Monetization.loadPasses(player)
	end
	for _, name in { "Offline", "QuestService", "Story" } do
		local s = optional(name)
		if s and s.onJoin then
			s.onJoin(player)
		end
	end
	State.ready[player] = true
	for _, name in { "Social", "LiveEventService", "Leaderboard", "Arena", "WorldBoss", "Auras", "Cosmetics" } do
		local s = optional(name)
		if s and s.onReady then
			s.onReady(player)
		end
	end
	Combat.refreshForms(player)
	State.sendFull(player)
	if player.Character then
		onCharacter(player, player.Character)
	end
	if not Data.isPersistent(player) then
		Remotes.notify(player, Locale.m("msg.no_save"), "error")
	end
end

local function onPlayerRemoving(player: Player)
	Data.release(player)
	State.cleanup(player)
	Remotes.forget(player)
	Training.forget(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
