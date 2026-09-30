--!nonstrict
-- Panel manager + left-side menu. Only one panel open at a time, scale-pop open/close.
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local DailyPanel = require(script.Parent.DailyPanel)
local Layout = require(script.Parent.Layout)

local Panels = {}
Panels.current = nil :: string?
Panels.menuButtons = {} :: { [string]: TextButton }
Panels.starter = nil :: any
Panels.setMenuExpanded = nil :: any -- (on: boolean) -> (), set in build
Panels.menuExpanded = nil :: any -- () -> boolean, set in build

type PanelDef = {
	frame: Frame,
	closeButton: TextButton?,
	onOpen: (() -> ())?,
	tick: (() -> ())?,
}

local defs: { [string]: PanelDef } = {}
local dim: TextButton? = nil
local openListeners: { (name: string?) -> () } = {}

local MENU = {
	{ name = "Shop", icon = "🛒", caption = "menu.shop", color = Theme.C.Green },
	{ name = "Upgrades", icon = "⚡", caption = "menu.upgrades", color = Theme.C.Blue },
	{ name = "Rebirth", icon = "🔁", caption = "menu.rebirth", color = Theme.C.Purple },
	{ name = "Store", icon = "💎", caption = "menu.store", color = Theme.C.Pink },
	{ name = "Daily", icon = "🎁", caption = "menu.daily", color = Theme.C.Orange },
	{ name = "Codes", icon = "🎟️", caption = "menu.codes", color = Theme.C.Teal },
	{ name = "Gifts", icon = "⏰", caption = "menu.gifts", color = Theme.C.Red },
	{ name = "Index", icon = "📖", caption = "menu.index", color = Theme.C.GreenDark },
	{ name = "Invite", icon = "👋", caption = "menu.invite", color = Theme.C.Blue },
	{ name = "Trophies", icon = "🏆", caption = "menu.trophies", color = Theme.C.Gold },
}

local function notify()
	for _, fn in openListeners do
		task.spawn(fn, Panels.current)
	end
end

function Panels.onOpenChanged(fn: (name: string?) -> ())
	table.insert(openListeners, fn)
end

