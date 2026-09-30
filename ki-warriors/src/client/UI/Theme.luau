--!nonstrict
-- Anime-fighter UI kit: dark glass panels, thick outlines, loud accent colours, chunky
-- buttons. Everything is UICorner / UIStroke / UIGradient: no image assets.
local TweenService = game:GetService("TweenService")

local Lang = require(script.Parent.Parent.Lang)
local Fx = require(script.Parent.Parent.Fx)

local Theme = {}

Theme.Font = Enum.Font.GothamBlack
Theme.FontBold = Enum.Font.GothamBold
Theme.Display = Enum.Font.Bangers -- numbers and short Latin words
Theme.Ink = Color3.fromRGB(18, 14, 34) -- outlines
Theme.Panel = Color3.fromRGB(30, 26, 56)
Theme.PanelLight = Color3.fromRGB(52, 46, 92)
Theme.PanelDark = Color3.fromRGB(18, 15, 36)
Theme.Text = Color3.fromRGB(255, 255, 255)
Theme.Dim = Color3.fromRGB(176, 172, 206)
Theme.Orange = Color3.fromRGB(255, 138, 40)
Theme.Yellow = Color3.fromRGB(255, 214, 64)
Theme.Red = Color3.fromRGB(255, 78, 84)
Theme.Green = Color3.fromRGB(96, 224, 110)
Theme.Cyan = Color3.fromRGB(64, 198, 255)
Theme.Blue = Color3.fromRGB(76, 126, 255)
Theme.Purple = Color3.fromRGB(176, 104, 255)
Theme.Pink = Color3.fromRGB(255, 96, 176)
Theme.Grey = Color3.fromRGB(120, 116, 150)
Theme.White = Color3.new(1, 1, 1)

function Theme.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- new("Frame", { props }, { children })
function Theme.new(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className)
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
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, r or 12) })
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

-- Text label. Extra props: Key/Args (translation), Stroke (false | thickness), MaxTextSize.
function Theme.text(props: { [string]: any }): TextLabel
	local t = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Text,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Stroke" and k ~= "MaxTextSize" and k ~= "Key" and k ~= "Args" then
			t[k] = v
		end
	end
	if props.Key then
		Lang.bind(t, props.Key, props.Args)
	end
	if props.Stroke ~= false then
		Theme.textStroke(if type(props.Stroke) == "number" then props.Stroke else 2).Parent = t
	end
	Theme.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 36, MinTextSize = 8, Parent = t })
	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

-- Dark glass panel with an ink outline. Extra props: Corner, StrokeThickness, Accent (top edge colour).
function Theme.panel(props: { [string]: any }): Frame
	local f = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	}, {
		Theme.corner(props.Corner or 14),
		Theme.stroke(props.StrokeThickness or 3),
		Theme.gradient(props.Top or Theme.PanelLight, props.Bottom or Theme.PanelDark),
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Corner" and k ~= "StrokeThickness" and k ~= "Accent" and k ~= "Top" and k ~= "Bottom" then
			f[k] = v
		end
	end
	if props.Accent then
		Theme.new("Frame", {
			Name = "Accent",
			Size = UDim2.new(1, -16, 0, 4),
			Position = UDim2.new(0, 8, 0, 3),
			BackgroundColor3 = props.Accent,
			BorderSizePixel = 0,
			ZIndex = (props.ZIndex or 1) + 1,
			Parent = f,
		}, { Theme.corner(2) })
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

function Theme.play(name: string, volume: number?, pitch: number?)
	Fx.sound(name, volume, pitch)
end

-- Chunky button face: light top, flat middle and a darker lip along the bottom edge.
function Theme.buttonFace(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighten(color, 0.36)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(0.84, Theme.darken(color, 0.06)),
		ColorSequenceKeypoint.new(0.85, Theme.darken(color, 0.3)),
		ColorSequenceKeypoint.new(1, Theme.darken(color, 0.36)),
	})
end

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
	}, { Theme.corner(math.max(4, corner - 4)) })
end

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
		BackgroundColor3 = Color3.fromRGB(8, 6, 18),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = panel.ZIndex - 1,
		Visible = panel.Visible,
		Parent = holder,
	}, { Theme.corner((corner or 22) + 4) })
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		sh.Visible = panel.Visible
	end)
