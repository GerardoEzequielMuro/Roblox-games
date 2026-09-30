--!strict
-- Builds the whole map in code: 5 themed zones along +Z separated by gates, eggs on
-- pedestals, landmarks, scenery, spawn plaza, leaderboard boards and lighting.
--
-- Every zone has its own border style, props, two landmarks, path lamps and a horizon
-- (hills, mountains, volcanoes, planets) on a "skirt" of ground beyond the invisible walls,
-- so the map never ends in a flat edge. Things that should move (windmill, UFO, planets,
-- balloons) carry the "TpsAnim" tag; the client animates them (WorldFx).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Palette = require(ReplicatedStorage.Shared.Palette)

local WorldBuilder = {}

export type Plot = { model: Model, chest: BasePart, spawn: CFrame }

export type WorldInfo = {
	plots: { Plot },
	eggPositions: { [string]: Vector3 },
	zoneSpawns: { [number]: CFrame },
	gates: { [number]: BasePart },
	boards: { [string]: BasePart },
}

local L = Config.ZoneLength
local W = Config.ZoneWidth
local GATE_W, GATE_H = 22, 18
local WALL_H = 80
local SKIRT = 320 -- ground beyond the side walls (scenery only)
local PARK_DEPTH = 68 -- Pet Park: the strip behind the spawn plaza

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local rgb = Palette.rgb
local V = Vector3.new
local C = Color3.fromRGB
local WHITE = C(255, 255, 255)

type Props = { [string]: any }
type Reserved = { pos: Vector3, r: number }

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function part(parent: Instance, props: Props): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanTouch = false -- nothing in the world uses Touched
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "ClassName" and k ~= "Shape" and k ~= "Mesh" then
			(p :: any)[k] = v
		end
	end
	if props.Shape then
		(p :: any).Shape = props.Shape
	end
	if props.Mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = props.Mesh
		m.Parent = p
	end
	p.Parent = parent
	return p
end

-- Scenery: never collides, never casts a shadow, invisible to raycasts.
local function deco(parent: Instance, props: Props): BasePart
	if props.CanCollide == nil then
		props.CanCollide = false
	end
	if props.CastShadow == nil then
		props.CastShadow = false
	end
	props.CanQuery = false
	props.CanTouch = false
	return part(parent, props)
end

