--!strict
-- Pacing simulator core (pure Luau). Plays a FREE, ACTIVE player through the real game rules and records milestones.
-- Reuses the real shared modules: Config (seeds, upgrades, gifts, daily, rebirth), Formulas (costs), Gifts (cash gifts),
-- AutoFarm (Farmhand pace), Odds (mutation chances, lucky pack), Trophies (size rolls).
-- Run the table with: luau sim/pacing_sim.luau     Drift check: luau tests/pacing_test.luau
local Config = require("../src/shared/Config")
local Formulas = require("../src/shared/Formulas")
local Gifts = require("../src/shared/Gifts")
local AutoFarm = require("../src/shared/AutoFarm")
local Odds = require("../src/shared/Odds")
local Trophies = require("../src/shared/Trophies")

local Core = {}

-- ===== player model knobs (documented in the handoff) =====
Core.ACT_SECONDS = 7 -- one manual round with a sale: harvest all, teleport to the sell stand, sell, back, buy, plant all
Core.PLANT_SECONDS = 3 -- a round that only buys and plants (nothing to harvest or sell)
Core.START_DELAY = 4 -- seconds before the first action: read the card, pick a seed, walk to a tile
Core.DAILY_CLAIM_AT = 6 -- the daily reward is the first thing on screen; an active player taps it within seconds
Core.TUTORIAL_SALE_DELAY = 3 -- tutorial gift lands a few seconds after the first sale
Core.MAX_PAYBACK = 1500 -- upgrades/tiles are bought only if they pay themselves back within this many seconds
Core.AMORTIZE = 1500 -- a regrowing tree's price is spread over this many seconds when ranking seeds

export type Tile = { seed: string, progress: number, rg: boolean }
export type Event = { t: number, kind: string, id: string }
export type S = {
	t: number,
	cash: number,
	totalEarned: number,
	rebirths: number,
	tilesOwned: number,
	up: { [string]: number },
	seeds: { [string]: number },
	tiles: { Tile? },
	basket: { [string]: number },
	basketCount: number,
	stock: { [string]: number },
	nextRestock: number,
	busyUntil: number,
	giftsClaimed: { [number]: boolean },
	dailyDone: boolean,
	tutorialPending: number,
	tutorialDone: boolean,
	boostUntil: number,
	earnLog: { { t: number, amount: number } },
	bestRate: number,
	curSeed: string,
	hitCap: boolean,
	autoNext: number,
	autoSeed: string,
	events: { Event },
	seen: { [string]: boolean },
	upgradeBuys: number,
	planted: number,
	lastHarvested: number,
}

local function roll(seed: number): ()
	math.randomseed(seed)
end

local function rollStock(): { [string]: number }
	local stock = {}
	for _, seed in Config.Seeds do
		if math.random() <= seed.stockChance then
			stock[seed.id] = math.random(seed.stockMin, seed.stockMax)
		else
			stock[seed.id] = 0
		end
	end
	return stock
end

-- ===== multipliers (same formulas as Session.cashMult / growthMult / luckMult, free player, no weather) =====
local function cashMult(s: S): number
	local m = 1 + s.rebirths * Config.RebirthBonus
	return m * (1 + (s.up.CropValue or 0) * Config.UpgradeById.CropValue.perLevel)
end

local function growMult(s: S): number
	local m = 1 + (s.up.GrowSpeed or 0) * Config.UpgradeById.GrowSpeed.perLevel
	if s.t < s.boostUntil then
		m *= 2
	end
	return m
end

-- Expected value of a harvest's sell multiplier (mutation x size), from the real Odds/Config/Trophies numbers.
local function expectedValueMult(luckLevel: number): number
	local ctx: Odds.Ctx = { luck = 1 + luckLevel * Config.UpgradeById.Luck.perLevel, weather = nil, goldenMult = 1, eventMult = 1 }
	local remaining, ev = 1, 0
	for _, m in Config.Mutations do
		local c = Odds.mutationChance(m, ctx)
		ev += remaining * c * m.multiplier
		remaining *= 1 - c
	end
	ev += remaining
	local sizeEv, rest = 0, 1
	for _, sz in Trophies.Sizes do
		sizeEv += sz.chance * sz.valueMult
		rest -= sz.chance
	end
	return ev * (sizeEv + rest)
