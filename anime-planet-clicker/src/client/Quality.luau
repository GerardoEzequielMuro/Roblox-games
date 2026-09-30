--!strict
-- Detail level. "Lite" drops the extras (pet auras, planet craters and rings, ambient
-- particles, extra debris): it is on for phones, for players who turned it on in Settings and
-- for anyone whose Roblox graphics slider is at 3 or lower. The game has to look right in
-- lite too: colours and shapes carry the look, effects are a bonus.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)

local Quality = {}

local changed = Instance.new("BindableEvent")
Quality.Changed = changed.Event

local isTouch = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) or Workspace:GetAttribute("ForceTouchLayout") == true

-- Roblox graphics slider (1..10), or nil on Automatic / when it cannot be read.
function Quality.savedLevel(): number?
	local ok, level = pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		return settings.SavedQualityLevel
	end)
	if ok and typeof(level) == "EnumItem" then
		local n = tonumber(string.match((level :: EnumItem).Name, "%d+"))
		return n
	end
	return nil
end

local function compute(): boolean
	if Workspace:GetAttribute("ForceLite") == true then
		return true
	end
	local s = Net.state
	if s and s.settings and s.settings.lite then
		return true
	end
	local level = Quality.savedLevel()
	if level and level <= 3 then
		return true
	end
	return isTouch
end

Quality.lite = compute()

local function refresh()
	local now = compute()
	if now ~= Quality.lite then
		Quality.lite = now
		changed:Fire(now)
	end
end

Net.Changed:Connect(function(kind)
	if kind == "full" then
		refresh()
	end
end)
task.spawn(function()
	while true do
		task.wait(5)
		refresh()
	end
end)

return Quality
