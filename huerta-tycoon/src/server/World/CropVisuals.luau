--!strict
-- Procedural crop models, one recognizable silhouette per seed. Rebuilt only when the growth stage changes.
-- The client plays a little "pop" on every new model (UI/Ambience), so the model carries its part count and pivot.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Trophies = require(ReplicatedStorage.Shared.Trophies)

local CropVisuals = {}

local STAGES = 5 -- 0..4 growing, 5 = ripe
CropVisuals.STAGES = STAGES
CropVisuals.MAX_PARTS = 24 -- budget per tile (30 tiles x 6 plots must stay cheap on phones)

local SOIL = Color3.fromRGB(122, 80, 50)
local SOIL_WET = Color3.fromRGB(88, 56, 36)
local SOIL_LOCKED = Color3.fromRGB(96, 142, 70)
local MOUND = Color3.fromRGB(70, 46, 30)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

type Props = { [string]: any }

local function base(part: BasePart, model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?)
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cf
	part.Color = color
	if props then
		for k, v in props do
			(part :: any)[k] = v
		end
	end
	part.Parent = model
end

local function block(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local part = Instance.new("Part")
	base(part, model, name, size, cf, color, props)
	return part
end

-- Sphere, or an ellipsoid when the size is not uniform.
local function ball(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local part = Instance.new("Part")
	if math.abs(size.X - size.Y) < 0.01 and math.abs(size.Y - size.Z) < 0.01 then
		part.Shape = Enum.PartType.Ball
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	base(part, model, name, size, cf, color, props)
	return part
end

-- Upright cylinder centered on cf.
local function cyl(model: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, props: Props?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	base(part, model, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, props)
	return part
end

function CropVisuals.stageFor(progress: number): number
	if progress >= 1 then
		return STAGES
	end
	return math.clamp(math.floor(progress * STAGES), 0, STAGES - 1)
end

-- ===== looks =====

type Look = { color: Color3, props: Props, rainbow: boolean }

local GLOWING = { starfruit = true, moonmelon = true, cosmiclotus = true }

-- How the fruit itself is painted: unripe fruit blends from the stem color, mutations change color AND material.
local function fruitLook(seed: Config.Seed, stage: number, mutation: string?): Look
	local ripe = stage == STAGES
	if ripe and mutation then
		if mutation == "Golden" then
			return { color = Color3.fromRGB(255, 205, 40), props = { Material = Enum.Material.Foil, Reflectance = 0.2, CastShadow = true }, rainbow = false }
		elseif mutation == "Frozen" then
			return { color = Color3.fromRGB(176, 232, 255), props = { Material = Enum.Material.Ice, Reflectance = 0.15, CastShadow = true }, rainbow = false }
		elseif mutation == "Wet" then
			return { color = seed.fruitColor:Lerp(Color3.fromRGB(70, 130, 255), 0.35), props = { Reflectance = 0.45, CastShadow = true }, rainbow = false }
		elseif mutation == "Shocked" then
			return { color = Color3.fromRGB(130, 225, 255), props = { Material = Enum.Material.Neon }, rainbow = false }
		elseif mutation == "Rainbow" then
			return { color = Color3.fromRGB(255, 110, 255), props = { Material = Enum.Material.Neon }, rainbow = true }
		end
		local m = Config.MutationById[mutation]
		if m then
			return { color = m.color, props = { Material = Enum.Material.Neon }, rainbow = false }
		end
	end
	local t = if ripe then 1 elseif stage >= 4 then 0.65 else 0.3
	local unripe = seed.stemColor:Lerp(Color3.fromRGB(190, 220, 110), 0.35)
	local color = unripe:Lerp(seed.fruitColor, t)
	if ripe and GLOWING[seed.id] then
		return { color = color, props = { Material = Enum.Material.Neon }, rainbow = false }
	end
	return { color = color, props = { CastShadow = ripe }, rainbow = false }
end

local function fruit(model: Instance, look: Look, size: Vector3, cf: CFrame): Part
	local part = ball(model, "Fruit", size, cf, look.color, look.props)
	if look.rainbow then
		CollectionService:AddTag(part, "CK_Rainbow")
	end
	return part
end

-- Pointed leaf (a flat ellipsoid) leaning outward from `at`.
local function blade(model: Instance, at: CFrame, yaw: number, len: number, lean: number, color: Color3)
	ball(model, "Leaf", Vector3.new(0.22, len, math.clamp(len * 0.36, 0.45, 1.1)), at * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(lean), 0, 0) * CFrame.new(0, len * 0.5, 0), color)
end

local function mound(model: Instance, top: CFrame, w: number, d: number)
	ball(model, "Mound", Vector3.new(w, 0.9, d), top * CFrame.new(0, 0.05, 0), MOUND, { Material = Enum.Material.Ground })
end

local function flatLeaf(model: Instance, at: CFrame, diameter: number, color: Color3)
	cyl(model, "Leaf", diameter, 0.16, at, color)
end

-- Fixed directions on the upper half of a sphere (berries, apples...).
local DIRS: { Vector3 } = {}
do
	for i = 0, 11 do
		local y = 0.85 - (i / 11) * 1.05
		local r = math.sqrt(math.max(0, 1 - y * y))
		local a = i * 2.39996
		DIRS[i + 1] = Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
	end
end

-- ===== one builder per seed =====

type Builder = (model: Model, top: CFrame, seed: Config.Seed, stage: number, g: number, look: Look) -> ()

local builders: { [string]: Builder } = {}

builders.carrot = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	for _, z in { -1.5, 1.5 } do
		mound(model, top * CFrame.new(0, 0, z), 5.6, 1.9)
		for _, x in { -1.5, 1.5 } do
			local at = top * CFrame.new(x, 0.25, z)
			local len = 0.9 + 2.3 * g
			blade(model, at, x + z, len, 14, seed.stemColor)
			blade(model, at, x + z + math.pi / 2, len * 0.85, -16, seed.stemColor:Lerp(Color3.new(1, 1, 1), 0.12))
			if stage >= 3 then
				local d = if ripe then 1.25 else 0.8
				local root = cyl(model, "Fruit", d, 0.9, at * CFrame.new(0, 0.2, 0), look.color, look.props)
				if look.rainbow then
					CollectionService:AddTag(root, "CK_Rainbow")
				end
			end
		end
	end
end

builders.tomato = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	mound(model, top, 4.2, 4.2)
	local h = 1.2 + 3.4 * g
	block(model, "Stake", Vector3.new(0.28, h + 0.8, 0.28), top * CFrame.new(0, (h + 0.8) / 2, 0), Color3.fromRGB(170, 130, 84), { Material = Enum.Material.Wood })
	local bush = 1.2 + 2.3 * g
	ball(model, "Bush", Vector3.new(bush * 1.2, bush * 1.25, bush * 1.2), top * CFrame.new(0, h * 0.55, 0), seed.stemColor, { CastShadow = true })
	ball(model, "Bush", Vector3.one * bush * 0.8, top * CFrame.new(bush * 0.45, h * 0.35, bush * 0.2), seed.stemColor:Lerp(Color3.new(1, 1, 1), 0.1))
	if stage >= 3 then
		local n = if ripe then 6 else 3
		local size = seed.fruitSize * (if ripe then 0.9 else 0.55)
		for i = 1, n do
			local a = (i / n) * math.pi * 2 + 0.4
			fruit(model, look, Vector3.one * size, top * CFrame.new(math.cos(a) * bush * 0.62, h * (0.3 + (i % 3) * 0.2), math.sin(a) * bush * 0.62))
		end
	end
end

builders.corn = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	mound(model, top, 6, 2)
	local h = 1.5 + 6 * g
	local dark = seed.stemColor:Lerp(Color3.new(0, 0, 0), 0.18)
	for k, x in { -1.9, 0, 1.9 } do
		local at = top * CFrame.new(x, 0, (k % 2) * 0.5 - 0.25) * CFrame.Angles(0, k * 1.3, 0)
		-- a stalk that tapers, with long drooping leaves in pairs up its height
		-- a sturdy stalk with long drooping leaves up its height
		cyl(model, "Stalk", 0.55, h, at * CFrame.new(0, h / 2, 0), dark, { CastShadow = true })
		local leaf = 1.4 + 2.6 * g
		blade(model, at * CFrame.new(0, h * 0.32, 0), 0, leaf, 62, seed.stemColor)
		blade(model, at * CFrame.new(0, h * 0.6, 0), math.pi, leaf * 0.9, 56, seed.stemColor:Lerp(Color3.new(1, 1, 1), 0.12))
		if stage >= 3 then
			local len = seed.fruitSize * (if ripe then 1.3 else 0.85)
			local side = if k % 2 == 0 then 1 else -1
			local cobCF = at * CFrame.new(side * 0.6, h * 0.52, 0) * CFrame.Angles(0, 0, math.rad(-side * 24))
			-- fat kernel cob peeking out of a green husk
			local cob = ball(model, "Fruit", Vector3.new(0.95, len, 0.95), cobCF, look.color, look.props)
			if look.rainbow then
				CollectionService:AddTag(cob, "CK_Rainbow")
			end
			ball(model, "Husk", Vector3.new(1.15, len * 0.7, 0.7), cobCF * CFrame.new(side * 0.22, -len * 0.22, 0), seed.stemColor:Lerp(Color3.fromRGB(200, 230, 140), 0.4))
		end
		if stage >= 4 then
			ball(model, "Tassel", Vector3.new(0.5, 1.3, 0.5), at * CFrame.new(0, h + 0.5, 0), Color3.fromRGB(236, 214, 130))
		end
	end
end

builders.blueberry = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	mound(model, top, 4.6, 4.6)
	local d = 1.6 + 3.2 * g
	local center = top * CFrame.new(0, d * 0.42, 0)
	ball(model, "Bush", Vector3.one * d, center, seed.stemColor, { CastShadow = true })
	ball(model, "Bush", Vector3.one * d * 0.7, top * CFrame.new(d * 0.42, d * 0.3, d * 0.15), seed.stemColor:Lerp(Color3.new(1, 1, 1), 0.1))
	ball(model, "Bush", Vector3.one * d * 0.62, top * CFrame.new(-d * 0.4, d * 0.26, -d * 0.2), seed.stemColor:Lerp(Color3.new(0, 0, 0), 0.1))
	if stage >= 3 then
		local n = if ripe then 12 else 6
		local size = if ripe then 0.62 else 0.42
		for i = 1, n do
			fruit(model, look, Vector3.one * size, center * CFrame.new(DIRS[i] * (d * 0.5)))
		end
	end
end

local function vineLeaves(model: Model, top: CFrame, color: Color3, g: number)
	for i = 1, 3 do
		local a = i * 2.1
		local r = 1.4 + 1.1 * g
		flatLeaf(model, top * CFrame.new(math.cos(a) * r, 0.5 + i * 0.12, math.sin(a) * r) * CFrame.Angles(math.cos(a) * 0.25, 0, math.sin(a) * 0.25), 1.4 + 1.6 * g, color)
	end
	block(model, "Vine", Vector3.new(0.3, 0.3, 2.4 + 2 * g), top * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0.7, 0), color)
end

builders.pumpkin = function(model, top, seed, stage, g, look)
	mound(model, top, 5, 5)
	vineLeaves(model, top, seed.stemColor, g)
	if stage >= 2 then
		local d = seed.fruitSize * (0.35 + 0.95 * g)
		local at = top * CFrame.new(0.2, d * 0.37 + 0.2, 0.2)
		fruit(model, look, Vector3.new(d, d * 0.78, d), at)
		local rib = look.color:Lerp(Color3.new(0, 0, 0), 0.1)
		ball(model, "Rib", Vector3.new(d * 0.62, d * 0.8, d * 1.04), at, rib, look.props)
		ball(model, "Rib", Vector3.new(d * 1.04, d * 0.8, d * 0.62), at, look.color:Lerp(Color3.new(1, 1, 1), 0.08), look.props)
		cyl(model, "Stem", d * 0.17, d * 0.3, at * CFrame.new(0, d * 0.44, 0) * CFrame.Angles(0, 0, 0.25), Color3.fromRGB(96, 128, 48))
	end
end

builders.watermelon = function(model, top, seed, stage, g, look)
	mound(model, top, 5, 5)
	vineLeaves(model, top, seed.stemColor, g)
	if stage >= 2 then
		local d = seed.fruitSize * (0.35 + 0.85 * g)
		local at = top * CFrame.new(0.2, d * 0.5 + 0.15, 0) * CFrame.Angles(0, 0.5, 0)
		fruit(model, look, Vector3.new(d * 1.35, d, d), at)
		if not look.rainbow and look.props.Material == nil then
			local stripe = look.color:Lerp(Color3.fromRGB(150, 220, 120), 0.6)
			for i = 0, 2 do
				ball(model, "Stripe", Vector3.new(d * 1.37, d * 1.03, d * 0.17), at * CFrame.Angles(i * math.pi / 3, 0, 0), stripe)
			end
		end
	end
end

local function fruitTree(model: Model, top: CFrame, seed: Config.Seed, stage: number, g: number, look: Look, leaf: Color3, fruitSize: Vector3, wide: number)
	local ripe = stage == STAGES
	mound(model, top, 3.6, 3.6)
	local h = 1.8 + 5.4 * g
	cyl(model, "Trunk", 0.5 + 0.9 * g, h, top * CFrame.new(0, h / 2, 0), seed.stemColor, { Material = Enum.Material.Wood, CastShadow = true })
	local crown = 1.6 + 3.3 * g
	local center = top * CFrame.new(0, h + crown * 0.22, 0)
	ball(model, "Crown", Vector3.new(crown * wide, crown, crown * wide), center, leaf, { CastShadow = true })
	ball(model, "Crown", Vector3.one * crown * 0.7, center * CFrame.new(crown * 0.36, crown * 0.28, crown * 0.12), leaf:Lerp(Color3.new(1, 1, 1), 0.1))
	ball(model, "Crown", Vector3.one * crown * 0.62, center * CFrame.new(-crown * 0.38, crown * 0.1, -crown * 0.2), leaf:Lerp(Color3.new(0, 0, 0), 0.1))
	if stage >= 3 then
		local n = if ripe then 7 else 4
		local scale = if ripe then 1 else 0.6
		for i = 1, n do
			local dir = DIRS[i + 3]
			fruit(model, look, fruitSize * scale, center * CFrame.new(Vector3.new(dir.X * wide, dir.Y - 0.12, dir.Z * wide) * (crown * 0.5)))
		end
	end
end

builders.apple = function(model, top, seed, stage, g, look)
	fruitTree(model, top, seed, stage, g, look, Color3.fromRGB(74, 164, 72), Vector3.one * seed.fruitSize, 1)
end

builders.mango = function(model, top, seed, stage, g, look)
	fruitTree(model, top, seed, stage, g, look, Color3.fromRGB(46, 128, 74), Vector3.new(seed.fruitSize * 0.8, seed.fruitSize * 1.2, seed.fruitSize * 0.8), 1.25)
end

builders.dragonfruit = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	mound(model, top, 4, 4)
	local h = 1.4 + 3.6 * g
	cyl(model, "Post", 0.6, h, top * CFrame.new(0, h / 2, 0), Color3.fromRGB(150, 110, 70), { Material = Enum.Material.Wood, CastShadow = true })
	local arm = 1.4 + 2.4 * g
	for i = 1, 4 do
		local a = i * math.pi / 2 + 0.4
		local at = top * CFrame.new(0, h, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(118), 0, 0)
		ball(model, "Arm", Vector3.new(0.75, arm, 0.75), at * CFrame.new(0, arm * 0.45, 0), seed.stemColor, { CastShadow = true })
		if stage >= 3 and (ripe or i % 2 == 0) then
			local s = seed.fruitSize * (if ripe then 0.78 else 0.5)
			local tip = at * CFrame.new(0, arm * 0.95, 0)
			fruit(model, look, Vector3.new(s, s * 1.3, s), tip)
			block(model, "Scale", Vector3.new(s * 0.3, s * 0.5, s * 1.15), tip * CFrame.Angles(0, 0.8, 0.5), Color3.fromRGB(120, 210, 110))
		end
	end
end

-- Eight-point star made of two crossed plates.
local function star(model: Model, look: Look, at: CFrame, s: number)
	local a = block(model, "Fruit", Vector3.new(s, s, s * 0.3), at, look.color, look.props)
	local b = block(model, "Fruit", Vector3.new(s, s, s * 0.3), at * CFrame.Angles(0, 0, math.rad(45)), look.color, look.props)
	if look.rainbow then
		CollectionService:AddTag(a, "CK_Rainbow")
		CollectionService:AddTag(b, "CK_Rainbow")
	end
end

builders.starfruit = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	mound(model, top, 3.6, 3.6)
	local h = 1.4 + 4.4 * g
	cyl(model, "Trunk", 0.4 + 0.4 * g, h, top * CFrame.new(0, h / 2, 0), Color3.fromRGB(120, 92, 60), { Material = Enum.Material.Wood, CastShadow = true })
	local crown = 1.5 + 3 * g
	local center = top * CFrame.new(0, h + crown * 0.2, 0)
	ball(model, "Crown", Vector3.new(crown * 1.15, crown * 0.85, crown * 1.15), center, seed.stemColor, { CastShadow = true })
	ball(model, "Crown", Vector3.one * crown * 0.6, center * CFrame.new(crown * 0.3, crown * 0.3, 0), seed.stemColor:Lerp(Color3.new(1, 1, 1), 0.12))
	if stage >= 3 then
		local n = if ripe then 5 else 3
		local s = seed.fruitSize * (if ripe then 0.85 else 0.5)
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			star(model, look, center * CFrame.new(math.cos(a) * crown * 0.62, -crown * 0.12 + (i % 2) * crown * 0.3, math.sin(a) * crown * 0.62) * CFrame.Angles(0, -a + math.pi / 2, 0), s)
		end
	end
end

builders.moonmelon = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	mound(model, top, 5, 5)
	vineLeaves(model, top, seed.stemColor, g)
	if stage >= 2 then
		local d = seed.fruitSize * (0.35 + 0.8 * g)
		local at = top * CFrame.new(0, d * 0.5 + 0.2, 0)
		fruit(model, look, Vector3.one * d, at)
		local crater = look.color:Lerp(Color3.fromRGB(90, 100, 170), 0.45)
		for i = 1, 3 do
			local dir = DIRS[i * 2]
			ball(model, "Crater", Vector3.one * d * 0.3, at * CFrame.new(dir * (d * 0.41)), crater, look.props)
		end
		if stage >= 4 then
			cyl(model, "Ring", d * 1.7, 0.12, at * CFrame.Angles(math.rad(20), 0, math.rad(12)), Color3.fromRGB(215, 225, 255), { Material = Enum.Material.Neon, Transparency = if ripe then 0.15 else 0.5 })
		end
	end
end

builders.cosmiclotus = function(model, top, seed, stage, g, look)
	local ripe = stage == STAGES
	flatLeaf(model, top * CFrame.new(0, 0.2, 0), 3 + 2.6 * g, seed.stemColor)
	local at = top * CFrame.new(0, 0.5 + 0.5 * g, 0)
	local len = 0.9 + 2 * g
	local inner = look.color:Lerp(Color3.fromRGB(255, 190, 240), 0.55)
	if stage >= 1 then
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			local petal = ball(model, "Fruit", Vector3.new(len * 0.55, 0.3, len), at * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(22 + 10 * (1 - g)), 0, 0) * CFrame.new(0, 0, -len * 0.5), look.color, look.props)
			if look.rainbow then
				CollectionService:AddTag(petal, "CK_Rainbow")
			end
		end
	end
	if stage >= 3 then
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2 + 0.5
			ball(model, "Petal", Vector3.new(len * 0.42, 0.28, len * 0.75), at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(58), 0, 0) * CFrame.new(0, 0, -len * 0.36), inner, look.props)
		end
	end
	ball(model, "Heart", Vector3.one * (0.5 + 0.9 * g), at * CFrame.new(0, 0.35 + 0.3 * g, 0), if ripe then Color3.fromRGB(255, 250, 200) else seed.stemColor:Lerp(look.color, 0.5), { Material = if ripe then Enum.Material.Neon else Enum.Material.SmoothPlastic })
