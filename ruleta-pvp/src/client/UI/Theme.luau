--!strict
-- The game-show UI kit: dark navy panels, saturated neon accents, chunky buttons. Colours, a
-- tiny instance factory and the reusable widgets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Icons = require(ReplicatedStorage.Shared.Icons)
local Lang = require(script.Parent.Parent.Lang)
local Audio = require(script.Parent.Parent.Audio)
local Prefs = require(script.Parent.Parent.Prefs)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.TitleFont = Enum.Font.LuckiestGuy
Theme.Ink = Color3.fromRGB(10, 10, 28) -- outlines
Theme.Panel = Color3.fromRGB(26, 28, 66)
Theme.Panel2 = Color3.fromRGB(40, 44, 100)
Theme.Line = Color3.fromRGB(76, 84, 170)
Theme.Cyan = Color3.fromRGB(0, 210, 245)
Theme.Pink = Color3.fromRGB(255, 70, 190)
Theme.Yellow = Color3.fromRGB(255, 205, 60)
Theme.Green = Color3.fromRGB(80, 215, 120)
Theme.Red = Color3.fromRGB(255, 84, 96)
Theme.Purple = Color3.fromRGB(165, 100, 255)
Theme.Orange = Color3.fromRGB(255, 150, 60)
Theme.Blue = Color3.fromRGB(70, 140, 255)
Theme.Grey = Color3.fromRGB(128, 134, 170)
Theme.White = Color3.new(1, 1, 1)
Theme.Dim = Color3.fromRGB(176, 182, 220) -- secondary text

-- Touch: smallest button height (design px) inside windows, which fit at ~0.85-1.0, so a
-- tap target lands at >= 44 px real. The HUD sets its own touch sizes (Root.real).
Theme.isTouch = Prefs.isTouch
Theme.TouchMin = 52
-- Smallest scaled-text size (design px) on touch; 9 on PC.
Theme.MinText = if Prefs.isTouch then 12 else 9

function Theme.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- create("Frame", { props }, { children })
function Theme.new(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className) :: any
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(r: number?): any
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, r or 14) })
end

function Theme.stroke(thickness: number?, color: Color3?): any
	return Theme.new("UIStroke", { Thickness = thickness or 3, Color = color or Theme.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function Theme.textStroke(thickness: number?, color: Color3?): any
	return Theme.new("UIStroke", { Thickness = thickness or 2, Color = color or Theme.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

function Theme.padding(px: number, py: number?): any
	local u, v = UDim.new(0, px), UDim.new(0, py or px)
	return Theme.new("UIPadding", { PaddingTop = v, PaddingBottom = v, PaddingLeft = u, PaddingRight = u })
end

function Theme.gradient(top: Color3, bottom: Color3, rotation: number?): any
	return Theme.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 })
end

function Theme.lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

function Theme.darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

function Theme.list(dir: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): any
	return Theme.new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	})
end

local TEXT_SKIP = { Parent = true, Stroke = true, MaxTextSize = true, MinTextSize = true, Key = true, Args = true, Prefix = true, Title = true }

-- Scaled text with an outline. Key/Args bind a translation; Title uses the display font.
function Theme.text(props: { [string]: any }): TextLabel
	local t = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = if props.Title then Theme.TitleFont else Theme.Font,
		TextColor3 = Theme.White,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	})
	for k, v in props do
		if not TEXT_SKIP[k] then
			(t :: any)[k] = v
		end
	end
	if props.Key then
		Lang.bind(t, props.Key, props.Args, nil, props.Prefix)
	end
	if props.Stroke ~= false then
		local st = Theme.textStroke(if type(props.Stroke) == "number" then props.Stroke else 2)
		st.Parent = t
	end
	local sizeConstraint = Theme.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 40, MinTextSize = props.MinTextSize or Theme.MinText })
	sizeConstraint.Parent = t
	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

---------------------------------------------------------------------------
-- Icons: the shared image pack when uploaded, the emoji glyph otherwise
---------------------------------------------------------------------------
-- Which pack icon stands in for which emoji (the map lives in Shared/Icons).
Theme.IconFor = Icons.emoji

-- Image for an icon name or an emoji, or nil while the pack is not uploaded.
function Theme.iconImage(nameOrEmoji: string): string?
	return Icons.get(nameOrEmoji)
end

local ICON_SKIP = { Parent = true, Icon = true, IconName = true }

