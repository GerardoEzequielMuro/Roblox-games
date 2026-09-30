-- Playtest harness, server side (only in test.project.json builds). Runs inside a Studio
-- playtest. The client LocalScript drives the real remotes; this script checks the server
-- state, exposes a __Test RemoteFunction for setup (coins, passes, a stand-in second human,
-- fake receipts...), taps every match event and prints the report.
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local errors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(errors, msg)
	end
end)

local results = {}
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail ~= nil then " :: " .. tostring(detail) else "")
	print("[TEST] " .. line)
	table.insert(results, line)
end

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Config = require(ReplicatedStorage.Shared.Config)
local MatchCore = require(ReplicatedStorage.Shared.MatchCore)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Data = require(Services.Data)
local State = require(Services.State)
local Remotes = require(Services.Remotes)
local Tables = require(Services.Tables)
local Runner = require(Services.MatchRunner)
local Monetization = require(Services.Monetization)
local Social = require(Services.Social)
local LiveEventService = require(Services.LiveEventService)
local QuestService = require(Services.QuestService)
local Cosmetics = require(Services.Cosmetics)
local CoreService = require(Services.CoreService)
local Leaderboard = require(Services.Leaderboard)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local t0 = os.clock()
while not State.ready[player] and os.clock() - t0 < 40 do
	task.wait(0.2)
