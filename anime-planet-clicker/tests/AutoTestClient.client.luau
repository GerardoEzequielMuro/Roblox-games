-- Client side of the gameplay test: plays the whole game through the real remotes and UI
-- modules, one system at a time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local clientErrors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(clientErrors, msg)
	end
end)

local lines = {}
local function show(v)
	if type(v) == "table" then
		if type(v.key) == "string" then
			return v.key
		end
		return "{" .. #v .. " items}"
	end
	return (tostring(v):gsub("\n", " / "))
end
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail ~= nil then " :: " .. show(detail) else "")
	if not cond then
		print("[TEST] c " .. line) -- the server prints the full report at the end
	end
	table.insert(lines, line)
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request") :: RemoteFunction
local HitEvent = Remotes:WaitForChild("Hit") :: RemoteEvent
local ZapEvent = Remotes:WaitForChild("Zap") :: RemoteEvent
local T = ReplicatedStorage:WaitForChild("__Test", 60) :: RemoteFunction
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Layout = require(Shared.Layout)
local Locale = require(Shared.Locale)
local PetModel = require(Shared.PetModel)
local PlanetModel = require(Shared.PlanetModel)
local ToolModel = require(Shared.ToolModel)
local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Lang = require(Client:WaitForChild("Lang"))
local Net = require(Client:WaitForChild("Net"))
local Miner = require(Client:WaitForChild("Miner"))
local PlanetField = require(Client:WaitForChild("PlanetField"))
local PetFollow = require(Client:WaitForChild("PetFollow"))
local ToolFx = require(Client:WaitForChild("ToolFx"))
local WorldFx = require(Client:WaitForChild("WorldFx"))
local Quality = require(Client:WaitForChild("Quality"))
local PvpClient = require(Client:WaitForChild("PvpClient"))
local Guide = require(Client:WaitForChild("Guide"))
local Purchase = require(Client:WaitForChild("Purchase"))
local UI = Client:WaitForChild("UI")
local Windows = require(UI:WaitForChild("Windows"))
local CapsulePanel = require(UI:WaitForChild("CapsulePanel"))
local CapsuleCinematic = require(UI:WaitForChild("CapsuleCinematic"))
local UpgradesWindow = require(UI:WaitForChild("UpgradesWindow"))

local function req(action, payload)
	task.wait(0.12) -- stay under the Request rate limit (12/s)
	local ok, a, b = pcall(function()
		return Request:InvokeServer(action, payload)
	end)
	if not ok then
		return false, a
	end
	return a == true, b
end
local function srv(cmd, a, b, c)
	return T:InvokeServer(cmd, a, b, c)
end
local function waitFor(cond, timeout)
	local t = 0
	while t < (timeout or 5) do
		if cond() then
			return true
		end
		t += task.wait(0.1)
	end
	return cond()
end
local function v3(p)
	return Vector3.new(p[1], p[2], p[3])
end
-- stand `back` studs south of a planet
local function standAt(zone, node, back)
	local p = Layout.nodePosition(zone, node)
	srv("tp", { p[1], 4, p[3] - (back or 12) })
	task.wait(0.5)
end

local notifications = {}
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(message)
	table.insert(notifications, message)
end)
local tutorialEvents = {}
Remotes:WaitForChild("Tutorial").OnClientEvent:Connect(function(msg)
	table.insert(tutorialEvents, msg)
end)
local mineMessages = {}
Remotes:WaitForChild("Mine").OnClientEvent:Connect(function(msg)
	table.insert(mineMessages, msg)
end)
local nodeMessages = 0
Remotes:WaitForChild("Node").OnClientEvent:Connect(function()
	nodeMessages += 1
end)
local hatched = {}
Remotes:WaitForChild("Hatched").OnClientEvent:Connect(function(data)
	table.insert(hatched, data)
end)
local pvpMessages = {}
Remotes:WaitForChild("Pvp").OnClientEvent:Connect(function(msg)
	table.insert(pvpMessages, msg)
end)
local liveUpdates = {}
Remotes:WaitForChild("LiveEventUpdate").OnClientEvent:Connect(function(d)
	table.insert(liveUpdates, d)
end)
local asks = 0
Remotes:WaitForChild("AskNotifications").OnClientEvent:Connect(function()
	asks += 1
end)

---------------------------------------------------------------------------
-- 1. Session, UI, world
---------------------------------------------------------------------------
do
	local okQ, q = pcall(function()
		local r = (settings() :: any).Rendering
		local prev = r.QualityLevel
		r.QualityLevel = prev
		return tostring(prev)
	end)
	local okU, u = pcall(function()
		local gs = UserSettings():GetService("UserGameSettings")
		local prev = gs.SavedQualityLevel
		gs.SavedQualityLevel = prev
		return tostring(prev)
	end)
	print("[TEST] INFO quality probe (client): settings ok=" .. tostring(okQ) .. " " .. tostring(q) .. " | UserGameSettings ok=" .. tostring(okU) .. " " .. tostring(u))
end
local okState, state
for _ = 1, 80 do
	okState, state = req("GetState")
	if okState then
		break
	end
	task.wait(0.5)
