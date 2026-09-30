--!strict
-- Window manager: one modal window at a time, pop-in animation, shared chrome (shadow,
-- coloured header with an icon medallion, close button) and a dim layer over the world.
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Lang = require(script.Parent.Parent.Lang)

local Windows = {}

export type Window = {
	name: string,
	frame: Frame,
	body: Frame,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

local windows: { [string]: Window } = {}
local current: string? = nil
local changed = Instance.new("BindableEvent")
Windows.Changed = changed.Event

-- Dim layer between the world and the HUD while a window is open. Clicking it closes.
local dimGui = Theme.new("ScreenGui", {
	Name = "SpinDim",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	IgnoreGuiInset = true,
	DisplayOrder = -1,
	Parent = Root.gui.Parent,
}) :: ScreenGui
local dim = Theme.new("TextButton", {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(6, 6, 22),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	Parent = dimGui,
}) :: TextButton

local function setDim(on: boolean)
	if on then
		dim.Visible = true
		TweenService:Create(dim, TweenInfo.new(0.18), { BackgroundTransparency = 0.45 }):Play()
	else
		local t = TweenService:Create(dim, TweenInfo.new(0.15), { BackgroundTransparency = 1 })
		t:Play()
		t.Completed:Once(function()
			if current == nil then
				dim.Visible = false
			end
		end)
	end
end

-- Creates window chrome and returns it; the caller fills `body`. titleKey is a translation key.
function Windows.create(name: string, icon: string, titleKey: string, color: Color3, size: Vector2?): Window
	local sz = size or Vector2.new(720, 440)
	local frame = Theme.panel({
		Name = name .. "Window",
		Size = UDim2.fromOffset(sz.X, sz.Y),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		Parent = Root.gui,
		Corner = 22,
		StrokeThickness = 4,
	})
	Theme.new("UIScale", { Parent = frame })
	Root.mount(frame)
	Theme.shadow(frame, 22)
	local header = Theme.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
		Parent = frame,
	}, { Theme.corner(22), Theme.gradient(Theme.lighten(color, 0.25), Theme.darken(color, 0.1)) })
	-- square off the header's bottom corners
	Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundColor3 = Theme.darken(color, 0.12),
		BorderSizePixel = 0,
		ZIndex = 21,
		Parent = header,
	})
	Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = Theme.Ink,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = header,
	})
	-- icon medallion poking out of the top-left corner
	local medal = Theme.new("Frame", {
		Name = "Medal",
		Size = UDim2.fromOffset(68, 68),
		Position = UDim2.fromOffset(-14, -16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 23,
		Parent = frame,
	}, { Theme.corner(34), Theme.stroke(4), Theme.gradient(Theme.White, Theme.lighten(color, 0.5)) })
	local medalIcon = Theme.text({ Text = icon, Stroke = false, Size = UDim2.fromScale(0.64, 0.64), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = medal })
	medalIcon.ZIndex = 24
	local titleLabel = Theme.text({
		Name = "Title",
		Text = "",
		Title = true,
		Size = UDim2.new(1, -210, 0, 38),
		Position = UDim2.new(0, 66, 0, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 34,
		Stroke = 3,
		Parent = header,
	})
	titleLabel.ZIndex = 22
	Lang.bind(titleLabel, titleKey)
	local close = Theme.button({
		Name = "Close",
		Text = "X",
		Color = Theme.Red,
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(1, 14, 0, -14),
		AnchorPoint = Vector2.new(1, 0),
		Corner = 27,
		ZIndex = 30,
		Parent = frame,
		OnClick = function()
			Windows.close()
		end,
	})
	local gloss = close:FindFirstChild("Gloss") :: GuiObject?
	if gloss then
		gloss.ZIndex = 30
	end
	local body = Theme.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, -74),
		Position = UDim2.new(0, 14, 0, 64),
		ZIndex = 21,
		Parent = frame,
	}) :: Frame
	local w: Window = { name = name, frame = frame, body = body }
	windows[name] = w
	return w
end

function Windows.get(name: string): Window?
	return windows[name]
end

function Windows.current(): string?
	return current
end

function Windows.isOpen(name: string): boolean
	return current == name
end

function Windows.close()
	if not current then
		return
	end
	local w = windows[current]
	current = nil
	if w then
		local s = w.frame:FindFirstChildOfClass("UIScale") :: UIScale
		local t = TweenService:Create(s, TweenInfo.new(0.12), { Scale = 0.85 })
		t:Play()
		t.Completed:Once(function()
			if current ~= w.name then
				w.frame.Visible = false
			end
		end)
		if w.onClose then
			w.onClose()
		end
	end
	setDim(false)
	changed:Fire(nil)
end

function Windows.open(name: string)
	if current == name then
		return
	end
	if current then
		local prev = windows[current]
		if prev then
			prev.frame.Visible = false
			if prev.onClose then
				prev.onClose()
			end
		end
	end
	local w = windows[name]
	if not w then
		return
	end
	current = name
	local s = w.frame:FindFirstChildOfClass("UIScale") :: UIScale
	s.Scale = 0.6
	w.frame.Visible = true
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	setDim(true)
	Theme.play("whoosh", 0.25, 1.4)
	if w.onOpen then
		w.onOpen()
	end
	changed:Fire(name)
end

function Windows.toggle(name: string)
	if current == name then
		Windows.close()
	else
		Windows.open(name)
	end
end

dim.Activated:Connect(function()
	Windows.close()
end)

-- A scrolling list body (used by most windows).
function Windows.scroller(parent: Instance, size: UDim2, position: UDim2?): ScrollingFrame
	return Theme.new("ScrollingFrame", {
		Name = "Scroll",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Line,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 21,
		Parent = parent,
	}) :: ScrollingFrame
end

return Windows
