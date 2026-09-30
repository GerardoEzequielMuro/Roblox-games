--!strict
-- Spin Showdown: client bootstrap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Audio = require(script.Parent.Audio)
local TableViews = require(script.Parent.Arena.TableViews)
local Avatars = require(script.Parent.Arena.Avatars)
local Director = require(script.Parent.Arena.Director)
local UI = script.Parent.UI
local Toasts = require(UI.Toasts)
local Windows = require(UI.Windows)
local Hud = require(UI.Hud)
local MatchHud = require(UI.MatchHud)
local MenuWindows = require(UI.MenuWindows)
local Popups = require(UI.Popups)
local CoreClient = require(script.Parent.CoreClient)
local WorldText = require(script.Parent.WorldText)

Toasts.init()
TableViews.init() -- waits for the stages to replicate, then builds the wheels
Avatars.init()
MatchHud.init()
Hud.init()
MenuWindows.init()
Director.init()
Popups.init()
CoreClient.init()
WorldText.init()

-- The lobby HUD steps aside while a match (or a spectated table) is on screen.
local function syncHud()
	local inMatch = MatchHud.isVisible()
	Hud.setVisible(not inMatch)
	if inMatch and Windows.current() then
		Windows.close()
	end
end
TableViews.Changed:Connect(function(id)
	if id == Director.focus then
		local view = TableViews.byId[id]
		if view.playing and not MatchHud.isVisible() then
			MatchHud.show(view, Director.spectating)
		elseif not view.playing and MatchHud.isVisible() and not MatchHud.resultVisible() and not Director.spectating then
			MatchHud.hide()
		end
	end
	syncHud()
end)
Net.Changed:Connect(syncHud)

local function request(action: string, payload: { [string]: any }?)
	task.spawn(function()
		local ok, err = Net.request(action, payload)
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end)
end

MatchHud.onLeave = function()
	MatchHud.closeResult()
	if Director.spectating then
		Director.stopSpectating()
		MatchHud.hide()
	elseif Net.get("table") then
		request("LeaveTable")
		MatchHud.hide()
	else
		MatchHud.hide()
	end
	syncHud()
end
MatchHud.onPlayAgain = function(mode: string)
	MatchHud.hide()
	syncHud()
	if not Net.get("table") then
		request("QuickPlay", { mode = if mode == "duel" then nil else mode })
	end
end
MenuWindows.onSpectate = function(tableId: string)
	Director.spectate(tableId)
end

Net.Changed:Connect(Audio.refreshVolume)
