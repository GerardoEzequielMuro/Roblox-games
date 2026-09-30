--!strict
-- The show. Takes the match events the server plays back and turns each one into camera,
-- light, sound, effects and HUD: the close-up on whoever is up, the push-in while the wheel
-- slows and the lights go down, the heartbeat, the black beat before a deadly result, the
-- hit, the finisher, sudden death, the winner. Tables the player is not watching only get
-- their numbers updated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local MatchCore = require(ReplicatedStorage.Shared.MatchCore)
local TableViews = require(script.Parent.TableViews)
local Cam = require(script.Parent.Cam)
local Mood = require(script.Parent.Mood)
local Fx = require(script.Parent.Fx)
local Avatars = require(script.Parent.Avatars)
local Finishers = require(script.Parent.Finishers)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Audio = require(script.Parent.Parent.Audio)
local Theme = require(script.Parent.Parent.UI.Theme)
local MatchHud = require(script.Parent.Parent.UI.MatchHud)

local Director = {}

local player = Players.LocalPlayer
local myId = "u" .. player.UserId

Director.focus = nil :: string? -- table on screen
Director.spectating = false
Director.seen = {} :: { [string]: number } -- events handled per type (playtest)
Director.lastOutcome = nil :: string?
Director.nearMisses = 0
Director.tutorial = false
Director.onTutorial = nil :: ((string, any) -> ())?
local token = 0
local specIndex = 0
local oracleTravel: number? = nil
local pendingResult: { [string]: any }? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------
-- Shots
---------------------------------------------------------------------------
local function centre(view: TableViews.View, y: number): Vector3
	return view.origin:PointToWorldSpace(Vector3.new(0, y, 0))
end

local function overview(view: TableViews.View, blend: number?)
	local base = (os.clock() * 0.05) % (math.pi * 2)
	Cam.shot("overview", function(t)
		local a = base + t * 0.07
		return CFrame.lookAt(view.origin:PointToWorldSpace(Layout.polar(a, 38, 23)), centre(view, 4)), 60
	end, blend or 1)
end

-- In front of a player, slowly pushing in.
local function closeUp(view: TableViews.View, seat: number, blend: number?, tight: boolean?)
	local cf = TableViews.seatCFrame(view, seat)
	local side = if seat % 2 == 0 then 2.6 else -2.6
	Cam.shot("closeup", function(t)
		local d = (if tight then 6.8 else 8.8) - math.min(t, 4) * 0.28
		return CFrame.lookAt((cf * CFrame.new(side, 1.4, -d)).Position, cf.Position + Vector3.new(0, 0.9, 0)), if tight then 42 else 50
	end, blend or 0.5)
end

-- Behind a player, looking across the wheel at everyone else (what you see on your turn).
local function overShoulder(view: TableViews.View, seat: number, blend: number?)
	local cf = TableViews.seatCFrame(view, seat)
	Cam.shot("shoulder", function(t)
		return CFrame.lookAt((cf * CFrame.new(3.4 + math.sin(t * 0.4) * 0.3, 5.2, 9.5)).Position, centre(view, 3.2)), 72
	end, blend or 0.6)
end

-- Over the pointer, pushing in on the slot as the wheel slows down.
local function wheelShot(view: TableViews.View, blend: number?)
	Cam.shot("wheel", function(_t)
		local _, speed = TableViews.spinAngle(view, serverNow())
		local k = 1 - math.clamp(speed / Config.Wheel.speed, 0, 1)
		k = k * k
		local pos = view.origin:PointToWorldSpace(Layout.polar(0.2 - 0.12 * k, 26 - 8.5 * k, 19 - 7.5 * k))
		local look = view.origin:PointToWorldSpace(Layout.polar(0, 3 + 4.2 * k, Layout.WheelY))
		return CFrame.lookAt(pos, look), 62 - 22 * k
	end, blend or 0.7)
end

local function twoShot(view: TableViews.View, seatA: number, seatB: number, blend: number?)
	local a, b = TableViews.seatCFrame(view, seatA).Position, TableViews.seatCFrame(view, seatB).Position
	local mid = (a + b) / 2
	local c = centre(view, mid.Y)
	local out = (c - mid)
	local dir = if out.Magnitude < 1 then (a - b).Unit:Cross(Vector3.yAxis) else out.Unit
	local dist = math.max(12, (a - b).Magnitude * 0.85)
	Cam.static("two", CFrame.lookAt(mid + dir * dist + Vector3.new(0, 7, 0), mid + Vector3.new(0, 0.5, 0)), 58, blend or 0.5)
end

