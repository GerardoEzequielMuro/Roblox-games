-- Client half of the gameplay harness: goes through the real remotes / HUD code paths and the
-- client-side systems (sky, feedback, abilities, wind), then sends its report to the server
-- (AutoTest.server.luau). The world is streamed: the server puts the character on pads
-- ("standOn"), and this script only looks at what is loaded around it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local clientErrors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then table.insert(clientErrors, msg) end
end)
local lines = {}
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail ~= nil then " :: " .. tostring(detail) else "")
	print("[TEST] c " .. line)
	table.insert(lines, line)
end

while not player:GetAttribute("ServerReady") do task.wait(0.2) end
local TRF = ReplicatedStorage:WaitForChild("__TestRF")
local function q(kind, arg) return TRF:InvokeServer(kind, arg) end

local ClientRoot = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Net = require(ClientRoot:WaitForChild("Net"))
local Hud = require(ClientRoot:WaitForChild("UI"):WaitForChild("Hud"))
local Kit = require(ClientRoot.UI.Kit)
local Progress = require(ClientRoot.UI.Progress)
local Atmos = require(ClientRoot:WaitForChild("World"):WaitForChild("Atmos"))
local Juice = require(ClientRoot.World.Juice)
local LocalFx = require(ClientRoot.World.LocalFx)
local Lang = require(ClientRoot:WaitForChild("Lang"))
local Shared = ReplicatedStorage.Shared
local Locale = require(Shared.Locale)
local Ambience = require(Shared.Ambience)
local Layout = require(Shared.Layout)
local Rules = require(Shared.Rules)
local Gifts = require(Shared.Gifts)
local Powerups = require(Shared.Powerups)
local Perks = require(Shared.Perks)
local TowerStyle = require(Shared.TowerStyle)
local Config = require(Shared.Config)

local BUDGET = { clientPartsLobby = 5200, stateBytes = 2600, remoteEventsIdle = 0.5, fps = 30, renderCpuMs = 16, drawCalls = 2500 }

local t0 = os.clock()
while Net.state.stage == nil and os.clock() - t0 < 20 do task.wait(0.2) end
check("client got State push", Net.state.stage ~= nil)

local winEvents, lastWin = 0, nil
ReplicatedStorage.Remotes.Win.OnClientEvent:Connect(function(d) winEvents += 1; lastWin = d end)
local offers, askNotif, liveUpdates, giftEvents, towerEnters, shieldEvents = 0, 0, 0, {}, 0, 0
ReplicatedStorage.Remotes.OfferSkip.OnClientEvent:Connect(function() offers += 1 end)
ReplicatedStorage.Remotes.AskNotifications.OnClientEvent:Connect(function() askNotif += 1 end)
ReplicatedStorage.Remotes.LiveEventUpdate.OnClientEvent:Connect(function() liveUpdates += 1 end)
ReplicatedStorage.Remotes.Gift.OnClientEvent:Connect(function(d) table.insert(giftEvents, d.id) end)
ReplicatedStorage.Remotes.TowerEnter.OnClientEvent:Connect(function() towerEnters += 1 end)
ReplicatedStorage.Remotes.Shield.OnClientEvent:Connect(function() shieldEvents += 1 end)
local stateBytes = 0
ReplicatedStorage.Remotes.State.OnClientEvent:Connect(function(st)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, st)
	if ok then stateBytes = math.max(stateBytes, #json) end
end)

local function char() return player.Character or player.CharacterAdded:Wait() end
local function stageNow(): number return player.leaderstats.Stage.Value end
local function standOn(k: number) q("standOn", k) end
local function waitFor(cond: () -> boolean, timeout: number): boolean
	local t = os.clock()
	while os.clock() - t < timeout do
		if cond() then return true end
		task.wait(0.1)
	end
	return cond()
end
local function req(action, payload)
	task.wait(0.2) -- stay far under the 8/s rate limit
	return Net.request(action, payload)
end
-- climbs pad by pad (every pad must count, saving or not)
local function climb(from: number, to: number, step: number?): number?
	local k = from
	while k < to do
		k = math.min(to, k + (step or 1))
		task.wait(0.84)
		standOn(k)
		if not waitFor(function() return stageNow() >= k end, 1.5) then
			standOn(k) -- one retry (landed during the cooldown or a respawn)
			if not waitFor(function() return stageNow() >= k end, 2.5) then
				return k
			end
		end
	end
	return nil
end
local function respawn()
	local before = player.Character
	q("killMe")
	waitFor(function() return player.Character ~= before and player.Character ~= nil and player.Character:FindFirstChild("HumanoidRootPart") ~= nil end, 7)
	task.wait(0.8)
end

-- performance probe: FPS, network, remote traffic, memory, what the client has loaded -------------------
local remoteEvents, remoteBytes = 0, 0
for _, r in ReplicatedStorage.Remotes:GetChildren() do
	if r:IsA("RemoteEvent") then
		r.OnClientEvent:Connect(function(...)
			remoteEvents += 1
			local ok, json = pcall(HttpService.JSONEncode, HttpService, { ... })
			remoteBytes += if ok then #json else 0
		end)
	end
end
local perf = {}
local function perfSample(label: string, seconds: number)
	local frames, slow = 0, 0
	local cpu, gpu, draws, tris = 0, 0, 0, 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		frames += 1
		if dt > 1 / 30 then slow += 1 end
		cpu += Stats.RenderCPUFrameTime
		gpu += Stats.RenderGPUFrameTime
		draws += Stats.SceneDrawcallCount
		tris += Stats.SceneTriangleCount
	end)
	local recv, sent, n = 0, 0, 0
	local ev0, by0 = remoteEvents, remoteBytes
	local t = os.clock()
	while os.clock() - t < seconds do
		task.wait(0.5)
		recv += Stats.DataReceiveKbps
		sent += Stats.DataSendKbps
		n += 1
	end
	conn:Disconnect()
	local dt = os.clock() - t
	local parts, instances = 0, 0
	for _, d in workspace:GetDescendants() do
		instances += 1
		if d:IsA("BasePart") then parts += 1 end
	end
	local r = {
		fps = frames / dt, slow = slow, recv = recv / n, sent = sent / n,
		cpuMs = cpu / math.max(frames, 1) * 1000, gpuMs = gpu / math.max(frames, 1) * 1000,
		draws = draws / math.max(frames, 1), tris = tris / math.max(frames, 1),
		events = (remoteEvents - ev0) / dt, bytes = (remoteBytes - by0) / dt,
		mem = Stats:GetTotalMemoryUsageMb(), parts = parts, instances = instances,
	}
	perf[label] = r
	print(("[TEST] c PERF %s (%.0f s): %.1f fps (%d frames over 33 ms), render CPU %.2f ms / GPU %.2f ms per frame, %.0f draw calls, %.0f triangles, network in %.1f kbps / out %.1f kbps, remote events %.2f/s (%.0f B/s), memory %.0f MB, client workspace %d instances / %d parts"):format(
		label, dt, r.fps, r.slow, r.cpuMs, r.gpuMs, r.draws, r.tris, r.recv, r.sent, r.events, r.bytes, r.mem, r.instances, r.parts))
	return r
