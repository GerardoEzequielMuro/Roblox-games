--!strict
-- Procedural prop kit for the map: primitives (block, wedge, ball/ellipsoid, cylinder) and everything built from
-- them (trees, farmhouse, barn, windmill, tractor, animals...). Parts + native materials only, no uploaded assets.
-- Conventions: a prop's CFrame is at ground level, +Y up, and its front is its LookVector (local -Z).
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelSlots = require(script.Parent.ModelSlots)
local ModelFit = require(ReplicatedStorage.Shared.ModelFit)

local Props = {}

Props.rng = Random.new(1337)
local rng = Props.rng

Props.WOOD = Color3.fromRGB(156, 106, 64)
Props.WOOD_DARK = Color3.fromRGB(104, 68, 40)
Props.WOOD_LIGHT = Color3.fromRGB(198, 158, 108)
Props.STONE = Color3.fromRGB(168, 164, 158)
Props.WHITE = Color3.fromRGB(246, 242, 232)
Props.HAY = Color3.fromRGB(226, 190, 92)
local WOOD, WOOD_DARK, WOOD_LIGHT, STONE, WHITE, HAY = Props.WOOD, Props.WOOD_DARK, Props.WOOD_LIGHT, Props.STONE, Props.WHITE, Props.HAY
local LEAF = Color3.fromRGB(70, 160, 72)
local METAL_DARK = Color3.fromRGB(52, 54, 60)
local GLOW = Color3.fromRGB(255, 225, 150)

-- Decoration that players walk through / that never blocks clicks.
Props.DECOR = { CanCollide = false, CanQuery = false } :: { [string]: any }
-- Same, and too small to be worth a shadow.
Props.TINY = { CanCollide = false, CanQuery = false, CastShadow = false } :: { [string]: any }
local DECOR, TINY = Props.DECOR, Props.TINY

type Extra = { [string]: any }?

function Props.darken(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

function Props.lighten(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), f)
end

-- Parts built without an explicit material get one from their name instead of flat SmoothPlastic
-- (painted trims and frames read as wood, ropes and flags as cloth, reeds and vines as plants).
-- Animals, fruit, balloons and small details keep the smooth cartoon finish.
local NAME_MATERIALS: { { pattern: string, mat: Enum.Material } } = {
	{ pattern = "Frame$", mat = Enum.Material.Wood },
	{ pattern = "Trim$", mat = Enum.Material.Wood },
	{ pattern = "Beam$", mat = Enum.Material.Wood },
	{ pattern = "Brace$", mat = Enum.Material.Wood },
	{ pattern = "Post$", mat = Enum.Material.Wood },
	{ pattern = "Eave$", mat = Enum.Material.Wood },
	{ pattern = "Bar$", mat = Enum.Material.Wood },
	{ pattern = "Rope$", mat = Enum.Material.Fabric },
	{ pattern = "Cord$", mat = Enum.Material.Fabric },
	{ pattern = "String$", mat = Enum.Material.Fabric },
	{ pattern = "Pennant$", mat = Enum.Material.Fabric },
	{ pattern = "Band$", mat = Enum.Material.Fabric },
	{ pattern = "Flag$", mat = Enum.Material.Fabric },
	{ pattern = "Reed", mat = Enum.Material.Grass },
	{ pattern = "Vine", mat = Enum.Material.Grass },
	{ pattern = "LilyPad$", mat = Enum.Material.Grass },
}
function Props.materialFor(name: string): Enum.Material
	for _, rule in NAME_MATERIALS do
		if string.find(name, rule.pattern) then
			return rule.mat
		end
	end
	return Enum.Material.SmoothPlastic
end

local function finish(p: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: Extra, parent: Instance)
	p.Name = name
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Props.materialFor(name)
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
end

-- Block.
function Props.P(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: Extra): Part
	local p = Instance.new("Part")
	finish(p, name, size, cf, color, material, extra, parent)
	return p
end
local P = Props.P

-- Wedge: low edge at local -Z, vertical face at local +Z.
function Props.W(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: Extra): WedgePart
	local p = Instance.new("WedgePart")
	finish(p, name, size, cf, color, material, extra, parent)
	return p
end
local W = Props.W

-- Ball. A non-uniform size makes an ellipsoid (block part + built-in sphere mesh).
function Props.B(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: Extra): Part
	local p = Instance.new("Part")
	local uniform = math.abs(size.X - size.Y) < 0.01 and math.abs(size.Y - size.Z) < 0.01
	if uniform then
		p.Shape = Enum.PartType.Ball
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	finish(p, name, size, cf, color, material, extra, parent)
	return p
end
local B = Props.B

