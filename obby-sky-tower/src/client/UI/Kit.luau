--!strict
-- Cartoony UI kit: palette, builders, screen regions that scale with the viewport
-- (UIScale per region, bigger on touch devices), and a one-panel-at-a-time modal system.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Lang = require(script.Parent.Parent.Lang)

local Kit = {}

---------------------------------------------------------------------------------------------
-- Localized text: any text passed to the builders as "@some.key" is translated, and every
-- object set through Kit.setText is re-translated live when the language changes.
---------------------------------------------------------------------------------------------
type Bound = { key: string, args: { [string]: any }?, prop: string }
-- Strong table (Instance keys in weak tables get dropped while the Instance is still alive);
-- entries are removed when the object is destroyed.
local bound: { [Instance]: Bound } = {}

local function applyBound(obj: Instance, b: Bound)
	(obj :: any)[b.prop] = Lang.t(b.key, b.args)
end

function Kit.setText(obj: Instance, key: string, args: { [string]: any }?, prop: string?)
	local b = { key = key, args = args, prop = prop or "Text" }
	if not bound[obj] then
		obj.Destroying:Once(function()
			bound[obj] = nil
		end)
	end
	bound[obj] = b
	applyBound(obj, b)
end

-- Plain (untranslated) text, e.g. numbers; drops any key bound to the object.
function Kit.setRaw(obj: Instance, text: string)
	bound[obj] = nil;
	(obj :: any).Text = text
end

local function setInitial(obj: Instance, text: string)
	if string.sub(text, 1, 1) == "@" then
		Kit.setText(obj, string.sub(text, 2))
	else
		(obj :: any).Text = text
	end
end

Lang.changed:Connect(function()
	for obj, b in bound do
		applyBound(obj, b)
	end
end)

Kit.Font = Enum.Font.FredokaOne
Kit.C = {
	ink = Color3.fromRGB(45, 40, 80),
	white = Color3.fromRGB(255, 255, 255),
	panel = Color3.fromRGB(255, 250, 242),
	card = Color3.fromRGB(255, 255, 255),
	blue = Color3.fromRGB(70, 160, 255),
	green = Color3.fromRGB(70, 205, 105),
	yellow = Color3.fromRGB(255, 200, 45),
	pink = Color3.fromRGB(255, 105, 170),
	red = Color3.fromRGB(255, 80, 90),
	purple = Color3.fromRGB(150, 100, 255),
	orange = Color3.fromRGB(255, 150, 50),
	grey = Color3.fromRGB(170, 170, 190),
	dark = Color3.fromRGB(35, 35, 60),
}

function Kit.darker(c: Color3, f: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), f or 0.25)
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 14)
	c.Parent = parent
	return c
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Kit.C.ink
	s.Thickness = thickness or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Kit.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function Kit.frame(parent: Instance, size: UDim2, pos: UDim2, color: Color3?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = color or Kit.C.panel
	f.BackgroundTransparency = if color then 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

function Kit.text(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, anchor: Vector2?, maxSize: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.AnchorPoint = anchor or Vector2.zero
	t.Font = Kit.Font
	setInitial(t, text)
	t.TextColor3 = color or Kit.C.white
	t.TextScaled = true
	t.RichText = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize or 40
	c.Parent = t
	t.Parent = parent
	return t
end

-- Outlined white text (for text on colourful backgrounds).
function Kit.bold(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, anchor: Vector2?, maxSize: number?): TextLabel
	local t = Kit.text(parent, text, size, pos, color, anchor, maxSize)
	local s = Instance.new("UIStroke")
	s.Color = Kit.C.ink
	s.Thickness = 2.5
	s.Parent = t
	return t
end

-- Button states. The face gradient ends in a darker "lip" (the 3D base of the button):
--   rest    : lip visible, scale 1
--   hover   : scale 1.04 + white outline (mouse only)
--   pressed : the face slides down over the lip, scale 0.95
-- Released / activated: springs back to rest (or hover).
local LIP = 0.86
local function faceGradient(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(240, 240, 240)),
		ColorSequenceKeypoint.new(LIP, Color3.fromRGB(215, 215, 215)),
		ColorSequenceKeypoint.new(LIP + 0.01, Color3.fromRGB(150, 150, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
	})
end

local function wireStates(btn: GuiButton, border: UIStroke, face: UIGradient)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = btn
	local hovered, down = false, false
	local function update(spring: boolean)
		local target = if down then 0.95 elseif hovered then 1.04 else 1
		local info = if spring then TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out) else TweenInfo.new(0.07)
		TweenService:Create(scale, info, { Scale = target }):Play()
		TweenService:Create(face, TweenInfo.new(0.07), { Offset = Vector2.new(0, if down then 1 - LIP else 0) }):Play()
		-- the outline follows the button colour (panels recolour buttons for on / off states)
		border.Color = if hovered and not down then Color3.new(1, 1, 1) else btn.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.45)
	end
	btn.MouseEnter:Connect(function()
		hovered = true
		update(false)
	end)
	btn.MouseLeave:Connect(function()
		hovered, down = false, false
		update(true)
	end)
	btn.MouseButton1Down:Connect(function()
		down = true
		update(false)
	end)
	btn.MouseButton1Up:Connect(function()
		down = false
		update(true)
	end)
	btn:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		update(false)
	end)
	-- touch taps and gamepad activations don't always send Down / Up: give them the same dip
	btn.Activated:Connect(function()
		if not down then
			down = true
			update(false)
			task.delay(0.08, function()
				down = false
				update(true)
			end)
		end
	end)
