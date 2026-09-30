--!strict
-- Window manager: one modal window at a time, pop-in animation, shared chrome (shadow,
-- glossy header, icon medallion, close button) and a dim layer over the world.
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Lang = require(script.Parent.Parent.Lang)

local Windows = {}

export type Window = {
	name: string,
	frame: Frame,
	body: Frame,
	bodyW: number, -- design size of `body` (windows lay their content out with these)
	bodyH: number,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

-- Touch windows are at most this tall (design units): Root scales them to ~0.8 on a
-- landscape phone, so 372 -> ~300 px of the ~311 px usable height. Their buttons are
-- >= 56 units tall (>= 44 px real).
Windows.TOUCH_H = 372
Windows.touch = Root.isTouch

local windows: { [string]: Window } = {}
local current: string? = nil
local changed = Instance.new("BindableEvent")
Windows.Changed = changed.Event

-- Dim layer between the world and the HUD while a window is open. It lives in its own
-- full-screen ScreenGui below the main UI, so the HUD stays bright and clickable (you can
-- jump straight to another window). Clicking the dim closes the window.
local dimGui = Theme.new("ScreenGui", {
	Name = "PlanetDim",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	DisplayOrder = -1,
	Parent = Root.gui.Parent,
}) :: ScreenGui
local dim = Theme.new("TextButton", {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(18, 12, 34),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	Parent = dimGui,
}) :: TextButton

local function setDim(on: boolean)
	if on then
		dim.Visible = true
		TweenService:Create(dim, TweenInfo.new(0.18), { BackgroundTransparency = 0.5 }):Play()
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
	local sz = size or Vector2.new(720, 470)
	local touch = Root.isTouch
	if touch then
		sz = Vector2.new(sz.X, math.min(sz.Y, Windows.TOUCH_H))
	end
	local headerH = if touch then 50 else 58
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
	Root.mount(frame, nil, true)
	Theme.shadow(frame, 22)
	local header = Theme.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerH),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
		Parent = frame,
	}, { Theme.corner(22), Theme.gradient(Theme.lighten(color, 0.3), color) })
	-- square off the header's bottom corners
	Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 21,
		Parent = header,
	}, { Theme.gradient(Theme.lighten(color, 0.04), Theme.darken(color, 0.08)) })
	Theme.gloss(header, 22, 0.82)
	-- dark rule under the header
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
		Size = UDim2.fromOffset(if touch then 62 else 70, if touch then 62 else 70),
		Position = UDim2.fromOffset(-16, if touch then -14 else -18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 23,
		Parent = frame,
	}, { Theme.corner(if touch then 31 else 35), Theme.stroke(4), Theme.gradient(Theme.White, Theme.lighten(color, 0.55)) })
	local medalIcon = Theme.glyph({ Emoji = icon, Size = UDim2.fromScale(0.66, 0.66), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = medal })
	medalIcon.ZIndex = 24
	local titleLabel = Theme.text({
		Text = "",
		Size = UDim2.new(1, -210, 0, if touch then 38 else 42),
		Position = UDim2.new(0, 68, 0, if touch then 6 else 7),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 36,
		Stroke = 3,
		Parent = header,
	})
	titleLabel.ZIndex = 22
	local function setTitle()
		titleLabel.Text = Lang.t(titleKey)
	end
	setTitle()
	Lang.Changed:Connect(setTitle)
	local close = Theme.button({
		Text = "X",
		Color = Theme.Red,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(1, 16, 0, -16),
		AnchorPoint = Vector2.new(1, 0),
		Corner = 28,
		Parent = frame,
		OnClick = function()
			Windows.close()
		end,
	})
	close.ZIndex = 30
	for _, d in close:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 31
		end
	end
	local body = Theme.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, -(headerH + 18)),
		Position = UDim2.new(0, 14, 0, headerH + 6),
		ZIndex = 21,
		Parent = frame,
	}) :: Frame
	local w: Window = { name = name, frame = frame, body = body, bodyW = sz.X - 28, bodyH = sz.Y - headerH - 18 }
	windows[name] = w
	return w
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
	Theme.play("open", 0.3)
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

return Windows
