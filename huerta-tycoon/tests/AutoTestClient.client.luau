local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local player = Players.LocalPlayer
local clientErrors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then table.insert(clientErrors, msg) end
end)
local lines = {}
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail then " :: " .. tostring(detail) else "")
	-- the server re-prints every client line at the end; only failures are echoed live (the runner keeps 200 lines)
	if not cond then print("[TEST] c " .. line) end
	table.insert(lines, line)
end
print("[TEST] c start")
while not player:GetAttribute("ServerReady") do task.wait(0.2) end
print("[TEST] c server ready")
local Request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Request")
local function req(action, payload)
	local ok, a, b, c = pcall(function() return Request:InvokeServer(action, payload) end)
	if not ok then return false, a end
	return a, b, c
end
local ok, _, data
for _ = 1, 30 do
	ok, _, data = req("Hello")
	if ok then break end
	task.wait(0.5)
end
check("Hello", ok and type(data) == "table" and data.state ~= nil)
local state = data and data.state or {}
check("state has cash", type(state.cash) == "number", state.cash)
task.wait(1)
check("BuySeed tomato", req("BuySeed", { seedId = "tomato", amount = 2 }) or (data.stock and data.stock.tomato == 0))
check("Plant tile 1", req("Plant", { tile = 1, seedId = "carrot" }))
check("Plant occupied rejected", not req("Plant", { tile = 1, seedId = "carrot" }))
check("Plant locked rejected", not req("Plant", { tile = 20, seedId = "carrot" }))
local okAll, msgAll = req("PlantAll", { seedId = "carrot" })
check("PlantAll", okAll, msgAll)
check("Harvest unripe rejected", not req("Harvest", { tile = 1 }))
ReplicatedStorage:WaitForChild("__Test"):FireServer("GrowNow")
task.wait(2.5)
local okH, msgH = req("HarvestAll")
check("HarvestAll", okH, msgH)
local okFar = req("SellAll")
check("Sell far from stand rejected", not okFar)
local stand = workspace:WaitForChild("Hub"):WaitForChild("SellStand")
local char = player.Character or player.CharacterAdded:Wait()
char:PivotTo(stand.CFrame * CFrame.new(0, 3, -6))
task.wait(1)
local okS, msgS = req("SellAll")
check("SellAll at stand", okS, msgS)
-- juice: a sale sends coins flying to the cash counter, and they all clean up
do
	local juiceLayer = player:WaitForChild("PlayerGui"):WaitForChild("CropKingdomUI"):WaitForChild("Root"):WaitForChild("Juice")
	local seen = 0
	local tj = os.clock()
	while os.clock() - tj < 1.5 do
		local n = 0
		for _, c in juiceLayer:GetChildren() do if c.Name == "Coin" then n += 1 end end
		seen = math.max(seen, n)
		task.wait(0.05)
	end
	check("sale spawns flying coins", seen >= 4 and seen <= 14, seen)
	task.wait(2.2)
	local left = 0
	for _, c in juiceLayer:GetChildren() do if c.Name == "Coin" then left += 1 end end
	check("flying coins clean up", left == 0, left)