end

-- Chunky 3D-ish button: coloured face over a darker "shadow" base.
function Kit.button(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, onClick: () -> (), anchor: Vector2?, maxText: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = color
	b.AutoButtonColor = false
	b.Font = Kit.Font
	setInitial(b, text)
	b.TextColor3 = Kit.C.white
	b.TextScaled = true
	b.RichText = true
	b.Parent = parent
	Kit.corner(b, 14)
	local st = Kit.stroke(b, Kit.darker(color, 0.45), 3)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local face = Instance.new("UIGradient")
	face.Color = faceGradient()
	face.Rotation = 90
	face.Parent = b
	local ts = Instance.new("UITextSizeConstraint")
	ts.MaxTextSize = maxText or 30
	ts.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	local textStroke = Instance.new("UIStroke")
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Color = Kit.darker(color, 0.5)
	textStroke.Thickness = 2
	textStroke.Parent = b
	wireStates(b, st, face)
	b.Activated:Connect(onClick)
	return b
end

-- Drawn coin (the coin emoji is missing from Roblox's emoji font).
function Kit.coin(parent: Instance, size: number, pos: UDim2, anchor: Vector2?): Frame
	local c = Kit.frame(parent, UDim2.fromOffset(size, size), pos, Color3.fromRGB(255, 205, 40), anchor)
	Kit.corner(c, size)
	Kit.stroke(c, Color3.fromRGB(200, 130, 10), math.max(2, size * 0.09))
	local inner = Kit.frame(c, UDim2.fromScale(0.56, 0.56), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 225, 100), Vector2.new(0.5, 0.5))
	Kit.corner(inner, size)
	Kit.stroke(inner, Color3.fromRGB(225, 160, 20), math.max(1, size * 0.06))
	return c
end

-- Keeps a short label on ONE line at the biggest size that fits (TextScaled would rather break a
-- long word like "Checkpoint" in two than shrink it). Re-fits on text / size / language changes.
function Kit.singleLine(obj: TextButton, maxSize: number)
	obj.TextScaled = false
	obj.TextWrapped = false
	local busy = false
	local function fit()
		if busy then
			return
		end
		busy = true
		local pad = obj:FindFirstChildOfClass("UIPadding")
		local padX = if pad then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0
		local padY = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		-- design (unscaled) box: TextSize is scaled by the region's UIScale just like Size
		local w = obj.Size.X.Offset - padX - 4
		local h = obj.Size.Y.Offset - padY
		local size = math.min(maxSize, math.floor(h))
		local plain = string.gsub(obj.Text, "<[^>]+>", "")
		while size > 8 do
			local ok, bounds = pcall(function()
				return TextService:GetTextSize(plain, size, obj.Font, Vector2.new(10000, 10000))
			end)
			if not ok or bounds.X <= w then
				break
			end
			size -= 1
		end
		obj.TextSize = size
		busy = false
	end
	obj:GetPropertyChangedSignal("Text"):Connect(fit)
	obj:GetPropertyChangedSignal("Size"):Connect(fit)
	fit()
end

function Kit.pop(obj: GuiObject, from: number?)
	local scale = obj:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = obj
	scale.Scale = from or 0.4
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Kit.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

function Kit.formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	local s = sec % 60
	if h > 0 then
		return ("%dh %02dm"):format(h, m)
	end
	return ("%d:%02d"):format(m, s)
end

---------------------------------------------------------------------------------------------
-- ScreenGui + scaled regions
---------------------------------------------------------------------------------------------
local gui: ScreenGui? = nil
type Region = { frame: Frame, scale: UIScale, fit: Vector2? }
local regions: { Region } = {}

function Kit.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function baseScale(): (number, Vector2)
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local s = math.min(vp.X / 1280, vp.Y / 720)
	if s < 1 then
		s = s ^ 0.6 -- shrink less than linearly on small screens so buttons stay tappable
	end
	if Kit.isTouch() then
		s *= 1.25 -- bigger touch targets on phones/tablets
	end
	return math.clamp(s, 0.55, 1.5), vp
end

type LayoutFn = (touch: boolean, area: Vector2, scale: number) -> ()
local layoutFns: { LayoutFn } = {}
local playerListOn: boolean? = nil

-- Usable area of the ScreenGui (the viewport minus the Roblox top bar, see CoreUISafeInsets).
function Kit.area(): Vector2
	local size = if gui then gui.AbsoluteSize else Vector2.zero
	if size.X < 10 then
		local cam = Workspace.CurrentCamera
		size = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	end
	return size
end

local function rescale()
	local s = baseScale()
	local area = Kit.area()
	for _, r in regions do
		local v = s
		if r.fit then
			-- panels: as big as the screen allows (capped), so their buttons stay tappable on
			-- phones regardless of the HUD scale, and never past the screen edges
			v = math.min(Kit.PANEL_MAX_SCALE, (area.X - 24) / r.fit.X, (area.Y - 24) / r.fit.Y)
			-- the drop shadow (22 design px below the panel) only where it fits on screen: on
			-- phones the panel takes the whole height and the dim veil does the separating
			local window = r.frame:FindFirstChild("Window")
			if window then
				local room = math.min((area.Y - v * r.fit.Y) / 2 - area.Y * 0.02, (area.X - v * r.fit.X) / 2)
				for _, c in window:GetChildren() do
					if c.Name == "Shadow" and c:IsA("GuiObject") then
						c.Visible = room >= 26 * v
					end
				end
			end
		end
		r.scale.Scale = v
	end
	-- The right edge belongs to the tower progress bar (everybody's head is on it), so the
	-- default player list stays closed.
	local wantList = false
	if wantList ~= playerListOn then
		playerListOn = wantList
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, wantList)
		end)
	end
	local touch = Kit.isTouch()
	for _, fn in layoutFns do
		fn(touch, area, s)
	end
