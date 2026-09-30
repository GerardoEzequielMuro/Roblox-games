--!nonstrict
-- Runs one match on one table: owns the MatchCore state machine, every timer and the server
-- RNG; turns player requests and bot decisions into core actions and plays the resulting
-- events back to the clients one at a time, with the pauses that make the suspense.
--
-- The server decides everything. Clients are told where the wheel will stop only after the
-- brake is final, and they only animate it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MatchCore = require(ReplicatedStorage.Shared.MatchCore)
local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local MatchRewards = require(script.Parent.MatchRewards)

local T = Config.Timing
local W = Config.Wheel

local Runner = {}
Runner.__index = Runner

-- Tests speed the whole thing up (every timer is divided by this).
Runner.timeScale = 1
-- Test / analytics taps: fn(tableId, event).
Runner.listeners = {} :: { (string, MatchCore.Event) -> () }

export type TableRef = { id: string, mode: string, wheelFrac: number }
export type Opts = { info: { [string]: any }?, tutorial: boolean, onFinished: (any) -> (), onEliminated: ((id: string) -> ())?, onRescued: ((id: string) -> ())? }

local seedSource = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

function Runner.new(tbl: TableRef, entrants: { MatchCore.Entrant }, humans: { [string]: Player }, opts: Opts)
	local self = setmetatable({}, Runner)
	self.tbl = tbl
	self.m = MatchCore.new(tbl.mode, entrants, seedSource:NextInteger(1, 2 ^ 31 - 1))
	self.brain = Rng.new(seedSource:NextInteger(1, 2 ^ 31 - 1))
	self.humans = table.clone(humans) -- id -> Player still at the table
	-- everyone seated at the start can be owed a reward, even if they walk off once eliminated
	self.payable = table.clone(humans) :: { [string]: Player }
	self.humanCount = 0
	for _ in humans do
		self.humanCount += 1
	end
	self.opts = opts
	self.pending = {} :: { MatchCore.Event }
	self.awaiting = nil :: string?
	self.state = nil :: any
	self.spin = nil :: any
	self.idle = {} :: { [string]: number }
	self.forfeit = {} :: { [string]: boolean }
	self.paid = {} :: { [string]: boolean }
	self.results = {} :: { [string]: any }
	self.aborted = false
	self.done = false
	self.startCount = #entrants
	self.events = 0
	return self
end

-- Public state plus where everyone physically sits (seat, user id, colour).
function Runner:snapshot()
	local snap = MatchCore.public(self.m)
	snap.info = self.opts.info
	return snap
end

function Runner:wait(seconds: number)
	if seconds > 0 then
		task.wait(seconds / Runner.timeScale)
	end
end

function Runner:broadcast(e: MatchCore.Event)
	self.events += 1
	Remotes.fireAll("Match", self.tbl.id, e)
	for _, fn in Runner.listeners do
		task.spawn(fn, self.tbl.id, e)
	end
end

function Runner:push(ev: { MatchCore.Event })
	for _, e in ev do
		table.insert(self.pending, e)
	end
end

function Runner:sendHands()
	for id, player in self.humans do
		local idx = self.m.byId[id]
		if idx and player.Parent then
			Remotes.fire("Hand", player, self.tbl.id, table.clone(self.m.players[idx].cards))
		end
	end
end

-- Auto-play: the player's own toggle, or two turns in a row without touching anything.
function Runner:isAuto(player: Player, id: string): boolean
	local p = Data.get(player)
	return (p ~= nil and p.settings.autoPlay) or (self.idle[id] or 0) >= 2
end

function Runner:pay(id: string)
	if self.paid[id] or self.forfeit[id] then
		return
	end
	local m = self.m
	local idx = m.byId[id]
	local player: Player? = self.payable[id]
	if not idx or not player or not player.Parent then
		return
	end
	self.paid[id] = true
	local st = m.players[idx]
	local place = if st.place > 0 then st.place else 2
	self.results[id] = MatchRewards.pay(player, {
		mode = m.mode.id,
		place = place,
		n = self.startCount,
		humans = self.humanCount,
		stats = st.stats,
		tutorial = self.opts.tutorial,
		tableId = self.tbl.id,
	})
