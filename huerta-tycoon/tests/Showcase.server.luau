-- Visual showcase (showcase.project.json): fills the player's plot with every crop, some mid-growth and some
-- mutated, so the client script can photograph the world from fixed cameras. Not part of the published game.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ev = Instance.new("RemoteEvent")
ev.Name = "__Showcase"
ev.Parent = ReplicatedStorage

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Session = require(Services.Session)
local Garden = require(Services.Garden)
local Weather = require(Services.Weather)
local Config = require(ReplicatedStorage.Shared.Config)

local t0 = os.clock()
while not Session.get(player) and os.clock() - t0 < 30 do
	task.wait(0.2)
end
local s = Session.get(player)
if not s then
	print("[TEST] FAIL showcase: no session")
	return
end

-- no random weather during the shoot
Weather.nextAt = os.time() + 99999

local p = s.profile
p.cash = 128500
p.totalEarned = 640000
p.tilesOwned = 24
p.tutorialDone = true
table.clear(p.tiles)
local MUT = { pumpkin = "Golden", corn = "Shocked", tomato = "Frozen", blueberry = "Wet", moonmelon = "Rainbow" }
-- rows 1-2: every seed, ripe
for i, seed in Config.Seeds do
	p.tiles[tostring(i)] = { seed = seed.id, progress = 1, mut = MUT[seed.id] }
end
-- row 3: slow seeds frozen at each growth stage (they barely move during the shoot)
local stages = { 0.05, 0.25, 0.45, 0.65, 0.85, 0.999 }
for k, prog in stages do
	p.tiles[tostring(12 + k)] = { seed = "mango", progress = prog }
end
-- row 4: mid-growth variety
local mids = { "starfruit", "dragonfruit", "moonmelon", "cosmiclotus", "watermelon", "apple" }
for k, id in mids do
	p.tiles[tostring(18 + k)] = { seed = id, progress = 0.62 }
end
p.tiles["5"].size = "Giant"
p.tiles["2"].size = "Big"
p.trophies = { { seed = "pumpkin", mut = "Golden", size = "Giant" }, { seed = "starfruit", size = "Big" }, { seed = "moonmelon", mut = "Rainbow" } }
p.seeds = { carrot = 12, tomato = 6, corn = 4, pumpkin = 2, starfruit = 1 }
p.backpack[Session.basketKey("tomato", nil)] = 9
p.backpack[Session.basketKey("pumpkin", "Golden")] = 2
Garden.renderAll(s)
Session.markDirty(s)
print("[TEST] showcase plot ready")

ev.OnServerEvent:Connect(function(who, kind, arg)
	if who ~= player then
		return
	end
	if kind == "weather" then
		if type(arg) == "string" then
			Weather.start(arg, 600)
			Weather.nextAt = os.time() + 99999
		else
			Weather.current = nil
			Weather.endsAt = os.time()
			Weather.broadcast()
		end
	elseif kind == "sell" then
		Garden.sell(s, true)
	elseif kind == "refill" then
		p.backpack[Session.basketKey("tomato", nil)] = 9
		p.backpack[Session.basketKey("pumpkin", "Golden")] = 2
		Session.markDirty(s)
	elseif kind == "home" then
		Garden.teleportHome(s)
	end
end)
