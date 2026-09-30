--!nocheck
-- Pacing model for Sky Tower Obby (pure Luau, no Roblox APIs). It reuses the REAL shared modules
-- (Layout, Rules, Gifts, Powerups, Economy) and turns them into "how long does a free player take".
--   * stage model : every generated stage (all 10 towers) -> a list of risk events (each jump, kill
--                   cube, spinner, laser gate ...) and waits (movers, lasers, lava ...). From it:
--                   analytic expected seconds per stage (no randomness: difficulty curve checks) and
--                   a sampled attempt (death, respawn, walk back from the last saving pad).
--   * player model: a free player with the obvious policy (see PacingModel.play).
-- The numbers that are guesses (per-jump risk, hesitation, skill growth) live in PacingModel.Tune
-- and are documented in the handoff: the model is for RELATIVE pacing (ramps, spikes, windows), not
-- for predicting a real CCU curve.
local Layout = require("../src/shared/Layout")
local Rules = require("../src/shared/Rules")
local Gifts = require("../src/shared/Gifts")
local Powerups = require("../src/shared/Powerups")
local Economy = require("../src/shared/Economy")

local PacingModel = {}
PacingModel.Layout = Layout
PacingModel.Economy = Economy

local L = Layout :: any
local WALK = Layout.Physics.walkSpeed

PacingModel.Tune = {
	pathFactor = 1.6, -- real path length / straight line (steering, corners, camera)
	jumpOverhead = 0.7, -- s lost per hop (landing, re-aim)
	respawn = 2.5, -- s from a death to standing on the pad again (RespawnTime 1.5 + fall + load)
	pace = 1.15, -- casual players stop, look around, re-aim the camera: x on all movement time
	climbSpeed = 12, -- studs/s on a truss
	baseRisk = 0.02, -- per hop, on the widest, shortest gap
	tightRisk = 0.42, -- extra risk when the gap is at 100% of the jump reach
	tightFrom = 0.45, -- share of reach below which tightness adds nothing
	-- novice -> practiced: risk multiplier and hesitation multiplier decay with stages cleared
	skillStart = 1.35,
	skillEnd = 0.8,
	skillTau = 40,
	hesitation = 0.6, -- extra movement time for the very first stages (x1.6 on top of `pace`)
	hesitationTau = 12,
	skillSigma = 0.22, -- per-player log-normal spread of the risk multiplier
	stuckDeaths = 4, -- Config.SkipOfferAfterDeaths: the "Stuck?" card (Config needs Roblox types, so mirrored)
	dailyClaimAfter = 25, -- s into a session when the player opens Rewards and claims the daily coins
	pickupChance = 0.75, -- share of the stage coins the player actually grabs
}

---------------------------------------------------------------------------------------------
-- Stage model
---------------------------------------------------------------------------------------------
export type Event = { pos: number, risk: number, wait: number, tag: string }
export type StageModel = {
	g: number,
	kind: string,
	move: number, -- seconds of walking/jumping/climbing with no waits
	events: { Event },
	save: boolean,
	firstCoinAt: number?, -- seconds after leaving the previous pad
	coins: number, -- coin pickups on the route
}

local function clamp(x: number, a: number, b: number): number
	return math.max(a, math.min(b, x))
end

-- Risk of a hop over `gap` studs onto a platform `len` x `width`, climbing `dh`.
local function hopRisk(T, gap: number, dh: number, len: number, width: number): number
	local limit = Layout.maxGap(math.max(dh, 0))
	local share = if limit > 0 then gap / limit else 1
	local tight = clamp((share - T.tightFrom) / (1 - T.tightFrom), 0, 1) ^ 2
	local size = 1 + math.max(0, 4 - len) * 0.25 + math.max(0, 4 - width) * 0.15
	return T.baseRisk + T.tightRisk * tight * size
end

