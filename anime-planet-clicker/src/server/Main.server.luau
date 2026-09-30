--!strict
-- Planet Crackers: server bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local Services = script.Parent.Services
local WorldBuilder = require(script.Parent.World.WorldBuilder)
local Data = require(Services.Data)
local Remotes = require(Services.Remotes)
local State = require(Services.State)
local Mining = require(Services.Mining)
local Pets = require(Services.Pets)
local Capsules = require(Services.Capsules)
local Rewards = require(Services.Rewards)
local Progression = require(Services.Progression)
local Auto = require(Services.Auto)
local Monetization = require(Services.Monetization)
local Leaderboard = require(Services.Leaderboard)
local LiveEventService = require(Services.LiveEventService)
local QuestService = require(Services.QuestService)
local Offline = require(Services.Offline)
local Social = require(Services.Social)
local Pvp = require(Services.Pvp)

local built = WorldBuilder.build()

State.start()
Mining.init()
Pets.init()
Capsules.init()
Rewards.init()
Progression.init()
Monetization.init()
Leaderboard.init(built.boards)
LiveEventService.init()
QuestService.init()
Offline.init()
Social.init()
Pvp.init(built.arena)
Auto.init()
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

local function onCharacter(player: Player, _char: Model)
	task.defer(function()
		Progression.applyWalkSpeed(player)
	end)
end

local function onPlayerAdded(player: Player)
	State.init(player)
	Leaderboard.setup(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	Data.load(player)
	if not player.Parent then
		Data.release(player)
		return
	end
	Monetization.loadPasses(player)
	Monetization.loadPolicy(player)
	Pets.clampEquipped(player)
	Offline.compute(player) -- needs passes + equipped pets for the income
	QuestService.ensure(player)
	State.ready[player] = true
	Social.onJoin(player)
	LiveEventService.sendTo(player)
	Rewards.refreshFriends()
	State.sendFull(player)
	if player.Character then
		onCharacter(player, player.Character)
	end
	if not Data.isPersistent(player) then
		Remotes.notify(player, Locale.m("msg.no_save"), "error")
	end
end

local function onPlayerRemoving(player: Player)
	Mining.forget(player) -- lands a drone in flight before the save
	Data.release(player)
	State.cleanup(player)
	Remotes.forget(player)
	Pvp.forget(player)
	task.defer(Rewards.refreshFriends)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
