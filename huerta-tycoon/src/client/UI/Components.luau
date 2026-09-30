--!nonstrict
-- Shared UI factories: chunky cartoon buttons, panels, labels, progress bars, badges, tweens.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local I18n = require(script.Parent.I18n)
local Sound = require(script.Parent.Sound)
local Icons = require(ReplicatedStorage.Shared.Icons)

local C = {}

function C.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className :: any)
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
		for _, ch in children do
			ch.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function C.tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function C.corner(parent: Instance, radius: number?): UICorner
	return C.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function C.round(parent: Instance): UICorner
	return C.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function C.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?, contextual: boolean?): UIStroke
	return C.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.C.Stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function C.gradient(parent: Instance, a: any, b: Color3?, rotation: number?): UIGradient
	local seq = if typeof(a) == "ColorSequence" then a else ColorSequence.new(a, b or a)
	return C.new("UIGradient", { Color = seq, Rotation = rotation or 90, Parent = parent })
end

-- Soft top-to-bottom shading so flat colors look chunky.
function C.shade(parent: Instance): UIGradient
	return C.gradient(parent, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200), 90)
end

-- Candy gloss for buttons: bright top half, a crisp step, darker bottom lip.
local GLOSS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.46, Color3.fromRGB(238, 238, 238)),
	ColorSequenceKeypoint.new(0.54, Color3.fromRGB(214, 214, 214)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 176, 176)),
})
function C.gloss(parent: Instance): UIGradient
	return C.new("UIGradient", { Name = "Gloss", Color = GLOSS, Rotation = 90, Parent = parent })
end

-- Current resting color of a C.button (its base color, or grey while disabled).
local function restColor(btn: GuiObject): Color3
	local base = btn:GetAttribute("BaseColor")
	if btn:GetAttribute("Disabled") or typeof(base) ~= "Color3" then
		return Theme.C.Grey
	end
	return base
end

function C.padding(parent: Instance, t: number, r: number?, b: number?, l: number?): UIPadding
	return C.new("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r or t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or r or t),
		Parent = parent,
	})
end

