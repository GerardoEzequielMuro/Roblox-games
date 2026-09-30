--!strict
-- The match as a pure state machine. No Roblox APIs, no clocks: the server feeds it actions
-- (card, target, spin, brake, leave) and plays back the events it returns; the standalone
-- tests run thousands of full matches through the very same code.
--
-- Wheel maths (units: slots). While free-spinning the wheel angle is R(t) = R0 + speed * t.
-- The spinner brakes at angle `phase`; the wheel then travels `travelTurns * N + jitter`
-- more slots (jitter rolled here, server side, when the spin starts) and the slot under
-- the pointer is floor(final mod N) + 1. Timing the brake is a skill; the jitter keeps it
-- from being a sure thing.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")
local RngMod: typeof(require(script.Parent.Rng)) = if script then require(script.Parent.Rng) :: any else (require :: any)("./Rng")

local MatchCore = {}

type Mode = typeof(Config.Modes[1])
type RngT = typeof(RngMod.new(0))

export type Entrant = { id: string, name: string, bot: boolean, team: number? }
export type PlayerState = {
	id: string,
	name: string,
	bot: boolean,
	team: number,
	seat: number,
	lives: number,
	shields: number,
	cards: { string },
	alive: boolean,
	left: boolean,
	place: number,
	stats: { zaps: number, elims: number, cards: number, spins: number, taken: number },
}
export type Event = { [string]: any }
export type Match = {
	mode: Mode,
	players: { PlayerState },
	byId: { [string]: number },
	rng: RngT,
	phase: string, -- "idle" | "decide" | "spinning" | "ended"
	turn: number,
	round: number,
	turnsInRound: number,
	roundSize: number,
	dir: number,
	turnIndex: number, -- whose turn it is in the order
	spinner: number, -- who actually spins (differs after a Pass card)
	target: number?,
	cardPlayed: boolean,
	double: boolean,
	oracle: boolean,
	passed: boolean,
	jitter: number,
	speed: number,
	modifier: string?,
	sudden: boolean,
	suddenFrom: number,
	dmgBonus: number,
	wheel: { string },
	maxLives: number,
	startCount: number,
	elimOrder: { number },
	winner: string?,
	winnerTeam: number?,
}

local function push(ev: { Event }, e: Event)
	table.insert(ev, e)
end

local function aliveCount(m: Match): number
	local n = 0
	for _, p in m.players do
		if p.alive then
			n += 1
		end
	end
	return n
end
MatchCore.aliveCount = aliveCount

local function aliveTeams(m: Match): (number, number)
	local seen: { [number]: boolean } = {}
	local n, last = 0, 0
	for _, p in m.players do
		if p.alive and not seen[p.team] then
			seen[p.team] = true
			n += 1
			last = p.team
		end
	end
	return n, last
end

function MatchCore.validTarget(m: Match, si: number, ti: number?): boolean
	if not ti then
		return false
	end
	local s, t = m.players[si], m.players[ti]
	if not s or not t or ti == si or not t.alive then
		return false
	end
	if m.mode.teams and s.team == t.team then
		return false
	end
	return true
end

function MatchCore.targets(m: Match, si: number): { number }
	local list = {}
	for i in m.players do
		if MatchCore.validTarget(m, si, i) then
			table.insert(list, i)
		end
	end
	return list
end