local function victimShot(view: TableViews.View, seat: number)
	local cf = TableViews.seatCFrame(view, seat)
	Cam.shot("victim", function(t)
		return CFrame.lookAt((cf * CFrame.new(-6.5, 3 + t * 1.2, -12 - t * 1.5)).Position, cf.Position + Vector3.new(0, 2 + t * 2.4, 0)), 58
	end, 0.35)
end

local function winnerShot(view: TableViews.View, seat: number)
	local cf = TableViews.seatCFrame(view, seat)
	Cam.shot("winner", function(t)
		local a = t * 0.55
		local p = cf.Position + Vector3.new(math.sin(a) * 10, 2.5 + math.sin(t * 0.7) * 0.8, math.cos(a) * 10)
		return CFrame.lookAt(p, cf.Position + Vector3.new(0, 0.8, 0)), 50
	end, 0.8)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function info(view: TableViews.View, id: string?): TableViews.PlayerView?
	return if id then view.players[id] else nil
end

local function modelOf(view: TableViews.View, id: string?): Model?
	local p = info(view, id)
	if not p then
		return nil
	end
	return Avatars.model({ id = p.id, bot = p.bot, userId = p.userId, name = p.name })
end

local function seatCF(view: TableViews.View, id: string?): CFrame?
	local p = info(view, id)
	return if p then TableViews.seatCFrame(view, p.seat) else nil
end

local function react(view: TableViews.View, id: string?, move: string, duration: number?)
	local cf = seatCF(view, id)
	if cf then
		Avatars.react(modelOf(view, id), cf, move, duration)
	end
end

local function nameOf(view: TableViews.View, id: string?): string
	local p = info(view, id)
	if not p then
		return "?"
	end
	return if id == myId then Lang.t("match.you") else p.name
end

