-- Gameplay test harness (only in test.project.json builds). Runs inside a Studio playtest.
-- The client LocalScript drives the real remotes; this script exposes a __Test RemoteFunction
-- for server-side setup (set stats, teleport, read fighters / enemies) and collects the report.
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
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(Services.Data)
local State = require(Services.State)
local Fighters = require(Services.Fighters)
local Combat = require(Services.Combat)
local Npcs = require(Services.Npcs)
local Auto = require(Services.Auto)
local Progression = require(Services.Progression)
local Training = require(Services.Training)

local function opt(name)
	local m = Services:FindFirstChild(name)
	return if m then require(m) else nil
end

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local t0 = os.clock()
while not State.ready[player] and os.clock() - t0 < 40 do
	task.wait(0.2)
end
check("session ready", State.ready[player] == true, string.format("%.1fs", os.clock() - t0))
local p = Data.get(player)
check("profile created", p ~= nil)
if p then
	check("starts with base stats, no sparks, planet 1", p.stats.strength == Config.StartStat and p.sparks == 0 and p.planet == 1 and #p.planets == 1)
	check("starting power matches the formula", State.power(p) == Formulas.power(p.stats), State.power(p))
end
local world = workspace:FindFirstChild("World")
check("world built", world ~= nil and #world:GetChildren() >= #Config.Planets)
if world then
	local n = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	check("world part budget", n <= Config.Budget.worldParts, n .. " / " .. Config.Budget.worldParts)
	local unanchored = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			unanchored += 1
		end
	end
	check("world is fully anchored", unanchored == 0, unanchored)
	for _, pl in Config.Planets do
		check("planet built: " .. pl.id, world:FindFirstChild("Planet_" .. pl.id) ~= nil)
	end
end
check("streaming enabled", workspace.StreamingEnabled == true)
task.wait(1.5)
check("enemies spawned only on the active planet", Npcs.activeCount() == 12, Npcs.activeCount())
for _, name in { "Arena", "Rewards", "Story", "QuestService", "Relics", "Auras", "WorldBoss", "LiveEventService", "Monetization", "Leaderboard", "Offline", "Social", "Guard" } do
	check("service loaded: " .. name, opt(name) ~= nil)
end
check("enemy budget", Npcs.activeCount() <= Config.Budget.npcs, Npcs.activeCount())

local function nearestNpc(kind, from, full)
	local best, bestD = nil, math.huge
	for _, npc in Npcs.list do
		if npc.spawned and npc.def.id == kind and (not full or npc.f.hp == npc.f.maxHp) then
			local d = (npc.pos - from).Magnitude
			if d < bestD then
				best, bestD = npc, d
			end
		end
	end
	return best
end

local dummyFolder = nil
local dummies = {}
local function makeDummy(name, pos, stats)
	if not dummyFolder then
		dummyFolder = Instance.new("Folder")
		dummyFolder.Name = "Dummies"
		dummyFolder.Parent = workspace
	end
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CanCollide = false
	root.Transparency = 0.2
	root.Color = Color3.fromRGB(240, 90, 90)
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0))
	head.Parent = m
	local hum = Instance.new("Humanoid")
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.Parent = m
	m.PrimaryPart = root
	m.Parent = dummyFolder
	local f = Fighters.addDummy(m, stats, name)
	dummies[name] = f
	return f
end

-- Server teleports stream the destination in first: wait until the character is really there.
local function arrive(f, pos: Vector3)
	local t0 = os.clock()
	while os.clock() - t0 < 8 do
		local root = f.root
		if root and ((root.Position - pos) * Vector3.new(1, 0, 1)).Magnitude < 6 then
			break
		end
		task.wait(0.05)
	end
	task.wait(0.25)
end

