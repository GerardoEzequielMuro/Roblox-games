--!nocheck
-- Pacing simulator core for Tap Pets Simulator (pure Luau, no Roblox APIs).
-- Reuses the REAL shared modules (Config, Formulas). Used by sim/pacing_sim.luau (prints the
-- milestone table) and tests/pacing_targets.luau (fails if milestones leave the target windows).
--
-- Player model: a FREE player (no passes) who is actively playing during their sessions:
--   * taps TAPS_PER_SEC times per second (the server cap is Config.MaxTapsPerSecond = 12);
--   * hatches the egg with the best expected gain whenever it pays back fast, every HATCH_EVERY s
--     (manual hatch cooldown is Config.HatchCooldown = 2.4 s; humans are slower than that);
--   * equips the best pets, crafts Golden/Rainbow as soon as it has 5 of a kind;
--   * buys the next zone gate as soon as it can, rebirths when affordable and no gate is near;
--   * spends gems on the cheapest economic upgrade (TapPower / Luck / PetSlots), WalkSpeed with leftovers;
--   * claims every in-session gift, the daily reward, the daily quests (+bonus Magic Egg) and the
--     offline earnings when it comes back. Free Auto Tap / Auto Hatch only matter while idle, so an
--     active player never needs them (they are what the player gets while away or AFK).
-- Not modelled: trait dice, index-page rewards/bonus, codes, friends boost, ads, events, walking time.

local F = require("../src/shared/Formulas")
local Config = F.Config

local Core = {}

Core.TAPS_PER_SEC = 6
Core.HATCH_EVERY = 3 -- seconds between hatches of an active human (>= Config.HatchCooldown)
Core.PAYBACK_LIMIT = 150 -- hatch only if the expected income gain repays the egg this fast
Core.REBIRTH_GATE_WAIT = 300 -- don't rebirth if the next gate is affordable within this many seconds
Core.QUEST_EVERY = 12 * 60 -- a daily quest gets done this often while playing
Core.DAILY_DELAY = 30 -- the first-session player notices the Rewards badge after ~30 s
Core.TIER_WINDOW = 3600 -- "first hour" for the dead-stretch check

export type Session = { start: number, duration: number }

-- One long first session (minutes), the usual way to measure the first-hour curve.
function Core.firstSession(minutes: number): { Session }
	return { { start = 0, duration = minutes * 60 } }
end

-- A week: day 1 = 90 min + 25 min in the evening; days 2-7 = 40 min + 25 min.
function Core.week(): { Session }
	local out = {}
	for d = 0, 6 do
		table.insert(out, { start = d * 86400 + 9 * 3600, duration = (if d == 0 then 90 else 40) * 60 })
		table.insert(out, { start = d * 86400 + 21 * 3600, duration = 25 * 60 })
	end
	return out
end

export type Result = {
	m: { [string]: number }, -- milestone key -> play time in seconds (first time)
	day: { [string]: number }, -- milestone key -> day index (0-based) when it happened
	tierEvents: { number }, -- play times of "a new tier became available" events (egg, zone gate, rebirth), sorted
	rewardEvents: { number }, -- tier events + gifts, daily, quests, first gem upgrade of each kind, sorted
	purchasesBy3: number, -- eggs + gem upgrades bought in the first 3 minutes
	upgradesBy3: number, -- gem upgrades bought in the first 3 minutes
	rebirths: number,
	finalTap: number,
	play: number,
	samples: { { min: number, income: number, zone: number, rebirths: number } }, -- every 5 play minutes
}

