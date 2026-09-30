--!nonstrict
-- Combat HUD. Layout follows what the top anime fighters on Roblox do:
--   PC     bottom-left: power + HP + ki + currencies   bottom-centre: auto toggles over the five
--          numbered training slots (+ weights)          bottom-right: the move list with its keys
--   touch  top-left: power + HP + ki + currencies       top-centre: training slots + auto toggles
--          (the bottom corners belong to the thumbstick and the round action buttons)
-- Plus: zone pill, combo counter, boss bar, beam charge meter, low-HP vignette, screen flash
-- and the giant form name when you transform.
-- Pieces that stack share a "dock" so they scale as one block at any resolution.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Fx = require(script.Parent.Parent.Fx)
local Controls = require(script.Parent.Parent.Controls)
local CombatFx = require(script.Parent.Parent.CombatFx)
local NpcRender = require(script.Parent.Parent.NpcRender)

local Hud = {}

local player = Players.LocalPlayer
local new = Theme.new
local touch = Root.isTouch
local C = Config.Combat

local refs: { [string]: any } = {}
Hud.refs = refs
Hud.notify = nil :: any -- set by Main (Toasts.show)
Hud.banner = nil :: any

---------------------------------------------------------------------------
-- Vitals dock: power, form, HP, ki, currencies
---------------------------------------------------------------------------
local function currency(parent: Instance, name: string, icon: string, color: Color3, pos: UDim2): TextLabel
	local f = new("Frame", { Name = name, Size = UDim2.fromOffset(122, 30), Position = pos, BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.25, Parent = parent }, {
		Theme.corner(15),
		Theme.stroke(2.5),
	})
	local medal = new("Frame", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(-3, -2), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, Parent = f }, {
		Theme.corner(17),
		Theme.stroke(2.5),
		Theme.gradient(Theme.lighten(color, 0.4), color),
	})
	Theme.text({ Text = icon, Stroke = false, Size = UDim2.fromScale(0.66, 0.66), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = medal }).ZIndex = 3
	local value = Theme.text({ Name = "Value", Text = "0", Font = Theme.Display, Size = UDim2.new(1, -42, 1, -4), Position = UDim2.fromOffset(36, 2), MaxTextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(color, 0.55), Parent = f })
	new("UIScale", { Parent = f })
	refs[name .. "Pill"] = f
	return value
end

local function buildVitals()
	local dock = new("Frame", {
		Name = "Vitals",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(254, 134),
		Position = if touch then UDim2.fromOffset(8, 6) else UDim2.new(0, 10, 1, -10),
		AnchorPoint = if touch then Vector2.zero else Vector2.new(0, 1),
		Parent = Root.gui,
	})
	Root.mount(dock)
	refs.vitals = dock
	-- power line
	local powerRow = new("Frame", { Name = "PowerRow", BackgroundTransparency = 1, Size = UDim2.fromOffset(254, 38), Parent = dock })
	new("UIScale", { Parent = powerRow })
	refs.powerBox = powerRow
	local badge = new("Frame", { Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Color3.new(1, 1, 1), Parent = powerRow }, {
		Theme.corner(19),
		Theme.stroke(3),
		Theme.gradient(Color3.fromRGB(255, 200, 70), Color3.fromRGB(240, 96, 30)),
	})
	Theme.text({ Text = "💥", Stroke = false, Size = UDim2.fromScale(0.66, 0.66), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = badge })
	refs.power = Theme.text({ Name = "Power", Text = "0", Font = Theme.Display, Size = UDim2.fromOffset(120, 38), Position = UDim2.fromOffset(44, 0), MaxTextSize = 38, Stroke = 3, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 226, 110), Parent = powerRow })
	Theme.text({ Key = "hud.power", Size = UDim2.fromOffset(84, 14), Position = UDim2.fromOffset(168, 4), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Parent = powerRow })
	refs.form = Theme.text({ Name = "Form", Text = "", Size = UDim2.fromOffset(88, 18), Position = UDim2.fromOffset(166, 18), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = powerRow })
	-- bars
	refs.hpBar, refs.setHp = Theme.bar({ Name = "HpBar", Size = UDim2.fromOffset(254, 24), Position = UDim2.fromOffset(0, 42), Color = Theme.Green, TextSize = 15, Parent = dock })
	refs.kiBar, refs.setKi = Theme.bar({ Name = "KiBar", Size = UDim2.fromOffset(254, 20), Position = UDim2.fromOffset(0, 70), Color = Theme.Cyan, TextSize = 13, Parent = dock })
	-- currencies + boost line
	refs.sparks = currency(dock, "Sparks", "⚡", Theme.Yellow, UDim2.fromOffset(4, 98))
	refs.gems = currency(dock, "Gems", "💎", Theme.Cyan, UDim2.fromOffset(132, 98))
	refs.boost = Theme.text({ Name = "Boost", Text = "", Size = UDim2.fromOffset(250, 14), Position = if touch then UDim2.fromOffset(2, 132) else UDim2.fromOffset(2, -18), MaxTextSize = 13, TextColor3 = Theme.Yellow, TextXAlignment = Enum.TextXAlignment.Left, Parent = dock })
