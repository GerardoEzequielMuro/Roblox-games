--!strict
-- The look of the world on this client:
--   * SkyRig: a painted space sky that follows the camera: an inside-out dome, a horizon
--     band, stars, nebula clouds and far planets. It is geometry with baked colours, so the
--     sky is there at graphics quality 1 too (no Atmosphere, no skybox texture needed).
--     In lite mode the rig is built small enough to sit inside the short draw distance.
--   * per-galaxy lighting (clock, ambient, sun colour) and, as extras, bloom / colour grade
--   * "PcAnim" props built by the server (bob, spin, orbit, pulse)
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Shared.Layout)
local Themes = require(ReplicatedStorage.Shared.Themes)
local Quality = require(script.Parent.Quality)

local WorldFx = {}

local player = Players.LocalPlayer
WorldFx.zone = nil :: number? -- galaxy the character stands in (nil = arena / nowhere)
WorldFx.place = "" -- "zone1".."zone6" | "arena" | ""
local placeChanged = Instance.new("BindableEvent")
WorldFx.PlaceChanged = placeChanged.Event

local NEON = Enum.Material.Neon
local rig: Model? = nil
local rigRoot: Part? = nil
local rigKey = ""

local function skyPart(parent: Instance, root: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, transparency: number, meshType: Enum.MeshType?, meshScale: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if meshType then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = meshType
		mesh.Scale = meshScale or Vector3.one
		mesh.Parent = p
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

-- Builds the sky for a theme. R = dome radius.
local function buildRig(theme: Themes.Theme, R: number, lite: boolean): Model
	local model = Instance.new("Model")
	model.Name = "SkyRig"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	rigRoot = root

	-- inside-out dome (negative mesh scale flips the faces towards the camera)
	skyPart(model, root, "Dome", Vector3.new(2, 2, 2), CFrame.new(), theme.skyTop, NEON, 0, Enum.MeshType.Sphere, Vector3.new(-R, -R, -R))
	-- horizon: two inside-out bands, the painted gradient between sky and "ground glow"
	local panels = 24
	local bands = {
		{ r = 0.97, y = -0.05, h = 0.5, color = theme.skyTop:Lerp(theme.skyHorizon, 0.4) },
		{ r = 0.955, y = -0.12, h = 0.3, color = theme.skyTop:Lerp(theme.skyHorizon, 0.75) },
		{ r = 0.94, y = -0.2, h = 0.22, color = theme.skyHorizon },
		{ r = 0.925, y = -0.3, h = 0.16, color = theme.skyHorizon:Lerp(Color3.new(1, 1, 1), 0.3) },
	}
	for _, b in bands do
		local width = 2 * math.pi * R * b.r / panels * 1.04
		for i = 1, panels do
			local a = i / panels * math.pi * 2
			local pos = Vector3.new(math.cos(a) * R * b.r, R * b.y, math.sin(a) * R * b.r)
			skyPart(model, root, "Horizon", Vector3.new(width, R * b.h, R * 0.004), CFrame.lookAt(pos, Vector3.new(0, R * b.y, 0)), b.color, NEON, 0)
		end
	end

	local rand = Random.new(7)
	-- stars
	local starCount = if lite then 46 else 110
	for i = 1, starCount do
		local y = rand:NextNumber(-0.25, 1)
		local a = rand:NextNumber(0, math.pi * 2)
		local rad = math.sqrt(math.max(0, 1 - y * y))
		local dir = Vector3.new(math.cos(a) * rad, y, math.sin(a) * rad)
		local s = R * rand:NextNumber(0.004, 0.011) * (if i % 9 == 0 then 2.2 else 1)
		local c = if i % 5 == 0 then theme.accent:Lerp(Color3.new(1, 1, 1), 0.5) elseif i % 7 == 0 then theme.accent2:Lerp(Color3.new(1, 1, 1), 0.5) else Color3.new(1, 1, 1)
		local star = skyPart(model, root, "Star", Vector3.new(s, s, s), CFrame.new(dir * R * 0.93) * CFrame.Angles(0.8, a, 0.8), c, NEON, 0)
		if i % 9 == 0 then
			-- a four-point sparkle: two thin crossed bars
			skyPart(model, root, "StarRay", Vector3.new(s * 4, s * 0.3, s * 0.3), CFrame.lookAt(dir * R * 0.93, Vector3.zero), c, NEON, 0.2)
			skyPart(model, root, "StarRay", Vector3.new(s * 0.3, s * 4, s * 0.3), CFrame.lookAt(dir * R * 0.93, Vector3.zero), c, NEON, 0.2)
			star.Shape = Enum.PartType.Ball
		end
	end
	-- nebula clouds: big soft blobs in the galaxy's colours
	local blobs = if lite then 5 else 9
	for i = 1, blobs do
		local a = i / blobs * math.pi * 2 + 0.7
		local y = rand:NextNumber(0.02, 0.5)
		local dir = Vector3.new(math.cos(a), y, math.sin(a)).Unit
		local c = theme.nebula[(i - 1) % #theme.nebula + 1]
		local w = R * rand:NextNumber(0.34, 0.6)
		skyPart(model, root, "Nebula", Vector3.new(2, 2, 2), CFrame.lookAt(dir * R * 0.86, Vector3.zero) * CFrame.Angles(0, 0, rand:NextNumber(-0.6, 0.6)), c, NEON, 0.72, Enum.MeshType.Sphere, Vector3.new(w, w * rand:NextNumber(0.3, 0.55), w * 0.1))
		if not lite then
			skyPart(model, root, "NebulaCore", Vector3.new(2, 2, 2), CFrame.lookAt(dir * R * 0.85, Vector3.zero) * CFrame.Angles(0, 0, rand:NextNumber(-0.6, 0.6)), c:Lerp(Color3.new(1, 1, 1), 0.35), NEON, 0.8, Enum.MeshType.Sphere, Vector3.new(w * 0.5, w * 0.2, w * 0.08))
		end
	end
	-- far planets with a lit side, bands and rings
	for i, fp in theme.farPlanets do
		local a = if i == 1 then 0.5 else 3.6
		local dir = Vector3.new(math.cos(a), if i == 1 then 0.32 else 0.5, math.sin(a)).Unit
		local size = fp.size / 1400 * R * 2.2
		local pos = dir * R * 0.78
		local planet = skyPart(model, root, "FarPlanet", Vector3.new(size, size, size), CFrame.new(pos), fp.color, Enum.Material.SmoothPlastic, 0)
		planet.Shape = Enum.PartType.Ball
		skyPart(model, root, "FarBand", Vector3.new(size * 0.16, size * 1.01, size * 1.01), CFrame.new(pos) * CFrame.Angles(0.3, 0, math.rad(90) + 0.2), fp.color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.SmoothPlastic, 0).Shape = Enum.PartType.Cylinder
		skyPart(model, root, "FarBand", Vector3.new(size * 0.1, size * 0.93, size * 0.93), CFrame.new(pos + Vector3.new(0, size * 0.28, 0)) * CFrame.Angles(0.3, 0, math.rad(90) + 0.2), fp.color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.SmoothPlastic, 0).Shape = Enum.PartType.Cylinder
		if fp.ring then
			local ring = skyPart(model, root, "FarRing", Vector3.new(size * 0.04, size * 2.1, size * 2.1), CFrame.new(pos) * CFrame.Angles(0.5, 0.3, math.rad(90) + 0.35), fp.ring, NEON, 0.25)
			ring.Shape = Enum.PartType.Cylinder
		end
	end
	return model
end

local function applyLighting(theme: Themes.Theme)
	Lighting.ClockTime = theme.clock
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = theme.brightness
	Lighting.Ambient = theme.ambient
	Lighting.OutdoorAmbient = theme.ambient
	Lighting.ColorShift_Top = theme.sun
	Lighting.ColorShift_Bottom = theme.skyHorizon
	Lighting.FogColor = theme.skyHorizon
	Lighting.FogStart = 900
	Lighting.FogEnd = 4000
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.55 -- Foil / Glacier / metal pick up the sky
	-- extras: only when the device can show them
	local bloom = Lighting:FindFirstChild("PcBloom") :: BloomEffect?
	if not bloom then
		local b = Instance.new("BloomEffect")
		b.Name = "PcBloom"
		b.Intensity = 0.55
		b.Size = 26
		b.Threshold = 1.35 -- neon (planet cores, pads, stars) glows; lit plastic does not
		b.Parent = Lighting
		bloom = b
	end
	local rays = Lighting:FindFirstChild("PcRays") :: SunRaysEffect?
	if not rays then
		local r = Instance.new("SunRaysEffect")
		r.Name = "PcRays"
		r.Intensity = 0.06
		r.Spread = 0.8
		r.Parent = Lighting
		rays = r
	end
	if rays then
		rays.Enabled = not Quality.lite
	end
	local grade = Lighting:FindFirstChild("PcGrade") :: ColorCorrectionEffect?
	if not grade then
		local g = Instance.new("ColorCorrectionEffect")
		g.Name = "PcGrade"
		g.Parent = Lighting
		grade = g
	end
	if bloom and grade then
		bloom.Enabled = not Quality.lite
		grade.Enabled = not Quality.lite
		grade.Saturation = 0.18
		grade.Contrast = 0.1
		grade.Brightness = 0.02
		grade.TintColor = theme.sun:Lerp(Color3.new(1, 1, 1), 0.7)
	end
end

local function setPlace(place: string, zone: number?)
	local key = place .. (if Quality.lite then ":lite" else ":full")
	if key == rigKey then
		return
	end
	rigKey = key
	local theme = if place == "arena" then Themes.Arena else Themes.get(zone or 1)
	if rig then
		rig:Destroy()
	end
	local model = buildRig(theme, if Quality.lite then 185 else 1500, Quality.lite)
	model.Parent = Workspace
	rig = model
	applyLighting(theme)
	if WorldFx.place ~= place then
		WorldFx.place = place
		WorldFx.zone = zone
		placeChanged:Fire(place, zone)
	end
end

---------------------------------------------------------------------------
-- Animated props
---------------------------------------------------------------------------
type Anim = { part: BasePart, base: CFrame, size: Vector3, bob: number, bobSpeed: number, spin: number, orbit: number, orbitSpeed: number, orbitPhase: number, orbitCentre: Vector3, pulse: number, pulseSpeed: number, seed: number }
local anims: { [Instance]: Anim } = {}

local function register(inst: Instance)
	if not inst:IsA("BasePart") or anims[inst] then
		return
	end
	local orbit = inst:GetAttribute("Orbit")
	anims[inst] = {
		part = inst,
		base = inst.CFrame,
		size = inst.Size,
		bob = (inst:GetAttribute("Bob") :: number?) or 0,
		bobSpeed = (inst:GetAttribute("BobSpeed") :: number?) or 1,
		spin = if inst:GetAttribute("SpinAxis") then ((inst:GetAttribute("SpinSpeed") :: number?) or 1) else 0,
		orbit = if type(orbit) == "number" then orbit else 0,
		orbitSpeed = (inst:GetAttribute("OrbitSpeed") :: number?) or 1,
		orbitPhase = (inst:GetAttribute("OrbitPhase") :: number?) or 0,
		orbitCentre = Vector3.new((inst:GetAttribute("OrbitX") :: number?) or 0, (inst:GetAttribute("OrbitY") :: number?) or 0, (inst:GetAttribute("OrbitZ") :: number?) or 0),
		pulse = (inst:GetAttribute("Pulse") :: number?) or 0,
		pulseSpeed = (inst:GetAttribute("PulseSpeed") :: number?) or 2,
		seed = (inst.Position.X + inst.Position.Z) % 6.28,
	}
end

function WorldFx.animCount(): number
	local n = 0
	for _ in anims do
		n += 1
	end
	return n
end

-- Big title when the player arrives somewhere (the HUD listens to PlaceChanged for it).
function WorldFx.flash(color: Color3)
	local grade = Lighting:FindFirstChild("PcGrade") :: ColorCorrectionEffect?
	if grade and grade.Enabled then
		grade.TintColor = color:Lerp(Color3.new(1, 1, 1), 0.4)
		TweenService:Create(grade, TweenInfo.new(0.6), { TintColor = Color3.new(1, 1, 1) }):Play()
	end
end

function WorldFx.init()
	for _, inst in CollectionService:GetTagged("PcAnim") do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal("PcAnim"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("PcAnim"):Connect(function(inst)
		anims[inst] = nil
	end)

	setPlace("zone1", 1)
	Quality.Changed:Connect(function()
		rigKey = ""
		setPlace(WorldFx.place, WorldFx.zone)
	end)

	-- where am I?
	task.spawn(function()
		while true do
			local char = player.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if root then
				local zone = Layout.zoneAt(root.Position.X, root.Position.Z)
				if zone then
					setPlace("zone" .. zone, zone)
				elseif Layout.onArenaPlatform(root.Position.X, root.Position.Z) then
					setPlace("arena", nil)
				end
			end
			task.wait(0.4)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		if rigRoot then
			rigRoot.CFrame = CFrame.new(camPos)
		end
		for inst, a in anims do
			if not inst.Parent then
				anims[inst] = nil
				continue
			end
			if (a.base.Position - camPos).Magnitude > 260 then
				continue
			end
			local cf = a.base
			if a.orbit > 0 then
				local ang = now * a.orbitSpeed + a.orbitPhase
				cf = CFrame.new(a.orbitCentre.X + math.cos(ang) * a.orbit, a.orbitCentre.Y + math.sin(now * 2 + a.orbitPhase) * 0.3, a.orbitCentre.Z + math.sin(ang) * a.orbit) * (a.base - a.base.Position)
			end
			if a.bob ~= 0 then
				cf += Vector3.new(0, math.sin(now * a.bobSpeed + a.seed) * a.bob, 0)
			end
			if a.spin ~= 0 then
				cf *= CFrame.Angles(0, now * a.spin, 0)
			end
			a.part.CFrame = cf
			if a.pulse ~= 0 then
				a.part.Size = a.size * (1 + math.sin(now * a.pulseSpeed + a.seed) * a.pulse)
			end
		end
	end)
end

return WorldFx
