--!strict
-- Robux price list (reference) + the pure rules that depend on it. PURE Luau, unit-tested by
-- tests/pricing_test.luau.
--
-- The REAL price of every product / pass is the one set in the Creator Dashboard (the game reads it
-- with MarketplaceService:GetProductInfo). This table is the intended price list: it is what the
-- owner types into the Dashboard, what the economy checks run against, and what the Starter Pack's
-- crossed-out "value" is computed from, so the anchor can never drift from real prices.
-- Source: docs/research/top-juegos-y-precios.md section 4.2 (obby references).
local Pricing = {}

Pricing.Products = {
	SkipStage = 19, -- 1 stage, levels 1-300
	SkipStageHigh = 29, -- 1 stage, levels 301-1000
	Skip10 = 149, -- 10 stages (vs 190-290 bought one by one)
	DoubleJump5 = 9, -- double jump for 5 minutes: the impulse first purchase
	Coins500 = 49, -- coin ladder: 10.2 / 12.6 / 14.0 coins per R$
	Coins2500 = 199,
	Coins7000 = 499,
	StarterPack = 59,
	AdSkip = 0, -- not sold: reward holder of the rewarded video
} :: { [string]: number }

Pricing.Passes = {
	SpeedCoil = 99,
	GravityCoil = 69,
	Fusion = 139, -- speed + gravity coil in one pass (both sold separately for 168)
	DoubleJump = 99,
	InfiniteRevives = 179,
	DoubleCoins = 195,
	VIP = 299,
} :: { [string]: number }

-- Coins each coin pack gives (Monetization and the store read this, so text and grant agree).
Pricing.CoinPacks = {
	Coins500 = 500,
	Coins2500 = 2500,
	Coins7000 = 7000,
} :: { [string]: number }

-- Levels 1..SkipLowMax use the cheap skip, the rest the dearer one.
Pricing.SkipLowMax = 300

-- The stage a skip would land on is `at + 1`: its band decides the product.
function Pricing.skipKey(at: number): string
	if at + 1 <= Pricing.SkipLowMax then
		return "SkipStage"
	end
	return "SkipStageHigh"
end

-- Product id to prompt for a 1-stage skip from `at`. `ids` = Config.Products. When the id of the
-- band is not created yet (0) the other band's id is used, so selling never stops for want of it.
function Pricing.skipProductId(ids: { [string]: number }, at: number): number
	local key = Pricing.skipKey(at)
	local other = if key == "SkipStage" then "SkipStageHigh" else "SkipStage"
	local id = ids[key] or 0
	if id ~= 0 then
		return id
	end
	return ids[other] or 0
end

-- Crossed-out "value" of the Starter Pack: what its skips and coins cost if bought separately at
-- today's list prices (the exclusive trail and the boost are a free extra, NOT counted).
function Pricing.starterValue(skips: number, coins: number): number
	local total = skips * Pricing.Products.SkipStage
	for key, amount in Pricing.CoinPacks do
		if amount == coins then
			total += Pricing.Products[key]
			return total
		end
	end
	-- coins that match no pack: priced at the smallest pack's rate, rounded up
	local small = Pricing.CoinPacks.Coins500
	return total + math.ceil(coins / small * Pricing.Products.Coins500)
end

-- Honest "-N%" badge: real discount of `price` against `value`, rounded down.
function Pricing.discountPct(value: number, price: number): number
	if value <= 0 or price >= value then
		return 0
	end
	return math.floor((1 - price / value) * 100)
end

-- Robux -> coins per R$ of a pack (for the ladder test and the owner's reference).
function Pricing.coinsPerRobux(key: string): number
	return (Pricing.CoinPacks[key] or 0) / (Pricing.Products[key] or 1)
end

return Pricing
