--!strict
-- Game passes (ownership cache + purchase-finished grant) and developer products
-- (ProcessReceipt, idempotent by PurchaseId stored in the profile and saved before
-- returning PurchaseGranted). Everything sold is cosmetic or comfort; there are no random
-- items and nothing here reaches into a match.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Cosmetics = require(script.Parent.Cosmetics)
local SeasonService = require(script.Parent.SeasonService)

local Monetization = {}

local MAX_RECEIPTS = 60

local passByGamepassId: { [number]: typeof(Config.Passes[1]) } = {}
for _, pass in Config.Passes do
	if pass.id ~= 0 then
		passByGamepassId[pass.id] = pass
	end
end
local function productForId(id: number): typeof(Config.Products[1])?
	for _, product in Config.Products do
		if product.id ~= 0 and product.id == id then
			return product
		end
	end
	return nil
end

-- Starter Pack: live product, not bought, within 24 h of the first join. Fixed contents.
function Monetization.starterState(p: Data.Profile): { available: boolean, endsAt: number, price: number, fullPrice: number }
	local product = Config.ProductByKey.StarterPack
	local endsAt = p.firstJoin + Config.StarterPack.windowSeconds
	local available = product ~= nil and product.id ~= 0 and not p.starterBought and os.time() < endsAt
	return { available = available, endsAt = endsAt, price = if product then product.price else 0, fullPrice = Config.StarterPack.fullPrice }
end

local function onPassChanged(player: Player)
	State.progressed(player)
	State.dirty(player)
end

-- Called once per join (yields on web calls).
function Monetization.loadPasses(player: Player)
	local owned = State.passes[player] or {}
	State.passes[player] = owned
	local grantAll = Config.StudioGrantAllPasses and RunService:IsStudio()
	for _, pass in Config.Passes do
		if grantAll then
			owned[pass.key] = true
		elseif pass.id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and has then
				owned[pass.key] = true
			end
		end
	end
end

-- Applies a product. Exposed so the playtest can drive it without a real purchase.
function Monetization.grantProduct(player: Player, key: string): boolean
	local p = Data.get(player)
	local product = Config.ProductByKey[key]
	if not p or not product then
		return false
	end
	if product.kind == "coins" then
		State.addCoins(player, product.amount)
	elseif product.kind == "starter" then
		p.starterBought = true
		State.addCoins(player, Config.StarterPack.coins)
		for _, id in Config.StarterPack.items do
			Cosmetics.grant(player, id)
		end
		Cosmetics.refresh(player, true)
	elseif product.kind == "season" then
		if not SeasonService.grantPremium(player) then
			return false
		end
	elseif product.kind == "tier" then
		if not SeasonService.grantTier(player) then
			return false
		end
	elseif product.kind == "party" then
		-- a gift to the whole server: confetti for everyone and a few coins each
		for _, other in Players:GetPlayers() do
			if State.ready[other] then
				State.addCoins(other, product.amount)
			end
		end
		Remotes.fireAll("Party", player.DisplayName, product.amount)
	end
	State.dirty(player)
	return true
end

function Monetization.processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = Data.get(player)
	if not p or not State.ready[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(p.purchases, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end
	local product = productForId(receipt.ProductId)
	if not product then
		warn("[Monetization] unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(Monetization.grantProduct, player, product.key)
	if not ok then
		warn("[Monetization] grant failed", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(p.purchases, purchaseId)
	while #p.purchases > MAX_RECEIPTS do
		table.remove(p.purchases, 1)
	end
	-- Persist before acknowledging, so a crash can't grant twice or lose the purchase.
	if Data.isPersistent(player) and not Data.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Remotes.notify(player, M("msg.thanks", { item = M("product." .. product.key .. ".name") }), "success")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.init()
	MarketplaceService.ProcessReceipt = Monetization.processReceipt

	State.extras.starter = function(_player, p)
		return Monetization.starterState(p)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		if not purchased then
			return
		end
		local pass = passByGamepassId[gamePassId]
		if pass then
			State.passes[player] = State.passes[player] or {}
			State.passes[player][pass.key] = true
			onPassChanged(player)
			Remotes.notify(player, M("msg.pass_unlocked", { item = M("pass." .. pass.key .. ".name") }), "success")
		end
	end)
end

return Monetization
