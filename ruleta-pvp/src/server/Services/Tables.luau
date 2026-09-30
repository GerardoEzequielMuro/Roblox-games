--!strict
-- Matchmaking: who sits where. Public tables (fixed mode, countdown, bots fill the empty
-- seats so there is always a match), private tables with a join code, 1v1 duels by
-- challenge, auto-queue, and the hand-off to MatchRunner. Also routes the in-match requests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local MatchCore = require(ReplicatedStorage.Shared.MatchCore)
local BotModel = require(ReplicatedStorage.Shared.BotModel)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Runner = require(script.Parent.MatchRunner)
local CoreService = require(script.Parent.CoreService)
local M = Locale.m

local Tables = {}

export type Seat = { id: string, name: string, bot: boolean, player: Player?, userId: number, color: { number }, model: Model?, variant: number }
export type Table = {
	id: string,
	index: number,
	kind: string, -- "public" | "flex"
	defaultMode: string,
	mode: string,
	theme: string,
	origin: CFrame,
	seats: { [number]: Seat },
	status: string, -- "open" | "countdown" | "playing"
	countdownEnds: number,
	private: { code: string, host: number, fill: boolean }?,
	duel: boolean,
	runner: any?,
	wheelFrac: number,
	matches: number,
}

Tables.list = {} :: { Table }
Tables.byId = {} :: { [string]: Table }
local where: { [Player]: { tbl: Table, seat: number } } = {}
local challenges: { [Player]: { from: Player, expires: number } } = {}
local botFolder: Instance
local dirty = true
local rng = Random.new()
local SEAT_ORDER = { 1, 5, 3, 7, 2, 6, 4, 8 }

local function now(): number
	return workspace:GetServerTimeNow()
end

local function humans(tbl: Table): { Seat }
	local list = {}
	for _, seat in tbl.seats do
		if not seat.bot then
			table.insert(list, seat)
		end
	end
	return list
end

local function seatCount(tbl: Table): number
	local n = 0
	for _ in tbl.seats do
		n += 1
	end
	return n
end

function Tables.seatOf(player: Player): (Table?, number?)
	local w = where[player]
	if w then
		return w.tbl, w.seat
	end
	return nil, nil
end

-- Puts the character at cf. Seated players are anchored (they stand at their podium).
local function placeCharacter(player: Player, cf: CFrame, anchored: boolean)
	if not player:IsA("Player") then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hrp then
		return
	end
	hrp.Anchored = anchored
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(cf)
end

local function snapshot(): { any }
	local out = {}
	for _, tbl in Tables.list do
		local seats = {}
		for i, seat in tbl.seats do
			table.insert(seats, { seat = i, id = seat.id, name = seat.name, bot = seat.bot, userId = seat.userId, color = seat.color, variant = seat.variant })
		end
		local host: string? = nil
		if tbl.private then
			local hp = Players:GetPlayerByUserId(tbl.private.host)
			host = if hp then hp.DisplayName else nil
		end
		table.insert(out, {
			id = tbl.id,
			index = tbl.index,
			kind = tbl.kind,
			mode = tbl.mode,
			theme = tbl.theme,
			status = tbl.status,
			countdownEnds = tbl.countdownEnds,
			private = tbl.private ~= nil,
			fill = if tbl.private then tbl.private.fill else true,
			host = host,
			duel = tbl.duel,
			seats = seats,
			max = Config.ModeById[tbl.mode].maxPlayers,
		})
	end
	return out
end
Tables.snapshot = snapshot

local function markDirty()
	dirty = true
end

local function releaseIfEmpty(tbl: Table)
	if tbl.status == "playing" then
		return
	end
	local hs = humans(tbl)
	if #hs == 0 then
		tbl.status = "open"
		tbl.countdownEnds = 0
		if tbl.kind == "flex" then
			tbl.private = nil
			tbl.duel = false
			tbl.mode = tbl.defaultMode
		end
	elseif tbl.private then
		-- the host left: the longest-seated player takes over
		local private = tbl.private
		local host = Players:GetPlayerByUserId(private.host)
		local w = if host then where[host] else nil
		if not w or w.tbl ~= tbl then
			private.host = hs[1].userId
			local newHost = hs[1].player
			if newHost then
				State.dirty(newHost)
			end
		end
	end
	markDirty()
end

local function startCountdown(tbl: Table, seconds: number)
	tbl.status = "countdown"
	tbl.countdownEnds = now() + seconds / Runner.timeScale
	markDirty()
end

local function freeSeat(tbl: Table): number?
	for _, i in SEAT_ORDER do
		if not tbl.seats[i] then
			return i
		end
	end
	return nil
