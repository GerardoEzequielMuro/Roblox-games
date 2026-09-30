-- Gameplay test harness (only in test.project.json builds). Runs inside a Studio playtest.
-- The client LocalScript drives the real remotes; this script exposes a __Test RemoteFunction
-- for server-side setup (give taps/pets, grant passes, read the profile) and collects the report.
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
local Pets = require(Services.Pets)
local Config = require(ReplicatedStorage.Shared.Config)
local Offline = require(Services.Offline)
local QuestService = require(Services.QuestService)
local Social = require(Services.Social)
local LiveEventService = require(Services.LiveEventService)
local Remotes = require(Services.Remotes)
local Tapping = require(Services.Tapping)
local Plots = require(Services.Plots)
local Stats = game:GetService("Stats")

-- performance sampling window (perfStart / perfEnd)
local perf = { frames = 0, time = 0, worst = 0, hb = 0, hbN = 0, t0 = 0, remotes = { out = 0, tapIn = 0, requestIn = 0 } }
game:GetService("RunService").Heartbeat:Connect(function(dt)
	perf.frames += 1
	perf.time += dt
	if dt > perf.worst then
		perf.worst = dt
	end
	perf.hb += Stats.HeartbeatTimeMs
	perf.hbN += 1
end)

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
	check("starts in zone 1 with 0 taps", #p.zones == 1 and p.taps == 0, p.taps)
end
check("world built", workspace:FindFirstChild("World") ~= nil and #workspace.World.Eggs:GetChildren() == #Config.Eggs)

local done = false
local rf = Instance.new("RemoteFunction")
rf.Name = "__Test"
rf.OnServerInvoke = function(plr, cmd, a, b)
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
		return {
			taps = prof.taps,
			gems = prof.gems,
			rebirths = prof.rebirths,
			zones = prof.zones,
			petCount = n,
			byId = byId,
			equipped = table.clone(prof.equipped),
			maxEquip = State.maxEquip(plr, prof),
			tapValue = State.tapValue(plr, prof),
			totalHatched = prof.totalHatched,
			pos = (plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart).Position,
		}
	elseif cmd == "giveTaps" then
		State.addTaps(plr, a, false)
		return true
	elseif cmd == "dice" then
		if a then
			prof.dice = a
			State.dirty(plr)
		end
		return prof.dice
	elseif cmd == "petTrait" then
		return prof.pets[a] and prof.pets[a].trait
	elseif cmd == "giveGems" then
		State.addGems(plr, a)
		return true
	elseif cmd == "setTaps" then
		prof.taps = a
		State.dirty(plr)
		return true
	elseif cmd == "givePets" then
		local uids = {}
		for _ = 1, b or 1 do
			table.insert(uids, Pets.add(plr, a, 0, true))
		end
		return uids
	elseif cmd == "grantPasses" then
		for _, pass in Config.Passes do
			State.passes[plr][pass.key] = true
		end
		Pets.clampEquipped(plr)
		State.dirty(plr)
		return true
	elseif cmd == "skipSession" then
		State.sessionStart[plr] -= a
		State.dirty(plr)
		return true
	elseif cmd == "fakeOffline" then
		-- pretend the last save was `a` seconds ago and recompute like a fresh join
		prof.savedAt = os.time() - a
		prof.offlinePending = 0
		Offline.compute(plr)
		return { pending = prof.offlinePending, seconds = prof.offlineSeconds, tapValue = State.tapValue(plr, prof), cap = Offline.capSeconds(plr) }
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
	elseif cmd == "worldAudit" then
		-- world dressing + budgets, counted on the server (the client only has what streamed in)
		local world = workspace.World
		local missing = {}
		for _, zone in Config.Zones do
			local folder = world:FindFirstChild("Zone" .. zone.index .. "_" .. zone.id)
			for _, name in { "Border", "Horizon", "Lamps", "Landmarks", "Decor" } do
				local f = folder and folder:FindFirstChild(name)
				if not f or #f:GetChildren() == 0 then
					table.insert(missing, zone.id .. "/" .. name)
				end
			end
		end
		local sparkly, atomic = 0, 0
		for _, egg in world.Eggs:GetChildren() do
			local shell = egg:FindFirstChild("Shell")
			if shell and shell:FindFirstChild("Sparkle") and typeof(shell:GetAttribute("Rest")) == "CFrame" then
				sparkly += 1
			end
			if egg:IsA("Model") and egg.ModelStreamingMode == Enum.ModelStreamingMode.Atomic then
				atomic += 1
			end
		end
		local unanchored = 0
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored and not d:FindFirstChildWhichIsA("WeldConstraint") then
				unanchored += 1
			end
		end
		return { missing = missing, sparkly = sparkly, atomic = atomic, unanchored = unanchored, streaming = workspace.StreamingEnabled }
	elseif cmd == "park" then
		local index = plr:GetAttribute("Plot")
		local plot = workspace.World.Park:FindFirstChild("Plot" .. tostring(index))
		local atomic = 0
		for _, m in workspace.World.Park:GetChildren() do
			if m:IsA("Model") and m.ModelStreamingMode == Enum.ModelStreamingMode.Atomic and m:FindFirstChild("Pedestal6") and m:FindFirstChild("Chest") then
				atomic += 1
			end
		end
		return { index = index, ownerId = plot and plot:GetAttribute("OwnerId"), ownerName = plot and plot:GetAttribute("OwnerName"), plots = atomic, used = Plots.used() }
	elseif cmd == "parkCollect" then
		local ok, msg = Plots.collect(plr, a)
		return ok, msg
	elseif cmd == "setRestricted" then
		State.paidRandomRestricted[plr] = a == true
		State.dirty(plr)
		return true
	elseif cmd == "settings" then
		return table.clone(prof.settings), prof.rebirths, prof.taps
	elseif cmd == "roundtrip" then
		-- what a save + load does to the profile: JSON, then reconcile
		local HttpService = game:GetService("HttpService")
		local copy = HttpService:JSONDecode(HttpService:JSONEncode(prof))
		local again = Data.reconcile(copy)
		local old = Data.reconcile({ settings = { autoTap = false }, pets = {}, equipped = {}, upgrades = {} })
		return { dice = again.dice, settings = again.settings, autoTapUpgrade = again.upgrades.AutoTap, oldSettings = old.settings, oldUpgrade = old.upgrades.AutoTap }
	elseif cmd == "leaks" then
		-- every per-player table is emptied by the cleanup the real PlayerRemoving handler runs
		local ghost: any = Instance.new("Folder")
		State.init(ghost)
		State.passes[ghost] = {}
		State.ready[ghost] = true
		State.paidRandomRestricted[ghost] = true
		State.autoHatch[ghost] = "basic"
		local before = State.tracked(ghost)
		State.cleanup(ghost)
		Remotes.forget(ghost)
		Tapping.forget(ghost)
		return { before = before, after = State.tracked(ghost), data = Data.tracked(ghost) }
	elseif cmd == "maxPets" then
		-- 9 equip slots, all filled with the heaviest pets
		prof.upgrades.PetSlots = 3
		for _, id in { "celestialdragon", "shadowdragon", "galaxydragon", "firedragon", "icedragon", "nebulaowl", "hellhound", "crystalunicorn", "jellyphoenix" } do
			Pets.add(plr, id, 0, true)
		end
		Pets.equipBest(plr)
		prof.settings.autoTap = true
		State.dirty(plr)
		return #prof.equipped
	elseif cmd == "perfStart" then
		perf.frames, perf.time, perf.worst, perf.hb, perf.hbN = 0, 0, 0, 0, 0
		perf.remotes = table.clone(Remotes.stats)
		perf.t0 = os.clock()
		return true
	elseif cmd == "perfEnd" then
		local secs = os.clock() - perf.t0
		local world = workspace:FindFirstChild("World")
		local parts, emitters, lights, shadowCasters, touchable = 0, 0, 0, 0, 0
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if world and d:IsDescendantOf(world) then
					if d.CastShadow and d.Transparency < 1 then
						shadowCasters += 1
					end
					if d.CanTouch then
						touchable += 1
					end
				end
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			elseif d:IsA("Light") then
				lights += 1
			end
		end
		local s = Remotes.stats
		return {
			instances = #workspace:GetDescendants(),
			parts = parts,
			emitters = emitters,
			lights = lights,
			shadowCasters = shadowCasters,
			touchable = touchable,
			memoryMb = Stats:GetTotalMemoryUsageMb(),
			frameMs = perf.time / math.max(1, perf.frames) * 1000,
			worstMs = perf.worst * 1000,
			heartbeatMs = perf.hb / math.max(1, perf.hbN),
			outPerSec = (s.out - perf.remotes.out) / secs,
			tapInPerSec = (s.tapIn - perf.remotes.tapIn) / secs,
			requestInPerSec = (s.requestIn - perf.remotes.requestIn) / secs,
			seconds = secs,
		}
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

local deadline = os.clock() + 420
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