end
do
	local r = perfSample("lobby idle", 12)
	local server = q("census")
	-- Studio caps an unfocused window at 15 fps whatever the place costs, so the frame budget is
	-- 30 fps OR (when the window is capped) a frame that costs less than half of a 30 fps frame
	check("BUDGET client frame: >= " .. BUDGET.fps .. " fps, or render CPU <= " .. BUDGET.renderCpuMs .. " ms when Studio caps the window", r.fps >= BUDGET.fps or (r.cpuMs > 0 and r.cpuMs <= BUDGET.renderCpuMs), ("%.1f fps, render CPU %.2f ms"):format(r.fps, r.cpuMs))
	check("BUDGET draw calls in the lobby <= " .. BUDGET.drawCalls, r.draws > 0 and r.draws <= BUDGET.drawCalls, ("%.0f"):format(r.draws))
	check("BUDGET remote events while idle <= " .. BUDGET.remoteEventsIdle .. "/s", r.events <= BUDGET.remoteEventsIdle, ("%.2f/s"):format(r.events))
	check("BUDGET client parts in the lobby <= " .. BUDGET.clientPartsLobby, r.parts <= BUDGET.clientPartsLobby, r.parts)
	check("streaming: the client holds only its stretch of the tower", r.parts < server.parts * 0.85, ("client %d of %d server parts"):format(r.parts, server.parts))
	check("far obstacles sleep: most animated obstacles are not running", server.obstacles > 40 and server.running < server.obstacles * 0.3, ("%d of %d running"):format(server.running, server.obstacles))
end

-- P0-3 referral (fake LaunchData) while the profile is new ---------------------------------------
local r0 = q("state")
check("invite ref: gift", q("invite", "ref:12345") == true)
local r1 = q("state")
check("invitee got +1 skip +50 coins", r1.freeSkips == r0.freeSkips + 1 and r1.coins == r0.coins + 50 and r1.referredBy == 12345, ("%d->%d skips, %d->%d coins"):format(r0.freeSkips, r1.freeSkips, r0.coins, r1.coins))
check("second invite ignored", q("invite", "ref:999") == false)
check("bad launch data ignored", q("invite", "ref:12x") == false)
check("inviter reward x2", q("grantInviter", 2) == 2)
q("setReferralRewards", 24)
check("inviter reward capped at 25", q("grantInviter", 3) == 1)
q("resetSkips")

-- UI with every id = 0 ------------------------------------------------------------------------------
local gui0 = player.PlayerGui:WaitForChild("SkyTowerUI")
local menu = gui0:WaitForChild("Menu")
task.wait(0.5)
check("Invite + Share buttons shown", menu:FindFirstChild("Invite") and menu.Invite.Visible and menu:FindFirstChild("Share") and menu.Share.Visible)
check("Starter / Group buttons hidden (ids 0)", not menu.Starter.Visible and not menu.Group.Visible)
check("WatchAd rejected (AdSkip id 0)", not req("WatchAd", { placement = "skip" }))
check("group gift rejected (GroupId 0)", not req("ClaimGroupGift"))
check("starter trail not for sale", not req("BuyTrail", { id = "starter" }))
check("gift / lounge cosmetics are not for sale", not req("BuyTrail", { id = "summit" }) and not req("BuyTrail", { id = "lounge_neon" }) and not req("BuyEffect", { id = "aurora" }))
local function boardTitle(name: string, key: string)
	local b = workspace.Lobby:FindFirstChild(name)
	if b then
		for _, d in b:GetDescendants() do
			if d:IsA("TextLabel") and d:GetAttribute("LocKey") == key then return d end
		end
	end
	return nil
end
check("Fastest Climb board in the lobby", boardTitle("FastestBoard", "board.fastest") ~= nil)
check("Highest Stage board in the lobby", boardTitle("StageBoard", "board.stage") ~= nil)
req("GetState")
check("live event state received", waitFor(function() return liveUpdates > 0 end, 5), liveUpdates)
check("run armed, not started", q("state").runValid == true and q("state").runStart == nil)

-- visual layer: sky by height, post-processing, intro, ambient particles -----------------------------
local function clockNear(h: number): boolean
	local d = math.abs(Lighting.ClockTime - h) % 24
	return math.min(d, 24 - d) < 0.35
end
check("intro title card gone after the join", waitFor(function() return player.PlayerGui:FindFirstChild("SkyTowerIntro") == nil end, 6))
local weatherBox = workspace:FindFirstChild("WeatherBox")
local weatherFx = weatherBox and weatherBox:FindFirstChild("Weather")
check("ambient particles follow the camera", weatherFx ~= nil and weatherFx.Enabled and waitFor(function() return (weatherBox.Position - workspace.CurrentCamera.CFrame.Position).Magnitude < 40 end, 3))
local weatherRate1 = weatherFx and weatherFx.Rate
check("post-processing present", Lighting:FindFirstChildOfClass("BloomEffect") ~= nil and Lighting:FindFirstChildOfClass("ColorCorrectionEffect") ~= nil and Lighting:FindFirstChildOfClass("SunRaysEffect") ~= nil and Lighting:FindFirstChildOfClass("Atmosphere") ~= nil)
check("lobby sky = world 1 of tower 1", waitFor(function() return Atmos.world == 1 and Atmos.tower == 1 and clockNear(Ambience.Profiles[1].clock) end, 6), ("world %d clock %.2f"):format(Atmos.world, Lighting.ClockTime))

-- pads near the lobby (the rest of the tower is not loaded: look things up when they are close)
local DONE = Color3.fromRGB(50, 215, 80)
local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.02
end
local function tagged(tagName: string, stage: number)
	for _, inst in CollectionService:GetTagged(tagName) do
		if inst:GetAttribute("Stage") == stage then return inst end
	end
	return nil
end
local localFx = workspace:WaitForChild("LocalFx", 5)
local beacon = localFx and localFx:FindFirstChild("NextBeacon")
local function beaconOn(stage: number): boolean
	local top = Juice.padTop(stage)
	return beacon ~= nil and (Vector3.new(beacon.Position.X, 0, beacon.Position.Z) - Vector3.new(top.X, 0, top.Z)).Magnitude < 1
