-- Pacing model for a FREE player (no passes, no Robux). Pure Luau, reuses the real Config and
-- Formulas. Used by sim/pacing_sim.luau (prints the table) and tests/pacing_test.luau (guards
-- the target windows). Returns { run = function(seed, hours, opts) -> Result, median = ... }.
--
-- Policy of the simulated player:
--   * 5 manual hits/s, plus the free Auto Mine (AutoMineRateFree hits/s) once the tutorial
--     reaches its "auto" step (first minute); the Cargo Drone sells the hold
--   * follows the tutorial (rewards included), claims the daily reward ~20 s after joining and
--     every in-session gift 10 s after it is ready
--   * buys whatever pays back fastest (tool, Power, Cargo, capsule of its top galaxy) and
--     spends Crystals on the first pet slot, then the cheapest lab upgrade, materials on their galaxy's system
--   * breaks a Gate Planet when it would fall in under 4 minutes; rebirths as soon as it can
local Config = require("../src/shared/Config")
local F = require("../src/shared/Formulas")

local Model = {}

local function rng(seed: number)
	local s = seed % 2147483646 + 1
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

-- average regular planet
local avgHp, avgValue, wsum = 0, 0, 0
for _, k in Config.PlanetKinds do
	if k.weight > 0 then
		avgHp += k.hpMult * k.weight
		avgValue += k.hpMult * k.valueMult * k.weight
		wsum += k.weight
	end
end
avgHp /= wsum
avgValue /= wsum

local MANUAL_HPS = 5 -- a real player taps a bit under the 6 hits/s cap
local AUTO_ON_AT = 45 -- seconds: the tutorial's "auto" step
local DAILY_AT = 20 -- seconds after joining
local GATE_SECONDS = 240 -- attacks the next Gate once it would fall in under this many seconds
local GIFT_DELAY = 10 -- seconds between a gift being ready and the player claiming it

export type Result = {
	events: { { t: number, kind: string, what: string } },
	m: { [string]: number }, -- milestones (seconds)
	upgradesAt: { number }, -- time of every upgrade purchase (tool / Power / Cargo / crystal / material)
	gaps: { { from: number, to: number, what: string } },
	trace: { { t: number, stardust: number, income: number, zone: number, tool: number, power: number, damage: number, gateLeft: number } }, -- one sample a minute
}