end

-- Re-runs every layout function (e.g. after a HUD element was shown or hidden).
function Kit.relayout()
	rescale()
end

-- Registers a function that re-positions regions whenever the screen size / input mode changes.
function Kit.onLayout(fn: LayoutFn)
	table.insert(layoutFns, fn)
	local s = baseScale()
	fn(Kit.isTouch(), Kit.area(), s)
end

Kit.PANEL_MAX_SCALE = 1.1

-- Overrides one region's scale (call from an onLayout function; the next rescale resets it first).
function Kit.setScale(region: Frame, value: number)
	local sc = region:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = value
	end
end

-- Bottom edge (px from the top of the safe area) of the always-on top-centre HUD; Hud keeps it updated.
Kit.hudTop = 0
-- Height (px) of the offer strip under it while one is showing (Cards keeps it updated).
Kit.cardInset = 0

-- Current base UI scale (what regions without `fit` use).
function Kit.scale(): number
	return (baseScale())
end

function Kit.gui(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "SkyTowerUI"
	g.ResetOnSpawn = false
	-- keep everything below the Roblox top bar (menu / chat buttons) and inside notches
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	local function hook()
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
		rescale()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	UserInputService.LastInputTypeChanged:Connect(rescale)
	hook()
	return g
end

-- A transparent container of `designSize` pixels, anchored on screen, scaled as one unit.
function Kit.region(name: string, anchor: Vector2, pos: UDim2, designSize: Vector2, fitScreen: boolean?): Frame
	local f = Kit.frame(Kit.gui(), UDim2.fromOffset(designSize.X, designSize.Y), pos, nil, anchor)
	f.Name = name
	local s = Instance.new("UIScale")
	s.Parent = f
	table.insert(regions, { frame = f, scale = s, fit = if fitScreen then designSize else nil })
	rescale()
	return f
end

---------------------------------------------------------------------------------------------
-- Panels (modal windows, one open at a time)
---------------------------------------------------------------------------------------------
type Panel = { root: Frame, onOpen: (() -> ())? }
local panels: { [string]: Panel } = {}
local current: string? = nil
local panelChanged = Instance.new("BindableEvent")
Kit.panelChanged = panelChanged.Event

-- Dark veil behind the open panel (covers the whole screen, top bar included). Tapping it closes
-- the panel.
local dim: TextButton? = nil
local function ensureDim(): TextButton
	if dim then
		return dim
	end
	local g = Kit.gui()
	local d = Instance.new("TextButton")
	d.Name = "Dim"
	d.Text = ""
	d.AutoButtonColor = false
	d.BackgroundColor3 = Color3.fromRGB(15, 15, 35)
	d.BackgroundTransparency = 1
	d.BorderSizePixel = 0
	d.ZIndex = 9
	d.Visible = false
	d.Parent = g
	local probe = Kit.frame(g, UDim2.fromOffset(1, 1), UDim2.new(), nil)
	probe.Name = "Origin"
	Kit.onLayout(function()
		local cam = Workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local inset = GuiService:GetGuiInset()
		-- AbsolutePosition is measured from under the top bar: shift up / left to the real corner
		d.Position = UDim2.fromOffset(-probe.AbsolutePosition.X, -probe.AbsolutePosition.Y - inset.Y)
		d.Size = UDim2.fromOffset(vp.X, vp.Y)
	end)
	d.Activated:Connect(function()
		Kit.close()
	end)
	dim = d
	return d
end

local function showDim(on: boolean)
	local d = ensureDim()
	if on then
		d.Visible = true
		TweenService:Create(d, TweenInfo.new(0.18), { BackgroundTransparency = 0.5 }):Play()
	else
		d.BackgroundTransparency = 1
		d.Visible = false
	end
end

function Kit.panel(name: string, title: string, color: Color3): (Frame, Frame)
	local root = Kit.region("Panel_" .. name, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), Vector2.new(640, 460), true)
	root.Visible = false
	root.ZIndex = 10
	ensureDim()
	-- "Window" is what pops open: a soft drop shadow under the body
	local window = Kit.frame(root, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), nil, Vector2.new(0.5, 0.5))
	window.Name = "Window"
	for i, spread in { 14, 7 } do
		local shadow = Kit.frame(window, UDim2.new(1, spread * 2, 1, spread * 2), UDim2.new(0.5, 0, 0.5, 8), Color3.new(0, 0, 0), Vector2.new(0.5, 0.5))
		shadow.Name = "Shadow"
		shadow.BackgroundTransparency = if i == 1 then 0.88 else 0.8
		Kit.corner(shadow, 24 + spread)
	end
	local body = Kit.frame(window, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Kit.C.panel)
	body.Name = "Body"
	Kit.corner(body, 24)
	Kit.stroke(body, Kit.C.ink, 4)
	local header = Kit.frame(body, UDim2.new(1, 0, 0, 64), UDim2.fromScale(0, 0), color)
	Kit.corner(header, 24)
	Kit.gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215))
	local headerFill = Kit.frame(header, UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 1, -24), Kit.darker(color, 0.12))
	headerFill.Name = "SquareBottom"
	local headerLine = Kit.frame(header, UDim2.new(1, 0, 0, 4), UDim2.new(0, 0, 1, -2), Kit.darker(color, 0.4))
	headerLine.Name = "Line"
	Kit.bold(header, title, UDim2.new(1, -140, 1, -12), UDim2.fromOffset(24, 6), Kit.C.white, nil, 38).TextXAlignment = Enum.TextXAlignment.Left
	Kit.button(header, "X", UDim2.fromOffset(52, 52), UDim2.new(1, -10, 0.5, 0), Kit.C.red, function()
		Kit.close()
	end, Vector2.new(1, 0.5), 30)
	Kit.relayout() -- decides whether this panel's shadow fits
	local content = Kit.frame(body, UDim2.new(1, -32, 1, -84), UDim2.fromOffset(16, 72), nil)
	content.Name = "Content"
	panels[name] = { root = root }
	return content, root