end
check("beacon on the next pad (1)", beaconOn(1), beacon and tostring(beacon.Position))
local flag1 = tagged("Flag", 1)
check("flag 1 starts lowered", flag1 ~= nil and (flag1.Position - flag1:GetAttribute("Low").Position).Magnitude < 0.1)
local pad2 = tagged("Checkpoint", 2)
local pad2Base = pad2 and pad2.Color
local progressGui = gui0:WaitForChild("Progress")
check("progress bar has the world gradient", progressGui:FindFirstChild("Fill", true) ~= nil and progressGui:FindFirstChild("Fill", true):FindFirstChildOfClass("UIGradient") ~= nil)
local levelGui = gui0:WaitForChild("LevelBar")
local towerLine = levelGui:WaitForChild("Tower")
check("level bar counts the whole climb", levelGui.Bar.Label.Text == Lang.t("progress.label", { stage = stageNow(), total = 1000, pct = 0 }), levelGui.Bar.Label.Text)
do
	-- HUD conventions of tower games: timer top centre, progress bar on the right edge, Menu +
	-- coins in the bottom-left corner, nothing else until you ask for it
	local vp = workspace.CurrentCamera.ViewportSize
	local track = progressGui:WaitForChild("Track")
	check("progress bar is vertical, on the right edge", track.AbsoluteSize.Y > track.AbsoluteSize.X * 8 and track.AbsolutePosition.X + track.AbsoluteSize.X > vp.X - 20 and track.AbsoluteSize.Y > vp.Y * 0.45, tostring(track.AbsoluteSize))
	local me = progressGui.Markers:FindFirstChild("Me")
	check("my head is on the progress bar", me ~= nil and me.AbsolutePosition.X < track.AbsolutePosition.X)
	local cornerGui = gui0:WaitForChild("Corner")
	check("Menu button in the corner, menu grid closed until asked", cornerGui:FindFirstChild("MenuButton") ~= nil and not menu.Visible)
	local timerTop = gui0.Stats.RunTimer.Time
	check("run timer is top centre", math.abs(timerTop.AbsolutePosition.X + timerTop.AbsoluteSize.X / 2 - vp.X / 2) < 6 and timerTop.AbsolutePosition.Y < vp.Y * 0.2)
	local visibleButtons = 0
	for _, d in gui0:GetDescendants() do
		if d:IsA("GuiButton") and d.AbsoluteSize.X > 0 then
			local shown, a = true, d
			while a and a:IsA("GuiObject") do
				shown = shown and a.Visible
				a = a.Parent
			end
			if shown then visibleButtons += 1 end
		end
	end
	check("minimal HUD: at most 5 buttons on screen while climbing", visibleButtons <= 5, visibleButtons)
end
check("progress bar names the tower and the next gift", towerLine.Text == Lang.t("progress.sub", { n = 1, name = { key = "tower.1" }, stage = 100, gift = { key = "gift.1.name" } }), towerLine.Text)
local pctLabel = progressGui:FindFirstChildWhichIsA("TextLabel", true)
check("progress label counts to 1000", Lang.t("progress.label", { stage = 0, total = 1000, pct = 0 }):find("1000") ~= nil)
Kit.open("settings")
local dimGui = gui0:FindFirstChild("Dim")
check("panel dims the screen", dimGui ~= nil and dimGui.Visible and gui0.Panel_settings.Visible)
check("dim covers the viewport", dimGui ~= nil and math.abs(dimGui.AbsoluteSize.X - workspace.CurrentCamera.ViewportSize.X) <= 2 and math.abs(dimGui.AbsoluteSize.Y - workspace.CurrentCamera.ViewportSize.Y) <= 2, dimGui and tostring(dimGui.AbsoluteSize))
Kit.close()
check("closing the panel removes the dim", dimGui ~= nil and not dimGui.Visible and not gui0.Panel_settings.Visible)
local bloomFx = Lighting:FindFirstChildOfClass("BloomEffect")
check("effects off: bloom disabled", req("SetSetting", { key = "effects", value = false }) and waitFor(function() return bloomFx.Enabled == false end, 3))
check("effects off: ambient particles off", weatherFx ~= nil and weatherFx.Enabled == false)
check("effects on again", req("SetSetting", { key = "effects", value = true }) and waitFor(function() return bloomFx.Enabled == true and weatherFx.Enabled == true end, 3))
do
	-- lite profile (phones, graphics slider at 1..3): cheaper dressing, same worlds
	local Quality = require(Shared.Quality)
	-- (ForceLite = false pins the normal profile, whatever the graphics slider of this machine says)
	workspace:SetAttribute("ForceLite", false)
	check("normal profile by default on PC", waitFor(function() return workspace:GetAttribute("LiteProfile") == false and bloomFx.Enabled == true end, 2))
	local rate = weatherFx.Rate
	local fogBefore = Lighting.FogColor
	local skyBefore = Lighting.OutdoorAmbient
	workspace:SetAttribute("ForceLite", true)
	check("lite profile: bloom and sun rays off, half the ambient particles", waitFor(function() return workspace:GetAttribute("LiteProfile") == true and bloomFx.Enabled == false end, 2) and Lighting:FindFirstChildOfClass("SunRaysEffect").Enabled == false and math.abs(weatherFx.Rate - rate * Quality.WEATHER_RATE_LITE) < 0.01 and weatherFx.Enabled, weatherFx.Rate)
	local function dressing(): (number, number)
		local sceneryOn, hazardOn = 0, 0
		for _, root in { workspace.Towers, workspace.Decor, workspace.Lobby } do
			for _, d in root:GetDescendants() do
				if (d:IsA("PointLight") or d:IsA("ParticleEmitter")) and d.Enabled then
					local a, inStage = d.Parent, false
					while a and a ~= workspace do
						if a:GetAttribute("Kind") ~= nil then inStage = true end
						a = a.Parent
					end
					if inStage then hazardOn += 1 else sceneryOn += 1 end
				end
			end
		end
		return sceneryOn, hazardOn
	end
	task.wait(0.3)
	local sceneryLit, hazardLit = dressing()
	check("lite profile: scenery particles and lights off, obstacle ones stay", sceneryLit == 0, ("%d scenery, %d obstacle"):format(sceneryLit, hazardLit))
	check("lite profile keeps the world look (sky and ambient colours unchanged)", Lighting.FogColor == fogBefore and Lighting.OutdoorAmbient == skyBefore and Lighting:FindFirstChildOfClass("ColorCorrectionEffect").Enabled)
	workspace:SetAttribute("ForceLite", false)
	check("lite profile off again", waitFor(function() return workspace:GetAttribute("LiteProfile") == false and bloomFx.Enabled == true end, 2) and math.abs(weatherFx.Rate - rate) < 0.01)
	task.wait(0.3)
	check("normal profile: scenery particles and lights are on", (dressing()) > 0, (dressing()))
	workspace:SetAttribute("ForceLite", nil)
end
check("unknown setting rejected", not req("SetSetting", { key = "nope", value = true }))
check("coil toggle without the pass does nothing", req("SetSetting", { key = "speedCoil", value = true }) and q("state").walkSpeed == 16 and req("SetSetting", { key = "speedCoil", value = false }))

-- lounge and portal are locked before stage 100 ----------------------------------------------------
check("lounge locked before stage 100", not req("TakePerk", { id = "dash" }) and not req("SetRoam", { id = "glider" }) and not req("Travel", { stage = 0 }))
check("portal locked before stage 100", not req("EnterPortal"))

local s0 = q("state")
local coins0 = s0.coins

