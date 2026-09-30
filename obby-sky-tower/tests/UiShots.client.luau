-- UI screenshot tour (uishots.project.json only). Every window resize by the runner moves to the
-- next step, so one run gives the HUD, the open menu, every panel, a celebration and the skip
-- offer at each resolution (pass 9 near-identical sizes per resolution, e.g. 1920x1032..1024).
-- The character is frozen on the lobby spawn for the whole tour: nothing falls, nothing dies.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Kit = require(Client:WaitForChild("UI"):WaitForChild("Kit"))
local Celebrate = require(Client.UI:WaitForChild("Celebrate"))
local Cards = require(Client.UI:WaitForChild("Cards"))
local Lang = require(Client:WaitForChild("Lang"))
local Config = require(ReplicatedStorage.Shared.Config)

local function freeze()
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
end
player.CharacterAdded:Connect(function()
	task.defer(freeze)
end)

local function menu(open: boolean)
	local grid = Kit.gui():FindFirstChild("Menu")
	if grid and grid:IsA("GuiObject") then
		grid.Visible = open
	end
end

local steps = {
	{ name = "hud", run = function() Kit.close() end },
	{ name = "menu open", run = function() menu(true) end },
	{ name = "settings", run = function() menu(false) Kit.open("settings") end },
	{ name = "shop", run = function() Kit.open("shop") end },
	{ name = "rewards", run = function() Kit.open("rewards") end },
	{ name = "store", run = function() Kit.open("store") end },
	{ name = "celebrate + skip offer", run = function()
		Kit.close()
		Cards.show("Stuck", Lang.t("offer.title", { n = 21 }), {
			{ name = "FreeSkip", text = Lang.t("offer.free", { n = 2 }), color = Kit.C.green, onClick = function() end },
			{ name = "PaidSkip", text = Lang.t("offer.paid_noprice"), color = Kit.C.blue, onClick = function() end },
		}, 30)
		-- keep the banner on screen until the screenshot (it fades after 4 s)
		for _ = 1, 3 do
			Celebrate.stage({ stage = 20, coins = 9, world = 3 })
			task.wait(2.2)
		end
	end },
	{ name = "win", run = function()
		Cards.hide()
		Kit.open("win")
	end },
	{ name = "travel", run = function() Kit.open("travel") end },
}
local i = 0
local function nextShot()
	i += 1
	local step = steps[((i - 1) % #steps) + 1]
	print(("[TEST] ui shot %d: %s (theme count %d)"):format(i, step.name, #Config.Themes))
	step.run()
end
task.wait(3)
freeze()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	task.spawn(nextShot)
end)
