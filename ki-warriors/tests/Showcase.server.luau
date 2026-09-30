-- Screenshot showcase (showcase*.project.json only): a strong character, every form unlocked,
-- and a small RemoteFunction the client scenes use to pose things. Ends the playtest after the
-- runner has taken its screenshots.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(Services.Data)
local State = require(Services.State)
local Fighters = require(Services.Fighters)
local Combat = require(Services.Combat)
local Npcs = require(Services.Npcs)
local Progression = require(Services.Progression)
local Training = require(Services.Training)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
while not State.ready[player] do
	task.wait(0.2)
end
local p = Data.get(player)
p.stats = { strength = 8400, ki = 12500, defense = 9000, agility = 4000, jump = 2600 }
p.bestPower = 1e15
p.forms = #Config.Forms
p.sparks = 48200
p.gems = 135
p.gear = 4
p.planets = { 1, 2, 3, 4, 5 }
for _, t in Config.Techniques do
	p.techniques[t.id] = true
end
p.settings.autoTrain = true
State.dirty(player)

local frozen = true
task.spawn(function()
	while true do
		if frozen then
			for _, npc in Npcs.list do
				npc.nextAttackAt = os.clock() + 5
				npc.nextPatternAt = os.clock() + 5
			end
		end
		task.wait(1)
	end
end)

local rf = Instance.new("RemoteFunction")
rf.Name = "__Show"
rf.OnServerInvoke = function(plr, cmd, a, b)
	local prof = Data.get(plr)
	local f = Fighters.ofPlayer(plr)
	if not prof or not f then
		return nil
	end
	if cmd == "tp" then
		Progression.teleport(plr, a)
		task.wait(0.4)
		return true
	elseif cmd == "planet" then
		Progression.toPlanet(plr, a)
		task.wait(0.6)
		return true
	elseif cmd == "ki" then
		f.ki = a
		return true
	elseif cmd == "heal" then
		if f.humanoid then
			f.humanoid.Health = f.humanoid.MaxHealth
		end
		return true
	elseif cmd == "form" then
		f.cd.form = 0
		f.ki = 1
		return Combat.setForm(f, a)
	elseif cmd == "beam" then
		f.cd.beam = 0
		f.ki = 1
		f.beamStart = nil
		return Combat.beamRelease(f, a, b or 1)
	elseif cmd == "frozen" then
		frozen = a
		if not a then
			for _, npc in Npcs.list do
				npc.nextAttackAt = 0
				npc.nextPatternAt = os.clock() + 0.5
			end
		end
		return true
	elseif cmd == "stats" then
		for k, v in a do
			prof.stats[k] = v
		end
		Fighters.syncHealth(f)
		Training.applyMovement(plr)
		State.dirty(plr)
		return true
	elseif cmd == "npc" then
		local best, bestD = nil, math.huge
		for _, npc in Npcs.list do
			if npc.spawned and npc.def.id == a then
				local d = (npc.pos - f.root.Position).Magnitude
				if d < bestD then
					best, bestD = npc, d
				end
			end
		end
		return best and { pos = best.pos, id = best.f.id }
	end
	return nil
end
rf.Parent = ReplicatedStorage

print("[TEST] showcase ready")
task.wait(tonumber(workspace:GetAttribute("ShowcaseSeconds")) or 150)
print("[TEST] showcase done")
StudioTestService:EndTest(0)
