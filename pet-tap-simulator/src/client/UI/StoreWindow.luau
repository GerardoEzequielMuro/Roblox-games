--!strict
-- Robux store: game passes and developer products. Items with id 0 in Config are hidden,
-- and so are paid random items for players PolicyService restricts. The cards are rebuilt
-- when that flag arrives or changes (it is unknown until the first state snapshot).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)

local StoreWindow = {}

local PASS_ICONS = { AutoTap = "🤖", TripleHatch = "🥚", OctoHatch = "🥚", AutoHatch = "🔄", AutoRebirth = "🔁", Lucky = "🍀", SuperLucky = "🍀", VIP = "👑", PetSlots = "🐾", PetSlots2 = "🐾", Storage = "🎒", DoubleTaps = "✌️", MagicEggs = "✨" }
local PRODUCT_ICONS = { taps = "👆", gems = "💎", luck = "🍀", egg = "🔮" }
-- icon pack names where the emoji's default mapping is not the right picture
local PRODUCT_ICON_NAMES = { taps = "coin", egg = "egg" }
-- ribbon on the biggest pack of each kind
local BEST = { TapsLarge = true, GemsHuge = true, MagicEgg3 = true }

-- Cards on screen: passes, products (playtest).
StoreWindow.counts = function(): (number, number)
	return 0, 0
end
StoreWindow.rebuild = function() end