end

export type ButtonOpts = {
	Text: string?,
	Key: string?,
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
	Icon: string?,
	ZIndex: number?,
}

function Theme.button(opts: ButtonOpts): TextButton
	local color = opts.Color or Theme.Blue
	local corner = opts.Corner or 12
	local b = Theme.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(160, 48),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = opts.ZIndex or 1,
	}, {
		Theme.corner(corner),
		Theme.stroke(3),
		Theme.new("UIGradient", { Color = Theme.buttonFace(color), Rotation = 90 }),
	})
	Theme.gloss(b, corner)
	local hasIcon = opts.Icon ~= nil
	if hasIcon then
		local icon = Theme.text({
			Name = "Icon",
			Text = opts.Icon,
			Stroke = false,
			Size = UDim2.new(0, 30, 1, -12),
			Position = UDim2.new(0, 8, 0.5, -1),
			AnchorPoint = Vector2.new(0, 0.5),
			MaxTextSize = 26,
			Parent = b,
		})
		icon.ZIndex = b.ZIndex + 1
	end
	local label = Theme.text({
		Name = "Label",
		Text = opts.Text or "",
		Size = if hasIcon then UDim2.new(1, -46, 1, -10) else UDim2.new(1, -12, 1, -10),
		Position = if hasIcon then UDim2.new(0, 40, 0.5, -1) else UDim2.new(0.5, 0, 0.5, -1),
		AnchorPoint = if hasIcon then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 26,
		Key = opts.Key,
		Args = opts.Args,
		Parent = b,
	})
	label.ZIndex = b.ZIndex + 1
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
	local label = b:FindFirstChild("Label")
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

-- Progress bar: returns the frame and a setter (fraction 0..1, optional text).
function Theme.bar(props: { [string]: any }): (Frame, (number, string?) -> ())
	local color: Color3 = props.Color or Theme.Green
	local back = Theme.new("Frame", {
		Name = props.Name or "Bar",
		Size = props.Size or UDim2.fromOffset(200, 22),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Theme.corner(props.Corner or 8), Theme.stroke(props.Stroke or 2.5) })
	local clip = Theme.new("Frame", { Name = "Clip", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Parent = back }, { Theme.corner(props.Corner or 8) })
	local fill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = clip,
	}, {
		Theme.corner(props.Corner or 8),
		Theme.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.lighten(color, 0.45)),
				ColorSequenceKeypoint.new(0.5, color),
				ColorSequenceKeypoint.new(1, Theme.darken(color, 0.25)),
			}),
			Rotation = 90,
		}),
	})
	local label = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, -8, 1, -2), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), MaxTextSize = props.TextSize or 16, Font = Theme.FontBold, Parent = back })
	label.ZIndex = 3
	local shown = -1
	local function set(frac: number, text: string?)
		frac = math.clamp(frac, 0, 1)
		if math.abs(frac - shown) > 0.002 then
			shown = frac
			TweenService:Create(fill, TweenInfo.new(0.12), { Size = UDim2.fromScale(frac, 1) }):Play()
		end
		if text and label.Text ~= text then
			label.Text = text
		end
	end
	return back, set
end

function Theme.setBarColor(bar: Frame, color: Color3)
	local fill = bar:FindFirstChild("Fill", true)
	local g = fill and fill:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.lighten(color, 0.45)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, Theme.darken(color, 0.25)),
		})
	end
end

-- Little red "!" badge on a button.
function Theme.badge(parent: GuiObject): Frame
	local f = Theme.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -6, 0, -6),
		BackgroundColor3 = Theme.Red,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	}, { Theme.corner(11), Theme.stroke(2) })
	local t = Theme.text({ Text = "!", Parent = f })
	t.ZIndex = 11
	local pulse = Theme.new("UIScale", { Parent = f })
	TweenService:Create(pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.22 }):Play()
	return f
end

function Theme.pop(obj: GuiObject, amount: number?)
	local s = obj:FindFirstChildOfClass("UIScale") or Theme.new("UIScale", { Parent = obj })
	s.Scale = amount or 1.15
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

return Theme
