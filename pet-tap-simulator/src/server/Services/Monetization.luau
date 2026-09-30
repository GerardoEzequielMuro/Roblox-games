--!strict
-- Game passes (ownership cache + purchase-finished grant) and developer products
-- (ProcessReceipt, idempotent by PurchaseId stored in the profile and saved before
-- returning PurchaseGranted).
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
local Pets = require(script.Parent.Pets)
local Progression = require(script.Parent.Progression)
local Offline = require(script.Parent.Offline)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)

local Monetization = {}

local MAX_RECEIPTS = 60

local passByGamepassId: { [number]: typeof(Config.Passes[1]) } = {}
for _, pass in Config.Passes do
	if pass.id ~= 0 then
		passByGamepassId[pass.id] = pass
	end
end
local productById: { [number]: typeof(Config.Products[1]) } = {}
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

-- Grants an ad placement's reward (called from ProcessReceipt).
local function grantAd(player: Player, p: Data.Profile, placement: string)
	if placement == "AdBoost" then
		p.tapBoostLeft += Config.AdBoostMinutes * 60
		State.dirty(player)
		Remotes.notify(player, M("msg.ad_boost", { n = Config.AdBoostMinutes }), "success")
	elseif placement == "AdOffline" then
		local amount = Offline.claim(player, 2)
		if amount <= 0 then
			amount = Formulas.tapsForMinutes(Config.AdOfflineFallbackMinutes, State.tapValue(player, p))
			State.addTaps(player, amount, false)
		end
		Remotes.notify(player, M("reward.taps", { n = Format.abbrev(amount) }), "success")
	end
end

local function onPassChanged(player: Player)
	Pets.clampEquipped(player)
	Progression.applyWalkSpeed(player)
	State.dirty(player)
	State.replicateEquipped(player)
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
	Formulas.applyIncluded(owned) -- x8 Hatch includes x3 Hatch
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
		elseif product and product.kind == "starter" then
			p.starterBought = true
			State.addGems(player, Config.StarterPack.gems)
			p.luckBoostLeft += Config.StarterPack.luckMinutes * 60
			Rewards.grant(player, { kind = "egg", amount = Config.StarterPack.eggs })
			State.dirty(player)
		elseif product then
			Rewards.grant(player, { kind = product.kind, amount = product.amount, label = product.name })
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
		-- Keep the marker in memory: when Roblox retries, the marker short-circuits to
		-- PurchaseGranted once a later save succeeds; if the server dies first, both the
		-- grant and the marker are lost together and the retry grants it again.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product then
		Remotes.notify(player, M("msg.thanks", { item = M("product." .. product.key .. ".name") }), "success")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.init()
	MarketplaceService.ProcessReceipt = processReceipt

	State.extras.starter = function(player, p)
		local st = Monetization.starterState(p)
		-- the pack contains an egg, so the whole pack is a paid random item
		if State.paidRandomRestricted[player] ~= false then
			st.available = false
		end
		return st
	end
	State.extras.ads = function(_player, p)
		return { left = adsLeft(p), boost = Config.AdProducts.AdBoost ~= 0, offline = Config.AdProducts.AdOffline ~= 0 }
	end

	-- Rewarded video: validate the placement and daily cap, then show the ad. The reward
	-- itself arrives through ProcessReceipt (the ad is tied to a developer product).
	Remotes.handle("WatchAd", function(player, payload)
		local p = Data.get(player)
		local placement = payload.placement
		local id = if type(placement) == "string" then (Config.AdProducts :: any)[placement] else nil
		if not p or type(id) ~= "number" then
			return false, M("msg.ad_unavailable")
		end
		if id == 0 then
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
			Formulas.applyIncluded(State.passes[player])
			onPassChanged(player)
			Remotes.notify(player, M("msg.pass_unlocked", { item = M("pass." .. pass.key .. ".name") }), "success")
		end
	end)
end

return Monetization
