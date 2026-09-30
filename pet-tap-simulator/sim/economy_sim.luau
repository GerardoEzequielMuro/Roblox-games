--!nocheck
-- Economy simulation for Tap Pets Simulator. Pure Luau (no Roblox APIs).
-- Run from the project root:
--   ../huerta-tycoon/tools/luau.exe sim/economy_sim.luau
-- Optional args: -a <seeds> <hours>   e.g. -a 20 6
--
-- Models an "average" free-to-play player: taps 6 times/second, never buys passes,
-- claims the in-session gifts, hatches only when an egg pays for itself quickly,
-- equips the best pets, crafts Golden/Rainbow automatically, buys gates as soon as
-- affordable, rebirths when it's affordable and no gate is within reach, spends gems
-- on the cheapest useful upgrade.

local F = require("../src/shared/Formulas")
local Config = F.Config

local TAPS_PER_SEC = 6
local PAYBACK_LIMIT = 150 -- seconds: hatch only if expected income gain repays the egg this fast
local REBIRTH_GATE_WAIT = 300 -- don't rebirth if the next gate is affordable within this many seconds

local args = { ... }
local SEEDS = tonumber(args[1]) or 25
local HOURS = tonumber(args[2]) or 6

local function simulate(seed: number, verbose: boolean, stopZone: number?, stopAtRebirth: boolean?)
	math.randomseed(seed)
	local s = {
		t = 0,
		taps = 0,
		gems = 0,
		rebirths = 0,
		maxZone = 1,
		upgrades = { TapPower = 0, Luck = 0, PetSlots = 0, WalkSpeed = 0 },
		inv = {} :: { [string]: number }, -- "id|tier" -> count
		hatches = 0,
		nextHatch = 0,
		giftIdx = 1,
		invVersion = 0,
	}
	s.inv[Config.StartingPet .. "|0"] = 1
	local events = {}
	local function log(what: string)
		table.insert(events, { t = s.t, what = what })
	end

	local passes = {}
	local cache: any = nil
	local function equipped(): ({ number }, number, number)
		if cache and cache.zone == s.maxZone and cache.slots == s.upgrades.PetSlots and cache.version == s.invVersion then
			return cache.powers, cache.sum, cache.weakest
		end
		local powers = {}
		for key, n in s.inv do
			local id, tier = key:match("^(.-)|(%d)$")
			local p = F.petPower(id, tonumber(tier), s.maxZone)
			for _ = 1, n do
				table.insert(powers, p)
			end
		end
		table.sort(powers, function(a, b)
			return a > b
		end)
		local slots = F.maxEquip(s.upgrades.PetSlots, passes)
		local sum, weakest = 0, 0
		for i = 1, slots do
			local p = powers[i]
			if p then
				sum += p
				weakest = p
			else
				weakest = 0
			end
		end
		cache = { zone = s.maxZone, slots = s.upgrades.PetSlots, version = s.invVersion, powers = powers, sum = sum, weakest = weakest }
		return powers, sum, weakest
	end

	local function tapValue(): number
		local _, sum = equipped()
		return F.tapValue({ petPower = sum, rebirths = s.rebirths, tapPowerLevel = s.upgrades.TapPower, passes = passes, friends = 0, indexZonesDone = 0 })
	end

	local function craft()
		local changed = true
		while changed do
			changed = false
			for key, n in s.inv do
				local id, tier = key:match("^(.-)|(%d)$")
				tier = tonumber(tier)
				if n >= Config.CraftCost and tier < 2 then
					s.inv[key] = n - Config.CraftCost
					local nk = id .. "|" .. (tier + 1)
					s.inv[nk] = (s.inv[nk] or 0) + 1
					changed = true
				end
			end
		end
	end

	local function reward(kind: string, amount: number)
		if kind == "taps" then
			s.taps += F.tapsForMinutes(amount, tapValue())
		elseif kind == "gems" then
			s.gems += amount
		end
	end

	local income = tapValue() * TAPS_PER_SEC
	local limit = HOURS * 3600
	local firstRebirth = nil
	local zoneTimes = { [1] = 0 }
	while s.t < limit do
		s.t += 1
		s.taps += income

		-- gifts during the first hour of the session
		local g = Config.Gifts[s.giftIdx]
		if g and s.t >= g.minutes * 60 then
			reward(g.reward.kind, g.reward.amount)
			s.giftIdx += 1
		end

		-- gates
		local nextZone = s.maxZone + 1
		local gateCost = F.zoneCost(nextZone)
		if Config.Zones[nextZone] and s.taps >= gateCost then
			s.taps -= gateCost
			s.maxZone = nextZone
			zoneTimes[nextZone] = s.t
			log(string.format("unlock zone %d (%s)  tap=%s", nextZone, Config.Zones[nextZone].name, tostring(math.floor(tapValue()))))
		end

		-- rebirth
		local rc = F.rebirthCost(s.rebirths)
		local gateEta = if Config.Zones[s.maxZone + 1] then (F.zoneCost(s.maxZone + 1) - s.taps) / math.max(income, 1) else math.huge
		if s.taps >= rc and gateEta > REBIRTH_GATE_WAIT then
			s.taps = 0
			s.gems += F.rebirthGems(s.rebirths)
			s.rebirths += 1
			if not firstRebirth then
				firstRebirth = s.t
			end
			log(string.format("REBIRTH #%d  (cost %s)", s.rebirths, tostring(rc)))
		end

		-- hatch the egg with the biggest expected gain among those that pay back quickly
		-- (hatching is limited by the cooldown, so gain per hatch is what matters)
		if s.t >= s.nextHatch then
			local _, sum, weakest = equipped()
			local mult = tapValue() / (Config.BaseTap + sum)
			local bestEgg, bestGain = nil, 0
			for _, egg in Config.Eggs do
				if not egg.exclusive and egg.zone <= s.maxZone and s.taps >= egg.price then
					local gain = 0
					for _, o in F.odds(egg.id, F.luck(s.upgrades.Luck, passes, false)) do
						local p = F.petPower(o.pet, 0, s.maxZone)
						gain += math.max(0, p - weakest) * o.chance / 100
					end
					-- crafting value: duplicates of weak pets still feed Golden crafts
					gain += 0.05 * F.expectedPower(egg.id, 1, s.maxZone)
					local payback = egg.price / math.max(gain * mult * TAPS_PER_SEC, 1e-9)
					if payback < PAYBACK_LIMIT and gain > bestGain then
						bestEgg, bestGain = egg, gain
					end
				end
			end
			if bestEgg then
				s.taps -= bestEgg.price
				local pet = F.roll(bestEgg.id, F.luck(s.upgrades.Luck, passes, false), math.random())
				local tier = if math.random() < Config.BaseGoldenHatchChance then 1 else 0
				local key = pet .. "|" .. tier
				s.inv[key] = (s.inv[key] or 0) + 1
				s.hatches += 1
				s.nextHatch = s.t + Config.HatchCooldown
				s.invVersion += 1
				craft()
			end
		end

		-- gems -> cheapest useful upgrade
		local bestU, bestC = nil, math.huge
		for _, id in { "TapPower", "PetSlots", "Luck" } do
			local u = Config.UpgradeById[id]
			if s.upgrades[id] < u.maxLevel then
				local c = F.upgradeCost(id, s.upgrades[id])
				if c < bestC then
					bestU, bestC = id, c
				end
			end
		end
		if bestU and s.gems >= bestC then
			s.gems -= bestC
			s.upgrades[bestU] += 1
		end

		if s.t % 5 == 0 then
			income = tapValue() * TAPS_PER_SEC
		end
		if (stopZone and s.maxZone >= stopZone) or (stopAtRebirth and firstRebirth) then
			break
		end
	end
	return { zoneTimes = zoneTimes, firstRebirth = firstRebirth, rebirths = s.rebirths, events = events, hatches = s.hatches, finalTap = tapValue(), upgrades = s.upgrades }