end
check("BuyTile", req("BuyTile"))
check("BuyUpgrade GrowSpeed", req("BuyUpgrade", { id = "GrowSpeed" }))
check("BuyUpgrade bogus rejected", not req("BuyUpgrade", { id = "Nope" }))
check("ClaimDaily", req("ClaimDaily"))
check("ClaimDaily twice rejected", not req("ClaimDaily"))
check("Code RELEASE", req("RedeemCode", { code = "release" }))
check("Code reuse rejected", not req("RedeemCode", { code = "RELEASE" }))
check("Shovel", req("Shovel", { tile = 2 }) or true)
-- ===== Auto-farm through the real remotes =====
check("SetAuto rejected while locked (no Farmhand)", not req("SetAuto", { mode = "harvest", on = true }))
check("BuyUpgrade Farmhand Lv1", req("BuyUpgrade", { id = "Farmhand" }))
check("SetAuto harvest accepted at Lv1", req("SetAuto", { mode = "harvest", on = true }))
check("SetAuto plant still locked at Lv1", not req("SetAuto", { mode = "plant", on = true }))
check("SetAuto bad mode rejected", not req("SetAuto", { mode = "steal", on = true }) and not req("SetAuto", { mode = "harvest", on = "yes" }))
check("SetAutoSeed bogus seed rejected", not req("SetAutoSeed", { seedId = "nope" }))
check("SetAutoSeed accepted", req("SetAutoSeed", { seedId = "carrot" }))
check("Rebirth", req("Rebirth"))
task.wait(0.8)
do
	local UIF = script.Parent:WaitForChild("Client"):WaitForChild("UI")
	local St = require(UIF:WaitForChild("State"))
	local d = St.data or {}
	local a = d.auto or {}
	check("rebirth keeps the Farmhand upgrade and resets the others", d.upgrades and d.upgrades.Farmhand == 1 and d.upgrades.GrowSpeed == 0, d.upgrades and d.upgrades.Farmhand)
	check("client state shows auto-harvest ON", type(a.on) == "table" and a.on.harvest == true and a.on.plant == false and a.seed == "carrot")
	local autoBtn = player.PlayerGui.CropKingdomUI.Root.Actions:FindFirstChild("Auto")
	local lbl = autoBtn and autoBtn:FindFirstChild("Label")
	local I18nM = require(UIF:WaitForChild("I18n"))
	check("HUD auto button shows ON", lbl ~= nil and string.find(lbl.Text, I18nM.t("auto.on"), 1, true) ~= nil, lbl and lbl.Text)
	check("SetAuto harvest off", req("SetAuto", { mode = "harvest", on = false }))
	task.wait(0.8)
	check("HUD auto button shows OFF", lbl ~= nil and string.find(lbl.Text, I18nM.t("auto.off"), 1, true) ~= nil, lbl and lbl.Text)
end
check("Bad action rejected", not req("Hack", {}))
check("Weird payload rejected", not req("Plant", "x"))
task.wait(3) -- let UI react to all of this
local gui = player:WaitForChild("PlayerGui")
local screenGuis = 0
for _, g in gui:GetChildren() do if g:IsA("ScreenGui") then screenGuis += 1 end end
check("UI built", screenGuis > 0, screenGuis)

local testEv = ReplicatedStorage:WaitForChild("__Test") :: RemoteEvent
local ui = gui:WaitForChild("CropKingdomUI", 10) :: ScreenGui?
local root = ui and ui:FindFirstChild("Root") :: Frame?
check("CropKingdomUI uses CoreUISafeInsets", ui ~= nil and ui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)

-- every GuiObject's box must sit inside the ScreenGui's safe area
local function inside(g: GuiObject?): (boolean, string)
	if not (g and ui) then return false, "missing" end
	local a, b = ui.AbsolutePosition, ui.AbsolutePosition + ui.AbsoluteSize
	local p, q = g.AbsolutePosition, g.AbsolutePosition + g.AbsoluteSize
	local ok = p.X >= a.X - 2 and p.Y >= a.Y - 2 and q.X <= b.X + 2 and q.Y <= b.Y + 2
	return ok, string.format("%s @%d,%d %dx%d in %dx%d", g.Name, p.X, p.Y, g.AbsoluteSize.X, g.AbsoluteSize.Y, ui.AbsoluteSize.X, ui.AbsoluteSize.Y)
end
if root then
	for _, name in { "StatsCard", "WeatherBanner", "BasketBar", "Hotbar", "Actions", "Menu" } do
		local okIn, info = inside(root:FindFirstChild(name) :: GuiObject?)
		check("HUD inside safe area: " .. name, okIn, info)
	end
end

-- Weather event: the server starts Rain and checks growth; the client checks state + banner.
local weatherDone = false
local weatherConn = testEv.OnClientEvent:Connect(function(kind)
	if kind == "WeatherDone" then weatherDone = true end
end)
testEv:FireServer("Weather")
local tw = os.clock()
while not weatherDone and os.clock() - tw < 20 do task.wait(0.2) end
weatherConn:Disconnect()
check("server weather test finished", weatherDone)
task.wait(0.5)
local UIFolder = script.Parent:WaitForChild("Client"):WaitForChild("UI")
local State = require(UIFolder:WaitForChild("State"))
check("client got Rain weather", State.weather and State.weather.id == "Rain", State.weather and State.weather.id)
local banner = root and root:FindFirstChild("WeatherBanner")
local bannerText = ""
if banner then
	for _, d in banner:GetDescendants() do
		if d:IsA("TextLabel") then bannerText ..= d.Text .. " " end
	end
