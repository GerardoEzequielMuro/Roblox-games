--!nonstrict
-- Pacing model for Spin Showdown: a FREE (non-paying) player over days and weeks, built on
-- the game's real shared modules (Config, Progression, SeasonPass, Quests, MatchCore,
-- BotBrain). Pure Luau: run `luau sim/pacing_sim.luau` from the repo root for the table,
-- tests/pacing_test.luau asserts the key milestones stay inside their target windows.
--
-- What is REAL: match rules (MatchCore + BotBrain play the human seat, so placements, turn
-- counts and per-match stats come from the actual engine), every reward number (match coins
-- / xp / trophies, level-up coins, quests, daily calendar, session gifts, season pass),
-- every price and unlock rule of the cosmetics, the Power Core.
-- What is MODELLED (see PARAMS): how long a turn takes on screen, how many tables have a
-- second human (season points / trophies are halved on bot-only tables), how fast the
-- player taps, when they log in. The limits are listed in the handoff doc.
local Config = require("../src/shared/Config")
local MatchCore = require("../src/shared/MatchCore")
local BotBrain = require("../src/shared/BotBrain")
local Rng = require("../src/shared/Rng")
local Progression = require("../src/shared/Progression")
local SeasonPass = require("../src/shared/SeasonPass")
local Quests = require("../src/shared/Quests")

local Model = {}

Model.PARAMS = {
	firstSessionMin = 75, -- day 0 session (the first hour is the critical one, plus a margin)
	dailyMin = 25, -- "active free player": 25 min every day
	humanTapsPerSec = 4, -- a real person tapping the Power Core (server cap is 8)
	lobbyTapsPerSec = 2, -- tapping by hand while waiting at the lobby between matches
	loadSec = 2, -- spawn to first tap
	pHumanTable = 0.6, -- share of tables with a 2nd human (the rest is practice: half points / trophies)
	walkSec = 12, -- reach a table and sit down
	humanDecideSec = 4.0, -- human turn: look at hand / aim
	humanSpinSec = 2.0, -- human turn: free spin before braking
	leaveAfterElimSec = 5, -- an eliminated player watches a bit and leaves for the next table
	modeWeights = { classic = 0.65, chaos = 0.2, teams = 0.15 }, -- duel needs a friend: not modelled
	matchPool = 300, -- engine matches sampled per mode
}

---------------------------------------------------------------------------
-- Match sampler: real engine, the human seat is played by BotBrain
---------------------------------------------------------------------------
export type Sample = { place: number, n: number, turns: number, elimTurn: number, elims: number, stats: { [string]: number }, wheel: number }

local function entrants(n: number)
	local list = {}
	for i = 1, n do
		list[i] = { id = "p" .. i, name = "P" .. i, bot = true }
	end
	return list
end

local function playOne(modeId: string, n: number, seed: number): Sample
	local m = MatchCore.new(modeId, entrants(n), seed)
	local brain = Rng.new(seed * 7919 + 13)
	MatchCore.start(m)
	local elimTurn = nil
	local steps = 0
	while m.phase ~= "ended" do
		steps += 1
		assert(steps < 5000, "match does not end")
		local si = m.spinner
		local p = m.players[si]
		local d = BotBrain.decide(m, si, brain)
		if d.card then
			MatchCore.playCard(m, p.id, d.card, d.cardTarget)
		end
		if m.phase == "decide" and m.spinner == si then
			if d.target and MatchCore.validTarget(m, si, m.byId[d.target]) then
				MatchCore.setTarget(m, p.id, d.target)
			end
			MatchCore.spin(m, p.id)
			MatchCore.brake(m, p.id, BotBrain.brakePhase(m, si, brain))
		end
		if elimTurn == nil and not m.players[1].alive then
			elimTurn = m.turn
		end
	end
	local me = m.players[1]
	local elims = 0
	for _, q in m.players do
		if not q.alive then
			elims += 1
		end
	end
	return {
		place = me.place,
		n = n,
		turns = m.turn,
		elimTurn = elimTurn or m.turn,
		elims = elims,
		stats = me.stats,
		wheel = #m.wheel,
	}
end

local pools: { [string]: { Sample } }? = nil
local function getPools(): { [string]: { Sample } }
	if pools then
		return pools
	end
	local out = {}
	for modeId, _ in Model.PARAMS.modeWeights do
		local mode = Config.ModeById[modeId]
		local list = {}
		for i = 1, Model.PARAMS.matchPool do
			table.insert(list, playOne(modeId, mode.fillTo, i * 97 + 5))
		end
		out[modeId] = list
	end
	pools = out
	return out