-- Upright cylinder.
local function cyl(parent: Instance, name: string, pos: Vector3, diameter: number, height: number, color: Color3, material: Enum.Material?, extra: Props?): BasePart
	local props: Props = { Name = name, Shape = Enum.PartType.Cylinder, Size = V(height, diameter, diameter), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material or Enum.Material.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return deco(parent, props)
end

local function ball(parent: Instance, name: string, pos: Vector3, size: number, color: Color3, material: Enum.Material?, extra: Props?): BasePart
	local props: Props = { Name = name, Shape = Enum.PartType.Ball, Size = V(size, size, size), Position = pos, Color = color, Material = material or Enum.Material.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return deco(parent, props)
end

-- Squashed / stretched sphere.
local function ell(parent: Instance, name: string, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?, extra: Props?): BasePart
	local props: Props = { Name = name, Mesh = Enum.MeshType.Sphere, Size = size, Position = pos, Color = color, Material = material or Enum.Material.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return deco(parent, props)
end

-- "Painted" contact shadow: a dark disc on the ground under big props. Real-time shadows
-- switch off below graphics level 4; this keeps things planted at any setting.
local function blob(parent: Instance, pos: Vector3, diameter: number, ground: Color3?)
	deco(parent, { Name = "Blob", Shape = Enum.PartType.Cylinder, Size = V(0.06, diameter, diameter), CFrame = CFrame.new(pos.X, 0.05, pos.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = darken(ground or C(70, 110, 60), 0.45), Transparency = 0.45 })
end

-- Client-side motion (WorldFx): spin around a local axis and/or bob up and down.
-- The client moves these, so the resting CFrame travels as an attribute, and models are
-- streamed whole.
local function anim(inst: Instance, spinAxis: Vector3?, spinSpeed: number?, bobAmp: number?, bobSpeed: number?)
	if inst:IsA("Model") then
		inst.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	if inst:IsA("PVInstance") then
		inst:SetAttribute("Rest", inst:GetPivot())
	end
	if spinAxis then
		inst:SetAttribute("SpinAxis", spinAxis)
		inst:SetAttribute("SpinSpeed", spinSpeed or 1)
	end
	if bobAmp then
		inst:SetAttribute("BobAmp", bobAmp)
		inst:SetAttribute("BobSpeed", bobSpeed or 1)
	end
	CollectionService:AddTag(inst, "TpsAnim")
end

local function light(parent: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.2
	l.Shadows = false
	l.Parent = parent
end

local function emitter(parent: Instance, texture: string, color: Color3, rate: number, size: number, speed: number, lifetime: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 0.8
	e.Parent = parent
	return e
end

-- Low-poly mountain: a cube standing on one corner, optionally with a smaller "cap" cube
-- (snow / lava) on the tip.
local PEAK_TILT = CFrame.Angles(math.atan(1 / math.sqrt(2)), 0, 0) * CFrame.Angles(0, 0, math.rad(45))
local function peak(parent: Instance, x: number, z: number, height: number, yaw: number, color: Color3, material: Enum.Material, capColor: Color3?, capMaterial: Enum.Material?): number
	local s = height / 0.866
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0) * PEAK_TILT
	deco(parent, { Name = "Peak", Size = V(s, s, s), CFrame = cf, Color = color, Material = material })
	if capColor then
		local cs = s * (if capMaterial == Enum.Material.Neon then 0.2 else 0.36)
		deco(parent, { Name = "PeakCap", Size = V(cs, cs, cs), CFrame = CFrame.new(x, height - cs * 0.866 + 1.5, z) * CFrame.Angles(0, yaw, 0) * PEAK_TILT, Color = capColor, Material = capMaterial or Enum.Material.SmoothPlastic })
	end
	return height
end

local function zoneCenter(i: number): number
	return (i - 1) * L
end

local function label(parent: Instance, text: string, size: UDim2, offset: Vector3, color: Color3, maxDist: number?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffset = offset
	bb.AlwaysOnTop = false
	bb.MaxDistance = maxDist or 120
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.RichText = true
	t.Name = "Text"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = C(30, 20, 40)
	stroke.Parent = t
	t.Parent = bb
	bb.Parent = parent
	return bb
end

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Name = "Text"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = C(30, 20, 40)
	stroke.Parent = t
	t.Parent = sg
	sg.Parent = p
	return t
end

---------------------------------------------------------------------------
-- Props (scattered inside each zone)
---------------------------------------------------------------------------
type Deco = (folder: Instance, pos: Vector3, rng: Random) -> ()

local function tree(folder: Instance, pos: Vector3, rng: Random, scale: number?)
	local k = scale or 1
	local h = rng:NextNumber(7, 12) * k
	if k == 1 then
		blob(folder, pos, 9)
	end
	part(folder, { Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = V(h, 1.8 * k, 1.8 * k), CFrame = CFrame.new(pos + V(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(120, 80, 50), Material = Enum.Material.Wood, CastShadow = k == 1 })
	local greens = { C(80, 180, 70), C(60, 160, 60), C(110, 200, 80), C(150, 215, 90) }
	for i = 1, 4 do
		local r = rng:NextNumber(4.5, 7) * k
		local off = V(rng:NextNumber(-2.2, 2.2) * k, h + rng:NextNumber(-1, 3) * k, rng:NextNumber(-2.2, 2.2) * k)
		part(folder, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * r, Position = pos + off, Color = greens[i], Material = Enum.Material.Grass, CanCollide = false, CastShadow = i == 1 and k == 1 })
	end
end

local function flower(folder: Instance, pos: Vector3, rng: Random)
	local cols = { C(255, 90, 120), C(255, 220, 60), C(170, 120, 255), WHITE, C(255, 150, 60) }
	local col = cols[rng:NextInteger(1, #cols)]
	local h = rng:NextNumber(1.1, 1.9)
	deco(folder, { Name = "Stem", Size = V(0.22, h, 0.22), Position = pos + V(0, h / 2, 0), Color = C(60, 150, 60) })
	ell(folder, "Bloom", pos + V(0, h + 0.15, 0), V(1.2, 0.5, 1.2), col)
	ball(folder, "Heart", pos + V(0, h + 0.3, 0), 0.5, C(255, 215, 70))
end

local function bush(folder: Instance, pos: Vector3, rng: Random)
	local greens = { C(60, 150, 60), C(75, 170, 70), C(95, 185, 80) }
	for i = 1, 3 do
		local r = rng:NextNumber(3, 4.6)
		deco(folder, { Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * r, Position = pos + V(rng:NextNumber(-1.6, 1.6), r * 0.3, rng:NextNumber(-1.6, 1.6)), Color = greens[i], Material = Enum.Material.Grass })
	end
	if rng:NextNumber() < 0.6 then
		for _ = 1, 3 do
			ball(folder, "Berry", pos + V(rng:NextNumber(-1.8, 1.8), rng:NextNumber(1.6, 2.6), rng:NextNumber(-1.8, 1.8)), 0.55, C(255, 80, 110))
		end
	end
end

local function mushroom(folder: Instance, pos: Vector3, rng: Random)
	local k = rng:NextNumber(0.8, 1.7)
	local cap = if rng:NextNumber() < 0.7 then C(235, 60, 70) else C(255, 170, 60)
	blob(folder, pos, 4 * k)
	cyl(folder, "Stem", pos + V(0, 1.1 * k, 0), 1.1 * k, 2.2 * k, C(250, 240, 225))
	ell(folder, "Cap", pos + V(0, 2.4 * k, 0), V(4 * k, 2 * k, 4 * k), cap)
	for i = 1, 4 do
		local a = i * 1.7
		ball(folder, "Dot", pos + V(math.cos(a) * 1.1 * k, 3.05 * k, math.sin(a) * 1.1 * k), 0.6 * k, WHITE)
	end
end

local function rock(folder: Instance, pos: Vector3, rng: Random, color: Color3?, mat: Enum.Material?)
	local s = rng:NextNumber(2, 5)
	part(folder, { Name = "Rock", Size = V(s, s * 0.7, s * 0.9), CFrame = CFrame.new(pos + V(0, s * 0.25, 0)) * CFrame.Angles(rng:NextNumber(0, 0.5), rng:NextNumber(0, 6), rng:NextNumber(0, 0.5)), Color = color or C(140, 140, 150), Material = mat or Enum.Material.Slate, CastShadow = false })
	if rng:NextNumber() < 0.5 then
		local s2 = s * 0.55
		deco(folder, { Name = "Rock", Size = V(s2, s2 * 0.7, s2), CFrame = CFrame.new(pos + V(s * 0.6, s2 * 0.25, s * 0.3)) * CFrame.Angles(rng:NextNumber(0, 0.5), rng:NextNumber(0, 6), 0), Color = darken(color or C(140, 140, 150), 0.12), Material = mat or Enum.Material.Slate })
	end
end

local function lollipop(folder: Instance, pos: Vector3, rng: Random, scale: number?)
	local k = scale or 1
	local h = rng:NextNumber(6, 11) * k
	local cols = { C(255, 80, 150), C(90, 200, 255), C(255, 200, 60), C(150, 110, 255), C(120, 230, 150) }
	local c = cols[rng:NextInteger(1, #cols)]
	if k == 1 then
		blob(folder, pos, 5, C(255, 180, 215))
	end
	part(folder, { Name = "Stick", Size = V(0.6 * k, h, 0.6 * k), Position = pos + V(0, h / 2, 0), Color = WHITE, CastShadow = false })
	local yaw = rng:NextNumber(0, math.pi * 2)
	local cf = CFrame.new(pos + V(0, h + 2.4 * k, 0)) * CFrame.Angles(0, yaw, 0)
	deco(folder, { Name = "Candy", Shape = Enum.PartType.Cylinder, Size = V(1.2 * k, 6 * k, 6 * k), CFrame = cf, Color = c })
	deco(folder, { Name = "Swirl", Shape = Enum.PartType.Cylinder, Size = V(1.3 * k, 4.2 * k, 4.2 * k), CFrame = cf, Color = WHITE })
	deco(folder, { Name = "Swirl", Shape = Enum.PartType.Cylinder, Size = V(1.4 * k, 2.4 * k, 2.4 * k), CFrame = cf, Color = c })
end

local function candyCane(folder: Instance, pos: Vector3, rng: Random, scale: number?)
	local k = scale or 1
	local seg = rng:NextInteger(6, 9)
	local red = C(230, 40, 60)
	for i = 0, seg - 1 do
		part(folder, { Name = "Cane", Size = V(1.2, 1.2, 1.2) * k, Position = pos + V(0, (0.6 + i * 1.2) * k, 0), Color = if i % 2 == 0 then red else WHITE, CastShadow = false })
	end
	for i = 1, 3 do
		deco(folder, { Name = "Hook", Size = V(1.2, 1.2, 1.2) * k, Position = pos + V(i * 1.1 * k, (seg * 1.2 + (if i == 3 then -0.6 else 0.2)) * k, 0), Color = if i % 2 == 0 then red else WHITE })
	end
end

local function gumdrop(folder: Instance, pos: Vector3, rng: Random)
	local cols = { C(255, 90, 90), C(120, 230, 120), C(255, 220, 80), C(190, 120, 255) }
	local s = rng:NextNumber(3, 6)
	part(folder, { Name = "Gumdrop", Shape = Enum.PartType.Ball, Size = Vector3.one * s, Position = pos + V(0, s * 0.2, 0), Color = cols[rng:NextInteger(1, #cols)], Material = Enum.Material.Glass, Transparency = 0.15, CastShadow = false })
end

local function cupcake(folder: Instance, pos: Vector3, rng: Random)
	local k = rng:NextNumber(1, 1.8)
	local wraps = { C(120, 200, 255), C(255, 210, 90), C(180, 140, 255) }
	local frosts = { C(255, 150, 200), C(255, 245, 235), C(150, 235, 200) }
	blob(folder, pos, 5.5 * k, C(255, 180, 215))
	part(folder, { Name = "Wrapper", Shape = Enum.PartType.Cylinder, Size = V(2.2 * k, 3.4 * k, 3.4 * k), CFrame = CFrame.new(pos + V(0, 1.1 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = wraps[rng:NextInteger(1, #wraps)], CastShadow = false })
	local frost = frosts[rng:NextInteger(1, #frosts)]
	ell(folder, "Frosting", pos + V(0, 2.7 * k, 0), V(4.2 * k, 2.2 * k, 4.2 * k), frost)
	ell(folder, "Frosting", pos + V(0, 3.7 * k, 0), V(2.8 * k, 1.7 * k, 2.8 * k), frost)
	ball(folder, "Cherry", pos + V(0, 4.8 * k, 0), 1.1 * k, C(230, 40, 70))
end

local function iceCream(folder: Instance, pos: Vector3, rng: Random)
	local k = rng:NextNumber(1, 1.5)
	local scoops = { C(255, 170, 200), C(170, 235, 200), C(255, 240, 200), C(150, 100, 70) }
	blob(folder, pos, 5 * k, C(255, 180, 215))
	part(folder, { Name = "Cone", Shape = Enum.PartType.Cylinder, Size = V(3.4 * k, 2.2 * k, 2.2 * k), CFrame = CFrame.new(pos + V(0, 1.7 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(225, 170, 100), Material = Enum.Material.Fabric, CastShadow = false })
	cyl(folder, "ConeRim", pos + V(0, 3.5 * k, 0), 3 * k, 0.5 * k, C(235, 185, 115), Enum.Material.Fabric)
	for i = 0, 1 do
		ball(folder, "Scoop", pos + V(0, (4.7 + i * 2.1) * k, 0), (3.2 - i * 0.5) * k, scoops[rng:NextInteger(1, #scoops)])
	end
	ball(folder, "Cherry", pos + V(0, 8.2 * k, 0), 0.9 * k, C(230, 40, 70))
end

local function pine(folder: Instance, pos: Vector3, rng: Random, scale: number?)
	local k = scale or 1
	local h = rng:NextNumber(9, 15) * k
	if k == 1 then
		blob(folder, pos, 10, C(200, 215, 235))
	end
	part(folder, { Name = "Trunk", Size = V(1.4 * k, 3 * k, 1.4 * k), Position = pos + V(0, 1.5 * k, 0), Color = C(100, 70, 50), Material = Enum.Material.Wood, CastShadow = false })
	local layers = 4
	for i = 0, layers - 1 do
		local w = (8 - i * 1.7) * k
		local y = 3 * k + i * (h - 3 * k) / layers
		local yaw = math.rad(45 + i * 20)
		part(folder, { Name = "Needles", Size = V(w, 2.4 * k, w), CFrame = CFrame.new(pos + V(0, y, 0)) * CFrame.Angles(0, yaw, 0), Color = C(40, 110, 80), Material = Enum.Material.Grass, CanCollide = i == 0, CastShadow = i == 0 and k == 1 })
		deco(folder, { Name = "Snow", Size = V(w * 0.8, 0.5 * k, w * 0.8), CFrame = CFrame.new(pos + V(0, y + 1.4 * k, 0)) * CFrame.Angles(0, yaw, 0), Color = C(250, 252, 255), Material = Enum.Material.Snow })
	end
end

local function crystal(folder: Instance, pos: Vector3, rng: Random, color: Color3?, neon: boolean?, scale: number?)
	local c = color or C(150, 210, 255)
	local k = scale or 1
	for _ = 1, rng:NextInteger(2, 4) do
		local h = rng:NextNumber(3, 8) * k
		part(folder, { Name = "Crystal", Size = V(1.4 * k, h, 1.4 * k), CFrame = CFrame.new(pos + V(rng:NextNumber(-1.5, 1.5) * k, h * 0.4, rng:NextNumber(-1.5, 1.5) * k)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), Color = c, Material = if neon then Enum.Material.Neon else Enum.Material.Glass, Transparency = if neon then 0 else 0.25, CastShadow = false })
	end
end

local function snowman(folder: Instance, pos: Vector3, _rng: Random)
	local white = C(250, 252, 255)
	blob(folder, pos, 5.5, C(200, 215, 235))
	part(folder, { Name = "Snow1", Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Position = pos + V(0, 1.8, 0), Color = white, Material = Enum.Material.Snow, CastShadow = false })
	deco(folder, { Name = "Snow2", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = pos + V(0, 4.6, 0), Color = white, Material = Enum.Material.Snow })
	deco(folder, { Name = "Snow3", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, Position = pos + V(0, 6.8, 0), Color = white, Material = Enum.Material.Snow })
	deco(folder, { Name = "Carrot", Size = V(0.35, 0.35, 1.3), Position = pos + V(0, 6.8, -1.4), Color = C(255, 140, 30) })
	for _, s in { -1, 1 } do
		ball(folder, "Eye", pos + V(0.4 * s, 7.2, -0.95), 0.35, C(20, 20, 20))
		deco(folder, { Name = "Arm", Size = V(2.6, 0.25, 0.25), CFrame = CFrame.new(pos + V(2.3 * s, 5.1, 0)) * CFrame.Angles(0, 0, math.rad(25 * s)), Color = C(95, 65, 45) })
	end
	cyl(folder, "HatBrim", pos + V(0, 7.85, 0), 2.4, 0.2, C(35, 35, 45))
	cyl(folder, "Hat", pos + V(0, 8.5, 0), 1.6, 1.2, C(35, 35, 45))
	ell(folder, "Scarf", pos + V(0, 5.95, 0), V(2.6, 0.7, 2.6), C(230, 50, 60), Enum.Material.Fabric)
end

local function snowMound(folder: Instance, pos: Vector3, rng: Random)
	local s = rng:NextNumber(6, 12)
	ell(folder, "Mound", pos + V(0, 0.2, 0), V(s, s * 0.35, s * rng:NextNumber(0.7, 1.1)), C(250, 252, 255), Enum.Material.Snow)
end

local function lavaPool(folder: Instance, pos: Vector3, rng: Random)
	local r = rng:NextNumber(6, 12)
	local pool = cyl(folder, "LavaPool", pos + V(0, 0.1, 0), r, 0.4, C(255, 110, 20), Enum.Material.Neon)
	cyl(folder, "LavaRim", pos + V(0, 0.05, 0), r + 1.6, 0.34, C(50, 38, 38), Enum.Material.Basalt)
	light(pool, C(255, 120, 40), r, 2)
	local fire = emitter(pool, FIRE, C(255, 150, 40), 5, 1.5, 4, 1.1)
	fire.LightEmission = 1
end

local function obsidian(folder: Instance, pos: Vector3, rng: Random)
	crystal(folder, pos, rng, C(35, 25, 40), false)
end

local function stalagmite(folder: Instance, pos: Vector3, rng: Random)
	local h = rng:NextNumber(5, 11)
	local col = C(62, 48, 48)
	blob(folder, pos, 5, C(60, 45, 45))
	part(folder, { Name = "Spike", Size = V(2.6, h * 0.55, 2.6), CFrame = CFrame.new(pos + V(0, h * 0.27, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color = col, Material = Enum.Material.Basalt, CastShadow = false })
	deco(folder, { Name = "Spike", Size = V(1.6, h * 0.4, 1.6), CFrame = CFrame.new(pos + V(0, h * 0.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color = darken(col, 0.15), Material = Enum.Material.Basalt })
	deco(folder, { Name = "Spike", Size = V(0.8, h * 0.25, 0.8), CFrame = CFrame.new(pos + V(0, h * 0.98, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color = C(255, 120, 30), Material = Enum.Material.Neon })
end

local function lavaCrack(folder: Instance, pos: Vector3, rng: Random)
	local yaw = rng:NextNumber(0, math.pi)
	local at = CFrame.new(pos + V(0, 0.07, 0)) * CFrame.Angles(0, yaw, 0)
	for i = 0, 3 do
		local len = rng:NextNumber(4, 8)
		local seg = at * CFrame.Angles(0, if i % 2 == 0 then 0.55 else -0.55, 0)
		deco(folder, { Name = "Crack", Size = V(0.5, 0.12, len), CFrame = seg * CFrame.new(0, 0, len / 2), Color = C(255, 120, 30), Material = Enum.Material.Neon })
		at = seg * CFrame.new(0, 0, len) * CFrame.Angles(0, if i % 2 == 0 then -0.55 else 0.55, 0)
	end
end

local function planet(folder: Instance, pos: Vector3, rng: Random)
	local cols = { C(255, 120, 200), C(120, 200, 255), C(255, 210, 90), C(150, 255, 170) }
	local c = cols[rng:NextInteger(1, #cols)]
	local s = rng:NextNumber(5, 12)
	local y = rng:NextNumber(18, 40)
	local model = Instance.new("Model")
	model.Name = "Planet"
	local body = deco(model, { Name = "Planet", Shape = Enum.PartType.Ball, Size = Vector3.one * s, Position = pos + V(0, y, 0), Color = c })
	deco(model, { Name = "Ring", Shape = Enum.PartType.Cylinder, Size = V(0.3, s * 1.8, s * 1.8), CFrame = CFrame.new(pos + V(0, y, 0)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, math.rad(90) + rng:NextNumber(-0.4, 0.4)), Color = WHITE, Material = Enum.Material.Neon, Transparency = 0.3 })
	model.PrimaryPart = body
	model.Parent = folder
	anim(model, V(0, 1, 0), rng:NextNumber(0.1, 0.3), rng:NextNumber(0.6, 1.4), rng:NextNumber(0.4, 0.9))
end

local function star(folder: Instance, pos: Vector3, rng: Random)
	ball(folder, "Star", pos + V(0, rng:NextNumber(6, 30), 0), rng:NextNumber(0.6, 1.4), C(255, 250, 200), Enum.Material.Neon)
end

local function asteroid(folder: Instance, pos: Vector3, rng: Random)
	local s = rng:NextNumber(4, 9)
	local model = Instance.new("Model")
	model.Name = "Asteroid"
	local body = deco(model, { Name = "Rock", Size = V(s, s * 0.75, s * 0.9), CFrame = CFrame.new(pos + V(0, rng:NextNumber(16, 36), 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)), Color = C(70, 60, 110), Material = Enum.Material.Slate })
	deco(model, { Name = "Gem", Size = V(s * 0.3, s * 0.7, s * 0.3), CFrame = body.CFrame * CFrame.new(0, s * 0.45, 0) * CFrame.Angles(0.3, 0, 0.2), Color = C(120, 220, 255), Material = Enum.Material.Neon })
	model.PrimaryPart = body
	model.Parent = folder
	anim(model, V(0.3, 1, 0.2).Unit, rng:NextNumber(0.1, 0.35), rng:NextNumber(0.8, 1.8), rng:NextNumber(0.3, 0.7))
end

local DECOR: { [string]: { { fn: Deco, count: number } } } = {
	meadow = { { fn = tree, count = 24 }, { fn = flower, count = 46 }, { fn = bush, count = 14 }, { fn = mushroom, count = 12 }, { fn = rock, count = 9 } },
	candy = { { fn = lollipop, count = 18 }, { fn = candyCane, count = 10 }, { fn = gumdrop, count = 18 }, { fn = cupcake, count = 12 }, { fn = iceCream, count = 9 } },
	frost = { { fn = pine, count = 24 }, { fn = crystal, count = 12 }, { fn = snowman, count = 6 }, { fn = snowMound, count = 16 } },
	lava = {
		{ fn = lavaPool, count = 9 },
		{ fn = obsidian, count = 12 },
		{ fn = stalagmite, count = 16 },
		{ fn = lavaCrack, count = 14 },
		{
			fn = function(f, p, r)
				rock(f, p, r, C(60, 45, 45), Enum.Material.Basalt)
			end,
			count = 14,
		},
	},
	cosmic = {
		{ fn = planet, count = 10 },
		{ fn = star, count = 40 },
		{ fn = asteroid, count = 9 },
		{
			fn = function(f, p, r)
				crystal(f, p, r, C(170, 110, 255), true)
			end,
			count = 14,
		},
	},
}

---------------------------------------------------------------------------
-- Zone borders (the visible edge; the invisible walls do the blocking)
---------------------------------------------------------------------------
local BORDER: { [string]: (folder: Instance, zc: number) -> () } = {
	meadow = function(folder, zc)
		local wood = C(205, 165, 115)
		for _, s in { -1, 1 } do
			local x = s * (W / 2 - 1)
			for z = zc - L / 2 + 4, zc + L / 2 - 4, 8 do
				deco(folder, { Name = "Post", Size = V(1.1, 5.6, 1.1), Position = V(x, 2.8, z), Color = wood, Material = Enum.Material.Wood })
			end
			for _, y in { 2, 4.2 } do
				deco(folder, { Name = "Rail", Size = V(0.5, 0.8, L), Position = V(x, y, zc), Color = lighten(wood, 0.12), Material = Enum.Material.Wood })
			end
			deco(folder, { Name = "Hedge", Size = V(5, 4.4, L), Position = V(s * (W / 2 + 3.5), 2.2, zc), Color = C(55, 140, 60), Material = Enum.Material.Grass })
		end
	end,
	candy = function(folder, zc)
		local tops = { C(255, 90, 90), C(120, 230, 120), C(255, 220, 80), C(190, 120, 255), C(90, 200, 255) }
		for _, s in { -1, 1 } do
			local x = s * (W / 2 - 1)
			local i = 0
			for z = zc - L / 2 + 4, zc + L / 2 - 4, 8 do
				i += 1
				deco(folder, { Name = "Post", Size = V(1.4, 6, 1.4), Position = V(x, 3, z), Color = if i % 2 == 0 then C(230, 40, 60) else WHITE })
				ball(folder, "Gumball", V(x, 6.6, z), 2.2, tops[i % #tops + 1], Enum.Material.Glass)
			end
			deco(folder, { Name = "Rail", Size = V(0.8, 1, L), Position = V(x, 3.4, zc), Color = C(255, 245, 250) })
			deco(folder, { Name = "Frosting", Size = V(4, 3, L), Position = V(s * (W / 2 + 3), 1.5, zc), Color = C(255, 235, 245) })
		end
	end,
	frost = function(folder, zc)
		local rng = Random.new(303)
		for _, s in { -1, 1 } do
			for z = zc - L / 2 + 4, zc + L / 2 - 4, 8 do
				local h = rng:NextNumber(5, 10)
				deco(folder, { Name = "IceBlock", Size = V(3, h, 8.2), CFrame = CFrame.new(s * (W / 2 - 1.5), h / 2, z) * CFrame.Angles(0, 0, rng:NextNumber(-0.06, 0.06)), Color = C(165, 215, 255), Material = Enum.Material.Ice, Transparency = 0.12 })
			end
			deco(folder, { Name = "SnowBank", Size = V(7, 3.2, L), Position = V(s * (W / 2 + 4), 1.2, zc), Color = C(250, 252, 255), Material = Enum.Material.Snow })
		end
	end,
	lava = function(folder, zc)
		local rng = Random.new(404)
		for _, s in { -1, 1 } do
			for z = zc - L / 2 + 4, zc + L / 2 - 4, 8 do
				local h = rng:NextNumber(6, 13)
				deco(folder, { Name = "Spike", Size = V(3.2, h, 5.4), CFrame = CFrame.new(s * (W / 2 - 1.5), h / 2 - 0.8, z) * CFrame.Angles(rng:NextNumber(-0.22, 0.22), rng:NextNumber(0, 1), rng:NextNumber(-0.22, 0.22)), Color = C(45, 35, 38), Material = Enum.Material.Basalt })
			end
			deco(folder, { Name = "Glow", Size = V(1.4, 0.3, L), Position = V(s * (W / 2 - 4), 0.12, zc), Color = C(255, 110, 25), Material = Enum.Material.Neon })
		end
	end,
	cosmic = function(folder, zc)
		for _, s in { -1, 1 } do
			local x = s * (W / 2 - 1.2)
			for z = zc - L / 2 + 6, zc + L / 2 - 6, 16 do
				deco(folder, { Name = "Pylon", Size = V(1.6, 8, 1.6), Position = V(x, 4, z), Color = C(40, 32, 80), Material = Enum.Material.Metal })
				ball(folder, "PylonOrb", V(x, 8.8, z), 2, C(120, 220, 255), Enum.Material.Neon)
			end
			deco(folder, { Name = "Beam", Size = V(0.35, 0.35, L), Position = V(x, 6, zc), Color = C(190, 120, 255), Material = Enum.Material.Neon, Transparency = 0.15 })
			deco(folder, { Name = "Beam", Size = V(0.35, 0.35, L), Position = V(x, 3, zc), Color = C(120, 220, 255), Material = Enum.Material.Neon, Transparency = 0.15 })
			deco(folder, { Name = "Edge", Size = V(1.6, 0.4, L), Position = V(s * (W / 2 - 0.8), 0.15, zc), Color = C(130, 90, 255), Material = Enum.Material.Neon })
		end
	end,
}

---------------------------------------------------------------------------
-- Path lamps
---------------------------------------------------------------------------
local function lamps(folder: Instance, zc: number, zone: any)
	for _, s in { -1, 1 } do
		for z = zc - L / 2 + 26, zc + L / 2 - 26, 42 do
			local pos = V(s * 11.5, 0, z)
			if zone.decor == "meadow" then
				deco(folder, { Name = "LampPost", Size = V(0.7, 7, 0.7), Position = pos + V(0, 3.5, 0), Color = C(110, 75, 50), Material = Enum.Material.Wood })
				deco(folder, { Name = "LampArm", Size = V(2, 0.4, 0.4), Position = pos + V(-s * 0.8, 6.8, 0), Color = C(110, 75, 50), Material = Enum.Material.Wood })
				ball(folder, "Lantern", pos + V(-s * 1.6, 6, 0), 1.5, C(255, 225, 120), Enum.Material.Neon)
			elseif zone.decor == "candy" then
				for i = 0, 4 do
					deco(folder, { Name = "LampPost", Size = V(0.9, 1.4, 0.9), Position = pos + V(0, 0.7 + i * 1.4, 0), Color = if i % 2 == 0 then C(255, 120, 190) else WHITE })
				end
				ball(folder, "Lantern", pos + V(0, 8, 0), 2.4, C(255, 170, 220), Enum.Material.Neon)
			elseif zone.decor == "frost" then
				deco(folder, { Name = "LampPost", Size = V(0.8, 6, 0.8), Position = pos + V(0, 3, 0), Color = C(170, 200, 230), Material = Enum.Material.Ice })
				deco(folder, { Name = "Lantern", Size = V(1.6, 1.6, 1.6), CFrame = CFrame.new(pos + V(0, 7, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = C(150, 225, 255), Material = Enum.Material.Neon })
			elseif zone.decor == "lava" then
				deco(folder, { Name = "LampPost", Size = V(1.2, 5, 1.2), Position = pos + V(0, 2.5, 0), Color = C(55, 42, 42), Material = Enum.Material.Basalt })
				local bowl = cyl(folder, "Brazier", pos + V(0, 5.3, 0), 2.6, 0.8, C(40, 30, 32), Enum.Material.Basalt)
				local flame = ball(folder, "Lantern", pos + V(0, 6.1, 0), 1.4, C(255, 140, 40), Enum.Material.Neon)
				local fire = emitter(bowl, FIRE, C(255, 160, 50), 12, 2, 5, 0.8)
				fire.EmissionDirection = Enum.NormalId.Right
				fire.LightEmission = 1
				light(flame, C(255, 140, 50), 20, 1.6)
			else
				local orb = ball(folder, "Lantern", pos + V(0, 6, 0), 2, C(190, 130, 255), Enum.Material.Neon)
				cyl(folder, "LampBase", pos + V(0, 0.25, 0), 3, 0.5, C(60, 45, 120), Enum.Material.Metal)
				anim(orb, nil, nil, 0.7, 1.3)
				light(orb, C(170, 120, 255), 20, 1.4)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Landmarks: two per zone, off the path. Each returns the circle it occupies.
---------------------------------------------------------------------------
local function windmill(folder: Instance, pos: Vector3, facing: number): Reserved
	local model = Instance.new("Model")
	model.Name = "Windmill"
	local towerH = 24
	part(model, { Name = "Tower", Shape = Enum.PartType.Cylinder, Size = V(towerH, 11, 11), CFrame = CFrame.new(pos + V(0, towerH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(250, 240, 220), Material = Enum.Material.Plaster })
	cyl(model, "Band", pos + V(0, 8, 0), 11.4, 1.2, C(200, 90, 80))
	ell(model, "Roof", pos + V(0, towerH + 1.5, 0), V(13, 9, 13), C(200, 70, 70))
	deco(model, { Name = "Door", Size = V(3, 5, 0.6), Position = pos + V(facing * 5.4, 2.5, 0), Color = C(120, 80, 50), Material = Enum.Material.Wood })
	ball(model, "Window", pos + V(facing * 5.2, 13, 0), 2.4, C(150, 220, 255), Enum.Material.Glass)
	-- blades turn around the hub's X axis
	local blades = Instance.new("Model")
	blades.Name = "Blades"
	local hubPos = pos + V(facing * 6.6, towerH - 3, 0)
	local hub = deco(blades, { Name = "Hub", Shape = Enum.PartType.Ball, Size = V(2.4, 2.4, 2.4), Position = hubPos, Color = C(120, 80, 50), Material = Enum.Material.Wood })
	for i = 0, 3 do
		local rot = CFrame.new(hubPos) * CFrame.Angles(math.rad(i * 90), 0, 0)
		deco(blades, { Name = "Arm", Size = V(0.5, 15, 0.7), CFrame = rot * CFrame.new(0, 7.5, 0), Color = C(120, 80, 50), Material = Enum.Material.Wood })
		deco(blades, { Name = "Sail", Size = V(0.3, 10.5, 3.6), CFrame = rot * CFrame.new(0, 9, 1.9), Color = C(255, 250, 235), Material = Enum.Material.Fabric })
	end
	blades.PrimaryPart = hub
	blades.Parent = model
	anim(blades, V(1, 0, 0), 0.7)
	model.Parent = folder
	return { pos = pos, r = 18 }
end

local function duck(folder: Instance, pos: Vector3, yaw: number)
	local model = Instance.new("Model")
	model.Name = "Duck"
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local body = deco(model, { Name = "Body", Mesh = Enum.MeshType.Sphere, Size = V(1.8, 1.4, 2.4), CFrame = cf, Color = C(255, 225, 70) })
	deco(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = V(1.2, 1.2, 1.2), CFrame = cf * CFrame.new(0, 0.9, -0.9), Color = C(255, 225, 70) })
	deco(model, { Name = "Beak", Size = V(0.5, 0.25, 0.6), CFrame = cf * CFrame.new(0, 0.8, -1.6), Color = C(255, 150, 30) })
	model.PrimaryPart = body
	model.Parent = folder
	anim(model, V(0, 1, 0), 0.25, 0.12, 2.2)
end

local function pond(folder: Instance, pos: Vector3): Reserved
	local rng = Random.new(77)
	cyl(folder, "Pond", pos + V(0, 0.08, 0), 34, 0.3, C(90, 185, 245), Enum.Material.Glass, { Reflectance = 0.2 })
	cyl(folder, "PondShore", pos + V(0, 0.04, 0), 38, 0.24, C(225, 205, 150), Enum.Material.Sand)
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2 + 0.3
		rock(folder, pos + V(math.cos(a) * 17.5, 0, math.sin(a) * 17.5), rng)
	end
	for i = 1, 4 do
		local a = i * 1.9
		local p = pos + V(math.cos(a) * 8, 0.28, math.sin(a) * 8)
		cyl(folder, "LilyPad", p, 3.4, 0.12, C(70, 170, 80))
		if i % 2 == 0 then
			ell(folder, "Lily", p + V(0, 0.4, 0), V(1.4, 0.7, 1.4), C(255, 160, 200))
		end
	end
	duck(folder, pos + V(4, 0.75, -3), 0.6)
	duck(folder, pos + V(-6, 0.75, 5), 2.4)
	return { pos = pos, r = 22 }
end

local function cake(folder: Instance, pos: Vector3): Reserved
	local tiers = { { d = 26, h = 8, c = C(255, 150, 200) }, { d = 19, h = 7, c = C(255, 245, 225) }, { d = 12, h = 6, c = C(150, 235, 205) } }
	local y = 0
	for t, tier in tiers do
		part(folder, { Name = "CakeTier", Shape = Enum.PartType.Cylinder, Size = V(tier.h, tier.d, tier.d), CFrame = CFrame.new(pos + V(0, y + tier.h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = tier.c })
		cyl(folder, "Icing", pos + V(0, y + tier.h, 0), tier.d + 0.8, 0.9, WHITE)
		local drips = 10 - t * 2
		for i = 1, drips do
			local a = i / drips * math.pi * 2 + t
			ell(folder, "Drip", pos + V(math.cos(a) * tier.d / 2, y + tier.h - 0.9, math.sin(a) * tier.d / 2), V(2.2, 3 + (i % 3), 2.2), WHITE)
		end
		y += tier.h
	end
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		local p = pos + V(math.cos(a) * 3.6, y, math.sin(a) * 3.6)
		deco(folder, { Name = "Candle", Size = V(0.7, 3.4, 0.7), Position = p + V(0, 1.7, 0), Color = if i % 2 == 0 then C(120, 200, 255) else C(255, 210, 90) })
		local flame = ell(folder, "Flame", p + V(0, 4, 0), V(0.8, 1.4, 0.8), C(255, 200, 70), Enum.Material.Neon)
		anim(flame, nil, nil, 0.15, 6 + i)
	end
	ball(folder, "Cherry", pos + V(0, y + 1.6, 0), 3.2, C(230, 40, 70))
	return { pos = pos, r = 20 }
end

local function chocolatePond(folder: Instance, pos: Vector3): Reserved
	cyl(folder, "Chocolate", pos + V(0, 0.08, 0), 34, 0.3, C(110, 65, 40), nil, { Reflectance = 0.25 })
	cyl(folder, "Shore", pos + V(0, 0.04, 0), 38, 0.24, C(255, 245, 225))
	for i = 1, 6 do
		local a = i * 1.1
		local rr = 4 + (i % 3) * 4
		local m = cyl(folder, "Marshmallow", pos + V(math.cos(a) * rr, 0.9, math.sin(a) * rr), 2.6, 2, if i % 2 == 0 then C(255, 200, 225) else WHITE)
		anim(m, nil, nil, 0.18, 1.2 + i * 0.2)
	end
	-- chocolate fountain in the middle
	cyl(folder, "FountainBase", pos + V(0, 1.5, 0), 6, 3, C(255, 235, 245))
	cyl(folder, "FountainBowl", pos + V(0, 3.4, 0), 8, 0.8, C(255, 150, 200))
	cyl(folder, "FountainStem", pos + V(0, 5.8, 0), 2, 4, C(255, 235, 245))
	local top = ell(folder, "FountainTop", pos + V(0, 8.2, 0), V(4, 2, 4), C(110, 65, 40), nil, { Reflectance = 0.25 })
	local drip = emitter(top, SMOKE, C(120, 70, 45), 14, 0.9, 5, 0.9)
	drip.Acceleration = V(0, -30, 0)
	drip.SpreadAngle = Vector2.new(60, 60)
	drip.LightEmission = 0
	drip.EmissionDirection = Enum.NormalId.Top
	return { pos = pos, r = 22 }
end

local function igloo(folder: Instance, pos: Vector3, facing: number): Reserved
	local white = C(245, 250, 255)
	part(folder, { Name = "Igloo", Shape = Enum.PartType.Ball, Size = V(24, 24, 24), Position = pos + V(0, -1, 0), Color = white, Material = Enum.Material.Snow })
	for i = 1, 3 do
		cyl(folder, "IglooRing", pos + V(0, i * 2.6, 0), 24.3 * math.sqrt(1 - ((i * 2.6 + 1) / 12) ^ 2), 0.25, C(200, 225, 245), Enum.Material.Ice)
	end
	deco(folder, { Name = "Tunnel", Shape = Enum.PartType.Cylinder, Size = V(7, 8, 8), Position = pos + V(facing * 11.5, 2.2, 0), Color = white, Material = Enum.Material.Snow, CanCollide = true })
	deco(folder, { Name = "Door", Shape = Enum.PartType.Cylinder, Size = V(7.3, 5.4, 5.4), Position = pos + V(facing * 11.6, 1.8, 0), Color = C(40, 50, 75) })
	ball(folder, "Lantern", pos + V(facing * 15.4, 6.4, 0), 1.4, C(255, 215, 120), Enum.Material.Neon)
	return { pos = pos, r = 19 }
end

local function frozenLake(folder: Instance, pos: Vector3): Reserved
	local rng = Random.new(91)
	cyl(folder, "Lake", pos + V(0, 0.08, 0), 36, 0.3, C(170, 225, 255), Enum.Material.Ice, { Reflectance = 0.3, CanCollide = true })
	cyl(folder, "LakeShore", pos + V(0, 0.04, 0), 40, 0.24, C(250, 252, 255), Enum.Material.Snow)
	for i = 1, 5 do
		local a = i * 1.3
		deco(folder, { Name = "IceCrack", Size = V(0.25, 0.06, rng:NextNumber(6, 12)), CFrame = CFrame.new(pos + V(math.cos(a) * 6, 0.26, math.sin(a) * 6)) * CFrame.Angles(0, a * 2, 0), Color = WHITE, Material = Enum.Material.Neon, Transparency = 0.4 })
	end
	-- crystal spire on the far shore
	for i = 1, 5 do
		local h = 10 + i * 4
		deco(folder, { Name = "Spire", Size = V(3.2, h, 3.2), CFrame = CFrame.new(pos + V(14 + (i % 3) * 2.2, h * 0.42, 12 - i * 2)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)), Color = C(140, 210, 255), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = true })
	end
	return { pos = pos, r = 24 }
end

local function volcano(folder: Instance, pos: Vector3): Reserved
	local rock = C(58, 44, 44)
	local tiers = { { d = 34, h = 8 }, { d = 26, h = 7 }, { d = 18, h = 7 }, { d = 11, h = 6 } }
	local y = 0
	for i, t in tiers do
		part(folder, { Name = "Volcano", Shape = Enum.PartType.Cylinder, Size = V(t.h, t.d, t.d), CFrame = CFrame.new(pos + V(0, y + t.h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = if i % 2 == 0 then darken(rock, 0.12) else rock, Material = Enum.Material.Basalt })
		y += t.h
	end
	local crater = cyl(folder, "Crater", pos + V(0, y + 0.1, 0), 8.6, 0.5, C(255, 120, 25), Enum.Material.Neon)
	light(crater, C(255, 120, 40), 40, 2.5)
	local fire = emitter(crater, FIRE, C(255, 150, 40), 22, 4, 12, 1.4)
	fire.EmissionDirection = Enum.NormalId.Right
	fire.LightEmission = 1
	local smoke = emitter(crater, SMOKE, C(70, 55, 55), 5, 9, 9, 5)
	smoke.EmissionDirection = Enum.NormalId.Right
	smoke.LightEmission = 0
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 16) })
	-- lava running down two sides
	for i = 0, 1 do
		local yaw = i * 2.2 + 0.4
		deco(folder, { Name = "LavaFlow", Size = V(3, 0.5, 33), CFrame = CFrame.new(pos + V(0, y, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-58), 0, 0) * CFrame.new(0, 0.2, 17.5), Color = C(255, 120, 25), Material = Enum.Material.Neon })
	end
	return { pos = pos, r = 22 }
end

local function lavaLake(folder: Instance, pos: Vector3): Reserved
	local rng = Random.new(55)
	local lake = cyl(folder, "LavaLake", pos + V(0, 0.1, 0), 36, 0.4, C(255, 105, 20), Enum.Material.Neon)
	cyl(folder, "LavaShore", pos + V(0, 0.05, 0), 40, 0.34, C(45, 34, 36), Enum.Material.Basalt)
	light(lake, C(255, 120, 40), 36, 2)
	local bubbles = emitter(lake, FIRE, C(255, 170, 60), 14, 2.2, 5, 1.2)
	bubbles.EmissionDirection = Enum.NormalId.Right
	bubbles.LightEmission = 1
	for i = 1, 5 do
		local a = i * 1.4
		local rr = 5 + (i % 3) * 4
		rock(folder, pos + V(math.cos(a) * rr, 0.1, math.sin(a) * rr), rng, C(50, 38, 40), Enum.Material.Basalt)
	end
	return { pos = pos, r = 23 }
end

local function ufo(folder: Instance, pos: Vector3): Reserved
	local model = Instance.new("Model")
	model.Name = "Ufo"
	local y = 24
	local disc = deco(model, { Name = "Disc", Shape = Enum.PartType.Cylinder, Size = V(2.4, 22, 22), CFrame = CFrame.new(pos + V(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(170, 175, 200), Material = Enum.Material.Metal })
	deco(model, { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = V(1, 26, 26), CFrame = CFrame.new(pos + V(0, y - 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(110, 115, 150), Material = Enum.Material.Metal })
	deco(model, { Name = "Dome", Shape = Enum.PartType.Ball, Size = V(11, 11, 11), Position = pos + V(0, y + 1.6, 0), Color = C(130, 230, 255), Material = Enum.Material.Glass, Transparency = 0.35 })
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		deco(model, { Name = "Light", Shape = Enum.PartType.Ball, Size = V(1.6, 1.6, 1.6), Position = pos + V(math.cos(a) * 11.5, y - 0.9, math.sin(a) * 11.5), Color = if i % 2 == 0 then C(255, 230, 90) else C(255, 110, 200), Material = Enum.Material.Neon })
	end
	local beam = deco(model, { Name = "Beam", Shape = Enum.PartType.Cylinder, Size = V(y - 1, 10, 10), CFrame = CFrame.new(pos + V(0, (y - 1) / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(140, 255, 200), Material = Enum.Material.Neon, Transparency = 0.82 })
	light(beam, C(140, 255, 200), 26, 1.5)
	model.PrimaryPart = disc
	model.Parent = folder
	anim(model, V(1, 0, 0), 0.5, 1.2, 0.9) -- the disc's X axis points up (cylinder)
	cyl(folder, "LandingPad", pos + V(0, 0.1, 0), 14, 0.3, C(120, 220, 255), Enum.Material.Neon, { Transparency = 0.5 })
	return { pos = pos, r = 18 }
end

local function rocket(folder: Instance, pos: Vector3): Reserved
	cyl(folder, "Pad", pos + V(0, 0.4, 0), 22, 0.8, C(70, 60, 120), Enum.Material.Metal, { CanCollide = true })
	cyl(folder, "PadRing", pos + V(0, 0.85, 0), 18, 0.2, C(255, 210, 80), Enum.Material.Neon)
	part(folder, { Name = "RocketBody", Shape = Enum.PartType.Cylinder, Size = V(22, 8, 8), CFrame = CFrame.new(pos + V(0, 15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(245, 245, 250) })
	cyl(folder, "Stripe", pos + V(0, 20, 0), 8.2, 2, C(235, 60, 70))
	ell(folder, "Nose", pos + V(0, 27, 0), V(8, 11, 8), C(235, 60, 70))
	ball(folder, "Window", pos + V(0, 17, -3.6), 3, C(120, 220, 255), Enum.Material.Neon)
	for i = 0, 2 do
		local cf = CFrame.new(pos + V(0, 6.5, 0)) * CFrame.Angles(0, i * math.pi * 2 / 3, 0)
		deco(folder, { Name = "Fin", ClassName = "WedgePart", Size = V(1, 8, 5), CFrame = cf * CFrame.new(0, 0, 6.2), Color = C(235, 60, 70) })
	end
	local nozzle = cyl(folder, "Nozzle", pos + V(0, 3, 0), 5.5, 2.4, C(90, 90, 110), Enum.Material.Metal)
	local smoke = emitter(nozzle, SMOKE, C(230, 230, 245), 6, 3.5, 3, 2.2)
	smoke.EmissionDirection = Enum.NormalId.Left
	smoke.LightEmission = 0.2
	return { pos = pos, r = 15 }
end

local function portal(folder: Instance, pos: Vector3)
	local model = Instance.new("Model")
	model.Name = "Portal"
	local cy = 17
	local core = deco(model, { Name = "Core", Shape = Enum.PartType.Cylinder, Size = V(0.6, 24, 24), CFrame = CFrame.new(pos + V(0, cy, 0)) * CFrame.Angles(0, math.rad(90), 0), Color = C(150, 90, 255), Material = Enum.Material.Neon, Transparency = 0.55 })
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		deco(model, { Name = "RingSeg", Size = V(5.6, 2.4, 2.4), CFrame = CFrame.new(pos + V(math.cos(a) * 14, cy + math.sin(a) * 14, 0)) * CFrame.Angles(0, 0, a + math.pi / 2), Color = if i % 2 == 0 then C(120, 220, 255) else C(255, 120, 220), Material = Enum.Material.Neon })
	end
	model.PrimaryPart = core
	model.Parent = folder
	anim(model, V(1, 0, 0), 0.35)
	local swirl = emitter(core, SPARKLES, C(200, 160, 255), 18, 1.6, 6, 1.6)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.LightEmission = 1
	light(core, C(170, 120, 255), 40, 2)
	for _, s in { -1, 1 } do
		deco(folder, { Name = "PortalBase", Size = V(6, 4, 6), Position = pos + V(s * 13, 2, 0), Color = C(40, 32, 80), Material = Enum.Material.Metal, CanCollide = true })
	end
end

local function rockArch(folder: Instance, z: number)
	local rng = Random.new(66)
	local col = C(58, 44, 46)
	for _, s in { -1, 1 } do
		for i = 0, 2 do
			part(folder, { Name = "ArchRock", Size = V(7 - i, 7, 7 - i), CFrame = CFrame.new(s * (13.5 - i * 0.8), 3.5 + i * 6.6, z) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 1), rng:NextNumber(-0.12, 0.12)), Color = if i % 2 == 0 then col else darken(col, 0.15), Material = Enum.Material.Basalt, CastShadow = false })
		end
	end
	part(folder, { Name = "ArchTop", Size = V(34, 5.5, 7), CFrame = CFrame.new(0, 22.5, z) * CFrame.Angles(0, 0.05, 0.03), Color = col, Material = Enum.Material.Basalt, CastShadow = false })
	deco(folder, { Name = "ArchGlow", Size = V(30, 0.5, 1.2), Position = V(0, 19.6, z), Color = C(255, 120, 30), Material = Enum.Material.Neon })
end

-- Builds a zone's landmarks and returns the areas props must keep out of.
local function landmarks(folder: Instance, zone: any, zc: number): { Reserved }
	local a, b = V(-56, 0, zc + 64), V(56, 0, zc - 38)
	if zone.decor == "meadow" then
		return { windmill(folder, a, 1), pond(folder, b) }
	elseif zone.decor == "candy" then
		return { cake(folder, a), chocolatePond(folder, b) }
	elseif zone.decor == "frost" then
		return { igloo(folder, a, 1), frozenLake(folder, b) }
	elseif zone.decor == "lava" then
		rockArch(folder, zc - 62)
		return { volcano(folder, a), lavaLake(folder, b), { pos = V(-13.5, 0, zc - 62), r = 9 }, { pos = V(13.5, 0, zc - 62), r = 9 } }
	end
	portal(folder, V(0, 0, zc + L / 2 - 16))
	return { ufo(folder, a), rocket(folder, b) }
end

---------------------------------------------------------------------------
-- Horizon: the ground beyond the walls plus big silhouettes
---------------------------------------------------------------------------
local function horizon(folder: Instance, zone: any, zc: number)
	local i = zone.index
	local rng = Random.new(2000 + i)
	local ground = rgb(zone.ground)
	local mat = Palette.material(zone.groundMaterial)
	if zone.decor ~= "cosmic" then
		for _, s in { -1, 1 } do
			deco(folder, { Name = "Skirt", Size = V(SKIRT, 4, L), Position = V(s * (W / 2 + SKIRT / 2 + 2), -2.15, zc), Color = darken(ground, 0.08), Material = mat })
		end
	end
	for _, s in { -1, 1 } do
		local function at(minOut: number, maxOut: number): (number, number)
			return s * (W / 2 + rng:NextNumber(minOut, maxOut)), zc + rng:NextNumber(-L / 2 + 10, L / 2 - 10)
		end
		if zone.decor == "meadow" then
			local greens = { C(95, 185, 75), C(80, 170, 70), C(115, 200, 85) }
			for k = 1, 5 do
				local size = rng:NextNumber(90, 150)
				local x, z = at(40, 150)
				x += s * size * 0.3
				ball(folder, "Hill", V(x, -size * 0.3, z), size, greens[k % 3 + 1], Enum.Material.Grass)
				tree(folder, V(x + rng:NextNumber(-8, 8), size * 0.19, z + rng:NextNumber(-8, 8)), rng, 2.4)
			end
			for _ = 1, 3 do
				local x, z = at(200, 270)
				peak(folder, x, z, rng:NextNumber(90, 130), rng:NextNumber(0, 6), C(120, 150, 190), Enum.Material.Slate, WHITE, Enum.Material.Snow)
			end
		elseif zone.decor == "candy" then
			local bodies = { C(255, 170, 205), C(175, 235, 210), C(255, 225, 160), C(200, 170, 255) }
			for k = 1, 5 do
				local size = rng:NextNumber(80, 140)
				local x, z = at(40, 150)
				x += s * size * 0.3
				local c = V(x, -size * 0.3, z)
				ball(folder, "Hill", c, size, bodies[k % 4 + 1])
				ball(folder, "HillFrosting", c + V(0, size * 0.115, 0), size * 0.8, WHITE)
				ball(folder, "HillCherry", V(x, size * 0.2 + 4, z), 9, C(230, 40, 70))
			end
			for _ = 1, 4 do
				local x, z = at(18, 120)
				lollipop(folder, V(x, 0, z), rng, 3.2)
			end
			for _ = 1, 2 do
				local x, z = at(30, 110)
				candyCane(folder, V(x, 0, z), rng, 3)
			end
		elseif zone.decor == "frost" then
			for k = 1, 6 do
				local x, z = at(if k <= 3 then 70 else 170, if k <= 3 then 150 else 270)
				peak(folder, x, z, rng:NextNumber(70, 140), rng:NextNumber(0, 6), if k % 2 == 0 then C(150, 185, 225) else C(175, 205, 240), Enum.Material.Slate, C(250, 252, 255), Enum.Material.Snow)
			end
			for _ = 1, 7 do
				local x, z = at(14, 70)
				pine(folder, V(x, 0, z), rng, 2.2)
			end
			for _ = 1, 3 do
				local x, z = at(20, 80)
				crystal(folder, V(x, 0, z), rng, C(150, 210, 255), false, 3)
			end
		elseif zone.decor == "lava" then
			for k = 1, 5 do
				local x, z = at(if k <= 3 then 70 else 170, if k <= 3 then 150 else 260)
				local h = rng:NextNumber(70, 125)
				peak(folder, x, z, h, rng:NextNumber(0, 6), if k % 2 == 0 then C(52, 40, 42) else C(68, 50, 50), Enum.Material.Basalt, C(255, 115, 25), Enum.Material.Neon)
				if k <= 2 then
					local vent = deco(folder, { Name = "Vent", Size = V(4, 1, 4), Position = V(x, h + 2, z), Transparency = 1 })
					local smoke = emitter(vent, SMOKE, C(80, 60, 60), 2, 26, 12, 8)
					smoke.LightEmission = 0
					smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 40) })
				end
			end
			for _ = 1, 4 do
				local x, z = at(15, 120)
				deco(folder, { Name = "LavaRiver", Size = V(rng:NextNumber(8, 16), 0.3, rng:NextNumber(60, 120)), CFrame = CFrame.new(x, -0.05, z) * CFrame.Angles(0, rng:NextNumber(-0.7, 0.7), 0), Color = C(255, 110, 25), Material = Enum.Material.Neon })
			end
		else
			-- cosmic: the zone floats in the void. Big planets, moons and drifting rock.
			local cols = { C(255, 130, 200), C(120, 200, 255), C(255, 200, 110), C(150, 120, 255) }
			for k = 1, 3 do
				local size = rng:NextNumber(70, 150)
				local x, z = at(120, 260)
				local y = rng:NextNumber(-30, 90)
				local model = Instance.new("Model")
				model.Name = "GiantPlanet"
				local body = deco(model, { Name = "Planet", Shape = Enum.PartType.Ball, Size = V(size, size, size), Position = V(x, y, z), Color = cols[(k + (if s > 0 then 1 else 0)) % 4 + 1] })
				if k ~= 2 then
					deco(model, { Name = "Ring", Shape = Enum.PartType.Cylinder, Size = V(1.2, size * 1.9, size * 1.9), CFrame = CFrame.new(x, y, z) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, math.rad(90) + rng:NextNumber(-0.4, 0.4)), Color = C(255, 240, 220), Material = Enum.Material.Neon, Transparency = 0.45 })
				end
				model.PrimaryPart = body
				model.Parent = folder
				anim(model, V(0, 1, 0), 0.05)
			end
			for _ = 1, 9 do
				local x, z = at(10, 120)
				local sz = rng:NextNumber(10, 26)
				local rockPart = deco(folder, { Name = "Drift", Size = V(sz, sz * 0.6, sz * 0.8), CFrame = CFrame.new(x, rng:NextNumber(-25, 30), z) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)), Color = C(62, 52, 105), Material = Enum.Material.Slate })
				anim(rockPart, V(0.2, 1, 0.3).Unit, rng:NextNumber(0.05, 0.15), rng:NextNumber(1, 3), rng:NextNumber(0.2, 0.5))
			end
			-- underside of the floating island
			deco(folder, { Name = "Underside", Size = V(W * 0.5, 26, L * 0.9), Position = V(s * W * 0.22, -17, zc), Color = C(35, 28, 70), Material = Enum.Material.Slate })
		end
	end
end

---------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------
local function buildEgg(folder: Instance, egg: typeof(Config.Eggs[1]), pos: Vector3, index: number)
	local model = Instance.new("Model")
	model.Name = "Egg_" .. egg.id
	model:SetAttribute("EggId", egg.id)
	local spots = rgb(egg.spots)
	local shellColor = rgb(egg.color)
	part(model, { Name = "Step", Shape = Enum.PartType.Cylinder, Size = V(0.6, 15, 15), CFrame = CFrame.new(pos + V(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(176, 172, 196), Material = Enum.Material.Marble })
	local pedestal = part(model, { Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = V(1.4, 11, 11), CFrame = CFrame.new(pos + V(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(214, 210, 228), Material = Enum.Material.Marble })
	cyl(model, "Trim", pos + V(0, 1.7, 0), 11.4, 0.22, spots, Enum.Material.Neon)
	cyl(model, "StepTrim", pos + V(0, 0.62, 0), 15.4, 0.12, lighten(spots, 0.15))
	ell(model, "Cushion", pos + V(0, 2.2, 0), V(6.6, 1.6, 6.6), if egg.exclusive then C(120, 60, 200) else lighten(spots, 0.2), Enum.Material.Fabric)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local p = pos + V(math.cos(a) * 6.4, 0.6, math.sin(a) * 6.4)
		deco(model, { Name = "Post", Size = V(0.9, 2.6, 0.9), Position = p + V(0, 1.3, 0), Color = C(200, 196, 216), Material = Enum.Material.Marble })
		local orb = ball(model, "PostOrb", p + V(0, 3.2, 0), 1.3, spots, Enum.Material.Neon)
		anim(orb, nil, nil, 0.25, 2 + i * 0.3)
	end
	-- light pillar: visible from across the zone
	cyl(model, "Pillar", pos + V(0, 24, 0), 5.5, 44, lighten(spots, 0.2), Enum.Material.Neon, { Transparency = 0.9 })

	local shell = part(model, { Name = "Shell", Size = V(5.5, 7, 5.5), Mesh = Enum.MeshType.Sphere, Position = pos + V(0, 5.9, 0), Color = shellColor, CanCollide = true, CastShadow = false })
	shell:SetAttribute("Rest", shell.CFrame) -- the client spins the shell; this is where it rests
	local function weldToShell(p: BasePart)
		p:SetAttribute("Offset", shell.CFrame:ToObjectSpace(p.CFrame))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = shell
		weld.Part1 = p
		weld.Parent = p
	end
	local rng = Random.new(#egg.id * 97)
	if index % 2 == 0 or egg.exclusive then
		-- belted egg
		weldToShell(ell(model, "Spot", shell.Position, V(5.75, 1.1, 5.75), spots))
		weldToShell(ell(model, "Spot", shell.Position + V(0, 2.55, 0), V(3.3, 1.2, 3.3), spots))
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			weldToShell(ball(model, "Spot", shell.Position + V(math.cos(a) * 2.45, -1.7, math.sin(a) * 2.45), 0.9, lighten(spots, 0.35)))
		end
	else
		for i = 1, 8 do
			local a = i * 2.2
			local y = rng:NextNumber(-2, 2.2)
			local rr = 2.75 * math.sqrt(1 - (y / 3.5) ^ 2)
			weldToShell(ball(model, "Spot", shell.Position + V(math.cos(a) * rr, y, math.sin(a) * rr), rng:NextNumber(1, 1.6), spots))
		end
	end
	local sparkle = emitter(shell, SPARKLES, lighten(spots, 0.3), if egg.exclusive then 9 else 3, 1, 3, 1.4)
	sparkle.Name = "Sparkle"
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	light(shell, lighten(spots, 0.3), 12, 0.45)

	model.PrimaryPart = pedestal
	local price = if egg.exclusive then '<font color="#7CFF7C">ROBUX EXCLUSIVE</font>' else Format.abbrev(egg.price) .. " Taps"
	-- world text carries Loc* attributes; the client rewrites it in the player's language
	local eggLabel = label(shell, string.format('%s\n<font color="#FFE066">%s</font>', egg.name, price), UDim2.fromScale(12, 4.8), V(0, 6.6, 0), Color3.new(1, 1, 1), 170)
	;(eggLabel:FindFirstChild("Text") :: TextLabel):SetAttribute("LocEgg", egg.id)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EggPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = egg.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("EggId", egg.id)
	prompt.Parent = pedestal
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder
end

---------------------------------------------------------------------------
-- Leaderboard boards
---------------------------------------------------------------------------
local function buildBoard(folder: Instance, name: string, title: string, pos: Vector3, color: Color3): BasePart
	local board = part(folder, { Name = "Board_" .. name, Size = V(16, 20, 1), CFrame = CFrame.lookAt(pos, pos + V(0, 0, 1)), Color = C(40, 35, 60) })
	part(folder, { Name = "Frame", Size = V(17, 21, 0.8), CFrame = board.CFrame * CFrame.new(0, 0, 0.2), Color = color, Material = Enum.Material.Neon })
	for _, s in { -1, 1 } do
		part(folder, { Name = "Leg", Size = V(1, pos.Y, 1), Position = V(pos.X + 7 * s, pos.Y / 2 - 5, pos.Z + 0.5), Color = C(60, 50, 80) })
		ball(folder, "BoardOrb", V(pos.X + 8.5 * s, pos.Y + 11.4, pos.Z), 2.2, lighten(color, 0.3), Enum.Material.Neon)
	end
	deco(folder, { Name = "BoardRoof", Size = V(19, 1.4, 3), Position = V(pos.X, pos.Y + 11.2, pos.Z), Color = C(60, 50, 80) })
	local sg = Instance.new("SurfaceGui")
	sg.Name = "BoardGui"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 25
	sg.LightInfluence = 0
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0.12, 0)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.Text = title
	titleLabel:SetAttribute("LocKey", "world.board_" .. name:lower())
	titleLabel.Parent = sg
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.04, 0.13)
	list.Size = UDim2.fromScale(0.92, 0.85)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.005, 0)
	layout.Parent = list
	list.Parent = sg
	sg.Parent = board
	return board
end

---------------------------------------------------------------------------
-- Spawn plaza
---------------------------------------------------------------------------
local function balloons(folder: Instance, pos: Vector3, rng: Random)
	local cols = { C(255, 90, 110), C(90, 200, 255), C(255, 215, 70), C(140, 230, 120), C(190, 120, 255) }
	deco(folder, { Name = "BalloonPost", Size = V(0.6, 3, 0.6), Position = pos + V(0, 1.5, 0), Color = C(235, 235, 245) })
	for i = 1, 5 do
		local off = V(rng:NextNumber(-2.4, 2.4), rng:NextNumber(9, 14), rng:NextNumber(-2.4, 2.4))
		local model = Instance.new("Model")
		model.Name = "Balloon"
		local b = deco(model, { Name = "Balloon", Mesh = Enum.MeshType.Sphere, Size = V(3, 3.7, 3), Position = pos + off, Color = cols[i], Reflectance = 0.15 })
		local from = pos + V(0, 3, 0)
		local to = pos + off - V(0, 1.8, 0)
		deco(model, { Name = "String", Size = V(0.08, 0.08, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to), Color = WHITE })
		model.PrimaryPart = b
		model.Parent = folder
		anim(model, nil, nil, 0.35, 0.9 + i * 0.17)
	end
end

local function buildSpawn(world: Instance, info: WorldInfo)
	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "Spawn"
	spawnFolder.Parent = world
	local centre = V(0, 0, -75)
	local rng = Random.new(11)
	part(spawnFolder, { Name = "PlazaRing", Shape = Enum.PartType.Cylinder, Size = V(0.3, 46, 46), CFrame = CFrame.new(0, 0.15, -75) * CFrame.Angles(0, 0, math.rad(90)), Color = C(255, 200, 90), Material = Enum.Material.SmoothPlastic, CastShadow = false })
	part(spawnFolder, { Name = "Plaza", Shape = Enum.PartType.Cylinder, Size = V(0.4, 40, 40), CFrame = CFrame.new(0, 0.2, -75) * CFrame.Angles(0, 0, math.rad(90)), Color = C(245, 235, 210), Material = Enum.Material.Pebble, CastShadow = false })
	cyl(spawnFolder, "PlazaStar", centre + V(0, 0.42, 0), 22, 0.06, C(255, 170, 205))
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = V(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, -75) * CFrame.Angles(0, math.rad(180), 0)
	spawn.Color = C(255, 200, 80)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.CanTouch = false
	spawn.Parent = spawnFolder
	-- pillars with glowing orbs around the plaza (the way forward stays open)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + math.pi / 10
		if math.abs(math.sin(a)) < 0.92 then
			local p = centre + V(math.cos(a) * 25, 0, math.sin(a) * 25)
			if math.abs(p.X) > 9 then
				part(spawnFolder, { Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = V(5, 2.4, 2.4), CFrame = CFrame.new(p + V(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(250, 245, 235), Material = Enum.Material.Marble, CastShadow = false })
				cyl(spawnFolder, "PillarCap", p + V(0, 5.2, 0), 3.2, 0.5, C(255, 200, 90))
				local orb = ball(spawnFolder, "PillarOrb", p + V(0, 6.6, 0), 2, if i % 2 == 0 then C(255, 130, 200) else C(110, 210, 255), Enum.Material.Neon)
				anim(orb, nil, nil, 0.3, 1.4 + i * 0.1)
			end
		end
	end
	balloons(spawnFolder, centre + V(-27, 0, -14), rng)
	balloons(spawnFolder, centre + V(27, 0, -14), rng)
	-- flower ring
	for i = 1, 22 do
		local a = i / 22 * math.pi * 2
		if math.abs(math.cos(a)) > 0.3 then
			flower(spawnFolder, centre + V(math.cos(a) * 21.5, 0.2, math.sin(a) * 21.5), rng)
		end
	end
	-- title sign
	local signPos = V(0, 17, -104)
	local title = part(spawnFolder, { Name = "TitleSign", Size = V(44, 9, 1), CFrame = CFrame.lookAt(signPos, V(0, 17, 0)), Color = C(255, 120, 190) })
	surfaceText(title, Enum.NormalId.Front, "TAP PETS SIMULATOR", Color3.new(1, 1, 1))
	deco(spawnFolder, { Name = "SignFrame", Size = V(46, 11, 0.8), Position = signPos + V(0, 0, -0.25), Color = C(255, 215, 70), Material = Enum.Material.Neon })
	deco(spawnFolder, { Name = "SignBack", Size = V(48, 13, 0.6), Position = signPos + V(0, 0, -0.6), Color = C(120, 70, 190) })
	for _, s in { -1, 1 } do
		part(spawnFolder, { Name = "SignPost", Size = V(1.6, 12, 1.6), Position = V(s * 19, 6, -104.4), Color = C(120, 70, 190), CastShadow = false })
		ball(spawnFolder, "SignStar", V(s * 24.5, 24, -104), 3, C(255, 225, 90), Enum.Material.Neon)
	end
	-- welcome arch over the path
	for _, s in { -1, 1 } do
		part(spawnFolder, { Name = "ArchPost", Size = V(1.6, 15, 1.6), Position = V(s * 10.5, 7.5, -46), Color = WHITE, CastShadow = false })
		ball(spawnFolder, "ArchOrb", V(s * 10.5, 15.8, -46), 2.6, C(255, 200, 80), Enum.Material.Neon)
	end
	local flagCols = { C(255, 90, 110), C(255, 215, 70), C(140, 230, 120), C(90, 200, 255), C(190, 120, 255) }
	for i = 0, 8 do
		local x = -9 + i * 2.25
		local sag = 1.6 * (1 - ((i - 4) / 4) ^ 2)
		deco(spawnFolder, { Name = "Flag", ClassName = "WedgePart", Size = V(0.2, 2, 1.6), CFrame = CFrame.new(x, 13.2 - sag, -46) * CFrame.Angles(0, math.rad(90), math.rad(180)), Color = flagCols[i % #flagCols + 1] })
	end
	deco(spawnFolder, { Name = "FlagLine", Size = V(21, 0.15, 0.15), Position = V(0, 13.6, -46), Color = WHITE })

	info.boards.taps = buildBoard(spawnFolder, "Taps", "TOP TAPPERS", V(-42, 14, -100), C(90, 200, 255))
	info.boards.rebirths = buildBoard(spawnFolder, "Rebirths", "TOP REBIRTHS", V(42, 14, -100), C(255, 200, 60))
end

---------------------------------------------------------------------------
-- Pet Park: 12 plots behind the spawn plaza (2 rows of 6 along an aisle). The server hands
-- one to each player (Services/Plots); clients put the owner's pets on the pedestals.
---------------------------------------------------------------------------
local PLOT_COLORS = { C(255, 120, 150), C(255, 170, 70), C(255, 215, 80), C(130, 220, 120), C(90, 200, 255), C(175, 130, 255) }

local function buildPlot(parent: Instance, index: number, centre: Vector3, front: number): Plot
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("OwnerName", "")
	-- pets look down the plot towards the aisle (front = +1: towards +Z)
	model:SetAttribute("Facing", if front > 0 then math.pi else 0)
	local accent = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local pad = part(model, { Name = "Pad", Size = V(24, 0.4, 22), Position = centre + V(0, 0.2, 0), Color = C(250, 242, 220), Material = Enum.Material.Sand, CastShadow = false })
	deco(model, { Name = "PadRim", Size = V(25.4, 0.2, 23.4), Position = centre + V(0, 0.1, 0), Color = accent })
	local slot = 0
	for row = 0, 1 do
		for col = -1, 1 do
			slot += 1
			local p = centre + V(col * 7.4, 1, -front * (row * 7 - 1.5))
			part(model, { Name = "Pedestal" .. slot, Shape = Enum.PartType.Cylinder, Size = V(1.2, 4, 4), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)), Color = if row == 0 then lighten(accent, 0.55) else lighten(accent, 0.35), CastShadow = false })
		end
	end
	-- chest at the front, facing the aisle
	local chestPos = centre + V(6.5, 0, front * 8.2)
	local chest = part(model, { Name = "Chest", Size = V(4.4, 2.6, 3), Position = chestPos + V(0, 1.7, 0), Color = C(150, 95, 55), Material = Enum.Material.Wood, CastShadow = false })
	deco(model, { Name = "ChestLid", Size = V(4.7, 0.9, 3.3), Position = chestPos + V(0, 3.4, 0), Color = C(255, 205, 70) })
	deco(model, { Name = "ChestLock", Size = V(0.9, 1.1, 0.4), Position = chestPos + V(0, 2.6, front * 1.6), Color = C(255, 235, 140) })
	local glow = ball(model, "ChestGlow", chestPos + V(0, 4.6, 0), 1.6, C(255, 230, 110), Enum.Material.Neon, { Transparency = 1 })
	anim(glow, nil, nil, 0.3, 2.4)
	local chestLabel = label(chest, "", UDim2.fromScale(11, 2.6), V(0, 5.2, 0), Color3.new(1, 1, 1), 70)
	;(chestLabel:FindFirstChild("Text") :: TextLabel).Name = "ChestText"
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Pet chest"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Chest", index)
	prompt.Parent = chest
	-- name sign
	local signPos = centre + V(-7, 0, front * 9.4)
	deco(model, { Name = "SignPost", Size = V(0.6, 5, 0.6), Position = signPos + V(0, 2.5, 0), Color = C(120, 80, 50), Material = Enum.Material.Wood })
	local board = part(model, { Name = "SignBoard", Size = V(9, 2.6, 0.5), Position = signPos + V(0, 5.4, 0), Color = darken(accent, 0.2), CanCollide = false, CastShadow = false })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		surfaceText(board, face, "", Color3.new(1, 1, 1)).Name = "OwnerText"
	end
	model.PrimaryPart = pad
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent
	return { model = model, chest = chest, spawn = CFrame.lookAt(centre + V(0, 4, front * 15), centre + V(0, 4, 0)) }
end

local function buildPark(world: Instance, info: WorldInfo, zStart: number)
	local park = Instance.new("Folder")
	park.Name = "Park"
	park.Parent = world
	local dressing = Instance.new("Folder")
	dressing.Name = "ParkDressing"
	dressing.Parent = world
	local zc = zStart - PARK_DEPTH / 2
	part(dressing, { Name = "Ground", Size = V(W, 4, PARK_DEPTH), Position = V(0, -2, zc), Color = C(125, 205, 95), Material = Enum.Material.Grass })
	local aisleZ = zc
	deco(dressing, { Name = "Aisle", Size = V(W - 8, 0.2, 9), Position = V(0, 0.1, aisleZ), Color = C(235, 215, 160), Material = Enum.Material.Sand })
	deco(dressing, { Name = "Walk", Size = V(12, 0.2, PARK_DEPTH / 2 + 4), Position = V(0, 0.1, (zStart + aisleZ) / 2 + 2), Color = C(235, 215, 160), Material = Enum.Material.Sand })
	for _, s in { -1, 1 } do
		part(dressing, { Name = "InvisibleWall", Size = V(2, WALL_H, PARK_DEPTH), Position = V(s * (W / 2 + 1), WALL_H / 2, zc), Transparency = 1 })
		deco(dressing, { Name = "Hedge", Size = V(5, 4.4, PARK_DEPTH), Position = V(s * (W / 2 + 3.5), 2.2, zc), Color = C(55, 140, 60), Material = Enum.Material.Grass })
	end
	-- entrance arch, seen from the plaza
	for _, s in { -1, 1 } do
		part(dressing, { Name = "ArchPost", Size = V(1.8, 13, 1.8), Position = V(s * 9, 6.5, zStart - 2), Color = C(250, 245, 235), CastShadow = false })
		ball(dressing, "ArchOrb", V(s * 9, 13.9, zStart - 2), 2.6, C(255, 140, 200), Enum.Material.Neon)
	end
	local beam = part(dressing, { Name = "ParkSign", Size = V(22, 4, 1), Position = V(0, 12.5, zStart - 2), Color = C(120, 70, 190), CanCollide = false, CastShadow = false })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		surfaceText(beam, face, "PET PARK", C(255, 225, 90)):SetAttribute("LocKey", "world.park")
	end
	deco(dressing, { Name = "ParkSignFrame", Size = V(23, 5, 0.6), Position = V(0, 12.5, zStart - 2), Color = C(255, 215, 70), Material = Enum.Material.Neon })
	local index = 0
	for row = 0, 1 do
		local front = if row == 0 then -1 else 1 -- both rows face the aisle
		for col = 0, 5 do
			index += 1
			local x = -70 + col * 28
			local z = aisleZ - front * 17
			table.insert(info.plots, buildPlot(park, index, V(x, 0, z), front))
		end
	end
end

---------------------------------------------------------------------------
-- Gates
---------------------------------------------------------------------------
local function buildGate(gatesFolder: Instance, zone: any, zc: number): BasePart
	local i = zone.index
	local gz = zc - L / 2
	local gate = Instance.new("Model")
	gate.Name = "Gate" .. i
	local wall = rgb(zone.wall)
	local accent = rgb(zone.path)
	local glow = if zone.decor == "candy" then C(255, 245, 190) elseif zone.decor == "frost" then C(150, 225, 255) elseif zone.decor == "lava" then C(255, 120, 30) else C(190, 120, 255)
	local sideW = (W - GATE_W) / 2
	for _, s in { -1, 1 } do
		local x = s * (GATE_W / 2 + sideW / 2)
		part(gate, { Name = "Wall", Size = V(sideW, GATE_H, 3), Position = V(x, GATE_H / 2, gz), Color = wall, Material = Enum.Material.Brick })
		deco(gate, { Name = "WallTop", Size = V(sideW, 1.4, 4), Position = V(x, GATE_H + 0.7, gz), Color = lighten(wall, 0.25) })
		deco(gate, { Name = "WallBase", Size = V(sideW, 1.6, 3.8), Position = V(x, 0.8, gz), Color = darken(wall, 0.22) })
		for k = 0, 5 do
			deco(gate, { Name = "Merlon", Size = V(4, 2.2, 3.4), Position = V(s * (GATE_W / 2 + 10 + k * 11.5), GATE_H + 2.5, gz), Color = lighten(wall, 0.12) })
		end
		local px = s * (GATE_W / 2 + 2)
		part(gate, { Name = "Pillar", Size = V(4, GATE_H + 6, 4), Position = V(px, (GATE_H + 6) / 2, gz), Color = accent, Material = Palette.material(zone.pathMaterial) })
		deco(gate, { Name = "PillarCap", Size = V(5.6, 1.4, 5.6), Position = V(px, GATE_H + 6.7, gz), Color = lighten(wall, 0.2) })
		local orb = ball(gate, "PillarOrb", V(px, GATE_H + 9.4, gz), 3.4, glow, Enum.Material.Neon)
		anim(orb, nil, nil, 0.3, 1.5)
		if i >= 4 then
			light(orb, glow, 22, 1.4)
		end
		for _, zo in { -2.15, 2.15 } do
			deco(gate, { Name = "PillarStrip", Size = V(0.6, GATE_H + 4, 0.3), Position = V(px - s * 1.4, (GATE_H + 4) / 2, gz + zo), Color = glow, Material = Enum.Material.Neon })
		end
	end
	local arch = part(gate, { Name = "Arch", Size = V(GATE_W + 8, 5, 4), Position = V(0, GATE_H + 3.5, gz), Color = wall })
	surfaceText(arch, Enum.NormalId.Front, zone.name:upper(), Color3.new(1, 1, 1)):SetAttribute("LocZone", i)
	surfaceText(arch, Enum.NormalId.Back, zone.name:upper(), Color3.new(1, 1, 1)):SetAttribute("LocZone", i)
	deco(gate, { Name = "ArchTrim", Size = V(GATE_W + 9, 0.6, 4.6), Position = V(0, GATE_H + 6.3, gz), Color = glow, Material = Enum.Material.Neon })
	deco(gate, { Name = "ArchTrim", Size = V(GATE_W + 9, 0.6, 4.6), Position = V(0, GATE_H + 0.7, gz), Color = glow, Material = Enum.Material.Neon })
	part(gate, { Name = "InvisibleTop", Size = V(W, WALL_H - GATE_H, 3), Position = V(0, GATE_H + (WALL_H - GATE_H) / 2, gz), Transparency = 1 })
	local barrier = part(gate, {
		Name = "Barrier",
		Size = V(GATE_W, GATE_H, 1.5),
		Position = V(0, GATE_H / 2, gz),
		Color = accent,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
	})
	barrier:SetAttribute("Zone", i)
	surfaceText(barrier, Enum.NormalId.Front, string.format("LOCKED\n%s Taps", Format.abbrev(zone.cost)), C(255, 230, 90)):SetAttribute("LocGate", i)
	local burst = emitter(barrier, SPARKLES, glow, 0, 2, 14, 1.2)
	burst.Name = "Unlock"
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.LightEmission = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatePrompt"
	prompt.ActionText = "Unlock (" .. Format.abbrev(zone.cost) .. " Taps)"
	prompt.ObjectText = zone.name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Zone", i)
	prompt.Parent = barrier
	gate.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	gate.Parent = gatesFolder
	return barrier
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function WorldBuilder.build(): WorldInfo
	local info: WorldInfo = { plots = {}, eggPositions = {}, zoneSpawns = {}, gates = {}, boards = {} }

	local old = Workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = "World"
	local eggsFolder = Instance.new("Folder")
	eggsFolder.Name = "Eggs"
	eggsFolder.Parent = world
	local gatesFolder = Instance.new("Folder")
	gatesFolder.Name = "Gates"
	gatesFolder.Parent = world

	local nZones = #Config.Zones
	local zStart = -L / 2
	local zEnd = zoneCenter(nZones) + L / 2

	for _, zone in Config.Zones do
		local i = zone.index
		local folder = Instance.new("Folder")
		folder.Name = "Zone" .. i .. "_" .. zone.id
		folder.Parent = world
		local zc = zoneCenter(i)
		local pathColor = rgb(zone.path)
		part(folder, { Name = "Ground", Size = V(W, 4, L), Position = V(0, -2, zc), Color = rgb(zone.ground), Material = Palette.material(zone.groundMaterial) })
		part(folder, { Name = "Path", Size = V(16, 0.2, L), Position = V(0, 0.1, zc), Color = pathColor, Material = Palette.material(zone.pathMaterial), CanCollide = false, CastShadow = false })
		for _, s in { -1, 1 } do
			deco(folder, { Name = "PathEdge", Size = V(1.2, 0.3, L), Position = V(s * 8.6, 0.15, zc), Color = if zone.decor == "cosmic" then C(120, 220, 255) else darken(pathColor, 0.18), Material = if zone.decor == "cosmic" or zone.decor == "lava" then Enum.Material.Neon else Enum.Material.SmoothPlastic })
			part(folder, { Name = "InvisibleWall", Size = V(2, WALL_H, L), Position = V(s * (W / 2 + 1), WALL_H / 2, zc), Transparency = 1 })
		end
		if zone.decor == "candy" then
			-- polka dots on the candy floor
			local dots = Random.new(515)
			local cols = { C(255, 205, 230), C(255, 240, 250), C(255, 160, 205) }
			for k = 1, 16 do
				local x = dots:NextNumber(14, W / 2 - 12) * (if k % 2 == 0 then 1 else -1)
				cyl(folder, "Dot", V(x, 0.04, zc + dots:NextNumber(-L / 2 + 12, L / 2 - 12)), dots:NextNumber(10, 22), 0.08, cols[k % 3 + 1])
			end
		end

		-- zone spawn (teleport target)
		local spawnZ = if i == 1 then -75 else zc - L / 2 + 22
		info.zoneSpawns[i] = CFrame.new(0, 4, spawnZ) * CFrame.Angles(0, math.rad(180), 0)

		local border = BORDER[zone.decor]
		if border then
			local borderFolder = Instance.new("Folder")
			borderFolder.Name = "Border"
			borderFolder.Parent = folder
			border(borderFolder, zc)
		end
		-- the horizon is the backdrop: always loaded, like a skybox (everything else streams)
		local scenery = Instance.new("Model")
		scenery.Name = "Horizon"
		scenery.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		scenery.Parent = folder
		horizon(scenery, zone, zc)
		local lampFolder = Instance.new("Folder")
		lampFolder.Name = "Lamps"
		lampFolder.Parent = folder
		lamps(lampFolder, zc, zone)
		local landmarkFolder = Instance.new("Folder")
		landmarkFolder.Name = "Landmarks"
		landmarkFolder.Parent = folder
		local reserved = landmarks(landmarkFolder, zone, zc)

		-- props (deterministic)
		local rng = Random.new(1000 + i)
		local decoFolder = Instance.new("Folder")
		decoFolder.Name = "Decor"
		decoFolder.Parent = folder
		for _, egg in Config.Eggs do
			if egg.zone == i or (i == 1 and egg.zone == 0) then
				table.insert(reserved, { pos = V(egg.offsetX, 0, zc + egg.offsetZ), r = 17 })
			end
		end
		for _, entry in DECOR[zone.decor] or ({} :: { { fn: Deco, count: number } }) do
			local placed, tries = 0, 0
			while placed < entry.count and tries < entry.count * 20 do
				tries += 1
				local x = rng:NextNumber(-W / 2 + 8, W / 2 - 8)
				local z = rng:NextNumber(zc - L / 2 + 14, zc + L / 2 - 14)
				local pos = V(x, 0, z)
				local ok = math.abs(x) > 14
				for _, e in reserved do
					if (e.pos - pos).Magnitude < e.r then
						ok = false
					end
				end
				if i == 1 and z < -42 and math.abs(x) < 44 then
					ok = false -- keep the spawn plaza clear
				end
				if ok then
					entry.fn(decoFolder, pos, rng)
					placed += 1
				end
			end
		end

		if i > 1 then
			info.gates[i] = buildGate(gatesFolder, zone, zc)
		end

		for index, egg in Config.Eggs do
			local ez = if egg.zone == 0 then 1 else egg.zone
			if ez == i then
				local pos = V(egg.offsetX, 0, zc + egg.offsetZ)
				info.eggPositions[egg.id] = pos + V(0, 4, 0)
				buildEgg(eggsFolder, egg, pos, index)
			end
		end
	end

	-- End walls + the ground behind them
	local first = Config.Zones[1]
	local parkEnd = zStart - PARK_DEPTH
	part(world, { Name = "BackWall", Size = V(W, WALL_H, 2), Position = V(0, WALL_H / 2, parkEnd - 1), Transparency = 1 })
	deco(world, { Name = "BackHedge", Size = V(W + 10, 4.4, 5), Position = V(0, 2.2, parkEnd - 3.5), Color = C(55, 140, 60), Material = Enum.Material.Grass })
	deco(world, { Name = "BackSkirt", Size = V(W + SKIRT * 2 + 4, 4, 240), Position = V(0, -2.15, zStart - 120), Color = darken(rgb(first.ground), 0.08), Material = Palette.material(first.groundMaterial) })
	local backRng = Random.new(808)
	for k = 1, 6 do
		local size = backRng:NextNumber(90, 150)
		local x = -260 + k * 75 + backRng:NextNumber(-15, 15)
		ball(world, "Hill", V(x, -size * 0.3, parkEnd - 60 - size * 0.3 - backRng:NextNumber(0, 50)), size, if k % 2 == 0 then C(95, 185, 75) else C(80, 170, 70), Enum.Material.Grass)
	end
	for k = 1, 4 do
		peak(world, -230 + k * 95, parkEnd - 215, backRng:NextNumber(100, 150), backRng:NextNumber(0, 6), C(120, 150, 190), Enum.Material.Slate, WHITE, Enum.Material.Snow)
	end
	part(world, { Name = "EndWall", Size = V(W, WALL_H, 2), Position = V(0, WALL_H / 2, zEnd + 1), Transparency = 1 })
	deco(world, { Name = "EndEdge", Size = V(W, 0.4, 1.6), Position = V(0, 0.15, zEnd - 0.8), Color = C(130, 90, 255), Material = Enum.Material.Neon })

	buildSpawn(world, info)
	buildPark(world, info, zStart)

	world.Parent = Workspace

	-- Lighting (the client retunes it per zone: WorldFx)
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 2.4
	Lighting.Ambient = C(120, 115, 130)
	Lighting.OutdoorAmbient = C(150, 155, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.28
		atm.Offset = 0.1
		atm.Haze = 1.2
		atm.Glare = 0.2
		atm.Color = C(205, 225, 255)
		atm.Decay = C(150, 190, 255)
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.45
		bloom.Size = 22
		bloom.Threshold = 1.5
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local rays = Instance.new("SunRaysEffect")
		rays.Intensity = 0.07
		rays.Spread = 0.7
		rays.Parent = Lighting
	end
	-- a soft far blur: the horizon props melt into the sky and the play area reads sharper
	-- (the client switches it off on the lite profile, like bloom and sun rays)
	if not Lighting:FindFirstChildOfClass("DepthOfFieldEffect") then
		local dof = Instance.new("DepthOfFieldEffect")
		dof.FarIntensity = 0.12
		dof.NearIntensity = 0
		dof.FocusDistance = 70
		dof.InFocusRadius = 90
		dof.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.StarCount = 5000
		sky.SunAngularSize = 16
		sky.MoonAngularSize = 14
		sky.Parent = Lighting
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.45
		clouds.Color = WHITE
		clouds.Parent = terrain
	end

	return info
end

function WorldBuilder.zoneAt(z: number): number
	return math.clamp(math.floor((z + L / 2) / L) + 1, 1, #Config.Zones)
end

return WorldBuilder