local done = false
local rf = Instance.new("RemoteFunction")
rf.Name = "__Test"
rf.OnServerInvoke = function(plr, cmd, a, b, c)
	local prof = Data.get(plr)
	local f = Fighters.ofPlayer(plr)
	if not prof or not f then
		return nil
	end
	if cmd == "profile" then
		return {
			stats = table.clone(prof.stats),
			power = State.power(prof),
			bestPower = prof.bestPower,
			sparks = prof.sparks,
			gems = prof.gems,
			gear = prof.gear,
			forms = prof.forms,
			kills = prof.kills,
			bossKills = table.clone(prof.bossKills),
			totalReps = prof.totalReps,
			planet = prof.planet,
			planets = table.clone(prof.planets),
			rebirths = prof.rebirths,
			techniques = table.clone(prof.techniques),
			settings = table.clone(prof.settings),
			story = table.clone(prof.story),
			perRep = State.gainPerRep(plr, prof, prof.settings.stat),
			autoRate = State.autoRate(plr, prof),
			pvp = table.clone(prof.pvp),
			playTime = prof.playTime,
			spins = prof.spins,
			auras = table.clone(prof.auras),
			wishes = prof.wishes,
			wishPower = prof.wishPower,
			boostLeft = prof.boostLeft,
			items = table.clone(prof.items),
			buffs = table.clone(prof.buffs),
			skins = table.clone(prof.skins),
			mounts = table.clone(prof.mounts),
			skin = prof.skin,
			mount = prof.mount,
			bp = prof.bp,
		}
	elseif cmd == "fighter" then
		local h = f.humanoid
		return {
			ki = f.ki,
			form = f.form,
			blocking = f.blocking,
			charging = f.charging,
			flying = f.flying,
			inArena = f.inArena,
			hp = h and h.Health or 0,
			maxHp = h and h.MaxHealth or 0,
			walkSpeed = h and h.WalkSpeed or 0,
			jumpPower = h and h.JumpPower or 0,
			pos = f.root and f.root.Position,
			alive = f.alive,
			invulnerable = f.invulnerableUntil > os.clock(),
		}
	elseif cmd == "setStats" then
		for k, v in a do
			prof.stats[k] = v
		end
		local power = State.power(prof)
		prof.bestPower = if b == "exact" then power else math.max(prof.bestPower, power)
		Combat.refreshForms(plr)
		Fighters.syncHealth(f)
		if f.humanoid then
			f.humanoid.Health = f.humanoid.MaxHealth
		end
		Training.applyMovement(plr)
		State.dirty(plr)
		return true
	elseif cmd == "set" then
		prof[a] = b
		State.dirty(plr)
		return true
	elseif cmd == "giveSparks" then
		State.addSparks(plr, a, false)
		return true
	elseif cmd == "giveGems" then
		State.addGems(plr, a)
		return true
	elseif cmd == "setKi" then
		f.ki = a
		return true
	elseif cmd == "heal" then
		if f.humanoid then
			f.humanoid.Health = f.humanoid.MaxHealth
		end
		f.lastDamagedAt = -100
		return true
	elseif cmd == "vulnerable" then
		f.invulnerableUntil = 0
		return true
	elseif cmd == "teleport" then
		Progression.teleport(plr, CFrame.new(a) * CFrame.Angles(0, b or 0, 0))
		arrive(f, a)
		return true
	elseif cmd == "place" then
		-- named places on the player's planet
		local cx, _, cz = Config.planetCenter(prof.planet)
		local pl = Config.Planets[prof.planet]
		local o
		if a == "zone" then
			o = pl.zones[b].offset
		elseif a == "camp" then
			o = pl.camps[b].offset
		elseif a == "boss" then
			o = pl.boss.offset
		elseif a == "arena" then
			o = Config.Arena.offset
		elseif a == "altar" then
			o = Config.WishAltar.offset
		elseif a == "worldboss" then
			o = Config.WorldBossSite.offset
		else
			o = { 0, 0, 24 }
		end
		local pos = Vector3.new(cx + o[1] + (c or 0), 5, cz + o[3])
		Progression.teleport(plr, CFrame.new(pos))
		arrive(f, pos)
		return pos
	elseif cmd == "npc" then
		local npc = nearestNpc(a, (f.root and f.root.Position) or Vector3.zero, b == "full")
		if not npc then
			return nil
		end
		return { id = npc.f.id, pos = npc.pos, hp = npc.f.hp, maxHp = npc.f.maxHp, state = npc.state, spawned = npc.spawned, alive = npc.f.alive }
	elseif cmd == "npcById" then
		local nf = Fighters.byId(a)
		if not nf or not nf.npc then
			return nil
		end
		return { id = nf.id, pos = nf.npc.pos, hp = nf.hp, maxHp = nf.maxHp, state = nf.npc.state, spawned = nf.npc.spawned, alive = nf.alive }
	elseif cmd == "freezeNpcs" then
		-- park enemies so tests are deterministic: huge attack delays
		for _, npc in Npcs.list do
			npc.nextAttackAt = os.clock() + (a or 600)
			npc.nextPatternAt = os.clock() + (a or 600)
		end
		return true
	elseif cmd == "npcHit" then
		-- an enemy-style hit on the player (raw damage through the real pipeline)
		local attacker = nearestNpc(a, f.root.Position)
		if not attacker then
			return -1
		end
		return Fighters.damage(attacker.f, f, "npc", b, { silent = true })
	elseif cmd == "noCrit" then
		Config.Combat.critChance = 0
		return true
	elseif cmd == "activeNpcs" then
		return Npcs.activeCount()
	elseif cmd == "autoAttacks" then
		return Auto.attacks[plr] or 0
	elseif cmd == "projectiles" then
		return Combat.projectileCount()
	elseif cmd == "grantPasses" then
		for _, pass in Config.Passes do
			State.passes[plr][pass.key] = a ~= false
		end
		State.dirty(plr)
		return true
	elseif cmd == "pass" then
		State.passes[plr][a] = b
		State.dirty(plr)
		return true
	elseif cmd == "skipSession" then
		prof.giftPlay.secs += a
		prof.playTime += a
		State.dirty(plr)
		return true
	elseif cmd == "dummy" then
		local d = makeDummy(a, b, c)
		return d.id
	elseif cmd == "dummyInfo" then
		local d = dummies[a]
		if not d then
			return nil
		end
		return { hp = d.humanoid.Health, maxHp = d.humanoid.MaxHealth, alive = d.alive, id = d.id }
	elseif cmd == "dummySet" then
		local d = dummies[a]
		if d then
			for k, v in b do
				(d :: any)[k] = v
			end
		end
		return true
	elseif cmd == "dummyAttack" then
		-- the dummy attacks the player through the same Combat code a real player uses
		local d = dummies[a]
		if not d then
			return -1
		end
		local before = f.humanoid.Health
		if b == "blast" then
			local dir = (f.root.Position - d.root.Position).Unit
			Combat.blast(d, dir, true)
			task.wait(0.6)
		else
			d.cd.melee = 0
			local aim = (f.root.Position - d.root.Position) * Vector3.new(1, 0, 1)
			Combat.melee(d, aim.Unit)
		end
		return before - f.humanoid.Health
	elseif cmd == "dummyRemove" then
		local d = dummies[a]
		if d then
			Fighters.remove(d)
			if d.char then
				d.char:Destroy()
			end
			dummies[a] = nil
		end
		return true
	elseif cmd == "story" then
		prof.story = { step = a, progress = b or 0 }
		State.dirty(plr)
		return true
	elseif cmd == "completeQuests" then
		for i, q in prof.quests.list do
			prof.quests.progress[i] = q.target
		end
		State.dirty(plr)
		return true
	elseif cmd == "dummyHp" then
		local d = dummies[a]
		if d and d.humanoid then
			d.humanoid.Health = b
		end
		return true
	elseif cmd == "npcSetHp" then
		local nf = Fighters.byId(a)
		if nf and nf.root then
			nf.hp = b
			nf.root:SetAttribute("Hp", b)
		end
		return true
	elseif cmd == "makeAdmin" then
		table.insert(Config.AdminUserIds, plr.UserId)
		return true
	elseif cmd == "liveOverride" then
		opt("LiveEventService").setOverride(a, os.time() + b)
		return true
	elseif cmd == "eventCommand" then
		local okCmd, msg = opt("LiveEventService").command(plr.UserId, a)
		return okCmd, msg
	elseif cmd == "receipt" then
		-- a real ProcessReceipt call for product `a` with purchase id `b`
		local product = Config.ProductByKey[a]
		product.id = 987001
		local decision = opt("Monetization").processReceipt({ PlayerId = plr.UserId, ProductId = 987001, PurchaseId = b })
		product.id = 0
		return decision.Name
	elseif cmd == "relicSpot" then
		local spot = opt("Relics").spots(prof)[a]
		return spot and spot.pos, spot and spot.planet
	elseif cmd == "arenaCenter" then
		local cx, _, cz = Config.planetCenter(Config.Arena.planet)
		return Vector3.new(cx + Config.Arena.offset[1], 3, cz + Config.Arena.offset[3])
	elseif cmd == "altar" then
		local cx, _, cz = Config.planetCenter(Config.WishAltar.planet)
		return Vector3.new(cx + Config.WishAltar.offset[1], 6, cz + Config.WishAltar.offset[3] + 10)
	elseif cmd == "setHp" then
		if f.humanoid then
			f.humanoid.Health = a
		end
		return true
	elseif cmd == "setPlayTime" then
		prof.playTime = a
		State.dirty(plr)
		return true
	elseif cmd == "leaderstats" then
		local ls = plr:FindFirstChild("leaderstats")
		local power = ls and ls:FindFirstChild("Power")
		return power and (power :: StringValue).Value
	elseif cmd == "service" then
		-- generic hook for later rounds: service name, function name, args
		local s = opt(a)
		if not s or type(s[b]) ~= "function" then
			return nil
		end
		return s[b](plr, c)
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

local deadline = os.clock() + 840
while not done and os.clock() < deadline do
	task.wait(0.25)
end
check("client finished", done)
check("server Lua heap within budget", gcinfo() / 1024 < Config.Budget.serverLuaHeapMb, string.format("%.1f MB", gcinfo() / 1024))
task.wait(0.5)
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
