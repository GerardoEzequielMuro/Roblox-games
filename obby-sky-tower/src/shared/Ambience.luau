--!strict
-- Look of the sky at every height of the tower. PURE Luau (no Roblox types: colours are {r, g, b}
-- in 0..255) so tests/visual_test.luau can check it with the standalone luau.exe.
--
-- Each world (10 stages) has one lighting profile. The client samples its camera height every
-- frame and blends the two neighbouring profiles around each world boundary, so climbing takes you
-- from a sunny meadow through a golden desert, a red-lit cave and a starry night to a sunrise.

local Ambience = {}

export type RGB = { number }
export type Profile = {
	clock: number, -- Lighting.ClockTime (0..24)
	brightness: number,
	exposure: number, -- Lighting.ExposureCompensation
	ambient: RGB,
	outdoor: RGB, -- Lighting.OutdoorAmbient
	density: number, -- Atmosphere
	haze: number,
	glare: number,
	atmColor: RGB,
	atmDecay: RGB,
	tint: RGB, -- ColorCorrection.TintColor
	saturation: number,
	contrast: number,
	bloom: number, -- Bloom.Intensity
	bloomSize: number,
	bloomThreshold: number,
	rays: number, -- SunRays.Intensity
	stars: number, -- Sky.StarCount
}

-- One profile per world, in tower order (same order as Config.Themes).
Ambience.Profiles = {
	-- 1 Grassy Hills: clear early afternoon
	{ clock = 14.5, brightness = 2.6, exposure = 0, ambient = { 150, 155, 168 }, outdoor = { 175, 182, 195 }, density = 0.27, haze = 0.8, glare = 0.2, atmColor = { 200, 228, 255 }, atmDecay = { 150, 195, 255 }, tint = { 255, 255, 255 }, saturation = 0.18, contrast = 0.06, bloom = 0.3, bloomSize = 24, bloomThreshold = 1.7, rays = 0.06, stars = 0 },
	-- 2 Candy Land: warm pink late afternoon
	{ clock = 16.4, brightness = 2.7, exposure = 0.05, ambient = { 150, 120, 145 }, outdoor = { 190, 150, 180 }, density = 0.3, haze = 1.0, glare = 0.35, atmColor = { 255, 214, 236 }, atmDecay = { 255, 170, 215 }, tint = { 255, 240, 250 }, saturation = 0.3, contrast = 0.04, bloom = 0.35, bloomSize = 28, bloomThreshold = 1.6, rays = 0.09, stars = 0 },
	-- 3 Frozen Peaks: cold, misty morning
	{ clock = 9.6, brightness = 2.3, exposure = 0.1, ambient = { 125, 145, 175 }, outdoor = { 160, 185, 215 }, density = 0.33, haze = 1.5, glare = 0.1, atmColor = { 215, 236, 255 }, atmDecay = { 170, 205, 245 }, tint = { 232, 243, 255 }, saturation = -0.08, contrast = 0.08, bloom = 0.35, bloomSize = 30, bloomThreshold = 1.5, rays = 0.04, stars = 0 },
	-- 4 Desert Ruins: golden hour
	{ clock = 17.35, brightness = 2.7, exposure = 0, ambient = { 150, 120, 85 }, outdoor = { 200, 160, 110 }, density = 0.3, haze = 1.3, glare = 0.7, atmColor = { 255, 214, 150 }, atmDecay = { 255, 160, 80 }, tint = { 255, 240, 214 }, saturation = 0.2, contrast = 0.1, bloom = 0.35, bloomSize = 26, bloomThreshold = 1.6, rays = 0.16, stars = 0 },
	-- 5 Lava Caves: dark red dusk, glowing embers
	{ clock = 17.7, brightness = 2.2, exposure = 0.1, ambient = { 165, 105, 95 }, outdoor = { 185, 115, 95 }, density = 0.38, haze = 1.9, glare = 0.4, atmColor = { 215, 110, 75 }, atmDecay = { 150, 50, 35 }, tint = { 255, 222, 205 }, saturation = 0.12, contrast = 0.2, bloom = 0.5, bloomSize = 28, bloomThreshold = 1.3, rays = 0.05, stars = 400 },
	-- 6 Ocean Reef: teal, thick "underwater" haze
	{ clock = 12.2, brightness = 2.2, exposure = 0.05, ambient = { 70, 140, 160 }, outdoor = { 90, 175, 195 }, density = 0.38, haze = 1.4, glare = 0.15, atmColor = { 110, 215, 225 }, atmDecay = { 30, 130, 190 }, tint = { 214, 248, 255 }, saturation = 0.24, contrast = 0.05, bloom = 0.4, bloomSize = 30, bloomThreshold = 1.5, rays = 0.12, stars = 0 },
	-- 7 Toxic Factory: sickly green smog at dusk
	{ clock = 17.6, brightness = 2.1, exposure = 0, ambient = { 130, 150, 105 }, outdoor = { 150, 175, 115 }, density = 0.34, haze = 1.7, glare = 0.3, atmColor = { 185, 215, 140 }, atmDecay = { 110, 145, 60 }, tint = { 236, 255, 214 }, saturation = 0.05, contrast = 0.14, bloom = 0.45, bloomSize = 30, bloomThreshold = 1.4, rays = 0.05, stars = 200 },
	-- 8 Cloud Kingdom: bright white morning above the clouds
	{ clock = 8.4, brightness = 2.6, exposure = 0, ambient = { 170, 175, 200 }, outdoor = { 215, 220, 240 }, density = 0.24, haze = 0.8, glare = 0.4, atmColor = { 240, 244, 255 }, atmDecay = { 205, 220, 255 }, tint = { 255, 252, 244 }, saturation = 0.1, contrast = 0.02, bloom = 0.4, bloomSize = 28, bloomThreshold = 1.7, rays = 0.2, stars = 0 },
	-- 9 Neon Space: midnight, stars, neon bloom
	{ clock = 0.2, brightness = 1.4, exposure = 0.1, ambient = { 75, 60, 130 }, outdoor = { 90, 75, 150 }, density = 0.16, haze = 0.4, glare = 0, atmColor = { 40, 28, 90 }, atmDecay = { 16, 10, 48 }, tint = { 236, 228, 255 }, saturation = 0.34, contrast = 0.18, bloom = 0.5, bloomSize = 26, bloomThreshold = 1.35, rays = 0, stars = 5000 },
	-- 10 Rainbow Summit: sunrise gold and pink
	{ clock = 6.35, brightness = 2.5, exposure = 0, ambient = { 160, 135, 150 }, outdoor = { 215, 180, 170 }, density = 0.25, haze = 1.0, glare = 0.6, atmColor = { 255, 226, 190 }, atmDecay = { 255, 150, 170 }, tint = { 255, 246, 236 }, saturation = 0.34, contrast = 0.08, bloom = 0.4, bloomSize = 28, bloomThreshold = 1.6, rays = 0.22, stars = 800 },
} :: { Profile }