-- An icon slot: an ImageLabel (ScaleType Fit) when the pack icon is uploaded, otherwise
-- the emoji as a text label exactly like before. props.Icon is the emoji; props.IconName
-- picks the pack icon (default: looked up from the emoji in Theme.IconFor).
function Theme.icon(props: { [string]: any }): GuiObject
	local emoji: string = props.Icon or ""
	local image = Icons.get(props.IconName or emoji)
	local obj: GuiObject
	if image then
		obj = Theme.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
		})
		for k, v in props do
			if not ICON_SKIP[k] then
				(obj :: any)[k] = v
			end
		end
	else
		local tp: { [string]: any } = { Name = "Icon", Text = emoji, Stroke = false }
		for k, v in props do
			if not ICON_SKIP[k] then
				tp[k] = v
			end
		end
		obj = Theme.text(tp)
	end
	if props.Parent then
		obj.Parent = props.Parent
	end
	return obj
end

local PANEL_SKIP = { Parent = true, Corner = true, StrokeThickness = true, StrokeColor = true }

function Theme.panel(props: { [string]: any }): Frame
	local f = Theme.new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, {
		Theme.corner(props.Corner or 16),
		Theme.stroke(props.StrokeThickness or 3, props.StrokeColor),
		-- soft top-lit sheen; multiplies whatever BackgroundColor3 the panel ends up with
		Theme.new("UIGradient", {
			Name = "Sheen",
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 200, 226)),
		}),
	})
	for k, v in props do
		if not PANEL_SKIP[k] then
			(f :: any)[k] = v
		end
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

function Theme.play(name: string, volume: number?, pitch: number?)
	Audio.play(name, volume, pitch)
end

---------------------------------------------------------------------------
-- Button with squash feedback
---------------------------------------------------------------------------
export type ButtonOpts = {
	Text: string?,
	Key: string?, -- translation key (overrides Text, re-renders on language change)
	Args: { [string]: any }?,
	Prefix: string?,
	Icon: string?, -- pack icon name: shown as an image left of the text (replacing Prefix) once uploaded
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
	TextSize: number?,
	Corner: number?,
	OnClick: (() -> ())?,
	Name: string?,
	Title: boolean?,
	ZIndex: number?,
	KeepSize: boolean?, -- touch: skip the TouchMin size floor (caller sized it)
}

-- Chunky button face: light top, flat middle and a darker "lip" along the bottom edge.
function Theme.buttonFace(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighten(color, 0.3)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(0.84, Theme.darken(color, 0.05)),
		ColorSequenceKeypoint.new(0.85, Theme.darken(color, 0.3)),
		ColorSequenceKeypoint.new(1, Theme.darken(color, 0.36)),
	})
end

-- Soft white highlight across the top of a rounded surface.
function Theme.gloss(parent: GuiObject, corner: number, alpha: number?): Frame
	local g = Theme.new("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -10, 0.36, 0),
		Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = alpha or 0.82,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex,
		Parent = parent,
	}, { Theme.corner(math.max(4, corner - 4)) }) :: Frame
	return g
end

-- Drop shadow behind a mounted panel: lives in the panel's holder and follows its visibility.
function Theme.shadow(panel: GuiObject, corner: number?)
	local holder = panel.Parent
	if not holder or not holder:IsA("GuiObject") then
		return
	end
	local sh = Theme.new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, 10, 1, 10),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(4, 4, 16),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = panel.ZIndex - 1,
		Visible = panel.Visible,
		Parent = holder,
	}, { Theme.corner((corner or 22) + 4) })
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		sh.Visible = panel.Visible
	end)
end

function Theme.button(opts: ButtonOpts): TextButton
	local color = opts.Color or Theme.Blue
	local z = opts.ZIndex or 1
	local size = opts.Size or UDim2.fromOffset(160, 50)
	if Theme.isTouch and not opts.KeepSize then
		-- fingers: never a button shorter than TouchMin (tall enough to tap) or narrower than it
		local h, w = size.Y, size.X
		if h.Scale == 0 and h.Offset < Theme.TouchMin then
			h = UDim.new(0, Theme.TouchMin)
		end
		if w.Scale == 0 and w.Offset < Theme.TouchMin then
			w = UDim.new(0, Theme.TouchMin)
		end
		size = UDim2.new(w, h)
	end
	local b = Theme.new("TextButton", {
		Name = opts.Name or "Button",
		Size = size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = z,
	}, {
		Theme.corner(opts.Corner or 14),
		Theme.stroke(3),
		Theme.new("UIGradient", { Color = Theme.buttonFace(color), Rotation = 90 }),
	}) :: TextButton
	Theme.gloss(b, opts.Corner or 14)
	local image = if opts.Icon then Icons.get(opts.Icon) else nil
	local label = Theme.text({
		Name = "Label",
		Text = opts.Text or "",
		Size = if image then UDim2.new(1, -44, 1, -10) else UDim2.new(1, -12, 1, -10),
		Position = if image then UDim2.new(0.5, 16, 0.5, -1) else UDim2.new(0.5, 0, 0.5, -1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 28,
		Key = opts.Key,
		Args = opts.Args,
		Prefix = if image then nil else opts.Prefix,
		Title = opts.Title,
		Parent = b,
	})
	label.ZIndex = z + 1
	if image then
		Theme.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(0, 30, 0.7, 0),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = z + 1,
			Parent = b,
		})
	end
	local scale = Theme.new("UIScale", { Parent = b })
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
	end)
	if opts.OnClick then
		local cb = opts.OnClick
		b.Activated:Connect(function()
			Theme.play("click", 0.35)
			cb()
		end)
	end
	if opts.Parent then
		b.Parent = opts.Parent
	end
	return b