-- checkpoints 1..3 in order ---------------------------------------------------------------------
for k = 1, 3 do
	standOn(k)
	local ok = waitFor(function() return stageNow() == k end, 3)
	local st = q("state")
	check(("checkpoint %d reached"):format(k), ok and st.stage == k and st.at == k and st.leaderStage == k and st.best >= k, ("profile %d leaderstat %d"):format(st.stage, st.leaderStage))
	waitFor(function() return Net.state.at == k end, 2)
	check(("client State stage %d"):format(k), Net.state.stage == k and Net.state.at == k, Net.state.stage)
	task.wait(0.9)
end
local sr0 = q("state")
check("run started on leaving stage 0 and valid", sr0.runStart ~= nil and sr0.runValid == true)
check("coins per stage: 5 each for stages 1-3", sr0.coins - coins0 == 15, sr0.coins - coins0)
local pad1, pad3, pad4 = tagged("Checkpoint", 1), tagged("Checkpoint", 3), tagged("Checkpoint", 4)
check("reached pads turn green", pad1 ~= nil and pad3 ~= nil and pad4 ~= nil and sameColor(pad1.Color, DONE) and sameColor(pad3.Color, DONE) and not sameColor(pad4.Color, DONE))
local dot2, dot4 = tagged("PadDot", 2), tagged("PadDot", 4)
check("pad centre dots follow the pads", dot2 ~= nil and dot4 ~= nil and sameColor(dot2.Color, DONE) and not sameColor(dot4.Color, DONE))
local flag3, flag4 = tagged("Flag", 3), tagged("Flag", 4)
check("flag 3 raised", flag3 ~= nil and waitFor(function() return (flag3.Position - flag3:GetAttribute("High").Position).Magnitude < 0.2 end, 2) and sameColor(flag3.Color, DONE))
check("flag 4 still lowered", flag4 ~= nil and (flag4.Position - flag4:GetAttribute("Low").Position).Magnitude < 0.1)
check("beacon moved to pad 4", beaconOn(4))
local timerGui = gui0:WaitForChild("Stats"):WaitForChild("RunTimer")
local tA = timerGui.Time.Text
task.wait(0.4)
check("HUD run timer ticking", timerGui.Time.Text ~= tA and timerGui.Time.Text ~= "00:00.000", timerGui.Time.Text)

-- obstacles near the player run, far ones sleep --------------------------------------------------------
do
	local near = q("obstacle", { tag = "Mover", seconds = 1.5 }) -- the first mover is on stage 9: six stages ahead
	check("mover near the player moves", near ~= nil and near.awake and near.moved > 0.2, near and ("stage %d moved %.2f"):format(near.stage, near.moved))
	local far = q("obstacle", { tag = "Mover", seconds = 1, from = 40 })
	check("mover far from the player sleeps", far ~= nil and not far.awake and far.moved < 0.001, far and ("stage %d moved %.3f"):format(far.stage, far.moved))
	local farSpin = q("obstacle", { tag = "Spinner", seconds = 1, from = 40 })
	check("spinner far from the player sleeps", farSpin ~= nil and farSpin.turned > 0.9999, farSpin and farSpin.turned)
end

-- anti-skip: 4 ahead (pad 7) is ignored -----------------------------------------------------------
standOn(7)
task.wait(1.5)
check("pad 3 -> 7 rejected (>3 ahead)", q("state").stage == 3, q("state").stage)
-- 0.8 s rule: two pads in quick succession
standOn(4)
waitFor(function() return stageNow() == 4 end, 3)
standOn(5)
task.wait(0.35)
check("0.8 s rule blocks a 2nd checkpoint", stageNow() == 4, stageNow())
task.wait(0.8)
standOn(5)
check("pad 5 after the cooldown", waitFor(function() return stageNow() == 5 end, 3), stageNow())

-- Skip Stage (Studio: product ids 0 -> free dev skip) through the real HUD code -------------------
local skipBtn = gui0:FindFirstChild("SkipStage", true) :: TextButton?
check("Skip Stage button visible", skipBtn ~= nil and skipBtn.Visible and skipBtn.AbsoluteSize.Y >= 40, skipBtn and tostring(skipBtn.AbsoluteSize))
check("action column is compact (Skip Stage is not wider than 190 design px)", skipBtn ~= nil and skipBtn.Size.X.Offset <= 190 and skipBtn.Size.Y.Offset <= 76, skipBtn and tostring(skipBtn.Size))
do
	-- the "Studio test" skip is a Studio thing: the rules used by the HUD hide it in a published build
	local published = Rules.skipButton(Layout, 5, false, 0, Config.Products.SkipStage, false, Config.StudioFreeSkips)
	check("published build: no Studio test skip button", Config.Products.SkipStage ~= 0 or not published.visible, published.sub)
	check("published build: no Skip 10 without a product", Config.Products.Skip10 ~= 0 or not Rules.skip10Visible(Layout, 5, false, Config.Products.Skip10, false, Config.StudioFreeSkips))
end
task.wait(0.9)
Hud.skip(1)
check("Skip Stage -> stage 6", waitFor(function() return stageNow() == 6 end, 3), stageNow())
task.wait(0.8)
check("skip teleports onto pad 6", (q("state").padDist or 99) < 10, q("state").padDist)
check("run invalid after a skip", q("state").runValid == false and q("state").help.skipped == true)
waitFor(function() return timerGui.Note.Text == Lang.t("run.unranked") end, 2)
check("timer shows 'not ranked'", timerGui.Note.Text == Lang.t("run.unranked"), timerGui.Note.Text)
task.wait(0.5)
Hud.skip(10)
check("Skip 10 -> stage 16", waitFor(function() return stageNow() == 16 end, 3), stageNow())
check("AskNotifications at the stage-10 world change", waitFor(function() return askNotif == 1 end, 3) and q("state").notifAskedAt > 0, askNotif)

-- rewards ---------------------------------------------------------------------------------------
local c2 = q("state").coins
check("ClaimDaily", req("ClaimDaily"))
check("ClaimDaily twice rejected", not req("ClaimDaily"))
check("code RELEASE", req("RedeemCode", { code = " release " }))
check("code reuse rejected", not req("RedeemCode", { code = "RELEASE" }))
check("bogus code rejected", not req("RedeemCode", { code = "NOPE123" }))
check("code SKYHIGH", req("RedeemCode", { code = "SKYHIGH" }))
check("SKYHIGH gives a free skip", q("state").freeSkips == 1, q("state").freeSkips)
check("play-time reward too early rejected", not req("ClaimPlaytime", { index = 1 }))
q("rewind", 3700)
for i = 1, 4 do
	check(("play-time reward %d"):format(i), req("ClaimPlaytime", { index = i }))
