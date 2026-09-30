--!strict
-- Spin Showdown: server bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local Services = script.Parent.Services
local LobbyBuilder = require(script.Parent.World.LobbyBuilder)
local Data = require(Services.Data)
local Remotes = require(Services.Remotes)
local State = require(Services.State)
local Cosmetics = require(Services.Cosmetics)
local Rewards = require(Services.Rewards)
local QuestService = require(Services.QuestService)
local Monetization = require(Services.Monetization)
local Leaderboard = require(Services.Leaderboard)
local LiveEventService = require(Services.LiveEventService)
local Social = require(Services.Social)
local CoreService = require(Services.CoreService)
local Tables = require(Services.Tables)

local world = LobbyBuilder.build()

State.start()
Cosmetics.init()
Rewards.init()
QuestService.init()
Monetization.init()
Leaderboard.init()
LiveEventService.init()
Social.init()
CoreService.init(world.corePos)
Tables.init(world)
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

local function onPlayerAdded(player: Player)
	State.init(player)
	Leaderboard.setup(player)
	player.CharacterAdded:Connect(function()
		Tables.onCharacter(player)
	end)
	Data.load(player)
	if not player.Parent then
		Data.release(player)
		return
	end
	Monetization.loadPasses(player)
	State.checkSeason(player)
	QuestService.ensure(player)
	Cosmetics.refresh(player, true)
	State.ready[player] = true
	Social.onJoin(player)
	LiveEventService.sendTo(player)
	State.sendFull(player)
	Remotes.fire("Tables", player, Tables.snapshot())
	if not Data.isPersistent(player) then
		Remotes.notify(player, Locale.m("msg.no_save"), "error")
	end
end

local function onPlayerRemoving(player: Player)
	Data.release(player)
	State.cleanup(player)
	Remotes.forget(player)
	Cosmetics.forget(player)
	CoreService.forget(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
