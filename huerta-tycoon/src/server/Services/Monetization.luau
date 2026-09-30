--!strict
-- Game passes and developer products (idempotent ProcessReceipt).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Garden = require(script.Parent.Garden)
local Shop = require(script.Parent.Shop)
local Rewards = require(script.Parent.Rewards)
local AdService = game:GetService("AdService")

local Monetization = {}

local passByKey: { [string]: Config.Pass } = {}
local passById: { [number]: Config.Pass } = {}
for _, pass in Config.GamePasses do
	passByKey[pass.key] = pass
	if pass.id ~= 0 then
		passById[pass.id] = pass
	end
end
local productById: { [number]: Config.Product } = {}
for _, prod in Config.AdProducts do
	if prod.id ~= 0 then
		productById[prod.id] = prod
	end
end
for _, prod in Config.DevProducts do
	if prod.id ~= 0 then
		productById[prod.id] = prod
	end
end

local seedByProductId: { [number]: string } = {}
for seedId, id in Config.SeedProducts do
	if id ~= 0 and Config.SeedById[seedId] then
		seedByProductId[id] = seedId
	end
end

local function applyPass(s: Session.S, key: string)
	s.passes[key] = true
	if key == "VIP" then
		s.player:SetAttribute("VIP", true)
	end
	Session.markDirty(s)
end

function Monetization.loadPasses(s: Session.S)
	for _, pass in Config.GamePasses do
		if pass.id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, s.player.UserId, pass.id)
			if ok and owns then
				applyPass(s, pass.key)
			end
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	local pass = passById[passId]
	local s = Session.get(player)
	if pass and s then
		applyPass(s, pass.key)
		Remotes.notify(player, R("msg.passThanks", { pass = R("pass." .. pass.key .. ".name") }), "success")
	end
end)

local function grant(s: Session.S, prod: Config.Product): boolean
	local key = prod.key
	local boughtSeed = string.match(key, "^Seed:(.+)$")
	if boughtSeed and Config.SeedById[boughtSeed] then
		s.profile.seeds[boughtSeed] = (s.profile.seeds[boughtSeed] or 0) + 1
		Session.markDirty(s)
		Remotes.notify(s.player, R("reward.seeds", { n = 1, seed = Locale.seedName(boughtSeed) }), "success")
		return true
	end
	if Config.CashPackMinutes[key] then
		local minutes = Config.CashPackMinutes[key]
		local amount = math.max(Config.CashPackFloor[key], math.floor(s.bestRate * minutes), math.floor(s.profile.cash * Config.CashPackCashShare[key]))
		Session.addCash(s, amount)
		Remotes.notify(s.player, R("msg.cashAdded", { cash = Format.cash(amount) }), "success")
		return true
	elseif key == "InstantGrow" then
		Garden.instantGrow(s)
		Remotes.notify(s.player, R("msg.instantGrow"), "success")
		return true
	elseif key == "InstantGrowOne" then
		if Garden.instantGrowOne(s) then
			Remotes.notify(s.player, R("msg.instantGrowOne"), "success")
		else
			-- nothing was growing: the purchase still has to give something, so it pays out a little cash
			local amount = math.max(Config.CashPackFloor.CashSmall // 5, math.floor(s.bestRate * Config.InstantGrowOneFallbackMinutes))
			Session.addCash(s, amount)
			Remotes.notify(s.player, R("msg.instantGrowOneNone", { cash = Format.cash(amount) }), "success")
		end
		return true
	elseif key == "Restock" then
		Shop.personalRestock(s)
		Remotes.notify(s.player, R("msg.restocked"), "success")
		return true
	elseif key == "LuckyPack" then
		local names = {}
		for _, id in Rewards.luckyPack(s, 1) do
			table.insert(names, Locale.seedName(id))
		end
		Remotes.notify(s.player, R("msg.luckyPack", { seeds = { list = names } }), "rare")
		return true
	elseif key == "StarterPack" then
		local g = Config.StarterPackGrant
		local text = Rewards.grant(s, {
			seeds = g.seeds,
			boost = { kind = "cash", mult = g.cashBoostMult, seconds = g.cashBoostSeconds },
		})
		s.profile.starterBought = true
		Remotes.notify(s.player, R("msg.starterThanks", { reward = text }), "rare")
		return true
	elseif key == "AdRestock" then
		Shop.personalRestock(s)
		local a = s.profile.ads
		local today = os.time() // 86400
		if a.day ~= today then
			a.day, a.count = today, 0
		end
		a.count += 1
		Session.markDirty(s)
		Remotes.notify(s.player, R("msg.adRestock"), "success")
		return true
	end
	return false
end

MarketplaceService.ProcessReceipt = function(receipt: any)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local s = player and Session.get(player)
	if not player or not s then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local prod = productById[receipt.ProductId]
	local seedId = seedByProductId[receipt.ProductId]
	if seedId then
		-- a seed bought straight from the Seed Shop row
		prod = { key = "Seed:" .. seedId, id = receipt.ProductId, name = seedId, description = "", priceHint = 0 }
	end
	if not prod then
		warn("[Monetization] unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchases = s.profile.purchases
	if table.find(purchases, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, granted = pcall(grant, s, prod)
	if not ok or not granted then
		warn("[Monetization] grant failed", prod.key, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(purchases, receipt.PurchaseId)
	while #purchases > 100 do
		table.remove(purchases, 1)
	end
	-- persist immediately so a crash can't grant twice
	Data.save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ===== Rewarded video ad -> free restock =====
local function adProduct(key: string): Config.Product?
	for _, p in Config.AdProducts do
		if p.key == key then
			return p
		end
	end
	return nil
end

Remotes.handle("WatchAd", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	if payload.placement ~= "restock" then
		return false, R("err.badRequest")
	end
	local prod = adProduct("AdRestock")
	if not prod or prod.id == 0 then
		return false, R("err.adUnavailable")
	end
	if Session.adsLeft(s) <= 0 then
		return false, R("err.adCap")
	end
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(prod.id)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	if not ok then
		return false, R("err.adUnavailable")
	end
	-- the restock itself arrives through ProcessReceipt for the ad product
	return true, nil, if typeof(result) == "EnumItem" then result.Name else tostring(result)
end)

function Monetization.hasPass(s: Session.S, key: string): boolean
	return s.passes[key] == true and passByKey[key] ~= nil
end

return Monetization
