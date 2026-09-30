-- Pricing / monetization rules (pure). Run with: luau tests/pricing_check.luau
-- Prices follow docs/research/top-juegos-y-precios.md section 4.5; the rest are the policy
-- rules of the round: honest anchors, no random paid items, every paid power item earnable.
local Config = require("../src/shared/Config")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

-- 1. exact recommended prices ------------------------------------------------------------
local passPrices = {
	VIP = 299, DoubleTraining = 249, DoubleSparks = 249, DoubleBundle = 449, TurboAuto = 249,
	KiMastery = 199, LuckyAura = 249, RelicRadar = 299, FastFlight = 79,
	TimeChamber = 499, UnboundForm = 599, DarkArts = 399, SkinPack = 299, MountPack = 149, AuraPack = 199,
}
local n = 0
for _, p in Config.Passes do
	n += 1
	check("pass has a known price " .. p.key, passPrices[p.key] ~= nil)
	check("pass price " .. p.key, p.price == passPrices[p.key], p.price)
	check("pass id is 0 until the owner creates it " .. p.key, p.id == 0)
end
local expectedPasses = 0
for _ in passPrices do
	expectedPasses += 1
end
check("all passes priced", n == expectedPasses, n .. "/" .. expectedPasses)

local productPrices = {
	StarterPack = 99, Sparks1 = 49, Sparks2 = 99, Sparks3 = 199, Sparks4 = 399, Gems1 = 49, Gems2 = 129, Gems3 = 299, Gems4 = 699,
	Boost30 = 49, WishNow = 199, SeedSampler = 25, SeedCase = 99, BattlePassS1 = 399, BattlePassS2 = 399, TierSkip = 49,
}
local seen: { [string]: boolean } = {}
for _, p in Config.Products do
	check("product price " .. p.key, p.price == productPrices[p.key], p.price)
	check("product id is 0 " .. p.key, p.id == 0)
	check("product key unique " .. p.key, not seen[p.key])
	seen[p.key] = true
	check("product kind is not random " .. p.key, ({ starter = true, sparks = true, gems = true, boost = true, wish = true, seeds = true, bp = true, bpskip = true })[p.kind] == true, p.kind)
end
for key in productPrices do
	check("product exists " .. key, seen[key] == true)
end

-- 2. currency ladders keep their bonus (research: Gems +20/+31/+52 %, Sparks +24/+48/+84 %) --
local function ladder(prefix: string)
	local base = Config.ProductByKey[prefix .. "1"].amount / Config.ProductByKey[prefix .. "1"].price
	local out = {}
	for i = 2, 4 do
		local p = Config.ProductByKey[prefix .. i]
		out[i] = (p.amount / p.price) / base - 1
	end
	return out
end
local g, sp = ladder("Gems"), ladder("Sparks")
check("Gems2 bonus ~20%", math.abs(g[2] - 0.20) < 0.02, g[2])
check("Gems3 bonus ~31%", math.abs(g[3] - 0.31) < 0.02, g[3])
check("Gems4 bonus ~52%", math.abs(g[4] - 0.52) < 0.02, g[4])
check("Sparks2 bonus ~24%", math.abs(sp[2] - 0.24) < 0.02, sp[2])
check("Sparks3 bonus ~48%", math.abs(sp[3] - 0.48) < 0.02, sp[3])
check("Sparks4 bonus ~84%", math.abs(sp[4] - 0.84) < 0.02, sp[4])

-- 3. honest price anchors --------------------------------------------------------------
-- The bundle is cheaper than its parts.
local bundle = Config.PassByKey.DoubleBundle
local apart = 0
for _, k in bundle.implies do
	apart += Config.PassByKey[k].price
end
check("bundle cheaper than the parts", bundle.price < apart, bundle.price .. " vs " .. apart)
check("bundle saves at least 5%", bundle.price <= apart * 0.95, bundle.price .. " vs " .. apart)
-- Starter Pack: the crossed-out number is what the contents cost in this very shop.
local sp_ = Config.StarterPack
local cheapestGem, cheapestSpark = math.huge, math.huge
for _, p in Config.Products do
	if p.kind == "gems" then
		cheapestGem = math.min(cheapestGem, p.price / p.amount)
	elseif p.kind == "sparks" then
		cheapestSpark = math.min(cheapestSpark, p.price / p.amount)
	end
