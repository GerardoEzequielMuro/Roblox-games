--!strict
-- The Power Core on this client: taps (clicking the core or the HUD button) are batched to
-- the server, which decides what counts; the core pulses, its rings spin and the charge bar
-- fills. The widget only shows while you stand near the core in the lobby.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Net = require(script.Parent.Net)
local Audio = require(script.Parent.Audio)
local Prefs = require(script.Parent.Prefs)
local Fx = require(script.Parent.Arena.Fx)
local Hud = require(script.Parent.UI.Hud)

local CoreClient = {}

local player = Players.LocalPlayer
local pending = 0
local lastTap = 0
local corePart: BasePart? = nil
local rings: { Part } = {}
CoreClient.sent = 0
CoreClient.near = false

local function near(): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or Net.get("table") ~= nil then
		return false
	end
	local d = hrp.Position - Layout.CorePos
	return Vector3.new(d.X, 0, d.Z).Magnitude <= Config.Core.range
end

-- One tap. Local feedback is instant; the server's answer moves the bar.
function CoreClient.tap()
	if not near() then
		return
	end
	local now = os.clock()
	if now - lastTap < 1 / (Config.Core.maxTapsPerSecond + 2) then
		return
	end
	lastTap = now
	pending += 1
	Audio.play("tick", 0.35, 1.6 + math.random() * 0.3)
	local core = corePart
	if core then
		core.Size = Vector3.one * (Layout.CoreRadius * 2 + 0.9)
		TweenService:Create(core, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = Vector3.one * Layout.CoreRadius * 2 }):Play()
		Fx.shards(core.Position, Color3.fromRGB(0, 235, 255), 3, 18, { life = 0.6, size = 0.4 })
	end
end

function CoreClient.init()
	Hud.onCoreTap = CoreClient.tap
	local tapEvent = Net.event("CoreTap")
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		local deadline = os.clock() + 20
		while #CollectionService:GetTagged("PowerCore") == 0 and os.clock() < deadline do
			task.wait(0.2)
		end
		local core = CollectionService:GetTagged("PowerCore")[1]
		if not core or not core:IsA("BasePart") then
			return
		end
		corePart = core
		local click = core:FindFirstChildOfClass("ClickDetector")
		if click then
			click.MouseClick:Connect(CoreClient.tap)
		end
		-- two rings around the core (one in lite)
		for i = 1, (if Prefs.lite() then 1 else 2) do
			local ring = Instance.new("Part")
			ring.Name = "CoreRing" .. i
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Material = Enum.Material.Neon
			ring.Color = if i == 1 then Color3.fromRGB(255, 70, 205) else Color3.fromRGB(255, 205, 60)
			ring.Size = Vector3.new(0.35, 13 + i * 2.5, 13 + i * 2.5)
			ring.Transparency = 0.35
			ring.Parent = Fx.folder
			table.insert(rings, ring)
		end
	end)

	Net.event("Core").OnClientEvent:Connect(function(d)
		Hud.coreProgress(d.taps, Config.Core.tapsPerCharge)
		if d.coins > 0 and corePart then
			Fx.floatText(corePart.Position + Vector3.new(0, 6, 0), "+" .. d.coins .. " 🪙", Color3.fromRGB(255, 215, 80), 4)
			Fx.ring(Vector3.new(0, 0.6, 0), Color3.fromRGB(0, 235, 255), 6, 22, 0.7)
			Audio.play("heal", 0.4, 1.5)
		end
	end)

	-- one loop: send the batch 5 times a second, spin the rings, show / hide the widget
	local acc, slow = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		slow += dt
		if acc >= 0.2 then
			acc = 0
			if pending > 0 then
				tapEvent:FireServer(pending)
				CoreClient.sent += pending
				pending = 0
			end
		end
		if slow >= 0.25 then
			slow = 0
			local isNear = near()
			if isNear ~= CoreClient.near then
				CoreClient.near = isNear
			end
			Hud.setCoreVisible(isNear)
		end
		if CoreClient.near or not Prefs.lite() then
			local t = os.clock()
			for i, ring in rings do
				ring.CFrame = CFrame.new(Layout.CorePos) * CFrame.Angles(t * (0.5 + i * 0.25), t * 0.4 * (if i % 2 == 0 then -1 else 1), math.rad(90))
			end
		end
	end)
end

return CoreClient
