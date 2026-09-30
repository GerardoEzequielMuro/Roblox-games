--!strict
-- Tap Pets Simulator: server bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local Services = script.Parent.Services
local WorldBuilder = require(script.Parent.World.WorldBuilder)
local Data = require(Services.Data)
local Remotes = require(Services.Remotes)
local State = require(Services.State)
local Pets = require(Services.Pets)
local Eggs = require(Services.Eggs)
local Tapping = require(Services.Tapping)
local Progression = require(Services.Progression)
local Rewards = require(Services.Rewards)
local Monetization = require(Services.Monetization)
local Leaderboard = require(Services.Leaderboard)
local LiveEventService = require(Services.LiveEventService)
local QuestService = require(Services.QuestService)
local Offline = require(Services.Offline)
local Social = require(Services.Social)
local Auto = require(Services.Auto)
local Plots = require(Services.Plots)
local PolicyService = game:GetService("PolicyService")

local world = WorldBuilder.build()

State.start()
Pets.init()
Eggs.init(world.eggPositions)
Tapping.init()
Progression.init(world.zoneSpawns, world.gates)
Rewards.init()
Monetization.init()
Leaderboard.init(world.boards)
LiveEventService.init()
QuestService.init()
Offline.init()
Social.init()
Auto.init()
Plots.init(world.plots)
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

local function vipTag(player: Player, char: Model)
	local head = char:WaitForChild("Head", 5)
	if not head or not State.owns(player, "VIP") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VIPTag"
	bb.Size = UDim2.fromOffset(80, 28)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 60
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "VIP"
	t.TextColor3 = Color3.fromRGB(255, 215, 60)
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Parent = t
	t.Parent = bb
	bb.Parent = head
end

local function onCharacter(player: Player, char: Model)
	task.defer(function()
		Progression.applyWalkSpeed(player)
		vipTag(player, char)
	end)
end

-- Paid random items policy (Australia, Belgium, Netherlands, UK, Brazil for some users).
-- Restricted until PolicyService answers, so nothing is ever offered by mistake.
local function loadPolicy(player: Player)
	State.paidRandomRestricted[player] = true
	for attempt = 1, 4 do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if not player.Parent then
			return
		end
		if ok and type(info) == "table" then
			State.paidRandomRestricted[player] = info.ArePaidRandomItemsRestricted == true
			State.dirty(player)
			return
		end
		task.wait(attempt * 2)
	end
end

local connections: { [Player]: RBXScriptConnection } = {}

local function onPlayerAdded(player: Player)
	State.init(player)
	task.spawn(loadPolicy, player)
	Leaderboard.setup(player)
	connections[player] = player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	Data.load(player)
	if not player.Parent then
		Data.release(player)
		return
	end
	Monetization.loadPasses(player)
	Pets.clampEquipped(player)
	Offline.compute(player) -- needs passes + equipped pets for the tap value
	QuestService.ensure(player)
	Plots.assign(player)
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
	local conn = connections[player]
	if conn then
		conn:Disconnect()
		connections[player] = nil
	end
	Plots.release(player)
	Data.release(player)
	State.cleanup(player)
	Remotes.forget(player)
	Tapping.forget(player)
	task.defer(Rewards.refreshFriends)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
