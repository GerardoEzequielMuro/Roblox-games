--!strict
-- The look of each of the ten towers. PURE Luau (colours are {r, g, b} in 0..255).
--
-- The ten world palettes (Grassy Hills ... Rainbow Summit) are defined once here. Every tower
-- plays those ten worlds (in a rotated order, see Layout.themeFor) through its own "mood":
--   * a palette shift baked into the colour of the parts (hue / saturation / value), so the towers
--     look different even with graphics at minimum, where there is no bloom or atmosphere;
--   * a lighting grade applied on top of the world's sky profile (Shared/Ambience).
-- Tower 1 is neutral: it is the original Sky Tower.
local TowerStyle = {}

export type RGB = { number }
export type World = { key: string, platform: RGB, alt: RGB, accent: RGB, pad: RGB, sky: RGB }
export type Mood = {
	key: string, -- locale key suffix: tower.<key>
	hue: number, -- degrees added to the hue of every palette colour
	sat: number, -- saturation multiplier
	val: number, -- value (brightness) multiplier
	core: RGB, -- accent of the tower's core pillar, halos and portal
	clock: number, -- time of day the tower leans towards
	clockMix: number, -- 0 = keep each world's own time, 1 = always `clock`
	bright: number, -- brightness multiplier
	tint: RGB, -- colour-correction tint multiplied in
	haze: RGB, -- atmosphere colour multiplied in
	density: number, -- added to the atmosphere density
	saturation: number, -- added to the colour-correction saturation
	stars: number, -- added to the star count
}

TowerStyle.Worlds = {
	{ key = "world.1", platform = { 125, 220, 95 }, alt = { 185, 140, 90 }, accent = { 255, 230, 90 }, pad = { 90, 220, 255 }, sky = { 170, 220, 255 } },
	{ key = "world.2", platform = { 255, 150, 210 }, alt = { 255, 240, 250 }, accent = { 120, 220, 255 }, pad = { 255, 230, 90 }, sky = { 255, 205, 235 } },
	{ key = "world.3", platform = { 190, 235, 255 }, alt = { 120, 180, 230 }, accent = { 255, 255, 255 }, pad = { 80, 255, 200 }, sky = { 215, 240, 255 } },
	{ key = "world.4", platform = { 235, 200, 130 }, alt = { 190, 140, 80 }, accent = { 80, 200, 220 }, pad = { 255, 150, 60 }, sky = { 255, 225, 170 } },
	{ key = "world.5", platform = { 80, 70, 80 }, alt = { 120, 70, 60 }, accent = { 255, 150, 40 }, pad = { 255, 200, 60 }, sky = { 255, 150, 110 } },
	{ key = "world.6", platform = { 80, 190, 200 }, alt = { 250, 220, 170 }, accent = { 255, 140, 170 }, pad = { 255, 240, 120 }, sky = { 150, 220, 240 } },
	{ key = "world.7", platform = { 120, 130, 140 }, alt = { 170, 230, 60 }, accent = { 255, 220, 40 }, pad = { 170, 255, 60 }, sky = { 200, 230, 170 } },
	{ key = "world.8", platform = { 250, 250, 255 }, alt = { 200, 215, 255 }, accent = { 255, 210, 90 }, pad = { 120, 200, 255 }, sky = { 235, 240, 255 } },
	{ key = "world.9", platform = { 40, 30, 70 }, alt = { 0, 255, 230 }, accent = { 255, 60, 220 }, pad = { 255, 255, 90 }, sky = { 110, 90, 180 } },
	{ key = "world.10", platform = { 255, 210, 80 }, alt = { 255, 150, 120 }, accent = { 120, 160, 255 }, pad = { 255, 255, 255 }, sky = { 255, 240, 200 } },
} :: { World }