-- Builds the model of one generated stage.
function PacingModel.stageModel(st, T): StageModel
	local nodes = {}
	for _, n in st.nodes do
		table.insert(nodes, n)
	end
	table.sort(nodes, function(a, b)
		return a.s < b.s
	end)
	local events: { Event } = {}
	local hazardsByNode = {}
	local prevEnd, prevY, prevKind = Layout.PAD_RADIUS, 0, "pad"
	local span = st.span
	local moveTime = (2 * Layout.PAD_RADIUS) / WALK * 0.5 -- cross the pads
	local lat0 = 0
	local extraWait = 0
	local firstCoin: number? = nil
	local function add(pos: number, risk: number, wait: number, tag: string)
		table.insert(events, { pos = pos, risk = clamp(risk, 0, 0.6), wait = wait, tag = tag })
	end
	for i = 1, #nodes + 1 do
		local n = nodes[i]
		local startS, endS, y, len, width, kind
		if n then
			startS, endS, y, len, width, kind = n.s - n.len / 2, n.s + n.len / 2, n.y, n.len, n.width, n.kind
		else
			startS, endS, y, len, width, kind = span - Layout.PAD_RADIUS, span - Layout.PAD_RADIUS + 1, st.rise, 12, 12, "pad"
		end
		local gap = math.max(0, startS - prevEnd)
		local dh = y - prevY
		local pos = startS / span
		if kind == "truss" then
			-- walk to it, climb it
			moveTime += math.max(0, startS - prevEnd) / WALK * T.pathFactor
			moveTime += math.max(1, (y - (n.yBottom or 0))) / T.climbSpeed
			add(pos, 0.02 + 0.01 * st.difficulty, 0, "truss")
		elseif gap > 0.6 then
			local landingLen, landingWidth = len, width
			local risk = hopRisk(T, gap, dh, landingLen, landingWidth)
			local wait = 0
			if kind == "ice" then
				risk *= 1.4
			elseif kind == "glass" then
				risk *= 1.3
			elseif kind == "disappear" or kind == "falling" then
				local delay = n.delay or 0.6
				local need = math.max(len, 2) / WALK + 0.3 -- time to cross it (and leave)
				risk *= 1 + 0.9 * clamp((need - delay) / 0.5, 0, 1)
			elseif kind == "moving" then
				local period = n.movePeriod or 4
				local amp = n.moveAmp or 3
				local speed = 2 * math.pi * amp / period
				risk *= 1.15 + 0.7 * clamp((speed - 3) / 8, 0, 1)
				wait = period * 0.25 -- wait for the platform to come round
			elseif kind == "bounce" then
				risk *= 1.1
			elseif kind == "conveyor" then
				risk *= 1 + math.abs(n.pushS or 0) / WALK + math.abs(n.pushLat or 0) / WALK * 0.5
			elseif kind == "ledge" then
				risk *= 1.3
			end
			moveTime += gap / WALK * T.pathFactor + T.jumpOverhead
			add(pos, risk, wait, kind)
		else
			moveTime += math.max(gap, 0.5) / WALK * T.pathFactor
		end
		-- standing/walking on the platform itself
		if n then
			local run = math.max(len - 1, 0)
			moveTime += run / WALK * T.pathFactor * (if kind == "conveyor" then 1.4 else 1)
			moveTime += math.abs(n.lat - lat0) / WALK
			lat0 = n.lat
			if kind == "beam" then
				local narrow = clamp((3 - width) / 2, 0, 1)
				add(n.s / span, 0.012 + 0.07 * narrow + 0.0015 * len * narrow, 0, "beam")
			end
		end
		prevEnd, prevY, prevKind = endS, y, kind
	end
	-- hazards
	for _, h in st.hazards do
		local pos = h.s / span
		local d = st.difficulty
		if h.kind == "killcube" then
			add(pos, 0.012 + 0.03 * d, 0, "killcube")
		elseif h.kind == "spinner" then
			local bars = h.bars or 1
			add(pos, 0.03 + 0.05 * d * bars + 0.02 * (math.abs(h.speed or 1.5) - 1.3), 0.8, "spinner")
		elseif h.kind == "laser" then
			local period = h.period or 3
			local duty = h.duty or 0.5
			add(pos, 0.02 + 0.06 * d, period * (1 - duty) * 0.5, "laser")
		elseif h.kind == "lava" then
			add(0.5, 0.05 + 0.12 * d, (h.period or 9) * 0.15, "lava")
		elseif h.kind == "wind" then
			-- the wind pushes you off line: the zone's hops are a bit riskier
			add(pos, 0.01 + 0.035 * ((h.push and math.abs(h.push) or 4) / 9), 0, "wind")
		elseif h.kind == "wall" then
			add(0.5, 0.02 + 0.03 * d, 0, "wall")
		end
		-- killstrip: the gap it fills already counts as a hop
	end
	table.sort(events, function(a, b)
		return a.pos < b.pos
	end)
	-- first coin: time to walk to the first coin of the stage (only used for stage 1)
	if st.coins[1] then
		local c = st.coins[1]
		for _, cc in st.coins do
			if cc.s < c.s then
				c = cc
			end
		end
		firstCoin = (c.s / WALK) * T.pathFactor
	end
	return {
		g = st.index,
		kind = st.kind,
		move = moveTime,
		events = events,
		save = Layout.isSave(st.index),
		firstCoinAt = firstCoin,
		coins = #st.coins,
	}