end

-- Seconds the human spends in a match (sit down excluded: that is the lobby part).
function Model.matchSeconds(s: Sample, first: boolean): number
	local P, T, W = Model.PARAMS, Config.Timing, Config.Wheel
	local travel = W.travelTurns * s.wheel + W.jitter
	local brake = W.easePower * travel / W.speed
	local botTurn = (T.decideBot[1] + T.decideBot[2]) / 2 + (W.minSpin + 0.6) + brake + T.landPause + T.effect + T.between
	local humanTurn = P.humanDecideSec + P.humanSpinSec + brake + T.landPause + T.effect + T.between
	-- the human plays roughly 1 of every (n/2) turns: the average table shrinks as people drop out
	local share = math.min(1, 2 / s.n)
	local turn = botTurn * (1 - share) + humanTurn * share
	local span = s.turns * turn + s.elims * T.elimination
	local survived = s.place <= 1 or s.elimTurn >= s.turns
	local mine = if survived then span + T.ending else span * (s.elimTurn / math.max(1, s.turns)) + P.leaveAfterElimSec
	local countdown = if first then 4 else T.countdown
	return P.walkSec + countdown + T.intro + mine
end

---------------------------------------------------------------------------
-- Player simulation
---------------------------------------------------------------------------
local COIN_ITEMS = {}
for _, it in Config.Cosmetics do
	if it.unlock.type == "coins" then
		table.insert(COIN_ITEMS, it)
	end
end
table.sort(COIN_ITEMS, function(a, b)
	return (a.unlock.n :: number) < (b.unlock.n :: number)
end)

export type Beat = { t: number, kind: string, what: string }

