--!nonstrict
-- Seed Shop: every seed with rarity, price, sell value, grow time, personal stock and buy x1/x5.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local ShopPanel = {}

local function restockProductId(): number
	for _, p in Config.DevProducts do
		if p.key == "Restock" then
			return p.id
		end
	end
	return 0
end

function ShopPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "ShopPanel",
		Title = L("panel.shop"),
		Icon = "🛒",
		Color = Theme.C.Green,
		Size = UDim2.fromOffset(700, 520),
	})

	local top: Frame = C.new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Parent = p.content,
	})
	local restockLbl = C.label(top, L("shop.restockSoon"), UDim2.new(1, -250, 1, 0), {
		TextSize = 22,
		TextColor3 = Theme.C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Outline = false,
	})
	local restockId = restockProductId()
	if restockId ~= 0 then
		C.button({
			Parent = top,
			Text = L("shop.restockNow"),
			TextSize = 18,
			Color = Theme.C.Yellow,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(240, 56),
			OnClick = function()
				pcall(function()
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, restockId)
				end)
			end,
		})
	end

	-- Rewarded video -> free restock (only with an AdRestock product id, ads available and daily cap left)
	local adProductId = 0
	for _, ap in Config.AdProducts do
		if ap.key == "AdRestock" then
			adProductId = ap.id
		end
	end
	local adBtn = C.button({
		Name = "AdRestock",
		Parent = top,
		Text = L("shop.adRestock"),
		TextSize = 18,
		Color = Theme.C.Teal,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, if restockId ~= 0 then -250 else 0, 0, 0),
		Size = UDim2.fromOffset(230, 56),
		OnClick = function()
			Net.request("WatchAd", { placement = "restock" }, { silentOk = true })
		end,
	})
	adBtn.Visible = false
	local function checkAd()
		adBtn.Visible = false
		local d = State.data
		if adProductId == 0 or not d or (d.adsLeft or 0) <= 0 then
			return
		end
		local ok, res = pcall(function()
			return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		end)
		if ok and type(res) == "table" and res.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable then
			adBtn.Visible = true
			restockLbl.Size = UDim2.new(1, if restockId ~= 0 then -490 else -240, 1, 0)
		end
	end

	local list = C.scroller(p.content, UDim2.new(1, 0, 1, -64), UDim2.fromOffset(0, 64))
	C.list(list, true, 10)

	type Row = { buy1: TextButton, buy5: TextButton, stock: TextLabel, owned: TextLabel, card: Frame }
	local rows: { [string]: Row } = {}

	for i, seed in Config.Seeds do
		local rc = Theme.rarityColor(seed.rarity)
		local card = C.card(list, UDim2.new(1, 0, 0, 120), Theme.darken(rc, 0.1), { LayoutOrder = i })

		local icon: Frame = C.new("Frame", {
			Size = UDim2.fromOffset(80, 80),
			Position = UDim2.fromOffset(12, 20),
			BackgroundColor3 = rc,
			Parent = card,
		})
		C.corner(icon, 16)
		C.stroke(icon, 3, Theme.darken(rc, 0.4))
		C.gradient(icon, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190), 90)
		C.label(icon, Theme.seedEmoji(seed.id), UDim2.fromScale(1, 1), { TextSize = 46, Outline = false })

		C.label(card, L("seed." .. seed.id), UDim2.fromOffset(250, 30), {
			Position = UDim2.fromOffset(106, 8),
			TextSize = 26,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Outline = false,
		})
		local tags: Frame = C.new("Frame", {
			Size = UDim2.fromOffset(300, 24),
			Position = UDim2.fromOffset(106, 40),
			BackgroundTransparency = 1,
			Parent = card,
		})
		C.list(tags, false, 6)
		C.pill(tags, L("rarity." .. seed.rarity), rc, { LayoutOrder = 1 })
		if seed.regrowTime then
			C.pill(tags, L("shop.regrows"), Theme.C.Green, { LayoutOrder = 2 })
		end
		C.label(card, L("shop.info", { cash = Format.cash(seed.sellValue), time = Format.time(seed.growTime) }), UDim2.fromOffset(300, 22), {
			Position = UDim2.fromOffset(106, 70),
			Font = Theme.FontAlt,
			TextSize = 16,
			TextColor3 = Theme.C.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Outline = false,
		})

		local stock = C.label(card, "", UDim2.fromOffset(230, 24), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 8),
			TextSize = 18,
			TextColor3 = Theme.C.GreenDark,
			TextXAlignment = Enum.TextXAlignment.Right,
			Outline = false,
		})
		local owned = C.label(card, "", UDim2.fromOffset(230, 16), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 32),
			Font = Theme.FontAlt,
			TextSize = 14,
			TextColor3 = Theme.C.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Right,
			Outline = false,
		})
		local buy1 = C.button({
			Parent = card,
			Text = Format.cash(seed.price),
			TextSize = 22,
			Color = Theme.C.Green,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -100, 1, -10),
			Size = UDim2.fromOffset(136, 56),
			OnClick = function()
				Net.request("BuySeed", { seedId = seed.id, amount = 1 })
			end,
		})
		local buy5 = C.button({
			Parent = card,
			Text = "x5",
			TextSize = 22,
			Color = Theme.C.Blue,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -10),
			Size = UDim2.fromOffset(80, 56),
			OnClick = function()
				Net.request("BuySeed", { seedId = seed.id, amount = 5 })
			end,
		})
		local seedProduct = Config.SeedProducts[seed.id] or 0
		if seedProduct ~= 0 then
			-- second way to pay, next to the cash price (never out of stock)
			local robux = C.button({
				Name = "Robux",
				Parent = card,
				Text = "R$",
				TextSize = 20,
				Color = Theme.C.Purple,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -244, 1, -10),
				Size = UDim2.fromOffset(96, 56),
				OnClick = function()
					pcall(function()
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, seedProduct)
					end)
				end,
			})
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(seedProduct, Enum.InfoType.Product)
				end)
				if ok and type(info) == "table" and info.PriceInRobux then
					C.setText(robux, "R$ " .. tostring(info.PriceInRobux))
				end
			end)
		end
		rows[seed.id] = { buy1 = buy1, buy5 = buy5, stock = stock, owned = owned, card = card }
	end

	local function refresh()
		local cash = State.cash()
		for id, row in rows do
			local seed = Config.SeedById[id]
			local n = State.stock[id] or 0
			if n > 0 then
				row.stock.Text = I18n.t("shop.inStock", { n = n })
				row.stock.TextColor3 = Theme.C.GreenDark
			else
				row.stock.Text = I18n.t("shop.soldOut")
				row.stock.TextColor3 = Theme.C.Red
			end
			local have = State.seedCount(id)
			row.owned.Text = if have > 0 then I18n.t("shop.youHave", { n = have }) else ""
			C.setEnabled(row.buy1, n >= 1 and cash >= seed.price)
			C.setEnabled(row.buy5, n >= 5 and cash >= seed.price * 5)
			row.card.BackgroundColor3 = if n > 0 then Theme.C.Card else Color3.fromRGB(236, 232, 224)
		end
	end

	State.onChanged(function(kind)
		if kind == "state" or kind == "stock" then
			refresh()
		end
	end)

	local function tick()
		local left = State.nextRestockAt - State.now()
		restockLbl.Text = if State.nextRestockAt > 0 then I18n.t("shop.restockIn", { time = Format.time(left) }) else I18n.t("shop.restockSoon")
	end

	return {
		frame = p.frame,
		closeButton = p.close,
		onOpen = function()
			refresh()
			task.spawn(checkAd)
		end,
		tick = tick,
	}
end

return ShopPanel
