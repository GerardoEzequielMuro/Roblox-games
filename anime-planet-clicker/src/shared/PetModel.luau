--!strict
-- Procedural low-poly companions. PetModel.build(petId, tier, opts) returns a Model whose
-- PrimaryPart ("Root") is anchored; every other part is welded to it, so PivotTo is cheap.
-- The pet faces -Z.
--
-- Six bodies (quad, orb, bot, slime, bird, dragon) plus features picked per pet in
-- Config.Pets[*].look (ears, tail, wings, horns, spots, spikes...). Parts that move hang
-- from a Weld named "Joint" with an "Anim" attribute; PetFollow drives Joint.C0.
-- The silhouette and the colours carry the look (readable at graphics quality 1);
-- opts.lite skips the particles, lights and the aura on top.
local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Palette = require(script.Parent.Palette)

local PetModel = {}

export type BuildOpts = { lite: boolean?, lights: boolean? }

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local BLACK = Color3.fromRGB(26, 24, 38)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLUSH = Color3.fromRGB(255, 140, 165)
local GOLD = Color3.fromRGB(255, 200, 50)
local GOLD2 = Color3.fromRGB(255, 240, 150)

local V = Vector3.new
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

type Joint = { kind: string, hinge: CFrame, side: number }
type Ctx = {
	model: Model,
	root: BasePart,
	s: number,
	tint: { BasePart },
	lite: boolean,
	color: Color3,
	accent: Color3,
	mat: Enum.Material,
	accentMat: Enum.Material,
	look: { [string]: any },
	head: Vector3, -- head centre
	headR: number, -- head radius
	back: number, -- z of the body's back end
	top: number, -- y of the top of the head
	foot: number, -- lowest point
	wingAt: Vector3,
}

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end
local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