end
check("session ready", State.ready[player] == true, string.format("%.1fs", os.clock() - t0))
local p = Data.get(player)
check("profile created", p ~= nil)
if p then
	check("starts at level 1 with 0 coins and 0 trophies", p.level == 1 and p.coins == 0 and p.trophies == 0)
	check("default cosmetics equipped", p.equipped.wheel == "w_classic" and p.equipped.finisher == "f_hammer" and #p.emotes == 4)
	check("season stamped on join", p.season == Progression.season(os.time()))
	check("daily quests rolled", #p.quests.list == Config.QuestsPerDay)
end

-- world
local world = workspace:FindFirstChild("World")
check("world built", world ~= nil)
local serverParts = 0
if world then
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			serverParts += 1
		end
	end
	local tableFolders = 0
	for _, c in world:GetChildren() do
		if c.Name:sub(1, 6) == "Table_" then
			tableFolders += 1
		end
	end
	check("one stage per table", tableFolders == #Config.Tables, tableFolders)
	check("power core exists", world:FindFirstChild("PowerCore") ~= nil and world.PowerCore:FindFirstChild("Core") ~= nil)
end
check("server part budget", serverParts > 300 and serverParts <= Config.Budget.serverParts, serverParts)
check("tables registered", #Tables.list == #Config.Tables and Tables.byId.t1 ~= nil)
check("leaderstats", player:FindFirstChild("leaderstats") ~= nil and player.leaderstats:FindFirstChild("Wins") ~= nil)
check("cosmetic attributes replicated", player:GetAttribute("Cos_wheel") == "w_classic" and player:GetAttribute("League") == "bronze")

---------------------------------------------------------------------------
-- RNG: the server's own entropy through the same wheel maths
---------------------------------------------------------------------------
do
	local entropy = Random.new()
	for name, wheel in Config.Wheels do
		local n = #wheel
		local m = MatchCore.new(if name == "sudden" then "classic" else name, { { id = "a", name = "A", bot = true }, { id = "b", name = "B", bot = true } }, entropy:NextInteger(1, 2 ^ 31 - 1))
		MatchCore.start(m)
		local slots = table.create(n, 0)
		local SPINS = 24000
		for _ = 1, SPINS do
			m.phase = "decide"
			MatchCore.spin(m, m.players[m.spinner].id)
			slots[MatchCore.slotAt(entropy:NextNumber() * n + MatchCore.travel(m), n)] += 1
		end
		local chi = 0
		for i = 1, n do
			chi += (slots[i] - SPINS / n) ^ 2 / (SPINS / n)
		end
		check("rng: wheel " .. name .. " lands evenly on random brakes", chi < (if n == 14 then 34.5 else 31.3), string.format("chi2=%.1f over %d spins", chi, SPINS))
	end
	-- two matches never share a seed
	local a, b = Runner.new({ id = "x", mode = "classic", wheelFrac = 0 }, { { id = "a", name = "A", bot = true }, { id = "b", name = "B", bot = true } }, {}, { tutorial = false, onFinished = function() end }), Runner.new({ id = "y", mode = "classic", wheelFrac = 0 }, { { id = "a", name = "A", bot = true }, { id = "b", name = "B", bot = true } }, {}, { tutorial = false, onFinished = function() end })
	check("every match gets its own seed", a.m.rng.state() ~= b.m.rng.state())
	local r = Rng.new(entropy:NextInteger(1, 2 ^ 31 - 1))
	local sum = 0
	for _ = 1, 20000 do
		sum += r.next()
	end
	check("rng mean", math.abs(sum / 20000 - 0.5) < 0.02, sum / 20000)
end

---------------------------------------------------------------------------
-- Match event tap
---------------------------------------------------------------------------
local log = {} -- tableId -> { counts, events (last match), ended, results }
local function entry(id)
	local e = log[id]
	if not e then
		e = { counts = {}, matches = 0, ended = nil, aborts = 0, leftElims = 0, autoDecides = 0, modifiers = 0, lastWinnerTeam = nil, order = {} }
		log[id] = e
	end
	return e
end
table.insert(Runner.listeners, function(tableId, e)
	local en = entry(tableId)
	en.counts[e.t] = (en.counts[e.t] or 0) + 1
	if e.t == "intro" then
		en.matches += 1
		en.order = {}
	elseif e.t == "ended" then
		en.ended = { winner = e.winner, team = e.team, placements = e.placements, turns = e.turns, results = e.results }
	elseif e.t == "abort" then
		en.aborts += 1
	elseif e.t == "elim" and e.cause == "left" then
		en.leftElims += 1
	elseif e.t == "decide" and e.auto then
		en.autoDecides += 1
	elseif e.t == "round" and e.modifier then
		en.modifiers += 1
	end
	table.insert(en.order, e.t)
end)

local ghosts = {}
local function addGhost(tbl, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	for i = 1, Config.Seats do
		if not tbl.seats[i] then
			tbl.seats[i] = { id = name, name = name, bot = false, player = folder, userId = 0, color = { 200, 200, 200 }, model = nil, variant = 0 }
			ghosts[name] = folder
			return i
		end
	end
	return nil
end

local done = false
local rf = Instance.new("RemoteFunction")
rf.Name = "__Test"
rf.OnServerInvoke = function(plr, cmd, a, b)
	local prof = Data.get(plr)
	if not prof then
		return nil
	end
	if cmd == "profile" then
		local tbl, seat = Tables.seatOf(plr)
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return {
			coins = prof.coins,
			xp = prof.xp,
			level = prof.level,
			trophies = prof.trophies,
			wins = prof.wins,
			matches = prof.matches,
			streak = prof.streak,
			elims = prof.elims,
			tutorialDone = prof.tutorialDone,
			owned = Cosmetics.ownedSet(plr),
			equipped = prof.equipped,
			emotes = prof.emotes,
			settings = prof.settings,
			core = prof.core,
			table = tbl and tbl.id,
			seat = seat,
			anchored = hrp and hrp.Anchored,
			pos = hrp and hrp.Position,
			referredBy = prof.referredBy,
			referralRewards = prof.referralRewards,
			purchases = #prof.purchases,
			starterBought = prof.starterBought,
			quests = prof.quests,
			season = prof.season,
			coinMult = State.coinMult(plr),
		}
	elseif cmd == "fast" then
		Runner.timeScale = a
		return true
	elseif cmd == "setCoins" then
		prof.coins = a
		State.dirty(plr)
		return true
	elseif cmd == "addXp" then
		return State.addXp(plr, a)
	elseif cmd == "addTrophies" then
		State.addTrophies(plr, a)
		return prof.trophies
	elseif cmd == "grantPass" then
		State.passes[plr][a] = true
		State.progressed(plr)
		State.dirty(plr)
		return true
	elseif cmd == "log" then
		local en = entry(a)
		return { counts = en.counts, matches = en.matches, ended = en.ended, aborts = en.aborts, leftElims = en.leftElims, autoDecides = en.autoDecides, modifiers = en.modifiers }
	elseif cmd == "table" then
		local tbl = Tables.byId[a]
		local humans, bots = 0, 0
		for _, seat in tbl.seats do
			if seat.bot then
				bots += 1
			else
				humans += 1
			end
		end
		local models = 0
		for _, m in workspace.World.Bots:GetChildren() do
			if m:GetAttribute("TableId") == a then
				models += 1
			end
		end
		return { status = tbl.status, mode = tbl.mode, humans = humans, bots = bots, botModels = models, private = tbl.private ~= nil, duel = tbl.duel, running = tbl.runner ~= nil, matches = tbl.matches, turn = if tbl.runner then tbl.runner.m.turn else 0, phase = if tbl.runner then tbl.runner.m.phase else "" }
	elseif cmd == "ghostSeat" then
		-- a stand-in second human at table `a`
		return addGhost(Tables.byId[a], b or "ghost1")
	elseif cmd == "ghostStart" then
		return Tables.startMatch(Tables.byId[a])
	elseif cmd == "ghostLeave" then
		local tbl = Tables.byId[a]
		local name = b or "ghost1"
		if tbl.runner then
			tbl.runner:leave(name)
		end
		for i, seat in tbl.seats do
			if seat.id == name then
				tbl.seats[i] = nil
			end
		end
		if ghosts[name] then
			ghosts[name]:Destroy()
			ghosts[name] = nil
		end
		return true
	elseif cmd == "receipt" then
		-- a developer-product receipt as Roblox would deliver it (the product gets a test id)
		local product = Config.ProductByKey[a]
		local saved = product.id
		product.id = 990001
		local decision = Monetization.processReceipt({ PlayerId = plr.UserId, PurchaseId = b, ProductId = 990001 })
		product.id = saved
		return decision.Name
	elseif cmd == "unknownReceipt" then
		local decision = Monetization.processReceipt({ PlayerId = plr.UserId, PurchaseId = "p-unknown", ProductId = 424242 })
		return decision.Name
	elseif cmd == "referral" then
		return Social.applyReferral(plr, a), prof.referredBy
	elseif cmd == "resetReferral" then
		prof.referredBy = 0
		prof.matches = 0
		return true
	elseif cmd == "payInviter" then
		return Social.payInviter(plr, a)
	elseif cmd == "eventCommand" then
		local ok, msg = LiveEventService.command(plr.UserId, a)
		return ok, msg
	elseif cmd == "makeAdmin" then
		table.insert(Config.AdminUserIds, plr.UserId)
		return true
	elseif cmd == "effects" then
		return LiveEventService.effects(a)
	elseif cmd == "clearEvent" then
		LiveEventService.clearOverride()
		return true
	elseif cmd == "oldSeason" then
		prof.season -= 1
		prof.trophies = a
		local before = prof.coins
		State.checkSeason(plr)
		return { trophies = prof.trophies, gained = prof.coins - before, season = prof.season }
	elseif cmd == "skipSession" then
		State.sessionStart[plr] -= a
		State.dirty(plr)
		return true
	elseif cmd == "forceQuests" then
		QuestService.ensure(plr, a)
		return prof.quests.list
	elseif cmd == "completeQuests" then
		for i, q in prof.quests.list do
			prof.quests.progress[i] = q.target
		end
		State.dirty(plr)
		return true
	elseif cmd == "teleport" then
		local char = plr.Character
		if char then
			char:PivotTo(CFrame.new(a))
		end
		return true
	elseif cmd == "coreRange" then
		return CoreService.inRange(plr)
	elseif cmd == "boards" then
		Leaderboard.refresh()
		return Leaderboard.rows
	elseif cmd == "stats" then
		return { out = Remotes.stats.out, requestIn = Remotes.stats.requestIn, tracked = State.tracked(plr), tablesTracked = Tables.tracked(plr) }
	elseif cmd == "yesterdayDaily" then
		prof.daily.last = os.time() // 86400 - 1
		State.dirty(plr)
		return true
	elseif cmd == "report" then
		for line in string.gmatch(a, "[^\n]+") do
			print("[TEST] client " .. line)
			table.insert(results, "client " .. line)
		end
		done = true
		return true
	end
	return nil
end
rf.Parent = ReplicatedStorage

local deadline = os.clock() + 520
while not done and os.clock() < deadline do
	task.wait(0.25)
end
check("client finished", done)
task.wait(0.5)
-- nothing left running or seated
local busy = 0
for _, tbl in Tables.list do
	if tbl.status ~= "open" or next(tbl.seats) ~= nil then
		busy += 1
	end
end
check("every table is free at the end", busy == 0, busy)
check("no bot bodies left behind", #workspace.World.Bots:GetChildren() == 0, #workspace.World.Bots:GetChildren())
check("no server errors", #errors == 0, table.concat(errors, " || "))
local fails = 0
for _, r in results do
	if r:sub(1, 4) == "FAIL" or r:find("^client FAIL") then
		fails += 1
	end
end
print("[TEST SUMMARY] " .. #results .. " checks, " .. fails .. " failures")
task.wait(1)
StudioTestService:EndTest(fails)
