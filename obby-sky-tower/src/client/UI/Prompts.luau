--!strict
-- Server-triggered cards:
--   OfferSkip (P0-1)        "Stuck on stage N?" after a death streak: free skip / watch a video /
--                           buy a skip (Studio with product ids at 0: free dev skip).
--   AskNotifications (P0-8) "Want a ping when 2x Coins Weekend starts?" -> ExperienceNotificationService.
local AdService = game:GetService("AdService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Kit = require(script.Parent.Kit)
local Cards = require(script.Parent.Cards)
local Toast = require(script.Parent.Toast)
local Hud = require(script.Parent.Hud)

local Prompts = {}

local OFFER_SECONDS = 10

local function adAvailable(): boolean
	if Config.Products.AdSkip == 0 then
		return false
	end
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	return ok and type(result) == "table" and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

local function say(ok: boolean, msg: string?, _data: any?)
	if msg then
		Toast.show(msg, if ok then "success" else "error")
	end
end

function Prompts.offerSkip(data: { [string]: any })
	local s = Net.state
	local stage = tonumber(data.stage) or ((s.stage or 0) + 1)
	local buttons: { Cards.CardButton } = {}
	local free = s.freeSkips or tonumber(data.freeSkips) or 0
	if free > 0 then
		table.insert(buttons, {
			name = "FreeSkip",
			text = Lang.t("offer.free", { n = free }),
			color = Kit.C.green,
			onClick = function()
				say(Net.request("UseFreeSkip"))
			end,
		})
	end
	-- ask AdService only when the card opens (it can yield), then show the card
	if data.adAvailableHint and adAvailable() then
		table.insert(buttons, {
			name = "AdSkip",
			text = Lang.t("offer.ad"),
			color = Kit.C.purple,
			onClick = function()
				say(Net.request("WatchAd", { placement = "skip" }))
			end,
		})
	end
	if Config.Products.SkipStage ~= 0 then
		local price = Hud.priceOf(Config.Products.SkipStage)
		table.insert(buttons, {
			name = "PaidSkip",
			text = if price then Lang.t("offer.paid", { price = price }) else Lang.t("offer.paid_noprice"),
			color = Kit.C.blue,
			onClick = function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, Config.Products.SkipStage)
			end,
		})
	elseif s.studio and Config.StudioFreeSkips then
		table.insert(buttons, {
			name = "PaidSkip",
			text = Lang.t("offer.studio"),
			color = Kit.C.blue,
			onClick = function()
				say(Net.request("DevSkip", { n = 1 }))
			end,
		})
	end
	if #buttons == 0 then
		return
	end
	Cards.show("offer", Lang.t("offer.title", { n = stage }), buttons, OFFER_SECONDS)
end

function Prompts.askNotifications()
	local ok, can = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if not ok or not can then
		return -- not eligible (or Studio): nothing to ask
	end
	Cards.show("notify", Lang.t("notify.title"), {
		{
			name = "Yes",
			text = Lang.t("notify.yes"),
			color = Kit.C.green,
			onClick = function()
				pcall(function()
					ExperienceNotificationService:PromptOptIn()
				end)
			end,
		},
		{ name = "No", text = Lang.t("notify.no"), color = Kit.C.grey, onClick = function() end },
	}, 15)
end

function Prompts.init()
	Net.on("OfferSkip", function(data)
		task.spawn(Prompts.offerSkip, if type(data) == "table" then data else {})
	end)
	Net.on("AskNotifications", function()
		task.spawn(Prompts.askNotifications)
	end)
	-- a skip / new checkpoint makes the offer pointless
	Net.changed:Connect(function(new, prev)
		if prev.stage and new.stage ~= prev.stage then
			Cards.hide("offer")
		end
	end)
end

return Prompts
