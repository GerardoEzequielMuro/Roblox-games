--!strict
-- Game passes (ownership cache + purchase-finished grant), developer products
-- (ProcessReceipt, idempotent by PurchaseId stored in the profile and saved before returning
-- PurchaseGranted), rewarded videos and the paid-random-items policy check.
local AdService = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Rewards = require(script.Parent.Rewards)
local Pets = require(script.Parent.Pets)
local Progression = require(script.Parent.Progression)
local Offline = require(script.Parent.Offline)

local Monetization = {}

local MAX_RECEIPTS = 60

local passByGamepassId: { [number]: any } = {}
for _, pass in Config.Passes do
	if pass.id ~= 0 then
		passByGamepassId[pass.id] = pass
	end
end
local productById: { [number]: any } = {}
for _, product in Config.Products do
	if product.id ~= 0 then
		productById[product.id] = product
	end
end
local adPlacementById: { [number]: string } = {}
for placement, id in Config.AdProducts :: { [string]: number } do
	if id ~= 0 then
		adPlacementById[id] = placement
	end
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

local function grantAd(player: Player, p: Data.Profile, placement: string)
	if placement == "AdBoost" then
		State.addBuff(player, "stardust", Config.AdBoostMinutes * 60)
		Remotes.notify(player, M("reward.boost", { n = Config.AdBoostMinutes }), "success")
	elseif placement == "AdOffline" then
		local amount = Offline.claim(player, 2)
		if amount <= 0 then
			amount = State.income(player, p) * 600
			State.addStardust(player, amount, false)
		end
		Remotes.notify(player, M("reward.stardust", { n = Format.abbrev(amount) }), "success")
	end
end

local function onPassChanged(player: Player)
	Pets.clampEquipped(player)
	State.dirty(player)
	Progression.applyWalkSpeed(player)
	State.replicateLook(player)
end

-- Roblox policy: paid random items (and what Roblox counts as one: a currency that buys
-- capsules, chance modifiers) must not be offered where they are restricted. When the
-- lookup fails we assume the player is restricted.
function Monetization.loadPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	State.restricted[player] = not ok or (type(info) == "table" and info.ArePaidRandomItemsRestricted == true)
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
	local okPremium, membership = pcall(function()
		return player.MembershipType
	end)
	State.premium[player] = okPremium and membership == Enum.MembershipType.Premium
end

-- Applies a product (also used by the playtest, which has no real receipts).
function Monetization.grantProduct(player: Player, p: Data.Profile, product: any)
	if product.kind == "starter" then
		p.starterBought = true
		State.addCrystals(player, Config.StarterPack.crystals)
		State.addBuff(player, "stardust", Config.StarterPack.boostMinutes * 60)
		Pets.add(player, Config.StarterPack.pet, 0, true)
		Pets.afterChange(player)
		State.dirty(player)
	else
		Rewards.grant(player, { kind = product.kind, amount = product.amount })
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
	local product = productById[receipt.ProductId]
	local adPlacement = adPlacementById[receipt.ProductId]
	if not product and not adPlacement then
		warn("[Monetization] unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(function()
		if adPlacement then
			grantAd(player, p, adPlacement)
		else
			Monetization.grantProduct(player, p, product)
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
	-- Persist before acknowledging, so a crash can't grant twice or lose the purchase.
	if Data.isPersistent(player) and not Data.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product then
		Remotes.notify(player, M("msg.thanks", { item = M("product." .. product.key .. ".name") }), "success")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.init()
	MarketplaceService.ProcessReceipt = processReceipt

	State.extras.starter = function(_player, p)
		return Monetization.starterState(p)
	end
	State.extras.ads = function(_player, p)
		return { left = adsLeft(p), boost = Config.AdProducts.AdBoost ~= 0, offline = Config.AdProducts.AdOffline ~= 0 }
	end

	-- The client asks before it opens a purchase prompt: paid random items are refused for
	-- restricted players (their buttons are hidden as well).
	Remotes.handle("CanBuy", function(player, payload)
		local key = payload.key
		local item = if type(key) == "string" then (Config.ProductByKey[key] or Config.PassByKey[key]) else nil
		if not item then
			return false, M("msg.bad_request")
		end
		if item.random and State.restricted[player] then
			return false, M("msg.restricted")
		end
		return true
	end)

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
