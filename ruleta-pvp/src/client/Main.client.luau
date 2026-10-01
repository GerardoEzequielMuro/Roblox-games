--!strict
-- Spin Showdown: client bootstrap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Loading screen first: it covers the build below and always goes away on its own.
local Loading = require(script.Parent.UI.Loading)
pcall(Loading.start)

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
local Guide = require(UI.Guide)
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
Guide.init()
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

-- tell the loading screen when the HUD is built and the profile has arrived
Loading.mark("ui")
if Net.state then
	Loading.mark("data")
else
	Net.Changed:Once(function()
		Loading.mark("data")
	end)
end

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
	-- always ask: the server frees the seat as soon as the results are out (and answers ok if already queued)
	request("QuickPlay", { mode = if mode == "duel" then nil else mode })
end
MenuWindows.onSpectate = function(tableId: string)
	Director.spectate(tableId)
end

Net.Changed:Connect(Audio.refreshVolume)
