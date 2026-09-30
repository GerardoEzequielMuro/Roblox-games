-- Ki Warriors pacing simulator (pure Luau, reuses the real Config / Formulas / Quests /
-- Collection / BattlePass modules). No Roblox APIs. Used by sim/pacing_sim.luau (prints the
-- milestone table) and tests/pacing_check.luau (fails when milestones drift).
--
-- The simulated player is a FREE (no passes) player:
--   * turns Auto-Train on after 15 s, punches ~3 times a second (melee cooldown is 0.3 s,
--     every punch is a training rep), trains strength/ki/defense evenly (the 1.0-weight stats)
--   * follows the story tracker (the first steps are the tutorial)
--   * trains in the best training zone it can stand in; hunts enemies when the next purchase
--     (planet, story item, cheap gear) is short of Sparks
--   * buys: next planet when power + Sparks allow, gear when it costs <= 10 min of hunting,
--     techniques, gem upgrades by (benefit / cost)
--   * ascends when it can and no new planet is close; claims gifts, daily reward, daily
--     quests, codes, free aura spins, relic wishes, world boss, battle pass tiers
-- Everything stochastic (aura spins) uses a seeded Park-Miller generator.
local Config = require("../src/shared/Config")
local F = require("../src/shared/Formulas")
local BP = require("../src/shared/BattlePass")
local Quests = require("../src/shared/Quests")
local Collection = require("../src/shared/Collection")

local Core = {}

Core.policy = {
	manualPerSec = 3.0, -- punches/s while active (cooldown 0.3 s => hard max 3.3)
	autoOnAt = 15, -- seconds until the player flips Auto-Train on
	smallPerMin = 8, -- hunting: kills per minute (same assumption as Formulas.sparksPerMinute)
	midPerMin = 4,
	bossEvery = 240, -- hunting: one boss kill per this many seconds of hunting
	bossOverhead = 15, -- seconds of walking/telegraphs per boss kill (story boss step)
	hitsPerSec = 3.0, -- melee hits/s against a boss
	gearPaybackMinutes = 10, -- hunts for gear only if the hunting time <= 10 min x the speed-up it gives
	ascendWaitMax = 1200, -- ascends when the next planet is further than this many seconds away
	codesAt = 240, -- seconds into the first session: redeems the four public codes (the sim does not count them for the early purchases)
	questMinSession = 20, -- minutes of a session needed to finish the daily quests
	wishEveryMin = 30, -- one relic wish per this many minutes of a session
	huntSwitchDelay = 10, -- seconds of walking to the camp before the first kill of each hunting trip
	tutorialSlow = 2, -- multiplier on the busy time of the tutorial steps
	worldBossEveryMin = 30, -- one world boss (lowest reward tier) per this many minutes
}

local BUSY_SECONDS = { charge = 4, blasts = 5, fly = 6, beam = 10, dash = 4, relic = 45, form = 3 }

local function rng(seed: number)
	local s = seed % 2147483646 + 1
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local function newState(seed: number)
	local st = {
		rand = rng(seed),
		t = 0, -- wall clock seconds since the first join
		play = 0, -- seconds actually played
		sessionT = 0, -- seconds into the current session
		stats = {},
		sparks = 0,
		gems = 0,
		gear = 1,
		planets = { [1] = true },
		up = {},
		rebirths = 0,
		bestPower = 0,
		forms = 0,
		techniques = {},
		story = 1,
		progress = 0,
		boostLeft = 0,
		spins = 1,
		auraMult = 1,
		auras = {},
		wishPower = 0,
		bossKills = {},
		kills = 0,
		autoOn = false,
		codes = false,
		giftsDone = {},
		bossClock = 0,
		dailyDay = -1,
		dailyStreak = 0,
		questDay = -1,
		spent = 0, -- purchases made (gear / gem upgrades / planets / techniques)
		upgrades = 0,
		events = {},
		seen = {},
		first = {},
		bp = {}, -- season id -> { xp, tier }
		bpLog = {},
		bpTier = {},
		sessionGems = 0,
	}
	for _, s in Config.Stats do
		st.stats[s] = Config.StartStat
	end
	for _, u in Config.Upgrades do
		st.up[u.id] = 0
	end
	return st
end

