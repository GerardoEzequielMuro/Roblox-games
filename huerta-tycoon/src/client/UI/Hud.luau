--!nonstrict
-- Always-on HUD: cash card, basket bar with SELL, and the right-side action buttons.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)
local Toasts = require(script.Parent.Toasts)
local Teleport = require(script.Parent.Teleport)
local Layout = require(script.Parent.Layout)
local Juice = require(script.Parent.Juice)
local Sound = require(script.Parent.Sound)

local Hud = {}
Hud.refs = {} :: { [string]: GuiObject }
Hud.onAuto = nil :: (() -> ())?

-- Compact HUD metrics (design pixels). Buttons keep a 54 px short side so they stay >= 44 real px on a
-- ~920x505 screen; everything else is as small as it can be so the garden stays visible.
Hud.CARD_W = 236
Hud.CARD_H = 84
Hud.CARD_H_TOUCH = 62
Hud.ACTION_W = 148
Hud.ACTIONS = 3 -- Harvest All, Plant All, Auto
Hud.BASKET_W = 430
Hud.BASKET_Y = 112 -- distance from the bottom edge to the basket bar's bottom

local shownCash = 0
local targetCash = 0
local hasCash = false

-- The server replies in the player's language, so match against the same translated sentence.
local function isDistanceError(msg: string?): boolean
	return msg ~= nil and msg == I18n.t("err.sellFar")
end

