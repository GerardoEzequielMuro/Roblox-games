-- Screenshot showcase (showcase*.project.json only): gives the player a developed account
-- (every galaxy, a good tool, a mixed set of pets, some progress in every system) and ends
-- the playtest after the runner has taken its screenshots.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Data = require(Services.Data)
local State = require(Services.State)
local Pets = require(Services.Pets)
local Mining = require(Services.Mining)
local Offline = require(Services.Offline)
local QuestService = require(Services.QuestService)
local LiveEventService = require(Services.LiveEventService)
local Progression = require(Services.Progression)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
while not State.ready[player] do
	task.wait(0.2)
end
local p = Data.get(player)
p.tutorial = #Config.Tutorial + 1
p.equipped = {}
for _, spec in { { "solarfox", 0 }, { "nebulaowl", 1 }, { "frostwyrm", 0 }, { "roverbot", 0 }, { "cometcat", 2 }, { "voltdrone", 0 } } do
	Pets.add(player, spec[1], spec[2], true)
end
for _, pet in Config.Pets do
	if pet.zone == 1 or pet.zone == 2 then
		Pets.add(player, pet.id, if pet.rarity == "Legendary" then 1 else 0, true)
	end
end
State.passes[player].PetSlots = true
Pets.equipBest(player)
p.zones = { 1, 2, 3, 4, 5, 6 }
p.tool = "drill_plasma"
p.stardust = 5.234e6
p.crystals = 1840
p.rebirths = 2
p.upgrades.Power = 14
p.upgrades.Cargo = 2
p.upgrades.HitSpeed = 3
p.upgrades.Luck = 2
p.upgrades.Temper = 4
p.mats = { spores = 46, cryo = 120, embers = 33, volt = 12, essence = 5 }
p.relics.damage = { grade = 3, dust = 2 }
p.relics.luck = { grade = 1, dust = 5 }
p.relics.stardust = { grade = 4, dust = 0 }
p.mastery = { rock = 140, fury = 31, zephyr = 12, aurum = 27, clover = 6, prism = 9, titan = 3 }
p.cargo = { count = 17, value = 48200 }
p.buffs = { damage = 38, luck = 52 }
p.auto.mine = true
p.arenaPoints = 130
p.daily = { last = os.time() - 21 * 3600, streak = 3 }
QuestService.ensure(player, { "planets", "hits", "capsules" })
p.quests.progress = { 26, 1500, 3 }
p.quests.claimed = { false, false, false }
LiveEventService.setOverride("MeteorShower", os.time() + 900)
Mining.reset(player)
State.dirty(player)

local ev = Instance.new("RemoteEvent")
ev.Name = "__Showcase"
ev.OnServerEvent:Connect(function(plr, what, arg)
	if what == "offline" then
		p.savedAt = os.time() - (3 * 3600 + 12 * 60)
		Offline.compute(plr)
	elseif what == "tp" then
		Progression.teleportTo(plr, arg)
	elseif what == "node" then -- arg = { zone, node, kind }
		local list = Mining.ensureZone(plr, p, arg[1])
		local node = { kind = arg[3], layer = arg[4] or 1, hp = 0, dense = arg[2] > 5 }
		node.hp = Mining.layerMax(arg[1], node) * 0.6
		list[arg[2]] = node
	elseif what == "auto" then
		p.auto.mine = arg == true
		State.dirty(plr)
	end
end)
ev.Parent = ReplicatedStorage
print("[TEST] showcase ready")
task.wait(tonumber(workspace:GetAttribute("ShowcaseSeconds")) or 235)
print("[TEST] showcase done")
StudioTestService:EndTest(0)