local function power(st): number
	return F.power(st.stats)
end

local function curPower(st): number
	return math.max(power(st), st.bestPower)
end

local function bestPlanet(st): number
	local b = 1
	for i in st.planets do
		b = math.max(b, i)
	end
	return b
end

-- Milestone log. kind: form | planet | zone | chapter | gear | technique | ascend | upgrade | story
local function mark(st, kind: string, label: string)
	if kind == "planet" or kind == "form" or kind == "gear" or kind == "zone" then
		local key = kind .. ":" .. label
		if st.seen[key] then
			kind = "re" .. kind
		end
		st.seen[key] = true
	end
	table.insert(st.events, { t = st.t, play = st.play, kind = kind, label = label })
	local key = kind .. ":" .. label
	if st.first[key] == nil then
		st.first[key] = { t = st.t, play = st.play }
	end
end

local function sparkMult(st): number
	return (1 + F.upgradeValue("sparkGain", st.up.sparkGain)) * 1.1 -- default race Terran: +10% Sparks
end

local function addSparks(st, n: number, scaled: boolean)
	if scaled then
		n *= sparkMult(st)
	end
	st.sparks += math.floor(n + 0.5)
end

local function bpXp(st, amount: number)
	local season = st.season
	if not season then
		return
	end
	local rec = st.bp[season.id]
	if not rec then
		rec = { xp = 0, tier = 0 }
		st.bp[season.id] = rec
	end
	local cap = Config.BattlePass.xpPerTier * Config.BattlePass.tiers
	rec.xp = math.min(cap, rec.xp + amount)
	local tier = BP.tier(rec.xp)
	while rec.tier < tier do
		rec.tier += 1
		st.bpTier[season.id] = st.bpTier[season.id] or {}
		st.bpTier[season.id][rec.tier] = { t = st.t, play = st.play }
		local r = BP.reward(season.id, "free", rec.tier)
		if r then
			if r.kind == "sparks" then
				addSparks(st, F.sparksPerMinute(bestPlanet(st)) * r.amount, false)
			elseif r.kind == "gems" then
				st.gems += r.amount
			elseif r.kind == "spins" then
				st.spins += r.amount
			elseif r.kind == "aura" then
				st.auras[r.id] = true
			end
		end
		if rec.tier == Config.BattlePass.tiers then
			st.bpLog[season.id] = st.bpDay
		end
	end
end

local function rollSpins(st)
	while st.spins > 0 do
		st.spins -= 1
		local id = F.rollAura(st.rand(), false)
		st.auras[id] = true
	end
	local best = 1
	for id in st.auras do
		best = math.max(best, Config.AuraById[id].mult)
	end
	-- exclusive auras earned by ascending (Config.Auras earn rules, free for everyone)
	local ctx = { passes = {}, bossKills = st.bossKills, rebirths = st.rebirths, pvpKills = 0, planet = bestPlanet(st), power = curPower(st) }
	for _, a in Config.Auras do
		if a.earn and Collection.earned(a.earn, ctx) then
			best = math.max(best, a.mult)
		end
	end
	st.auraMult = best
end

---------------------------------------------------------------------------
-- economy helpers
---------------------------------------------------------------------------
local function zoneFor(st): any?
	-- best training zone the player may stand in (any unlocked planet; teleporting is free)
	local best = nil
	local p = curPower(st)
	for index in st.planets do
		for _, z in Config.Planets[index].zones do
			if p >= z.reqPower and (best == nil or z.mult > best.mult) then
				best = z
			end
		end
	end
	return best
end

local function trainCtx(st, zoneMult: number)
	return {
		zoneMult = zoneMult,
		gearTier = st.gear,
		rebirths = st.rebirths,
		upgradeLevel = st.up.trainPower,
		auraMult = st.auraMult,
		wishPower = st.wishPower,
		passDouble = false,
		vip = false,
		boost = st.boostLeft > 0,
		eventMult = 1,
		socialBonus = 0,
		raceBonus = 0,
	}
end

local function huntRates(planet: number)
	local pl = Config.Planets[planet]
	local small, mid = Config.Npcs[pl.camps[1].npc], Config.Npcs[pl.camps[2].npc]
	return small, mid, Config.Npcs[pl.boss.npc]