function C.list(parent: Instance, vertical: boolean, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return C.new("UIListLayout", {
		FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, gap or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Shrink-to-fit: text keeps its TextSize when it fits and shrinks (down to ~12) when a translation runs long.
function C.fitText(lbl: any)
	local maxSize = lbl.TextSize
	local cons = C.new("UITextSizeConstraint", {
		Name = "Fit",
		MaxTextSize = maxSize,
		MinTextSize = math.min(12, maxSize),
		Parent = lbl,
	})
	lbl.TextScaled = true
	lbl:GetPropertyChangedSignal("TextSize"):Connect(function()
		cons.MaxTextSize = lbl.TextSize
		cons.MinTextSize = math.min(tonumber(lbl:GetAttribute("MinText")) or 12, lbl.TextSize)
	end)
end

-- Outlined cartoon text. props override defaults; Outline=false removes the outline; NoFit=true keeps a fixed size.
-- text may be a plain string or an I18n.L(...) value (re-rendered when the language changes).
function C.label(parent: Instance?, text: any, size: UDim2?, props: { [string]: any }?): TextLabel
	local outline = true
	local fit = true
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.C.White,
		TextSize = 22,
		Size = size or UDim2.fromScale(1, 1),
		TextWrapped = true,
		Parent = parent,
	}
	if props then
		for k, v in props do
			if k == "Outline" then
				outline = v
			elseif k == "NoFit" then
				fit = not v
			else
				merged[k] = v
			end
		end
	end
	local lbl = C.new("TextLabel", merged)
	I18n.set(lbl, "Text", text)
	if fit and lbl.AutomaticSize == Enum.AutomaticSize.None then
		C.fitText(lbl)
	end
	if outline then
		local st = C.stroke(lbl, if type(outline) == "number" then outline else 2, Theme.C.Stroke, 0, true)
		st.Name = "TextOutline"
	end
	return lbl
end

-- ===== Icons: image from the shared pack when uploaded, the emoji glyph otherwise =====

-- "rbxassetid://..." for an emoji used as an icon (or an explicit pack name), nil while the pack isn't uploaded.
function C.iconImage(emoji: string?, name: string?): string?
	local key = name or (emoji and Theme.EmojiIcon[emoji])
	if not key then
		return nil
	end
	return Icons.get(key)
end

-- "<emoji> " to prefix a button/title text, or "" when the icon is drawn as an image (see C.addIcon).
function C.iconPrefix(emoji: string, name: string?, sep: string?): string
	if C.iconImage(emoji, name) then
		return ""
	end
	return emoji .. (sep or " ")
end

local ICON_PROPS = { "Name", "Position", "AnchorPoint", "ZIndex", "LayoutOrder", "Visible", "BackgroundColor3", "BackgroundTransparency" }

-- An icon slot: with the image uploaded, a transparent frame holding a centered ImageLabel (ScaleType Fit);
-- otherwise exactly C.label(parent, emoji, size, props) as before.
function C.icon(parent: Instance?, emoji: string, size: UDim2?, props: { [string]: any }?, name: string?): GuiObject
	local image = C.iconImage(emoji, name)
	if not image then
		return C.label(parent, emoji, size, props)
	end
	local slot: Frame = C.new("Frame", { Name = "Icon", Size = size or UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	if props then
		for _, k in ICON_PROPS do
			if props[k] ~= nil then
				(slot :: any)[k] = props[k]
			end
		end
	end
	C.new("ImageLabel", {
		Name = "Img",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Image = image,
		ZIndex = slot.ZIndex,
		Parent = slot,
	})
	slot.Parent = parent
	return slot
end

-- Puts the pack image on a button (left of its label, or centered when the button has no text).
-- Returns false and does nothing when the image isn't uploaded: the caller keeps the emoji in the text.
function C.addIcon(btn: GuiObject, emoji: string, name: string?, centered: boolean?): boolean
	local image = C.iconImage(emoji, name)
	if not image then
		return false
	end
	local h = if btn.Size.Y.Offset > 0 then btn.Size.Y.Offset else 40
	local side = math.floor(h * (if centered then 0.62 else 0.58))
	C.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = if centered then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5),
		Position = if centered then UDim2.fromScale(0.5, 0.5) else UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(side, side),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Image = image,
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})
	local lbl = btn:FindFirstChild("Label")
	if lbl and lbl:IsA("TextLabel") and not centered then
		lbl.Position = UDim2.fromOffset(side + 4, 0)
		lbl.Size = UDim2.new(1, -(side + 4), 1, 0)
	end
	return true
end

-- Soft drop shadow for a static HUD block: a darker sibling one step below it that follows its
-- position, size and visibility (children always draw above their parent, so it can't be a child).
function C.dropShadow(target: GuiObject, offset: number?, radius: number?): Frame
	local o = offset or 4
	local sh: Frame = C.new("Frame", {
		Name = target.Name .. "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = target.ZIndex - 1,
	})
	C.corner(sh, radius or 18)
	local function sync()
		sh.AnchorPoint = target.AnchorPoint
		sh.Position = target.Position + UDim2.fromOffset(0, o)
		sh.Size = target.Size
		sh.Visible = target.Visible
	end
	sync()
	for _, prop in { "Position", "Size", "Visible", "AnchorPoint" } do
		target:GetPropertyChangedSignal(prop):Connect(sync)
	end
	sh.Parent = target.Parent
	return sh
end

export type ButtonOpts = {
	Parent: Instance?,
	Name: string?,
	Text: any?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	TextColor: Color3?,
	TextSize: number?,
	Radius: number?,
	LayoutOrder: number?,
	StrokeThickness: number?,
	OnClick: (() -> ())?,
}

function C.button(opts: ButtonOpts): (TextButton, TextLabel)
	local color = opts.Color or Theme.C.Green
	local btn: TextButton = C.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(160, 56),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
	})
	btn:SetAttribute("BaseColor", color)
	C.corner(btn, opts.Radius or 14)
	local border = C.stroke(btn, opts.StrokeThickness or 3, Theme.darken(color, 0.45))
	border.Name = "Border"
	C.gloss(btn)
	local lbl = C.label(btn, opts.Text or "", UDim2.fromScale(1, 1), {
		Name = "Label",
		TextSize = opts.TextSize or 24,
		TextColor3 = opts.TextColor or Theme.C.White,
	})
	C.padding(lbl, 2, 6)
	local scale = C.new("UIScale", { Name = "PressScale", Parent = btn })

	-- hover = lift + brighten, pressed = squash + darken, release = spring back
	btn.MouseEnter:Connect(function()
		if not btn:GetAttribute("Disabled") then
			C.tween(scale, 0.12, { Scale = 1.06 })
			C.tween(btn, 0.12, { BackgroundColor3 = Theme.lighten(restColor(btn), 0.16) })
		end
	end)
	btn.MouseLeave:Connect(function()
		C.tween(scale, 0.12, { Scale = 1 })
		C.tween(btn, 0.12, { BackgroundColor3 = restColor(btn) })
	end)
	btn.MouseButton1Down:Connect(function()
		if not btn:GetAttribute("Disabled") then
			C.tween(scale, 0.08, { Scale = 0.9 })
			C.tween(btn, 0.08, { BackgroundColor3 = Theme.darken(restColor(btn), 0.14) })
		end
	end)
	btn.MouseButton1Up:Connect(function()
		C.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		C.tween(btn, 0.18, { BackgroundColor3 = restColor(btn) })
	end)
	btn.Activated:Connect(function()
		if btn:GetAttribute("Disabled") then
			return
		end
		scale.Scale = 0.9
		C.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		Sound.play("click")
		if opts.OnClick then
			task.spawn(opts.OnClick)
		end
	end)
	btn.Parent = opts.Parent
	return btn, lbl