end

---------------------------------------------------------------------------
-- Training dock: auto toggles + five numbered stat slots + weights
---------------------------------------------------------------------------
local statSlots: { [string]: { frame: TextButton, value: TextLabel, ring: UIStroke, scale: UIScale } } = {}
local SLOT = if touch then 50 else 58

local function toggleButton(key: string, locKey: string, order: number, parent: Instance, w: number): TextButton
	local b = new("TextButton", {
		Name = "Auto_" .. key,
		Size = UDim2.fromOffset(w, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { Theme.corner(13), Theme.stroke(2.5), new("UIGradient", { Name = "G", Rotation = 90 }) })
	local dot = new("Frame", { Name = "Dot", Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = Theme.Grey, Parent = b }, { Theme.corner(6), Theme.stroke(1.5) })
	local _ = dot
	Theme.text({ Name = "Label", Text = "", Size = UDim2.new(1, -28, 1, -6), Position = UDim2.fromOffset(23, 3), MaxTextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = b })
	b:SetAttribute("SettingKey", key)
	b:SetAttribute("LocKey", locKey)
	b.Activated:Connect(function()
		Theme.play("click", 0.3)
		Controls.toggleSetting(key)
	end)
	return b
end

local function buildTraining()
	local n = #Config.Stats
	local gap = 8
	local gearW = if touch then 96 else 118
	local w = n * SLOT + (n - 1) * gap + gap + gearW
	local h = 26 + 6 + SLOT + 20
	local dock = new("Frame", {
		Name = "Training",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h),
		Position = if touch then UDim2.new(0.5, 40, 0, 6) else UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.new(0.5, 1),
		Parent = Root.gui,
	})
	Root.mount(dock)
	refs.training = dock
	-- auto toggles (top row on PC, bottom row on touch so the slots sit under the Roblox bar)
	local autos = new("Frame", {
		Name = "Autos",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, 26),
		Position = if touch then UDim2.fromOffset(0, SLOT + 24) else UDim2.fromOffset(0, 0),
		Parent = dock,
	}, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local bw = math.floor((w - 12) / 3)
	refs.autoTrain = toggleButton("autoTrain", "hud.auto_train", 1, autos, bw)
	refs.autoCharge = toggleButton("autoCharge", "hud.auto_ki", 2, autos, bw)
	refs.autoFight = toggleButton("autoFight", "hud.auto_fight", 3, autos, bw)
	refs.autos = autos
	-- stat slots
	local top = if touch then 0 else 32
	for i, stat in Config.Stats do
		local info = Config.StatInfo[stat]
		local color = Theme.rgb(info.color)
		local b = new("TextButton", {
			Name = "Stat_" .. stat,
			Size = UDim2.fromOffset(SLOT, SLOT),
			Position = UDim2.fromOffset((i - 1) * (SLOT + gap) + SLOT / 2, top + SLOT / 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
			Text = "",
			Parent = dock,
		}, {
			Theme.corner(SLOT),
			Theme.gradient(Theme.PanelLight, Theme.PanelDark),
		})
		local ring = new("UIStroke", { Thickness = 3, Color = Theme.White, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		local scale = new("UIScale", { Parent = b })
		Theme.text({ Text = info.icon, Stroke = false, Size = UDim2.fromScale(0.58, 0.58), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = b })
		if not touch then
			Theme.text({ Text = tostring(i), Font = Theme.Display, Size = UDim2.fromOffset(18, 20), Position = UDim2.fromOffset(-2, -6), MaxTextSize = 20, Stroke = 2.5, Parent = b }).ZIndex = 4
		end
		local value = Theme.text({ Name = "Value", Text = "0", Font = Theme.Display, Size = UDim2.fromOffset(SLOT + gap, 18), Position = UDim2.new(0.5, 0, 1, 2), AnchorPoint = Vector2.new(0.5, 0), MaxTextSize = 18, TextColor3 = Theme.lighten(color, 0.45), Parent = b })
		b.Activated:Connect(function()
			Theme.play("click", 0.3)
			Controls.setStat(stat)
		end)
		statSlots[stat] = { frame = b, value = value, ring = ring, scale = scale }
	end
	-- weights
	local gear = new("TextButton", {
		Name = "Gear",
		Size = UDim2.fromOffset(gearW, SLOT),
		Position = UDim2.fromOffset(n * (SLOT + gap), top),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Parent = dock,
	}, { Theme.corner(12), Theme.stroke(3), new("UIGradient", { Name = "G", Rotation = 90 }) })
	Theme.gloss(gear, 12, 0.85)
	new("UIScale", { Parent = gear })
	refs.gearTop = Theme.text({ Name = "Top", Text = "", Size = UDim2.new(1, -8, 0.5, -2), Position = UDim2.fromOffset(4, 3), MaxTextSize = 17, Parent = gear })
	refs.gearBottom = Theme.text({ Name = "Bottom", Text = "", Font = Theme.Display, Size = UDim2.new(1, -8, 0.5, -4), Position = UDim2.new(0, 4, 0.5, 0), MaxTextSize = 20, TextColor3 = Theme.Yellow, Parent = gear })
	gear.Activated:Connect(function()
		local ok, res = Net.request("BuyGear")
		if ok then
			Theme.play("land", 0.5, 1.3)
			Theme.pop(gear, 1.12)
		elseif Hud.notify then
			Hud.notify(Lang.msg(res), "error")
		end
	end)
	refs.gear = gear
	-- selected stat readout: "+12 per rep · auto 1.5/s"
	refs.trainRate = Theme.text({ Name = "Rate", Text = "", Size = UDim2.fromOffset(w, 14), Position = if touch then UDim2.fromOffset(0, SLOT + 52) else UDim2.fromOffset(0, -18), MaxTextSize = 13, TextColor3 = Theme.Yellow, Parent = dock })
end

---------------------------------------------------------------------------
-- Moves dock (PC): the move list with its keys and cooldown fills
---------------------------------------------------------------------------
type Slot = { frame: TextButton, cool: Frame, action: string }
local slots: { Slot } = {}

local function moveSlot(parent: Instance, order: number, icon: string, key: string, locKey: string, action: string, color: Color3, onClick: (() -> ())?): Slot
	local f = new("TextButton", { Name = "Slot_" .. action, Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.3, AutoButtonColor = false, Text = "", LayoutOrder = order, ClipsDescendants = false, Parent = parent }, {
		Theme.corner(8),
		Theme.stroke(2.5, Theme.lighten(color, 0.25)),
	})
	-- cooldown: a fill of the move colour that drains as the move comes back
	local clip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Parent = f }, { Theme.corner(8) })
	local cool = new("Frame", { Name = "Cool", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = color, BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = clip })
	Theme.text({ Text = icon, Stroke = false, Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), Parent = f }).ZIndex = 2
	local keyLabel = Theme.text({ Text = key, Font = Theme.Display, Size = UDim2.fromOffset(34, 16), Position = UDim2.new(1, 1, 1, 1), AnchorPoint = Vector2.new(1, 1), MaxTextSize = 16, Stroke = 2.5, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow, Parent = f })
	keyLabel.ZIndex = 4
	f:SetAttribute("LocKey", locKey)
	new("UIScale", { Parent = f })
	if onClick then
		f.Activated:Connect(onClick)
	end
	local s = { frame = f, cool = cool, action = action }
	table.insert(slots, s)
	return s
end

local function buildMoves()
	local dock = new("Frame", {
		Name = "Moves",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(292, 116),
		Position = UDim2.new(1, -10, 1, -10),
		AnchorPoint = Vector2.new(1, 1),
		Parent = Root.gui,
	})
	Root.mount(dock)
	refs.moves = dock
	refs.moveName = Theme.text({ Key = "hud.moves", Size = UDim2.fromOffset(288, 16), Position = UDim2.fromOffset(0, 0), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.FontBold, Parent = dock })
	local grid = new("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromOffset(292, 96), Position = UDim2.fromOffset(0, 20), Parent = dock }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(44, 44), CellPadding = UDim2.fromOffset(5, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom, StartCorner = Enum.StartCorner.TopLeft }),
	})
	moveSlot(grid, 1, "👊", "LMB", "act.punch", "melee", Theme.Red, nil)
	moveSlot(grid, 2, "🔵", "Q", "act.blast", "blast", Theme.Cyan, Controls.blast)
	moveSlot(grid, 3, "☄️", "R", "act.beam", "beam", Theme.Blue, nil)
	moveSlot(grid, 4, "🛡️", "F", "act.block", "block", Theme.Green, nil)
	moveSlot(grid, 5, "💨", "E", "act.dash", "dash", Theme.Yellow, Controls.dash)
	moveSlot(grid, 6, "🔋", "C", "act.charge", "charge", Theme.Purple, nil)
	moveSlot(grid, 7, "🔥", "G", "act.form", "form", Theme.Orange, function()
		Controls.transform()
	end)
	moveSlot(grid, 8, "🕊️", "H", "act.fly", "fly", Theme.Pink, Controls.toggleFly)
	for i, t in Config.Techniques do
		local s = moveSlot(grid, 8 + i, t.icon, t.key, "tech." .. t.id, "t_" .. t.id, Theme.Purple, function()
			Controls.technique(t.id)
		end)
		refs["tech_" .. t.id] = s.frame
	end
	-- hovering a move shows its name over the grid
	for _, s in slots do
		s.frame.MouseEnter:Connect(function()
			Lang.unbind(refs.moveName)
			refs.moveName.Text = Lang.t(s.frame:GetAttribute("LocKey"))
		end)
		s.frame.MouseLeave:Connect(function()
			Lang.bind(refs.moveName, "hud.moves")
		end)
	end
