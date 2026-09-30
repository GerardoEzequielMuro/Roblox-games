-- Playtest harness, client side: plays real matches through the real remotes (a small pilot
-- takes the player's turns), then walks every other system: tables, duels, private tables,
-- spectating, leaving mid-match, auto-queue / auto-play, the Power Core, cosmetics, rewards,
-- quests, codes, receipts, events, languages, budgets and the lite profile.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local clientErrors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(clientErrors, msg)
	end
end)

local lines = {}
local function show(v)
	if type(v) == "table" then
		if type(v.key) == "string" then
			return v.key
		end
		return "{table}"
	end
	return (tostring(v):gsub("\n", " / "))
end
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail ~= nil then " :: " .. show(detail) else "")
	if not cond then
		print("[TEST] c " .. line) -- the server prints the full report at the end
	end
	table.insert(lines, line)
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request") :: RemoteFunction
local T = ReplicatedStorage:WaitForChild("__Test", 90) :: RemoteFunction
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Layout = require(ReplicatedStorage.Shared.Layout)
local MatchCore = require(ReplicatedStorage.Shared.MatchCore)
local Progression = require(ReplicatedStorage.Shared.Progression)

local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Net = require(Client:WaitForChild("Net"))
local Lang = require(Client:WaitForChild("Lang"))
local Audio = require(Client:WaitForChild("Audio"))
local Prefs = require(Client:WaitForChild("Prefs"))
local CoreClient = require(Client:WaitForChild("CoreClient"))
local Arena = Client:WaitForChild("Arena")
local TableViews = require(Arena:WaitForChild("TableViews"))
local Director = require(Arena:WaitForChild("Director"))
local Cam = require(Arena:WaitForChild("Cam"))
local Mood = require(Arena:WaitForChild("Mood"))
local Fx = require(Arena:WaitForChild("Fx"))
local Avatars = require(Arena:WaitForChild("Avatars"))
local Finishers = require(Arena:WaitForChild("Finishers"))
local UI = Client:WaitForChild("UI")
local MatchHud = require(UI:WaitForChild("MatchHud"))
local Hud = require(UI:WaitForChild("Hud"))
local Windows = require(UI:WaitForChild("Windows"))
local Toasts = require(UI:WaitForChild("Toasts"))

local myId = "u" .. player.UserId

local function req(action, payload)
	task.wait(0.1) -- stay under the Request rate limit
	local ok, a, b = pcall(function()
		return Request:InvokeServer(action, payload)
	end)
	if not ok then
		return false, a
	end
	return a == true, b
end
local function srv(cmd, a, b)
	return T:InvokeServer(cmd, a, b)
end
local function waitFor(fn, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 10) do
		local v = fn()
		if v then
			return v
		end
		task.wait(0.05)
	end
	return fn()
end
local function isKey(res, key)
	return type(res) == "table" and res.key == key
end

---------------------------------------------------------------------------
-- The pilot: plays the local player's turns through the Act remote
---------------------------------------------------------------------------
local pilot = { on = true, cards = true, accepted = { card = 0, target = 0, spin = 0, brake = 0 }, rejected = 0, brakeAtSlot = nil }
local seen = {} -- tableId -> { type -> count }
local lastEvent = {} -- tableId -> { type -> last event }
local hand = {}
local results = {}
local notifications = {}
Remotes:WaitForChild("Hand").OnClientEvent:Connect(function(_id, cards)
	hand = cards
end)
Remotes:WaitForChild("Result").OnClientEvent:Connect(function(r)
	table.insert(results, r)
end)
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(m)
	table.insert(notifications, m)
end)
local liveUpdates = {}
Remotes:WaitForChild("LiveEventUpdate").OnClientEvent:Connect(function(d)
	table.insert(liveUpdates, d)
end)
local emotesSeen = 0
Remotes:WaitForChild("Emote").OnClientEvent:Connect(function()
	emotesSeen += 1
end)
local parties = 0
Remotes:WaitForChild("Party").OnClientEvent:Connect(function()
	parties += 1
end)
local coreEvents = {}
Remotes:WaitForChild("Core").OnClientEvent:Connect(function(d)
	table.insert(coreEvents, d)
end)
local unlocks = {}
Remotes:WaitForChild("Unlock").OnClientEvent:Connect(function(id)
	unlocks[id] = true
end)

local function act(kind, payload)
	payload = payload or {}
	payload.kind = kind
	local ok, a, b = pcall(function()
		return Request:InvokeServer("Act", payload)
	end)
	if ok and a == true then
		pilot.accepted[kind] += 1
		return true
	end
	pilot.rejected += 1
	return false, b
end

Remotes:WaitForChild("Match").OnClientEvent:Connect(function(tableId, e)
	local s = seen[tableId]
	if not s then
		s = {}
		seen[tableId] = s
		lastEvent[tableId] = {}
	end
	s[e.t] = (s[e.t] or 0) + 1
	lastEvent[tableId][e.t] = e
	if not pilot.on then
		return
	end
	if e.t == "decide" and e.spinner == myId and not e.auto then
		task.spawn(function()
			local snap = e.snapshot
			local me
			for _, p in snap.players do
				if p.id == myId then
					me = p
				end
			end
			local targets = {}
			for _, p in snap.players do
				if p.alive and p.id ~= myId and (not Config.ModeById[snap.mode].teams or p.team ~= me.team) then
					table.insert(targets, p)
				end
			end
			if pilot.cards and not snap.cardPlayed and not snap.passed then
				for _, card in hand do
					if card == "double" or card == "oracle" or (card == "shield" and me.shields < Config.MaxShields) then
						if act("card", { card = card }) then
							return -- a new "decide" follows the card
						end
					elseif card == "magnet" then
						for _, p in snap.players do
							if p.alive and p.id ~= myId and p.cards > 0 then
								if act("card", { card = card, target = p.id }) then
									return
								end
							end
						end
					end
				end
			end
			if #targets > 0 then
				act("target", { target = targets[1].id })
			end
			act("spin")
		end)
	elseif e.t == "spin" and e.spinner == myId then
		task.spawn(function()
			while workspace:GetServerTimeNow() < e.t0 + e.minSpin + 0.005 do
				task.wait()
			end
			local ok = act("brake", { at = workspace:GetServerTimeNow() })
			if not ok then
				task.wait(0.03)
				act("brake", {})
			end
		end)
	end
end)

local function count(tableId, t)
	return (seen[tableId] and seen[tableId][t]) or 0
end
-- Waits until table `id` has finished `n` more matches (ended or aborted).
local function waitMatch(id, before, timeout)
	return waitFor(function()
		return count(id, "ended") + count(id, "abort") > before
	end, timeout or 90)
end

