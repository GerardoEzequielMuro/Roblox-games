--!nonstrict
-- Crop Kingdom client entry point: builds the UI, wires remotes, handshakes with the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
ReplicatedStorage:WaitForChild("Shared")

local UI = script.Parent.UI
local C = require(UI.Components)
local State = require(UI.State)
local Net = require(UI.Net)
local Toasts = require(UI.Toasts)
local Hud = require(UI.Hud)
local Hotbar = require(UI.Hotbar)
local Panels = require(UI.Panels)
local Weather = require(UI.Weather)
local Tiles = require(UI.Tiles)
local Fx = require(UI.Fx)
local Tutorial = require(UI.Tutorial)
local Layout = require(UI.Layout)
local I18n = require(UI.I18n)
local WorldText = require(UI.WorldText)
local LiveEvent = require(UI.LiveEvent)
local NotifyCard = require(UI.NotifyCard)
local Juice = require(UI.Juice)
local Ambience = require(UI.Ambience)
local Perf = require(UI.Perf)
local WildPatch = require(UI.WildPatch)
local Sound = require(UI.Sound)
local Loading = require(UI.Loading)

-- Branded loading screen first: it fades out by itself after a few seconds even if something below fails.
Loading.show()

-- ===== ScreenGui + safe-area-based scaling =====
-- CoreUISafeInsets keeps the whole UI below the Roblox top bar (menu/chat buttons) and inside device notches.
local gui: ScreenGui = C.new("ScreenGui", {
	Name = "CropKingdomUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
})

-- Root is laid out in "design pixels"; the UIScale maps them to the real screen.
local root: Frame = C.new("Frame", {
	Name = "Root",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
})
local rootScale: UIScale = C.new("UIScale", { Parent = root })

-- Design canvas: at least 1100x540 on PC (1000x480 on touch) so the HUD always fits; buttons of 56 design px
-- stay >= 44 real px at a ~920x505 viewport.
local function safeAreaSize(): Vector2
	local a = gui.AbsoluteSize
	if gui.Parent and a.X > 2 and a.Y > 2 then
		return a
	end
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	return Vector2.new(vp.X, vp.Y - GuiService:GetGuiInset().Y)
end

local playerListShown: boolean? = nil
local function updatePlayerList()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- The default PlayerList covers the right-side buttons on small screens.
	local want = cam.ViewportSize.X >= 1000
	if want ~= playerListShown then
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, want)
		end)
		if ok then
			playerListShown = want
		end
	end
end

local function updateScale()
	local size = safeAreaSize()
	if size.X < 2 or size.Y < 2 then
		return
	end
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local dw, dh, compact = Layout.designFor(touchOnly, size.X, size.Y)
	local s = math.clamp(math.min(size.X / dw, size.Y / dh), 0.25, if touchOnly or compact then 1.1 else 1)
	rootScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
	Layout.set(touchOnly, size / s, s, compact)
	updatePlayerList()
end

local camConn: RBXScriptConnection? = nil
local function hookCamera()
	if camConn then
		camConn:Disconnect()
	end
	local cam = workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
hookCamera()

-- Loading label until the handshake succeeds
local loading = C.label(root, I18n.L("main.loading"), UDim2.fromOffset(500, 60), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	TextSize = 34,
	ZIndex = 50,
})

-- ===== Build UI =====
Toasts.build(root)
Hud.build(root)
Hotbar.build(root)
Panels.build(root)
Hud.onAuto = function()
	Panels.toggle("Auto")
end
Weather.build(root)
LiveEvent.build(root)
NotifyCard.build(root)
Tiles.init(root)
Perf.init()
Juice.init(root)
Ambience.init()
WildPatch.init()
Tutorial.init(root, {
	shopButton = Panels.menuButtons.Shop,
	hotbar = Hotbar.frame,
	sellButton = Hud.refs.sellButton,
})

gui.Parent = player:WaitForChild("PlayerGui")
updateScale()
Loading.stage() -- UI built

-- ===== Remotes =====
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
Net.init(Remotes)
Loading.stage() -- remotes wired

local function onEvent(name: string, fn: (...any) -> ())
	task.spawn(function()
		local ev = Remotes:WaitForChild(name)
		if ev:IsA("RemoteEvent") then
			ev.OnClientEvent:Connect(fn)
		end
	end)
end

-- ===== Language: server-confirmed choice wins; switching re-renders bound texts and rebuilds computed ones =====
I18n.onChanged(State.refreshAll)
WorldText.init()
local function applyLang(s: any)
	if type(s) == "table" and type(s.lang) == "string" then
		I18n.setLang(s.lang)
	end
end

onEvent("StateUpdate", function(s)
	applyLang(s)
	State.setState(s)
end)
onEvent("StockUpdate", function(stock, nextRestockAt)
	State.setStock(stock, nextRestockAt)
end)
onEvent("WeatherUpdate", function(id, endsAt, nextAt)
	State.setWeather(id, endsAt, nextAt)
end)
onEvent("Notify", function(text, kind)
	Toasts.show(text, kind)
end)
onEvent("LiveEventUpdate", function(current, nxt)
	State.setLiveEvent(current, nxt)
end)
onEvent("AskNotifications", function()
	NotifyCard.ask()
end)
onEvent("HarvestFx", function(position, seedId, mutation, value, size)
	Fx.harvest(position, seedId, mutation, value, size)
end)

-- ===== World prompts open the matching panel =====
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then
		return
	end
	local parent = prompt.Parent
	local name = parent and parent.Name
	if name == "SeedShop" then
		Panels.open("Shop")
	elseif name == "UpgradeShop" then
		Panels.open("Upgrades")
	elseif name == "RobuxShop" then
		Panels.open("Store")
	end
end)

-- ===== Handshake =====
task.spawn(function()
	local request = Remotes:WaitForChild("Request") :: RemoteFunction
	while true do
		local callOk, ok, _msg, data = pcall(function()
			return request:InvokeServer("Hello", { lang = I18n.autoLang })
		end)
		if callOk and ok == true and type(data) == "table" then
			if type(data.stock) == "table" or data.nextRestockAt then
				State.setStock(data.stock or {}, data.nextRestockAt)
			end
			if type(data.weather) == "table" then
				State.setWeather(data.weather.id, data.weather.endsAt, data.weather.nextAt)
			end
			if type(data.liveEvent) == "table" then
				State.setLiveEvent(data.liveEvent.current, data.liveEvent.next)
			end
			if type(data.state) == "table" then
				applyLang(data.state)
				State.setState(data.state)
			end
			break
		end
		task.wait(2)
	end
	loading:Destroy()
	Loading.stage() -- handshake answered
	Sound.music()
	Toasts.show(I18n.L("msg.welcomeNew", { game = "Crop Kingdom" }), "success")
end)
