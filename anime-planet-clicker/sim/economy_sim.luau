-- Economy simulation (run from the repo root). For the pacing of a session (first minutes,
-- tier timeline, dead stretches) use sim/pacing_sim.luau; this one is the stricter long-run view
-- (no tutorial, daily or gift rewards, a Gate only when it falls in under 2.5 min), so its
-- galaxy times are later than the pacing sim's.
--   ../huerta-tycoon/tools/luau.exe sim/economy_sim.luau -a <hours> <seeds>
--   ../huerta-tycoon/tools/luau.exe sim/economy_sim.luau -a tune      (fits gates, prices, rebirth)
-- An average free player: 5 manual hits/s + free Auto Mine, no passes, the Cargo Drone sells,
-- buys whatever pays back fastest (tool, Power, Cargo, capsule), attacks a Gate Planet when it
-- would fall in under 2.5 minutes, spends galaxy materials on that galaxy's system, and
-- rebirths as soon as it can.
local Config = require("../src/shared/Config")
local F = require("../src/shared/Formulas")

local args = { ... }
local HOURS = tonumber(args[1]) or 8
local SEEDS = tonumber(args[2]) or 6

local function rng(seed)
	local s = seed % 2147483646 + 1
	return function()
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

local TRACE = false
local hm
local function run(seed)
	local rand = rng(seed)
	local st = {
		stardust = 0, crystals = 0, rebirths = 0, zone = 1, tool = 1,
		up = {},
		pets = { F.petPower(Config.StartingPet, 0, 1) },
		trait = 1,
		mats = { spores = 0, cryo = 0, embers = 0, volt = 0, essence = 0 },
		relics = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 },
		gate = {},
		t = 0, milestones = {}, opened = 0,
	}
	for _, u in Config.Upgrades do
		st.up[u.id] = 0
	end
	local function slots()
		return F.maxEquip(st.up, {})
	end
	local function petSum()
		table.sort(st.pets, function(a, b) return a > b end)
		local s = 0
		for i = 1, math.min(slots(), #st.pets) do
			s += st.pets[i] * (if i == 1 then st.trait else 1)
		end
		return s
	end
	local function stats(toolIdx, powerLvl, petPower)
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
	-- stardust per second mining in `zone` with those stats: the best of the three planet
	-- classes (inner ring, dense outer ring, Titan)
	local function income(zone, s)
		local z = Config.Zones[zone]
		local dmg = F.hitDamage(s) * F.hardness(s.toolIndex, zone) * (1 + F.critChance(s) * (Config.CritMult - 1))
		local hps = 5 + F.autoRate(s)
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
			local cycle = math.max(hits / hps + c.walk, c.respawn)
			local chunkRate = 4 / cycle
			local cargoEff = math.min(1, F.cargoCapacity(s) / (chunkRate * F.droneSeconds(s)))
			local inc = c.value * mult / cycle * cargoEff
			if inc > bestInc then
				bestInc, bestCores = inc, cargoEff / cycle
			end
		end
		return bestInc, bestCores
	end
	local function best(s)
		local bi, bz, bc = 0, 1, 0
		for z = 1, st.zone do
			local inc, cores = income(z, s)
			if inc > bi then
				bi, bz, bc = inc, z, cores
			end
		end
		return bi, bz, bc
	end
	local giftsDone = {}
	local dt = 1
	while st.t < HOURS * 3600 do
		st.t += dt
		local pp = petSum()
		local s = stats(st.tool, st.up.Power, pp)
		local inc, zoneMined, cores = best(s)

		-- Gate Planet of the current top galaxy
		local nz = Config.Zones[st.zone + 1]
		local atGate = false
		if nz then
			local left = st.gate[st.zone + 1] or nz.gateHp
			local dps = F.hitDamage(s) * (5 + F.autoRate(s))
			if left <= dps * 150 then
				atGate = true
				left -= dps * dt
				st.gate[st.zone + 1] = left
				if left <= 0 then
					st.zone += 1
					st.crystals += Config.GateCrystals[st.zone]
					if not st.milestones["zone" .. st.zone] then
						st.milestones["zone" .. st.zone] = st.t
						st.milestones["dmg" .. st.zone] = F.hitDamage(s)
					end
				end
			end
		end
		if not atGate then
			st.stardust += inc * dt
			local mat = Config.Zones[zoneMined].material
			if mat then
				st.mats[mat] += cores * dt * 1.4
			end
			st.crystals += Config.Zones[zoneMined].crystal * dt / 14
		end
		for i, g in Config.Gifts do
			if not giftsDone[i] and st.t >= g.minutes * 60 then
				giftsDone[i] = true
				if g.reward.kind == "stardustMin" then
					st.stardust += inc * 60 * g.reward.amount
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
					if st.crystals >= cost and cost < 600 then
						st.crystals -= cost
						st.up[u.id] += 1
					end
				elseif st.mats[u.currency] >= cost then
					st.mats[u.currency] -= cost
					st.up[u.id] += 1
				end
			end
		end
		while st.mats.spores >= Config.RelicCost do
			st.mats.spores -= Config.RelicCost
			local stat = Config.RelicStats[math.floor(rand() * #Config.RelicStats) + 1]
			local grade = F.rollTable(Config.RelicGrades, rand())
			if grade > st.relics[stat] then
				st.relics[stat] = grade
			end
		end
		while st.mats.embers >= Config.TraitCost do
			st.mats.embers -= Config.TraitCost
			local m = Config.Traits[F.rollTable(Config.Traits, rand())].mult
			if m > st.trait then
				st.trait = m
			else
				st.mats.embers += Config.TraitRefund
			end
		end
		-- stardust purchases: repeat while something pays back quickly
		for _ = 1, 6 do
			local options = {}
			local tool = Config.Tools[st.tool + 1]
			if tool and tool.zone <= st.zone then
				table.insert(options, { cost = tool.cost, gain = best(stats(st.tool + 1, st.up.Power, pp)) - inc, limit = 300, apply = function() st.tool += 1 end })
			end
			if st.up.Power < Config.UpgradeById.Power.max then
				table.insert(options, { cost = F.upgradeCost("Power", st.up.Power), gain = best(stats(st.tool, st.up.Power + 1, pp)) - inc, limit = 400, apply = function() st.up.Power += 1 end })
			end
			if st.up.Cargo < Config.UpgradeById.Cargo.max then
				st.up.Cargo += 1
				local gain = best(stats(st.tool, st.up.Power, pp)) - inc
				st.up.Cargo -= 1
				table.insert(options, { cost = F.upgradeCost("Cargo", st.up.Cargo), gain = gain, limit = 240, apply = function() st.up.Cargo += 1 end })
			end
			local capsule = Config.Capsules[st.zone]
			if capsule and not capsule.exclusive then
				local weakest = if #st.pets >= slots() then st.pets[slots()] else 0
				local exp = 0
				for _, o in F.odds(capsule.id, 1 + 0.1 * st.up.Luck) do
					exp += o.chance / 100 * math.max(0, F.petPower(o.id, 0, st.zone) - weakest)
				end
				table.insert(options, { cost = capsule.price, capsule = true, gain = best(stats(st.tool, st.up.Power, pp + exp)) - inc, limit = 120, apply = function()
					local odd = F.rollCapsule(capsule.id, 1 + 0.1 * st.up.Luck, rand())
					table.insert(st.pets, F.petPower(odd.id, 0, st.zone))
					st.opened += 1
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
			pp = petSum()
			s = stats(st.tool, st.up.Power, pp)
			inc = best(s)
		end
		if TRACE and st.t % 600 == 0 then
			print(string.format("t=%s sd=%.3g inc=%.3g z=%d mined=%d dmg=%.3g tool=%d pow=%d cargo=%d pets=%.3g reb=%d gateLeft=%.3g", hm(st.t), st.stardust, inc, st.zone, zoneMined, F.hitDamage(s), st.tool, st.up.Power, st.up.Cargo, pp, st.rebirths, st.gate[st.zone + 1] or -1))
		end
		-- rebirth
		if st.stardust >= F.rebirthCost(st.rebirths) then
			st.crystals += F.rebirthCrystals(st.rebirths)
			st.rebirths += 1
			if not st.milestones["rebirth" .. st.rebirths] then
				st.milestones["rebirth" .. st.rebirths] = st.t
			end
			st.stardust, st.tool, st.up.Power = 0, 1, 0
		end
	end
	return st
end

local keys = { "dmg2", "dmg3", "dmg4", "dmg5", "dmg6", "zone2", "zone3", "rebirth1", "zone4", "rebirth2", "zone5", "rebirth3", "zone6", "rebirth4", "rebirth5", "rebirth6" }
function hm(s)
	return string.format("%dh %02dm %02ds", s // 3600, (s % 3600) // 60, s % 60)
end
-- Median over the seeds; a milestone a run never reached counts as 1.3x the simulated time.
local function average(seeds)
	local lists, counts = {}, {}
	local lastSt
	for seed = 1, seeds do
		local st = run(seed * 7919)
		lastSt = st
		for _, k in keys do
			lists[k] = lists[k] or {}
			if st.milestones[k] then
				table.insert(lists[k], st.milestones[k])
				counts[k] = (counts[k] or 0) + 1
			elseif k:sub(1, 3) ~= "dmg" then
				table.insert(lists[k], HOURS * 3600 * 1.3)
			end
		end
	end
	local avg = {}
	for k, list in lists do
		if #list > 0 and counts[k] then
			table.sort(list)
			avg[k] = list[(#list + 1) // 2]
		end
	end
	return avg, counts, lastSt
end

local function round(n)
	local e = 10 ^ math.floor(math.log10(n) - 1)
	return math.floor(n / e + 0.5) * e
end

-- "tune": tool and capsule prices are "planets' worth" of their galaxy, and the gates + the
-- first rebirth cost are fitted to the target times.
-- Prices are "planets' worth" of their galaxy.
local function follow()
	local PLANETS = { capsule = 4, toolA = 10, toolB = 110 }
	for z = 2, #Config.Zones do
		local pv = Config.Zones[z].hp * Config.Zones[z].value
		Config.Capsules[z].price = round(pv * PLANETS.capsule)
		local first = true
		for _, t in Config.Tools do
			if t.zone == z then
				t.cost = round(pv * (if first then PLANETS.toolA else PLANETS.toolB))
				first = false
			end
		end
	end
end
local function printConfig()
	for z = 2, #Config.Zones do
		print(string.format("zone %d gateHp = %.3g hp = %.3g", z, Config.Zones[z].gateHp, Config.Zones[z].hp))
	end
	print(string.format("RebirthBaseCost = %.3g", Config.RebirthBaseCost))
	for _, t in Config.Tools do
		if t.zone > 1 then
			print(string.format("tool %s cost = %.3g", t.id, t.cost))
		end
	end
	for z = 2, #Config.Zones do
		print(string.format("capsule %s price = %.3g", Config.Capsules[z].id, Config.Capsules[z].price))
	end
end

-- "tune": one galaxy at a time, in order. Two knobs per galaxy: its Gate's HP (when you
-- get in) and its planets' HP (a Rock planet = HP_HITS hits with the damage you arrive with).
-- Rebirths are off while fitting; set Config.RebirthBaseCost by hand afterwards.
if args[1] == "tune" then
	local targets = { zone2 = 360, zone3 = 2100, zone4 = 7200, zone5 = 14400, zone6 = 25200 }
	local HP_HITS = 40
	local rebirthCost = Config.RebirthBaseCost
	Config.RebirthBaseCost = 1e300
	for zi = 2, #Config.Zones do
		local key = "zone" .. zi
		local want = targets[key]
		local z = Config.Zones[zi]
		HOURS = math.max(0.5, want * 2.2 / 3600)
		for iter = 1, 24 do
			local avg = average(5)
			local got = avg[key] or HOURS * 3600 * 1.3
			local d = avg["dmg" .. zi]
			if d then
				z.hp *= (d * HP_HITS / z.hp) ^ 0.7
			end
			z.gateHp *= math.clamp((want / got) ^ 1.2, 0.2, 5)
			follow()
			if math.abs(math.log(want / got)) < 0.04 and iter > 3 then
				break
			end
		end
		z.gateHp = round(z.gateHp)
		z.hp = round(z.hp)
		follow()
		print(string.format("-- fitted zone %d", zi))
	end
	Config.RebirthBaseCost = rebirthCost
	printConfig()
	HOURS = 10
	SEEDS = 8
end
if args[1] == "trace" then
	TRACE = true
	HOURS = tonumber(args[2]) or 4
	run(7919)
	return
end
local avg, counts, lastSt = average(SEEDS)
print(string.format("economy sim: %d seeds x %d h (free player)", SEEDS, HOURS))
for _, k in keys do
	if k:sub(1, 3) == "dmg" then
		print(string.format("  %-9s %.3g", k, avg[k] or 0))
	elseif counts[k] then
		print(string.format("  %-9s %s  (%d/%d runs)", k, hm(math.floor(avg[k])), counts[k], SEEDS))
	else
		print(string.format("  %-9s not reached", k))
	end
end
print(string.format("  last run: rebirths=%d zone=%d tool=%d power=%d cargo=%d capsules=%d crystals=%d temper=%d starPower=%d trait=x%.2f", lastSt.rebirths, lastSt.zone, lastSt.tool, lastSt.up.Power, lastSt.up.Cargo, lastSt.opened, math.floor(lastSt.crystals), lastSt.up.Temper, lastSt.up.StarPower, lastSt.trait))