end

-- All 1000 stage models (deterministic: Layout.generate is seeded).
local cached: { [number]: StageModel }? = nil
function PacingModel.stages(): { [number]: StageModel }
	if cached then
		return cached
	end
	local out: { [number]: StageModel } = {}
	for tower = 1, Layout.TOWERS do
		local map = Layout.generate(Layout.DEFAULT_SEED, tower)
		for _, st in map.stages do
			out[st.index] = PacingModel.stageModel(st, PacingModel.Tune)
		end
	end
	cached = out
	return out
end

local function clean(m: StageModel, hes: number): number
	local t = m.move * hes
	for _, e in m.events do
		t += e.wait
	end
	return t
end
PacingModel.cleanTime = clean

function PacingModel.skill(n: number): number
	local T = PacingModel.Tune
	return T.skillEnd + (T.skillStart - T.skillEnd) * math.exp(-n / T.skillTau)
end
function PacingModel.hesitation(n: number): number
	local T = PacingModel.Tune
	return T.pace + T.hesitation * math.exp(-n / T.hesitationTau)
end

-- Cost (s) of dying on stage g: respawn + redo of the unsaved stages before it.
local function redoCost(models, g: number, hes: number): number
	local cost = PacingModel.Tune.respawn
	local k = g - 1
	while k >= 1 and not models[k].save do
		cost += clean(models[k], hes) * 0.85
		k -= 1
	end
	return cost
end

-- Expected seconds to clear stage g for a player with risk multiplier `sk` and hesitation `hes`
-- (analytic: attempts are geometric, a failed attempt costs the time up to the failure + redoCost).
function PacingModel.expected(g: number, sk: number, hes: number): (number, number)
	local models = PacingModel.stages()
	local m = models[g]
	local pAlive, t, cost = 1, 0, 0
	local waitBefore = 0
	local redo = redoCost(models, g, hes)
	for _, e in m.events do
		local tPos = m.move * hes * e.pos + waitBefore
		local r = clamp(e.risk * sk, 0, 0.85)
		cost += pAlive * r * (tPos + redo)
		pAlive *= 1 - r
		waitBefore += e.wait
	end
	local tClean = clean(m, hes)
	cost += pAlive * tClean
	return cost / pAlive, 1 / pAlive -- seconds, expected attempts
end

---------------------------------------------------------------------------------------------
-- Player model
---------------------------------------------------------------------------------------------
-- Policy of the free player:
--   * walks the tower; dies, respawns at the last saving pad, tries again;
--   * after Config.SkipOfferAfterDeaths deaths on a stage uses a free skip if it has one; after 8
--     deaths buys a coin skip (Powerups "skip") if it can pay it;
--   * claims every play-time gift the minute it opens and the daily reward at the start of a session;
--   * picks the coins on the route (75%), and buys the most expensive cosmetic it can afford,
--     except that it keeps a skip's worth of coins once it is past stage 30... (see RESERVE);
--   * at the world shops it buys a shield when it has spare coins (it is a stuck-avoiding tool).
local RESERVE_FROM, RESERVE = 30, 0 -- no reserve: cosmetics first (what most kids do)