end

-- Sparks per second from hunting camps on a planet (before the Spark multiplier).
local function huntIncome(planet: number): number
	local small, mid = huntRates(planet)
	local P = Core.policy
	return (small.sparks * P.smallPerMin + mid.sparks * P.midPerMin) / 60
end

local function bossIncome(planet: number): number
	local _, _, boss = huntRates(planet)
	return boss.sparks / Core.policy.bossEvery
end

local function sparksPerSecond(st, planet: number): number
	return (huntIncome(planet) + bossIncome(planet)) * sparkMult(st)
end

local function bossKillTime(st, planet: number): number
	local _, _, boss = huntRates(planet)
	local form = math.max(st.forms, 0)
	local dmg = (Config.Combat.meleeBase + st.stats.strength * Config.Combat.meleePerStrength) * F.formMult(form)
	local dps = Core.policy.hitsPerSec * dmg * 1.35
	return math.max(15, boss.hp / dps) + Core.policy.bossOverhead
end

local function pickUpgrade(st)
	local best, bestScore = nil, 0
	local reps = F.autoRate(st.up.autoSpeed, false) + Core.policy.manualPerSec
	for _, u in Config.Upgrades do
		local lvl = st.up[u.id]
		if lvl < u.max then
			local benefit = 0
			if u.id == "trainPower" then
				benefit = u.perLevel / (1 + u.perLevel * lvl)
			elseif u.id == "sparkGain" then
				benefit = 0.25 * u.perLevel / (1 + u.perLevel * lvl)
			elseif u.id == "autoSpeed" then
				benefit = u.perLevel / reps
			end
			if benefit > 0 then
				local cost = F.upgradeCost(u.id, lvl)
				local score = benefit / cost
				if score > bestScore then
					best, bestScore = u, score
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- decisions (run once per tick)
---------------------------------------------------------------------------
local function refreshForms(st)
	local best = F.bestForm(curPower(st), st.rebirths, nil)
	while st.forms < best do
		st.forms += 1
		mark(st, "form", Config.Forms[st.forms].id)
	end
end

local function nextPlanetIndex(st): number?
	local nxt = bestPlanet(st) + 1
	if Config.Planets[nxt] then
		return nxt
	end
	return nil
end

local function tryPurchases(st)
	-- planet: the highest one power allows and Sparks cover
	local p = curPower(st)
	for index = #Config.Planets, bestPlanet(st) + 1, -1 do
		local pl = Config.Planets[index]
		if not st.planets[index] and p >= pl.reqPower and st.sparks >= pl.cost then
			st.sparks -= pl.cost
			st.planets[index] = true
			st.spent += 1
			mark(st, "planet", pl.id)
			break
		end
	end
	-- gear: only when cheap compared with hunting income (keeps Sparks for planets)
	local nextPl = nextPlanetIndex(st)
	local reserve = 0
	if nextPl and p >= 0.3 * Config.Planets[nextPl].reqPower then
		reserve = Config.Planets[nextPl].cost
	end
	while true do
		local g = Config.Gear[st.gear + 1]
		if not g or st.sparks - g.cost < reserve or st.sparks < g.cost then
			break
		end
		st.sparks -= g.cost
		st.gear += 1
		st.spent += 1
		mark(st, "gear", "tier" .. st.gear)
	end
	-- techniques (non-dark): when power allows and Sparks cover (after planet / gear)
	for _, t in Config.Techniques do
		if not st.techniques[t.id] and not t.special and p >= t.reqPower and st.sparks - t.cost >= reserve then
			local g = Config.Gear[st.gear + 1]
			if not g or st.sparks - t.cost >= g.cost * 0 then
				st.sparks -= t.cost
				st.techniques[t.id] = true
				st.spent += 1
				mark(st, "technique", t.id)
			end
		end
	end
	-- gem upgrades
	while true do
		local u = pickUpgrade(st)
		if not u then
			break
		end
		local cost = F.upgradeCost(u.id, st.up[u.id])
		if st.gems < cost then
			break
		end
		st.gems -= cost
		st.up[u.id] += 1
		st.upgrades += 1
		st.spent += 1
		mark(st, "upgrade", u.id .. st.up[u.id])
	end
end

