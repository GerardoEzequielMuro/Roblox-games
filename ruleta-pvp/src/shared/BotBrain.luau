--!strict
-- Bot decisions (pure). The server asks it what a bot does on its turn; the standalone
-- tests use it to play thousands of full matches. Bots get no hidden information: they
-- see exactly what MatchCore.public() shows plus their own hand.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")
local MatchCore: typeof(require(script.Parent.MatchCore)) = if script then require(script.Parent.MatchCore) :: any else (require :: any)("./MatchCore")
local RngMod: typeof(require(script.Parent.Rng)) = if script then require(script.Parent.Rng) :: any else (require :: any)("./Rng")

local BotBrain = {}

type Match = typeof(MatchCore.new("classic", {}, 0))
type PlayerState = typeof((({} :: any) :: Match).players[1])
type RngT = typeof(RngMod.new(0))

export type Decision = { card: string?, cardTarget: string?, target: string? }

BotBrain.Skill = 0.35 -- chance that a bot tries to time the brake at all
BotBrain.AimError = 2.0 -- +- slots of timing error when it does

local function has(p: PlayerState, card: string): boolean
	return table.find(p.cards, card) ~= nil
end

local function pickTarget(m: Match, si: number, rng: RngT): number?
	local list = MatchCore.targets(m, si)
	if #list == 0 then
		return nil
	end
	local r = rng.next()
	if r < 0.3 then
		return list[rng.int(1, #list)]
	end
	-- 50% the leader, 20% the weakest; ties broken at random so no seat is picked on
	local best, bestScore = list[1], -math.huge
	for _, i in list do
		local a = m.players[i]
		local score = (if r < 0.8 then a.lives + a.shields else -a.lives) + rng.next() * 0.5
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	return best
end

-- What the bot does in the decide phase. At most one card.
function BotBrain.decide(m: Match, si: number, rng: RngT): Decision
	local p = m.players[si]
	local d: Decision = {}
	local ti = pickTarget(m, si, rng)
	d.target = if ti then m.players[ti].id else nil
	if m.cardPlayed or m.passed or #p.cards == 0 then
		return d
	end
	local lowLife = p.lives == 1 and p.shields == 0
	if has(p, "shield") and p.shields < Config.MaxShields and (lowLife and rng.next() < 0.8 or rng.next() < 0.15) then
		d.card = "shield"
	elseif has(p, "skip") and lowLife and rng.next() < 0.35 then
		d.card = "skip"
	elseif has(p, "pass") and lowLife and rng.next() < 0.3 then
		-- any other living player
		local others = {}
		for i, o in m.players do
			if o.alive and i ~= si then
				table.insert(others, o.id)
			end
		end
		if #others > 0 then
			d.card = "pass"
			d.cardTarget = others[rng.int(1, #others)]
		end
	elseif has(p, "magnet") and rng.next() < 0.4 then
		local rich = {}
		for i, o in m.players do
			if o.alive and i ~= si and #o.cards > 0 then
				table.insert(rich, o.id)
			end
		end
		if #rich > 0 then
			d.card = "magnet"
			d.cardTarget = rich[rng.int(1, #rich)]
		end
	elseif has(p, "double") and ti and m.players[ti].lives >= 2 and rng.next() < 0.3 then
		d.card = "double"
	elseif has(p, "oracle") and rng.next() < 0.45 then
		d.card = "oracle"
	end
	return d
end

local SCORE = { doom = 5, double = 4, zap = 3, steal = 3, meteor = 3, heal = 2, shield = 2, swap = 1, card = 1, gift = 1, reverse = 1, rescue = 2, wild = 0, backfire = -5 }

-- Wheel angle (slots) at which the bot brakes. Mostly a random angle; sometimes it aims at
-- its favourite slot with a timing error. It does not know the jitter.
function BotBrain.brakePhase(m: Match, si: number, rng: RngT): number
	local n = #m.wheel
	if m.modifier == "blackout" or rng.next() >= BotBrain.Skill then
		return rng.next() * n
	end
	local p = m.players[si]
	local bestSlot, bestScore = 1, -math.huge
	for slot, outcome in m.wheel do
		local s = SCORE[outcome] or 0
		if outcome == "heal" and p.lives >= m.maxLives then
			s = 0
		end
		s += rng.next() * 0.5
		if s > bestScore then
			bestSlot, bestScore = slot, s
		end
	end
	local want = (bestSlot - 1) + 0.5 -- centre of the slot
	local err = (rng.next() * 2 - 1) * BotBrain.AimError
	return (want - Config.Wheel.travelTurns * n + err) % n
end

return BotBrain