function Core.simulate(seed: number, sessions: { Session }): Result
	math.randomseed(seed)
	local s = {
		t = 0, -- wall clock
		play = 0, -- active play seconds
		taps = 0,
		gems = 0,
		rebirths = 0,
		maxZone = 1,
		upgrades = { TapPower = 0, Luck = 0, PetSlots = 0, WalkSpeed = 0 },
		inv = {} :: { [string]: number },
		invVersion = 0,
		dailyLast = -math.huge,
		streak = 0,
		questDay = -1,
		questsDone = 0,
	}
	s.inv[Config.StartingPet .. "|0"] = 1
	local passes = {}
	local m: { [string]: number } = {}
	local dayOf: { [string]: number } = {}
	local tierEvents: { number } = {}
	local rewardEvents: { number } = {}
	local purchasesBy3, upgradesBy3 = 0, 0
	local eggSeen: { [string]: boolean } = {}
	local samples = {}

	local function mark(key: string, major: boolean?)
		if m[key] == nil then
			m[key] = s.play
			dayOf[key] = math.floor(s.t / 86400)
			if major then
				table.insert(tierEvents, s.play)
			end
		end
	end

	local cache: any = nil
	local function equipped(): (number, number)
		if cache and cache.zone == s.maxZone and cache.slots == s.upgrades.PetSlots and cache.version == s.invVersion then
			return cache.sum, cache.weakest
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
		cache = { zone = s.maxZone, slots = s.upgrades.PetSlots, version = s.invVersion, sum = sum, weakest = weakest }
		return sum, weakest
	end

	local function tapValue(): number
		local sum = equipped()
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

	local function addPet(id: string, tier: number)
		local key = id .. "|" .. tier
		s.inv[key] = (s.inv[key] or 0) + 1
		s.invVersion += 1
		craft()
	end

	local function hatchExclusive(n: number)
		for _ = 1, n do
			local r = math.random() * 100
			local acc, pick = 0, "sparklecat"
			for _, e in F.EggById.magic.entries do
				acc += e.chance
				if r < acc then
					pick = e.pet
					break
				end
			end
			addPet(pick, 0)
		end
	end

	local luckBoostLeft = 0
	local function luck(): number
		return F.luck(s.upgrades.Luck, passes, luckBoostLeft > 0)
	end

	local function grant(kind: string, amount: number)
		table.insert(rewardEvents, s.play)
		if kind == "taps" then
			s.taps += F.tapsForMinutes(amount, tapValue())
		elseif kind == "gems" then
			s.gems += amount
		elseif kind == "luck" then
			luckBoostLeft += amount * 60
		elseif kind == "egg" then
			hatchExclusive(amount)
		end
	end

	local function spendGems()
		while true do
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
			if not (bestU and s.gems >= bestC) then
				-- leftovers: Walk Speed (cheap, never wasted)
				local ws = Config.UpgradeById.WalkSpeed
				local wc = F.upgradeCost("WalkSpeed", s.upgrades.WalkSpeed)
				if s.upgrades.WalkSpeed >= ws.maxLevel or s.gems < wc then
					return
				end
				bestU, bestC = "WalkSpeed", wc
			end
			s.gems -= bestC
			s.upgrades[bestU] += 1
			mark("upgrade1")
			if m["upgradeKind:" .. bestU] == nil then
				mark("upgradeKind:" .. bestU)
				table.insert(rewardEvents, s.play)
			end
			if s.play <= 180 then
				upgradesBy3 += 1
				purchasesBy3 += 1
			end
		end
	end

	local function tryHatch()
		local sum, weakest = equipped()
		local mult = tapValue() / (Config.BaseTap + sum)
		local lk = luck()
		local bestEgg, bestGain = nil, 0
		for _, egg in Config.Eggs do
			if not egg.exclusive and egg.zone <= s.maxZone and s.taps >= egg.price then
				local gain = 0
				for _, o in F.odds(egg.id, lk) do
					local p = F.petPower(o.pet, 0, s.maxZone)
					gain += math.max(0, p - weakest) * o.chance / 100
				end
				gain += 0.05 * F.expectedPower(egg.id, 1, s.maxZone) -- duplicates feed Golden crafts
				local payback = egg.price / math.max(gain * mult * Core.TAPS_PER_SEC, 1e-9)
				if payback < Core.PAYBACK_LIMIT and gain > bestGain then
					bestEgg, bestGain = egg, gain
				end
			end
		end
		if not bestEgg then
			return false
		end
		s.taps -= bestEgg.price
		local pet = F.roll(bestEgg.id, lk, math.random())
		addPet(pet, if math.random() < Config.BaseGoldenHatchChance then 1 else 0)
		mark("firstEgg")
		mark("hatch:" .. bestEgg.id)
		if s.play <= 180 then
			purchasesBy3 += 1
		end
		return true
	end

	local function checkTiers()
		-- a new egg is available (its zone is open and the player can pay for it)
		for _, egg in Config.Eggs do
			if not egg.exclusive and not eggSeen[egg.id] and egg.zone <= s.maxZone and s.taps >= egg.price then
				eggSeen[egg.id] = true
				mark("egg:" .. egg.id, true)
			end
		end
		local nz = Config.Zones[s.maxZone + 1]
		if nz and s.taps >= nz.cost then
			mark("zoneAff" .. (s.maxZone + 1), true)
		end
		if s.taps >= F.rebirthCost(s.rebirths) then
			mark("rebirthAff" .. (s.rebirths + 1), true)
		end
	end

	mark("firstGain") -- the first tap pays out immediately (Config.BaseTap x (1 + dog) per tap)
	m.firstGain = 1 / Core.TAPS_PER_SEC

	local lastEnd = nil
	for _, sess in sessions do
		-- away: offline earnings, Super Luck expires
		if lastEnd then
			local away = sess.start - lastEnd
			luckBoostLeft = 0
			if away >= Config.OfflineMinSeconds then
				s.taps += F.offlineEarnings(tapValue(), away, Config.OfflineCapHours * 3600)
			end
		end
		s.t = sess.start
		local sessionStart = s.t
		local giftIdx = 1
		local dailyPending = true
		local nextHatch = s.t
		local sessionEnd = sess.start + sess.duration
		while s.t < sessionEnd do
			s.t += 1
			s.play += 1
			luckBoostLeft = math.max(0, luckBoostLeft - 1)
			s.taps += tapValue() * Core.TAPS_PER_SEC

			local g = Config.Gifts[giftIdx]
			while g and s.t - sessionStart >= g.minutes * 60 do
				grant(g.reward.kind, g.reward.amount)
				giftIdx += 1
				g = Config.Gifts[giftIdx]
			end

			-- daily quests: one every ~12 active minutes of the day's first long session (3 per day,
			-- gems each, Magic Egg bonus for the third)
			local day = math.floor(s.t / 86400)
			if s.questDay ~= day then
				s.questDay, s.questsDone = day, 0
			end
			if s.questsDone < Config.QuestsPerDay and s.t - sessionStart >= Core.QUEST_EVERY * (s.questsDone + 1) then
				s.questsDone += 1
				grant("gems", Config.QuestPool[math.random(#Config.QuestPool)].gems)
				if s.questsDone == Config.QuestsPerDay then
					grant(Config.QuestBonus.kind, Config.QuestBonus.amount)
				end
			end

			if dailyPending and s.t - sessionStart >= Core.DAILY_DELAY then
				dailyPending = false
				if s.t - s.dailyLast >= Config.DailyCooldown then
					if s.t - s.dailyLast > Config.DailyStreakWindow then
						s.streak = 0
					end
					local r = Config.DailyRewards[(s.streak % #Config.DailyRewards) + 1]
					s.streak += 1
					s.dailyLast = s.t
					grant(r.kind, r.amount)
				end
			end

			if s.play % 300 == 0 then
				table.insert(samples, { min = s.play / 60, income = tapValue() * Core.TAPS_PER_SEC, zone = s.maxZone, rebirths = s.rebirths })
			end

			checkTiers()

			-- gate
			local nextZone = s.maxZone + 1
			if Config.Zones[nextZone] and s.taps >= F.zoneCost(nextZone) then
				s.taps -= F.zoneCost(nextZone)
				s.maxZone = nextZone
				mark("zone" .. nextZone)
			end

			-- rebirth
			local rc = F.rebirthCost(s.rebirths)
			local income = tapValue() * Core.TAPS_PER_SEC
			local gateEta = if Config.Zones[s.maxZone + 1] then (F.zoneCost(s.maxZone + 1) - s.taps) / math.max(income, 1) else math.huge
			if s.taps >= rc and gateEta > Core.REBIRTH_GATE_WAIT then
				s.taps = 0
				s.gems += F.rebirthGems(s.rebirths)
				s.rebirths += 1
				mark("rebirth" .. s.rebirths)
			end

			while s.t >= nextHatch do
				if not tryHatch() then
					nextHatch = s.t + 1
					break
				end
				nextHatch = math.max(nextHatch, s.t - 1) + Core.HATCH_EVERY
			end

			if s.gems > 0 then
				spendGems()
			end
		end
		lastEnd = sessionEnd
	end

	for _, t in tierEvents do
		table.insert(rewardEvents, t)
	end
	table.sort(tierEvents)
	table.sort(rewardEvents)
	return {
		m = m,
		day = dayOf,
		tierEvents = tierEvents,
		rewardEvents = rewardEvents,
		purchasesBy3 = purchasesBy3,
		upgradesBy3 = upgradesBy3,
		rebirths = s.rebirths,
		finalTap = tapValue(),
		play = s.play,
		samples = samples,
	}
end

-- Longest stretch (seconds) inside [0, window] with no "new tier" event. The clock starts at 0 and
-- the last interval runs to the first event at or after the window (or the end of play).
function Core.maxDeadGap(events: { number }, window: number): number
	local prev, worst = 0, 0
	for _, t in events do
		worst = math.max(worst, math.min(t, window) - prev)
		prev = t
		if t >= window then
			return worst
		end
	end
	return math.max(worst, window - prev)
end

function Core.median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	table.sort(xs)
	return xs[(#xs + 1) // 2]
end

-- Runs `seeds` simulations and returns the median play time of every milestone key, plus the
-- median of the scalar outputs. reached = how many seeds hit the key.
function Core.aggregate(seeds: number, sessions: { Session })
	local times: { [string]: { number } } = {}
	local days: { [string]: { number } } = {}
	local gaps, rgaps, p3, u3, rb = {}, {}, {}, {}, {}
	for i = 1, seeds do
		local r = Core.simulate(i * 7919, sessions)
		for k, t in r.m do
			times[k] = times[k] or {}
			table.insert(times[k], t)
			days[k] = days[k] or {}
			table.insert(days[k], r.day[k])
		end
		table.insert(gaps, Core.maxDeadGap(r.tierEvents, Core.TIER_WINDOW))
		table.insert(rgaps, Core.maxDeadGap(r.rewardEvents, Core.TIER_WINDOW))
		table.insert(p3, r.purchasesBy3)
		table.insert(u3, r.upgradesBy3)
		table.insert(rb, r.rebirths)
	end
	local med: { [string]: number } = {}
	local reached: { [string]: number } = {}
	local dayMed: { [string]: number } = {}
	for k, xs in times do
		reached[k] = #xs
		med[k] = Core.median(xs) :: number
		dayMed[k] = Core.median(days[k]) :: number
	end
	-- worst seed for the dead-gap (the test wants a bound, not a typical value)
	table.sort(gaps)
	table.sort(rgaps)
	return {
		med = med,
		reached = reached,
		dayMed = dayMed,
		seeds = seeds,
		gapMedian = gaps[(#gaps + 1) // 2],
		gapWorst = gaps[#gaps],
		rewardGapMedian = rgaps[(#rgaps + 1) // 2],
		rewardGapWorst = rgaps[#rgaps],
		purchasesBy3 = Core.median(p3) :: number,
		upgradesBy3 = Core.median(u3) :: number,
		rebirthsMedian = Core.median(rb) :: number,
	}
end

return Core
