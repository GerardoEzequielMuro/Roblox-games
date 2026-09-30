--!strict
-- Game passes (ownership cache + purchase-finished grant) and developer products
-- (ProcessReceipt, idempotent by PurchaseId stored in the profile and saved before
-- returning PurchaseGranted). Nothing sold here is random: the Starter Pack gives a fixed aura.
local AdService = game:GetService("AdService")
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
local Rewards = require(script.Parent.Rewards)
local Relics = require(script.Parent.Relics)
local Training = require(script.Parent.Training)

local Monetization = {}

local MAX_RECEIPTS = 60

-- Lookups read Config every time, so IDs pasted into Config (or set by a test) just work.
local function passByGamepassId(id: number): any
	for _, pass in Config.Passes do
		if pass.id ~= 0 and pass.id == id then
			return pass
		end
	end
	return nil
end
local function productById(id: number): any
	for _, product in Config.Products do
		if product.id ~= 0 and product.id == id then
			return product
		end
	end
	return nil
end
local function adPlacementById(id: number): string?
	for placement, pid in Config.AdProducts :: { [string]: number } do
		if pid ~= 0 and pid == id then
			return placement
		end
	end
	return nil
end

-- Starter Pack: live product, not bought, within 24 h of the first join.
function Monetization.starterState(p: Data.Profile): { available: boolean, endsAt: number, price: number, fullPrice: number }
	local product = Config.ProductByKey.StarterPack
	local endsAt = p.firstJoin + Config.StarterPack.windowSeconds
	local available = product ~= nil and product.id ~= 0 and not p.starterBought and os.time() < endsAt
	return { available = available, endsAt = endsAt, price = if product then product.price else 0, fullPrice = Config.StarterPack.fullPrice }
end

local function adDay(): number
	return os.time() // 86400
end

local function adsLeft(p: Data.Profile): number
	if p.ads.day ~= adDay() then
		return Config.AdDailyCap
	end
	return math.max(0, Config.AdDailyCap - p.ads.count)
end

-- What a product gives. Also used by the playtest (no Robux involved there).
function Monetization.grantProduct(player: Player, key: string): boolean
	local p = Data.get(player)
	local product = Config.ProductByKey[key]
	if not p or not product then
		return false
	end
	if product.kind == "starter" then
		p.starterBought = true
		State.addGems(player, Config.StarterPack.gems)
		p.boostLeft += Config.StarterPack.boostMinutes * 60
		local aura = Config.StarterPack.aura
		p.auras[aura] = (p.auras[aura] or 0) + 1
		if p.auraEquipped == "" then
			p.auraEquipped = aura
			local char = player.Character
			if char then
				char:SetAttribute("Aura", aura)
			end
		end
	elseif product.kind == "wish" then
		Relics.completeSet(player)
	else
		Rewards.grant(player, { kind = product.kind, amount = product.amount })
	end
	State.dirty(player)
	return true
end

local function grantAd(player: Player, p: Data.Profile, placement: string)
	if placement == "AdBoost" then
		p.boostLeft += Config.AdBoostMinutes * 60
		State.dirty(player)
		Remotes.notify(player, M("reward.boost", { n = Config.AdBoostMinutes }), "success")
	elseif placement == "AdSpin" then
		Rewards.grant(player, { kind = "spins", amount = 1 })
	end
end

local function onPassChanged(player: Player)
	Training.applyMovement(player)
	local char = player.Character
	if char then
		char:SetAttribute("VIP", State.owns(player, "VIP"))
	end
	local p = Data.get(player)
	if p and State.owns(player, "VIP") and not p.auras.vip_gold then
		p.auras.vip_gold = 1
	end
	State.dirty(player)
end
Monetization.onPassChanged = onPassChanged

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
	local p = Data.get(player)
	if p and owned.VIP and not p.auras.vip_gold then
		p.auras.vip_gold = 1
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
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
	local product = productById(receipt.ProductId)
	local adPlacement = adPlacementById(receipt.ProductId)
	if not product and not adPlacement then
		warn("[Monetization] unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(function()
		if adPlacement then
			grantAd(player, p, adPlacement)
		elseif product then
			Monetization.grantProduct(player, product.key)
		end
	end)
	if not ok then
		warn("[Monetization] grant failed", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(p.purchases, purchaseId)
	while #p.purchases > MAX_RECEIPTS do
		table.remove(p.purchases, 1)
	end
	-- Persist before acknowledging, so a crash cannot grant twice or lose the purchase.
	if Data.isPersistent(player) and not Data.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product then
		Remotes.notify(player, M("msg.thanks", { item = M("product." .. product.key .. ".name") }), "success")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
Monetization.processReceipt = processReceipt

function Monetization.init()
	MarketplaceService.ProcessReceipt = processReceipt

	State.extras.starter = function(_player, p)
		return Monetization.starterState(p)
	end
	State.extras.ads = function(_player, p)
		return { left = adsLeft(p), boost = Config.AdProducts.AdBoost ~= 0, spin = Config.AdProducts.AdSpin ~= 0 }
	end

	-- Rewarded video: validate the placement and daily cap, then show the ad. The reward
	-- itself arrives through ProcessReceipt (the ad is tied to a developer product).
	Remotes.handle("WatchAd", function(player, payload)
		local p = Data.get(player)
		local placement = payload.placement
		local id = if type(placement) == "string" then (Config.AdProducts :: any)[placement] else nil
		if not p or type(id) ~= "number" or id == 0 then
			return false, M("msg.ad_unavailable")
		end
		if adsLeft(p) <= 0 then
			return false, M("msg.ad_cap")
		end
		if p.ads.day ~= adDay() then
			p.ads = { day = adDay(), count = 0 }
		end
		local ok, result = pcall(function()
			local reward = (AdService :: any):CreateAdRewardFromDevProductId(id)
			return (AdService :: any):ShowRewardedVideoAdAsync(player, reward)
		end)
		if not ok then
			warn("[Monetization] ad failed", result)
			return false, M("msg.ad_unavailable")
		end
		p.ads.count += 1
		State.dirty(player)
		return true, tostring(if typeof(result) == "EnumItem" then (result :: any).Name else result)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		if not purchased then
			return
		end
		local pass = passByGamepassId(gamePassId)
		if pass then
			State.passes[player] = State.passes[player] or {}
			State.passes[player][pass.key] = true
			onPassChanged(player)
			Remotes.notify(player, M("msg.pass_unlocked", { item = M("pass." .. pass.key .. ".name") }), "success")
		end
	end)
end

return Monetization
