-- Screenshot showcase: every time the runner resizes the window a scene is (re)staged, so
-- each scene is captured once per size. Scenes are driven through the real Director with
-- scripted match events; nothing here exists in the published game.
--   workspace attributes: ShowcaseSizes (captures per scene, default 3), ShowcaseFrom
--   (first scene), ShowcaseLow (lowest graphics: real setting if allowed + everything that
--   level 1 drops switched off by hand, and the lite profile).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(Client:WaitForChild("Net"))
local Arena = Client:WaitForChild("Arena")
local TableViews = require(Arena:WaitForChild("TableViews"))
local Director = require(Arena:WaitForChild("Director"))
local Cam = require(Arena:WaitForChild("Cam"))
local Mood = require(Arena:WaitForChild("Mood"))
local Fx = require(Arena:WaitForChild("Fx"))
local UI = Client:WaitForChild("UI")
local MatchHud = require(UI:WaitForChild("MatchHud"))
local Windows = require(UI:WaitForChild("Windows"))
local Theme = require(UI:WaitForChild("Theme"))

local showcase = ReplicatedStorage:WaitForChild("__Showcase") :: RemoteEvent
local myId = "u" .. player.UserId
local perScene = tonumber(workspace:GetAttribute("ShowcaseSizes")) or 3
local from = tonumber(workspace:GetAttribute("ShowcaseFrom")) or 1
local low = workspace:GetAttribute("ShowcaseLow") == true

local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart")
while not TableViews.ready or not Net.state do
	task.wait(0.2)
end