end

-- Fallback for seeds added to Config without a dedicated builder.
local function generic(model: Model, top: CFrame, seed: Config.Seed, stage: number, g: number, look: Look)
	if seed.shape == "Tree" then
		fruitTree(model, top, seed, stage, g, look, Color3.fromRGB(74, 164, 72), Vector3.one * seed.fruitSize, 1)
	else
		builders.tomato(model, top, seed, stage, g, look)
	end
end

local function build(model: Model, top: CFrame, seed: Config.Seed, stage: number, mutation: string?)
	local g = (stage + 1) / (STAGES + 1) -- 0.17 .. 1
	if stage == 0 then
		mound(model, top, 2.6, 2.6)
		block(model, "Sprout", Vector3.new(0.3, 1, 0.3), top * CFrame.new(0, 0.7, 0), seed.stemColor)
		blade(model, top * CFrame.new(0, 1, 0), 0, 0.9, 55, seed.stemColor)
		blade(model, top * CFrame.new(0, 1, 0), math.pi, 0.9, 55, seed.stemColor)
		return
	end
	local look = fruitLook(seed, stage, mutation)
	local builder: Builder = builders[seed.id] or generic :: Builder
	builder(model, top, seed, stage, g, look)

	if stage == STAGES then
		local mut = if mutation then Config.MutationById[mutation] else nil
		local anchor = block(model, "Glow", Vector3.new(5, 0.2, 5), top * CFrame.new(0, 1.5, 0), Color3.new(1, 1, 1), { Transparency = 1, CanQuery = false })
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = SPARKLE
		sparkles.Color = ColorSequence.new(if mut then mut.color else Color3.fromRGB(255, 240, 150))
		sparkles.Rate = if mut then 14 else 4
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(1, 3)
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
		sparkles.LightEmission = 0.8
		sparkles.Parent = anchor
		if mut then
			-- only mutated crops carry a real light: 30 ripe tiles must not mean 30 lights
			local light = Instance.new("PointLight")
			light.Range = 9
			light.Brightness = 1.6
			light.Color = mut.color
			light.Parent = anchor
			if mutation == "Frozen" then
				for i = 1, 2 do
					block(model, "IceShard", Vector3.new(0.5, 1.8, 0.5), top * CFrame.new((i * 2 - 3) * 1.6, 0.7, (i * 2 - 3) * -0.9) * CFrame.Angles(0.3 * i, i, 0.4), Color3.fromRGB(190, 236, 255), { Material = Enum.Material.Ice, Transparency = 0.25 })
				end
			end
		end
	end
