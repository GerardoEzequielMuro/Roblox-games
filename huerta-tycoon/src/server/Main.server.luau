--!strict
-- Crop Kingdom server bootstrap.
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Services = script.Parent.Services
local Validate = require(script.Parent.Security.Validate)
local Remotes = require(Services.Remotes)
local Data = require(Services.Data)
local Session = require(Services.Session)
local Weather = require(Services.Weather)
local Shop = require(Services.Shop)
local Garden = require(Services.Garden)
local Monetization = require(Services.Monetization)
local Rewards = require(Services.Rewards)
local Events = require(Services.Events)
local Social = require(Services.Social)
local AutoFarm = require(Services.AutoFarm)
local Wild = require(Services.Wild)
require(Services.Trophies)
local Leaderboard = require(Services.Leaderboard)
local WorldBuilder = require(script.Parent.World.WorldBuilder)

local world = WorldBuilder.build()
Garden.init(world)
Leaderboard.run(world.board)
Weather.run()
Shop.run()
Garden.run()
Events.run()
Social.run()
AutoFarm.run()
Wild.init(world.wildNodes)
Wild.run()
Data.startAutosave()

local function onPlayerAdded(player: Player)
	local profile = Data.load(player)
	if not player.Parent then
		return
	end
	local s = Session.create(player, profile)

	if Config.GroupId ~= 0 then
		local ok, inGroup = pcall(player.IsInGroupAsync, player, Config.GroupId)
		s.inGroup = ok and inGroup == true
	end
	Monetization.loadPasses(s)
	-- Paid random items (Lucky Seed Pack, luck boosts) are hidden where Roblox restricts them. Until the policy
	-- call answers, and if it fails, the player is treated as restricted.
	task.spawn(function()
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false then
			s.paidRandomAllowed = true
			Session.markDirty(s)
		end
	end)
	local grewOffline = Garden.applyOffline(s)
	if not Garden.assignPlot(s) then
		player:Kick(Remotes.tr(player, R("msg.serverFull")))
		return
	end
	Shop.giveCopy(s)
	Weather.broadcast(player)
	Events.send(player)
	if player.Character then
		Garden.teleportHome(s)
	end
	Session.refreshFriends()
	Session.pushNow(s)
	if not Data.isPersistent(player) then
		Remotes.notify(player, R("msg.noSave"), "error")
	end
	local welcome = if profile.totalEarned == 0 then R("msg.welcomeNew", { game = Config.GameName }) else R("msg.welcomeBack")
	Remotes.notify(player, welcome, "success")
	if grewOffline > 0 then
		-- the offline loop is the reason to come back: say it out loud
		Remotes.notify(player, R("msg.offlineGrew", { n = grewOffline }), "success")
	end
	Social.onPlayerJoined(s)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local s = Session.get(player)
	if s then
		s.profile.playTime += os.time() - s.joinedAt
		Garden.releasePlot(s)
	end
	Data.release(player)
	Session.remove(player)
	Remotes.forget(player)
	Rewards.forget(player)
	Session.refreshFriends()
end)

Remotes.handle("Hello", function(player, payload)
	local s = Session.get(player)
	if not s or s.plotIndex == 0 then
		return false, R("err.loading")
	end
	-- the client reports its auto-detected language (used until the player picks one)
	if Validate.key(payload.lang, Locale.Supported, 8) and s.autoLang ~= payload.lang then
		s.autoLang = payload.lang
		Session.markDirty(s)
	end
	-- always follow the handshake with a fresh snapshot (covers anything that changed while the reply travels)
	Session.markDirty(s)
	local cur, nxt = Events.payload()
	return true, nil, {
		state = Session.buildState(s),
		stock = s.stock,
		nextRestockAt = Shop.nextRestockAt,
		weather = { id = Weather.id(), endsAt = Weather.endsAt, nextAt = Weather.nextAt },
		liveEvent = { current = cur, next = nxt },
	}
end)

Remotes.handle("SetLanguage", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	if not Validate.key(payload.lang, Locale.Supported, 8) then
		return false, R("err.badRequest")
	end
	s.profile.lang = payload.lang
	Session.markDirty(s)
	return true
end)

Remotes.handle("GoHome", function(player)
	local s = Session.get(player)
	if s then
		Garden.teleportHome(s)
	end
	return true
end)