TowerStyle.Moods = {
	{ key = "1", hue = 0, sat = 1, val = 1, core = { 255, 205, 70 }, clock = 14.5, clockMix = 0, bright = 1, tint = { 255, 255, 255 }, haze = { 255, 255, 255 }, density = 0, saturation = 0, stars = 0 }, -- Sky
	{ key = "2", hue = 22, sat = 1.05, val = 1, core = { 255, 140, 60 }, clock = 17.6, clockMix = 0.6, bright = 0.95, tint = { 255, 228, 205 }, haze = { 255, 215, 185 }, density = 0.02, saturation = 0.05, stars = 0 }, -- Sunset
	{ key = "3", hue = 215, sat = 0.9, val = 0.82, core = { 120, 150, 255 }, clock = 0.5, clockMix = 0.85, bright = 0.62, tint = { 205, 215, 255 }, haze = { 70, 85, 160 }, density = -0.04, saturation = 0.05, stars = 3500 }, -- Midnight
	{ key = "4", hue = 200, sat = 0.5, val = 0.85, core = { 255, 240, 120 }, clock = 15, clockMix = 0.4, bright = 0.78, tint = { 205, 215, 232 }, haze = { 150, 160, 178 }, density = 0.1, saturation = -0.2, stars = 0 }, -- Storm
	{ key = "5", hue = 165, sat = 0.8, val = 1.08, core = { 120, 245, 255 }, clock = 10, clockMix = 0.4, bright = 1, tint = { 225, 245, 255 }, haze = { 190, 232, 255 }, density = 0, saturation = 0.1, stars = 0 }, -- Crystal
	{ key = "6", hue = -32, sat = 1.12, val = 0.92, core = { 255, 120, 40 }, clock = 17.9, clockMix = 0.6, bright = 0.9, tint = { 255, 212, 190 }, haze = { 225, 120, 80 }, density = 0.05, saturation = 0.08, stars = 300 }, -- Inferno
	{ key = "7", hue = 190, sat = 0.42, val = 1.12, core = { 190, 235, 255 }, clock = 8.2, clockMix = 0.5, bright = 1, tint = { 222, 238, 255 }, haze = { 226, 240, 255 }, density = 0.06, saturation = -0.15, stars = 0 }, -- Frozen
	{ key = "8", hue = 80, sat = 1, val = 0.92, core = { 170, 255, 60 }, clock = 17, clockMix = 0.45, bright = 0.85, tint = { 228, 255, 208 }, haze = { 172, 215, 125 }, density = 0.04, saturation = 0, stars = 0 }, -- Toxic
	{ key = "9", hue = 268, sat = 1.05, val = 0.7, core = { 200, 90, 255 }, clock = 2, clockMix = 0.9, bright = 0.58, tint = { 228, 208, 255 }, haze = { 45, 25, 85 }, density = -0.08, saturation = 0.12, stars = 5000 }, -- Void
	{ key = "10", hue = 305, sat = 0.92, val = 1.08, core = { 255, 255, 255 }, clock = 6.4, clockMix = 0.5, bright = 1, tint = { 255, 240, 246 }, haze = { 255, 218, 228 }, density = 0, saturation = 0.15, stars = 800 }, -- Rainbow
} :: { Mood }

-- Colour of the things that kill you. No palette colour may be mistaken for it (see isDanger).
TowerStyle.KILL = { 255, 30, 40 }

local function toHSV(c: RGB): (number, number, number)
	local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h *= 60
	end
	local s = if max == 0 then 0 else d / max
	return h, s, max
end
TowerStyle.toHSV = toHSV

local function fromHSV(h: number, s: number, v: number): RGB
	h = h % 360
	local c = v * s
	local x = c * (1 - math.abs((h / 60) % 2 - 1))
	local m = v - c
	local r, g, b
	if h < 60 then
		r, g, b = c, x, 0
	elseif h < 120 then
		r, g, b = x, c, 0
	elseif h < 180 then
		r, g, b = 0, c, x
	elseif h < 240 then
		r, g, b = 0, x, c
	elseif h < 300 then
		r, g, b = x, 0, c
	else
		r, g, b = c, 0, x
	end
	return { math.floor((r + m) * 255 + 0.5), math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5) }
end
TowerStyle.fromHSV = fromHSV

-- A strong red reads as "this kills you": keep it for kill bricks only.
function TowerStyle.isDanger(c: RGB): boolean
	local h, s, v = toHSV(c)
	return (h >= 342 or h <= 14) and s >= 0.6 and v >= 0.6
end

-- One palette colour seen through a tower's mood. Never lands on "danger red": it is pushed
-- to orange instead.
function TowerStyle.shift(c: RGB, mood: Mood): RGB
	local h, s, v = toHSV(c)
	-- near-greys keep their hue (rotating noise would tint white platforms at random)
	local nh = if s < 0.08 then h else (h + mood.hue) % 360
	local out = fromHSV(nh, math.clamp(s * mood.sat, 0, 1), math.clamp(v * mood.val, 0.16, 1))
	if TowerStyle.isDanger(out) then
		local _, s2, v2 = toHSV(out)
		out = fromHSV(28, s2, v2)
	end
	return out
end

function TowerStyle.mood(tower: number): Mood
	return TowerStyle.Moods[math.clamp(math.floor(tower), 1, #TowerStyle.Moods)]
end

-- The five colours of world look `style` (1..10) on tower `tower`.
function TowerStyle.palette(tower: number, style: number): World
	local w = TowerStyle.Worlds[math.clamp(math.floor(style), 1, #TowerStyle.Worlds)]
	local m = TowerStyle.mood(tower)
	return {
		key = w.key,
		platform = TowerStyle.shift(w.platform, m),
		alt = TowerStyle.shift(w.alt, m),
		accent = TowerStyle.shift(w.accent, m),
		pad = TowerStyle.shift(w.pad, m),
		sky = TowerStyle.shift(w.sky, m),
	}
end

return TowerStyle
