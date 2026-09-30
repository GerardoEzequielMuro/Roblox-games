--!strict
-- Robux purchase prompts. Items with id 0 in Config are not live yet.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
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

-- Odds of the random item a product gives, as numeric percentages that add up to 100 plus
-- the Golden chance, localized: "Sparkle Cat 70% · Crystal Unicorn 29% · ... · Golden 1%".
-- nil for products with a fixed reward. Shown on the store card and the offer card, before
-- the purchase prompt (paid random items rule). The exclusive egg's entries are all Rare+,
-- so luck scales every weight equally and the odds do not depend on the buyer's luck.
function Purchase.oddsText(key: string): string?
	local eggId = Formulas.productEgg(key)
	if not eggId then
		return nil
	end
	local parts = {}
	for _, o in Formulas.displayOdds(eggId, 1) do
		table.insert(parts, Lang.pet(o.pet) .. " " .. o.text)
	end
	local golden = (Net.get("goldenChance") :: number?) or 0
	if golden > 0 then
		-- same text as the egg panel's Golden line
		local pct = Format.chance(golden * 100):gsub("%%", "")
		table.insert(parts, Lang.t("egg.golden", { pct = pct }))
	end
	return table.concat(parts, " · ")
end

-- What a paid probability modifier does to the odds, with this player's numbers:
-- "Luck x1.10 → x1.60" (Lucky, VIP, Super Luck) or "Golden 1% → 10%" (Magic Eggs).
-- The exact odds after luck are on every egg panel. nil for items that change no odds.
function Purchase.effectText(key: string): string?
	local s = Net.state
	if not s then
		return nil
	end
	if key == "MagicEggs" then
		-- the live-event multiplier (Golden Weekend) is whatever the server's number implies
		local owns = Net.owns("MagicEggs")
		local plain = Formulas.goldenChance(owns, 1)
		local ev = if plain > 0 and s.goldenChance then s.goldenChance / plain else 1
		local before = Formulas.goldenChance(owns, ev)
		local after = Formulas.goldenChance(true, ev)
		local function pct(c: number): string
			return (Format.chance(c * 100):gsub("%%", ""))
		end
		return Lang.t("egg.golden", { pct = pct(before) }) .. " → " .. pct(after) .. "%"
	end
	if key ~= "Lucky" and key ~= "VIP" and key ~= "SuperLuck" then
		return nil
	end
	local level = (s.upgrades and s.upgrades.Luck) or 0
	local passes = table.clone((Net.get("passes") :: { [string]: boolean }?) or {})
	local boosted = (s.luckBoostLeft or 0) > 0
	local base = Formulas.luck(level, passes, boosted, 1)
	local eventLuck = if base > 0 and s.luck then s.luck / base else 1
	local before = Formulas.luck(level, passes, boosted, eventLuck)
	if key == "SuperLuck" then
		boosted = true -- stacks time if it is already running
	else
		passes[key] = true
	end
	local after = Formulas.luck(level, passes, boosted, eventLuck)
	return Lang.t("egg.luck", { luck = string.format("%.2f", before) }) .. " → x" .. string.format("%.2f", after)
end

-- Text for a store card: the odds of a random reward, or the odds change of a luck item.
function Purchase.cardOdds(key: string): string?
	return Purchase.oddsText(key) or Purchase.effectText(key)
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