end
check("play-time reward twice rejected", not req("ClaimPlaytime", { index = 1 }))
check("bad play-time index rejected", not req("ClaimPlaytime", { index = 9 }))
local s2 = q("state")
check("rewards gave coins", s2.coins > c2, ("%d -> %d"):format(c2, s2.coins))
check("free skips 1 + 1 + 2", s2.freeSkips == 4, s2.freeSkips)
waitFor(function() return Net.state.freeSkips == 4 end, 2)
Hud.skip(1) -- free skip is used before any Robux prompt
check("free skip used -> stage 17", waitFor(function() return stageNow() == 17 end, 3), stageNow())
check("free skip count 3", q("state").freeSkips == 3, q("state").freeSkips)
task.wait(1)

-- P0-1 death streak -> skip offer ----------------------------------------------------------------------
for i = 1, 4 do
	respawn()
	if i == 3 then
		check("no offer before 4 deaths", offers == 0, offers)
	end
end
check("OfferSkip fired at 4 deaths", waitFor(function() return offers == 1 end, 3), offers)
local card = gui0:FindFirstChild("Card")
check("Stuck card shown", waitFor(function() return card ~= nil and card.Visible end, 3))
local body = card and card:FindFirstChild("Body")
check("card: free skip + (Studio) skip, no ad button", body ~= nil and body:FindFirstChild("FreeSkip") ~= nil and body:FindFirstChild("PaidSkip") ~= nil and body:FindFirstChild("AdSkip") == nil)
check("card auto-hides", waitFor(function() return card ~= nil and not card.Visible end, 12))
check("still on stage 17 after deaths", stageNow() == 17 and (q("state").padDist or 99) < 10)
perfSample("stage 17 idle", 8)
local fxGui = player.PlayerGui:FindFirstChild("SkyTowerFx")
check("death flash layer exists and has faded", fxGui ~= nil and fxGui.Flash.BackgroundTransparency > 0.95, fxGui and fxGui.Flash.BackgroundTransparency)
check("sky follows the climb (stage 17 = world 2)", waitFor(function() return Atmos.world == 2 and clockNear(Ambience.Profiles[2].clock) end, 6), ("world %d clock %.2f"):format(Atmos.world, Lighting.ClockTime))
local tag = q("nametag")
check("overhead tag with stage + title", tag.exists and tag.hidden and tag.stageKey == "tag.stage" and tag.stage == 17 and tag.titleKey == "title.1", tag.stage)
local myTag = player.Character and player.Character:FindFirstChild("Head") and player.Character.Head:FindFirstChild("SkyTag")
check("tag localized on the client", myTag ~= nil and myTag.StageLine.Text == Locale.t(Lang.code, "tag.stage", { n = 17, w = 0 }), myTag and myTag.StageLine.Text)

-- P0-6 2x Coins Weekend (admin override path) + P0-4 starter pack grant ------------------------------------
local wk = q("weekend")
check("weekend doubles coin grants", wk.natural or wk.on == wk.off * 2, ("off %s on %s gained %s"):format(tostring(wk.off), tostring(wk.on), tostring(wk.gained)))
local bar = gui0:WaitForChild("EventBar")
check("event pill shown", waitFor(function() return bar.Visible end, 4))
q("weekendOff")
local stp = q("starter")
check("starter pack grant: +3 skips, trail, 30 min x2", stp.skips == 3 and stp.trail and stp.boost > 1700 and stp.mult >= 2, ("skips %d boost %d mult %d"):format(stp.skips, stp.boost, stp.mult))
check("boost pill shown", waitFor(function() return bar.Visible end, 3))
q("resetSkips")
q("clearBoosts")

-- languages: saved preference, live UI re-render, server messages translated -----------------------
local shopLabel = nil
for _, d in gui0:WaitForChild("Menu"):GetDescendants() do
	if d:IsA("TextLabel") and d.Text == Locale.t(Lang.code, "hud.shop") then shopLabel = d end
end
check("menu Shop label found", shopLabel ~= nil)
for _, code in { "de", "ru", "ja", "pt", "es", "ko", "th" } do
	check("SetLanguage " .. code, req("SetLanguage", { lang = code }))
	check(code .. " applied from saved profile", waitFor(function() return Lang.code == code and Net.state.lang == code end, 3), Lang.code)
	check(code .. " HUD re-rendered live", shopLabel ~= nil and shopLabel.Text == Locale.t(code, "hud.shop"), shopLabel and shopLabel.Text)
	local okBad, msgBad = req("RedeemCode", { code = "NOPE123" })
	check(code .. " server message translated", not okBad and msgBad == Locale.t(code, "err.invalid_code"), msgBad)
end
check("tower line translated live (th)", towerLine.Text:find(Locale.t("th", "tower.1"), 1, true) ~= nil, towerLine.Text)
check("unknown language rejected", not req("SetLanguage", { lang = "xx" }))
check("back to auto language", req("SetLanguage", { lang = "" }) and waitFor(function() return Lang.code == Lang.auto end, 3), Lang.code)

-- kill bricks kill; respawn in lobby mode ---------------------------------------------------------------
check("GoToLobby", req("GoToLobby"))
task.wait(0.8)
check("in lobby after GoToLobby", q("state").lobbyDist < 12, q("state").lobbyDist)
local signLabel = nil
for _, d in workspace:WaitForChild("Lobby"):GetDescendants() do
	if d:IsA("TextLabel") and d:GetAttribute("LocKey") == "sign.start" then signLabel = d end
end
check("world sign localized", signLabel ~= nil and signLabel.Text == Lang.t("sign.start"), signLabel and signLabel.Text)
do
	local c = char()
	local hum = c:FindFirstChildOfClass("Humanoid")
	local died = false
	hum.Died:Connect(function() died = true end)
	q("moveTo", q("killPart"))
	check("kill brick kills", waitFor(function() return died or hum.Health <= 0 end, 3), ("health %.0f"):format(hum.Health))
	check("respawned after death", waitFor(function() return player.Character ~= c and player.Character ~= nil end, 6))
	task.wait(1.2)
	local sd = q("state")
	check("respawn in lobby (lobby mode)", sd.lobbyDist < 12 and sd.stage == 17, ("dist %.1f stage %d"):format(sd.lobbyDist or -1, sd.stage))
	local fd = q("touch", "Disappear")
	check("disappearing platform vanishes, hides its icon and comes back", fd ~= nil and fd.gone and fd.back and fd.iconHidden)
	local ff = q("touch", "Falling")
	check("falling plank drops and resets", ff ~= nil and ff.gone and ff.back)
end
check("ReturnToCheckpoint", req("ReturnToCheckpoint"))
task.wait(0.8)
check("back on pad 17", (q("state").padDist or 99) < 10, q("state").padDist)

