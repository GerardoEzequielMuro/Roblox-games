-- Gameplay test harness (only in test.project.json builds). Runs inside a Studio playtest.
-- The client LocalScript drives the real remotes; this script exposes a __Test
-- RemoteFunction for server-side setup (give currency / pets, force a planet, stage a PvP
-- rival, read the profile) and collects the report.
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
local Data = require(Services.Data)
local State = require(Services.State)
local Mining = require(Services.Mining)
local Pets = require(Services.Pets)
local Auto = require(Services.Auto)
local Progression = require(Services.Progression)
local Monetization = require(Services.Monetization)
local Offline = require(Services.Offline)
local QuestService = require(Services.QuestService)
local Social = require(Services.Social)
local LiveEventService = require(Services.LiveEventService)
local Pvp = require(Services.Pvp)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Layout = require(ReplicatedStorage.Shared.Layout)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local t0 = os.clock()
while not State.ready[player] and os.clock() - t0 < 40 do
	task.wait(0.2)
end
check("session ready", State.ready[player] == true, string.format("%.1fs", os.clock() - t0))
local p = Data.get(player)
check("profile created", p ~= nil)
if p then
	check("starter pet equipped", #p.equipped == 1 and p.pets[p.equipped[1]] ~= nil and p.pets[p.equipped[1]].id == Config.StartingPet)
	check("starts in galaxy 1 with the first tool and 0 Stardust", #p.zones == 1 and p.stardust == 0 and p.tool == Config.Tools[1].id, p.tool)
	check("autos default: sell + best on, mine off", p.auto.sell == true and p.auto.best == true and p.auto.mine == false)
end
local world = workspace:FindFirstChild("World")
local worldParts = 0
if world then
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			worldParts += 1
		end
	end
end
check("world built (6 galaxies + arena)", world ~= nil and #world:GetChildren() >= #Config.Zones + 1, world and #world:GetChildren())
check("world part budget (<= 3600 parts)", worldParts > 500 and worldParts <= 3600, worldParts)
check("streaming is on", workspace.StreamingEnabled == true)
-- can a playtest script switch the render quality? (decides how the low-quality captures are taken)
do
	local okQ, q = pcall(function()
		local r = (settings() :: any).Rendering
		local prev = r.QualityLevel
		r.QualityLevel = prev
		return tostring(prev)
	end)
	print("[TEST] INFO quality probe (server script): ok=" .. tostring(okQ) .. " " .. tostring(q))
end

local done = false
local rng = Random.new(99)
local rf = Instance.new("RemoteFunction")
rf.Name = "__Test"
rf.OnServerInvoke = function(plr, cmd, a, b, c)
	local prof = Data.get(plr)
	if not prof then
		return nil
	end
	if cmd == "profile" then
		local byId = {}
		local n = 0
		for _, pet in prof.pets do
			n += 1
			local k = pet.id .. ":" .. pet.tier
			byId[k] = (byId[k] or 0) + 1
		end
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local transit = State.transit[plr]
		return {
			stardust = prof.stardust,
			crystals = prof.crystals,
			totalMined = prof.totalMined,
			rebirths = prof.rebirths,
			zones = prof.zones,
			tool = prof.tool,
			upgrades = prof.upgrades,
			mats = prof.mats,
			relics = prof.relics,
			petCount = n,
			byId = byId,
			pets = prof.pets,
			equipped = table.clone(prof.equipped),
			maxEquip = State.maxEquip(plr, prof),
			damage = State.hitDamage(plr, prof),
			basePower = State.basePower(plr, prof),
			income = State.income(plr, prof),
			cargo = { count = prof.cargo.count, value = prof.cargo.value, cap = Formulas.cargoCapacity(State.stats(plr, prof)) },
			transit = transit and { value = transit.value, left = transit.arriveAt - os.clock() } or nil,
			buffs = prof.buffs,
			mastery = prof.mastery,
			gate = prof.gate,
			auto = prof.auto,
			autoDelete = prof.autoDelete,
			totalOpened = prof.totalOpened,
			planetsBroken = prof.planetsBroken,
			hits = prof.hits,
			tutorial = prof.tutorial,
			arenaPoints = prof.arenaPoints,
			arenaKos = prof.arenaKos,
			anomalyWindow = prof.anomalyWindow,
			starterBought = prof.starterBought,
			playTime = prof.playTime,
			charge = State.chargeFraction(plr, prof),
			pos = root and root.Position,
			walkSpeed = hum and hum.WalkSpeed,
			mineNode = plr:GetAttribute("MineNode"),
			toolAttr = plr:GetAttribute("Tool"),
		}
	elseif cmd == "give" then -- a = currency, b = amount
		if a == "stardust" then
			State.addStardust(plr, b, false)
		elseif a == "crystals" then
			State.addCrystals(plr, b)
		else
			State.addMaterial(plr, a, b)
		end
		State.dirty(plr)
		return true
	elseif cmd == "set" then -- a = field, b = value
		if a == "stardust" then
			prof.stardust = b
		elseif a == "playTime" then
			prof.playTime = b
		elseif a == "cargoFull" then
			prof.cargo.count = Formulas.cargoCapacity(State.stats(plr, prof))
			prof.cargo.value = b
		elseif a == "cargo" then
			prof.cargo.count = b
			prof.cargo.value = c or 0
		elseif a == "tutorial" then
			prof.tutorial = b
		end
		State.dirty(plr)
		return true
	elseif cmd == "givePets" then
		local uids = {}
		for _ = 1, b or 1 do
			table.insert(uids, Pets.add(plr, a, c or 0, true))
		end
		return uids
	elseif cmd == "grantPass" then
		(State.passes[plr] :: any)[a] = if b ~= false then true else nil
		Pets.clampEquipped(plr)
		State.dirty(plr)
		return true
	elseif cmd == "unlockZones" then -- up to galaxy a
		for z = 2, a do
			if not table.find(prof.zones, z) then
				table.insert(prof.zones, z)
			end
		end
		Mining.reset(plr)
		State.dirty(plr)
		return true
	elseif cmd == "setNode" then -- a = zone, b = node, c = kind: a fresh planet of that kind
		local list = Mining.ensureZone(plr, prof, a)
		local node = { kind = c, layer = 1, hp = 0, dense = false }
		node.hp = Mining.layerMax(a, node)
		list[b] = node
		return { hp = node.hp, layers = Formulas.layerCount(c) }
	elseif cmd == "node" then
		local list = Mining.ensureZone(plr, prof, a)
		local node = list[b]
		if not node then
			return nil
		end
		return { kind = node.kind, layer = node.layer, hp = node.hp, max = Mining.layerMax(a, node), respawning = node.respawnAt ~= nil, dense = node.dense }
	elseif cmd == "hits" then -- a = zone, b = node, c = hits (no range / rate checks)
		Mining.applyHits(plr, a, b, c)
		return true
	elseif cmd == "setGate" then -- a = zone the gate is in, b = HP left
		local list = Mining.ensureZone(plr, prof, a)
		local node = list[Config.NodeGate]
		if node then
			node.hp = b
			prof.gate[tostring(a + 1)] = b
		end
		return node ~= nil
	elseif cmd == "tp" then -- a = { x, y, z }
		Progression.teleportTo(plr, a)
		return true
	elseif cmd == "rollMany" then -- a = capsule, b = luck, c = n: the same roll the game uses
		local counts = {}
		for _ = 1, c do
			local odd = Formulas.rollCapsule(a, b, rng:NextNumber())
			counts[odd.id] = (counts[odd.id] or 0) + 1
		end
		return counts
	elseif cmd == "setRestricted" then
		State.restricted[plr] = a == true
		State.dirty(plr)
		return true
	elseif cmd == "grantProduct" then
		local product = Config.ProductByKey[a]
		if not product then
			return false
		end
		Monetization.grantProduct(plr, prof, product)
		return true
	elseif cmd == "autoTicks" then
		return Auto.ticks
	elseif cmd == "skipSession" then
		State.sessionStart[plr] -= a
		State.dirty(plr)
		return true
	elseif cmd == "fakeOffline" then
		prof.savedAt = os.time() - a
		prof.offlinePending = 0
		Offline.compute(plr)
		return { pending = prof.offlinePending, seconds = prof.offlineSeconds, rate = Offline.rate(plr, prof), cap = Offline.capSeconds(plr) }
	elseif cmd == "forceQuests" then
		QuestService.ensure(plr, a)
		State.dirty(plr)
		return prof.quests.list
	elseif cmd == "completeQuests" then
		for i, q in prof.quests.list do
			prof.quests.progress[i] = q.target
		end
		State.dirty(plr)
		return true
	elseif cmd == "quests" then
		return prof.quests
	elseif cmd == "referral" then
		return Social.applyReferral(plr, a), prof.referredBy
	elseif cmd == "eventCommand" then
		local ok, msg = LiveEventService.command(plr.UserId, a)
		return ok, msg
	elseif cmd == "makeAdmin" then
		table.insert(Config.AdminUserIds, plr.UserId)
		return true
	elseif cmd == "effects" then
		return State.eventEffects
	elseif cmd == "pvpDummy" then -- a = id, b = { dx, dz } from the arena centre, c = { power, playTime }
		local centre = Config.ArenaCenter
		local d = Pvp.spawnDummy(a, Vector3.new(centre[1] + b[1], 4, centre[3] + b[2]), c[1], c[2])
		return { hp = d.hp, inArena = d.inArena }
	elseif cmd == "pvpDummyAttack" then -- the dummy zaps the player with the normal rules
		local dummy = Pvp.combatants[a]
		if not dummy then
			return false, "no dummy"
		end
		local ok, reason = Pvp.resolve(dummy, Pvp.combatantFor(plr))
		return ok, reason
	elseif cmd == "pvpInfo" then
		local me = Pvp.combatantFor(plr)
		local other = a and Pvp.combatants[a]
		local bots = 0
		for _, comb in Pvp.combatants do
			if comb.kind == "bot" then
				bots += 1
			end
		end
		return {
			hp = me.hp, inArena = me.inArena, rookie = Pvp.isRookie(me), protected = me.protectedUntil - os.clock(),
			other = other and { hp = other.hp, inArena = other.inArena, respawning = other.respawnAt ~= nil, rookie = Pvp.isRookie(other) } or nil,
			bots = bots,
		}
	elseif cmd == "pvpClear" then
		local me = Pvp.combatantFor(plr)
		me.protectedUntil = 0
		return true
	elseif cmd == "pvpRemoveDummy" then
		Pvp.removeDummy(a)
		return true
	elseif cmd == "worldParts" then
		return worldParts
	elseif cmd == "report" then
		-- the runner keeps the first 200 [TEST lines: failures go one per line, passes are packed
		local passed = {}
		for line in string.gmatch(a, "[^\n]+") do
			table.insert(results, "client " .. line)
			if line:sub(1, 4) == "FAIL" then
				print("[TEST] client " .. line)
			else
				table.insert(passed, (line:gsub("^PASS ", ""):gsub(" :: .*$", "")))
			end
		end
		for i = 1, #passed, 12 do
			print("[TEST] client PASS x" .. math.min(12, #passed - i + 1) .. ": " .. table.concat(passed, " | ", i, math.min(i + 11, #passed)))
		end
		done = true
		return true
	end
	return nil
end
rf.Parent = ReplicatedStorage

local _ = Layout
local deadline = os.clock() + 400
while not done and os.clock() < deadline do
	task.wait(0.25)
end
check("client finished", done)
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
