--!strict
-- Tap Pets Simulator: client bootstrap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local Net = require(script.Parent.Net)
local Purchase = require(script.Parent.Purchase)
local Tapper = require(script.Parent.Tapper)
local PetFollow = require(script.Parent.PetFollow)
local WorldFx = require(script.Parent.WorldFx)
local WorldText = require(script.Parent.WorldText)
local ParkFx = require(script.Parent.ParkFx)
local UI = script.Parent.UI
local Theme = require(UI.Theme)
local Toasts = require(UI.Toasts)
local Hud = require(UI.Hud)
local HatchCinematic = require(UI.HatchCinematic)
local EggPanel = require(UI.EggPanel)
local PetsWindow = require(UI.PetsWindow)
local ProgressWindows = require(UI.ProgressWindows)
local StoreWindow = require(UI.StoreWindow)
local RewardsWindow = require(UI.RewardsWindow)
local IndexWindow = require(UI.IndexWindow)
local QuestsWindow = require(UI.QuestsWindow)
local InviteWindow = require(UI.InviteWindow)
local Popups = require(UI.Popups)
local Ads = require(script.Parent.Ads)
local Onboarding = require(script.Parent.Onboarding)

Purchase.setNotifier(Toasts.show)
Ads.setNotifier(Toasts.show)
Toasts.init()
Hud.init()
PetsWindow.init()
ProgressWindows.init()
StoreWindow.init()
RewardsWindow.init()
IndexWindow.init()
QuestsWindow.init()
InviteWindow.init()
Popups.init()
EggPanel.init()
Tapper.init()
Onboarding.init()
PetFollow.init()
WorldFx.init()
WorldText.init()
ParkFx.init()

HatchCinematic.setBusyCallback(function(busy)
	Tapper.setEnabled(not busy)
end)
HatchCinematic.setBurstCallback(WorldFx.eggBurst)
if Hud.tapsPill then
	local pill = Hud.tapsPill
	Tapper.setCounter(pill, function()
		Theme.pop(pill, 1.07)
	end)
end

if Hud.tapButton then
	local btn = Hud.tapButton
	local lastSquash = 0
	-- squash and stretch on every tap (at most ~12 times a second; the tween is tiny)
	Tapper.setTapHook(function()
		local now = os.clock()
		if now - lastSquash > 0.08 then
			lastSquash = now
			Theme.pop(btn, 0.9)
		end
	end)
end

Net.event("Hatched").OnClientEvent:Connect(function(data)
	HatchCinematic.play(data.egg, data.results, data.auto)
end)