end

---------------------------------------------------------------------------
-- Presentation: one event at a time
---------------------------------------------------------------------------
local function publicEvent(e: MatchCore.Event): MatchCore.Event
	if e.t == "draw" then
		return { t = "draw", player = e.player, count = e.count }
	elseif e.t == "stolen" then
		return { t = "stolen", from = e.from, to = e.to, fromCount = e.fromCount, toCount = e.toCount }
	end
	return e
end

function Runner:present(e: MatchCore.Event, nextEvent: MatchCore.Event?)
	local t = e.t
	local m = self.m
	if t == "ended" then
		-- pay whoever is still owed before the results go out
		for id in self.payable do
			self:pay(id)
		end
		e.results = self.results
		self:broadcast(e)
		self:wait(T.ending)
		return
	end
	self:broadcast(publicEvent(e))
	if t == "landed" then
		task.wait(e.duration)
		self:wait(T.landPause)
	elseif t == "hit" then
		local elimNext = nextEvent ~= nil and nextEvent.t == "elim" and nextEvent.player == e.target
		self:wait(if elimNext then 1.2 elseif e.cause == "meteor" then 0.7 else T.effect)
	elseif t == "elim" then
		if e.cause ~= "left" and not m.mode.teams then
			self:pay(e.player)
		end
		if self.opts.onEliminated then
			self.opts.onEliminated(e.player)
		end
		self:wait(if e.cause == "left" then 1.5 else T.elimination)
	elseif t == "wildpick" then
		self:wait(T.wildSweep)
	elseif t == "card" then
		self:wait(T.cardFx)
	elseif t == "turn" then
		self:wait(T.between)
	elseif t == "shield" or t == "heal" or t == "reverse" then
		self:wait(1.5)
	elseif t == "draw" or t == "stolen" then
		self:wait(0.6)
	elseif t == "swap" or t == "meteor" then
		self:wait(2.0)
	elseif t == "rescue" then
		if self.opts.onRescued then
			self.opts.onRescued(e.player)
		end
		self:wait(2.4)
	elseif t == "sudden" then
		self:wait(T.sudden)
	elseif t == "escalate" then
		self:wait(1.4)
	elseif t == "round" then
		self:wait(if e.modifier then T.modifier else 0.4)
	elseif t == "cancel" then
		self:wait(0.4)
	end
end

function Runner:flush()
	while #self.pending > 0 and not self.aborted do
		local e = table.remove(self.pending, 1) :: MatchCore.Event
		self:present(e, self.pending[1])
	end
end

---------------------------------------------------------------------------
-- Spin / brake
---------------------------------------------------------------------------
function Runner:beginSpin(id: string): (boolean, any)
	local m = self.m
	local ok, ev = MatchCore.spin(m, id)
	if not ok then
		return false, ev
	end
	local e = ev[1]
	local now = serverNow()
	local n = #m.wheel
	local r0 = self.tbl.wheelFrac * n
	self.spin = { t0 = now, r0 = r0, speed = e.speed, n = n }
	e.t0 = now
	e.r0 = r0
	e.n = n
	e.minSpin = W.minSpin / Runner.timeScale
	e.maxSpin = W.maxSpin / Runner.timeScale
	self:broadcast(e)
	local human = self.humans[id]
	if e.oracle and human and human.Parent then
		-- the Oracle card: only its owner learns where this spin would stop
		Remotes.fire("Match", human, self.tbl.id, { t = "oracle", travel = MatchCore.travel(m) })
	end
	return true, nil
end

function Runner:doBrake(id: string, tb: number): (boolean, any)
	local m = self.m
	local sp = self.spin
	tb = math.max(tb, sp.t0)
	local phase = sp.r0 + sp.speed * (tb - sp.t0)
	local ok, ev = MatchCore.brake(m, id, phase)
	if not ok then
		return false, ev
	end
	local landed = ev[1]
	landed.tb = tb
	landed.speed = sp.speed
	landed.n = sp.n
	landed.duration = (W.easePower * landed.travel / sp.speed) / Runner.timeScale
	self.tbl.wheelFrac = (landed.final % sp.n) / sp.n
	self:push(ev)
	self:sendHands()
	return true, nil
