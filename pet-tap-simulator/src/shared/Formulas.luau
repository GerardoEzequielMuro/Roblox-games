--!strict
-- Pure economy math shared by the server (authoritative), the client (display) and
-- the standalone economy simulation (sim/economy_sim.luau, run with luau.exe).
-- No Roblox APIs in here.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Formulas = {}
Formulas.Config = Config

export type Owned = { [string]: boolean }

-- Everything tapValue needs, decoupled from the DataStore profile shape.
export type TapContext = {
	petPower: number, -- sum of equipped pets' power (already tier-multiplied)
	rebirths: number,
	tapPowerLevel: number,
	passes: Owned,
	friends: number,
	indexZonesDone: number,
	tapBoost: boolean?, -- rewarded-video x2 taps active
}

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
local PetById: { [string]: any } = {}
for _, p in Config.Pets do
	PetById[p.id] = p
end
local EggById: { [string]: any } = {}
for _, e in Config.Eggs do
	EggById[e.id] = e
end
Formulas.PetById = PetById :: { [string]: typeof(Config.Pets[1]) }
Formulas.EggById = EggById :: { [string]: typeof(Config.Eggs[1]) }

-- Rebirths needed before an egg can be opened (0 for eggs that only need their zone).
function Formulas.eggMinRebirths(eggId: string): number
	local egg = EggById[eggId]
	return if egg and egg.minRebirths then egg.minRebirths else 0
end

function Formulas.eggUnlocked(eggId: string, rebirths: number): boolean
	return rebirths >= Formulas.eggMinRebirths(eggId)
end

-- Eggs that open exactly at this rebirth count (for the "new egg" message after a rebirth).
function Formulas.eggsUnlockedAt(rebirths: number): { string }
	local out = {}
	for _, egg in Config.Eggs do
		if egg.minRebirths == rebirths and rebirths > 0 then
			table.insert(out, egg.id)
		end
	end
	return out
end

-- Pets that only come out of rebirth-gated eggs. They are extra content inside a zone's band and do
-- not move the power that exclusive pets scale with (that would make Robux pets jump at rebirth 2).
local gatedPets: { [string]: boolean } = {}
for _, e in Config.Eggs do
	if e.minRebirths and e.minRebirths > 0 then
		for _, entry in e.entries do
			gatedPets[entry.pet] = true
		end
	end
end
for _, e in Config.Eggs do
	if not e.minRebirths then
		for _, entry in e.entries do
			gatedPets[entry.pet] = nil -- a pet that also drops from an open egg (the secret pet)
		end
	end
end

-- Strongest regular (tap-bought) pet per zone, used to scale exclusive pets.
local bestPowerByZone: { number } = {}
for z = 1, #Config.Zones do
	local best = 1
	for _, p in Config.Pets do
		if p.zone >= 1 and p.zone <= z and p.power > best and not gatedPets[p.id] then
			best = p.power
		end
	end
	bestPowerByZone[z] = best
end

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
function Formulas.tierMult(tier: number): number
	local t = Config.Tiers[tier]
	return if t then t.mult else 1
end

-- Power multiplier of a trait grade (index into Config.TraitGrades; nil / 0 = no trait).
function Formulas.traitMult(grade: number?): number
	local g = if grade then Config.TraitGrades[grade] else nil
	return if g then g.mult else 1
end

-- r in [0, 1). Returns the grade index rolled.
function Formulas.rollTrait(r: number): number
	local acc = 0
	local target = r * 100
	for i, g in Config.TraitGrades do
		acc += g.chance
		if target < acc then
			return i
		end
	end
	return #Config.TraitGrades
end

