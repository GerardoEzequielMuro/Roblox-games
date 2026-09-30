-- Client side of the gameplay test: exercises the core loop through the real remotes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")

local player = Players.LocalPlayer
local clientErrors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(clientErrors, msg)
	end
end)

local lines = {}
local PERF: { [string]: any } = {}
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
local TapEvent = Remotes:WaitForChild("Tap") :: RemoteEvent
local T = ReplicatedStorage:WaitForChild("__Test", 60) :: RemoteFunction
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Lang = require(player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Lang"))

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
local function srv(cmd, a, b)
	return T:InvokeServer(cmd, a, b)
end

local notifications = {}
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(message)
	table.insert(notifications, message)
end)
local asks = 0
Remotes:WaitForChild("AskNotifications").OnClientEvent:Connect(function()
	asks += 1
end)
local questPushes = 0
Remotes:WaitForChild("Quests").OnClientEvent:Connect(function()
	questPushes += 1
end)
local liveUpdates = {}
Remotes:WaitForChild("LiveEventUpdate").OnClientEvent:Connect(function(d)
	table.insert(liveUpdates, d)
end)
local hatchedEvents = {}
Remotes:WaitForChild("Hatched").OnClientEvent:Connect(function(data)
	table.insert(hatchedEvents, data)
end)