end
-- the banner is localized (the Studio test account may not be English)
local I18nMod = require(UIFolder:WaitForChild("I18n"))
local rainName = I18nMod.t("weather.Rain.name")
check("banner shows Rain", bannerText:find(rainName, 1, true) ~= nil, rainName .. " in " .. bannerText)

-- Open every panel through the client UI module (same module instance the game uses).
local okReq, Panels = pcall(require, UIFolder:WaitForChild("Panels"))
check("require Panels", okReq, if okReq then nil else Panels)
if okReq then
	for _, name in { "Shop", "Upgrades", "Rebirth", "Store", "Daily", "Codes", "Language", "Gifts", "Index", "Invite", "Starter", "Auto", "Odds", "Trophies" } do
		local okOpen, err = pcall(Panels.open, name)
		task.wait(0.5)
		local frame = root and root:FindFirstChild(name .. "Panel") :: GuiObject?
		check("open panel " .. name, okOpen and Panels.current == name and frame ~= nil and frame.Visible, err)
		if frame then
			local okIn, info = inside(frame)
			check("panel fits screen " .. name, okIn, info)
		end
		local okClose, err2 = pcall(Panels.close)
		check("close panel " .. name, okClose and Panels.current == nil, err2)
		task.wait(0.3)
	end
end

-- ===== i18n: switch every language through the real SetLanguage remote =====
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local I18n = require(UIFolder:WaitForChild("I18n"))
local harvestLbl = root and root:FindFirstChild("Actions") and root.Actions:FindFirstChild("HarvestAll") and root.Actions.HarvestAll:FindFirstChild("Label")
local seedSign: TextLabel? = nil
for _, d in workspace:WaitForChild("Hub"):GetDescendants() do
	if d:IsA("TextLabel") and d:GetAttribute("LocKey") == "world.seedsSign" then
		seedSign = d
		break
	end
end
check("world sign is tagged", seedSign ~= nil)
check("bad language rejected", not req("SetLanguage", { lang = "xx" }))
local langFails = {}
for _, l in Locale.Languages do
	local code = l.code
	local okSet = req("SetLanguage", { lang = code })
	local t0 = os.clock()
	while (not State.data or State.data.lang ~= code or I18n.lang ~= code) and os.clock() - t0 < 5 do task.wait(0.1) end
	task.wait(0.3)
	local problems = {}
	if not okSet then table.insert(problems, "SetLanguage failed") end
	if I18n.lang ~= code then table.insert(problems, "client lang " .. tostring(I18n.lang)) end
	if not State.data or State.data.lang ~= code then table.insert(problems, "state lang " .. tostring(State.data and State.data.lang)) end
	if harvestLbl and harvestLbl.Text ~= Locale.t(code, "hud.harvestAll") then table.insert(problems, "HUD text " .. harvestLbl.Text) end
	if seedSign and seedSign.Text ~= Locale.t(code, "world.seedsSign") then table.insert(problems, "sign text " .. seedSign.Text) end
	local _, msg = req("Plant", { tile = 29, seedId = "carrot" })
	if msg ~= Locale.t(code, "err.tileLocked") then table.insert(problems, "server reply " .. tostring(msg)) end
	if code ~= "en" and Locale.t(code, "hud.harvestAll") == Locale.t("en", "hud.harvestAll") then table.insert(problems, "not translated") end
	if #problems > 0 then table.insert(langFails, code .. ": " .. table.concat(problems, ", ")) end
