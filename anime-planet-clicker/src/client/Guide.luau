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
local TutorialFlow = require(ReplicatedStorage.Shared.TutorialFlow)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local PlanetField = require(script.Parent.PlanetField)
local Theme = require(script.Parent.UI.Theme)
local Root = require(script.Parent.UI.Root)
local Hud = require(script.Parent.UI.Hud)
local Toasts = require(script.Parent.UI.Toasts)
local Feel = require(script.Parent.Feel)

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

-- Where the arrow goes for a hint target ("planet" | "refinery" | "capsule" | "workshop" |
-- "autoButton" | "fallback"). Never errors: a missing planet or capsule falls back to the
-- plaza so the arrow always points somewhere useful.
local function targetFor(kind: string): Vector3?
	local zone = PlanetField.zone or 1
	local function plaza(): Vector3
		local p = Layout.refineryPosition(zone)
		return Vector3.new(p[1], 5, p[3])
	end
	if kind == "planet" then
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
	elseif kind == "refinery" then
		return plaza()
	elseif kind == "capsule" then
		local cap = Config.Capsules[zone]
		local p = if cap then Layout.capsulePosition(cap.id) else nil
		if p then
			return Vector3.new(p[1], 18, p[3])
		end
		return plaza()
	elseif kind == "workshop" then
		local p = Layout.workshopPosition(zone)
		return Vector3.new(p[1], 13, p[3])
	elseif kind == "autoButton" then
		return nil -- a screen button: pulsed in the HUD, no world arrow
	end
	return plaza()
end

-- Is there a live planet to point at right now?
local function planetFound(): boolean
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	return root ~= nil and PlanetField.nearest(root.Position, 400, false) ~= nil
end

local pulseTarget: GuiObject? = nil
local clock = TutorialFlow.newClock()
local hintTarget = "fallback"
local loud = false
local skipChip: TextButton? = nil

local function stepNeedDust(s: { [string]: any }, id: string): number?
	if id == "tool" then
		local nextTool = Config.Tools[(Config.ToolIndex[s.tool] or 1) + 1]
		return if nextTool then nextTool.cost else nil
	elseif id == "capsule" then
		local cap = Config.Capsules[PlanetField.zone or 1]
		return if cap and not (cap :: any).exclusive then cap.price else nil
	end
	return nil
end

-- Small "Skip" chip under the objective pill; only shown once the player has been on one step
-- for a while. The server keeps the step, so rejoining resumes it; Skip ends it for good.
local function ensureChip(): TextButton?
	if skipChip and skipChip.Parent then
		return skipChip
	end
	local obj = Root.gui:FindFirstChild("Objective", true) :: GuiObject?
	if not obj then
		return nil
	end
	local chip = Theme.button({ Name = "TutorialSkip", Key = "tutorial.skip", Color = Theme.Grey, Size = UDim2.fromOffset(150, if Root.isTouch then 56 else 30), Position = UDim2.new(1, 0, 1, 6), AnchorPoint = Vector2.new(1, 0), TextSize = 16, Corner = 10, ZIndex = 5, Parent = obj, OnClick = function()
		Net.request("SkipTutorial")
	end })
	chip.Visible = false
	skipChip = chip
	return chip
end

local function refresh()
	local s = Net.state
	if not s then
		return
	end
	local def = Config.Tutorial[s.tutorial]
	Guide.step = if def then def.id else nil
	local elapsed = clock.tick(Guide.step, os.clock())
	if not def then
		Hud.objective = nil
		Guide.target = nil
		pulseTarget = nil
		hintTarget = "fallback"
		loud = false
		if skipChip then
			skipChip.Visible = false
		end
	else
		local cargo = s.cargo
		local hint = TutorialFlow.hint({
			step = def.id,
			elapsed = elapsed,
			cargo = if cargo then cargo.count + (cargo.transit or 0) else 0,
			stardust = s.stardust,
			needDust = stepNeedDust(s, def.id),
			targetFound = planetFound(),
		})
		hintTarget, loud = hint.target, hint.loud
		local text = ICONS[def.id] .. " " .. Lang.t("tutorial." .. def.id)
		if hint.reasonKey then
			text = "👉 " .. Lang.t(hint.reasonKey)
		end
		Hud.objective = { text = text .. "  (" .. s.tutorial .. "/" .. #Config.Tutorial .. ")", progress = TutorialFlow.progress(s.tutorial, #Config.Tutorial) }
		pulseTarget = if def.id == "auto" then Root.gui:FindFirstChild("Auto_mine", true) :: GuiObject? else nil
		local chip = ensureChip()
		if chip then
			chip.Visible = hint.skip
		end
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
		local last = msg.step > #Config.Tutorial
		Feel.sparkleSelf(YELLOW, if last then 36 else 18)
		Feel.shake(if last then "big" else "crit")
		if last then
			Toasts.milestone(Lang.t("tutorial.complete"), Lang.t("tutorial.complete_sub"), Theme.Green)
		end
	end)
	refresh()

	-- re-evaluate a few times a second: time on the step, cargo, a planet streaming in
	task.spawn(function()
		while true do
			task.wait(0.4)
			refresh()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local step = Guide.step
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		local target = if step and root then targetFor(hintTarget) else nil
		Guide.target = target
		if target and root then
			local a0 = root:FindFirstChild("RootRigAttachment") :: Attachment? or root:FindFirstChildOfClass("Attachment")
			anchor.CFrame = CFrame.new(target)
			beam.Attachment0 = a0
			beam.Enabled = a0 ~= nil and (target - root.Position).Magnitude > 14
			if arrow.Parent ~= Workspace then
				arrow.Parent = Workspace
			end
			-- after a few seconds on one step the arrow bobs wider and faster
			local bob = math.sin(os.clock() * (if loud then 8 else 5)) * (if loud then 2 else 1.2)
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
