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

-- Usable (safe-area) size of the HUD layer, with a viewport fallback before it is laid out.
local function areaSize(): Vector2
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

-- PC: design size 1100x560 of usable space, capped at 1.15 on big monitors so the layout
-- stays compact. Touch: the HUD is laid out for ~960x420 (Hud.luau has a compact touch
-- layout) so a landscape phone (~750x330 usable) gets ~0.75 instead of 0.55 and every
-- button is sized in design px to land at >= 44 px real.
local function compute(): number
	local size = areaSize()
	if Root.isTouch then
		return math.clamp(math.min(size.X / 960, size.Y / 420), 0.62, 1.1)
	end
	return math.clamp(math.min(size.X / 1100, size.Y / 560), 0.5, 1.15)
end

-- Design px that land at `realPx` on screen with the current HUD scale.
function Root.real(realPx: number): number
	return math.ceil(realPx / Root.scale)
end

-- Windows on touch get their own fit: scale 1 when the window fits, otherwise shrunk only as
-- much as needed, and the design height is trimmed so the window never leaves the screen
-- (window bodies scroll).
type WindowFit = { holder: Frame, scale: UIScale, w: number, h: number }
local windowFits: { WindowFit } = {}
local function fitWindow(f: WindowFit)
	local a = areaSize()
	local ws = math.clamp((a.X - 24) / (f.w + 28), 0.7, 1)
	local hh = math.min(f.h, (a.Y - 30) / ws)
	f.scale.Scale = ws
	f.holder.Size = UDim2.fromOffset(f.w, hh)
end

local playerListShown: boolean? = nil
Root.hidePlayerList = false -- set while a match is on screen
local function apply()
	Root.scale = compute()
	for _, s in scales do
		s.Scale = Root.scale
	end
	for _, f in windowFits do
		fitWindow(f)
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

-- Like mount, for the modal windows: on touch they scale by the screen fit instead of the HUD
-- scale (PC behaves exactly like mount).
function Root.mountWindow(obj: GuiObject, parent: Instance?): Frame
	local sz = obj.Size
	local holder = Root.mount(obj, parent)
	if Root.isTouch then
		local s = holder:FindFirstChildOfClass("UIScale") :: UIScale
		table.remove(scales, table.find(scales, s) :: number)
		local f: WindowFit = { holder = holder, scale = s, w = sz.X.Offset, h = sz.Y.Offset }
		table.insert(windowFits, f)
		fitWindow(f)
	end
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