end

-- Seats `player` at `tbl`. Returns ok, error message.
function Tables.sit(player: Player, tbl: Table): (boolean, Locale.Message?)
	local p = Data.get(player)
	if not p or not State.ready[player] then
		return false, M("msg.loading")
	end
	if where[player] then
		return false, M("msg.already_seated")
	end
	if tbl.status == "playing" then
		return false, M("msg.table_busy")
	end
	local mode = Config.ModeById[tbl.mode]
	if #humans(tbl) >= mode.maxPlayers then
		return false, M("msg.table_full")
	end
	local index = freeSeat(tbl)
	if not index then
		return false, M("msg.table_full")
	end
	tbl.seats[index] = {
		id = "u" .. player.UserId,
		name = player.DisplayName,
		bot = false,
		player = player,
		userId = player.UserId,
		color = Config.BotColors[(index - 1) % #Config.BotColors + 1],
		model = nil,
		variant = 0,
	}
	where[player] = { tbl = tbl, seat = index }
	player:SetAttribute("TableId", tbl.id)
	player:SetAttribute("Seat", index)
	placeCharacter(player, Layout.seatCFrame(tbl.origin, index, Config.Seats), true)
	if not tbl.private and not tbl.duel then
		local count = #humans(tbl)
		if tbl.status == "open" then
			-- first match ever: no waiting around
			startCountdown(tbl, if p.tutorialDone then Config.Timing.countdown else 4)
		end
		if count >= mode.maxPlayers then
			tbl.countdownEnds = math.min(tbl.countdownEnds, now() + Config.Timing.countdownFull / Runner.timeScale)
		end
	end
	State.dirty(player)
	markDirty()
	return true, nil
end

-- Takes `player` off their table (walks away, disconnects, or the match is over).
function Tables.leave(player: Player)
	local w = where[player]
	if not w then
		return
	end
	local tbl = w.tbl
	local seat = tbl.seats[w.seat]
	where[player] = nil
	if tbl.runner and seat then
		tbl.runner:leave(seat.id)
	end
	tbl.seats[w.seat] = nil
	if player.Parent then
		player:SetAttribute("TableId", nil)
		player:SetAttribute("Seat", nil)
		placeCharacter(player, Layout.exitCFrame(tbl.origin, w.seat), false)
		State.dirty(player)
	end
	releaseIfEmpty(tbl)
	markDirty()
end

local function addBots(tbl: Table, count: number)
	local used: { [string]: boolean } = {}
	for _, seat in tbl.seats do
		used[seat.name] = true
	end
	for n = 1, count do
		local index = freeSeat(tbl)
		if not index then
			break
		end
		local name
		repeat
			name = Config.BotNames[rng:NextInteger(1, #Config.BotNames)]
		until not used[name]
		used[name] = true
		local colorRgb = Config.BotColors[(index + tbl.index + n) % #Config.BotColors + 1]
		local variant = rng:NextInteger(0, 2)
		local model = BotModel.build(Color3.fromRGB(colorRgb[1], colorRgb[2], colorRgb[3]), Layout.seatCFrame(tbl.origin, index, Config.Seats), variant)
		local id = "b" .. tbl.index .. "_" .. index
		model.Name = id
		model:SetAttribute("BotName", name)
		model:SetAttribute("TableId", tbl.id)
		model:SetAttribute("Seat", index)
		model.Parent = botFolder
		tbl.seats[index] = { id = id, name = name, bot = true, player = nil, userId = 0, color = colorRgb, model = model, variant = variant }
	end
end

local function clearBots(tbl: Table)
	for i, seat in tbl.seats do
		if seat.bot then
			if seat.model then
				seat.model:Destroy()
			end
			tbl.seats[i] = nil
		end
	end
end

-- Exposed for the screenshot showcase (poses a table without running a match).
Tables.addBots = addBots
Tables.clearBots = clearBots

local function seatById(tbl: Table, id: string): (Seat?, number?)
	for i, seat in tbl.seats do
		if seat.id == id then
			return seat, i
		end
	end
	return nil, nil
end

local function moveSeat(tbl: Table, id: string, bench: boolean)
	local seat, index = seatById(tbl, id)
	if not seat or not index then
		return
	end
	local cf = if bench then Layout.benchCFrame(tbl.origin, index, Config.Seats) else Layout.seatCFrame(tbl.origin, index, Config.Seats)
	if seat.bot then
		if seat.model then
			seat.model:PivotTo(cf)
		end
	elseif seat.player and where[seat.player] and where[seat.player].tbl == tbl then
		placeCharacter(seat.player, cf, true)
	end
end

local function finishMatch(tbl: Table)
	tbl.runner = nil
	tbl.status = "open"
	tbl.countdownEnds = 0
	tbl.matches += 1
	clearBots(tbl)
	local staying = 0
	local leaving: { Player } = {}
	for index, seat in tbl.seats do
		local player = seat.player
		if player and player.Parent then
			local p = Data.get(player)
			if where[player] == nil or where[player].tbl ~= tbl then
				tbl.seats[index] = nil -- no longer really here
			elseif tbl.private or (p and p.settings.autoQueue and not tbl.duel) then
				-- stays for the next match
				staying += 1
				placeCharacter(player, Layout.seatCFrame(tbl.origin, index, Config.Seats), true)
			else
				table.insert(leaving, player)
			end
		else
			tbl.seats[index] = nil
		end
	end
	for _, player in leaving do
		Tables.leave(player)
	end
	if staying > 0 and not tbl.private then
		startCountdown(tbl, Config.Timing.countdown)
	end
	releaseIfEmpty(tbl)
	markDirty()
end

function Tables.startMatch(tbl: Table): boolean
	local hs = humans(tbl)
	if #hs == 0 or tbl.status == "playing" then
		return false
	end
	local mode = Config.ModeById[tbl.mode]
	local fill = not tbl.duel and (tbl.private == nil or tbl.private.fill)
	local want = if fill then math.max(#hs, mode.fillTo) else #hs
	want = math.clamp(math.max(want, 2), 2, mode.maxPlayers)
	if want > #hs then
		addBots(tbl, want - #hs)
	end
	local entrants: { MatchCore.Entrant } = {}
	local humanMap: { [string]: Player } = {}
	local tutorial = false
	local info: { [string]: any } = {}
	for i = 1, Config.Seats do
		local seat = tbl.seats[i]
		if seat then
			info[seat.id] = { seat = i, userId = seat.userId, color = seat.color, variant = seat.variant }
			table.insert(entrants, { id = seat.id, name = seat.name, bot = seat.bot })
			if seat.player then
				humanMap[seat.id] = seat.player
				local p = Data.get(seat.player)
				tutorial = tutorial or (p ~= nil and not p.tutorialDone)
				-- a respawn during the countdown may have moved them
				placeCharacter(seat.player, Layout.seatCFrame(tbl.origin, i, Config.Seats), true)
			end
		end
	end
	if #entrants < 2 then
		clearBots(tbl)
		return false
	end
	tbl.status = "playing"
	local runner = Runner.new(tbl :: any, entrants, humanMap, {
		info = info,
		tutorial = tutorial,
		onFinished = function()
			finishMatch(tbl)
		end,
		onEliminated = function(id: string)
			task.delay(Config.Timing.elimination * 0.85 / Runner.timeScale, function()
				if tbl.runner then
					moveSeat(tbl, id, true)
				end
			end)
		end,
		onRescued = function(id: string)
			moveSeat(tbl, id, false)
		end,
	})
	tbl.runner = runner
	markDirty()
	runner:start()
	return true
end

-- Best public table for a mode (nil = any): one that is already counting down, then an open one.
function Tables.findPublic(modeId: string?): Table?
	local best: Table?, bestScore = nil, -1
	for _, tbl in Tables.list do
		if tbl.kind == "public" and tbl.status ~= "playing" and (modeId == nil or tbl.mode == modeId) then
			local count = #humans(tbl)
			if count < Config.ModeById[tbl.mode].maxPlayers then
				local score = count + (if tbl.status == "countdown" then 10 else 0)
				if score > bestScore then
					best, bestScore = tbl, score
				end
			end
		end
	end
	return best
end

local function freeFlex(): Table?
	for _, tbl in Tables.list do
		if tbl.kind == "flex" and tbl.status == "open" and not tbl.private and not tbl.duel and seatCount(tbl) == 0 then
			return tbl
		end
	end
	return nil
end

local function makeCode(): string
	local letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
	while true do
		local code = ""
		for _ = 1, 4 do
			local i = rng:NextInteger(1, #letters)
			code ..= letters:sub(i, i)
		end
		local taken = false
		for _, tbl in Tables.list do
			taken = taken or (tbl.private ~= nil and tbl.private.code == code)
		end
		if not taken then
			return code
		end
	end
end

-- Creates a duel between two players on a free flex table.
function Tables.startDuel(a: Player, b: Player): (boolean, Locale.Message?)
	if where[a] or where[b] then
		return false, M("msg.already_seated")
	end
	local tbl = freeFlex()
	if not tbl then
		return false, M("msg.no_free_table")
	end
	tbl.duel = true
	tbl.mode = "duel"
	local ok, err = Tables.sit(a, tbl)
	if ok then
		ok, err = Tables.sit(b, tbl)
	end
	if not ok then
		Tables.leave(a)
		Tables.leave(b)
		releaseIfEmpty(tbl)
		return false, err
	end
	startCountdown(tbl, 3)
	return true, nil
end

function Tables.init(world: { tables: { [string]: { origin: CFrame, folder: Folder, prompt: ProximityPrompt, index: number } } })
	botFolder = workspace:WaitForChild("World"):WaitForChild("Bots")
	for i, def in Config.Tables do
		local w = world.tables[def.id]
		local tbl: Table = {
			id = def.id,
			index = i,
			kind = def.kind,
			defaultMode = def.mode,
			mode = def.mode,
			theme = def.theme,
			origin = w.origin,
			seats = {},
			status = "open",
			countdownEnds = 0,
			private = nil,
			duel = false,
			runner = nil,
			wheelFrac = 0,
			matches = 0,
		}
		Tables.list[i] = tbl
		Tables.byId[def.id] = tbl
		w.prompt.Triggered:Connect(function(player: Player)
			if tbl.kind == "flex" then
				Remotes.notify(player, M("msg.flex_hint"), "info")
				return
			end
			local ok, err = Tables.sit(player, tbl)
			if not ok and err then
				Remotes.notify(player, err, "error")
			end
		end)
	end

	CoreService.isSeated = function(player: Player): boolean
		return where[player] ~= nil
	end

	State.extras.table = function(player)
		local w = where[player]
		if not w then
			return nil
		end
		local tbl = w.tbl
		local private = tbl.private
		return {
			id = tbl.id,
			seat = w.seat,
			mode = tbl.mode,
			code = if private then private.code else nil,
			host = private ~= nil and private.host == player.UserId,
			fill = if private then private.fill else nil,
			duel = tbl.duel,
		}
	end

	Remotes.handle("GetTables", function()
		return true, snapshot()
	end)

	Remotes.handle("QuickPlay", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false, M("msg.loading")
		end
		local modeId = payload.mode
		if modeId ~= nil and (type(modeId) ~= "string" or not Config.ModeById[modeId] or modeId == "duel") then
			return false, M("msg.bad_request")
		end
		if not p.tutorialDone then
			modeId = "classic" -- the first match is always the simple one
		end
		local tbl = Tables.findPublic(modeId)
		if not tbl then
			return false, M("msg.no_free_table")
		end
		local ok, err = Tables.sit(player, tbl)
		return ok, if ok then tbl.id else err
	end)

	Remotes.handle("JoinTable", function(player, payload)
		local tbl = if type(payload.table) == "string" then Tables.byId[payload.table] else nil
		if not tbl or tbl.kind ~= "public" then
			return false, M("msg.bad_request")
		end
		local ok, err = Tables.sit(player, tbl)
		return ok, if ok then tbl.id else err
	end)

	Remotes.handle("LeaveTable", function(player)
		if not where[player] then
			return false, M("msg.not_in_match")
		end
		Tables.leave(player)
		return true
	end)

	Remotes.handle("CreatePrivate", function(player, payload)
		local modeId = payload.mode
		if type(modeId) ~= "string" or not Config.ModeById[modeId] then
			return false, M("msg.bad_request")
		end
		if where[player] then
			return false, M("msg.already_seated")
		end
		local tbl = freeFlex()
		if not tbl then
			return false, M("msg.no_free_table")
		end
		tbl.mode = modeId
		tbl.private = { code = makeCode(), host = player.UserId, fill = payload.fill ~= false }
		local ok, err = Tables.sit(player, tbl)
		if not ok then
			tbl.private = nil
			tbl.mode = tbl.defaultMode
			return false, err
		end
		return true, (tbl.private :: any).code
	end)

	Remotes.handle("JoinPrivate", function(player, payload)
		local code = payload.code
		if type(code) ~= "string" or #code > 8 then
			return false, M("msg.code_invalid")
		end
		code = code:upper():gsub("%s", "")
		for _, tbl in Tables.list do
			if tbl.private and tbl.private.code == code then
				local ok, err = Tables.sit(player, tbl)
				return ok, if ok then tbl.id else err
			end
		end
		return false, M("msg.code_invalid")
	end)

	Remotes.handle("PrivateOptions", function(player, payload)
		local w = where[player]
		local tbl = w and w.tbl
		if not tbl or not tbl.private or tbl.private.host ~= player.UserId or tbl.status == "playing" then
			return false, M("msg.host_only")
		end
		if payload.mode ~= nil then
			local mode = if type(payload.mode) == "string" then Config.ModeById[payload.mode] else nil
			if not mode or #humans(tbl) > mode.maxPlayers then
				return false, M("msg.bad_request")
			end
			tbl.mode = mode.id
		end
		if type(payload.fill) == "boolean" then
			tbl.private.fill = payload.fill
		end
		for _, seat in humans(tbl) do
			if seat.player then
				State.dirty(seat.player)
			end
		end
		markDirty()
		return true
	end)

	Remotes.handle("StartPrivate", function(player)
		local w = where[player]
		local tbl = w and w.tbl
		if not tbl or not tbl.private or tbl.private.host ~= player.UserId then
			return false, M("msg.host_only")
		end
		if tbl.status ~= "open" then
			return false, M("msg.table_busy")
		end
		if #humans(tbl) < 2 and not tbl.private.fill then
			return false, M("msg.need_players")
		end
		startCountdown(tbl, 3)
		return true
	end)

	-- 1v1 duels: challenge someone in the lobby; they get 20 s to answer.
	Remotes.handle("Challenge", function(player, payload)
		local target = if type(payload.userId) == "number" then Players:GetPlayerByUserId(payload.userId) else nil
		if not target or target == player or not State.ready[target] then
			return false, M("msg.bad_target")
		end
		if where[player] then
			return false, M("msg.already_seated")
		end
		if where[target] then
			return false, M("msg.player_busy")
		end
		local pending = challenges[target]
		if pending and pending.expires > os.clock() then
			return false, M("msg.player_busy")
		end
		challenges[target] = { from = player, expires = os.clock() + 20 }
		Remotes.fire("Challenge", target, { from = player.UserId, name = player.DisplayName, seconds = 20 })
		return true
	end)

	Remotes.handle("AnswerChallenge", function(player, payload)
		local pending = challenges[player]
		challenges[player] = nil
		if not pending or pending.expires < os.clock() or not pending.from.Parent then
			return false, M("msg.challenge_expired")
		end
		if payload.accept ~= true then
			Remotes.notify(pending.from, M("msg.challenge_declined", { name = player.DisplayName }), "info")
			return true
		end
		local ok, err = Tables.startDuel(pending.from, player)
		if not ok and err then
			Remotes.notify(pending.from, err, "error")
		end
		return ok, err
	end)

	-- In-match actions: { kind = "card" | "target" | "spin" | "brake", ... }
	Remotes.handle("Act", function(player, payload)
		local w = where[player]
		local runner = w and w.tbl.runner
		if not runner or type(payload.kind) ~= "string" then
			return false, M("msg.not_in_match")
		end
		local ok, err = runner:act(player, payload.kind, payload)
		if not ok then
			return false, M(if type(err) == "string" then err else "msg.error")
		end
		return true
	end)

	-- Spectators (and late joiners) ask for the current state of a table's match.
	Remotes.handle("GetMatch", function(_player, payload)
		local tbl = if type(payload.table) == "string" then Tables.byId[payload.table] else nil
		if not tbl or not tbl.runner then
			return false, M("msg.not_in_match")
		end
		return true, { snapshot = tbl.runner:snapshot(), spin = tbl.runner.spin, awaiting = tbl.runner.awaiting }
	end)

	Players.PlayerRemoving:Connect(function(player)
		Tables.leave(player)
		challenges[player] = nil
		for target, c in challenges do
			if c.from == player then
				challenges[target] = nil
			end
		end
	end)

	-- one loop: countdowns and the table list broadcast
	task.spawn(function()
		while true do
			task.wait(0.2)
			local t = now()
			for _, tbl in Tables.list do
				if tbl.status == "countdown" then
					if #humans(tbl) == 0 then
						releaseIfEmpty(tbl)
					elseif t >= tbl.countdownEnds then
						if not Tables.startMatch(tbl) then
							releaseIfEmpty(tbl)
						end
					end
				end
			end
			if dirty then
				dirty = false
				Remotes.fireAll("Tables", snapshot())
			end
		end
	end)
end

-- Re-seat a character that respawned while its player was at a table.
function Tables.onCharacter(player: Player)
	local w = where[player]
	if w then
		local tbl = w.tbl
		task.defer(function()
			if where[player] == w then
				placeCharacter(player, Layout.seatCFrame(tbl.origin, w.seat, Config.Seats), true)
			end
		end)
	end
end

-- Leak check for the playtest.
function Tables.tracked(player: Player): number
	return (if where[player] then 1 else 0) + (if challenges[player] then 1 else 0)
end

return Tables