local function hide(def: PanelDef, animated: boolean)
	local sc = def.frame:FindFirstChild("PopScale") :: UIScale?
	if animated and sc then
		local t = C.tween(sc, 0.12, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Once(function()
			-- only hide if it wasn't reopened meanwhile
			if Panels.current == nil or defs[Panels.current] ~= def then
				def.frame.Visible = false
			end
		end)
	else
		def.frame.Visible = false
	end
end

function Panels.open(name: string)
	local def = defs[name]
	if not def then
		return
	end
	if Panels.current == name then
		return
	end
	if Panels.current and defs[Panels.current] then
		hide(defs[Panels.current], false)
	end
	Panels.current = name
	def.frame.Visible = true
	local sc = def.frame:FindFirstChild("PopScale") :: UIScale?
	if sc then
		-- shrink big panels so they always fit the screen (small phones)
		local target = Layout.fit(def.frame.Size.X.Offset, def.frame.Size.Y.Offset, 40)
		sc.Scale = 0.6 * target
		C.tween(sc, 0.28, { Scale = target }, Enum.EasingStyle.Back)
	end
	if dim then
		dim.Visible = true
		C.tween(dim, 0.2, { BackgroundTransparency = 0.55 })
	end
	if def.onOpen then
		task.spawn(def.onOpen)
	end
	if def.tick then
		task.spawn(def.tick)
	end
	notify()
end

function Panels.close()
	local name = Panels.current
	if not name then
		return
	end
	Panels.current = nil
	hide(defs[name], true)
	if dim then
		local d = dim
		local t = C.tween(d, 0.15, { BackgroundTransparency = 1 })
		t.Completed:Once(function()
			if Panels.current == nil then
				d.Visible = false
			end
		end)
	end
	notify()
end

function Panels.toggle(name: string)
	if Panels.current == name then
		Panels.close()
	else
		Panels.open(name)
	end
end

function Panels.register(name: string, def: PanelDef)
	defs[name] = def
	if def.closeButton then
		def.closeButton.Activated:Connect(Panels.close)
	end
end

function Panels.build(root: Instance)
	dim = C.new("TextButton", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 8,
		Parent = root,
	});
	(dim :: TextButton).Activated:Connect(Panels.close)

	-- Left menu, under the stats card. PC: 3 x 3 grid. Touch: 5 x 2 smaller cells right under the compact stats card,
	-- so it ends above the thumbstick zone (bottom 40% of the screen).
	-- PC: a slim 2 x 5 strip down the left edge. Touch: 5 x 2 right under the stats card (above the thumbstick).
	local CELL, GAP = 58, 6
	local menu: Frame = C.new("Frame", {
		Name = "Menu",
		Position = UDim2.fromOffset(12, 100),
		Size = UDim2.fromOffset(2 * CELL + GAP, 5 * CELL + 4 * GAP),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL, CELL),
		CellPadding = UDim2.fromOffset(GAP, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	-- Compact screens (phones): only Shop + "More"; More unfolds the rest over the game and folds again on a pick.
	local expanded = false
	local moreBadge: Frame? = nil
	local moreBtn = C.button({
		Name = "More",
		Parent = menu,
		Text = "📋",
		TextSize = 30,
		Color = Theme.C.Dark,
		Radius = 16,
		LayoutOrder = 0,
		OnClick = function()
			Panels.setMenuExpanded(not expanded)
		end,
	})
	local function layoutMenu()
		local compact = Layout.compact
		moreBtn.Visible = compact
		for i, m in MENU do
			local b = Panels.menuButtons[m.name]
			if b then
				b.Visible = not compact or expanded or i == 1
			end
		end
		menu.ZIndex = if compact and expanded then 7 else 1
		if compact then
			local cols = if expanded then 6 else 2
			local rowsN = if expanded then 2 else 1
			menu.Position = UDim2.fromOffset(12, 78)
			menu.Size = UDim2.fromOffset(cols * CELL + (cols - 1) * GAP, rowsN * CELL + (rowsN - 1) * GAP)
		elseif Layout.isTouch then
			menu.Position = UDim2.fromOffset(12, 78)
			menu.Size = UDim2.fromOffset(5 * CELL + 4 * GAP, 2 * CELL + GAP)
		else
			menu.Position = UDim2.fromOffset(12, 100)
			menu.Size = UDim2.fromOffset(2 * CELL + GAP, 5 * CELL + 4 * GAP)
		end
	end
	Panels.setMenuExpanded = function(on: boolean)
		expanded = on
		layoutMenu()
	end
	Panels.menuExpanded = function(): boolean
		return expanded
	end
	for i, m in MENU do
		local btn = C.button({
			Name = m.name,
			Parent = menu,
			Text = "",
			Color = m.color,
			Radius = 16,
			LayoutOrder = i,
			OnClick = function()
				if Layout.compact and expanded then
					Panels.setMenuExpanded(false)
				end
				Panels.toggle(m.name)
			end,
		})
		C.label(btn, m.icon, UDim2.new(1, 0, 0.62, 0), {
			Position = UDim2.fromScale(0, 0.04),
			TextSize = 28,
			Outline = false,
		})
		local caption = C.label(btn, L(m.caption), UDim2.new(1, -4, 0.3, 0), {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 2, 1, -2),
			TextSize = 13,
			TextWrapped = false,
			Outline = 1.5,
		})
		local fit = caption:FindFirstChild("Fit")
		if fit then
			fit.MinTextSize = 8 -- long translations shrink instead of being cut
		end
		Panels.menuButtons[m.name] = btn
	end
	Layout.onChanged(layoutMenu)
	moreBadge = C.badge(moreBtn)
	local dailyBadge = C.badge(Panels.menuButtons.Daily)
	local giftsBadge = C.badge(Panels.menuButtons.Gifts)
	local indexBadge = C.badge(Panels.menuButtons.Index)

	-- Panels
	Panels.register("Shop", require(script.Parent.ShopPanel).build(root))
	Panels.register("Upgrades", require(script.Parent.UpgradesPanel).build(root))
	Panels.register("Rebirth", require(script.Parent.RebirthPanel).build(root))
	local function openOdds()
		Panels.open("Odds")
	end
	Panels.register("Odds", require(script.Parent.OddsPanel).build(root))
	Panels.register("Store", require(script.Parent.StorePanel).build(root, openOdds))
	Panels.register("Daily", DailyPanel.build(root))
	Panels.register("Codes", require(script.Parent.CodesPanel).build(root))
	Panels.register("Language", require(script.Parent.LanguagePanel).build(root))
	local GiftsPanel = require(script.Parent.GiftsPanel)
	Panels.register("Gifts", GiftsPanel.build(root))
	local IndexPanel = require(script.Parent.IndexPanel)
	Panels.register("Index", IndexPanel.build(root, openOdds))
	Panels.register("Invite", require(script.Parent.InvitePanel).build(root))
	Panels.register("Trophies", require(script.Parent.TrophiesPanel).build(root))
	Panels.register("Auto", require(script.Parent.AutoPanel).build(root, function()
		Panels.open("Upgrades")
	end))
	local StarterPanel = require(script.Parent.StarterPanel)
	Panels.register("Starter", StarterPanel.build(root))
	Panels.starter = StarterPanel
	StarterPanel.wire(Panels)

	-- Language picker button, top-right corner of the stats card.
	local card = root:FindFirstChild("StatsCard")
	if card then
		-- shows the current language code (the globe emoji doesn't render on every device)
		Panels.menuButtons.Language = C.button({
			Name = "LanguageButton",
			Parent = card,
			Text = string.upper(I18n.lang),
			TextSize = 20,
			Color = Theme.C.Blue,
			Radius = 14,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -1),
			Size = UDim2.fromOffset(54, 54),
			OnClick = function()
				Panels.toggle("Language")
			end,
		})
		I18n.onChanged(function()
			C.setText(Panels.menuButtons.Language, string.upper(I18n.lang))
		end)
	end

	Layout.onChanged(function()
		local cur = Panels.current and defs[Panels.current]
		local sc = cur and cur.frame:FindFirstChild("PopScale") :: UIScale?
		if cur and sc then
			sc.Scale = Layout.fit(cur.frame.Size.X.Offset, cur.frame.Size.Y.Offset, 40)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == Enum.KeyCode.Escape then
			Panels.close()
		end
	end)

	-- Timers: open panel countdowns + daily badge.
	task.spawn(function()
		while true do
			local cur = Panels.current and defs[Panels.current]
			if cur and cur.tick then
				pcall(cur.tick)
			end
			dailyBadge.Visible = State.data ~= nil and DailyPanel.canClaim()
			local nGifts = GiftsPanel.readyCount()
			giftsBadge.Visible = nGifts > 0
			C.setBadgeText(giftsBadge, tostring(nGifts))
			indexBadge.Visible = IndexPanel.claimableCount() > 0
			if moreBadge then
				-- folded away: the More button carries the alert for whatever is hidden behind it
				moreBadge.Visible = Layout.compact and not expanded and (dailyBadge.Visible or giftsBadge.Visible or indexBadge.Visible)
			end
			task.wait(0.25)
		end
	end)
end

return Panels