-- days: how many days to simulate. Returns the run summary (see bottom).
function Model.run(seed: number, days: number): { [string]: any }
	local P = Model.PARAMS
	local pool = getPools()
	local rng = Rng.new(seed * 131 + 7)
	local S = {
		coins = 0, level = 1, xp = 0, wins = 0, matches = 0, streak = 0, bestStreak = 0,
		trophies = 0, bestTrophies = 0, charges = 0, taps = 0, dailyStreak = 0, lastDay = -2,
		owned = {}, sp = SeasonPass.fresh(1), seasonDay = nil, coinsSpent = 0,
	}
	for _, it in Config.Cosmetics do
		if it.unlock.type == "default" then
			S.owned[it.id] = true
		end
	end
	local beats: { Beat } = {}
	local M = {} -- milestones (absolute play seconds since install unless noted)
	local clock = 0 -- seconds since install (play time, sessions back to back with day gaps)
	local dayStartOf = function(d: number) return d * 86400 end
	local now = 0 -- absolute seconds (install = 0)
	local function mark(name: string)
		if M[name] == nil then
			M[name] = now
		end
	end
	local function beat(kind: string, what: string)
		table.insert(beats, { t = now, kind = kind, what = what })
	end
	local function grantItem(id: string, why: string): boolean
		if S.owned[id] then
			return false
		end
		S.owned[id] = true
		beat("cosmetic", id .. " (" .. why .. ")")
		mark("firstCosmetic")
		return true
	end
	local function addCoins(n: number)
		S.coins += n
		mark("firstCoins")
	end
	local function addXp(n: number)
		local before = S.level
		local level, xp, gained = Progression.addXp(S.level, S.xp, n)
		for l = before + 1, level do
			addCoins(Progression.levelUpCoins(l))
		end
		S.level, S.xp = level, xp
		if gained > 0 then
			beat("level", "L" .. level)
			mark("level" .. level)
		end
	end
	local function reward(r: { kind: string, amount: number, item: string? }, why: string)
		if r.kind == "coins" then
			addCoins(r.amount)
		elseif r.kind == "xp" then
			addXp(r.amount)
		elseif r.kind == "item" then
			if not grantItem(r.item :: string, why) then
				addCoins(r.amount)
			end
		end
	end
	local function unlocks()
		local ctx = { level = S.level, wins = S.wins, bestStreak = S.bestStreak, bestTrophies = S.bestTrophies, passes = {} }
		for _, it in Config.Cosmetics do
			local t = it.unlock.type
			if not S.owned[it.id] and (t == "level" or t == "wins" or t == "streak" or t == "league") and Progression.unlocked(it.unlock, ctx) then
				grantItem(it.id, t)
			end
		end
		local _, li = Progression.league(S.bestTrophies)
		if li > 1 then
			mark("league" .. Config.Leagues[li].id)
		end
		if S.charges >= Config.Core.auraAtCharges then
			grantItem("a_core", "core")
		end
	end
	local function shop()
		-- policy: buy the cheapest coin cosmetic you can afford
		local bought = true
		while bought do
			bought = false
			for _, it in COIN_ITEMS do
				if not S.owned[it.id] and S.coins >= it.unlock.n then
					S.coins -= it.unlock.n
					S.coinsSpent += it.unlock.n
					S.bought = (S.bought or 0) + 1
					if M.firstPurchase == nil then
						M.firstPurchaseMatch = S.matches
					end
					mark("firstPurchase")
					if S.bought == 3 then
						mark("purchase3")
					end
					grantItem(it.id, "coins " .. it.unlock.n)
					bought = true
					break
				end
			end
		end
		if S.bought and S.bought == #COIN_ITEMS then
			mark("shopDone")
		end
	end
	local function tiers()
		local tier = SeasonPass.tier(S.sp.points)
		for t = 1, tier do
			if SeasonPass.canClaim(S.sp, "free", t) then
				S.sp.claimed[SeasonPass.key("free", t)] = true
				beat("tier", "T" .. t)
				mark("tier" .. t)
				reward(SeasonPass.reward("free", t) :: any, "season")
			end
		end
	end
	local function settle()
		unlocks()
		tiers()
		shop()
	end

	for day = 0, days - 1 do
		local minutes = if day == 0 then P.firstSessionMin else P.dailyMin
		local limit = minutes * 60
		local t0 = dayStartOf(day)
		local elapsed = 0
		now = t0
		S.giftsClaimed = {}
		-- daily reward (one press on login)
		S.dailyStreak = if S.lastDay == day - 1 then S.dailyStreak + 1 else 1
		S.lastDay = day
		local dayIndex = (S.dailyStreak - 1) % #Config.DailyRewards + 1
		now = t0 + P.loadSec
		reward(Config.DailyRewards[dayIndex], "daily")
		beat("daily", "day " .. dayIndex)
		-- daily quests: progress[i]
		local quests = Quests.forDay(day)
		local qprog, qdone, qclaimed = {}, {}, 0
		for i = 1, #quests do
			qprog[i] = 0
		end
		local function questAdd(kind: string, n: number)
			for i, q in quests do
				if q.kind == kind and not qdone[i] then
					qprog[i] += n
					if qprog[i] >= q.target then
						qdone[i] = true
						qclaimed += 1
						addCoins(q.coins)
						addXp(q.xp)
						beat("quest", kind)
						if qclaimed == #quests then
							addCoins(Config.QuestBonus.coins)
							addXp(Config.QuestBonus.xp)
						end
					end
				end
			end
		end
		-- first session: tap the Power Core by hand right away
		if day == 0 then
			now = t0 + P.loadSec
			local tapSec = Config.Core.tapsPerCharge / P.humanTapsPerSec
			now = t0 + P.loadSec + tapSec
			S.charges += 1
			S.taps += Config.Core.tapsPerCharge
			addCoins(Config.Core.coinsPerCharge)
			M.firstCoreCoin = now
			questAdd("charge", Config.Core.tapsPerCharge)
			elapsed = P.loadSec + tapSec
		end
		settle()
		local first = S.matches == 0
		while elapsed < limit do
			-- pick a mode: chase an open chaos/teams quest, otherwise by weight
			local modeId = nil
			for i, q in quests do
				if not qdone[i] and (q.kind == "chaos" or q.kind == "teams") then
					modeId = q.kind
				end
			end
			if not modeId then
				local r, acc = rng.next(), 0
				for id, w in Model.PARAMS.modeWeights do
					acc += w
					if r <= acc and not modeId then
						modeId = id
					end
				end
				modeId = modeId or "classic"
			end
			local list = pool[modeId]
			local s = list[rng.int(1, #list)]
			-- lobby part: tap the core while walking / waiting
			local lobby = P.walkSec + (if first then 4 else Config.Timing.countdown)
			local rate = if S.level >= Config.Core.autoUnlockLevel then Config.Core.autoRate else P.lobbyTapsPerSec
			local taps = lobby * rate
			local dur = Model.matchSeconds(s, first)
			elapsed += dur
			now = t0 + elapsed
			if elapsed > limit + 600 then
				break
			end
			-- core charges made in the lobby
			S.taps += taps
			local newCharges = math.floor(S.taps / Config.Core.tapsPerCharge) - S.charges
			if newCharges > 0 then
				S.charges += newCharges
				addCoins(newCharges * Config.Core.coinsPerCharge)
				questAdd("charge", taps)
			end
			-- session gifts (claimed when the player looks at the HUD: match end)
			for gi, g in Config.Gifts do
				if not S.giftsClaimed[gi] and elapsed >= g.minutes * 60 then
					S.giftsClaimed[gi] = true
					reward(g.reward, "gift")
					beat("gift", g.minutes .. " min")
				end
			end
			-- match rewards (real formulas)
			local humans = if rng.next() < P.pHumanTable then 2 else 1
			local won = s.place == 1
			local r = Progression.matchRewards(modeId, s.place, s.n, { coin = 1, xp = 1, streak = if won then S.streak else 0, humans = humans })
			S.matches += 1
			mark("match" .. S.matches)
			if won then
				S.wins += 1
				S.streak += 1
				S.bestStreak = math.max(S.bestStreak, S.streak)
			else
				S.streak = 0
			end
			addCoins(r.coins)
			S.trophies += r.trophies
			S.bestTrophies = math.max(S.bestTrophies, S.trophies)
			addXp(r.xp)
			SeasonPass.addPoints(S.sp, SeasonPass.matchPoints(s.place, s.n, humans))
			questAdd("play", 1)
			if won then
				questAdd("win", 1)
			end
			if s.place <= 3 and s.n >= 4 then
				questAdd("top3", 1)
			end
			questAdd("zaps", s.stats.zaps)
			questAdd("cards", s.stats.cards)
			questAdd("elims", s.stats.elims)
			questAdd("spins", s.stats.spins)
			if modeId == "chaos" or modeId == "teams" then
				questAdd(modeId, 1)
			end
			if first then
				first = false
				addCoins(Config.Tutorial.coins)
				grantItem(Config.Tutorial.item, "tutorial")
			end
			settle()
			if SeasonPass.tier(S.sp.points) >= Config.SeasonPass.tiers then
				M.seasonDay = M.seasonDay or (day + 1)
			end
		end
		if day == 0 then
			M.matchesDay0 = S.matches
		end
		-- end of the day: store the checkpoint values
		if day == 6 or day == 29 or day == 89 then
			M["level_d" .. (day + 1)] = S.level
			M["owned_d" .. (day + 1)] = 0
			for _, v in S.owned do
				M["owned_d" .. (day + 1)] += 1
			end
			M["trophies_d" .. (day + 1)] = S.trophies
		end
	end
	M.matches = S.matches
	M.ownedTotal = 0
	for _ in S.owned do
		M.ownedTotal += 1
	end
	M.beats = beats
	M.seasonPoints = S.sp.points
	return M
end

---------------------------------------------------------------------------
-- Aggregates over many seeded players
---------------------------------------------------------------------------
-- Longest stretch (seconds) with no beat of the given kinds, inside the first `window`
-- seconds. The stretch that crosses the window end is measured up to the next beat.
function Model.maxGap(beats: { Beat }, kinds: { [string]: boolean }, window: number): number
	local last, worst = 0, 0
	for _, b in beats do
		if kinds[b.kind] then
			if last >= window then
				break
			end
			worst = math.max(worst, b.t - last)
			last = b.t
		end
	end
	return worst
end

local function percentile(list: { number }, p: number): number?
	if #list == 0 then
		return nil
	end
	table.sort(list)
	return list[math.clamp(math.ceil(p * #list), 1, #list)]
end
Model.percentile = percentile

-- Runs `runs` players; returns stats per metric: { median, p10, p90, n }.
function Model.study(runs: number, days: number): { [string]: { median: number?, p10: number?, p90: number?, n: number } }
	local raw: { [string]: { number } } = {}
	local function add(k: string, v: number?)
		if v ~= nil then
			raw[k] = raw[k] or {}
			table.insert(raw[k], v)
		end
	end
	local any = Model.PARAMS
	for seed = 1, runs do
		local M = Model.run(seed, days)
		for k, v in M do
			if type(v) == "number" then
				add(k, v)
			end
		end
		add("gapAny60", Model.maxGap(M.beats, { cosmetic = true, level = true, tier = true, gift = true, quest = true, daily = true }, 3600))
		add("gapItem60", Model.maxGap(M.beats, { cosmetic = true, level = true, tier = true }, 3600))
		add("gapAny600", Model.maxGap(M.beats, { cosmetic = true, level = true, tier = true, gift = true, quest = true, daily = true }, 600))
	end
	local out = {}
	for k, list in raw do
		out[k] = { median = percentile(list, 0.5), p10 = percentile(list, 0.1), p90 = percentile(list, 0.9), n = #list }
	end
	return out
end

return Model