end
local honest = math.floor(sp_.gems * cheapestGem + 0.5) + math.floor(sp_.boostMinutes / 30 * Config.ProductByKey.Boost30.price + 0.5) + math.floor(sp_.sparkMinutes * cheapestSpark + 0.5)
check("Starter Pack fullPrice is the real sum (best rates)", sp_.fullPrice == honest, sp_.fullPrice .. " vs " .. honest)
check("Starter Pack real price is 99", Config.ProductByKey.StarterPack.price == 99)
check("Starter Pack really is a deal (>= 2x)", sp_.fullPrice >= 2 * Config.ProductByKey.StarterPack.price, sp_.fullPrice)
check("Starter Pack window is 24 h and enforced by the server", sp_.windowSeconds == 86400)

-- 4. nothing paid is random; every paid power item can also be earned --------------------
local purePower = { VIP = true, DoubleTraining = true, DoubleSparks = true, DoubleBundle = true, TurboAuto = true, KiMastery = true, FastFlight = true, RelicRadar = true, LuckyAura = true }
for _, p in Config.Passes do
	if not purePower[p.key] then
		check("pass is earnable by playing " .. p.key, p.earnable == true)
	end
end
check("Time Chamber can be earned", Config.PassByKey.TimeChamber.earn ~= nil)
for _, f in Config.Forms do
	if f.special then
		check("special form has earn (boss kills) " .. f.id, f.special.boss ~= nil and (f.special.count or 0) > 0 and Config.Npcs[f.special.boss] ~= nil)
		check("special form has a pass " .. f.id, Config.PassByKey[f.special.pass] ~= nil)
	end
end
for _, t in Config.Techniques do
	if t.dark or t.special then
		check("dark technique is special " .. t.id, t.special ~= nil and t.dark == true)
		check("dark technique earn boss exists " .. t.id, Config.Npcs[t.special.boss] ~= nil and t.special.count > 0)
		check("dark technique pass exists " .. t.id, Config.PassByKey[t.special.pass] ~= nil)
	end
end
for _, list in { Config.Skins, Config.Mounts } do
	for _, c in list :: { any } do
		check("cosmetic has earn " .. c.id, c.earn ~= nil)
		check("cosmetic pass exists " .. c.id, Config.PassByKey[c.pass] ~= nil)
	end
end
for _, a in Config.Auras do
	if a.pass then
		check("paid aura has earn " .. a.id, a.earn ~= nil)
		check("paid aura is not in the random spin " .. a.id, a.weight == 0 and a.exclusive == true)
		check("paid aura pass exists " .. a.id, Config.PassByKey[a.pass] ~= nil)
	end
end
-- the random spin odds still add up to 100 and only contain spin auras
local total = 0
for _, a in Config.Auras do
	total += a.weight
end
check("aura odds add up to 100", math.abs(total - 100) < 1e-9, total)
for _, p in Config.Products do
	check("seed packs have fixed contents " .. p.key, p.kind ~= "seeds" or (p.amount >= 1 and p.amount % 1 == 0))
end

-- 5. battle pass products ------------------------------------------------------------
for _, season in Config.BattlePass.seasons do
	local product = Config.ProductByKey[season.product]
	check("season product exists " .. season.id, product ~= nil and product.kind == "bp" and product.season == season.id)
	check("season premium price in 299..499", product ~= nil and product.price >= 299 and product.price <= 499)
end
check("tier skip is 49", Config.ProductByKey.TierSkip.price == 49)

-- 6. PvP is not pay-to-win: the special content is flagged so the server switches it off ---
for _, t in Config.Techniques do
	if t.special then
		check("special technique is arena-disabled by flag " .. t.id, t.dark == true)
	end
end
for _, sd in Config.Seeds do
	check("seed effect defined " .. sd.id, sd.kiGive ~= nil or sd.damageMult ~= nil or sd.regenMult ~= nil)
end

if fails == 0 then
	print(string.format("PRICING CHECKS PASSED (%d passes, %d products, starter value %d R$ for %d R$)", #Config.Passes, #Config.Products, Config.StarterPack.fullPrice, Config.ProductByKey.StarterPack.price))
else
	error(fails .. " pricing check(s) failed")
end