-- The blend starts BELOW the boundary pad (you see the next world coming) and ends a little above it.
Ambience.BLEND_BELOW = 22
Ambience.BLEND_ABOVE = 8

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpRGB(a: RGB, b: RGB, t: number): RGB
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

-- Shortest way round the 24 h clock (23 -> 1 goes through midnight, not back through noon).
function Ambience.lerpClock(a: number, b: number, t: number): number
	local d = (b - a) % 24
	if d > 12 then
		d -= 24
	end
	return (a + d * t) % 24
end

-- Heights of the world boundaries (top of pads 10, 20 ... 90) from the pad heights of a map.
function Ambience.bounds(padY: { [number]: number }): { number }
	local out = {}
	local worlds = #Ambience.Profiles
	for w = 1, worlds - 1 do
		local y = padY[w * 10]
		if y == nil then
			break
		end
		table.insert(out, y)
	end
	return out
end

-- Which two worlds the height `y` is between, and how far (0 = all `a`, 1 = all `b`).
function Ambience.blend(y: number, bounds: { number }): (number, number, number)
	local world = 1
	for i, by in bounds do
		if y >= by - Ambience.BLEND_BELOW then
			world = i + 1
		end
	end
	if world == 1 then
		return 1, 1, 0
	end
	local by = bounds[world - 1]
	local t = (y - (by - Ambience.BLEND_BELOW)) / (Ambience.BLEND_BELOW + Ambience.BLEND_ABOVE)
	if t >= 1 then
		return world, world, 0
	end
	t = math.clamp(t, 0, 1)
	return world - 1, world, t * t * (3 - 2 * t) -- smoothstep
end