-- shape: "Block" | "Ball" | "Cylinder" | "Ellipsoid" | "Wedge". cf / size in pet units.
local function add(ctx: Ctx, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, tintable: boolean?, joint: Joint?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = name
	p.Size = size * ctx.s
	p.CFrame = CFrame.new(cf.Position * ctx.s) * cf.Rotation
	p.Color = color
	p.Material = material or SMOOTH
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

---------------------------------------------------------------------------
-- Face: big eyes with a glint, blush, a small mouth. On the front (-Z) of the head.
---------------------------------------------------------------------------
local function face(ctx: Ctx, visor: boolean?)
	local h, r = ctx.head, ctx.headR
	if visor then
		-- robots: a dark visor band with two lit eyes
		add(ctx, "Visor", "Block", V(r * 1.5, r * 0.62, 0.2), CFrame.new(h.X, h.Y + r * 0.1, h.Z - r * 0.98), BLACK)
		for _, side in { -1, 1 } do
			add(ctx, "Eye", "Block", V(r * 0.34, r * 0.34, 0.12), CFrame.new(h.X + side * r * 0.38, h.Y + r * 0.1, h.Z - r * 1.06), ctx.accent, NEON)
		end
		return
	end
	for _, side in { -1, 1 } do
		local ex = h.X + side * r * 0.42
		local ey = h.Y + r * 0.12
		local ez = h.Z - r * 0.84
		add(ctx, "EyeWhite", "Ball", V(r * 0.52, r * 0.52, r * 0.52), CFrame.new(ex, ey, ez), WHITE)
		add(ctx, "Pupil", "Ball", V(r * 0.36, r * 0.36, r * 0.36), CFrame.new(ex, ey - r * 0.02, ez - r * 0.13), BLACK)
		add(ctx, "Glint", "Ball", V(r * 0.13, r * 0.13, r * 0.13), CFrame.new(ex + r * 0.07, ey + r * 0.09, ez - r * 0.29), WHITE, NEON)
		add(ctx, "Blush", "Ellipsoid", V(r * 0.34, r * 0.18, 0.1), CFrame.new(h.X + side * r * 0.7, h.Y - r * 0.28, h.Z - r * 0.7) * CFrame.Angles(0, -side * 0.5, 0), BLUSH)
	end
	add(ctx, "Mouth", "Ellipsoid", V(r * 0.3, r * 0.16, 0.14), CFrame.new(h.X, h.Y - r * 0.34, h.Z - r * 0.92), darken(BLUSH, 0.45))
	if ctx.look.whiskers then
		for _, side in { -1, 1 } do
			for i = 0, 1 do
				add(ctx, "Whisker", "Block", V(r * 0.7, 0.05, 0.05), CFrame.new(h.X + side * r * 0.85, h.Y - r * 0.2 - i * r * 0.16, h.Z - r * 0.7) * CFrame.Angles(0, side * 0.4, side * (0.1 + i * 0.25)), BLACK)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Features
---------------------------------------------------------------------------
local function ears(ctx: Ctx, kind: string)
	local h, r = ctx.head, ctx.headR
	for _, side in { -1, 1 } do
		local base = CFrame.new(h.X + side * r * 0.62, h.Y + r * 0.72, h.Z + r * 0.05)
		local joint: Joint = { kind = "Ear", hinge = base, side = side }
		if kind == "flop" then
			add(ctx, "Ear", "Ellipsoid", V(r * 0.5, r * 1.0, r * 0.3), CFrame.new(h.X + side * r * 0.95, h.Y + r * 0.2, h.Z) * CFrame.Angles(0, 0, side * 0.35), darken(ctx.color, 0.22), ctx.mat, true, joint)
		elseif kind == "long" then
			add(ctx, "Ear", "Ellipsoid", V(r * 0.42, r * 1.7, r * 0.3), base * CFrame.new(0, r * 0.7, 0) * CFrame.Angles(0, 0, -side * 0.18), ctx.color, ctx.mat, true, joint)
			add(ctx, "EarIn", "Ellipsoid", V(r * 0.22, r * 1.2, r * 0.12), base * CFrame.new(0, r * 0.7, -r * 0.12) * CFrame.Angles(0, 0, -side * 0.18), ctx.accent, SMOOTH, false, joint)
		elseif kind == "point" then
			add(ctx, "Ear", "Wedge", V(r * 0.22, r * 0.9, r * 0.62), base * CFrame.new(0, r * 0.28, 0) * CFrame.Angles(0, math.rad(90) * side, 0) * CFrame.Angles(0, 0, 0), ctx.color, ctx.mat, true, joint)
			add(ctx, "EarIn", "Wedge", V(r * 0.1, r * 0.55, r * 0.36), base * CFrame.new(0, r * 0.2, -r * 0.1) * CFrame.Angles(0, math.rad(90) * side, 0), ctx.accent, SMOOTH, false, joint)
		elseif kind == "round" then
			add(ctx, "Ear", "Ball", V(r * 0.62, r * 0.62, r * 0.62), base * CFrame.new(side * r * 0.12, r * 0.12, 0), ctx.color, ctx.mat, true, joint)
			add(ctx, "EarIn", "Ball", V(r * 0.36, r * 0.36, r * 0.36), base * CFrame.new(side * r * 0.12, r * 0.12, -r * 0.18), ctx.accent, SMOOTH, false, joint)
		elseif kind == "fin" then
			add(ctx, "Ear", "Wedge", V(r * 0.12, r * 0.7, r * 0.9), CFrame.new(h.X + side * r * 0.95, h.Y + r * 0.25, h.Z + r * 0.3) * CFrame.Angles(0, 0, -side * 0.7), ctx.accent, SMOOTH, false, { kind = "Ear", hinge = CFrame.new(h.X + side * r * 0.9, h.Y, h.Z + r * 0.2), side = side })
		elseif kind == "tuft" then
			add(ctx, "Ear", "Wedge", V(r * 0.2, r * 0.75, r * 0.4), base * CFrame.new(side * r * 0.1, r * 0.25, 0) * CFrame.Angles(0, math.rad(90) * side, side * 0.35), ctx.accent, SMOOTH, false, joint)
		end
	end
end

local function tail(ctx: Ctx, kind: string)
	local z = ctx.back
	local y = ctx.foot + 1.05
	local hinge = CFrame.new(0, y, z)
	local function j(): Joint
		return { kind = "Tail", hinge = hinge, side = 1 }
	end
	if kind == "stub" then
		add(ctx, "Tail", "Ball", V(0.42, 0.42, 0.42), CFrame.new(0, y + 0.1, z + 0.2), darken(ctx.color, 0.15), ctx.mat, true, j())
	elseif kind == "puff" then
		add(ctx, "Tail", "Ball", V(0.72, 0.72, 0.72), CFrame.new(0, y + 0.1, z + 0.3), lighten(ctx.color, 0.35), SMOOTH, false, j())
	elseif kind == "long" then
		add(ctx, "Tail", "Block", V(0.3, 0.3, 1.0), CFrame.new(0, y + 0.18, z + 0.5) * CFrame.Angles(0.45, 0, 0), ctx.color, ctx.mat, true, j())
		add(ctx, "TailB", "Block", V(0.24, 0.24, 0.8), CFrame.new(0, y + 0.62, z + 1.15) * CFrame.Angles(0.85, 0, 0), ctx.color, ctx.mat, true, j())
		add(ctx, "TailTip", "Ball", V(0.42, 0.42, 0.42), CFrame.new(0, y + 1.0, z + 1.45), ctx.accent, ctx.accentMat, false, j())
	elseif kind == "comet" then
		add(ctx, "Tail", "Ball", V(0.5, 0.5, 0.5), CFrame.new(0, y + 0.2, z + 0.35), ctx.accent, NEON, false, j())
		add(ctx, "TailB", "Ball", V(0.36, 0.36, 0.36), CFrame.new(0, y + 0.42, z + 0.8), lighten(ctx.accent, 0.3), NEON, false, j())
		add(ctx, "TailC", "Ball", V(0.24, 0.24, 0.24), CFrame.new(0, y + 0.66, z + 1.15), WHITE, NEON, false, j())
	elseif kind == "flame" then
		add(ctx, "Tail", "Block", V(0.26, 0.26, 0.6), CFrame.new(0, y + 0.15, z + 0.3) * CFrame.Angles(0.5, 0, 0), ctx.color, ctx.mat, true, j())
		add(ctx, "Flame", "Ellipsoid", V(0.62, 0.95, 0.62), CFrame.new(0, y + 0.7, z + 0.7), Color3.fromRGB(255, 130, 40), NEON, false, j())
		add(ctx, "FlameIn", "Ellipsoid", V(0.34, 0.58, 0.34), CFrame.new(0, y + 0.62, z + 0.66), Color3.fromRGB(255, 235, 120), NEON, false, j())
	elseif kind == "fin" then
		add(ctx, "Tail", "Wedge", V(0.14, 0.7, 0.9), CFrame.new(0, y + 0.2, z + 0.5) * CFrame.Angles(math.rad(180), 0, 0), ctx.accent, SMOOTH, false, j())
	end
end

local function wings(ctx: Ctx, kind: string)
	local w = ctx.wingAt
	for _, side in { -1, 1 } do
		local hinge = CFrame.new(w.X * side, w.Y, w.Z)
		local joint: Joint = { kind = "Wing", hinge = hinge, side = side }
		if kind == "moth" then
			add(ctx, "Wing", "Ellipsoid", V(1.15, 0.1, 0.95), hinge * CFrame.new(side * 0.62, 0.12, 0.05) * CFrame.Angles(0, 0, side * 0.2), ctx.accent, SMOOTH, false, joint)
			add(ctx, "WingB", "Ellipsoid", V(0.75, 0.1, 0.62), hinge * CFrame.new(side * 0.45, -0.15, 0.4) * CFrame.Angles(0, 0, side * -0.1), lighten(ctx.accent, 0.35), SMOOTH, false, joint)
			add(ctx, "WingDot", "Ball", V(0.3, 0.14, 0.3), hinge * CFrame.new(side * 0.72, 0.2, 0.05), WHITE, SMOOTH, false, joint)
		elseif kind == "feather" then
			for i = 0, 2 do
				add(ctx, "Feather", "Block", V(1.15 - i * 0.24, 0.12, 0.42), hinge * CFrame.new(side * (0.6 - i * 0.1), -i * 0.04, -0.2 + i * 0.36) * CFrame.Angles(0, side * -0.18 * i, side * 0.12), if i == 0 then ctx.accent else lighten(ctx.color, 0.2 * i), SMOOTH, i > 0, joint)
			end
		elseif kind == "bat" then
			add(ctx, "WingArm", "Block", V(1.3, 0.16, 0.16), hinge * CFrame.new(side * 0.65, 0.12, -0.2), darken(ctx.color, 0.25), SMOOTH, true, joint)
			add(ctx, "WingSkin", "Wedge", V(0.08, 0.95, 1.3), hinge * CFrame.new(side * 0.65, 0.1, 0.28) * CFrame.Angles(0, math.rad(90) * side, math.rad(90)), ctx.accent, SMOOTH, false, joint)
			add(ctx, "WingClaw", "Ball", V(0.24, 0.24, 0.24), hinge * CFrame.new(side * 1.3, 0.14, -0.2), WHITE, SMOOTH, false, joint)
		elseif kind == "ray" then
			add(ctx, "Wing", "Wedge", V(0.14, 1.0, 1.5), hinge * CFrame.new(side * 0.72, 0, 0) * CFrame.Angles(0, math.rad(90) * side, math.rad(90)), ctx.color, ctx.mat, true, joint)
			add(ctx, "WingEdge", "Block", V(1.4, 0.1, 0.16), hinge * CFrame.new(side * 0.7, 0.06, -0.48), ctx.accent, SMOOTH, false, joint)
		end
	end
end

local function horns(ctx: Ctx, kind: string)
	local h, r = ctx.head, ctx.headR
	local bone = Color3.fromRGB(245, 236, 215)
	if kind == "crown" then
		add(ctx, "Crown", "Cylinder", V(r * 0.3, r * 1.15, r * 1.15), CFrame.new(h.X, h.Y + r * 0.9, h.Z) * CFrame.Angles(0, 0, math.rad(90)), GOLD, SMOOTH)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			add(ctx, "CrownTip", "Block", V(r * 0.2, r * 0.42, r * 0.2), CFrame.new(h.X + math.cos(a) * r * 0.46, h.Y + r * 1.2, h.Z + math.sin(a) * r * 0.46), if i % 2 == 0 then GOLD2 else ctx.accent, if i % 2 == 0 then SMOOTH else NEON)
		end
		return
	end
	for _, side in { -1, 1 } do
		local base = CFrame.new(h.X + side * r * 0.45, h.Y + r * 0.85, h.Z)
		if kind == "spike" then
			add(ctx, "Horn", "Wedge", V(r * 0.22, r * 0.85, r * 0.4), base * CFrame.new(0, r * 0.3, 0) * CFrame.Angles(0, math.rad(90) * side, side * -0.25), bone)
		elseif kind == "ram" then
			add(ctx, "Horn", "Cylinder", V(r * 0.26, r * 0.8, r * 0.8), CFrame.new(h.X + side * r * 1.0, h.Y + r * 0.3, h.Z + r * 0.1) * CFrame.Angles(0, 0, 0), bone)
			add(ctx, "HornIn", "Cylinder", V(r * 0.3, r * 0.4, r * 0.4), CFrame.new(h.X + side * r * 1.02, h.Y + r * 0.3, h.Z + r * 0.1), darken(bone, 0.25))
		elseif kind == "antler" then
			add(ctx, "Antler", "Block", V(r * 0.14, r * 0.9, r * 0.14), base * CFrame.new(side * r * 0.12, r * 0.4, 0) * CFrame.Angles(0, 0, side * -0.35), bone)
			add(ctx, "AntlerB", "Block", V(r * 0.12, r * 0.5, r * 0.12), base * CFrame.new(side * r * 0.5, r * 0.7, 0) * CFrame.Angles(0, 0, side * -1.0), bone)
			add(ctx, "AntlerC", "Block", V(r * 0.12, r * 0.4, r * 0.12), base * CFrame.new(side * r * 0.1, r * 0.95, 0) * CFrame.Angles(0, 0, side * 0.4), bone)
			add(ctx, "AntlerTip", "Ball", V(r * 0.22, r * 0.22, r * 0.22), base * CFrame.new(side * r * 0.74, r * 0.88, 0), ctx.accent, NEON)
		end
	end
end

local function spots(ctx: Ctx, centre: Vector3, radius: Vector3)
	local dirs = { V(0.5, 0.75, 0.35), V(-0.6, 0.6, 0.5), V(0.1, 0.85, -0.3), V(-0.3, 0.5, 0.8), V(0.75, 0.3, -0.2) }
	for i, d in dirs do
		local u = d.Unit
		add(ctx, "Spot", "Ball", V(0.3, 0.3, 0.3) * (0.8 + (i % 3) * 0.25), CFrame.new(centre + V(u.X * radius.X, u.Y * radius.Y, u.Z * radius.Z) * 0.94), ctx.accent, ctx.accentMat)
	end
end

local function spikes(ctx: Ctx, fromZ: number, toZ: number, y: number)
	for i = 0, 3 do
		local z = fromZ + (toZ - fromZ) * i / 3
		add(ctx, "Spike", "Wedge", V(0.16, 0.42 - i * 0.04, 0.4), CFrame.new(0, y + 0.18 - i * 0.05, z) * CFrame.Angles(0, math.rad(180), 0), ctx.accent, ctx.accentMat)
	end
end

local function antenna(ctx: Ctx)
	local h, r = ctx.head, ctx.headR
	for _, side in { -1, 1 } do
		local joint: Joint = { kind = "Ear", hinge = CFrame.new(h.X + side * r * 0.3, h.Y + r * 0.85, h.Z), side = side }
		add(ctx, "Antenna", "Block", V(0.07, r * 0.8, 0.07), CFrame.new(h.X + side * r * 0.38, h.Y + r * 1.2, h.Z - r * 0.1) * CFrame.Angles(-0.25, 0, side * -0.25), BLACK, SMOOTH, false, joint)
		add(ctx, "AntennaTip", "Ball", V(0.26, 0.26, 0.26), CFrame.new(h.X + side * r * 0.5, h.Y + r * 1.6, h.Z - r * 0.22), ctx.accent, NEON, false, joint)
	end
end

---------------------------------------------------------------------------
-- Bodies. Each sets ctx.head / headR / back / top / foot / wingAt.
---------------------------------------------------------------------------
local function legs(ctx: Ctx, xs: number, zs: { number }, y: number, h: number)
	for _, z in zs do
		for _, side in { -1, 1 } do
			add(ctx, "Leg", "Cylinder", V(h, 0.46, 0.46), CFrame.new(side * xs, y, z) * CFrame.Angles(0, 0, math.rad(90)), darken(ctx.color, 0.12), ctx.mat, true)
			add(ctx, "Paw", "Ball", V(0.52, 0.34, 0.56), CFrame.new(side * xs, y - h / 2, z - 0.06), ctx.accent, SMOOTH)
		end
	end
end

local bodies: { [string]: (Ctx) -> () } = {}

-- Four-legged: a round head on a barrel body.
bodies.quad = function(ctx: Ctx)
	ctx.head, ctx.headR = V(0, 0.55, -0.62), 0.92
	ctx.back, ctx.top, ctx.foot = 0.98, 1.5, -1.12
	ctx.wingAt = V(0.5, 0.2, 0.25)
	add(ctx, "Body", "Ellipsoid", V(1.35, 1.2, 1.75), CFrame.new(0, -0.3, 0.2), ctx.color, ctx.mat, true)
	add(ctx, "Belly", "Ellipsoid", V(1.0, 0.75, 1.3), CFrame.new(0, -0.55, 0.14), lighten(ctx.color, 0.4), SMOOTH)
	add(ctx, "Head", "Ball", V(1.84, 1.84, 1.84), CFrame.new(ctx.head), ctx.color, ctx.mat, true)
	add(ctx, "Muzzle", "Ellipsoid", V(0.78, 0.55, 0.5), CFrame.new(0, 0.26, -1.42), lighten(ctx.color, 0.45), SMOOTH)
	add(ctx, "Nose", "Ball", V(0.26, 0.2, 0.2), CFrame.new(0, 0.42, -1.66), BLACK)
	legs(ctx, 0.46, { -0.32, 0.72 }, -0.85, 0.55)
end

-- A floating ball with the face on it.
bodies.orb = function(ctx: Ctx)
	ctx.head, ctx.headR = V(0, 0, 0), 1.08
	ctx.back, ctx.top, ctx.foot = 0.95, 1.1, -1.1
	ctx.wingAt = V(0.85, 0.2, 0.2)
	add(ctx, "Body", "Ball", V(2.16, 2.16, 2.16), CFrame.new(0, 0, 0), ctx.color, ctx.mat, true)
	add(ctx, "Belly", "Ellipsoid", V(1.5, 1.2, 0.6), CFrame.new(0, -0.35, -0.72), lighten(ctx.color, 0.4), SMOOTH)
	if ctx.look.legs then
		for _, side in { -1, 1 } do
			for i = 0, 1 do
				add(ctx, "Leg", "Block", V(0.14, 0.6, 0.14), CFrame.new(side * (0.55 + i * 0.3), -1.05, -0.2 + i * 0.5) * CFrame.Angles(0, 0, side * -0.5), BLACK)
			end
		end
		ctx.foot = -1.35
	end
end

-- Boxy robot: a cube head on a small chassis.
bodies.bot = function(ctx: Ctx)
	ctx.head, ctx.headR = V(0, 0.35, 0), 0.95
	ctx.back, ctx.top, ctx.foot = 0.9, 1.3, -1.15
	ctx.wingAt = V(0.95, 0.4, 0.2)
	add(ctx, "Head", "Block", V(1.9, 1.6, 1.8), CFrame.new(ctx.head), ctx.color, ctx.mat, true)
	add(ctx, "Trim", "Block", V(1.96, 0.22, 1.86), CFrame.new(0, -0.3, 0), ctx.accent, ctx.accentMat)
	add(ctx, "Chassis", "Block", V(1.3, 0.55, 1.3), CFrame.new(0, -0.72, 0), darken(ctx.color, 0.25), ctx.mat, true)
	if ctx.look.wheels then
		for _, side in { -1, 1 } do
			for _, z in { -0.5, 0.5 } do
				add(ctx, "Wheel", "Cylinder", V(0.26, 0.62, 0.62), CFrame.new(side * 0.78, -0.84, z), BLACK, SMOOTH, false, { kind = "Spin", hinge = CFrame.new(side * 0.78, -0.84, z), side = side })
				add(ctx, "Hub", "Cylinder", V(0.3, 0.26, 0.26), CFrame.new(side * 0.8, -0.84, z), ctx.accent)
			end
		end
	elseif ctx.look.legs then
		for _, side in { -1, 1 } do
			for _, z in { -0.5, 0.1, 0.6 } do
				add(ctx, "Leg", "Block", V(0.6, 0.14, 0.14), CFrame.new(side * 1.0, -0.9, z) * CFrame.Angles(0, 0, side * -0.45), darken(ctx.color, 0.3))
			end
		end
	else
		add(ctx, "Thruster", "Cylinder", V(0.3, 0.7, 0.7), CFrame.new(0, -1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), ctx.accent, NEON)
	end
	if ctx.look.claws then
		for _, side in { -1, 1 } do
			add(ctx, "Arm", "Block", V(0.7, 0.24, 0.24), CFrame.new(side * 1.2, -0.2, -0.6) * CFrame.Angles(0, side * 0.6, 0), darken(ctx.color, 0.2))
			add(ctx, "Claw", "Wedge", V(0.24, 0.5, 0.6), CFrame.new(side * 1.5, -0.2, -1.05) * CFrame.Angles(0, 0, 0), ctx.accent, ctx.accentMat, false, { kind = "Ear", hinge = CFrame.new(side * 1.4, -0.2, -0.8), side = side })
		end
	end
	if ctx.look.arms then
		for _, side in { -1, 1 } do
			add(ctx, "Shoulder", "Ball", V(0.6, 0.6, 0.6), CFrame.new(side * 1.2, 0.1, 0), ctx.accent, ctx.accentMat)
			add(ctx, "Fist", "Block", V(0.62, 0.7, 0.62), CFrame.new(side * 1.35, -0.6, -0.1), darken(ctx.color, 0.15), ctx.mat, true, { kind = "Ear", hinge = CFrame.new(side * 1.2, 0.1, 0), side = side })
		end
	end
	if ctx.look.rotor then
		add(ctx, "Mast", "Block", V(0.14, 0.4, 0.14), CFrame.new(0, 1.35, 0), BLACK)
		add(ctx, "Rotor", "Block", V(2.3, 0.08, 0.3), CFrame.new(0, 1.58, 0), lighten(ctx.color, 0.4), SMOOTH, false, { kind = "Rotor", hinge = CFrame.new(0, 1.58, 0), side = 1 })
	end
end

-- A squashed blob.
bodies.slime = function(ctx: Ctx)
	ctx.head, ctx.headR = V(0, 0.05, -0.1), 1.0
	ctx.back, ctx.top, ctx.foot = 1.0, 0.95, -0.92
	ctx.wingAt = V(0.9, 0.1, 0.2)
	add(ctx, "Body", "Ellipsoid", V(2.4, 1.85, 2.3), CFrame.new(0, 0, 0), ctx.color, ctx.mat, true)
	add(ctx, "Base", "Ellipsoid", V(2.6, 0.8, 2.5), CFrame.new(0, -0.6, 0), darken(ctx.color, 0.1), ctx.mat, true)
	add(ctx, "Shine", "Ellipsoid", V(0.6, 0.34, 0.2), CFrame.new(-0.5, 0.62, -0.62) * CFrame.Angles(0.5, 0.4, 0.3), WHITE, SMOOTH)
	if ctx.look.sprout then
		add(ctx, "Stem", "Block", V(0.1, 0.5, 0.1), CFrame.new(0, 1.1, 0), ctx.accent)
		for _, side in { -1, 1 } do
			add(ctx, "Leaf", "Ellipsoid", V(0.62, 0.12, 0.36), CFrame.new(side * 0.3, 1.36, 0) * CFrame.Angles(0, 0, side * 0.5), Color3.fromRGB(120, 230, 110), SMOOTH, false, { kind = "Ear", hinge = CFrame.new(0, 1.3, 0), side = side })
		end
	end
	if ctx.look.tentacles then
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2 + 0.5
			add(ctx, "Tentacle", "Block", V(0.2, 0.9, 0.2), CFrame.new(math.cos(a) * 0.7, -1.2, math.sin(a) * 0.7), ctx.accent, ctx.accentMat, false, { kind = "Tail", hinge = CFrame.new(math.cos(a) * 0.7, -0.8, math.sin(a) * 0.7), side = 1 })
		end
		ctx.foot = -1.65
	end
end

-- Upright bird: egg body, beak, stubby feet.
bodies.bird = function(ctx: Ctx)
	ctx.head, ctx.headR = V(0, 0.55, -0.1), 0.9
	ctx.back, ctx.top, ctx.foot = 0.75, 1.45, -1.3
	ctx.wingAt = V(0.78, -0.05, 0.1)
	add(ctx, "Body", "Ellipsoid", V(1.6, 1.7, 1.5), CFrame.new(0, -0.4, 0.05), ctx.color, ctx.mat, true)
	add(ctx, "Chest", "Ellipsoid", V(1.15, 1.2, 0.7), CFrame.new(0, -0.5, -0.45), lighten(ctx.color, 0.45), SMOOTH)
	add(ctx, "Head", "Ball", V(1.8, 1.8, 1.8), CFrame.new(ctx.head), ctx.color, ctx.mat, true)
	add(ctx, "Beak", "Wedge", V(0.4, 0.3, 0.55), CFrame.new(0, 0.32, -1.14) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(255, 170, 40))
	for _, side in { -1, 1 } do
		add(ctx, "Foot", "Block", V(0.36, 0.14, 0.5), CFrame.new(side * 0.36, -1.23, -0.2), Color3.fromRGB(255, 170, 40))
	end
end

-- Little dragon: long snout, chunky body, thick tail.
bodies.dragon = function(ctx: Ctx)
	ctx.head, ctx.headR = V(0, 0.62, -0.7), 0.85
	ctx.back, ctx.top, ctx.foot = 1.05, 1.5, -1.15
	ctx.wingAt = V(0.52, 0.35, 0.35)
	add(ctx, "Body", "Ellipsoid", V(1.45, 1.4, 1.9), CFrame.new(0, -0.3, 0.25), ctx.color, ctx.mat, true)
	add(ctx, "Belly", "Ellipsoid", V(1.0, 1.0, 1.3), CFrame.new(0, -0.5, 0.05), ctx.accent, ctx.accentMat)
	add(ctx, "Head", "Ball", V(1.7, 1.7, 1.7), CFrame.new(ctx.head), ctx.color, ctx.mat, true)
	add(ctx, "Snout", "Block", V(0.85, 0.55, 0.7), CFrame.new(0, 0.34, -1.55), ctx.color, ctx.mat, true)
	for _, side in { -1, 1 } do
		add(ctx, "Nostril", "Ball", V(0.12, 0.12, 0.12), CFrame.new(side * 0.22, 0.5, -1.9), BLACK)
		add(ctx, "Fang", "Wedge", V(0.1, 0.22, 0.14), CFrame.new(side * 0.3, 0.02, -1.78) * CFrame.Angles(math.rad(180), 0, 0), WHITE)
	end
	legs(ctx, 0.5, { -0.2, 0.75 }, -0.88, 0.55)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local RARITY_SIZE = { Common = 1, Uncommon = 1.04, Rare = 1.1, Epic = 1.18, Legendary = 1.3, Mythic = 1.42, Secret = 1.55 }

function PetModel.build(petId: string, tier: number, opts: BuildOpts?): Model
	local def = Formulas.PetById[petId] or Config.Pets[1]
	local look = def.look :: { [string]: any }
	local lite = opts ~= nil and opts.lite == true
	local model = Instance.new("Model")
	model.Name = "Pet_" .. def.id
	local s = (RARITY_SIZE[def.rarity] or 1) * (if tier > 0 then 1.08 else 1)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local color, accent = Palette.rgb(look.color), Palette.rgb(look.accent)
	if tier == 1 then
		color, accent = GOLD, GOLD2
	end
	local ctx: Ctx = {
		model = model, root = root, s = s, tint = {}, lite = lite, color = color, accent = accent,
		mat = if look.neon then NEON elseif tier == 1 then Enum.Material.Metal else SMOOTH,
		accentMat = if look.neonAccent or look.glow then NEON else SMOOTH,
		look = look, head = V(0, 0, 0), headR = 1, back = 1, top = 1, foot = -1, wingAt = V(0.6, 0, 0),
	}
	local body = bodies[look.body] or bodies.quad
	body(ctx)
	face(ctx, look.body == "bot")
	if look.ears then
		ears(ctx, look.ears)
	end
	if look.tail then
		tail(ctx, look.tail)
	end
	if look.wings then
		wings(ctx, look.wings)
	end
	if look.horns then
		horns(ctx, look.horns)
	end
	if look.spots then
		spots(ctx, V(0, -0.3, 0.2), V(0.68, 0.6, 0.88))
	end
	if look.spikes then
		spikes(ctx, -0.2, ctx.back, ctx.top - 0.75)
	end
	if look.antenna then
		antenna(ctx)
	end

	model:SetAttribute("FootY", ctx.foot * s)
	model:SetAttribute("Size", s)
	model:SetAttribute("Flyer", look.fly == true)
	model:SetAttribute("Tier", tier)
	if tier == 2 then
		model:SetAttribute("Rainbow", true)
		PetModel.updateRainbow(model, 0)
	end

	-- Rarity dressing that survives quality 1: orbiting gems for Legendary and up.
	local order = Config.RarityByName[def.rarity].order
	if order >= 5 or tier > 0 then
		local n = if order >= 6 then 3 else 2
		local gem = if tier == 1 then GOLD2 elseif tier == 2 then WHITE else Palette.rarity(def.rarity)
		for i = 1, n do
			local orb = add(ctx, "Orb", "Block", V(0.26, 0.26, 0.26), CFrame.new(1.6, 0, 0), gem, NEON, tier == 2, { kind = "Orbit", hinge = CFrame.new(), side = 1 })
			local joint = orb:FindFirstChild("Joint") :: Weld
			joint:SetAttribute("Radius", 1.75 * s)
			joint:SetAttribute("Height", (ctx.top - 0.3) * s)
			joint:SetAttribute("Phase", i / n * math.pi * 2)
		end
	end
	if not lite then
		if look.glow or order >= 5 or tier > 0 then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Sparkle"
			e.Texture = SPARKLES
			e.Color = ColorSequence.new(if tier == 1 then GOLD2 else lighten(accent, 0.3))
			e.Rate = if order >= 6 or tier > 0 then 7 else 3
			e.Lifetime = NumberRange.new(0.6, 1.1)
			e.Speed = NumberRange.new(0.6, 1.6)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45 * s), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			e.LightEmission = 0.8
			e.Parent = root
		end
		if opts == nil or opts.lights ~= false then
			if order >= 6 or tier == 2 then
				local light = Instance.new("PointLight")
				light.Color = accent
				light.Range = 9
				light.Brightness = 0.9
				light.Shadows = false
				light.Parent = root
			end
		end
	end
	return model
end

-- Prism pets cycle their body colours.
function PetModel.updateRainbow(model: Model, t: number)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local i = d:GetAttribute("Tint")
			if type(i) == "number" then
				d.Color = Palette.rainbow(t, i * 0.09)
			end
		end
	end
end

return PetModel