local function trySpecialRebirth(st)
	local need = F.rebirthRequirement(st.rebirths)
	local p = power(st)
	if p < need then
		return
	end
	-- The in-game "next goal" tracker (Shared/Goals) points at the ascension as soon as it is the
	-- closest goal. The player follows it unless the next planet is about to open anyway
	-- (less than ascendWaitMax seconds away at the current growth) or it is the story step.
	local step = Config.Story[st.story]
	local forced = step ~= nil and step.kind == "rebirth"
	local nxt = nextPlanetIndex(st)
	local wait = math.huge
	if nxt then
		wait = math.max(0, Config.Planets[nxt].reqPower - p) / math.max(st.lastRate or 1, 1e-9)
	end
	if not forced and wait < Core.policy.ascendWaitMax then
		return
	end
	st.preAscendPower = p
	st.rebirths += 1
	for _, s in Config.Stats do
		st.stats[s] = Config.StartStat
	end
	st.sparks = 0
	st.gear = 1
	st.planets = { [1] = true }
	st.bestPower = 0
	st.forms = 0
	st.gems += Config.Rebirth.gems
	st.ascendedAt = st.play
	st.regrowing = true
	mark(st, "ascend", tostring(st.rebirths))
	rollSpins(st)
end

---------------------------------------------------------------------------
-- story
---------------------------------------------------------------------------
local function storyDone(st)
	local step = Config.Story[st.story]
	if step.sparks and step.sparks > 0 then
		addSparks(st, step.sparks, false)
	end
	if step.gems and step.gems > 0 then
		st.gems += step.gems
	end
	mark(st, "story", tostring(st.story))
	if step.kind == "boss" then
		mark(st, "chapter", step.npc)
	end
	st.story += 1
	st.progress = 0
end

local function storyStatic(st)
	-- "reach a value" steps
	while true do
		local step = Config.Story[st.story]
		if not step then
			return
		end
		local value = nil
		if step.kind == "power" then
			value = curPower(st)
		elseif step.kind == "gear" then
			value = st.gear
		elseif step.kind == "technique" then
			local n = 0
			for _ in st.techniques do
				n += 1
			end
			value = n
		elseif step.kind == "travel" then
			value = if st.planets[step.planet] then 1 else 0
		elseif step.kind == "rebirth" then
			value = st.rebirths
		end
		if value ~= nil and value >= step.target then
			storyDone(st)
		else
			return
		end
	end
end

-- What is the player doing right now? Returns mode, extra.
--   busy  = tutorial-like action (no punching, no Sparks)   hunt = fighting enemies
--   train = standing in a training zone
local function plan(st): (string, any?)
	local step = Config.Story[st.story]
	if step then
		local k = step.kind
		if k == "defeat" or k == "boss" then
			return "hunt", Config.Npcs[step.npc].planet
		elseif BUSY_SECONDS[k] then
			if k == "form" and st.forms < 1 then
				-- wait for the power first
			else
				return "busy", nil
			end
		elseif k == "zone" then
			local z = Config.ZoneById[step.zone]
			if st.planets[z.planet] and curPower(st) >= z.reqPower then
				return "train", z
			end
		elseif k == "technique" then
			local cheapest = nil
			for _, t in Config.Techniques do
				if not t.special and (cheapest == nil or t.cost < cheapest.cost) then
					cheapest = t
				end
			end
			if cheapest and curPower(st) >= cheapest.reqPower and st.sparks < cheapest.cost then
				return "hunt", bestPlanet(st)
			end
		elseif k == "gear" then
			local g = Config.Gear[st.gear + 1]
			if g and st.sparks < g.cost then
				return "hunt", bestPlanet(st)
			end
		end
	end
	local planet = bestPlanet(st)
	-- next planet: power ready but Sparks short => hunt
	local nxt = nextPlanetIndex(st)
	if nxt and curPower(st) >= Config.Planets[nxt].reqPower and st.sparks < Config.Planets[nxt].cost then
		return "hunt", planet
	end
	-- cheap gear
	local g = Config.Gear[st.gear + 1]
	if g and st.sparks < g.cost then
		local cur = Config.Gear[st.gear]
		local gain = g.mult / cur.mult - 1 -- extra training speed the gear would give
		local huntMinutes = (g.cost - st.sparks) / (sparksPerSecond(st, planet) * 60)
		if huntMinutes <= Core.policy.gearPaybackMinutes * gain then
			return "hunt", planet
		end
	end
	return "train", zoneFor(st)
