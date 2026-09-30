-- Screenshot showcase (showcase*.project.json only): gives the player a lived-in profile,
-- poses table t1 with five bots on request (no match is run: the client plays scripted
-- events through the real Director) and ends the playtest after the runner has taken its
-- screenshots.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Data = require(Services.Data)
local State = require(Services.State)
local Remotes = require(Services.Remotes)
local Tables = require(Services.Tables)
local Cosmetics = require(Services.Cosmetics)
local QuestService = require(Services.QuestService)
local LiveEventService = require(Services.LiveEventService)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
while not State.ready[player] do
	task.wait(0.2)
end
local p = Data.get(player)
p.coins = 2450
p.level = 7
p.xp = 180
p.trophies = 320
p.bestTrophies = 320
p.wins = 12
p.matches = 31
p.streak = 3
p.bestStreak = 4
p.tutorialDone = true
for _, id in { "w_neon", "w_candy", "f_ufo", "f_rocket", "a_sparks", "e_cool", "ti_lucky" } do
	p.owned[id] = true
end
p.equipped.finisher = "f_ufo"
p.equipped.aura = "a_sparks"
p.equipped.title = "ti_lucky"
QuestService.ensure(player, { "play", "zaps", "win" })
p.quests.progress = { 2, 5, 0 }
LiveEventService.setOverride("DoubleXP", os.time() + 900)
Cosmetics.refresh(player, true)
State.dirty(player)

local tbl = Tables.byId.t1
local ev = Instance.new("RemoteEvent")
ev.Name = "__Showcase"
ev.OnServerEvent:Connect(function(plr, what)
	if what == "stage" then
		if not Tables.seatOf(plr) then
			Tables.sit(plr, tbl)
			Tables.addBots(tbl, 5)
			tbl.status = "playing" -- keeps the countdown from starting a real match
			Remotes.fireAll("Tables", Tables.snapshot())
			State.dirty(plr)
		end
	elseif what == "unstage" then
		tbl.status = "open"
		Tables.clearBots(tbl)
		Tables.leave(plr)
		Remotes.fireAll("Tables", Tables.snapshot())
	end
end)
ev.Parent = ReplicatedStorage
print("[TEST] showcase ready")
task.wait(tonumber(workspace:GetAttribute("ShowcaseSeconds")) or 240)
print("[TEST] showcase done")
StudioTestService:EndTest(0)