end

local function harvestValue(s: S, seedId: string): number
	return Config.SeedById[seedId].sellValue * cashMult(s) * expectedValueMult(s.up.Luck or 0)
end

local function addCash(s: S, amount: number, fromSale: boolean)
	amount = math.floor(amount)
	s.cash += amount
	if amount > 0 then
		s.totalEarned += amount
		if fromSale then
			table.insert(s.earnLog, { t = s.t, amount = amount })
			while #s.earnLog > 0 and s.t - s.earnLog[1].t > 300 do
				table.remove(s.earnLog, 1)
			end
			local sum = 0
			for _, e in s.earnLog do
				sum += e.amount
			end
			local minutes = math.max(1, math.min(5, s.t / 60))
			s.bestRate = math.max(s.bestRate, sum / minutes)
		end
	end
end

local function earnRate(s: S): number
	local sum = 0
	for _, e in s.earnLog do
		if s.t - e.t <= 300 then
			sum += e.amount
		end
	end
	return math.floor(sum / math.max(1, math.min(5, s.t / 60)))
end

local function log(s: S, kind: string, id: string)
	table.insert(s.events, { t = s.t, kind = kind, id = id })
end

-- First time something happens (first harvest, first tomato planted, ...).
local function once(s: S, kind: string, id: string)
	local key = kind .. ":" .. id
	if not s.seen[key] then
		s.seen[key] = true
		log(s, kind, id)
	end
end

local function backpackCap(s: S): number
	return Formulas.backpackCap(s.up.Backpack or 0, false)
end

local function grant(s: S, reward: any)
	local cash = (reward.cash or 0)
	if reward.cashMinutes then
		cash += Gifts.cashFor(reward.cashMinutes, math.max(earnRate(s), s.bestRate), Config.GiftCashFloorPerMinute)
	end
	if cash > 0 then
		addCash(s, cash, false)
	end
	if reward.seeds then
		for id, n in reward.seeds do
			s.seeds[id] = (s.seeds[id] or 0) + n
		end
	end
	if reward.boost and reward.boost.kind == "growth" then
		s.boostUntil = math.max(s.boostUntil, s.t) + reward.boost.seconds
	end
	if reward.luckyPack then
		for _ = 1, reward.luckyPack * Odds.LuckyPerPack do
			local id = Odds.rollLucky(math.random())
			s.seeds[id] = (s.seeds[id] or 0) + 1
		end
	end
end

-- ===== income estimate used by the buying policy =====
local function seedRatePerTile(s: S, seedId: string, inventory: boolean): number
	local seed = Config.SeedById[seedId]
	local gm = growMult(s)
	local value = harvestValue(s, seedId)
	local price = if inventory then 0 else seed.price
	local overhead = Core.ACT_SECONDS
	if seed.regrowTime then
		return value / (seed.regrowTime / gm + overhead) - price / Core.AMORTIZE
	end
	return (value - price) / (seed.growTime / gm + overhead)
end

local function income(s: S): number
	return s.tilesOwned * math.max(0.001, seedRatePerTile(s, s.curSeed, false))
end

local function withChange(s: S, id: string?, tiles: number): number
	local save = if id then s.up[id] else 0
	if id then
		s.up[id] = (s.up[id] or 0) + 1
	end
	local savedTiles = s.tilesOwned
	s.tilesOwned += tiles
	local r = income(s)
	s.tilesOwned = savedTiles
	if id then
		s.up[id] = save
	end
	return r
end

local function farmhandLevel(s: S): number
	return s.up.Farmhand or 0