-- wait for the session
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
check("state: 1 pet, 1 equipped, 3 slots", #state.equipped == 1 and state.maxEquip == Config.BaseEquipSlots)

local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
task.wait(1)

-- UI built
local gui = player:WaitForChild("PlayerGui")
local mainGui = gui:WaitForChild("TapPetsUI", 10) :: ScreenGui
check("main UI built", mainGui ~= nil and #mainGui:GetDescendants() > 50)
check("main UI uses CoreUISafeInsets", mainGui and mainGui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)

---------------------------------------------------------------------------
-- Tapping: burst of 100 in one event is clamped to the bucket (12/s + 6 burst)
---------------------------------------------------------------------------
local prof = srv("profile")
local tv = prof.tapValue
local before = prof.taps
local tStart = os.clock()
TapEvent:FireServer(100)
task.wait(0.6)
prof = srv("profile")
local accepted = (prof.taps - before) / tv
check("tap burst accepted but clamped", accepted >= 1 and accepted <= Config.MaxTapsPerSecond + Config.TapBurst + 0.5, accepted)
-- sustained: 5 taps every 0.05 s for 2 s = 200 taps sent
before = prof.taps
tStart = os.clock()
for _ = 1, 40 do
	TapEvent:FireServer(5)
	task.wait(0.05)
end
task.wait(0.3)
prof = srv("profile")
local elapsed = os.clock() - tStart
accepted = (prof.taps - before) / tv
local maxAllowed = Config.MaxTapsPerSecond * (elapsed + 0.7) + 1
check("sustained taps capped at 12/s", accepted > 0 and accepted <= maxAllowed, string.format("%d accepted in %.2fs (max %d)", accepted, elapsed, maxAllowed))
TapEvent:FireServer(-5)
TapEvent:FireServer(0 / 0)
TapEvent:FireServer("lots")
task.wait(0.3)
check("bogus tap payloads ignored", srv("profile").taps >= prof.taps)

-- tap filter (touch on UI buttons / thumbstick / jump zones must not count)
local Tapper = require(player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Tapper"))
local petsButton = mainGui:FindFirstChild("Pets", true) :: GuiObject?
if petsButton and Tapper.isBlocked then
	local c = petsButton.AbsolutePosition + petsButton.AbsoluteSize / 2
	check("tap on a UI button is blocked", Tapper.isBlocked(c, false) == true)
	local vp = workspace.CurrentCamera.ViewportSize - game:GetService("GuiService"):GetGuiInset()
	check("tap on open world counts", Tapper.isBlocked(Vector2.new(vp.X * 0.5, vp.Y * 0.42), false) == false)
	check("touch in thumbstick zone blocked", Tapper.isBlocked(Vector2.new(vp.X * 0.12, vp.Y * 0.85), true) == true)
	check("touch in jump zone blocked", Tapper.isBlocked(Vector2.new(vp.X * 0.9, vp.Y * 0.85), true) == true)
else
	check("Tapper.isBlocked exists", false)
end

---------------------------------------------------------------------------
-- HUD layout (dock, objective) and the guide that drives the objective
---------------------------------------------------------------------------
do
	local Guide = require(player.PlayerScripts.Client.Guide)
	local RootH = require(player.PlayerScripts.Client.UI.Root)
	local price = Config.Eggs[1].price
	local g = Guide.current({ taps = 0, totalHatched = 0, zones = { 1 }, rebirths = 0 })
	check("guide: first earn Taps for an egg", g.key == "goal.earn" and g.progress == 0 and g.target == nil, g.key)
	g = Guide.current({ taps = price, totalHatched = 0, zones = { 1 }, rebirths = 0 })
	check("guide: then hatch it (beam to the first egg)", g.key == "goal.hatch1" and g.target ~= nil and g.target.Z == Config.Eggs[1].offsetZ, g.key)
	g = Guide.current({ taps = 0, totalHatched = 2, zones = { 1 }, rebirths = 0 })
	check("guide: then a few more eggs", g.key == "goal.hatchN" and math.abs(g.progress - 0.4) < 1e-6, g.progress)
	g = Guide.current({ taps = Config.Zones[2].cost / 2, totalHatched = 9, zones = { 1 }, rebirths = 0 })
	check("guide: then the next zone, with progress", g.key == "goal.zone" and g.zoneArg == 2 and math.abs(g.progress - 0.5) < 1e-6 and g.window == "Teleport", g.key)
	g = Guide.current({ taps = Config.Zones[2].cost, totalHatched = 9, zones = { 1 }, rebirths = 0 })
	check("guide: gate affordable -> beam to the gate", g.key == "goal.gate" and g.target ~= nil and g.target.Z == Config.ZoneLength / 2, g.key)
	g = Guide.current({ taps = 100, totalHatched = 9, zones = { 1, 2, 3 }, rebirths = 0 })
	check("guide: rebirth when it is cheaper than the next gate", g.key == "goal.rebirth" and g.window == "Rebirth", g.key)
	g = Guide.current({ taps = Config.RebirthBaseCost, totalHatched = 9, zones = { 1, 2, 3, 4, 5 }, rebirths = 0 })
	check("guide: rebirth ready", g.key == "goal.rebirth_ready" and g.progress == 1, g.key)

	task.wait(1.2)
	local objective = mainGui:FindFirstChild("Objective", true)
	local objText = objective and objective:FindFirstChild("Text") :: TextLabel?
	check("objective line shown at the top", objText ~= nil and #objText.Text > 3 and objective.AbsolutePosition.Y < 80, objText and objText.Text)
	local dockBad = {}
	for _, spec in { { "Rewards", 80 }, { "TapButton", 92 }, { "Pets", 80 } } do
		local b = mainGui:FindFirstChild(spec[1], true)
		if not b or not b:IsA("GuiButton") then
			table.insert(dockBad, spec[1] .. " missing")
		elseif b.AbsoluteSize.Y < spec[2] * RootH.scale then
			table.insert(dockBad, spec[1] .. " too small")
		elseif b.AbsolutePosition.Y < workspace.CurrentCamera.ViewportSize.Y * 0.5 then
			table.insert(dockBad, spec[1] .. " not at the bottom")
		end
	end
	check("dock: Rewards, TAP and Pets at the bottom centre", #dockBad == 0, table.concat(dockBad, ", "))
	local tapBtn = mainGui:FindFirstChild("TapButton", true) :: GuiObject?
	local TapperH = require(player.PlayerScripts.Client.Tapper)
	check("the TAP button never double counts (world taps are blocked on it)", tapBtn ~= nil and TapperH.isBlocked(tapBtn.AbsolutePosition + tapBtn.AbsoluteSize / 2, false) == true)
	local perTap = mainGui:FindFirstChild("PerTap", true) :: TextLabel?
	check("per-tap value under the TAP button", perTap ~= nil and perTap.Text:sub(1, 1) == "+", perTap and perTap.Text)
	local petsCount = mainGui:FindFirstChild("Count", true)
	local countText = petsCount and petsCount:FindFirstChildOfClass("TextLabel")
	check("pets badge shows how many you own", countText ~= nil and countText.Text == "1", countText and countText.Text)
end

---------------------------------------------------------------------------
-- Auto systems (no passes yet): free idle auto tap, toggles, pace
---------------------------------------------------------------------------
do
	local _, st0 = req("GetState")
	check("auto state in snapshot", st0.auto ~= nil and st0.auto.tap == true and st0.auto.equip == false and st0.auto.rebirth == false and st0.auto.tapRate == Config.AutoTapFreeRate, st0.auto and st0.auto.tapRate)
	local tvA = srv("profile").tapValue
	task.wait(Config.AutoTapIdleSeconds + 0.6) -- go idle
	local a0 = srv("profile").taps
	task.wait(4)
	local gained = (srv("profile").taps - a0) / tvA
	check("free auto tap pays ~1 tap/s while idle", gained >= 3 and gained <= 5.2, gained)
	-- manual tapping: the free auto tap steps aside (no stacking for active players)
	local m0 = srv("profile").taps
	for _ = 1, 10 do
		TapEvent:FireServer(1)
		task.wait(0.2)
	end
	task.wait(0.4)
	gained = (srv("profile").taps - m0) / tvA
	check("no free auto taps while tapping", gained >= 9 and gained <= 10.6, gained)
	ok, res = req("SetAuto", { key = "tap", on = false })
	check("auto tap off", ok and srv("settings").autoTap == false, res)
	task.wait(Config.AutoTapIdleSeconds + 0.6)
	local o0 = srv("profile").taps
	task.wait(2)
	check("auto tap off pays nothing", srv("profile").taps == o0, srv("profile").taps - o0)
	ok = req("SetAuto", { key = "tap", on = true })
	check("auto tap back on", ok and srv("settings").autoTap == true)
	ok, res = req("SetAuto", { key = "hax", on = true })
	check("unknown auto key rejected", not ok, res)
	ok, res = req("SetAuto", { key = "rebirth", on = true })
	check("auto rebirth locked before the first rebirth", not ok and type(res) == "table" and res.key == "msg.autorebirth_locked", res)
	-- 56 design px tall: 45+ px at the 920x505 phone viewport (scale ~0.82)
	local RootT = require(player.PlayerScripts.Client.UI.Root)
	local chipNames = { "AutoTap", "AutoHatch", "AutoEquip", "AutoRebirth" }
	local chipsBad = {}
	-- progressive HUD: a chip is only on screen once HudUnlock opens it (Auto Rebirth after
	-- the first rebirth); the ones on screen must be full size
	local HudUnlockT = require(ReplicatedStorage.Shared.HudUnlock)
	local _, stU = req("GetState")
	local shouldShow = HudUnlockT.visible(stU)
	task.wait(0.6)
	for _, name in chipNames do
		local chip = mainGui:FindFirstChild(name, true)
		if not chip or not chip:IsA("GuiButton") then
			table.insert(chipsBad, name .. " missing")
		elseif shouldShow[name] and not chip.Visible then
			table.insert(chipsBad, name .. " should be unlocked")
		elseif name == "AutoRebirth" and (stU.rebirths or 0) == 0 and chip.Visible then
			table.insert(chipsBad, "AutoRebirth shown before the first rebirth")
		elseif chip.Visible and (chip.AbsoluteSize.Y < 54 * RootT.scale or chip.AbsoluteSize.X < 90 * RootT.scale) then
			table.insert(chipsBad, string.format("%s %dx%d at scale %.2f", name, chip.AbsoluteSize.X, chip.AbsoluteSize.Y, RootT.scale))
		end
	end
	check("HUD auto chips: unlocked ones at full cell size", #chipsBad == 0, table.concat(chipsBad, ", "))
	task.wait(0.6)
	local tapChip = mainGui:FindFirstChild("AutoTap", true)
	local stateLabel = tapChip and tapChip:FindFirstChild("State") :: TextLabel?
	check("auto tap chip shows ON and the rate", stateLabel ~= nil and stateLabel.Text:find(Lang.t("hud.on"), 1, true) ~= nil and stateLabel.Text:find("/s", 1, true) ~= nil, stateLabel and stateLabel.Text)
end

---------------------------------------------------------------------------
-- Hatching
---------------------------------------------------------------------------
srv("giveTaps", 1e6)
local ok, res = req("Hatch", { egg = "basic", count = 1 })
check("hatch from spawn (too far) rejected", not ok and type(res) == "table" and res.key == "msg.get_closer", res)
local basicPos = Vector3.new(-30, 4, 30)
char:PivotTo(CFrame.lookAt(basicPos + Vector3.new(0, 0, -10), basicPos))
task.wait(1)
prof = srv("profile")
local count0 = prof.petCount
local _, stBeforeHatch = req("GetState")
ok, res = req("Hatch", { egg = "basic", count = 1 })
check("hatch x1 near egg", ok and type(res) == "table" and #res == 1, res)
if ok and type(res) == "table" and res[1] then
	-- NEW! badge flag: true only the first time this player sees the pet
	local wasKnown = stBeforeHatch.discovered[res[1].id] == true
	check("hatch result carries the new flag", res[1].new == not wasKnown, tostring(res[1].id) .. " new=" .. tostring(res[1].new))
end
prof = srv("profile")
check("pet added to inventory", prof.petCount == count0 + 1, prof.petCount)
check("taps spent", prof.taps < 1e6, prof.taps)
ok, res = req("Hatch", { egg = "basic", count = 1 })
check("hatch during cooldown rejected", not ok and res == "cooldown", res)
task.wait(2.5)
ok, res = req("Hatch", { egg = "basic", count = 3 })
check("hatch x3 without pass rejected", not ok, res)
ok, res = req("Hatch", { egg = "basic", count = 8 })
check("hatch x8 without pass rejected", not ok, res)
ok, res = req("Hatch", { egg = "basic", count = 5 })
check("hatch with a made-up size rejected", not ok, res)
ok, res = req("Hatch", { egg = "spotted", count = 1 })
check("hatch other egg from far rejected", not ok, res)
ok, res = req("Hatch", { egg = "candy", count = 1 })
check("hatch in locked zone rejected", not ok, res)
ok, res = req("Hatch", { egg = "magic", count = 1 })
check("hatch robux egg with taps rejected", not ok, res)

-- free Auto Hatch (no pass): x1 at the slow pace, on the server's clock
task.wait(2.5)
ok, res = req("SetAutoHatch", { egg = "basic" })
check("free auto hatch on (no pass)", ok, res)
local fh0 = srv("profile").totalHatched
task.wait(10)
req("SetAutoHatch", {})
local freeHatches = srv("profile").totalHatched - fh0
check("free auto hatch keeps the slow pace (x1 every 4.5 s)", freeHatches >= 1 and freeHatches <= 3, freeHatches)
task.wait(2.6)

srv("grantPasses")
task.wait(0.5)
prof = srv("profile")
count0 = prof.petCount
ok, res = req("Hatch", { egg = "basic", count = 3 })
check("hatch x3 with pass", ok and type(res) == "table" and #res == 3, res)
check("3 pets added", srv("profile").petCount == count0 + 3)
task.wait(2.5)
count0 = srv("profile").petCount
ok, res = req("Hatch", { egg = "basic", count = 8 })
check("hatch x8 with pass", ok and type(res) == "table" and #res == 8, res)
check("8 pets added", srv("profile").petCount == count0 + 8)
task.wait(2.5)
ok, res = req("SetAutoHatch", { egg = "basic" })
check("auto hatch on", ok, res)
local h0 = srv("profile").totalHatched
task.wait(5.5)
req("SetAutoHatch", {})
local h1 = srv("profile").totalHatched
check("auto hatch hatched", h1 > h0, h1 - h0)
local autoEvent = false
for _, e in hatchedEvents do
	if e.auto then
		autoEvent = true
	end
end
check("auto hatch sent Hatched event", autoEvent)
task.wait(3)
check("auto hatch off stops", srv("profile").totalHatched == h1)

---------------------------------------------------------------------------
-- Inventory: craft, lock, delete, equip, equip best
---------------------------------------------------------------------------
local foxes = srv("givePets", "fox", 5)
prof = srv("profile")
local fox0 = prof.byId["fox:0"] or 0
ok, res = req("Craft", { uid = foxes[1] })
prof = srv("profile")
check("craft golden from 5", ok and (prof.byId["fox:1"] or 0) == 1 and (prof.byId["fox:0"] or 0) == fox0 - 5, res)
ok, res = req("Craft", { uid = type(res) == "string" and res or "" })
check("craft with 1 golden rejected", not ok, res)

local chick = srv("givePets", "chick", 1)[1]
check("lock", (req("Lock", { uid = chick, locked = true })))
ok, res = req("Delete", { uids = { chick } })
check("delete locked rejected", not ok, res)
req("Lock", { uid = chick, locked = false })
local c0 = srv("profile").petCount
ok, res = req("Delete", { uids = { chick } })
check("delete unlocked", ok and srv("profile").petCount == c0 - 1, res)

ok = req("EquipBest")
prof = srv("profile")
check("equip best fills slots", ok and #prof.equipped == math.min(prof.maxEquip, prof.petCount), #prof.equipped .. "/" .. prof.maxEquip)
local goldFox
local _, st = req("GetState")
for uid, pet in st.pets do
	if pet.id == "fox" and pet.tier == 1 then
		goldFox = uid
	end
end
check("equip best picks golden fox", goldFox ~= nil and table.find(prof.equipped, goldFox) ~= nil)
local someUid = prof.equipped[#prof.equipped]
req("Unequip", { uid = someUid })
check("unequip", table.find(srv("profile").equipped, someUid) == nil)
check("equip", (req("Equip", { uid = someUid })) and table.find(srv("profile").equipped, someUid) ~= nil)
local spare
for uid in st.pets do
	if not table.find(prof.equipped, uid) then
		spare = uid
	end
end
ok, res = req("Equip", { uid = spare })
check("equip when slots full rejected", not ok, res)
ok, res = req("Equip", { uid = "nope" })
check("equip unknown pet rejected", not ok, res)

-- pets render following the player
task.wait(3)
prof = srv("profile")
local petFolder = workspace:FindFirstChild("ClientPets")
local near, total = 0, 0
if petFolder then
	for _, m in petFolder:GetChildren() do
		if m:IsA("Model") then
			total += 1
			if (m:GetPivot().Position - hrp.Position).Magnitude < 16 then
				near += 1
			end
		end
	end
end
check("equipped pets rendered near player", total == #prof.equipped and near == total, string.format("%d models, %d near, %d equipped", total, near, #prof.equipped))
char:PivotTo(CFrame.new(20, 4, -40))
task.wait(1.5)
near = 0
if petFolder then
	for _, m in petFolder:GetChildren() do
		if m:IsA("Model") and (m:GetPivot().Position - hrp.Position).Magnitude < 16 then
			near += 1
		end
	end
end
check("pets follow after moving", near == total, near)

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
ok, res = req("BuyZone", { zone = 3 })
check("buy zone 3 before 2 rejected", not ok, res)
ok, res = req("Teleport", { zone = 2 })
check("teleport to locked zone rejected", not ok, res)
srv("setTaps", 10)
ok, res = req("BuyZone", { zone = 2 })
check("buy zone without taps rejected", not ok, res)
srv("setTaps", Config.Zones[2].cost + 5)
ok, res = req("BuyZone", { zone = 2 })
prof = srv("profile")
check("buy zone 2", ok and table.find(prof.zones, 2) ~= nil and prof.taps < 1000, res)
task.wait(0.8)
-- gates stream in as whole models
local gate2 = workspace.World.Gates:WaitForChild("Gate2", 15):WaitForChild("Barrier", 5) :: BasePart
local gate3 = workspace.World.Gates:WaitForChild("Gate3", 15):WaitForChild("Barrier", 5) :: BasePart
check("gate 2 opens locally, gate 3 stays shut", gate2.CanCollide == false and gate3.CanCollide == true)
ok = req("Teleport", { zone = 2 })
task.wait(1)
local z = hrp.Position.Z
check("teleport to zone 2", ok and z > Config.ZoneLength / 2 and z < Config.ZoneLength * 1.5, z)
char:PivotTo(CFrame.new(0, 4, Config.ZoneLength * 2))
task.wait(2.5)
z = hrp.Position.Z
check("trespass into zone 3 sent back", z < Config.ZoneLength * 1.5, z)
-- hatch in zone 2 now that it's owned
srv("giveTaps", 1e6)
local candyPos = Vector3.new(-30, 4, Config.ZoneLength + 20)
char:PivotTo(CFrame.lookAt(candyPos + Vector3.new(0, 0, -10), candyPos))
task.wait(1)
ok, res = req("Hatch", { egg = "candy", count = 1 })
check("hatch candy egg in zone 2", ok, res)
-- zone look: Candy Land has its own clock, clouds and weather
task.wait(1.5)
local lighting = game:GetService("Lighting")
check("zone 2 look applied (clock)", math.abs(lighting.ClockTime - 16.4) < 0.2, lighting.ClockTime)
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
check("clouds exist and are tinted for the zone", clouds ~= nil and clouds.Cover > 0.6, clouds and clouds.Cover)
local weatherNear = workspace:FindFirstChild("WeatherNear")
local weatherSky = workspace:FindFirstChild("WeatherSky")
local weatherOn = 0
for _, box in { weatherNear, weatherSky } do
	for _, e in box:GetChildren() do
		if e:IsA("ParticleEmitter") and e.Enabled then
			weatherOn += 1
		end
	end
end
check("exactly one weather emitter on in zone 2", weatherNear ~= nil and weatherSky ~= nil and weatherOn == 1, weatherOn)

-- paid random item rules: the egg panel shows every outcome in %, adding up to 100
do
	local EggPanelT = require(player.PlayerScripts.Client.UI.EggPanel)
	EggPanelT.open("candy", candyPos)
	task.wait(0.4)
	local panelGui = mainGui:FindFirstChild("EggPanel", true)
	local units, cells, badText = 0, 0, {}
	if panelGui then
		for _, d in panelGui:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "Chance" then
				cells += 1
				units += (d:GetAttribute("Units") :: number?) or 0
				if not d.Text:match("^%d+%.?%d*%%$") or d.Text == "0%" then
					table.insert(badText, d.Text)
				end
			end
		end
	end
	local candyEgg = require(ReplicatedStorage.Shared.Formulas).EggById.candy
	check("egg panel odds: numeric %, every outcome, sum = 100", cells == #candyEgg.entries and units == 1000000 and #badText == 0, string.format("%d cells, %d units, bad: %s", cells, units, table.concat(badText, ",")))
	local goldenShown = false
	if panelGui then
		for _, d in panelGui:GetDescendants() do
			if d:IsA("TextLabel") and d.Text:find("⭐", 1, true) and d.Text:find("%%") then
				goldenShown = true
			end
		end
	end
	check("egg panel shows the golden chance", goldenShown)
	EggPanelT.close()
end

---------------------------------------------------------------------------
-- Rebirth, upgrades, daily, gifts, codes, index
---------------------------------------------------------------------------
srv("setTaps", 1000)
ok, res = req("Rebirth")
check("rebirth without taps rejected", not ok, res)
srv("setTaps", Config.RebirthBaseCost + 10)
local g0 = srv("profile").gems
ok, res = req("Rebirth")
prof = srv("profile")
check("rebirth", ok and prof.rebirths == 1 and prof.taps < 1e5 and prof.gems == g0 + Config.RebirthGemsBase, res)

-- Auto Rebirth (unlocked by the manual rebirth above) and Auto Equip
ok, res = req("SetAuto", { key = "rebirth", on = true })
check("auto rebirth on after the first rebirth", ok and srv("settings").autoRebirth == true, res)
srv("setTaps", Config.RebirthBaseCost * Config.RebirthCostGrowth + 10)
task.wait(2.4)
prof = srv("profile")
check("auto rebirth fires on the server", prof.rebirths == 2 and prof.taps < Config.RebirthBaseCost, prof.rebirths)
req("SetAuto", { key = "rebirth", on = false })
srv("setTaps", Config.RebirthBaseCost * Config.RebirthCostGrowth ^ 2 + 10)
task.wait(2.2)
check("auto rebirth off does nothing", srv("profile").rebirths == 2)
srv("setTaps", 1000)
do
	local eq0 = srv("profile").equipped
	req("Unequip", { uid = eq0[1] })
	ok, res = req("SetAuto", { key = "equip", on = true })
	prof = srv("profile")
	check("auto equip on refills the slots with the best", ok and #prof.equipped == prof.maxEquip, #prof.equipped .. "/" .. prof.maxEquip)
	local unis = srv("givePets", "unicorn", 5)
	ok, res = req("Craft", { uid = unis[1] })
	prof = srv("profile")
	check("auto equip picks up a fresh craft", ok and type(res) == "string" and table.find(prof.equipped, res) ~= nil, res)
	req("SetAuto", { key = "equip", on = false })
	local rt = srv("roundtrip")
	check("auto settings survive save + load", rt.settings.autoTap == true and rt.settings.autoEquip == false and rt.settings.autoRebirth == false and rt.autoTapUpgrade == 0)
	check("old profiles get the new settings filled in", rt.oldSettings.autoTap == false and rt.oldSettings.autoEquip == false and rt.oldSettings.autoRebirth == false and rt.oldUpgrade == 0)
	g0 = srv("profile").gems
	srv("giveGems", 100)
	ok, res = req("Upgrade", { id = "AutoTap" })
	local _, stU = req("GetState")
	check("Auto Tap upgrade raises the idle rate", ok and stU.auto.tapRate == Config.AutoTapFreeRate + Config.UpgradeById.AutoTap.perLevel + Config.AutoTapRate, stU.auto.tapRate)
end

ok, res = req("ClaimDaily")
check("daily claim", ok, res)
ok, res = req("ClaimDaily")
check("daily twice rejected", not ok, res)
ok, res = req("ClaimGift", { index = 1 })
check("gift not ready rejected", not ok, res)
srv("skipSession", 3700)
ok, res = req("ClaimGift", { index = 1 })
check("gift 1 claimed", ok, res)
ok, res = req("ClaimGift", { index = 1 })
check("gift twice rejected", not ok, res)
local magicBefore = #hatchedEvents
ok, res = req("ClaimGift", { index = #Config.Gifts })
task.wait(0.5)
local magicEvent = hatchedEvents[#hatchedEvents]
check("gift magic egg hatches exclusive pet", ok and #hatchedEvents > magicBefore and magicEvent.egg == "magic", res)
ok, res = req("ClaimGift", { index = 99 })
check("bogus gift rejected", not ok, res)

g0 = srv("profile").gems
ok, res = req("RedeemCode", { code = " release " })
check("code RELEASE", ok and srv("profile").gems == g0 + 50, res)
ok, res = req("RedeemCode", { code = "RELEASE" })
check("code reuse rejected", not ok, res)
ok, res = req("RedeemCode", { code = "NOTACODE" })
check("bad code rejected", not ok, res)

g0 = srv("profile").gems
ok, res = req("Upgrade", { id = "TapPower" })
check("upgrade TapPower", ok and srv("profile").gems < g0, res)
ok, res = req("Upgrade", { id = "Hax" })
check("bogus upgrade rejected", not ok, res)

ok, res = req("ClaimIndex", { zone = 3 })
check("index incomplete rejected", not ok, res)
for _, pet in Config.Pets do
	if pet.zone == 1 then
		srv("givePets", pet.id, 1)
	end
end
g0 = srv("profile").gems
ok, res = req("ClaimIndex", { zone = 1 })
check("index zone 1 claimed", ok and srv("profile").gems == g0 + Config.IndexRewardGems[1], res)
ok, res = req("ClaimIndex", { zone = 1 })
check("index twice rejected", not ok, res)

ok, res = req("Hack", {})
check("unknown action rejected", not ok, res)
ok, res = req("Equip", "x")
check("non-table payload rejected", not ok, res)

---------------------------------------------------------------------------
-- P0: offline earnings, quests, referral, live events, offers, social
---------------------------------------------------------------------------
check("notification ask after first rebirth", asks >= 1, asks)
local LiveEventClient = require(player.PlayerScripts.Client.LiveEventClient)
check("live event state received on join", LiveEventClient.data ~= nil and LiveEventClient.data.nextAt ~= nil)

-- offline earnings from a faked savedAt (1 h ago)
local off = srv("fakeOffline", 3600)
check("offline pending = tapValue x 1/s x 3600", off.pending == math.floor(off.tapValue * Config.OfflineTapsPerSecond * 3600) and off.seconds == 3600, off.pending)
local capped = srv("fakeOffline", 30 * 3600)
check("offline capped at 8/12 h", capped.seconds == capped.cap and capped.cap >= Config.OfflineCapHours * 3600, capped.seconds)
task.wait(1)
local popup = mainGui:FindFirstChild("PopupHolder")
check("offline popup shown", popup ~= nil)
local beforeTaps = srv("profile").taps
ok, res = req("ClaimOffline")
local afterTaps = srv("profile").taps
check("claim offline", ok and afterTaps - beforeTaps >= capped.pending * 0.999, res)
ok, res = req("ClaimOffline")
check("claim offline twice rejected", not ok, res)
local _, stOff = req("GetState")
check("offline cleared", stOff.offline and stOff.offline.pending == 0)
if popup and popup.Parent then
	popup:Destroy()
end

-- quests: progress from real hatches and taps, claims and bonus
srv("forceQuests", { "hatch", "taps", "rarity" })
srv("giveTaps", 1e7)
char:PivotTo(CFrame.lookAt(basicPos + Vector3.new(0, 0, -10), basicPos))
task.wait(2.6)
ok = req("Hatch", { egg = "basic", count = 1 })
TapEvent:FireServer(5)
task.wait(1.2)
local q = srv("quests")
check("quest progress on hatch", ok and q.progress[1] >= 1, q.progress[1])
check("quest progress on taps", q.progress[2] >= 1, q.progress[2])
local _, stQ = req("GetState")
check("quests in state", stQ.quests and #stQ.quests.list == 3 and stQ.quests.list[1].kind == "hatch")
check("quest progress pushed to client", questPushes >= 1, questPushes)
ok, res = req("ClaimQuest", { i = 1 })
check("claim unfinished quest rejected", not ok or q.progress[1] >= q.list[1].target, res)
ok, res = req("ClaimQuestBonus")
check("bonus before all quests rejected", not ok, res)
srv("completeQuests")
local gq = srv("profile").gems
local claimedAll = true
for i = 1, 3 do
	req("ClaimQuest", { i = i })
end
local _, stQ2 = req("GetState")
for _, quest in stQ2.quests.list do
	if not quest.claimed then
		claimedAll = false
	end
end
check("claim 3 quests", claimedAll and srv("profile").gems > gq)
ok, res = req("ClaimQuest", { i = 1 })
check("claim quest twice rejected", not ok, res)
local hb = #hatchedEvents
ok, res = req("ClaimQuestBonus")
task.wait(0.5)
check("quest bonus = magic egg", ok and #hatchedEvents > hb and hatchedEvents[#hatchedEvents].egg == "magic", res)
ok, res = req("ClaimQuest", { i = 9 })
check("bogus quest rejected", not ok, res)

-- referral via faked launch data
local gr = srv("profile").gems
local applied, refBy = srv("referral", "ref:" .. (player.UserId + 7))
check("referral invitee gift", applied == true and refBy == player.UserId + 7 and srv("profile").gems == gr + Config.ReferralInviteeGift.amount, refBy)
applied = srv("referral", "ref:" .. (player.UserId + 8))
check("second referral ignored", applied == false)
applied = srv("referral", "garbage")
check("bad launch data ignored", applied == false)

-- live events: admin command, override changes luck and the displayed odds
local Formulas = require(ReplicatedStorage.Shared.Formulas)
ok, res = srv("eventCommand", "/event LuckyHour 5")
check("event command needs admin", ok == false, res)
srv("makeAdmin")
ok, res = srv("eventCommand", "/event LuckyHour 999")
check("event command validates minutes", ok == false, res)
local _, stL0 = req("GetState")
local fx0 = srv("effects")
local nUpdates = #liveUpdates
ok, res = srv("eventCommand", "/event LuckyHour 5")
task.wait(1.5)
local _, stL1 = req("GetState")
local fx1 = srv("effects")
check("event command starts Lucky Hour", ok == true and #liveUpdates > nUpdates and liveUpdates[#liveUpdates].current ~= nil, res)
local oddsBefore = Formulas.odds("basic", stL0.luck)[3].chance
local oddsAfter = Formulas.odds("basic", stL1.luck)[3].chance
if fx0.luckMult >= 2 then
	check("Lucky Hour odds (already active on schedule)", stL1.luck == stL0.luck)
else
	check("Lucky Hour doubles luck + raises displayed odds", math.abs(stL1.luck - stL0.luck * 2) < 1e-6 and oddsAfter > oddsBefore and fx1.luckMult == 2, string.format("%.2f -> %.2f", stL0.luck, stL1.luck))
end
local eventPill = mainGui:FindFirstChild("EventPill", true) :: GuiObject?
check("event pill visible", eventPill ~= nil and eventPill.Visible)

-- offers / ads / social with every ID = 0 in Studio: hidden, no errors
local _, stO = req("GetState")
check("starter pack hidden (id 0)", stO.starter and stO.starter.available == false)
local starterBtn = mainGui:FindFirstChild("StarterPack", true) :: GuiObject?
check("starter button hidden", starterBtn ~= nil and not starterBtn.Visible)
local adBtn = mainGui:FindFirstChild("AdBoost", true) :: GuiObject?
check("ad button hidden (id 0)", adBtn ~= nil and not adBtn.Visible)
ok, res = req("WatchAd", { placement = "AdBoost" })
check("WatchAd unavailable (id 0)", not ok and type(res) == "table" and res.key == "msg.ad_unavailable", res)
ok, res = req("WatchAd", { placement = "Hack" })
check("WatchAd bad placement", not ok, res)
ok, res = req("ClaimGroupGift")
check("group gift hidden (GroupId 0)", not ok, res)
ok, res = req("ShareLink")
check("ShareLink answers", ok == true or (type(res) == "table" and res.key ~= nil), res)
local storeGui = mainGui:FindFirstChild("StoreWindow", true)
local starterCard = false
if storeGui then
	for _, d in storeGui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == Locale.t(Lang.code, "product.StarterPack.name") then
			starterCard = true
		end
	end
end
check("starter pack not in store grid", not starterCard)
local questsBtn = mainGui:FindFirstChild("Quests", true)
local inviteBtn = mainGui:FindFirstChild("Invite", true)
check("Quests + Invite buttons", questsBtn ~= nil and inviteBtn ~= nil)

---------------------------------------------------------------------------
-- Visual round: pets, world dressing, tap juice, hatch cinematic, window chrome
---------------------------------------------------------------------------
do
	local CollectionService = game:GetService("CollectionService")
	local ClientScripts = player.PlayerScripts.Client
	local PetModel = require(ReplicatedStorage.Shared.PetModel)
	local PetFollow = require(ClientScripts.PetFollow)
	local WorldFx = require(ClientScripts.WorldFx)
	local HatchCinematic = require(ClientScripts.UI.HatchCinematic)
	local Windows = require(ClientScripts.UI.Windows)

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
	check("pets have flyers and animated joints", flyers >= 8 and jointed >= 25, flyers .. " flyers, " .. jointed .. " jointed")

	-- pets in the world: shadow each, feet near the ground, hop on a tap
	local petFolder2 = workspace:FindFirstChild("ClientPets")
	local models, shadows = 0, 0
	local lowest, highest = math.huge, -math.huge
	if petFolder2 then
		for _, c in petFolder2:GetChildren() do
			if c:IsA("Model") then
				models += 1
				local y = c:GetPivot().Position.Y + ((c:GetAttribute("FootY") :: number?) or 0)
				lowest = math.min(lowest, y)
				highest = math.max(highest, y)
			elseif c.Name == "PetShadow" then
				shadows += 1
			end
		end
	end
	local groundY = hrp.Position.Y - 3
	check("each pet has a blob shadow", models > 0 and shadows == models, models .. " pets, " .. shadows .. " shadows")
	check("pet feet stay between the ground and hover height", lowest > groundY - 1.5 and highest < groundY + 5, string.format("%.1f..%.1f (ground %.1f)", lowest, highest, groundY))
	local okPulse = pcall(PetFollow.pulse)
	check("pets hop on a tap (pulse)", okPulse)

	-- world dressing (audited on the server: with instance streaming the client only
	-- holds the zones around the player)
	local audit = srv("worldAudit")
	local animatedCount = #CollectionService:GetTagged("TpsAnim")
	check("every zone has border, horizon, lamps, landmarks and props", #audit.missing == 0, table.concat(audit.missing, ", "))
	check("every egg: sparkle emitter, rest CFrame, streamed as one model", audit.sparkly == #Config.Eggs and audit.atomic == #Config.Eggs, audit.sparkly .. "/" .. audit.atomic)
	check("instance streaming is on and the world is anchored", audit.streaming == true and audit.unanchored == 0, audit.unanchored)
	check("client tracks the eggs that streamed in", WorldFx.eggCount() >= 3 and WorldFx.eggCount() <= #Config.Eggs, WorldFx.eggCount())
	local spinner
	for _, inst in CollectionService:GetTagged("TpsAnim") do
		if inst:GetAttribute("SpinAxis") and (inst:GetPivot().Position - hrp.Position).Magnitude < 500 then
			spinner = inst
			break
		end
	end
	local moved = false
	if spinner then
		local before = spinner:GetPivot()
		task.wait(0.5)
		moved = spinner:GetPivot() ~= before
	end
	check("tagged world props animate", animatedCount >= 30 and moved, animatedCount .. " tagged")
	check("egg burst hook", (pcall(WorldFx.eggBurst, "basic")))

	-- tap juice: combo counts real taps and drops after a pause
	local vpSize = workspace.CurrentCamera.ViewportSize - game:GetService("GuiService"):GetGuiInset()
	local tapsBefore = srv("profile").taps
	for _ = 1, 8 do
		Tapper.simulate(Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.42))
		task.wait(0.1)
	end
	check("combo counts taps", Tapper.combo >= 6, Tapper.combo)
	local fxGui = gui:FindFirstChild("TapFx")
	local comboText = false
	if fxGui then
		for _, d in fxGui:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == Lang.t("tap.combo", { n = Tapper.combo }) and d.TextTransparency < 0.5 then
				comboText = true
			end
		end
	end
	check("combo label shown", comboText)
	task.wait(0.6)
	check("simulated taps reach the server", srv("profile").taps > tapsBefore)
	task.wait(1.4)
	check("combo drops after a pause", Tapper.combo == 0, Tapper.combo)

	-- hatch cinematic runs to the end (Legendary path: flash, sunburst, confetti)
	HatchCinematic.play("basic", { { uid = "t1", id = "unicorn", tier = 1, chance = 0.1, rarity = "Legendary", new = true } }, false)
	task.wait(0.3)
	check("cinematic starts", HatchCinematic.isPlaying())
	local waited = 0
	while HatchCinematic.isPlaying() and waited < 12 do
		waited += task.wait(0.25)
	end
	local overlayGui = gui:FindFirstChild("TapPetsOverlay")
	check("cinematic finishes and cleans up", not HatchCinematic.isPlaying() and overlayGui ~= nil and overlayGui:FindFirstChild("Hatch") == nil, string.format("%.1fs", waited))

	-- window chrome: dim layer follows the open window
	local dimGui = gui:FindFirstChild("TapPetsDim")
	local dim = dimGui and dimGui:FindFirstChild("Dim") :: GuiObject?
	Windows.open("Pets")
	task.wait(0.4)
	local dimOn = dim ~= nil and dim.Visible
	local petsWindow = mainGui:FindFirstChild("PetsWindow", true) :: GuiObject?
	check("pets window opens with the dim layer", dimOn and petsWindow ~= nil and petsWindow.Visible)
	Windows.close()
	task.wait(0.5)
	check("dim layer hides on close", dim ~= nil and not dim.Visible)
end

---------------------------------------------------------------------------
-- Traits: rolled with Trait Dice (earned by playing, never sold)
---------------------------------------------------------------------------
do
	local diceNow = srv("dice")
	check("trait dice earned by playing (start + rebirths + quests + index)", diceNow >= Config.TraitDice.start + 2 * Config.TraitDice.rebirth + 3 * Config.TraitDice.quest + Config.TraitDice.questBonus + Config.TraitDice.index, diceNow)
	local profT = srv("profile")
	local target = profT.equipped[1]
	srv("dice", 0)
	ok, res = req("RollTrait", { uid = target })
	check("trait roll without dice rejected", not ok and type(res) == "table" and res.key == "msg.no_dice", res)
	srv("dice", 3)
	local tvBefore = srv("profile").tapValue
	ok, res = req("RollTrait", { uid = target })
	local grade = srv("petTrait", target)
	check("trait roll gives a grade and spends a die", ok and type(res) == "number" and res >= 1 and res <= #Config.TraitGrades and grade == res and srv("dice") == 2, res)
	task.wait(0.6)
	check("trait raises the tap value", srv("profile").tapValue > tvBefore, srv("profile").tapValue / tvBefore)
	ok, res = req("RollTrait", { uid = "nope" })
	check("trait roll on an unknown pet rejected", not ok and srv("dice") == 2, res)
	local rtT = srv("roundtrip")
	check("dice survive save + load", rtT.dice == 2, rtT.dice)
	local WindowsT = require(player.PlayerScripts.Client.UI.Windows)
	local PetsWindowT = require(player.PlayerScripts.Client.UI.PetsWindow)
	WindowsT.open("Pets")
	task.wait(0.5)
	PetsWindowT.selectFirst()
	task.wait(0.3)
	local petsGui = mainGui:FindFirstChild("PetsWindow", true)
	local oddsLabel = petsGui and petsGui:FindFirstChild("TraitOdds", true) :: TextLabel?
	local rollBtn = petsGui and petsGui:FindFirstChild("RollTrait", true) :: GuiObject?
	local pctSum = 0
	if oddsLabel then
		for n in oddsLabel.Text:gmatch("([%d%.]+)%%") do
			pctSum += tonumber(n) :: number
		end
	end
	check("pets window shows the trait odds (sum 100) and the roll button", oddsLabel ~= nil and oddsLabel.Visible and math.abs(pctSum - 100) < 1e-6 and rollBtn ~= nil and rollBtn.Visible, oddsLabel and oddsLabel.Text)
	WindowsT.close()
	task.wait(0.4)
end

---------------------------------------------------------------------------
-- Pet Park: own plot, pets on the pedestals, offline earnings wait in the chest
---------------------------------------------------------------------------
do
	local ParkFx = require(player.PlayerScripts.Client.ParkFx)
	local park = srv("park")
	check("player owns one of the 12 plots", park.plots == 12 and type(park.index) == "number" and park.ownerId == player.UserId and park.ownerName == player.DisplayName and park.used == 1, park.index)
	local _, stPark = req("GetState")
	check("plot index in state", stPark.plot == park.index, stPark.plot)
	ok, res = req("GoPark")
	task.wait(2.5)
	check("teleport to my park", ok and hrp.Position.Z < -Config.ZoneLength / 2, hrp.Position.Z)
	local statues, plotsShown = ParkFx.counts()
	local equippedNow = #srv("profile").equipped
	check("my pets stand on the pedestals", plotsShown == 1 and statues == math.min(6, equippedNow), statues .. " statues, " .. equippedNow .. " equipped")
	local plotModel = workspace.World.Park:FindFirstChild("Plot" .. park.index)
	local signText = plotModel and plotModel:FindFirstChild("OwnerText", true) :: TextLabel?
	check("sign shows the owner", signText ~= nil and signText.Text == player.DisplayName, signText and signText.Text)
	local pending = srv("fakeOffline", 7200).pending
	task.wait(1.5)
	local chestText = plotModel and plotModel:FindFirstChild("ChestText", true) :: TextLabel?
	check("chest shows what is waiting", pending > 0 and chestText ~= nil and chestText.Text == Lang.t("park.pending", { n = require(ReplicatedStorage.Shared.Format).abbrev(pending) }), chestText and chestText.Text)
	local otherPlot = if park.index == 1 then 2 else 1
	ok, res = srv("parkCollect", otherPlot)
	check("someone else's chest stays shut", ok == false and res.key == "msg.not_your_chest", res)
	local tapsBeforeChest = srv("profile").taps
	ok, res = srv("parkCollect", park.index)
	check("my chest pays the offline earnings", ok == true and srv("profile").taps - tapsBeforeChest >= pending * 0.999, res)
	ok, res = srv("parkCollect", park.index)
	check("an empty chest gives nothing", ok == false and res.key == "msg.nothing_to_claim", res)
	local popupP = mainGui:FindFirstChild("PopupHolder")
	if popupP then
		popupP:Destroy()
	end
end

---------------------------------------------------------------------------
-- Performance: normal play = 9 pets equipped, auto tap on, tapping 10 times a second,
-- 7 other "players" (ghost rigs) with 9 pets each standing around.
---------------------------------------------------------------------------
do
	local Stats = game:GetService("Stats")
	local RunService = game:GetService("RunService")
	local PetFollow = require(player.PlayerScripts.Client.PetFollow)
	char:PivotTo(CFrame.new(0, 4, -20))
	srv("maxPets")
	local ghosts = Instance.new("Folder")
	ghosts.Name = "PerfGhosts"
	ghosts.Parent = workspace
	local ghostKey = "celestialdragon:0,shadowdragon:0,galaxydragon:2,firedragon:1,icedragon:0,nebulaowl:0,hellhound:0,crystalunicorn:0,jellyphoenix:0"
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local g = Instance.new("Part")
		g.Anchored = true
		g.CanCollide = false
		g.Transparency = 1
		g.Size = Vector3.new(2, 2, 1)
		g.CFrame = CFrame.new(math.cos(a) * 34, 3, -20 + math.sin(a) * 34)
		g.Parent = ghosts
		PetFollow.addGhost(g, ghostKey)
	end
	task.wait(2.5)
	local vp = workspace.CurrentCamera.ViewportSize - game:GetService("GuiService"):GetGuiInset()
	local frames, time, worst = 0, 0, 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		frames += 1
		time += dt
		worst = math.max(worst, dt)
	end)
	srv("perfStart")
	local t0 = os.clock()
	while os.clock() - t0 < 6 do
		Tapper.simulate(Vector2.new(vp.X * (0.45 + math.random() * 0.1), vp.Y * 0.42))
		task.wait(0.1)
	end
	conn:Disconnect()
	local sp = srv("perfEnd")
	local fps = frames / math.max(time, 0.001)
	local clientParts, clientEmitters, clientLights, petParts = 0, 0, 0, 0
	local petFolderP = workspace:FindFirstChild("ClientPets")
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			clientParts += 1
			if petFolderP and d:IsDescendantOf(petFolderP) then
				petParts += 1
			end
		elseif d:IsA("ParticleEmitter") then
			clientEmitters += 1
		elseif d:IsA("Light") then
			clientLights += 1
		end
	end
	local guiObjects = 0
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			guiObjects += 1
		end
	end
	local perfLine = string.format(
		"server: %d instances, %d parts, %d emitters, %d lights, %d shadow casters, %d touchable, %.0f MB, frame %.2f ms (worst %.1f), heartbeat %.2f ms | remotes/s: %.1f out, %.1f tap in, %.1f request in | client: %.0f FPS (worst frame %.0f ms), %d parts (%d in %d pets), %d emitters, %d lights, %d gui objects, %.0f MB",
		sp.instances, sp.parts, sp.emitters, sp.lights, sp.shadowCasters, sp.touchable, sp.memoryMb, sp.frameMs, sp.worstMs, sp.heartbeatMs,
		sp.outPerSec, sp.tapInPerSec, sp.requestInPerSec,
		fps, worst * 1000, clientParts, petParts, PetFollow.visibleCount(), clientEmitters, clientLights, guiObjects, Stats:GetTotalMemoryUsageMb()
	)
	print("[TEST] PERF " .. perfLine)
	check("perf measured", sp.parts > 0 and fps > 0, perfLine)
	-- Budgets: fail the playtest when someone goes over.
	check("budget: world parts <= 3800", sp.parts <= 3800, sp.parts)
	check("budget: server emitters <= 60, lights <= 60", sp.emitters <= 60 and sp.lights <= 60, sp.emitters .. " / " .. sp.lights)
	check("budget: shadow casters in the world <= 160", sp.shadowCasters <= 160, sp.shadowCasters)
	check("budget: nothing in the world is touchable", sp.touchable == 0, sp.touchable)
	check("budget: server heartbeat <= 2 ms", sp.heartbeatMs <= 2, sp.heartbeatMs)
	check("budget: remotes out <= 3.2/s, tap in <= 4.5/s, requests <= 1/s in normal play", sp.outPerSec <= 3.2 and sp.tapInPerSec <= 4.5 and sp.requestInPerSec <= 1, string.format("%.1f / %.1f / %.1f", sp.outPerSec, sp.tapInPerSec, sp.requestInPerSec))
	check("budget: client >= 45 FPS with 72 pets on screen", fps >= 45, fps)
	check("budget: <= 60 parts per pet on screen", petParts / math.max(1, PetFollow.visibleCount()) <= 60, petParts / math.max(1, PetFollow.visibleCount()))
	check("budget: HUD + windows <= 1300 gui objects", guiObjects <= 1300, guiObjects)

	-- Lite profile (phones / graphics slider <= 3): fewer pets of other players, no pet
	-- lights or trails, no real-time shadows. Preview it with the ForceLite attribute.
	local Quality = require(player.PlayerScripts.Client.Quality)
	check("quality rule: touch or graphics <= 3 is lite", Quality.isLite(true, 0, false) and Quality.isLite(false, 3, false) and Quality.isLite(false, 1, false) and not Quality.isLite(false, 4, false) and not Quality.isLite(false, 0, false) and Quality.isLite(false, 10, true))
	local fullVisible = PetFollow.visibleCount()
	workspace:SetAttribute("ForceLite", true)
	task.wait(1.5)
	local liteVisible = PetFollow.visibleCount()
	local liteTrails, liteLights, liteParts = 0, 0, 0
	if petFolderP then
		for _, d in petFolderP:GetDescendants() do
			if d:IsA("Trail") then
				liteTrails += 1
			elseif d:IsA("Light") then
				liteLights += 1
			elseif d:IsA("BasePart") then
				liteParts += 1
			end
		end
	end
	check("lite: at most 4 pets per other player", Quality.lite and liteVisible <= 9 + 7 * 4 and liteVisible < fullVisible, liteVisible .. " (full " .. fullVisible .. ")")
	check("lite: no pet trails or lights, far fewer parts", liteTrails == 0 and liteLights == 0 and liteParts < petParts * 0.7, string.format("%d trails, %d lights, %d parts (full %d)", liteTrails, liteLights, liteParts, petParts))
	check("lite: real-time shadows off", game:GetService("Lighting").GlobalShadows == false)
	print(string.format("[TEST] PERF lite: %d pets, %d pet parts (full: %d pets, %d parts)", liteVisible, liteParts, fullVisible, petParts))
	workspace:SetAttribute("ForceLite", false)
	task.wait(1)
	check("back to full quality", not Quality.lite and PetFollow.visibleCount() == fullVisible and game:GetService("Lighting").GlobalShadows == true, PetFollow.visibleCount())

	-- Virtualized inventory: a big inventory only builds the icons on screen
	srv("givePets", "dog", 70)
	task.wait(0.6)
	local PetsWindowT = require(player.PlayerScripts.Client.UI.PetsWindow)
	local WindowsT = require(player.PlayerScripts.Client.UI.Windows)
	WindowsT.open("Pets")
	task.wait(0.8)
	local icons, cellsTotal = PetsWindowT.iconCount()
	check("inventory is virtualized (icons only for visible rows)", cellsTotal >= 70 and icons >= 8 and icons <= 32, icons .. " icons / " .. cellsTotal .. " cells")
	WindowsT.close()
	task.wait(0.4)
	icons = PetsWindowT.iconCount()
	check("closed inventory holds no icons", icons == 0, icons)

	-- nothing left behind when a player leaves
	local leaks = srv("leaks")
	check("player cleanup empties every per-player table", leaks.before >= 5 and leaks.after == 0 and leaks.data == 0, leaks.before .. " -> " .. leaks.after)
	local rigsTracked, connsTracked = PetFollow.tracked()
	ghosts:Destroy()
	task.wait(0.3)
	local rigsAfter, connsAfter = PetFollow.tracked()
	check("pet rigs are dropped with their owner", rigsTracked == 8 and rigsAfter == 1 and connsAfter == connsTracked, rigsTracked .. " -> " .. rigsAfter)

	-- paid random items: restricted players can't buy eggs, packs with eggs, luck or Taps
	local Purchase = require(player.PlayerScripts.Client.Purchase)
	local _, stP = req("GetState")
	check("policy flag resolved for this player", type(stP.paidRandomRestricted) == "boolean", stP.paidRandomRestricted)
	srv("setRestricted", true)
	task.wait(0.6)
	local _, stR = req("GetState")
	Config.ProductByKey.MagicEgg1.id = 1 -- pretend the product is live (client copy only)
	Config.PassByKey.Lucky.id = 1
	Config.ProductByKey.GemsSmall.id = 1
	Config.PassByKey.AutoTap.id = 1
	local StoreT = require(player.PlayerScripts.Client.UI.StoreWindow)
	StoreT.rebuild()
	local storePasses, storeProducts = StoreT.counts()
	check("restricted: the store only lists what is allowed", storePasses == 1 and storeProducts == 1, storePasses .. " passes, " .. storeProducts .. " products")
	check("restricted: state flag, starter pack off", stR.paidRandomRestricted == true and stR.starter.available == false)
	check("restricted: eggs, luck, taps and luck passes blocked", Purchase.productBlocked("MagicEgg1") and Purchase.productBlocked("SuperLuck") and Purchase.productBlocked("TapsSmall") and Purchase.productBlocked("StarterPack") and Purchase.passBlocked("Lucky") and Purchase.passBlocked("VIP") and not Purchase.productAvailable("MagicEgg1") and not Purchase.passAvailable("Lucky"))
	check("restricted: gems and utility passes still fine", not Purchase.productBlocked("GemsSmall") and not Purchase.passBlocked("AutoTap") and not Purchase.passBlocked("PetSlots"))
	local function magicPrompt(): ProximityPrompt?
		for _, d in workspace.World.Eggs:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("EggId") == "magic" then
				return d
			end
		end
		return nil
	end
	local mp = magicPrompt()
	check("restricted: the Robux egg's prompt is off", mp == nil or mp.Enabled == false, mp and mp.Enabled)
	srv("setRestricted", false)
	task.wait(0.6)
	mp = magicPrompt()
	check("unrestricted: the Robux egg's prompt is back", mp == nil or mp.Enabled == true, mp and mp.Enabled)
	check("unrestricted: purchases available again", not Purchase.productBlocked("MagicEgg1") and Purchase.productAvailable("MagicEgg1") and Purchase.passAvailable("Lucky"))
	storePasses, storeProducts = StoreT.counts()
	check("unrestricted: the store rebuilt itself with everything", storePasses == 2 and storeProducts == 2, storePasses .. " passes, " .. storeProducts .. " products")
	local storeOdds = mainGui:FindFirstChild("StoreWindow", true)
	local oddsText: string? = nil
	if storeOdds then
		for _, d in storeOdds:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "Odds" and d.Text:find("%", 1, true) then
				oddsText = d.Text
			end
		end
	end
	check("store: the Magic Egg card shows its odds in % before buying", oddsText ~= nil, oddsText)
	check("offer odds: Starter Pack and Magic Egg list every pet", Purchase.oddsText("StarterPack") ~= nil and Purchase.oddsText("MagicEgg3") ~= nil and Purchase.oddsText("GemsSmall") == nil)
	Config.ProductByKey.MagicEgg1.id = 0
	Config.PassByKey.Lucky.id = 0
	Config.ProductByKey.GemsSmall.id = 0
	Config.PassByKey.AutoTap.id = 0
	StoreT.rebuild()
	PERF = { server = sp, fps = fps, worst = worst, clientParts = clientParts, petParts = petParts, emitters = clientEmitters, lights = clientLights, gui = guiObjects }
end

---------------------------------------------------------------------------
-- Languages
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
for _, code in { "de", "ja", "pt" } do
	ok, res = req("SetLanguage", { lang = code })
	task.wait(0.8)
	local _, st2 = req("GetState")
	local petsBtn = mainGui:FindFirstChild("Pets", true)
	local want = Locale.t(code, "menu.Pets")
	check("SetLanguage " .. code, ok and st2.lang == code and Lang.code == code and petsBtn ~= nil and labelIn(petsBtn, want), string.format("ok=%s state=%s lang=%s btn=%s want=%s", tostring(ok), tostring(st2.lang), Lang.code, if petsBtn then petsBtn:GetFullName() else "nil", want))
end
local eggText
for _, d in workspace.World.Eggs.Egg_basic:GetDescendants() do
	if d:IsA("TextLabel") then
		eggText = d.Text
	end
end
check("world egg label localized", eggText ~= nil and eggText:find(Locale.t("pt", "egg.basic"), 1, true) ~= nil, eggText)
req("SetLanguage", { lang = "" })
task.wait(0.8)
check("language back to account locale", Lang.code == Locale.resolve(player.LocaleId), Lang.code)
local plain = 0
for _, m in notifications do
	if type(m) ~= "table" or type(m.key) ~= "string" then
		plain += 1
	end
end
check("server notifications are translation keys", #notifications > 0 and plain == 0, #notifications .. " notes, " .. plain .. " plain")

task.wait(3) -- let UI react (hatch cinematics, toasts)
check("no client errors", #clientErrors == 0, table.concat(clientErrors, " || "))
srv("report", table.concat(lines, "\n"))
