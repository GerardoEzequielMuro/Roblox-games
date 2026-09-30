--!strict
-- Builds the whole map in code: six galaxy stations (deck, hull, planet pedestals, plaza with
-- capsule machine / refinery / workshop / warp pad, themed scenery, gate pylons) and the
-- Meteor Arena. Planets themselves are drawn by each client (PlanetField).
-- Everything is anchored Parts with colours baked in: it has to read well at graphics
-- quality 1 (no shadows, no glow, few particles).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Themes = require(ReplicatedStorage.Shared.Themes)
local ModelSlots = require(script.Parent.ModelSlots)

local WorldBuilder = {}

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local INK = Color3.fromRGB(26, 24, 40)
local WHITE = Color3.fromRGB(245, 246, 250)

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end
local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

type Opts = { collide: boolean?, shadow: boolean?, transparency: number?, shape: Enum.PartType?, query: boolean? }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SMOOTH
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local o: Opts = opts or {}
	p.CanCollide = o.collide == true
	p.CanTouch = false
	p.CanQuery = o.collide == true or o.query == true
	p.CastShadow = o.shadow == true
	p.Transparency = o.transparency or 0
	if o.shape then
		p.Shape = o.shape
	end
	p.Parent = parent
	return p
end

-- Upright cylinder: (x, z) centre, top at yTop.
local function disc(parent: Instance, name: string, x: number, yTop: number, z: number, radius: number, thick: number, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local o: Opts = opts or {}
	o.shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(thick, radius * 2, radius * 2), CFrame.new(x, yTop - thick / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, o)
end

local function ball(parent: Instance, name: string, pos: Vector3, diameter: number, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local o: Opts = opts or {}
	o.shape = Enum.PartType.Ball
	return part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, material, o)
end

-- Floating text. attrs are Loc* attributes the client turns into translated text.
local function sign(parent: BasePart, text: string, attrs: { [string]: any }?, offsetY: number, width: number, height: number, color: Color3?, maxDistance: number?): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Name = "Sign"
	bb.Size = UDim2.fromScale(width, height)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = maxDistance or 160
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.LuckiestGuy
	t.TextScaled = true
	t.RichText = true
	t.Text = text
	t.TextColor3 = color or WHITE
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = INK
	st.Parent = t
	if attrs then
		for k, v in attrs do
			t:SetAttribute(k, v)
		end
	end
	t.Parent = bb
	bb.Parent = parent
	return t
end

local function prompt(parent: BasePart, open: string, attrs: { [string]: any }?, distance: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Open"
	pp.ObjectText = ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = distance or 14
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp:SetAttribute("Open", open)
	if attrs then
		for k, v in attrs do
			pp:SetAttribute(k, v)
		end
	end
	pp.Parent = parent
	return pp
end

-- A real light on a glowing prop (Future lighting makes the deck around it light up).
local function addLight(p: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.6
	l.Shadows = false
	l.Parent = p
end

local function anim(inst: Instance, attrs: { [string]: any })
	for k, v in attrs do
		inst:SetAttribute(k, v)
	end
	CollectionService:AddTag(inst, "PcAnim")
end

-- Invisible, non-colliding anchor that keeps prompts/signs/lights attached when a model replaces
-- the primitive build.
local function proxy(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	return part(parent, name, size, cf, INK, SMOOTH, { transparency = 1 })
end

---------------------------------------------------------------------------
-- Station pieces
---------------------------------------------------------------------------
local function deck(folder: Instance, cx: number, cz: number, radius: number, theme: Themes.Theme)
	disc(folder, "Deck", cx, 0, cz, radius, 6, theme.ground, theme.groundMaterial, { collide = true })
	disc(folder, "Rim", cx, -0.8, cz, radius + 2.5, 3, theme.rim, Enum.Material.DiamondPlate, { collide = true })
	disc(folder, "RimLight", cx, -3.8, cz, radius + 1.2, 1, theme.accent, NEON)
	disc(folder, "Hull1", cx, -6, cz, radius * 0.8, 9, theme.under, Enum.Material.Metal)
	disc(folder, "Hull2", cx, -15, cz, radius * 0.55, 11, darken(theme.under, 0.15), Enum.Material.Metal)
	disc(folder, "Hull3", cx, -26, cz, radius * 0.28, 14, darken(theme.under, 0.3), Enum.Material.Metal)
	disc(folder, "Thruster", cx, -40, cz, radius * 0.14, 3, theme.accent, NEON)
	-- railing posts with a light on top
	local posts = 20
	for i = 1, posts do
		local a = (i / posts) * math.pi * 2
		local x, z = cx + math.sin(a) * (radius - 1.5), cz + math.cos(a) * (radius - 1.5)
		part(folder, "Post", Vector3.new(1.2, 5, 1.2), CFrame.new(x, 2.5, z), theme.rim, Enum.Material.Metal, { collide = true })
		part(folder, "PostLight", Vector3.new(1.6, 1, 1.6), CFrame.new(x, 5.5, z), if i % 2 == 0 then theme.accent else theme.accent2, NEON)
	end
end

local function pedestal(folder: Instance, x: number, z: number, radius: number, theme: Themes.Theme, accent: Color3)
	disc(folder, "PadBase", x, 0.5, z, radius, 0.5, theme.rim, SMOOTH)
	disc(folder, "PadGlow", x, 0.62, z, radius * 0.72, 0.14, accent, NEON)
	disc(folder, "PadCore", x, 0.74, z, radius * 0.42, 0.14, darken(theme.rim, 0.2), SMOOTH)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.4
		local px, pz = x + math.sin(a) * radius * 0.9, z + math.cos(a) * radius * 0.9
		part(folder, "Prong", Vector3.new(0.8, 2.6, 0.8), CFrame.new(px, 1.4, pz) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-22), 0, 0), lighten(theme.rim, 0.25), SMOOTH)
	end
end

local RARITY_DOTS = { Color3.fromRGB(96, 214, 120), Color3.fromRGB(70, 160, 255), Color3.fromRGB(176, 96, 255), Color3.fromRGB(255, 190, 50) }

local function capsuleMachine(folder: Instance, capsuleId: string, theme: Themes.Theme, exclusive: boolean)
	local pos = Layout.capsulePosition(capsuleId) :: { number }
	local x, z = pos[1], pos[3]
	local body = if exclusive then Color3.fromRGB(120, 70, 220) else theme.accent
	local model = Instance.new("Model")
	model.Name = "Capsule_" .. capsuleId
	local base: Part
	local dome: Part
	local function primitive(): Instance?
		base = disc(model, "Base", x, 2.2, z, 5.2, 2.2, darken(body, 0.35), SMOOTH, { collide = true })
		disc(model, "BaseTrim", x, 2.5, z, 4.6, 0.4, lighten(body, 0.3), SMOOTH)
		disc(model, "Column", x, 5.2, z, 3.2, 2.8, body, SMOOTH, { collide = true })
		part(model, "Chute", Vector3.new(2.6, 1.6, 1.6), CFrame.new(x, 3.4, z + 3.4), INK, SMOOTH)
		part(model, "ChuteLip", Vector3.new(3.2, 0.5, 2), CFrame.new(x, 2.5, z + 3.8), lighten(body, 0.3), SMOOTH)
		dome = ball(model, "Dome", Vector3.new(x, 9.2, z), 9, lighten(body, 0.55), Enum.Material.Glass, { transparency = 0.45 })
		dome.Reflectance = 0.1
		-- capsules inside the dome: they orbit (client) and show the rarity colours
		for i, c in RARITY_DOTS do
			local a = i / #RARITY_DOTS * math.pi * 2
			local b = ball(model, "Mini", Vector3.new(x + math.cos(a) * 2.1, 8.4 + (i % 2) * 1.4, z + math.sin(a) * 2.1), 2, if exclusive then Color3.fromHSV(i / 5, 0.6, 1) else c, SMOOTH)
			anim(b, { Orbit = 2.1, OrbitSpeed = 0.9, OrbitPhase = a, OrbitY = b.Position.Y, OrbitX = x, OrbitZ = z })
		end
		disc(model, "Cap", x, 14.6, z, 3, 1.2, darken(body, 0.2), SMOOTH)
		local star = ball(model, "Beacon", Vector3.new(x, 15.8, z), 1.8, if exclusive then Color3.fromRGB(255, 220, 90) else WHITE, NEON)
		anim(star, { Bob = 0.35, BobSpeed = 2 })
		return nil
	end
	local swapped = ModelSlots.spawn("capsule_machine", CFrame.new(x, 0, z), Vector3.new(10.4, 17, 10.4), model, primitive, { collide = true })
	if swapped then
		base = proxy(model, "Base", Vector3.new(10.4, 2.2, 10.4), CFrame.new(x, 1.1, z))
		dome = proxy(model, "Dome", Vector3.new(9, 9, 9), CFrame.new(x, 9.2, z))
	end
	addLight(dome, body, 16, 1.4)
	model.PrimaryPart = base
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("CapsuleId", capsuleId)
	model.Parent = folder
	sign(dome, capsuleId, { LocCapsule = capsuleId }, 9.5, 17, 5.2, nil, 130)
	prompt(base, "Capsule", { CapsuleId = capsuleId }, 16)
end

local function refinery(folder: Instance, zone: number, theme: Themes.Theme)
	local pos = Layout.refineryPosition(zone)
	local x, z = pos[1], pos[3]
	local yellow = Color3.fromRGB(255, 205, 60)
	disc(folder, "RefineryPad", x, 0.3, z, Config.RefineryRadius, 0.3, yellow, SMOOTH)
	disc(folder, "RefineryPadIn", x, 0.4, z, Config.RefineryRadius - 1.4, 0.12, INK, SMOOTH)
	local glow = disc(folder, "RefineryGlow", x, 0.5, z, Config.RefineryRadius - 3.4, 0.12, Color3.fromRGB(90, 230, 130), NEON)
	-- chevrons pointing at the hopper
	for i = -1, 1 do
		part(folder, "Chevron", Vector3.new(3.4, 0.14, 0.9), CFrame.new(x + i * 2.4, 0.64, z + 1.2 - math.abs(i) * 1.4) * CFrame.Angles(0, math.rad(i * 35), 0), yellow, SMOOTH)
	end
	-- the hopper building, west of the pad
	local bx, bz = x - 11.5, z + 3
	local hopper: Part
	local swapped = ModelSlots.spawn("refinery_building", CFrame.new(bx, 0, bz), Vector3.new(14, 15.4, 8.4), folder, function()
		hopper = part(folder, "Hopper", Vector3.new(8, 9, 8), CFrame.new(bx, 4.5, bz), darken(theme.rim, 0.1), Enum.Material.Metal, { collide = true })
		part(folder, "HopperBand", Vector3.new(8.4, 1.4, 8.4), CFrame.new(bx, 6.4, bz), yellow, SMOOTH)
		part(folder, "HopperMouth", Vector3.new(5, 0.6, 5), CFrame.new(bx, 9.3, bz), INK, SMOOTH)
		disc(folder, "Chimney", bx - 2.2, 14, bz - 2.2, 1.1, 5, lighten(theme.rim, 0.2), Enum.Material.Metal)
		part(folder, "Conveyor", Vector3.new(6, 0.7, 2.6), CFrame.new(bx + 5.5, 1.4, bz - 1) * CFrame.Angles(0, 0, math.rad(12)), INK, SMOOTH)
		return nil
	end, { collide = true })
	if swapped then
		hopper = proxy(folder, "Hopper", Vector3.new(8, 9, 8), CFrame.new(bx, 4.5, bz))
	end
	local gem = ball(folder, "OreSample", Vector3.new(bx, 11.2, bz), 2.4, theme.accent2, NEON)
	addLight(hopper, theme.accent2, 14, 1.2)
	anim(gem, { Bob = 0.5, BobSpeed = 1.6, SpinAxis = "Y", SpinSpeed = 1.2 })
	sign(hopper, "REFINERY", { LocKey = "world.refinery" }, 12.5, 20, 5, yellow, 140)
	glow:SetAttribute("Refinery", zone)
end

local function workshop(folder: Instance, zone: number, theme: Themes.Theme)
	local pos = Layout.workshopPosition(zone)
	local x, z = pos[1], pos[3]
	local wood = Color3.fromRGB(150, 104, 70)
	local counter: Part
	local swapped = ModelSlots.spawn("workshop_stall", CFrame.new(x, 0, z), Vector3.new(9.8, 9.5, 5.6), folder, function()
		counter = part(folder, "Counter", Vector3.new(9, 3.4, 3.4), CFrame.new(x, 1.7, z), wood, Enum.Material.WoodPlanks, { collide = true })
		part(folder, "CounterTop", Vector3.new(9.8, 0.6, 4.2), CFrame.new(x, 3.7, z), lighten(wood, 0.25), SMOOTH)
		for _, sx in { -4.4, 4.4 } do
			part(folder, "Pole", Vector3.new(0.7, 9, 0.7), CFrame.new(x + sx, 4.5, z - 2.2), theme.rim, SMOOTH)
		end
		-- striped awning
		for i = 0, 4 do
			part(folder, "Awning", Vector3.new(2, 0.5, 5.6), CFrame.new(x - 4 + i * 2, 9, z - 0.6) * CFrame.Angles(math.rad(-16), 0, 0), if i % 2 == 0 then theme.accent else WHITE, SMOOTH)
		end
		-- a big pickaxe on the counter as the shop's icon
		local handle = part(folder, "PickHandle", Vector3.new(0.6, 5.4, 0.6), CFrame.new(x, 6.6, z) * CFrame.Angles(0, 0, math.rad(28)), Color3.fromRGB(120, 84, 60), SMOOTH)
		part(folder, "PickHead", Vector3.new(4.6, 0.9, 0.9), handle.CFrame * CFrame.new(0, 2.4, 0), Color3.fromRGB(200, 210, 225), Enum.Material.Metal)
		part(folder, "PickTipL", Vector3.new(1.2, 0.7, 0.7), handle.CFrame * CFrame.new(-2.7, 2.2, 0) * CFrame.Angles(0, 0, math.rad(25)), theme.accent2, SMOOTH)
		part(folder, "PickTipR", Vector3.new(1.2, 0.7, 0.7), handle.CFrame * CFrame.new(2.7, 2.2, 0) * CFrame.Angles(0, 0, math.rad(-25)), theme.accent2, SMOOTH)
		return nil
	end, { collide = true })
	if swapped then
		counter = proxy(folder, "Counter", Vector3.new(9, 3.4, 3.4), CFrame.new(x, 1.7, z))
	end
	sign(counter, "WORKSHOP", { LocKey = "world.workshop" }, 11.5, 20, 5, theme.accent, 140)
	prompt(counter, "Upgrades", nil, 14)
end

local function warpPad(folder: Instance, x: number, z: number, theme: Themes.Theme, zone: number?)
	local pad = disc(folder, "WarpPad", x, 0.4, z, 6.5, 0.4, theme.rim, SMOOTH)
	disc(folder, "WarpRing", x, 0.52, z, 5.4, 0.14, theme.accent2, NEON)
	disc(folder, "WarpCore", x, 0.64, z, 3.6, 0.14, darken(theme.accent2, 0.55), SMOOTH)
	ModelSlots.spawn("warp_gate", CFrame.new(x, 0, z), Vector3.new(15, 14.2, 2.6), folder, function()
		for _, sx in { -6.6, 6.6 } do
			part(folder, "WarpPylon", Vector3.new(1.6, 12, 1.6), CFrame.new(x + sx, 6, z), theme.rim, SMOOTH, { collide = true })
			part(folder, "WarpPylonLight", Vector3.new(1.9, 1.2, 1.9), CFrame.new(x + sx, 12.4, z), theme.accent2, NEON)
		end
		part(folder, "WarpBar", Vector3.new(15, 1.6, 1.6), CFrame.new(x, 13.4, z), theme.rim, SMOOTH)
		return nil
	end, { collide = true })
	local orb = ball(folder, "WarpOrb", Vector3.new(x, 6.5, z), 3, theme.accent2, NEON, { transparency = 0.25 })
	addLight(orb, theme.accent2, 18, 2)
	anim(orb, { Bob = 0.6, BobSpeed = 1.4, SpinAxis = "Y", SpinSpeed = 1 })
	if zone then
		sign(pad, "", { LocZone = zone }, 17.5, 30, 6.5, theme.accent, 220)
	else
		sign(pad, "METEOR ARENA", { LocKey = "world.arena" }, 17.5, 30, 6.5, theme.accent, 220)
	end
	prompt(pad, "Teleport", nil, 12)
end

local function systemStation(folder: Instance, zone: number, theme: Themes.Theme)
	local system
	for _, s in Config.Systems do
		if s.zone == zone and zone > 1 then
			system = s
		end
	end
	if not system then
		return
	end
	local pos = Layout.systemPosition(zone)
	local x, z = pos[1], pos[3]
	local base = disc(folder, "SystemBase", x, 1.4, z, 5, 1.4, theme.rim, SMOOTH, { collide = true })
	disc(folder, "SystemStep", x, 2.2, z, 3.6, 0.8, lighten(theme.rim, 0.2), SMOOTH, { collide = true })
	addLight(base, theme.accent, 16, 1.5)
	ModelSlots.spawn("system_monument", CFrame.new(x, 2.2, z), Vector3.new(7, 10.5, 7), folder, function()
		part(folder, "SystemPillar", Vector3.new(2.4, 5, 2.4), CFrame.new(x, 4.7, z), theme.propColor, SMOOTH, { collide = true })
		local relic = part(folder, "SystemRelic", Vector3.new(3, 3, 3), CFrame.new(x, 10, z) * CFrame.Angles(math.rad(35), math.rad(45), 0), theme.accent, NEON)
		anim(relic, { Bob = 0.6, BobSpeed = 1.3, SpinAxis = "Y", SpinSpeed = 1.5 })
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			local shard = part(folder, "SystemShard", Vector3.new(0.7, 1.8, 0.7), CFrame.new(x + math.cos(a) * 3.4, 9.6, z + math.sin(a) * 3.4), theme.accent2, NEON)
			anim(shard, { Orbit = 3.4, OrbitSpeed = 1.2, OrbitPhase = a, OrbitY = 9.6, OrbitX = x, OrbitZ = z })
		end
		return nil
	end, { collide = true })
	sign(base, system.id, { LocKey = "system." .. system.id .. ".name" }, 14.5, 20, 5, theme.accent2, 140)
	prompt(base, "Upgrades", { System = system.id }, 14)
end

local function gateFrame(folder: Instance, zone: number, theme: Themes.Theme)
	local nextZone = Config.Zones[zone + 1]
	if not nextZone then
		return
	end
	local g = Layout.nodePosition(zone, Config.NodeGate)
	local x, z = g[1], g[3]
	for _, sx in { -24, 24 } do
		local pylon: Part
		local swapped = ModelSlots.spawn("gate_pylon", CFrame.new(x + sx, -6, z - 12), Vector3.new(5.6, 52, 5.6), folder, function()
			pylon = part(folder, "GatePylon", Vector3.new(5, 46, 5), CFrame.new(x + sx, 17, z - 12), theme.rim, SMOOTH, { collide = true })
			part(folder, "GatePylonBand", Vector3.new(5.6, 2, 5.6), CFrame.new(x + sx, 30, z - 12), theme.accent, NEON)
			part(folder, "GatePylonBand", Vector3.new(5.6, 2, 5.6), CFrame.new(x + sx, 12, z - 12), theme.accent, NEON)
			part(folder, "GatePylonTip", Vector3.new(3, 6, 3), CFrame.new(x + sx, 43, z - 12), theme.accent2, NEON)
			return nil
		end, { collide = true })
		if swapped then
			pylon = proxy(folder, "GatePylon", Vector3.new(5, 46, 5), CFrame.new(x + sx, 17, z - 12))
		end
		addLight(pylon, theme.accent, 26, 2)
		if sx < 0 then
			sign(pylon, "", { LocGate = zone + 1 }, 30, 44, 9, theme.accent, 260)
		end
	end
	-- arrows on the deck leading to the gate
	for i = 0, 3 do
		part(folder, "GateArrow", Vector3.new(5, 0.14, 1.4), CFrame.new(x, 0.1, z - 22 - i * 5) * CFrame.Angles(0, 0, 0), theme.accent, SMOOTH)
	end
end

local function board(folder: Instance, slot: number, titleKey: string, faceTowards: Vector3, theme: Themes.Theme): BasePart
	local p = Layout.boardPosition(slot)
	local origin = Vector3.new(p[1], 8.5, p[3])
	local cf = CFrame.lookAt(origin, Vector3.new(faceTowards.X, 8.5, faceTowards.Z))
	local panel = part(folder, "Board_" .. titleKey, Vector3.new(16, 11, 1), cf, Color3.fromRGB(24, 28, 52), SMOOTH, { collide = true })
	part(folder, "BoardFrame", Vector3.new(17.2, 12.2, 0.6), cf * CFrame.new(0, 0, 0.3), theme.accent, SMOOTH)
	for _, sx in { -6.5, 6.5 } do
		part(folder, "BoardLeg", Vector3.new(1, 4, 1), cf * CFrame.new(sx, -7.4, 0), theme.rim, SMOOTH, { collide = true })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(640, 440)
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.TextScaled = true
	title.TextColor3 = theme.accent
	title.Text = titleKey
	title:SetAttribute("LocKey", titleKey)
	title.Parent = gui
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(0.92, 0, 0.8, 0)
	list.Position = UDim2.new(0.04, 0, 0.18, 0)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	list.Parent = gui
	gui.Parent = panel
	return panel
end

---------------------------------------------------------------------------
-- Scenery
---------------------------------------------------------------------------
local function primitiveProp(folder: Instance, style: string, x: number, z: number, scale: number, theme: Themes.Theme, rand: Random)
	local c1, c2 = theme.propColor, theme.propColor2
	if style == "rocks" then
		local h = 4 + scale * 5
		part(folder, "Spire", Vector3.new(3 * scale, h, 3 * scale), CFrame.new(x, h / 2 - 0.3, z) * CFrame.Angles(math.rad(rand:NextNumber(-8, 8)), rand:NextNumber(0, 3), math.rad(rand:NextNumber(-8, 8))), c1, Enum.Material.Slate, { collide = true })
		part(folder, "SpireCap", Vector3.new(2.2 * scale, 1.2, 2.2 * scale), CFrame.new(x, h - 0.2, z) * CFrame.Angles(0, rand:NextNumber(0, 3), 0), c2, SMOOTH)
		part(folder, "Boulder", Vector3.new(2.4 * scale, 1.8 * scale, 2.6 * scale), CFrame.new(x + 2.4 * scale, 0.7 * scale, z + 0.6) * CFrame.Angles(0.3, rand:NextNumber(0, 3), 0.2), darken(c1, 0.15), Enum.Material.Slate)
	elseif style == "mushrooms" then
		local h = 3 + scale * 4
		disc(folder, "Stem", x, h, z, 0.7 * scale, h, c2, SMOOTH, { collide = true })
		local cap = ball(folder, "Cap", Vector3.new(x, h + 0.4, z), 5.2 * scale, c1, SMOOTH)
		cap.Size = Vector3.new(5.2 * scale, 2.6 * scale, 5.2 * scale)
		for i = 0, 2 do
			local a = i * 2.1 + rand:NextNumber(0, 1)
			ball(folder, "Spot", Vector3.new(x + math.cos(a) * 1.4 * scale, h + 1.35 * scale, z + math.sin(a) * 1.4 * scale), 0.9 * scale, c2, SMOOTH)
		end
		disc(folder, "Moss", x, 0.2, z, 2.6 * scale, 0.2, theme.groundAlt, SMOOTH)
	elseif style == "ice" then
		for i = 0, 2 do
			local h = (3 + scale * 5) * (1 - i * 0.28)
			local ox, oz = (i - 1) * 1.7 * scale, (i % 2) * 1.4 * scale
			part(folder, "IceSpike", Vector3.new(1.8 * scale, h, 1.8 * scale), CFrame.new(x + ox, h / 2 - 0.4, z + oz) * CFrame.Angles(math.rad((i - 1) * 14), rand:NextNumber(0, 3), math.rad((i - 1) * -12)), if i == 0 then c1 else c2, Enum.Material.Ice, { collide = i == 0, transparency = 0 })
		end
		disc(folder, "Frost", x, 0.15, z, 3 * scale, 0.15, theme.groundAlt, SMOOTH)
	elseif style == "vents" then
		disc(folder, "VentBase", x, 1.6, z, 2.6 * scale, 1.6, c1, Enum.Material.Basalt, { collide = true })
		disc(folder, "VentRim", x, 2.6, z, 1.9 * scale, 1, darken(c1, 0.2), Enum.Material.Basalt)
		local lava = disc(folder, "VentLava", x, 2.7, z, 1.3 * scale, 0.2, c2, NEON)
		lava:SetAttribute("Ember", true)
		part(folder, "LavaSeam", Vector3.new(0.7, 0.12, 7 * scale), CFrame.new(x, 0.08, z) * CFrame.Angles(0, rand:NextNumber(0, 3), 0), c2, NEON)
	elseif style == "coils" then
		local h = 6 + scale * 4
		disc(folder, "CoilBase", x, 1, z, 2 * scale, 1, c1, Enum.Material.Metal, { collide = true })
		disc(folder, "CoilMast", x, h, z, 0.5 * scale, h - 1, lighten(c1, 0.25), Enum.Material.Metal, { collide = true })
		for i = 1, 3 do
			disc(folder, "CoilRing", x, 1 + i * (h - 2) / 4 + 0.3, z, (1.7 - i * 0.3) * scale, 0.5, c2, SMOOTH)
		end
		local orb = ball(folder, "CoilOrb", Vector3.new(x, h + 1, z), 2 * scale, theme.accent2, NEON)
		anim(orb, { Pulse = 0.18, PulseSpeed = 3 + rand:NextNumber(0, 2) })
	elseif style == "obelisks" then
		local h = 6 + scale * 6
		part(folder, "Obelisk", Vector3.new(2.2 * scale, h, 2.2 * scale), CFrame.new(x, h / 2, z) * CFrame.Angles(0, rand:NextNumber(0, 3), 0), c1, SMOOTH, { collide = true })
		part(folder, "ObeliskLine", Vector3.new(2.3 * scale, 0.5, 2.3 * scale), CFrame.new(x, h * 0.7, z), c2, NEON)
		part(folder, "ObeliskLine", Vector3.new(2.3 * scale, 0.5, 2.3 * scale), CFrame.new(x, h * 0.35, z), theme.accent2, NEON)
		local cube = part(folder, "ObeliskCube", Vector3.new(1.6 * scale, 1.6 * scale, 1.6 * scale), CFrame.new(x, h + 2.2, z) * CFrame.Angles(0.6, 0.8, 0), c2, NEON)
		anim(cube, { Bob = 0.5, BobSpeed = 1.2 + rand:NextNumber(0, 1), SpinAxis = "Y", SpinSpeed = 1.4 })
	end
end

-- style -> slot name and target bounding box (scale s = the prop's random size factor)
local PROP_SLOTS: { [string]: { slot: string, size: (s: number) -> Vector3 } } = {
	rocks = { slot = "rock_spire", size = function(s) return Vector3.new(5 * s, 4 + 5 * s, 5 * s) end },
	mushrooms = { slot = "mushroom", size = function(s) return Vector3.new(5.2 * s, 4.7 + 4 * s, 5.2 * s) end },
	ice = { slot = "ice_crystal", size = function(s) return Vector3.new(5 * s, 3 + 5 * s, 4 * s) end },
	vents = { slot = "lava_vent", size = function(s) return Vector3.new(5.2 * s, 3, 5.2 * s) end },
	coils = { slot = "tesla_coil", size = function(s) return Vector3.new(4 * s, 7 + 5 * s, 4 * s) end },
	obelisks = { slot = "obelisk", size = function(s) return Vector3.new(3 * s, 9 + 6 * s, 3 * s) end },
}

local function prop(folder: Instance, style: string, x: number, z: number, scale: number, theme: Themes.Theme, rand: Random)
	local def = PROP_SLOTS[style]
	if not def then
		primitiveProp(folder, style, x, z, scale, theme, rand)
		return
	end
	local yaw = ((math.floor(x) * 7 + math.floor(z) * 13) % 628) / 100
	ModelSlots.spawn(def.slot, CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0), def.size(scale), folder, function()
		primitiveProp(folder, style, x, z, scale, theme, rand)
		return nil
	end, { collide = true })
end

local function scenery(folder: Instance, zone: number, theme: Themes.Theme)
	local c = Layout.zoneCenter(zone)
	local rand = Random.new(zone * 977)
	local placed: { Vector3 } = {}
	local blockers: { { number } } = {}
	for n = 0, Config.NodeGate do
		table.insert(blockers, Layout.nodePosition(zone, n))
	end
	local tries = 0
	while #placed < 22 and tries < 600 do
		tries += 1
		local a = rand:NextNumber(0, math.pi * 2)
		local r = rand:NextNumber(18, Config.ZoneRadius - 9)
		local x, z = c[1] + math.sin(a) * r, c[3] + math.cos(a) * r
		local ok = not (z - c[3] < -34 and math.abs(x - c[1]) < 74) -- keep the plaza clear
		if ok and math.abs(x - c[1]) < 9 and z - c[3] > 30 then
			ok = false -- and the lane to the gate
		end
		if ok then
			for _, b in blockers do
				if (b[1] - x) ^ 2 + (b[3] - z) ^ 2 < 15 ^ 2 then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, q in placed do
				if (q.X - x) ^ 2 + (q.Z - z) ^ 2 < 11 ^ 2 then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(placed, Vector3.new(x, 0, z))
			prop(folder, theme.prop, x, z, rand:NextNumber(0.7, 1.3), theme, rand)
		end
	end
end

---------------------------------------------------------------------------
-- A galaxy station
---------------------------------------------------------------------------
local function buildZone(world: Folder, zone: number)
	local def = Config.Zones[zone]
	local theme = Themes.get(zone)
	local folder = Instance.new("Folder")
	folder.Name = "Zone" .. zone .. "_" .. def.id
	folder.Parent = world
	local c = Layout.zoneCenter(zone)
	local cx, cz = c[1], c[3]

	local deckFolder = Instance.new("Folder")
	deckFolder.Name = "Deck"
	deckFolder.Parent = folder
	deck(deckFolder, cx, cz, Config.ZoneRadius, theme)
	-- painted rings: the two planet orbits and the plaza
	disc(deckFolder, "OrbitOuter", cx, 0.06, cz + 6, 78, 0.12, theme.groundAlt, SMOOTH)
	disc(deckFolder, "OrbitOuterIn", cx, 0.1, cz + 6, 74, 0.12, theme.ground, theme.groundMaterial)
	disc(deckFolder, "OrbitInner", cx, 0.14, cz + 6, 46, 0.12, theme.groundAlt, SMOOTH)
	disc(deckFolder, "OrbitInnerIn", cx, 0.18, cz + 6, 42, 0.12, theme.ground, theme.groundMaterial)
	local spawn = Layout.spawnPoint(zone)
	disc(deckFolder, "Plaza", spawn[1], 0.24, spawn[3] - 4, 27, 0.12, lighten(theme.ground, 0.22), SMOOTH)
	disc(deckFolder, "PlazaRing", spawn[1], 0.3, spawn[3] - 4, 9, 0.12, theme.accent, SMOOTH)
	disc(deckFolder, "PlazaCore", spawn[1], 0.36, spawn[3] - 4, 7.6, 0.12, lighten(theme.ground, 0.4), SMOOTH)

	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = folder
	for n = 1, Config.NodesPerZone do
		local p = Layout.nodePosition(zone, n)
		pedestal(pads, p[1], p[3], if n > 5 then 4.2 else 3.4, theme, if n > 5 then theme.accent2 else theme.accent)
	end
	local titan = Layout.nodePosition(zone, Config.NodeTitan)
	pedestal(pads, titan[1], titan[3], 9, theme, Color3.fromRGB(150, 130, 255))
	disc(pads, "TitanRing", titan[1], 0.22, titan[3], 15, 0.12, Color3.fromRGB(150, 130, 255), SMOOTH)
	disc(pads, "TitanRingIn", titan[1], 0.26, titan[3], 13.4, 0.12, theme.ground, theme.groundMaterial)
	local anomaly = Layout.nodePosition(zone, Config.NodeAnomaly)
	pedestal(pads, anomaly[1], anomaly[3], 5, theme, Color3.fromRGB(60, 240, 220))

	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = folder
	for _, cap in Config.Capsules do
		if cap.zone == zone then
			capsuleMachine(plaza, cap.id, theme, (cap :: any).exclusive == true)
		end
	end
	refinery(plaza, zone, theme)
	workshop(plaza, zone, theme)
	systemStation(plaza, zone, theme)
	local portal = Layout.portalPosition(zone)
	warpPad(plaza, portal[1], portal[3], theme, zone)

	local gate = Instance.new("Folder")
	gate.Name = "Gate"
	gate.Parent = folder
	gateFrame(gate, zone, theme)

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	scenery(decor, zone, theme)
end

---------------------------------------------------------------------------
-- Meteor Arena
---------------------------------------------------------------------------
local function buildArena(world: Folder): Folder
	local theme = Themes.Arena
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = world
	local c = Config.ArenaCenter
	local cx, cz = c[1], c[3]
	local R, L = Config.ArenaRadius, Config.ArenaLobbyRadius
	deck(folder, cx, cz, L + 10, theme)
	-- safe lobby ring (blue) and the danger floor (dark with a red border)
	disc(folder, "Lobby", cx, 0.06, cz, L + 6, 0.12, Color3.fromRGB(70, 130, 200), SMOOTH)
	disc(folder, "Border", cx, 0.12, cz, R + 2.5, 0.12, Color3.fromRGB(235, 60, 60), NEON)
	disc(folder, "Floor", cx, 0.18, cz, R, 0.12, Color3.fromRGB(52, 50, 66), Enum.Material.Metal)
	disc(folder, "FloorRing", cx, 0.24, cz, 30, 0.12, Color3.fromRGB(235, 60, 60), SMOOTH)
	disc(folder, "FloorRingIn", cx, 0.3, cz, 28, 0.12, Color3.fromRGB(62, 60, 78), Enum.Material.Metal)
	disc(folder, "FloorCore", cx, 0.36, cz, 9, 0.12, Color3.fromRGB(255, 190, 60), SMOOTH)
	-- hazard pylons around the ring
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local x, z = cx + math.sin(a) * (R + 2.5), cz + math.cos(a) * (R + 2.5)
		ModelSlots.spawn("arena_pylon", CFrame.new(x, 0, z), Vector3.new(2.6, 10.2, 2.6), folder, function()
			part(folder, "Pylon", Vector3.new(2, 9, 2), CFrame.new(x, 4.5, z), if i % 2 == 0 then Color3.fromRGB(240, 200, 60) else INK, SMOOTH, { collide = true })
			part(folder, "PylonLight", Vector3.new(2.4, 1.2, 2.4), CFrame.new(x, 9.6, z), Color3.fromRGB(235, 60, 60), NEON)
			return nil
		end, { collide = true })
	end
	-- cover inside the arena
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local x, z = cx + math.sin(a) * 36, cz + math.cos(a) * 36
		ModelSlots.spawn("arena_cover", CFrame.new(x, 0, z) * CFrame.Angles(0, a, 0), Vector3.new(10.2, 7, 3.2), folder, function()
			part(folder, "Cover", Vector3.new(10, 7, 3), CFrame.new(x, 3.5, z) * CFrame.Angles(0, a, 0), Color3.fromRGB(84, 90, 116), Enum.Material.Metal, { collide = true })
			part(folder, "CoverStripe", Vector3.new(10.2, 1.2, 3.2), CFrame.new(x, 5.4, z) * CFrame.Angles(0, a, 0), Color3.fromRGB(240, 200, 60), SMOOTH)
			return nil
		end, { collide = true })
	end
	local marker = part(folder, "PvpMarker", Vector3.new(1, 1, 1), CFrame.new(cx, 1, cz), INK, SMOOTH, { transparency = 1 })
	sign(marker, "PVP ZONE", { LocKey = "world.pvp_zone" }, 34, 46, 9, Color3.fromRGB(255, 90, 90), 300)
	local sp = Layout.arenaSpawn()
	local safe = part(folder, "SafeMarker", Vector3.new(1, 1, 1), CFrame.new(sp[1], 1, sp[3]), INK, SMOOTH, { transparency = 1 })
	sign(safe, "SAFE ZONE", { LocKey = "world.safe_zone" }, 13, 26, 5, Color3.fromRGB(120, 200, 255), 120)
	warpPad(folder, cx, cz - L - 1, theme, nil)
	return folder
end

function WorldBuilder.build(): { boards: { [string]: BasePart }, world: Folder, arena: Folder }
	local world = Instance.new("Folder")
	world.Name = "World"
	for zone = 1, #Config.Zones do
		buildZone(world, zone)
	end
	local arena = buildArena(world)

	-- the only SpawnLocation: the Dawn Belt plaza
	local sp = Layout.spawnPoint(1)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(sp[1], 0.2, sp[3]) * CFrame.Angles(0, math.pi, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = world

	local boards: { [string]: BasePart } = {}
	local zone1 = world:FindFirstChild("Zone1_" .. Config.Zones[1].id) :: Instance
	local spawnV = Vector3.new(sp[1], 0, sp[3])
	boards.mined = board(zone1, 1, "world.board_mined", spawnV, Themes.get(1))
	boards.rebirths = board(zone1, 2, "world.board_rebirths", spawnV, Themes.get(1))
	local asp = Layout.arenaSpawn()
	boards.arena = board(arena, 3, "world.board_arena", Vector3.new(asp[1], 0, asp[3]), Themes.Arena)

	world.Parent = Workspace
	return { boards = boards, world = world, arena = arena }
end

return WorldBuilder