end

-- ===== buying policy =====
local function buyUpgradesAndTiles(s: S)
	-- a full basket blocks harvesting: Bigger Basket first
	local bp = Config.UpgradeById.Backpack
	if s.hitCap and (s.up.Backpack or 0) < bp.maxLevel then
		local cost = Formulas.upgradeCost("Backpack", s.up.Backpack or 0)
		if s.cash >= cost then
			s.cash -= cost
			s.up.Backpack = (s.up.Backpack or 0) + 1
			s.upgradeBuys += 1
			log(s, "upgrade", "Backpack" .. s.up.Backpack)
			s.hitCap = false
		end
	end
	-- Farmhand (auto-farm): taken when it costs a modest slice of income
	local fh = Config.UpgradeById.Farmhand
	while farmhandLevel(s) < fh.maxLevel do
		local cost = Formulas.upgradeCost("Farmhand", farmhandLevel(s))
		if s.cash >= cost and cost <= income(s) * 1200 then
			s.cash -= cost
			s.up.Farmhand = farmhandLevel(s) + 1
			s.upgradeBuys += 1
			log(s, "upgrade", "Farmhand" .. s.up.Farmhand)
		else
			break
		end
	end
	-- income upgrades and tiles: best (income gained / cost) that is affordable and pays back soon enough
	while true do
		local base = income(s)
		local bestId: string? = nil
		local bestRatio, bestCost = 0, 0
		local bestIsTile = false
		for _, id in { "GrowSpeed", "CropValue", "Luck" } do
			local u = Config.UpgradeById[id]
			local lvl = s.up[id] or 0
			if lvl < u.maxLevel then
				local cost = Formulas.upgradeCost(id, lvl)
				local gain = withChange(s, id, 0) - base
				if cost <= s.cash and gain > 0 and cost / gain <= Core.MAX_PAYBACK and gain / cost > bestRatio then
					bestId, bestRatio, bestCost, bestIsTile = id, gain / cost, cost, false
				end
			end
		end
		if s.tilesOwned < Config.MaxTiles then
			local cost = Formulas.tileCost(s.tilesOwned)
			local gain = withChange(s, nil, 1) - base
			if cost <= s.cash and gain > 0 and cost / gain <= Core.MAX_PAYBACK and gain / cost > bestRatio then
				bestId, bestRatio, bestCost, bestIsTile = "tile", gain / cost, cost, true
			end
		end
		if not bestId then
			break
		end
		s.cash -= bestCost
		s.upgradeBuys += 1
		if bestIsTile then
			s.tilesOwned += 1
			log(s, "tile", tostring(s.tilesOwned))
		else
			s.up[bestId] = (s.up[bestId] or 0) + 1
			log(s, "upgrade", bestId .. s.up[bestId])
		end
	end
end

local function emptyTiles(s: S): { number }
	local list = {}
	for i = 1, s.tilesOwned do
		if not s.tiles[i] then
			table.insert(list, i)
		end
	end
	return list
end

local function plantOn(s: S, i: number, seedId: string)
	s.tiles[i] = { seed = seedId, progress = 0, rg = false }
	s.curSeed = seedId
	s.planted += 1
	once(s, "seed", seedId)
end

-- Fill empty tiles with the best seed on offer (by profit rate; inventory seeds are free, the rest is bought from the
-- personal stock). Tiles holding a much worse regrowing crop are shoveled and replanted: a real player does this the
-- moment a better tree shows up in the shop.
local REPLACE_FACTOR = 1.6

