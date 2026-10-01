--!strict
-- Game passes (cached per session) and Developer Products (idempotent ProcessReceipt).
local AdService = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Powerups = require(ReplicatedStorage.Shared.Powerups)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Checkpoints = require(script.Parent.Checkpoints)
local Cosmetics = require(script.Parent.Cosmetics)

local Monetization = {}

local MAX_RECEIPTS = 60

-- productId -> handler(player) -> message (a Remotes.M spec or a list of them)
type Grant = (Player, Data.Profile) -> any
local productHandlers: { [number]: Grant } = {}
local M = Remotes.M

local function formatCoins(n: number): string
	local digits = tostring(math.floor(n)):reverse()
	local grouped = digits:gsub("(%d%d%d)", "%1,")
	return (grouped:reverse():gsub("^,", ""))
end

local function register(id: number, fn: Grant)
	if id ~= 0 then
		productHandlers[id] = fn
	end
end

-- Skip Sale Hour (P0-6): a skip bought while the event runs also gives +1 free skip.
local function saleBonus(p: Data.Profile, msg: Remotes.Msg): any
	if Session.eventActive("SkipSaleHour") then
		p.freeSkips += 1
		return { msg, M("msg.sale_bonus") }
	end
	return msg
end

-- One grant for both price bands (19 R$ up to level 300, 29 R$ above): the client offers the band
-- of the level you are on; what is granted is the same either way.
local function grantSkip(player: Player, p: Data.Profile): any
	if Checkpoints.skip(player, 1, "skip") then
		return saleBonus(p, M("msg.stage_skipped"))
	end
	p.freeSkips += 1 -- already at the top: keep it for the next run
	return saleBonus(p, M("msg.saved_skip"))
end
register(Config.Products.SkipStage, grantSkip)
register(Config.Products.SkipStageHigh, grantSkip)
register(Config.Products.Skip10, function(player, p)
	if Checkpoints.skip(player, 10, "skip") then
		return saleBonus(p, M("msg.skipped_ahead"))
	end
	p.freeSkips += 10
	return saleBonus(p, M("msg.saved_10_skips"))
end)
-- Rewarded video (P0-1): the ad reward arrives as a receipt for the AdSkip product.
register(Config.Products.AdSkip, function(player, p)
	if Checkpoints.skip(player, 1, "ad") then
		return M("msg.stage_skipped")
	end
	p.freeSkips += 1
	return M("msg.saved_skip")
end)

-- Starter pack (P0-4). Exposed for the Studio test harness (product ids are 0 there).
function Monetization.grantStarter(_player: Player, p: Data.Profile): Remotes.Msg
	p.starterBought = true
	p.freeSkips += Config.StarterPackSkips
	p.coins += Config.StarterPackCoins
	p.totalCoins += Config.StarterPackCoins
	p.trails.starter = true
	p.boostEndsAt = math.max(os.time(), p.boostEndsAt) + Config.StarterBoostSeconds
	return M("msg.starter_thanks", { n = Config.StarterPackSkips, coins = Config.StarterPackCoins, minutes = Config.StarterBoostSeconds // 60 })
end
register(Config.Products.StarterPack, function(player, p)
	return Monetization.grantStarter(player, p)
end)
-- Coin packs (amounts in Shared/Pricing.CoinPacks). Bought coins are not multiplied by boosts.
for key, amount in Pricing.CoinPacks do
	register(Config.Products[key] or 0, function(_player, p)
		p.coins += amount
		p.totalCoins += amount
		return M("msg.coins_added", { n = formatCoins(amount) })
	end)
end

-- Double jump for 5 minutes (9 R$). Stacks like the coin shop's timed power-ups (up to the cap).
-- Like the pass and the shop version it makes the run unranked (Session.refreshHelp).
register(Config.Products.DoubleJump5, function(player, p)
	local seconds = 300
	local now = os.time()
	local left = Powerups.remaining(p.boosts, "doublejump", now)
	p.boosts.doublejump = now + math.min(left + seconds, Powerups.MAX_TIMED)
	Cosmetics.applyCoils(player)
	Session.refreshHelp(player)
	return M("msg.doublejump_added", { minutes = seconds // 60 })
end)

local function passNameById(id: number): string?
	for name, pid in Config.Passes do
		if pid == id and pid ~= 0 then
			return name
		end
	end
	return nil
end

function Monetization.loadPasses(player: Player)
	local s = Session.get(player)
	if not s then
		return
	end
	for name, id in Config.Passes do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns then
				s.passes[name] = true
			end
		end
	end
end

local watching: { [Player]: boolean } = {} -- a rewarded ad is being shown to this player
Players.PlayerRemoving:Connect(function(player)
	watching[player] = nil
end)

local function utcDay(): number
	return os.time() // 86400
end

function Monetization.init()
	-- Rewarded video ad skip: the server shows the ad; the grant comes through ProcessReceipt.
	Remotes.handle("WatchAd", function(player, payload)
		local p = Data.get(player)
		if not p or Config.Products.AdSkip == 0 or payload.placement ~= "skip" then
			return false, M("err.not_available")
		end
		if p.ads.day ~= utcDay() then
			p.ads = { day = utcDay(), count = 0 }
		end
		if watching[player] then
			return false, M("err.slow_down") -- ShowRewardedVideoAdAsync yields: no parallel requests
		end
		if p.ads.count >= Config.AdDailyCap then
			return false, M("err.ad_cap")
		end
		watching[player] = true
		local ok, result = pcall(function()
			local reward = AdService:CreateAdRewardFromDevProductId(Config.Products.AdSkip)
			return AdService:ShowRewardedVideoAdAsync(player, reward)
		end)
		watching[player] = nil
		if not ok then
			warn("[Monetization] rewarded ad failed:", result)
			return false, M("err.ad_unavailable")
		end
		p.ads.count += 1
		return true
	end)

	MarketplaceService.ProcessReceipt = function(info)
		local player = Players:GetPlayerByUserId(info.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local p = Data.get(player)
		if not p or not Data.isPersistent(player) then
			-- Profile not loaded (or DataStore down): Roblox will retry later.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local receiptId = tostring(info.PurchaseId)
		if table.find(p.purchases, receiptId) then
			-- already applied (a retry, or the first save failed): grant only once it is on disk
			if Data.save(player, false, true) then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local handler = productHandlers[info.ProductId]
		if not handler then
			warn("[Monetization] unknown product", info.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, msg = pcall(handler, player, p)
		if not ok then
			warn("[Monetization] grant failed", msg)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(p.purchases, receiptId)
		while #p.purchases > MAX_RECEIPTS do
			table.remove(p.purchases, 1)
		end
		Remotes.notify(player, msg, "success")
		Session.push(player)
		-- PurchaseGranted only after the receipt id and the grant are saved. If the save fails the
		-- grant stays in memory (and the receipt id with it), Roblox retries and the branch above
		-- saves again without granting twice.
		if not Data.save(player, false, true) then
			warn("[Monetization] receipt", receiptId, "granted but not saved yet")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local name = passNameById(passId)
		local s = Session.get(player)
		if not name or not s then
			return
		end
		-- PromptGamePassPurchaseFinished is raised by Roblox itself (a client cannot fire it), and
		-- UserOwnsGamePassAsync is cached for a while after a purchase, so the signal is what
		-- refreshes the session cache. Ownership is re-read from Roblox on every join.
		s.passes[name] = true
		Cosmetics.applyAll(player)
		Remotes.notify(player, M("msg.thanks_pass", { name = M("store." .. name .. ".name") }), "success")
		Session.push(player)
	end)
end

return Monetization