-- lowest graphics
if low then
	workspace:SetAttribute("ForceLite", true)
	local okSet, errSet = pcall(function()
		(settings() :: any).Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	print("[TEST] showcase low quality: settings().Rendering " .. (if okSet then "applied" else "not allowed (" .. tostring(errSet) .. ")") .. "; level-1 losses also switched off by hand")
	Lighting.GlobalShadows = false
	for _, e in Lighting:GetChildren() do
		if e:IsA("PostEffect") or e:IsA("Atmosphere") then
			(e :: any).Parent = nil
		end
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = false
		end
	end
	for _, view in TableViews.list do
		TableViews.setWheel(view, view.slots, false, nil)
	end
end

-- free lobby camera
local lobbyCam: CFrame? = nil
RunService:BindToRenderStep("ShowcaseCam", Enum.RenderPriority.Camera.Value + 9, function()
	if lobbyCam and not Cam.active then
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = lobbyCam
		cam.FieldOfView = 70
	end
end)

local view = TableViews.byId.t1
local staged = false
local function stage()
	if staged then
		return
	end
	staged = true
	lobbyCam = nil
	showcase:FireServer("stage")
	local t0 = os.clock()
	while os.clock() - t0 < 8 do
		local n = 0
		for _ in view.lobbySeats do
			n += 1
		end
		if n >= 6 and type(Net.get("table")) == "table" then
			break
		end
		task.wait(0.1)
	end
	task.wait(0.4)
end
local function unstage()
	if not staged then
		return
	end
	staged = false
	Director.onMatch("t1", { t = "abort" })
	showcase:FireServer("unstage")
	task.wait(0.8)
end

-- A public snapshot built from who is seated. lives[i] by seat order; 0 = eliminated.
local function snapshot(lives: { number }, opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local seats = {}
	for seat in view.lobbySeats do
		table.insert(seats, seat)
	end
	table.sort(seats)
	local players, info = {}, {}
	local place = #seats
	for i, seat in seats do
		local s = view.lobbySeats[seat]
		local l = lives[i] or 3
		local alive = l > 0
		players[i] = { id = s.id, name = s.name, bot = s.bot, team = i, seat = i, lives = l, shields = (o.shields and o.shields[i]) or 0, cards = (o.cards and o.cards[i]) or 2, alive = alive, left = false, place = if alive then 0 else place }
		if not alive then
			place -= 1
		end
		info[s.id] = { seat = seat, userId = s.userId, color = s.color, variant = s.variant }
	end
	return {
		mode = "classic",
		phase = "decide",
		turn = o.turn or 5,
		round = o.round or 2,
		dir = 1,
		modifier = o.modifier,
		sudden = o.sudden == true,
		dmgBonus = 0,
		wheel = if o.sudden then Config.Wheels.sudden else Config.Wheels.classic,
		maxLives = 4,
		spinner = o.spinner or myId,
		owner = o.spinner or myId,
		target = o.target,
		double = false,
		passed = false,
		cardPlayed = false,
		players = players,
		info = info,
	}
end
local function ids(): { string }
	local seats = {}
	for seat in view.lobbySeats do
		table.insert(seats, seat)
	end
	table.sort(seats)
	local list = {}
	for _, seat in seats do
		table.insert(list, view.lobbySeats[seat].id)
	end
	return list
end
local function others(): { string }
	local list = {}
	for _, id in ids() do
		if id ~= myId then
			table.insert(list, id)
		end
	end
	return list
end
local function now(): number
	return workspace:GetServerTimeNow()
end
local function fire(e)
	Director.onMatch("t1", e)
end

local run = 0
local scenes: { { name: string, play: (number) -> () } } = {}
local function scene(name: string, play: (number) -> ())
	table.insert(scenes, { name = name, play = play })
end
local function alive(my: number): boolean
	return my == run
end

scene("lobby", function()
	unstage()
	Windows.close()
	lobbyCam = CFrame.lookAt(Vector3.new(30, 17, 74), Vector3.new(-6, 10, 0))
end)

scene("my turn", function()
	stage()
	local o = others()
	fire({ t = "intro", snapshot = snapshot({ 3, 3, 2, 3, 1, 3 }, { shields = { 0, 1, 0, 0, 0, 0 } }), tutorial = false, duration = 1 })
	MatchHud.setHand({ "oracle", "shield", "double" })
	task.wait(0.4)
	fire({ t = "turn", spinner = myId, turn = 5, round = 2 })
	fire({ t = "decide", spinner = myId, deadline = now() + 11, duration = 14, auto = false, snapshot = snapshot({ 3, 3, 2, 3, 1, 3 }, { shields = { 0, 1, 0, 0, 0, 0 } }) })
	task.wait(1)
	fire({ t = "aim", spinner = myId, target = o[3] })
end)

scene("wheel slowing", function(my)
	stage()
	local o = others()
	fire({ t = "decide", spinner = o[2], deadline = now() + 2, duration = 3, auto = false, snapshot = snapshot({ 2, 3, 2, 3, 1, 3 }, { spinner = o[2], target = myId }) })
	fire({ t = "turn", spinner = o[2], turn = 6, round = 2 })
	fire({ t = "aim", spinner = o[2], target = myId })
	task.wait(0.6)
	if not alive(my) then
		return
	end
	local t0 = now()
	fire({ t = "spin", spinner = o[2], target = myId, speed = 7, double = false, oracle = false, t0 = t0, r0 = 0, n = 12, minSpin = 0.7, maxSpin = 6 })
	task.wait(0.9)
	if not alive(my) then
		return
	end
	-- stops a hair inside DOOM (slot 5) after crawling across BACKFIRE
	local final = 12 * 3 + 4.07
	fire({ t = "landed", spinner = o[2], target = myId, phase = final - 15, travel = 15, final = final, slot = 5, outcome = "doom", double = false, tb = now(), speed = 7, n = 12, duration = 8.4 })
end)

scene("doom", function(my)
	stage()
	local o = others()
	fire({ t = "decide", spinner = o[2], deadline = now() + 2, duration = 3, auto = false, snapshot = snapshot({ 2, 3, 2, 3, 1, 3 }, { spinner = o[2], target = o[4] }) })
	fire({ t = "turn", spinner = o[2], turn = 6, round = 2 })
	fire({ t = "aim", spinner = o[2], target = o[4] })
	local final = 12 * 3 + 4.5
	fire({ t = "spin", spinner = o[2], target = o[4], speed = 7, double = false, oracle = false, t0 = now(), r0 = final - 16, n = 12, minSpin = 0.7, maxSpin = 6 })
	fire({ t = "landed", spinner = o[2], target = o[4], phase = final - 15, travel = 15, final = final, slot = 5, outcome = "doom", double = false, tb = now() - 2.3, speed = 7, n = 12, duration = 3 })
	task.wait(1.4)
	if not alive(my) then
		return
	end
	task.wait(3.6)
	if alive(my) then
		fire({ t = "hit", target = o[4], amount = 3, blocked = false, lives = 0, shields = 0, by = o[2], cause = "doom" })
	end
end)

scene("finisher", function(my)
	stage()
	local o = others()
	fire({ t = "decide", spinner = myId, deadline = now() + 2, duration = 3, auto = false, snapshot = snapshot({ 3, 3, 2, 3, 1, 3 }, { target = o[1] }) })
	task.wait(4.6)
	if not alive(my) then
		return
	end
	fire({ t = "hit", target = o[1], amount = 3, blocked = false, lives = 0, shields = 0, by = myId, cause = "doom" })
	fire({ t = "elim", player = o[1], place = 6, by = myId, cause = "doom" })
end)

scene("sudden death", function(my)
	stage()
	local o = others()
	fire({ t = "decide", spinner = myId, deadline = now() + 12, duration = 14, auto = false, snapshot = snapshot({ 2, 0, 0, 1, 0, 0 }, { round = 5, turn = 19 }) })
	task.wait(0.5)
	if not alive(my) then
		return
	end
	fire({ t = "sudden", wheel = Config.Wheels.sudden })
	task.wait(1)
	MatchHud.banner("💀 SUDDEN DEATH", "No more heals. Hits keep getting harder.", Theme.Red, 40)
	_ = o
end)

scene("winner", function(my)
	stage()
	fire({ t = "decide", spinner = myId, deadline = now() + 2, duration = 3, auto = false, snapshot = snapshot({ 2, 0, 0, 0, 0, 0 }, { round = 6, turn = 23, sudden = true }) })
	task.wait(0.4)
	local placements = {}
	for i, id in ids() do
		table.insert(placements, { id = id, place = if id == myId then 1 else i + 1, left = false })
	end
	fire({ t = "ended", winner = myId, placements = placements, turns = 23, results = {} })
	task.wait(1)
	MatchHud.banner("🏆 VICTORY", nil, Theme.Yellow, 40)
	local seat = Net.get("table").seat
	local pos = TableViews.seatCFrame(view, seat).Position
	while alive(my) do
		Fx.confetti(pos + Vector3.new(math.random(-6, 6), 7, math.random(-6, 6)), 16, 30)
		task.wait(0.45)
	end
end)

scene("results", function()
	stage()
	MatchHud.show(view, false)
	MatchHud.showResult({ table = "t1", mode = "classic", place = 1, n = 6, won = true, coins = 156, xp = 110, trophies = 26, streak = 4, level = 8, levelUp = true, stats = {}, tutorial = false, tutorialCoins = 0, eventCoin = 1, eventXp = 2 }, true)
end)

scene("locker", function()
	unstage()
	MatchHud.closeResult()
	MatchHud.hide()
	Mood.reset()
	lobbyCam = CFrame.lookAt(Vector3.new(30, 17, 74), Vector3.new(-6, 10, 0))
	Windows.open("Locker")
end)

scene("shop", function()
	Windows.open("Shop")
end)

scene("play", function()
	Windows.open("Play")
end)

-- advance on every resize
local resizes = 0
local function play(index: number)
	run += 1
	local s = scenes[math.clamp(index, 1, #scenes)]
	print("[TEST] showcase scene " .. index .. ": " .. s.name)
	local my = run
	task.spawn(function()
		local ok, err = pcall(function()
			s.play(my)
		end)
		if not ok then
			print("[TEST] showcase scene error: " .. tostring(err))
		end
	end)
end
local cam = workspace.CurrentCamera
local last = cam.ViewportSize
local lastAt = 0
play(from)
cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	local size = cam.ViewportSize
	if math.abs(size.X - last.X) < 8 and math.abs(size.Y - last.Y) < 8 then
		return
	end
	if os.clock() - lastAt < 2 then
		last = size
		return -- the same window resize settling
	end
	lastAt = os.clock()
	last = size
	resizes += 1
	play(from + (resizes - 1) // perScene)
end)
