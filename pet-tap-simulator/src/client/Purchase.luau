--!strict
-- Robux purchase prompts. Items with id 0 in Config are not live yet.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Lang = require(script.Parent.Lang)
local Net = require(script.Parent.Net)

local Purchase = {}

local notify: (string, string?) -> () = function(_text, _kind) end
function Purchase.setNotifier(fn: (string, string?) -> ())
	notify = fn
end

-- Paid random items (eggs, packs with an egg, luck, Taps): not sold where PolicyService
-- restricts them. Unknown (state not loaded yet) counts as restricted.
function Purchase.restricted(): boolean
	return Net.get("paidRandomRestricted") ~= false
end

function Purchase.passBlocked(key: string): boolean
	return Formulas.isPaidRandomPass(key) and Purchase.restricted()
end

function Purchase.productBlocked(key: string): boolean
	return Formulas.isPaidRandomProduct(key) and Purchase.restricted()
end

function Purchase.pass(key: string)
	if Purchase.passBlocked(key) then
		notify(Lang.t("egg.restricted"), "info")
		return
	end
	local pass = Config.PassByKey[key]
	if not pass or pass.id == 0 then
		notify(Lang.t("toast.coming_soon", { item = Lang.t("pass." .. key .. ".name") }), "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
end

function Purchase.product(key: string)
	if Purchase.productBlocked(key) then
		notify(Lang.t("egg.restricted"), "info")
		return
	end
	local product = Config.ProductByKey[key]
	if not product or product.id == 0 then
		notify(Lang.t("toast.coming_soon", { item = Lang.t("product." .. key .. ".name") }), "info")
		return
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
end

function Purchase.passAvailable(key: string): boolean
	local pass = Config.PassByKey[key]
	return pass ~= nil and pass.id ~= 0 and not Purchase.passBlocked(key)
end

function Purchase.productAvailable(key: string): boolean
	local product = Config.ProductByKey[key]
	return product ~= nil and product.id ~= 0 and not Purchase.productBlocked(key)
end

return Purchase