local function plantAll(s: S)
	local slots: { { i: number, rate: number } } = {}
	for i = 1, s.tilesOwned do
		local t = s.tiles[i]
		if not t then
			table.insert(slots, { i = i, rate = -math.huge })
		elseif t.rg or Config.SeedById[t.seed].regrowTime then
			table.insert(slots, { i = i, rate = seedRatePerTile(s, t.seed, true) })
		end
	end
	if #slots == 0 then
		return
	end
	table.sort(slots, function(a, b)
		if a.rate == b.rate then
			return a.i < b.i
		end
		return a.rate < b.rate
	end)
	local order = {}
	for _, seed in Config.Seeds do
		if (s.seeds[seed.id] or 0) > 0 or (s.stock[seed.id] or 0) > 0 then
			table.insert(order, seed.id)
		end
	end
	table.sort(order, function(a, b)
		local ra = seedRatePerTile(s, a, (s.seeds[a] or 0) > 0)
		local rb = seedRatePerTile(s, b, (s.seeds[b] or 0) > 0)
		if ra == rb then
			return a < b
		end
		return ra > rb
	end)
	for _, slot in slots do
		for _, id in order do
			local seed = Config.SeedById[id]
			local have = s.seeds[id] or 0
			local canBuy = (s.stock[id] or 0) > 0 and s.cash >= seed.price
			if have > 0 or canBuy then
				local r = seedRatePerTile(s, id, have > 0)
				if slot.rate == -math.huge or r > slot.rate * REPLACE_FACTOR then
					if have > 0 then
						s.seeds[id] = have - 1
					else
						s.cash -= seed.price
						s.stock[id] -= 1
						once(s, "buy", id)
					end
					plantOn(s, slot.i, id)
				end
				break
			end
		end
	end
end

local function harvest(s: S, limit: number): number
	local n = 0
	for i = 1, s.tilesOwned do
		local t = s.tiles[i]
		if t and t.progress >= 1 and n < limit then
			if s.basketCount >= backpackCap(s) then
				s.hitCap = true
				break
			end
			s.basket[t.seed] = (s.basket[t.seed] or 0) + 1
			s.basketCount += 1
			once(s, "harvest", "first")
			local seed = Config.SeedById[t.seed]
			if seed.regrowTime then
				s.tiles[i] = { seed = t.seed, progress = 0, rg = true }
			else
				s.tiles[i] = nil
			end
			n += 1
		end
	end
	return n
end

local function sell(s: S)
	if s.basketCount == 0 then
		return
	end
	local total = 0
	for id, n in s.basket do
		total += math.floor(harvestValue(s, id)) * n
	end
	s.basket = {}
	s.basketCount = 0
	addCash(s, total, true)
	if not s.seen["sale:first"] then
		s.seen["sale:first"] = true
		log(s, "sale", "first")
		s.tutorialPending = s.t + Core.TUTORIAL_SALE_DELAY
	end
end

local function rebirth(s: S)
	local cost = Formulas.rebirthCost(s.rebirths)
	if s.cash < cost then
		return
	end
	s.rebirths += 1
	log(s, "rebirth", tostring(s.rebirths))
	s.cash = Config.StartingCash
	s.tilesOwned = Config.StartingTiles
	for id in s.up do
		local u = Config.UpgradeById[id]
		if not (u and u.keepOnRebirth) then
			s.up[id] = 0
		end
	end
	s.seeds = table.clone(Config.StartingSeeds)
	s.basket = {}
	s.basketCount = 0
	s.tiles = {}
	s.curSeed = "carrot"
end

local function claimFree(s: S)
	if not s.dailyDone and s.t >= Core.DAILY_CLAIM_AT then
		s.dailyDone = true
		grant(s, Config.DailyRewards[1])
		log(s, "daily", "day1")
	end
	if s.tutorialPending > 0 and not s.tutorialDone and s.t >= s.tutorialPending then
		s.tutorialDone = true
		grant(s, Config.TutorialGift)
		log(s, "gift", "tutorial")
	end
	for i, g in Config.PlaytimeGifts do
		if not s.giftsClaimed[i] and s.t >= g.minutes * 60 then
			s.giftsClaimed[i] = true
			grant(s, g)
			log(s, "gift", "play" .. g.minutes)
		end
	end
end