function StoreWindow.init()
	local w = Windows.create("Store", "🛒", "win.store", Theme.Green, Vector2.new(820, 520))
	local scroll = Theme.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Ink,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = w.body,
	}, { Theme.list(Enum.FillDirection.Vertical, 12), Theme.padding(6) })

	local function section(titleKey: string, order: number): (Frame, TextLabel)
		local label = Theme.text({ Key = titleKey, Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 30, LayoutOrder = order, Parent = scroll })
		local grid = Theme.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order + 1,
			Parent = scroll,
		}, { Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(180, 236), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }) })
		return grid, label
	end

	local passGrid, passTitle = section("store.passes", 1)
	local productGrid, productTitle = section("store.boosts", 3)
	-- empty state (no product IDs configured yet): big cart + message, centred
	local empty = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 380), LayoutOrder = 10, Visible = false, Parent = scroll }) :: Frame
	local emptyDisc = Theme.new("Frame", { Size = UDim2.fromOffset(150, 150), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), Parent = empty }, { Theme.corner(75), Theme.stroke(4), Theme.gradient(Theme.White, Theme.lighten(Theme.Green, 0.55)) })
	Theme.icon("\u{1F6D2}", { Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = emptyDisc })
	Theme.text({ Key = "store.soon", Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 236), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 32, Parent = empty })

	type Card = { frame: Frame, buy: TextButton, key: string }
	local passCards: { Card } = {}
	local productCards = 0

	-- One icon template for every pass and product: a disc in the item's colour with turning
	-- rays behind the emoji (the look every simulator uses for its pass icons).
	-- oddsKey: product whose random reward's odds are printed on the card (paid random items
	-- show numeric odds before the purchase prompt).
	local oddsLabels: { [TextLabel]: string } = {}
	local function card(parent: Instance, order: number, color: Color3, icon: string, iconName: string?, nameKey: string, descKey: string, price: number, best: boolean, onBuy: () -> (), oddsKey: string?): (Frame, TextButton)
		local f = Theme.panel({ LayoutOrder = order, BackgroundColor3 = Color3.new(1, 1, 1), Parent = parent })
		local top = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, Parent = f }, { Theme.corner(16), Theme.gradient(Theme.lighten(color, 0.35), Theme.darken(color, 0.05)) })
		local rays = Theme.new("Frame", { Size = UDim2.fromOffset(230, 230), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = top })
		for k = 0, 5 do
			Theme.new("Frame", { Size = UDim2.new(0, 22, 1, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = k * 30, BackgroundColor3 = Theme.White, BackgroundTransparency = 0.78, BorderSizePixel = 0, Parent = rays })
		end
		TweenService:Create(rays, TweenInfo.new(20, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		local disc = Theme.new("Frame", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = top }, { Theme.corner(32), Theme.stroke(3), Theme.gradient(Theme.White, Theme.lighten(color, 0.6)) })
		Theme.icon(icon, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = disc }, iconName)
		if best then
			local ribbon = Theme.new("Frame", { Size = UDim2.fromOffset(96, 24), Position = UDim2.new(1, -6, 0, 6), AnchorPoint = Vector2.new(1, 0), Rotation = 6, BackgroundColor3 = Theme.Red, ZIndex = 3, Parent = f }, { Theme.corner(8), Theme.stroke(2) })
			local t = Theme.text({ Key = "store.best", Size = UDim2.new(1, -6, 1, -2), Position = UDim2.fromOffset(3, 1), MaxTextSize = 15, Parent = ribbon })
			t.ZIndex = 4
		end
		Theme.text({ Key = nameKey, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 80), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 22, Parent = f })
		Theme.text({ Key = descKey, TextWrapped = true, Size = UDim2.new(1, -12, 0, if oddsKey then 30 else 64), Position = UDim2.fromOffset(6, 104), TextColor3 = Theme.darken(Theme.Grey, 0.25), Stroke = false, MaxTextSize = 16, Parent = f })
		if oddsKey then
			local plate = Theme.new("Frame", { Name = "OddsPlate", Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 134), BackgroundColor3 = Theme.lighten(color, 0.8), Parent = f }, { Theme.corner(8) })
			local odds = Theme.text({ Name = "Odds", Text = Purchase.cardOdds(oddsKey) or "", TextWrapped = true, Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 14, Parent = plate })
			odds.AutoLocalize = false
			oddsLabels[odds] = oddsKey
		end
		-- Robux prices are purple everywhere
		local b = Theme.button({ Text = "R$ " .. price, Color = Theme.Purple, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1), TextSize = 24, Parent = f, OnClick = onBuy })
		return f, b
	end

	local function refresh()
		-- the Golden chance in the odds changes with the Magic Eggs pass and Golden Weekend
		for label, key in oddsLabels do
			if label.Parent then
				label.Text = Purchase.cardOdds(key) or ""
			else
				oddsLabels[label] = nil
			end
		end
		for _, c in passCards do
			if Net.owns(c.key) then
				Theme.setButton(c.buy, Lang.t("store.owned") .. " ✓", Theme.Grey)
			end
		end
	end

	local function build()
		for _, grid in { passGrid, productGrid } do
			for _, c in grid:GetChildren() do
				if c:IsA("Frame") then
					c:Destroy()
				end
			end
		end
		table.clear(passCards)
		table.clear(oddsLabels)
		productCards = 0
		for i, pass in Config.Passes do
			if Purchase.passAvailable(pass.key) then
				local key = pass.key
				local f, b = card(passGrid, i, Palette.rgb(pass.color), PASS_ICONS[pass.key] or "⭐", nil, "pass." .. pass.key .. ".name", "pass." .. pass.key .. ".desc", pass.price, false, function()
					if not Net.owns(key) then
						Purchase.pass(key)
					end
				end, if Purchase.cardOdds(key) then key else nil)
				table.insert(passCards, { frame = f, buy = b, key = key })
			end
		end
		for i, product in Config.Products do
			if Purchase.productAvailable(product.key) and not Config.HiddenProductKinds[product.kind] then
				productCards += 1
				local key = product.key
				card(productGrid, i, Palette.rgb(product.color), PRODUCT_ICONS[product.kind] or "⭐", PRODUCT_ICON_NAMES[product.kind], "product." .. product.key .. ".name", "product." .. product.key .. ".desc", product.price, BEST[product.key] == true, function()
					Purchase.product(key)
				end, if Purchase.cardOdds(key) then key else nil)
			end
		end
		empty.Visible = #passCards + productCards == 0
		passTitle.Visible, passGrid.Visible = #passCards > 0, #passCards > 0
		productTitle.Visible, productGrid.Visible = productCards > 0, productCards > 0
		refresh()
	end
	StoreWindow.rebuild = build
	StoreWindow.counts = function(): (number, number)
		return #passCards, productCards
	end

	build()
	w.onOpen = refresh
	Lang.Changed:Connect(refresh)
	local lastRestricted: any = "unset"
	Net.Changed:Connect(function(kind)
		if kind ~= "full" then
			return
		end
		local restricted = Purchase.restricted()
		if restricted ~= lastRestricted then
			lastRestricted = restricted
			build()
		elseif Windows.isOpen("Store") then
			refresh()
		end
	end)
end

return StoreWindow
