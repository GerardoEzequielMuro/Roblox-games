--!strict
-- Planet Crackers: client bootstrap.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Purchase = require(script.Parent.Purchase)
local Ads = require(script.Parent.Ads)
local Quality = require(script.Parent.Quality)
local LiveEventClient = require(script.Parent.LiveEventClient)
local WorldFx = require(script.Parent.WorldFx)
local WorldText = require(script.Parent.WorldText)
local PlanetField = require(script.Parent.PlanetField)
local Miner = require(script.Parent.Miner)
local PetFollow = require(script.Parent.PetFollow)
local ToolFx = require(script.Parent.ToolFx)
local UI = script.Parent.UI
local Theme = require(UI.Theme)
local Windows = require(UI.Windows)
local Toasts = require(UI.Toasts)
local Hud = require(UI.Hud)
local CapsuleCinematic = require(UI.CapsuleCinematic)
local CapsulePanel = require(UI.CapsulePanel)
local PetsWindow = require(UI.PetsWindow)
local UpgradesWindow = require(UI.UpgradesWindow)
local ProgressWindows = require(UI.ProgressWindows)
local StoreWindow = require(UI.StoreWindow)
local RewardsWindow = require(UI.RewardsWindow)
local IndexWindow = require(UI.IndexWindow)
local SocialWindows = require(UI.SocialWindows)
local PvpClient = require(script.Parent.PvpClient)
local Guide = require(script.Parent.Guide)

Purchase.setNotifier(Toasts.show)
Ads.setNotifier(Toasts.show)
WorldFx.init()
Toasts.init()
PlanetField.init()
Miner.init()
Hud.init()
PetsWindow.init()
UpgradesWindow.init()
ProgressWindows.init()
StoreWindow.init()
RewardsWindow.init()
IndexWindow.init()
SocialWindows.init()
CapsulePanel.init()
CapsuleCinematic.init()
PetFollow.init()
ToolFx.init()
WorldText.init()
PvpClient.init()
Guide.init()

CapsuleCinematic.setBusyCallback(function(busy)
	Miner.setEnabled(not busy)
end)

Net.event("Hatched").OnClientEvent:Connect(function(data)
	CapsuleCinematic.play(data.capsule, data.results, data.auto)
end)

-- every local hit: tool swing, pets peck, a tick
Miner.Hit:Connect(function()
	ToolFx.swing()
	PetFollow.pulse()
	Theme.play("tap", 0.25, 0.9 + math.random() * 0.3)
end)
local lastBlocked = 0
Miner.Blocked:Connect(function(reason)
	if os.clock() - lastBlocked > 2 then
		lastBlocked = os.clock()
		Toasts.show(Lang.t(if reason == "range" then "toast.get_closer" else "toast.no_planet"), "info", 1.6)
	end
end)

-- server results that need words
local lastFull, lastSoft = 0, 0
Net.event("Mine").OnClientEvent:Connect(function(msg)
	local now = os.clock()
	if msg.full and now - lastFull > 3 then
		lastFull = now
		Toasts.show("🎒 " .. Lang.t("toast.cargo_full"), "error", 2.2)
	elseif msg.soft and now - lastSoft > 6 then
		lastSoft = now
		Toasts.show("🛠️ " .. Lang.t("toast.too_hard"), "error", 2.6)
	end
	if msg.drops then
		Theme.play("boom", 0.3, 1.2)
		if msg.drops.gate then
			Toasts.milestone(Lang.t("toast.gate_broken"), Lang.zone(msg.drops.gate), Theme.Purple)
			WorldFx.flash(Theme.Purple)
		end
	elseif msg.b and msg.b > 0 then
		Theme.play("hit", 0.25, 1.1)
	end
end)

-- prompts in the world open the matching UI
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local open = prompt:GetAttribute("Open")
	if open == "Capsule" then
		CapsulePanel.open(prompt:GetAttribute("CapsuleId") :: string)
	elseif open == "Upgrades" then
		UpgradesWindow.open(prompt:GetAttribute("System") :: string?)
	elseif open == "Teleport" then
		Windows.open("Teleport")
	end
end)

-- the Anomaly appears / leaves on the hour: refetch the planets
local anomalyOn: boolean? = nil
LiveEventClient.Changed:Connect(function(data)
	if anomalyOn ~= nil and data.anomalyOn ~= anomalyOn then
		PlanetField.reload()
		if data.anomalyOn then
			Toasts.banner("🌀 " .. Lang.t("toast.anomaly"), Theme.Teal)
		end
	end
	anomalyOn = data.anomalyOn
end)

-- sound setting
Net.Changed:Connect(function(kind)
	local s = Net.state
	if kind == "full" and s and s.settings then
		Theme.muted = s.settings.sfx == false
	end
end)

-- keep the analyzer honest about modules that only need to be loaded
local _ = Quality
