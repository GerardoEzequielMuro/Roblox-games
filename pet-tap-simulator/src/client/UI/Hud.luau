--!strict
-- HUD, laid out the way the top simulators do it (see docs: ROBLOX-HUD-GUIA).
--
-- PC:    top-centre   objective with a progress bar (what to do next)
--        left         rebirth line, Gems and Taps as bars with an icon, then the menu grid
--        bottom-centre dock: Rewards · the big TAP button (with +N per tap) · Pets (count badge)
--        right        gift timer, live event, boosts, offers, the four auto chips
-- Touch: currencies + menu top-left and the right column at the top, so the thumbstick
--        (bottom-left) and jump button (bottom-right) stay free; the dock sits between them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local HudUnlock = require(ReplicatedStorage.Shared.HudUnlock)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local LiveEventClient = require(script.Parent.Parent.LiveEventClient)
local Ads = require(script.Parent.Parent.Ads)
local Guide = require(script.Parent.Parent.Guide)
local Tapper = require(script.Parent.Parent.Tapper)

local Hud = {}

local shown = { taps = 0, gems = 0 }
local target = { taps = 0, gems = 0 }

local EVENT_COLORS = { LuckyHour = Theme.Green, GoldenWeekend = Theme.Yellow }
local EVENT_ICONS = { LuckyHour = "🍀", GoldenWeekend = "⭐" }