end

---------------------------------------------------------------------------
-- one tick
---------------------------------------------------------------------------
local function tick(st, dt: number)
	local P = Core.policy
	st.t += dt
	st.play += dt
	st.sessionT += dt
	if not st.autoOn and st.play >= P.autoOnAt then
		st.autoOn = true
	end
	local mode, extra = plan(st)
	local zone = if mode == "train" then extra else nil
	-- reps
	local auto = if st.autoOn then F.autoRate(st.up.autoSpeed, false) else 0
	local manual = if mode == "busy" then 0 else P.manualPerSec
	local reps = (auto + manual) * dt
	local gain = F.trainGain(trainCtx(st, if zone then zone.mult else 1))
	local before = power(st)
	-- evenly over strength / ki / defense
	local each = reps * gain / 3
	st.stats.strength += each
	st.stats.ki += each
	st.stats.defense += each
	local now = power(st)
	st.lastRate = (now - before) / dt
	if now > st.bestPower then
		st.bestPower = now
	end
	if st.regrowing and now >= (st.preAscendPower or 0) then
		st.regrowing = false
		st.regrowEst = st.play - st.ascendedAt
	end
	if st.first["gain"] == nil and reps > 0 then
		st.first["gain"] = { t = st.play, play = st.play }
	end
	-- story progress from reps
	local step = Config.Story[st.story]
	if step then
		if step.kind == "reps" then
			st.progress += reps
		elseif step.kind == "zone" and zone and zone.id == step.zone then
			st.progress += reps
		elseif BUSY_SECONDS[step.kind] and mode == "busy" then
			-- tutorial steps take twice as long (reading the prompt, finding the button)
			local slow = if st.story <= Config.TutorialSteps then P.tutorialSlow else 1
			st.progress += step.target * dt / (BUSY_SECONDS[step.kind] * slow)
		end
	end
	-- hunting (the first kill of each trip comes after the walk to the camp)
	st.huntRun = if mode == "hunt" then (st.huntRun or 0) + dt else 0
	if mode == "hunt" and st.huntRun > P.huntSwitchDelay then
		local planet = extra
		local small, mid, boss = huntRates(planet)
		addSparks(st, huntIncome(planet) * dt, true)
		st.kills += (P.smallPerMin + P.midPerMin) * dt / 60
		st.bossClock += dt
		if step then
			if step.kind == "defeat" then
				local rate = if step.npc == small.id then P.smallPerMin elseif step.npc == mid.id then P.midPerMin else 0
				st.progress += rate * dt / 60
			elseif step.kind == "boss" then
				st.progress += dt / bossKillTime(st, planet)
			end
		end
		-- free-roaming boss kills (income + gems + BP XP)
		if not (step and step.kind == "boss") and st.bossClock >= P.bossEvery then
			st.bossClock -= P.bossEvery
			addSparks(st, boss.sparks, true)
			st.gems += boss.gems or 0
			st.bossKills[boss.id] = (st.bossKills[boss.id] or 0) + 1
			bpXp(st, Config.BattlePass.xp.bossKill)
		end
	end
	if step and step.kind == "boss" and mode == "hunt" and st.progress >= step.target then
		local _, _, boss = huntRates(extra)
		st.bossKills[boss.id] = (st.bossKills[boss.id] or 0) + 1
		addSparks(st, boss.sparks, true)
		st.gems += boss.gems or 0
		bpXp(st, Config.BattlePass.xp.bossKill)
	end
	if step and step.kind ~= "power" and step.kind ~= "gear" and step.kind ~= "technique" and step.kind ~= "travel" and step.kind ~= "rebirth" and st.progress >= step.target then
		storyDone(st)
	end
	-- boost timer
	if st.boostLeft > 0 then
		st.boostLeft = math.max(0, st.boostLeft - dt)
	end
	-- decisions
	refreshForms(st)
	tryPurchases(st)
	storyStatic(st)
	tryPurchases(st)
	trySpecialRebirth(st)
	-- zone unlock log
	local z = zoneFor(st)
	if z and not st.first["zone:" .. z.id] then
		mark(st, "zone", z.id)
	end
	for index in st.planets do
		for _, zz in Config.Planets[index].zones do
			if curPower(st) >= zz.reqPower and not st.first["zone:" .. zz.id] then
				mark(st, "zone", zz.id)
			end
		end
	end
	-- time-based rewards of the session
	local minutes = st.sessionT / 60
	for i, gift in Config.Gifts do
		if not st.giftsDone[i] and minutes >= gift.minutes then
			st.giftsDone[i] = true
			local r = gift.reward
			if r.kind == "sparks" then
				addSparks(st, F.sparksPerMinute(bestPlanet(st)) * r.amount, false)
			elseif r.kind == "gems" then
				st.gems += r.amount
			elseif r.kind == "boost" then
				st.boostLeft += r.amount * 60
			elseif r.kind == "spins" then
				st.spins += r.amount
			end
		end
	end
	if not st.codes and st.play >= P.codesAt then
		st.codes = true
		for _, r in Config.Codes do
			if r.kind == "gems" then
				st.gems += r.amount
			elseif r.kind == "boost" then
				st.boostLeft += r.amount * 60
			elseif r.kind == "spins" then
				st.spins += r.amount
			end
		end
	end
	st.minuteAcc = (st.minuteAcc or 0) + dt
	while st.minuteAcc >= 300 do
		st.minuteAcc -= 300
		bpXp(st, Config.BattlePass.xp.minutes)
	end
	-- daily reward (once a UTC day, claimed 30 s into the session)
	if st.dailyPending and st.sessionT >= 30 then
		st.dailyPending = false
		local streak = if st.dailyDay == st.day - 1 then st.dailyStreak else 0
		st.dailyDay = st.day
		local r = Config.DailyRewards[(streak % #Config.DailyRewards) + 1]
		st.dailyStreak = streak + 1
		if r.kind == "sparks" then
			addSparks(st, F.sparksPerMinute(bestPlanet(st)) * r.amount, false)
		elseif r.kind == "gems" then
			st.gems += r.amount
		elseif r.kind == "boost" then
			st.boostLeft += r.amount * 60
		elseif r.kind == "spins" then
			st.spins += r.amount
		end
		st.spins += Config.AuraSpin.freePerDay
	end
	-- quests (daily)
	if st.questDay ~= st.day and st.sessionT >= P.questMinSession * 60 then
		st.questDay = st.day
		local list = Quests.forDay(st.day, bestPlanet(st))
		local done = 0
		for _, q in list do
			if q.kind ~= "arena" then -- PvP arena wins are not assumed
				done += 1
				st.gems += q.gems
				bpXp(st, Config.BattlePass.xp.questClaim)
			end
		end
		if done == #list then
			st.gems += Config.QuestBonusGems
			bpXp(st, Config.BattlePass.xp.questBonus)
		end
	end
	-- relic wish and world boss (per N minutes of session)
	local wishes = math.floor(minutes / P.wishEveryMin)
	while (st.wishesDone or 0) < wishes do
		st.wishesDone = (st.wishesDone or 0) + 1
		if st.wishPower < Config.WishPowerMax then
			st.wishPower += 1
		else
			st.gems += 60
		end
		for _ = 1, Config.Relics.count do
			bpXp(st, Config.BattlePass.xp.relic)
		end
	end
	local wb = math.floor(minutes / P.worldBossEveryMin)
	while (st.wbDone or 0) < wb do
		st.wbDone = (st.wbDone or 0) + 1
		local tier = Config.WorldBoss.tiers[#Config.WorldBoss.tiers]
		st.gems += tier.gems
		addSparks(st, F.sparksPerMinute(bestPlanet(st)) * tier.sparkMinutes, false)
		bpXp(st, Config.BattlePass.xp.worldBoss)
	end
	if st.spins > 0 then
		rollSpins(st)
	end
end

---------------------------------------------------------------------------
-- sessions
---------------------------------------------------------------------------
local function startSession(st, day: number)
	st.sessionT = 0
	st.giftsDone = {}
	st.wishesDone = 0
	st.wbDone = 0
	st.day = day
	st.bpDay = day
	local season = BP.active(Config.BattlePass.seasons[1].startsAt + day * 86400 + 12 * 3600)
	st.season = season
	st.dailyPending = st.dailyDay ~= day
	rollSpins(st)
end

-- Offline training while away (Offline.compute): selected stat only, no zone, 25% of auto.
local function offline(st, seconds: number)
	seconds = math.min(seconds, Config.Offline.capSeconds)
	if seconds < Config.Offline.minSeconds then
		return
	end
	local gain = F.trainGain(trainCtx(st, 1)) * F.autoRate(st.up.autoSpeed, false) * Config.Offline.rate * seconds
	st.stats.strength += gain
	local p = power(st)
	if p > st.bestPower then
		st.bestPower = p
	end
end

-- schedule: function(day) -> list of { startHour, minutes }. Runs `days` calendar days.
function Core.run(seed: number, schedule: (number) -> { { number } }, days: number, stop: ((any) -> boolean)?)
	local st = newState(seed)
	for day = 0, days - 1 do
		for _, s in schedule(day) do
			local start = day * 86400 + s[1] * 3600
			if start > st.t then
				if st.t > 0 then
					offline(st, start - st.t)
					refreshForms(st)
				end
				st.t = start
			end
			startSession(st, day)
			local dur = s[2] * 60
			local left = dur
			while left > 0 do
				local dt = if st.play < 7200 then 1 else 5
				dt = math.min(dt, left)
				tick(st, dt)
				left -= dt
				if stop and stop(st) then
					return st
				end
			end
		end
	end
	return st
end

Core.schedules = {
	-- first session 100 minutes, then two 35-minute sessions a day
	active = function(day: number)
		if day == 0 then
			return { { 0, 100 } }
		end
		return { { 8, 35 }, { 20, 35 } }
	end,
	-- first session 60 minutes, then one 25-minute session a day
	casual = function(day: number)
		if day == 0 then
			return { { 0, 60 } }
		end
		return { { 20, 25 } }
	end,
}

---------------------------------------------------------------------------
-- reports
---------------------------------------------------------------------------
local PURCHASE = { gear = true, upgrade = true, planet = true, technique = true }

-- Seconds of play at which the n-th purchase (gear, gem upgrade, planet, technique) happened.
function Core.purchaseTime(st, n: number): number?
	local count = 0
	for _, e in st.events do
		if PURCHASE[e.kind] then
			count += 1
			if count == n then
				return e.play
			end
		end
	end
	return nil
end

-- Largest gap (seconds) between two "something new" events before `untilPlay`. `major` only
-- counts forms, planets, training zones, story chapters, techniques and ascensions.
function Core.maxGap(st, untilPlay: number, major: boolean): (number, number)
	local MAJOR = { form = true, planet = true, zone = true, chapter = true, technique = true, ascend = true, reform = true, replanet = true }
	local MINOR = { gear = true, regear = true }
	local last, best, at = 0, 0, 0
	for _, e in st.events do
		if e.play > untilPlay then
			break
		end
		if MAJOR[e.kind] or (not major and MINOR[e.kind]) then
			if e.play - last > best then
				best, at = e.play - last, last
			end
			last = e.play
		end
	end
	if untilPlay - last > best then
		best, at = untilPlay - last, last
	end
	return best, at
end

function Core.firstPlay(st, key: string): number?
	local f = st.first[key]
	return f and f.play or nil
end

function Core.firstDay(st, key: string): number?
	local f = st.first[key]
	return f and f.t / 86400 or nil
end

function Core.median(list: { number }): number?
	if #list == 0 then
		return nil
	end
	table.sort(list)
	return list[(#list + 1) // 2]
end

-- Runs the same schedule over several seeds; returns the runs.
function Core.runSeeds(seeds: number, schedule: (number) -> { { number } }, days: number)
	local out = {}
	for seed = 1, seeds do
		table.insert(out, Core.run(seed, schedule, days))
	end
	return out
end

-- Median over runs of a per-run number (nil when a run never got there).
function Core.medianOf(runs, fn: (any) -> number?): number?
	local vals = {}
	for _, st in runs do
		local v = fn(st)
		if v == nil then
			return nil
		end
		table.insert(vals, v)
	end
	return Core.median(vals)
end

return Core