end

function Theme.setButton(b: TextButton, text: string?, color: Color3?)
	local label = b:FindFirstChild("Label") :: TextLabel?
	if text and label then
		Lang.unbind(label)
		label.Text = text
	end
	if color then
		local g = b:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = Theme.buttonFace(color)
		end
	end
end

-- Pill: icon + value, used for currencies and chips.
function Theme.pill(props: { Name: string?, Icon: string, IconName: string?, Color: Color3, Size: UDim2, Parent: Instance?, LayoutOrder: number?, RightPad: number? }): (Frame, TextLabel)
	local f = Theme.new("Frame", {
		Name = props.Name or "Pill",
		Size = props.Size,
		BackgroundColor3 = Theme.Panel,
		LayoutOrder = props.LayoutOrder or 0,
	}, { Theme.corner(999), Theme.stroke(3, Theme.Ink) }) :: Frame
	local iconHolder = Theme.new("Frame", {
		Name = "IconBg",
		Size = UDim2.new(0, 0, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = props.Color,
		Parent = f,
	}, { Theme.corner(999), Theme.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }) })
	iconHolder.Size = UDim2.new(1, 0, 1, -6)
	Theme.icon({ Icon = props.Icon, IconName = props.IconName, Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = iconHolder })
	local value = Theme.text({
		Name = "Value",
		Text = "0",
		Size = UDim2.new(1, if Theme.isTouch then -(props.Size.Y.Offset + (props.RightPad or 10)) else -(52 + (props.RightPad or 0)), 1, -10),
		Position = UDim2.new(0, if Theme.isTouch then props.Size.Y.Offset - 2 else 44, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = f,
	})
	if props.Parent then
		f.Parent = props.Parent
	end
	return f, value
end

-- Little "!" badge on a button.
function Theme.badge(parent: GuiObject): Frame
	local f = Theme.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -6, 0, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Red,
		Visible = false,
		ZIndex = parent.ZIndex + 5,
		Parent = parent,
	}, { Theme.corner(11), Theme.stroke(2) })
	local t = Theme.text({ Text = "!", Parent = f })
	t.ZIndex = parent.ZIndex + 6
	local pulse = Theme.new("UIScale", { Parent = f })
	TweenService:Create(pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.22 }):Play()
	return f
end

function Theme.pop(obj: GuiObject, amount: number?)
	local s = obj:FindFirstChildOfClass("UIScale") or Theme.new("UIScale", { Parent = obj })
	local sc = s :: UIScale
	sc.Scale = amount or 1.15
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- ON / OFF toggle row used by the HUD and the settings window.
function Theme.toggle(props: { Key: string, Parent: Instance?, Size: UDim2?, LayoutOrder: number?, Get: () -> boolean, Set: (boolean) -> (), Name: string? }): (Frame, () -> ())
	local row = Theme.new("Frame", {
		Name = props.Name or "Toggle",
		Size = props.Size or UDim2.new(1, 0, 0, if Theme.isTouch then 62 else 44),
		BackgroundColor3 = Theme.Panel2,
		LayoutOrder = props.LayoutOrder or 0,
	}, { Theme.corner(12) }) :: Frame
	Theme.text({ Key = props.Key, Size = UDim2.new(1, -110, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = row })
	local b: TextButton
	local function refresh()
		local on = props.Get()
		Theme.setButton(b, if on then "ON" else "OFF", if on then Theme.Green else Theme.Grey)
	end
	b = Theme.button({
		Name = "Switch",
		Text = "OFF",
		Color = Theme.Grey,
		Size = UDim2.fromOffset(86, 36),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 20,
		Corner = 10,
		Parent = row,
		OnClick = function()
			props.Set(not props.Get())
			refresh()
		end,
	})
	refresh()
	if props.Parent then
		row.Parent = props.Parent
	end
	return row, refresh
end

return Theme