-- climb 18..100: every pad counts; rest pads (odd, after 50) raise the stage without saving -----------------
local climbStart = os.clock()
local stuck = climb(17, 56)
check("every pad 18..56 counts", stuck == nil, stuck)
do
	-- a laser gate a few stages ahead is running; wait on stage 51/53 rest-pad rules first
	local st = q("state")
	check("stage 56 saved (even pads save after 50)", st.stage == 56 and st.at == 56, ("stage %d at %d"):format(st.stage, st.at))
	task.wait(0.84)
	standOn(57)
	waitFor(function() return stageNow() == 57 end, 3)
	st = q("state")
	check("rest pad 57: level goes up, checkpoint stays at 56", st.at == 57 and st.stage == 56 and st.leaderStage == 57, ("stage %d at %d"):format(st.stage, st.at))
	local rest57 = tagged("Checkpoint", 57)
	check("rest pad is marked (no flag, Save = false)", rest57 ~= nil and rest57:GetAttribute("Save") == false and tagged("Flag", 57) == nil and tagged("Flag", 56) ~= nil)
	local coinsBefore = st.coins
	respawn()
	st = q("state")
	check("death on a rest pad: back to the last save (56)", st.stage == 56 and st.at == 56 and (st.padDist or 99) < 10, ("stage %d at %d dist %s"):format(st.stage, st.at, tostring(st.padDist)))
	task.wait(0.5)
	standOn(57)
	waitFor(function() return stageNow() == 57 end, 3)
	check("re-reaching a rest pad pays no coins twice", q("state").coins == coinsBefore, ("%d -> %d"):format(coinsBefore, q("state").coins))
	local laser = q("obstacle", { tag = "Laser", seconds = 4.2, from = 50 })
	check("laser gate switches on and off", laser == nil or not laser.awake or laser.switched, laser and ("stage %d awake %s"):format(laser.stage, tostring(laser.awake)))
end
stuck = climb(57, 100)
print(("[TEST] c INFO climb took %.1f s"):format(os.clock() - climbStart))
check("every pad 58..100 counts", stuck == nil, stuck)
local sw = q("state")
check("stage 100 reached", sw.stage == 100 and sw.at == 100 and sw.leaderStage == 100, sw.stage)
check("Wins +1", sw.wins == 1 and sw.leaderWins == 1, sw.wins)
check("Win event received (tower 1)", waitFor(function() return winEvents == 1 end, 3) and lastWin.tower == 1, winEvents)
check("win panel opens with the portal button", waitFor(function()
	local panel = gui0:FindFirstChild("Panel_win")
	local btn = panel and panel:FindFirstChild("Portal", true)
	return panel ~= nil and panel.Visible and btn ~= nil and btn.Visible
end, 6))
check("skipped run: no ranked time", sw.bestRunMs == 0 and lastWin and lastWin.newBest == false and q("state").runFinalMs ~= nil, sw.bestRunMs)
check("gift 1 (stage 100): Summit Flame trail", sw.gifts["1"] == true and sw.trails.summit == true and giftEvents[1] == 1 and lastWin.gift == 1, table.concat(giftEvents, ","))
check("summit sky = world 10", waitFor(function() return Atmos.world == 10 and clockNear(Ambience.Profiles[10].clock) end, 8), ("world %d clock %.2f"):format(Atmos.world, Lighting.ClockTime))
check("ambient particles changed with the world", weatherFx ~= nil and weatherFx.Rate ~= weatherRate1, weatherFx and weatherFx.Rate)
check("top of tower 1: flag 100 raised, no beacon before the portal", tagged("Flag", 100) ~= nil and sameColor(tagged("Flag", 100).Color, DONE) and beacon ~= nil and beacon.Position.Y < -100)
task.wait(0.5)
check("title after 1 win", q("nametag").titleKey == "title.2")
check("progress line: next gift is at 200", waitFor(function() return towerLine.Text == Lang.t("progress.sub", { n = 1, name = { key = "tower.1" }, stage = 200, gift = { key = "gift.2.name" } }) end, 3), towerLine.Text)
Kit.close()
check("Portal button on the HUD at a summit; nothing to skip there", waitFor(function()
	local b = gui0:FindFirstChild("Portal", true)
	return b ~= nil and b.Visible and skipBtn ~= nil and not skipBtn.Visible
end, 3))
perfSample("summit idle", 6)

-- fall catcher ----------------------------------------------------------------------------------------
q("moveTo", CFrame.new(q("padTop", 100) - Vector3.new(0, 60, 0)))
check("fall catcher returns you to pad 100", waitFor(function() return (q("state").padDist or 99) < 10 end, 4), q("state").padDist)