-- maxZone: highest zone the owner has unlocked (exclusive pets scale with it).
-- trait: grade index of the pet's trait, if it has one.
function Formulas.petPower(petId: string, tier: number, maxZone: number, trait: number?): number
	local pet = PetById[petId]
	if not pet then
		return 0
	end
	local base = pet.power
	local factor = (Config.ExclusivePowerFactor :: any)[petId]
	if factor then
		base = factor * bestPowerByZone[math.clamp(maxZone, 1, #Config.Zones)]
	end
	return base * Formulas.tierMult(tier) * Formulas.traitMult(trait)
end

function Formulas.maxEquip(slotLevel: number, passes: Owned): number
	local n = Config.BaseEquipSlots + slotLevel
	if passes.PetSlots then
		n += Config.PassEffects.ExtraSlots
	end
	if passes.PetSlots2 then
		n += Config.PassEffects.ExtraSlots2
	end
	return n
end

-- Pet inventory cap (the Storage pass adds room).
function Formulas.maxInventory(passes: Owned): number
	return Config.MaxInventory + (if passes.Storage then Config.PassEffects.ExtraStorage else 0)
end

-- Biggest hatch the player may open at once: x8 (x8 Hatch pass, which includes x3), x3, or x1.
function Formulas.maxHatch(passes: Owned): number
	if passes.OctoHatch then
		return Config.OctoHatchCount
	elseif passes.TripleHatch then
		return Config.TripleHatchCount
	end
	return 1
end

-- Auto Hatch picks the biggest size (x8, x3, x1) up to maxCount that the player can pay for
-- and that still fits in the inventory; falls back to x1 (the server then reports why not).
function Formulas.autoHatchCount(maxCount: number, taps: number, price: number, room: number): number
	for _, n in { Config.OctoHatchCount, Config.TripleHatchCount } do
		if n <= maxCount and taps >= price * n and room >= n then
			return n
		end
	end
	return 1
end

-- Pass that unlocks a hatch size (nil for x1 / unknown sizes).
function Formulas.hatchPass(count: number): string?
	if count == Config.OctoHatchCount then
		return "OctoHatch"
	elseif count == Config.TripleHatchCount then
		return "TripleHatch"
	end
	return nil
end

-- Hatch sizes the server accepts at all.
function Formulas.validHatchCount(count: any): boolean
	return count == 1 or count == Config.TripleHatchCount or count == Config.OctoHatchCount
end

-- Passes that include another pass: owning the big one also marks the small one as owned, so
-- nobody is ever sold something they already have. Mutates and returns the set.
Formulas.IncludedPasses = { OctoHatch = "TripleHatch" } :: { [string]: string }
function Formulas.applyIncluded(owned: Owned): Owned
	for big, small in Formulas.IncludedPasses do
		if owned[big] then
			owned[small] = true
		end
	end
	return owned
end

-- Can this player turn Auto Rebirth on? Free after Config.AutoRebirthMinRebirths manual
-- rebirths; the pass opens it after Config.AutoRebirthPassMinRebirths.
function Formulas.autoRebirthUnlocked(rebirths: number, passes: Owned): boolean
	local need = if passes.AutoRebirth then Config.AutoRebirthPassMinRebirths else Config.AutoRebirthMinRebirths
	return rebirths >= need
end

---------------------------------------------------------------------------
-- Tapping
---------------------------------------------------------------------------
function Formulas.rebirthMult(rebirths: number): number
	return 1 + rebirths * Config.RebirthMultPer
end

function Formulas.tapMultiplier(ctx: TapContext): number
	local m = 1 + ctx.tapPowerLevel * Config.UpgradeById.TapPower.perLevel
	m *= Formulas.rebirthMult(ctx.rebirths)
	if ctx.passes.DoubleTaps then
		m *= Config.PassEffects.DoubleTapsMult
	end
	if ctx.passes.VIP then
		m *= Config.PassEffects.VIPTapMult
	end
	m *= 1 + math.min(Config.FriendBoostMax, ctx.friends * Config.FriendBoostPer)
	m *= 1 + ctx.indexZonesDone * Config.IndexTapBonus
	if ctx.tapBoost then
		m *= Config.AdBoostMult
	end
	return m
end

function Formulas.tapValue(ctx: TapContext): number
	return (Config.BaseTap + ctx.petPower) * Formulas.tapMultiplier(ctx)
end

-- Rewards measured in "minutes of taps" scale with the player's current income.
function Formulas.tapsForMinutes(minutes: number, tapValue: number): number
	return math.floor(tapValue * Config.RewardMinTapsPerSecond * 60 * minutes)
end

---------------------------------------------------------------------------
-- Rebirth & upgrades
---------------------------------------------------------------------------
function Formulas.rebirthCost(rebirths: number): number
	return math.floor(Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths)
end

function Formulas.rebirthGems(rebirths: number): number
	return Config.RebirthGemsBase + rebirths * Config.RebirthGemsPer
end

function Formulas.upgradeCost(id: string, level: number): number
	local u = Config.UpgradeById[id]
	return math.floor(u.baseCost * u.costGrowth ^ level)
end

---------------------------------------------------------------------------
-- Luck & eggs
---------------------------------------------------------------------------
-- eventLuck: product of the active live events' luckMult (1 when none).
function Formulas.luck(luckLevel: number, passes: Owned, boosted: boolean, eventLuck: number?): number
	local l = 1 + luckLevel * Config.UpgradeById.Luck.perLevel
	if passes.Lucky then
		l += Config.PassEffects.LuckyLuck
	end
	if passes.SuperLucky then
		l += Config.PassEffects.SuperLuckyLuck
	end
	if passes.VIP then
		l += Config.PassEffects.VIPLuck
	end
	if boosted then
		l *= Config.BoostLuckMult
	end
	return l * (eventLuck or 1)
end

-- Chance that a hatch comes out Golden (Magic Eggs pass, live-event multiplier).
function Formulas.goldenChance(magicEggs: boolean, eventGolden: number?): number
	local base = if magicEggs then Config.MagicEggsGoldenChance else Config.BaseGoldenHatchChance
	return math.min(1, base * (eventGolden or 1))
end

-- Taps collected while away: tapValue x rate x seconds, seconds clamped to [0, cap].
function Formulas.offlineEarnings(tapValue: number, seconds: number, capSeconds: number): number
	local s = math.clamp(seconds, 0, capSeconds)
	return math.floor(tapValue * Config.OfflineTapsPerSecond * s)
end

-- Auto taps per second. idle = the player made no manual tap for Config.AutoTapIdleSeconds.
-- The free rate and the gem upgrade only count while idle; the pass always counts.
function Formulas.autoTapRate(level: number, ownsPass: boolean, idle: boolean): number
	local rate = 0
	if idle then
		rate += Config.AutoTapFreeRate + level * Config.UpgradeById.AutoTap.perLevel
	end
	if ownsPass then
		rate += Config.AutoTapRate
	end
	return rate
end

-- Is this pass / product a paid random item (or a paid probability modifier)?
function Formulas.isPaidRandomPass(key: string): boolean
	return Config.PaidRandomPasses[key] == true
end

function Formulas.isPaidRandomProduct(key: string): boolean
	local product = Config.ProductByKey[key]
	return product ~= nil and Config.PaidRandomProductKinds[product.kind] == true
end

-- The egg a Robux product hatches, if it hatches one (Magic Egg products and the Starter
-- Pack): the store and the offer card show that egg's odds before the purchase prompt.
function Formulas.productEgg(key: string): string?
	local product = Config.ProductByKey[key]
	if not product or (product.kind ~= "egg" and product.kind ~= "starter") then
		return nil
	end
	for _, egg in Config.Eggs do
		if egg.exclusive then
			return egg.id
		end
	end
	return nil
end

export type Odds = { pet: string, chance: number } -- chance in percent

-- Egg odds after luck: every Rare+ weight is multiplied by luck, then renormalised.
function Formulas.odds(eggId: string, luck: number): { Odds }
	local egg = EggById[eggId]
	local out: { Odds } = {}
	if not egg then
		return out
	end
	local total = 0
	local weights: { number } = {}
	for i, e in egg.entries do
		local pet = PetById[e.pet]
		local order = Config.RarityByName[pet.rarity].order
		local w = e.chance
		if order >= Config.LuckAffectsFromOrder then
			w *= luck
		end
		weights[i] = w
		total += w
	end
	for i, e in egg.entries do
		table.insert(out, { pet = e.pet, chance = weights[i] / total * 100 })
	end
	return out
end

-- Odds as shown to the player: numeric percentages that add up to exactly 100.
-- units = millionths (1 unit = 0.0001%), rounded with the largest-remainder method, and no
-- outcome ever shows as 0. text has trailing zeros trimmed ("60%", "8.999%", "0.001%").
export type DisplayOdds = { pet: string, chance: number, units: number, text: string }
local UNITS = 1000000

function Formulas.displayOdds(eggId: string, luck: number): { DisplayOdds }
	local odds = Formulas.odds(eggId, luck)
	local out: { DisplayOdds } = {}
	local used = 0
	local rema: { { i: number, r: number } } = {}
	for i, o in odds do
		local exact = o.chance / 100 * UNITS
		local u = math.max(1, math.floor(exact))
		used += u
		out[i] = { pet = o.pet, chance = o.chance, units = u, text = "" }
		rema[i] = { i = i, r = exact - math.floor(exact) }
	end
	table.sort(rema, function(a, b)
		if a.r == b.r then
			return a.i < b.i
		end
		return a.r > b.r
	end)
	local k = 1
	while used < UNITS do
		out[rema[(k - 1) % #rema + 1].i].units += 1
		used += 1
		k += 1
	end
	-- the max(1, ...) floor can overshoot by a few units: take them from the biggest entry
	while used > UNITS do
		local big = 1
		for i, o in out do
			if o.units > out[big].units then
				big = i
			end
		end
		out[big].units -= 1
		used -= 1
	end
	for _, o in out do
		local whole = o.units // 10000
		local frac = o.units % 10000
		local text = tostring(whole)
		if frac > 0 then
			text ..= "." .. (string.format("%04d", frac):gsub("0+$", ""))
		end
		o.text = text .. "%"
	end
	return out
end

-- r in [0, 1). Returns petId and its (post-luck) chance in percent.
function Formulas.roll(eggId: string, luck: number, r: number): (string, number)
	local odds = Formulas.odds(eggId, luck)
	local acc = 0
	local target = r * 100
	for _, o in odds do
		acc += o.chance
		if target < acc then
			return o.pet, o.chance
		end
	end
	local last = odds[#odds]
	return last.pet, last.chance
end

-- Expected (average) power of one hatch at the given luck; used by the sim and the egg UI.
function Formulas.expectedPower(eggId: string, luck: number, maxZone: number): number
	local sum = 0
	for _, o in Formulas.odds(eggId, luck) do
		sum += Formulas.petPower(o.pet, 0, maxZone) * o.chance / 100
	end
	return sum
end

function Formulas.zoneCost(zoneIndex: number): number
	local z = Config.Zones[zoneIndex]
	return if z then z.cost else math.huge
end

function Formulas.friendBoost(friends: number): number
	return math.min(Config.FriendBoostMax, friends * Config.FriendBoostPer)
end

return Formulas