end

local function partCount(model: Instance): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
CropVisuals.partCount = partCount

-- Builds a crop model standing on `top` (used by render and by the tests). The caller parents it.
-- size ("Big" / "Giant") and extraScale enlarge or shrink the finished model around its base.
function CropVisuals.buildModel(top: CFrame, seed: Config.Seed, stage: number, mutation: string?, size: string?, extraScale: number?): Model
	local model = Instance.new("Model")
	model.Name = "Crop"
	build(model, top, seed, stage, mutation)
	model.WorldPivot = top
	model:SetAttribute("Parts", partCount(model))
	model:SetAttribute("Stage", stage)
	local scale = Trophies.scale(size) * (extraScale or 1)
	if math.abs(scale - 1) > 0.01 then
		model:ScaleTo(scale)
	end
	model:SetAttribute("BaseScale", scale) -- the client's pop animation scales relative to this
	return model
end

-- Renders the crop on a tile. mutation is only used for visuals of ripe crops (pre-rolled "preview").
function CropVisuals.render(tile: BasePart, seedId: string?, progress: number, mutation: string?, size: string?)
	local existing = tile:FindFirstChild("Crop")
	if not seedId then
		if existing then
			existing:Destroy()
		end
		return
	end
	local seed = Config.SeedById[seedId]
	if not seed then
		return
	end
	local stage = CropVisuals.stageFor(progress)
	local key = seedId .. ":" .. stage .. ":" .. (mutation or "") .. ":" .. (size or "")
	if existing and existing:GetAttribute("Key") == key then
		return
	end
	if existing then
		existing:Destroy()
	end
	local tileTop = tile.CFrame * CFrame.new(0, tile.Size.Y / 2, 0)
	local model = CropVisuals.buildModel(tileTop, seed, stage, mutation, size)
	model:SetAttribute("Key", key)
	model.Parent = tile