-- Winner's Lounge: free items -----------------------------------------------------------------------------
do
	check("teleporter pedestal opens the travel panel", req("TakePerk", { id = "teleport" }) and waitFor(function() return Kit.current() == "travel" end, 3))
	local travel = gui0:FindFirstChild("Panel_travel")
	local count = 0
	if travel then
		for _, d in travel:GetDescendants() do
			if d:IsA("TextButton") and d.Name:match("^To_%d+$") then count += 1 end
		end
	end
	check("travel panel lists the lobby + the 10 worlds reached", count == #Perks.travelTargets(100) and count == 11, count)
	Kit.close()
	check("ability: dash on", req("TakePerk", { id = "dash" }) and waitFor(function() return player:GetAttribute("Dash") == true end, 3))
	check("Dash button on the HUD", waitFor(function()
		local b = gui0:FindFirstChild("Dash", true)
		return b ~= nil and b.Visible
	end, 3))
	local root = char():WaitForChild("HumanoidRootPart")
	check("dash: a burst of speed, then a cooldown", LocalFx.dash() and waitFor(function() return Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 35 end, 0.5) and not LocalFx.dash() and LocalFx.dashCooldown() > 1)
	task.wait(1)
	q("standOn", 100)
	check("ability: triple jump = 2 air jumps", req("TakePerk", { id = "triplejump" }) and waitFor(function() return player:GetAttribute("AirJumps") == 2 end, 3))
	check("abilities switch off again", req("TakePerk", { id = "dash" }) and req("TakePerk", { id = "triplejump" }) and waitFor(function() return player:GetAttribute("Dash") == false and player:GetAttribute("AirJumps") == 0 end, 3))
	check("glow skin: a Highlight on the character", req("TakePerk", { id = "glow_cyan" }) and waitFor(function() return q("state").glow == true end, 3))
	check("rainbow glow needs the stage-700 gift", not req("TakePerk", { id = "glow_rainbow" }))
	check("jump effect selected", req("TakePerk", { id = "jumpfx_ring" }) and q("state").jumpFx == "jumpfx_ring")
	check("free trail taken and equipped", req("TakePerk", { id = "lounge_neon" }) and q("state").trails.lounge_neon == true and q("state").equippedTrail == "lounge_neon")
	check("free aura taken and equipped", req("TakePerk", { id = "lounge_stars" }) and q("state").effects.lounge_stars == true and q("state").equippedEffect == "lounge_stars")
	-- explore mode: glider
	check("glider on = explore mode", req("TakePerk", { id = "glider" }) and waitFor(function() return player:GetAttribute("Roam") == "glider" and q("state").roam == "glider" end, 3))
	check("Stop exploring button on the HUD", waitFor(function()
		local b = gui0:FindFirstChild("StopExploring", true)
		return b ~= nil and b.Visible
	end, 3))
	q("moveTo", CFrame.new(q("padTop", 100) + Vector3.new(0, 40, 0)))
	task.wait(1.2)
	local vy = char().HumanoidRootPart.AssemblyLinearVelocity.Y
	-- (read after a physics step: one frame of gravity, 3.3 studs/s, is on top of the cap)
	check("glider caps the falling speed", vy > -Perks.GLIDE_FALL_SPEED - 4.5 and vy < 0, ("%.1f"):format(vy))
	check("explore mode off: back on your checkpoint", req("SetRoam", { id = "" }) and waitFor(function() return player:GetAttribute("Roam") == nil and (q("state").padDist or 99) < 10 end, 4), q("state").padDist)
	check("cloud on, then off", req("TakePerk", { id = "cloud" }) and waitFor(function() return player:GetAttribute("Roam") == "cloud" end, 3) and req("SetRoam", { id = "" }) and waitFor(function() return player:GetAttribute("Roam") == nil end, 3))
	task.wait(1)
end

-- portal to tower 2 (stages 101..200) ------------------------------------------------------------------
do
	check("tower 2 is pre-built while you stand on the summit", waitFor(function() return table.find(q("state").towers, 2) ~= nil end, 25), table.concat(q("state").towers, ","))
	check("pad 101 does not count from the summit (portal first)", (function()
		standOn(101)
		task.wait(1.6)
		return q("state").at == 100
	end)())
	check("EnterPortal", req("EnterPortal"))
	check("arrived on the base of tower 2", waitFor(function()
		local st = q("state")
		return st.base == true and st.stage == 100 and (st.spawnDist or 99) < 10 and st.rootPos.X > Layout.TOWER_SPACING - 200
	end, 10), tostring(q("state").rootPos))
	check("TowerEnter event", waitFor(function() return towerEnters == 1 end, 3), towerEnters)
	check("sky of tower 2 (Sunset mood)", waitFor(function() return Atmos.tower == 2 end, 6) and TowerStyle.mood(2).key == "2", Atmos.tower)
	check("progress bar switches to tower 2", waitFor(function() return towerLine.Text:find(Lang.t("tower.2"), 1, true) ~= nil end, 3), towerLine.Text)
	check("beacon on pad 101 (tower 2)", beaconOn(101))
	check("tower 2 palette differs from tower 1", (function()
		local a, b = Config.theme(1, 2).platform, Config.theme(2, 2).platform
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) > 0.1
	end)())
	task.wait(0.9)
	local stuck2 = climb(100, 103)
	local st = q("state")
	check("pads 101..103 count; 102 saves, 103 is a rest pad", stuck2 == nil and st.at == 103 and st.stage == 102 and st.base == false, ("stage %d at %d"):format(st.stage, st.at))
	check("coins per stage grow with the worlds (25 at stage 101)", Rules.coinsForStage(101) == 25)
	local c = q("census")
	check("two towers in Workspace for a player at the start of tower 2", #c.towers == 2 and c.towers[1] == 1 and c.towers[2] == 2, table.concat(c.towers, ","))
	-- summit of tower 2: gift 2 (the shoulder pet)
	q("warp", 198)
	task.wait(0.9)
	stuck2 = climb(198, 200)
	st = q("state")
	check("stage 200 reached (tower 2 summit)", stuck2 == nil and st.stage == 200 and st.wins == 1, ("stage %d wins %d"):format(st.stage, st.wins))
	check("gift 2 (stage 200): the Cloud Buddy pet rides on your shoulder", st.gifts["2"] == true and waitFor(function() return q("state").pet == true end, 3) and table.find(giftEvents, 2) ~= nil)
	check("Win event for tower 2 (no extra win)", waitFor(function() return winEvents == 2 end, 3) and lastWin.tower == 2 and lastWin.gift == 2, winEvents)
	check("tower 3 pre-built at the summit of tower 2", waitFor(function() return table.find(q("state").towers, 3) ~= nil end, 25), table.concat(q("state").towers, ","))
	check("portal to tower 3", req("EnterPortal") and waitFor(function() return q("state").base == true and q("state").rootPos.X > 2 * Layout.TOWER_SPACING - 200 end, 10))
	-- an empty tower is released
	task.wait(1)
	q("sweep", 1)
	task.wait(2.5)
	q("sweep", 1)
	task.wait(1)
	local towers = q("state").towers
	check("the tower nobody is on is destroyed (tower 2 gone, 1 and 3 stay)", table.find(towers, 2) == nil and table.find(towers, 1) ~= nil and table.find(towers, 3) ~= nil, table.concat(towers, ","))
	q("sweep", 75)
	-- the very top
	q("warp", 998)
	task.wait(0.9)
	stuck2 = climb(998, 1000)
	st = q("state")
	check("stage 1000 reached", stuck2 == nil and st.stage == 1000 and st.best == 1000, st.stage)
	check("gift 10 (stage 1000): the Sky Crown and the Conqueror title", st.gifts["10"] == true and waitFor(function() return q("state").crown == true end, 3) and q("nametag").titleKey == "title.conqueror")
	check("nothing beyond 1000: no skip, no portal", not req("EnterPortal") and Rules.skipTarget(Layout, 1000, 1, true) == nil and skipBtn ~= nil and not skipBtn.Visible)
	check("progress: no next gift after the last one", waitFor(function() return towerLine.Text == Lang.t("progress.sub_done", { n = 10, name = { key = "tower.10" } }) end, 3), towerLine.Text)
	check("sky of tower 10", waitFor(function() return Atmos.tower == 10 end, 6), Atmos.tower)
	q("sweep", 1)
	task.wait(2.5)
	q("sweep", 1)
	task.wait(1)
	local c10 = q("census")
	check("at the top of tower 10 only towers 1 and 10 are left in Workspace", #c10.towers == 2 and c10.towers[1] == 1 and c10.towers[2] == 10, table.concat(c10.towers, ","))
	q("sweep", 75)
	perfSample("stage 1000 idle", 6)
	-- teleporter
	check("travel to a world not on the grid rejected", not req("Travel", { stage = 45 }) and not req("Travel", { stage = 1010 }))
	check("travel to world 5 of tower 1 (stage 40)", req("Travel", { stage = 40 }) and waitFor(function()
		local s2x = q("state")
		return s2x.stage == 40 and s2x.at == 40 and (s2x.padDist or 99) < 10
	end, 12), q("state").stage)
	check("best stage kept after travelling back", q("state").best == 1000 and q("state").help.travelled == true)
end

-- shop zone (world entrance at stage 40): power-ups bought with coins -------------------------------------
do
	q("clearBoosts")
	q("coins", 30)
	local okPoor = req("BuyPower", { id = "speed" })
	check("shop: not enough coins rejected, nothing charged", not okPoor and q("state").coins == 30)
	q("coins", 2000)
	check("shop: unknown item rejected", not req("BuyPower", { id = "rocket" }))
	check("shop: speed coil for 3 min -> WalkSpeed 24", req("BuyPower", { id = "speed" }) and waitFor(function() return q("state").walkSpeed == Config.SpeedCoilWalkSpeed end, 3) and q("state").coins == 2000 - 60, q("state").walkSpeed)
	check("shop: gravity coil applied", req("BuyPower", { id = "gravity" }) and waitFor(function() return q("state").gravityCoil == true end, 3))
	check("shop: double jump = 1 air jump", req("BuyPower", { id = "doublejump" }) and waitFor(function() return player:GetAttribute("AirJumps") == 1 end, 3))
	check("power-up chips on the HUD", waitFor(function()
		local chip = gui0:FindFirstChild("Chip_speed", true)
		return chip ~= nil and chip.Visible
	end, 3))
	check("power-ups make the run assisted", q("state").runValid == false and q("state").help.coil == true and q("state").help.powerup == true)
	-- shield
	check("shop: shields are charges, max 3", req("BuyPower", { id = "shield" }) and req("BuyPower", { id = "shield" }) and req("BuyPower", { id = "shield" }) and not req("BuyPower", { id = "shield" }) and q("state").charges.shield == 3)
	local c = char()
	local hum = c:FindFirstChildOfClass("Humanoid")
	q("moveTo", q("killPart"))
	check("shield absorbs a kill brick", waitFor(function() return shieldEvents >= 1 end, 3) and hum.Health > 0 and q("state").charges.shield < 3, q("state").charges.shield)
	req("ReturnToCheckpoint")
	task.wait(1.8)
	-- magnet
	local coin = q("coinNear", 9)
	if coin and not coin.collected then
		q("hold", coin.spot)
		task.wait(0.6)
		check("no magnet: a coin 9 studs away is not collected", q("coinTaken", coin.id) == false)
		check("shop: magnet pulls the coin in", req("BuyPower", { id = "magnet" }) and waitFor(function() return q("coinTaken", coin.id) == true end, 3))
		q("hold", nil)
	else
		check("magnet test has a coin to use", false, coin and "already collected")
	end
	req("ReturnToCheckpoint")
	task.wait(1)
	-- skip with coins
	local before = q("state")
	check("shop: skip stage for 150 coins", req("BuyPower", { id = "skip" }) and waitFor(function() return stageNow() == before.at + 1 end, 3) and q("state").coins == before.coins - 150, stageNow())
	task.wait(1)
	-- pocket checkpoint
	check("pocket checkpoint needs a charge", not req("PlacePocket"))
	check("shop: pocket checkpoint bought", req("BuyPower", { id = "pocket" }) and q("state").charges.pocket == 1)
	check("Pocket button on the HUD", waitFor(function()
		local b = gui0:FindFirstChild("Pocket", true)
		return b ~= nil and b.Visible
	end, 3))
	local stx = q("state")
	local spot = CFrame.new(q("padTop", stx.stage) + Vector3.new(4, 3, 0))
	q("moveTo", spot)
	task.wait(0.8)
	check("pocket checkpoint placed where you stand", req("PlacePocket") and q("state").pocket == true and q("state").charges.pocket == 0)
	respawn()
	local after = q("state")
	check("respawn on the pocket checkpoint", (after.rootPos - spot.Position).Magnitude < 6 and (after.spawnDist or 99) < 6, tostring(after.rootPos))
	q("clearBoosts")
	check("boosts cleared: back to the classic character", waitFor(function() return q("state").walkSpeed == 16 and player:GetAttribute("AirJumps") == 0 end, 3))
end

-- wind: standing in a wind zone pushes the character sideways -----------------------------------------------
do
	local zone = q("obstacle", { tag = "Wind", seconds = 0.2, from = 36 })
	if zone then
		q("warp", math.floor((zone.stage - 1) / 10) * 10)
		task.wait(1)
		q("moveTo", zone.cf * CFrame.new(0, -zone.size.Y / 2 + 22, 0))
		local root = char():WaitForChild("HumanoidRootPart")
		task.wait(0.1)
		local start = root.Position
		local t = os.clock()
		task.wait(0.7)
		local elapsed = os.clock() - t
		local moved = root.Position - start
		local speed = Vector3.new(moved.X, 0, moved.Z).Magnitude / elapsed
		check("wind carries you sideways in the air (at most 60% of WalkSpeed)", speed > 2.5 and speed <= Layout.Physics.walkSpeed * Layout.WIND_MAX_SHARE + 1, ("%.1f studs/s"):format(speed))
		task.wait(1.5)
	else
		check("a wind zone exists in tower 1", false)
	end
end

-- rebirth -------------------------------------------------------------------------------------------
check("Rebirth (from anywhere past stage 100)", (function()
	q("warp", 100)
	task.wait(1)
	return req("Rebirth")
end)())
task.wait(1)
local sr = q("state")
check("rebirth -> stage 0, wins / best / gifts kept", sr.stage == 0 and sr.at == 0 and sr.wins == 1 and sr.leaderStage == 0 and sr.best == 1000 and sr.gifts["10"] == true, ("stage %d wins %d best %d"):format(sr.stage, sr.wins, sr.best))
check("rebirth twice rejected", not req("Rebirth"))
check("rebirth lowers the flags and restores the pads", waitFor(function()
	local f, pd = tagged("Flag", 2), tagged("Checkpoint", 2)
	return f ~= nil and pd ~= nil and (f.Position - f:GetAttribute("Low").Position).Magnitude < 0.1 and pad2Base ~= nil and sameColor(pd.Color, pad2Base)
end, 6))
check("sky back to world 1 after rebirth", waitFor(function() return Atmos.world == 1 and Atmos.tower == 1 and clockNear(Ambience.Profiles[1].clock) end, 8), ("world %d clock %.2f"):format(Atmos.world, Lighting.ClockTime))
check("rebirth re-arms a ranked run", q("state").runValid == true and q("state").runStart == nil)

-- P0-2 a clean (unassisted) climb sets a personal best --------------------------------------------------
local fastStuck = climb(0, 100, 3)
check("clean climb reached 100", fastStuck == nil and stageNow() == 100, fastStuck)
local sb = q("state")
check("personal best saved (nothing helped)", sb.bestRunMs > 0 and sb.runValid == true and lastWin and lastWin.newBest == true and lastWin.runMs == sb.bestRunMs and next(sb.help) == nil, sb.bestRunMs)
check("second win: Wins 2, no gift twice", sb.wins == 2 and #giftEvents == 3, ("wins %d gifts %s"):format(sb.wins, table.concat(giftEvents, ",")))

print(("[TEST] c PERF whole run: %d remote events, %d bytes of payload, biggest State push %d bytes"):format(remoteEvents, remoteBytes, stateBytes))
check("BUDGET State push <= " .. BUDGET.stateBytes .. " bytes", stateBytes > 0 and stateBytes <= BUDGET.stateBytes, stateBytes)
task.wait(2)
check("no client errors", #clientErrors == 0, table.concat(clientErrors, " || "))
q("Done", table.concat(lines, "\n"))