export type Milestone = { t: number, what: string }

export type Catalog = { { id: string, price: number, kind: string, tower: number } }
-- Everything sold for coins: trails, effects and the shoulder pets (tower = towers to clear first)
function PacingModel.catalog(): Catalog
	local out = {}
	for id, price in Economy.TrailPrice do
		table.insert(out, { id = "trail:" .. id, price = price, kind = "trail", tower = Economy.towerReq("trail", id) })
	end
	for id, price in Economy.EffectPrice do
		table.insert(out, { id = "effect:" .. id, price = price, kind = "effect", tower = Economy.towerReq("effect", id) })
	end
	for id, price in Economy.PetPrice do
		table.insert(out, { id = "pet:" .. id, price = price, kind = "pet", tower = Economy.towerReq("pet", id) })
	end
	table.sort(out, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.id < b.id
	end)
	return out
end

export type Options = {
	seed: number,
	sessions: { number }?, -- minutes of each day's session (a session per day); default 60 then 30/day
	days: number?,
	maxStage: number?,
	stopAtStage: number?,
}

export type Result = {
	reached: { [number]: number }, -- stage -> active seconds since the first join
	purchases: { { t: number, id: string, price: number } },
	events: { Milestone },
	firstReward: number,
	firstPlaytimeGift: number,
	dayStage: { number }, -- stage at the end of each day
	dayStageAt: { number }, -- active seconds at the end of each day
	coinsEarned: number,
	coinsSpent: number,
	skipsUsed: number,
	paidSkips: number,
	deaths: number,
	activeSeconds: number,
	stageSeconds: { [number]: number },
	novelty: { number }, -- times of "something new" events (first hour view)
	bankAt: { [number]: number }, -- tower -> coins unspent when its summit is reached
	unownedAt: { [number]: number }, -- tower -> catalogue items (trails / effects / pets) not owned yet at its summit
	shineBought: number,
}