local function autoFarm(s: S)
	local lvl = farmhandLevel(s)
	if lvl <= 0 or s.t < s.autoNext then
		return
	end
	local rules = Config.AutoFarm :: any
	local allowed = AutoFarm.allowed(rules, lvl, false)
	local interval = AutoFarm.interval(rules, lvl, false)
	local batch = AutoFarm.batch(rules, lvl, false)
	s.autoNext = s.t + interval
	if allowed.harvest then
		harvest(s, batch)
	end
	if allowed.plant then
		-- plants from the inventory only (the seed picked in the hotbar)
		local n = 0
		for i = 1, s.tilesOwned do
			if not s.tiles[i] and n < batch and (s.seeds[s.curSeed] or 0) > 0 then
				s.seeds[s.curSeed] -= 1
				plantOn(s, i, s.curSeed)
				n += 1
			end
		end
	end
	if allowed.sell and AutoFarm.shouldSell(s.basketCount, backpackCap(s), rules) then
		sell(s)
	end
end

local function canAct(s: S): boolean
	if s.t < s.busyUntil then
		return false
	end
	if s.basketCount > 0 then
		return true
	end
	for i = 1, s.tilesOwned do
		local t = s.tiles[i]
		if t and t.progress >= 1 then
			return true
		end
	end
	if #emptyTiles(s) > 0 then
		-- only worth a trip when there is something to plant
		for _, seed in Config.Seeds do
			if (s.seeds[seed.id] or 0) > 0 or ((s.stock[seed.id] or 0) > 0 and s.cash >= seed.price) then
				return true
			end
		end
	end
	return false
end

local function manualRound(s: S)
	local before = s.upgradeBuys + s.planted
	s.lastHarvested = harvest(s, 1000) + s.basketCount
	sell(s)
	claimFree(s)
	rebirth(s)
	buyUpgradesAndTiles(s)
	plantAll(s)
	-- a round that found nothing to do costs only a moment
	local acted = s.upgradeBuys + s.planted > before
	s.busyUntil = s.t + (if s.lastHarvested > 0 then Core.ACT_SECONDS elseif acted then Core.PLANT_SECONDS else 1)
end

local function tick(s: S)
	s.t += 1
	-- growth
	local gm = growMult(s)
	for i = 1, s.tilesOwned do
		local t = s.tiles[i]
		if t and t.progress < 1 then
			local seed = Config.SeedById[t.seed]
			local gt = if t.rg and seed.regrowTime then seed.regrowTime else seed.growTime
			t.progress = math.min(1, t.progress + gm / gt)
		end
	end
	if s.t >= s.nextRestock then
		s.stock = rollStock()
		s.nextRestock += Config.RestockInterval
	end
	claimFree(s)
	autoFarm(s)
	if s.t >= Core.START_DELAY and canAct(s) then
		manualRound(s)
	end
end

-- Runs one player for `seconds` of active play. seed: RNG seed (stock rolls, restock phase, lucky packs).
function Core.run(seed: number, seconds: number): S
	roll(seed)
	local s: S = {
		t = 0,
		cash = Config.StartingCash,
		totalEarned = 0,
		rebirths = 0,
		tilesOwned = Config.StartingTiles,
		up = {},
		seeds = table.clone(Config.StartingSeeds),
		tiles = {},
		basket = {},
		basketCount = 0,
		stock = rollStock(),
		nextRestock = math.random(30, Config.RestockInterval), -- joined mid-cycle of the server's restock timer
		busyUntil = 0,
		giftsClaimed = {},
		dailyDone = false,
		tutorialPending = 0,
		tutorialDone = false,
		boostUntil = 0,
		earnLog = {},
		bestRate = 0,
		curSeed = "carrot",
		hitCap = false,
		autoNext = 0,
		autoSeed = "carrot",
		events = {},
		seen = {},
		upgradeBuys = 0,
		planted = 0,
		lastHarvested = 0,
	}
	for _, u in Config.Upgrades do
		s.up[u.id] = 0
	end
	-- the player's first plant: they start with 3 carrots; the first round happens at t=1
	for _ = 1, seconds do
		tick(s)
	end
	return s