end

---------------------------------------------------------------------------
-- Top-centre: zone pill, boss bar. Centre: combo, beam meter, form title. Overlays.
---------------------------------------------------------------------------
local comboAt = 0
local function buildCombat()
	-- touch: the training dock owns the top centre, so these sit lower / to the right
	local zone = new("Frame", {
		Name = "Zone",
		Size = UDim2.fromOffset(320, 32),
		Position = if touch then UDim2.new(0.5, 40, 0, 118) else UDim2.new(0.5, 0, 0, 88),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = Root.gui,
	}, { Theme.corner(16), Theme.stroke(3), new("UIGradient", { Name = "G", Rotation = 90 }) })
	new("UIScale", { Parent = zone })
	Root.mount(zone)
	refs.zone = zone
	refs.zoneText = Theme.text({ Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), MaxTextSize = 19, Parent = zone })

	local boss = new("Frame", { Name = "BossBar", BackgroundTransparency = 1, Size = UDim2.fromOffset(440, 44), Position = if touch then UDim2.new(0.5, 40, 0, 154) else UDim2.new(0.5, 0, 0, 126), AnchorPoint = Vector2.new(0.5, 0), Visible = false, Parent = Root.gui })
	Root.mount(boss)
	refs.boss = boss
	refs.bossName = Theme.text({ Text = "", Size = UDim2.new(1, 0, 0, 20), MaxTextSize = 19, Stroke = 3, TextColor3 = Theme.Yellow, Parent = boss })
	refs.bossBar, refs.setBoss = Theme.bar({ Name = "BossHp", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 22), Color = Theme.Red, TextSize = 14, Parent = boss })

	local combo = new("Frame", { Name = "Combo", BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 96), Position = if touch then UDim2.new(0.42, 0, 0.44, 0) else UDim2.new(0.5, 300, 0.42, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, Parent = Root.gui })
	new("UIScale", { Parent = combo })
	Root.mount(combo)
	refs.combo = combo
	refs.comboN = Theme.text({ Text = "x2", Font = Theme.Display, Size = UDim2.new(1, 0, 0, 64), MaxTextSize = 64, Stroke = 4, TextColor3 = Theme.Yellow, Rotation = -6, Parent = combo })
	Theme.text({ Key = "hud.hits", Font = Theme.Display, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 60), MaxTextSize = 28, Stroke = 3, Rotation = -6, Parent = combo })

	local beamMeter, setBeam = Theme.bar({ Name = "BeamMeter", Size = UDim2.fromOffset(260, 20), Position = if touch then UDim2.new(0.42, 0, 0.62, 0) else UDim2.new(0.5, 0, 1, -150), AnchorPoint = Vector2.new(0.5, 1), Color = Theme.Blue, TextSize = 13, Parent = Root.gui })
	beamMeter.Visible = false
	Root.mount(beamMeter)
	refs.beamMeter, refs.setBeam = beamMeter, setBeam

	-- giant form name for a second when you transform
	local title = Theme.text({ Name = "FormTitle", Text = "", Font = Theme.Display, Size = UDim2.fromOffset(900, 120), Position = UDim2.fromScale(0.5, 0.3), AnchorPoint = Vector2.new(0.5, 0.5), MaxTextSize = 110, Stroke = 6, Visible = false, Parent = Root.gui })
	new("UIScale", { Parent = title })
	Root.mount(title)
	refs.formTitle = title

	-- full-screen overlays (no input)
	refs.flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.White, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = Root.overlay })
	refs.hurt = new("Frame", { Name = "Hurt", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Red, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = Root.overlay }, {
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 0) }),
		}),
	})
