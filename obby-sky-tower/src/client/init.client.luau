--!strict
-- Sky Tower Obby: client bootstrap.
local Net = require(script.Net)
local Lang = require(script.Lang)
local Kit = require(script.UI.Kit)
local Toast = require(script.UI.Toast)
local Hud = require(script.UI.Hud)
local Progress = require(script.UI.Progress)
local Celebrate = require(script.UI.Celebrate)
local Intro = require(script.UI.Intro)
local ShopPanel = require(script.UI.ShopPanel)
local StorePanel = require(script.UI.StorePanel)
local RewardsPanel = require(script.UI.RewardsPanel)
local SettingsPanel = require(script.UI.SettingsPanel)
local WinPanel = require(script.UI.WinPanel)
local Prompts = require(script.UI.Prompts)
local EventBar = require(script.UI.EventBar)
local StarterPanel = require(script.UI.StarterPanel)
local TravelPanel = require(script.UI.TravelPanel)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local TowerStyle = require(game:GetService("ReplicatedStorage").Shared.TowerStyle)
local RunTime = require(game:GetService("ReplicatedStorage").Shared.RunTime)
local Quality = require(game:GetService("ReplicatedStorage").Shared.Quality)
local LocalFx = require(script.World.LocalFx)
local Atmos = require(script.World.Atmos)
local Juice = require(script.World.Juice)
local Weather = require(script.World.Weather)
local ChatTags = require(script.World.ChatTags)
local WorldText = require(script.World.WorldText)

Kit.gui()
Intro.play()
Progress.init()
Hud.init()
ShopPanel.init()
StorePanel.init()
RewardsPanel.init()
SettingsPanel.init()
WinPanel.init()
StarterPanel.init()
TravelPanel.init()
Prompts.init()
EventBar.init()
LocalFx.init()
Atmos.init()
Juice.init()
Weather.init()
ChatTags.init()
WorldText.init()

-- saved language preference and the effects switch arrive with the State push
local effectsOn = true
Net.changed:Connect(function(s)
	Lang.apply(s.lang)
	local on = not (type(s.settings) == "table" and s.settings.effects == false)
	if on ~= effectsOn then
		effectsOn = on
		Atmos.setEffects(on)
		Juice.setEffects(on)
		Weather.setEffects(on)
	end
end)

-- lite profile: phones / tablets, the graphics slider at 1..3, or ForceLite (tests, screenshots)
do
	local Workspace = game:GetService("Workspace")
	local lite = false
	local function refresh()
		local level = 0
		pcall(function()
			level = Quality.level(UserSettings():GetService("UserGameSettings").SavedQualityLevel.Name)
		end)
		-- ForceLite: true = lite, false = never lite (tests pin the profile), unset = by device
		local forced = Workspace:GetAttribute("ForceLite")
		local now = if forced == false then false else Quality.isLite(Kit.isTouch(), level, forced == true)
		if now ~= lite then
			lite = now
			Atmos.setLite(now)
			Juice.setLite(now)
			Weather.setLite(now)
		end
		Workspace:SetAttribute("LiteProfile", lite)
	end
	refresh()
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(refresh)
	end)
	Workspace:GetAttributeChangedSignal("ForceLite"):Connect(refresh)
	game:GetService("UserInputService").LastInputTypeChanged:Connect(refresh)
end

Net.on("Notify", function(msg: any, kind: string?)
	Toast.show(Lang.msg(msg) or "", kind)
end)
Net.on("Celebrate", function(data)
	Celebrate.stage(data)
end)
local function moodColors(tower: number): { Color3 }
	local mood = TowerStyle.mood(tower)
	local c = Config.c3(mood.core)
	return { c:Lerp(Kit.C.ink, 0.45), c:Lerp(Kit.C.ink, 0.15) }
end

Net.on("Gift", function(data)
	Toast.show(Lang.t("gift.got", { name = { key = "gift." .. tostring(data.id) .. ".name" } }), "success")
end)
Net.on("TowerEnter", function(data)
	local tower = tonumber(data.tower) or 2
	Celebrate.show(Lang.t("celebrate.tower_enter", { n = tower }), Lang.t("tower." .. TowerStyle.mood(tower).key), true, moodColors(tower))
end)
Net.on("Win", function(data)
	local tower = tonumber(data.tower) or 1
	if tower > 1 then
		-- summit of a later tower: the gift is the headline, the portal is the next step
		local gift = if data.gift then Lang.t("gift." .. tostring(data.gift) .. ".name") else nil
		Celebrate.show(Lang.t("celebrate.tower", { n = tower }), gift, true, moodColors(tower))
		return
	end
	local sub = Lang.t("celebrate.total_wins", { n = data.wins or 1 })
	if data.newBest and data.runMs then
		sub = Lang.t("celebrate.new_best", { time = RunTime.format(data.runMs) })
	elseif data.runMs then
		sub = Lang.t("celebrate.run_time", { time = RunTime.format(data.runMs) })
	end
	Celebrate.show(Lang.t("celebrate.win"), sub, true, { Kit.C.orange, Kit.C.pink })
	task.delay(2.5, function()
		Kit.open("win")
	end)
end)
Net.on("OpenPanel", function(name: string)
	Kit.open(name)
end)

-- Ask for a fresh snapshot in case the first push happened before we connected.
task.spawn(function()
	Net.request("GetState")
end)