end

function Kit.onOpen(name: string, fn: () -> ())
	local p = panels[name]
	if p then
		p.onOpen = fn
	end
end

function Kit.open(name: string)
	for n, p in panels do
		p.root.Visible = n == name
	end
	local p = panels[name]
	if not p then
		return
	end
	current = name
	showDim(true)
	Kit.pop(p.root:FindFirstChild("Window") :: Frame, 0.6)
	if p.onOpen then
		p.onOpen()
	end
	panelChanged:Fire(name)
end

function Kit.close()
	for _, p in panels do
		p.root.Visible = false
	end
	current = nil
	showDim(false)
	panelChanged:Fire(nil)
end

function Kit.toggle(name: string)
	if current == name then
		Kit.close()
	else
		Kit.open(name)
	end
end

function Kit.current(): string?
	return current
end

-- Scrolling grid used by shop/store panels.
function Kit.grid(parent: Instance, cell: Vector2, size: UDim2?, pos: UDim2?): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Size = size or UDim2.fromScale(1, 1)
	sf.Position = pos or UDim2.fromScale(0, 0)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 8
	sf.ScrollBarImageColor3 = Kit.C.ink
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new()
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = sf
	sf.Parent = parent
	return sf
end

function Kit.card(parent: Instance, order: number): Frame
	local c = Kit.frame(parent, UDim2.fromOffset(100, 100), UDim2.new(), Kit.C.card)
	c.LayoutOrder = order
	Kit.corner(c, 16)
	Kit.stroke(c, Color3.fromRGB(220, 210, 235), 3)
	return c
end

return Kit
