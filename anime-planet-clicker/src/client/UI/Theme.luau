--!strict
-- UI kit: saturated simulator look on dark space panels. White text with a thick dark
-- outline, chunky buttons with a lip, rounded panels. No image assets: everything is
-- frames, gradients, strokes and emoji.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Lang = require(script.Parent.Parent.Lang)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.NumberFont = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
Theme.Ink = Color3.fromRGB(16, 14, 32) -- outlines
Theme.Paper = Color3.fromRGB(30, 34, 66) -- window body
Theme.PaperDark = Color3.fromRGB(20, 22, 46) -- wells / list backgrounds
Theme.PaperLight = Color3.fromRGB(52, 60, 108) -- cards
Theme.Blue = Color3.fromRGB(56, 160, 255)
Theme.Yellow = Color3.fromRGB(255, 206, 58)
Theme.Pink = Color3.fromRGB(255, 96, 170)
Theme.Green = Color3.fromRGB(64, 214, 92)
Theme.Red = Color3.fromRGB(240, 70, 80)
Theme.Purple = Color3.fromRGB(168, 96, 250)
Theme.Orange = Color3.fromRGB(255, 150, 50)
Theme.Teal = Color3.fromRGB(50, 214, 200)
Theme.Grey = Color3.fromRGB(128, 134, 160)
Theme.White = Color3.new(1, 1, 1)
Theme.Robux = Color3.fromRGB(168, 60, 240)
-- currencies: colour = meaning
Theme.Stardust = Color3.fromRGB(255, 214, 80)
Theme.Crystals = Color3.fromRGB(90, 220, 255)
Theme.Power = Color3.fromRGB(255, 100, 150)

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

function Theme.textStroke(thickness: number?): any
	return Theme.new("UIStroke", { Thickness = thickness or 2, Color = Theme.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round })
end

function Theme.padding(px: number): any
	local u = UDim.new(0, px)
	return Theme.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
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

-- Special keys: Key / Args (translation), Stroke (false or px), MaxTextSize, Italic.
function Theme.text(props: { [string]: any }): TextLabel
	local t = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.White,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Stroke" and k ~= "MaxTextSize" and k ~= "Key" and k ~= "Args" and k ~= "Italic" then
			(t :: any)[k] = v
		end
	end
	if props.Italic then
		t.FontFace = Theme.NumberFont
	end
	if props.Key then
		Lang.bind(t, props.Key, props.Args)
	end
	if props.Stroke ~= false then
		local st = Theme.textStroke(if type(props.Stroke) == "number" then props.Stroke else 2)
		st.Parent = t
	end
	local sizeConstraint = Theme.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 40, MinTextSize = 8 })
	sizeConstraint.Parent = t
	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

-- Rounded panel. Special keys: Corner, StrokeThickness, StrokeColor.
function Theme.panel(props: { [string]: any }): Frame
	local f = Theme.new("Frame", {
		BackgroundColor3 = Theme.Paper,
		BorderSizePixel = 0,
	}, { Theme.corner(props.Corner or 16), Theme.stroke(props.StrokeThickness or 3, props.StrokeColor) })
	for k, v in props do
		if k ~= "Parent" and k ~= "Corner" and k ~= "StrokeThickness" and k ~= "StrokeColor" then
			(f :: any)[k] = v
		end
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

---------------------------------------------------------------------------
-- Sounds (built-in rbxasset sounds that exist in every Roblox install)
---------------------------------------------------------------------------
local sounds: { [string]: Sound } = {}
local SOUND_IDS = {
	tap = "rbxasset://sounds/volume_slider.ogg",
	click = "rbxasset://sounds/volume_slider.ogg",
	open = "rbxasset://sounds/action_jump.mp3",
	buy = "rbxasset://sounds/action_jump_land.mp3",
	hit = "rbxasset://sounds/impact_water.mp3",
	error = "rbxasset://sounds/action_get_up.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
}
Theme.muted = false
function Theme.play(name: string, volume: number?, pitch: number?)
	local id = SOUND_IDS[name]
	if not id or Theme.muted then
		return
	end
	local snd = sounds[name]
	if not snd then
		local created = Instance.new("Sound")
		created.SoundId = id
		created.Parent = SoundService
		sounds[name] = created
		snd = created
	end
	snd.Volume = volume or 0.4
	snd.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(snd)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