end

function Hud.flash(color: Color3, strength: number?)
	local f = refs.flash
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (strength or 0.7)
	TweenService:Create(f, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
end

local function formTitle(text: string, color: Color3)
	local t = refs.formTitle
	t.Text = text
	t.TextColor3 = Theme.lighten(color, 0.35)
	t.TextTransparency = 0
	t.Visible = true
	local st = t:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	local sc = t:FindFirstChildOfClass("UIScale")
	sc.Scale = 2.2
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.9, function()
		TweenService:Create(t, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		if st then
			TweenService:Create(st, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
		task.wait(0.36)
		if t.TextTransparency >= 0.99 then
			t.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local lastPower = -1
local lastSparks, lastGems = -1, -1

local function refreshNumbers()
	local s = Net.state
	if not s then
		return
	end
	if s.power ~= lastPower then
		if lastPower >= 0 and s.power > lastPower then
			Theme.pop(refs.powerBox, 1.05)
		end
		lastPower = s.power
		refs.power.Text = Format.abbrev(s.power)
	end
	if s.sparks ~= lastSparks then
		if lastSparks >= 0 and s.sparks > lastSparks then
			Theme.pop(refs.SparksPill, 1.1)
		end
		lastSparks = s.sparks
		refs.sparks.Text = Format.abbrev(s.sparks)
	end
	if s.gems ~= lastGems then
		if lastGems >= 0 and s.gems > lastGems then
			Theme.pop(refs.GemsPill, 1.1)
		end
		lastGems = s.gems
		refs.gems.Text = Format.abbrev(s.gems)
	end
	for stat, slot in statSlots do
		slot.value.Text = Format.abbrev(s.stats[stat] or 0)
	end
end

local function face(color: Color3): ColorSequence
	return ColorSequence.new(Theme.lighten(color, 0.2), Theme.darken(color, 0.28))
end

local function refreshFull()
	local s = Net.state
	if not s then
		return
	end
	refreshNumbers()
	local selected = s.settings.stat
	for stat, slot in statSlots do
		local on = stat == selected
		local color = Theme.rgb(Config.StatInfo[stat].color)
		slot.ring.Color = if on then color else Theme.White
		slot.ring.Thickness = if on then 5 else 2.5
		slot.ring.Transparency = if on then 0 else 0.35
		slot.scale.Scale = if on then 1.12 else 0.94
		local g = slot.frame:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = if on then ColorSequence.new(Theme.lighten(color, 0.15), Theme.darken(color, 0.45)) else ColorSequence.new(Theme.PanelLight, Theme.PanelDark)
		end
	end
	refs.trainRate.Text = Lang.t("hud.rate", { stat = Lang.t("stat." .. selected), n = Format.abbrev(math.max(1, s.perRep[selected] or 0)), auto = string.format("%.1f", s.autoRate) })
	for _, key in { "autoTrain", "autoCharge", "autoFight" } do
		local b = refs[key]
		local on = s.settings[key] == true
		b.Label.Text = Lang.t(b:GetAttribute("LocKey")) .. ": " .. Lang.t(if on then "hud.on" else "hud.off")
		b.G.Color = face(if on then Theme.Green else Theme.Grey)
		b.Dot.BackgroundColor3 = if on then Color3.fromRGB(210, 255, 170) else Theme.PanelDark
	end
	-- weights
	local nextTier = Config.Gear[s.gear + 1]
	local cur = string.format("x%g", Formulas.gearMult(s.gear))
	if nextTier then
		refs.gearTop.Text = "🏋️ " .. cur .. " → " .. string.format("x%g", nextTier.mult)
		refs.gearBottom.Text = "⚡ " .. Format.abbrev(nextTier.cost)
		refs.gear.G.Color = Theme.buttonFace(if s.sparks >= nextTier.cost then Theme.Green else Theme.Orange)
	else
		refs.gearTop.Text = "🏋️ " .. cur
		refs.gearBottom.Text = "MAX"
		refs.gear.G.Color = Theme.buttonFace(Theme.Grey)
	end
	-- zone pill
	local zone = Config.ZoneById[s.zone]
	if zone then
		refs.zone.Visible = true
		local g = refs.zone.G
		if s.zoneLocked then
			g.Color = face(Theme.Red)
			refs.zoneText.Text = "🔒 " .. Lang.t("hud.zone_locked", { power = Format.abbrev(zone.reqPower) })
		else
			g.Color = face(Theme.Purple)
			refs.zoneText.Text = Lang.t("zone." .. zone.id) .. "  x" .. Format.abbrev(zone.mult)
		end
	else
		refs.zone.Visible = false
	end
	-- moves: techniques appear once owned; the form slot is dim until a form is unlocked
	for _, t in Config.Techniques do
		local f = refs["tech_" .. t.id]
		if f then
			f.Visible = s.techniques[t.id] == true
		end
	end
	-- boost line
	local parts = {}
	if s.boostLeft and s.boostLeft > 0 then
		table.insert(parts, "🔥 x2 " .. Format.time(s.boostLeft))
	end
	if s.rebirths and s.rebirths > 0 then
		table.insert(parts, "🌟 " .. s.rebirths)
	end
	refs.boost.Text = table.concat(parts, "   ")
end

local function nearestBoss(pos: Vector3): any
	local best, bestD = nil, 170
	for root, v in NpcRender.visuals do
		if v.def.boss then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = v, d
			end
		end
	end
	return best
end

local lastForm = -1
local function tick()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	refs.setHp(hum.Health / math.max(1, hum.MaxHealth), "HP  " .. Format.abbrev(math.ceil(hum.Health)) .. " / " .. Format.abbrev(hum.MaxHealth))
	local ki = char:GetAttribute("Ki") or 0
	refs.setKi(ki, Lang.t("hud.ki") .. "  " .. math.floor(ki * 100 + 0.5) .. "%")
	local form = char:GetAttribute("Form") or 0
	if form ~= lastForm then
		local first = lastForm == -1
		lastForm = form
		local c1 = Fx.formColors(form)
		if form > 0 then
			local name = Lang.t("form." .. Config.Forms[form].id)
			refs.form.Text = name .. " x" .. Format.abbrev(Config.Forms[form].mult)
			refs.form.TextColor3 = Theme.lighten(c1, 0.5)
			Theme.setBarColor(refs.kiBar, c1)
			if not first then
				Hud.flash(Theme.lighten(c1, 0.5), 0.75)
				formTitle(Lang.upper(name) .. "!", c1)
			end
		else
			refs.form.Text = ""
			Theme.setBarColor(refs.kiBar, Theme.Cyan)
		end
	end
	-- low HP vignette
	local frac = hum.Health / math.max(1, hum.MaxHealth)
	refs.hurt.BackgroundTransparency = if frac < 0.3 and hum.Health > 0 then 0.55 + math.sin(os.clock() * 7) * 0.12 else 1
	-- boss bar
	local root = char:FindFirstChild("HumanoidRootPart")
	local boss = root and nearestBoss(root.Position)
	if boss then
		refs.boss.Visible = true
		refs.bossName.Text = Lang.t("npc." .. boss.def.id)
		local hp, max = boss.root:GetAttribute("Hp") or 0, boss.root:GetAttribute("MaxHp") or 1
		refs.setBoss(hp / max, Format.abbrev(hp) .. " / " .. Format.abbrev(max))
	else
		refs.boss.Visible = false
	end
	-- combo fade
	if refs.combo.Visible and os.clock() - comboAt > C.comboWindow + 0.2 then
		refs.combo.Visible = false
	end
end

local function cooldowns()
	local now = os.clock()
	for _, s in slots do
		local total = Controls.cooldownOf[s.action]
		local frac = 0
		if total then
			frac = math.clamp(((Controls.nextAt[s.action] or 0) - now) / total, 0, 1)
		end
		s.cool.Size = UDim2.fromScale(1, frac)
	end
	local started = Controls.beamStartedAt
	if started then
		local charge = math.clamp((now - started) / C.beamMaxCharge, 0, 1)
		refs.beamMeter.Visible = true
		refs.setBeam(charge, if charge >= 1 then "MAX" else math.floor(charge * 100) .. "%")
	elseif refs.beamMeter.Visible then
		refs.beamMeter.Visible = false
	end
end

function Hud.init()
	buildVitals()
	buildTraining()
	if not touch then
		buildMoves()
	end
	buildCombat()

	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refreshFull()
		else
			refreshNumbers()
		end
	end)
	Lang.Changed:Connect(function()
		lastForm = -1
		refreshFull()
	end)
	refreshFull()

	Net.event("Combat").OnClientEvent:Connect(function(kind, a)
		if kind == "combo" then
			comboAt = os.clock()
			if a >= 2 then
				refs.combo.Visible = true
				refs.comboN.Text = "x" .. a
				refs.comboN.TextColor3 = if a % C.comboFinisher == 0 then Theme.Red else Theme.Yellow
				Theme.pop(refs.combo, if a % C.comboFinisher == 0 then 1.5 else 1.22)
			end
		elseif kind == "kill" then
			if Hud.notify and a.b then
				Hud.notify(Lang.t("toast.boss_down", { boss = Lang.t("npc." .. a.n), n = Format.abbrev(a.s), g = a.g }), "success")
			end
		elseif kind == "formUnlocked" then
			if Hud.banner then
				local f = Config.Forms[a]
				Hud.banner(Lang.t("toast.form_unlocked", { form = Lang.t("form." .. f.id), key = if touch then "🔥" else "G" }), Theme.rgb(f.color))
			end
		elseif kind == "planetUnlocked" then
			if Hud.banner then
				Hud.banner(Lang.t("toast.planet_unlocked", { planet = Lang.t("planet." .. Config.Planets[a].id) }), Theme.Cyan)
			end
		end
	end)

	-- rep feedback: a big "+N" in the colour of the stat on every punch
	Controls.Used:Connect(function(action)
		if action == "melee" then
			local s = Net.state
			local char = player.Character
			local head = char and char:FindFirstChild("Head")
			if s and head then
				local stat = s.settings.stat
				local gain = s.perRep[stat] or 1
				CombatFx.damageNumber(head.Position + Vector3.new(0, 1, 0), "+" .. Format.abbrev(math.max(1, gain)) .. " " .. Config.StatInfo[stat].icon, Theme.rgb(Config.StatInfo[stat].color):Lerp(Theme.White, 0.25), true)
				local slot = statSlots[stat]
				if slot then
					slot.scale.Scale = 1.26
					TweenService:Create(slot.scale, TweenInfo.new(0.16), { Scale = 1.12 }):Play()
				end
			end
		elseif action == "noKi" then
			Theme.pop(refs.kiBar, 1.1)
			if Hud.notify then
				Hud.notify(Lang.t("hud.no_ki"), "error")
			end
		end
	end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		cooldowns()
		acc += dt
		if acc >= 0.066 then
			acc = 0
			tick()
		end
	end)
end

return Hud
