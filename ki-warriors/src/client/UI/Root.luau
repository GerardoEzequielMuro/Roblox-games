--!strict
-- The ScreenGuis for the game UI plus resolution scaling and the touch layout flag.
-- Scaling is applied per top-level element through Root.mount (a holder frame with a
-- UIScale), because a UIScale on the ScreenGui itself would also shrink full-screen
-- layouts and edge anchoring.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local Root = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Phones/tablets: the Roblox thumbstick (bottom-left) and jump button (bottom-right) own
-- those corners, so the HUD moves to the top and panels open at the top.
-- (Studio can't emulate touch: workspace attribute ForceTouchLayout previews it.)
Root.isTouch = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) or Workspace:GetAttribute("ForceTouchLayout") == true

Root.gui = Theme.new("ScreenGui", {
	Name = "KiWarriorsUI",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- stays clear of the Roblox topbar buttons
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

-- Full-screen overlay (transformation flash, cinematics), ignores insets, drawn above everything.
Root.overlay = Theme.new("ScreenGui", {
	Name = "KiWarriorsOverlay",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

-- Smallest text (design px) TextScaled labels may shrink to: 13 * 0.85 = 11 px on a phone.
Theme.minText = if Root.isTouch then 13 else 8
Theme.minButtonH = if Root.isTouch then 52 else 0

Root.scale = 1
local scales: { UIScale } = {}
local changed = Instance.new("BindableEvent")
Root.Changed = changed.Event

-- PC: design size 1100x560 of usable (safe-area) space, capped at 1.1 on big monitors so the
-- layout stays compact.
-- Touch: the usable area of a landscape phone is only ~750x310 px, so the design size is
-- 860x365 and the scale never goes under 0.75 (0.85 on a typical phone). That keeps buttons
-- >= 44 px and text >= 11 px, at the price of a denser layout (see Hud / Menu / TouchControls).
Root.TOUCH_MIN_SCALE = 0.75
Root.area = Vector2.new(1100, 560) -- usable space in design units (screen size / scale)
local function compute(): number
	local size = Root.gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		local cam = Workspace.CurrentCamera
		if not cam then
			return 1
		end
		size = cam.ViewportSize
	end
	local s: number
	if Root.isTouch then
		s = math.clamp(math.min(size.X / 860, size.Y / 365), Root.TOUCH_MIN_SCALE, 1.1)
	else
		s = math.clamp(math.min(size.X / 1100, size.Y / 560), 0.5, 1.1)
	end
	Root.area = size / s
	return s
end

local playerListShown: boolean? = nil
local function apply()
	Root.scale = compute()
	for _, s in scales do
		s.Scale = Root.scale
	end
	-- The default player list covers the right-side HUD on small screens.
	local cam = Workspace.CurrentCamera
	local show = cam ~= nil and cam.ViewportSize.X >= 1000 and not Root.isTouch
	if show ~= playerListShown then
		playerListShown = show
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, show)
		end)
	end
	changed:Fire(Root.scale)
end

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
		Parent = parent or Root.gui,
	}) :: Frame
	local s = Theme.new("UIScale", { Scale = Root.scale, Parent = holder }) :: UIScale
	table.insert(scales, s)
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Position = UDim2.fromScale(0.5, 0.5)
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