end

function C.setEnabled(btn: GuiObject, enabled: boolean)
	btn:SetAttribute("Disabled", not enabled)
	local base = btn:GetAttribute("BaseColor")
	local color = if enabled and typeof(base) == "Color3" then base else Theme.C.Grey
	btn.BackgroundColor3 = color
	local border = btn:FindFirstChild("Border")
	if border and border:IsA("UIStroke") then
		border.Color = Theme.darken(color, 0.45)
	end
	local lbl = btn:FindFirstChild("Label")
	if lbl and lbl:IsA("TextLabel") then
		lbl.TextTransparency = if enabled then 0 else 0.3
	end
end

function C.setColor(btn: GuiObject, color: Color3)
	btn:SetAttribute("BaseColor", color)
	C.setEnabled(btn, not btn:GetAttribute("Disabled"))
end

function C.setText(btn: GuiObject, text: any)
	local lbl = btn:FindFirstChild("Label")
	if lbl and lbl:IsA("TextLabel") then
		I18n.set(lbl, "Text", text)
	end
end

-- White rounded card with a colored border.
function C.card(parent: Instance?, size: UDim2, borderColor: Color3?, props: { [string]: any }?): Frame
	local f = C.new("Frame", { Size = size, BackgroundColor3 = Theme.C.Card, Parent = parent })
	if props then
		for k, v in props do
			f[k] = v
		end
	end
	C.corner(f, 16)
	local st = C.stroke(f, 3, borderColor or Theme.darken(Theme.C.Panel, 0.25))
	st.Name = "Border"
	return f
end

-- Small colored pill tag like "Rare" or "Regrows".
function C.pill(parent: Instance?, text: any, color: Color3, props: { [string]: any }?): TextLabel
	local lbl = C.label(parent, text, UDim2.fromOffset(0, 24), {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		TextSize = 15,
		TextWrapped = false,
		Outline = 1.5,
	})
	if props then
		for k, v in props do
			(lbl :: any)[k] = v
		end
	end
	C.round(lbl)
	C.padding(lbl, 0, 10)
	return lbl
end

export type Bar = { frame: Frame, fill: Frame, label: TextLabel, set: (p: number) -> () }

function C.progressBar(parent: Instance?, size: UDim2, color: Color3, props: { [string]: any }?): Bar
	local frame: Frame = C.new("Frame", {
		Size = size,
		BackgroundColor3 = Color3.fromRGB(45, 40, 36),
		Parent = parent,
	})
	if props then
		for k, v in props do
			(frame :: any)[k] = v
		end
	end
	C.round(frame)
	C.stroke(frame, 2, Theme.C.Stroke)
	local fill: Frame = C.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		Parent = frame,
	})
	C.round(fill)
	C.shade(fill)
	local lbl = C.label(frame, "", UDim2.fromScale(1, 1), { TextSize = 16, ZIndex = 3 })
	local bar = { frame = frame, fill = fill, label = lbl, set = nil :: any }
	function bar.set(p: number)
		p = math.clamp(if p ~= p then 0 else p, 0, 1)
		fill.Visible = p > 0.001
		C.tween(fill, 0.2, { Size = UDim2.fromScale(p, 1) })
	end
	return bar
end

-- Red "!" notification badge in the top-right corner of parent. Hidden by default.
function C.setBadgeText(badge: Frame, text: string)
	local lbl = badge:FindFirstChildOfClass("TextLabel")
	if lbl and lbl.Text ~= text then
		lbl.Text = text
	end
end

