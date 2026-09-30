--!nonstrict
-- Ki Warriors: client bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local Net = require(script.Parent.Net)
local Purchase = require(script.Parent.Purchase)
local Fx = require(script.Parent.Fx)
local CombatFx = require(script.Parent.CombatFx)
local CharFx = require(script.Parent.CharFx)
local NpcRender = require(script.Parent.NpcRender)
local Flight = require(script.Parent.Flight)
local Controls = require(script.Parent.Controls)
local Lang = require(script.Parent.Lang)
local WorldFx = require(script.Parent.WorldFx)
local UI = script.Parent.UI
local Toasts = require(UI.Toasts)
local Hud = require(UI.Hud)
local TouchControls = require(UI.TouchControls)

Purchase.setNotifier(Toasts.show)
Controls.toast = function(msg, kind)
	Toasts.show(Lang.msg(msg), kind)
end
Hud.notify = Toasts.show
Hud.banner = Toasts.banner

CombatFx.init()
CharFx.init()
NpcRender.init()
Flight.init()
Controls.init()
WorldFx.init()
Toasts.init()
Hud.init()
TouchControls.init()

-- Optional UI / feature modules (added round by round); each exposes init().
for _, name in { "Menu", "QuestTracker", "RelicsClient", "EventsHud" } do
	local module = script.Parent:FindFirstChild(name) or UI:FindFirstChild(name)
	if module then
		local m = (require :: any)(module)
		if name == "RelicsClient" then
			m.notify = Toasts.show
		end
		m.init()
	end
end

-- Knockback from the server (our character is simulated on this client).
Net.event("Knock").OnClientEvent:Connect(function(vel: Vector3)
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and typeof(vel) == "Vector3" and vel.Magnitude < 400 then
		root.AssemblyLinearVelocity = vel
		Fx.shake(0.6)
	end
end)
