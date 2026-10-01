--!strict
-- Game passes (ownership cache + purchase-finished grant) and developer products
-- (ProcessReceipt, idempotent by PurchaseId stored in the profile and saved before
-- returning PurchaseGranted). Nothing sold here is random: the Starter Pack gives a fixed aura,
-- seed packs and battle pass products are fixed lists.
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
local Items = require(script.Parent.Items)
local Combat = require(script.Parent.Combat)
local Season = require(script.Parent.Season)
local Cosmetics = require(script.Parent.Cosmetics)

local Monetization = {}

local MAX_RECEIPTS = 60
local receiptBusy: { [string]: boolean } = {} -- PurchaseIds being processed right now
local adBusy: { [Player]: boolean } = {} -- one rewarded ad at a time per player

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
		Rewards.grant(player, { kind = "sparks", amount = Config.StarterPack.sparkMinutes })
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
	elseif product.kind == "seeds" then
		Items.grantPack(player, product.amount)
	elseif product.kind == "bp" then
		if not Season.grantPremium(player, product.season) then
			return false
		end
	elseif product.kind == "bpskip" then
		if not Season.skipTier(player) then
			return false
		end
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
	State.refreshPasses(player)
	Cosmetics.sync(player)
	Combat.refreshForms(player)
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
	State.refreshPasses(player)
end

-- Persist the profile (it holds the PurchaseId) before the receipt is acknowledged.
local function persisted(player: Player): boolean
	if Data.isPersistent(player) then
		return Data.save(player)
	end
	-- no DataStore at all (Studio without API access): nothing to wait for
	return RunService:IsStudio()
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	if type(receipt) ~= "table" or type(receipt.PlayerId) ~= "number" or type(receipt.ProductId) ~= "number" or receipt.PurchaseId == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = Data.get(player)
	if not p or not State.ready[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	-- Roblox can call this again while a previous call is still saving: answer "not yet"
	if receiptBusy[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- A profile that failed to load would lose the grant on leave: do not take the money yet.
	if not Data.isPersistent(player) and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	receiptBusy[purchaseId] = true
	local decision = Enum.ProductPurchaseDecision.NotProcessedYet
	local okRun, errRun = (pcall :: any)(function()
		if table.find(p.purchases, purchaseId) then
			-- granted earlier; make sure it reached the DataStore before saying so (a failed
			-- save on the first attempt leaves the id in memory only)
			if persisted(player) then
				decision = Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return
		end
		local product = productById(receipt.ProductId)
		local adPlacement = adPlacementById(receipt.ProductId)
		if not product and not adPlacement then
			warn("[Monetization] unknown product", receipt.ProductId)
			return
		end
		local granted = true
		local ok, err = pcall(function()
			if adPlacement then
				grantAd(player, p, adPlacement)
			elseif product then
				granted = Monetization.grantProduct(player, product.key)
			end
		end)
		if not ok or not granted then
			warn("[Monetization] grant failed", err)
			return
		end
		table.insert(p.purchases, purchaseId)
		while #p.purchases > MAX_RECEIPTS do
			table.remove(p.purchases, 1)
		end
		-- Persist before acknowledging, so a crash cannot grant twice or lose the purchase.
		if not persisted(player) then
			return
		end
		if product then
			Remotes.notify(player, M("msg.thanks", { item = M("product." .. product.key .. ".name") }), "success")
		end
		decision = Enum.ProductPurchaseDecision.PurchaseGranted
	end)
	receiptBusy[purchaseId] = nil
	if not okRun then
		warn("[Monetization] receipt error", errRun)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
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
		if adBusy[player] then
			return false, M("msg.slow_down")
		end
		if adsLeft(p) <= 0 then
			return false, M("msg.ad_cap")
		end
		if p.ads.day ~= adDay() then
			p.ads = { day = adDay(), count = 0 }
		end
		adBusy[player] = true -- ShowRewardedVideoAdAsync yields: block overlapping calls
		local ok, result = pcall(function()
			local reward = (AdService :: any):CreateAdRewardFromDevProductId(id)
			return (AdService :: any):ShowRewardedVideoAdAsync(player, reward)
		end)
		adBusy[player] = nil
		if not ok then
			warn("[Monetization] ad failed", result)
			return false, M("msg.ad_unavailable")
		end
		p.ads.count += 1
		State.dirty(player)
		return true, tostring(if typeof(result) == "EnumItem" then (result :: any).Name else result)
	end)

	Players.PlayerRemoving:Connect(function(player)
		adBusy[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		if purchased ~= true or not player.Parent then
			return
		end
		local pass = passByGamepassId(gamePassId)
		if pass then
			-- the engine's own server-side signal; cache it, then refresh the rest of the
			-- cache from the Marketplace so a pass bought elsewhere (another server) shows too
			State.passes[player] = State.passes[player] or {}
			State.passes[player][pass.key] = true
			task.spawn(function()
				local ok, has = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
				end)
				if ok and not has then
					warn("[Monetization] Marketplace has not confirmed the pass yet:", pass.key)
				end
			end)
			onPassChanged(player)
			Remotes.notify(player, M("msg.pass_unlocked", { item = M("pass." .. pass.key .. ".name") }), "success")
		end
	end)
end

return Monetization
