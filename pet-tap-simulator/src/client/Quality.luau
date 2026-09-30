--!strict
-- Device / graphics profile. "lite" = phones and tablets, or a player who turned the Roblox
-- graphics slider down to 3 or less. Lite keeps the look (shapes, colours, UI) and drops the
-- expensive extras: fewer particles, no pet lights or trails, fewer pets drawn for other
-- players, no real-time shadows or post-processing. PC at normal quality is untouched.
--
-- Workspace attribute ForceLite = true previews it in Studio.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Quality = {}

local changed = Instance.new("BindableEvent")
Quality.Changed = changed.Event

local FULL = {
	particles = 1, -- multiplier on ambient / tap / hatch particle counts
	petFx = true, -- pet trails, point lights, full emitter rates
	remotePets = 9, -- pets drawn per other player
	remoteCull = 220, -- studs: other players' pets beyond this are not drawn
	animDistance = 110, -- studs: joints / rainbow only animate this close to the camera
	slowDistance = 70, -- studs: beyond this, other players' pets update every other frame
	shadows = true, -- real-time shadows + bloom / sun rays
}
local LITE = {
	particles = 0.5,
	petFx = false,
	remotePets = 4,
	remoteCull = 110,
	animDistance = 55,
	slowDistance = 35,
	shadows = false,
}

Quality.lite = false
Quality.level = 0 -- Roblox graphics level 1..10 (0 = automatic)
Quality.particles = FULL.particles
Quality.petFx = FULL.petFx
Quality.remotePets = FULL.remotePets
Quality.remoteCull = FULL.remoteCull
Quality.animDistance = FULL.animDistance
Quality.slowDistance = FULL.slowDistance
Quality.shadows = FULL.shadows

local function savedLevel(): number
	local level = 0
	pcall(function()
		local saved = UserSettings():GetService("UserGameSettings").SavedQualityLevel
		level = tonumber(saved.Name:match("(%d+)$")) or 0
	end)
	return level
end

-- Pure rule, exported for tests.
function Quality.isLite(touchOnly: boolean, level: number, forced: boolean): boolean
	return forced or touchOnly or (level > 0 and level <= 3)
end

local function refresh()
	local level = savedLevel()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local lite = Quality.isLite(touchOnly, level, Workspace:GetAttribute("ForceLite") == true)
	local was = Quality.lite
	Quality.level = level
	Quality.lite = lite
	local src = if lite then LITE else FULL
	Quality.particles = src.particles
	Quality.petFx = src.petFx
	Quality.remotePets = src.remotePets
	Quality.remoteCull = src.remoteCull
	Quality.animDistance = src.animDistance
	Quality.slowDistance = src.slowDistance
	Quality.shadows = src.shadows
	if was ~= lite then
		changed:Fire(lite)
	end
end

refresh()
pcall(function()
	UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(refresh)
end)
Workspace:GetAttributeChangedSignal("ForceLite"):Connect(refresh)

return Quality