local function finisherOf(view: TableViews.View, byId: string?): string
	local p = info(view, byId)
	if p and not p.bot then
		local pl = Players:GetPlayerByUserId(p.userId)
		local id = pl and pl:GetAttribute("Cos_finisher")
		if type(id) == "string" and Config.CosmeticById[id] then
			return id
		end
	elseif p then
		-- bots show the finishers off: a stable pick per bot name
		local h = 0
		for i = 1, #p.name do
			h += string.byte(p.name, i)
		end
		return Finishers.ids[h % #Finishers.ids + 1]
	end
	return "f_hammer"
end

local function outcomeColor(outcome: string): Color3
	local def = Config.OutcomeById[outcome]
	if outcome == "doom" then
		return Theme.Red
	end
	return if def then rgb(def.color):Lerp(Color3.new(1, 1, 1), 0.2) else Theme.White
end

local function count(t: string)
	Director.seen[t] = (Director.seen[t] or 0) + 1
end

local function tutorial(step: string, arg: any?)
	if Director.tutorial and Director.onTutorial then
		Director.onTutorial(step, arg)
	end
end

---------------------------------------------------------------------------
-- Focus
---------------------------------------------------------------------------
local function applyIdleLook(view: TableViews.View)
	Mood.reset()
	TableViews.rigColor(view, nil)
	TableViews.spotlight(view, nil, nil)
	TableViews.screenIcon(view, nil)
	overview(view, 1)
end

function Director.setFocus(tableId: string?, spectating: boolean)
	if Director.focus == tableId and Director.spectating == spectating then
		return
	end
	token += 1
	local old = Director.focus and TableViews.byId[Director.focus]
	if old then
		TableViews.spotlight(old, nil, nil)
	end
	Director.focus = tableId
	Director.spectating = spectating
	pendingResult = nil
	local view = tableId and TableViews.byId[tableId]
	if not view then
		Mood.reset()
		Cam.release()
		MatchHud.hide()
		Audio.music("lobby")
		return
	end
	applyIdleLook(view)
	if view.playing or spectating then
		MatchHud.show(view, spectating)
		Audio.music("match")
		if view.playing then
			if view.sudden then
				Mood.color(Color3.fromRGB(70, 0, 8))
				Mood.set(0.45, 0.5)
				TableViews.rigColor(view, Color3.fromRGB(255, 40, 50))
			end
		end
	else
		MatchHud.hide()
	end
end

-- Watch a table you are not sitting at.
function Director.spectate(tableId: string)
	local view = TableViews.byId[tableId]
	if not view then
		return
	end
	task.spawn(function()
		local ok, data = Net.request("GetMatch", { table = tableId })
		if ok and type(data) == "table" then
			TableViews.applySnapshot(view, data.snapshot)
		end
		Director.setFocus(tableId, true)
	end)
end

function Director.stopSpectating()
	if Director.spectating then
		Director.setFocus(nil, false)
	end
end

local function spectateStep(delta: number)
	local view = Director.focus and TableViews.byId[Director.focus]
	if not view then
		return
	end
	local alive = {}
	for _, id in view.order do
		if view.players[id].alive then
			table.insert(alive, id)
		end
	end
	if #alive == 0 then
		overview(view, 0.6)
		return
	end
	specIndex = (specIndex + delta - 1) % #alive + 1
	Cam.free.enabled = false
	closeUp(view, view.players[alive[specIndex]].seat, 0.5)
end

local function freeCam()
	local view = Director.focus and TableViews.byId[Director.focus]
	if not view then
		return
	end
	if Cam.free.enabled then
		overview(view, 0.6)
		Cam.free.enabled = false
	else
		Cam.free.yaw, Cam.free.pitch, Cam.free.dist = 0, 0.55, 42
		Cam.freeOrbit("free", function()
			return centre(view, 4)
		end, 0.6)
	end
end

-- Spectators and eliminated players choose their own camera: don't cut it away from them.
local function cameraLocked(view: TableViews.View): boolean
	if Cam.free.enabled then
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Event handlers (focused table)
---------------------------------------------------------------------------
local H: { [string]: (view: TableViews.View, e: { [string]: any }, my: number) -> () } = {}

H.intro = function(view, e, _my)
	Director.tutorial = e.tutorial == true and Net.get("tutorialDone") == false and view.players[myId] ~= nil
	MatchHud.show(view, Director.spectating)
	MatchHud.closeResult()
	Audio.music("match")
	Mood.set(0.25, 1)
	local mode = Config.ModeById[view.mode]
	MatchHud.banner(mode.icon .. " " .. Lang.upper(Lang.t("mode." .. view.mode .. ".name")), Lang.t("match.intro_sub"), rgb(mode.color):Lerp(Color3.new(1, 1, 1), 0.3), 2.6, "soft")
	-- a fast sweep around the table
	local start = os.clock()
	Cam.shot("intro", function(_t)
		local t = os.clock() - start
		local a = -1.2 + t * 0.55
		return CFrame.lookAt(view.origin:PointToWorldSpace(Layout.polar(a, 30 - t * 1.2, 13 + t)), centre(view, 4)), 64
	end, 0.8)
	for i, id in view.order do
		task.delay(0.25 * i, function()
			if view.players[id] then
				react(view, id, "hop", 0.5)
				Audio.play("tick", 0.3, 0.8 + i * 0.08)
			end
		end)
	end
	tutorial("intro")
end

H.turn = function(view, e, _my)
	local p = info(view, e.spinner)
	oracleTravel = nil
	MatchHud.turn(e.spinner, e.passedFrom)
	TableViews.screenIcon(view, nil)
	-- the wheel wears the skin of whoever spins it
	local skin = TableViews.skinOf(view, e.spinner)
	if skin ~= view.skin then
		TableViews.setWheel(view, view.slots, view.hidden, skin)
	end
	view.wheel:setHighlight(nil)
	if not p then
		return
	end
	Mood.heartbeat(0)
	Mood.set(if view.sudden then 0.45 else 0.3, 0.5)
	TableViews.spotlight(view, p.seat, nil)
	Audio.play("tick", 0.5, 1.4)
	if e.spinner == myId then
		overShoulder(view, p.seat, 0.6)
		Audio.play("card", 0.5, 1.3)
	elseif not cameraLocked(view) then
		closeUp(view, p.seat, 0.55)
	end
	react(view, e.spinner, "hop", 0.45)
	if e.passedFrom then
		MatchHud.banner("👉 " .. Lang.t("match.passed_to", { name = nameOf(view, e.spinner) }), nil, Theme.Orange, 1.4, "soft")
	end
end

H.decide = function(view, e, _my)
	MatchHud.decide(e)
	if e.spinner == myId and not e.auto then
		tutorial("decide")
	end
end

H.aim = function(view, e, _my)
	local s, t = info(view, e.spinner), info(view, e.target)
	MatchHud.refresh()
	if not s or not t then
		TableViews.spotlight(view, if s then s.seat else nil, nil)
		return
	end
	TableViews.spotlight(view, s.seat, t.seat)
	local a = TableViews.seatCFrame(view, s.seat).Position
	local b = TableViews.seatCFrame(view, t.seat).Position
	Fx.line(a + Vector3.new(0, 1, 0), b + Vector3.new(0, 1, 0), Color3.fromRGB(255, 70, 80), 0.35, 0.7)
	Fx.ring(b - Vector3.new(0, 2.7, 0), Color3.fromRGB(255, 70, 80), 5, 2.4, 0.5)
	Audio.play("tick", 0.45, 0.7)
	react(view, e.target, "shake", 0.4)
	if e.spinner ~= myId and not cameraLocked(view) then
		twoShot(view, s.seat, t.seat, 0.45)
	end
end

H.card = function(view, e, _my)
	local def = Config.CardById[e.card]
	MatchHud.showCard(e.card, nameOf(view, e.player), if e.target then nameOf(view, e.target) else nil)
	Audio.play("card", 0.6)
	local cf = seatCF(view, e.player)
	if cf and def then
		Fx.ring(cf.Position - Vector3.new(0, 2.7, 0), rgb(def.color), 1, 7, 0.6)
		Fx.sparks(cf.Position + Vector3.new(0, 2, 0), rgb(def.color), 16)
		react(view, e.player, "hop", 0.5)
	end
	if e.player == myId then
		MatchHud.cardPlayed = true
	end
	MatchHud.refresh()
end

H.spin = function(view, e, _my)
	local mine = e.spinner == myId and not (Net.setting("autoPlay") == true)
	Director.lastOutcome = nil
	MatchHud.spinning(e, mine)
	if view.hidden then
		MatchHud.readoutHidden()
	end
	Mood.set(0.55, 0.8)
	Mood.heartbeat(70)
	local s, t = info(view, e.spinner), info(view, e.target)
	TableViews.spotlight(view, if s then s.seat else nil, if t then t.seat else nil)
	Audio.play("whoosh", 0.6, 1)
	if not cameraLocked(view) then
		wheelShot(view, 0.7)
	end
	if e.double then
		MatchHud.banner("✖️2", Lang.t("card.double.short"), Theme.Red, 1, "soft")
	end
	if mine then
		tutorial("spin")
	end
end

H.oracle = function(_view, e, _my)
	oracleTravel = e.travel
end

H.cancel = function(view, _e, _my)
	Mood.heartbeat(0)
	MatchHud.readout(nil)
	MatchHud.braking()
end

H.landed = function(view, e, my)
	MatchHud.braking()
	oracleTravel = nil
	Mood.set(0.95, math.max(0.3, e.duration * 0.6))
	if not cameraLocked(view) then
		wheelShot(view, 0.5)
	end
	-- everyone at the table holds their breath
	for _, id in view.order do
		if view.players[id].alive then
			react(view, id, "tremble", e.duration)
		end
	end
	local def = Config.OutcomeById[e.outcome]
	local frac = e.final % 1
	local n = e.n
	local near: string? = nil
	if frac < 0.14 then
		near = view.slots[(e.slot - 2) % n + 1] -- barely got past the previous slot
	elseif frac > 0.86 then
		near = view.slots[e.slot % n + 1] -- one more hair and it was the next one
	end
	task.delay(e.duration, function()
		if token ~= my then
			return
		end
		Director.lastOutcome = e.outcome
		Mood.heartbeat(0)
		if view.hidden then
			view.wheel:reveal()
			view.hidden = false
		end
		view.wheel:setHighlight(e.slot)
		TableViews.screenIcon(view, if def then def.icon else nil)
		local danger = if def then def.danger else 0
		if danger >= 3 then
			Mood.blackout(0.16)
			task.wait(0.16)
			if token ~= my then
				return
			end
		end
		local color = outcomeColor(e.outcome)
		local sub = Lang.t("out." .. e.outcome .. ".desc")
		if near and near ~= e.outcome then
			local nd = Config.OutcomeById[near]
			Director.nearMisses += 1
			sub = Lang.t("match.so_close", { icon = if nd then nd.icon else "", name = Lang.t("out." .. near) })
		end
		MatchHud.readout(e.outcome, "", true)
		MatchHud.banner((if def then def.icon .. " " else "") .. Lang.upper(Lang.t("out." .. e.outcome)) .. (if e.double then " ×2" else ""), sub, color, 1.6)
		Cam.punch(if danger >= 2 then -12 else -6)
		Cam.shake(0.25 + danger * 0.2)
		Mood.flash(color, 0.12 + danger * 0.1, 0.35)
		Audio.play(if danger >= 2 then "zap" else "shield", 0.6, if danger >= 2 then 0.7 else 1.2)
		Fx.ring(view.wheel:slotWorld(e.slot), color, 1, 6, 0.5)
		Fx.sparks(view.wheel:slotWorld(e.slot) + Vector3.new(0, 1, 0), color, 24)
		Mood.set(if view.sudden then 0.5 else 0.4, 0.6)
	end)
end

H.hit = function(view, e, _my)
	local p = info(view, e.target)
	local cf = seatCF(view, e.target)
	MatchHud.refresh()
	if not p or not cf then
		return
	end
	local from = view.origin:PointToWorldSpace(Vector3.new(0, Layout.WheelY + 2, 0))
	local to = cf.Position + Vector3.new(0, 0.5, 0)
	if e.cause ~= "meteor" and not cameraLocked(view) then
		closeUp(view, p.seat, 0.25, true)
	end
	if e.blocked then
		Fx.bolt(from, to, Color3.fromRGB(120, 210, 255))
		Fx.pulse(cf.Position, Color3.fromRGB(120, 210, 255), 3.5, 6.5, 0.45)
		Fx.floatText(cf.Position + Vector3.new(0, 4, 0), "🛡️ " .. Lang.t("match.blocked"), Color3.fromRGB(150, 220, 255), 4)
		Audio.play("shield", 0.7, 1.1)
		react(view, e.target, "hop", 0.5)
		Cam.shake(0.25)
		return
	end
	local color = if e.cause == "doom" then Color3.fromRGB(255, 60, 70) else Color3.fromRGB(255, 225, 90)
	Fx.bolt(from, to, color, if e.amount >= 2 then 0.8 else 0.45)
	Fx.shards(to, color, 8 + e.amount * 4, 24)
	Fx.sparks(to, color, 22)
	Fx.floatText(cf.Position + Vector3.new(0, 4.2, 0), "-" .. e.amount .. " ❤️", Color3.fromRGB(255, 90, 100), 4 + math.min(e.amount, 3))
	Audio.play("zap", 0.7, 1 - math.min(e.amount, 3) * 0.1)
	react(view, e.target, "flinch", 0.7)
	Cam.shake(0.35 + 0.15 * math.min(e.amount, 3))
	Cam.punch(-5)
	if e.target == myId then
		Mood.flash(Color3.fromRGB(255, 40, 60), 0.35, 0.5)
	end
	if e.by and e.by ~= e.target then
		task.delay(0.5, function()
			react(view, e.by, "hop", 0.45)
		end)
	end
end

H.heal = function(view, e, _my)
	local cf = seatCF(view, e.player)
	MatchHud.refresh()
	if cf and e.amount > 0 then
		local green = Color3.fromRGB(110, 240, 140)
		Fx.ring(cf.Position - Vector3.new(0, 2.7, 0), green, 1, 6, 0.7)
		Fx.shards(cf.Position - Vector3.new(0, 2, 0), green, 8, 14, { gravity = -14, life = 1.1, up = 1 })
		Fx.floatText(cf.Position + Vector3.new(0, 4.2, 0), "+" .. e.amount .. " ❤️", green, 4.5)
		Audio.play("heal", 0.6, 1.3)
		react(view, e.player, "hop", 0.55)
		local p = info(view, e.player)
		if p and not cameraLocked(view) then
			closeUp(view, p.seat, 0.35)
		end
	end
end

H.shield = function(view, e, _my)
	local cf = seatCF(view, e.player)
	MatchHud.refresh()
	if cf then
		local blue = Color3.fromRGB(110, 200, 255)
		Fx.pulse(cf.Position, blue, 1, 5.5, 0.5)
		Fx.floatText(cf.Position + Vector3.new(0, 4.2, 0), "🛡️", blue, 4.5)
		Audio.play("shield", 0.6, 1)
		react(view, e.player, "hop", 0.5)
		local p = info(view, e.player)
		if p and not cameraLocked(view) then
			closeUp(view, p.seat, 0.35)
		end
	end
end

H.draw = function(view, e, _my)
	local cf = seatCF(view, e.player)
	MatchHud.refresh()
	if cf then
		Fx.floatText(cf.Position + Vector3.new(0, 4, 0), "+🃏", Color3.fromRGB(240, 240, 255), 3.6)
		Audio.play("card", 0.4, 1.2)
	end
end

H.stolen = function(view, e, _my)
	local a, b = seatCF(view, e.from), seatCF(view, e.to)
	MatchHud.refresh()
	if a and b then
		Fx.line(a.Position, b.Position, Color3.fromRGB(255, 105, 180), 0.5, 0.6)
		Fx.floatText(a.Position + Vector3.new(0, 4, 0), "-🃏", Color3.fromRGB(255, 120, 160), 3.6)
		Fx.floatText(b.Position + Vector3.new(0, 4, 0), "+🃏", Color3.fromRGB(240, 240, 255), 3.6)
		react(view, e.from, "shake", 0.5)
	end
end

H.reverse = function(view, e, _my)
	local c = centre(view, Layout.WheelY + 1)
	Fx.ring(c, Color3.fromRGB(60, 205, 200), 3, 16, 0.8)
	Fx.ring(c, Color3.fromRGB(60, 205, 200), 1, 12, 1.0)
	Audio.play("whoosh", 0.6, if e.dir > 0 then 1.2 else 0.8)
	if not cameraLocked(view) then
		overview(view, 0.5)
	end
end

H.swap = function(view, e, _my)
	local a, b = seatCF(view, e.a), seatCF(view, e.b)
	MatchHud.refresh()
	if a and b then
		local green = Color3.fromRGB(120, 225, 90)
		Fx.line(a.Position, b.Position, green, 0.7, 0.8)
		Fx.pulse(a.Position, green, 1, 5, 0.5)
		Fx.pulse(b.Position, green, 1, 5, 0.5)
		react(view, e.a, "spin", 0.8)
		react(view, e.b, "spin", 0.8)
		Audio.play("whoosh", 0.6, 1.4)
		local pa, pb = info(view, e.a), info(view, e.b)
		if pa and pb and not cameraLocked(view) then
			twoShot(view, pa.seat, pb.seat, 0.4)
		end
	end
end

H.meteor = function(view, _e, _my)
	if not cameraLocked(view) then
		overview(view, 0.4)
	end
	Mood.flash(Color3.fromRGB(255, 120, 40), 0.3, 0.8)
	Audio.play("whoosh", 0.8, 0.5)
	for _, id in view.order do
		local p = view.players[id]
		if p.alive and id ~= view.spinner then
			local cf = TableViews.seatCFrame(view, p.seat)
			local from = cf.Position + Vector3.new(math.random(-20, 20), 80, math.random(-20, 20))
			Fx.line(from, cf.Position, Color3.fromRGB(255, 140, 50), 1.6, 0.9)
		end
	end
	task.delay(0.5, function()
		Cam.shake(0.8)
	end)
end

H.rescue = function(view, e, _my)
	local cf = seatCF(view, e.player)
	MatchHud.refresh()
	MatchHud.banner("🚑 " .. Lang.t("match.rescued", { name = nameOf(view, e.player) }), nil, Color3.fromRGB(110, 240, 200), 1.8, "soft")
	if cf then
		Fx.line(cf.Position + Vector3.new(0, 60, 0), cf.Position, Color3.fromRGB(110, 240, 200), 3, 1.2)
		Fx.confetti(cf.Position + Vector3.new(0, 3, 0), 16, 22)
		Audio.play("heal", 0.8, 1)
		local p = info(view, e.player)
		if p and not cameraLocked(view) then
			closeUp(view, p.seat, 0.4)
		end
		task.delay(0.4, function()
			react(view, e.player, "cheer", 1.2)
		end)
	end
end

-- The wild pointer: a laser sweeps the table and slows down on whoever gets it.
H.wildpick = function(view, e, my)
	local alive = {}
	local targetIndex = 1
	for _, id in view.order do
		local p = view.players[id]
		if p.alive or id == e.target then
			table.insert(alive, p)
			if id == e.target then
				targetIndex = #alive
			end
		end
	end
	if #alive == 0 then
		return
	end
	if not cameraLocked(view) then
		overview(view, 0.4)
	end
	Mood.set(0.8, 0.4)
	Mood.heartbeat(110)
	local steps = #alive * 2 + targetIndex
	local total = Config.Timing.wildSweep * 0.86
	local from = centre(view, Layout.WheelY + 1.5)
	task.spawn(function()
		for i = 1, steps do
			if token ~= my then
				return
			end
			local p = alive[(i - 1) % #alive + 1]
			local pos = TableViews.seatCFrame(view, p.seat).Position
			Fx.line(from, pos, Color3.fromRGB(255, 105, 180), 0.5, 0.22)
			TableViews.spotlight(view, nil, nil)
			TableViews.spotlight(view, p.seat, p.seat)
			Audio.play("tick", 0.45, 0.7 + 0.6 * (1 - i / steps))
			-- ease out: the last few hops take most of the time
			local a0, a1 = ((i - 1) / steps) ^ 2.2, (i / steps) ^ 2.2
			task.wait(total * (a1 - a0))
		end
		if token ~= my then
			return
		end
		Mood.heartbeat(0)
		local victim = info(view, e.target)
		if victim then
			MatchHud.banner("🎯 " .. nameOf(view, e.target), nil, Color3.fromRGB(255, 105, 180), 1.1)
			if not cameraLocked(view) then
				closeUp(view, victim.seat, 0.25, true)
			end
		end
	end)
end

H.elim = function(view, e, _my)
	local p = info(view, e.player)
	MatchHud.refresh()
	if not p then
		return
	end
	local cf = TableViews.seatCFrame(view, p.seat)
	local me = e.player == myId
	Mood.set(0.7, 0.3)
	if e.cause == "left" then
		MatchHud.banner("🚪 " .. Lang.t("match.left", { name = p.name }), nil, Theme.Dim, 1.3, "soft")
		Fx.pulse(cf.Position, Color3.fromRGB(180, 180, 200), 1, 6, 0.5)
		return
	end
	MatchHud.banner((if me then "💥 " .. Lang.t("match.you_out") else "💥 " .. Lang.t("match.eliminated", { name = p.name })), Lang.t("result.place", { n = e.place, total = #view.order }), Theme.Red, 2.6)
	if not cameraLocked(view) then
		victimShot(view, p.seat)
	end
	Audio.play("doom", 0.7, 0.8)
	Finishers.play(finisherOf(view, e.by), modelOf(view, e.player), cf, p.color)
	if e.by and e.by ~= e.player then
		task.delay(1.6, function()
			react(view, e.by, "cheer", 1.1)
		end)
	end
	if me then
		Mood.flash(Color3.fromRGB(255, 30, 50), 0.4, 0.8)
		tutorial("eliminated")
		-- the reward screen comes once the finisher has played
		task.delay(Finishers.Duration, function()
			if pendingResult and not pendingResult.won and Director.focus == view.id then
				MatchHud.showResult(pendingResult, false)
			end
		end)
	end
	task.delay(Finishers.Duration, function()
		Mood.set(if view.sudden then 0.5 else 0.3, 0.6)
	end)
end

H.sudden = function(view, e, _my)
	TableViews.setWheel(view, e.wheel, false, nil)
	MatchHud.refresh()
	Mood.color(Color3.fromRGB(70, 0, 8))
	Mood.blackout(0.2)
	Mood.set(0.6, 0.4)
	TableViews.rigColor(view, Color3.fromRGB(255, 40, 50))
	Audio.music("sudden")
	Audio.play("doom", 0.9, 0.6)
	Cam.shake(0.7)
	MatchHud.banner("💀 " .. Lang.upper(Lang.t("match.sudden")), Lang.t("match.sudden_sub"), Theme.Red, 3)
	local alive = {}
	for _, id in view.order do
		if view.players[id].alive then
			table.insert(alive, view.players[id])
		end
	end
	if #alive >= 2 and not cameraLocked(view) then
		twoShot(view, alive[1].seat, alive[2].seat, 0.6)
	end
	for _, p in alive do
		react(view, p.id, "shake", 0.8)
	end
end

H.escalate = function(view, e, _my)
	MatchHud.refresh()
	MatchHud.banner("🔥 +" .. e.bonus, Lang.t("match.escalate"), Theme.Orange, 1.2, "soft")
	Cam.shake(0.3)
end

H.round = function(view, e, _my)
	local hidden = e.modifier == "blackout"
	TableViews.setWheel(view, e.wheel, hidden, nil)
	MatchHud.refresh()
	if e.modifier then
		local mod = Config.ModifierById[e.modifier]
		MatchHud.banner(mod.icon .. " " .. Lang.upper(Lang.t("mod." .. e.modifier .. ".name")), Lang.t("mod." .. e.modifier .. ".desc"), rgb(mod.color):Lerp(Color3.new(1, 1, 1), 0.3), 2.2, "soft")
		Audio.play("whoosh", 0.6, 0.9)
		if hidden then
			Mood.blackout(0.25)
		end
		if not cameraLocked(view) then
			overview(view, 0.6)
		end
	end
end

H.ended = function(view, e, _my)
	-- view state was already cleared by TableViews.applyEvent; e carries what we need
	Mood.reset()
	Mood.set(0.2, 0.5)
	Audio.music("win")
	Audio.play("win", 0.8)
	MatchHud.readout(nil)
	local result = e.results and e.results[myId]
	local winnerSeat: number? = nil
	local winnerName = "?"
	local lobby = view.lobbySeats
	for seat, s in lobby do
		if s.id == e.winner then
			winnerSeat, winnerName = seat, s.name
		end
	end
	if e.team and not e.winner then
		winnerName = Lang.t("match.team", { n = e.team })
	end
	local iWon = result ~= nil and result.won == true
	MatchHud.banner("🏆 " .. (if iWon then Lang.t("result.victory") else Lang.t("match.winner", { name = winnerName })), nil, Theme.Yellow, 3.4)
	TableViews.spotlight(view, winnerSeat, nil)
	if winnerSeat then
		local cf = TableViews.seatCFrame(view, winnerSeat)
		winnerShot(view, winnerSeat)
		local s = lobby[winnerSeat]
		local model = Avatars.model({ id = s.id, bot = s.bot, userId = s.userId, name = s.name })
		Avatars.react(model, cf, "cheer", 1.6)
		for i = 0, 4 do
			task.delay(i * 0.45, function()
				Fx.confetti(cf.Position + Vector3.new(math.random(-6, 6), 6, math.random(-6, 6)), 18, 30)
				Fx.pulse(cf.Position + Vector3.new(math.random(-16, 16), 20 + math.random(0, 10), math.random(-16, 16)), Color3.fromHSV(math.random(), 0.7, 1), 1, 7, 0.6)
				Audio.play("tick", 0.4, 1.2 + i * 0.1)
			end)
		end
	else
		overview(view, 0.8)
		Fx.confetti(centre(view, 14), 40, 40)
	end
	if result and view.players[myId] == nil then
		task.delay(if iWon then 3.2 else 1.6, function()
			if Director.focus == view.id and not MatchHud.resultVisible() then
				MatchHud.showResult(result, true)
			end
		end)
	end
	tutorial("ended", iWon)
end

H.abort = function(view, _e, _my)
	applyIdleLook(view)
	MatchHud.readout(nil)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function onMatch(tableId: string, e: { [string]: any })
	local view = TableViews.byId[tableId]
	if not view or type(e) ~= "table" then
		return
	end
	count(e.t)
	-- remember who was seated before the end clears the match state
	TableViews.applyEvent(view, e)
	if Director.focus ~= tableId then
		return
	end
	token += 1
	local handler = H[e.t]
	if handler then
		local my = token
		local ok, err = pcall(function()
			handler(view, e, my)
		end)
		if not ok then
			warn("[Director]", e.t, err)
		end
	end
end
Director.onMatch = onMatch

function Director.init()
	Net.event("Match").OnClientEvent:Connect(onMatch)
	Net.event("Result").OnClientEvent:Connect(function(result)
		pendingResult = result
	end)
	Net.event("Emote").OnClientEvent:Connect(function(userId, id)
		local item = Config.CosmeticById[id]
		local pl = Players:GetPlayerByUserId(userId)
		if not item or not pl or not pl.Character then
			return
		end
		Avatars.bubble(pl.Character, item.icon)
		local tableId = pl:GetAttribute("TableId")
		local seat = pl:GetAttribute("Seat")
		local view = if type(tableId) == "string" then TableViews.byId[tableId] else nil
		if view and type(seat) == "number" then
			Avatars.react(pl.Character, TableViews.seatCFrame(view, seat), (item.look :: any).move or "hop", 0.7)
		end
	end)

	-- ticks: sound, readout, heartbeat that speeds up as the wheel slows
	TableViews.Ticked:Connect(function(tableId, slot, speed)
		if tableId ~= Director.focus then
			return
		end
		local view = TableViews.byId[tableId]
		local slow = 1 - math.clamp(speed / Config.Wheel.speed, 0, 1)
		Audio.play("tick", 0.25 + slow * 0.4, 1.5 - slow * 0.7)
		if view.spin.mode == "brake" then
			Mood.heartbeat(80 + slow * 90)
			if slow > 0.75 then
				Cam.punch(-1.2)
			end
		end
		if view.hidden then
			MatchHud.readoutHidden()
		else
			local outcome = view.slots[slot]
			local sub: string? = nil
			if oracleTravel and view.spin.mode == "free" then
				local land = MatchCore.slotAt(view.wheel.angle + oracleTravel, #view.slots)
				local def = Config.OutcomeById[view.slots[land]]
				sub = "🔮 " .. Lang.t("match.oracle", { icon = if def then def.icon else "", name = Lang.t("out." .. view.slots[land]) })
			end
			MatchHud.readout(outcome, sub, slow > 0.6)
		end
		local def = Config.OutcomeById[view.slots[slot]]
		TableViews.screenIcon(view, if view.hidden then "❓" elseif def then def.icon else nil)
	end)

	-- sitting down / standing up moves the focus
	local function syncSeat()
		local t = Net.get("table")
		local id = if type(t) == "table" then t.id else nil
		if id then
			if Director.focus ~= id or Director.spectating then
				Director.setFocus(id, false)
			end
		elseif Director.focus and not Director.spectating then
			Director.setFocus(nil, false)
		end
	end
	Net.Changed:Connect(syncSeat)
	syncSeat()

	MatchHud.onSpectateStep = spectateStep
	MatchHud.onFreeCam = freeCam
	Audio.music("lobby")
end

return Director
