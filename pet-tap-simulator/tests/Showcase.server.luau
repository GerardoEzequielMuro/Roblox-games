-- Screenshot showcase (showcase.project.json only): gives the player a nice set of pets,
-- unlocks zones 1-4 (zone 5 on request) and ends the playtest after the runner has taken
-- its screenshots.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Data = require(Services.Data)
local State = require(Services.State)
local Pets = require(Services.Pets)
local Offline = require(Services.Offline)
local QuestService = require(Services.QuestService)
local LiveEventService = require(Services.LiveEventService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
while not State.ready[player] do
	task.wait(0.2)
end
local p = Data.get(player)
for _, pass in Config.Passes do
	State.passes[player][pass.key] = true
end
p.equipped = {}
for _, spec in { { "unicorn", 0 }, { "fox", 1 }, { "candydragon", 0 }, { "hellhound", 0 }, { "owl", 0 }, { "chick", 2 } } do
	Pets.add(player, spec[1], spec[2], true)
end
for _, pet in Config.Pets do
	if pet.zone == 1 or pet.zone == 2 then
		Pets.add(player, pet.id, if pet.rarity == "Legendary" then 1 else 0, true)
	end
end
for z = 2, 4 do
	table.insert(p.zones, z)
end
p.taps = 523400
p.gems = 180
QuestService.ensure(player, { "hatch", "taps", "rarity" })
p.quests.progress = { 6, 300, 0 }
p.quests.claimed = { false, true, false }
LiveEventService.setOverride("LuckyHour", os.time() + 900)
State.dirty(player)
-- the client asks for the offline popup / the last zone when its scene comes up
local ev = Instance.new("RemoteEvent")
ev.Name = "__Showcase"
ev.OnServerEvent:Connect(function(plr, what)
	if what == "offline" then
		p.savedAt = os.time() - (3 * 3600 + 12 * 60)
		Offline.compute(plr)
	elseif what == "unlock5" then
		if not table.find(p.zones, 5) then
			table.insert(p.zones, 5)
			State.dirty(plr)
		end
	end
end)
ev.Parent = game:GetService("ReplicatedStorage")
print("[TEST] showcase ready")
task.wait(tonumber(workspace:GetAttribute("ShowcaseSeconds")) or 215)
print("[TEST] showcase done")
StudioTestService:EndTest(0)