-- iconName: image from the shared icon pack (Theme.setIcon); the emoji is the fallback.
local function pill(parent: Instance, icon: string, iconName: string, color: Color3, width: number, height: number): (Frame, TextLabel)
	local f = Theme.new("Frame", {
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, { Theme.corner(height // 2), Theme.stroke(3), Theme.new("UIGradient", { Color = Theme.buttonFace(color), Rotation = 90 }) })
	Theme.gloss(f, height // 2, 0.78)
	local iconFrame = Theme.new("Frame", {
		Size = UDim2.fromOffset(height + 8, height + 8),
		Position = UDim2.new(0, -4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Paper,
		Parent = f,
	}, { Theme.corner((height + 8) // 2), Theme.stroke(3), Theme.gradient(Theme.White, Theme.lighten(color, 0.6)) })
	Theme.icon(icon, { Size = UDim2.fromScale(0.75, 0.75), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = iconFrame }, iconName)
	local label = Theme.text({ Text = "0", Size = UDim2.new(1, -(height + 18), 1, -8), Position = UDim2.new(0, height + 10, 0, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 34, Stroke = 3, Parent = f })
	label.AutoLocalize = false
	Theme.new("UIScale", { Parent = f })
	return f, label
end

Hud.tapsPill = nil :: Frame?
local sides: { GuiObject } = {}
local dockHolder: GuiObject? = nil

-- Touch layout hides the side columns while a top panel (egg panel) is open.
function Hud.setSidesVisible(visible: boolean)
	for _, s in sides do
		s.Visible = visible
	end
end

-- The egg panel (PC: bottom-centre) takes the dock's place while it is open.
function Hud.setDockVisible(visible: boolean)
	if dockHolder then
		dockHolder.Visible = visible
	end
end

-- Pets and Rewards live in the bottom dock; everything else is in the menu grid.
local MENU: { { any } } = {
	{ "Upgrades", "⬆️", Theme.Teal },
	{ "Rebirth", "🔁", Theme.Purple },
	{ "Quests", "📜", Theme.Orange },
	{ "Store", "🛒", Theme.Green },
	{ "Index", "📖", Theme.Blue },
	{ "Teleport", "🌀", Theme.Yellow },
	{ "Invite", "💌", Theme.Pink },
	{ "Codes", "🎟️", Theme.Red },
}

function Hud.init()
	local gui = Root.gui
	local touch = Root.isTouch
	-- icon in front of a button's text (see Theme.lead)
	local function lead(b: TextButton, emoji: string, name: string?): string
		return Theme.lead(b:FindFirstChild("Label") :: TextLabel, emoji, name)
	end
	local badges: { [string]: Frame } = {}
	local badgeText: { [string]: TextLabel } = {}

	-- Square icon button with a label underneath (menu grid and dock).
	local function iconButton(parent: Instance, name: string, icon: string, color: Color3, order: number, onClick: () -> ()): TextButton
		local b = Theme.button({
			Name = name,
			Color = color,
			LayoutOrder = order,
			Corner = 18,
			OnClick = onClick,
			Parent = parent,
		})
		local label = b:FindFirstChild("Label") :: TextLabel
		Theme.setIcon(label, icon)
		label.Size = UDim2.new(1, -16, 0.58, 0)
		label.Position = UDim2.new(0.5, 0, 0.36, 0)
		local st = label:FindFirstChildOfClass("UIStroke")
		if st then
			st.Enabled = false
		end
		Theme.text({ Key = "menu." .. name, Size = UDim2.new(1, -8, 0.28, 0), Position = UDim2.new(0.5, 0, 0.84, 0), AnchorPoint = Vector2.new(0.5, 0.5), MaxTextSize = 17, Parent = b })
		badges[name] = Theme.badge(b)
		badgeText[name] = (badges[name] :: any):FindFirstChildOfClass("TextLabel")
		return b
	end

	---------------------------------------------------------------------------
	-- Currencies + menu (left)
	---------------------------------------------------------------------------
	local COLS, CELL, GAP = if touch then 4 else 3, if touch then 70 else 80, if touch then 8 else 10
	local rows = math.ceil(#MENU / COLS)
	local menuW, menuH = COLS * CELL + (COLS - 1) * GAP, rows * CELL + (rows - 1) * GAP
	local CUR_H = if touch then 104 else 142 -- currency block height
	local left = Theme.new("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.max(menuW, 264), CUR_H + menuH),
		Position = if touch then UDim2.fromOffset(14, 8) else UDim2.new(0, 14, 0.6, 0),
		AnchorPoint = if touch then Vector2.zero else Vector2.new(0, 0.5),
		Parent = gui,
	})
	local currencies = Theme.new("Frame", { Name = "Currencies", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, CUR_H), Parent = left })
	-- rebirth line
	local rebirthLabel = Theme.text({
		Name = "Rebirths",
		Text = "",
		Size = UDim2.fromOffset(250, 24),
		Position = UDim2.fromOffset(6, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		TextColor3 = Theme.lighten(Theme.Purple, 0.45),
		Visible = not touch,
		Parent = currencies,
	})
	local gemsPill, gemsLabel = pill(currencies, "💎", "gem", Theme.Teal, if touch then 170 else 214, if touch then 42 else 44)
	local tapsPill, tapsLabel = pill(currencies, "👆", "coin", Theme.Blue, 250, 50)
	if touch then
		tapsPill.Position = UDim2.fromOffset(4, 0)
		gemsPill.Position = UDim2.fromOffset(4, 58)
	else
		gemsPill.Position = UDim2.fromOffset(4, 30)
		tapsPill.Position = UDim2.fromOffset(4, 84)
	end
	Hud.tapsPill = tapsPill
	local menu = Theme.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(menuW, menuH),
		Position = UDim2.fromOffset(0, CUR_H),
		Parent = left,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(CELL, CELL),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	table.insert(sides, Root.mount(left))
	-- buttons that appear as the player progresses (HudUnlock), keyed by HudUnlock name
	local unlockables: { [string]: GuiObject } = {}
	for i, e in MENU do
		local name = e[1]
		unlockables[name] = iconButton(menu, name, e[2], e[3], i, function()
			Windows.toggle(name)
		end)
	end

	---------------------------------------------------------------------------
	-- Dock (bottom-centre): Rewards · TAP · Pets
	---------------------------------------------------------------------------
	local dock = Theme.new("Frame", {
		Name = "Dock",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 128),
		Position = UDim2.new(if touch then 0.56 else 0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = gui,
	})
	dockHolder = Root.mount(dock)
	local rewardsB = iconButton(dock, "Rewards", "🎁", Theme.Pink, 1, function()
		Windows.toggle("Rewards")
	end)
	rewardsB.Size = UDim2.fromOffset(84, 84)
	rewardsB.Position = UDim2.fromOffset(0, 36)
	local petsB = iconButton(dock, "Pets", "🐾", Theme.Orange, 3, function()
		Windows.toggle("Pets")
	end)
	petsB.Size = UDim2.fromOffset(84, 84)
	petsB.Position = UDim2.fromOffset(216, 36)
	-- the pets badge shows how many you own (blue, not an alert)
	local petsCount = Theme.new("Frame", { Name = "Count", Size = UDim2.fromOffset(40, 26), Position = UDim2.new(1, -30, 0, -10), BackgroundColor3 = Theme.Blue, ZIndex = 10, Parent = petsB }, { Theme.corner(13), Theme.stroke(2) })
	local petsCountText = Theme.text({ Text = "0", Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2), MaxTextSize = 18, Parent = petsCount })
	petsCountText.ZIndex = 11
	petsCountText.AutoLocalize = false
	-- the big tap button: same thing as tapping the world, always under the thumb
	local tapB = Theme.button({
		Name = "TapButton",
		Text = "👆",
		Color = Theme.Yellow,
		Size = UDim2.fromOffset(112, 96),
		Position = UDim2.fromOffset(94, 0),
		Corner = 30,
		TextSize = 60,
		Parent = dock,
	})
	local tapIcon = tapB:FindFirstChild("Label") :: TextLabel
	Theme.setIcon(tapIcon, "👆", "tap")
	local tapIconStroke = tapIcon:FindFirstChildOfClass("UIStroke")
	if tapIconStroke then
		tapIconStroke.Enabled = false
	end
	tapB.Activated:Connect(function()
		Tapper.simulate(tapB.AbsolutePosition + Vector2.new(tapB.AbsoluteSize.X / 2, -6 * Root.scale))
	end)
	local perTap = Theme.text({
		Name = "PerTap",
		Text = "",
		Size = UDim2.fromOffset(200, 28),
		Position = UDim2.fromOffset(50, 98),
		MaxTextSize = 24,
		Stroke = 3,
		TextColor3 = Theme.Yellow,
		Parent = dock,
	})
	-- First-session hint over the TAP button (it was lost in the HUD rewrite): wobbles until
	-- the player has tapped a bit, then fades out for good.
	local hint = Theme.text({
		Name = "TapHint",
		Key = "hint.tap",
		Size = UDim2.fromOffset(460, 40),
		Position = UDim2.new(0.5, 0, 0, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 34,
		Stroke = 3,
		TextColor3 = Theme.Yellow,
		Parent = dock,
	})
	local hintStroke = hint:FindFirstChildOfClass("UIStroke")
	task.spawn(function()
		local t = 0
		while hint.Parent do
			t += task.wait()
			hint.Rotation = math.sin(t * 3) * 3
			local s = Net.state
			if (s and (s.totalTaps or 0) > 60) or t > 90 then
				local info = TweenInfo.new(0.5)
				TweenService:Create(hint, info, { TextTransparency = 1 }):Play()
				if hintStroke then
					TweenService:Create(hintStroke, info, { Transparency = 1 }):Play()
				end
				task.wait(0.6)
				hint:Destroy()
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Objective (top-centre): what to do next, with a progress bar
	---------------------------------------------------------------------------
	local objective = Theme.new("TextButton", {
		Name = "Objective",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 60),
		Position = UDim2.new(if touch then 0.53 else 0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	local objectiveHolder = Root.mount(objective)
	if touch then
		table.insert(sides, objectiveHolder)
	end
	local objectiveText = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, 0, 0, 30), MaxTextSize = 26, Stroke = 3, Parent = objective })
	local objBarBg = Theme.new("Frame", { Name = "Bar", Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 34), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.35, Parent = objective }, { Theme.corner(10), Theme.stroke(3) })
	local objBar = Theme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = objBarBg }, { Theme.corner(10), Theme.gradient(Theme.lighten(Theme.Green, 0.35), Theme.Green) })
	local objPct = Theme.text({ Name = "Pct", Text = "", Size = UDim2.new(1, 0, 1, -2), Position = UDim2.fromOffset(0, 1), MaxTextSize = 16, Parent = objBarBg })
	objPct.AutoLocalize = false
	local objWindow: string? = nil
	objective.Activated:Connect(function()
		if objWindow then
			Windows.open(objWindow)
		end
	end)
	local function refreshObjective()
		local s = Net.state
		if not s then
			return
		end
		local o = Guide.current(s)
		local args = table.clone(o.args)
		if o.zoneArg then
			args.zone = Lang.zone(o.zoneArg)
		end
		local text = Lang.t(o.key, args)
		if objectiveText.Text ~= text then
			objectiveText.Text = text
			Theme.pop(objective, 1.12)
		end
		local p = math.clamp(o.progress, 0, 1)
		objBar.Size = UDim2.fromScale(math.max(p, 0.03), 1)
		objBar.BackgroundColor3 = if p >= 1 then Theme.Yellow else Color3.new(1, 1, 1)
		local pct = math.floor(p * 100) .. "%"
		if objPct.Text ~= pct then
			objPct.Text = pct
		end
		objWindow = o.window
		Guide.point(o.target)
	end

	---------------------------------------------------------------------------
	-- Right column: gift timer, live event, offers, boosts, auto toggles
	---------------------------------------------------------------------------
	local right = Theme.new("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(210, 440),
		Position = if touch then UDim2.new(1, -14, 0, 8) else UDim2.new(1, -16, 0.55, 0),
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Parent = gui,
	}, { Theme.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center) })
	table.insert(sides, Root.mount(right))

	local giftButton = Theme.button({
		Name = "GiftTimer",
		Key = "hud.gift_ready",
		Color = Theme.Pink,
		Size = UDim2.fromOffset(200, 56),
		LayoutOrder = 1,
		Parent = right,
		OnClick = function()
			Windows.open("Rewards")
		end,
	})
	-- live event pill
	local eventPill = Theme.new("Frame", {
		Name = "EventPill",
		Size = UDim2.fromOffset(200, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = 2,
		Visible = false,
		Parent = right,
	}, { Theme.corner(22), Theme.stroke(3) })
	local eventGradient = Theme.gradient(Theme.lighten(Theme.Green, 0.3), Theme.Green)
	eventGradient.Parent = eventPill
	local eventText = Theme.text({ Text = "", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxTextSize = 22, Parent = eventPill })

	-- Boost status: small dark chips (icon + timer) instead of loose coloured text.
	local function statusChip(name: string, emoji: string, color: Color3, order: number): (Frame, TextLabel)
		local f = Theme.new("Frame", {
			Name = name,
			Size = UDim2.fromOffset(200, 32),
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = 0.25,
			LayoutOrder = order,
			Visible = false,
			Parent = right,
		}, { Theme.corner(16), Theme.stroke(2, Theme.darken(color, 0.35)) })
		Theme.icon(emoji, { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, 5, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = f })
		local t = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, -44, 1, -6), Position = UDim2.fromOffset(36, 3), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(color, 0.25), MaxTextSize = 20, Parent = f })
		return f, t
	end
	local luckChip, luckLabel = statusChip("SuperLuck", "🍀", Theme.Green, 3)
	local boostChip, boostLabel = statusChip("TapBoost", "⚡", Theme.Red, 4)
	local friendChip, friendLabel = statusChip("FriendBoost", "👥", Theme.Yellow, 5)

	local starterButton = Theme.button({
		Name = "StarterPack",
		Text = "",
		Color = Theme.Orange,
		Size = UDim2.fromOffset(200, 56),
		LayoutOrder = 6,
		TextSize = 24,
		Parent = right,
		OnClick = function()
			Hud.onStarterClick()
		end,
	})
	starterButton.Visible = false
	local adButton = Theme.button({
		Name = "AdBoost",
		Text = "",
		Color = Theme.Red,
		Size = UDim2.fromOffset(200, 56),
		LayoutOrder = 7,
		TextSize = 22,
		Parent = right,
		OnClick = function()
			Ads.watch("AdBoost")
		end,
	})
	adButton.Visible = false

	-- Auto toggles: one chip each, green = ON, grey = OFF. The server does the work (and
	-- sets the pace), so they keep running while the player is away from the keyboard.
	local autoGrid = Theme.new("Frame", {
		Name = "Auto",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 118),
		LayoutOrder = 8,
		Parent = right,
	}, {
		Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(97, 56), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	type Chip = { button: TextButton, name: TextLabel, state: TextLabel, key: string, icon: string, on: boolean? }
	local chips: { [string]: Chip } = {}
	local function autoState(key: string): boolean
		local s = Net.state
		if not s then
			return false
		end
		if key == "hatch" then
			return s.autoHatch ~= nil
		end
		return s.auto ~= nil and s.auto[key] == true
	end
	local function toggleAuto(key: string)
		local on = not autoState(key)
		local ok, err
		if key == "hatch" then
			if on then
				-- needs an egg: the egg panel's Auto button starts it
				Toasts.show(Lang.t("toast.autohatch_hint"), "info")
				return
			end
			ok, err = Net.request("SetAutoHatch", {})
		else
			ok, err = Net.request("SetAuto", { key = key, on = on })
		end
		if ok then
			Toasts.show(Lang.t("toast.auto", { name = Lang.t("hud.auto." .. key), state = Lang.t(if on then "hud.on" else "hud.off") }), if on then "success" else "info")
		elseif err then
			Toasts.show(Lang.msg(err), "error")
		end
	end
	for i, spec in { { "tap", "AutoTap", "🤖" }, { "hatch", "AutoHatch", "🥚" }, { "equip", "AutoEquip", "🐾" }, { "rebirth", "AutoRebirth", "🔁" } } do
		local key, name, icon = spec[1], spec[2], spec[3]
		local b = Theme.button({
			Name = name,
			Text = "",
			Color = Theme.Grey,
			LayoutOrder = i,
			Corner = 14,
			Parent = autoGrid,
			OnClick = function()
				toggleAuto(key)
			end,
		})
		local top = b:FindFirstChild("Label") :: TextLabel
		top.Size = UDim2.new(1, -34, 0.5, -2)
		top.Position = UDim2.new(0.5, 13, 0.3, 0)
		local iconHolder = Theme.icon(icon, { Name = "ChipIcon", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 6, 0.3, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = b })
		iconHolder.ZIndex = top.ZIndex
		local topLimit = top:FindFirstChildOfClass("UITextSizeConstraint")
		if topLimit then
			topLimit.MaxTextSize = 18
		end
		local state = Theme.text({ Name = "State", Text = "", Size = UDim2.new(1, -8, 0.42, 0), Position = UDim2.new(0.5, 0, 0.72, 0), AnchorPoint = Vector2.new(0.5, 0.5), MaxTextSize = 17, Parent = b })
		state.ZIndex = top.ZIndex
		chips[key] = { button = b, name = top, state = state, key = key, icon = icon }
		unlockables[name] = b
	end
	local function refreshChips()
		for key, chip in chips do
			local on = autoState(key)
			local label = Lang.t("hud.auto." .. key)
			if chip.name.Text ~= label then
				chip.name.Text = label
			end
			if chip.on ~= on or chip.state.Text == "" then
				chip.on = on
				Theme.setButton(chip.button, nil, if on then Theme.Green else Theme.Grey)
			end
			local text = Lang.t(if on then "hud.on" else "hud.off")
			if key == "tap" and on then
				local s = Net.state
				local rate = if s and s.auto then s.auto.tapRate else 0
				text = text .. " · " .. tostring(rate) .. "/s"
			end
			if chip.state.Text ~= text then
				chip.state.Text = text
			end
		end
	end

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
	RunService.RenderStepped:Connect(function(dt: number)
		local a = math.min(1, dt * 9)
		for k, v in target do
			local cur = shown[k]
			if math.abs(v - cur) < 1 then
				shown[k] = v
			else
				shown[k] = cur + (v - cur) * a
			end
		end
		-- only touch the labels when the text really changes (no layout work on idle frames)
		local tapsText = Format.abbrev(shown.taps)
		if tapsText ~= tapsLabel.Text then
			tapsLabel.Text = tapsText
		end
		local gemsText = Format.abbrev(shown.gems)
		if gemsText ~= gemsLabel.Text then
			gemsLabel.Text = gemsText
		end
	end)

	-- Progressive HUD: a new player sees Rewards, TAP, Pets and the Store; the other buttons
	-- and auto chips appear (with a pop) as they are reached, and never hide again.
	local unlocked: { [string]: boolean } = {}
	local firstUnlock = true
	local function applyUnlocks(s: any)
		local vis = HudUnlock.visible(s)
		local anyChip = false
		for name, obj in unlockables do
			local show = vis[name] == true or unlocked[name] == true
			if show and not unlocked[name] then
				unlocked[name] = true
				if not firstUnlock then
					task.defer(function()
						Theme.pop(obj, 1.35)
					end)
					Theme.play("open", 0.35, 1.3)
				end
			end
			if obj.Visible ~= show then
				obj.Visible = show
			end
			if show and obj.Parent == autoGrid then
				anyChip = true
			end
		end
		autoGrid.Visible = anyChip
		firstUnlock = false
	end

	local lastTaps, lastGems = nil :: number?, nil :: number?
	local lastFull = 0
	local function refresh(kind: string?)
		local s = Net.state
		if not s then
			return
		end
		target.taps = s.taps
		target.gems = s.gems
		if lastGems and s.gems > lastGems then
			Theme.pop(gemsPill, 1.2)
		end
		if lastTaps and s.taps > lastTaps + (s.tapValue or 1) * 20 then
			Theme.pop(tapsPill, 1.12)
		end
		lastTaps, lastGems = s.taps, s.gems
		-- currency-only updates arrive several times a second: the rest is refreshed on full
		-- snapshots, and at most twice a second in between (objective progress, badges)
		local now = os.clock()
		if kind ~= "full" and now - lastFull < 0.5 then
			return
		end
		lastFull = now
		local perTapText = "+" .. Format.abbrev(math.max(1, s.tapValue or 1))
		if perTap.Text ~= perTapText then
			perTap.Text = perTapText
		end
		local rebirthText = Theme.lead(rebirthLabel, "🔁") .. Lang.t("rebirth.count", { n = s.rebirths }) .. "  ·  x" .. tostring(Formulas.rebirthMult(s.rebirths))
		if rebirthLabel.Text ~= rebirthText then
			rebirthLabel.Text = rebirthText
		end
		local petCount = 0
		for _ in s.pets do
			petCount += 1
		end
		petsCountText.Text = tostring(petCount)

		refreshChips()
		applyUnlocks(s)
		refreshObjective()
		friendLabel.Text = if (s.friends or 0) > 0 then Lang.t("hud.friend_boost", { pct = math.floor(Formulas.friendBoost(s.friends) * 100) }) else ""
		friendChip.Visible = friendLabel.Text ~= ""

		-- badges
		badges.Rebirth.Visible = s.taps >= s.rebirthCost
		local nextZone = Config.Zones[#s.zones + 1]
		badges.Teleport.Visible = nextZone ~= nil and s.taps >= nextZone.cost
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
		Hud.refreshQuestBadge()
	end

	function Hud.refreshQuestBadge()
		local s = Net.state
		local q = s and s.quests
		local ready = 0
		if q then
			local allClaimed = true
			for _, quest in q.list do
				if not quest.claimed then
					allClaimed = false
					if quest.progress >= quest.target then
						ready += 1
					end
				end
			end
			if allClaimed and not q.bonusClaimed and #q.list > 0 then
				ready += 1
			end
		end
		badges.Quests.Visible = ready > 0
		local bt = badgeText.Quests
		if bt then
			bt.Text = tostring(ready)
		end
	end

	Net.Changed:Connect(refresh)
	refresh("full")

	-- Timers (gifts, daily, luck, events, offers) once per second
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
		giftButton.Visible = ready or nextIn ~= nil
		local giftLead = lead(giftButton, "🎁")
		Theme.setButton(giftButton, if ready then (giftLead .. Lang.t("hud.gift_ready")) elseif nextIn then (giftLead .. Format.time(nextIn)) else "", if ready then Theme.Pink else Theme.Purple)
		local luckLeft = math.max(0, (s.luckBoostLeft or 0) - since)
		luckLabel.Text = if luckLeft > 0 then Lang.t("hud.super_luck", { time = Format.time(luckLeft) }) else ""
		luckChip.Visible = luckLeft > 0
		local boostLeft = math.max(0, (s.tapBoostLeft or 0) - since)
		boostLabel.Text = if boostLeft > 0 then Lang.t("hud.tap_boost", { time = Format.time(boostLeft) }) else ""
		boostChip.Visible = boostLeft > 0

		-- live event
		local active = LiveEventClient.active()
		local ev = active[1]
		eventPill.Visible = ev ~= nil
		if ev then
			local c = EVENT_COLORS[ev.id] or Theme.Green
			eventGradient.Color = ColorSequence.new(Theme.lighten(c, 0.3), c)
			eventText.Text = Theme.lead(eventText, EVENT_ICONS[ev.id] or "✨") .. Lang.t("event." .. ev.id) .. " " .. Format.time(ev.endsAt - LiveEventClient.now())
		end

		-- starter pack
		local st = s.starter
		starterButton.Visible = st ~= nil and st.available and serverNow < st.endsAt
		if starterButton.Visible then
			Theme.setButton(starterButton, lead(starterButton, "🎉") .. Lang.t("starter.button") .. " " .. Format.time(st.endsAt - serverNow))
		end
		-- rewarded video boost
		adButton.Visible = boostLeft <= 0 and Ads.canShow("AdBoost")
		if adButton.Visible then
			Theme.setButton(adButton, lead(adButton, "📺") .. Lang.t("ads.boost_button", { n = Config.AdBoostMinutes }))
		end
		-- the beam follows the player, so re-aim it as they walk
		refreshObjective()
	end
	Lang.Changed:Connect(tick)
	LiveEventClient.Changed:Connect(function(data, started)
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

	-- Reward popups (taps/gems given by rewards)
	Net.event("Reward").OnClientEvent:Connect(function(r)
		if r.kind == "taps" then
			Toasts.show(Lang.t("toast.got_taps", { n = Format.abbrev(r.amount) }), "success")
			Theme.pop(tapsPill, 1.25)
		elseif r.kind == "gems" then
			Toasts.show(Lang.t("toast.got_gems", { n = Format.abbrev(r.amount) }), "success")
		elseif r.kind == "luck" then
			Toasts.show(Lang.t("toast.got_luck", { n = r.amount }), "success")
		end
		Theme.play("buy", 0.4, 1.2)
	end)
end

-- Set by Popups (opens the Starter Pack offer card).
Hud.onStarterClick = function() end
Hud.refreshQuestBadge = function() end

return Hud
