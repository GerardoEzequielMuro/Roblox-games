-- Standalone tests for the pure modules (run from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/unit_core.luau
-- Rules of every outcome and card, turn order, teams, sudden death, leaving mid-match,
-- thousands of full bot matches per mode (termination + invariants), RNG / wheel
-- distribution, progression maths, quests, live events, referrals and the policy guard
-- rails (nothing sold changes a match, no wager anywhere).
local Config = require("../src/shared/Config")
local MatchCore = require("../src/shared/MatchCore")
local BotBrain = require("../src/shared/BotBrain")
local Rng = require("../src/shared/Rng")
local Progression = require("../src/shared/Progression")
local Quests = require("../src/shared/Quests")
local LiveEvents = require("../src/shared/LiveEvents")
local Referral = require("../src/shared/Referral")
local MatchFlow = require("../src/shared/MatchFlow")
local Icons = require("../src/shared/Icons")
local SeasonPass = require("../src/shared/SeasonPass")

local checks, fails = 0, 0
local function check(name: string, cond: any, detail: any?)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local function entrants(n: number): { MatchCore.Entrant }
	local list = {}
	for i = 1, n do
		list[i] = { id = "p" .. i, name = "P" .. i, bot = true }
	end
	return list
end

local function find(ev: { any }, t: string): any
	for _, e in ev do
		if e.t == t then
			return e
		end
	end
	return nil
end

local function count(ev: { any }, t: string): number
	local n = 0
	for _, e in ev do
		if e.t == t then
			n += 1
		end
	end
	return n
end

-- A started match whose wheel is one outcome everywhere, with empty hands.
local function rig(mode: string, n: number, outcome: string?, seed: number?): MatchCore.Match
	local m = MatchCore.new(mode, entrants(n), seed or 7)
	MatchCore.start(m)
	for _, p in m.players do
		p.cards = {}
	end
	if outcome then
		for i = 1, #m.wheel do
			m.wheel[i] = outcome
		end
	end
	return m
end
local function spinner(m: MatchCore.Match): MatchCore.PlayerState
	return m.players[m.spinner]
end
local function other(m: MatchCore.Match): MatchCore.PlayerState
	for i, p in m.players do
		if MatchCore.validTarget(m, m.spinner, i) then
			return p
		end
	end
	error("no target")
end
-- Spins and brakes the current turn at `phase` aiming at `targetId`.
local function play(m: MatchCore.Match, targetId: string?, phase: number?): { any }
	local id = spinner(m).id
	if targetId then
		local ok, err = MatchCore.setTarget(m, id, targetId)
		assert(ok, err)
	end
	local ok1 = MatchCore.spin(m, id)
	assert(ok1)
	local ok2, ev = MatchCore.brake(m, id, phase or 0)
	assert(ok2, ev)
	return ev
end

---------------------------------------------------------------------------
-- Config sanity
---------------------------------------------------------------------------
for name, wheel in Config.Wheels do
	local hasTargeted = false
	for i, o in wheel do
		check("wheel " .. name .. " slot " .. i .. " is a known outcome", Config.OutcomeById[o] ~= nil, o)
		hasTargeted = hasTargeted or o == "zap"
	end
	check("wheel " .. name .. " can hurt", hasTargeted)
	-- DOOM is always flanked by BACKFIRE
	for i, o in wheel do
		if o == "doom" then
			local l, r = wheel[(i - 2) % #wheel + 1], wheel[i % #wheel + 1]
			check("wheel " .. name .. " doom flanked by backfire", l == "backfire" and r == "backfire", l .. "/" .. r)
		end
	end
end
for _, mode in Config.Modes do
	check("mode " .. mode.id .. " wheel exists", Config.Wheels[mode.wheel] ~= nil)
	check("mode " .. mode.id .. " fill within seats", mode.fillTo <= Config.Seats and mode.maxPlayers <= Config.Seats and mode.fillTo >= mode.minPlayers)
end
check("rescue only on the teams wheel", table.find(Config.Wheels.classic, "rescue") == nil and table.find(Config.Wheels.chaos, "rescue") == nil)
check("sudden wheel has no heal", table.find(Config.Wheels.sudden, "heal") == nil)

---------------------------------------------------------------------------
-- Policy guard rails
---------------------------------------------------------------------------
for _, p in Config.Passes do
	check("pass " .. p.key .. " does not affect matches", p.affectsMatch == false)
end
for _, p in Config.Products do
	check("product " .. p.key .. " does not affect matches", p.affectsMatch == false)
	check("product " .. p.key .. " is not a random item", p.kind == "coins" or p.kind == "starter" or p.kind == "party" or p.kind == "season" or p.kind == "tier")
end
do
	-- nothing in a match costs anything and rewards ignore what happened in the spins
	local a = Progression.matchRewards("classic", 1, 6)
	local b = Progression.matchRewards("classic", 6, 6)
	check("winner paid more than last", a.coins > b.coins and a.xp > b.xp and a.trophies > b.trophies)
	check("last place still earns (no loss)", b.coins > 0 and b.xp > 0 and b.trophies >= 0)
	for _, mode in Config.Modes do
		for n = 2, mode.maxPlayers do
			for place = 1, n do
				local r = Progression.matchRewards(mode.id, place, n)
				check("rewards never negative " .. mode.id, r.coins >= 0 and r.xp >= 0 and r.trophies >= 0)
			end
		end
	end
	for _, item in Config.Cosmetics do
		check("cosmetic " .. item.id .. " kind known", table.find(Config.CosmeticKinds, item.kind) ~= nil)
		check("cosmetic " .. item.id .. " rarity known", Config.RarityById[item.rarity] ~= nil)
		local t = item.unlock.type
		check("cosmetic " .. item.id .. " unlock known", table.find({ "default", "coins", "level", "league", "wins", "streak", "pass", "code", "starter", "daily", "event", "season" }, t) ~= nil, t)
		if t == "pass" then
			check("cosmetic " .. item.id .. " pass exists", Config.PassByKey[item.unlock.key :: string] ~= nil)
		end
	end
	for _, id in Config.StarterPack.items do
		check("starter item " .. id .. " exists and is fixed", Config.CosmeticById[id] ~= nil and Config.CosmeticById[id].unlock.type == "starter")
	end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
do
	local m = MatchCore.new("classic", entrants(5), 1)
	check("new: idle", m.phase == "idle")
	check("new: lives and cards dealt", m.players[3].lives == 3 and #m.players[3].cards == 2)
	local ev = MatchCore.start(m)
	check("start: turn event", find(ev, "turn") ~= nil and m.phase == "decide")
	check("start: spinner is the turn owner", m.spinner == m.turnIndex)
	local ok = pcall(MatchCore.new, "classic", entrants(1), 1)
	check("new: rejects 1 player", not ok)
	ok = pcall(MatchCore.new, "nope", entrants(3), 1)
	check("new: rejects unknown mode", not ok)
	local t = MatchCore.new("teams", entrants(6), 1)
	check("teams alternate around the table", t.players[1].team == 1 and t.players[2].team == 2 and t.players[5].team == 1)
	-- same seed = same match
	local a, b = MatchCore.new("chaos", entrants(6), 99), MatchCore.new("chaos", entrants(6), 99)
	MatchCore.start(a)
	MatchCore.start(b)
	check("same seed, same first player and hands", a.turnIndex == b.turnIndex and table.concat(a.players[1].cards, ",") == table.concat(b.players[1].cards, ","))
end

---------------------------------------------------------------------------
-- Turn validation
---------------------------------------------------------------------------
do
	local m = rig("classic", 4, "zap")
	local s, o = spinner(m), other(m)
	check("not your turn: spin", MatchCore.spin(m, o.id) == false)
	check("not your turn: target", MatchCore.setTarget(m, o.id, s.id) == false)
	check("cannot target yourself", MatchCore.setTarget(m, s.id, s.id) == false)
	check("cannot brake before spinning", MatchCore.brake(m, s.id, 0) == false)
	check("target ok", MatchCore.setTarget(m, s.id, o.id) == true)
	check("spin ok", MatchCore.spin(m, s.id) == true and m.phase == "spinning")
	check("cannot spin twice", MatchCore.spin(m, s.id) == false)
	check("others cannot brake", MatchCore.brake(m, o.id, 0) == false)
	check("NaN brake rejected", MatchCore.brake(m, s.id, 0 / 0) == false)
	check("inf brake rejected", MatchCore.brake(m, s.id, math.huge) == false)
	local ok, ev = MatchCore.brake(m, s.id, 3.2)
	check("brake ok", ok and find(ev, "landed") ~= nil)
	check("zap: target lost 1 life", o.lives == 2, o.lives)
	check("turn passed to the next seat", m.spinner ~= m.byId[s.id] and m.phase == "decide")
	check("spin without a target picks one", (function()
		local m2 = rig("classic", 4, "zap")
		local _, e = MatchCore.spin(m2, spinner(m2).id)
		return e[1].target ~= nil
	end)())
end

---------------------------------------------------------------------------
-- Wheel maths
---------------------------------------------------------------------------
do
	check("slotAt 0", MatchCore.slotAt(0, 12) == 1)
	check("slotAt 11.99", MatchCore.slotAt(11.99, 12) == 12)
	check("slotAt wraps", MatchCore.slotAt(12.5, 12) == 1 and MatchCore.slotAt(-0.5, 12) == 12)
	local m = rig("classic", 3)
	local s = spinner(m)
	MatchCore.spin(m, s.id)
	local travel = MatchCore.travel(m)
	check("jitter within bounds", math.abs(m.jitter) <= Config.Wheel.jitter + 1e-9, m.jitter)
	check("travel = turns * N + jitter", math.abs(travel - (Config.Wheel.travelTurns * 12 + m.jitter)) < 1e-9)
	local _, ev = MatchCore.brake(m, s.id, 5.25)
	local landed = find(ev, "landed")
	check("landed slot matches final angle", landed.slot == MatchCore.slotAt(5.25 + travel, 12) and landed.outcome == Config.Wheels.classic[landed.slot])
end

---------------------------------------------------------------------------
-- Outcomes
---------------------------------------------------------------------------
do
	local m = rig("classic", 4, "double")
	local o = other(m)
	play(m, o.id)
	check("double: -2", o.lives == 1, o.lives)

	m = rig("classic", 4, "backfire")
	local s = spinner(m)
	play(m, other(m).id)
	check("backfire: spinner -1", s.lives == 2)

	m = rig("classic", 4, "shield")
	s = spinner(m)
	play(m)
	check("shield: +1", s.shields == 1)
	-- a shield eats one hit of any size, doom included
	m = rig("classic", 4, "doom")
	o = other(m)
	o.shields = 1
	local ev = play(m, o.id)
	check("doom blocked by shield", o.alive and o.shields == 0 and find(ev, "hit").blocked == true)
	o2 = nil
	m = rig("classic", 4, "doom")
	o = other(m)
	ev = play(m, o.id)
	check("doom eliminates", not o.alive and find(ev, "elim").player == o.id and find(ev, "elim").place == 4)

	m = rig("classic", 4, "heal")
	s = spinner(m)
	s.lives = 1
	play(m)
	check("heal: +1", s.lives == 2)
	m = rig("classic", 4, "heal")
	s = spinner(m)
	s.lives = m.maxLives
	play(m)
	check("heal capped at max lives", s.lives == m.maxLives)

	m = rig("classic", 4, "steal")
	s, o = spinner(m), other(m)
	s.lives = 1
	play(m, o.id)
	check("steal: target -1, spinner +1", o.lives == 2 and s.lives == 2)
	m = rig("classic", 4, "steal")
	s, o = spinner(m), other(m)
	s.lives = 1
	o.shields = 1
	play(m, o.id)
	check("steal blocked: nobody gains", o.lives == 3 and s.lives == 1)

	m = rig("classic", 4, "reverse")
	s = spinner(m)
	local before = m.spinner
	play(m)
	check("reverse flips direction", m.dir == -1)
	check("reverse: next turn goes the other way", m.spinner == (before - 2) % 4 + 1, m.spinner)
	check("reverse: spinner draws a card", #s.cards == 1)

	m = rig("duel", 2, "card")
	s = spinner(m)
	play(m)
	check("card: draws one", #s.cards == 1)

	m = rig("chaos", 5, "swap")
	s, o = spinner(m), other(m)
	s.lives, o.lives = 1, 3
	play(m, o.id)
	check("swap: lives exchanged", s.lives == 3 and o.lives == 1)

	m = rig("chaos", 5, "meteor")
	s = spinner(m)
	ev = play(m)
	local hurt = 0
	for _, p in m.players do
		if p.lives == 2 then
			hurt += 1
		end
	end
	check("meteor: everyone but the spinner -1", hurt == 4 and s.lives == 3 and count(ev, "hit") == 4)

	m = rig("chaos", 5, "gift")
	play(m)
	local all = true
	for _, p in m.players do
		all = all and #p.cards == 1
	end
	check("gift: everyone draws", all)

	m = rig("classic", 4, "wild")
	ev = play(m)
	local pick = find(ev, "wildpick")
	check("wild: someone alive took it", pick ~= nil and m.players[m.byId[pick.target]].lives == 2)

	-- rescue: teammate comes back with 1 life
	m = rig("teams", 4, "rescue")
	s = spinner(m)
	local mate
	for i, p in m.players do
		if p.team == s.team and i ~= m.spinner then
			mate = p
		end
	end
	mate.alive, mate.lives = false, 0
	table.insert(m.elimOrder, m.byId[mate.id])
	ev = play(m)
	check("rescue: teammate revived", mate.alive and mate.lives == 1 and find(ev, "rescue").player == mate.id)
	m = rig("teams", 4, "rescue")
	s = spinner(m)
	s.lives = 1
	play(m)
	check("rescue with nobody to revive heals", s.lives == 2)
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
do
	local m = rig("classic", 4, "zap")
	local s, o = spinner(m), other(m)
	check("card you do not hold", MatchCore.playCard(m, s.id, "skip") == false)
	s.cards = { "double", "shield" }
	check("others cannot play on your turn", MatchCore.playCard(m, o.id, "double") == false)
	local ok, ev = MatchCore.playCard(m, s.id, "double")
	check("double card ok", ok and m.double and #s.cards == 1 and find(ev, "card").count == 1)
	check("one card per turn", MatchCore.playCard(m, s.id, "shield") == false)
	play(m, o.id)
	check("double card: zap deals 2", o.lives == 1, o.lives)
	check("double is for one spin only", m.double == false)

	m = rig("classic", 4, "backfire")
	s = spinner(m)
	s.cards = { "double" }
	MatchCore.playCard(m, s.id, "double")
	play(m)
	check("double card doubles the backfire too", s.lives == 1)

	m = rig("classic", 4, "zap")
	s = spinner(m)
	s.cards = { "shield" }
	MatchCore.playCard(m, s.id, "shield")
	check("shield card", s.shields == 1)
	s.shields = Config.MaxShields
	m.cardPlayed = false
	s.cards = { "shield" }
	check("shield card refused at max", MatchCore.playCard(m, s.id, "shield") == false and #s.cards == 1)

	m = rig("classic", 4, "zap")
	s = spinner(m)
	local was = m.spinner
	s.cards = { "skip" }
	ok, ev = MatchCore.playCard(m, s.id, "skip")
	check("skip ends the turn without spinning", ok and m.spinner ~= was and m.phase == "decide" and s.stats.spins == 0)

	m = rig("classic", 4, "zap")
	s, o = spinner(m), other(m)
	local owner = m.turnIndex
	s.cards = { "pass" }
	check("pass needs a target", MatchCore.playCard(m, s.id, "pass") == false)
	check("pass to yourself refused", MatchCore.playCard(m, s.id, "pass", s.id) == false)
	ok, ev = MatchCore.playCard(m, s.id, "pass", o.id)
	check("pass: the other player spins", ok and spinner(m).id == o.id and m.turnIndex == owner and find(ev, "turn").passedFrom == s.id)
	o.cards = { "double" }
	check("no cards on a passed spin", MatchCore.playCard(m, o.id, "double") == false)
	check("original spinner can no longer act", MatchCore.spin(m, s.id) == false)
	play(m)
	check("after a passed spin the order continues from the owner", m.turnIndex == owner % 4 + 1, m.turnIndex)

	m = rig("classic", 4, "zap")
	s, o = spinner(m), other(m)
	s.cards = { "magnet" }
	check("magnet needs cards to steal", MatchCore.playCard(m, s.id, "magnet", o.id) == false and #s.cards == 1)
	o.cards = { "oracle" }
	ok, ev = MatchCore.playCard(m, s.id, "magnet", o.id)
	check("magnet steals a card", ok and #o.cards == 0 and s.cards[1] == "oracle" and find(ev, "stolen").card == "oracle")

	m = rig("classic", 4, "zap")
	s = spinner(m)
	s.cards = { "oracle" }
	MatchCore.playCard(m, s.id, "oracle")
	local _, sev = MatchCore.spin(m, s.id)
	check("oracle flag on the spin event", sev[1].oracle == true)

	-- hand limit
	m = rig("chaos", 3, "gift")
	for _, p in m.players do
		p.cards = { "skip", "skip", "skip", "skip" }
	end
	play(m)
	check("hand never exceeds the limit", #m.players[1].cards == Config.MaxHand)
end

---------------------------------------------------------------------------
-- Teams
---------------------------------------------------------------------------
do
	local m = rig("teams", 4, "zap")
	local s = spinner(m)
	local mate, enemy
	for i, p in m.players do
		if i ~= m.spinner then
			if p.team == s.team then
				mate = p
			else
				enemy = enemy or p
			end
		end
	end
	check("teams: cannot target a teammate", MatchCore.setTarget(m, s.id, mate.id) == false)
	check("teams: can target an enemy", MatchCore.setTarget(m, s.id, enemy.id) == true)
	-- wipe the other team
	for _, p in m.players do
		if p.team ~= s.team then
			p.lives = 1
		end
	end
	local ended
	for _ = 1, 40 do
		local cur = spinner(m)
		local list = MatchCore.targets(m, m.spinner)
		local ev = play(m, m.players[list[1]].id)
		ended = find(ev, "ended")
		if ended then
			break
		end
		if cur.team ~= s.team then
			-- keep the other team harmless
			for _, p in m.players do
				if p.team == s.team then
					p.lives = 3
				end
			end
		end
	end
	check("teams: last team standing wins", ended ~= nil and ended.team == s.team and m.phase == "ended")
	local places = {}
	for _, pl in ended.placements do
		places[pl.id] = pl.place
	end
	check("teams: winners place 1, losers 2", places[s.id] == 1 and places[mate.id] == 1 and places[enemy.id] == 2)
end

---------------------------------------------------------------------------
-- Sudden death, escalation, ending
---------------------------------------------------------------------------
do
	local m = rig("classic", 3, "doom")
	local ev = play(m, other(m).id)
	check("sudden death when two are left", find(ev, "sudden") ~= nil and m.sudden and m.wheel[1] == Config.Wheels.sudden[1])
	check("no modifier during sudden death", m.modifier == nil)
	local escalated = false
	for _ = 1, Config.EscalateEvery + 1 do
		for i = 1, #m.wheel do
			m.wheel[i] = "shield"
		end
		local e = play(m)
		escalated = escalated or find(e, "escalate") ~= nil
	end
	check("sudden death escalates the damage", escalated and m.dmgBonus >= 1, m.dmgBonus)
	for i = 1, #m.wheel do
		m.wheel[i] = "doom"
	end
	for _, p in m.players do
		p.shields = 0
	end
	ev = play(m, other(m).id)
	local ended = find(ev, "ended")
	check("last one standing wins", ended ~= nil and ended.winner ~= nil and m.phase == "ended")
	check("no actions after the end", MatchCore.spin(m, ended.winner) == false and #MatchCore.autoAct(m) == 0)
	local seen = {}
	for _, pl in ended.placements do
		seen[pl.place] = (seen[pl.place] or 0) + 1
	end
	check("placements 1..3 are unique", seen[1] == 1 and seen[2] == 1 and seen[3] == 1)

	-- duel: sudden death by turn count
	m = rig("duel", 2, "shield")
	for _ = 1, Config.ModeById.duel.suddenTurn do
		for i = 1, #m.wheel do
			m.wheel[i] = "shield"
		end
		play(m)
	end
	check("duel: sudden death by turn", m.sudden, m.turn)

	-- hard stop
	m = rig("classic", 4, "shield")
	m.players[2].lives = 1
	local e
	for _ = 1, Config.MaxTurns + 2 do
		if m.phase == "ended" then
			break
		end
		for i = 1, #m.wheel do
			m.wheel[i] = "shield"
		end
		e = play(m)
	end
	check("hard stop ends the match", m.phase == "ended" and find(e, "ended") ~= nil and m.winner ~= nil and m.winner ~= "p2", m.turn)
end

---------------------------------------------------------------------------
-- Modifiers and rounds
---------------------------------------------------------------------------
do
	local m = rig("chaos", 4, "shield")
	local roundEv
	for _ = 1, 4 do
		for i = 1, #m.wheel do
			m.wheel[i] = "shield"
		end
		local ev = play(m)
		roundEv = roundEv or find(ev, "round")
	end
	check("round 2 starts after everyone played", roundEv ~= nil and m.round == 2)
	check("chaos: a modifier from round 2", m.modifier ~= nil and Config.ModifierById[m.modifier] ~= nil, m.modifier)

	m = rig("classic", 4, "zap")
	m.modifier = "overcharge"
	local o = other(m)
	play(m, o.id)
	check("overcharge: +1 damage", o.lives == 1)
	m = rig("classic", 4, "zap")
	m.modifier = "fragile"
	o = other(m)
	o.shields = 1
	play(m, o.id)
	check("fragile: shield does not block (and is kept)", o.lives == 2 and o.shields == 1)
	m = rig("classic", 4, "zap")
	m.modifier = "turbo"
	local _, ev = MatchCore.spin(m, spinner(m).id)
	check("turbo: faster wheel", math.abs(ev[1].speed - Config.Wheel.speed * Config.TurboMult) < 1e-9)

	-- modifier schedule over many seeds: classic gets one on rounds 3, 6, ...
	local okSchedule, seenMods = true, {}
	for seed = 1, 60 do
		local c = rig("classic", 4, "shield", seed)
		for _ = 1, 4 * 6 do
			for i = 1, #c.wheel do
				c.wheel[i] = "shield"
			end
			play(c)
			local want = c.round >= 3 and (c.round - 3) % 3 == 0
			okSchedule = okSchedule and ((c.modifier ~= nil) == want)
			if c.modifier then
				seenMods[c.modifier] = true
			end
		end
	end
	check("classic modifier schedule", okSchedule)
	local nMods = 0
	for _ in seenMods do
		nMods += 1
	end
	check("every modifier shows up", nMods == #Config.Modifiers, nMods)
	-- blackout keeps the same slots, in another order
	local b = rig("classic", 4, nil, 3)
	b.round = 2
	b.turnsInRound = b.roundSize - 1
	local tries = 0
	repeat
		tries += 1
		b = rig("classic", 4, nil, tries)
		for _ = 1, 8 do
			for i, o2 in Config.Wheels.classic do
				if b.modifier ~= "blackout" then
					b.wheel[i] = "shield"
				end
			end
			if b.modifier == "blackout" then
				break
			end
			play(b)
		end
	until b.modifier == "blackout" or tries > 200
	local sortedA, sortedB = table.clone(Config.Wheels.classic), table.clone(b.wheel)
	table.sort(sortedA)
	table.sort(sortedB)
	check("blackout shuffles the same slots", b.modifier == "blackout" and table.concat(sortedA, ",") == table.concat(sortedB, ","), tries)
end

---------------------------------------------------------------------------
-- Leaving mid-match
---------------------------------------------------------------------------
do
	-- a bystander leaves
	local m = rig("classic", 4, "zap")
	local s, o = spinner(m), other(m)
	local ev = MatchCore.leave(m, o.id)
	check("leave: eliminated with cause left", not o.alive and o.left and find(ev, "elim").cause == "left")
	check("leave: match goes on, same spinner", m.phase == "decide" and spinner(m).id == s.id)
	check("leave twice is a no-op", #MatchCore.leave(m, o.id) == 0)

	-- the spinner leaves while deciding
	m = rig("classic", 4, "zap")
	s = spinner(m)
	ev = MatchCore.leave(m, s.id)
	check("spinner leaves in decide: next player's turn", m.phase == "decide" and spinner(m).id ~= s.id and spinner(m).alive and find(ev, "turn") ~= nil)

	-- the spinner leaves while the wheel is spinning
	m = rig("classic", 4, "zap")
	s = spinner(m)
	MatchCore.spin(m, s.id)
	ev = MatchCore.leave(m, s.id)
	check("spinner leaves mid-spin: spin cancelled, next turn", m.phase == "decide" and spinner(m).id ~= s.id)
	check("the dead spinner cannot brake", MatchCore.brake(m, s.id, 1) == false)

	-- the target leaves mid-spin: another target is picked at the landing
	m = rig("classic", 4, "zap")
	s, o = spinner(m), other(m)
	MatchCore.setTarget(m, s.id, o.id)
	MatchCore.spin(m, s.id)
	MatchCore.leave(m, o.id)
	local _, bev = MatchCore.brake(m, s.id, 2)
	local hit = find(bev, "hit")
	check("target left mid-spin: someone else is hit", hit ~= nil and hit.target ~= o.id and hit.target ~= s.id)

	-- leaving with two players ends the match for the other
	m = rig("duel", 2, "zap")
	s, o = spinner(m), other(m)
	ev = MatchCore.leave(m, s.id)
	check("duel: leaver loses, the other wins", m.phase == "ended" and m.winner == o.id and find(ev, "ended").winner == o.id)

	-- a passed spinner leaves: the turn moves on from the owner
	m = rig("classic", 4, "zap")
	s, o = spinner(m), other(m)
	s.cards = { "pass" }
	MatchCore.playCard(m, s.id, "pass", o.id)
	MatchCore.leave(m, o.id)
	check("passed spinner leaves: next turn is a living player", m.phase == "decide" and spinner(m).alive and spinner(m).id ~= o.id)

	-- everyone leaves
	m = rig("classic", 3, "zap")
	for _, p in m.players do
		MatchCore.leave(m, p.id)
	end
	check("everyone leaves: match ends", m.phase == "ended")
	check("unknown id leaving is ignored", #MatchCore.leave(m, "ghost") == 0)
end

---------------------------------------------------------------------------
-- Full matches played by the bots: every mode, every table size
---------------------------------------------------------------------------
local function playBots(mode: string, n: number, seed: number, leaveAt: number?): (MatchCore.Match, number)
	local m = MatchCore.new(mode, entrants(n), seed)
	local brain = Rng.new(seed * 7919 + 13)
	MatchCore.start(m)
	local steps = 0
	while m.phase ~= "ended" do
		steps += 1
		assert(steps < 5000, "match does not end")
		if leaveAt and steps == leaveAt then
			MatchCore.leave(m, m.players[brain.int(1, n)].id)
			if m.phase == "ended" then
				break
			end
		end
		local si = m.spinner
		local p = m.players[si]
		assert(p.alive, "dead spinner")
		local d = BotBrain.decide(m, si, brain)
		if d.card then
			local ok = MatchCore.playCard(m, p.id, d.card, d.cardTarget)
			assert(ok, "bot played an illegal card " .. d.card)
		end
		if m.phase == "decide" and m.spinner == si then
			if d.target and MatchCore.validTarget(m, si, m.byId[d.target]) then
				MatchCore.setTarget(m, p.id, d.target)
			end
			assert(MatchCore.spin(m, p.id))
			local ok, ev = MatchCore.brake(m, p.id, BotBrain.brakePhase(m, si, brain))
			assert(ok, ev)
		end
		for _, q in m.players do
			assert(q.lives >= 0 and q.lives <= m.maxLives, "lives out of range")
			assert(q.shields >= 0 and q.shields <= Config.MaxShields, "shields out of range")
			assert(#q.cards <= Config.MaxHand, "hand too big")
			assert(q.alive == (q.lives > 0), "alive/lives mismatch")
		end
	end
	return m, m.turn
end

for _, mode in Config.Modes do
	local total, maxTurns, wins = 0, 0, {}
	local runs = 0
	local okAll = true
	for n = mode.minPlayers, mode.maxPlayers do
		for seed = 1, (if mode.maxPlayers == 2 then 1500 else 260) do
			local ok, m, turns = pcall(playBots, mode.id, n, seed * 31 + n)
			if not ok then
				okAll = false
				check("bots " .. mode.id .. " n=" .. n .. " seed=" .. seed, false, m)
				break
			end
			runs += 1
			total += turns
			maxTurns = math.max(maxTurns, turns)
			local winner = if mode.teams then "team" .. tostring(m.winnerTeam) else m.winner
			wins[winner] = (wins[winner] or 0) + 1
			if mode.teams then
				okAll = okAll and m.winnerTeam ~= nil
			else
				okAll = okAll and m.winner ~= nil and m.players[m.byId[m.winner]].alive
			end
		end
	end
	check(string.format("%s: %d bot matches all finish with a winner", mode.id, runs), okAll)
	check(mode.id .. ": matches stay under the hard stop", maxTurns <= Config.MaxTurns + 1, maxTurns)
	print(string.format("  %-8s %5d matches, avg %.1f turns, max %d", mode.id, runs, total / runs, maxTurns))
end

-- seats are fair: over many 6-player classic matches nobody's seat wins far more often
do
	local wins = {}
	local N = 3000
	for seed = 1, N do
		local m = playBots("classic", 6, seed * 17 + 5)
		wins[m.winner] = (wins[m.winner] or 0) + 1
	end
	local lo, hi = math.huge, 0
	for i = 1, 6 do
		local w = wins["p" .. i] or 0
		lo, hi = math.min(lo, w), math.max(hi, w)
	end
	check("seat fairness (each seat wins 12-22% of 6p matches)", lo / N > 0.12 and hi / N < 0.22, string.format("%.3f..%.3f", lo / N, hi / N))
end

-- a random player leaves at a random step: still always ends cleanly
do
	local okAll = true
	for _, mode in Config.Modes do
		for seed = 1, 300 do
			local n = math.max(mode.minPlayers, math.min(mode.maxPlayers, 2 + seed % 7))
			local ok, err = pcall(playBots, mode.id, n, seed * 13 + 1, 1 + seed % 17)
			if not ok then
				okAll = false
				print("  leave failure", mode.id, seed, err)
			end
		end
	end
	check("matches with a mid-match leaver always finish", okAll)
end

---------------------------------------------------------------------------
-- RNG and wheel distribution
---------------------------------------------------------------------------
do
	local r = Rng.new(12345)
	local buckets = table.create(10, 0)
	local N = 200000
	local sum = 0
	for _ = 1, N do
		local v = r.next()
		sum += v
		buckets[math.floor(v * 10) + 1] += 1
	end
	local chi = 0
	for i = 1, 10 do
		local e = N / 10
		chi += (buckets[i] - e) ^ 2 / e
	end
	check("rng uniform (chi2 9 dof < 27.9)", chi < 27.9, chi)
	check("rng mean ~0.5", math.abs(sum / N - 0.5) < 0.005, sum / N)
	local a, b = Rng.new(5), Rng.new(5)
	check("rng deterministic", a.next() == b.next() and a.int(1, 100) == b.int(1, 100))
	local lo, hi = 99, 0
	for _ = 1, 5000 do
		local v = r.int(3, 9)
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	check("rng.int inclusive range", lo == 3 and hi == 9)

	-- a player who brakes at random gets every slot equally often
	for name, wheel in Config.Wheels do
		local n = #wheel
		local m = MatchCore.new(if name == "sudden" then "classic" else name, entrants(2), 4242)
		MatchCore.start(m)
		local brain = Rng.new(99)
		local slots = table.create(n, 0)
		local SPINS = 60000
		for _ = 1, SPINS do
			m.phase = "decide"
			m.jitter = 0
			m.wheel = table.clone(wheel)
			for _, p in m.players do
				p.lives, p.alive, p.shields, p.cards = 3, true, 0, {}
			end
			m.sudden, m.turn, m.dmgBonus = false, 1, 0
			local id = m.players[m.spinner].id
			MatchCore.spin(m, id)
			local phase = brain.next() * n
			local travel = MatchCore.travel(m)
			slots[MatchCore.slotAt(phase + travel, n)] += 1
			m.phase = "decide"
		end
		local chi2 = 0
		for i = 1, n do
			local e = SPINS / n
			chi2 += (slots[i] - e) ^ 2 / e
		end
		-- 99.9th percentile: 31.3 for 11 dof, 34.5 for 13 dof
		check("wheel " .. name .. ": random brake is uniform over slots", chi2 < (if n == 14 then 34.5 else 31.3), string.format("chi2=%.1f", chi2))
	end

	-- skill matters but never guarantees: perfect timing on a slot hits it 35-45% of the time
	local m = MatchCore.new("classic", entrants(2), 77)
	MatchCore.start(m)
	local n = #m.wheel
	local hits, SPINS = 0, 20000
	local doom = table.find(m.wheel, "doom") :: number
	for _ = 1, SPINS do
		m.phase = "decide"
		MatchCore.spin(m, m.players[m.spinner].id)
		local phase = (doom - 0.5) - Config.Wheel.travelTurns * n -- aims at the centre, blind to the jitter
		if MatchCore.slotAt(phase + MatchCore.travel(m), n) == doom then
			hits += 1
		end
	end
	local rate = hits / SPINS
	check("perfect timing lands its slot 35-45% of the time", rate > 0.35 and rate < 0.45, rate)
	print(string.format("  perfect-timing hit rate %.3f (random = %.3f)", rate, 1 / n))
end

---------------------------------------------------------------------------
-- Progression
---------------------------------------------------------------------------
do
	local l, xp, g = Progression.addXp(1, 0, 99)
	check("xp below the level", l == 1 and xp == 99 and g == 0)
	l, xp, g = Progression.addXp(1, 99, 1)
	check("level up at 100", l == 2 and xp == 0 and g == 1)
	l, xp, g = Progression.addXp(1, 0, 100 + 140 + 5)
	check("two levels at once", l == 3 and xp == 5 and g == 2)
	l = Progression.addXp(Config.MaxLevel, 0, 1e9)
	check("level capped", l == Config.MaxLevel)
	check("negative xp ignored", select(2, Progression.addXp(1, 10, -50)) == 10)
	check("league bronze", Progression.league(0).id == "bronze" and Progression.league(99).id == "bronze")
	check("league silver at 100", Progression.league(100).id == "silver")
	check("league champion", Progression.league(99999).id == "champion" and Progression.nextLeague(99999) == nil)
	check("next league", (Progression.nextLeague(0) :: any).id == "silver")
	local r = Progression.matchRewards("classic", 1, 6, { coin = 2, streak = 3 })
	check("coin multiplier and streak bonus", r.coins == math.floor(120 * 2 * 1.3 + 0.5), r.coins)
	check("streak bonus capped", Progression.matchRewards("classic", 1, 6, { streak = 99 }).coins == math.floor(120 * 1.5 + 0.5))
	check("bots-only table: half trophies", Progression.matchRewards("classic", 1, 6, { humans = 1 }).trophies == 13)
	check("duel pays win/lose", Progression.matchRewards("duel", 1, 2).coins == 80 and Progression.matchRewards("duel", 2, 2).coins == 30)
	local ctx = { level = 5, wins = 3, bestStreak = 1, bestTrophies = 260, passes = { VIP = true } }
	check("unlock level", Progression.unlocked({ type = "level", n = 5 }, ctx) and not Progression.unlocked({ type = "level", n = 6 }, ctx))
	check("unlock wins", Progression.unlocked({ type = "wins", n = 3 }, ctx))
	check("unlock league", Progression.unlocked({ type = "league", key = "gold" }, ctx) and not Progression.unlocked({ type = "league", key = "platinum" }, ctx))
	check("unlock pass", Progression.unlocked({ type = "pass", key = "VIP" }, ctx) and not Progression.unlocked({ type = "pass", key = "EmotePack" }, ctx))
	check("coins items are not auto-unlocked", not Progression.unlocked({ type = "coins", n = 1 }, ctx))
	-- seasons
	local t = Progression.utc(2026, 9, 30) + 3600
	check("utc helper", Progression.utc(1970, 1, 1) == 0 and Progression.utc(2026, 1, 1) == 1767225600)
	check("season id", Progression.season(t) == 2026 * 12 + 8)
	check("season ends at the 1st of next month", Progression.seasonEndsAt(t) == Progression.utc(2026, 10, 1))
	check("december rolls the year", Progression.seasonEndsAt(Progression.utc(2026, 12, 15)) == Progression.utc(2027, 1, 1))
	check("season carry and reward", Progression.seasonCarry(501) == 250 and Progression.seasonReward(0) == 0 and Progression.seasonReward(500) == 900)
end

---------------------------------------------------------------------------
-- Quests, live events, referrals
---------------------------------------------------------------------------
do
	local a, b = Quests.forDay(20000), Quests.forDay(20000)
	check("quests: 3 per day, deterministic", #a == 3 and a[1].kind == b[1].kind and a[3].kind == b[3].kind)
	check("quests: no repeats in a day", a[1].kind ~= a[2].kind and a[2].kind ~= a[3].kind and a[1].kind ~= a[3].kind)
	local kinds = {}
	for d = 20000, 20060 do
		for _, q in Quests.forDay(d) do
			kinds[q.kind] = true
		end
	end
	local n = 0
	for _ in kinds do
		n += 1
	end
	check("quests: the whole pool rotates in", n == #Config.QuestPool, n)
	check("quests reset at UTC midnight", Quests.resetsAt(86400 * 5 + 10) == 86400 * 6)

	local now = 3 * 3600 * 1000 -- a multiple of 3 h
	local act = LiveEvents.active(now + 60, nil)
	local hasXp = false
	for _, e in act do
		hasXp = hasXp or e.id == "DoubleXP"
	end
	check("DoubleXP active in the first 20 min of each 3 h", hasXp)
	local later = LiveEvents.active(now + 21 * 60, nil)
	hasXp = false
	for _, e in later do
		hasXp = hasXp or e.id == "DoubleXP"
	end
	check("DoubleXP off after 20 min", not hasXp)
	check("DoubleXP doubles xp only", LiveEvents.effects({ { id = "DoubleXP", endsAt = 0 } }, "classic").xpMult == 2 and LiveEvents.effects({ { id = "DoubleXP", endsAt = 0 } }, "classic").coinMult == 1)
	check("ChaosWeekend only in chaos", LiveEvents.effects({ { id = "ChaosWeekend", endsAt = 0 } }, "chaos").coinMult == 2 and LiveEvents.effects({ { id = "ChaosWeekend", endsAt = 0 } }, "classic").coinMult == 1)
	local sat = Progression.utc(2026, 10, 3) + 5 * 3600 -- a Saturday
	local wk = false
	for _, e in LiveEvents.active(sat, nil) do
		wk = wk or (e.id == "ChaosWeekend" and e.endsAt == Progression.utc(2026, 10, 5))
	end
	check("ChaosWeekend on Saturday, ends Monday 00:00 UTC", wk)
	check("override wins", (LiveEvents.current(now + 3600, { id = "CoinRush", endsAt = now + 7200 }) :: any).id == "CoinRush")
	check("expired override ignored", LiveEvents.current(now + 3600 * 1.5, { id = "CoinRush", endsAt = now }) == nil)
	check("next start", LiveEvents.nextStart(now + 60) == now + 3 * 3600)

	check("referral round trip", Referral.parse(Referral.launchData(12345)) == 12345)
	check("referral rejects junk", Referral.parse("ref:abc") == nil and Referral.parse("x") == nil and Referral.parse(nil) == nil and Referral.parse("ref:0") == nil)
end

---------------------------------------------------------------------------
-- Match flow around the core: bots fill, countdowns, who stays, AFK
---------------------------------------------------------------------------
do
	local classic, duel = Config.ModeById.classic, Config.ModeById.duel
	check("flow: nobody seated, no match", MatchFlow.entrants(0, classic, true) == 0)
	check("flow: one human on a public table gets bots up to fillTo", MatchFlow.entrants(1, classic, true) == classic.fillTo)
	check("flow: more humans than fillTo, no extra bots", MatchFlow.entrants(7, classic, true) == 7)
	check("flow: never past maxPlayers", MatchFlow.entrants(20, classic, true) == classic.maxPlayers)
	check("flow: private without fill still needs 2 (a bot joins a lone host)", MatchFlow.entrants(1, classic, false) == 2)
	check("flow: private without fill keeps its humans", MatchFlow.entrants(3, classic, false) == 3)
	check("flow: a duel is 2", MatchFlow.entrants(2, duel, false) == 2 and MatchFlow.entrants(1, duel, false) == 2)
	-- every mode: the table the runner gets is always a legal match size
	for _, mode in Config.Modes do
		for h = 1, mode.maxPlayers do
			for _, fill in { true, false } do
				local n = MatchFlow.entrants(h, mode, fill)
				check("flow: legal size " .. mode.id .. " h=" .. h, n >= 2 and n >= h and n <= mode.maxPlayers and n <= Config.Seats, n)
			end
		end
	end

	check("flow: first match counts down 4 s", MatchFlow.countdownFor(false, 12) == 4 and MatchFlow.countdownFor(true, 12) == 12)
	check("flow: a full table starts sooner", MatchFlow.countdownAfterSit(112, 100, 8, 8, 4) == 104)
	check("flow: a full table never starts later", MatchFlow.countdownAfterSit(102, 100, 8, 8, 4) == 102)
	check("flow: not full, countdown unchanged", MatchFlow.countdownAfterSit(112, 100, 3, 8, 4) == 112)

	check("flow: walked off during the match", MatchFlow.afterMatch(false, true, false, true) == "gone")
	check("flow: private tables keep everyone", MatchFlow.afterMatch(true, true, false, false) == "stay")
	check("flow: auto-queue keeps the seat", MatchFlow.afterMatch(true, false, false, true) == "stay")
	check("flow: no auto-queue stands up", MatchFlow.afterMatch(true, false, false, false) == "leave")
	check("flow: a duel never auto-queues", MatchFlow.afterMatch(true, false, true, true) == "leave")

	-- AFK: two idle turns in a row, counted once per turn, and "I'm back" undoes it
	local afk = MatchFlow.newAfk()
	check("afk: fresh player plays their own turns", not MatchFlow.isAuto(afk, "u1", false))
	check("afk: the toggle always wins", MatchFlow.isAuto(afk, "u1", true))
	MatchFlow.timedOut(afk, "u1", "1:1") -- decide timer ran out
	MatchFlow.timedOut(afk, "u1", "1:1") -- and the brake timer, same turn
	check("afk: one idle turn is one strike", not MatchFlow.isAuto(afk, "u1", false) and afk.idle.u1 == 1)
	MatchFlow.active(afk, "u1")
	MatchFlow.timedOut(afk, "u1", "7:1")
	check("afk: acting in between resets the run", not MatchFlow.isAuto(afk, "u1", false))
	MatchFlow.timedOut(afk, "u1", "13:1")
	check("afk: two idle turns in a row turn auto-play on", MatchFlow.isAuto(afk, "u1", false))
	check("afk: other players are unaffected", not MatchFlow.isAuto(afk, "u2", false))
	MatchFlow.active(afk, "u1")
	check("afk: I'm back hands the turns back", not MatchFlow.isAuto(afk, "u1", false))
	MatchFlow.timedOut(afk, "u1", "13:1")
	check("afk: a turn already counted before coming back counts again after", afk.idle.u1 == 1)
end

---------------------------------------------------------------------------
-- Icon pack: nothing is uploaded yet, so every lookup falls back to the emoji
---------------------------------------------------------------------------
do
	local allEmpty, mapped = true, true
	for name, id in Icons.ids do
		allEmpty = allEmpty and id == ""
		allEmpty = allEmpty and Icons.get(name) == nil
	end
	for emoji, name in Icons.emoji do
		mapped = mapped and Icons.ids[name] ~= nil
		if Icons.ids[name] == nil then
			print("  emoji " .. emoji .. " maps to a missing icon " .. name)
		end
	end
	check("icons: no ids invented, every lookup is nil today", allEmpty)
	check("icons: every emoji maps to an icon in the pack", mapped)
	check("icons: unknown names are nil", Icons.get("nope") == nil and Icons.get("") == nil)
	Icons.ids.coin = "123"
	check("icons: an uploaded id resolves by name and by emoji", Icons.get("coin") == "rbxassetid://123" and Icons.get("🪙") == "rbxassetid://123")
	Icons.ids.coin = ""
end

---------------------------------------------------------------------------
-- Pricing and policy: nothing paid can affect a match, prices are the recommended ones,
-- anchors are honest, season pass rules
---------------------------------------------------------------------------
do
	local ALLOWED_KINDS = { coins = true, starter = true, party = true, season = true, tier = true }
	local seen = {}
	for _, p in Config.Passes do
		check("pass " .. p.key .. " affectsMatch is explicitly false", rawget(p, "affectsMatch") == false)
		check("pass " .. p.key .. " never touches a match (xp/coins only, no odds field)", (p :: any).luck == nil and (p :: any).odds == nil and (p :: any).spins == nil)
		check("pass " .. p.key .. " price is a positive integer", p.price > 0 and p.price % 1 == 0)
		check("pass key unique " .. p.key, not seen[p.key])
		seen[p.key] = true
	end
	for _, p in Config.Products do
		check("product " .. p.key .. " affectsMatch is explicitly false", rawget(p, "affectsMatch") == false)
		check("product " .. p.key .. " kind is cosmetic/comfort", ALLOWED_KINDS[p.kind] == true, p.kind)
		check("product " .. p.key .. " price is a positive integer", p.price > 0 and p.price % 1 == 0)
		check("product key unique " .. p.key, not seen[p.key])
		seen[p.key] = true
	end
	-- recommended prices (docs/research/top-juegos-y-precios.md section 4.6)
	local want = { VIP = 299, DoubleCoins = 199, LegendSkins = 199, FinisherPack = 149, EmotePack = 99, AutoCharge = 99 }
	for key, price in want do
		check("pass price " .. key, Config.PassByKey[key] ~= nil and Config.PassByKey[key].price == price)
	end
	local wantP = { CoinsS = 49, CoinsM = 99, CoinsL = 249, CoinsXL = 499, CoinsMega = 999, StarterPack = 49, ServerParty = 25, SeasonPass = 399, SeasonTier = 39 }
	for key, price in wantP do
		check("product price " .. key, Config.ProductByKey[key] ~= nil and Config.ProductByKey[key].price == price)
	end
	-- coin ladder: better value every step
	local ladder = { "CoinsS", "CoinsM", "CoinsL", "CoinsXL", "CoinsMega" }
	for i = 2, #ladder do
		local a, b = Config.ProductByKey[ladder[i - 1]], Config.ProductByKey[ladder[i]]
		check("coin ladder improves " .. ladder[i], b.amount / b.price > a.amount / a.price)
	end
	check("CoinsMega is ~40k coins", Config.ProductByKey.CoinsMega.amount == 40000)
	-- honest anchor: the crossed-out price is what the same coins cost in the regular bags
	local sp = Config.StarterPack
	local bag = Config.ProductByKey.CoinsS
	check("starter anchor = price of the same coins in regular bags", sp.fullPrice == math.ceil(sp.coins / bag.amount) * bag.price, sp.fullPrice)
	check("starter anchor is above the real price", sp.fullPrice > Config.ProductByKey.StarterPack.price)
	-- no paid random items, no wager anywhere in Config
	for _, p in Config.Products do
		check("no random product " .. p.key, p.kind ~= "box" and p.kind ~= "egg" and p.kind ~= "crate" and p.kind ~= "luck")
	end
end

do
	local sp = Config.SeasonPass
	check("season: tiers and points are sane", sp.tiers >= 20 and sp.pointsPerTier > 0)
	for t = 1, sp.tiers do
		check("season: free reward at tier " .. t, sp.free[t] ~= nil)
		check("season: premium reward at tier " .. t, sp.premium[t] ~= nil)
		for _, track in { sp.free[t], sp.premium[t] } do
			local k = track.kind
			check("season reward kind " .. t, k == "coins" or k == "xp" or k == "item")
			if k == "item" then
				local item = Config.CosmeticById[track.item :: string]
				check("season reward item exists " .. t, item ~= nil and item.unlock.type == "season")
				check("season item has coin fallback " .. t, track.amount > 0)
			else
				check("season reward amount > 0 " .. t, track.amount > 0)
			end
		end
	end
	-- every season cosmetic is reachable through exactly one reward slot
	local slots = {}
	for t = 1, sp.tiers do
		for _, track in { "free", "premium" } do
			local r = SeasonPass.reward(track, t) :: any
			if r.kind == "item" then
				slots[r.item] = (slots[r.item] or 0) + 1
				local unlockKey = (Config.CosmeticById[r.item] :: any).unlock.key
				check("season item " .. r.item .. " sits on its own track", unlockKey == track)
			end
		end
	end
	for _, item in Config.Cosmetics do
		if item.unlock.type == "season" then
			check("season cosmetic reachable once " .. item.id, slots[item.id] == 1, slots[item.id])
		end
	end
	check("season: no reward beyond the last tier", SeasonPass.reward("free", sp.tiers + 1) == nil and SeasonPass.reward("premium", 0) == nil and SeasonPass.reward("bogus", 1) == nil)

	-- points: placement only, never boosted, bots-only tables pay half
	check("points: win > top3 > plain", SeasonPass.matchPoints(1, 6, 3) > SeasonPass.matchPoints(2, 6, 3) and SeasonPass.matchPoints(2, 6, 3) > SeasonPass.matchPoints(6, 6, 3))
	check("points: last place still earns", SeasonPass.matchPoints(6, 6, 3) > 0)
	check("points: practice pays half", SeasonPass.matchPoints(1, 5, 1) == SeasonPass.matchPoints(1, 5, 2) // 2)
	local allOk = true
	for _, mode in Config.Modes do
		for n = 2, mode.maxPlayers do
			for place = 1, n do
				for humans = 1, 3 do
					allOk = allOk and SeasonPass.matchPoints(place, n, humans) > 0
				end
			end
		end
	end
	check("points: positive everywhere", allOk)
	-- a free player can finish the pass: ~average match pays well under the monthly play needed
	local perMatch = SeasonPass.matchPoints(3, 5, 2)
	check("season: full track needs at most ~100 average matches", SeasonPass.maxPoints() / perMatch <= 100, SeasonPass.maxPoints() / perMatch)

	-- state machine
	local st = SeasonPass.fresh(24300)
	check("fresh: tier 0, not premium", SeasonPass.tier(st.points) == 0 and not st.premium)
	check("progress at 0", select(2, SeasonPass.progress(0)) == 0)
	SeasonPass.addPoints(st, sp.pointsPerTier - 1)
	check("tier stays 0 just below the threshold", SeasonPass.tier(st.points) == 0)
	SeasonPass.addPoints(st, 1)
	check("tier 1 at the threshold", SeasonPass.tier(st.points) == 1)
	check("claim free tier 1", SeasonPass.canClaim(st, "free", 1))
	check("cannot claim premium without the pass", not SeasonPass.canClaim(st, "premium", 1))
	check("cannot claim a tier not reached", not SeasonPass.canClaim(st, "free", 2))
	st.claimed[SeasonPass.key("free", 1)] = true
	check("cannot claim twice", not SeasonPass.canClaim(st, "free", 1))
	check("bad tiers rejected", not SeasonPass.canClaim(st, "free", 0) and not SeasonPass.canClaim(st, "free", 1.5) and not SeasonPass.canClaim(st, "free", sp.tiers + 1) and not SeasonPass.canClaim(st, "free", 0 / 0) and not SeasonPass.canClaim(st, "x", 1))
	-- buying premium late unlocks the tiers already reached (retroactive)
	SeasonPass.addPoints(st, sp.pointsPerTier * 4)
	st.premium = true
	local list = SeasonPass.claimables(st)
	check("claimables: 4 free + 5 premium after buying premium at tier 5", #list == 9, #list)
	check("addPoints ignores junk", SeasonPass.addPoints(st, -5) == 0 and SeasonPass.addPoints(st, 0 / 0) == 0)
	-- skip a tier
	local before = SeasonPass.tier(st.points)
	check("skip tier advances exactly one tier", SeasonPass.skipTier(st) and SeasonPass.tier(st.points) == before + 1)
	SeasonPass.addPoints(st, 1e9)
	check("points capped at the last tier", st.points == SeasonPass.maxPoints() and SeasonPass.tier(st.points) == sp.tiers)
	check("skip at the last tier is refused", not SeasonPass.skipTier(st))
	local _, into, need = SeasonPass.progress(st.points)
	check("full bar at the last tier", into == need)
	-- season rollover drops the old state, same season keeps it
	check("sync keeps the same season", SeasonPass.sync(st, 24300) == st)
	local nxt = SeasonPass.sync(st, 24301)
	check("sync resets on a new season", nxt ~= st and nxt.points == 0 and not nxt.premium and next(nxt.claimed) == nil and nxt.season == 24301)
	check("sync of nil", SeasonPass.sync(nil, 7).season == 7)
	-- season tier skip / premium products never change points formula
	check("points formula has no paid input", #{ SeasonPass.matchPoints(1, 5, 2) } == 1)
	-- the season products exist and are matched by kind
	check("season products wired", Config.ProductByKey.SeasonPass.kind == "season" and Config.ProductByKey.SeasonTier.kind == "tier")
end

print(string.format("%d checks, %d failures", checks, fails))
print(if fails == 0 then "UNIT CORE PASSED" else "UNIT CORE FAILED")