function C.badge(parent: Instance): Frame
	local b: Frame = C.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		BackgroundColor3 = Theme.C.Red,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	C.round(b)
	C.stroke(b, 2.5, Theme.C.White)
	C.label(b, "!", UDim2.fromScale(1, 1), { TextSize = 20, ZIndex = 6 })
	local sc = C.new("UIScale", { Parent = b })
	TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.2 }):Play()
	return b
end

export type Panel = { frame: Frame, content: Frame, close: TextButton, title: TextLabel, header: Frame }

-- Standard window: cream body, colored header with emoji title, round red close button.
function C.panel(parent: Instance, opts: { Name: string, Title: any, Icon: string?, IconName: string?, Size: UDim2?, Color: Color3? }): Panel
	local color = opts.Color or Theme.C.Green
	local frame: Frame = C.new("Frame", {
		Name = opts.Name,
		Size = opts.Size or UDim2.fromOffset(660, 480),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.C.Panel,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	})
	C.corner(frame, 24)
	C.stroke(frame, 5, Theme.C.PanelEdge)
	C.gradient(frame, Color3.new(1, 1, 1), Color3.fromRGB(240, 226, 204), 90)
	C.new("UIScale", { Name = "PopScale", Parent = frame })

	local header: Frame = C.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 66),
		BackgroundColor3 = color,
		Parent = frame,
	})
	C.corner(header, 24)
	-- square the bottom corners of the header
	C.new("Frame", {
		Name = "Filler",
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -24),
		BackgroundColor3 = Theme.darken(color, 0.08),
		BorderSizePixel = 0,
		Parent = header,
	})
	C.gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(235, 235, 235), 90)
	C.new("Frame", {
		Name = "Line",
		Size = UDim2.new(1, 0, 0, 5),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.C.PanelEdge,
		BorderSizePixel = 0,
		Parent = header,
	})
	local titleText: any = opts.Title
	local titleX = 24
	local titleImage = if opts.Icon then C.iconImage(opts.Icon, opts.IconName) else nil
	if titleImage then
		-- pack icon left of the title instead of the emoji prefix
		C.new("ImageLabel", {
			Name = "TitleIcon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 20, 0.5, 0),
			Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Image = titleImage,
			ZIndex = 2,
			Parent = header,
		})
		titleX = 74
	elseif opts.Icon then
		if I18n.isLoc(titleText) then
			titleText = I18n.L(titleText.key, titleText.args, opts.Icon .. "  ")
		else
			titleText = opts.Icon .. "  " .. tostring(titleText)
		end
	end
	local title = C.label(header, titleText, UDim2.new(1, -(96 + titleX), 1, 0), {
		Position = UDim2.fromOffset(titleX, 0),
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Outline = 3,
		ZIndex = 2,
	})

	local close = C.button({
		Name = "Close",
		Parent = frame,
		Text = C.iconPrefix("✕", nil, ""),
		TextSize = 28,
		Size = UDim2.fromOffset(56, 56),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -14, 0, 14),
		Color = Theme.C.Red,
		Radius = 27,
		StrokeThickness = 4,
	})
	close.ZIndex = 5
	C.addIcon(close, "✕", nil, true)

	local content: Frame = C.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 71),
		Size = UDim2.new(1, 0, 1, -71),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	C.padding(content, 12, 16)

	return { frame = frame, content = content, close = close, title = title, header = header }
end

function C.scroller(parent: Instance, size: UDim2, position: UDim2?): ScrollingFrame
	local sf: ScrollingFrame = C.new("ScrollingFrame", {
		Size = size,
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.C.PanelEdge,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	C.padding(sf, 4, 14, 8, 4)
	return sf
end

-- Fade out every visible piece of a GUI tree (used for toasts and floating text).
function C.fadeOut(root: Instance, time: number)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local function fade(inst: Instance)
		if inst:IsA("GuiObject") then
			local props: { [string]: any } = {}
			if inst.BackgroundTransparency < 1 then
				props.BackgroundTransparency = 1
			end
			if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
				props.TextTransparency = 1
			end
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				props.ImageTransparency = 1
			end
			if next(props) then
				TweenService:Create(inst, info, props):Play()
			end
		elseif inst:IsA("UIStroke") then
			TweenService:Create(inst, info, { Transparency = 1 }):Play()
		end
	end
	fade(root)
	for _, d in root:GetDescendants() do
		fade(d)
	end
end

function C.fmtMult(n: number?): string
	n = n or 1
	local s = string.format("%.2f", n :: number)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return "x" .. s
end

return C