-- Upright cylinder (axis = cf's Y); cf is its center.
function Props.Cy(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?, extra: Extra): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	finish(p, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, extra, parent)
	return p
end
local Cy = Props.Cy

-- Lying cylinder (axis = cf's X); cf is its center.
function Props.CyX(parent: Instance, name: string, diameter: number, length: number, cf: CFrame, color: Color3, material: Enum.Material?, extra: Extra): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	finish(p, name, Vector3.new(length, diameter, diameter), cf, color, material, extra, parent)
	return p
end
local CyX = Props.CyX

-- Wedge placed by its up and "tall side" directions.
local function wedgeToward(parent: Instance, name: string, size: Vector3, pos: Vector3, up: Vector3, back: Vector3, color: Color3, material: Enum.Material?, extra: Extra): WedgePart
	return W(parent, name, size, CFrame.fromMatrix(pos, up:Cross(back), up, back), color, material, extra)
end

-- Two-slope roof. cf = center of the roof base, ridge along cf's X.
function Props.gableRoof(parent: Instance, cf: CFrame, length: number, span: number, height: number, color: Color3, material: Enum.Material?, extra: Extra)
	local size = Vector3.new(length, height, span / 2)
	wedgeToward(parent, "Roof", size, (cf * CFrame.new(0, height / 2, -span / 4)).Position, cf.UpVector, -cf.LookVector, color, material, extra)
	wedgeToward(parent, "Roof", size, (cf * CFrame.new(0, height / 2, span / 4)).Position, cf.UpVector, cf.LookVector, color, material, extra)
end

-- Triangular wall under a gable. cf = center of the triangle's base; the triangle lies in cf's XY plane.
function Props.gableEnd(parent: Instance, cf: CFrame, span: number, height: number, thickness: number, color: Color3, material: Enum.Material?, extra: Extra)
	local size = Vector3.new(thickness, height, span / 2)
	wedgeToward(parent, "Gable", size, (cf * CFrame.new(-span / 4, height / 2, 0)).Position, cf.UpVector, cf.RightVector, color, material, extra)
	wedgeToward(parent, "Gable", size, (cf * CFrame.new(span / 4, height / 2, 0)).Position, cf.UpVector, -cf.RightVector, color, material, extra)
end

-- Repaints terrain voxels in place. FillBlock/FillCylinder change the height of the ground (a full voxel
-- renders 2 studs above its top), so flat features (paths, the square, mud yards, the pond) only swap the
-- material of the two top voxel layers and keep their occupancy.
-- pick(x, z, layer) gets the cell center and layer (2 = surface, y -4..0; 1 = below, y -8..-4) and returns the
-- new material and/or occupancy, or nil to leave the cell alone.
function Props.paint(center: Vector3, halfExtent: number, pick: (x: number, z: number, layer: number) -> (Enum.Material?, number?))
	local terrain = Workspace.Terrain
	local region = Region3.new(
		Vector3.new(center.X - halfExtent, -8, center.Z - halfExtent),
		Vector3.new(center.X + halfExtent, 0, center.Z + halfExtent)
	):ExpandToGrid(4)
	local mats, occ = terrain:ReadVoxels(region, 4)
	local size = mats.Size
	local min = region.CFrame.Position - region.Size / 2
	for x = 1, size.X do
		local wx = min.X + (x - 0.5) * 4
		for z = 1, size.Z do
			local wz = min.Z + (z - 0.5) * 4
			for y = 1, size.Y do
				local m, o = pick(wx, wz, y)
				if m then
					mats[x][y][z] = m
				end
				if o then
					occ[x][y][z] = o
				end
			end
		end
	end
	terrain:WriteVoxels(region, 4, mats, occ)
end

-- Flat disc of another ground material (surface layer only).
function Props.paintDisc(center: Vector3, radius: number, material: Enum.Material)
	Props.paint(center, radius + 4, function(x, z, layer)
		if layer == 2 and (x - center.X) ^ 2 + (z - center.Z) ^ 2 <= radius * radius then
			return material, nil
		end
		return nil, nil
	end)
end

local function light(parent: Instance, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = Color3.fromRGB(255, 210, 140)
	l.Parent = parent
end

-- ===================================================================== nature

local function green(): Color3
	return Color3.fromHSV(0.27 + rng:NextNumber(-0.035, 0.05), 0.62 + rng:NextNumber(-0.05, 0.1), 0.56 + rng:NextNumber(0, 0.16))
end

local function treePrimitive(parent: Instance, pos: Vector3, s: number)
	local m = Instance.new("Model")
	m.Name = "Tree"
	local at = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local roll = rng:NextNumber()
	if roll < 0.24 then
		-- pine: stacked discs
		local trunkH = 5 * s
		Cy(m, "Trunk", 1.7 * s, trunkH, at * CFrame.new(0, trunkH / 2, 0), WOOD_DARK, Enum.Material.Wood)
		local c = Color3.fromHSV(0.36 + rng:NextNumber(-0.02, 0.02), 0.6, 0.42 + rng:NextNumber(0, 0.1))
		for k = 0, 3 do
			Cy(m, "Needles", (10.5 - k * 2.6) * s, 3 * s, at * CFrame.new(0, (4.2 + k * 2.7) * s, 0), if k % 2 == 0 then c else Props.lighten(c, 0.08), Enum.Material.Grass, DECOR)
		end
		B(m, "Tip", Vector3.one * 2.4 * s, at * CFrame.new(0, 14.6 * s, 0), Props.lighten(c, 0.12), Enum.Material.Grass, DECOR)
	else
		local trunkH = (if roll > 0.9 then 10 else 7.5) * s
		Cy(m, "Trunk", 2.1 * s, trunkH, at * CFrame.new(0, trunkH / 2, 0), WOOD_DARK, Enum.Material.Wood)
		local c = green()
		if roll > 0.78 and roll <= 0.9 then
			c = Color3.fromHSV(0.94 + rng:NextNumber(-0.02, 0.02), 0.34, 0.97) -- blossom tree
		elseif roll > 0.72 and roll <= 0.78 then
			c = Color3.fromHSV(0.1 + rng:NextNumber(-0.02, 0.03), 0.72, 0.95) -- golden tree
		end
		B(m, "Leaves", Vector3.one * 9.5 * s, at * CFrame.new(0, trunkH + 2.6 * s, 0), c, Enum.Material.Grass, DECOR)
		for k = 1, 3 do
			local a = k * 2.1 + rng:NextNumber(-0.3, 0.3)
			local d = 6 + rng:NextNumber(0, 1.6)
			B(m, "Leaves", Vector3.one * d * s, at * CFrame.new(math.cos(a) * 3.4 * s, trunkH + (1 + k * 1.3) * s, math.sin(a) * 3.4 * s), if k == 2 then Props.lighten(c, 0.1) else Props.darken(c, 0.06 * k), Enum.Material.Grass, DECOR)
		end
		P(m, "Branch", Vector3.new(0.7 * s, 3.4 * s, 0.7 * s), at * CFrame.new(1.2 * s, trunkH - 1.2 * s, 0) * CFrame.Angles(0, 0, math.rad(-38)), WOOD_DARK, Enum.Material.Wood, TINY)
	end
	m.Parent = parent
end

local function bushPrimitive(parent: Instance, pos: Vector3, s: number)
	local c = green()
	local at = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	B(parent, "Bush", Vector3.one * 3.4 * s, at * CFrame.new(0, 1.1 * s, 0), c, Enum.Material.Grass, DECOR)
	B(parent, "Bush", Vector3.one * 2.5 * s, at * CFrame.new(1.5 * s, 0.8 * s, 0.4 * s), Props.lighten(c, 0.08), Enum.Material.Grass, TINY)
	B(parent, "Bush", Vector3.one * 2.2 * s, at * CFrame.new(-1.3 * s, 0.7 * s, -0.6 * s), Props.darken(c, 0.08), Enum.Material.Grass, TINY)
end

local function rockPrimitive(parent: Instance, pos: Vector3, s: number)
	local g = rng:NextInteger(132, 168)
	local c = Color3.fromRGB(g, g - 3, g - 8)
	local rot = CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3))
	P(parent, "Rock", Vector3.new(1.9, 1.3, 1.6) * s, CFrame.new(pos + Vector3.new(0, 0.35 * s, 0)) * rot, c, Enum.Material.Slate, { CanQuery = false })
	if s > 1.3 then
		P(parent, "Rock", Vector3.new(1.1, 0.9, 1.2) * s, CFrame.new(pos + Vector3.new(1.1 * s, 0.2 * s, 0.5 * s)) * rot * CFrame.Angles(0.4, 1, 0), Props.darken(c, 0.1), Enum.Material.Slate, TINY)
	end
end

function Props.log(parent: Instance, pos: Vector3)
	local at = CFrame.new(pos + Vector3.new(0, 0.85, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	CyX(parent, "Log", 1.8, 6.5, at, WOOD_DARK, Enum.Material.Wood, { CanQuery = false })
	for _, x in { -3.28, 3.28 } do
		CyX(parent, "LogEnd", 1.5, 0.1, at * CFrame.new(x, 0, 0), WOOD_LIGHT, Enum.Material.Wood, TINY)
	end
	B(parent, "Mushroom", Vector3.new(0.9, 0.6, 0.9), at * CFrame.new(1.2, 0.95, 0.3), Color3.fromRGB(230, 70, 60), nil, TINY)
end

local BLOOMS = {
	Color3.fromRGB(255, 96, 128),
	Color3.fromRGB(255, 222, 74),
	Color3.fromRGB(186, 118, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 154, 64),
	Color3.fromRGB(110, 190, 255),
}

-- Round patch around center, or (with rowHalf + rowCF) a border row along rowCF's X axis.
function Props.flowerPatch(parent: Instance, center: Vector3, radius: number, count: number, rowHalf: number?, rowCF: CFrame?)
	for _ = 1, count do
		local p
		if rowHalf and rowCF then
			p = center + rowCF.RightVector * rng:NextNumber(-rowHalf, rowHalf) + rowCF.LookVector * rng:NextNumber(-radius, radius) * 0.4
		else
			local a = rng:NextNumber(0, math.pi * 2)
			local d = radius * math.sqrt(rng:NextNumber())
			p = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		end
		local h = rng:NextNumber(0.9, 1.5)
		P(parent, "Stem", Vector3.new(0.18, h, 0.18), CFrame.new(p + Vector3.new(0, h / 2, 0)), Color3.fromRGB(64, 156, 64), nil, TINY)
		B(parent, "Bloom", Vector3.one * rng:NextNumber(0.7, 1), CFrame.new(p + Vector3.new(0, h + 0.15, 0)), BLOOMS[rng:NextInteger(1, #BLOOMS)], nil, TINY)
	end
end

-- ===================================================================== small props

local function lampPrimitive(parent: Instance, pos: Vector3, lit: boolean)
	local m = Instance.new("Model")
	m.Name = "Lamp"
	local at = CFrame.new(pos)
	Cy(m, "Base", 1.5, 0.6, at * CFrame.new(0, 0.3, 0), STONE, Enum.Material.Slate, { CanQuery = false })
	P(m, "Pole", Vector3.new(0.5, 8.6, 0.5), at * CFrame.new(0, 4.9, 0), METAL_DARK, Enum.Material.Metal, { CanQuery = false })
	local bulb = P(m, "Bulb", Vector3.new(1.3, 1.5, 1.3), at * CFrame.new(0, 9.9, 0), GLOW, Enum.Material.Neon, TINY)
	P(m, "Cap", Vector3.new(1.9, 0.3, 1.9), at * CFrame.new(0, 10.8, 0), METAL_DARK, Enum.Material.Metal, TINY)
	if lit then
		light(bulb, 20, 1.1)
	end
	m.Parent = parent
end

function Props.crate(parent: Instance, cf: CFrame, size: number, produce: { Color3 }?)
	P(parent, "Crate", Vector3.new(size, size * 0.8, size), cf * CFrame.new(0, size * 0.4, 0), WOOD, Enum.Material.WoodPlanks, { CanQuery = false })
	for _, y in { 0.15, 0.65 } do
		P(parent, "CrateBand", Vector3.new(size + 0.16, size * 0.12, size + 0.16), cf * CFrame.new(0, size * y, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	end
	if produce then
		local n = 0
		for ix = -1, 1, 2 do
			for iz = -1, 1, 2 do
				n += 1
				B(parent, "Produce", Vector3.one * size * 0.42, cf * CFrame.new(ix * size * 0.22, size * 0.82, iz * size * 0.22), produce[(n - 1) % #produce + 1], nil, TINY)
			end
		end
	end
end

function Props.sack(parent: Instance, cf: CFrame)
	B(parent, "Sack", Vector3.new(2, 2.4, 1.8), cf * CFrame.new(0, 1.1, 0), Color3.fromRGB(198, 164, 112), Enum.Material.Fabric, TINY)
	B(parent, "SackTie", Vector3.one * 0.8, cf * CFrame.new(0, 2.4, 0), Color3.fromRGB(170, 136, 90), Enum.Material.Fabric, TINY)
end

function Props.barrel(parent: Instance, cf: CFrame)
	Cy(parent, "Barrel", 2.5, 3.1, cf * CFrame.new(0, 1.55, 0), WOOD, Enum.Material.WoodPlanks, { CanQuery = false })
	for _, y in { 0.6, 2.5 } do
		Cy(parent, "BarrelBand", 2.64, 0.26, cf * CFrame.new(0, y, 0), METAL_DARK, Enum.Material.Metal, TINY)
	end
	Cy(parent, "BarrelWater", 2.1, 0.1, cf * CFrame.new(0, 3.08, 0), Color3.fromRGB(90, 170, 230), Enum.Material.Glass, TINY)
end

function Props.hayBale(parent: Instance, cf: CFrame)
	P(parent, "HayBale", Vector3.new(3.4, 2.2, 2.3), cf * CFrame.new(0, 1.1, 0), HAY, Enum.Material.Grass, { CanQuery = false })
	for _, x in { -0.9, 0.9 } do
		P(parent, "HayBand", Vector3.new(0.2, 2.3, 2.4), cf * CFrame.new(x, 1.1, 0), Props.darken(HAY, 0.35), nil, TINY)
	end
end

function Props.roundBale(parent: Instance, cf: CFrame)
	CyX(parent, "RoundBale", 3.8, 3.2, cf * CFrame.new(0, 1.9, 0), HAY, Enum.Material.Grass, { CanQuery = false })
	for _, x in { -1.62, 1.62 } do
		CyX(parent, "BaleEnd", 3, 0.06, cf * CFrame.new(x, 1.9, 0), Props.darken(HAY, 0.18), Enum.Material.Grass, TINY)
	end
end

function Props.wateringCan(parent: Instance, cf: CFrame)
	local c = Color3.fromRGB(74, 156, 236)
	Cy(parent, "Can", 1.5, 1.6, cf * CFrame.new(0, 0.8, 0), c, Enum.Material.Metal, TINY)
	P(parent, "CanSpout", Vector3.new(0.32, 0.32, 1.6), cf * CFrame.new(0, 1.1, -1.2) * CFrame.Angles(math.rad(28), 0, 0), c, Enum.Material.Metal, TINY)
	P(parent, "CanHandle", Vector3.new(0.25, 1.3, 0.25), cf * CFrame.new(0, 1.2, 0.95), c, Enum.Material.Metal, TINY)
end

local function scarecrowPrimitive(parent: Instance, cf: CFrame)
	local straw = Color3.fromRGB(222, 190, 110)
	P(parent, "ScarecrowPole", Vector3.new(0.45, 6.2, 0.45), cf * CFrame.new(0, 3.1, 0), WOOD_DARK, Enum.Material.Wood, DECOR)
	P(parent, "ScarecrowArms", Vector3.new(5.4, 0.4, 0.4), cf * CFrame.new(0, 4.5, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	P(parent, "ScarecrowShirt", Vector3.new(2.3, 2.5, 1.1), cf * CFrame.new(0, 3.7, 0), Color3.fromRGB(206, 72, 62), Enum.Material.Fabric, DECOR)
	P(parent, "ScarecrowPants", Vector3.new(1.9, 1.5, 0.9), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(70, 96, 150), Enum.Material.Fabric, TINY)
	B(parent, "ScarecrowHead", Vector3.one * 1.8, cf * CFrame.new(0, 5.8, 0), straw, Enum.Material.Fabric, TINY)
	Cy(parent, "ScarecrowBrim", 3, 0.2, cf * CFrame.new(0, 6.55, 0), Color3.fromRGB(150, 110, 60), Enum.Material.Fabric, TINY)
	Cy(parent, "ScarecrowHat", 1.6, 1.1, cf * CFrame.new(0, 7.1, 0), Color3.fromRGB(150, 110, 60), Enum.Material.Fabric, TINY)
	for _, x in { -0.38, 0.38 } do
		B(parent, "ScarecrowEye", Vector3.one * 0.3, cf * CFrame.new(x, 5.95, -0.82), Color3.fromRGB(30, 26, 22), nil, TINY)
	end
	for _, x in { -2.8, 2.8 } do
		B(parent, "ScarecrowHand", Vector3.one * 0.8, cf * CFrame.new(x, 4.5, 0), straw, Enum.Material.Grass, TINY)
	end
end

local function benchPrimitive(parent: Instance, cf: CFrame)
	P(parent, "BenchSeat", Vector3.new(6.4, 0.4, 2), cf * CFrame.new(0, 1.7, 0), WOOD, Enum.Material.WoodPlanks, { CanQuery = false })
	P(parent, "BenchBack", Vector3.new(6.4, 1.7, 0.35), cf * CFrame.new(0, 2.85, 0.95) * CFrame.Angles(math.rad(8), 0, 0), WOOD, Enum.Material.WoodPlanks, TINY)
	for _, x in { -2.8, 2.8 } do
		P(parent, "BenchLeg", Vector3.new(0.4, 1.5, 1.9), cf * CFrame.new(x, 0.75, 0), METAL_DARK, Enum.Material.Metal, TINY)
	end
end

function Props.planter(parent: Instance, cf: CFrame)
	P(parent, "Planter", Vector3.new(4.4, 1.8, 4.4), cf * CFrame.new(0, 0.9, 0), WOOD_DARK, Enum.Material.WoodPlanks, { CanQuery = false })
	P(parent, "PlanterSoil", Vector3.new(3.8, 0.2, 3.8), cf * CFrame.new(0, 1.82, 0), Color3.fromRGB(84, 58, 40), Enum.Material.Ground, TINY)
	B(parent, "PlanterBush", Vector3.one * 3, cf * CFrame.new(0, 2.7, 0), green(), Enum.Material.Grass, TINY)
	for k = 1, 4 do
		local a = k * math.pi / 2 + 0.6
		B(parent, "Bloom", Vector3.one * 0.9, cf * CFrame.new(math.cos(a) * 1.35, 2.5, math.sin(a) * 1.35), BLOOMS[(k - 1) % #BLOOMS + 1], nil, TINY)
	end
end

-- String of pennants between two lamp posts.
function Props.bunting(parent: Instance, a: Vector3, b: Vector3, colors: { Color3 }, seed: number)
	local mid = a:Lerp(b, 0.5) - Vector3.new(0, 1.3, 0)
	local n = seed
	for _, seg in { { a, mid }, { mid, b } } do
		local p0, p1 = seg[1], seg[2]
		local len = (p1 - p0).Magnitude
		local frame = CFrame.lookAt(p0:Lerp(p1, 0.5), p1)
		P(parent, "BuntingString", Vector3.new(0.08, 0.08, len), frame, WHITE, nil, TINY)
		for k = 1, 3 do
			n += 1
			local at = CFrame.lookAt(p0:Lerp(p1, (k - 0.5) / 3), p1)
			P(parent, "Pennant", Vector3.new(0.1, 1.2, 1.2), at * CFrame.new(0, -0.75, 0) * CFrame.Angles(math.rad(45), 0, 0), colors[(n - 1) % #colors + 1], nil, TINY)
		end
	end
end

-- ===================================================================== buildings

local function window(parent: Instance, cf: CFrame, w: number, h: number)
	P(parent, "WindowFrame", Vector3.new(w + 0.7, h + 0.7, 0.3), cf, WHITE, nil, TINY)
	P(parent, "Window", Vector3.new(w, h, 0.4), cf, Color3.fromRGB(150, 208, 245), Enum.Material.Glass, TINY)
	P(parent, "WindowBar", Vector3.new(0.2, h, 0.46), cf, WHITE, nil, TINY)
	P(parent, "WindowBar", Vector3.new(w, 0.2, 0.46), cf, WHITE, nil, TINY)
end

local function smoke(parent: BasePart)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	e.Lifetime = NumberRange.new(5, 7)
	e.Rate = 2
	e.Speed = NumberRange.new(2, 3)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Acceleration = Vector3.new(0.6, 0.3, 0.3)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
end

-- Small cottage. Front (door) = LookVector.
local function farmhousePrimitive(parent: Instance, cf: CFrame, color: Color3)
	local m = Instance.new("Model")
	m.Name = "Farmhouse"
	local roofColor = Color3.fromRGB(92, 70, 66)
	P(m, "Foundation", Vector3.new(19.4, 1.2, 15.4), cf * CFrame.new(0, 0.6, 0), STONE, Enum.Material.Slate)
	P(m, "Walls", Vector3.new(18, 8.6, 14), cf * CFrame.new(0, 5.5, 0), color, Enum.Material.WoodPlanks)
	for _, x in { -9, 9 } do
		for _, z in { -7, 7 } do
			P(m, "Trim", Vector3.new(0.9, 8.6, 0.9), cf * CFrame.new(x, 5.5, z), WHITE, nil, TINY)
		end
	end
	Props.gableRoof(m, cf * CFrame.new(0, 9.8, 0), 21, 17.6, 6.4, roofColor, Enum.Material.Slate)
	P(m, "Eave", Vector3.new(21, 0.4, 17.6), cf * CFrame.new(0, 9.75, 0), WHITE, nil, TINY)
	-- front: door, porch and two windows
	P(m, "Door", Vector3.new(3.2, 5.6, 0.4), cf * CFrame.new(0, 4, -7.1), WOOD_DARK, Enum.Material.Wood, TINY)
	P(m, "DoorFrame", Vector3.new(4, 6.2, 0.3), cf * CFrame.new(0, 4.2, -7.05), WHITE, nil, TINY)
	B(m, "Knob", Vector3.one * 0.45, cf * CFrame.new(1, 4, -7.4), Color3.fromRGB(255, 205, 60), Enum.Material.Foil, TINY)
	P(m, "Porch", Vector3.new(9, 0.5, 4), cf * CFrame.new(0, 1.05, -9), WOOD_LIGHT, Enum.Material.WoodPlanks, { CanQuery = false })
	for _, x in { -4, 4 } do
		P(m, "PorchPost", Vector3.new(0.5, 6.2, 0.5), cf * CFrame.new(x, 4.3, -10.6), WHITE, nil, TINY)
	end
	local porchRoof = cf * CFrame.new(0, 7.4, -9)
	wedgeToward(m, "PorchRoof", Vector3.new(10, 1.5, 4.6), (porchRoof * CFrame.new(0, 0.75, 0)).Position, cf.UpVector, -cf.LookVector, roofColor, Enum.Material.Slate, TINY)
	for _, x in { -5.6, 5.6 } do
		window(m, cf * CFrame.new(x, 5.6, -7.05), 2.8, 2.8)
		P(m, "FlowerBox", Vector3.new(3.4, 0.7, 0.9), cf * CFrame.new(x, 3.6, -7.5), WOOD_DARK, Enum.Material.Wood, TINY)
		for k = -1, 1 do
			B(m, "Bloom", Vector3.one * 0.8, cf * CFrame.new(x + k * 1.05, 4.25, -7.5), BLOOMS[(k + 2)], nil, TINY)
		end
	end
	for _, s in { -1, 1 } do
		window(m, cf * CFrame.new(s * 9.05, 5.6, 0) * CFrame.Angles(0, math.rad(90), 0), 3, 2.8)
	end
	-- chimney with a lazy curl of smoke
	P(m, "Chimney", Vector3.new(2.2, 7, 2.2), cf * CFrame.new(5.4, 13.5, 2.4), Color3.fromRGB(170, 96, 80), Enum.Material.Brick, DECOR)
	local top = P(m, "ChimneyTop", Vector3.new(2.8, 0.6, 2.8), cf * CFrame.new(5.4, 17.2, 2.4), STONE, Enum.Material.Slate, TINY)
	smoke(top)
	m.Parent = parent
end

local function fountainPrimitive(parent: Instance, cf: CFrame)
	local marble = Color3.fromRGB(214, 212, 216)
	local waterColor = Color3.fromRGB(84, 176, 236)
	Cy(parent, "FountainStep", 28, 0.6, cf * CFrame.new(0, 0.3, 0), STONE, Enum.Material.Slate)
	Cy(parent, "FountainBase", 24, 2.2, cf * CFrame.new(0, 1.7, 0), marble, Enum.Material.Marble)
	local water = Cy(parent, "FountainWater", 21.4, 0.4, cf * CFrame.new(0, 2.7, 0), waterColor, Enum.Material.Glass, { Transparency = 0.2, CanCollide = false, CanQuery = false, CastShadow = false })
	Cy(parent, "FountainPillar", 3.2, 6, cf * CFrame.new(0, 5.8, 0), marble, Enum.Material.Marble)
	Cy(parent, "FountainBowl", 10, 1, cf * CFrame.new(0, 9.2, 0), marble, Enum.Material.Marble)
	Cy(parent, "FountainBowlWater", 8.6, 0.3, cf * CFrame.new(0, 9.75, 0), waterColor, Enum.Material.Glass, { Transparency = 0.2, CanCollide = false, CanQuery = false, CastShadow = false })
	Cy(parent, "FountainSpire", 1.6, 3, cf * CFrame.new(0, 11.2, 0), marble, Enum.Material.Marble, DECOR)
	B(parent, "FountainOrb", Vector3.one * 2.2, cf * CFrame.new(0, 13.4, 0), Color3.fromRGB(255, 208, 70), Enum.Material.Foil, TINY)

	local nozzle = P(parent, "Nozzle", Vector3.one, cf * CFrame.new(0, 14.4, 0), WHITE, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(190, 230, 255))
	spray.LightEmission = 0.4
	spray.Rate = 60
	spray.Lifetime = NumberRange.new(1.1, 1.7)
	spray.Speed = NumberRange.new(11, 15)
	spray.SpreadAngle = Vector2.new(24, 24)
	spray.Acceleration = Vector3.new(0, -26, 0)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.15) })
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = nozzle
	local ripple = Instance.new("ParticleEmitter")
	ripple.Name = "Ripple"
	ripple.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	ripple.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	ripple.LightEmission = 0.6
	ripple.Rate = 14
	ripple.Lifetime = NumberRange.new(0.8, 1.4)
	ripple.Speed = NumberRange.new(0.5, 1.5)
	ripple.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 0) })
	ripple.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis (up)
	ripple.Parent = water
end

-- The kingdom's mascot: a giant crowned carrot on a pedestal.
function Props.carrotStatue(parent: Instance, cf: CFrame)
	local orange = Color3.fromRGB(255, 138, 40)
	local gold = Color3.fromRGB(255, 205, 60)
	ModelSlots.spawn("carrot_statue", cf, Vector3.new(9, 16, 9), parent, function()
		P(parent, "StatueBase", Vector3.new(9, 1.6, 9), cf * CFrame.new(0, 0.8, 0), STONE, Enum.Material.Slate)
		Cy(parent, "StatuePlinth", 6.6, 1.4, cf * CFrame.new(0, 2.3, 0), Props.lighten(STONE, 0.25), Enum.Material.Marble)
		local tilt = cf * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(7))
		for k, d in { 1.8, 3, 4, 4.6 } do
			Cy(parent, "StatueCarrot", d, 2.5, tilt * CFrame.new(0, (k - 0.5) * 2.4, 0), if k % 2 == 0 then orange else Props.darken(orange, 0.06), nil, DECOR)
		end
		B(parent, "StatueCarrotTop", Vector3.one * 4.6, tilt * CFrame.new(0, 9.7, 0), orange, nil, DECOR)
		Cy(parent, "StatueCrown", 3.6, 0.9, tilt * CFrame.new(0, 11.7, 0), gold, Enum.Material.Foil, TINY)
		for k = 1, 5 do
			local a = k / 5 * math.pi * 2
			P(parent, "StatueCrownPoint", Vector3.new(0.7, 1.2, 0.7), tilt * CFrame.new(math.cos(a) * 1.45, 12.6, math.sin(a) * 1.45) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(45)), gold, Enum.Material.Foil, TINY)
		end
		for k = 1, 3 do
			local a = k / 3 * math.pi * 2
			B(parent, "StatueLeaf", Vector3.new(1.3, 4.6, 1.3), tilt * CFrame.new(math.cos(a) * 0.9, 13.6, math.sin(a) * 0.9) * CFrame.Angles(math.sin(a) * 0.35, 0, -math.cos(a) * 0.35), LEAF, Enum.Material.Grass, TINY)
		end
		return nil
	end, { collide = "solid", name = "CarrotStatue" })
	Props.flowerPatch(parent, cf.Position, 7.5, 14)
end

-- ===================================================================== animals

local function cow(parent: Instance, cf: CFrame)
	local black = Color3.fromRGB(40, 38, 40)
	P(parent, "CowBody", Vector3.new(3, 2.4, 5), cf * CFrame.new(0, 2.8, 0), WHITE, nil, { CanQuery = false })
	P(parent, "CowHead", Vector3.new(1.9, 1.9, 1.9), cf * CFrame.new(0, 3.6, -3.2), WHITE, nil, TINY)
	P(parent, "CowSnout", Vector3.new(1.5, 0.9, 0.7), cf * CFrame.new(0, 3.2, -4.3), Color3.fromRGB(244, 170, 170), nil, TINY)
	P(parent, "CowSpot", Vector3.new(3.06, 1.2, 1.6), cf * CFrame.new(0, 3.2, 0.8), black, nil, TINY)
	P(parent, "CowSpot", Vector3.new(1.4, 2.46, 1.3), cf * CFrame.new(0.82, 2.8, -1.2), black, nil, TINY)
	for _, x in { -0.75, 0.75 } do
		P(parent, "CowHorn", Vector3.new(0.3, 0.7, 0.3), cf * CFrame.new(x, 4.8, -3.2), Color3.fromRGB(230, 220, 190), nil, TINY)
		B(parent, "CowEye", Vector3.one * 0.32, cf * CFrame.new(x * 0.8, 3.95, -4.16), black, nil, TINY)
		for _, z in { -1.7, 1.7 } do
			P(parent, "CowLeg", Vector3.new(0.8, 1.7, 0.8), cf * CFrame.new(x * 1.2, 0.85, z), black, nil, TINY)
		end
	end
end

local function pig(parent: Instance, cf: CFrame)
	local pink = Color3.fromRGB(246, 170, 182)
	B(parent, "PigBody", Vector3.new(2.4, 2.2, 3.4), cf * CFrame.new(0, 1.7, 0), pink, nil, { CanQuery = false })
	B(parent, "PigHead", Vector3.one * 1.8, cf * CFrame.new(0, 2.2, -1.9), pink, nil, TINY)
	CyX(parent, "PigSnout", 0.9, 0.5, cf * CFrame.new(0, 2.1, -2.85) * CFrame.Angles(0, math.rad(90), 0), Props.darken(pink, 0.12), nil, TINY)
	for _, x in { -0.5, 0.5 } do
		P(parent, "PigEar", Vector3.new(0.5, 0.6, 0.2), cf * CFrame.new(x, 3.1, -1.8), Props.darken(pink, 0.1), nil, TINY)
		B(parent, "PigEye", Vector3.one * 0.26, cf * CFrame.new(x * 0.8, 2.5, -2.7), Color3.fromRGB(40, 38, 40), nil, TINY)
		for _, z in { -0.9, 0.9 } do
			P(parent, "PigLeg", Vector3.new(0.6, 0.9, 0.6), cf * CFrame.new(x * 1.3, 0.45, z), Props.darken(pink, 0.1), nil, TINY)
		end
	end
end

local function chicken(parent: Instance, cf: CFrame, color: Color3)
	B(parent, "ChickenBody", Vector3.new(1.3, 1.3, 1.7), cf * CFrame.new(0, 0.95, 0), color, nil, TINY)
	B(parent, "ChickenHead", Vector3.one * 0.9, cf * CFrame.new(0, 1.8, -0.7), color, nil, TINY)
	P(parent, "ChickenBeak", Vector3.new(0.3, 0.25, 0.4), cf * CFrame.new(0, 1.75, -1.25), Color3.fromRGB(255, 170, 40), nil, TINY)
	P(parent, "ChickenComb", Vector3.new(0.2, 0.4, 0.5), cf * CFrame.new(0, 2.35, -0.7), Color3.fromRGB(226, 60, 60), nil, TINY)
end

local function duck(parent: Instance, cf: CFrame)
	local yellow = Color3.fromRGB(255, 220, 70)
	B(parent, "DuckBody", Vector3.new(1.4, 1.1, 1.9), cf * CFrame.new(0, 0.35, 0), yellow, nil, TINY)
	B(parent, "DuckHead", Vector3.one * 0.95, cf * CFrame.new(0, 1.15, -0.65), yellow, nil, TINY)
	P(parent, "DuckBeak", Vector3.new(0.45, 0.2, 0.5), cf * CFrame.new(0, 1.05, -1.25), Color3.fromRGB(255, 140, 40), nil, TINY)
end

-- ===================================================================== landmarks

function Props.pond(m: Instance, cf: CFrame, radius: number)
	local c = cf.Position
	local waterR = radius - 9
	-- water sits a little below the ground, ringed by a sandy shore
	Props.paint(c, waterR + 8, function(x, z, layer)
		local d = math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2)
		if d <= waterR then
			return Enum.Material.Water, if layer == 2 then 0.3 else 1
		elseif d <= waterR + 5 then
			return Enum.Material.Sand, nil
		end
		return nil, nil
	end)

	-- dock toward the hub
	local dock = cf * CFrame.new(0, 0, -(waterR - 3))
	P(m, "Dock", Vector3.new(5.5, 0.45, 15), dock * CFrame.new(0, 0.9, 0), WOOD, Enum.Material.WoodPlanks, { CanQuery = false })
	for _, x in { -2.5, 2.5 } do
		for _, z in { -6.5, 0, 6.5 } do
			Cy(m, "DockPost", 0.7, 4.4, dock * CFrame.new(x, -0.4, z), WOOD_DARK, Enum.Material.Wood, TINY)
		end
	end
	-- rowboat
	local boat = cf * CFrame.new(6.5, -0.55, -4) * CFrame.Angles(0, math.rad(35), 0)
	P(m, "BoatHull", Vector3.new(3.4, 1.2, 7), boat * CFrame.new(0, 0.3, 0), Color3.fromRGB(178, 72, 60), Enum.Material.WoodPlanks, DECOR)
	P(m, "BoatInside", Vector3.new(2.6, 0.3, 6.2), boat * CFrame.new(0, 0.82, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	wedgeToward(m, "BoatBow", Vector3.new(3.4, 1.2, 2), (boat * CFrame.new(0, 0.3, -4.5)).Position, boat.UpVector, -boat.LookVector, Color3.fromRGB(178, 72, 60), Enum.Material.WoodPlanks, TINY)
	for _, z in { -1.4, 1.6 } do
		P(m, "BoatSeat", Vector3.new(3.3, 0.25, 0.9), boat * CFrame.new(0, 0.95, z), WOOD_LIGHT, Enum.Material.Wood, TINY)
	end
	-- lily pads, reeds, ducks, rocks
	for k = 1, 9 do
		local a = k * 0.7 + 1
		local d = waterR * (0.35 + 0.5 * ((k * 37) % 10) / 10)
		local at = cf * CFrame.new(math.cos(a) * d, -0.62, math.sin(a) * d)
		Cy(m, "LilyPad", rng:NextNumber(2, 3.2), 0.14, at, Color3.fromRGB(70, 170, 90), nil, TINY)
		if k % 3 == 0 then
			B(m, "LilyBloom", Vector3.one * 0.9, at * CFrame.new(0.3, 0.4, 0), Color3.fromRGB(255, 170, 210), nil, TINY)
		end
	end
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2 + 0.35
		local base = cf * CFrame.new(math.cos(a) * (waterR + 1.5), 0, math.sin(a) * (waterR + 1.5))
		for j = 1, 3 do
			local h = rng:NextNumber(3, 4.6)
			local at = base * CFrame.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			Cy(m, "Reed", 0.22, h, at * CFrame.new(0, h / 2 - 0.4, 0), Color3.fromRGB(96, 160, 80), nil, TINY)
			if j < 3 then
				Cy(m, "ReedHead", 0.5, 1.1, at * CFrame.new(0, h - 0.4, 0), Color3.fromRGB(120, 78, 46), nil, TINY)
			end
		end
	end
	for k = 1, 3 do
		local a = k * 2.2
		duck(m, cf * CFrame.new(math.cos(a) * waterR * 0.45, -0.7, math.sin(a) * waterR * 0.45) * CFrame.Angles(0, a, 0))
	end
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2 + 1.1
		Props.rock(m, (cf * CFrame.new(math.cos(a) * (radius - 5), 0, math.sin(a) * (radius - 5))).Position, rng:NextNumber(1.4, 2.4))
	end
end

function Props.windmill(m: Instance, cf: CFrame)
	local cream = Color3.fromRGB(244, 236, 214)
	Cy(m, "MillBase", 13, 10, cf * CFrame.new(0, 5, 0), cream, Enum.Material.Brick)
	Cy(m, "MillMid", 11, 8, cf * CFrame.new(0, 14, 0), cream, Enum.Material.Brick)
	Cy(m, "MillTop", 9.2, 6, cf * CFrame.new(0, 21, 0), cream, Enum.Material.Brick)
	Cy(m, "MillBand", 13.4, 0.8, cf * CFrame.new(0, 10, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	Cy(m, "MillBand", 11.4, 0.8, cf * CFrame.new(0, 18, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	B(m, "MillCap", Vector3.new(10.4, 7, 10.4), cf * CFrame.new(0, 24.4, 0), Color3.fromRGB(190, 70, 60), nil, DECOR)
	P(m, "MillDoor", Vector3.new(3, 5, 0.5), cf * CFrame.new(0, 2.5, -6.4), WOOD_DARK, Enum.Material.Wood, TINY)
	window(m, cf * CFrame.new(0, 13, -5.45), 2, 2.4)
	-- blades: a separate model the client spins around its hub (tag CK_Spin)
	local blades = Instance.new("Model")
	blades.Name = "Blades"
	local hubCF = cf * CFrame.new(0, 21, -6.6)
	local hubPart = P(blades, "Hub", Vector3.new(1.6, 1.6, 2), hubCF, WOOD_DARK, Enum.Material.Wood, DECOR)
	for k = 0, 3 do
		local arm = hubCF * CFrame.Angles(0, 0, k * math.pi / 2)
		P(blades, "Arm", Vector3.new(0.5, 14, 0.4), arm * CFrame.new(0, 7.4, -0.6), WOOD_DARK, Enum.Material.Wood, DECOR)
		P(blades, "Sail", Vector3.new(3, 10.5, 0.2), arm * CFrame.new(1.7, 8.8, -0.6), WHITE, Enum.Material.Fabric, DECOR)
	end
	blades.PrimaryPart = hubPart
	blades.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	blades:SetAttribute("BasePivot", hubCF)
	blades:SetAttribute("SpinSpeed", 0.55)
	blades:SetAttribute("SpinAxis", "Z")
	CollectionService:AddTag(blades, "CK_Spin")
	blades.Parent = m
	-- flour sacks and a little wheat
	Props.sack(m, cf * CFrame.new(-5, 0, -8))
	Props.sack(m, cf * CFrame.new(-7, 0, -7.2))
	Props.crate(m, cf * CFrame.new(5.5, 0, -8) * CFrame.Angles(0, 0.4, 0), 2.6, nil)
	for k = 1, 5 do
		Props.bush(m, (cf * CFrame.new(math.cos(k * 1.2 + 2) * 10.5, 0, math.sin(k * 1.2 + 2) * 10.5 + 2)).Position, 1.1)
	end
end

local function cart(parent: Instance, cf: CFrame, load: Color3?)
	P(parent, "CartBed", Vector3.new(4.4, 0.5, 7), cf * CFrame.new(0, 2.2, 0), WOOD, Enum.Material.WoodPlanks, { CanQuery = false })
	for _, x in { -2.1, 2.1 } do
		P(parent, "CartSide", Vector3.new(0.3, 1.5, 7), cf * CFrame.new(x, 3.1, 0), WOOD, Enum.Material.WoodPlanks, TINY)
		CyX(parent, "CartWheel", 3.4, 0.5, cf * CFrame.new(x * 1.25, 1.7, 0.4), WOOD_DARK, Enum.Material.Wood, TINY)
		P(parent, "CartHandle", Vector3.new(0.3, 0.3, 4.5), cf * CFrame.new(x * 0.8, 1.7, -5.4) * CFrame.Angles(math.rad(14), 0, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	end
	for _, z in { -3.4, 3.4 } do
		P(parent, "CartEnd", Vector3.new(4.4, 1.5, 0.3), cf * CFrame.new(0, 3.1, z), WOOD, Enum.Material.WoodPlanks, TINY)
	end
	if load then
		B(parent, "CartLoad", Vector3.new(4.2, 3, 6.6), cf * CFrame.new(0, 3.6, 0), load, Enum.Material.Grass, TINY)
	end
end

function Props.hayField(m: Instance, cf: CFrame)
	-- golden wheat in rows
	for k = -4, 4 do
		local z = k * 3.4 + 4
		local halfLen = math.sqrt(math.max(16, 22 * 22 - (k * 3.4) ^ 2))
		P(m, "Wheat", Vector3.new(halfLen * 2, 2.6, 1.5), cf * CFrame.new(0, 1.3, z), HAY, Enum.Material.Grass, DECOR)
		P(m, "WheatTop", Vector3.new(halfLen * 2, 0.7, 1.8), cf * CFrame.new(0, 2.8, z), Props.lighten(HAY, 0.18), Enum.Material.Grass, TINY)
	end
	Props.roundBale(m, cf * CFrame.new(-10, 0, -16) * CFrame.Angles(0, 0.5, 0))
	Props.roundBale(m, cf * CFrame.new(-4, 0, -18.5) * CFrame.Angles(0, -0.3, 0))
	Props.hayBale(m, cf * CFrame.new(9, 0, -16))
	Props.hayBale(m, cf * CFrame.new(12.6, 0, -16.4) * CFrame.Angles(0, 0.2, 0))
	Props.hayBale(m, cf * CFrame.new(10.6, 2.2, -16.2) * CFrame.Angles(0, 0.1, 0))
	cart(m, cf * CFrame.new(2.5, 0, -19.5) * CFrame.Angles(0, math.rad(80), 0), HAY)
	Props.scarecrow(m, cf * CFrame.new(0, 0, 4))
end

function Props.barn(m: Instance, cf: CFrame)
	local red = Color3.fromRGB(184, 56, 50)
	local roofColor = Color3.fromRGB(76, 70, 74)
	local w, h, d = 26, 13, 22
	-- trodden farmyard (no tall grass hiding the animals)
	Props.paintDisc(cf.Position + cf.LookVector * 6, 27, Enum.Material.Mud)
	ModelSlots.spawn("barn", cf, Vector3.new(26, 21, 23), m, function()
		P(m, "BarnBody", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), red, Enum.Material.WoodPlanks)
		for _, x in { -w / 2, w / 2 } do
			for _, z in { -d / 2, d / 2 } do
				P(m, "BarnTrim", Vector3.new(1.1, h, 1.1), cf * CFrame.new(x, h / 2, z), WHITE, nil, TINY)
			end
		end
		-- ridge runs front to back, so the red gable faces the hub
		local roofCF = cf * CFrame.new(0, h, 0) * CFrame.Angles(0, math.rad(90), 0)
		Props.gableRoof(m, roofCF, d + 3, w + 3, 9, roofColor, Enum.Material.Slate)
		Props.gableEnd(m, cf * CFrame.new(0, h, -d / 2 - 0.2), w, 8.2, 0.5, red, Enum.Material.WoodPlanks, DECOR)
		P(m, "BarnBeam", Vector3.new(w + 0.6, 0.8, 0.6), cf * CFrame.new(0, h, -d / 2 - 0.3), WHITE, nil, TINY)
		-- big double door with white X braces
		local door = cf * CFrame.new(0, 5, -d / 2 - 0.15)
		P(m, "BarnDoor", Vector3.new(9, 10, 0.4), door, Props.darken(red, 0.25), Enum.Material.WoodPlanks, TINY)
		P(m, "BarnDoorFrame", Vector3.new(10, 0.8, 0.5), door * CFrame.new(0, 5.2, -0.05), WHITE, nil, TINY)
		for _, x in { -4.9, 0, 4.9 } do
			P(m, "BarnDoorFrame", Vector3.new(0.6, 10, 0.5), door * CFrame.new(x, 0, -0.05), WHITE, nil, TINY)
		end
		for _, x in { -2.45, 2.45 } do
			for _, r in { 24, -24 } do
				P(m, "BarnBrace", Vector3.new(0.5, 10.6, 0.3), door * CFrame.new(x, 0, -0.15) * CFrame.Angles(0, 0, math.rad(r)), WHITE, nil, TINY)
			end
		end
		window(m, cf * CFrame.new(0, h + 3.6, -d / 2 - 0.5), 3, 3)
		return nil
	end, { collide = "solid", name = "BarnBuilding" })
	-- silo
	local silo = cf * CFrame.new(w / 2 + 7, 0, 3)
	Cy(m, "Silo", 9, 22, silo * CFrame.new(0, 11, 0), Color3.fromRGB(196, 200, 206), Enum.Material.Metal)
	for _, y in { 5, 11, 17 } do
		Cy(m, "SiloBand", 9.3, 0.5, silo * CFrame.new(0, y, 0), Color3.fromRGB(150, 154, 162), Enum.Material.Metal, TINY)
	end
	B(m, "SiloDome", Vector3.one * 9, silo * CFrame.new(0, 22, 0), Color3.fromRGB(214, 78, 66), Enum.Material.Metal, DECOR)
	-- animal pen on the other side
	local pen = cf * CFrame.new(-w / 2 - 9, 0, -2)
	local pw, pd = 14, 16
	for _, x in { -pw / 2, pw / 2 } do
		for k = 0, 4 do
			P(m, "PenPost", Vector3.new(0.6, 3.2, 0.6), pen * CFrame.new(x, 1.6, -pd / 2 + k * pd / 4), WOOD_DARK, Enum.Material.Wood, { CanQuery = false })
		end
		for _, y in { 1.4, 2.6 } do
			P(m, "PenRail", Vector3.new(0.3, 0.4, pd), pen * CFrame.new(x, y, 0), WOOD, Enum.Material.Wood, { CanQuery = false })
		end
	end
	for _, z in { -pd / 2, pd / 2 } do
		for _, y in { 1.4, 2.6 } do
			P(m, "PenRail", Vector3.new(pw, 0.4, 0.3), pen * CFrame.new(0, y, z), WOOD, Enum.Material.Wood, { CanQuery = false })
		end
	end
	P(m, "PenMud", Vector3.new(pw - 1, 0.16, pd - 1), pen * CFrame.new(0, 0.08, 0), Color3.fromRGB(132, 98, 68), Enum.Material.Ground, TINY)
	P(m, "Trough", Vector3.new(4.4, 1.1, 1.5), pen * CFrame.new(0, 0.55, -pd / 2 + 1.6), WOOD_DARK, Enum.Material.Wood, TINY)
	cow(m, pen * CFrame.new(-2.6, 0, 1) * CFrame.Angles(0, math.rad(20), 0))
	cow(m, pen * CFrame.new(3, 0, 4) * CFrame.Angles(0, math.rad(-140), 0))
	pig(m, pen * CFrame.new(3.2, 0, -3.6) * CFrame.Angles(0, math.rad(70), 0))
	-- chickens out front, hay by the door
	chicken(m, cf * CFrame.new(-7, 0, -17) * CFrame.Angles(0, 0.6, 0), WHITE)
	chicken(m, cf * CFrame.new(-4.4, 0, -19.4) * CFrame.Angles(0, -1.2, 0), Color3.fromRGB(206, 140, 80))
	chicken(m, cf * CFrame.new(-8.6, 0, -20.4) * CFrame.Angles(0, 2.4, 0), WHITE)
	Props.hayBale(m, cf * CFrame.new(8.4, 0, -13.4))
	Props.hayBale(m, cf * CFrame.new(8.8, 2.2, -13.2) * CFrame.Angles(0, 0.2, 0))
	Props.barrel(m, cf * CFrame.new(-8.2, 0, -12.6))
end

function Props.pumpkinPatch(m: Instance, cf: CFrame)
	local orange = Color3.fromRGB(240, 118, 22)
	Props.paintDisc(cf.Position, 20, Enum.Material.Mud)
	local function pumpkin(at: CFrame, d: number)
		B(m, "Pumpkin", Vector3.new(d, d * 0.78, d), at * CFrame.new(0, d * 0.36, 0), orange, nil, { CanQuery = false })
		B(m, "PumpkinRib", Vector3.new(d * 0.62, d * 0.8, d * 1.04), at * CFrame.new(0, d * 0.36, 0), Props.darken(orange, 0.08), nil, TINY)
		B(m, "PumpkinRib", Vector3.new(d * 1.04, d * 0.8, d * 0.62), at * CFrame.new(0, d * 0.36, 0), Props.lighten(orange, 0.06), nil, TINY)
		Cy(m, "PumpkinStem", d * 0.16, d * 0.28, at * CFrame.new(0, d * 0.8, 0) * CFrame.Angles(0, 0, 0.2), Color3.fromRGB(88, 130, 50), nil, TINY)
	end
	pumpkin(cf * CFrame.new(-3, 0, -2), 7.5)
	pumpkin(cf * CFrame.new(6.5, 0, 3), 5.4)
	pumpkin(cf * CFrame.new(-9, 0, 7), 4.4)
	for k = 1, 9 do
		local a = k * 0.72
		local d = 4 + (k * 53) % 8
		pumpkin(cf * CFrame.new(math.cos(a) * d, 0, math.sin(a) * d) * CFrame.Angles(0, a, 0), 1.7 + (k % 3) * 0.5)
	end
	for k = 1, 10 do
		local a = k * 0.63 + 0.2
		local d = 5 + (k * 31) % 7
		local at = cf * CFrame.new(math.cos(a) * d, 0.35, math.sin(a) * d) * CFrame.Angles(0, a * 2.3, 0)
		P(m, "Vine", Vector3.new(0.3, 0.25, 6), at, Color3.fromRGB(70, 140, 60), nil, TINY)
		Cy(m, "VineLeaf", 2.2, 0.14, at * CFrame.new(0.8, 0.2, 1.4), Color3.fromRGB(80, 168, 74), nil, TINY)
	end
	-- wheelbarrow
	local wb = cf * CFrame.new(2, 0, -9) * CFrame.Angles(0, math.rad(-40), 0)
	P(m, "BarrowTray", Vector3.new(3, 1.3, 4), wb * CFrame.new(0, 2, 0), Color3.fromRGB(84, 150, 110), Enum.Material.Metal, { CanQuery = false })
	CyX(m, "BarrowWheel", 1.8, 0.5, wb * CFrame.new(0, 0.9, -2.5), METAL_DARK, nil, TINY)
	for _, x in { -1.2, 1.2 } do
		P(m, "BarrowHandle", Vector3.new(0.25, 0.25, 4), wb * CFrame.new(x, 1.9, 3.2) * CFrame.Angles(math.rad(-10), 0, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	end
	B(m, "Pumpkin", Vector3.new(2.4, 1.9, 2.4), wb * CFrame.new(0, 3, 0), orange, nil, TINY)
	Props.scarecrow(m, cf * CFrame.new(3, 0, 10))
end

local function well(parent: Instance, cf: CFrame)
	Cy(parent, "Well", 6.4, 2.8, cf * CFrame.new(0, 1.4, 0), STONE, Enum.Material.Cobblestone)
	Cy(parent, "WellWater", 5, 0.2, cf * CFrame.new(0, 2.76, 0), Color3.fromRGB(70, 150, 220), Enum.Material.Glass, TINY)
	for _, x in { -3.1, 3.1 } do
		P(parent, "WellPost", Vector3.new(0.6, 5.4, 0.6), cf * CFrame.new(x, 5.4, 0), WOOD_DARK, Enum.Material.Wood, TINY)
	end
	CyX(parent, "WellAxle", 0.5, 6.4, cf * CFrame.new(0, 7, 0), WOOD, Enum.Material.Wood, TINY)
	P(parent, "WellRope", Vector3.new(0.1, 2.4, 0.1), cf * CFrame.new(0, 5.7, 0), WHITE, nil, TINY)
	Cy(parent, "WellBucket", 1.2, 1.2, cf * CFrame.new(0, 4.2, 0), WOOD, Enum.Material.WoodPlanks, TINY)
	Props.gableRoof(parent, cf * CFrame.new(0, 8, 0), 8.4, 6, 2.4, Color3.fromRGB(190, 70, 60), Enum.Material.Wood, TINY)
end

function Props.tractorYard(m: Instance, cf: CFrame)
	local greenC = Color3.fromRGB(66, 168, 76)
	local tire = Color3.fromRGB(34, 34, 38)
	local yellow = Color3.fromRGB(255, 205, 60)
	Props.paintDisc(cf.Position, 18, Enum.Material.Mud)
	local t = cf * CFrame.new(-4, 0, -2) * CFrame.Angles(0, math.rad(-35), 0)
	ModelSlots.spawn("tractor", t, Vector3.new(8.6, 9.3, 12), m, function()
		for _, x in { -3.4, 3.4 } do
			CyX(m, "RearWheel", 6.4, 1.8, t * CFrame.new(x, 3.2, 2.6), tire, nil, { CanQuery = false })
			CyX(m, "RearHub", 2.8, 1.9, t * CFrame.new(x, 3.2, 2.6), yellow, nil, TINY)
		end
		for _, x in { -2.8, 2.8 } do
			CyX(m, "FrontWheel", 3.4, 1.3, t * CFrame.new(x, 1.7, -4.4), tire, nil, { CanQuery = false })
			CyX(m, "FrontHub", 1.5, 1.4, t * CFrame.new(x, 1.7, -4.4), yellow, nil, TINY)
		end
		P(m, "Chassis", Vector3.new(4.2, 1.4, 10), t * CFrame.new(0, 2.8, -0.8), Props.darken(greenC, 0.3), Enum.Material.Metal, { CanQuery = false })
		P(m, "Hood", Vector3.new(3.6, 2.8, 5.6), t * CFrame.new(0, 4.8, -3), greenC, Enum.Material.Metal, { CanQuery = false })
		P(m, "Grill", Vector3.new(3, 2, 0.3), t * CFrame.new(0, 4.6, -5.9), tire, Enum.Material.Metal, TINY)
		for _, x in { -1.1, 1.1 } do
			B(m, "Headlight", Vector3.one * 0.8, t * CFrame.new(x, 5.6, -5.9), Color3.fromRGB(255, 240, 170), Enum.Material.Neon, TINY)
		end
		Cy(m, "Exhaust", 0.5, 3.2, t * CFrame.new(1.2, 7.6, -4), tire, Enum.Material.Metal, TINY)
		P(m, "Seat", Vector3.new(2.2, 0.6, 2), t * CFrame.new(0, 4.2, 1.8), tire, Enum.Material.Fabric, TINY)
		P(m, "SeatBack", Vector3.new(2.2, 2, 0.5), t * CFrame.new(0, 5.4, 2.9), tire, Enum.Material.Fabric, TINY)
		P(m, "Wheel", Vector3.new(0.3, 0.3, 1.8), t * CFrame.new(0, 6, 0) * CFrame.Angles(math.rad(-50), 0, 0), tire, Enum.Material.Metal, TINY)
		for _, x in { -2.1, 2.1 } do
			for _, z in { 0.2, 3.6 } do
				P(m, "CabPost", Vector3.new(0.3, 5, 0.3), t * CFrame.new(x, 6.4, z), tire, Enum.Material.Metal, TINY)
			end
		end
		P(m, "CabRoof", Vector3.new(5.2, 0.4, 4.6), t * CFrame.new(0, 9.1, 1.9), greenC, Enum.Material.Metal, DECOR)
		return nil
	end, { collide = "solid", offset = Vector3.new(0, 0, -0.05), name = "Tractor" })
	-- trailer full of crates
	local tr = t * CFrame.new(0, 0, 10.5)
	P(m, "TrailerBed", Vector3.new(5, 0.5, 7), tr * CFrame.new(0, 2.2, 0), WOOD, Enum.Material.WoodPlanks, { CanQuery = false })
	P(m, "TrailerHitch", Vector3.new(0.4, 0.4, 3), tr * CFrame.new(0, 2.2, -4.6), tire, Enum.Material.Metal, TINY)
	for _, x in { -2.9, 2.9 } do
		CyX(m, "TrailerWheel", 3, 0.8, tr * CFrame.new(x, 1.5, 0.6), tire, nil, TINY)
	end
	Props.crate(m, tr * CFrame.new(-1.2, 2.45, -1.6), 2.2, { Color3.fromRGB(230, 40, 40) })
	Props.crate(m, tr * CFrame.new(1.2, 2.45, -1.4) * CFrame.Angles(0, 0.2, 0), 2.2, { Color3.fromRGB(255, 220, 60) })
	Props.crate(m, tr * CFrame.new(0, 2.45, 1.4) * CFrame.Angles(0, -0.2, 0), 2.2, { Color3.fromRGB(255, 140, 20) })
	well(m, cf * CFrame.new(9, 0, 6))
	Props.barrel(m, cf * CFrame.new(13.5, 0, -2))
	Props.sack(m, cf * CFrame.new(11, 0, -6))
end

-- Hot-air balloon far above the hills.
local function balloonPrimitive(parent: Instance, pos: Vector3, a: Color3, b: Color3)
	local m = Instance.new("Model")
	m.Name = "HotAirBalloon"
	local at = CFrame.new(pos)
	local env = B(m, "Envelope", Vector3.one * 30, at, a, Enum.Material.Fabric, TINY)
	for _, y in { -6, 0, 6 } do
		local r = math.sqrt(15 * 15 - y * y) * 2 + 0.5
		Cy(m, "Stripe", r, 3, at * CFrame.new(0, y, 0), b, Enum.Material.Fabric, TINY)
	end
	B(m, "Neck", Vector3.new(10, 8, 10), at * CFrame.new(0, -14, 0), a, Enum.Material.Fabric, TINY)
	P(m, "Basket", Vector3.new(5.5, 4, 5.5), at * CFrame.new(0, -24, 0), WOOD, Enum.Material.WoodPlanks, TINY)
	for _, x in { -2.5, 2.5 } do
		for _, z in { -2.5, 2.5 } do
			P(m, "Rope", Vector3.new(0.15, 7, 0.15), at * CFrame.new(x, -19, z), WHITE, nil, TINY)
		end
	end
	B(m, "Burner", Vector3.one * 1.6, at * CFrame.new(0, -18.4, 0), Color3.fromRGB(255, 190, 80), Enum.Material.Neon, TINY)
	m.PrimaryPart = env
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m:SetAttribute("BasePivot", at)
	m:SetAttribute("FloatPhase", rng:NextNumber(0, 6))
	CollectionService:AddTag(m, "CK_Float")
	m.Parent = parent
end

-- ===================================================================== model slots
-- Public props: each looks for a real model in ServerStorage.ModelLibrary (assets/models/<slot>.rbxm, see
-- docs/modelos/huerta-tycoon.md) and falls back to the primitive version above. With an empty library the primitive
-- runs untouched (same rng stream). Models never use Props.rng: rotation/variant come from the position.

function Props.tree(parent: Instance, pos: Vector3, s: number)
	if not ModelSlots.has("tree") then
		return treePrimitive(parent, pos, s)
	end
	local at = CFrame.new(pos) * CFrame.Angles(0, ModelFit.yaw(pos.X, pos.Z), 0)
	ModelSlots.spawn("tree", at, Vector3.new(12, 15, 12) * s, parent, function()
		treePrimitive(parent, pos, s)
		return nil
	end, { collide = "decor", collider = Vector3.new(0.17, 0.5, 0.17), maxParts = 80, name = "Tree" })
end

function Props.bush(parent: Instance, pos: Vector3, s: number)
	if not ModelSlots.has("bush") then
		return bushPrimitive(parent, pos, s)
	end
	local at = CFrame.new(pos) * CFrame.Angles(0, ModelFit.yaw(pos.X, pos.Z), 0)
	ModelSlots.spawn("bush", at, Vector3.new(4.8, 2.8, 4.2) * s, parent, function()
		bushPrimitive(parent, pos, s)
		return nil
	end, { collide = "decor", maxParts = 40, name = "Bush" })
end

function Props.rock(parent: Instance, pos: Vector3, s: number)
	if not ModelSlots.has("rock") then
		return rockPrimitive(parent, pos, s)
	end
	local at = CFrame.new(pos - Vector3.new(0, 0.2 * s, 0)) * CFrame.Angles(0, ModelFit.yaw(pos.X, pos.Z), 0)
	ModelSlots.spawn("rock", at, Vector3.new(2.4, 1.65, 2) * s, parent, function()
		rockPrimitive(parent, pos, s)
		return nil
	end, { collide = "solid", query = false, maxParts = 40, name = "Rock" })
end

function Props.lamp(parent: Instance, pos: Vector3, lit: boolean)
	if not ModelSlots.has("lamp") then
		return lampPrimitive(parent, pos, lit)
	end
	local used = false
	ModelSlots.spawn("lamp", CFrame.new(pos), Vector3.new(1.9, 11, 1.9), parent, function()
		lampPrimitive(parent, pos, lit)
		used = true
		return nil
	end, { collide = "solid", query = false, maxParts = 60, name = "Lamp" })
	if not used and lit then
		-- the primitive lamp carries its own light; a library lamp gets an invisible one at the top
		local glow = P(parent, "LampLight", Vector3.one * 0.2, CFrame.new(pos + Vector3.new(0, 9.9, 0)), GLOW, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		light(glow, 20, 1.1)
	end
end

function Props.bench(parent: Instance, cf: CFrame)
	ModelSlots.spawn("bench", cf, Vector3.new(6.4, 3.4, 2.1), parent, function()
		benchPrimitive(parent, cf)
		return nil
	end, { collide = "solid", query = false, maxParts = 60, name = "Bench" })
end

function Props.scarecrow(parent: Instance, cf: CFrame)
	ModelSlots.spawn("scarecrow", cf, Vector3.new(5.4, 7.7, 1.8), parent, function()
		scarecrowPrimitive(parent, cf)
		return nil
	end, { collide = "decor", maxParts = 100, name = "Scarecrow" })
end

function Props.farmhouse(parent: Instance, cf: CFrame, color: Color3)
	ModelSlots.spawn("farmhouse", cf, Vector3.new(21, 17.5, 19.8), parent, function()
		farmhousePrimitive(parent, cf, color)
		return nil
	end, { collide = "solid", offset = Vector3.new(0, 0, -1.1), maxParts = 300, name = "Farmhouse" })
end

function Props.fountain(parent: Instance, cf: CFrame)
	ModelSlots.spawn("fountain", cf, Vector3.new(28, 14.5, 28), parent, function()
		fountainPrimitive(parent, cf)
		return nil
	end, { collide = "solid", maxParts = 300, name = "Fountain" })
end

function Props.balloon(parent: Instance, pos: Vector3, a: Color3, b: Color3)
	if not ModelSlots.has("balloon") then
		return balloonPrimitive(parent, pos, a, b)
	end
	local placed = false
	local m = ModelSlots.spawn("balloon", CFrame.new(pos - Vector3.new(0, 26, 0)), Vector3.new(30, 41, 30), parent, function()
		balloonPrimitive(parent, pos, a, b)
		placed = true
		return nil
	end, { collide = "decor", maxParts = 150, name = "HotAirBalloon" })
	if m and not placed and m:IsA("Model") then
		-- same contract as the primitive: the client bobs models tagged CK_Float around BasePivot
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		m:SetAttribute("BasePivot", m:GetPivot())
		m:SetAttribute("FloatPhase", (pos.X * 0.013 + pos.Z * 0.007) % 6)
		CollectionService:AddTag(m, "CK_Float")
	end
end

return Props
