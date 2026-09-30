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
	Name = "PlanetUI",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- stays clear of the Roblox topbar buttons
	DisplayOrder = 1, -- above Roblox's touch controls: a modal window covers the thumbstick
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

-- Full-screen overlay (capsule cinematic), ignores insets, drawn above everything.
Root.overlay = Theme.new("ScreenGui", {
	Name = "PlanetOverlay",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
}) :: ScreenGui

Root.scale = 1
-- Each mounted element: its UIScale and, for windows, the design size it has to fit in.
local scales: { { scale: UIScale, fit: Vector2? } } = {}
local changed = Instance.new("BindableEvent")
Root.Changed = changed.Event

local function usable(): Vector2
	local size = Root.gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		local cam = Workspace.CurrentCamera
		if not cam then
			return Vector2.new(1100, 560)
		end
		size = cam.ViewportSize
	end
	return size
end

-- PC: design size 1100x560 of usable (safe-area) space, capped at 1.1 on big monitors.
-- Touch: the HUD is laid out for ~940x390 design units (Hud.luau "touch" branch), which is
-- 0.8 on a landscape phone (750x311 usable): every button is >= 44 px and text >= 11 px
-- real. The floor is 0.6 so a very small phone still gets everything on screen.
local function compute(): number
	local size = usable()
	if Root.isTouch then
		return math.clamp(math.min(size.X / 940, size.Y / 390), 0.6, 1.1)
	end
	return math.clamp(math.min(size.X / 1100, size.Y / 560), 0.5, 1.1)
end

-- Scale for a window of `fit` design size. PC: same as the HUD. Touch: as big as fits the
-- usable area (windows are drawn at <= 372 design units tall on touch, see Windows.create),
-- never below the HUD scale.
local function computeFit(fit: Vector2): number
	if not Root.isTouch then
		return Root.scale
	end
	local size = usable()
	return math.clamp(math.min(size.X / (fit.X + 40), size.Y / (fit.Y + 10)), 0.6, 1.1)
end

local playerListShown: boolean? = nil
local function apply()
	Root.scale = compute()
	for _, e in scales do
		e.scale.Scale = if e.fit then computeFit(e.fit) else Root.scale
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
-- object stays free to use its own UIScale for pop animations. `asWindow`: the object is a
-- window/popup with a fixed design size; on touch it is scaled to fit the screen.
function Root.mount(obj: GuiObject, parent: Instance?, asWindow: boolean?): Frame
	local holder = Theme.new("Frame", {
		Name = obj.Name .. "Holder",
		BackgroundTransparency = 1,
		Size = obj.Size,
		Position = obj.Position,
		AnchorPoint = obj.AnchorPoint,
		ZIndex = obj.ZIndex,
		Parent = parent or Root.gui,
	}) :: Frame
	local fit = if asWindow then Vector2.new(obj.Size.X.Offset, obj.Size.Y.Offset) else nil
	local s = Theme.new("UIScale", { Scale = if fit then computeFit(fit) else Root.scale, Parent = holder }) :: UIScale
	table.insert(scales, { scale = s, fit = fit })
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