local function randomTarget(m: Match, si: number): number?
	local list = MatchCore.targets(m, si)
	if #list == 0 then
		return nil
	end
	return list[m.rng.int(1, #list)]
end

local function drawCard(m: Match, p: PlayerState, ev: { Event }?): string?
	if #p.cards >= Config.MaxHand then
		return nil
	end
	local total = 0
	for _, cd in Config.Cards do
		total += cd.weight
	end
	local r = m.rng.next() * total
	local pick = Config.Cards[#Config.Cards].id
	for _, cd in Config.Cards do
		r -= cd.weight
		if r < 0 then
			pick = cd.id
			break
		end
	end
	table.insert(p.cards, pick)
	if ev then
		push(ev, { t = "draw", player = p.id, card = pick, count = #p.cards })
	end
	return pick
end

local function baseWheel(m: Match): { string }
	return table.clone(Config.Wheels[if m.sudden then "sudden" else m.mode.wheel])
end

function MatchCore.new(modeId: string, entrants: { Entrant }, seed: number): Match
	local mode = Config.ModeById[modeId]
	assert(mode, "unknown mode " .. tostring(modeId))
	assert(#entrants >= 2 and #entrants <= Config.Seats, "bad player count")
	local rng = RngMod.new(seed)
	local players: { PlayerState } = {}
	local byId: { [string]: number } = {}
	for i, e in entrants do
		assert(byId[e.id] == nil, "duplicate id " .. e.id)
		local team = if mode.teams then (e.team or ((i - 1) % 2 + 1)) else i
		players[i] = {
			id = e.id,
			name = e.name,
			bot = e.bot,
			team = team,
			seat = i,
			lives = mode.lives,
			shields = 0,
			cards = {},
			alive = true,
			left = false,
			place = 0,
			stats = { zaps = 0, elims = 0, cards = 0, spins = 0, taken = 0 },
		}
		byId[e.id] = i
	end
	local m: Match = {
		mode = mode,
		players = players,
		byId = byId,
		rng = rng,
		phase = "idle",
		turn = 0,
		round = 1,
		turnsInRound = 0,
		roundSize = #players,
		dir = 1,
		turnIndex = 1,
		spinner = 1,
		target = nil,
		cardPlayed = false,
		double = false,
		oracle = false,
		passed = false,
		jitter = 0,
		speed = Config.Wheel.speed,
		modifier = nil,
		sudden = false,
		suddenFrom = 0,
		dmgBonus = 0,
		wheel = table.clone(Config.Wheels[mode.wheel]),
		maxLives = mode.lives + 1,
		startCount = #players,
		elimOrder = {},
		winner = nil,
		winnerTeam = nil,
	}
	for _, p in players do
		for _ = 1, mode.cards do
			drawCard(m, p, nil)
		end
	end
	return m
end

local function beginTurn(m: Match, ev: { Event })
	m.spinner = m.turnIndex
	m.phase = "decide"
	m.target = nil
	m.cardPlayed = false
	m.double = false
	m.oracle = false
	m.passed = false
	push(ev, { t = "turn", spinner = m.players[m.spinner].id, turn = m.turn, round = m.round })
end

local function finish(m: Match, ev: { Event })
	m.phase = "ended"
	local placements = {}
	if m.mode.teams then
		for _, p in m.players do
			p.place = if p.team == m.winnerTeam then 1 else 2
		end
	else
		for _, p in m.players do
			if p.alive then
				p.place = if p.id == m.winner then 1 else 2
			end
		end
	end
	for _, p in m.players do
		table.insert(placements, { id = p.id, place = p.place, left = p.left })
	end
	table.sort(placements, function(a, b)
		return a.place < b.place
	end)
	push(ev, { t = "ended", winner = m.winner, team = m.winnerTeam, placements = placements, turns = m.turn })
end

-- True when the match is over (and emits "ended" once).
local function checkEnd(m: Match, ev: { Event }): boolean
	if m.phase == "ended" then
		return true
	end
	if m.mode.teams then
		local n, last = aliveTeams(m)
		if n <= 1 then
			m.winnerTeam = if n == 1 then last else nil
			finish(m, ev)
			return true
		end
	else
		local n = aliveCount(m)
		if n <= 1 then
			for _, p in m.players do
				if p.alive then
					m.winner = p.id
				end
			end
			finish(m, ev)
			return true
		end
	end
	return false
end

local function eliminate(m: Match, idx: number, by: number?, cause: string, ev: { Event })
	local p = m.players[idx]
	if not p.alive then
		return
	end
	p.place = aliveCount(m)
	p.alive = false
	p.lives = 0
	p.shields = 0
	table.insert(m.elimOrder, idx)
	if by and by ~= idx then
		m.players[by].stats.elims += 1
	end
	push(ev, { t = "elim", player = p.id, place = p.place, by = if by then m.players[by].id else nil, cause = cause })
end

-- Returns the damage that went through (0 when a shield ate it).
local function damage(m: Match, idx: number, amount: number, by: number?, cause: string, ev: { Event }): number
	local p = m.players[idx]
	if not p.alive then
		return 0
	end
	if p.shields > 0 and m.modifier ~= "fragile" then
		p.shields -= 1
		push(ev, { t = "hit", target = p.id, amount = 0, blocked = true, lives = p.lives, shields = p.shields, by = if by then m.players[by].id else nil, cause = cause })
		return 0
	end
	local dealt = math.min(p.lives, amount)
	p.lives -= dealt
	p.stats.taken += dealt
	if by and by ~= idx then
		m.players[by].stats.zaps += 1
	end
	push(ev, { t = "hit", target = p.id, amount = dealt, blocked = false, lives = p.lives, shields = p.shields, by = if by then m.players[by].id else nil, cause = cause })
	if p.lives <= 0 then
		eliminate(m, idx, by, cause, ev)
	end
	return dealt
end

local function heal(m: Match, idx: number, amount: number, ev: { Event })
	local p = m.players[idx]
	local before = p.lives
	p.lives = math.min(m.maxLives, p.lives + amount)
	push(ev, { t = "heal", player = p.id, amount = p.lives - before, lives = p.lives })
end

local function nextIndex(m: Match, from: number): number
	local n = #m.players
	local i = from
	for _ = 1, n do
		i = (i - 1 + m.dir) % n + 1
		if m.players[i].alive then
			return i
		end
	end
	return from
end

local function shuffle(m: Match, list: { string })
	for i = #list, 2, -1 do
		local j = m.rng.int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function startRound(m: Match, ev: { Event })
	m.round += 1
	m.turnsInRound = 0
	m.roundSize = aliveCount(m)
	local previous = m.modifier
	m.modifier = nil
	local mode = m.mode
	if not m.sudden and mode.modifierEvery > 0 and m.round >= mode.modifierFrom and (m.round - mode.modifierFrom) % mode.modifierEvery == 0 then
		local pool = {}
		for _, mod in Config.Modifiers do
			if mod.id ~= previous then
				table.insert(pool, mod.id)
			end
		end
		m.modifier = pool[m.rng.int(1, #pool)]
	end
	m.wheel = baseWheel(m)
	if m.modifier == "blackout" then
		shuffle(m, m.wheel)
	end
	push(ev, { t = "round", round = m.round, modifier = m.modifier, wheel = table.clone(m.wheel) })
	if m.modifier == "gift" then
		for _, p in m.players do
			if p.alive then
				drawCard(m, p, ev)
			end
		end
	end
end

-- Ends the current turn and starts the next one (or the end of the match).
local function advance(m: Match, ev: { Event })
	if checkEnd(m, ev) then
		return
	end
	m.turn += 1
	m.turnsInRound += 1
	if m.turn > Config.MaxTurns then
		-- hard stop: most lives wins (ties broken by the rng, server side)
		local best, bestLives = {}, -1
		for i, p in m.players do
			if p.alive then
				if p.lives > bestLives then
					best, bestLives = { i }, p.lives
				elseif p.lives == bestLives then
					table.insert(best, i)
				end
			end
		end
		local keep = best[m.rng.int(1, #best)]
		for i, p in m.players do
			if p.alive and (if m.mode.teams then p.team ~= m.players[keep].team else i ~= keep) then
				eliminate(m, i, nil, "timeout", ev)
			end
		end
		checkEnd(m, ev)
		return
	end
	local mode = m.mode
	if not m.sudden and ((mode.suddenAlive > 0 and m.startCount > mode.suddenAlive and aliveCount(m) <= mode.suddenAlive) or m.turn >= mode.suddenTurn) then
		m.sudden = true
		m.suddenFrom = m.turn
		m.modifier = nil
		m.wheel = baseWheel(m)
		push(ev, { t = "sudden", wheel = table.clone(m.wheel) })
	end
	if m.sudden then
		local bonus = (m.turn - m.suddenFrom) // Config.EscalateEvery
		if bonus ~= m.dmgBonus then
			m.dmgBonus = bonus
			push(ev, { t = "escalate", bonus = bonus })
		end
	end
	if m.turnsInRound >= m.roundSize then
		startRound(m, ev)
	end
	m.turnIndex = nextIndex(m, m.turnIndex)
	beginTurn(m, ev)
end

function MatchCore.start(m: Match): { Event }
	assert(m.phase == "idle", "already started")
	local ev: { Event } = {}
	m.turn = 1
	m.turnIndex = m.rng.int(1, #m.players)
	push(ev, { t = "start", first = m.players[m.turnIndex].id })
	beginTurn(m, ev)
	return ev
end

local function removeCard(p: PlayerState, card: string): boolean
	local i = table.find(p.cards, card)
	if not i then
		return false
	end
	table.remove(p.cards, i)
	return true
end

-- Cards: one per turn, only by the spinner, only before the spin.
function MatchCore.playCard(m: Match, id: string, card: string, targetId: string?): (boolean, any)
	local si = m.byId[id]
	if m.phase ~= "decide" or not si or si ~= m.spinner then
		return false, "msg.not_your_turn"
	end
	if m.cardPlayed or m.passed then
		return false, "msg.card_limit"
	end
	local p = m.players[si]
	local def = Config.CardById[card]
	if not def or not table.find(p.cards, card) then
		return false, "msg.no_card"
	end
	local ti: number? = if targetId then m.byId[targetId] else nil
	local ev: { Event } = {}
	if card == "pass" then
		if not ti or ti == si or not m.players[ti].alive then
			return false, "msg.bad_target"
		end
	elseif card == "magnet" then
		if not ti or ti == si or not m.players[ti].alive then
			return false, "msg.bad_target"
		end
		if #m.players[ti].cards == 0 then
			return false, "msg.no_cards_to_steal"
		end
	elseif card == "shield" then
		if p.shields >= Config.MaxShields then
			return false, "msg.shield_max"
		end
	end
	removeCard(p, card)
	p.stats.cards += 1
	m.cardPlayed = true
	push(ev, { t = "card", player = p.id, card = card, target = if ti then m.players[ti].id else nil, count = #p.cards })
	if card == "oracle" then
		m.oracle = true
	elseif card == "double" then
		m.double = true
	elseif card == "shield" then
		p.shields += 1
		push(ev, { t = "shield", player = p.id, shields = p.shields })
	elseif card == "skip" then
		advance(m, ev)
	elseif card == "pass" and ti then
		m.spinner = ti
		m.passed = true
		m.target = nil
		push(ev, { t = "turn", spinner = m.players[ti].id, turn = m.turn, round = m.round, passedFrom = p.id })
	elseif card == "magnet" and ti then
		local victim = m.players[ti]
		local stolen = table.remove(victim.cards, m.rng.int(1, #victim.cards)) :: string
		table.insert(p.cards, stolen)
		push(ev, { t = "stolen", from = victim.id, to = p.id, card = stolen, fromCount = #victim.cards, toCount = #p.cards })
	end
	return true, ev
end

function MatchCore.setTarget(m: Match, id: string, targetId: string): (boolean, any)
	local si = m.byId[id]
	if m.phase ~= "decide" or not si or si ~= m.spinner then
		return false, "msg.not_your_turn"
	end
	local ti = m.byId[targetId]
	if not MatchCore.validTarget(m, si, ti) then
		return false, "msg.bad_target"
	end
	m.target = ti
	return true, { { t = "aim", spinner = id, target = targetId } }
end

function MatchCore.spin(m: Match, id: string): (boolean, any)
	local si = m.byId[id]
	if m.phase ~= "decide" or not si or si ~= m.spinner then
		return false, "msg.not_your_turn"
	end
	if not MatchCore.validTarget(m, si, m.target) then
		m.target = randomTarget(m, si)
	end
	m.phase = "spinning"
	m.jitter = (m.rng.next() * 2 - 1) * Config.Wheel.jitter
	m.speed = Config.Wheel.speed * (if m.modifier == "turbo" then Config.TurboMult else 1)
	m.players[si].stats.spins += 1
	return true, { { t = "spin", spinner = id, target = if m.target then m.players[m.target].id else nil, speed = m.speed, double = m.double, oracle = m.oracle } }
end

-- Slot (1-based) under the pointer for a wheel angle in slots.
function MatchCore.slotAt(angle: number, n: number): number
	return math.floor(angle % n) + 1
end

-- Total braking distance in slots for the current spin.
function MatchCore.travel(m: Match): number
	return Config.Wheel.travelTurns * #m.wheel + m.jitter
end

local function resolve(m: Match, si: number, outcome: string, ev: { Event })
	local s = m.players[si]
	local mult = if m.double then 2 else 1
	local bonus = m.dmgBonus + (if m.modifier == "overcharge" then 1 else 0)
	local def = Config.OutcomeById[outcome]
	local ti = m.target
	if def.needsTarget and not MatchCore.validTarget(m, si, ti) then
		ti = randomTarget(m, si)
		m.target = ti
		if ti then
			push(ev, { t = "aim", spinner = s.id, target = m.players[ti].id })
		end
	end
	if def.needsTarget and not ti then
		return
	end
	local target = ti :: number
	if outcome == "zap" then
		damage(m, target, 1 * mult + bonus, si, outcome, ev)
	elseif outcome == "double" then
		damage(m, target, 2 * mult + bonus, si, outcome, ev)
	elseif outcome == "backfire" then
		damage(m, si, 1 * mult + bonus, si, outcome, ev)
	elseif outcome == "shield" then
		s.shields = math.min(Config.MaxShields, s.shields + mult)
		push(ev, { t = "shield", player = s.id, shields = s.shields })
	elseif outcome == "heal" then
		heal(m, si, mult, ev)
	elseif outcome == "steal" then
		local dealt = damage(m, target, 1 * mult + bonus, si, outcome, ev)
		if dealt > 0 and s.alive then
			heal(m, si, math.min(dealt, mult), ev)
		end
	elseif outcome == "reverse" then
		m.dir = -m.dir
		push(ev, { t = "reverse", dir = m.dir })
		drawCard(m, s, ev)
	elseif outcome == "card" then
		for _ = 1, mult do
			drawCard(m, s, ev)
		end
	elseif outcome == "gift" then
		for _, p in m.players do
			if p.alive then
				drawCard(m, p, ev)
			end
		end
	elseif outcome == "wild" then
		local pool = {}
		for i, p in m.players do
			if p.alive then
				table.insert(pool, i)
			end
		end
		local pick = pool[m.rng.int(1, #pool)]
		push(ev, { t = "wildpick", target = m.players[pick].id })
		damage(m, pick, 1 * mult + bonus, si, outcome, ev)
	elseif outcome == "doom" then
		damage(m, target, 99, si, outcome, ev)
	elseif outcome == "swap" then
		local t = m.players[target]
		s.lives, t.lives = t.lives, s.lives
		push(ev, { t = "swap", a = s.id, b = t.id, aLives = s.lives, bLives = t.lives })
	elseif outcome == "meteor" then
		push(ev, { t = "meteor", by = s.id })
		for i, p in m.players do
			if p.alive and i ~= si then
				damage(m, i, 1 + bonus, si, outcome, ev)
			end
		end
	elseif outcome == "rescue" then
		local revived: number? = nil
		for k = #m.elimOrder, 1, -1 do
			local idx = m.elimOrder[k]
			local p = m.players[idx]
			if p.team == s.team and not p.alive and not p.left then
				revived = idx
				table.remove(m.elimOrder, k)
				break
			end
		end
		if revived then
			local p = m.players[revived]
			p.alive = true
			p.lives = 1
			p.place = 0
			push(ev, { t = "rescue", player = p.id, by = s.id, lives = 1 })
		else
			heal(m, si, mult, ev)
		end
	end
end

-- The spinner brakes at wheel angle `phase` (slots). Resolves the spin and moves on.
function MatchCore.brake(m: Match, id: string, phase: number): (boolean, any)
	local si = m.byId[id]
	if m.phase ~= "spinning" or not si or si ~= m.spinner then
		return false, "msg.not_your_turn"
	end
	if type(phase) ~= "number" or phase ~= phase or math.abs(phase) == math.huge then
		return false, "msg.bad_request"
	end
	local n = #m.wheel
	local travel = MatchCore.travel(m)
	local final = phase + travel
	local slot = MatchCore.slotAt(final, n)
	local outcome = m.wheel[slot]
	local ev: { Event } = {}
	push(ev, {
		t = "landed",
		spinner = id,
		target = if m.target then m.players[m.target].id else nil,
		phase = phase,
		travel = travel,
		final = final,
		slot = slot,
		outcome = outcome,
		double = m.double,
	})
	m.phase = "resolving"
	resolve(m, si, outcome, ev)
	advance(m, ev)
	return true, ev
end

-- A player disconnects or leaves the table. The match goes on without them.
function MatchCore.leave(m: Match, id: string): { Event }
	local idx = m.byId[id]
	local ev: { Event } = {}
	if not idx or m.phase == "ended" then
		return ev
	end
	local p = m.players[idx]
	if p.left then
		return ev
	end
	p.left = true
	if not p.alive then
		return ev
	end
	if m.phase == "idle" then
		p.alive = false
		p.place = #m.players
		return ev
	end
	eliminate(m, idx, nil, "left", ev)
	if checkEnd(m, ev) then
		return ev
	end
	if m.spinner == idx then
		advance(m, ev)
	elseif m.target == idx then
		m.target = nil
		if m.phase == "decide" then
			push(ev, { t = "aim", spinner = m.players[m.spinner].id, target = nil })
		end
	end
	return ev
end

-- What happens when a timer runs out: spin with a random target, or brake at a random angle.
function MatchCore.autoAct(m: Match): { Event }
	if m.phase == "decide" then
		local _, ev = MatchCore.spin(m, m.players[m.spinner].id)
		return ev
	elseif m.phase == "spinning" then
		local _, ev = MatchCore.brake(m, m.players[m.spinner].id, m.rng.next() * #m.wheel)
		return ev
	end
	return {}
end

-- Everything a spectator may know (hands are counts only).
function MatchCore.public(m: Match): { [string]: any }
	local players = {}
	for i, p in m.players do
		players[i] = {
			id = p.id,
			name = p.name,
			bot = p.bot,
			team = p.team,
			seat = p.seat,
			lives = p.lives,
			shields = p.shields,
			cards = #p.cards,
			alive = p.alive,
			left = p.left,
			place = p.place,
		}
	end
	return {
		mode = m.mode.id,
		phase = m.phase,
		turn = m.turn,
		round = m.round,
		dir = m.dir,
		modifier = m.modifier,
		sudden = m.sudden,
		dmgBonus = m.dmgBonus,
		wheel = table.clone(m.wheel),
		maxLives = m.maxLives,
		spinner = m.players[m.spinner].id,
		owner = m.players[m.turnIndex].id,
		target = if m.target then m.players[m.target].id else nil,
		double = m.double,
		passed = m.passed,
		cardPlayed = m.cardPlayed,
		players = players,
	}
end

return MatchCore