end

-- ===== milestone extraction =====
export type Milestones = {
	firstGain: number, -- first cash in the wallet from anything (daily reward)
	firstHarvest: number,
	firstSale: number,
	firstBuy: number, -- first purchase of any kind (seed, tile, upgrade)
	firstUpgrade: number, -- first tile/upgrade purchase
	third: number, -- time of the 3rd tile/upgrade purchase
	tiles: { [number]: number },
	seeds: { [string]: number }, -- first time each seed is planted
	farmhand: { number },
	rebirth: { number },
	maxGapFirstHour: number, -- longest stretch with no "something new" (tile, upgrade, new seed tier, rebirth)
	maxSeedGapFirstHour: number,
}

local INF = math.huge

function Core.milestones(s: S): Milestones
	local m: Milestones = {
		firstGain = INF,
		firstHarvest = INF,
		firstSale = INF,
		firstBuy = INF,
		firstUpgrade = INF,
		third = INF,
		tiles = {},
		seeds = {},
		farmhand = {},
		rebirth = {},
		maxGapFirstHour = 0,
		maxSeedGapFirstHour = 0,
	}
	local purchases = 0
	local newTimes: { number } = { 0 }
	local seedTimes: { number } = { 0 }
	for _, e in s.events do
		if e.kind == "daily" and e.t < m.firstGain then
			m.firstGain = e.t
		elseif e.kind == "harvest" then
			m.firstHarvest = math.min(m.firstHarvest, e.t)
			m.firstGain = math.min(m.firstGain, e.t)
		elseif e.kind == "sale" then
			m.firstSale = math.min(m.firstSale, e.t)
		elseif e.kind == "seed" then
			m.seeds[e.id] = m.seeds[e.id] or e.t
			if e.t > 0 then
				table.insert(newTimes, e.t)
				table.insert(seedTimes, e.t)
			end
		elseif e.kind == "buy" then
			m.firstBuy = math.min(m.firstBuy, e.t)
		elseif e.kind == "tile" or e.kind == "upgrade" then
			purchases += 1
			m.firstBuy = math.min(m.firstBuy, e.t)
			m.firstUpgrade = math.min(m.firstUpgrade, e.t)
			if purchases == 3 then
				m.third = e.t
			end
			table.insert(newTimes, e.t)
			if e.kind == "tile" then
				local n = tonumber(e.id) :: number
				m.tiles[n] = m.tiles[n] or e.t
			elseif string.sub(e.id, 1, 8) == "Farmhand" then
				m.farmhand[tonumber(string.sub(e.id, 9)) :: number] = e.t
			end
		elseif e.kind == "gift" and e.id ~= "tutorial" then
			table.insert(newTimes, e.t)
		elseif e.kind == "rebirth" then
			m.rebirth[tonumber(e.id) :: number] = e.t
			table.insert(newTimes, e.t)
			table.insert(seedTimes, e.t)
		end
	end
	-- the tutorial's first buy is the carrots it starts you with: count the seed purchase as the first buy
	local function maxGap(times: { number }): number
		table.sort(times)
		local gap, last = 0, 0
		for _, t in times do
			if t > 3600 then
				break
			end
			gap = math.max(gap, t - last)
			last = t
		end
		return math.max(gap, math.min(3600, s.t) - last)
	end
	m.maxGapFirstHour = maxGap(newTimes)
	m.maxSeedGapFirstHour = maxGap(seedTimes)
	return m
end

function Core.percentile(list: { number }, p: number): number
	local copy = table.clone(list)
	table.sort(copy)
	if #copy == 0 then
		return INF
	end
	return copy[math.clamp(math.ceil(#copy * p), 1, #copy)]
end

return Core