function Model.run(seed: number, hours: number, opts: { daily: boolean? }?): Result
	local useDaily = not (opts and opts.daily == false)
	local rand = rng(seed)
	local st = {
		stardust = 0, crystals = 0, rebirths = 0, zone = 1, tool = 1,
		up = {} :: { [string]: number },
		pets = { F.petPower(Config.StartingPet, 0, 1) },
		trait = 1,
		mats = { spores = 0, cryo = 0, embers = 0, volt = 0, essence = 0 } :: { [string]: number },
		relics = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 } :: { [string]: number },
		gate = {} :: { [number]: number },
		t = 0,
	}
	for _, u in Config.Upgrades do
		st.up[u.id] = 0
	end
	local res: Result = { events = {}, m = {}, upgradesAt = {}, gaps = {}, trace = {} }
	local function mark(key: string)
		if not res.m[key] then
			res.m[key] = st.t
		end
	end
	local function log(kind: string, what: string)
		table.insert(res.events, { t = st.t, kind = kind, what = what })
	end
	-- "tier" events: something new for the player (first time owning a tool, a galaxy, the first
	-- capsule of a galaxy, a galaxy system used for the first time, a pet slot, a rebirth)
	local tierTimes: { { t: number, what: string } } = {}
	local function tier(what: string)
		table.insert(tierTimes, { t = st.t, what = what })
		log("tier", what)
	end
	local function upgraded(what: string)
		table.insert(res.upgradesAt, st.t)
		mark("firstPurchase")
		log("buy", what)
	end

	local function slots()
		return F.maxEquip(st.up, {})
	end
	local function petSum()
		table.sort(st.pets, function(a, b)
			return a > b
		end)
		local s = 0
		for i = 1, math.min(slots(), #st.pets) do
			s += st.pets[i] * (if i == 1 then st.trait else 1)
		end
		return s
	end
	local function stats(toolIdx: number, powerLvl: number, petPower: number): any
		local s = F.blankStats()
		s.toolIndex = toolIdx
		s.upgrades = table.clone(st.up)
		s.upgrades.Power = powerLvl
		s.petPower = petPower
		s.rebirths = st.rebirths
		s.mastery = { damage = 0.06, speed = 0, luck = 0, stardust = 0.03, crystals = 0 }
		local rb = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 }
		for stat, g in st.relics do
			if g > 0 then
				rb[stat] = Config.RelicGrades[g].bonus
			end
		end
		s.relics = rb
		s.charge = if st.zone >= 5 then 0.85 else 0
		return s
	end
	local autoOn = false
	local function hps(s: any): number
		return MANUAL_HPS + (if autoOn then F.autoRate(s) else 0)
	end
	-- stardust per second mining in `zone`: the best of the three planet classes
	local function income(zone: number, s: any): (number, number)
		local z = Config.Zones[zone]
		local dmg = F.hitDamage(s) * F.hardness(s.toolIndex, zone) * (1 + F.critChance(s) * (Config.CritMult - 1))
		local rate = hps(s)
		local mult = F.stardustMult(s) * 1.1 -- buffs give ~+10%
		local bestInc, bestCores = 0, 0
		local classes = {
			{ hp = z.hp * avgHp, value = z.hp * avgValue * z.value, respawn = 0, walk = 1.5 },
			{ hp = z.hp * avgHp * Config.DenseMult, value = z.hp * avgValue * z.value * Config.DenseMult, respawn = 0, walk = 2.5 },
			{ hp = z.hp * Config.PlanetKindById.titan.hpMult, value = z.hp * Config.PlanetKindById.titan.hpMult * Config.PlanetKindById.titan.valueMult * z.value, respawn = Config.TitanRespawn, walk = 0 },
		}
		for _, c in classes do
			local hits = 0
			for _, layer in Config.Layers do
				hits += math.ceil(c.hp * layer.share / dmg)
			end
			local cycle = math.max(hits / rate + c.walk, c.respawn)
			local chunkRate = 4 / cycle
			local cargoEff = math.min(1, F.cargoCapacity(s) / (chunkRate * F.droneSeconds(s)))
			local inc = c.value * mult / cycle * cargoEff
			if inc > bestInc then
				bestInc, bestCores = inc, cargoEff / cycle
			end
		end
		return bestInc, bestCores
	end
	local function best(s: any): (number, number, number)
		local bi, bz, bc = 0, 1, 0
		for z = 1, st.zone do
			local inc, cores = income(z, s)
			if inc > bi then
				bi, bz, bc = inc, z, cores
			end
		end
		return bi, bz, bc
	end

	-- Tutorial (Config.Tutorial): rewards arrive as the player does each step
	local tut = 1
	local function tutorial(id: string)
		local step = Config.Tutorial[tut]
		if step and step.id == id then
			tut += 1
			if step.reward.kind == "stardust" then
				st.stardust += step.reward.amount
			else
				st.crystals += step.reward.amount
			end
			mark("tut_" .. id)
			mark("firstGain")
			log("tutorial", id)
		end
	end
	-- first planet: seconds for crust / core / sell with the starting kit
	do
		local s = stats(1, 0, petSum())
		local d = F.hitDamage(s)
		local rate = MANUAL_HPS
		local crustT = math.ceil(F.layerHp(1, "rock", 1) / d) / rate
		local mantleT = math.ceil(F.layerHp(1, "rock", 2) / d) / rate
		local coreT = math.ceil(F.layerHp(1, "rock", 3) / d) / rate
		res.m.crustBreak = crustT
		res.m.firstPlanet = crustT + mantleT + coreT
		res.m.firstSale = crustT + mantleT + coreT + 2 -- walk to the Refinery pad
	end

	local nextSample = 60
	local giftsDone: { [number]: boolean } = {}
	local dailyDone = not useDaily
	local dt = 0.5
	local zoneCapsuleSeen: { [number]: boolean } = {}
	local toolSeen: { [number]: boolean } = {}
	local systemSeen: { [string]: boolean } = {}
	local firstSaleDone = false
	local function bump(key: string, n: number)
		res.m[key] = (res.m[key] or 0) + n
	end
	while st.t < hours * 3600 do
		st.t += dt
		if st.t > 300 then
			dt = 1
		end
		if not autoOn and st.t >= AUTO_ON_AT then
			autoOn = true
			tutorial("auto") -- the tutorial orders steps; the reward lands whenever all earlier ones are done
		end
		if st.t >= res.m.crustBreak then
			tutorial("mine")
		end
		if st.t >= res.m.firstPlanet - 0.6 then
			tutorial("core")
		end
		if not firstSaleDone and st.t >= res.m.firstSale then
			firstSaleDone = true
			st.stardust += 60 * 1.2 -- the first rock, sold by hand
			tutorial("sell")
			mark("firstStardust")
		end
		local pp = petSum()
		local s = stats(st.tool, st.up.Power, pp)
		local inc, zoneMined, cores = best(s)
		if firstSaleDone == false then
			inc = 0 -- nothing sold yet
		end

		-- Gate Planet of the current top galaxy
		local nz = Config.Zones[st.zone + 1]
		local atGate = false
		if nz and firstSaleDone then
			local left = st.gate[st.zone + 1] or nz.gateHp
			local dps = F.hitDamage(s) * hps(s)
			if left <= dps * GATE_SECONDS then
				atGate = true
				left -= dps * dt
				st.gate[st.zone + 1] = left
				if left <= 0 then
					st.zone += 1
					st.crystals += Config.GateCrystals[st.zone]
					mark("zone" .. st.zone)
					tier("zone " .. st.zone)
				end
			end
		end
		if not atGate and firstSaleDone then
			st.stardust += inc * dt
			local mat = Config.Zones[zoneMined].material
			if mat then
				st.mats[mat] += cores * dt * 1.4
			end
			st.crystals += Config.Zones[zoneMined].crystal * dt / 14
		end
		-- daily reward: minutes of your income at that moment (Rewards.grant: at least 50)
		if not dailyDone and st.t >= DAILY_AT then
			dailyDone = true
			local dInc = F.income(F.hitDamage(s), 1, F.stardustMult(s))
			local v = math.max(50, dInc * 60 * Config.DailyRewards[1].amount)
			st.stardust += v
			mark("firstGain")
			log("daily", string.format("%.0f stardust", v))
		end
		for i, g in Config.Gifts do
			if not giftsDone[i] and st.t >= g.minutes * 60 + GIFT_DELAY then
				giftsDone[i] = true
				log("gift", g.reward.kind .. " " .. g.reward.amount)
				if g.reward.kind == "stardustMin" then
					st.stardust += math.max(50, F.income(F.hitDamage(s), zoneMined, F.stardustMult(s)) * 60 * g.reward.amount)
				elseif g.reward.kind == "crystals" then
					st.crystals += g.reward.amount
				end
			end
		end
		-- crystal + material upgrades: cheapest first
		for _, u in Config.Upgrades do
			if u.currency ~= "stardust" and st.up[u.id] < u.max then
				local cost = F.upgradeCost(u.id, st.up[u.id])
				if u.currency == "crystals" then
					-- saves for the first extra pet slot before anything else in the Lab
					local saving = u.id ~= "PetSlots" and st.up.PetSlots == 0
					if st.crystals >= cost and cost < 600 and not saving then
						st.crystals -= cost
						st.up[u.id] += 1
						upgraded(u.id .. " " .. st.up[u.id])
						if u.id == "PetSlots" then
							tier("pet slot " .. st.up[u.id])
						end
					end
				elseif st.mats[u.currency] >= cost then
					st.mats[u.currency] -= cost
					st.up[u.id] += 1
					upgraded(u.id .. " " .. st.up[u.id])
					if not systemSeen[u.system] then
						systemSeen[u.system] = true
						tier("system " .. u.system)
					end
				end
			end
		end
		while st.mats.spores >= Config.RelicCost do
			st.mats.spores -= Config.RelicCost
			if not systemSeen.relics then
				systemSeen.relics = true
				tier("system relics")
			end
			local stat = Config.RelicStats[math.floor(rand() * #Config.RelicStats) + 1]
			local grade = F.rollTable(Config.RelicGrades, rand())
			if grade > st.relics[stat] then
				st.relics[stat] = grade
			end
		end
		while st.mats.embers >= Config.TraitCost do
			st.mats.embers -= Config.TraitCost
			if not systemSeen.traits then
				systemSeen.traits = true
				tier("system traits")
			end
			local m = Config.Traits[F.rollTable(Config.Traits, rand())].mult
			if m > st.trait then
				st.trait = m
			else
				st.mats.embers += Config.TraitRefund
			end
		end
		-- stardust purchases: repeat while something pays back quickly
		-- a damage purchase that saves more seconds on the next Gate than it costs in income is
		-- worth it even when income itself is capped by the planets' HP (what a player heading for
		-- the next galaxy does)
		local gateZone = Config.Zones[st.zone + 1]
		local gateLeft = if gateZone then (st.gate[st.zone + 1] or gateZone.gateHp) else 0
		local function gateEta(toolIdx: number, powerLvl: number, petPower: number): number
			local gs = stats(toolIdx, powerLvl, petPower)
			return gateLeft / math.max(1e-9, F.hitDamage(gs) * hps(gs))
		end
		for _ = 1, 6 do
			local options: { any } = {}
			local eta0 = if gateZone then gateEta(st.tool, st.up.Power, pp) else 0
			local tool = Config.Tools[st.tool + 1]
			if tool and tool.zone <= st.zone then
				table.insert(options, { name = "tool " .. tool.id, isTool = true, cost = tool.cost, gain = best(stats(st.tool + 1, st.up.Power, pp)) - inc, limit = 300, gateSecs = if gateZone then eta0 - gateEta(st.tool + 1, st.up.Power, pp) else 0, apply = function()
					st.tool += 1
				end })
			end
			if st.up.Power < Config.UpgradeById.Power.max then
				table.insert(options, { name = "Power", cost = F.upgradeCost("Power", st.up.Power), gain = best(stats(st.tool, st.up.Power + 1, pp)) - inc, limit = 400, gateSecs = if gateZone then eta0 - gateEta(st.tool, st.up.Power + 1, pp) else 0, apply = function()
					st.up.Power += 1
				end })
			end
			if st.up.Cargo < Config.UpgradeById.Cargo.max then
				st.up.Cargo += 1
				local gain = best(stats(st.tool, st.up.Power, pp)) - inc
				st.up.Cargo -= 1
				table.insert(options, { name = "Cargo", cost = F.upgradeCost("Cargo", st.up.Cargo), gain = gain, limit = 240, apply = function()
					st.up.Cargo += 1
				end })
			end
			local capsule = Config.Capsules[st.zone]
			if capsule and not capsule.exclusive then
				local weakest = if #st.pets >= slots() then st.pets[slots()] else 0
				local exp = 0
				for _, o in F.odds(capsule.id, 1 + 0.1 * st.up.Luck) do
					exp += o.chance / 100 * math.max(0, F.petPower(o.id, 0, st.zone) - weakest)
				end
				table.insert(options, { name = "capsule " .. capsule.id, capsule = true, cost = capsule.price, gain = best(stats(st.tool, st.up.Power, pp + exp)) - inc, limit = 120, apply = function()
					local odd = F.rollCapsule(capsule.id, 1 + 0.1 * st.up.Luck, rand())
					table.insert(st.pets, F.petPower(odd.id, 0, st.zone))
					tutorial("capsule")
					bump("capsules", 1)
				end })
			end
			local pick, pickPayback = nil, math.huge
			for _, o in options do
				if o.cost <= st.stardust then
					-- spare money (under 5% of the wallet) is spent even when the gain is capped
					local payback = if o.gain > 0 then o.cost / o.gain else math.huge
					if o.cost < st.stardust * 0.05 and not o.capsule then
						payback = math.min(payback, 1)
					end
					if o.gateSecs and o.gateSecs > o.cost / math.max(inc, 1e-9) then
						payback = math.min(payback, 10)
					end
					if payback < o.limit and payback < pickPayback then
						pick, pickPayback = o, payback
					end
				end
			end
			if not pick then
				break
			end
			st.stardust -= pick.cost
			pick.apply()
			if pick.capsule then
				if not zoneCapsuleSeen[st.zone] then
					zoneCapsuleSeen[st.zone] = true
					tier("capsule " .. Config.Capsules[st.zone].id)
				end
				log("buy", pick.name)
			else
				upgraded(pick.name)
			end
			if pick.isTool then
				tutorial("tool")
				if not toolSeen[st.tool] then
					toolSeen[st.tool] = true
					tier(pick.name)
				end
			end
			pp = petSum()
			s = stats(st.tool, st.up.Power, pp)
			inc = best(s)
		end
		if st.t >= nextSample then
			nextSample += 60
			table.insert(res.trace, { t = st.t, stardust = st.stardust, income = inc, zone = st.zone, tool = st.tool, power = st.up.Power, damage = F.hitDamage(s), gateLeft = st.gate[st.zone + 1] or (if nz then nz.gateHp else 0) })
		end
		-- rebirth
		if st.stardust >= F.rebirthCost(st.rebirths) then
			st.crystals += F.rebirthCrystals(st.rebirths)
			st.rebirths += 1
			mark("rebirth" .. st.rebirths)
			tier("rebirth " .. st.rebirths)
			st.stardust, st.tool, st.up.Power = 0, 1, 0
		end
	end

	-- derived milestones
	local n3 = 0
	for _, t in res.upgradesAt do
		if t <= 180 then
			n3 += 1
		end
	end
	res.m.upgradesBy3min = n3
	res.m.endRebirths = st.rebirths
	-- longest stretch without a new tier event (t = 0 to the 1 h mark)
	local prev = 0
	local worst, worstFrom, worstTo = 0, 0, 0
	for _, e in tierTimes do
		local to = math.min(e.t, 3600)
		if to - prev > worst then
			worst, worstFrom, worstTo = to - prev, prev, to
		end
		prev = e.t
		if prev >= 3600 then
			break
		end
	end
	if prev < 3600 and hours >= 1 and 3600 - prev > worst then
		worst, worstFrom, worstTo = 3600 - prev, prev, 3600
	end
	res.m.maxTierGap1h = worst
	res.m.maxTierGapFrom = worstFrom
	res.m.maxTierGapTo = worstTo
	-- every tier-event gap over 10 min in the whole run (what the player waits for)
	prev = 0
	for _, e in tierTimes do
		if e.t - prev > 600 then
			table.insert(res.gaps, { from = prev, to = e.t, what = e.what })
		end
		prev = e.t
	end
	res.m.tiers1h = 0
	for _, e in tierTimes do
		if e.t <= 3600 then
			res.m.tiers1h += 1
		end
	end
	return res
end

-- Median of each milestone over several seeds (a run that never got there is left out).
function Model.median(seeds: number, hours: number, opts: any?): ({ [string]: number }, { Result })
	local lists: { [string]: { number } } = {}
	local runs = {}
	for i = 1, seeds do
		local r = Model.run(i * 7919, hours, opts)
		table.insert(runs, r)
		for k, v in r.m do
			lists[k] = lists[k] or {}
		end
	end
	for k, list in lists do
		for _, r in runs do
			local v = r.m[k]
			if v == nil and (k:sub(1, 4) == "zone" or k:sub(1, 7) == "rebirth") then
				v = hours * 3600 * 1.3 -- not reached: counts as 1.3x the horizon
			end
			if v ~= nil then
				table.insert(list, v)
			end
		end
	end
	local out = {}
	for k, list in lists do
		table.sort(list)
		out[k] = list[(#list + 1) // 2]
	end
	-- the worst seed, for the "never a dead stretch" rule
	out.worstTierGap1h = 0
	for _, r in runs do
		out.worstTierGap1h = math.max(out.worstTierGap1h, r.m.maxTierGap1h)
	end
	return out, runs
end

return Model