function Ambience.mix(a: Profile, b: Profile, t: number): Profile
	if t <= 0 then
		return a
	elseif t >= 1 then
		return b
	end
	return {
		clock = Ambience.lerpClock(a.clock, b.clock, t),
		brightness = lerp(a.brightness, b.brightness, t),
		exposure = lerp(a.exposure, b.exposure, t),
		ambient = lerpRGB(a.ambient, b.ambient, t),
		outdoor = lerpRGB(a.outdoor, b.outdoor, t),
		density = lerp(a.density, b.density, t),
		haze = lerp(a.haze, b.haze, t),
		glare = lerp(a.glare, b.glare, t),
		atmColor = lerpRGB(a.atmColor, b.atmColor, t),
		atmDecay = lerpRGB(a.atmDecay, b.atmDecay, t),
		tint = lerpRGB(a.tint, b.tint, t),
		saturation = lerp(a.saturation, b.saturation, t),
		contrast = lerp(a.contrast, b.contrast, t),
		bloom = lerp(a.bloom, b.bloom, t),
		bloomSize = lerp(a.bloomSize, b.bloomSize, t),
		bloomThreshold = lerp(a.bloomThreshold, b.bloomThreshold, t),
		rays = lerp(a.rays, b.rays, t),
		stars = lerp(a.stars, b.stars, t),
	}
end

-- The profile to show at height `y`. `profiles` = the ten profiles of the tower in climbing order
-- (default: Ambience.Profiles, i.e. tower 1).
function Ambience.sample(y: number, bounds: { number }, profiles: { Profile }?): Profile
	local list = profiles or Ambience.Profiles
	local a, b, t = Ambience.blend(y, bounds)
	return Ambience.mix(list[a], list[b], t)
end

-- A tower's mood (Shared/TowerStyle.Moods) applied on top of a world profile. A neutral mood
-- returns the profile itself. The result always stays bright enough to read the obstacles.
export type Mood = {
	clock: number,
	clockMix: number,
	bright: number,
	tint: RGB,
	haze: RGB,
	density: number,
	saturation: number,
	stars: number,
}
Ambience.MIN_BRIGHTNESS = 1.1
Ambience.MIN_AMBIENT_SUM = 210

function Ambience.grade(p: Profile, m: Mood): Profile
	if m.clockMix <= 0 and m.bright == 1 and m.density == 0 and m.saturation == 0 and m.stars == 0 and m.tint[1] + m.tint[2] + m.tint[3] == 765 then
		return p
	end
	local function mul(a: RGB, b: RGB): RGB
		return { a[1] * b[1] / 255, a[2] * b[2] / 255, a[3] * b[3] / 255 }
	end
	local light = math.max(m.bright, 0.8)
	local ambient = { p.ambient[1] * light, p.ambient[2] * light, p.ambient[3] * light }
	local sum = ambient[1] + ambient[2] + ambient[3]
	if sum < Ambience.MIN_AMBIENT_SUM then
		local k = Ambience.MIN_AMBIENT_SUM / math.max(sum, 1)
		ambient = { math.min(255, ambient[1] * k), math.min(255, ambient[2] * k), math.min(255, ambient[3] * k) }
	end
	return {
		clock = Ambience.lerpClock(p.clock, m.clock, m.clockMix),
		brightness = math.max(Ambience.MIN_BRIGHTNESS, p.brightness * m.bright),
		exposure = p.exposure,
		ambient = ambient,
		outdoor = { p.outdoor[1] * light, p.outdoor[2] * light, p.outdoor[3] * light },
		density = math.clamp(p.density + m.density, 0.12, 0.5),
		haze = p.haze,
		glare = p.glare,
		atmColor = lerpRGB(p.atmColor, m.haze, 0.55),
		atmDecay = lerpRGB(p.atmDecay, m.haze, 0.45),
		tint = mul(p.tint, m.tint),
		saturation = math.clamp(p.saturation + m.saturation, -0.3, 0.5),
		contrast = p.contrast,
		bloom = p.bloom,
		bloomSize = p.bloomSize,
		bloomThreshold = p.bloomThreshold,
		rays = p.rays,
		stars = math.min(10000, p.stars + m.stars),
	}
end

-- The world (1..10) whose look dominates at height `y`.
function Ambience.worldAt(y: number, bounds: { number }): number
	local a, b, t = Ambience.blend(y, bounds)
	return if t >= 0.5 then b else a
end

return Ambience
