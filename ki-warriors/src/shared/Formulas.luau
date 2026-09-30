--!strict
-- Economy and combat math. Pure Luau (shared by server, client, unit tests and the sim).
local Config: any = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Formulas = {}

export type Stats = { strength: number, ki: number, defense: number, agility: number, jump: number }

function Formulas.power(stats: any): number
	local w = Config.PowerWeights
	return math.floor(stats.strength * w.strength + stats.ki * w.ki + stats.defense * w.defense + stats.agility * w.agility + stats.jump * w.jump)
end

function Formulas.gearMult(tier: number): number
	local g = Config.Gear[math.clamp(tier, 1, #Config.Gear)]
	return g.mult
end

function Formulas.rebirthMult(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.multPerRebirth
end

function Formulas.rebirthRequirement(rebirths: number): number
	return Config.Rebirth.basePower * Config.Rebirth.growth ^ rebirths
end

function Formulas.upgradeCost(id: string, level: number): number
	local u = Config.UpgradeById[id]
	return math.floor(u.baseCost * u.costGrowth ^ level + 0.5)
end

function Formulas.upgradeValue(id: string, level: number): number
	return Config.UpgradeById[id].perLevel * level
end

export type TrainContext = {
	zoneMult: number,
	gearTier: number,
	rebirths: number,
	upgradeLevel: number, -- trainPower
	auraMult: number,
	wishPower: number, -- stacks
	passDouble: boolean,
	vip: boolean,
	boost: boolean, -- x2 timed boost
	eventMult: number,
	socialBonus: number, -- friends + premium + group, additive fraction
	raceBonus: number, -- fraction for this stat
}

-- Stat points gained by one training rep.
function Formulas.trainGain(c: TrainContext): number
	local m = Config.Train.baseGain
	m *= c.zoneMult
	m *= Formulas.gearMult(c.gearTier)
	m *= Formulas.rebirthMult(c.rebirths)
	m *= 1 + Formulas.upgradeValue("trainPower", c.upgradeLevel)
	m *= c.auraMult
	m *= 1 + math.min(c.wishPower, Config.WishPowerMax) * 0.05
	if c.passDouble then
		m *= 2
	end
	if c.vip then
		m *= 1 + Config.VipTrainBonus
	end
	if c.boost then
		m *= 2
	end
	m *= c.eventMult
	m *= 1 + c.socialBonus + c.raceBonus
	return m
end

function Formulas.autoRate(upgradeLevel: number, turbo: boolean): number
	local r = Config.Train.autoPerSecond + Formulas.upgradeValue("autoSpeed", upgradeLevel)
	if turbo then
		r *= Config.Train.turboMult
	end
	return r
end

-- Movement derived from stats (log curves so huge numbers stay controllable).
function Formulas.walkSpeed(agility: number): number
	return math.min(62, 16 + 5.2 * math.log10(1 + agility))
end

function Formulas.flySpeed(agility: number, fastFlight: boolean): number
	local s = math.min(230, 72 + 16 * math.log10(1 + agility))
	return if fastFlight then s * Config.FastFlightMult else s
end

function Formulas.jumpPower(jump: number): number
	return math.min(135, 50 + 8.5 * math.log10(1 + jump))
end

function Formulas.maxHp(defense: number): number
	return math.floor(Config.Combat.baseHp + defense * Config.Combat.hpPerDefense)
end

function Formulas.formMult(formIndex: number): number
	local f = Config.Forms[formIndex]
	return if f then f.mult else 1
end

function Formulas.meleeDamage(strength: number, formIndex: number): number
	return (Config.Combat.meleeBase + strength * Config.Combat.meleePerStrength) * Formulas.formMult(formIndex)
end

function Formulas.blastDamage(ki: number, formIndex: number): number
	return (Config.Combat.blastBase + ki * Config.Combat.blastPerKi) * Formulas.formMult(formIndex)
end

-- charge: 0..1
function Formulas.beamDamage(ki: number, formIndex: number, charge: number): number
	local c = math.clamp(charge, 0, 1)
	return (Config.Combat.beamBase + ki * Config.Combat.beamPerKi) * (0.3 + 0.7 * c) * Formulas.formMult(formIndex)
end

function Formulas.beamCost(charge: number): number
	local c = math.clamp(charge, 0, 1)
	return Config.Combat.beamCostMin + (Config.Combat.beamCostMax - Config.Combat.beamCostMin) * c
end

-- Damage a transformed defender actually takes.
function Formulas.mitigate(damage: number, defenderForm: number, blocking: boolean): number
	local d = damage / Formulas.formMult(defenderForm) ^ Config.FormDefenseExponent
	if blocking then
		d *= 1 - Config.Combat.blockReduction
	end
	return d
end

-- PvP: a fraction of the victim's max HP, nudged by the power ratio.
function Formulas.pvpDamage(kind: string, attackerPower: number, victimPower: number, victimMaxHp: number, scale: number?): number
	local pvp = Config.Combat.pvp
	local base = (pvp :: any)[kind] or pvp.melee
	local ratio = math.clamp(((attackerPower + 1) / (victimPower + 1)) ^ pvp.ratioExp, pvp.ratioMin, pvp.ratioMax)
	return victimMaxHp * base * ratio * (scale or 1)
end

-- Highest form the player may use.
function Formulas.bestForm(power: number, rebirths: number): number
	local best = 0
	for i, f in Config.Forms do
		if power >= f.reqPower and rebirths >= (f.reqRebirths or 0) then
			best = i
		end
	end
	return best
end

-- Income estimate: Sparks per minute from fighting on the player's best planet
-- (used to scale "minutes of Sparks" rewards).
function Formulas.sparksPerMinute(bestPlanet: number): number
	local pl = Config.Planets[math.clamp(bestPlanet, 1, #Config.Planets)]
	local small = Config.Npcs[pl.camps[1].npc]
	local mid = Config.Npcs[pl.camps[2].npc]
	return small.sparks * 8 + mid.sparks * 4
end

-- Best planet a power level can enter (ignores the Sparks cost).
function Formulas.planetForPower(power: number): number
	local best = 1
	for i, pl in Config.Planets do
		if power >= pl.reqPower then
			best = i
		end
	end
	return best
end

function Formulas.worldBossHp(bestMelee: number, players: number): number
	local wb = Config.WorldBoss
	local base = Config.Npcs[wb.npc].hp
	local hp = math.max(base, bestMelee * wb.hpPerMelee)
	return math.floor(hp * (1 + math.max(0, players - 1) * wb.maxPlayersScale))
end

-- Weighted aura roll. r in [0,1). lucky doubles the weight of Rare and better.
function Formulas.rollAura(r: number, lucky: boolean): string
	local total = 0
	local weights = {}
	for i, a in Config.Auras do
		local w = a.weight
		if lucky and w > 0 and Config.RarityByName[a.rarity].order >= 3 then
			w *= Config.AuraSpin.luckyMult
		end
		weights[i] = w
		total += w
	end
	local x = r * total
	for i, a in Config.Auras do
		x -= weights[i]
		if x < 0 and weights[i] > 0 then
			return a.id
		end
	end
	return Config.Auras[1].id
end

-- Displayed odds (percent) for each aura in the spin.
function Formulas.auraOdds(lucky: boolean): { { id: string, pct: number } }
	local total = 0
	local list = {}
	for _, a in Config.Auras do
		local w = a.weight
		if lucky and w > 0 and Config.RarityByName[a.rarity].order >= 3 then
			w *= Config.AuraSpin.luckyMult
		end
		if w > 0 then
			total += w
			table.insert(list, { id = a.id, pct = w })
		end
	end
	for _, e in list do
		e.pct = e.pct / total * 100
	end
	return list
end

return Formulas
