--!strict
-- HUD, laid out like the top simulators (docs: ROBLOX-HUD-GUIA, section 8.4).
--
-- PC:    top-centre    galaxy name, then the objective (tutorial step / Gate progress) or
--                      the boss bar of the big planet being mined
--        left          Shop, then the menu grid (buttons appear as they unlock)
--        bottom-left   counters: Power (pink), Crystals (cyan), Stardust (gold)
--        bottom-centre the Cargo panel with its bar and SELL, the auto chips above it
--        right         gift timer, offers
--        bottom-right  Anomaly clock, live event, active buffs with timers
-- Touch: counters + menu go top-left and the right column to the top, so the thumbstick
--        (bottom-left) and the jump button (bottom-right) stay free.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local LiveEventClient = require(script.Parent.Parent.LiveEventClient)
local Ads = require(script.Parent.Parent.Ads)
local Miner = require(script.Parent.Parent.Miner)
local PlanetField = require(script.Parent.Parent.PlanetField)
local WorldFx = require(script.Parent.Parent.WorldFx)

local Hud = {}

local EVENT_COLORS = { MeteorShower = Theme.Orange, LuckyNebula = Theme.Green, CrystalWeekend = Theme.Crystals, StarSurge = Theme.Yellow }
local EVENT_ICONS = { MeteorShower = "☄️", LuckyNebula = "🍀", CrystalWeekend = "💎", StarSurge = "🌠" }
local BUFF_ICONS = { damage = "💥", speed = "💨", luck = "🍀", stardust = "✨" }
local AUTO_CHIPS: { { any } } = {
	{ "mine", "⛏️" },
	{ "sell", "🚀" },
	{ "open", "🧬" },
	{ "best", "⭐" },
	{ "rebirth", "🔁" },
}

-- name, icon, colour, unlock: tutorial step index the button appears at (0 = always)
local MENU: { { any } } = {
	{ "Pets", "🐾", Theme.Pink, 4 },
	{ "Upgrades", "⛏️", Theme.Orange, 0 },
	{ "Teleport", "🌀", Theme.Purple, 5 },
	{ "Rebirth", "🔁", Theme.Teal, 7 },
	{ "Index", "📖", Theme.Blue, 7 },
	{ "Quests", "📜", Theme.Yellow, 7 },
	{ "Rewards", "🎁", Theme.Green, 6 },
	{ "Auto", "🤖", Theme.Grey, 6 },
	{ "Invite", "💌", Theme.Pink, 7 },
	{ "Settings", "⚙️", Theme.Grey, 0 },
}

Hud.cargoPanel = nil :: Frame?
Hud.stardustPill = nil :: Frame?
local sides: { GuiObject } = {}

function Hud.setSidesVisible(visible: boolean)
	for _, s in sides do
		s.Visible = visible
	end
end

-- Set by Popups (opens the Starter Pack offer card).
Hud.onStarterClick = function() end
-- Set by Guide: the current objective line and its progress (0..1 or nil).
Hud.objective = nil :: { text: string, progress: number? }?
Hud.refreshObjective = function() end

-- Currency pill: dark glass capsule with a tinted rim, the icon on a coloured disc and the
-- number in the currency's colour.
local function counter(parent: Instance, icon: string, color: Color3, order: number, name: string): (Frame, TextLabel)
	local f = Theme.new("Frame", { Name = name, Size = UDim2.fromOffset(190, 32), BackgroundColor3 = Theme.PaperDark, BackgroundTransparency = 0.25, LayoutOrder = order, Parent = parent }, {
		Theme.corner(16),
		Theme.stroke(2, Theme.darken(color, 0.35)),
		Theme.gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 200)),
	}) :: Frame
	local disc = Theme.new("Frame", { Name = "IconDisc", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, -2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = f }, {
		Theme.corner(17),
		Theme.stroke(2),
		Theme.gradient(Theme.lighten(color, 0.35), Theme.darken(color, 0.35)),
	})
	Theme.glyph({ Emoji = icon, Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = disc })
	local label = Theme.text({ Name = "Value", Text = "0", Italic = true, TextColor3 = color, Size = UDim2.new(1, -44, 1, -2), Position = UDim2.fromOffset(38, 1), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 28, Stroke = 3, Parent = f })
	label.AutoLocalize = false
	Theme.new("UIScale", { Parent = f })
	return f, label