function Hud.build(root: Instance)
	-- ===== Cash / stats card (top-left, below the Roblox top bar) =====
	local card: Frame = C.new("Frame", {
		Name = "StatsCard",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(Hud.CARD_W, Hud.CARD_H),
		BackgroundColor3 = Theme.C.Dark,
		BackgroundTransparency = 0.12,
		Parent = root,
	})
	C.corner(card, 18)
	C.stroke(card, 3, Theme.C.Stroke, 0.2)
	C.gradient(card, Color3.new(1, 1, 1), Color3.fromRGB(176, 186, 206), 90)
	C.padding(card, 7, 10)

	-- coin badge: where sold crops fly to
	local coin: Frame = C.new("Frame", {
		Name = "Coin",
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.C.Gold,
		Parent = card,
	})
	C.round(coin)
	C.stroke(coin, 3, Theme.darken(Theme.C.Gold, 0.5))
	C.gradient(coin, Color3.new(1, 1, 1), Color3.fromRGB(215, 190, 140), 60)
	C.label(coin, "$", UDim2.fromScale(1, 1), { TextSize = 22, TextColor3 = Color3.fromRGB(255, 250, 210), Outline = 2, NoFit = true })
	local coinScale = C.new("UIScale", { Parent = coin })

	local cashLbl = C.label(card, "$0", UDim2.new(1, -100, 0, 36), {
		Name = "Cash",
		Position = UDim2.fromOffset(40, 0),
		TextSize = 34,
		TextColor3 = Theme.C.Cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Outline = 3,
	})
	local cashScale = C.new("UIScale", { Parent = cashLbl })
	local rateLbl = C.label(card, "+$0/min", UDim2.new(1, -62, 0, 16), {
		Position = UDim2.fromOffset(2, 37),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(200, 255, 190),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local infoLbl = C.label(card, "", UDim2.new(1, 0, 0, 16), {
		Position = UDim2.fromOffset(2, 54),
		TextSize = 13,
		TextWrapped = false,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- ===== Basket bar (bottom-center, above the hotbar) =====
	local basket: Frame = C.new("Frame", {
		Name = "BasketBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Hud.BASKET_Y),
		Size = UDim2.fromOffset(Hud.BASKET_W, 62),
		BackgroundColor3 = Theme.C.Dark,
		BackgroundTransparency = 0.12,
		Parent = root,
	})
	C.corner(basket, 18)
	C.stroke(basket, 3, Theme.C.Stroke, 0.2)
	local basketBar = C.progressBar(basket, UDim2.new(1, -156, 0, 38), Theme.C.Orange, {
		Position = UDim2.fromOffset(10, 12),
	})
	basketBar.label.TextSize = 18
	basketBar.label.Text = "🎒 0/0"

	local sellBtn = C.button({
		Name = "Sell",
		Parent = basket,
		Text = L("hud.sell"),
		TextSize = 22,
		Color = Theme.C.Gold,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(132, 54),
	})
	local sellPulse = C.new("UIScale", { Parent = basket })

	local tpSellBtn = C.button({
		Name = "TeleportSell",
		Parent = basket,
		Text = L("hud.tpSell"),
		TextSize = 20,
		Color = Theme.C.Orange,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 0, -8),
		Size = UDim2.fromOffset(220, 56),
	})
	tpSellBtn.Visible = false
	local tpHideToken = 0

	local function showTeleportSell()
		tpHideToken += 1
		local token = tpHideToken
		tpSellBtn.Visible = true
		task.delay(10, function()
			if token == tpHideToken then
				tpSellBtn.Visible = false
			end
		end)
	end

	tpSellBtn.Activated:Connect(function()
		if Teleport.toSellStand() then
			tpSellBtn.Visible = false
			tpHideToken += 1
		end
	end)

	sellBtn.Activated:Connect(function()
		if sellBtn:GetAttribute("Disabled") then
			return
		end
		local d = State.data
		if d and (d.backpackCount or 0) <= 0 then
			Toasts.show(L("hud.basketEmpty"), "info")
			return
		end
		local ok, msg = Net.request("SellAll", nil, { quiet = true })
		if ok then
			tpSellBtn.Visible = false
			return
		end
		if msg then
			Toasts.show(msg, "error")
		end
		if isDistanceError(msg) and not State.hasPass("SellAnywhere") then
			showTeleportSell()
		end
	end)

	-- ===== Right-side action column =====
	local actions: Frame = C.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(Hud.ACTION_W, Hud.ACTIONS * 54 + (Hud.ACTIONS - 1) * 8),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local actionsList = C.list(actions, true, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

	local harvestBtn = C.button({
		Name = "HarvestAll",
		Parent = actions,
		Text = L("hud.harvestAll"),
		TextSize = 17,
		Color = Theme.C.Green,
		Size = UDim2.fromOffset(Hud.ACTION_W, 54),
		LayoutOrder = 1,
		OnClick = function()
			Net.request("HarvestAll")
		end,
	})
	local plantBtn, plantLbl = C.button({
		Name = "PlantAll",
		Parent = actions,
		Text = L("hud.plantAll", nil, "🌱 "),
		TextSize = 17,
		Color = Theme.C.Teal,
		Size = UDim2.fromOffset(Hud.ACTION_W, 54),
		LayoutOrder = 2,
		OnClick = function()
			local seed = State.selectedSeed
			if not seed or State.seedCount(seed) <= 0 then
				Toasts.show(L("hud.selectSeed"), "error")
				return
			end
			Net.request("PlantAll", { seedId = seed })
		end,
	})
	-- ===== Teleports: top-center row, each button in the color of its place =====
	local TP_W, TP_GAP = 108, 6
	local teleports: Frame = C.new("Frame", {
		Name = "Teleports",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(3 * TP_W + 2 * TP_GAP, 54),
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.list(teleports, false, TP_GAP, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local shopTpBtn = C.button({
		Name = "ShopTeleport",
		Parent = teleports,
		Text = L("tp.seeds"),
		TextSize = 18,
		Color = Theme.C.Green,
		Size = UDim2.fromOffset(TP_W, 54),
		LayoutOrder = 1,
		OnClick = function()
			Teleport.toShop()
		end,
	})
	local gardenBtn = C.button({
		Name = "Garden",
		Parent = teleports,
		Text = L("tp.garden"),
		TextSize = 18,
		Color = Color3.fromRGB(176, 112, 60),
		Size = UDim2.fromOffset(TP_W, 54),
		LayoutOrder = 2,
		OnClick = function()
			Teleport.toGarden()
		end,
	})
	C.button({
		Name = "SellTeleport",
		Parent = teleports,
		Text = L("tp.sell"),
		TextSize = 18,
		Color = Theme.C.Gold,
		Size = UDim2.fromOffset(TP_W, 54),
		LayoutOrder = 3,
		OnClick = function()
			Teleport.toSellStand()
		end,
	})

	-- Auto-farm switchboard: shows ON/OFF at a glance, opens the panel (wired by Main through Hud.onAuto)
	local autoBtn = C.button({
		Name = "Auto",
		Parent = actions,
		Text = L("auto.off", nil, "🤖 "),
		TextSize = 17,
		Color = Theme.C.Grey,
		Size = UDim2.fromOffset(Hud.ACTION_W, 54),
		LayoutOrder = 3,
		OnClick = function()
			if Hud.onAuto then
				Hud.onAuto()
			end
		end,
	})

	-- ===== Responsive placement =====
	-- PC: stats top-left, teleports top-center, 3 actions mid-right, basket bottom-center.
	-- Stacked (touch or tiny screens): short stats card, actions top-right (clear of the jump button), basket
	-- inside x = 35%..75% so it never sits on the thumbstick or jump zones.
	Layout.onChanged(function()
		local stacked = Layout.stacked
		local h = 54
		card.Size = UDim2.fromOffset(Hud.CARD_W, if stacked then Hud.CARD_H_TOUCH else Hud.CARD_H)
		infoLbl.Visible = not stacked
		actions.AnchorPoint = if stacked then Vector2.new(1, 0) else Vector2.new(1, 0.5)
		actions.Position = if stacked then UDim2.new(1, -12, 0, 8) else UDim2.new(1, -12, 0.5, 0)
		actions.Size = UDim2.fromOffset(Hud.ACTION_W, Hud.ACTIONS * h + (Hud.ACTIONS - 1) * 8)
		actionsList.VerticalAlignment = if stacked then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
		for _, b in actions:GetChildren() do
			if b:IsA("TextButton") then
				b.Size = UDim2.fromOffset(Hud.ACTION_W, h)
			end
		end
		-- teleports sit between the stats card and the action column (narrower buttons on compact screens)
		local tpW = if Layout.compact then 96 else TP_W
		for _, b in teleports:GetChildren() do
			if b:IsA("TextButton") then
				b.Size = UDim2.fromOffset(tpW, 54)
			end
		end
		teleports.Size = UDim2.fromOffset(3 * tpW + 2 * TP_GAP, 54)
		local rowW = teleports.Size.X.Offset
		local minCenter = 12 + Hud.CARD_W + 8 + rowW / 2
		teleports.Position = UDim2.fromOffset(math.max(Layout.canvas.X / 2, minCenter), 8)
		if stacked then
			local w = math.clamp(math.floor(Layout.canvas.X * 0.36), 300, Hud.BASKET_W)
			basket.Position = UDim2.new(0.55, 0, 1, -Hud.BASKET_Y)
			basket.Size = UDim2.fromOffset(w, 62)
			basketBar.label.TextSize = if w < 400 then 15 else 18
		else
			basket.Position = UDim2.new(0.5, 0, 1, -Hud.BASKET_Y)
			basket.Size = UDim2.fromOffset(Hud.BASKET_W, 62)
			basketBar.label.TextSize = 18
		end
	end)

	Hud.refs = {
		statsCard = card,
		basketBar = basket,
		sellButton = sellBtn,
		teleportSellButton = tpSellBtn,
		harvestAllButton = harvestBtn,
		plantAllButton = plantBtn,
		gardenButton = gardenBtn,
		shopTeleportButton = shopTpBtn,
		autoButton = autoBtn,
		teleports = teleports,
	}

	-- ===== Updates =====
	local lastFull = false
	local lastCount, lastCash = 0, math.huge
	local function refresh()
		local d = State.data
		if not d then
			return
		end
		targetCash = d.cash or 0
		-- a sale (from the button, the stand or Sell Anywhere): the basket empties and the cash goes up
		local countNow = d.backpackCount or 0
		if lastCount > 0 and countNow == 0 and targetCash > lastCash then
			Juice.coins(basket, coin, lastCount)
			Sound.play("sell")
			task.delay(0.55, function()
				coinScale.Scale = 1.35
				C.tween(coinScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
		lastCount, lastCash = countNow, targetCash
		if not hasCash then
			hasCash = true
			shownCash = targetCash
			cashLbl.Text = Format.cash(shownCash)
		end
		rateLbl.Text = I18n.t("hud.rate", { cash = Format.cash(d.earnRate or 0) })
		local mult = d.mult or {}
		infoLbl.Text = string.format("⭐ %d   💰 %s   🌱 %s   🍀 %s", d.rebirths or 0, C.fmtMult(mult.cash), C.fmtMult(mult.growth), C.fmtMult(mult.luck))

		local count, cap = d.backpackCount or 0, math.max(1, d.backpackCap or Config.BackpackBase)
		local full = count >= cap
		basketBar.set(count / cap)
		basketBar.fill.BackgroundColor3 = if full then Theme.C.Red else Theme.C.Orange
		basketBar.label.Text = I18n.t(if full then "hud.basketFull" else "hud.basket", { count = count, cap = cap, cash = Format.cash(d.backpackValue or 0) })
		if full and not lastFull then
			Toasts.show(L("hud.basketFullToast"), "info")
		end
		lastFull = full
	end

	local lastAuto: boolean? = nil
	local function refreshAuto()
		local a = State.data and State.data.auto
		local on = type(a) == "table" and type(a.on) == "table" and (a.on.harvest or a.on.plant or a.on.sell) == true
		if on ~= lastAuto then
			lastAuto = on
			C.setColor(autoBtn, if on then Theme.C.Green else Theme.C.Grey)
			C.setText(autoBtn, L(if on then "auto.on" else "auto.off", nil, "🤖 "))
		end
	end

	local function refreshPlant()
		local seed = State.selectedSeed
		I18n.set(plantLbl, "Text", L("hud.plantAll", nil, (if seed then Theme.seedEmoji(seed) else "🌱") .. " "))
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
			refreshPlant()
			lastAuto = nil
			refreshAuto()
		elseif kind == "selected" then
			refreshPlant()
		end
	end)

	-- Cash count-up + basket-full pulse
	local lastShownText = ""
	RunService.RenderStepped:Connect(function(dt)
		if hasCash and shownCash ~= targetCash then
			local diff = targetCash - shownCash
			local wasUp = diff > 0
			shownCash += diff * math.min(1, dt * 7)
			if math.abs(targetCash - shownCash) < math.max(1, math.abs(targetCash) * 0.0005) then
				shownCash = targetCash
			end
			local txt = Format.cash(shownCash)
			if txt ~= lastShownText then
				lastShownText = txt
				cashLbl.Text = txt
				if wasUp then
					cashScale.Scale = 1.12
					C.tween(cashScale, 0.2, { Scale = 1 })
				end
			end
		end
		if lastFull then
			sellPulse.Scale = 1 + math.abs(math.sin(os.clock() * 4)) * 0.04
		elseif sellPulse.Scale ~= 1 then
			sellPulse.Scale = 1
		end
	end)
end

return Hud
