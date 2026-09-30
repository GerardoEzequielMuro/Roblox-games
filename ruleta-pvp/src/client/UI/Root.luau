--!strict
-- The ScreenGuis plus resolution scaling and the touch layout flag.
-- Scaling is applied per top-level element through Root.mount (a holder frame with a
-- UIScale), because a UIScale on the ScreenGui itself would also shrink full-screen
-- layouts and edge anchoring.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local Prefs = require(script.Parent.Parent.Prefs)

local Root = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Phones/tablets: the Roblox thumbstick (bottom-left) and jump button (bottom-right) own
-- those corners in the lobby, so the HUD keeps clear of them.
Root.isTouch = Prefs.isTouch

-- Below everything: the mood veil (dims the world, never the HUD).
Root.veil = Theme.new("ScreenGui", {
	Name = "SpinVeil",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	DisplayOrder = -5,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

Root.gui = Theme.new("ScreenGui", {
	Name = "SpinUI",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- stays clear of the Roblox topbar buttons
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

-- Full-screen overlay (cinematic banners, flashes), ignores insets, drawn above everything.
Root.overlay = Theme.new("ScreenGui", {
	Name = "SpinOverlay",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

Root.scale = 1
local scales: { UIScale } = {}
local changed = Instance.new("BindableEvent")
Root.Changed = changed.Event

-- Design size 1100x560 of usable (safe-area) space: ~0.8 on a 920x505 phone, capped at 1.15
-- on big monitors so the PC layout stays compact.
local function compute(): number
	local size = Root.gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		local cam = Workspace.CurrentCamera
		if not cam then
			return 1
		end
		size = cam.ViewportSize
	end
	return math.clamp(math.min(size.X / 1100, size.Y / 560), 0.5, 1.15)
end

local playerListShown: boolean? = nil
Root.hidePlayerList = false -- set while a match is on screen
local function apply()
	Root.scale = compute()
	for _, s in scales do
		s.Scale = Root.scale
	end
	-- The default player list covers the right-side HUD on small screens.
	local cam = Workspace.CurrentCamera
	local show = cam ~= nil and cam.ViewportSize.X >= 1000 and not Root.isTouch and not Root.hidePlayerList
	if show ~= playerListShown then
		playerListShown = show
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, show)
		end)
	end
	changed:Fire(Root.scale)
end
Root.apply = apply

-- Wraps a top-level GuiObject in a holder that carries the resolution UIScale. The holder
-- takes the object's Size/Position/AnchorPoint, so edge anchoring keeps working, and the
-- object stays free to use its own UIScale for pop animations.
function Root.mount(obj: GuiObject, parent: Instance?): Frame
	local holder = Theme.new("Frame", {
		Name = obj.Name .. "Holder",
		BackgroundTransparency = 1,
		Size = obj.Size,
		Position = obj.Position,
		AnchorPoint = obj.AnchorPoint,
		ZIndex = obj.ZIndex,
		Visible = true,
		Parent = parent or Root.gui,
	}) :: Frame
	local s = Theme.new("UIScale", { Scale = Root.scale, Parent = holder }) :: UIScale
	table.insert(scales, s)
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Position = UDim2.fromScale(0.5, 0.5)
	obj.Size = UDim2.fromScale(1, 1)
	obj.Parent = holder
	return holder
end

local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	apply()
end
Root.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
hookCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)

return Root