end

function CropVisuals.setTileState(tile: BasePart, unlocked: boolean, hasCrop: boolean, isNextBuyable: boolean, cost: number?)
	-- locked tiles are lawn waiting to be tilled; unlocked ones are rich soil (darker once planted)
	tile.Color = if not unlocked then SOIL_LOCKED elseif hasCrop then SOIL_WET else SOIL
	tile.Material = if unlocked then Enum.Material.Ground else Enum.Material.LeafyGrass
	local gui = tile:FindFirstChild("LockGui") :: SurfaceGui?
	if not unlocked and isNextBuyable and cost then
		if not gui then
			local g = Instance.new("SurfaceGui")
			g.Name = "LockGui"
			g.Face = Enum.NormalId.Top
			g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			g.PixelsPerStud = 30
			g.LightInfluence = 0
			local t = Instance.new("TextLabel")
			t.Name = "Text"
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.TextScaled = true
			t.Font = Enum.Font.FredokaOne
			t.TextColor3 = Color3.fromRGB(255, 230, 120)
			local s = Instance.new("UIStroke")
			s.Thickness = 2
			s.Parent = t
			t.Parent = g
			g.Parent = tile
			gui = g
		end
		local text = (gui :: SurfaceGui):FindFirstChild("Text") :: TextLabel
		text.Text = "🔒\n$" .. require(ReplicatedStorage.Shared.Format).abbrev(cost)
	elseif gui then
		gui:Destroy()
	end
end

return CropVisuals