end

---------------------------------------------------------------------------
-- Player requests (called from the Tables service's remote handlers)
---------------------------------------------------------------------------
local function idOf(self: any, player: Player): string?
	for id, pl in self.humans do
		if pl == player then
			return id
		end
	end
	return nil
end

function Runner:act(player: Player, kind: string, payload: any): (boolean, any)
	local m = self.m
	local id = idOf(self, player)
	if not id or m.phase == "ended" or self.aborted then
		return false, "msg.not_in_match"
	end
	if m.players[m.spinner].id ~= id then
		return false, "msg.not_your_turn"
	end
	if kind == "brake" then
		if self.awaiting ~= "spin" then
			return false, "msg.not_your_turn"
		end
		local sp = self.spin
		local now = serverNow()
		local earliest = sp.t0 + W.minSpin / Runner.timeScale
		if now < earliest then
			return false, "msg.too_early"
		end
		-- small latency allowance: the client says when the button went down
		local tb = now
		local at = payload.at
		if type(at) == "number" and at == at then
			tb = math.clamp(at, math.max(now - 0.2, earliest), now)
		end
		self.idle[id] = 0
		return self:doBrake(id, tb)
	end
	if self.awaiting ~= "decide" then
		return false, "msg.not_your_turn"
	end
	if kind == "card" then
		if type(payload.card) ~= "string" or (payload.target ~= nil and type(payload.target) ~= "string") then
			return false, "msg.bad_request"
		end
		local ok, ev = MatchCore.playCard(m, id, payload.card, payload.target)
		if not ok then
			return false, ev
		end
		self.idle[id] = 0
		self:push(ev)
		self:sendHands()
		return true, nil
	elseif kind == "target" then
		if type(payload.target) ~= "string" then
			return false, "msg.bad_request"
		end
		local ok, ev = MatchCore.setTarget(m, id, payload.target)
		if not ok then
			return false, ev
		end
		self.idle[id] = 0
		self:broadcast(ev[1])
		return true, nil
	elseif kind == "spin" then
		self.idle[id] = 0
		return self:beginSpin(id)
	end
	return false, "msg.bad_request"
end

-- The player walks away or disconnects. Alive = forfeit (nothing is lost, nothing is paid).
function Runner:leave(id: string)
	local m = self.m
	local idx = m.byId[id]
	if not idx or not self.humans[id] then
		return
	end
	if m.players[idx].alive and m.phase ~= "ended" then
		self.forfeit[id] = true
	end
	self.humans[id] = nil
	local wasSpinning = m.phase == "spinning" and m.spinner == idx
	local ev = MatchCore.leave(m, id)
	if wasSpinning then
		table.insert(self.pending, { t = "cancel" })
	end
	self:push(ev)
	if next(self.humans) == nil and m.phase ~= "ended" then
		self.aborted = true
	end
end

---------------------------------------------------------------------------
-- Turn phases
---------------------------------------------------------------------------
function Runner:decide()
	local m = self.m
	local si, turn = m.spinner, m.turn
	local p = m.players[si]
	local human: Player? = self.humans[p.id]
	local auto = human ~= nil and self:isAuto(human, p.id)
	local key = turn .. ":" .. si
	local now = serverNow()
	local scale = Runner.timeScale
	local ts = self.state
	if not ts or ts.key ~= key then
		local dur = if not human then T.decideBot[1] + self.brain.next() * (T.decideBot[2] - T.decideBot[1]) elseif auto then T.afkDecide else T.decide
		ts = {
			key = key,
			deadline = now + dur / scale,
			cardAt = now + dur * 0.3 / scale,
			targetAt = now + dur * 0.6 / scale,
			plan = if not human then BotBrain.decide(m, si, self.brain) else nil,
			cardDone = false,
			targetDone = false,
		}
		self.state = ts
	else
		-- back from showing a card: a moment to keep going
		ts.deadline = math.max(ts.deadline, now + (if human and not auto then 3 else 0.9) / scale)
	end
	self.awaiting = "decide"
	self:broadcast({ t = "decide", spinner = p.id, deadline = ts.deadline, duration = ts.deadline - now, auto = auto, snapshot = self:snapshot() })
	while true do
		task.wait(0.04)
		if self.aborted or #self.pending > 0 or m.phase ~= "decide" or m.spinner ~= si or m.turn ~= turn then
			break
		end
		now = serverNow()
		local plan = ts.plan
		if plan then
			if plan.card and not ts.cardDone and now >= ts.cardAt then
				ts.cardDone = true
				local ok, ev = MatchCore.playCard(m, p.id, plan.card, plan.cardTarget)
				if ok then
					self:push(ev)
					self:sendHands()
					break
				end
			end
			if plan.target and not ts.targetDone and now >= ts.targetAt then
				ts.targetDone = true
				local ok, ev = MatchCore.setTarget(m, p.id, plan.target)
				if ok then
					self:broadcast(ev[1])
				end
			end
		end
		if now >= ts.deadline then
			if human and not auto then
				self.idle[p.id] = (self.idle[p.id] or 0) + 1
			end
			self:beginSpin(p.id)
			break
		end
	end
	self.awaiting = nil
end

function Runner:spinWait()
	local m = self.m
	local si, turn = m.spinner, m.turn
	local p = m.players[si]
	local human: Player? = self.humans[p.id]
	local sp = self.spin
	local scale = Runner.timeScale
	local brakeAt: number
	if not human then
		local tBase = sp.t0 + (W.minSpin + 0.3 + self.brain.next() * 1.6) / scale
		brakeAt = tBase
		if scale == 1 then
			-- wait for the wheel to come round to the angle the bot wants
			local want = BotBrain.brakePhase(m, si, self.brain)
			local rBase = sp.r0 + sp.speed * (tBase - sp.t0)
			brakeAt = tBase + ((want - rBase) % sp.n) / sp.speed
		end
	elseif self:isAuto(human, p.id) then
		brakeAt = sp.t0 + (W.minSpin + 0.4 + self.brain.next() * 1.4) / scale
	else
		brakeAt = sp.t0 + W.maxSpin / scale
	end
	self.awaiting = "spin"
	while true do
		task.wait(0.02)
		if self.aborted or #self.pending > 0 or m.phase ~= "spinning" or m.spinner ~= si or m.turn ~= turn then
			break
		end
		local now = serverNow()
		if now >= brakeAt then
			if human and not self:isAuto(human, p.id) then
				self.idle[p.id] = (self.idle[p.id] or 0) + 1
			end
			self:doBrake(p.id, if human then now else brakeAt)
			break
		end
	end
	self.awaiting = nil
end

function Runner:run()
	local m = self.m
	self:broadcast({ t = "intro", snapshot = self:snapshot(), tutorial = self.opts.tutorial, duration = T.intro / Runner.timeScale })
	self:sendHands()
	self:wait(T.intro)
	self:push(MatchCore.start(m))
	while not self.aborted do
		self:flush()
		if self.aborted or (m.phase == "ended" and #self.pending == 0) then
			break
		end
		if #self.pending == 0 then
			if m.phase == "decide" then
				self:decide()
			elseif m.phase == "spinning" then
				self:spinWait()
			else
				task.wait(0.05)
			end
		end
	end
	if self.aborted and m.phase ~= "ended" then
		-- nobody is watching any more: pay what is owed (teams pay at the end) and stop
		if m.mode.teams then
			for id in self.payable do
				self:pay(id)
			end
		end
		self:broadcast({ t = "abort" })
	end
	self.done = true
	self.opts.onFinished(self)
end

function Runner:start()
	self.thread = task.spawn(function()
		local ok, err = xpcall(function()
			self:run()
		end, debug.traceback)
		if not ok then
			warn("[MatchRunner] match crashed on", self.tbl.id, err)
			self.aborted = true
			self.done = true
			self:broadcast({ t = "abort" })
			self.opts.onFinished(self)
		end
	end)
end

return Runner
