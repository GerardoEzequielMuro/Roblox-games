--!strict
-- Bright cartoony UI kit: colors, a tiny instance factory and reusable widgets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Icons = require(ReplicatedStorage.Shared.Icons)
local Lang = require(script.Parent.Parent.Lang)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.Ink = Color3.fromRGB(43, 33, 64) -- outlines / dark text
Theme.Paper = Color3.fromRGB(255, 250, 240)
Theme.PaperDark = Color3.fromRGB(240, 230, 215)
Theme.Blue = Color3.fromRGB(63, 169, 245)
Theme.Yellow = Color3.fromRGB(255, 210, 63)
Theme.Pink = Color3.fromRGB(255, 111, 181)
Theme.Green = Color3.fromRGB(92, 214, 92)
Theme.Red = Color3.fromRGB(255, 90, 90)
Theme.Purple = Color3.fromRGB(165, 105, 255)
Theme.Orange = Color3.fromRGB(255, 160, 60)
Theme.Teal = Color3.fromRGB(60, 210, 190)
Theme.Grey = Color3.fromRGB(170, 170, 185)
Theme.White = Color3.new(1, 1, 1)

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
	return Theme.new("UIStroke", { Thickness = thickness or 2, Color = Theme.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

function Theme.padding(px: number): any
	local u = UDim.new(0, px)
	return Theme.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Theme.gradient(top: Color3, bottom: Color3): any
	return Theme.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
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

function Theme.text(props: { [string]: any }): TextLabel
	local t = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.White,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Stroke" and k ~= "MaxTextSize" and k ~= "Key" and k ~= "Args" then
			(t :: any)[k] = v
		end
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

---------------------------------------------------------------------------
-- Icons: the shared image pack (Shared/Icons) when it is uploaded, the emoji otherwise.
-- Every icon slot is a TextLabel "holder": with no image id it shows the emoji exactly as
-- before; with an id the text is cleared and an ImageLabel (ScaleType Fit) fills it.
---------------------------------------------------------------------------
Theme.EMOJI_ICONS = {
	["⬆️"] = "upgrade",
	["🔁"] = "rebirth",
	["📜"] = "quest",
	["🛒"] = "shop",
	["📖"] = "book",
	["🌀"] = "teleport",
	["💌"] = "invite",
	["🎟️"] = "ticket",
	["🎁"] = "gift",
	["🐾"] = "paw",
	["👆"] = "tap",
	["💎"] = "gem",
	["🤖"] = "auto",
	["🔄"] = "auto",
	["🥚"] = "egg",
	["🍀"] = "luck",
	["⚡"] = "bolt",
	["⭐"] = "star",
	["👑"] = "crown",
	["⏱️"] = "clock",
	["⏰"] = "clock",
	["🔮"] = "orb",
	["👥"] = "group",
	["✨"] = "aura",
	["🔒"] = "lock",
	["✌️"] = "fist",
	["👟"] = "rocket",
	["🎉"] = "gift",
	["🌐"] = "planet",
	["🟣"] = "orb",
} :: { [string]: string }

-- Image for an emoji (or an explicit pack name), nil while the pack is not uploaded.
function Theme.iconImage(emoji: string, name: string?): string?
	local n = name or Theme.EMOJI_ICONS[emoji]
	return if n then Icons.get(n) else nil
end

-- Shows `emoji` (or the pack image `name`, defaulting to the emoji's mapping) in a holder label.
function Theme.setIcon(holder: TextLabel, emoji: string, name: string?)
	local img = Theme.iconImage(emoji, name)
	local image = holder:FindFirstChild("IconImage") :: ImageLabel?
	if not img then
		if image then
			image:Destroy()
		end
		if holder.Text ~= emoji then
			holder.Text = emoji
		end
		return
	end
	holder.Text = ""
	if not image then
		local created = Instance.new("ImageLabel")
		created.Name = "IconImage"
		created.BackgroundTransparency = 1
		created.ScaleType = Enum.ScaleType.Fit
		created.Size = UDim2.fromScale(1, 1)
		created.ZIndex = holder.ZIndex
		created.Parent = holder
		image = created
	end
	(image :: ImageLabel).Image = img
end

-- A new icon holder. props are TextLabel props (Size, Position, AnchorPoint, ZIndex, Parent...).
function Theme.icon(emoji: string, props: { [string]: any }?, name: string?): TextLabel
	local p = table.clone(props or {})
	p.Text = emoji
	p.Stroke = false
	p.Name = p.Name or "Icon"
	local zIndex = p.ZIndex
	p.ZIndex = nil
	local t = Theme.text(p)
	if zIndex then
		t.ZIndex = zIndex
	end
	Theme.setIcon(t, emoji, name)
	return t
end

-- Icon in front of a text: returns the prefix to put before the text. Without an image it is
-- the emoji and a space (the text looks exactly as before); with one, an image sits at the
-- label's left edge (the label gets a left padding for it) and the prefix is empty.
function Theme.lead(label: TextLabel, emoji: string, name: string?): string
	local img = Theme.iconImage(emoji, name)
	local image = label:FindFirstChild("LeadIcon") :: ImageLabel?
	if not img then
		if image then
			image:Destroy()
			local pad = label:FindFirstChild("LeadPad")
			if pad then
				pad:Destroy()
			end
		end
		return emoji .. " "
	end
	if not image then
		local h = label.AbsoluteSize.Y
		if h < 4 then
			local parent = label.Parent
			local parentH = if parent and parent:IsA("GuiObject") then parent.Size.Y.Offset else 0
			h = label.Size.Y.Offset + label.Size.Y.Scale * parentH
		end
		h = math.clamp(if h > 0 then h else 28, 14, 64)
		Theme.new("UIPadding", { Name = "LeadPad", PaddingLeft = UDim.new(0, h + 4), Parent = label })
		image = Theme.new("ImageLabel", {
			Name = "LeadIcon",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(h, h),
			Position = UDim2.new(0, -(h + 4), 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = label.ZIndex,
			Parent = label,
		})
	end
	(image :: ImageLabel).Image = img
	return ""
end

-- Removes a lead icon (for states of the same label that have no icon, like "✓ Done").
function Theme.clearLead(label: TextLabel)
	local image = label:FindFirstChild("LeadIcon")
	if image then
		image:Destroy()
	end
	local pad = label:FindFirstChild("LeadPad")
	if pad then
		pad:Destroy()
	end
end

function Theme.panel(props: { [string]: any }): Frame
	local f = Theme.new("Frame", {
		BackgroundColor3 = Theme.Paper,
		BorderSizePixel = 0,
	}, {
		Theme.corner(props.Corner or 16),
		Theme.stroke(props.StrokeThickness or 3),
		-- soft top-to-bottom shade: multiplies whatever background colour the caller sets
		Theme.new("UIGradient", { Name = "Shade", Color = ColorSequence.new(Theme.White, Color3.fromRGB(232, 228, 242)), Rotation = 90 }),
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Corner" and k ~= "StrokeThickness" then
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
-- Only these ship in content/sounds: action_*.mp3/ogg, impact_*.mp3, oof/ouch.ogg, volume_slider.ogg.
local SOUND_IDS = {
	tap = "rbxasset://sounds/volume_slider.ogg",
	click = "rbxasset://sounds/volume_slider.ogg",
	open = "rbxasset://sounds/action_jump.mp3",
	buy = "rbxasset://sounds/action_jump_land.mp3",
	hatch = "rbxasset://sounds/impact_water.mp3",
	error = "rbxasset://sounds/action_get_up.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
}
function Theme.play(name: string, volume: number?, pitch: number?)
	local id = SOUND_IDS[name]
	if not id then
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
-- Button with squash feedback
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
}

-- Chunky button face: light top, flat middle and a darker "lip" along the bottom edge.
function Theme.buttonFace(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighten(color, 0.34)),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(0.84, Theme.darken(color, 0.04)),
		ColorSequenceKeypoint.new(0.85, Theme.darken(color, 0.24)),
		ColorSequenceKeypoint.new(1, Theme.darken(color, 0.3)),
	})
end

-- Soft white highlight across the top of a rounded surface (buttons, pills, cards).
function Theme.gloss(parent: GuiObject, corner: number, alpha: number?): Frame
	local g = Theme.new("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -10, 0.4, 0),
		Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = alpha or 0.8,
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
		Size = UDim2.new(1, 8, 1, 8),
		Position = UDim2.new(0.5, 0, 0.5, 9),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(15, 10, 30),
		BackgroundTransparency = 0.68,
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
	local b = Theme.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(160, 50),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
	}, {
		Theme.corner(opts.Corner or 14),
		Theme.stroke(3),
		Theme.new("UIGradient", { Color = Theme.buttonFace(color), Rotation = 90 }),
	}) :: TextButton
	Theme.gloss(b, opts.Corner or 14)
	local label = Theme.text({
		Name = "Label",
		Text = opts.Text or "",
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 30,
		Key = opts.Key,
		Args = opts.Args,
		Parent = b,
	})
	label.ZIndex = b.ZIndex + 1
	local scale = Theme.new("UIScale", { Parent = b })
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.9 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
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
		ZIndex = 10,
		Parent = parent,
	}, { Theme.corner(12), Theme.stroke(2) })
	local t = Theme.text({ Text = "!", ZIndex = 11, Parent = f })
	t.ZIndex = 11
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

return Theme
