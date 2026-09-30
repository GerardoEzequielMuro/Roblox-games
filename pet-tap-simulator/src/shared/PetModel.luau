--!strict
-- Procedural low-poly pets. PetModel.build(petId, tier, opts) returns a Model whose PrimaryPart
-- ("Root") is anchored; every other part is welded to it, so PivotTo on the model is cheap.
-- Front of the pet faces -Z (the model's LookVector).
--
-- Anatomy: three rigs ("ball" = quadruped with a big head, "block" = cube pet, "tall" = upright
-- bird-like body) and a species "family" per pet that draws the face, ears, tail and wings.
-- Parts that move (wings, tail, ears, aura orbs) hang from a Weld named "Joint" with an "Anim"
-- attribute; PetFollow drives Joint.C0 on the client. In ViewportFrames they simply stay put.
--
-- opts.lite = true (icons, hatch reveal) skips particles, lights, trails and the aura.
local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Palette = require(script.Parent.Palette)

local PetModel = {}

-- lite: icons (no effects at all). fx = false: world pets on the lite profile (geometry
-- aura and orbs stay; no trail, no light, half the particles). lights: point light allowed.
export type BuildOpts = { lite: boolean?, lights: boolean?, fx: boolean? }

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local BLACK = Color3.fromRGB(28, 26, 38)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLUSH = Color3.fromRGB(255, 140, 165)
local BEAK = Color3.fromRGB(255, 170, 40)
local PINK = Color3.fromRGB(255, 130, 160)
local TONGUE = Color3.fromRGB(255, 105, 130)
local SECRET = Color3.fromRGB(170, 60, 255)

type Joint = { kind: string, hinge: CFrame, side: number }
type Rig = {
	c: Vector3, -- head centre
	r: Vector3, -- head radii
	block: boolean,
	upright: boolean,
	faceY: number, -- face centre above the head centre
	rear: number, -- z of the body's back
	footY: number, -- lowest point
	wing: Vector3, -- wing hinge (x is mirrored)
	tail: Vector3, -- tail hinge
}
type Ctx = {
	model: Model,
	root: BasePart,
	s: number,
	tint: { BasePart },
	lite: boolean,
	rig: Rig,
	color: Color3,
	accent: Color3,
	light: Color3,
	mat: Enum.Material,
	extras: { [string]: boolean },
}

local V = Vector3.new

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function lum(c: Color3): number
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end

-- shape: "Block" | "Ball" | "Cylinder" | "Ellipsoid". cf and size are in pet units (scaled by ctx.s).
local function add(ctx: Ctx, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, tintable: boolean?, joint: Joint?): BasePart
	local p = Instance.new("Part")
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Name = name
	p.Size = size * ctx.s
	p.CFrame = CFrame.new(cf.Position * ctx.s) * cf.Rotation
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	if shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	if joint then
		local hinge = CFrame.new(joint.hinge.Position * ctx.s) * joint.hinge.Rotation
		local weld = Instance.new("Weld")
		weld.Name = "Joint"
		weld.Part0 = ctx.root
		weld.Part1 = p
		weld.C0 = hinge
		weld.C1 = p.CFrame:ToObjectSpace(hinge)
		weld:SetAttribute("Anim", joint.kind)
		weld:SetAttribute("Side", joint.side)
		weld.Parent = p
	else
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ctx.root
		weld.Part1 = p
		weld.Parent = p
	end
	p.Parent = ctx.model
	if tintable then
		table.insert(ctx.tint, p)
		p:SetAttribute("Tint", #ctx.tint)
	end
	return p
end

local function emitter(parent: Instance, texture: string, color: Color3, rate: number, size: number, speed: number, light: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = light or 0.8
	e.LockedToPart = false
	e.Parent = parent
	return e
end

---------------------------------------------------------------------------
-- Head surface helpers: (x, y) are offsets from the face centre, `out` pushes the point
-- away from the surface.
---------------------------------------------------------------------------
local function surfaceZ(rig: Rig, x: number, yy: number): number
	if rig.block then
		return -rig.r.Z
	end
	local k = 1 - (x / rig.r.X) ^ 2 - (yy / rig.r.Y) ^ 2
	return -rig.r.Z * math.sqrt(math.max(k, 0.04))
end

local function face(rig: Rig, x: number, y: number, out: number?): Vector3
	local yy = y + rig.faceY
	return rig.c + V(x, yy, surfaceZ(rig, x, yy) - (out or 0))
end

-- Same point, turned so a flat part hugs the curve of the head.
local function faceCF(rig: Rig, x: number, y: number, out: number?): CFrame
	local p = face(rig, x, y, out)
	if rig.block then
		return CFrame.new(p)
	end
	local yy = y + rig.faceY
	return CFrame.new(p) * CFrame.Angles(0, -math.atan2(x, -surfaceZ(rig, x, yy)) * 0.8, 0)
end

-- Height of the head's top surface at horizontal offset x.
local function crownY(rig: Rig, x: number): number
	if rig.block then
		return rig.c.Y + rig.r.Y
	end
	return rig.c.Y + rig.r.Y * math.sqrt(math.max(0.04, 1 - (x / rig.r.X) ^ 2))
end

---------------------------------------------------------------------------
-- Bodies
---------------------------------------------------------------------------
local function buildBody(ctx: Ctx, body: string, birdFeet: boolean): Rig
	local color, mat = ctx.color, ctx.mat
	local paw = lighten(color, 0.32)
	if body == "block" then
		add(ctx, "Body", "Block", V(1.6, 1.3, 1.7), CFrame.new(0, -0.35, 0.5), color, mat, true)
		add(ctx, "Head", "Block", V(1.85, 1.7, 1.7), CFrame.new(0, 0.4, -0.45), color, mat, true)
		for _, side in { -1, 1 } do
			add(ctx, "Paw", "Block", V(0.56, 0.5, 0.6), CFrame.new(0.5 * side, -1.1, -0.15), paw)
			add(ctx, "Paw", "Block", V(0.56, 0.5, 0.6), CFrame.new(0.5 * side, -1.1, 0.98), paw)
		end
		return { c = V(0, 0.4, -0.45), r = V(0.925, 0.85, 0.85), block = true, upright = false, faceY = 0, rear = 1.35, footY = -1.35, wing = V(0.72, 0.28, 0.6), tail = V(0, -0.2, 1.3) }
	elseif body == "tall" then
		add(ctx, "Body", "Ellipsoid", V(1.9, 2.4, 1.8), CFrame.new(), color, mat, true)
		add(ctx, "Belly", "Ellipsoid", V(1.35, 1.55, 0.5), CFrame.new(0, -0.42, -0.66), ctx.light)
		for _, side in { -1, 1 } do
			add(ctx, "Foot", "Ellipsoid", V(0.55, 0.3, 0.8), CFrame.new(0.42 * side, -1.13, -0.3), if birdFeet then BEAK else paw)
		end
		return { c = V(0, 0, 0), r = V(0.95, 1.2, 0.9), block = false, upright = true, faceY = 0.42, rear = 0.9, footY = -1.28, wing = V(0.86, 0.2, 0.15), tail = V(0, -0.6, 0.8) }
	end
	add(ctx, "Body", "Ellipsoid", V(1.6, 1.4, 1.9), CFrame.new(0, -0.3, 0.45), color, mat, true)
	add(ctx, "Head", "Ball", V(1.9, 1.9, 1.9), CFrame.new(0, 0.4, -0.5), color, mat, true)
	for _, side in { -1, 1 } do
		add(ctx, "Paw", "Ball", V(0.62, 0.62, 0.62), CFrame.new(0.5 * side, -0.98, -0.2), paw)
		add(ctx, "Paw", "Ball", V(0.62, 0.62, 0.62), CFrame.new(0.52 * side, -0.98, 0.95), paw)
	end
	return { c = V(0, 0.4, -0.5), r = V(0.95, 0.95, 0.95), block = false, upright = false, faceY = 0, rear = 1.4, footY = -1.29, wing = V(0.6, 0.25, 0.55), tail = V(0, -0.15, 1.3) }
end

---------------------------------------------------------------------------
-- Faces
---------------------------------------------------------------------------
-- style: "dot" (big glossy), "fierce" (sclera + slit pupil + brow), "glow" (neon, no pupil),
-- "alien" (huge tilted), "rect" (golem). k scales the eyes, out pushes them off the surface.
local function eyes(ctx: Ctx, style: string, k: number, out: number)
	local rig = ctx.rig
	for _, side in { -1, 1 } do
		local x = 0.43 * side
		if style == "fierce" or style == "glow" then
			add(ctx, "Eye", "Ellipsoid", V(0.46, 0.42, 0.2) * k, faceCF(rig, x, 0.12, out), if style == "glow" then ctx.accent else WHITE, if style == "glow" then Enum.Material.Neon else nil)
			if style == "fierce" then
				add(ctx, "Pupil", "Ellipsoid", V(0.16, 0.34, 0.12) * k, faceCF(rig, x * 0.95, 0.12, out + 0.09), BLACK)
			end
			add(ctx, "Brow", "Block", V(0.58, 0.14, 0.16) * k, faceCF(rig, x, 0.4, out + 0.06) * CFrame.Angles(0, 0, math.rad(18 * side)), darken(ctx.color, 0.5))
		elseif style == "rect" then
			add(ctx, "Eye", "Block", V(0.42, 0.24, 0.1) * k, faceCF(rig, x, 0.14, out + 0.02) * CFrame.Angles(0, 0, math.rad(10 * side)), ctx.accent, Enum.Material.Neon)
		elseif style == "alien" then
			add(ctx, "Eye", "Ellipsoid", V(0.5, 0.68, 0.24) * k, faceCF(rig, x, 0.14, out) * CFrame.Angles(0, 0, math.rad(18 * side)), BLACK)
			add(ctx, "EyeShine", "Ball", V(0.18, 0.18, 0.18) * k, CFrame.new(face(rig, x + 0.08, 0.3, out + 0.1)), Color3.fromRGB(190, 255, 200), Enum.Material.Neon)
		else
			add(ctx, "Eye", "Ellipsoid", V(0.4, 0.54, 0.24) * k, faceCF(rig, x, 0.12, out), BLACK)
			add(ctx, "EyeShine", "Ball", V(0.17, 0.17, 0.17) * k, CFrame.new(face(rig, x + 0.08, 0.26, out + 0.1)), WHITE, Enum.Material.Neon)
			add(ctx, "EyeShine", "Ball", V(0.09, 0.09, 0.09) * k, CFrame.new(face(rig, x - 0.07, 0.0, out + 0.1)), WHITE, Enum.Material.Neon)
		end
		if style == "dot" or style == "alien" then
			add(ctx, "Blush", "Ellipsoid", V(0.34, 0.18, 0.08), faceCF(rig, 0.72 * side, -0.14, 0), BLUSH)
		end
	end
end

local function beak(ctx: Ctx, out: number)
	add(ctx, "Beak", "Ellipsoid", V(0.36, 0.26, 0.5), CFrame.new(face(ctx.rig, 0, -0.12, out + 0.14)), BEAK)
end

local MUZZLE: { [string]: (ctx: Ctx) -> () } = {
	dog = function(ctx)
		local m = face(ctx.rig, 0, -0.26, 0.02)
		add(ctx, "Muzzle", "Ellipsoid", V(0.82, 0.56, 0.5), CFrame.new(m), ctx.light)
		add(ctx, "Nose", "Ellipsoid", V(0.28, 0.2, 0.18), CFrame.new(m + V(0, 0.14, -0.22)), BLACK)
		add(ctx, "Tongue", "Ellipsoid", V(0.2, 0.26, 0.1), CFrame.new(m + V(0, -0.2, -0.2)), TONGUE)
	end,
	bear = function(ctx)
		local m = face(ctx.rig, 0, -0.26, 0.02)
		add(ctx, "Muzzle", "Ellipsoid", V(0.78, 0.56, 0.42), CFrame.new(m), ctx.light)
		add(ctx, "Nose", "Ellipsoid", V(0.3, 0.22, 0.18), CFrame.new(m + V(0, 0.12, -0.19)), BLACK)
		add(ctx, "Mouth", "Ellipsoid", V(0.22, 0.07, 0.07), CFrame.new(m + V(0, -0.12, -0.2)), BLACK)
	end,
	cat = function(ctx)
		local rig = ctx.rig
		local whisker = if lum(ctx.color) > 0.8 then Color3.fromRGB(120, 120, 135) else WHITE
		for _, side in { -1, 1 } do
			add(ctx, "Cheek", "Ball", V(0.36, 0.36, 0.36), CFrame.new(face(rig, 0.17 * side, -0.26, 0)), ctx.light)
			for j = 0, 1 do
				add(ctx, "Whisker", "Block", V(0.6, 0.035, 0.035), CFrame.new(face(rig, 0.8 * side, -0.2 - 0.13 * j, 0.02)) * CFrame.Angles(0, 0, math.rad((8 - 16 * j) * side)), whisker)
			end
		end
		add(ctx, "Nose", "Ellipsoid", V(0.17, 0.13, 0.12), CFrame.new(face(rig, 0, -0.14, 0.07)), PINK)
	end,
	bunny = function(ctx)
		local rig = ctx.rig
		local m = face(rig, 0, -0.24, 0)
		add(ctx, "Muzzle", "Ellipsoid", V(0.52, 0.38, 0.3), CFrame.new(m), ctx.light)
		add(ctx, "Nose", "Ellipsoid", V(0.17, 0.13, 0.12), CFrame.new(m + V(0, 0.1, -0.14)), PINK)
		add(ctx, "Teeth", "Block", V(0.2, 0.2, 0.06), CFrame.new(face(rig, 0, -0.47, 0.03)), WHITE)
	end,
	pig = function(ctx)
		local m = face(ctx.rig, 0, -0.2, 0.06)
		add(ctx, "Snout", "Ellipsoid", V(0.72, 0.52, 0.4), CFrame.new(m), ctx.accent)
		for _, side in { -1, 1 } do
			add(ctx, "Nostril", "Ellipsoid", V(0.1, 0.18, 0.08), CFrame.new(m + V(0.13 * side, 0, -0.18)), darken(ctx.accent, 0.4))
		end
	end,
	fox = function(ctx)
		local rig = ctx.rig
		for _, side in { -1, 1 } do
			add(ctx, "Cheek", "Ellipsoid", V(0.56, 0.5, 0.36), faceCF(rig, 0.58 * side, -0.32, -0.02), ctx.light)
		end
		local m = face(rig, 0, -0.24, 0.12)
		add(ctx, "Muzzle", "Ellipsoid", V(0.62, 0.46, 0.8), CFrame.new(m), ctx.light)
		add(ctx, "Nose", "Ball", V(0.22, 0.22, 0.22), CFrame.new(m + V(0, 0.1, -0.36)), BLACK)
	end,
	wolf = function(ctx)
		local rig = ctx.rig
		for _, side in { -1, 1 } do
			add(ctx, "Cheek", "Ellipsoid", V(0.56, 0.5, 0.36), faceCF(rig, 0.58 * side, -0.32, -0.02), ctx.light)
		end
		local m = face(rig, 0, -0.24, 0.12)
		add(ctx, "Muzzle", "Ellipsoid", V(0.66, 0.48, 0.85), CFrame.new(m), ctx.light)
		add(ctx, "Nose", "Ball", V(0.22, 0.22, 0.22), CFrame.new(m + V(0, 0.1, -0.38)), BLACK)
		for _, side in { -1, 1 } do
			add(ctx, "Fang", "Block", V(0.09, 0.18, 0.07), CFrame.new(m + V(0.15 * side, -0.22, -0.22)), WHITE)
		end
	end,
	bird = function(ctx)
		beak(ctx, 0)
	end,
	phoenix = function(ctx)
		beak(ctx, 0)
		-- crest
		local rig = ctx.rig
		for i = -1, 1 do
			add(ctx, "Crest", "Ellipsoid", V(0.2, 0.75, 0.3), CFrame.new(0.22 * i, crownY(rig, 0.22 * i) + 0.22, rig.c.Z + 0.1) * CFrame.Angles(math.rad(20), 0, math.rad(-22 * i)), ctx.accent)
		end
	end,
	owl = function(ctx)
		local rig = ctx.rig
		for _, side in { -1, 1 } do
			add(ctx, "EyeDisc", "Ellipsoid", V(0.74, 0.74, 0.12), faceCF(rig, 0.43 * side, 0.12, -0.02), ctx.light)
		end
		add(ctx, "Beak", "Ellipsoid", V(0.26, 0.3, 0.34), CFrame.new(face(rig, 0, -0.16, 0.1)), BEAK)
	end,
	penguin = function(ctx)
		local rig = ctx.rig
		add(ctx, "FacePatch", "Ellipsoid", V(1.3, 1.0, 0.3), CFrame.new(face(rig, 0, 0.06, -0.08)), ctx.light)
		beak(ctx, 0.04)
		for _, side in { -1, 1 } do
			add(ctx, "Flipper", "Ellipsoid", V(0.2, 1.05, 0.62), CFrame.new(0.98 * side, -0.1, 0.05) * CFrame.Angles(0, 0, math.rad(14 * side)), ctx.color, nil, true, { kind = "Ear", hinge = CFrame.new(0.92 * side, 0.4, 0.05), side = side })
		end
	end,
	dragon = function(ctx)
		local rig = ctx.rig
		local m = face(rig, 0, -0.26, 0.18)
		add(ctx, "Snout", "Ellipsoid", V(0.9, 0.6, 0.85), CFrame.new(m), lighten(ctx.color, 0.12), ctx.mat, true)
		for _, side in { -1, 1 } do
			add(ctx, "Nostril", "Ball", V(0.11, 0.11, 0.11), CFrame.new(m + V(0.17 * side, 0.17, -0.36)), darken(ctx.color, 0.55))
			add(ctx, "Fang", "Block", V(0.09, 0.2, 0.07), CFrame.new(m + V(0.22 * side, -0.27, -0.25)), WHITE)
		end
		-- belly plates
		if not rig.upright then
			add(ctx, "Chest", "Ellipsoid", V(1.0, 0.7, 1.3), CFrame.new(0, -0.78, 0.4), ctx.accent)
		end
	end,
	unicorn = function(ctx)
		local rig = ctx.rig
		local m = face(rig, 0, -0.3, 0.12)
		add(ctx, "Muzzle", "Ellipsoid", V(0.74, 0.62, 0.7), CFrame.new(m), ctx.light)
		for _, side in { -1, 1 } do
			add(ctx, "Nostril", "Ellipsoid", V(0.09, 0.13, 0.07), CFrame.new(m + V(0.14 * side, 0.02, -0.33)), darken(ctx.accent, 0.35))
		end
		for i = 0, 3 do
			add(ctx, "Mane", "Ball", V(0.52 - i * 0.04, 0.52 - i * 0.04, 0.52 - i * 0.04), CFrame.new(0, rig.c.Y + rig.r.Y - 0.05 - i * 0.22, rig.c.Z + 0.25 + i * 0.3), ctx.accent)
		end
	end,
	golem = function(ctx)
		local rig = ctx.rig
		add(ctx, "Mouth", "Block", V(0.7, 0.09, 0.08), CFrame.new(face(rig, 0, -0.36, 0.02)), ctx.accent, Enum.Material.Neon)
		add(ctx, "Crack", "Block", V(0.08, 0.7, 0.08), CFrame.new(face(rig, 0.55, 0.45, 0.02)) * CFrame.Angles(0, 0, math.rad(-25)), ctx.accent, Enum.Material.Neon)
		add(ctx, "Crack", "Block", V(0.9, 0.1, 0.1), CFrame.new(0.2, 0.31, 0.6) * CFrame.Angles(0, math.rad(30), 0), ctx.accent, Enum.Material.Neon)
		for _, side in { -1, 1 } do
			add(ctx, "Shoulder", "Block", V(0.62, 0.55, 0.7), CFrame.new(1.02 * side, 0.05, 0.55) * CFrame.Angles(math.rad(12), math.rad(20 * side), math.rad(15 * side)), darken(ctx.color, 0.2), ctx.mat)
		end
	end,
	yeti = function(ctx)
		local rig = ctx.rig
		add(ctx, "FacePatch", "Block", V(1.4, 1.1, 0.1), CFrame.new(face(rig, 0, -0.04, 0)), ctx.accent)
		add(ctx, "Nose", "Ellipsoid", V(0.26, 0.18, 0.14), CFrame.new(face(rig, 0, -0.14, 0.1)), darken(ctx.accent, 0.55))
		for _, side in { -1, 1 } do
			add(ctx, "Fang", "Block", V(0.13, 0.22, 0.08), CFrame.new(face(rig, 0.2 * side, -0.42, 0.08)), WHITE)
		end
	end,
}
MUZZLE.alien = MUZZLE.dog

---------------------------------------------------------------------------
-- Ears
---------------------------------------------------------------------------
local function ears(ctx: Ctx, kind: string)
	local rig = ctx.rig
	local z = rig.c.Z + 0.12
	local color, accent = ctx.color, ctx.accent
	if kind == "cat" or kind == "fox" or kind == "pig" then
		local sz = if kind == "fox" then 0.86 elseif kind == "pig" then 0.52 else 0.7
		local inner = if kind == "fox" then ctx.light elseif kind == "pig" then darken(accent, 0.12) else (if lum(accent) > 0.2 then accent else PINK)
		for _, side in { -1, 1 } do
			local x = 0.56 * side
			local y = crownY(rig, 0.56) + 0.06
			add(ctx, "Ear", "Block", V(sz, sz, 0.24), CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(45)), color, ctx.mat, true)
			add(ctx, "EarInner", "Block", V(sz * 0.56, sz * 0.56, 0.1), CFrame.new(x, y + 0.04, z - 0.1) * CFrame.Angles(0, 0, math.rad(45)), inner)
		end
	elseif kind == "dog" then
		local earColor = if lum(accent) < lum(color) then accent else darken(color, 0.3)
		for _, side in { -1, 1 } do
			add(ctx, "Ear", "Ellipsoid", V(0.36, 1.0, 0.62), CFrame.new((rig.r.X + 0.04) * side, rig.c.Y + 0.18, z) * CFrame.Angles(0, 0, math.rad(12 * side)), earColor, nil, false, { kind = "Ear", hinge = CFrame.new((rig.r.X - 0.05) * side, rig.c.Y + 0.62, z), side = side })
		end
	elseif kind == "bunny" then
		local inner = if lum(accent) > 0.2 then accent else PINK
		for _, side in { -1, 1 } do
			local x = 0.36 * side
			local base = crownY(rig, 0.36)
			local hinge = CFrame.new(x, base - 0.1, z)
			local rot = CFrame.Angles(0, 0, math.rad(-8 * side))
			add(ctx, "Ear", "Ellipsoid", V(0.42, 1.4, 0.3), CFrame.new(x + 0.07 * side, base + 0.52, z) * rot, color, ctx.mat, true, { kind = "Ear", hinge = hinge, side = side })
			add(ctx, "EarInner", "Ellipsoid", V(0.22, 1.0, 0.1), CFrame.new(x + 0.07 * side, base + 0.52, z - 0.13) * rot, inner, nil, false, { kind = "Ear", hinge = hinge, side = side })
		end
	elseif kind == "bear" then
		for _, side in { -1, 1 } do
			local x = 0.66 * side
			local y = crownY(rig, 0.66) + 0.08
			add(ctx, "Ear", "Ball", V(0.62, 0.62, 0.62), CFrame.new(x, y, z), color, ctx.mat, true)
			add(ctx, "EarInner", "Ball", V(0.34, 0.34, 0.34), CFrame.new(x, y, z - 0.2), ctx.light)
		end
	end
end

---------------------------------------------------------------------------
-- Tails and wings
---------------------------------------------------------------------------
local function tail(ctx: Ctx, family: string)
	local rig = ctx.rig
	local function frame(pitch: number): (CFrame, Joint)
		local f = CFrame.new(rig.tail) * CFrame.Angles(math.rad(pitch), 0, 0)
		return f, { kind = "Tail", hinge = f, side = 1 }
	end
	if family == "fox" or family == "wolf" then
		local f, j = frame(-35)
		add(ctx, "Tail", "Ellipsoid", V(0.62, 0.62, 1.25), f * CFrame.new(0, 0, 0.55), ctx.color, ctx.mat, true, j)
		add(ctx, "TailTip", "Ball", V(0.5, 0.5, 0.5), f * CFrame.new(0, 0, 1.12), ctx.light, nil, false, j)
	elseif family == "cat" then
		local f, j = frame(-62)
		add(ctx, "Tail", "Ellipsoid", V(0.26, 0.26, 1.2), f * CFrame.new(0, 0, 0.55), ctx.color, ctx.mat, true, j)
		add(ctx, "TailTip", "Ball", V(0.32, 0.32, 0.32), f * CFrame.new(0, 0, 1.15), ctx.light, nil, false, j)
	elseif family == "dragon" then
		local f, j = frame(-14)
		add(ctx, "Tail", "Ellipsoid", V(0.52, 0.46, 0.95), f * CFrame.new(0, 0, 0.4), ctx.color, ctx.mat, true, j)
		add(ctx, "Tail", "Ellipsoid", V(0.36, 0.32, 0.85), f * CFrame.new(0, 0.05, 1.05), ctx.color, ctx.mat, true, j)
		add(ctx, "TailTip", "Block", V(0.42, 0.14, 0.42), f * CFrame.new(0, 0.08, 1.55) * CFrame.Angles(0, math.rad(45), 0), ctx.accent, nil, false, j)
	elseif family == "pig" then
		local f, j = frame(-30)
		add(ctx, "Tail", "Ball", V(0.3, 0.3, 0.3), f * CFrame.new(0, 0, 0.12), ctx.accent, nil, false, j)
		add(ctx, "Tail", "Ball", V(0.22, 0.22, 0.22), f * CFrame.new(0.12, 0.12, 0.26), ctx.accent, nil, false, j)
	elseif family == "bunny" then
		add(ctx, "Tail", "Ball", V(0.46, 0.46, 0.46), CFrame.new(rig.tail + V(0, 0.05, 0.05)), ctx.light)
	elseif family == "unicorn" then
		local f, j = frame(20)
		for i = 0, 2 do
			add(ctx, "Tail", "Ball", V(0.46 - i * 0.06, 0.46 - i * 0.06, 0.46 - i * 0.06), f * CFrame.new(0, 0, 0.15 + i * 0.3), ctx.accent, nil, false, j)
		end
	elseif family == "phoenix" then
		for i = -1, 1 do
			local f = CFrame.new(rig.tail) * CFrame.Angles(0, math.rad(22 * i), 0) * CFrame.Angles(math.rad(-38), 0, 0)
			add(ctx, "TailFeather", "Ellipsoid", V(0.34, 0.12, 1.3), f * CFrame.new(0, 0, 0.6), if i == 0 then ctx.accent else ctx.color, nil, i ~= 0, { kind = "Tail", hinge = f, side = 1 })
		end
	else
		local f, j = frame(-42)
		add(ctx, "Tail", "Ellipsoid", V(0.3, 0.3, 0.8), f * CFrame.new(0, 0, 0.35), ctx.color, ctx.mat, true, j)
		add(ctx, "TailTip", "Ball", V(0.3, 0.3, 0.3), f * CFrame.new(0, 0, 0.72), ctx.light, nil, false, j)
	end
end

local function wings(ctx: Ctx, family: string)
	local rig = ctx.rig
	for _, side in { -1, 1 } do
		local hinge = CFrame.new(rig.wing.X * side, rig.wing.Y, rig.wing.Z) * CFrame.Angles(0, math.rad(-32 * side), 0) * CFrame.Angles(0, 0, math.rad(24 * side))
		local j: Joint = { kind = "Wing", hinge = hinge, side = side }
		if family == "dragon" then
			add(ctx, "Wing", "Ellipsoid", V(1.7, 1.15, 0.1), hinge * CFrame.new(0.85 * side, 0.1, 0), ctx.accent, nil, false, j)
			add(ctx, "WingBone", "Block", V(1.7, 0.15, 0.15), hinge * CFrame.new(0.85 * side, 0.58, 0), darken(ctx.color, 0.15), nil, false, j)
			add(ctx, "WingBone", "Block", V(0.13, 0.9, 0.13), hinge * CFrame.new(0.9 * side, 0.12, 0) * CFrame.Angles(0, 0, math.rad(-28 * side)), darken(ctx.color, 0.15), nil, false, j)
		else
			add(ctx, "Wing", "Ellipsoid", V(1.35, 0.95, 0.14), hinge * CFrame.new(0.66 * side, 0.05, 0), ctx.accent, nil, false, j)
			add(ctx, "WingTip", "Ellipsoid", V(0.85, 0.6, 0.12), hinge * CFrame.new(1.12 * side, -0.18, -0.03), lighten(ctx.accent, 0.35), nil, false, j)
		end
	end
end

---------------------------------------------------------------------------
-- Extras
---------------------------------------------------------------------------
local EXTRA: { [string]: (ctx: Ctx) -> () } = {
	horn = function(ctx)
		local rig = ctx.rig
		local base = CFrame.new(0, crownY(rig, 0) - 0.05, rig.c.Z - 0.45) * CFrame.Angles(math.rad(-22), 0, 0)
		add(ctx, "Horn", "Block", V(0.26, 0.5, 0.26), base * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, math.rad(45), 0), Palette.Gold, Enum.Material.Neon)
		add(ctx, "Horn", "Block", V(0.16, 0.46, 0.16), base * CFrame.new(0, 0.66, 0) * CFrame.Angles(0, math.rad(20), 0), lighten(Palette.Gold, 0.35), Enum.Material.Neon)
	end,
	horns = function(ctx)
		local rig = ctx.rig
		local col = if lum(ctx.accent) > lum(ctx.color) then ctx.accent else lighten(ctx.color, 0.55)
		for _, side in { -1, 1 } do
			local base = CFrame.new(0.42 * side, crownY(rig, 0.42) - 0.08, rig.c.Z + 0.15) * CFrame.Angles(math.rad(14), 0, math.rad(-24 * side))
			add(ctx, "Horn", "Block", V(0.26, 0.46, 0.26), base * CFrame.new(0, 0.2, 0), col)
			add(ctx, "Horn", "Block", V(0.16, 0.42, 0.16), base * CFrame.new(0, 0.58, 0) * CFrame.Angles(math.rad(18), 0, math.rad(-14 * side)), lighten(col, 0.3))
		end
	end,
	crown = function(ctx)
		local rig = ctx.rig
		local y = crownY(rig, 0)
		local z = rig.c.Z
		add(ctx, "CrownBase", "Cylinder", V(0.2, 0.78, 0.78), CFrame.new(0, y + 0.06, z) * CFrame.Angles(0, 0, math.rad(90)), Palette.Gold, Enum.Material.Metal)
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2 + math.pi / 4
			add(ctx, "CrownPoint", "Block", V(0.17, 0.3, 0.17), CFrame.new(math.cos(a) * 0.29, y + 0.26, z + math.sin(a) * 0.29) * CFrame.Angles(0, -a, math.rad(45)), Palette.Gold, Enum.Material.Metal)
		end
		add(ctx, "CrownGem", "Ball", V(0.18, 0.18, 0.18), CFrame.new(0, y + 0.08, z - 0.4), Color3.fromRGB(255, 70, 110), Enum.Material.Neon)
	end,
	antenna = function(ctx)
		local rig = ctx.rig
		for _, side in { -1, 1 } do
			local y = crownY(rig, 0.3)
			add(ctx, "Antenna", "Block", V(0.08, 0.62, 0.08), CFrame.new(0.32 * side, y + 0.22, rig.c.Z) * CFrame.Angles(0, 0, math.rad(-15 * side)), ctx.accent)
			add(ctx, "AntennaBall", "Ball", V(0.26, 0.26, 0.26), CFrame.new(0.4 * side, y + 0.55, rig.c.Z), ctx.color, Enum.Material.Neon)
		end
	end,
	flames = function(ctx)
		local rig = ctx.rig
		local y = crownY(rig, 0)
		local core = add(ctx, "Flame", "Ellipsoid", V(0.42, 0.7, 0.42), CFrame.new(0, y + 0.22, rig.c.Z + 0.25), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		add(ctx, "Flame", "Ellipsoid", V(0.24, 0.46, 0.24), CFrame.new(0, y + 0.3, rig.c.Z + 0.22), Color3.fromRGB(255, 225, 90), Enum.Material.Neon)
		if not ctx.lite then
			local e = emitter(core, FIRE, Color3.fromRGB(255, 140, 40), 10, 0.8 * ctx.s, 1.5, 1)
			e.Acceleration = V(0, 4, 0)
			e.SpreadAngle = Vector2.new(15, 15)
		end
	end,
	halo = function(ctx)
		local rig = ctx.rig
		local y = crownY(rig, 0) + 0.5
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			add(ctx, "Halo", "Block", V(0.4, 0.09, 0.11), CFrame.new(math.cos(a) * 0.46, y, rig.c.Z + math.sin(a) * 0.46) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
		end
	end,
	spikes = function(ctx)
		local rig = ctx.rig
		local spots: { Vector3 } = { V(0, rig.c.Y + rig.r.Y * 0.72, rig.c.Z + 0.62), V(0, 0.42, 0.55), V(0, 0.28, 1.05) }
		if rig.upright then
			spots = { V(0, 0.85, 0.6), V(0, 0.3, 0.88), V(0, -0.25, 0.86) }
		end
		for i, p in spots do
			local sz = 0.36 - i * 0.04
			add(ctx, "Spike", "Block", V(sz * 0.7, sz, sz), CFrame.new(p) * CFrame.Angles(math.rad(45), 0, 0), if lum(ctx.accent) > 0.12 then ctx.accent else lighten(ctx.color, 0.4))
		end
	end,
	scarf = function(ctx)
		local rig = ctx.rig
		local red = Color3.fromRGB(230, 50, 60)
		if rig.block then
			add(ctx, "Scarf", "Block", V(2.0, 0.3, 1.85), CFrame.new(0, -0.38, -0.45), red, Enum.Material.Fabric)
			add(ctx, "ScarfEnd", "Block", V(0.36, 0.6, 0.12), CFrame.new(0.5, -0.78, -1.36) * CFrame.Angles(0, 0, math.rad(8)), red, Enum.Material.Fabric)
		elseif rig.upright then
			add(ctx, "Scarf", "Ellipsoid", V(2.04, 0.42, 1.94), CFrame.new(0, -0.08, 0), red, Enum.Material.Fabric)
			add(ctx, "ScarfEnd", "Block", V(0.36, 0.62, 0.12), CFrame.new(0.45, -0.46, -0.9) * CFrame.Angles(0, 0, math.rad(10)), red, Enum.Material.Fabric)
		else
			add(ctx, "Scarf", "Ellipsoid", V(1.78, 0.42, 1.62), CFrame.new(0, -0.24, -0.28), red, Enum.Material.Fabric)
			add(ctx, "ScarfEnd", "Block", V(0.34, 0.62, 0.14), CFrame.new(0.5, -0.66, -0.98) * CFrame.Angles(0, 0, math.rad(10)), red, Enum.Material.Fabric)
		end
	end,
	sprinkles = function(ctx)
		local rig = ctx.rig
		local cols = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 230, 60), Color3.fromRGB(120, 230, 120) }
		for i = 1, 7 do
			local a = i * 2.4
			local rr = 0.22 + (i % 3) * 0.17
			local x, zz = math.cos(a) * rr, math.sin(a) * rr
			local y = if rig.block then rig.c.Y + rig.r.Y + 0.03 else rig.c.Y + rig.r.Y * math.sqrt(math.max(0.05, 1 - (x / rig.r.X) ^ 2 - (zz / rig.r.Z) ^ 2)) + 0.02
			add(ctx, "Sprinkle", "Block", V(0.09, 0.09, 0.26), CFrame.new(x, y, rig.c.Z + zz) * CFrame.Angles(0, a, 0.3), cols[(i % #cols) + 1], Enum.Material.Neon)
		end
	end,
}

---------------------------------------------------------------------------
-- Species
---------------------------------------------------------------------------
local FAMILY: { [string]: string } = {
	piggy = "pig",
	chick = "bird",
	owl = "owl",
	arcticowl = "owl",
	nebulaowl = "owl",
	unicorn = "unicorn",
	crystalunicorn = "unicorn",
	candydragon = "dragon",
	icedragon = "dragon",
	firedragon = "dragon",
	galaxydragon = "dragon",
	celestialdragon = "dragon",
	shadowdragon = "dragon",
	jellyphoenix = "phoenix",
	frostphoenix = "phoenix",
	penguin = "penguin",
	icewolf = "wolf",
	hellhound = "wolf",
	yeti = "yeti",
	magmagolem = "golem",
	alienpup = "alien",
}
local EYES: { [string]: string } = { dragon = "fierce", wolf = "fierce", yeti = "fierce", golem = "rect", alien = "alien" }
local EYE_OUT: { [string]: number } = { yeti = 0.06, penguin = 0.05, owl = 0.05 }
local EAR_OF: { [string]: string } = { wolf = "fox", pig = "pig", alien = "dog", unicorn = "cat" }
-- pets that keep their feet on the ground even though they have wings
local WALKERS: { [string]: boolean } = { chick = true }

function PetModel.family(petId: string): string
	local def = Formulas.PetById[petId]
	if not def then
		return "dog"
	end
	local f = FAMILY[petId]
	if f then
		return f
	end
	return if def.ears == "none" then "dog" else def.ears
end

---------------------------------------------------------------------------
-- Rainbow pets: call every frame (client) to cycle their tinted parts. Each part sits at
-- its own hue offset, so the pet reads as a rainbow rather than one flat colour.
---------------------------------------------------------------------------
local tintCache: { [Model]: { BasePart } } = {}

local function tintParts(model: Model): { BasePart }
	local list = tintCache[model]
	if list then
		return list
	end
	local found: { BasePart } = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("Tint") then
			table.insert(found, d)
		end
	end
	tintCache[model] = found
	model.Destroying:Once(function()
		tintCache[model] = nil
	end)
	return found
end

function PetModel.updateRainbow(model: Model, now: number)
	if not model:GetAttribute("Rainbow") then
		return
	end
	for i, p in tintParts(model) do
		p.Color = Palette.rainbow(now, i * 0.09)
	end
end

-- Builds a pet at the origin. tier: 0 Normal, 1 Golden, 2 Rainbow.
function PetModel.build(petId: string, tier: number?, opts: BuildOpts?): Model
	local t = tier or 0
	local lite = opts ~= nil and opts.lite == true
	local def = Formulas.PetById[petId] or Formulas.PetById[Config.StartingPet]
	local family = PetModel.family(def.id)
	local model = Instance.new("Model")
	model.Name = def.id
	model:SetAttribute("PetId", def.id)
	model:SetAttribute("Tier", t)

	local s = def.size * (if t == 2 then 1.15 elseif t == 1 then 1.08 else 1)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local color = Palette.rgb(def.color)
	local accent = Palette.rgb(def.accent)
	local mat = Palette.material(def.material)
	if t == 1 then
		color = Palette.Gold
		accent = Color3.fromRGB(255, 240, 170)
		mat = Enum.Material.SmoothPlastic
	elseif t == 2 then
		mat = Enum.Material.SmoothPlastic
	end
	local extras: { [string]: boolean } = {}
	for _, e in def.extras do
		extras[e] = true
	end
	local ctx: Ctx = {
		model = model,
		root = root,
		s = s,
		tint = {},
		lite = lite,
		rig = nil :: any,
		color = color,
		accent = accent,
		light = if lum(accent) > lum(color) + 0.08 then accent else lighten(color, 0.55),
		mat = mat,
		extras = extras,
	}
	local birdFeet = family == "bird" or family == "phoenix" or family == "owl" or family == "penguin"
	ctx.rig = buildBody(ctx, def.body, birdFeet)
	local rig = ctx.rig

	-- face: patches first, then the eyes on top
	local muzzle = MUZZLE[family] or MUZZLE.dog
	muzzle(ctx)
	if extras.beak and not birdFeet then
		beak(ctx, 0)
	end
	local style = EYES[family] or "dot"
	if def.rarity == "Secret" then
		style = "glow"
	end
	local order = Config.RarityByName[def.rarity].order
	eyes(ctx, style, if order >= 5 and style == "dot" then 1.12 else 1, EYE_OUT[family] or 0)

	ears(ctx, EAR_OF[family] or def.ears)
	if extras.tail or family == "bunny" or family == "unicorn" or family == "phoenix" then
		tail(ctx, family)
	end
	if extras.wings then
		wings(ctx, family)
		if not WALKERS[def.id] then
			model:SetAttribute("Flyer", true)
		end
	end
	for _, extra in def.extras do
		local fn = EXTRA[extra]
		if fn then
			fn(ctx)
		end
	end
	model:SetAttribute("FootY", rig.footY * s)
	model:SetAttribute("Size", s)

	-- Tiers
	if t == 1 then
		for _, p in ctx.tint do
			p.Reflectance = 0.1
		end
	elseif t == 2 then
		model:SetAttribute("Rainbow", true)
		for _, p in ctx.tint do
			p.Reflectance = 0.12
		end
		PetModel.updateRainbow(model, 0)
	end

	if lite then
		return model
	end

	---------------------------------------------------------------------------
	-- World-only effects: tier sparkles, rarity aura, trail, lights
	---------------------------------------------------------------------------
	local rcol = if def.rarity == "Secret" then SECRET else Palette.rarity(def.rarity)
	local fx = not (opts ~= nil and opts.fx == false)
	local rateK = if fx then 1 else 0.5
	if t >= 1 then
		emitter(root, SPARKLES, if t == 1 then Palette.Gold else WHITE, 4 * rateK, 0.7 * s, 1.5)
	end
	if order >= 5 then
		local disc = add(ctx, "Aura", "Cylinder", V(0.05, 2.9, 2.9), CFrame.new(0, rig.footY + 0.05, 0.2) * CFrame.Angles(0, 0, math.rad(90)), rcol, Enum.Material.Neon)
		disc.Transparency = 0.86
		local rim = add(ctx, "Aura", "Cylinder", V(0.04, 3.3, 3.3), CFrame.new(0, rig.footY + 0.03, 0.2) * CFrame.Angles(0, 0, math.rad(90)), lighten(rcol, 0.3), Enum.Material.Neon)
		rim.Transparency = 0.93
		emitter(root, SPARKLES, rcol, (if order >= 6 then 7 else 4) * rateK, 0.8 * s, 2)
	end
	if order >= 5 and fx then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.55 * s, 0.4 * s)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.55 * s, 0.4 * s)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(lighten(rcol, 0.3), rcol)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		trail.Lifetime = 0.45
		trail.MinLength = 0.2
		trail.LightEmission = 0.8
		trail.FaceCamera = true
		trail.Parent = root
	end
	-- orbiting orbs are plain geometry, so the rarity still reads with graphics at minimum
	if order >= 5 then
		local orbs = order - 3 -- Legendary 2, Mythic 3, Secret 4
		for i = 1, orbs do
			local orb = add(ctx, "Orb", "Ball", V(0.3, 0.3, 0.3), CFrame.new(1.9, 0.2, 0), lighten(rcol, 0.25), Enum.Material.Neon, false, { kind = "Orbit", hinge = CFrame.new(), side = 1 })
			local joint = orb:FindFirstChild("Joint") :: Weld
			joint.C1 = CFrame.new()
			joint:SetAttribute("Radius", 1.9 * s)
			joint:SetAttribute("Height", (0.1 + (i % 2) * 0.5) * s)
			joint:SetAttribute("Phase", i / orbs * math.pi * 2)
		end
	end
	if def.rarity == "Secret" then
		local smoke = emitter(root, SMOKE, Color3.fromRGB(60, 20, 110), 8 * rateK, 1.6 * s, 1.2, 0.2)
		smoke.Lifetime = NumberRange.new(0.8, 1.4)
		smoke.Acceleration = V(0, 2, 0)
	end
	if fx and (extras.glow or order >= 6) and opts ~= nil and opts.lights == true then
		local light = Instance.new("PointLight")
		light.Color = if order >= 6 then rcol else accent
		light.Range = 9 * s
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = root
	end
	return model
end

return PetModel