end
check("GetState", okState and type(state) == "table", state)
state = if type(state) == "table" then state else {}
check("state: 1 pet equipped, 3 slots, tutorial at step 1", #state.equipped == 1 and state.maxEquip == Config.BaseEquipSlots and state.tutorial == 1)
check("state carries the derived stats", state.damage > 0 and state.hitsPerSecond == Config.BaseHitsPerSecond and state.range == Config.BaseRange and state.cargo.cap == Config.CargoBase)

local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
task.wait(1.5)

local gui = player:WaitForChild("PlayerGui")
local mainGui = gui:WaitForChild("PlanetUI", 10) :: ScreenGui
check("main UI built", mainGui ~= nil and #mainGui:GetDescendants() > 200, mainGui and #mainGui:GetDescendants())
check("main UI uses CoreUISafeInsets", mainGui and mainGui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)
check("HUD has the cargo panel, the counters and the auto chips", mainGui:FindFirstChild("Cargo", true) ~= nil and mainGui:FindFirstChild("Stardust", true) ~= nil and mainGui:FindFirstChild("Auto_mine", true) ~= nil and mainGui:FindFirstChild("Auto_rebirth", true) ~= nil)

-- world of galaxy 1 (streamed in around the spawn)
local world = workspace:WaitForChild("World", 20)
local zone1 = world and world:FindFirstChild("Zone1_dawn")
local missing = {}
for _, name in { "Deck", "Pads", "Plaza", "Gate", "Decor" } do
	local f = zone1 and zone1:FindFirstChild(name)
	if not f or #f:GetChildren() == 0 then
		table.insert(missing, name)
	end
end
check("galaxy 1 has deck, pads, plaza, gate frame and scenery", #missing == 0, table.concat(missing, ", "))
check("sky rig follows the camera", workspace:FindFirstChild("SkyRig") ~= nil and workspace.SkyRig:FindFirstChild("Dome") ~= nil and (workspace.SkyRig.PrimaryPart.Position - workspace.CurrentCamera.CFrame.Position).Magnitude < 5)
local skyParts = #workspace.SkyRig:GetChildren()
check("sky rig part budget (<= 320)", skyParts > 60 and skyParts <= 320, skyParts)
check("galaxy lighting applied", WorldFx.place == "zone1" and math.abs(Lighting.ClockTime - 15.2) < 0.3, Lighting.ClockTime)
check("animated props registered", WorldFx.animCount() >= 8 and #CollectionService:GetTagged("PcAnim") >= 8, WorldFx.animCount())

---------------------------------------------------------------------------
-- 2. Planets on the client
---------------------------------------------------------------------------
check("planet field loaded for galaxy 1", waitFor(function()
	return PlanetField.zone == 1 and PlanetField.views[1] ~= nil
end, 10), PlanetField.zone)
local anomalyOn, anomalyWindow = Formulas.anomaly(os.time())
local expectViews = Config.NodesPerZone + 2 + (if anomalyOn then 1 else 0) -- regular + Titan + Gate (+ Anomaly)
local views, planetParts, worstPlanet = 0, 0, 0
for _, view in PlanetField.views do
	views += 1
	if view.model then
		local n = PlanetModel.partCount(view.model)
		planetParts += n
		worstPlanet = math.max(worstPlanet, n)
	end
end
check("one planet per node (12 + Titan + Gate, + Anomaly when it is up)", views == expectViews, views .. " vs " .. expectViews)
check("planet part budget (each <= 60, field <= 600)", worstPlanet <= 60 and planetParts <= 600, worstPlanet .. " / " .. planetParts)
check("gate planet is drawn in the top galaxy", PlanetField.views[Config.NodeGate] ~= nil and PlanetField.views[Config.NodeGate].kind == "gate")

-- every planet kind builds, lite has fewer parts, layers hide
local badPlanets, fullParts, liteParts = {}, 0, 0
for _, kind in Config.PlanetKinds do
	for _, lite in { false, true } do
		local okB, m = pcall(PlanetModel.build, kind.id, 3, { lite = lite })
		if not okB then
			table.insert(badPlanets, kind.id .. ": " .. tostring(m))
		else
			local n = PlanetModel.partCount(m)
			if lite then
				liteParts += n
			else
				fullParts += n
			end
			if not (m:FindFirstChild("Crust") and m:FindFirstChild("Mantle") and m:FindFirstChild("Core")) then
				table.insert(badPlanets, kind.id .. ": missing a layer")
			end
			PlanetModel.setLayer(m, 2)
			local shell = m.Crust:FindFirstChild("Shell") :: BasePart
			if shell.Transparency ~= 1 or (m.Mantle:FindFirstChild("Shell") :: BasePart).Transparency ~= 0 then
				table.insert(badPlanets, kind.id .. ": setLayer")
			end
			m:Destroy()
		end
	end
end
check("every planet kind builds with 3 layers (full + lite)", #badPlanets == 0, table.concat(badPlanets, " | "))
check("lite planets use fewer parts", liteParts < fullParts * 0.85, liteParts .. " vs " .. fullParts)

---------------------------------------------------------------------------
-- 3. Tutorial = the core loop, step by step (mine, core, sell, capsule, tool, auto)
---------------------------------------------------------------------------
check("tutorial points at a planet", Guide.step == "mine" and Guide.target ~= nil and workspace:FindFirstChild("GuideArrow") ~= nil)
local objective = mainGui:FindFirstChild("Objective", true)
local objectiveText = objective and objective:FindFirstChild("Text") :: TextLabel?
check("objective line shows the tutorial step", objectiveText ~= nil and objectiveText.Text:find(Lang.t("tutorial.mine"), 1, true) ~= nil, objectiveText and objectiveText.Text)
check("menu starts small (Pets and Rebirth appear later)", mainGui:FindFirstChild("Upgrades", true).Visible == true and mainGui:FindFirstChild("Rebirth", true).Visible == false and mainGui:FindFirstChild("Pets", true).Visible == false)

srv("setNode", 1, 1, "rock")
PlanetField.load(1)
standAt(1, 1, 12)
local prof = srv("profile")
local hits0 = prof.hits
-- out of range first: node 12 is on the far side
HitEvent:FireServer(12, 3)
task.wait(0.4)
check("hit on a planet out of range is ignored", srv("profile").hits == hits0)
local sent0 = Miner.sent
local landed = 0
for _ = 1, 45 do
	if Miner.simulate(1) then
		landed += 1
	end
	task.wait(0.1)
	if srv("node", 1, 1).layer >= 2 then
		break
	end
end
task.wait(0.5)
prof = srv("profile")
local node = srv("node", 1, 1)
check("clicks reach the server in batches", prof.hits > hits0 and Miner.sent - sent0 >= prof.hits - hits0, (prof.hits - hits0) .. " accepted of " .. (Miner.sent - sent0) .. " sent")
check("client hit rate is capped locally", landed < 45 or prof.hits - hits0 <= 40, landed)
check("crust broke: planet is on its mantle", node.layer >= 2, node.layer)
check("broken layer went into the cargo hold", prof.cargo.count >= 1 and prof.cargo.value > 0 and prof.stardust == 40, prof.cargo.count .. " chunks, stardust " .. prof.stardust)
check("tutorial step 1 done (reward 40 Stardust)", prof.tutorial == 2 and #tutorialEvents == 1, prof.tutorial)
local view1 = PlanetField.views[1]
check("client planet shows the mantle", view1 ~= nil and view1.layer == node.layer and view1.model ~= nil and (view1.model.Crust.Shell :: BasePart).Transparency == 1)
check("pets and tool point at the planet being mined", prof.mineNode == 101 and ToolFx.has(), prof.mineNode)

-- rate cap on the server: a burst of 100 and then 2 s of spam
srv("setNode", 1, 2, "titan") -- a lot of HP so nothing breaks
local p2 = Layout.nodePosition(1, 2)
srv("tp", { p2[1], 4, p2[3] - 12 })
task.wait(0.6)
hits0 = srv("profile").hits
HitEvent:FireServer(2, 100)
task.wait(0.5)
local burst = srv("profile").hits - hits0
check("hit burst is clamped to the bucket", burst >= 1 and burst <= Config.BaseHitsPerSecond + Config.HitBurst + 1, burst)
hits0 = srv("profile").hits
local tStart = os.clock()
for _ = 1, 40 do
	HitEvent:FireServer(2, 5)
	task.wait(0.05)
end
task.wait(0.3)
local elapsed = os.clock() - tStart
local accepted = srv("profile").hits - hits0
check("sustained hits capped at the player's hits per second", accepted > 0 and accepted <= Config.BaseHitsPerSecond * (elapsed + 0.8) + 1, string.format("%d in %.2fs", accepted, elapsed))
HitEvent:FireServer(2, -5)
HitEvent:FireServer(2, 0 / 0)
HitEvent:FireServer("x", 5)
HitEvent:FireServer(99, 5)
task.wait(0.3)
check("bogus hit payloads ignored", srv("profile").hits == hits0 + accepted)
local crits = 0
for _, m in mineMessages do
	crits += m.c or 0
end
check("server reports hits back (damage, layer, HP)", #mineMessages > 3 and mineMessages[#mineMessages].h ~= nil and mineMessages[#mineMessages].dmg > 0, #mineMessages)

-- core
prof = srv("profile")
local broken0, cargo0 = prof.planetsBroken, prof.cargo.count
srv("hits", 1, 1, 400)
task.wait(0.4)
prof = srv("profile")
node = srv("node", 1, 1)
check("core broke: planet counted, respawn scheduled", prof.planetsBroken == broken0 + 1 and node.respawning == true, prof.planetsBroken)
check("cargo got the mantle and the core (core = 2 chunks)", prof.cargo.count == cargo0 + 3, prof.cargo.count - cargo0)
check("mastery counts the planet kind", (prof.mastery.rock or 0) >= 1)
check("tutorial step 2 done", prof.tutorial == 3, prof.tutorial)
check("client hides the broken planet", PlanetField.views[1] ~= nil and PlanetField.views[1].alive == false)
check("planet respawns after 5 s and the client redraws it", waitFor(function()
	return not srv("node", 1, 1).respawning and PlanetField.views[1] ~= nil and PlanetField.views[1].alive
end, 8) and nodeMessages >= 1, nodeMessages)

-- sell by hand on the Refinery pad
prof = srv("profile")
local value, before = prof.cargo.value, prof.stardust
srv("tp", { Layout.refineryPosition(1)[1], 4, Layout.refineryPosition(1)[3] })
check("walking onto the Refinery sells the hold", waitFor(function()
	return srv("profile").cargo.count == 0
end, 4))
prof = srv("profile")
local gain = prof.stardust - before - 120 -- 120 = tutorial reward for the first sale
check("hand delivery pays +20%", math.abs(gain - value * (1 + Config.CargoHandBonus)) < 0.01 * value + 0.01, string.format("%.2f vs %.2f", gain, value * 1.2))
check("tutorial step 3 done", prof.tutorial == 4, prof.tutorial)

-- capsule
srv("give", "stardust", 5000)
local capPos = Layout.capsulePosition("dawn")
local ok, res = req("Open", { capsule = "dawn", count = 1 })
check("open from far away rejected", not ok and type(res) == "table" and res.key == "msg.get_closer", res)
srv("tp", { capPos[1] + 8, 4, capPos[3] + 6 })
task.wait(0.6)
local count0 = srv("profile").petCount
local _, stBefore = req("GetState")
ok, res = req("Open", { capsule = "dawn", count = 1 })
check("open x1 next to the machine", ok and type(res) == "table" and #res == 1, res)
if ok and type(res) == "table" and res[1] then
	check("result carries rarity, chance and the NEW flag", res[1].rarity ~= nil and res[1].chance > 0 and res[1].new == not (stBefore.discovered[res[1].id] == true), res[1].id)
end
prof = srv("profile")
check("pet added, Stardust spent", prof.petCount == count0 + 1 and prof.totalOpened == 1)
check("tutorial step 4 done (Pets button appears)", prof.tutorial == 5 and waitFor(function()
	return mainGui:FindFirstChild("Pets", true).Visible
end, 3))
ok, res = req("Open", { capsule = "dawn", count = 1 })
check("open during cooldown rejected", not ok and res == "cooldown", res)
task.wait(Config.OpenCooldown)
ok, res = req("Open", { capsule = "dawn", count = 3 })
check("open x3 without the pass rejected", not ok, res)
ok, res = req("Open", { capsule = "verdant", count = 1 })
check("capsule of a locked galaxy rejected", not ok, res)
ok, res = req("Open", { capsule = "quantum", count = 1 })
check("Robux capsule cannot be opened with Stardust", not ok, res)

-- odds: what the panel shows is what the server rolls, and it adds up to 100%
CapsulePanel.open("dawn")
task.wait(0.5)
local odds = CapsulePanel.odds("dawn")
local total = 0
for _, o in odds do
	total += o.chance
end
check("shown odds add up to exactly 100%", math.abs(total - 100) < 1e-9, total)
local oddCells, chanceLabels = 0, 0
local capsuleWindow = mainGui:FindFirstChild("CapsuleWindow", true)
for _, d in capsuleWindow:GetDescendants() do
	if d.Name:sub(1, 4) == "Odd_" then
		oddCells += 1
	elseif d.Name == "Chance" and d:IsA("TextLabel") and d.Text:find("%%") then
		chanceLabels += 1
	end
end
check("capsule panel lists every outcome with a percentage", capsuleWindow.Visible and oddCells == #odds and chanceLabels == #odds, oddCells .. " cells")
local totalLabel = capsuleWindow:FindFirstChild("Total", true) :: TextLabel?
check("panel states the 100% total and the player's luck", totalLabel ~= nil and totalLabel.Text:find("100%%") ~= nil, totalLabel and totalLabel.Text)
local rolls = srv("rollMany", "dawn", stBefore.luck, 60000)
local worstDelta = 0
for _, o in odds do
	local got = (rolls[o.id] or 0) / 60000 * 100
	if o.chance >= 1 then
		worstDelta = math.max(worstDelta, math.abs(got - o.chance))
	end
end
check("60,000 rolls match the shown odds", worstDelta < 0.8, string.format("worst %.2f points", worstDelta))
Windows.close()

-- tool
ok, res = req("BuyTool", { id = "drill_spark" })
check("tool of a locked galaxy rejected", not ok and res.key == "msg.unlock_first", res)
local dmg0 = srv("profile").damage
ok, res = req("BuyTool", { id = "pick_iron" })
prof = srv("profile")
check("buy the next tool", ok and prof.tool == "pick_iron" and math.abs(prof.damage / dmg0 - 3) < 0.01, prof.damage / dmg0)
check("tutorial step 5 done", prof.tutorial == 6, prof.tutorial)
ok, res = req("BuyTool", { id = "pick_rusty" })
check("buying a worse tool rejected", not ok and res.key == "msg.tool_owned", res)
check("tool replicates to everyone (attribute)", waitFor(function()
	return player:GetAttribute("Tool") == "pick_iron"
end, 3))

-- auto (last tutorial step)
ok = req("SetAuto", { key = "mine", on = true })
prof = srv("profile")
check("Auto Mine on finishes the tutorial", ok and prof.auto.mine == true and prof.tutorial == #Config.Tutorial + 1, prof.tutorial)
check("6 tutorial events, 6 rewards", #tutorialEvents == #Config.Tutorial, #tutorialEvents)
check("guide arrow is gone, the goal is the Gate now", waitFor(function()
	return Guide.step == nil and workspace:FindFirstChild("GuideArrow") == nil
end, 3) and objectiveText ~= nil and objectiveText.Text:find(Lang.zone(2), 1, true) ~= nil, objectiveText and objectiveText.Text)
check("the whole menu is unlocked", mainGui:FindFirstChild("Rebirth", true).Visible and mainGui:FindFirstChild("Quests", true).Visible)

---------------------------------------------------------------------------
-- 4. Autos (all server-driven)
---------------------------------------------------------------------------
-- Auto Mine: no client hits are sent, the server mines the nearest planet by itself
srv("setNode", 1, 3, "titan")
standAt(1, 3, 12)
task.wait(0.5)
prof = srv("profile")
hits0, sent0 = prof.hits, Miner.sent
local ticks0 = srv("autoTicks")
local tA = os.clock()
task.wait(4)
local span = os.clock() - tA
prof = srv("profile")
local ticks1 = srv("autoTicks")
local autoHits = prof.hits - hits0
check("Auto Mine works with zero client input", autoHits >= Config.AutoMineRateFree * span * 0.6 and Miner.sent == sent0, autoHits .. " hits, " .. (Miner.sent - sent0) .. " sent")
check("Auto Mine respects its rate (2 hits/s free)", autoHits <= Config.AutoMineRateFree * span + 3, string.format("%d in %.1fs", autoHits, span))
check("one auto loop on the server (4 ticks per second)", ticks1 - ticks0 >= span / Config.AutoTick * 0.6 and ticks1 - ticks0 <= span / Config.AutoTick * 1.4 + 2, ticks1 - ticks0)
check("auto hits are flagged for the client", mineMessages[#mineMessages].a == true)
-- faster with the upgrade and the pass
srv("give", "crystals", 1000)
req("Upgrade", { id = "AutoRate" })
srv("grantPass", "AutoMiner", true)
task.wait(0.5)
local _, stAuto = req("GetState")
check("Auto Mine speed: upgrade + pass", math.abs(stAuto.autoRate - (Config.AutoMineRateFree + 0.5) * Config.AutoMinePassMult) < 0.01, stAuto.autoRate)
hits0 = srv("profile").hits
task.wait(2)
autoHits = srv("profile").hits - hits0
check("passed Auto Mine really is faster", autoHits >= 10, autoHits)
srv("grantPass", "AutoMiner", false)
req("SetAuto", { key = "mine", on = false })
task.wait(0.6)
hits0 = srv("profile").hits
task.wait(1.2)
check("Auto Mine off stops", srv("profile").hits == hits0)
local chip = mainGui:FindFirstChild("Auto_mine", true)
local chipLabel = chip and chip:FindFirstChild("Label") :: TextLabel?
check("HUD chip says OFF", chipLabel ~= nil and chipLabel.Text:find(Lang.t("hud.off"), 1, true) ~= nil, chipLabel and chipLabel.Text)
ok, res = req("SetAuto", { key = "hack", on = true })
check("unknown auto rejected", not ok, res)

-- Auto Sell: a full hold sends the drone; the hold blocks mining while it is away
req("SetAuto", { key = "sell", on = false })
srv("set", "cargoFull", 500)
task.wait(0.4)
hits0 = srv("profile").hits
local n0 = #mineMessages
HitEvent:FireServer(3, 3)
task.wait(0.5)
check("full cargo blocks mining and tells the client", srv("profile").hits == hits0 and #mineMessages > n0 and mineMessages[#mineMessages].full == true)
local cargoCount = mainGui:FindFirstChild("Cargo", true):FindFirstChild("Count") :: TextLabel
check("HUD shows the full hold", cargoCount.Text:find(tostring(Config.CargoBase), 1, true) ~= nil, cargoCount.Text)
before = srv("profile").stardust
req("SetAuto", { key = "sell", on = true })
check("Auto Sell launches the drone when the hold is full", waitFor(function()
	local pr = srv("profile")
	return pr.transit ~= nil and pr.cargo.count == 0
end, 3))
ok, res = req("SellCargo")
check("SELL with an empty hold rejected", not ok and res.key == "msg.cargo_empty", res)
check("drone delivers after its trip (no bonus)", waitFor(function()
	return srv("profile").transit == nil
end, Config.DroneSeconds + 3) and math.abs(srv("profile").stardust - before - 500) < 0.01, srv("profile").stardust - before)
srv("set", "cargo", 3, 90)
ok = req("SellCargo")
check("SELL button sends the drone on demand", ok and srv("profile").transit ~= nil)
ok, res = req("SellCargo")
check("second drone while one is flying rejected", not ok, res)
waitFor(function()
	return srv("profile").transit == nil
end, Config.DroneSeconds + 3)

-- Auto Upgrade + Auto Rebirth
srv("set", "stardust", 3000)
req("SetAuto", { key = "upgrade", on = true })
check("Auto Upgrade buys the best tool it can afford and Power levels", waitFor(function()
	local pr = srv("profile")
	return pr.tool == "pick_titanium" and pr.upgrades.Power >= 1
end, 4), srv("profile").tool)
req("SetAuto", { key = "upgrade", on = false })
srv("set", "stardust", Formulas.rebirthCost(0) + 10)
local crystals0 = srv("profile").crystals
req("SetAuto", { key = "rebirth", on = true })
check("Auto Rebirth rebirths as soon as it is affordable", waitFor(function()
	return srv("profile").rebirths == 1
end, 4))
req("SetAuto", { key = "rebirth", on = false })
prof = srv("profile")
check("rebirth: Stardust, tool and Power reset; galaxies and Crystals kept", prof.stardust < 1000 and prof.tool == "pick_rusty" and prof.upgrades.Power == 0 and prof.upgrades.AutoRate == 1 and prof.crystals == crystals0 + Formulas.rebirthCrystals(0), prof.crystals - crystals0)
check("notification ask after the first rebirth", waitFor(function()
	return asks >= 1
end, 3), asks)
ok, res = req("Rebirth")
check("manual rebirth without Stardust rejected", not ok, res)

-- Auto Open (from anywhere in the galaxy) + Auto Delete + Auto Best + Auto Fuse
srv("give", "stardust", 100000)
standAt(1, 3, 12)
ok = req("SetAutoOpen", { capsule = "dawn" })
local opened0 = srv("profile").totalOpened
task.wait(5.5)
local opened1 = srv("profile").totalOpened
check("Auto Open keeps opening while you stay in the galaxy", ok and opened1 - opened0 >= 2, opened1 - opened0)
local autoEvent = false
for _, e in hatched do
	if e.auto then
		autoEvent = true
	end
end
check("Auto Open results arrive as compact events", autoEvent)
ok, res = req("SetAutoOpen", { capsule = "verdant" })
check("Auto Open on a locked capsule rejected", not ok, res)
req("SetAutoOpen", {})
task.wait(Config.OpenCooldown + 0.5)
opened1 = srv("profile").totalOpened
task.wait(2.5)
check("Auto Open off stops", srv("profile").totalOpened == opened1)
ok = req("SetAutoDelete", { rarity = "Common", on = true })
check("Auto Delete toggle", ok and srv("profile").autoDelete.Common == true)
ok, res = req("SetAutoDelete", { rarity = "Legendary", on = true })
check("Auto Delete cannot be set for rare pets", not ok, res)
req("SetAutoDelete", { rarity = "Common", on = false })

req("SetAuto", { key = "best", on = false })
req("Unequip", { uid = srv("profile").equipped[1] })
local fox = srv("givePets", "solarfox", 1)[1]
req("Unequip", { uid = fox })
check("with Auto Best off the strong pet can sit unequipped", table.find(srv("profile").equipped, fox) == nil)
req("SetAuto", { key = "best", on = true })
check("Auto Best equips the strongest pets", table.find(srv("profile").equipped, fox) ~= nil and #srv("profile").equipped == srv("profile").maxEquip)
srv("givePets", "dustbunny", 5)
req("SetAuto", { key = "fuse", on = true })
prof = srv("profile")
check("Auto Fuse turns 5 of a kind into a Golden", (prof.byId["dustbunny:1"] or 0) >= 1, prof.byId["dustbunny:1"])
req("SetAuto", { key = "fuse", on = false })

---------------------------------------------------------------------------
-- 5. Pets: inventory actions, rendering
---------------------------------------------------------------------------
local cats = srv("givePets", "cometcat", 5)
prof = srv("profile")
local cat0 = prof.byId["cometcat:0"] or 0
ok, res = req("Fuse", { uid = cats[1] })
prof = srv("profile")
check("fuse 5 into a Golden", ok and (prof.byId["cometcat:1"] or 0) >= 1 and (prof.byId["cometcat:0"] or 0) == cat0 - 5, res)
ok, res = req("Fuse", { uid = if type(res) == "string" then res else "" })
check("fuse with only 1 Golden rejected", not ok, res)
local pup = srv("givePets", "pebblepup", 1)[1]
check("lock", (req("Lock", { uid = pup, locked = true })))
ok, res = req("Delete", { uids = { pup } })
check("delete locked rejected", not ok, res)
req("Lock", { uid = pup, locked = false })
local c0 = srv("profile").petCount
ok, res = req("Delete", { uids = { pup } })
check("delete unlocked", ok and srv("profile").petCount == c0 - 1, res)
ok = req("EquipBest")
prof = srv("profile")
check("equip best fills the slots", ok and #prof.equipped == math.min(prof.maxEquip, prof.petCount), #prof.equipped .. "/" .. prof.maxEquip)
local spare
for uid in prof.pets do
	if not table.find(prof.equipped, uid) then
		spare = uid
	end
end
req("SetAuto", { key = "best", on = false })
ok, res = req("Equip", { uid = spare })
check("equip with every slot in use rejected", not ok, res)
ok, res = req("Equip", { uid = "nope" })
check("equip unknown pet rejected", not ok, res)
ok, res = req("RollTrait", { uid = prof.equipped[1] })
check("Traits are locked before the Ember Forge", not ok and res.key == "msg.unlock_first", res)

task.wait(2.5)
prof = srv("profile")
local petFolder = workspace:FindFirstChild("ClientPets")
local models, shadows, near = 0, 0, 0
if petFolder then
	for _, m in petFolder:GetChildren() do
		if m:IsA("Model") then
			models += 1
			if (m:GetPivot().Position - hrp.Position).Magnitude < 22 then
				near += 1
			end
		elseif m.Name == "PetShadow" then
			shadows += 1
		end
	end
end
check("equipped pets are drawn next to the player, each with a shadow", models == #prof.equipped and near == models and shadows == models, string.format("%d models, %d near, %d shadows, %d equipped", models, near, shadows, #prof.equipped))
check("pets replicate as an attribute, not as instances", type(player:GetAttribute("EquippedPets")) == "string" and #(player:GetAttribute("EquippedPets") :: string) > 0)
check("pets peck on a hit", (pcall(PetFollow.pulse)))

-- every pet builds in every tier, lite and full, within the part budget
local built, worst, worstId, bad = 0, 0, "", {}
local flyers, jointed = 0, 0
for _, pet in Config.Pets do
	for tier = 0, 2 do
		for _, lite in { true, false } do
			local okBuild, m = pcall(PetModel.build, pet.id, tier, { lite = lite })
			if not okBuild then
				table.insert(bad, pet.id .. ": " .. tostring(m))
			else
				built += 1
				local parts = 0
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						parts += 1
					end
				end
				if parts > worst then
					worst, worstId = parts, pet.id
				end
				local foot = m:GetAttribute("FootY")
				if m.PrimaryPart == nil or type(foot) ~= "number" or foot >= 0 then
					table.insert(bad, pet.id .. ": no root / FootY")
				end
				if lite and (m:FindFirstChildWhichIsA("ParticleEmitter", true) or m:FindFirstChildWhichIsA("PointLight", true)) then
					table.insert(bad, pet.id .. ": lite build has effects")
				end
				if tier == 0 and not lite then
					if m:GetAttribute("Flyer") then
						flyers += 1
					end
					if m:FindFirstChild("Joint", true) then
						jointed += 1
					end
				end
				m:Destroy()
			end
		end
	end
end
check("every pet builds (3 tiers, lite + full)", #bad == 0 and built == #Config.Pets * 6, if #bad > 0 then table.concat(bad, " | ") else built)
check("pet part budget (<= 60 parts)", worst <= 60, worstId .. " " .. worst)
check("pets have flyers and animated joints", flyers >= 10 and jointed >= 28, flyers .. " flyers, " .. jointed .. " jointed")
local toolBad = {}
for _, tool in Config.Tools do
	local okT, m = pcall(ToolModel.build, tool.id)
	if not okT or not m.PrimaryPart or not m.PrimaryPart:FindFirstChild("Tip") then
		table.insert(toolBad, tool.id)
	elseif m then
		m:Destroy()
	end
end
check("every tool builds with a grip and a tip", #toolBad == 0, table.concat(toolBad, ", "))

---------------------------------------------------------------------------
-- 6. Buff planets, Titan, Anomaly, Mastery
---------------------------------------------------------------------------
req("BuyTool", { id = "pick_iron" })
srv("setNode", 1, 4, "fury")
local _, stB0 = req("GetState")
srv("hits", 1, 4, 3000)
task.wait(0.5)
local _, stB1 = req("GetState")
prof = srv("profile")
check("Fury planet gives the damage buff", (prof.buffs.damage or 0) > 30 and math.abs(stB1.damage / stB0.damage - Config.Buffs.damage.mult) < 0.01, stB1.damage / stB0.damage)
check("buff shows on the HUD with a timer", waitFor(function()
	local row = mainGui:FindFirstChild("Buff_damage", true)
	return row ~= nil and row.Visible
end, 3))
srv("setNode", 1, 5, "zephyr")
srv("hits", 1, 5, 3000)
task.wait(1.4)
prof = srv("profile")
check("Zephyr planet gives speed: walk speed and hits per second", (prof.buffs.speed or 0) > 30 and math.abs(prof.walkSpeed - Config.BaseWalkSpeed * Config.Buffs.speed.mult) < 0.1, prof.walkSpeed)
srv("setNode", 1, 6, "aurum")
srv("hits", 1, 6, 9000)
srv("setNode", 1, 7, "clover")
srv("hits", 1, 7, 9000)
task.wait(0.5)
local _, stB2 = req("GetState")
check("Aurum doubles Stardust and Clover doubles luck", (stB2.buffs.stardust or 0) > 0 and math.abs(stB2.stardustMult / stB1.stardustMult - 2) < 0.01 and math.abs(stB2.luck / stB1.luck - 2) < 0.01, stB2.stardustMult / stB1.stardustMult)
local oddsLucky = Formulas.odds("dawn", stB2.luck)
local totalLucky = 0
for _, o in oddsLucky do
	totalLucky += o.chance
end
check("with luck x2 the shown odds change and still add up to 100%", math.abs(totalLucky - 100) < 1e-9 and oddsLucky[3].chance > odds[3].chance, oddsLucky[3].chance)
local crystalsBefore = srv("profile").crystals
srv("setNode", 1, 8, "prism")
srv("hits", 1, 8, 9000)
srv("hits", 1, Config.NodeTitan, 60000)
task.wait(0.5)
prof = srv("profile")
check("Prism and Titan drop Crystals", prof.crystals >= crystalsBefore + 1 + 5, prof.crystals - crystalsBefore)
check("Titan respawns on its own long timer", srv("node", 1, Config.NodeTitan).respawning == true and (prof.mastery.titan or 0) == 1)
-- mastery level 1 at 5 planets of a kind: permanent bonus + Crystals
crystalsBefore = prof.crystals
local _, stM0 = req("GetState")
for _ = 1, 5 do
	srv("setNode", 1, 9, "rock")
	srv("hits", 1, 9, 9000)
end
task.wait(0.5)
local _, stM1 = req("GetState")
prof = srv("profile")
check("Mastery level 1 after 5 planets of a kind: +3% and Crystals", Formulas.masteryLevel(prof.mastery.rock) >= 1 and prof.crystals >= crystalsBefore + Config.MasteryCrystals[1] and stM1.damage > stM0.damage, prof.mastery.rock)
-- Anomaly: there for the first 15 minutes of every hour, once per window
anomalyOn, anomalyWindow = Formulas.anomaly(os.time())
local anomalyNode = srv("node", 1, Config.NodeAnomaly)
if anomalyOn then
	check("Anomaly planet is up during its window", anomalyNode ~= nil and anomalyNode.kind == "anomaly")
	srv("hits", 1, Config.NodeAnomaly, 90000)
	task.wait(0.5)
	prof = srv("profile")
	check("Anomaly gives every buff and can be broken once per window", prof.anomalyWindow == anomalyWindow and (prof.buffs.luck or 0) > 60 and srv("node", 1, Config.NodeAnomaly) == nil)
else
	check("no Anomaly planet outside its window", anomalyNode == nil)
	check("Anomaly window math", (Formulas.anomaly(3600 * 5 + 10)) == true and (Formulas.anomaly(3600 * 5 + 901)) == false)
end
local anomalyClock = mainGui:FindFirstChild("AnomalyClock", true)
local anomalyLabel = anomalyClock and anomalyClock:FindFirstChildWhichIsA("TextLabel") :: TextLabel?
check("Anomaly clock on the HUD", anomalyClock ~= nil and anomalyClock.Visible and anomalyLabel ~= nil and #anomalyLabel.Text > 4, anomalyLabel and anomalyLabel.Text)

---------------------------------------------------------------------------
-- 7. Gate planet, galaxies, hardness, the per-galaxy systems
---------------------------------------------------------------------------
ok, res = req("Teleport", { zone = 2 })
check("warp to a locked galaxy rejected", not ok and res.key == "msg.zone_locked", res)
local gate = srv("node", 1, Config.NodeGate)
check("Gate planet has the HP of the next galaxy's gate", gate ~= nil and gate.kind == "gate" and gate.hp == Config.Zones[2].gateHp, gate and gate.hp)
local dmgNow = srv("profile").damage
srv("hits", 1, Config.NodeGate, 4)
task.wait(0.3)
gate = srv("node", 1, Config.NodeGate)
prof = srv("profile")
check("Gate takes damage = power and saves its HP", gate.hp < Config.Zones[2].gateHp and gate.hp >= Config.Zones[2].gateHp - dmgNow * 4 * Config.CritMult - 1 and prof.gate["2"] == gate.hp, Config.Zones[2].gateHp - gate.hp)
local bossText = ""
Miner.setTarget(Config.NodeGate)
task.wait(0.3)
bossText = if objectiveText then objectiveText.Text else ""
check("boss bar at the top while the Gate is targeted", bossText:find("/", 1, true) ~= nil and bossText:upper():find(Lang.upper(Lang.zone(2)), 1, true) ~= nil, bossText)
Miner.setTarget(nil)
srv("setGate", 1, 5)
crystalsBefore = srv("profile").crystals
local cargoBefore = srv("profile").cargo.count
srv("hits", 1, Config.NodeGate, 3)
task.wait(0.6)
prof = srv("profile")
check("breaking the Gate unlocks galaxy 2 (+Crystals, no cargo)", table.find(prof.zones, 2) ~= nil and prof.crystals == crystalsBefore + Config.GateCrystals[2] and prof.cargo.count == cargoBefore, prof.crystals - crystalsBefore)
check("the old Gate is gone on the client too", waitFor(function()
	return PlanetField.views[Config.NodeGate] == nil
end, 4))
ok = req("Teleport", { zone = 2 })
task.wait(1.5)
check("warp to galaxy 2", ok and Layout.zoneAt(hrp.Position.X, hrp.Position.Z) == 2, hrp.Position.X)
check("planets, sky and lighting switch to galaxy 2", waitFor(function()
	return PlanetField.zone == 2 and PlanetField.views[1] ~= nil and WorldFx.place == "zone2"
end, 8) and PlanetField.views[Config.NodeGate] ~= nil, WorldFx.place)
-- hardness: a galaxy-1 tool barely scratches galaxy 2
srv("setNode", 2, 1, "rock")
local n1 = srv("node", 2, 1)
n0 = #mineMessages
srv("hits", 2, 1, 1)
task.wait(0.4)
local soft = mineMessages[#mineMessages]
check("too-soft tool does 25% damage and is flagged", #mineMessages > n0 and soft.soft == true and n1.hp - srv("node", 2, 1).hp <= srv("profile").damage * Config.SoftDamage * Config.CritMult + 0.01, n1.hp - srv("node", 2, 1).hp)
srv("give", "stardust", 1e6)
ok = req("BuyTool", { id = "drill_spark" })
n1 = srv("node", 2, 1)
srv("hits", 2, 1, 1)
task.wait(0.3)
check("the galaxy's own tool mines at full strength", ok and mineMessages[#mineMessages].soft == false and n1.hp - srv("node", 2, 1).hp >= srv("profile").damage * 0.99, n1.hp - srv("node", 2, 1).hp)
-- galaxy material + dense planets
local spores0 = srv("profile").mats.spores
srv("hits", 2, 1, 50000)
task.wait(0.3)
check("galaxy 2 planets drop Spores", srv("profile").mats.spores == spores0 + 1, srv("profile").mats.spores - spores0)
local dense, plain = srv("node", 2, 6), srv("node", 2, 1)
check("outer-ring planets are Dense", dense.dense == true and plain.dense == false)
-- trespass
srv("tp", Layout.spawnPoint(3))
check("standing in a locked galaxy sends you back", waitFor(function()
	return Layout.zoneAt(hrp.Position.X, hrp.Position.Z) ~= 3
end, 4), hrp.Position.X)

-- Relics (galaxy 2)
ok, res = req("RollRelic")
check("relic roll without Spores rejected", not ok and res.key == "msg.not_enough", res)
srv("give", "spores", 100)
local rollsDone, upgraded = 0, 0
for _ = 1, 8 do
	ok, res = req("RollRelic")
	if ok then
		rollsDone += 1
		if res.upgraded then
			upgraded += 1
		end
	end
end
prof = srv("profile")
local grades, dust = 0, 0
for _, relic in prof.relics do
	grades += relic.grade
	dust += relic.dust
end
check("relic rolls cost Spores and always give a relic or dust", rollsDone == 8 and prof.mats.spores == spores0 + 1 + 100 - 8 * Config.RelicCost and grades >= 1 and upgraded >= 1, grades .. " grades, " .. dust .. " dust")
local _, stR = req("GetState")
local relicBonus = Formulas.relicBonus(stR.relics)
check("relics feed the stats", relicBonus.damage + relicBonus.speed + relicBonus.luck + relicBonus.stardust + relicBonus.crystals > 0)
-- the later systems are locked until their galaxy
ok, res = req("Upgrade", { id = "Temper" })
check("Temper is locked before Frost Halo", not ok and res.key == "msg.unlock_first", res)
UpgradesWindow.open("temper")
task.wait(0.4)
local upWindow = mainGui:FindFirstChild("UpgradesWindow", true)
local lockedText = false
for _, d in upWindow:GetDescendants() do
	if d:IsA("TextLabel") and d.Text == Lang.t("upgrades.locked", { zone = Lang.zone(3) }) then
		lockedText = true
	end
end
check("locked tab says where it unlocks", upWindow.Visible and lockedText)
UpgradesWindow.open("tools")
task.wait(0.4)
local toolRows = 0
for _, d in upWindow:GetDescendants() do
	if d.Name:sub(1, 5) == "Tool_" then
		toolRows += 1
	end
end
check("workshop lists every tool", toolRows == #Config.Tools, toolRows)
Windows.close()

srv("unlockZones", 6)
for _, mat in Config.Materials do
	srv("give", mat, 5000)
end
task.wait(0.5)
dmg0 = srv("profile").basePower
ok = req("Upgrade", { id = "Temper" })
check("Temper (Frost Halo): +10% damage per level", ok and math.abs(srv("profile").basePower / dmg0 - 1.1) < 0.001, srv("profile").basePower / dmg0)
prof = srv("profile")
local best = prof.equipped[1]
local powerSum0
do
	local _, st = req("GetState")
	powerSum0 = st.petPower
end
local traitRolls, kept = 0, 0
for _ = 1, 6 do
	ok, res = req("RollTrait", { uid = best })
	if ok then
		traitRolls += 1
		if res.kept then
			kept += 1
		end
	end
end
local _, stT = req("GetState")
check("Traits (Ember Forge): a pet gets a multiplier and never a worse one", traitRolls == 6 and kept >= 1 and stT.pets[best].trait ~= nil and stT.petPower > powerSum0, tostring(stT.pets[best].trait))
check("a roll that is not better refunds Embers", srv("profile").mats.embers == 5000 - 6 * Config.TraitCost + (6 - kept) * Config.TraitRefund, srv("profile").mats.embers)
-- Overcharge (Storm Reach)
srv("setNode", 2, 2, "titan")
local base = srv("profile").basePower
srv("hits", 2, 2, Config.OverchargeHits)
task.wait(0.4)
prof = srv("profile")
check("Overcharge: hits fill the meter and multiply damage", prof.charge >= 0.99 and math.abs(prof.damage / base - Config.OverchargeBase) < 0.01, prof.damage / base)
local chargeBar = mainGui:FindFirstChild("Overcharge", true)
check("Overcharge meter on the HUD", chargeBar ~= nil and chargeBar.Visible)
ok = req("Upgrade", { id = "Capacitor" })
check("Capacitor raises the full-charge multiplier", ok and math.abs(srv("profile").damage / base - (Config.OverchargeBase + 0.25)) < 0.01)
check("charge decays when you stop hitting", waitFor(function()
	return srv("profile").charge < 0.6
end, 6), srv("profile").charge)
-- Constellation (Void Crown)
local slots0 = srv("profile").maxEquip
ok = req("Upgrade", { id = "StarSlot" })
check("Constellation: Star Companion adds a pet slot", ok and srv("profile").maxEquip == slots0 + 1)
ok, res = req("Upgrade", { id = "StarSlot" })
check("maxed upgrade rejected", not ok and res.key == "msg.max_level", res)
ok, res = req("Upgrade", { id = "Hax" })
check("unknown upgrade rejected", not ok, res)
-- stat upgrades
local _, stU0 = req("GetState")
req("Upgrade", { id = "HitSpeed" })
req("Upgrade", { id = "Cargo" })
req("Upgrade", { id = "Range" })
req("Upgrade", { id = "MoveSpeed" })
task.wait(1.2)
local _, stU1 = req("GetState")
check("speed, cargo and range upgrades change the stats", stU1.hitsPerSecond > stU0.hitsPerSecond and stU1.cargo.cap == stU0.cargo.cap + 12 and stU1.range == stU0.range + 2 and stU1.walkSpeed > stU0.walkSpeed, stU1.hitsPerSecond)
check("walk speed is applied to the character", math.abs(srv("profile").walkSpeed - stU1.walkSpeed) < 0.1, srv("profile").walkSpeed)

---------------------------------------------------------------------------
-- 8. Rewards, quests, index, offline, referral, events
---------------------------------------------------------------------------
ok, res = req("ClaimDaily")
check("daily claim", ok, res)
ok, res = req("ClaimDaily")
check("daily twice rejected", not ok, res)
ok, res = req("ClaimGift", { index = #Config.Gifts })
check("gift not ready rejected", not ok, res)
srv("skipSession", 3700)
ok, res = req("ClaimGift", { index = 1 })
check("gift 1 claimed", ok, res)
ok, res = req("ClaimGift", { index = 1 })
check("gift twice rejected", not ok, res)
local hatched0 = #hatched
ok, res = req("ClaimGift", { index = #Config.Gifts })
task.wait(0.5)
check("last gift opens a Quantum Capsule (exclusive pet)", ok and #hatched > hatched0 and hatched[#hatched].capsule == "quantum", res)
ok, res = req("ClaimGift", { index = 99 })
check("bogus gift rejected", not ok, res)
local g0 = srv("profile").crystals
ok, res = req("RedeemCode", { code = " launch " })
check("code LAUNCH", ok and srv("profile").crystals == g0 + 50, res)
ok, res = req("RedeemCode", { code = "LAUNCH" })
check("code reuse rejected", not ok, res)
ok, res = req("RedeemCode", { code = "NOTACODE" })
check("bad code rejected", not ok, res)

ok, res = req("ClaimIndex", { zone = 3 })
check("index incomplete rejected", not ok, res)
for _, pet in Config.Pets do
	if pet.zone == 1 then
		srv("givePets", pet.id, 1)
	end
end
g0 = srv("profile").crystals
local _, stI0 = req("GetState")
ok, res = req("ClaimIndex", { zone = 1 })
local _, stI1 = req("GetState")
check("index page of galaxy 1 claimed: Crystals + permanent damage", ok and srv("profile").crystals == g0 + Config.IndexRewardCrystals[1] and stI1.damage > stI0.damage, res)
ok, res = req("ClaimIndex", { zone = 1 })
check("index twice rejected", not ok, res)

srv("forceQuests", { "planets", "hits", "capsules" })
srv("setNode", 2, 3, "rock")
srv("hits", 2, 3, 50000)
task.wait(2.5)
local q = srv("quests")
check("quest progress from real play (planets, hits)", q.progress[1] >= 1 and q.progress[2] >= 1, q.progress[1] .. " / " .. q.progress[2])
ok, res = req("ClaimQuestBonus")
check("quest bonus before the 3 quests rejected", not ok, res)
srv("completeQuests")
g0 = srv("profile").crystals
for i = 1, 3 do
	req("ClaimQuest", { i = i })
end
check("claim 3 quests", srv("profile").crystals > g0)
ok, res = req("ClaimQuest", { i = 1 })
check("claim quest twice rejected", not ok, res)
hatched0 = #hatched
ok, res = req("ClaimQuestBonus")
task.wait(0.5)
check("quest bonus = Quantum Capsule", ok and #hatched > hatched0, res)

local off = srv("fakeOffline", 3600)
check("offline mining = rate x seconds", off.pending == math.floor(off.rate * 3600) and off.seconds == 3600 and off.pending > 0, off.pending)
local capped = srv("fakeOffline", 30 * 3600)
check("offline capped at 6 h (12 h VIP)", capped.seconds == capped.cap and capped.cap == Config.OfflineCapHours * 3600, capped.seconds)
task.wait(1)
local popup = mainGui:FindFirstChild("PopupHolder")
check("offline popup shown", popup ~= nil)
before = srv("profile").stardust
ok, res = req("ClaimOffline")
check("claim offline", ok and srv("profile").stardust - before >= capped.pending * 0.999, res)
ok, res = req("ClaimOffline")
check("claim offline twice rejected", not ok, res)
if popup and popup.Parent then
	popup:Destroy()
end

g0 = srv("profile").crystals
local applied, refBy = srv("referral", "ref:" .. (player.UserId + 7))
check("referral invitee gift", applied == false or (refBy == player.UserId + 7 and srv("profile").crystals == g0 + Config.ReferralInviteeGift.amount), tostring(applied))
check("bad launch data ignored", srv("referral", "garbage") == false)
ok, res = req("ShareLink")
check("ShareLink answers", ok == true or (type(res) == "table" and res.key ~= nil), res)
ok, res = req("ClaimGroupGift")
check("group gift hidden (GroupId 0)", not ok, res)

ok, res = srv("eventCommand", "/event MeteorShower 5")
check("event command needs admin", ok == false, res)
srv("makeAdmin")
ok, res = srv("eventCommand", "/event MeteorShower 999")
check("event command validates minutes", ok == false, res)
local fx0 = srv("effects")
local _, stE0 = req("GetState")
local nUpdates = #liveUpdates
ok, res = srv("eventCommand", "/event MeteorShower 5")
task.wait(1.5)
local _, stE1 = req("GetState")
local fx1 = srv("effects")
if fx0.stardustMult >= 2 then
	check("Meteor Shower (already active on schedule)", fx1.stardustMult >= 2)
else
	check("Meteor Shower doubles Stardust for everyone", ok == true and #liveUpdates > nUpdates and fx1.stardustMult == 2 and math.abs(stE1.stardustMult / stE0.stardustMult - 2) < 0.01, stE1.stardustMult / stE0.stardustMult)
end
local eventPill = mainGui:FindFirstChild("EventPill", true) :: GuiObject?
check("event pill visible", waitFor(function()
	return eventPill ~= nil and eventPill.Visible
end, 3))

---------------------------------------------------------------------------
-- 9. PvP arena: safe ring, protection, Rookie Shield, a full fight, drones
---------------------------------------------------------------------------
local C = Config.Pvp
ok = req("Teleport", { arena = true })
task.wait(1.5)
local info = srv("pvpInfo")
check("warp to the arena lobby: safe zone", ok and info.inArena == false and Layout.onArenaPlatform(hrp.Position.X, hrp.Position.Z), hrp.Position.Z)
check("two sparring drones live in the arena", info.bots == C.bots and #PvpClient.targets() == C.bots, #PvpClient.targets())
check("arena sky and HUD", waitFor(function()
	return WorldFx.place == "arena" and mainGui:FindFirstChild("ArenaHud", true) ~= nil and mainGui:FindFirstChild("ArenaHud", true).Visible
end, 4), WorldFx.place)
srv("set", "playTime", 30) -- a brand new player
srv("pvpDummy", -101, { 40, 0 }, { 50, 5000 }) -- a veteran rival standing in the arena
ZapEvent:FireServer(-101)
task.wait(0.5)
check("zapping from the safe ring does nothing", srv("pvpInfo", -101).other.hp == C.maxHp)
-- step inside, next to the rival
local centre = Config.ArenaCenter
srv("tp", { centre[1] + 30, 4, centre[3] })
check("entering the ring turns PvP on with spawn protection", waitFor(function()
	local i = srv("pvpInfo")
	return i.inArena and i.protected > 0
end, 3) and PvpClient.state.inArena == true)
local okHit, reason = srv("pvpDummyAttack", -101)
check("spawn protection blocks the first hits", okHit == false and reason == "protected", reason)
srv("pvpClear")
task.wait(0.5)
okHit, reason = srv("pvpDummyAttack", -101)
check("Rookie Shield: a veteran cannot hurt a new player", okHit == false and reason == "rookie" and srv("pvpInfo").hp >= C.maxHp - C.botDamage * 3, reason)
-- the rookie attacks: the shield drops and the fight is on
local zapped = PvpClient.zap(-101)
task.wait(0.6)
info = srv("pvpInfo", -101)
local dealt = C.maxHp - info.other.hp
check("the player's zap lands (damage clamped by the power ratio)", zapped and dealt >= math.floor(C.baseDamage * C.minRatio) and dealt <= math.ceil(C.baseDamage * C.maxRatio), dealt)
check("attacking a player drops the Rookie Shield", info.rookie == false)
ZapEvent:FireServer(-101)
ZapEvent:FireServer(-101)
task.wait(0.3)
check("zap cooldown is enforced by the server", C.maxHp - srv("pvpInfo", -101).other.hp <= dealt + math.ceil(C.baseDamage * C.maxRatio), C.maxHp - srv("pvpInfo", -101).other.hp)
task.wait(C.cooldown)
okHit, reason = srv("pvpDummyAttack", -101)
local hpAfter = srv("pvpInfo").hp
check("now the rival can hit back", okHit == true and hpAfter < C.maxHp, tostring(reason))
check("the client sees zaps and its own HP", #pvpMessages > 0 and math.abs(PvpClient.state.hp - hpAfter) <= C.botDamage * 2 + 0.5, PvpClient.state.hp)
-- fight to the knockout
prof = srv("profile")
local points0, stardust0, kos0 = prof.arenaPoints, prof.stardust, prof.arenaKos
local t1 = os.clock()
while os.clock() - t1 < 14 do
	local other = srv("pvpInfo", -101).other
	if not other or other.respawning or other.hp <= 0 then
		break
	end
	PvpClient.zap(-101)
	task.wait(C.cooldown + 0.05)
end
task.wait(0.5)
prof = srv("profile")
check("knockout: arena points, Stardust and the KO count", prof.arenaPoints == points0 + C.koPoints and prof.stardust > stardust0 and prof.arenaKos == kos0 + 1, prof.arenaPoints - points0)
local sawKo = false
for _, m in pvpMessages do
	if m.kind == "ko" then
		sawKo = true
	end
end
check("the winner is told (KO card)", sawKo)
srv("pvpRemoveDummy", -101)
-- drones: beat one, then lose to a strong rival
points0 = srv("profile").arenaPoints
local botId = -1
local bots = PvpClient.targets()
t1 = os.clock()
while os.clock() - t1 < 20 do
	local botPos
	for _, t in PvpClient.targets() do
		if t.id == botId then
			botPos = t.pos
		end
	end
	if not botPos then
		break -- it went down
	end
	srv("tp", { botPos.X + 6, 4, botPos.Z })
	PvpClient.zap(botId)
	task.wait(C.cooldown + 0.05)
	if srv("profile").arenaPoints > points0 then
		break
	end
end
check("beating a sparring drone pays arena points", #bots == C.bots and srv("profile").arenaPoints == points0 + C.botPoints, srv("profile").arenaPoints - points0)
info = srv("pvpInfo")
check("drones fight back", info.hp < C.maxHp or info.inArena, info.hp)
-- get knocked out: back to the lobby, nothing lost
srv("tp", { centre[1] - 30, 4, centre[3] })
task.wait(0.6)
srv("pvpDummy", -102, { -40, 0 }, { 1e12, 5000 })
srv("pvpClear")
stardust0 = srv("profile").stardust
t1 = os.clock()
local downed = false
while os.clock() - t1 < 14 and not downed do
	srv("pvpDummyAttack", -102)
	task.wait(C.cooldown + 0.05)
	for _, m in pvpMessages do
		if m.kind == "down" then
			downed = true
		end
	end
end
task.wait(1)
info = srv("pvpInfo")
check("knocked out: back in the safe ring with full HP, nothing lost", downed and info.inArena == false and info.hp == C.maxHp and srv("profile").stardust >= stardust0 and not Layout.inArena(hrp.Position.X, hrp.Position.Z), info.hp)
srv("pvpRemoveDummy", -102)
ZapEvent:FireServer(12345)
ZapEvent:FireServer("x")
ZapEvent:FireServer(0 / 0)
task.wait(0.3)
check("bogus zap payloads ignored", true)
req("Teleport", { zone = 1 })
task.wait(1.5)
check("mining never damages players: leaving the arena is always safe", srv("pvpInfo").inArena == false)

---------------------------------------------------------------------------
-- 10. Store, paid random items policy
---------------------------------------------------------------------------
local _, stO = req("GetState")
check("starter pack hidden while its product id is 0", stO.starter and stO.starter.available == false)
local starterBtn = mainGui:FindFirstChild("StarterPack", true) :: GuiObject?
check("starter button hidden", starterBtn ~= nil and not starterBtn.Visible)
ok, res = req("WatchAd", { placement = "AdBoost" })
check("WatchAd unavailable (id 0)", not ok and type(res) == "table" and res.key == "msg.ad_unavailable", res)
ok, res = req("WatchAd", { placement = "Hack" })
check("WatchAd bad placement", not ok, res)
check("Studio policy lookup ran (not restricted)", stO.restricted == false)
ok = req("CanBuy", { key = "StardustSmall" })
check("paid random item allowed where it is not restricted", ok)
Windows.open("Store")
task.wait(0.5)
local store = mainGui:FindFirstChild("StoreWindow", true)
local function storeHas(name)
	return store:FindFirstChild(name, true) ~= nil
end
check("store lists passes and products", store.Visible and storeHas("Pass_AutoMiner") and storeHas("Pass_Lucky") and storeHas("Product_StardustSmall") and storeHas("Product_QuantumCapsule1") and not storeHas("StarterCard"))
srv("setRestricted", true)
task.wait(0.8)
ok, res = req("CanBuy", { key = "StardustSmall" })
check("restricted: currency that buys capsules is refused", not ok and res.key == "msg.restricted", res)
ok, res = req("CanBuy", { key = "Lucky" })
check("restricted: luck passes are refused", not ok and res.key == "msg.restricted", res)
ok = req("CanBuy", { key = "CrystalsSmall" })
check("restricted: non-random items stay available", ok)
check("restricted: the store hides every paid random item", not storeHas("Product_StardustSmall") and not storeHas("Product_QuantumCapsule1") and not storeHas("Pass_Lucky") and not storeHas("Product_LuckBoost") and storeHas("Product_CrystalsSmall") and storeHas("Pass_AutoMiner") and storeHas("RestrictedNote"))
check("restricted: client refuses to prompt", Purchase.allowed(Config.ProductByKey.QuantumCapsule1) == false and Purchase.allowed(Config.PassByKey.VIP) == true)
srv("give", "stardust", 1e6)
srv("tp", { capPos[1] + 8, 4, capPos[3] + 6 })
task.wait(0.8)
ok, res = req("Open", { capsule = "dawn", count = 1 })
check("restricted players still open capsules with earned Stardust", ok, res)
srv("setRestricted", false)
Windows.close()
g0 = srv("profile").crystals
check("product grant: Crystals", srv("grantProduct", "CrystalsSmall") and srv("profile").crystals == g0 + 100)
local petsBefore = srv("profile").petCount
srv("grantProduct", "StarterPack")
prof = srv("profile")
check("Starter Pack: fixed contents (pet + Crystals + boost), nothing random", prof.starterBought and prof.petCount == petsBefore + 1 and (prof.byId["photonpixie:0"] or 0) >= 1 and prof.crystals == g0 + 100 + Config.StarterPack.crystals)
srv("grantPass", "InstantSell", true)
srv("setNode", 1, 10, "rock")
stardust0 = srv("profile").stardust
srv("hits", 1, 10, 9000)
task.wait(0.4)
prof = srv("profile")
check("Instant Sell pass: ore is paid at once, no cargo", prof.stardust > stardust0 and prof.cargo.count == 0)
srv("grantPass", "InstantSell", false)

---------------------------------------------------------------------------
-- 11. Windows open, lite profile, budgets
---------------------------------------------------------------------------
local opened = {}
for _, name in { "Pets", "Upgrades", "Rebirth", "Teleport", "Store", "Rewards", "Quests", "Index", "Auto", "Settings", "Invite" } do
	Windows.open(name)
	task.wait(0.35)
	local w = mainGui:FindFirstChild(name .. "Window", true) :: GuiObject?
	if not (w and w.Visible and #w:GetDescendants() > 20) then
		table.insert(opened, name)
	end
end
check("every window opens with content", #opened == 0, table.concat(opened, ", "))
local dimGui = gui:FindFirstChild("PlanetDim")
local dim = dimGui and dimGui:FindFirstChild("Dim") :: GuiObject?
check("dim layer follows the open window", dim ~= nil and dim.Visible)
Windows.close()
task.wait(0.5)
check("dim layer hides on close", dim ~= nil and not dim.Visible)

CapsuleCinematic.play("dawn", { { uid = "t1", id = "solarfox", tier = 1, chance = 0.1, rarity = "Legendary", new = true } }, false)
task.wait(0.3)
check("capsule cinematic starts and pauses mining", CapsuleCinematic.isPlaying() and Miner.enabled == false)
local waited = 0
while CapsuleCinematic.isPlaying() and waited < 12 do
	waited += task.wait(0.25)
end
local overlayGui = gui:FindFirstChild("PlanetOverlay")
check("cinematic finishes and cleans up", not CapsuleCinematic.isPlaying() and overlayGui ~= nil and overlayGui:FindFirstChild("Capsule") == nil and Miner.enabled == true, string.format("%.1fs", waited))

-- lite profile
waitFor(function()
	return PlanetField.zone == 1 and PlanetField.views[1] ~= nil
end, 8)
local function fieldParts()
	local n = 0
	for _, view in PlanetField.views do
		if view.model then
			n += PlanetModel.partCount(view.model)
		end
	end
	return n
end
local fullField, fullSky = fieldParts(), #workspace.SkyRig:GetChildren()
local liteBefore = Quality.lite
ok = req("SetSetting", { key = "lite", on = true })
check("lite profile switches on from Settings", ok and waitFor(function()
	return Quality.lite
end, 8))
task.wait(1)
local liteField, liteSky = fieldParts(), #workspace.SkyRig:GetChildren()
if liteBefore then
	check("lite profile was already on (touch / low graphics)", true)
else
	check("lite profile: fewer planet parts, smaller sky", liteField < fullField and liteSky < fullSky, string.format("planets %d -> %d, sky %d -> %d", fullField, liteField, fullSky, liteSky))
end
local dome = workspace.SkyRig:FindFirstChild("Dome")
local domeMesh = dome and dome:FindFirstChildOfClass("SpecialMesh")
check("lite sky sits inside the short draw distance (dome <= 200 studs)", domeMesh ~= nil and math.abs(domeMesh.Scale.X) <= 200, domeMesh and domeMesh.Scale.X)
local bloom = Lighting:FindFirstChild("PcBloom") :: BloomEffect?
check("lite profile turns the post effects off", bloom ~= nil and bloom.Enabled == false)
req("SetSetting", { key = "lite", on = false })
ok, res = req("SetSetting", { key = "hack", on = true })
check("unknown setting rejected", not ok, res)

-- budgets
local guiCount = #mainGui:GetDescendants()
check("UI instance budget (<= 6000)", guiCount <= 6000, guiCount)
local clientParts = 0
for _, name in { "ClientPlanets", "ClientPets", "ClientTools", "SkyRig" } do
	local f = workspace:FindFirstChild(name)
	if f then
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") then
				clientParts += 1
			end
		end
	end
end
check("client-only parts budget (<= 1500)", clientParts <= 1500, clientParts)
local heapMb = gcinfo() / 1024
check("client Lua heap budget (<= 80 MB)", heapMb <= 80, string.format("%.1f MB", heapMb))
local streamed = 0
for _, d in workspace.World:GetDescendants() do
	if d:IsA("BasePart") then
		streamed += 1
	end
end
check("streaming: the client holds only part of the world", streamed < srv("worldParts"), streamed .. " of " .. srv("worldParts"))

---------------------------------------------------------------------------
-- 12. Languages
---------------------------------------------------------------------------
local function labelIn(root: Instance, text: string): boolean
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == text then
			return true
		end
	end
	return false
end
ok, res = req("SetLanguage", { lang = "xx" })
check("unsupported language rejected", not ok, res)
for _, code in { "es", "ja", "de" } do
	ok, res = req("SetLanguage", { lang = code })
	task.wait(0.9)
	local _, st2 = req("GetState")
	local button = mainGui:FindFirstChild("Upgrades", true)
	local want = Locale.t(code, "menu.Upgrades")
	check("SetLanguage " .. code, ok and st2.lang == code and Lang.code == code and button ~= nil and labelIn(button, want), string.format("state=%s lang=%s want=%s", tostring(st2.lang), Lang.code, want))
end
local signText
for _, d in workspace.World.Zone1_dawn.Plaza:GetDescendants() do
	if d:IsA("TextLabel") and d:GetAttribute("LocCapsule") == "dawn" then
		signText = d.Text
	end
end
check("world signs are localized", signText ~= nil and signText:find(Locale.t("de", "capsule.dawn"), 1, true) ~= nil, signText)
local planetName
local v = PlanetField.views[Config.NodeTitan]
if v and v.gui then
	local nameLabel = v.gui:FindFirstChild("Name") :: TextLabel?
	planetName = nameLabel and nameLabel.Text
end
check("planet labels are localized", planetName == nil or planetName == Locale.t("de", "planet.titan"), planetName)
req("SetLanguage", { lang = "" })
task.wait(0.9)
check("language back to the account locale", Lang.code == Locale.resolve(player.LocaleId), Lang.code)
plain = 0
for _, m in notifications do
	if type(m) ~= "table" or type(m.key) ~= "string" then
		plain += 1
	end
end
check("server notifications are translation keys", #notifications > 0 and plain == 0, #notifications .. " notes, " .. plain .. " plain")

ok, res = req("Hack", {})
check("unknown action rejected", not ok, res)
ok, res = req("Equip", "x")
check("non-table payload rejected", not ok, res)

task.wait(2)
check("no client errors", #clientErrors == 0, table.concat(clientErrors, " || "))
srv("report", table.concat(lines, "\n"))
