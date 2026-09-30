--!strict
-- Converts Config's pure-data colors into Color3.
local Config = require(script.Parent.Config)

local Palette = {}

function Palette.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Palette.rarity(name: string): Color3
	local r = Config.RarityByName[name]
	return if r then Palette.rgb(r.color) else Color3.new(1, 1, 1)
end

Palette.Gold = Color3.fromRGB(255, 196, 38)
Palette.TierColors = {
	[0] = Color3.fromRGB(255, 255, 255),
	[1] = Color3.fromRGB(255, 205, 55),
	[2] = Color3.fromRGB(255, 120, 220),
}
Palette.Buff = {
	damage = Color3.fromRGB(255, 84, 84),
	speed = Color3.fromRGB(80, 210, 255),
	luck = Color3.fromRGB(96, 226, 120),
	stardust = Color3.fromRGB(255, 205, 60),
}

-- Rainbow hue for time t (seconds) and phase offset.
function Palette.rainbow(t: number, offset: number?): Color3
	return Color3.fromHSV(((t * 0.35) + (offset or 0)) % 1, 0.7, 1)
end

function Palette.lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

function Palette.darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

return Palette
