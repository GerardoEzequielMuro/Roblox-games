--!strict
-- Converts Config's pure-data colors into Color3 and holds UI colors.
local Config = require(script.Parent.Config)

local Palette = {}

function Palette.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Palette.rarity(name: string): Color3
	local r = Config.RarityByName[name]
	return if r then Palette.rgb(r.color) else Color3.new(1, 1, 1)
end

function Palette.material(name: string?): Enum.Material
	if not name then
		return Enum.Material.SmoothPlastic
	end
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

Palette.Gold = Color3.fromRGB(255, 196, 38)
Palette.TierColors = {
	[0] = Color3.fromRGB(255, 255, 255),
	[1] = Color3.fromRGB(255, 205, 55),
	[2] = Color3.fromRGB(255, 120, 220),
}

-- Rainbow hue for time t (seconds) and phase offset.
function Palette.rainbow(t: number, offset: number?): Color3
	return Color3.fromHSV(((t * 0.35) + (offset or 0)) % 1, 0.75, 1)
end

return Palette
