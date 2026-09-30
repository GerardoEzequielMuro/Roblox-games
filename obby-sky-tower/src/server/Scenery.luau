--!strict
-- Everything you look at but never stand on: floating set pieces per world, ornaments on the core
-- pillar, the halo "gates" between worlds, the lobby island dressing and the props hanging under
-- the platforms. Positions come from the pure Shared/DecorPlan (unit-tested to stay out of the
-- lane); this file only turns them into parts.
--
-- Rules that keep it safe and cheap:
--   * every part made by `deco` is anchored with CanCollide / CanTouch / CanQuery off and no
--     shadow, so scenery can never change how a stage plays or block the camera;
--   * no uploaded assets: Parts, built-in SpecialMesh shapes, native materials and the particle
--     textures that ship with Roblox (rbxasset://);
--   * part / light / emitter counts are capped (checked by the Studio playtest).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local DecorPlan = require(ReplicatedStorage.Shared.DecorPlan)
local TowerStyle = require(ReplicatedStorage.Shared.TowerStyle)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Powerups = require(ReplicatedStorage.Shared.Powerups)
local Perks = require(ReplicatedStorage.Shared.Perks)

local Scenery = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(255, 255, 255)
local GOLD = rgb(255, 205, 70)

type Rng = Layout.Rng

---------------------------------------------------------------------------------------------
-- part helpers
---------------------------------------------------------------------------------------------
-- While a list is being recorded, every decoration part made goes into it (see withMood).
local recording: { BasePart }? = nil

local function deco(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	if recording then
		table.insert(recording, p)
	end
	return p
end
Scenery.deco = deco

-- A part you can stand on (shop decks, the lounge floor, base islands).
local function solid(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = deco(parent, size, cf, color, material)
	p.CanCollide = true
	p.CanQuery = true
	return p
end

-- Runs `build` and then repaints every decoration part it made with the tower's mood (hue /
-- saturation / value shift, Shared/TowerStyle): the scenery of each tower is a different colour
-- in the parts themselves, which still shows with graphics at minimum. Tower 1 is left as is.
local function withMood(tower: number, build: () -> ())
	if tower <= 1 then
		build()
		return
	end
	local outer = recording
	local list: { BasePart } = {}
	recording = list
	build()
	recording = outer
	local mood = TowerStyle.mood(tower)
	for _, part in list do
		local c = part.Color
		local shifted = TowerStyle.shift({ math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }, mood)
		part.Color = Color3.fromRGB(shifted[1], shifted[2], shifted[3])
		if outer then
			table.insert(outer, part)
		end
	end
end
Scenery.withMood = withMood

type LocFn = (label: Instance, key: string, args: { [string]: any }?) -> ()

-- Upright cylinder: `cf` is the centre, Y is the axis.
local function cyl(parent: Instance, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = deco(parent, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = deco(parent, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Ellipsoid (built-in sphere mesh, no asset): flat clouds, domes, gumdrops.
local function blob(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = deco(parent, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Cone pointing up (built-in wedge-free trick: a very tapered FileMesh is an asset, so cones are
-- stacked shrinking cylinders instead).
local function cone(parent: Instance, diameter: number, height: number, base: CFrame, color: Color3, material: Enum.Material?, steps: number?)
	local n = steps or 3
	for i = 1, n do
		local k = 1 - (i - 1) / n
		cyl(parent, diameter * k, height / n, base * CFrame.new(0, (i - 0.5) * height / n, 0), color, material)
	end
end

local lightCount, emitterCount = 0, 0

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	lightCount += 1
end

type EmitterOpts = {
	texture: string,
	color: Color3,
	color2: Color3?,
	rate: number,
	life: number,
	speed: number,
	size: number,
	size2: number?,
	spread: number?,
	accel: Vector3?,
	emission: number?,
	transparency: number?,
	face: Enum.NormalId?,
}
local function emitter(parent: BasePart, o: EmitterOpts): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.texture
	e.Color = ColorSequence.new(o.color, o.color2 or o.color)
	e.Rate = o.rate
	e.Lifetime = NumberRange.new(o.life * 0.7, o.life)
	e.Speed = NumberRange.new(o.speed * 0.6, o.speed)
	e.Size = NumberSequence.new(o.size, o.size2 or o.size)
	e.SpreadAngle = Vector2.new(o.spread or 20, o.spread or 20)
	e.Acceleration = o.accel or Vector3.zero
	e.LightEmission = o.emission or 0
	local t = o.transparency or 0
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, t),
		NumberSequenceKeypoint.new(0.8, t),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.EmissionDirection = o.face or Enum.NormalId.Top
	e.Parent = parent
	emitterCount += 1
	return e
end

-- Floating island: a top disc over rock that tapers to a point.
local function island(parent: Instance, cf: CFrame, r: number, top: Color3, topMat: Enum.Material, rock: Color3, rockMat: Enum.Material?)
	cyl(parent, r * 2, 2.4, cf * CFrame.new(0, -1.2, 0), top, topMat)
	local mat = rockMat or Enum.Material.Slate
	cyl(parent, r * 1.7, r * 0.45, cf * CFrame.new(0, -2.4 - r * 0.225, 0), rock, mat)
	cyl(parent, r * 1.1, r * 0.5, cf * CFrame.new(r * 0.08, -2.4 - r * 0.7, 0), rock:Lerp(Color3.new(), 0.12), mat)
	cyl(parent, r * 0.5, r * 0.5, cf * CFrame.new(r * 0.12, -2.4 - r * 1.2, -r * 0.05), rock:Lerp(Color3.new(), 0.22), mat)
end

local function tree(parent: Instance, base: CFrame, h: number, trunk: Color3, leaves: Color3, leafMat: Enum.Material?)
	cyl(parent, h * 0.18, h, base * CFrame.new(0, h / 2, 0), trunk, Enum.Material.Wood)
	ball(parent, h * 0.95, (base * CFrame.new(0, h + h * 0.25, 0)).Position, leaves, leafMat or Enum.Material.Grass)
end

local function pine(parent: Instance, base: CFrame, h: number, leaves: Color3)
	cyl(parent, h * 0.12, h * 0.3, base * CFrame.new(0, h * 0.15, 0), rgb(110, 80, 60), Enum.Material.Wood)
	cone(parent, h * 0.62, h * 0.8, base * CFrame.new(0, h * 0.25, 0), leaves, Enum.Material.Grass, 3)
end

---------------------------------------------------------------------------------------------
-- outer set pieces, one builder per world. `cf` faces the tower, `r` is the footprint radius.
---------------------------------------------------------------------------------------------
type OuterBuilder = (parent: Instance, cf: CFrame, r: number, variant: number, rng: Rng) -> ()
local Outer: { OuterBuilder } = {}

-- 1 Grassy Hills: meadow islands with trees, one windmill in three
Outer[1] = function(parent, cf, r, variant, rng)
	island(parent, cf, r, rgb(105, 200, 90), Enum.Material.Grass, rgb(140, 105, 75))
	if variant == 3 then
		local h = r * 1.3
		cone(parent, r * 0.55, h, cf, rgb(245, 235, 215), Enum.Material.SmoothPlastic, 2)
		cone(parent, r * 0.5, r * 0.35, cf * CFrame.new(0, h, 0), rgb(200, 80, 70), Enum.Material.SmoothPlastic, 2)
		local hub = cf * CFrame.new(0, h * 0.85, -r * 0.3)
		for i = 0, 3 do
			deco(parent, Vector3.new(r * 0.16, r * 0.95, 0.4), hub * CFrame.Angles(0, 0, i * math.pi / 2 + 0.4) * CFrame.new(0, r * 0.5, 0), rgb(250, 245, 235), Enum.Material.Wood)
		end
	else
		for i = 1, 3 do
			local a = rng.range(0, math.pi * 2)
			local d = rng.range(0.15, 0.6) * r
			tree(parent, cf * CFrame.new(math.cos(a) * d, 0, math.sin(a) * d), rng.range(0.35, 0.55) * r, rgb(130, 90, 60), rgb(70, 175, 80):Lerp(rgb(190, 220, 90), rng.next() * 0.5))
		end
		ball(parent, r * 0.3, (cf * CFrame.new(-r * 0.5, r * 0.08, r * 0.3)).Position, rgb(150, 150, 155), Enum.Material.Slate)
	end
end

-- 2 Candy Land: lollipops on frosting islands, cupcakes
Outer[2] = function(parent, cf, r, variant, rng)
	local pinks = { rgb(255, 120, 190), rgb(120, 220, 255), rgb(255, 230, 90), rgb(170, 130, 255) }
	if variant == 3 then
		-- cupcake
		cyl(parent, r * 1.5, r * 0.5, cf * CFrame.new(0, -r * 0.15, 0), rgb(255, 230, 150))
		cyl(parent, r * 1.25, r * 0.5, cf * CFrame.new(0, -r * 0.6, 0), rgb(245, 205, 120))
		blob(parent, Vector3.new(r * 1.9, r * 0.8, r * 1.9), cf * CFrame.new(0, r * 0.25, 0), rgb(255, 150, 210))
		blob(parent, Vector3.new(r * 1.35, r * 0.7, r * 1.35), cf * CFrame.new(0, r * 0.7, 0), rgb(255, 245, 250))
		blob(parent, Vector3.new(r * 0.8, r * 0.55, r * 0.8), cf * CFrame.new(0, r * 1.1, 0), rgb(255, 150, 210))
		ball(parent, r * 0.35, (cf * CFrame.new(0, r * 1.45, 0)).Position, rgb(230, 30, 60))
	else
		island(parent, cf, r, rgb(255, 245, 250), Enum.Material.SmoothPlastic, rgb(255, 150, 210), Enum.Material.SmoothPlastic)
		for i = 1, 2 do
			local x = (i - 1.5) * r * 0.8
			local h = rng.range(0.9, 1.4) * r
			local c = pinks[rng.int(1, #pinks)]
			cyl(parent, r * 0.07, h, cf * CFrame.new(x, h / 2, 0), WHITE)
			local face = cf * CFrame.new(x, h + r * 0.3, 0) * CFrame.Angles(math.pi / 2, 0, 0)
			cyl(parent, r * 0.75, r * 0.12, face, c)
			cyl(parent, r * 0.45, r * 0.14, face, WHITE)
			cyl(parent, r * 0.2, r * 0.16, face, c)
		end
		for i = 1, 3 do
			local a = rng.range(0, math.pi * 2)
			blob(parent, Vector3.new(r * 0.26, r * 0.22, r * 0.26), cf * CFrame.new(math.cos(a) * r * 0.6, r * 0.05, math.sin(a) * r * 0.6), pinks[rng.int(1, #pinks)])
		end
	end
end

-- 3 Frozen Peaks: icebergs, snowy islands with pines and a snowman
Outer[3] = function(parent, cf, r, variant, rng)
	if variant == 3 then
		island(parent, cf, r, rgb(245, 250, 255), Enum.Material.Snow, rgb(140, 190, 230), Enum.Material.Ice)
		for i = 1, 3 do
			local a = rng.range(0, math.pi * 2)
			local d = rng.range(0.2, 0.6) * r
			pine(parent, cf * CFrame.new(math.cos(a) * d, 0, math.sin(a) * d), rng.range(0.5, 0.8) * r, rgb(230, 245, 250):Lerp(rgb(70, 140, 110), 0.55))
		end
		local s = cf * CFrame.new(r * 0.5, 0, -r * 0.4)
		ball(parent, r * 0.3, (s * CFrame.new(0, r * 0.13, 0)).Position, WHITE, Enum.Material.Snow)
		ball(parent, r * 0.22, (s * CFrame.new(0, r * 0.34, 0)).Position, WHITE, Enum.Material.Snow)
		ball(parent, r * 0.15, (s * CFrame.new(0, r * 0.5, 0)).Position, WHITE, Enum.Material.Snow)
	else
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2 + rng.range(-0.3, 0.3)
			local d = if i == 1 then 0 else rng.range(0.3, 0.6) * r
			local h = if i == 1 then r * 1.9 else rng.range(0.7, 1.4) * r
			local w = if i == 1 then r * 0.6 else rng.range(0.3, 0.5) * r
			local shard = deco(parent, Vector3.new(w, h, w), cf * CFrame.new(math.cos(a) * d, h * 0.1, math.sin(a) * d) * CFrame.Angles(rng.range(-0.25, 0.25), rng.range(0, 1.5), rng.range(-0.25, 0.25)), rgb(170, 225, 255):Lerp(WHITE, rng.next() * 0.4), Enum.Material.Ice)
			shard.Transparency = 0.12
		end
		blob(parent, Vector3.new(r * 1.6, r * 0.35, r * 1.6), cf * CFrame.new(0, -r * 0.35, 0), rgb(245, 250, 255), Enum.Material.Snow)
	end
end

-- 4 Desert Ruins: stepped pyramids with a glowing capstone, mesas with broken columns
Outer[4] = function(parent, cf, r, variant, rng)
	local sand = rgb(235, 200, 130)
	local stone = rgb(205, 165, 100)
	if variant == 3 then
		for i = 0, 3 do
			local w = r * 1.7 * (1 - i * 0.24)
			deco(parent, Vector3.new(w, r * 0.32, w), cf * CFrame.new(0, -r * 0.4 + i * r * 0.32, 0), if i % 2 == 0 then sand else stone, Enum.Material.Sandstone)
		end
		local cap = deco(parent, Vector3.new(r * 0.3, r * 0.3, r * 0.3), cf * CFrame.new(0, r * 0.95, 0) * CFrame.Angles(0, math.pi / 4, 0), rgb(80, 230, 240), Enum.Material.Neon)
		light(cap, rgb(80, 230, 240), 30, 1.5)
		cyl(parent, r * 1.2, r * 0.5, cf * CFrame.new(0, -r * 0.8, 0), stone:Lerp(Color3.new(), 0.15), Enum.Material.Sandstone)
	else
		island(parent, cf, r, sand, Enum.Material.Sand, rgb(190, 140, 80), Enum.Material.Sandstone)
		local n = 4
		for i = 1, n do
			local x = (i - (n + 1) / 2) * r * 0.42
			local h = if rng.next() < 0.35 then rng.range(0.25, 0.5) * r else r * 0.9
			cyl(parent, r * 0.16, h, cf * CFrame.new(x, h / 2, 0), rgb(240, 220, 175), Enum.Material.Sandstone)
			if h > r * 0.8 then
				deco(parent, Vector3.new(r * 0.24, r * 0.08, r * 0.24), cf * CFrame.new(x, h + r * 0.04, 0), stone, Enum.Material.Sandstone)
			end
		end
		deco(parent, Vector3.new(r * 0.9, r * 0.12, r * 0.22), cf * CFrame.new(-r * 0.2, r * 1.0, 0), stone, Enum.Material.Sandstone)
		-- a palm
		local p = cf * CFrame.new(r * 0.55, 0, r * 0.45)
		cyl(parent, r * 0.07, r * 0.7, p * CFrame.new(0, r * 0.35, 0) * CFrame.Angles(0, 0, 0.12), rgb(150, 110, 70), Enum.Material.Wood)
		for i = 0, 3 do
			deco(parent, Vector3.new(r * 0.5, 0.3, r * 0.13), p * CFrame.new(0, r * 0.72, 0) * CFrame.Angles(0, i * math.pi / 2, -0.35) * CFrame.new(r * 0.22, 0, 0), rgb(70, 170, 90), Enum.Material.Grass)
		end
	end
end

-- 5 Lava Caves: volcanic rocks with a lava pool, basalt spikes with glowing cores
Outer[5] = function(parent, cf, r, variant, rng)
	local basalt = rgb(62, 54, 60)
	local lava = rgb(255, 110, 25)
	if variant == 3 then
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			local d = if i == 1 then 0 else rng.range(0.35, 0.6) * r
			local h = if i == 1 then r * 2 else rng.range(0.8, 1.5) * r
			local w = if i == 1 then r * 0.55 else rng.range(0.25, 0.42) * r
			local tilt = CFrame.Angles(rng.range(-0.2, 0.2), rng.range(0, 1.5), rng.range(-0.2, 0.2))
			deco(parent, Vector3.new(w, h, w), cf * CFrame.new(math.cos(a) * d, 0, math.sin(a) * d) * tilt, basalt, Enum.Material.Basalt)
			if i <= 2 then
				deco(parent, Vector3.new(w * 0.24, h * 0.8, w + 0.2), cf * CFrame.new(math.cos(a) * d, 0, math.sin(a) * d) * tilt, lava, Enum.Material.Neon)
			end
		end
	else
		cyl(parent, r * 1.9, r * 0.5, cf * CFrame.new(0, -r * 0.25, 0), basalt, Enum.Material.Basalt)
		cyl(parent, r * 1.2, r * 0.6, cf * CFrame.new(0, -r * 0.8, 0), basalt:Lerp(Color3.new(), 0.2), Enum.Material.Basalt)
		cyl(parent, r * 0.5, r * 0.5, cf * CFrame.new(r * 0.1, -r * 1.3, 0), basalt:Lerp(Color3.new(), 0.3), Enum.Material.Basalt)
		local pool = cyl(parent, r * 1.2, 0.5, cf * CFrame.new(0, 0.1, 0), lava, Enum.Material.Neon)
		light(pool, lava, 36, 2)
		emitter(pool, { texture = FIRE, color = rgb(255, 190, 60), color2 = rgb(255, 60, 20), rate = 5, life = 2.2, speed = 7, size = 1.6, size2 = 0.2, spread = 25, emission = 1 })
		-- a lava fall off the edge
		deco(parent, Vector3.new(r * 0.22, r * 1.5, 0.5), cf * CFrame.new(0, -r * 0.75, -r * 0.93), lava, Enum.Material.Neon)
		for i = 1, 3 do
			local a = i * 2.1
			deco(parent, Vector3.new(r * 0.28, rng.range(0.4, 0.8) * r, r * 0.28), cf * CFrame.new(math.cos(a) * r * 0.78, r * 0.2, math.sin(a) * r * 0.78) * CFrame.Angles(0.15, a, 0.1), basalt:Lerp(Color3.new(), 0.1), Enum.Material.Basalt)
		end
	end
end

-- 6 Ocean Reef: coral rocks with bubbles, giant jellyfish
Outer[6] = function(parent, cf, r, variant, rng)
	local corals = { rgb(255, 120, 140), rgb(255, 170, 80), rgb(190, 110, 255), rgb(255, 230, 120) }
	if variant == 3 then
		local c = corals[rng.int(1, #corals)]
		local dome = blob(parent, Vector3.new(r * 1.5, r * 0.9, r * 1.5), cf * CFrame.new(0, r * 0.4, 0), c, Enum.Material.Neon)
		dome.Transparency = 0.35
		blob(parent, Vector3.new(r * 1.0, r * 0.5, r * 1.0), cf * CFrame.new(0, r * 0.35, 0), WHITE, Enum.Material.Neon).Transparency = 0.5
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			local h = rng.range(1.0, 1.9) * r
			local tentacle = deco(parent, Vector3.new(r * 0.07, h, r * 0.07), cf * CFrame.new(math.cos(a) * r * 0.42, r * 0.2 - h / 2, math.sin(a) * r * 0.42) * CFrame.Angles(rng.range(-0.12, 0.12), 0, rng.range(-0.12, 0.12)), c:Lerp(WHITE, 0.3), Enum.Material.Neon)
			tentacle.Transparency = 0.3
		end
		light(dome, c, 28, 1.2)
	else
		blob(parent, Vector3.new(r * 2, r * 0.9, r * 2), cf * CFrame.new(0, -r * 0.3, 0), rgb(235, 215, 170), Enum.Material.Sand)
		blob(parent, Vector3.new(r * 1.2, r * 1.1, r * 1.2), cf * CFrame.new(r * 0.1, -r * 0.8, 0), rgb(90, 140, 150), Enum.Material.Slate)
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + rng.range(-0.4, 0.4)
			local base = cf * CFrame.new(math.cos(a) * r * 0.5, 0, math.sin(a) * r * 0.5)
			local c = corals[rng.int(1, #corals)]
			local h = rng.range(0.5, 0.9) * r
			for j = -1, 1 do
				cyl(parent, r * 0.1, h * (1 - math.abs(j) * 0.25), base * CFrame.Angles(0, 0, j * 0.45) * CFrame.new(0, h * 0.45, 0), c)
			end
		end
		-- seaweed + bubbles
		for i = 1, 2 do
			deco(parent, Vector3.new(r * 0.12, r * 1.3, 0.3), cf * CFrame.new((i - 1.5) * r * 0.5, r * 0.5, r * 0.3) * CFrame.Angles(0.1, i, 0.1), rgb(50, 170, 120), Enum.Material.Grass)
		end
		local src = deco(parent, Vector3.new(r * 0.8, 0.4, r * 0.8), cf * CFrame.new(0, r * 0.2, 0), WHITE)
		src.Transparency = 1
		emitter(src, { texture = SPARKLES, color = rgb(220, 250, 255), rate = 4, life = 4, speed = 6, size = 0.9, size2 = 1.6, spread = 12, emission = 0.6, transparency = 0.3 })
	end
end

-- 7 Toxic Factory: smokestack platforms, goo tanks
Outer[7] = function(parent, cf, r, variant, rng)
	local steel = rgb(110, 118, 128)
	local goo = rgb(170, 255, 60)
	if variant == 3 then
		local tank = cyl(parent, r * 1.2, r * 1.5, cf * CFrame.new(0, r * 0.2, 0), steel, Enum.Material.Metal)
		cyl(parent, r * 1.25, r * 0.5, cf * CFrame.new(0, r * 0.2, 0), goo, Enum.Material.Neon)
		cyl(parent, r * 1.3, r * 0.12, cf * CFrame.new(0, r * 0.97, 0), rgb(70, 75, 85), Enum.Material.DiamondPlate)
		cyl(parent, r * 1.3, r * 0.12, cf * CFrame.new(0, -r * 0.57, 0), rgb(70, 75, 85), Enum.Material.DiamondPlate)
		-- pipe to nowhere
		cyl(parent, r * 0.2, r * 1.2, cf * CFrame.new(r * 0.8, -r * 0.2, 0), rgb(200, 170, 60), Enum.Material.Metal)
		deco(parent, Vector3.new(r * 0.5, r * 0.2, r * 0.2), cf * CFrame.new(r * 0.62, r * 0.4, 0), rgb(200, 170, 60), Enum.Material.Metal)
		-- drip
		deco(parent, Vector3.new(r * 0.12, r * 1.1, r * 0.12), cf * CFrame.new(0, -r * 1.15, 0), goo, Enum.Material.Neon)
		light(tank, goo, 30, 1.4)
	else
		deco(parent, Vector3.new(r * 1.8, r * 0.18, r * 1.4), cf * CFrame.new(0, -r * 0.09, 0), steel, Enum.Material.DiamondPlate)
		deco(parent, Vector3.new(r * 1.5, r * 0.5, r * 1.1), cf * CFrame.new(0, -r * 0.43, 0), rgb(80, 86, 96), Enum.Material.Metal)
		-- hazard stripe along the front edge
		for i = -3, 3 do
			deco(parent, Vector3.new(r * 0.24, r * 0.2, 0.3), cf * CFrame.new(i * r * 0.25, -r * 0.09, -r * 0.71), if i % 2 == 0 then rgb(255, 215, 40) else rgb(35, 35, 40))
		end
		for i = 1, 2 do
			local x = (i - 1.5) * r * 0.9
			local h = rng.range(1.2, 1.9) * r
			local stack = cyl(parent, r * 0.36, h, cf * CFrame.new(x, h / 2, 0), rgb(150, 90, 70), Enum.Material.Brick)
			cyl(parent, r * 0.4, r * 0.18, cf * CFrame.new(x, h * 0.75, 0), rgb(240, 240, 240))
			cyl(parent, r * 0.4, r * 0.18, cf * CFrame.new(x, h * 0.75 - r * 0.2, 0), rgb(220, 60, 60))
			if i == 1 then
				local top = deco(parent, Vector3.new(r * 0.3, 0.4, r * 0.3), cf * CFrame.new(x, h, 0), WHITE)
				top.Transparency = 1
				emitter(top, { texture = SMOKE, color = rgb(170, 220, 90), color2 = rgb(90, 110, 70), rate = 3, life = 5, speed = 6, size = 3, size2 = 9, spread = 10, transparency = 0.45 })
			end
			stack.Name = "Stack"
		end
		-- barrels
		for i = 1, 3 do
			cyl(parent, r * 0.2, r * 0.28, cf * CFrame.new(rng.range(-0.6, 0.6) * r, r * 0.14, r * 0.45), if i == 2 then goo else rgb(255, 215, 40), if i == 2 then Enum.Material.Neon else Enum.Material.Metal)
		end
	end
end

-- 8 Cloud Kingdom: golden towers on clouds, cloud gates
Outer[8] = function(parent, cf, r, variant, rng)
	local function cloud(at: CFrame, s: number)
		blob(parent, Vector3.new(s * 2, s * 0.7, s * 1.5), at, WHITE)
		blob(parent, Vector3.new(s * 1.2, s * 0.8, s * 1.1), at * CFrame.new(-s * 0.55, s * 0.18, s * 0.1), WHITE)
		blob(parent, Vector3.new(s * 1.3, s * 0.9, s * 1.2), at * CFrame.new(s * 0.5, s * 0.2, -s * 0.1), rgb(240, 244, 255))
		blob(parent, Vector3.new(s * 0.9, s * 0.6, s * 0.9), at * CFrame.new(0, s * 0.36, 0), WHITE)
	end
	cloud(cf * CFrame.new(0, -r * 0.2, 0), r)
	if variant == 3 then
		for _, x in { -r * 0.45, r * 0.45 } do
			cyl(parent, r * 0.2, r * 1.2, cf * CFrame.new(x, r * 0.6, 0), WHITE, Enum.Material.Marble)
			ball(parent, r * 0.26, (cf * CFrame.new(x, r * 1.28, 0)).Position, GOLD, Enum.Material.Neon)
		end
		deco(parent, Vector3.new(r * 1.2, r * 0.16, r * 0.26), cf * CFrame.new(0, r * 1.1, 0), GOLD, Enum.Material.SmoothPlastic)
	else
		local h = rng.range(1.1, 1.6) * r
		local tower = cyl(parent, r * 0.5, h, cf * CFrame.new(0, h / 2, 0), WHITE, Enum.Material.Marble)
		cyl(parent, r * 0.58, r * 0.1, cf * CFrame.new(0, h * 0.62, 0), GOLD)
		cyl(parent, r * 0.66, r * 0.12, cf * CFrame.new(0, h, 0), rgb(235, 238, 250), Enum.Material.Marble)
		cone(parent, r * 0.62, r * 0.7, cf * CFrame.new(0, h + r * 0.06, 0), rgb(120, 170, 255), Enum.Material.SmoothPlastic, 3)
		ball(parent, r * 0.12, (cf * CFrame.new(0, h + r * 0.82, 0)).Position, GOLD, Enum.Material.Neon)
		-- glowing windows
		for i = 0, 1 do
			deco(parent, Vector3.new(r * 0.1, r * 0.2, r * 0.52), cf * CFrame.new(0, h * (0.35 + i * 0.4), 0) * CFrame.Angles(0, i * math.pi / 2, 0), rgb(255, 230, 140), Enum.Material.Neon)
		end
		tower.Name = "CloudTower"
	end
end

-- 9 Neon Space: ringed planets with a moon, neon crystal frames
Outer[9] = function(parent, cf, r, variant, rng)
	local neons = { rgb(0, 255, 230), rgb(255, 60, 220), rgb(255, 240, 80), rgb(120, 110, 255) }
	local c = neons[rng.int(1, #neons)]
	if variant == 3 then
		-- wireframe cube: 12 neon edges
		local s = r * 1.1
		local tilt = cf * CFrame.Angles(0.5, 0.7, 0.2)
		for _, axis in { "x", "y", "z" } do
			for _, a in { -1, 1 } do
				for _, b in { -1, 1 } do
					local size, offset
					if axis == "x" then
						size, offset = Vector3.new(s, 0.5, 0.5), Vector3.new(0, a * s / 2, b * s / 2)
					elseif axis == "y" then
						size, offset = Vector3.new(0.5, s, 0.5), Vector3.new(a * s / 2, 0, b * s / 2)
					else
						size, offset = Vector3.new(0.5, 0.5, s), Vector3.new(a * s / 2, b * s / 2, 0)
					end
					deco(parent, size, tilt * CFrame.new(offset), c, Enum.Material.Neon)
				end
			end
		end
		local core = ball(parent, s * 0.35, tilt.Position, neons[rng.int(1, #neons)], Enum.Material.Neon)
		light(core, c, 34, 1.6)
	else
		local planet = ball(parent, r * 1.3, cf.Position, rgb(60, 45, 120):Lerp(c, 0.35), Enum.Material.SmoothPlastic)
		blob(parent, Vector3.new(r * 0.5, r * 0.3, r * 0.5), cf * CFrame.new(r * 0.3, r * 0.45, -r * 0.35), c, Enum.Material.Neon).Transparency = 0.2
		local tilt = cf * CFrame.Angles(rng.range(0.2, 0.5), 0, rng.range(-0.4, 0.4))
		local ring = cyl(parent, r * 2.4, 0.4, tilt, c, Enum.Material.Neon)
		ring.Transparency = 0.45
		cyl(parent, r * 1.9, 0.5, tilt, rgb(255, 255, 255), Enum.Material.Neon).Transparency = 0.7
		ball(parent, r * 0.3, (cf * CFrame.new(r * 1.2, r * 0.7, 0)).Position, rgb(220, 220, 235), Enum.Material.Slate)
		light(planet, c, 30, 1)
	end
end

-- 10 Rainbow Summit: rainbow arches, golden crystal islands
Outer[10] = function(parent, cf, r, variant, rng)
	local bands = { rgb(255, 80, 90), rgb(255, 190, 50), rgb(90, 220, 110), rgb(80, 160, 255), rgb(190, 100, 255) }
	if variant == 1 then
		local segs = 9
		for b, color in bands do
			local radius = r * (1.0 - (b - 1) * 0.11)
			for i = 0, segs - 1 do
				local a = (i + 0.5) / segs * math.pi
				local len = math.pi * radius / segs * 1.08
				local seg = deco(parent, Vector3.new(len, r * 0.1, r * 0.16), cf * CFrame.new(math.cos(a) * radius, math.sin(a) * radius - r * 0.4, 0) * CFrame.Angles(0, 0, a + math.pi / 2), color, Enum.Material.Neon)
				seg.Transparency = 0.15
			end
		end
		for _, x in { -r * 0.85, r * 0.85 } do
			blob(parent, Vector3.new(r * 0.9, r * 0.4, r * 0.7), cf * CFrame.new(x, -r * 0.4, 0), WHITE)
		end
	else
		island(parent, cf, r * 0.85, rgb(255, 215, 90), Enum.Material.SmoothPlastic, rgb(255, 150, 130), Enum.Material.SmoothPlastic)
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			local d = if i == 1 then 0 else r * 0.42
			local h = if i == 1 then r * 1.5 else rng.range(0.5, 1.0) * r
			local w = if i == 1 then r * 0.3 else r * 0.18
			local crystal = deco(parent, Vector3.new(w, h, w), cf * CFrame.new(math.cos(a) * d, h * 0.4, math.sin(a) * d) * CFrame.Angles(rng.range(-0.3, 0.3), a, rng.range(-0.3, 0.3)), bands[((i - 1) % #bands) + 1], Enum.Material.Neon)
			crystal.Transparency = 0.1
			if i == 1 then
				light(crystal, WHITE, 34, 1.5)
				emitter(crystal, { texture = SPARKLES, color = rgb(255, 240, 150), color2 = rgb(255, 130, 220), rate = 5, life = 2.5, speed = 4, size = 1.2, size2 = 0.2, spread = 180, emission = 0.9 })
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- core ornaments. `cf` sits on the pillar surface: -Z points into the pillar, +Y is up.
---------------------------------------------------------------------------------------------
type CoreBuilder = (parent: Instance, cf: CFrame, s: number, variant: number, rng: Rng) -> ()
local Core: { CoreBuilder } = {}

-- Axis of the tower being built (core ornaments that wrap the whole pillar are centred on it).
local towerAxis = Vector3.zero

local function ringBand(parent: Instance, y: number, thickness: number, extra: number, color: Color3, material: Enum.Material?): Part
	return cyl(parent, Layout.CORE_RADIUS * 2 + extra, thickness, CFrame.new(towerAxis.X, y, towerAxis.Z), color, material)
end

Core[1] = function(parent, cf, s, variant, rng)
	-- vines with leaves; sometimes a mushroom shelf
	local h = s * 3
	deco(parent, Vector3.new(0.7, h, 0.5), cf * CFrame.new(0, 0, 0.2) * CFrame.Angles(0, 0, rng.range(-0.15, 0.15)), rgb(60, 150, 70), Enum.Material.Grass)
	for i = 1, 3 do
		ball(parent, rng.range(1.6, 2.6), (cf * CFrame.new(rng.range(-1.5, 1.5), (i - 2) * h * 0.3, 1)).Position, rgb(80, 185, 85):Lerp(rgb(255, 170, 200), if rng.next() < 0.3 then 0.8 else 0), Enum.Material.Grass)
	end
	if variant == 3 then
		cyl(parent, s * 1.1, 0.8, cf * CFrame.new(0, -h * 0.4, s * 0.4), rgb(230, 80, 70))
		cyl(parent, s * 0.3, 1.4, cf * CFrame.new(0, -h * 0.4 - 1, s * 0.3), rgb(245, 235, 215))
	end
end

Core[2] = function(parent, cf, s, variant, rng)
	if variant == 1 then
		ringBand(parent, cf.Position.Y, 2.2, 1.2, rgb(255, 250, 252))
		ringBand(parent, cf.Position.Y + 3, 1.2, 0.9, rgb(120, 220, 255))
	else
		local colors = { rgb(255, 90, 120), rgb(120, 220, 255), rgb(255, 230, 90), rgb(150, 230, 120) }
		for i = 1, 4 do
			blob(parent, Vector3.new(s * 0.5, s * 0.5, s * 0.4), cf * CFrame.new(rng.range(-s, s) * 0.6, rng.range(-s, s) * 0.6, 0.3), colors[rng.int(1, #colors)])
		end
	end
end

Core[3] = function(parent, cf, s, variant, rng)
	-- snowy ledge with icicles
	blob(parent, Vector3.new(s * 1.6, 1.6, s * 0.9), cf * CFrame.new(0, 0, s * 0.3), rgb(245, 250, 255), Enum.Material.Snow)
	for i = 1, 4 do
		local h = rng.range(0.5, 1.4) * s
		local x = (i - 2.5) * s * 0.36
		local ice = deco(parent, Vector3.new(0.9, h * 0.6, 0.9), cf * CFrame.new(x, -0.6 - h * 0.3, s * 0.35), rgb(190, 235, 255), Enum.Material.Ice)
		ice.Transparency = 0.15
		deco(parent, Vector3.new(0.45, h * 0.5, 0.45), cf * CFrame.new(x, -0.6 - h * 0.6 - h * 0.25, s * 0.35), rgb(215, 245, 255), Enum.Material.Ice).Transparency = 0.2
	end
end

Core[4] = function(parent, cf, s, variant, rng)
	if variant == 1 then
		ringBand(parent, cf.Position.Y, 2.5, 1.6, rgb(200, 160, 100), Enum.Material.Sandstone)
	else
		-- a carved tablet with glowing glyph bars
		deco(parent, Vector3.new(s * 1.2, s * 1.6, 0.8), cf * CFrame.new(0, 0, 0.3), rgb(235, 205, 145), Enum.Material.Sandstone)
		for i = 1, 3 do
			deco(parent, Vector3.new(rng.range(0.4, 0.85) * s, s * 0.14, 0.3), cf * CFrame.new(0, (i - 2) * s * 0.42, 0.85), rgb(80, 225, 235), Enum.Material.Neon)
		end
	end
end

Core[5] = function(parent, cf, s, variant, rng)
	-- glowing cracks in the rock, some dripping embers
	local x = 0
	local y = s * 1.2
	local crackA: Part? = nil
	for i = 1, 4 do
		local len = rng.range(0.5, 0.9) * s
		local a = rng.range(-0.7, 0.7)
		local part = deco(parent, Vector3.new(0.6, len, 0.4), cf * CFrame.new(x + math.sin(a) * len / 2, y - math.cos(a) * len / 2, 0.12) * CFrame.Angles(0, 0, a), rgb(255, 120, 30), Enum.Material.Neon)
		crackA = crackA or part
		x += math.sin(a) * len
		y -= math.cos(a) * len
	end
	if variant == 3 and crackA then
		light(crackA, rgb(255, 120, 40), 22, 1.6)
		emitter(crackA, { texture = FIRE, color = rgb(255, 200, 80), color2 = rgb(255, 70, 20), rate = 3, life = 1.8, speed = 3, size = 0.9, size2 = 0.1, spread = 40, emission = 1, accel = Vector3.new(0, 3, 0), face = Enum.NormalId.Back })
	end
end

Core[6] = function(parent, cf, s, variant, rng)
	local corals = { rgb(255, 120, 140), rgb(255, 170, 80), rgb(190, 110, 255) }
	if variant == 1 then
		-- seaweed
		for i = 1, 3 do
			deco(parent, Vector3.new(0.9, rng.range(1.5, 2.6) * s, 0.4), cf * CFrame.new((i - 2) * 1.6, 0, 0.5) * CFrame.Angles(0, 0, rng.range(-0.2, 0.2)), rgb(50, 170, 120):Lerp(rgb(120, 220, 140), rng.next()), Enum.Material.Grass)
		end
	else
		local c = corals[rng.int(1, #corals)]
		for j = -1, 1 do
			-- tilted out of the pillar (+Z) and fanned sideways
			cyl(parent, 0.8, s * (1.1 - math.abs(j) * 0.3), cf * CFrame.Angles(0.9, 0, j * 0.45) * CFrame.new(0, s * 0.5, 0), c)
		end
		ball(parent, s * 0.35, (cf * CFrame.new(s * 0.5, -s * 0.3, 0.3)).Position, rgb(255, 230, 150), Enum.Material.Sand)
	end
end

Core[7] = function(parent, cf, s, variant, rng)
	if variant == 1 then
		-- hazard band
		ringBand(parent, cf.Position.Y, 1.6, 1.0, rgb(255, 215, 40))
		ringBand(parent, cf.Position.Y + 1.6, 1.6, 1.0, rgb(35, 35, 40))
	else
		-- a pipe with an elbow and a goo drip
		local h = s * 3
		cyl(parent, 1.6, h, cf * CFrame.new(0, 0, 1.6), rgb(140, 148, 158), Enum.Material.Metal)
		cyl(parent, 2.1, 0.8, cf * CFrame.new(0, h * 0.3, 1.6), rgb(200, 170, 60), Enum.Material.Metal)
		cyl(parent, 2.1, 0.8, cf * CFrame.new(0, -h * 0.3, 1.6), rgb(200, 170, 60), Enum.Material.Metal)
		deco(parent, Vector3.new(0.5, s * 0.9, 0.5), cf * CFrame.new(0, -h / 2 - s * 0.45, 1.6), rgb(170, 255, 60), Enum.Material.Neon)
	end
end

Core[8] = function(parent, cf, s, variant, rng)
	if variant == 1 then
		ringBand(parent, cf.Position.Y, 1.2, 1.4, GOLD)
	else
		blob(parent, Vector3.new(s * 1.8, s * 0.8, s * 1.1), cf * CFrame.new(0, 0, s * 0.2), WHITE)
		blob(parent, Vector3.new(s * 1.1, s * 0.7, s * 0.9), cf * CFrame.new(-s * 0.6, s * 0.2, s * 0.3), WHITE)
		blob(parent, Vector3.new(s * 1.0, s * 0.6, s * 0.9), cf * CFrame.new(s * 0.6, s * 0.1, s * 0.3), rgb(235, 240, 255))
	end
end

Core[9] = function(parent, cf, s, variant, rng)
	local neons = { rgb(0, 255, 230), rgb(255, 60, 220), rgb(255, 240, 80) }
	if variant == 1 then
		ringBand(parent, cf.Position.Y, 0.7, 0.8, neons[rng.int(1, #neons)], Enum.Material.Neon)
	else
		-- circuit lines
		local c = neons[rng.int(1, #neons)]
		local h = s * 2.5
		deco(parent, Vector3.new(0.5, h, 0.3), cf * CFrame.new(0, 0, 0.1), c, Enum.Material.Neon)
		deco(parent, Vector3.new(s * 0.7, 0.5, 0.3), cf * CFrame.new(s * 0.35, h / 2, 0.1), c, Enum.Material.Neon)
		deco(parent, Vector3.new(1.4, 1.4, 0.4), cf * CFrame.new(s * 0.7, h / 2, 0.1), c, Enum.Material.Neon)
		deco(parent, Vector3.new(1.4, 1.4, 0.4), cf * CFrame.new(0, -h / 2, 0.1), c, Enum.Material.Neon)
	end
end

Core[10] = function(parent, cf, s, variant, rng)
	local bands = { rgb(255, 80, 90), rgb(255, 190, 50), rgb(255, 240, 90), rgb(90, 220, 110), rgb(80, 160, 255), rgb(190, 100, 255) }
	if variant == 1 then
		for i, c in bands do
			ringBand(parent, cf.Position.Y + (i - 1) * 0.9, 0.9, 1.0, c, Enum.Material.Neon).Transparency = 0.1
		end
	else
		-- a golden star: two crossed diamonds
		for i = 0, 1 do
			deco(parent, Vector3.new(s * 0.7, s * 0.7, 0.5), cf * CFrame.new(0, 0, 0.4) * CFrame.Angles(0, 0, i * math.pi / 4), GOLD, Enum.Material.Neon)
		end
	end
end

---------------------------------------------------------------------------------------------
-- halo between two worlds
---------------------------------------------------------------------------------------------
local function buildRing(parent: Instance, axis: Vector3, y: number, theme: Config.Theme)
	local n = 24
	local radius = DecorPlan.RING_RADIUS
	local len = 2 * math.pi * radius / n
	for i = 1, n do
		local a = i / n * math.pi * 2
		local seg = deco(parent, Vector3.new(2, 2, len * 1.02), CFrame.new(axis + Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)) * CFrame.Angles(0, -a, 0), if i % 2 == 0 then theme.accent else theme.pad, Enum.Material.Neon)
		seg.Transparency = 0.45
		seg.Name = "Halo"
	end
end

---------------------------------------------------------------------------------------------
-- public: tower scenery
---------------------------------------------------------------------------------------------
export type Stats = { parts: number, lights: number, emitters: number, outer: number, core: number, rings: number }

-- Floating set pieces, core ornaments and halos of one tower. Tower 1 (always built, seen from
-- the lobby) gets the full set; the towers built on demand get a lighter one.
function Scenery.buildTower(parent: Instance, map: Layout.Map): Stats
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	local t = map.tower
	local axis = Vector3.new(map.origin.x, map.origin.y, map.origin.z)
	towerAxis = axis
	local padY: { [number]: number } = {}
	for k, p in map.pads do
		padY[k] = p.y
	end
	local pieces = DecorPlan.generate(Config.MapSeed, padY, Layout, {
		tower = t,
		outer = if t == 1 then nil else 6,
		core = if t == 1 then nil else 8,
	})
	local lights0, emitters0 = lightCount, emitterCount
	local nOuter, nCore, nRing = 0, 0, 0
	local function styleOf(slot: number): number
		return Layout.themeFor((t - 1) * Layout.STAGES + (slot - 1) * 10 + 1)
	end
	withMood(t, function()
		for _, piece in pieces do
			local group = Instance.new("Model")
			group.Name = ("%s_w%d"):format(piece.kind, piece.world)
			group:SetAttribute("World", piece.world)
			local rng = Layout.newRng(piece.seed)
			local pos = axis + Vector3.new(piece.x, piece.y, piece.z)
			local style = styleOf(piece.world)
			if piece.kind == "outer" then
				local cf = CFrame.lookAt(pos, Vector3.new(axis.X, pos.Y, axis.Z))
				Outer[style](group, cf, piece.size * 0.62, piece.variant, rng)
				nOuter += 1
			elseif piece.kind == "core" then
				-- on the pillar surface, looking away from the axis (so +Z of `cf` sticks out)
				local out = Vector3.new(piece.x, 0, piece.z).Unit
				local cf = CFrame.lookAt(pos, pos - out)
				Core[style](group, cf, piece.size * 0.5, piece.variant, rng)
				nCore += 1
			end
			group.Parent = folder
		end
	end)
	-- halos are painted with the (already shifted) theme of the world they open
	for _, piece in pieces do
		if piece.kind == "ring" then
			local group = Instance.new("Model")
			group.Name = "ring_w" .. piece.world
			buildRing(group, axis, piece.y, Config.theme(t, styleOf(piece.world)))
			group.Parent = folder
			nRing += 1
		end
	end
	folder.Parent = parent
	local parts = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return { parts = parts, lights = lightCount - lights0, emitters = emitterCount - emitters0, outer = nOuter, core = nCore, rings = nRing }
end

---------------------------------------------------------------------------------------------
-- public: under-platform dressing (darker skirt + a themed prop hanging below)
---------------------------------------------------------------------------------------------
local HANG: { (parent: Instance, cf: CFrame, w: number, rng: Rng) -> () } = {
	-- 1 roots
	function(parent, cf, w, rng)
		for i = 1, 2 do
			local h = rng.range(1.2, 2.6)
			deco(parent, Vector3.new(0.35, h, 0.35), cf * CFrame.new(rng.range(-w, w) * 0.3, -h / 2, rng.range(-w, w) * 0.3) * CFrame.Angles(0, 0, rng.range(-0.2, 0.2)), rgb(120, 85, 55), Enum.Material.Wood)
		end
	end,
	-- 2 frosting drips
	function(parent, cf, w, rng)
		for i = 1, 2 do
			local h = rng.range(0.8, 1.8)
			local x, z = rng.range(-w, w) * 0.32, rng.range(-w, w) * 0.32
			deco(parent, Vector3.new(0.6, h, 0.6), cf * CFrame.new(x, -h / 2, z), rgb(255, 245, 250))
			ball(parent, 0.9, (cf * CFrame.new(x, -h, z)).Position, rgb(255, 245, 250))
		end
	end,
	-- 3 icicles
	function(parent, cf, w, rng)
		for i = 1, 3 do
			local h = rng.range(1, 2.4)
			local x, z = rng.range(-w, w) * 0.34, rng.range(-w, w) * 0.34
			deco(parent, Vector3.new(0.55, h * 0.6, 0.55), cf * CFrame.new(x, -h * 0.3, z), rgb(200, 238, 255), Enum.Material.Ice).Transparency = 0.15
			deco(parent, Vector3.new(0.28, h * 0.5, 0.28), cf * CFrame.new(x, -h * 0.85, z), rgb(225, 246, 255), Enum.Material.Ice).Transparency = 0.2
		end
	end,
	-- 4 crumbling bricks
	function(parent, cf, w, rng)
		for i = 1, 2 do
			deco(parent, Vector3.new(rng.range(0.8, 1.4), rng.range(0.6, 1.1), rng.range(0.8, 1.4)), cf * CFrame.new(rng.range(-w, w) * 0.3, -rng.range(0.3, 0.9), rng.range(-w, w) * 0.3) * CFrame.Angles(rng.range(-0.3, 0.3), rng.range(0, 1.5), 0), rgb(205, 165, 100), Enum.Material.Sandstone)
		end
	end,
	-- 5 glowing stalactite
	function(parent, cf, w, rng)
		local h = rng.range(1.4, 2.6)
		deco(parent, Vector3.new(1.0, h * 0.6, 1.0), cf * CFrame.new(0, -h * 0.3, 0), rgb(62, 54, 60), Enum.Material.Basalt)
		deco(parent, Vector3.new(0.45, h * 0.5, 0.45), cf * CFrame.new(0, -h * 0.8, 0), rgb(255, 120, 30), Enum.Material.Neon)
	end,
	-- 6 seaweed strands
	function(parent, cf, w, rng)
		for i = 1, 2 do
			local h = rng.range(1.5, 3)
			deco(parent, Vector3.new(0.5, h, 0.2), cf * CFrame.new(rng.range(-w, w) * 0.3, -h / 2, rng.range(-w, w) * 0.3) * CFrame.Angles(0, rng.range(0, 3), rng.range(-0.15, 0.15)), rgb(50, 170, 120), Enum.Material.Grass)
		end
	end,
	-- 7 goo drip
	function(parent, cf, w, rng)
		local h = rng.range(1, 2.2)
		local x, z = rng.range(-w, w) * 0.3, rng.range(-w, w) * 0.3
		deco(parent, Vector3.new(0.45, h, 0.45), cf * CFrame.new(x, -h / 2, z), rgb(170, 255, 60), Enum.Material.Neon)
		ball(parent, 0.8, (cf * CFrame.new(x, -h, z)).Position, rgb(170, 255, 60), Enum.Material.Neon)
	end,
	-- 8 cloud puff
	function(parent, cf, w, rng)
		blob(parent, Vector3.new(w * 0.9, 1.6, w * 0.9), cf * CFrame.new(0, -0.7, 0), WHITE)
	end,
	-- 9 neon underglow bar
	function(parent, cf, w, rng)
		deco(parent, Vector3.new(w * 0.7, 0.25, 0.4), cf * CFrame.new(0, -0.15, 0), if rng.next() < 0.5 then rgb(0, 255, 230) else rgb(255, 60, 220), Enum.Material.Neon)
	end,
	-- 10 crystal
	function(parent, cf, w, rng)
		local bands = { rgb(255, 80, 90), rgb(255, 190, 50), rgb(90, 220, 110), rgb(80, 160, 255), rgb(190, 100, 255) }
		local h = rng.range(1.2, 2.2)
		deco(parent, Vector3.new(0.7, h, 0.7), cf * CFrame.new(0, -h / 2, 0) * CFrame.Angles(0, math.pi / 4, 0), bands[rng.int(1, #bands)], Enum.Material.Neon).Transparency = 0.15
	end,
}

-- Top layer of a platform per world: { body colour?, body material?, cap colour?, cap material? }.
-- Worlds without an entry get a cap that is simply a lighter shade of the slab.
type CapStyle = { body: Color3?, bodyMat: Enum.Material?, cap: Color3?, capMat: Enum.Material? }
local CAPS: { [number]: CapStyle } = {
	[1] = { body = rgb(205, 155, 105), bodyMat = Enum.Material.Sand, cap = rgb(140, 235, 105), capMat = Enum.Material.Grass }, -- turf on dirt
	[3] = { cap = rgb(246, 250, 255), capMat = Enum.Material.Snow }, -- snow on ice
	[4] = { cap = rgb(250, 228, 175), capMat = Enum.Material.Sand }, -- sand on sandstone
	[5] = { cap = rgb(105, 92, 98), capMat = Enum.Material.Basalt },
	[6] = { cap = rgb(250, 228, 180), capMat = Enum.Material.Sand }, -- seabed sand on reef rock
	[7] = { capMat = Enum.Material.Metal }, -- steel deck plates on the factory slabs
	[8] = { bodyMat = Enum.Material.Marble, capMat = Enum.Material.Marble }, -- white-marble sky palace
	[9] = { bodyMat = Enum.Material.Slate, capMat = Enum.Material.Neon }, -- dark slabs, glowing tops
}

-- `slab` is a static platform. Gives it a top layer (grass on dirt, snow on ice, frosting on
-- cake...), a darker underside so the spiral overhead isn't flat-shaded slabs, and (for about a
-- third of them) a small themed prop hanging below. The slab itself - the only solid part - keeps
-- its size and position.
function Scenery.dressPlatform(model: Instance, slab: BasePart, theme: Config.Theme, tower: number, world: number, rng: Rng)
	local size = slab.Size
	local style: CapStyle = CAPS[world] or {}
	local isAlt = slab.Color == theme.alt
	withMood(tower, function()
		local body = slab.Color
		if style.body then
			body = style.body:Lerp(Color3.new(), if isAlt then 0.12 else 0)
			if tower > 1 then
				local shifted = TowerStyle.shift({ math.floor(body.R * 255 + 0.5), math.floor(body.G * 255 + 0.5), math.floor(body.B * 255 + 0.5) }, TowerStyle.mood(tower))
				body = Color3.fromRGB(shifted[1], shifted[2], shifted[3])
			end
			slab.Color = body
		end
		if style.bodyMat then
			slab.Material = style.bodyMat
		end
		local softMat = if slab.Material == Enum.Material.Neon or slab.Material == Enum.Material.Glass then Enum.Material.SmoothPlastic else slab.Material
		-- caps whose colour comes from the theme are already in the tower's palette: made outside
		-- the recording below so they are not shifted twice
		local capColor = style.cap
		local fromTheme = false
		if world == 2 then
			-- candy: white frosting on the pink cakes, pink on the white ones
			capColor = if isAlt then theme.platform else rgb(255, 250, 252)
			fromTheme = isAlt
		elseif not capColor then
			capColor = body:Lerp(Color3.new(1, 1, 1), 0.4)
			fromTheme = true
		end
		local saved = recording
		if fromTheme then
			recording = nil
		end
		local cap = deco(model, Vector3.new(size.X + 0.4, 0.3, size.Z + 0.4), slab.CFrame * CFrame.new(0, size.Y / 2 - 0.12, 0), capColor :: Color3, style.capMat or softMat)
		cap.Name = "Cap"
		local under = slab.CFrame * CFrame.new(0, -size.Y / 2, 0)
		recording = nil
		local skirt = deco(model, Vector3.new(math.max(0.6, size.X - 0.8), 0.7, math.max(0.6, size.Z - 0.8)), under * CFrame.new(0, -0.35, 0), body:Lerp(Color3.new(), 0.28), softMat)
		skirt.Name = "Skirt"
		recording = saved
		if rng.next() < 0.36 and math.min(size.X, size.Z) >= 3 then
			local hang = HANG[world]
			if hang then
				hang(model, under * CFrame.new(0, -0.7, 0), math.min(size.X, size.Z), rng)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- public: lobby dressing. The lobby floor is a disc of radius 150 with its top at y = 0.
---------------------------------------------------------------------------------------------
function Scenery.buildLobby(parent: Instance, start: Vector3, spawnPos: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "LobbyScenery"
	local rng = Layout.newRng(Config.MapSeed + 61)

	-- the floor becomes a floating island: rock tapering below it, a sea of clouds further down
	local rock = rgb(128, 100, 78)
	cyl(folder, 292, 10, CFrame.new(0, -9, 0), rock, Enum.Material.Slate)
	cyl(folder, 236, 18, CFrame.new(4, -23, -3), rock:Lerp(Color3.new(), 0.1), Enum.Material.Slate)
	cyl(folder, 160, 24, CFrame.new(-6, -44, 5), rock:Lerp(Color3.new(), 0.18), Enum.Material.Slate)
	cyl(folder, 84, 28, CFrame.new(3, -70, -2), rock:Lerp(Color3.new(), 0.26), Enum.Material.Slate)
	cyl(folder, 30, 26, CFrame.new(0, -97, 0), rock:Lerp(Color3.new(), 0.32), Enum.Material.Slate)
	for i = 1, 26 do
		local a = i / 26 * math.pi * 2 + rng.range(-0.08, 0.08)
		local r = rng.range(190, 330)
		local s = rng.range(50, 95)
		local cloud = blob(folder, Vector3.new(s, s * 0.32, s * 0.8), CFrame.new(math.cos(a) * r, rng.range(-70, -34), math.sin(a) * r) * CFrame.Angles(0, a, 0), WHITE)
		cloud.Transparency = 0.08
		cloud.Name = "CloudSea"
	end
	-- boulders and bushes along the rim hide the hard edge of the disc
	for i = 1, 44 do
		local a = i / 44 * math.pi * 2 + rng.range(-0.05, 0.05)
		local r = rng.range(143, 149)
		local bush = rng.next() < 0.45
		local s = rng.range(5, 10)
		blob(folder, Vector3.new(s * 1.3, s * 0.8, s), CFrame.new(math.cos(a) * r, s * 0.15, math.sin(a) * r) * CFrame.Angles(0, rng.range(0, 3), 0), if bush then rgb(70, 165, 80) else rgb(150, 150, 158), if bush then Enum.Material.Grass else Enum.Material.Slate)
	end

	-- plaza around the spawn, stone kerbs along the path
	local plazaCenter = Vector3.new(spawnPos.X, 0, spawnPos.Z)
	cyl(folder, 52, 0.12, CFrame.new(plazaCenter + Vector3.new(0, 0.06, 0)), rgb(205, 190, 165), Enum.Material.Cobblestone)
	cyl(folder, 40, 0.2, CFrame.new(plazaCenter + Vector3.new(0, 0.1, 0)), rgb(240, 226, 196), Enum.Material.Sandstone)
	local ringGlow = cyl(folder, 22, 0.3, CFrame.new(plazaCenter + Vector3.new(0, 0.15, 0)), rgb(110, 225, 255), Enum.Material.Neon)
	ringGlow.Name = "SpawnGlow"
	cyl(folder, 18.6, 0.36, CFrame.new(plazaCenter + Vector3.new(0, 0.18, 0)), rgb(240, 226, 196), Enum.Material.Sandstone)
	for _, x in { -6.6, 6.6 } do
		deco(folder, Vector3.new(1.2, 0.7, 50), CFrame.new(x, 0.35, 90), rgb(225, 225, 232), Enum.Material.Concrete)
	end

	-- lamp posts + flower beds along the path to the tower
	local flowers = { rgb(255, 110, 150), rgb(255, 215, 70), rgb(170, 120, 255), WHITE, rgb(255, 150, 60) }
	for i = 0, 2 do
		local z = 72 + i * 15
		for _, side in { -1, 1 } do
			local x = side * 10
			cyl(folder, 0.7, 9, CFrame.new(x, 4.5, z), rgb(60, 62, 80), Enum.Material.Metal)
			cyl(folder, 1.6, 0.5, CFrame.new(x, 0.25, z), rgb(60, 62, 80), Enum.Material.Metal)
			local lamp = ball(folder, 2.2, Vector3.new(x, 9.8, z), rgb(255, 236, 170), Enum.Material.Neon)
			lamp.Name = "Lamp"
			light(lamp, rgb(255, 225, 160), 20, 1.2)
			-- flower bed between lamps
			local bedZ = z + 7.5
			if i < 2 then
				blob(folder, Vector3.new(5, 1.2, 8), CFrame.new(x + side * 1.5, 0.2, bedZ), rgb(80, 170, 85), Enum.Material.Grass)
				for _ = 1, 5 do
					ball(folder, rng.range(0.8, 1.3), Vector3.new(x + side * 1.5 + rng.range(-1.8, 1.8), rng.range(0.8, 1.2), bedZ + rng.range(-3, 3)), flowers[rng.int(1, #flowers)])
				end
			end
		end
	end

	-- the tower entrance: gold caps, banners and glowing orbs on the START arch
	for _, x in { -8, 8 } do
		local top = start + Vector3.new(x, 14, 4)
		ball(folder, 3, top + Vector3.new(0, 1.2, 0), GOLD, Enum.Material.Neon)
		cyl(folder, 3, 0.8, CFrame.new(start + Vector3.new(x, -1.6, 4)), rgb(225, 225, 232), Enum.Material.Marble)
		local banner = deco(folder, Vector3.new(0.3, 9, 3.4), CFrame.new(start + Vector3.new(x + (if x < 0 then -1.3 else 1.3), 7, 4)), rgb(255, 90, 120))
		banner.Name = "Banner"
		deco(folder, Vector3.new(0.34, 1, 3.4), CFrame.new(start + Vector3.new(x + (if x < 0 then -1.3 else 1.3), 3, 4)), GOLD)
		local orb = ball(folder, 1.4, start + Vector3.new(x * 1.6, 4, 6), rgb(120, 230, 255), Enum.Material.Neon)
		cyl(folder, 0.5, 3.4, CFrame.new(start + Vector3.new(x * 1.6, 1.0, 6)), rgb(225, 225, 232), Enum.Material.Marble)
		emitter(orb, { texture = SPARKLES, color = rgb(160, 240, 255), color2 = rgb(255, 240, 150), rate = 6, life = 1.6, speed = 3, size = 0.8, size2 = 0.1, spread = 180, emission = 0.8 })
		light(orb, rgb(120, 230, 255), 16, 1.5)
	end

	-- the tower base: a stone plinth with gold trim and a title plate (inside the core's footprint
	-- + 8 studs, nowhere near a lane)
	local plinth = cyl(folder, 60, 3, CFrame.new(0, 1.5, 0), rgb(225, 225, 232), Enum.Material.Marble)
	plinth.Name = "Plinth"
	local plinth2 = cyl(folder, 54, 2, CFrame.new(0, 4, 0), rgb(205, 205, 215), Enum.Material.Marble)
	for _, step in { plinth, plinth2 } do
		-- solid: you can climb the steps (radius 30, the nearest lane starts at 42)
		step.CanCollide = true
		step.CanQuery = true
	end
	cyl(folder, Layout.CORE_RADIUS * 2 + 2.4, 1.4, CFrame.new(0, 5.7, 0), GOLD, Enum.Material.Neon)
	cyl(folder, Layout.CORE_RADIUS * 2 + 2.4, 1.0, CFrame.new(0, 40, 0), GOLD, Enum.Material.Neon)
	local plate = deco(folder, Vector3.new(30, 9, 1), CFrame.lookAt(Vector3.new(0, 31, Layout.CORE_RADIUS + 0.6), Vector3.new(0, 31, 200)), rgb(40, 45, 80))
	plate.Name = "TitlePlate"
	deco(folder, Vector3.new(31.4, 10.4, 0.6), plate.CFrame * CFrame.new(0, 0, 0.3), GOLD, Enum.Material.Neon)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 24
	sg.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = string.upper(Config.GameName) -- a name: the same in every language
	title.TextColor3 = rgb(255, 225, 90)
	title.TextStrokeTransparency = 0
	title.TextStrokeColor3 = rgb(20, 20, 45)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = title
	title.Parent = sg
	sg.Parent = plate

	-- two hot-air balloons drifting beside the island
	for i, spec in { { pos = Vector3.new(-120, 70, 150), color = rgb(255, 110, 130) }, { pos = Vector3.new(150, 110, 60), color = rgb(90, 180, 255) } } do
		local p = spec.pos
		local model = Instance.new("Model")
		model.Name = "Balloon"
		ball(model, 26, p, spec.color)
		cyl(model, 26.4, 3, CFrame.new(p), WHITE)
		cyl(model, 21, 3, CFrame.new(p + Vector3.new(0, 7.5, 0)), rgb(255, 225, 90))
		cyl(model, 21, 3, CFrame.new(p + Vector3.new(0, -7.5, 0)), rgb(255, 225, 90))
		deco(model, Vector3.new(5, 4, 5), CFrame.new(p + Vector3.new(0, -21, 0)), rgb(165, 120, 80), Enum.Material.WoodPlanks)
		for _, o in { Vector3.new(2.2, 0, 2.2), Vector3.new(-2.2, 0, 2.2), Vector3.new(2.2, 0, -2.2), Vector3.new(-2.2, 0, -2.2) } do
			deco(model, Vector3.new(0.2, 9, 0.2), CFrame.new(p + o + Vector3.new(0, -15, 0)), rgb(245, 240, 230))
		end
		model:SetAttribute("Bob", i)
		model.Parent = folder
	end

	folder.Parent = parent
end

---------------------------------------------------------------------------------------------
-- public: victory room dressing. `center` = middle of the round floor (radius 25, top at
-- center.Y), `outward` = unit vector pointing away from the tower.
---------------------------------------------------------------------------------------------
function Scenery.buildVictory(parent: Instance, center: Vector3, outward: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "VictoryScenery"
	local frame = CFrame.lookAt(center, center - outward) -- -Z looks back at the tower
	local bands = { rgb(255, 80, 90), rgb(255, 190, 50), rgb(255, 240, 90), rgb(90, 220, 110), rgb(80, 160, 255), rgb(190, 100, 255) }

	-- floor: glowing rim + two inlaid rings
	cyl(folder, 53, 1.2, CFrame.new(center - Vector3.new(0, 1.2, 0)), rgb(255, 170, 60))
	cyl(folder, 38, 0.12, CFrame.new(center + Vector3.new(0, 0.06, 0)), rgb(255, 170, 60))
	cyl(folder, 35, 0.16, CFrame.new(center + Vector3.new(0, 0.08, 0)), rgb(255, 235, 120))
	cyl(folder, 16, 0.2, CFrame.new(center + Vector3.new(0, 0.1, 0)), WHITE, Enum.Material.Marble)
	-- a cloud bank under the room so it doesn't hang in the void
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		blob(folder, Vector3.new(34, 11, 28), CFrame.new(center + Vector3.new(math.cos(a) * 22, -8, math.sin(a) * 22)) * CFrame.Angles(0, a, 0), WHITE)
	end

	-- two giant golden cups flanking the WINNER sign
	for _, tx in { -16, 16 } do
		local t = frame * CFrame.new(tx, 0, 9)
		cyl(folder, 8, 1.4, t * CFrame.new(0, 0.7, 0), rgb(90, 70, 50), Enum.Material.Wood)
		cyl(folder, 5.4, 1.2, t * CFrame.new(0, 2, 0), GOLD, Enum.Material.Metal)
		cyl(folder, 1.8, 4.4, t * CFrame.new(0, 4.8, 0), GOLD, Enum.Material.Metal)
		for i = 0, 3 do
			cyl(folder, 4.4 + i * 1.5, 1.5, t * CFrame.new(0, 7.7 + i * 1.5, 0), GOLD, Enum.Material.Metal)
		end
		local glow = cyl(folder, 7.2, 0.5, t * CFrame.new(0, 13.3, 0), rgb(255, 245, 170), Enum.Material.Neon)
		for _, side in { -1, 1 } do
			deco(folder, Vector3.new(0.8, 4, 0.8), t * CFrame.new(side * 5.6, 10.6, 0), GOLD, Enum.Material.Metal)
			deco(folder, Vector3.new(2.2, 0.8, 0.8), t * CFrame.new(side * 4.7, 12.3, 0), GOLD, Enum.Material.Metal)
			deco(folder, Vector3.new(2.6, 0.8, 0.8), t * CFrame.new(side * 4.4, 9, 0), GOLD, Enum.Material.Metal)
		end
		for i = 0, 1 do
			deco(folder, Vector3.new(3, 3, 0.6), t * CFrame.new(0, 16.4, 0) * CFrame.Angles(0, 0, i * math.pi / 4), rgb(255, 250, 190), Enum.Material.Neon)
		end
		light(glow, rgb(255, 230, 140), 36, 1.6)
		emitter(glow, { texture = SPARKLES, color = rgb(255, 250, 190), color2 = rgb(255, 200, 80), rate = 8, life = 2.2, speed = 8, size = 1.3, size2 = 0.2, spread = 35, emission = 0.9, accel = Vector3.new(0, -6, 0) })
	end

	-- rainbow over the far side of the room
	local segs = 12
	for b, color in bands do
		local radius = 27 - (b - 1) * 1.5
		for i = 0, segs - 1 do
			local a = (i + 0.5) / segs * math.pi
			local len = math.pi * radius / segs * 1.06
			deco(folder, Vector3.new(len, 1.5, 1.6), frame * CFrame.new(math.cos(a) * radius, math.sin(a) * radius - 1, 20) * CFrame.Angles(0, 0, a + math.pi / 2), color, Enum.Material.Neon).Transparency = 0.12
		end
	end

	-- four searchlight beams around the room
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local beam = cyl(folder, 3.4, 90, CFrame.new(center + Vector3.new(math.cos(a) * 25.5, 44, math.sin(a) * 25.5)) * CFrame.Angles(math.cos(a) * 0.12, 0, math.sin(a) * -0.12), bands[i + 1], Enum.Material.Neon)
		beam.Transparency = 0.9
		beam.Name = "Searchlight"
	end
	folder.Parent = parent
end

---------------------------------------------------------------------------------------------
-- shared bits for the interactive set pieces (shops, lounge, portals, gift plinths)
---------------------------------------------------------------------------------------------
-- Two lines of text floating over `part`: a big one and a smaller one. Both are localized on
-- each client through `loc` (StageGenerator.loc).
local function caption(part: BasePart, offsetY: number, width: number, loc: LocFn, topKey: string, topArgs: { [string]: any }?, topColor: Color3, bottomKey: string?, bottomArgs: { [string]: any }?, bottomColor: Color3?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Caption"
	bb.Size = UDim2.fromScale(width, width * 0.36)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.Adornee = part
	local function line(name: string, y: number, h: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, h)
		l.Position = UDim2.fromScale(0, y)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.TextStrokeColor3 = Color3.fromRGB(30, 30, 50)
		l.Parent = bb
		return l
	end
	local top = line("Top", 0, if bottomKey then 0.56 else 1, topColor)
	loc(top, topKey, topArgs)
	if bottomKey then
		loc(line("Bottom", 0.58, 0.42, bottomColor or WHITE), bottomKey, bottomArgs)
	end
	bb.Parent = part
end

-- A pedestal with something floating over it. Returns the base (where the ProximityPrompt goes).
local function pedestal(parent: Instance, base: CFrame, color: Color3): Part
	local foot = solid(parent, Vector3.new(1.1, 2.6, 2.6), base * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(235, 235, 242), Enum.Material.Marble)
	foot.Shape = Enum.PartType.Cylinder
	foot.Name = "Pedestal"
	cyl(parent, 2.2, 1.3, base * CFrame.new(0, 1.75, 0), color)
	cyl(parent, 2.9, 0.3, base * CFrame.new(0, 2.5, 0), rgb(255, 255, 255), Enum.Material.Neon)
	return foot
end

-- Small floating models of the shop items, built from parts (no uploads). `at` = centre.
local ICONS: { [string]: (parent: Instance, at: CFrame, color: Color3) -> () } = {
	speed = function(parent, at, color)
		for i = -1, 1 do
			cyl(parent, 1.9, 0.34, at * CFrame.new(0, i * 0.5, 0) * CFrame.Angles(0.18, 0, 0), color, Enum.Material.Neon)
		end
		cyl(parent, 0.5, 1.9, at * CFrame.new(0, -0.1, 0), rgb(90, 95, 110), Enum.Material.Metal)
	end,
	gravity = function(parent, at, color)
		for i = -1, 1 do
			cyl(parent, 1.9 - math.abs(i) * 0.4, 0.34, at * CFrame.new(0, i * 0.55, 0), color, Enum.Material.Neon)
		end
		ball(parent, 0.8, (at * CFrame.new(0, 1.3, 0)).Position, WHITE, Enum.Material.Neon)
	end,
	doublejump = function(parent, at, color)
		for i = 0, 1 do
			for _, side in { -1, 1 } do
				deco(parent, Vector3.new(0.4, 1.3, 0.5), at * CFrame.new(side * 0.42, i * 1.0 - 0.5, 0) * CFrame.Angles(0, 0, side * 0.75), color, Enum.Material.Neon)
			end
		end
	end,
	shield = function(parent, at, color)
		cyl(parent, 2.2, 0.4, at * CFrame.Angles(math.pi / 2, 0, 0), color)
		cyl(parent, 1.3, 0.5, at * CFrame.Angles(math.pi / 2, 0, 0), WHITE, Enum.Material.Neon)
	end,
	magnet = function(parent, at, color)
		deco(parent, Vector3.new(2, 0.6, 0.6), at * CFrame.new(0, 0.7, 0), color)
		for _, side in { -1, 1 } do
			deco(parent, Vector3.new(0.6, 1.1, 0.6), at * CFrame.new(side * 0.7, -0.1, 0), color)
			deco(parent, Vector3.new(0.62, 0.5, 0.62), at * CFrame.new(side * 0.7, -0.85, 0), WHITE, Enum.Material.Neon)
		end
	end,
	skip = function(parent, at, color)
		for i = 0, 1 do
			for _, side in { -1, 1 } do
				deco(parent, Vector3.new(0.4, 1.2, 0.5), at * CFrame.new(i * 0.9 - 0.7, side * 0.38, 0) * CFrame.Angles(0, 0, math.pi / 2 + side * 0.75), color, Enum.Material.Neon)
			end
		end
		deco(parent, Vector3.new(0.35, 1.7, 0.5), at * CFrame.new(1.05, 0, 0), color, Enum.Material.Neon)
	end,
	pocket = function(parent, at, color)
		cyl(parent, 1.9, 0.3, at * CFrame.new(0, -0.8, 0), rgb(120, 225, 255), Enum.Material.Neon)
		cyl(parent, 0.16, 2, at * CFrame.new(-0.4, 0.2, 0), WHITE, Enum.Material.Metal)
		deco(parent, Vector3.new(1.1, 0.7, 0.12), at * CFrame.new(0.2, 0.8, 0), color)
	end,
}

---------------------------------------------------------------------------------------------
-- public: shop platform next to the first pad of a world. `out` = unit vector away from the tower.
-- The deck hangs OUTSIDE the ring of pads (8..22 studs from the pad centre), where no stage runs,
-- and ends 4 studs short of the nearest floating scenery.
---------------------------------------------------------------------------------------------
export type Interactive = { id: string, part: Part }

Scenery.SHOP_NEAR = Layout.SHOP_NEAR
Scenery.SHOP_DEPTH = Layout.SHOP_DEPTH
Scenery.SHOP_WIDTH = Layout.SHOP_WIDTH

function Scenery.buildShop(parent: Instance, padPos: Vector3, out: Vector3, theme: Config.Theme, loc: LocFn): { Interactive }
	local model = Instance.new("Model")
	model.Name = "Shop"
	local depth, width = Scenery.SHOP_DEPTH, Scenery.SHOP_WIDTH
	local center = padPos + out * (Scenery.SHOP_NEAR + depth / 2)
	-- frame: origin on the deck top at its centre, -Z towards the far edge, +X along the deck
	local frame = CFrame.lookAt(center, center + out)
	local wood = rgb(245, 225, 190)
	solid(model, Vector3.new(width, 1, depth), frame * CFrame.new(0, -0.5, 0), wood, Enum.Material.WoodPlanks).Name = "ShopDeck"
	solid(model, Vector3.new(7, 1, Scenery.SHOP_NEAR - Layout.PAD_RADIUS + 1.2), frame * CFrame.new(0, -0.5, depth / 2 + (Scenery.SHOP_NEAR - Layout.PAD_RADIUS + 1.2) / 2 - 0.3), wood, Enum.Material.WoodPlanks).Name = "ShopBridge"
	deco(model, Vector3.new(width - 1, 0.8, depth - 1), frame * CFrame.new(0, -1.4, 0), wood:Lerp(Color3.new(), 0.3), Enum.Material.Wood)
	-- rails on the three open sides
	local railColor = theme.accent:Lerp(WHITE, 0.2)
	solid(model, Vector3.new(width, 2.4, 0.5), frame * CFrame.new(0, 1.2, -depth / 2 + 0.25), railColor).Name = "ShopRail"
	for _, side in { -1, 1 } do
		solid(model, Vector3.new(0.5, 2.4, depth), frame * CFrame.new(side * (width / 2 - 0.25), 1.2, 0), railColor).Name = "ShopRail"
	end
	-- striped canopy + sign over the entrance
	for _, side in { -1, 1 } do
		cyl(model, 0.7, 9.5, frame * CFrame.new(side * (width / 2 - 0.8), 4.75, depth / 2 - 0.8), WHITE)
	end
	for i = 0, 6 do
		deco(model, Vector3.new(width / 7, 0.5, 4.4), frame * CFrame.new(-width / 2 + (i + 0.5) * width / 7, 9.4, depth / 2 - 2.4) * CFrame.Angles(math.rad(10), 0, 0), if i % 2 == 0 then theme.accent else WHITE)
	end
	local sign = deco(model, Vector3.new(12, 2.6, 0.4), frame * CFrame.new(0, 11.4, depth / 2 - 0.5), rgb(40, 45, 80))
	sign.Name = "ShopSign"
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back -- faces the pad
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rgb(255, 225, 90)
	label.TextStrokeTransparency = 0.2
	loc(label, "shop.zone")
	label.Parent = sg
	sg.Parent = sign

	local items: { Interactive } = {}
	local n = #Powerups.List
	for i, item in Powerups.List do
		local base = frame * CFrame.new((i - (n + 1) / 2) * (width - 3) / n, 0, -depth / 2 + 2.2)
		local color = Color3.fromRGB(item.color[1], item.color[2], item.color[3])
		local foot = pedestal(model, base, color)
		local icon = ICONS[item.id]
		if icon then
			icon(model, base * CFrame.new(0, 4.2, 0), color)
		end
		caption(foot, 6.6, 5.4, loc, "power." .. item.id .. ".name", nil, WHITE, "shop.price", { price = item.price }, rgb(255, 225, 90))
		foot:SetAttribute("Item", item.id)
		table.insert(items, { id = item.id, part = foot })
	end
	model.Parent = parent
	return items
end

---------------------------------------------------------------------------------------------
-- public: gift plinth ("this is what you get at stage N"). `cf` = on the ground, facing the viewer.
---------------------------------------------------------------------------------------------
function Scenery.buildGiftPreview(parent: Instance, cf: CFrame, gift: Gifts.Gift, loc: LocFn)
	local model = Instance.new("Model")
	model.Name = "Gift_" .. gift.id
	local foot = pedestal(model, cf, GOLD)
	local box = cf * CFrame.new(0, 4.4, 0) * CFrame.Angles(0, 0.5, 0)
	local paper = rgb(170, 110, 255)
	deco(model, Vector3.new(2.6, 2.2, 2.6), box, paper)
	deco(model, Vector3.new(2.9, 0.5, 2.9), box * CFrame.new(0, 1.2, 0), paper:Lerp(WHITE, 0.25))
	deco(model, Vector3.new(0.6, 2.8, 2.7), box * CFrame.new(0, 0.1, 0), GOLD, Enum.Material.Neon)
	deco(model, Vector3.new(2.7, 2.8, 0.6), box * CFrame.new(0, 0.1, 0), GOLD, Enum.Material.Neon)
	ball(model, 0.9, (box * CFrame.new(0.3, 1.8, 0)).Position, GOLD, Enum.Material.Neon)
	ball(model, 0.9, (box * CFrame.new(-0.3, 1.8, 0)).Position, GOLD, Enum.Material.Neon)
	caption(foot, 8.6, 9, loc, "gift.at", { n = gift.stage }, rgb(255, 225, 90), "gift." .. gift.id .. ".name", nil, WHITE)
	model.Parent = parent
end

---------------------------------------------------------------------------------------------
-- public: a portal. `cf` = on the ground, facing the viewer. Returns the swirling disc (walk in).
---------------------------------------------------------------------------------------------
function Scenery.buildPortal(parent: Instance, cf: CFrame, color: Color3, key: string, args: { [string]: any }?, loc: LocFn): Part
	local model = Instance.new("Model")
	model.Name = "PortalFrame"
	for _, side in { -1, 1 } do
		solid(model, Vector3.new(2, 12, 2), cf * CFrame.new(side * 5.5, 6, 0), rgb(235, 235, 242), Enum.Material.Marble)
		ball(model, 2.4, (cf * CFrame.new(side * 5.5, 12.8, 0)).Position, color, Enum.Material.Neon)
	end
	deco(model, Vector3.new(13, 1.6, 2.2), cf * CFrame.new(0, 12.4, 0), rgb(215, 215, 228), Enum.Material.Marble)
	local disc = cyl(model, 9.4, 0.6, cf * CFrame.new(0, 6, 0) * CFrame.Angles(math.pi / 2, 0, 0), color, Enum.Material.Neon)
	disc.Transparency = 0.25
	disc.CanTouch = true
	local inner = cyl(model, 6, 0.8, cf * CFrame.new(0, 6, 0) * CFrame.Angles(math.pi / 2, 0, 0), WHITE, Enum.Material.Neon)
	inner.Transparency = 0.35
	cyl(model, 2.6, 1, cf * CFrame.new(0, 6, 0) * CFrame.Angles(math.pi / 2, 0, 0), color, Enum.Material.Neon)
	emitter(disc, { texture = SPARKLES, color = WHITE, color2 = color, rate = 8, life = 1.6, speed = 4, size = 0.9, size2 = 0.1, spread = 180, emission = 0.9 })
	light(disc, color, 22, 1.6)
	caption(disc, 9.4, 17, loc, key, args, rgb(255, 240, 120))
	model.Parent = parent
	return disc
end

---------------------------------------------------------------------------------------------
-- public: the Winner's Lounge, a round terrace beyond the summit room of tower 1 with one
-- pedestal per free item (Shared/Perks). `center` = middle of the victory floor.
---------------------------------------------------------------------------------------------
function Scenery.buildLounge(parent: Instance, center: Vector3, outward: Vector3, loc: LocFn): { Interactive }
	local model = Instance.new("Model")
	model.Name = "Lounge"
	local mid = center + outward * 46
	local frame = CFrame.lookAt(mid, mid + outward)
	local floor = solid(model, Vector3.new(2, 40, 40), frame * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(245, 245, 250), Enum.Material.Marble)
	floor.Shape = Enum.PartType.Cylinder
	floor.Name = "LoungeFloor"
	cyl(model, 42, 1.2, frame * CFrame.new(0, -1.4, 0), GOLD)
	cyl(model, 26, 0.12, frame * CFrame.new(0, 0.06, 0), rgb(200, 215, 255))
	cyl(model, 23, 0.16, frame * CFrame.new(0, 0.08, 0), rgb(245, 245, 250), Enum.Material.Marble)
	solid(model, Vector3.new(9, 2, 5), CFrame.lookAt(center + outward * 25.5 - Vector3.new(0, 1, 0), mid - Vector3.new(0, 1, 0)), rgb(245, 245, 250), Enum.Material.Marble).Name = "LoungeBridge"
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		blob(model, Vector3.new(26, 9, 22), frame * CFrame.new(math.cos(a) * 17, -8, math.sin(a) * 17) * CFrame.Angles(0, a, 0), WHITE)
	end
	-- sign over the way in
	for _, side in { -1, 1 } do
		cyl(model, 0.9, 11, frame * CFrame.new(side * 7, 5.5, 19), GOLD)
	end
	local sign = deco(model, Vector3.new(16, 3, 0.5), frame * CFrame.new(0, 11.5, 19), rgb(40, 45, 80))
	sign.Name = "LoungeSign"
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rgb(255, 225, 90)
	label.TextStrokeTransparency = 0.2
	loc(label, "lounge.sign")
	label.Parent = sg
	sg.Parent = sign

	-- pedestals on a ring, leaving the entrance (towards the summit room) open
	local items: { Interactive } = {}
	local n = #Perks.List
	for i, perk in Perks.List do
		local a = math.rad(-150) + (i - 1) / (n - 1) * math.rad(300) -- 300 degrees, gap at the entrance
		local pos = frame * CFrame.new(math.sin(a) * 15.5, 0, -math.cos(a) * 15.5)
		local base = CFrame.lookAt(pos.Position, mid)
		local color = if perk.color then Color3.fromRGB(perk.color[1], perk.color[2], perk.color[3]) else rgb(120, 200, 255)
		local foot = pedestal(model, base, color)
		local orb = ball(model, 1.7, (base * CFrame.new(0, 4.1, 0)).Position, color, Enum.Material.Neon)
		orb.Transparency = 0.15
		caption(foot, 6.4, 5.2, loc, "perk." .. perk.id .. ".name", nil, WHITE, "lounge.free", nil, rgb(120, 255, 150))
		foot:SetAttribute("Perk", perk.id)
		table.insert(items, { id = perk.id, part = foot })
	end
	model.Parent = parent
	return items
end

---------------------------------------------------------------------------------------------
-- public: the base island of towers 2..10 (where the portal drops you). `padPos` = top of pad 0.
-- Returns the "back to the lobby" portal disc.
---------------------------------------------------------------------------------------------
function Scenery.buildBase(parent: Instance, padPos: Vector3, axis: Vector3, tower: number, loc: LocFn): Part
	local model = Instance.new("Model")
	model.Name = "Base"
	local out = Vector3.new(padPos.X - axis.X, 0, padPos.Z - axis.Z).Unit
	local ground = padPos.Y - 2 -- pad 0 is 2 studs thick
	local mid = Vector3.new(padPos.X, ground, padPos.Z) + out * 12
	local frame = CFrame.lookAt(mid, mid + out)
	local mood = TowerStyle.mood(tower)
	local accent = Color3.fromRGB(mood.core[1], mood.core[2], mood.core[3])
	local floor = solid(model, Vector3.new(3, 56, 56), frame * CFrame.new(0, -1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(225, 225, 235), Enum.Material.Cobblestone)
	floor.Shape = Enum.PartType.Cylinder
	floor.Name = "BaseFloor"
	local rock = rgb(120, 110, 125)
	cyl(model, 48, 12, frame * CFrame.new(0, -9, 0), rock, Enum.Material.Slate)
	cyl(model, 30, 14, frame * CFrame.new(2, -22, -1), rock:Lerp(Color3.new(), 0.15), Enum.Material.Slate)
	cyl(model, 12, 14, frame * CFrame.new(1, -36, 0), rock:Lerp(Color3.new(), 0.28), Enum.Material.Slate)
	cyl(model, 58, 0.5, frame * CFrame.new(0, -0.3, 0), accent, Enum.Material.Neon)
	-- name of the tower over the way in
	for _, side in { -1, 1 } do
		solid(model, Vector3.new(2, 15, 2), frame * CFrame.new(side * 9, 7.5, 16), WHITE)
		ball(model, 2.6, (frame * CFrame.new(side * 9, 16, 16)).Position, accent, Enum.Material.Neon)
	end
	local sign = deco(model, Vector3.new(20, 4.4, 1), frame * CFrame.new(0, 15, 16), rgb(40, 45, 80))
	sign.Name = "TowerSign"
	deco(model, Vector3.new(21, 5.4, 0.6), frame * CFrame.new(0, 15, 16.2), accent, Enum.Material.Neon)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 30
		sg.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = rgb(255, 225, 90)
		label.TextStrokeTransparency = 0.2
		loc(label, "portal.next", { n = tower, name = { key = "tower." .. mood.key }, from = (tower - 1) * Layout.STAGES + 1, to = tower * Layout.STAGES })
		label.Parent = sg
		sg.Parent = sign
	end
	-- the way home
	local home = Scenery.buildPortal(model, CFrame.lookAt((frame * CFrame.new(15, 0, 4)).Position, Vector3.new(padPos.X, ground, padPos.Z)), rgb(120, 225, 255), "portal.home", nil, loc)
	home.Name = "HomePortal"
	model.Parent = parent
	return home
end

return Scenery
