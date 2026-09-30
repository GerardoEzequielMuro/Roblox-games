--!strict
-- First-minute tutorial: one instruction at the top of the screen, a beam from the player
-- to the objective and a bouncing arrow over it. The step lives in the profile (server);
-- this module only points the way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local PlanetField = require(script.Parent.PlanetField)
local Theme = require(script.Parent.UI.Theme)
local Root = require(script.Parent.UI.Root)
local Hud = require(script.Parent.UI.Hud)
local Toasts = require(script.Parent.UI.Toasts)

local Guide = {}

local player = Players.LocalPlayer
local ICONS = { mine = "⛏️", core = "💥", sell = "🚀", capsule = "🧬", tool = "🛠️", auto = "🤖" }
local YELLOW = Color3.fromRGB(255, 220, 70)

Guide.step = nil :: string?
Guide.target = nil :: Vector3?

local anchor = Instance.new("Part")
anchor.Name = "GuideAnchor"
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.Transparency = 1
anchor.Size = Vector3.new(1, 1, 1)
anchor.Parent = Workspace
local a1 = Instance.new("Attachment")
a1.Parent = anchor
local beam = Instance.new("Beam")
beam.Name = "GuideBeam"
beam.Attachment1 = a1
beam.Width0 = 1.4
beam.Width1 = 1.4
beam.FaceCamera = true
beam.Color = ColorSequence.new(YELLOW)
beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 0.2) })
beam.LightEmission = 1
beam.Segments = 12
beam.Enabled = false
beam.Parent = anchor

-- the arrow: a shaft and a head made of parts (it has to show at graphics quality 1)
local arrow = Instance.new("Model")
arrow.Name = "GuideArrow"
local function arrowPart(size: Vector3, offset: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = YELLOW
	p.Size = size
	p:SetAttribute("Offset", offset)
	p.Parent = arrow
	return p
end
arrowPart(Vector3.new(1.4, 3.4, 1.4), CFrame.new(0, 2.6, 0))
arrowPart(Vector3.new(3.6, 1.2, 1.4), CFrame.new(0, 0.9, 0))
arrowPart(Vector3.new(2.2, 1.0, 1.4), CFrame.new(0, 0, 0))
arrowPart(Vector3.new(0.9, 0.9, 1.4), CFrame.new(0, -0.8, 0))
arrow.Parent = nil

local function targetFor(step: string): Vector3?
	local zone = PlanetField.zone or 1
	if step == "mine" or step == "core" then
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if root then
			local view = PlanetField.nearest(root.Position, 400, false)
			if view then
				return view.pos + Vector3.new(0, view.radius + 3, 0)
			end
		end
		local p = Layout.nodePosition(zone, 3)
		return Vector3.new(p[1], p[2] + 8, p[3])
	elseif step == "sell" then
		local p = Layout.refineryPosition(zone)
		return Vector3.new(p[1], 5, p[3])
	elseif step == "capsule" then
		local p = Layout.capsulePosition(Config.Capsules[zone].id) :: { number }
		return Vector3.new(p[1], 18, p[3])
	elseif step == "tool" then
		local p = Layout.workshopPosition(zone)
		return Vector3.new(p[1], 13, p[3])
	end
	return nil
end

local pulseTarget: GuiObject? = nil

local function refresh()
	local s = Net.state
	if not s then
		return
	end
	local def = Config.Tutorial[s.tutorial]
	Guide.step = if def then def.id else nil
	if not def then
		Hud.objective = nil
		Guide.target = nil
		pulseTarget = nil
	else
		Hud.objective = { text = ICONS[def.id] .. " " .. Lang.t("tutorial." .. def.id) .. "  (" .. s.tutorial .. "/" .. #Config.Tutorial .. ")", progress = (s.tutorial - 1) / #Config.Tutorial }
		pulseTarget = if def.id == "auto" then Root.gui:FindFirstChild("Auto_mine", true) :: GuiObject? else nil
	end
	Hud.refreshObjective()
end

function Guide.init()
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
	Lang.Changed:Connect(refresh)
	Net.event("Tutorial").OnClientEvent:Connect(function(msg)
		Toasts.show("✅ " .. Lang.t("tutorial.done_" .. msg.done) .. "  " .. Lang.msg(msg.reward), "success", 3)
		Theme.play("buy", 0.5, 1.3)
		if msg.step > #Config.Tutorial then
			Toasts.milestone(Lang.t("tutorial.complete"), Lang.t("tutorial.complete_sub"), Theme.Green)
		end
	end)
	refresh()

	RunService.RenderStepped:Connect(function()
		local step = Guide.step
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		local target = if step and root then targetFor(step) else nil
		Guide.target = target
		if target and root then
			local a0 = root:FindFirstChild("RootRigAttachment") :: Attachment? or root:FindFirstChildOfClass("Attachment")
			anchor.CFrame = CFrame.new(target)
			beam.Attachment0 = a0
			beam.Enabled = a0 ~= nil and (target - root.Position).Magnitude > 14
			if arrow.Parent ~= Workspace then
				arrow.Parent = Workspace
			end
			local bob = math.sin(os.clock() * 5) * 1.2
			local base = CFrame.new(target + Vector3.new(0, 4 + bob, 0)) * CFrame.Angles(0, os.clock() * 2, 0)
			for _, p in arrow:GetChildren() do
				if p:IsA("BasePart") then
					p.CFrame = base * (p:GetAttribute("Offset") :: CFrame)
				end
			end
		else
			beam.Enabled = false
			if arrow.Parent then
				arrow.Parent = nil
			end
		end
		local pulse = pulseTarget
		if pulse and pulse.Parent then
			local sc = pulse:FindFirstChildOfClass("UIScale")
			if sc then
				sc.Scale = 1.08 + math.sin(os.clock() * 7) * 0.08
			end
		end
	end)
end

return Guide