end

local function fmt(sec: number?): string
	if not sec then
		return "  never "
	end
	return string.format("%2dh %02dm %02ds", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function avgTime(seeds: number, fn: (number) -> number?): number
	local sum = 0
	for i = 1, seeds do
		sum += fn(i * 7919) or HOURS * 3600 * 2
	end
	return sum / seeds
end

-- Tuner: binary-searches each gate cost (with that zone's egg prices scaled along) and the
-- first rebirth cost so the average player hits the target times. Prints values for Config.
local function tune()
	local targets = { [2] = 5 * 60, [3] = 35 * 60, [4] = 105 * 60, [5] = 210 * 60 }
	local REBIRTH_TARGET = 60 * 60
	local TSEEDS = 6
	local eggRatios = {}
	for _, egg in Config.Eggs do
		if egg.zone >= 2 then
			eggRatios[egg.id] = egg.price / Config.Zones[egg.zone].cost
		end
	end
	local function setGate(z: number, cost: number)
		cost = tonumber(string.format("%.2g", cost)) :: number
		Config.Zones[z].cost = cost
		for _, egg in Config.Eggs do
			if egg.zone == z and eggRatios[egg.id] then
				egg.price = tonumber(string.format("%.2g", cost * eggRatios[egg.id])) :: number
			end
		end
	end
	local function searchGate(z: number)
		local lo, hi = Config.Zones[z].cost / 60, Config.Zones[z].cost * 60
		for _ = 1, 14 do
			local mid = math.sqrt(lo * hi)
			setGate(z, mid)
			local t = avgTime(TSEEDS, function(seed)
				return simulate(seed, false, z).zoneTimes[z]
			end)
			if t < targets[z] then
				lo = mid
			else
				hi = mid
			end
		end
		setGate(z, math.sqrt(lo * hi))
	end
	local savedRebirth = Config.RebirthBaseCost
	Config.RebirthBaseCost = 1e300 -- no rebirths while tuning the early gates
	searchGate(2)
	searchGate(3)
	Config.RebirthBaseCost = savedRebirth
	local lo, hi = savedRebirth / 50, savedRebirth * 50
	for _ = 1, 14 do
		local mid = math.sqrt(lo * hi)
		Config.RebirthBaseCost = tonumber(string.format("%.2g", mid)) :: number
		local t = avgTime(TSEEDS, function(seed)
			return simulate(seed, false, nil, true).firstRebirth
		end)
		if t < REBIRTH_TARGET then
			lo = mid
		else
			hi = mid
		end
	end
	Config.RebirthBaseCost = tonumber(string.format("%.2g", math.sqrt(lo * hi))) :: number
	searchGate(4)
	searchGate(5)
	print("-- tuned values (paste into Config.luau)")
	for _, z in Config.Zones do
		print(string.format("zone %d %-12s cost = %.0f", z.index, z.id, z.cost))
	end
	for _, egg in Config.Eggs do
		print(string.format("egg %-9s price = %.0f", egg.id, egg.price))
	end
	print(string.format("RebirthBaseCost = %.0f", Config.RebirthBaseCost))
end

if args[1] == "tune" then
	SEEDS = 12
	HOURS = 6
	tune()
end

-- One verbose run
local r = simulate(1, true)
print(string.format("=== Tap Pets Simulator economy sim: %d taps/s, %d h, seed 1 ===", TAPS_PER_SEC, HOURS))
for _, e in r.events do
	print(fmt(e.t) .. "  " .. e.what)
end
print(string.format("hatches=%d  final tap value=%.0f  upgrades: TapPower=%d PetSlots=%d Luck=%d", r.hatches, r.finalTap, r.upgrades.TapPower, r.upgrades.PetSlots, r.upgrades.Luck))

-- Averages over many seeds
local sums, counts = {}, {}
local rbSum, rbN = 0, 0
for seed = 1, SEEDS do
	local x = simulate(seed * 7919, false)
	for z, t in x.zoneTimes do
		sums[z] = (sums[z] or 0) + t
		counts[z] = (counts[z] or 0) + 1
	end
	if x.firstRebirth then
		rbSum += x.firstRebirth
		rbN += 1
	end
end
print(string.format("\n=== Averages over %d seeds ===", SEEDS))
for z = 2, #Config.Zones do
	local avg = if counts[z] then sums[z] / counts[z] else nil
	print(string.format("Zone %d %-13s  avg unlock %s   (reached in %d/%d runs)", z, Config.Zones[z].name, fmt(avg and math.floor(avg)), counts[z] or 0, SEEDS))
end
print(string.format("First rebirth           avg %s   (reached in %d/%d runs)", fmt(rbN > 0 and math.floor(rbSum / rbN) or nil), rbN, SEEDS))