export type ButtonOpts = {
	Text: string?,
	Key: string?, -- translation key (overrides Text, re-renders on language change)
	Args: { [string]: any }?,
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
	ZIndex: number?,
}

-- Chunky button face: light top, flat middle and a darker "lip" along the bottom edge.
function Theme.buttonFace(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighten(color, 0.3)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(0.84, Theme.darken(color, 0.06)),
		ColorSequenceKeypoint.new(0.85, Theme.darken(color, 0.3)),
		ColorSequenceKeypoint.new(1, Theme.darken(color, 0.36)),
	})
end

-- Soft highlight across the top of a rounded surface.
function Theme.gloss(parent: GuiObject, corner: number, alpha: number?): Frame
	return Theme.new("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -10, 0.38, 0),
		Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = alpha or 0.82,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex,
		Parent = parent,
	}, { Theme.corner(math.max(4, corner - 4)) }) :: Frame
end

-- Drop shadow behind a mounted panel: lives in the panel's holder and follows its visibility.
function Theme.shadow(panel: GuiObject, corner: number?)
	local holder = panel.Parent
	if not holder or not holder:IsA("GuiObject") then
		return
	end
	local sh = Theme.new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, 8, 1, 8),
		Position = UDim2.new(0.5, 0, 0.5, 9),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(4, 4, 14),
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
	local b = Theme.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(160, 50),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = z,
	}, {
		Theme.corner(opts.Corner or 12),
		Theme.stroke(3),
		Theme.new("UIGradient", { Color = Theme.buttonFace(color), Rotation = 90 }),
	}) :: TextButton
	Theme.gloss(b, opts.Corner or 12)
	local label = Theme.text({
		Name = "Label",
		Text = opts.Text or "",
		Size = UDim2.new(1, -12, 1, -10),
		Position = UDim2.new(0.5, 0, 0.5, -1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 28,
		Key = opts.Key,
		Args = opts.Args,
		Parent = b,
	})
	label.ZIndex = z + 1
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
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
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

-- Little red "!" badge on a button.
function Theme.badge(parent: GuiObject): Frame
	local f = Theme.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -8, 0, -8),
		BackgroundColor3 = Theme.Red,
		Visible = false,
		ZIndex = parent.ZIndex + 8,
		Parent = parent,
	}, { Theme.corner(12), Theme.stroke(2) })
	local t = Theme.text({ Text = "!", Parent = f })
	t.ZIndex = parent.ZIndex + 9
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

-- Round icon tile: two-tone disc with an emoji (the "pass icon" template).
function Theme.icon(parent: Instance, emoji: string, color: Color3, size: number): Frame
	local f = Theme.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, { Theme.corner(size), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.45), Theme.darken(color, 0.15)) }) :: Frame
	Theme.text({ Name = "Emoji", Text = emoji, Stroke = false, Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = f })
	return f
end

export type Bar = { frame: Frame, fill: Frame, label: TextLabel, set: (self: Bar, fraction: number, text: string?) -> () }

-- Progress bar with a centred label.
function Theme.bar(parent: Instance, size: UDim2, color: Color3): Bar
	local frame = Theme.new("Frame", { Name = "Bar", Size = size, BackgroundColor3 = Theme.PaperDark, Parent = parent }, { Theme.corner(10), Theme.stroke(3) }) :: Frame
	local clip = Theme.new("Frame", { Name = "Clip", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, ClipsDescendants = true, Parent = frame }, { Theme.corner(7) })
	local fill = Theme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = clip }, { Theme.corner(7), Theme.gradient(Theme.lighten(color, 0.3), Theme.darken(color, 0.1)) }) :: Frame
	local label = Theme.text({ Name = "Label", Text = "", Size = UDim2.new(1, -10, 1, -4), Position = UDim2.fromOffset(5, 2), MaxTextSize = 22, Parent = frame })
	label.ZIndex = frame.ZIndex + 2
	local bar = { frame = frame, fill = fill, label = label } :: any
	function bar:set(fraction: number, text: string?)
		local f = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(f, 1)
		if text then
			label.Text = text
		end
	end
	return bar :: Bar
end

function Theme.setBarColor(bar: Bar, color: Color3)
	local g = bar.fill:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(Theme.lighten(color, 0.3), Theme.darken(color, 0.1))
	end
end

return Theme