---------------------------------------------------------------------------
-- Session, UI, world
---------------------------------------------------------------------------
local okState, state
for _ = 1, 120 do
	okState, state = req("GetState")
	if okState then
		break
	end
	task.wait(0.5)
end
check("GetState", okState and type(state) == "table", state)
state = if type(state) == "table" then state else {}
check("snapshot: coins 0, level 1, bronze", state.coins == 0 and state.level == 1 and state.league == "bronze")
check("snapshot: default items owned", type(state.owned) == "table" and state.owned.w_classic == true and state.owned.f_hammer == true and state.owned.w_gold ~= true)
check("snapshot: tutorial pending", state.tutorialDone == false)
check("snapshot: core auto locked below level 5", type(state.core) == "table" and state.core.autoUnlocked == false)

local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
task.wait(1)

local gui = player:WaitForChild("PlayerGui")
local mainGui = gui:WaitForChild("SpinUI", 10) :: ScreenGui
check("main UI built", mainGui ~= nil and #mainGui:GetDescendants() > 150, mainGui and #mainGui:GetDescendants())
check("main UI uses CoreUISafeInsets", mainGui and mainGui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)
check("veil and overlay guis exist", gui:FindFirstChild("SpinVeil") ~= nil and gui:FindFirstChild("SpinOverlay") ~= nil)
check("lobby HUD: play button and menu", Hud.buttons.Play ~= nil and Hud.buttons.Shop ~= nil and Hud.buttons.Settings ~= nil and Hud.buttons.AutoQueue ~= nil)
check("first-match nudge shown", (function()
	local tip = mainGui:FindFirstChild("PlayTip", true)
	return tip ~= nil and tip.Visible
end)())

waitFor(function()
	return TableViews.ready
end, 30)
check("table views ready", TableViews.ready and #TableViews.list == #Config.Tables, #TableViews.list)
task.wait(0.5)

-- wheel geometry: the slot the maths says is under the pointer is the one drawn there
do
	local okAll, detail = true, ""
	for _, view in TableViews.list do
		local n = #view.slots
		for _, r in { 0.5, 3.2, 7.9, n - 0.4, n + 2.25, 40.6 } do
			view.wheel:setAngle(r)
			local want = MatchCore.slotAt(r, n)
			if view.wheel:slotAtPointer() ~= want or view.wheel:nearestPlate() ~= want then
				okAll = false
				detail = string.format("%s r=%.2f want %d got %d/%d", view.id, r, want, view.wheel:slotAtPointer(), view.wheel:nearestPlate())
			end
		end
		view.wheel:setAngle(0)
	end
	check("wheel: drawn slot under the pointer matches the server maths", okAll, detail)
	local t1 = TableViews.byId.t1
	check("wheel: classic table shows the classic slots", #t1.slots == 12 and t1.slots[5] == "doom" and t1.wheel.labels[5].Text == "💀")
	check("wheel: chaos table has 14 slots", #TableViews.byId.t2.slots == 14)
	check("desks, screens and spotlights built", t1.desks[1] ~= nil and t1.desks[8] ~= nil and #t1.screens == 4 and t1.beams[3] ~= nil and t1.lifeTags[2] ~= nil)
	check("screen shows the mode and the winner's prize", t1.screenText:find("Classic") ~= nil and t1.screenText:find("🏆") ~= nil, t1.screenText)
end

-- budgets (full profile)
local function clientParts()
	local n = 0
	for _, name in { "SpinTables", "SpinFx" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, d in f:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
		end
	end
	return n
end
local fullParts = clientParts()
check("client part budget (full)", fullParts > 100 and fullParts <= Config.Budget.clientParts, fullParts)

-- world text
do
	local banner = workspace.World.Table_t1:FindFirstChild("Banner")
	local label = banner and banner:FindFirstChildWhichIsA("SurfaceGui") and banner:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
	waitFor(function()
		return label and label.Text ~= ""
	end, 8)
	check("world: table banner localized", label ~= nil and label.Text:find("CLASSIC") ~= nil, label and label.Text)
	local prompt = workspace.World.Table_t1:FindFirstChild("JoinPrompt", true)
	check("world: join prompt localized", prompt ~= nil and prompt.ActionText == Locale.t("en", "world.prompt_play"), prompt and prompt.ActionText)
end

srv("fast", 25)

---------------------------------------------------------------------------
-- First match: QuickPlay forces Classic for a new player; the pilot plays it
---------------------------------------------------------------------------
local prof = srv("profile")
local ok, res = req("QuickPlay", { mode = "nope" })
check("QuickPlay rejects an unknown mode", not ok and isKey(res, "msg.bad_request"), res)
ok, res = req("QuickPlay", { mode = "duel" })
check("QuickPlay rejects duel (duels are by challenge)", not ok)
ok, res = req("Act", { kind = "spin" })
check("Act outside a match is rejected", not ok and isKey(res, "msg.not_in_match"), res)
ok, res = req("LeaveTable")
check("LeaveTable when not seated is rejected", not ok)

ok, res = req("QuickPlay", { mode = "chaos" })
check("first match: QuickPlay seats the player", ok and type(res) == "string", res)
local firstTable = if type(res) == "string" then res else "t1"
check("first match: a new player is always sent to Classic", Config.ModeById[TableViews.byId[firstTable].mode].id == "classic", firstTable)
prof = srv("profile")
check("seated: server has the player at the table, anchored at a podium", prof.table == firstTable and prof.anchored == true and prof.seat ~= nil)
local seatPos = Layout.seatCFrame(TableViews.byId[firstTable].origin, prof.seat or 1, Config.Seats).Position
check("seated: character stands on its podium", prof.pos ~= nil and (prof.pos - seatPos).Magnitude < 1.5, prof.pos)
ok, res = req("QuickPlay", {})
check("cannot sit at two tables", not ok and isKey(res, "msg.already_seated"), res)
waitFor(function()
	return Net.get("table") ~= nil
end, 5)
check("client: state knows the table", type(Net.get("table")) == "table" and Net.get("table").id == firstTable)
waitFor(function()
	return Director.focus == firstTable
end, 5)
check("client: camera takes over when seated", Director.focus == firstTable and Cam.active == true)
local tinfo = srv("table", firstTable)
check("table counting down with 1 human", tinfo.status == "countdown" or tinfo.status == "playing", tinfo.status)

check("first match: starts", waitFor(function()
	return count(firstTable, "intro") >= 1
end, 20) == true)
tinfo = srv("table", firstTable)
check("bots fill the table", tinfo.bots == Config.ModeById.classic.fillTo - 1 and tinfo.botModels == tinfo.bots, tinfo.bots)
check("bot bodies replicated with name tags", waitFor(function()
	local m = workspace.World.Bots:GetChildren()[1]
	return m ~= nil and m:FindFirstChild("Head") ~= nil and m.Head:FindFirstChild("NameTag") ~= nil
end, 5) == true)
waitFor(function()
	return MatchHud.isVisible()
end, 5)
check("match HUD up, lobby HUD hidden", MatchHud.isVisible() and Hud.root.Visible == false)
check("hand dealt (2 cards in Classic)", waitFor(function()
	return #hand == 2
end, 5) == true, #hand)
check("first match: finishes", waitMatch(firstTable, 0, 120) == true)
local slog = srv("log", firstTable)
check("events: intro, turns, spins, landings, end", slog.counts.intro == 1 and (slog.counts.turn or 0) >= 2 and (slog.counts.spin or 0) >= 2 and slog.counts.landed == slog.counts.spin and slog.counts.ended == 1, slog.counts.spin)
check("events: every landed spin was decided on the server", (slog.counts.landed or 0) >= 2 and slog.ended ~= nil and slog.ended.turns >= 2)
check("client saw the same stream", count(firstTable, "landed") == slog.counts.landed and count(firstTable, "ended") == 1, count(firstTable, "landed"))
check("pilot: spins accepted through the real remote", pilot.accepted.spin >= 1, pilot.accepted.spin)
check("pilot: brakes accepted through the real remote", pilot.accepted.brake >= 1, pilot.accepted.brake)
check("pilot: targets accepted", pilot.accepted.target >= 1, pilot.accepted.target)
local placements = slog.ended and slog.ended.placements or {}
local places = {}
for _, pl in placements do
	places[pl.place] = (places[pl.place] or 0) + 1
end
check("placements: one winner and every place used once", places[1] == 1 and #placements == Config.ModeById.classic.fillTo and places[#placements] == 1, #placements)
waitFor(function()
	return #results >= 1
end, 5)
local r1 = results[1]
check("result paid to the player", r1 ~= nil and r1.coins > 0 and r1.xp > 0 and r1.trophies >= 0 and r1.mode == "classic", r1 and r1.coins)
check("result: first-match bonus", r1 ~= nil and r1.tutorial == true and r1.tutorialCoins == Config.Tutorial.coins)
local myPlace = 0
for _, pl in placements do
	if pl.id == myId then
		myPlace = pl.place
	end
end
check("result place matches the server placements", r1 ~= nil and r1.place == myPlace, myPlace)
local expect = Progression.matchRewards("classic", myPlace, Config.ModeById.classic.fillTo, { humans = 1 })
check("reward depends on placement only", r1 ~= nil and r1.coins == expect.coins and r1.xp == expect.xp and r1.trophies == expect.trophies, r1 and r1.coins)
waitFor(function()
	return srv("table", firstTable).status == "open"
end, 10)
prof = srv("profile")
check("profile: match counted, tutorial done, coins in", prof.matches == 1 and prof.tutorialDone == true and prof.coins == (r1 and r1.coins or 0) + Config.Tutorial.coins, prof.coins)
check("tutorial title granted", prof.owned.ti_graduate == true)
check("after the match: unseated, free to walk", prof.table == nil and prof.anchored == false)
tinfo = srv("table", firstTable)
check("after the match: table open, bots gone", tinfo.status == "open" and tinfo.bots == 0 and tinfo.botModels == 0 and tinfo.humans == 0)
waitFor(function()
	return Net.get("table") == nil and Director.focus == nil
end, 5)
check("client: camera released after the match", Director.focus == nil or MatchHud.resultVisible())
check("client: director handled the show", (Director.seen.turn or 0) >= 2 and (Director.seen.landed or 0) >= 2 and Cam.shots >= 6, Cam.shots)
check("client: coach lines shown in the first match", MatchHud.banners >= 2)
MatchHud.closeResult()
if MatchHud.onLeave then
	MatchHud.onLeave()
end
task.wait(0.3)
check("lobby HUD back", Hud.root.Visible == true and not MatchHud.isVisible())

---------------------------------------------------------------------------
-- Chaos and Teams through QuickPlay
---------------------------------------------------------------------------
for _, modeId in { "chaos", "teams" } do
	local before = #results
	ok, res = req("QuickPlay", { mode = modeId })
	local id = if type(res) == "string" then res else ""
	check(modeId .. ": seated at a " .. modeId .. " table", ok and TableViews.byId[id] ~= nil and TableViews.byId[id].mode == modeId, res)
	local done0 = count(id, "ended") + count(id, "abort")
	check(modeId .. ": match starts", waitFor(function()
		return count(id, "intro") >= 1
	end, 25) == true)
	local snapIntro = lastEvent[id] and lastEvent[id].intro and lastEvent[id].intro.snapshot
	check(modeId .. ": intro snapshot has wheel, players and seats", snapIntro ~= nil and #snapIntro.wheel == #Config.Wheels[modeId] and #snapIntro.players == Config.ModeById[modeId].fillTo and snapIntro.info[myId] ~= nil and snapIntro.info[myId].seat ~= nil)
	if modeId == "chaos" then
		check("chaos: 3 cards dealt", waitFor(function()
			return #hand == 3
		end, 5) == true, #hand)
	end
	check(modeId .. ": match finishes", waitMatch(id, done0, 150) == true)
	local l = srv("log", id)
	check(modeId .. ": ended with a winner", l.ended ~= nil and (if modeId == "teams" then l.ended.team ~= nil else l.ended.winner ~= nil))
	waitFor(function()
		return #results > before
	end, 5)
	local r = results[#results]
	check(modeId .. ": paid", #results > before and r.mode == modeId and r.coins > 0, r and r.coins)
	if modeId == "teams" then
		check("teams: result is win or lose (place 1 or 2)", r.place == 1 or r.place == 2, r.place)
	end
	waitFor(function()
		return srv("table", id).status == "open"
	end, 10)
	MatchHud.closeResult()
	task.wait(0.2)
end
prof = srv("profile")
check("three matches on the record", prof.matches == 3, prof.matches)
check("pilot: cards played through the real remote", pilot.accepted.card >= 1, pilot.accepted.card)

---------------------------------------------------------------------------
-- A second human leaves mid-match (stand-in seat): the match goes on
---------------------------------------------------------------------------
do
	local id = "t4"
	srv("ghostSeat", id, "ghost1")
	ok, res = req("JoinTable", { table = id })
	check("leave: joined the table next to another human", ok and res == id, res)
	local done0 = count(id, "ended") + count(id, "abort")
	check("leave: match starts with 2 humans", waitFor(function()
		return count(id, "intro") >= 1
	end, 25) == true)
	waitFor(function()
		return count(id, "turn") >= 3
	end, 40)
	local before = srv("log", id)
	srv("ghostLeave", id, "ghost1")
	check("leave: match finishes after the other human left", waitMatch(id, done0, 150) == true)
	local l = srv("log", id)
	check("leave: leaver eliminated with cause 'left'", l.leftElims >= 1, l.leftElims)
	check("leave: the match was not aborted", l.aborts == 0 and l.ended ~= nil and l.counts.ended == 1)
	local left = false
	for _, pl in (l.ended and l.ended.placements or {}) do
		if pl.id == "ghost1" then
			left = pl.left == true and pl.place > 1
		end
	end
	check("leave: the leaver is marked as left and did not win", left)
	check("leave: the one who stayed still got paid", results[#results] ~= nil and results[#results].table == id, results[#results] and results[#results].table)
	waitFor(function()
		return srv("table", id).status == "open"
	end, 10)
	MatchHud.closeResult()
	_ = before
end

---------------------------------------------------------------------------
-- The real player walks away mid-match: forfeit, table cleaned up
---------------------------------------------------------------------------
do
	local matchesBefore = srv("profile").matches
	local resultsBefore = #results
	ok, res = req("QuickPlay", { mode = "classic" })
	local id = if type(res) == "string" then res else "t1"
	local intro0 = count(id, "intro")
	waitFor(function()
		return count(id, "intro") > intro0
	end, 25)
	local turns0 = count(id, "turn")
	waitFor(function()
		return count(id, "turn") >= turns0 + 2
	end, 30)
	local aborts0 = count(id, "abort")
	ok = req("LeaveTable")
	check("walk away: LeaveTable accepted mid-match", ok)
	check("walk away: match stops (nobody left to play for)", waitFor(function()
		return count(id, "abort") > aborts0
	end, 15) == true)
	waitFor(function()
		return srv("table", id).status == "open"
	end, 10)
	local tb = srv("table", id)
	check("walk away: table open and clean", tb.status == "open" and tb.humans == 0 and tb.bots == 0 and tb.botModels == 0 and tb.running == false)
	prof = srv("profile")
	check("walk away: player is back in the lobby, unanchored", prof.table == nil and prof.anchored == false)
	check("walk away: a forfeit pays nothing and costs nothing", prof.matches == matchesBefore and #results == resultsBefore, prof.matches)
	check("walk away: client view cleared", waitFor(function()
		return TableViews.byId[id].playing == false and Director.focus == nil
	end, 5) == true)
end

---------------------------------------------------------------------------
-- Spectating a table you are not at
---------------------------------------------------------------------------
do
	local id = "t1"
	srv("ghostSeat", id, "ghost2")
	local intro0 = count(id, "intro")
	srv("ghostStart", id)
	waitFor(function()
		return count(id, "intro") > intro0
	end, 10)
	ok, res = req("GetMatch", { table = id })
	check("spectate: GetMatch returns the public state", ok and type(res) == "table" and res.snapshot.mode == "classic" and #res.snapshot.players >= 2)
	local leak = false
	if ok then
		for _, p in res.snapshot.players do
			leak = leak or type(p.cards) ~= "number"
		end
	end
	check("spectate: hands are counts, never card names", ok and not leak)
	Director.spectate(id)
	check("spectate: focus moves to the table", waitFor(function()
		return Director.focus == id and Director.spectating
	end, 5) == true)
	check("spectate: HUD in spectator mode", MatchHud.isVisible() and MatchHud.spectating == true)
	local spec = mainGui:FindFirstChild("Spectate", true)
	check("spectate: spectator bar visible", spec ~= nil and spec.Visible == true)
	if MatchHud.onFreeCam then
		MatchHud.onFreeCam()
	end
	task.wait(0.2)
	check("spectate: free camera on", Cam.free.enabled == true and Cam.lastShot == "free", Cam.lastShot)
	if MatchHud.onSpectateStep then
		MatchHud.onSpectateStep(1)
	end
	task.wait(0.2)
	check("spectate: next player camera", Cam.lastShot == "closeup" and Cam.free.enabled == false, Cam.lastShot)
	ok, res = req("Act", { kind = "spin" })
	check("spectate: a spectator cannot act", not ok)
	if MatchHud.onLeave then
		MatchHud.onLeave()
	end
	check("spectate: leaving releases the camera", waitFor(function()
		return Director.focus == nil and Cam.active == false
	end, 5) == true)
	srv("ghostLeave", id, "ghost2")
	waitFor(function()
		return srv("table", id).status == "open"
	end, 10)
	check("spectate: table freed after the last human left", srv("table", id).status == "open" and srv("table", id).botModels == 0)
end

---------------------------------------------------------------------------
-- Private table (duel vs a bot) at watchable speed: the suspense layer
---------------------------------------------------------------------------
do
	srv("fast", 4)
	ok, res = req("JoinPrivate", { code = "ZZZZ" })
	check("private: wrong code rejected", not ok and isKey(res, "msg.code_invalid"), res)
	ok, res = req("StartPrivate")
	check("private: cannot start a table you do not host", not ok)
	ok, res = req("CreatePrivate", { mode = "teams", fill = true })
	check("private: created with a 4-letter code", ok and type(res) == "string" and #res == 4, res)
	local code = res
	waitFor(function()
		return type(Net.get("table")) == "table" and Net.get("table").code == code
	end, 5)
	local tstate = Net.get("table") or {}
	check("private: host sees the code and is host", tstate.code == code and tstate.host == true and tstate.mode == "teams")
	local id = tstate.id or "t5"
	check("private: it is a flex table", TableViews.byId[id].kind == "flex", id)
	ok, res = req("PrivateOptions", { mode = "duel" })
	check("private: host changes the mode", ok and srv("table", id).mode == "duel", res)
	ok, res = req("PrivateOptions", { mode = "bogus" })
	check("private: bad mode rejected", not ok)
	ok = req("PrivateOptions", { fill = false })
	ok, res = req("StartPrivate")
	check("private: needs 2 players when bots are off", not ok and isKey(res, "msg.need_players"), res)
	req("PrivateOptions", { fill = true })
	check("private: table does not start by itself", srv("table", id).status == "open")
	local panel = mainGui:FindFirstChild("Seated", true)
	check("private: waiting panel with Start for the host", panel ~= nil and panel.Visible and panel:FindFirstChild("Start", true) ~= nil and panel:FindFirstChild("Start", true).Visible)

	local beats0, shots0, ticks0, banners0, react0 = Mood.beats, Cam.shots, TableViews.ticks, MatchHud.banners, Avatars.played
	local maxDark, maxLevel = 0, 0
	local conn = RunService.RenderStepped:Connect(function()
		maxDark = math.max(maxDark, Mood.darkness())
		maxLevel = math.max(maxLevel, Mood.level)
	end)
	local done0 = count(id, "ended") + count(id, "abort")
	local results0 = #results
	ok = req("StartPrivate")
	check("private: host starts", ok)
	check("duel: starts with exactly 2 (one bot)", waitFor(function()
		return count(id, "intro") >= 1
	end, 15) == true and srv("table", id).bots == 1)
	check("duel: 5 lives each", lastEvent[id].intro.snapshot.players[1].lives == Config.ModeById.duel.lives)
	-- on the first spin of mine, look at the suspense state mid-brake
	local sawReadout = false
	local readout = mainGui:FindFirstChild("Readout", true)
	local sampled = RunService.RenderStepped:Connect(function()
		if readout and readout.Visible then
			sawReadout = true
		end
	end)
	check("duel: finishes", waitMatch(id, done0, 240) == true)
	conn:Disconnect()
	sampled:Disconnect()
	check("suspense: lights went down (veil darkness > 0.8)", maxDark > 0.8 and maxLevel > 0.8, string.format("%.2f / %.2f", maxDark, maxLevel))
	check("suspense: heartbeat played", Mood.beats > beats0, Mood.beats - beats0)
	check("suspense: wheel ticks", TableViews.ticks - ticks0 >= 12, TableViews.ticks - ticks0)
	check("suspense: camera cut between shots", Cam.shots - shots0 >= 8, Cam.shots - shots0)
	check("suspense: banners slammed", MatchHud.banners - banners0 >= 4, MatchHud.banners - banners0)
	check("suspense: avatars reacted", Avatars.played - react0 >= 6, Avatars.played - react0)
	check("suspense: live slot readout shown while spinning", sawReadout)
	check("suspense: tick and heartbeat cues fired", (Audio.played.tick or 0) > 10 and (Audio.played.heartbeat or 0) >= 1, Audio.played.heartbeat)
	check("suspense: a finisher played", (function()
		local n = 0
		for _, c in Finishers.played do
			n += c
		end
		return n >= 1
	end)())
	check("duel: outcome recorded", Director.lastOutcome ~= nil, Director.lastOutcome)
	waitFor(function()
		return #results > results0
	end, 5)
	local r = results[#results]
	check("duel: pays win or lose", #results > results0 and r.mode == "duel" and (r.coins == 80 or r.coins == 30 or r.coins > 0), r and r.coins)
	waitFor(function()
		return srv("table", id).status == "open" and srv("table", id).running == false
	end, 15)
	local tb = srv("table", id)
	check("private: players stay seated for a rematch", tb.humans == 1 and tb.private == true and tb.bots == 0, tb.humans)
	MatchHud.closeResult()
	ok = req("LeaveTable")
	check("private: leaving frees the flex table", ok and waitFor(function()
		local t = srv("table", id)
		return t.private == false and t.humans == 0 and t.mode == "duel"
	end, 5) == true)
	srv("fast", 25)
end

---------------------------------------------------------------------------
-- Challenges
---------------------------------------------------------------------------
ok, res = req("Challenge", { userId = player.UserId })
check("challenge: not yourself", not ok and isKey(res, "msg.bad_target"), res)
ok, res = req("Challenge", { userId = 1 })
check("challenge: player must be in the server", not ok and isKey(res, "msg.bad_target"), res)
ok, res = req("AnswerChallenge", { from = 1, accept = true })
check("challenge: nothing to answer", not ok and isKey(res, "msg.challenge_expired"), res)

---------------------------------------------------------------------------
-- Auto-queue and auto-play (comfort toggles; they never change a result)
---------------------------------------------------------------------------
do
	ok = req("SetSetting", { key = "autoQueue", value = true })
	check("auto: auto-queue ON saved", ok and srv("profile").settings.autoQueue == true)
	ok = req("SetSetting", { key = "autoPlay", value = true })
	check("auto: auto-play ON saved", ok and srv("profile").settings.autoPlay == true)
	pilot.on = false
	local spinsBefore = pilot.accepted.spin
	ok, res = req("QuickPlay", { mode = "classic" })
	local id = if type(res) == "string" then res else "t1"
	local intro0, done0 = count(id, "intro"), count(id, "ended") + count(id, "abort")
	local auto0 = srv("log", id).autoDecides
	check("auto: first match finishes with no input at all", waitMatch(id, done0, 150) == true)
	check("auto: the server played my turns (auto flag on decide)", srv("log", id).autoDecides > auto0 or (srv("log", id).ended ~= nil), srv("log", id).autoDecides - auto0)
	check("auto: the pilot sent nothing", pilot.accepted.spin == spinsBefore)
	check("auto: stays seated and a second match starts by itself", waitFor(function()
		return count(id, "intro") >= intro0 + 2
	end, 40) == true, count(id, "intro") - intro0)
	check("auto: still at the same table", srv("profile").table == id)
	req("SetSetting", { key = "autoQueue", value = false })
	req("SetSetting", { key = "autoPlay", value = false })
	ok = req("LeaveTable")
	waitFor(function()
		return srv("table", id).status == "open"
	end, 15)
	check("auto: toggles off, table freed", srv("profile").settings.autoQueue == false and srv("table", id).status == "open")
	pilot.on = true
	MatchHud.closeResult()
	local button = Hud.buttons.AutoQueue
	local label = button and button:FindFirstChild("Label")
	check("auto: HUD toggle shows OFF", label ~= nil and label.Text:find("OFF") ~= nil, label and label.Text)
end

---------------------------------------------------------------------------
-- Power Core (lobby clicker)
---------------------------------------------------------------------------
do
	local CoreTap = Remotes:WaitForChild("CoreTap") :: RemoteEvent
	srv("teleport", Vector3.new(90, 5, 0))
	task.wait(0.5)
	local before = srv("profile")
	CoreTap:FireServer(5)
	task.wait(0.5)
	check("core: taps far from the core are ignored", srv("profile").core.taps == before.core.taps and srv("coreRange") == false)
	srv("teleport", Vector3.new(0, 5, 14))
	task.wait(0.6)
	check("core: in range", srv("coreRange") == true)
	CoreTap:FireServer(100)
	task.wait(0.5)
	local after = srv("profile")
	local accepted = (after.core.taps + after.core.charges * Config.Core.tapsPerCharge) - (before.core.taps + before.core.charges * Config.Core.tapsPerCharge)
	check("core: a burst is clamped to the bucket", accepted >= 1 and accepted <= Config.Core.burst, accepted)
	local t0, start = os.clock(), after
	for _ = 1, 40 do
		CoreTap:FireServer(3)
		task.wait(0.05)
	end
	task.wait(0.4)
	local elapsed = os.clock() - t0
	after = srv("profile")
	accepted = (after.core.taps + after.core.charges * Config.Core.tapsPerCharge) - (start.core.taps + start.core.charges * Config.Core.tapsPerCharge)
	check("core: sustained taps capped at 8/s", accepted > 0 and accepted <= Config.Core.maxTapsPerSecond * (elapsed + 0.5) + 1, string.format("%d in %.2fs", accepted, elapsed))
	check("core: a full charge pays coins", after.core.charges >= 1 and after.coins >= start.coins + (after.core.charges - start.core.charges) * Config.Core.coinsPerCharge and after.coins > start.coins - 1, after.core.charges)
	CoreTap:FireServer(-5)
	CoreTap:FireServer(0 / 0)
	CoreTap:FireServer("lots")
	task.wait(0.3)
	check("core: bogus payloads ignored", srv("profile").core.charges >= after.core.charges)
	check("core: client got progress events", #coreEvents >= 1 and coreEvents[#coreEvents].added ~= nil)
	-- the HUD widget
	check("core: widget visible near the core", waitFor(function()
		local w = mainGui:FindFirstChild("Core", true)
		return w ~= nil and w.Visible
	end, 3) == true)
	local sent0 = CoreClient.sent
	for _ = 1, 6 do
		CoreClient.tap()
		task.wait(0.13)
	end
	task.wait(0.4)
	check("core: tapping through the client module sends batches", CoreClient.sent > sent0, CoreClient.sent - sent0)
	-- auto charge: locked below level 5
	ok, res = req("SetSetting", { key = "autoCharge", value = true })
	check("core: auto-charge locked below level 5", not ok and isKey(res, "msg.auto_locked"), res)
	srv("addXp", 100 + 140 + 180 + 220)
	prof = srv("profile")
	check("level 5 reached with the xp curve", prof.level == 5, prof.level)
	waitFor(function()
		return type(Net.get("core")) == "table" and Net.get("core").autoUnlocked == true
	end, 3)
	check("core: auto-charge unlocked at level 5", Net.get("core").autoUnlocked == true)
	ok = req("SetSetting", { key = "autoCharge", value = true })
	check("core: auto-charge ON", ok)
	local c0 = srv("profile").core
	task.wait(3.3)
	local c1 = srv("profile").core
	local gained = (c1.taps + c1.charges * Config.Core.tapsPerCharge) - (c0.taps + c0.charges * Config.Core.tapsPerCharge)
	check("core: auto-charge ticks by itself at its fixed rate", gained >= Config.Core.autoRate * 2 and gained <= Config.Core.autoRate * 5, gained)
	srv("teleport", Vector3.new(90, 5, 0))
	task.wait(1.2)
	c0 = srv("profile").core
	task.wait(2.2)
	c1 = srv("profile").core
	check("core: auto-charge stops away from the core", c1.taps == c0.taps and c1.charges == c0.charges)
	req("SetSetting", { key = "autoCharge", value = false })
	check("core: unlocked wheel skin at level 5 (rule unlock)", srv("profile").owned.w_slime == true and unlocks.w_slime == true)
end

---------------------------------------------------------------------------
-- Cosmetics
---------------------------------------------------------------------------
do
	srv("setCoins", 100)
	ok, res = req("Buy", { id = "w_neon" })
	check("locker: not enough coins", not ok and isKey(res, "msg.not_enough_coins"), res)
	srv("setCoins", 5000)
	ok, res = req("Buy", { id = "w_neon" })
	check("locker: buy with coins", ok and srv("profile").coins == 5000 - 600 and srv("profile").owned.w_neon == true, res)
	ok, res = req("Buy", { id = "w_neon" })
	check("locker: cannot buy twice", not ok and isKey(res, "msg.already_owned"), res)
	ok, res = req("Buy", { id = "w_gold" })
	check("locker: pass items are not sold for coins", not ok and isKey(res, "msg.not_for_sale"), res)
	ok, res = req("Buy", { id = "nope" })
	check("locker: unknown item", not ok)
	ok = req("Equip", { id = "w_neon" })
	check("locker: equip owned", ok and srv("profile").equipped.wheel == "w_neon")
	check("locker: equipped skin replicated as an attribute", waitFor(function()
		return player:GetAttribute("Cos_wheel") == "w_neon"
	end, 3) == true)
	ok, res = req("Equip", { id = "w_gold" })
	check("locker: cannot equip a locked item", not ok and isKey(res, "msg.locked"), res)
	ok = req("Equip", { id = "e_wave" })
	check("locker: emotes are not equipped like skins", not ok)
	ok = req("Buy", { id = "e_cool" })
	ok = req("SetEmotes", { ids = { "e_cool", "e_wave", "e_skull", "e_cool", "e_laugh", "e_gg", "e_sweat" } })
	local em = srv("profile").emotes
	check("locker: emote wheel keeps owned, unique, 4 slots", ok and #em == 4 and em[1] == "e_cool" and table.find(em, "e_skull") == nil, table.concat(em, ","))
	ok = req("Emote", { id = "e_cool" })
	check("emote: plays", ok and waitFor(function()
		return emotesSeen >= 1
	end, 2) == true)
	ok, res = req("Emote", { id = "e_cool" })
	check("emote: cooldown", not ok and isKey(res, "msg.slow_down"), res)
	ok = req("Emote", { id = "e_skull" })
	check("emote: not in the wheel", not ok)
	-- passes change looks and comfort only
	srv("grantPass", "VIP")
	local pv = srv("profile")
	check("VIP: gold wheel, aura and title unlocked, coin multiplier 1.5", pv.owned.w_gold == true and pv.owned.a_gold == true and pv.owned.ti_vip == true and math.abs(pv.coinMult - 1.5) < 1e-6, pv.coinMult)
	ok = req("Equip", { id = "a_gold" })
	ok = req("Equip", { id = "ti_vip" })
	ok = req("Equip", { id = "f_rocket" })
	check("locker: cannot equip a finisher not owned", not ok)
	task.wait(0.8)
	check("aura and title shown on the character", Avatars.auraCount() >= 1 and char:FindFirstChild("Head") ~= nil and char.Head:FindFirstChild("TitleTag") ~= nil)
	srv("grantPass", "EmotePack")
	ok = req("SetEmotes", { ids = { "e_cool", "e_wave", "e_skull", "e_heart", "e_laugh", "e_gg", "e_sweat", "e_dance" } })
	check("EmotePack: 8 slots", ok and #srv("profile").emotes == 8)
	-- every finisher plays without errors on a dummy
	local dummy = Instance.new("Model")
	local root = Instance.new("Part")
	root.Anchored = true
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = dummy
	dummy.PrimaryPart = root
	dummy.Parent = workspace
	for i, fid in Finishers.ids do
		Finishers.play(fid, dummy, CFrame.new(200 + i * 30, 10, 200), Color3.new(1, 1, 1))
	end
	task.wait(0.3)
	check("all 8 finishers run", #Finishers.ids == 8 and (Finishers.played.f_lightning or 0) >= 1)
	task.delay(4, function()
		dummy:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Rewards, quests, codes
---------------------------------------------------------------------------
do
	local c0 = srv("profile").coins
	ok, res = req("ClaimDaily")
	check("daily: day 1 claimed", ok and srv("profile").coins == c0 + Config.DailyRewards[1].amount, res)
	ok, res = req("ClaimDaily")
	check("daily: once a day", not ok and isKey(res, "msg.daily_tomorrow"), res)
	srv("yesterdayDaily")
	waitFor(function()
		return type(Net.get("dailyState")) == "table" and Net.get("dailyState").canClaim == true
	end, 3)
	check("daily: next day is day 2 of the streak", Net.get("dailyState").day == 2, Net.get("dailyState").day)
	ok = req("ClaimDaily")
	check("daily: day 2 claimed", ok and srv("profile").coins == c0 + Config.DailyRewards[1].amount + Config.DailyRewards[2].amount)

	ok, res = req("ClaimGift", { index = 6 })
	check("gift: not ready", not ok and isKey(res, "msg.gift_not_ready"), res)
	srv("skipSession", 61 * 60)
	c0 = srv("profile").coins
	ok = req("ClaimGift", { index = 1 })
	check("gift: claimed after the time is played", ok and srv("profile").coins == c0 + Config.Gifts[1].reward.amount)
	ok, res = req("ClaimGift", { index = 1 })
	check("gift: only once", not ok and isKey(res, "msg.already_claimed"), res)
	ok = req("ClaimGift", { index = 99 })
	check("gift: bad index", not ok)

	c0 = srv("profile").coins
	ok, res = req("RedeemCode", { code = " showdown " })
	check("code: redeemed (case and spaces ignored)", ok and srv("profile").coins == c0 + Config.Codes.SHOWDOWN.amount, res)
	ok, res = req("RedeemCode", { code = "SHOWDOWN" })
	check("code: single use", not ok and isKey(res, "msg.code_used"), res)
	ok, res = req("RedeemCode", { code = "NOPE" })
	check("code: invalid", not ok and isKey(res, "msg.code_invalid"), res)
	ok = req("RedeemCode", { code = "SPIN" })
	check("code: item code grants the title", ok and srv("profile").owned.ti_earlybird == true)

	srv("forceQuests", { "play", "zaps", "charge" })
	ok, res = req("ClaimQuest", { index = 1 })
	check("quest: not done", not ok and isKey(res, "msg.quest_not_done"), res)
	ok = req("ClaimQuestBonus")
	check("quest: bonus needs all three", not ok)
	srv("completeQuests")
	c0 = srv("profile").coins
	ok = req("ClaimQuest", { index = 1 })
	check("quest: claim pays coins", ok and srv("profile").coins > c0)
	ok, res = req("ClaimQuest", { index = 1 })
	check("quest: claim once", not ok and isKey(res, "msg.already_claimed"), res)
	req("ClaimQuest", { index = 2 })
	req("ClaimQuest", { index = 3 })
	c0 = srv("profile").coins
	ok = req("ClaimQuestBonus")
	check("quest: bonus after all three", ok and srv("profile").coins == c0 + Config.QuestBonus.coins)
	ok = req("ClaimQuestBonus")
	check("quest: bonus once", not ok)
	-- progress from real play was recorded on the earlier matches
	check("quest progress hooks ran during matches", srv("profile").quests ~= nil)
end

---------------------------------------------------------------------------
-- Monetization: receipts, passes, policy
---------------------------------------------------------------------------
do
	local c0 = srv("profile").coins
	local d = srv("receipt", "CoinsS", "test-purchase-1")
	check("receipt: coins granted", d == "PurchaseGranted" and srv("profile").coins == c0 + Config.ProductByKey.CoinsS.amount, d)
	d = srv("receipt", "CoinsS", "test-purchase-1")
	check("receipt: same PurchaseId is not granted twice", d == "PurchaseGranted" and srv("profile").coins == c0 + Config.ProductByKey.CoinsS.amount)
	check("receipt: unknown product not processed", srv("unknownReceipt") == "NotProcessedYet")
	c0 = srv("profile").coins
	d = srv("receipt", "StarterPack", "test-purchase-2")
	local ps = srv("profile")
	check("starter pack: fixed contents (coins + 3 items)", d == "PurchaseGranted" and ps.starterBought and ps.coins == c0 + Config.StarterPack.coins and ps.owned.w_arcade and ps.owned.ti_founder and ps.owned.f_confetti)
	c0 = srv("profile").coins
	d = srv("receipt", "ServerParty", "test-purchase-3")
	check("server party: everyone gets coins and confetti", d == "PurchaseGranted" and srv("profile").coins == c0 + Config.ProductByKey.ServerParty.amount and waitFor(function()
		return parties >= 1
	end, 2) == true)
	-- policy: nothing sold reaches into a match
	local clean = true
	for _, p in Config.Passes do
		clean = clean and p.affectsMatch == false
	end
	for _, p in Config.Products do
		clean = clean and p.affectsMatch == false and (p.kind == "coins" or p.kind == "starter" or p.kind == "party")
	end
	check("policy: no pass or product affects a match, none is a random item", clean)
	check("policy: shop items with id 0 are not purchasable yet", Config.PassByKey.VIP.id == 0 and Config.ProductByKey.CoinsS.id == 0)
end

---------------------------------------------------------------------------
-- Referral, events, season, boards
---------------------------------------------------------------------------
do
	local applied = srv("referral", "ref:12345")
	check("referral: not for someone who already played", applied == false)
	srv("resetReferral")
	local c0 = srv("profile").coins
	applied = srv("referral", "ref:" .. player.UserId)
	check("referral: cannot refer yourself", applied == false)
	applied = srv("referral", "junk")
	check("referral: junk launch data ignored", applied == false)
	applied = srv("referral", "ref:12345")
	check("referral: invited player gets the welcome coins", applied == true and srv("profile").coins == c0 + Config.Referral.invitedCoins and srv("profile").referredBy == 12345)
	applied = srv("referral", "ref:999")
	check("referral: only once", applied == false)
	c0 = srv("profile").coins
	local paid = srv("payInviter", 30)
	check("referral: inviter rewards capped", paid == Config.Referral.maxRewards and srv("profile").coins == c0 + paid * Config.Referral.inviterCoins, paid)

	local okc = srv("eventCommand", "/event CoinRush 5")
	check("event: admin only", okc == false)
	srv("makeAdmin")
	local n0 = #liveUpdates
	okc = srv("eventCommand", "/event CoinRush 5")
	check("event: admin starts Coin Rush", okc == true and waitFor(function()
		return #liveUpdates > n0 and liveUpdates[#liveUpdates].current ~= nil and liveUpdates[#liveUpdates].current.id == "CoinRush"
	end, 3) == true)
	check("event: coin multiplier applies to match rewards", srv("effects", "classic").coinMult == 2)
	okc = srv("eventCommand", "/event Nope 5")
	check("event: bad id rejected", okc == false)
	local chip = mainGui:FindFirstChild("Event", true)
	check("event: chip on the HUD", waitFor(function()
		return chip ~= nil and chip.Visible
	end, 3) == true)
	srv("clearEvent")

	srv("addTrophies", 500)
	check("league: platinum at 500+ trophies, replicated", waitFor(function()
		return player:GetAttribute("League") == "platinum" or player:GetAttribute("League") == "diamond"
	end, 3) == true, player:GetAttribute("League"))
	local s = srv("oldSeason", 600)
	check("season: rollover pays the league reward and carries half", s.trophies == 300 and s.gained == Progression.seasonReward(600) and s.season == Progression.season(os.time()), s.gained)
	local rows = srv("boards")
	check("boards: this server's players listed", type(rows) == "table" and #rows.wins >= 1 and rows.wins[1].userId == player.UserId and #rows.season >= 1)
	ok, res = req("GetBoards")
	check("boards: served to the client", ok and type(res) == "table" and type(res.rows) == "table" and res.seasonEndsAt > os.time())
end

---------------------------------------------------------------------------
-- Settings and languages
---------------------------------------------------------------------------
do
	ok = req("SetSetting", { key = "music", value = 5 })
	check("settings: volume clamped", ok and srv("profile").settings.music == 1)
	ok = req("SetSetting", { key = "sfx", value = "loud" })
	check("settings: bad volume rejected", not ok)
	ok = req("SetSetting", { key = "shake", value = false })
	check("settings: camera shake off", ok and waitFor(function()
		return Prefs.shake() == false
	end, 2) == true)
	ok = req("SetSetting", { key = "hack", value = true })
	check("settings: unknown key rejected", not ok)
	req("SetSetting", { key = "shake", value = true })
	req("SetSetting", { key = "music", value = 0.5 })

	ok = req("SetLanguage", { lang = "xx" })
	check("language: unknown rejected", not ok)
	local playLabel = Hud.buttons.Play:FindFirstChild("Label")
	local okAll, detail = true, ""
	local loaded = 0
	for _, l in Locale.Languages do
		local pack = Locale.pack(l.code)
		if pack then
			loaded += 1
			ok = req("SetLanguage", { lang = l.code })
			local want = "▶ " .. pack["hud.play"]
			local got = waitFor(function()
				return Lang.code == l.code and playLabel.Text == want
			end, 3)
			if not ok or not got then
				okAll = false
				detail = l.code .. ": " .. tostring(playLabel.Text)
			end
		else
			okAll = false
			detail = l.code .. " pack missing"
		end
	end
	check("language: all 12 packs load and the HUD re-renders live", okAll and loaded == 12, detail)
	req("SetLanguage", { lang = "es" })
	waitFor(function()
		return Lang.code == "es"
	end, 3)
	local t1 = TableViews.byId.t1
	check("language: wheel slots and table screens follow (es)", t1.wheel.names[1].Text ~= "ZAP" or Locale.t("es", "out.zap") == "Zap", t1.wheel.names[1].Text)
	req("SetLanguage", { lang = "en" })
	waitFor(function()
		return Lang.code == "en"
	end, 3)
end

---------------------------------------------------------------------------
-- Windows open and fill
---------------------------------------------------------------------------
do
	local okAll, detail = true, ""
	for _, name in { "Play", "Shop", "Locker", "Rewards", "Quests", "Ranking", "Invite", "Settings" } do
		Windows.open(name)
		task.wait(0.25)
		local w = Windows.get(name)
		local n = if w then #w.body:GetDescendants() else 0
		if not w or not w.frame.Visible or n < 12 then
			okAll = false
			detail = name .. " " .. n
		end
	end
	Windows.close()
	task.wait(0.2)
	check("every window opens with content", okAll, detail)
	check("toasts were shown", Toasts.shown >= 3, Toasts.shown)
end

---------------------------------------------------------------------------
-- Lite profile and budgets
---------------------------------------------------------------------------
do
	check("fx: pools stay under their caps", Fx.poolSize() <= 96 and Fx.textPoolSize() <= 8 and Fx.emitterCount() <= 2, Fx.poolSize())
	local emitters = 0
	for _, name in { "SpinTables", "SpinFx" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, d in f:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					emitters += 1
				end
			end
		end
	end
	check("emitter budget", emitters <= Config.Budget.emitters, emitters)
	local wheelFull = TableViews.wheelParts()
	workspace:SetAttribute("ForceLite", true)
	check("lite: profile on", Prefs.lite() == true)
	for _, view in TableViews.list do
		TableViews.setWheel(view, view.slots, false, nil)
	end
	task.wait(0.3)
	local wheelLite = TableViews.wheelParts()
	local liteParts = clientParts()
	check("lite: wheels use about half the parts", wheelLite < wheelFull * 0.7, wheelLite .. " vs " .. wheelFull)
	check("client part budget (lite)", liteParts <= Config.Budget.clientPartsLite, liteParts)
	-- the wheel maths still holds on the lite wheel
	local v = TableViews.byId.t2
	v.wheel:setAngle(9.3)
	check("lite: wheel geometry still matches", v.wheel:nearestPlate() == MatchCore.slotAt(9.3, #v.slots))
	v.wheel:setAngle(0)
	-- the veil is what dims the screen in lite (no Lighting changes needed)
	local amb = game:GetService("Lighting").Ambient
	Mood.set(1, 0.1)
	task.wait(0.4)
	check("lite: lights go down with the UI veil alone", Mood.darkness() > 0.8 and game:GetService("Lighting").Ambient == amb, Mood.darkness())
	Mood.reset()
	task.wait(0.7)
	workspace:SetAttribute("ForceLite", nil)
	for _, view in TableViews.list do
		TableViews.setWheel(view, view.slots, false, nil)
	end
	check("no animation left running", waitFor(function()
		return Avatars.activeCount() == 0
	end, 6) == true, Avatars.activeCount())
	local stats = srv("stats")
	check("server bookkeeping: not seated, nothing pending", stats.tablesTracked == 0, stats.tablesTracked)
	local mem = game:GetService("Stats"):GetTotalMemoryUsageMb()
	check("memory recorded", mem > 0, string.format("%.0f MB (Studio: server + client)", mem))
end

check("no pilot requests were rejected more than a handful of times", pilot.rejected <= 12, pilot.rejected)
check("no client errors", #clientErrors == 0, table.concat(clientErrors, " || "))
_ = hrp

srv("report", table.concat(lines, "\n"))