end

function Hud.init()
	local gui = Root.gui
	local touch = Root.isTouch
	local badges: { [string]: Frame } = {}

	---------------------------------------------------------------------------
	-- Top centre: galaxy name + objective / boss bar
	---------------------------------------------------------------------------
	local top = Theme.new("Frame", {
		Name = "Top",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(if touch then 430 else 540, 96),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	Root.mount(top)
	local zoneTitle = Theme.text({ Name = "Zone", Text = "", Size = UDim2.new(1, 0, 0, 30), MaxTextSize = 28, Stroke = 3, Parent = top })
	local objective = Theme.new("Frame", { Name = "Objective", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 34), BackgroundColor3 = Theme.PaperDark, BackgroundTransparency = 0.15, Parent = top }, { Theme.corner(14), Theme.stroke(3) })
	local objectiveFill = Theme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = objective }, { Theme.corner(14), Theme.gradient(Theme.lighten(Theme.Green, 0.2), Theme.darken(Theme.Green, 0.15)) })
	local objectiveText = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), MaxTextSize = 24, ZIndex = 2, Parent = objective })

	---------------------------------------------------------------------------
	-- Left: Shop + menu grid
	---------------------------------------------------------------------------
	local COLS, CELL, GAP = if touch then 5 else 3, if touch then 56 else 66, 6
	local gridW = COLS * CELL + (COLS - 1) * GAP
	local left = Theme.new("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(gridW, if touch then 300 else 360),
		Position = if touch then UDim2.fromOffset(12, 6) else UDim2.new(0, 12, 0.46, 0),
		AnchorPoint = if touch then Vector2.zero else Vector2.new(0, 0.5),
		Parent = gui,
	}, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center) })
	table.insert(sides, Root.mount(left))

	-- counters (touch: on top of the menu; PC: bottom-left)
	local counters = Theme.new("Frame", {
		Name = "Counters",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 104),
		LayoutOrder = 0,
		Parent = if touch then left else gui,
	}, { Theme.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom) })
	if not touch then
		counters.Position = UDim2.new(0, 12, 1, -8)
		counters.AnchorPoint = Vector2.new(0, 1)
		table.insert(sides, Root.mount(counters))
	end
	local _powerPill, powerLabel = counter(counters, "💪", Theme.Power, 1, "Power")
	local crystalPill, crystalLabel = counter(counters, "💎", Theme.Crystals, 2, "Crystals")
	local stardustPill, stardustLabel = counter(counters, "✨", Theme.Stardust, 3, "Stardust")
	Hud.stardustPill = stardustPill

	local shop = Theme.button({ Name = "Store", Text = "", Color = Theme.Red, Size = UDim2.fromOffset(gridW, if touch then 44 else 50), LayoutOrder = 1, TextSize = 30, Parent = left, OnClick = function()
		Windows.toggle("Store")
	end })
	local shopLabel = shop:FindFirstChild("Label") :: TextLabel
	local shopImage = Theme.iconImage("🛒")
	if shopImage then
		-- icon pack uploaded: picture on the left, words on the right
		Theme.glyph({ Emoji = "🛒", Size = UDim2.new(0, 38, 1, -10), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = shopLabel.ZIndex, Parent = shop })
		shopLabel.Size = UDim2.new(1, -56, 1, -10)
		shopLabel.Position = UDim2.new(0.5, 22, 0.5, -1)
	end
	local function shopText()
		shopLabel.Text = (if shopImage then "" else "🛒 ") .. Lang.t("menu.Store")
	end
	shopText()
	Lang.Changed:Connect(shopText)

	local menu = Theme.new("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromOffset(gridW, 4 * (CELL + GAP)), LayoutOrder = 2, Parent = left }, {
		Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(CELL, CELL), CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local menuButtons: { [string]: TextButton } = {}
	for i, e in MENU do
		local name, icon, color = e[1], e[2], e[3]
		local b = Theme.button({ Name = name, Color = color, LayoutOrder = i, Corner = 14, Parent = menu, OnClick = function()
			Windows.toggle(name)
		end })
		local label = b:FindFirstChild("Label") :: TextLabel
		label.Size = UDim2.new(1, -14, 0.56, 0)
		label.Position = UDim2.new(0.5, 0, 0.36, 0)
		local st = label:FindFirstChildOfClass("UIStroke")
		if st then
			st.Enabled = false
		end
		if Theme.iconImage(icon) then
			label.Text = ""
			Theme.glyph({ Name = "Icon", Emoji = icon, Size = label.Size, Position = label.Position, AnchorPoint = label.AnchorPoint, ZIndex = label.ZIndex, Parent = b })
		else
			label.Text = icon
		end
		Theme.text({ Key = "menu." .. name, Size = UDim2.new(1, -6, 0.28, 0), Position = UDim2.new(0.5, 0, 0.84, 0), AnchorPoint = Vector2.new(0.5, 0.5), MaxTextSize = 15, ZIndex = 2, Parent = b })
		badges[name] = Theme.badge(b)
		menuButtons[name] = b
	end

	---------------------------------------------------------------------------
	-- Bottom centre: auto chips + Overcharge + the Cargo panel
	---------------------------------------------------------------------------
	local bottom = Theme.new("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(460, 132),
		Position = UDim2.new(if touch then 0.54 else 0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = gui,
	})
	Root.mount(bottom)
	local chipRow = Theme.new("Frame", { Name = "Autos", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = bottom }, {
		Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local chips: { [string]: TextButton } = {}
	for i, e in AUTO_CHIPS do
		local key, icon = e[1], e[2]
		local chip = Theme.button({ Name = "Auto_" .. key, Text = "", Color = Theme.Grey, Size = UDim2.fromOffset(86, 34), LayoutOrder = i, Corner = 10, TextSize = 17, Parent = chipRow, OnClick = function()
			local s = Net.state
			if not s then
				return
			end
			if key == "open" then
				if s.autoOpen then
					Net.request("SetAutoOpen", {})
				else
					Toasts.show(Lang.t("toast.autoopen_hint"), "info")
				end
				return
			end
			Net.request("SetAuto", { key = key, on = not s.auto[key] })
		end })
		chip:SetAttribute("Icon", icon)
		chips[key] = chip
	end
	-- Overcharge meter (Storm Reach)
	local charge = Theme.bar(bottom, UDim2.fromOffset(300, 16), Theme.Yellow)
	charge.frame.Name = "Overcharge"
	charge.frame.Position = UDim2.new(0.5, 0, 0, 40)
	charge.frame.AnchorPoint = Vector2.new(0.5, 0)
	charge.frame.Visible = false

	local cargo = Theme.panel({ Name = "Cargo", Size = UDim2.fromOffset(460, 70), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Theme.PaperDark, BackgroundTransparency = 0.1, Corner = 14, Parent = bottom })
	cargo:SetAttribute("BlocksMining", true)
	Hud.cargoPanel = cargo
	Theme.text({ Key = "hud.cargo", Size = UDim2.fromOffset(110, 22), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, TextColor3 = Color3.fromRGB(190, 200, 230), Parent = cargo })
	local cargoCount = Theme.text({ Name = "Count", Text = "0 / 24", Size = UDim2.fromOffset(170, 26), Position = UDim2.fromOffset(12, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = cargo })
	local cargoValue = Theme.text({ Name = "Value", Text = "", Italic = true, TextColor3 = Theme.Stardust, Size = UDim2.fromOffset(150, 24), Position = UDim2.new(1, -262, 0, 8), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 22, Parent = cargo })
	local cargoBar = Theme.bar(cargo, UDim2.new(1, -124, 0, 16), Theme.Orange)
	cargoBar.frame.Position = UDim2.fromOffset(12, 50)
	local sellButton = Theme.button({ Name = "Sell", Key = "hud.sell", Color = Theme.Green, Size = UDim2.fromOffset(96, 56), Position = UDim2.new(1, -7, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 24, Parent = cargo, OnClick = function()
		local ok, res = Net.request("SellCargo")
		if not ok and res then
			Toasts.show(Lang.msg(res), "error")
		end
	end })

	---------------------------------------------------------------------------
	-- Right column: gift timer + offers; bottom-right: clocks and buffs
	---------------------------------------------------------------------------
	local right = Theme.new("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(190, 330),
		Position = if touch then UDim2.new(1, -12, 0, 6) else UDim2.new(1, -12, 1, -8),
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 1),
		Parent = gui,
	}, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right, if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom) })
	table.insert(sides, Root.mount(right))

	local starterButton = Theme.button({ Name = "StarterPack", Text = "", Color = Theme.Orange, Size = UDim2.fromOffset(186, 46), LayoutOrder = 1, TextSize = 20, Parent = right, OnClick = function()
		Hud.onStarterClick()
	end })
	starterButton.Visible = false
	local adButton = Theme.button({ Name = "AdBoost", Text = "", Color = Theme.Purple, Size = UDim2.fromOffset(186, 42), LayoutOrder = 2, TextSize = 18, Parent = right, OnClick = function()
		Ads.watch("AdBoost")
	end })
	adButton.Visible = false
	local giftButton = Theme.button({ Name = "GiftTimer", Text = "", Color = Theme.Pink, Size = UDim2.fromOffset(186, 42), LayoutOrder = 3, TextSize = 20, Parent = right, OnClick = function()
		Windows.open("Rewards")
	end })
	local buffRows: { [string]: TextLabel } = {}
	for i, id in Config.BuffOrder do
		local row = Theme.new("Frame", { Name = "Buff_" .. id, Size = UDim2.fromOffset(150, 28), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 10 + i, Visible = false, Parent = right }, {
			Theme.corner(14), Theme.stroke(2), Theme.gradient(Theme.lighten((Palette.Buff :: any)[id], 0.1), Theme.darken((Palette.Buff :: any)[id], 0.3)),
		})
		buffRows[id] = Theme.text({ Text = "", Size = UDim2.new(1, -12, 1, -4), Position = UDim2.fromOffset(6, 2), MaxTextSize = 18, Parent = row })
	end
	local eventPill = Theme.new("Frame", { Name = "EventPill", Size = UDim2.fromOffset(186, 34), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 20, Visible = false, Parent = right }, { Theme.corner(17), Theme.stroke(3) })
	local eventGradient = Theme.gradient(Theme.lighten(Theme.Green, 0.2), Theme.darken(Theme.Green, 0.2))
	eventGradient.Parent = eventPill
	local eventText = Theme.text({ Text = "", Size = UDim2.new(1, -14, 1, -6), Position = UDim2.fromOffset(7, 3), MaxTextSize = 19, Parent = eventPill })
	local anomalyPill = Theme.new("Frame", { Name = "AnomalyClock", Size = UDim2.fromOffset(186, 34), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 21, Parent = right }, { Theme.corner(17), Theme.stroke(3) })
	local anomalyGradient = Theme.gradient(Color3.fromRGB(60, 200, 190), Color3.fromRGB(30, 110, 130))
	anomalyGradient.Parent = anomalyPill
	local anomalyText = Theme.text({ Text = "", Size = UDim2.new(1, -14, 1, -6), Position = UDim2.fromOffset(7, 3), MaxTextSize = 19, Parent = anomalyPill })

	-- the starter button pulses while the offer is live
	local starterScale = starterButton:FindFirstChildOfClass("UIScale") :: UIScale
	task.spawn(function()
		while true do
			if starterButton.Visible then
				local t = TweenService:Create(starterScale, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Scale = 1.06 })
				t:Play()
				t.Completed:Wait()
				TweenService:Create(starterScale, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
				task.wait(0.6)
			else
				task.wait(1)
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Count-up and refresh
	---------------------------------------------------------------------------
	local shown = { stardust = 0, crystals = 0, power = 0 }
	local target = { stardust = 0, crystals = 0, power = 0 }
	RunService.RenderStepped:Connect(function(dt: number)
		local a = math.min(1, dt * 9)
		for k, v in target do
			local cur = (shown :: any)[k]
			if math.abs(v - cur) < 1 then
				(shown :: any)[k] = v
			else
				(shown :: any)[k] = cur + (v - cur) * a
			end
		end
		stardustLabel.Text = Format.abbrev(shown.stardust)
		crystalLabel.Text = Format.abbrev(shown.crystals)
		powerLabel.Text = Format.abbrev(shown.power)
	end)

	local lastStardust, lastCrystals = nil :: number?, nil :: number?
	local function refreshChips(s: { [string]: any })
		for _, e in AUTO_CHIPS do
			local key, icon = e[1], e[2]
			local on = if key == "open" then s.autoOpen ~= nil else s.auto[key] == true
			Theme.setButton(chips[key], icon .. " " .. Lang.t("auto." .. key .. ".short") .. " " .. Lang.t(if on then "hud.on" else "hud.off"), if on then Theme.Green else Theme.Grey)
		end
	end

	local function bossView(): PlanetField.View?
		local view = Miner.targetView()
		if view then
			local kind = Config.PlanetKindById[view.kind]
			if kind.boss or kind.special then
				return view
			end
		end
		return nil
	end

	local function refreshObjective()
		local s = Net.state
		if not s then
			return
		end
		local boss = bossView()
		local text, progress, color = "", nil :: number?, Theme.Green
		if boss then
			-- boss bar: name + HP of the big planet being mined
			local name = if boss.kind == "gate" and Config.Zones[(PlanetField.zone or 1) + 1] then Lang.t("world.gate_to", { zone = Lang.zone((PlanetField.zone or 1) + 1) }) else Lang.planet(boss.kind)
			local total = Formulas.layerHp(PlanetField.zone or 1, boss.kind, boss.layer)
			text = Lang.upper(name) .. "  " .. Format.abbrev(math.ceil(boss.hp)) .. " / " .. Format.abbrev(math.max(total, boss.max))
			progress = if boss.max > 0 then boss.hp / boss.max else 0
			color = Theme.Red
		elseif Hud.objective then
			text, progress = Hud.objective.text, Hud.objective.progress
		else
			local nextZone = Config.Zones[s.maxZone + 1]
			local nextTool = Config.Tools[(Config.ToolIndex[s.tool] or 1) + 1]
			local toolFrac = if nextTool and nextTool.cost > 0 and table.find(s.zones, nextTool.zone) then s.stardust / nextTool.cost else 2
			if toolFrac >= 0.25 and toolFrac < 1 then
				-- a tool you are close to affording beats the far-away gate
				text = "🔨 " .. Lang.t("hud.goal_tool", { tool = Lang.tool(nextTool.id), pct = math.floor(toolFrac * 100) })
				progress = toolFrac
				color = Theme.Orange
			elseif nextZone then
				local done = 1 - s.gateLeft / nextZone.gateHp
				text = "🚀 " .. Lang.t("hud.goal_gate", { zone = Lang.zone(s.maxZone + 1), pct = math.floor(done * 100) })
				progress = done
				color = Theme.Purple
			else
				local frac = math.clamp(s.stardust / s.rebirthCost, 0, 1)
				text = "🔁 " .. Lang.t("hud.goal_rebirth", { pct = math.floor(frac * 100) })
				progress = frac
				color = Theme.Teal
			end
		end
		objectiveText.Text = text
		objective.Visible = text ~= ""
		objectiveFill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
		objectiveFill.Visible = progress ~= nil and progress > 0.02
		local g = objectiveFill:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(Theme.lighten(color, 0.2), Theme.darken(color, 0.15))
		end
	end
	Hud.refreshObjective = refreshObjective

	local function refresh()
		local s = Net.state
		if not s then
			return
		end
		target.stardust = s.stardust
		target.crystals = s.crystals
		target.power = s.damage
		if lastCrystals and s.crystals > lastCrystals then
			Theme.pop(crystalPill, 1.2)
		end
		if lastStardust and s.stardust > lastStardust + math.max(1, s.income) * 3 then
			Theme.pop(stardustPill, 1.15)
		end
		lastStardust, lastCrystals = s.stardust, s.crystals
		-- cargo
		local c = s.cargo
		if c then
			local full = not c.instant and c.count >= c.cap
			cargoCount.Text = if c.instant then "∞" else (c.count .. " / " .. c.cap)
			cargoCount.TextColor3 = if full then Theme.Red else Theme.White
			cargoValue.Text = if c.value > 0 then ("+" .. Format.abbrev(c.value) .. " ✨") elseif c.transit > 0 then ("🚀 " .. Format.abbrev(c.transitValue)) else ""
			cargoBar:set(if c.instant then 0 else c.count / math.max(1, c.cap), if full then Lang.t("hud.cargo_full") else "")
			Theme.setBarColor(cargoBar, if full then Theme.Red else Theme.Orange)
			Theme.setButton(sellButton, if c.transit > 0 then "🚀" else Lang.t("hud.sell"), if c.count > 0 and c.transit <= 0 then Theme.Green else Theme.Grey)
		end
		refreshChips(s)
		-- Overcharge
		local hasCharge = table.find(s.zones, Config.SystemById.overcharge.zone) ~= nil
		charge.frame.Visible = hasCharge
		if hasCharge then
			local mult = Formulas.overchargeMult(s.charge or 0, s.upgrades.Capacitor or 0)
			charge:set(s.charge or 0, "⚡ x" .. string.format("%.2f", mult))
		end
		-- progressive menu: buttons appear as the tutorial advances
		for _, e in MENU do
			local b = menuButtons[e[1]]
			b.Visible = s.tutorial >= e[4]
		end
		-- badges
		badges.Rebirth.Visible = s.stardust >= s.rebirthCost
		local nextTool = Config.Tools[(Config.ToolIndex[s.tool] or 1) + 1]
		badges.Upgrades.Visible = nextTool ~= nil and s.stardust >= nextTool.cost and table.find(s.zones, nextTool.zone) ~= nil
		local indexReady = false
		for _, zone in Config.Zones do
			if not s.indexClaimed[tostring(zone.index)] then
				local all = true
				for _, pet in Config.Pets do
					if pet.zone == zone.index and not s.discovered[pet.id] then
						all = false
						break
					end
				end
				if all then
					indexReady = true
				end
			end
		end
		badges.Index.Visible = indexReady
		local q = s.quests
		local ready = 0
		if q then
			local allClaimed = #q.list > 0
			for _, quest in q.list do
				if not quest.claimed then
					allClaimed = false
					if quest.progress >= quest.target then
						ready += 1
					end
				end
			end
			if allClaimed and not q.bonusClaimed then
				ready += 1
			end
		end
		badges.Quests.Visible = ready > 0
		refreshObjective()
	end
	Net.Changed:Connect(refresh)
	Net.event("Quests").OnClientEvent:Connect(function(q)
		local s = Net.state
		if s then
			s.quests = q
			refresh()
		end
	end)
	Miner.TargetChanged:Connect(refreshObjective)
	PlanetField.Changed:Connect(refreshObjective)
	refresh()

	local function zoneText()
		local zone = WorldFx.zone
		if WorldFx.place == "arena" then
			zoneTitle.Text = "⚔️ " .. Lang.upper(Lang.t("world.arena"))
		elseif zone then
			zoneTitle.Text = Lang.upper(Lang.zone(zone)) .. "  ·  " .. Lang.t("hud.galaxy_n", { n = zone })
		end
	end
	zoneText()
	WorldFx.PlaceChanged:Connect(function(place, zone)
		zoneText()
		if place == "arena" then
			Toasts.milestone(Lang.upper(Lang.t("world.arena")), Lang.t("hud.arena_sub"), Theme.Red)
		elseif zone then
			Toasts.milestone(Lang.upper(Lang.zone(zone)), Lang.t("hud.galaxy_n", { n = zone }), Theme.Yellow)
		end
	end)

	-- Timers once per second
	local function tick()
		local s = Net.state
		if not s then
			return
		end
		local since = os.clock() - Net.receivedAt
		local elapsed = s.sessionElapsed + since
		local claimed = {}
		for _, i in s.giftsClaimed do
			claimed[i] = true
		end
		local nextIn: number? = nil
		local ready = false
		for i, g in Config.Gifts do
			if not claimed[i] then
				local left = g.minutes * 60 - elapsed
				if left <= 0 then
					ready = true
				elseif not nextIn or left < nextIn then
					nextIn = left
				end
			end
		end
		local serverNow = s.serverTime + since
		local dailyReady = serverNow - s.daily.last >= Config.DailyCooldown
		badges.Rewards.Visible = ready or dailyReady
		giftButton.Visible = (ready or nextIn ~= nil) and s.tutorial >= 6
		Theme.setButton(giftButton, if ready then ("🎁 " .. Lang.t("hud.gift_ready")) elseif nextIn then ("🎁 " .. Format.time(nextIn)) else "", if ready then Theme.Green else Theme.Pink)
		-- buffs
		for _, id in Config.BuffOrder do
			local left = math.max(0, (s.buffs[id] or 0) - since)
			local label = buffRows[id]
			local row = label.Parent :: Frame
			row.Visible = left > 0
			if left > 0 then
				label.Text = BUFF_ICONS[id] .. " " .. Lang.t("buff." .. id) .. " " .. Format.time(left)
			end
		end
		-- live event
		local ev = LiveEventClient.active()[1]
		eventPill.Visible = ev ~= nil
		if ev then
			local c = EVENT_COLORS[ev.id] or Theme.Green
			eventGradient.Color = ColorSequence.new(Theme.lighten(c, 0.2), Theme.darken(c, 0.25))
			eventText.Text = (EVENT_ICONS[ev.id] or "✨") .. " " .. Lang.t("event." .. ev.id) .. " " .. Format.time(ev.endsAt - LiveEventClient.now())
		end
		-- Anomaly clock
		local now = LiveEventClient.now()
		local active, window, edge = Formulas.anomaly(now)
		if active and s.anomalyWindow ~= window then
			anomalyText.Text = "🌀 " .. Lang.t("hud.anomaly_now", { time = Format.time(edge - now) })
			anomalyGradient.Color = ColorSequence.new(Color3.fromRGB(90, 250, 230), Color3.fromRGB(20, 150, 150))
		else
			local nextAt = if active then window + Config.AnomalyEvery else edge
			anomalyText.Text = "🌀 " .. Lang.t("hud.anomaly_in", { time = Format.time(nextAt - now) })
			anomalyGradient.Color = ColorSequence.new(Color3.fromRGB(70, 110, 150), Color3.fromRGB(34, 50, 84))
		end
		anomalyPill.Visible = s.tutorial > #Config.Tutorial
		-- starter pack
		local st = s.starter
		starterButton.Visible = st ~= nil and st.available and serverNow < st.endsAt
		if starterButton.Visible then
			Theme.setButton(starterButton, "🎁 " .. Lang.t("starter.button") .. " " .. Format.time(st.endsAt - serverNow))
		end
		adButton.Visible = (s.buffs.stardust or 0) - since <= 0 and Ads.canShow("AdBoost")
		if adButton.Visible then
			Theme.setButton(adButton, "📺 " .. Lang.t("ads.boost_button", { n = Config.AdBoostMinutes }))
		end
		-- drone countdown
		local c = s.cargo
		if c and c.transit > 0 then
			local left = c.transit - (os.clock() - Net.receivedCurrencyAt)
			if left > 0 then
				cargoValue.Text = "🚀 " .. Format.abbrev(c.transitValue) .. " · " .. math.ceil(left) .. "s"
			end
		end
	end
	Lang.Changed:Connect(function()
		tick()
		refresh()
		zoneText()
	end)
	LiveEventClient.Changed:Connect(function(_data, started)
		tick()
		for _, id in started do
			Toasts.banner((EVENT_ICONS[id] or "✨") .. " " .. Lang.t("event.started", { event = Lang.t("event." .. id) }), EVENT_COLORS[id] or Theme.Green)
		end
	end)
	task.spawn(function()
		while true do
			tick()
			task.wait(1)
		end
	end)

	-- Reward toasts
	Net.event("Reward").OnClientEvent:Connect(function(r)
		if r.kind == "stardust" then
			Toasts.show(Lang.t("toast.got_stardust", { n = Format.abbrev(r.amount) }), "success")
			Theme.pop(stardustPill, 1.25)
		elseif r.kind == "crystals" then
			Toasts.show(Lang.t("toast.got_crystals", { n = Format.abbrev(r.amount) }), "success")
		elseif r.kind == "luck" then
			Toasts.show(Lang.t("toast.got_luck", { n = r.amount }), "success")
		elseif r.kind == "boost" then
			Toasts.show(Lang.t("toast.got_boost", { n = r.amount }), "success")
		elseif r.kind == "sold" then
			Toasts.show(Lang.t(if r.hand then "toast.sold_hand" else "toast.sold", { n = Format.abbrev(r.amount) }), "success", 1.6)
			Theme.pop(stardustPill, 1.25)
			Theme.play("buy", 0.4, 1.3)
			return
		elseif r.kind == "drone" then
			return
		end
		Theme.play("buy", 0.4, 1.2)
	end)
end

return Hud
