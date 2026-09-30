--!nonstrict
-- Robux store: game passes + developer products from Config (only ids ~= 0).
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Odds = require(ReplicatedStorage.Shared.Odds)

local player = Players.LocalPlayer

local StorePanel = {}

-- May this player be offered this store item? (paid random items are hidden where Roblox restricts them)
function StorePanel.canOffer(key: string): boolean
	local d = State.data
	local allowed = d ~= nil and type(d.policy) == "table" and d.policy.paidRandom == true
	return Odds.canOffer(key, allowed)
end

function StorePanel.build(root: Instance, openOdds: (() -> ())?)
	local p = C.panel(root, {
		Name = "StorePanel",
		Title = L("panel.store"),
		Icon = "💎",
		Color = Theme.C.Pink,
		Size = UDim2.fromOffset(700, 520),
	})

	local passes, products = {}, {}
	for _, gp in Config.GamePasses do
		if gp.id ~= 0 then
			table.insert(passes, gp)
		end
	end
	for _, dp in Config.DevProducts do
		if dp.id ~= 0 then
			table.insert(products, dp)
		end
	end

	if #passes == 0 and #products == 0 then
		C.label(p.content, L("store.soon"), UDim2.fromScale(1, 0.7), {
			TextSize = 40,
			TextColor3 = Theme.C.Pink,
			Outline = 3,
		})
		C.label(p.content, L("store.soonDesc"), UDim2.new(1, 0, 0.3, 0), {
			Position = UDim2.fromScale(0, 0.7),
			Font = Theme.FontAlt,
			TextSize = 18,
			TextColor3 = Theme.C.InkSoft,
			Outline = false,
		})
		return { frame = p.frame, closeButton = p.close }
	end

	local list = C.scroller(p.content, UDim2.fromScale(1, 1))
	C.list(list, true, 10)

	local passButtons: { [string]: TextButton } = {}
	local cards: { [string]: Frame } = {}

	local function section(order: number, title: any, items: { any }, isPass: boolean)
		if #items == 0 then
			return
		end
		C.label(list, title, UDim2.new(1, 0, 0, 34), {
			TextSize = 26,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Outline = false,
			LayoutOrder = order,
		})
		local grid: Frame = C.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order + 1,
			Parent = list,
		})
		C.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(196, 232),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for i, item in items do
			local color = if isPass then Theme.C.Purple else Theme.C.Blue
			local card = C.card(grid, UDim2.new(), Theme.darken(color, 0.1), { LayoutOrder = i })
			cards[item.key] = card
			if Odds.RandomItems[item.key] then
				-- chances must be one tap away from the price
				local odds = C.button({
					Name = "Odds",
					Parent = card,
					Text = "%",
					TextSize = 22,
					Color = Theme.C.Purple,
					Radius = 27,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -6, 0, 6),
					Size = UDim2.fromOffset(54, 54),
					OnClick = function()
						if openOdds then
							openOdds()
						end
					end,
				})
				odds.ZIndex = 3
			end
			C.icon(card, Theme.ProductEmoji[item.key] or "🎁", UDim2.new(1, 0, 0, 60), {
				Position = UDim2.fromOffset(0, 8),
				TextSize = 48,
				Outline = false,
			})
			C.label(card, L((if isPass then "pass." else "product.") .. item.key .. ".name"), UDim2.new(1, -12, 0, 28), {
				Position = UDim2.fromOffset(6, 70),
				TextSize = 22,
				TextColor3 = Theme.C.Ink,
				Outline = false,
			})
			C.label(card, L((if isPass then "pass." else "product.") .. item.key .. ".desc"), UDim2.new(1, -16, 0, 56), {
				Position = UDim2.fromOffset(8, 98),
				Font = Theme.FontAlt,
				TextSize = 13,
				TextColor3 = Theme.C.InkSoft,
				TextYAlignment = Enum.TextYAlignment.Top,
				Outline = false,
			})
			local btn = C.button({
				Parent = card,
				Text = "R$ " .. tostring(item.priceHint),
				TextSize = 22,
				Color = Theme.C.Green,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -24, 0, 56),
				OnClick = function()
					pcall(function()
						if isPass then
							MarketplaceService:PromptGamePassPurchase(player, item.id)
						else
							MarketplaceService:PromptProductPurchase(player, item.id)
						end
					end)
				end,
			})
			if isPass then
				passButtons[item.key] = btn
			end
			-- Real price from the platform (falls back to priceHint).
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(item.id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
				end)
				if ok and type(info) == "table" and info.PriceInRobux and not (isPass and State.hasPass(item.key)) then
					C.setText(btn, "R$ " .. tostring(info.PriceInRobux))
					btn:SetAttribute("PriceText", "R$ " .. tostring(info.PriceInRobux))
				end
			end)
			btn:SetAttribute("PriceText", "R$ " .. tostring(item.priceHint))
		end
	end

	section(1, L("store.passes"), passes, true)
	section(10, L("store.boosts"), products, false)

	local function refresh()
		for key, card in cards do
			card.Visible = StorePanel.canOffer(key)
		end
		for key, btn in passButtons do
			if State.hasPass(key) then
				C.setText(btn, L("store.owned"))
				C.setEnabled(btn, false)
			else
				local t = btn:GetAttribute("PriceText")
				C.setText(btn, if type(t) == "string" then t else L("store.buy"))
				C.setEnabled(btn, true)
			end
		end
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return StorePanel
