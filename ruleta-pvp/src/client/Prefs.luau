--!strict
-- Client preferences derived from the saved settings and the device: the lite profile
-- (phones, low graphics), screen shake, flashes.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)

local Prefs = {}

Prefs.isTouch = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) or Workspace:GetAttribute("ForceTouchLayout") == true

local function savedQuality(): number
	local ok, level = pcall(function()
		return (UserSettings() :: any):GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return if ok and type(level) == "number" then level else 0
end

-- Lite: fewer wheel parts, fewer particles, no post-processing. On by default on phones and
-- when the player runs Roblox at graphics 1-3; the setting forces it on.
function Prefs.lite(): boolean
	if Workspace:GetAttribute("ForceLite") == true then
		return true
	end
	if Net.setting("lite") == true then
		return true
	end
	local q = savedQuality()
	return Prefs.isTouch or (q >= 1 and q <= 3)
end

function Prefs.shake(): boolean
	return Net.setting("shake") ~= false
end

function Prefs.flashes(): boolean
	return Net.setting("flashes") ~= false
end

return Prefs
