--!strict
-- Economy math. Pure (also loaded by sim/ and tests/ with luau.exe).
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Formulas = {}

Formulas.PetById = {} :: { [string]: any }
for _, p in Config.Pets do
	Formulas.PetById[p.id] = p
end
Formulas.CapsuleById = {} :: { [string]: any }
for _, c in Config.Capsules do
	Formulas.CapsuleById[c.id] = c
end

-- Strongest regular pet (Legendary or lower) of each galaxy: the yardstick for exclusive pets.
local zoneRef: { [number]: number } = {}
for _, p in Config.Pets do
	local r = Config.RarityByName[p.rarity]
	if p.zone > 0 and r.order <= 5 then
		zoneRef[p.zone] = math.max(zoneRef[p.zone] or 0, p.power)
	end
end
Formulas.ZoneRef = zoneRef

function Formulas.traitMult(traitId: string?): number
	local i = if traitId then Config.TraitIndex[traitId] else nil
	return if i then Config.Traits[i].mult else 1
end

function Formulas.petPower(id: string, tier: number, maxZone: number, traitId: string?): number
	local pet = Formulas.PetById[id]
	if not pet then
		return 0
	end
	local base = pet.power
	if pet.scale then
		base = (zoneRef[math.clamp(maxZone, 1, #Config.Zones)] or 1) * pet.scale
	end
	local t = Config.Tiers[tier] or Config.Tiers[0]
	return base * t.mult * Formulas.traitMult(traitId)
end

export type Odd = { id: string, rarity: string, chance: number }

-- What the player sees and what the server rolls: percentages that sum to exactly 100.
-- Luck multiplies the weight of every Rare-or-better pet, then everything is renormalised.
-- Galaxy capsules also hold the Secret pet at a fixed Config.SecretChance.
function Formulas.odds(capsuleId: string, luck: number): { Odd }
	local cap = Formulas.CapsuleById[capsuleId]
	local out: { Odd } = {}
	if not cap then
		return out
	end
	local total = 0
	local weights = {}
	for i, entry in cap.pets do
		local pet = Formulas.PetById[entry[1]]
		local w = entry[2]
		if Config.RarityByName[pet.rarity].order >= 3 then
			w *= math.max(1, luck)
		end
		weights[i] = w
		total += w
	end
	local secret = if cap.exclusive then 0 else Config.SecretChance
	local scale = (100 - secret) / total
	local sum = 0
	for i, entry in cap.pets do
		local pet = Formulas.PetById[entry[1]]
		local chance = weights[i] * scale
		sum += chance
		table.insert(out, { id = pet.id, rarity = pet.rarity, chance = chance })
	end
	if secret > 0 then
		table.insert(out, { id = Config.SecretPet, rarity = "Secret", chance = secret })
		sum += secret
	end
	-- absorb floating point drift into the most common entry
	out[1].chance += 100 - sum
	return out
end

-- rnd in [0, 1)
function Formulas.rollCapsule(capsuleId: string, luck: number, rnd: number): Odd
	local odds = Formulas.odds(capsuleId, luck)
	local x = rnd * 100
	-- walk from the rarest entry so tiny chances are not lost to rounding at the top
	for i = #odds, 1, -1 do
		x -= odds[i].chance
		if x < 0 then
			return odds[i]
		end
	end
	return odds[1]
end

-- Generic "pick by chance" for the Relic and Trait tables (chances sum to 100). Returns the index.
function Formulas.rollTable(list: { any }, rnd: number): number
	local x = rnd * 100
	for i = #list, 1, -1 do
		x -= list[i].chance
		if x < 0 then
			return i
		end
	end
	return 1
end

function Formulas.goldenChance(hasPass: boolean): number
	return if hasPass then Config.GoldenChancePass else Config.GoldenChance
end

function Formulas.upgradeCost(id: string, level: number): number
	local u = Config.UpgradeById[id]
	return math.floor(u.base * u.growth ^ level)
end

function Formulas.friendBoost(friends: number): number
	return math.min(Config.FriendBoostMax, Config.FriendBoostPer * friends)
end

function Formulas.maxEquip(upgrades: { [string]: number }, passes: { [string]: boolean }): number
	return Config.BaseEquipSlots + (upgrades.PetSlots or 0) + (upgrades.StarSlot or 0) + (if passes.PetSlots then Config.PetSlotsPass else 0)
end

function Formulas.masteryLevel(count: number): number
	local level = 0
	for i, t in Config.MasteryThresholds do
		if count >= t then
			level = i
		end
	end
	return level
end

export type Bonus = { damage: number, speed: number, luck: number, stardust: number, crystals: number }

-- Permanent bonuses from Mastery, per stat (0.03 = +3%).
function Formulas.masteryBonus(mastery: { [string]: number }): Bonus
	local out: any = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 }
	for _, kind in Config.PlanetKinds do
		local level = Formulas.masteryLevel(mastery[kind.id] or 0)
		out[kind.perm] += level * Config.MasteryBonus
	end
	return out
end

-- Relics: { [stat] = { grade = 0..6, dust = n } } -> bonus per stat.
function Formulas.relicBonus(relics: { [string]: any }): Bonus
	local out: any = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 }
	for _, stat in Config.RelicStats do
		local r = relics[stat]
		local g = if type(r) == "table" then Config.RelicGrades[r.grade] else nil
		if g then
			out[stat] = g.bonus
		end
	end
	return out
end

-- Everything the damage / income formulas need. Built by the server from the profile
-- (State.stats) and by the simulation.
export type Stats = {
	toolIndex: number,
	upgrades: { [string]: number },
	petPower: number,
	rebirths: number,
	passes: { [string]: boolean },
	buffs: { [string]: boolean },
	mastery: Bonus,
	relics: Bonus,
	friends: number,
	indexZones: number,
	premium: boolean,
	eventStardust: number,
	eventLuck: number,
	eventCrystals: number,
	charge: number, -- Overcharge 0..1 (0 before Storm Reach)
}

local function lvl(s: Stats, id: string): number
	return s.upgrades[id] or 0
end

function Formulas.overchargeMult(charge: number, capacitorLevel: number): number
	return 1 + (Config.OverchargeBase + Config.UpgradeById.Capacitor.per * capacitorLevel - 1) * math.clamp(charge, 0, 1)
end

function Formulas.overchargeDecay(insulationLevel: number): number
	return Config.OverchargeDecay + Config.UpgradeById.Insulation.per * insulationLevel
end

-- Damage of one hit (before the galaxy's hardness check and crits).
function Formulas.hitDamage(s: Stats): number
	local tool = Config.Tools[s.toolIndex] or Config.Tools[1]
	local d = tool.power
		* (1 + Config.UpgradeById.Power.per) ^ lvl(s, "Power")
		* (1 + Config.UpgradeById.Temper.per * lvl(s, "Temper"))
		* (1 + s.petPower)
		* (1 + Config.RebirthMult * s.rebirths)
		* (1 + s.mastery.damage + s.relics.damage)
		* (1 + Config.UpgradeById.StarPower.per * lvl(s, "StarPower"))
		* (1 + Config.IndexBoostPerZone * s.indexZones)
		* (1 + Formulas.friendBoost(s.friends))
		* Formulas.overchargeMult(s.charge, lvl(s, "Capacitor"))
	if s.passes.DoubleDamage then
		d *= 2
	end
	if s.passes.VIP then
		d *= Config.VipDamage
	end
	if s.buffs.damage then
		d *= Config.Buffs.damage.mult
	end
	return d
end

-- 1 when the tool is hard enough for the galaxy, Config.SoftDamage otherwise.
function Formulas.hardness(toolIndex: number, zone: number): number
	local z = Config.Zones[zone]
	return if z and toolIndex < z.hardness then Config.SoftDamage else 1
end

-- Multiplier on Stardust drops (the base drop is HP mined x the galaxy's value).
function Formulas.stardustMult(s: Stats): number
	local m = (1 + Config.UpgradeById.Magnet.per * lvl(s, "Magnet"))
		* (1 + Config.RebirthMult * s.rebirths)
		* (1 + s.mastery.stardust + s.relics.stardust)
		* (1 + Config.UpgradeById.StarFortune.per * lvl(s, "StarFortune"))
		* s.eventStardust
	if s.passes.DoubleStardust then
		m *= 2
	end
	if s.premium then
		m *= 1 + Config.PremiumBoost
	end
	if s.buffs.stardust then
		m *= Config.Buffs.stardust.mult
	end
	return m
end

function Formulas.crystalMult(s: Stats): number
	return (1 + s.mastery.crystals + s.relics.crystals) * s.eventCrystals
end

function Formulas.luck(s: Stats): number
	local l = 1 + Config.UpgradeById.Luck.per * lvl(s, "Luck") + Config.UpgradeById.StarLuck.per * lvl(s, "StarLuck") + s.mastery.luck + s.relics.luck
	if s.passes.Lucky then
		l += Config.LuckyPassLuck
	end
	if s.passes.SuperLucky then
		l += Config.SuperLuckyPassLuck
	end
	if s.buffs.luck then
		l *= Config.Buffs.luck.mult
	end
	return l * s.eventLuck
end

function Formulas.hitsPerSecond(s: Stats): number
	local h = (Config.BaseHitsPerSecond + Config.UpgradeById.HitSpeed.per * lvl(s, "HitSpeed")) * (1 + s.mastery.speed + s.relics.speed)
	if s.buffs.speed then
		h *= Config.Buffs.speed.mult
	end
	return h
end

function Formulas.autoRate(s: Stats): number
	local r = Config.AutoMineRateFree + Config.UpgradeById.AutoRate.per * lvl(s, "AutoRate")
	if s.passes.AutoMiner then
		r *= Config.AutoMinePassMult
	end
	if s.buffs.speed then
		r *= Config.Buffs.speed.mult
	end
	return r
end

function Formulas.walkSpeed(s: Stats): number
	local w = Config.BaseWalkSpeed + Config.UpgradeById.MoveSpeed.per * lvl(s, "MoveSpeed")
	if s.passes.Sprint then
		w += Config.SprintPassSpeed
	end
	if s.buffs.speed then
		w *= Config.Buffs.speed.mult
	end
	return w
end

function Formulas.range(s: Stats, auto: boolean?): number
	return Config.BaseRange + Config.UpgradeById.Range.per * lvl(s, "Range") + (if auto and s.passes.AutoMiner then Config.AutoMinePassRange else 0)
end

function Formulas.critChance(s: Stats): number
	return Config.CritChance + Config.UpgradeById.Crit.per * lvl(s, "Crit")
end

function Formulas.cargoCapacity(s: Stats): number
	local c = Config.CargoBase + Config.UpgradeById.Cargo.per * lvl(s, "Cargo")
	if s.passes.VIP then
		c *= 1 + Config.VipCargo
	end
	return math.floor(c)
end

function Formulas.droneSeconds(s: Stats): number
	return math.max(Config.DroneSecondsMin, Config.DroneSeconds - Config.UpgradeById.StarDrone.per * lvl(s, "StarDrone"))
end

function Formulas.planetHp(zone: number, kindId: string): number
	if kindId == "gate" then
		local nextZone = Config.Zones[zone + 1]
		return if nextZone then nextZone.gateHp else 0
	end
	local z = Config.Zones[zone]
	local k = Config.PlanetKindById[kindId]
	return z.hp * k.hpMult
end

-- The Gate is a single slab; every other planet has the three layers.
function Formulas.layerCount(kindId: string): number
	return if kindId == "gate" then 1 else #Config.Layers
end

function Formulas.layerHp(zone: number, kindId: string, layer: number): number
	if kindId == "gate" then
		return Formulas.planetHp(zone, kindId)
	end
	return math.max(1, math.floor(Formulas.planetHp(zone, kindId) * Config.Layers[layer].share + 0.5))
end

-- Stardust value of a whole layer (before the player's multiplier).
function Formulas.layerValue(zone: number, kindId: string, layer: number): number
	return Formulas.layerHp(zone, kindId, layer) * Config.Zones[zone].value * Config.PlanetKindById[kindId].valueMult
end

-- Kind of a regular node when it (re)spawns. rnd in [0, 1).
function Formulas.rollKind(luck: number, rnd: number): string
	local boost = math.clamp(luck, 1, 3)
	local total = 0
	for _, k in Config.PlanetKinds do
		total += if k.rare then k.weight * boost else k.weight
	end
	local x = rnd * total
	for _, k in Config.PlanetKinds do
		x -= if k.rare then k.weight * boost else k.weight
		if x < 0 then
			return k.id
		end
	end
	return "rock"
end

function Formulas.rebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

function Formulas.rebirthCrystals(rebirths: number): number
	return Config.RebirthCrystalsBase + Config.RebirthCrystalsPer * rebirths
end

-- Best galaxy the player can mine at full strength (hardness) among the ones they own.
function Formulas.incomeZone(toolIndex: number, maxZone: number): number
	local best = 1
	for z = 1, maxZone do
		if Formulas.hardness(toolIndex, z) == 1 then
			best = z
		end
	end
	return best
end

-- Expected Stardust per second of active mining in `zone` ("minutes of income" rewards,
-- arena rewards and offline mining). A hit cannot mine more than a whole layer.
function Formulas.income(hitDamage: number, zone: number, stardustMult: number): number
	local z = Config.Zones[zone]
	local perHit = math.min(hitDamage, z.hp / #Config.Layers)
	return perHit * z.value * stardustMult * Config.IncomeHitsPerSecond
end

function Formulas.pvpDamage(attackerPower: number, defenderPower: number): number
	local c = Config.Pvp
	local ratio = (math.max(1, attackerPower) / math.max(1, defenderPower)) ^ c.ratioExponent
	return math.floor(c.baseDamage * math.clamp(ratio, c.minRatio, c.maxRatio) + 0.5)
end

-- The Anomaly planet is up during the first AnomalyDuration seconds of every AnomalyEvery.
function Formulas.anomaly(now: number): (boolean, number, number)
	local phase = now % Config.AnomalyEvery
	local window = now - phase
	if phase < Config.AnomalyDuration then
		return true, window, window + Config.AnomalyDuration
	end
	return false, window, window + Config.AnomalyEvery
end

-- A blank Stats value (tests, sim).
function Formulas.blankStats(): Stats
	return {
		toolIndex = 1,
		upgrades = {},
		petPower = 0,
		rebirths = 0,
		passes = {},
		buffs = {},
		mastery = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 },
		relics = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 },
		friends = 0,
		indexZones = 0,
		premium = false,
		eventStardust = 1,
		eventLuck = 1,
		eventCrystals = 1,
		charge = 0,
	}
end

return Formulas