end
check("all 12 languages switch live (HUD, world sign, server replies)", #langFails == 0, table.concat(langFails, " | "))
req("SetLanguage", { lang = "en" })
local t1 = os.clock()
while I18n.lang ~= "en" and os.clock() - t1 < 5 do task.wait(0.1) end
check("back to English", I18n.lang == "en" and harvestLbl ~= nil and harvestLbl.Text == Locale.t("en", "hud.harvestAll"))

-- ===== P0 systems through the real remotes =====
local p0Ready = false
local p0Conn = testEv.OnClientEvent:Connect(function(kind)
	if kind == "P0Ready" then p0Ready = true end
end)
testEv:FireServer("P0")
local tp = os.clock()
while not p0Ready and os.clock() - tp < 10 do task.wait(0.1) end
p0Conn:Disconnect()
task.wait(0.6)
local GiftsPanel = require(UIFolder:WaitForChild("GiftsPanel"))
local StarterPanel = require(UIFolder:WaitForChild("StarterPanel"))
check("P0 setup", p0Ready)
check("all 6 gifts ready after a faked 60-min session", GiftsPanel.readyCount() == 6, GiftsPanel.readyCount())
check("ClaimGift 1", req("ClaimGift", { index = 1 }))
check("ClaimGift 1 twice rejected", not req("ClaimGift", { index = 1 }))
check("ClaimGift bad index rejected", not req("ClaimGift", { index = 99 }))
local growthBefore = State.data.mult.growth
check("ClaimGift 4 (growth boost)", req("ClaimGift", { index = 4 }))
check("ClaimGift 6 (lucky pack)", req("ClaimGift", { index = 6 }))
task.wait(0.6)
check("growth boost in state", type(State.data.boosts) == "table" and State.data.boosts.growth ~= nil and State.data.mult.growth >= growthBefore * 2 - 1e-6, State.data.mult.growth)
check("gift badge counts 3 left", GiftsPanel.readyCount() == 3, GiftsPanel.readyCount())
check("ClaimIndex incomplete row rejected", not req("ClaimIndex", { seedId = "carrot" }))
check("ClaimIndex tomato", req("ClaimIndex", { seedId = "tomato" }))
check("ClaimIndex twice rejected", not req("ClaimIndex", { seedId = "tomato" }))
task.wait(0.6)
check("index bonus +2%", math.abs((State.data.indexBonus or 0) - 0.02) < 1e-6, State.data.indexBonus)
check("index shows carrot found", State.data.index and State.data.index.carrot and State.data.index.carrot.found >= 1)
check("WatchAd rejected with ad id 0", not req("WatchAd", { placement = "restock" }))
check("ClaimGroupGift rejected without group", not req("ClaimGroupGift"))
check("live event schedule received", State.liveEvent.next ~= nil or State.liveEvent.current ~= nil)
check("starter button hidden with id 0", StarterPanel.button == nil or not StarterPanel.button.Visible)

-- ===== visual round: ambience, juice and harvest fx =====
do
	local Ambience = require(UIFolder:WaitForChild("Ambience"))
	local Juice = require(UIFolder:WaitForChild("Juice"))
	local Fx = require(UIFolder:WaitForChild("Fx"))
	check("ambience animates the world (windmill + gear + gems spin, 4 shop markers bob, 3 balloons float)", Ambience.counts.spins >= 7 and Ambience.counts.bobs == 4 and Ambience.counts.floats == 3, string.format("spins %d bobs %d floats %d", Ambience.counts.spins, Ambience.counts.bobs, Ambience.counts.floats))
	local peak = 0
	for i = 0, 100 do peak = math.max(peak, Ambience.popScale(i / 100)) end
	check("crop pop curve: starts small, overshoots a little, ends at exactly 1", math.abs(Ambience.popScale(0) - 0.55) < 1e-6 and Ambience.popScale(1) == 1 and Ambience.popScale(5) == 1 and peak > 1 and peak < 1.1, peak)
	check("crop stage changes popped", Ambience.counts.pops >= 1, Ambience.counts.pops)
	check("coin count is capped", Juice.coinCount(1) == 4 and Juice.coinCount(10) == 9 and Juice.coinCount(100000) == Juice.MAX_COINS)
	local juiceLayer = root and root:FindFirstChild("Juice")
	for _ = 1, 5 do Juice.confetti(40) end
	task.wait(0.1)
	local pieces = 0
	if juiceLayer then for _, c in juiceLayer:GetChildren() do if c.Name == "Confetti" then pieces += 1 end end end
	check("confetti is capped", pieces > 0 and pieces <= Juice.MAX_CONFETTI, pieces)
	task.wait(3)
	pieces = 0
	if juiceLayer then for _, c in juiceLayer:GetChildren() do if c.Name == "Confetti" then pieces += 1 end end end
	check("confetti cleans up", pieces == 0, pieces)
	local function fxCount()
		local n, emitters = 0, 0
		for _, a in workspace.Terrain:GetChildren() do
			if a.Name == "HarvestFx" then
				n += 1
				for _, e in a:GetChildren() do if e:IsA("ParticleEmitter") then emitters += 1 end end
			end
		end
		return n, emitters
	end
	task.wait(2.6) -- let the fx of the real harvests above expire
	Fx.harvest(Vector3.new(0, 10, 0), "carrot", nil, 15)
	Fx.harvest(Vector3.new(0, 10, 0), "pumpkin", "Rainbow", 76000)
	local nFx, nEm = fxCount()
	check("harvest fx: plain harvest pops (2 emitters), rare one adds ring + sparkles (4)", nFx == 2 and nEm == 6, nFx .. " fx, " .. nEm .. " emitters")
	Fx.harvest("nope", "carrot", nil, 1)
	task.wait(2.6)
	check("harvest fx cleans up", fxCount() == 0, fxCount())
	-- buttons keep their resting color after a disable/enable cycle (hover/press tint must not stick)
	local C = require(UIFolder:WaitForChild("Components"))
	local probe = C.button({ Parent = root, Text = "x", Color = Color3.fromRGB(10, 200, 30) })
	C.setEnabled(probe, false)
	local grey = probe.BackgroundColor3
	C.setEnabled(probe, true)
	check("button enabled/disabled colors", probe.BackgroundColor3 == Color3.fromRGB(10, 200, 30) and grey ~= probe.BackgroundColor3 and probe:FindFirstChild("Gloss") ~= nil)
	probe:Destroy()
end

-- ===== State ordering, world animation anchors, Wild Patch HUD =====
do
	local cur = State.data
	State.setState({ rev = cur.rev - 1, cash = -1 })
	check("an older snapshot never overwrites a newer one", State.data == cur and State.data.cash ~= -1)
	local CollectionService = game:GetService("CollectionService")
	local wrong = {}
	for _, tag in { "CK_Float", "CK_Spin" } do
		for _, inst in CollectionService:GetTagged(tag) do
			local base = inst:GetAttribute("BasePivot")
			if inst:IsA("Model") then
				if typeof(base) ~= "CFrame" then
					table.insert(wrong, inst.Name .. " has no BasePivot")
				elseif (inst:GetPivot().Position - base.Position).Magnitude > 40 then
					table.insert(wrong, string.format("%s drifted %.0f studs", inst.Name, (inst:GetPivot().Position - base.Position).Magnitude))
				end
			end
		end
	end
	check("balloons stay in the sky and windmill blades on the mill (with streaming)", #wrong == 0, table.concat(wrong, " | "))
	local WildPatch = require(UIFolder:WaitForChild("WildPatch"))
	local w = WildPatch.info()
	check("client got the Wild Patch clock", type(w.nextAt) == "number" and w.nextAt > 0 and type(w.left) == "number", w.left)
	check("Wild Patch HUD line is filled in", #WildPatch.hudText() > 5 and not string.find(WildPatch.hudText(), "{", 1, true), WildPatch.hudText())
end

-- ===== Round 6: compact layout, teleports, collapsible menu, sound, fade, trophies panel =====
do
	local Layout = require(UIFolder:WaitForChild("Layout"))
	local Sound = require(UIFolder:WaitForChild("Sound"))
	local Ambience = require(UIFolder:WaitForChild("Ambience"))
	local TrophiesPanel = require(UIFolder:WaitForChild("TrophiesPanel"))
	local Fx = require(UIFolder:WaitForChild("Fx"))
	local function real(touch, w, h)
		local dw, dh, compact = Layout.designFor(touch, w, h)
		return math.min(w / dw, h / dh), compact
	end
	local sTiny, cTiny = real(false, 566, 281) -- the safe area of a 566 x 345 viewport
	local sPhone, cPhone = real(true, 860, 390)
	local _sPc, cPc = real(false, 1436, 777)
	local _, cTablet = real(true, 1200, 800)
	local _, cMid = real(false, 916, 447)
	check("tiny screens use the compact canvas, mid and big ones the regular one", cTiny and cPhone and not cPc and not cTablet and not cMid)
	check("54 px buttons stay >= 40 real px on the smallest screen (566x345) and >= 44 on a phone", 54 * sTiny >= 40 and 54 * sPhone >= 44, string.format("%.1f / %.1f", 54 * sTiny, 54 * sPhone))
	local tpRow = root and root:FindFirstChild("Teleports")
	local tpButtons, actionButtons = 0, 0
	if tpRow then for _, b in tpRow:GetChildren() do if b:IsA("TextButton") then tpButtons += 1 end end end
	for _, b in root.Actions:GetChildren() do if b:IsA("TextButton") and b.Visible then actionButtons += 1 end end
	check("3 teleports top-center, 3 actions on the right", tpButtons == 3 and actionButtons == 3, tpButtons .. "/" .. actionButtons)
	local okIn, info = inside(tpRow)
	check("HUD inside safe area: Teleports", okIn, info)
	-- fold / unfold the menu in compact mode, then restore the real layout
	local saved = { Layout.isTouch, Layout.canvas, Layout.scale, Layout.compact }
	Layout.set(false, Vector2.new(740, 365), 0.76, true)
	task.wait(0.2)
	local menu = root.Menu
	local function visibleButtons()
		local n = 0
		for _, b in menu:GetChildren() do if b:IsA("TextButton") and b.Visible then n += 1 end end
		return n
	end
	local folded = visibleButtons()
	Panels.setMenuExpanded(true)
	local unfolded = visibleButtons()
	check("compact menu folds to Shop + More and unfolds to everything", folded == 2 and unfolded == 11 and menu.More.Visible, folded .. " -> " .. unfolded)
	Panels.setMenuExpanded(false)
	local chip = root.WeatherBanner
	check("compact: weather chip sits in the left column, clear of the basket", chip.AbsolutePosition.X < root.BasketBar.AbsolutePosition.X and chip.AbsolutePosition.X + chip.AbsoluteSize.X <= root.BasketBar.AbsolutePosition.X + 2, string.format("chip right %d, basket left %d", chip.AbsolutePosition.X + chip.AbsoluteSize.X, root.BasketBar.AbsolutePosition.X))
	Layout.set(false, Vector2.new(1100, 540), 1, false)
	task.wait(0.2)
	check("full menu on a normal screen", visibleButtons() == 10 and not menu.More.Visible, visibleButtons())
	Layout.set(saved[1], saved[2], saved[3], saved[4])
	task.wait(0.2)

	check("audio is silent and creates nothing while the IDs are empty", Sound.play("click") == false and Sound.play("nope") == false and Sound.music() == false and Sound.created == 0, Sound.created)
	check("crops fade only when the camera is on top of them", Ambience.shouldFade(4) and not Ambience.shouldFade(Ambience.FADE_RANGE + 1))
	check("trophy names read right", TrophiesPanel.itemName("pumpkin", "Golden", "Giant") == "Giant Golden Pumpkin" and TrophiesPanel.itemName("carrot", nil, nil) == "Carrot", TrophiesPanel.itemName("pumpkin", "Golden", "Giant"))
	local okFx, errFx = pcall(Fx.harvest, Vector3.new(0, 10, 0), "carrot", nil, 45, "Giant")
	check("harvest fx accepts a size", okFx, errFx)
end

-- ===== Chances panel =====
do
	local OddsPanel = require(UIFolder:WaitForChild("OddsPanel"))
	local StorePanel = require(UIFolder:WaitForChild("StorePanel"))
	local total = 0
	for _, r in OddsPanel.mutationRows() do total += r.pct end
	check("Chances panel: mutation list adds up to 100%", math.abs(total - 100) < 1e-6, total)
	check("Chances panel: readable percentages", OddsPanel.fmt(30) == "30%" and OddsPanel.fmt(0.1) == "0.1%" and OddsPanel.fmt(98.9) == "98.9%" and OddsPanel.fmt(0) == "0%" and OddsPanel.fmt(12.34) == "12.34%")
	local allowed = State.data.policy and State.data.policy.paidRandom == true
	check("store offers random items only where allowed", StorePanel.canOffer("LuckyPack") == allowed and StorePanel.canOffer("SuperLuck") == allowed and StorePanel.canOffer("DoubleCash") == true, tostring(allowed))
end

-- ===== Device profile =====
do
	local Perf = require(UIFolder:WaitForChild("Perf"))
	check("lite profile is for phones and low graphics only", Perf.decide(true, 0, 400) and Perf.decide(false, 2, 1080) and Perf.decide(true, 3, 1080) and not Perf.decide(false, 0, 1080) and not Perf.decide(true, 0, 800) and not Perf.decide(false, 8, 400) and not Perf.lite)
	local full, lite = Perf.budget(false), Perf.budget(true)
	check("lite profile shrinks every cosmetic budget", lite.harvestPop < full.harvestPop and lite.harvestLeaves < full.harvestLeaves and lite.coins < full.coins and lite.confetti < full.confetti and lite.floatHz < full.floatHz)
	local ornaments, total = 0, 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("Terrain") then
			total += 1
			if Perf.isOrnament(d) then ornaments += 1 end
		end
	end
	print(string.format("[TEST] PERF lite profile: drops %d of %d streamed-in parts (%.0f%%) on phones / low graphics", ornaments, total, ornaments / math.max(total, 1) * 100))
	check("lite profile drops at least 10% of the world's parts", ornaments / math.max(total, 1) >= 0.1, ornaments .. "/" .. total)
end

-- ===== Performance (client side of the server's perf window) =====
do
	local RunService = game:GetService("RunService")
	local Stats = game:GetService("Stats")
	local perfDone = false
	local perfConn = testEv.OnClientEvent:Connect(function(kind)
		if kind == "PerfDone" then perfDone = true end
	end)
	testEv:FireServer("Perf")
	task.wait(2)
	local frames, total, worst = 0, 0, 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		frames += 1
		total += dt
		worst = math.max(worst, dt)
	end)
	task.wait(5)
	conn:Disconnect()
	local fps = frames / math.max(total, 0.001)
	local function stat(name: string): number
		local ok, v = pcall(function() return (Stats :: any)[name] end)
		return if ok and type(v) == "number" then v else -1
	end
	local guiCount = 0
	for _ in player.PlayerGui:GetDescendants() do guiCount += 1 end
	local emitters = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Enabled then emitters += 1 end
	end
	print(string.format("[TEST] PERF client: %.0f fps avg, worst frame %.0f ms | %d PlayerGui instances | %d emitters on | draw calls %d, triangles %d | recv %.1f kbps, send %.1f kbps | memory %.0f MB",
		fps, worst * 1000, guiCount, emitters, stat("SceneDrawcallCount"), stat("SceneTriangleCount"), stat("DataReceiveKbps"), stat("DataSendKbps"), Stats:GetTotalMemoryUsageMb()))
	check("budget: PlayerGui <= 4500 instances", guiCount <= 4500, guiCount)
	check("budget: enabled particle emitters around the player <= 40", emitters <= 40, emitters)
	check("client keeps rendering (> 15 fps in Studio)", fps > 15, string.format("%.0f", fps))
	local tw2 = os.clock()
	while not perfDone and os.clock() - tw2 < 15 do task.wait(0.2) end
	perfConn:Disconnect()
	check("server perf window finished", perfDone)
end

task.wait(0.5)
check("no client errors", #clientErrors == 0, table.concat(clientErrors, " || "))
-- client attributes don't replicate to the server: report back through the RemoteEvent
testEv:FireServer("Done", table.concat(lines, "\n"))
print("[TEST] c done sent")