function PacingModel.play(opts: Options): Result
	local T = PacingModel.Tune
	local models = PacingModel.stages()
	local rng = Layout.newRng(opts.seed * 7919 + 13)
	-- per-player skill multiplier (log-normal)
	local function gauss(): number
		local u1, u2 = math.max(rng.next(), 1e-9), rng.next()
		return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	end
	local skillMul = math.exp(T.skillSigma * gauss())
	local days = opts.days or 14
	local sessions = opts.sessions or {}
	local maxStage = opts.maxStage or Layout.TOTAL
	local res: Result = {
		reached = {},
		purchases = {},
		events = {},
		firstReward = math.huge,
		firstPlaytimeGift = math.huge,
		dayStage = {},
		dayStageAt = {},
		coinsEarned = 0,
		coinsSpent = 0,
		skipsUsed = 0,
		paidSkips = 0,
		deaths = 0,
		activeSeconds = 0,
		stageSeconds = {},
		novelty = {},
		bankAt = {},
		unownedAt = {},
		shineBought = 0,
	}
	local coins, freeSkips, stage = 0, 0, 0
	local clock = 0 -- active seconds
	local owned: { [string]: boolean } = {}
	local catalog = PacingModel.catalog()
	local gifts: { [string]: boolean } = {}
	local shield = 0
	local seenKind: { [string]: boolean } = {}
	local streak = 0

	local function coinMult(): number
		return Gifts.coinMult(gifts)
	end
	local function earn(base: number)
		local got = math.floor(base * coinMult() + 0.5)
		coins += got
		res.coinsEarned += got
	end
	local function log(what: string)
		table.insert(res.events, { t = clock, what = what })
	end
	local function novelty(what: string)
		table.insert(res.novelty, clock)
		log(what)
	end
	local shineLevel: { [string]: number } = {}
	local function buy(id: string, price: number)
		coins -= price
		res.coinsSpent += price
		table.insert(res.purchases, { t = clock, id = id, price = price })
		novelty("buy " .. id)
	end
	local function shop()
		local again = true
		while again do
			again = false
			-- cosmetics: the most expensive thing it can afford, among the unowned items it has
			-- unlocked (towers cleared = best stage reached) and the Shine upgrades of what it owns
			local best, bestPrice, shineOf
			local saving = false -- an unlocked item it cannot pay yet: it saves for that one
			for _, it in catalog do
				if not owned[it.id] and Economy.towerCleared(stage, it.tower) then
					if it.price <= coins - (if stage >= RESERVE_FROM then RESERVE else 0) then
						if it.price >= (bestPrice or 0) then
							best, bestPrice, shineOf = it.id, it.price, nil
						end
					else
						saving = true
					end
				end
			end
			-- while it waits for the next tower to unlock something new it polishes what it owns
			-- (cheapest level first); with a goal in sight it does not spend on Shine
			if not best and not saving then
				for id in owned do
					local cost = Economy.shineCost(shineLevel[id] or 0)
					if cost and cost <= coins and cost < (bestPrice or math.huge) then
						best, bestPrice, shineOf = id, cost, id
					end
				end
			end
			if best and bestPrice then
				if shineOf then
					shineLevel[shineOf] = (shineLevel[shineOf] or 0) + 1
					res.shineBought += 1
					buy(("shine %s L%d"):format(shineOf, shineLevel[shineOf]), bestPrice)
				else
					owned[best] = true
					buy(best, bestPrice)
				end
				again = true
			end
		end
	end

	for day = 1, days do
		local minutes = sessions[day] or (if day == 1 then 60 else 30)
		local sessionStart = clock
		local sessionEnd = clock + minutes * 60
		local claimed: { [number]: boolean } = {}
		-- daily reward: claimed in the first seconds of the session
		streak += 1
		local dailyDone = false
		local function daily()
			dailyDone = true
			earn(Economy.DailyRewards[math.min(streak, #Economy.DailyRewards)])
			if streak % Economy.DailyFreeSkipOnDay == 0 then
				freeSkips += 1
			end
			novelty("daily reward (day " .. streak .. ")")
			shop()
		end
		local function playtimeGifts()
			for i, r in Economy.PlaytimeRewards do
				if not claimed[i] and clock - sessionStart >= r.minutes * 60 then
					claimed[i] = true
					if clock < res.firstPlaytimeGift then
						res.firstPlaytimeGift = clock
					end
					earn(r.coins)
					freeSkips += r.freeSkips
					novelty(("playtime gift %d (+%d coins%s)"):format(i, r.coins, if r.freeSkips > 0 then (" +%d skip"):format(r.freeSkips) else ""))
					shop()
				end
			end
		end
		while clock < sessionEnd and stage < maxStage do
			if not dailyDone and clock - sessionStart >= T.dailyClaimAfter then
				daily() -- the player opens the Rewards panel a few seconds after joining
			end
			playtimeGifts()
			local g = stage + 1
			local m = models[g]
			local hes = PacingModel.hesitation(stage)
			local stageStart = clock
			local deaths = 0
			local spent = 0
			local skipped = false
			if not seenKind[m.kind] and g > 10 then
				seenKind[m.kind] = true
				novelty("new obstacle: " .. m.kind .. " (stage " .. g .. ")")
			end
			while true do
				local sk = PacingModel.skill(stage) * skillMul
				-- one attempt
				local tt, died = 0, false
				local redo = redoCost(models, g, hes)
				local waitBefore = 0
				for _, e in m.events do
					local tPos = m.move * hes * e.pos + waitBefore
					local r = clamp(e.risk * sk, 0, 0.85)
					if rng.next() < r then
						if shield > 0 and (e.tag == "killcube" or e.tag == "laser" or e.tag == "spinner") then
							shield -= 1 -- a shield absorbs the hit
							waitBefore += e.wait
						else
							tt = tPos + redo
							died = true
							break
						end
					else
						waitBefore += e.wait
					end
				end
				if not died then
					tt = clean(m, hes)
				end
				clock += tt
				spent += tt
				if not died then
					break
				end
				deaths += 1
				res.deaths += 1
				-- the "Stuck?" card: free skip first, a coin skip when really stuck
				if deaths >= T.stuckDeaths and freeSkips > 0 then
					freeSkips -= 1
					res.skipsUsed += 1
					skipped = true
					log(("free skip used on stage %d"):format(g))
					break
				elseif deaths >= 2 * T.stuckDeaths and coins >= (Powerups.get("skip") :: any).price then
					coins -= (Powerups.get("skip") :: any).price
					res.coinsSpent += (Powerups.get("skip") :: any).price
					res.skipsUsed += 1
					res.paidSkips += 1
					skipped = true
					log(("coin skip bought on stage %d"):format(g))
					break
				end
				if clock >= sessionEnd + 600 then
					break -- gave up this session (rage quit after a long streak of deaths)
				end
			end
			stage = g
			res.reached[g] = clock
			res.stageSeconds[g] = spent
			-- coins: stage reward (+ tower bonus) and the pickups on the way
			earn(Rules.coinsForStage(g))
			for _ = 1, models[g].coins do
				if rng.next() < T.pickupChance then
					earn(Economy.CoinPickupValue)
					if g == 1 and res.firstReward == math.huge then
						res.firstReward = stageStart + (m.firstCoinAt or 0) * hes -- walked to the first coin
					end
				end
			end
			if g == 1 and res.firstReward == math.huge then
				res.firstReward = clock -- the stage reward itself
			end
			if g % Layout.STAGES == 0 then
				earn(Economy.CoinsPerTower)
				local gift = Gifts.at(g)
				if gift then
					gifts[tostring(gift.id)] = true
				end
				res.bankAt[g // Layout.STAGES] = coins
				local left = 0
				for _, it in catalog do
					if not owned[it.id] then
						left += 1
					end
				end
				res.unownedAt[g // Layout.STAGES] = left
				novelty(("summit of tower %d"):format(g // Layout.STAGES))
			end
			if g % 10 == 0 and g < Layout.TOTAL then
				novelty(("world %d (stage %d)"):format(g // 10 + 1, g))
				-- the shop deck of the world: a shield if it has coins to spare
				local shieldPrice = (Powerups.get("shield") :: any).price
				if coins >= shieldPrice * 3 and shield < 3 and g >= 20 then
					coins -= shieldPrice
					res.coinsSpent += shieldPrice
					shield += 1
				end
			end
			shop()
			if opts.stopAtStage and stage >= opts.stopAtStage then
				break
			end
			if clock >= sessionEnd + 600 then
				break
			end
		end
		if not dailyDone then
			daily()
		end
		playtimeGifts()
		res.dayStage[day] = stage
		res.dayStageAt[day] = clock
		-- idle time between days does not count as active time
		if clock < sessionEnd then
			-- finished early (reached maxStage)
			if stage >= maxStage then
				break
			end
		end
	end
	res.activeSeconds = clock
	return res
end

---------------------------------------------------------------------------------------------
-- Summary over many players (used by sim/pacing_sim.luau and tests/pacing_test.luau)
---------------------------------------------------------------------------------------------
local function median(t: { number }): number
	local a = table.clone(t)
	table.sort(a)
	if #a == 0 then
		return math.huge
	end
	return a[math.ceil(#a / 2)]
end
PacingModel.median = median

-- Expected seconds per stage for a practiced-by-then player of median skill (analytic).
function PacingModel.curve(): { number }
	local out = {}
	for g = 1, Layout.TOTAL do
		out[g] = (PacingModel.expected(g, PacingModel.skill(g - 1), PacingModel.hesitation(g - 1)))
	end
	return out
end

export type Summary = {
	seeds: number,
	firstReward: number,
	firstPlaytimeGift: number,
	firstPurchase: number,
	thirdPurchase: number,
	stageAt: { [number]: number }, -- stage (10, 20 .. 1000) -> median active seconds
	maxDeadStretch: number, -- longest time without "something new" in the first hour
	maxDeadStretch2h: number, -- same over the first two hours
	deadAt: number,
	dayStage: { number },
	purchasesFirstHour: number,
	coinsPerMinuteFirstHour: number,
}

function PacingModel.summary(seeds: number, days: number, sessions: { number }?): (Summary, { Result })
	local runs: { Result } = {}
	for seed = 1, seeds do
		table.insert(runs, PacingModel.play({ seed = seed, days = days, sessions = sessions }))
	end
	local function col(f: (Result) -> number): number
		local v = {}
		for _, r in runs do
			table.insert(v, f(r))
		end
		return median(v)
	end
	local stageAt = {}
	for g = 10, Layout.TOTAL, 10 do
		stageAt[g] = col(function(r)
			return r.reached[g] or math.huge
		end)
	end
	stageAt[1] = col(function(r)
		return r.reached[1] or math.huge
	end)
	local dayStage = {}
	for d = 1, days do
		dayStage[d] = col(function(r)
			return r.dayStage[d] or r.dayStage[#r.dayStage] or 0
		end)
	end
	local function deadStretch(window: number): number
		return col(function(r)
			local prev, worst = 0, 0
			for _, t in r.novelty do
				if t > window then
					break
				end
				worst = math.max(worst, t - prev)
				prev = t
			end
			return math.max(worst, math.min(window, r.activeSeconds) - prev)
		end)
	end
	local dead, deadAt = deadStretch(3600), 0
	return {
		seeds = seeds,
		firstReward = col(function(r)
			return r.firstReward
		end),
		firstPlaytimeGift = col(function(r)
			return r.firstPlaytimeGift
		end),
		firstPurchase = col(function(r)
			return if r.purchases[1] then r.purchases[1].t else math.huge
		end),
		thirdPurchase = col(function(r)
			return if r.purchases[3] then r.purchases[3].t else math.huge
		end),
		stageAt = stageAt,
		maxDeadStretch = dead,
		maxDeadStretch2h = deadStretch(7200),
		deadAt = deadAt,
		dayStage = dayStage,
		purchasesFirstHour = col(function(r)
			local n = 0
			for _, p in r.purchases do
				if p.t <= 3600 then
					n += 1
				end
			end
			return n
		end),
		coinsPerMinuteFirstHour = 0,
	}, runs
end

---------------------------------------------------------------------------------------------
-- Late game (towers 2-10): is there always something to save coins for?
---------------------------------------------------------------------------------------------
export type LateGame = {
	seeds: number,
	medianWorstGap: number, -- median over players of the longest time between two purchases after tower 2 (s)
	maxWorstGap: number, -- the same for the most unlucky player
	purchasesAfterTower2: number, -- median
	bank: { [number]: number }, -- tower -> median coins unspent at its summit
	maxBank: number, -- largest of those medians
	unowned: { [number]: number }, -- tower -> median catalogue items still to buy at its summit
	shineBought: number, -- median
	coinsEarned: number, -- median
	coinsSpent: number, -- median
}

function PacingModel.lateGame(seeds: number, days: number): (LateGame, { Result })
	local runs: { Result } = {}
	for seed = 1, seeds do
		table.insert(runs, PacingModel.play({ seed = seed, days = days }))
	end
	local worst, after, shine, earned, spent = {}, {}, {}, {}, {}
	for _, r in runs do
		local from = r.reached[2 * Layout.STAGES] or math.huge
		local prev: number?, w, n = nil, 0, 0
		for _, p in r.purchases do
			if p.t >= from then
				n += 1
				if prev then
					w = math.max(w, p.t - prev)
				end
				prev = p.t
			end
		end
		table.insert(worst, w)
		table.insert(after, n)
		table.insert(shine, r.shineBought)
		table.insert(earned, r.coinsEarned)
		table.insert(spent, r.coinsSpent)
	end
	local bank, unowned = {}, {}
	local maxBank = 0
	for t = 2, Layout.TOWERS do
		local b, u = {}, {}
		for _, r in runs do
			table.insert(b, r.bankAt[t] or 0)
			table.insert(u, r.unownedAt[t] or 0)
		end
		bank[t] = median(b)
		unowned[t] = median(u)
		maxBank = math.max(maxBank, bank[t])
	end
	table.sort(worst)
	return {
		seeds = seeds,
		medianWorstGap = median(worst),
		maxWorstGap = worst[#worst],
		purchasesAfterTower2 = median(after),
		bank = bank,
		maxBank = maxBank,
		unowned = unowned,
		shineBought = median(shine),
		coinsEarned = median(earned),
		coinsSpent = median(spent),
	}, runs
end

return PacingModel
