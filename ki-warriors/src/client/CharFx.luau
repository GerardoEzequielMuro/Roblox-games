--!nonstrict
-- Character visuals for every fighter the client can see (players and server dummies):
--   * auras built from GEOMETRY (rising flame tongues, shell, ground ring, lightning bolts) plus
--     optional particles / light, so they still read at graphics quality 1
--   * transformation looks: aura colour, glowing head crest, recoloured hair, outline
--   * procedural poses through Motor6D.Transform (punch, charge, block, beam, flight): no
--     animation assets
--   * power tag over the head
-- One Stepped loop (poses) and one RenderStepped loop (auras) for everybody.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local CombatFx = require(script.Parent.CombatFx)
local Lang = require(script.Parent.Lang)

local CharFx = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

type Rig = { [string]: any }

local rigs: { [Model]: Rig } = {}
local byFighter: { [number]: Rig } = {}
CharFx.rigs = rigs

local JOINTS = { "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightHip", "LeftHip", "RightKnee", "LeftKnee", "Root" }

local function weld(part: BasePart, to: BasePart, offset: CFrame)
	part.Anchored = false
	part.Massless = true
	part.CFrame = to.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
end

local function newPart(shape: string, size: Vector3, color: Color3, neon: boolean): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "ball" then
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Ball
		p = b
	elseif shape == "cyl" then
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Cylinder
		p = b
	else
		p = Instance.new("Part")
	end
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = "KiwCrest"
	return p
end

---------------------------------------------------------------------------
-- Transformation look: crest + hair + outline
---------------------------------------------------------------------------
local function clearCrest(rig: Rig)
	for _, p in rig.crest do
		p:Destroy()
	end
	table.clear(rig.crest)
	for _, h in rig.hair do
		if h.part.Parent then
			h.part.Color = h.color
			if h.texture ~= nil and h.part:IsA("MeshPart") then
				h.part.TextureID = h.texture
			end
			if h.mesh and h.mesh.Parent and h.meshTexture then
				h.mesh.TextureId = h.meshTexture
			end
		end
	end
	table.clear(rig.hair)
	if rig.highlight then
		rig.highlight:Destroy()
		rig.highlight = nil
	end
end

-- Ring of thin segments welded around a point behind the head (a filled disc would hide it).
local function haloRing(rig: Rig, head: BasePart, radius: number, thick: number, color: Color3, offset: CFrame, neon: boolean)
	local n = 12
	local len = 2 * math.pi * radius / n * 1.1
	for i = 1, n do
		local a = i / n * math.pi * 2
		local p = newPart("block", Vector3.new(len, thick, thick), color, neon)
		weld(p, head, offset * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2))
		p.Parent = rig.char
		table.insert(rig.crest, p)
	end
end

local function applyForm(rig: Rig, form: number)
	clearCrest(rig)
	rig.shownForm = form
	local head = rig.head
	if form <= 0 or not head then
		return
	end
	local c1, c2, style = Fx.formColors(form)
	-- hair takes the form colour (texture off so the colour shows)
	for _, acc in rig.char:GetChildren() do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local isHair = acc.AccessoryType == Enum.AccessoryType.Hair or acc.Name:lower():find("hair") ~= nil
			if handle and handle:IsA("BasePart") and isHair then
				local entry = { part = handle, color = handle.Color, texture = nil, mesh = nil, meshTexture = nil }
				if handle:IsA("MeshPart") then
					entry.texture = handle.TextureID
					handle.TextureID = ""
				end
				local mesh = handle:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					entry.mesh = mesh
					entry.meshTexture = mesh.TextureId
					mesh.TextureId = ""
				end
				handle.Color = c1
				table.insert(rig.hair, entry)
			end
		end
	end
	-- crest: a glowing crown behind / above the head, different per style
	local function add(shape: string, size: Vector3, color: Color3, offset: CFrame)
		local p = newPart(shape, size, color, true)
		weld(p, head, offset)
		p.Parent = rig.char
		table.insert(rig.crest, p)
		return p
	end
	local tier = math.min(form, 7)
	if style == "flame" then
		-- fan of flame blades rising behind the head
		local n = 3 + math.min(tier, 2) * 2
		for i = 1, n do
			local k = (i - (n + 1) / 2)
			local h = 2.2 + (1 - math.abs(k) / n) * 2.2 + tier * 0.2
			add("wedge", Vector3.new(0.35, h, 1), if i % 2 == 0 then c2 else c1, CFrame.new(k * 0.42, 0.7 + h * 0.4, 0.75) * CFrame.Angles(math.rad(-16), 0, math.rad(-k * 13)))
		end
	elseif style == "lightning" then
		-- swept-back blades + a halo
		for _, side in { -1, 1 } do
			add("wedge", Vector3.new(0.3, 3.4, 1.2), c1, CFrame.new(side * 0.55, 1.5, 0.9) * CFrame.Angles(math.rad(-38), 0, math.rad(-side * 20)))
			add("wedge", Vector3.new(0.3, 2.2, 0.9), c2, CFrame.new(side * 1.05, 1.0, 0.7) * CFrame.Angles(math.rad(-30), 0, math.rad(-side * 44)))
		end
		add("wedge", Vector3.new(0.35, 4.2, 1.2), c2, CFrame.new(0, 1.9, 1.0) * CFrame.Angles(math.rad(-30), 0, 0))
		haloRing(rig, head, 1.9, 0.16, c1, CFrame.new(0, 2.6, 0.2) * CFrame.Angles(math.rad(90), 0, 0), true)
	elseif style == "shadow" then
		-- horns + dark halo
		for _, side in { -1, 1 } do
			add("wedge", Vector3.new(0.5, 2.6, 0.8), c1, CFrame.new(side * 0.85, 1.3, 0) * CFrame.Angles(0, math.rad(90 * side), math.rad(-side * 18)))
			add("wedge", Vector3.new(0.4, 1.6, 0.6), WHITE, CFrame.new(side * 1.25, 2.7, 0) * CFrame.Angles(0, math.rad(90 * side), math.rad(side * 10)))
		end
		haloRing(rig, head, 2.3, 0.22, c1, CFrame.new(0, 0.5, 1.0), true)
		haloRing(rig, head, 1.75, 0.14, WHITE, CFrame.new(0, 0.5, 1.0), true)
	else -- prism: halo + shards
		haloRing(rig, head, 2.5, 0.2, c1, CFrame.new(0, 0.5, 1.1), true)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			add("block", Vector3.new(0.4, 1.7, 0.4), if i % 2 == 0 then c1 else c2, CFrame.new(math.cos(a) * 2.9, 0.5 + math.sin(a) * 2.9, 1.1) * CFrame.Angles(0, 0, a + math.rad(90)))
		end
	end
	local hl = Instance.new("Highlight")
	hl.Name = "KiwFormOutline"
	hl.FillColor = c1
	hl.FillTransparency = 0.9
	hl.OutlineColor = c2
	hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = rig.char
	hl.Parent = rig.char
	rig.highlight = hl
end

-- Race marks (small welded parts; none for terran).
local function applyRace(rig: Rig, race: string?)
	for _, p in rig.marks do
		p:Destroy()
	end
	table.clear(rig.marks)
	rig.race = race
	local head = rig.head
	local def = race and Config.RaceById[race]
	if not head or not def or race == "terran" then
		return
	end
	local c = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local function add(shape, size, offset)
		local p = newPart(shape, size, c, true)
		p.Name = "KiwMark"
		weld(p, head, offset)
		p.Parent = rig.char
		table.insert(rig.marks, p)
	end
	if race == "voltari" then
		add("block", Vector3.new(0.25, 0.7, 0.12), CFrame.new(0, 0.32, -0.62) * CFrame.Angles(0, 0, math.rad(20)))
		add("block", Vector3.new(0.25, 0.5, 0.12), CFrame.new(0.12, 0.05, -0.62) * CFrame.Angles(0, 0, math.rad(-30)))
	elseif race == "lumen" then
		for _, side in { -1, 1 } do
			add("block", Vector3.new(0.3, 0.9, 0.3), CFrame.new(side * 0.72, 0.35, 0) * CFrame.Angles(0, 0, math.rad(-side * 25)))
		end
		add("ball", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, 0.3, -0.62))
	elseif race == "drakhar" then
		for _, side in { -1, 1 } do
			add("wedge", Vector3.new(0.3, 1.1, 0.5), CFrame.new(side * 0.5, 0.95, -0.1) * CFrame.Angles(math.rad(12), 0, math.rad(-side * 14)))
		end
	end
end

---------------------------------------------------------------------------
-- Aura
---------------------------------------------------------------------------
local function releaseAura(rig: Rig)
	for _, p in rig.tongues do
		Fx.release(p)
	end
	table.clear(rig.tongues)
	for _, p in rig.bolts do
		Fx.release(p)
	end
	table.clear(rig.bolts)
	if rig.shell then
		Fx.release(rig.shell)
		rig.shell = nil
	end
	if rig.ring then
		Fx.release(rig.ring)
		rig.ring = nil
	end
	if rig.emitter then
		rig.emitter.Enabled = false
	end
	if rig.light then
		rig.light.Enabled = false
	end
	rig.auraOn = false
end

local function ensureAura(rig: Rig, count: number, withBolts: boolean)
	while #rig.tongues < count do
		local p = Fx.get("blob")
		p:SetAttribute("Phase", math.random())
		p:SetAttribute("Angle", math.random() * math.pi * 2)
		table.insert(rig.tongues, p)
	end
	while #rig.tongues > count do
		Fx.release(table.remove(rig.tongues) :: any)
	end
	if not rig.shell then
		rig.shell = Fx.get("blob")
	end
	if not rig.ring then
		rig.ring = Fx.get("cyl")
	end
	local wantBolts = if withBolts then 3 else 0
	while #rig.bolts < wantBolts * 3 do
		table.insert(rig.bolts, Fx.get("block"))
	end
	while #rig.bolts > wantBolts * 3 do
		Fx.release(table.remove(rig.bolts) :: any)
	end
	if not Fx.lite then
		if not rig.emitter then
			local att = Instance.new("Attachment")
			att.Name = "KiwAura"
			att.Position = Vector3.new(0, -2.6, 0)
			att.Parent = rig.root
			local e = Instance.new("ParticleEmitter")
			e.Speed = NumberRange.new(9, 16)
			e.Lifetime = NumberRange.new(0.5, 0.9)
			e.Rate = 34
			e.SpreadAngle = Vector2.new(24, 24)
			e.EmissionDirection = Enum.NormalId.Top
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.1) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			e.LightEmission = 1
			e.Squash = NumberSequence.new(1.6)
			e.Parent = att
			rig.emitter = e
			local l = Instance.new("PointLight")
			l.Range = 22
			l.Brightness = 2
			l.Shadows = false
			l.Parent = rig.root
			rig.light = l
		end
		rig.emitter.Enabled = true
		rig.light.Enabled = true
	end
	rig.auraOn = true
end

local function zigzag(parts: { BasePart }, index: number, from: Vector3, to: Vector3, color: Color3)
	local a = from
	for seg = 1, 3 do
		local t = seg / 3
		local b = from:Lerp(to, t)
		if seg < 3 then
			b += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2
		end
		local p = parts[(index - 1) * 3 + seg]
		local len = (b - a).Magnitude
		p.Size = Vector3.new(0.22, 0.22, len)
		p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
		p.Color = color
		a = b
	end
end

local function updateAura(rig: Rig, now: number, camPos: Vector3)
	local char = rig.char
	local form = char:GetAttribute("Form") or 0
	local charging = char:GetAttribute("Charging") == true
	local beaming = char:GetAttribute("Beam") == true
	local auraColor = Fx.auraColor(char:GetAttribute("Aura"))
	local hum = rig.hum
	local alive = not hum or hum.Health > 0
	local intensity = 0
	if alive then
		if charging then
			intensity = 1.15
		elseif beaming then
			intensity = 0.9
		elseif form > 0 then
			intensity = 0.72
		elseif auraColor then
			intensity = 0.34
		end
	end
	if rig.surge > 0 then
		intensity = math.max(intensity, 0.8) + rig.surge
	end
	local pos = rig.root.Position
	local dist = (camPos - pos).Magnitude
	if intensity <= 0 or dist > (if Fx.lite then 170 else 320) then
		if rig.auraOn then
			releaseAura(rig)
		end
		return
	end
	local c1, c2, style = Fx.formColors(form)
	if form <= 0 and auraColor then
		c1, c2 = auraColor, auraColor:Lerp(WHITE, 0.6)
	end
	if style == "prism" then
		c1 = Color3.fromHSV((now * 0.25) % 1, 0.55, 1)
	end
	local far = dist > 120
	local count = if intensity < 0.5 then 4 elseif Fx.lite or far then 7 else 12
	ensureAura(rig, count, (style == "lightning" or style == "prism") and form > 0 and not far)
	local scale = 0.75 + intensity * 0.45
	local rootCf = CFrame.new(pos)
	local speed = 1.3 + intensity * 0.9
	for i, p in rig.tongues do
		local t = (now * speed + p:GetAttribute("Phase")) % 1
		local a = p:GetAttribute("Angle") + now * 0.6
		local r = (2.2 - t * 1.6) * scale
		local h = (2.6 + math.sin(math.pi * t) * 4.2) * scale
		local w = (1.25 - t * 0.95) * scale
		p.Size = Vector3.new(w, h, w)
		p.CFrame = rootCf * CFrame.new(math.cos(a) * r, -2.8 + t * 7.5 * scale, math.sin(a) * r)
		-- shadow forms: every third tongue is a darker streak, still glowing and see-through
		-- (it used to be opaque SmoothPlastic in a near-black colour: dark blobs on the body)
		local dark = style == "shadow" and i % 3 == 0
		p.Color = if dark then c2:Lerp(c1, 0.4) else c1:Lerp(c2, t * 0.8)
		p.Transparency = (if dark then 0.4 else 0.22) + t * 0.58
	end
	local pulse = 1 + math.sin(now * 9) * 0.05
	local shell = rig.shell
	shell.Size = Vector3.new(6.2, 9.4, 6.2) * scale * pulse
	shell.CFrame = rootCf * CFrame.new(0, 0.6, 0)
	shell.Color = c1
	-- ForceField: bright rim, clear centre. A Neon ellipsoid here read as a solid coloured ball
	-- over the character (worst with Eclipse's purple under bloom).
	if shell.Material ~= Enum.Material.ForceField then
		shell.Material = Enum.Material.ForceField
	end
	shell.Transparency = 0.62 - math.min(intensity, 1.2) * 0.14
	local ring = rig.ring
	local grounded = hum and hum.FloorMaterial ~= Enum.Material.Air
	if grounded then
		local rr = (5 + math.sin(now * 6) * 0.6) * scale
		ring.Size = Vector3.new(0.25, rr * 2, rr * 2)
		ring.CFrame = rootCf * CFrame.new(0, -2.85, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = c1
		ring.Transparency = 0.45
	else
		ring.Transparency = 1
	end
	if #rig.bolts > 0 and now >= rig.boltAt then
		rig.boltAt = now + 0.07
		for b = 1, #rig.bolts // 3 do
			local a = math.random() * math.pi * 2
			local from = pos + Vector3.new(math.cos(a) * 1.6, -2.4 + math.random() * 1.5, math.sin(a) * 1.6)
			local to = pos + Vector3.new(math.cos(a + 1) * 3.2, 1.5 + math.random() * 3.5, math.sin(a + 1) * 3.2)
			zigzag(rig.bolts, b, from, to, if style == "prism" then c2 else c2:Lerp(WHITE, 0.4))
		end
	end
	if rig.emitter and rig.emitter.Enabled then
		rig.emitter.Color = ColorSequence.new(c2, c1)
		rig.emitter.Rate = 16 + intensity * 30
		rig.light.Color = c1
		rig.light.Brightness = 1 + intensity * 1.6
	end
end

---------------------------------------------------------------------------
-- Poses
---------------------------------------------------------------------------
local rad = math.rad
local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end
local POSES: { [string]: { [string]: CFrame } } = {
	charge = {
		Waist = A(-10, 0, 0),
		Neck = A(12, 0, 0),
		RightShoulder = A(-18, 0, 34),
		LeftShoulder = A(-18, 0, -34),
		RightElbow = A(70, 0, 0),
		LeftElbow = A(70, 0, 0),
		RightHip = A(30, 0, 12),
		LeftHip = A(30, 0, -12),
		RightKnee = A(-52, 0, 0),
		LeftKnee = A(-52, 0, 0),
	},
	block = {
		Waist = A(-6, 0, 0),
		RightShoulder = A(105, 0, -42),
		LeftShoulder = A(105, 0, 42),
		RightElbow = A(62, 0, 0),
		LeftElbow = A(62, 0, 0),
		RightHip = A(14, 0, 8),
		LeftHip = A(-10, 0, -8),
	},
	beamCharge = {
		Waist = A(-6, -46, 0),
		Neck = A(0, 40, 0),
		RightShoulder = A(22, 0, 12),
		LeftShoulder = A(60, 0, 56),
		RightElbow = A(74, 0, 0),
		LeftElbow = A(60, 0, 0),
		RightHip = A(22, 0, 14),
		LeftHip = A(-16, 0, -10),
		RightKnee = A(-30, 0, 0),
		LeftKnee = A(-22, 0, 0),
	},
	beamFire = {
		Waist = A(-10, 0, 0),
		RightShoulder = A(92, 0, -14),
		LeftShoulder = A(92, 0, 14),
		RightElbow = A(6, 0, 0),
		LeftElbow = A(6, 0, 0),
		RightHip = A(26, 0, 12),
		LeftHip = A(-22, 0, -12),
		RightKnee = A(-24, 0, 0),
		LeftKnee = A(-10, 0, 0),
	},
	fly = {
		Waist = A(6, 0, 0),
		Neck = A(34, 0, 0),
		RightShoulder = A(-32, 0, 12),
		LeftShoulder = A(-32, 0, -12),
		RightElbow = A(10, 0, 0),
		LeftElbow = A(10, 0, 0),
		RightHip = A(-8, 0, 4),
		LeftHip = A(12, 0, -4),
		RightKnee = A(-8, 0, 0),
		LeftKnee = A(-36, 0, 0),
	},
	hover = {
		RightShoulder = A(-8, 0, 16),
		LeftShoulder = A(-8, 0, -16),
		RightElbow = A(28, 0, 0),
		LeftElbow = A(28, 0, 0),
		RightHip = A(10, 0, 5),
		LeftHip = A(-4, 0, -5),
		RightKnee = A(-26, 0, 0),
		LeftKnee = A(-10, 0, 0),
	},
	punchR = {
		Waist = A(-4, 28, 0),
		RightShoulder = A(96, 0, -10),
		RightElbow = A(4, 0, 0),
		LeftShoulder = A(30, 0, 18),
		LeftElbow = A(96, 0, 0),
	},
	punchL = {
		Waist = A(-4, -28, 0),
		LeftShoulder = A(96, 0, 10),
		LeftElbow = A(4, 0, 0),
		RightShoulder = A(30, 0, -18),
		RightElbow = A(96, 0, 0),
	},
	flinch = {
		Waist = A(16, 0, 0),
		Neck = A(-14, 0, 0),
		RightShoulder = A(-20, 0, 22),
		LeftShoulder = A(-20, 0, -22),
	},
}
local POSE_ORDER = { "hover", "fly", "charge", "block", "beamCharge", "beamFire", "punchR", "punchL", "flinch" }

local function blendTo(current: number, target: number, dt: number, speed: number): number
	if current < target then
		return math.min(target, current + dt * speed)
	end
	return math.max(target, current - dt * speed)
end

local function updatePose(rig: Rig, dt: number, now: number)
	if not rig.r15 then
		return
	end
	local char = rig.char
	local w = rig.w
	local flying = char:GetAttribute("Flying") == true
	local moving = rig.root.AssemblyLinearVelocity.Magnitude > 14
	w.fly = blendTo(w.fly, if flying and moving then 1 else 0, dt, 6)
	w.hover = blendTo(w.hover, if flying and not moving then 1 else 0, dt, 6)
	w.charge = blendTo(w.charge, if char:GetAttribute("Charging") == true then 1 else 0, dt, 9)
	w.block = blendTo(w.block, if char:GetAttribute("Blocking") == true then 1 else 0, dt, 14)
	w.beamCharge = blendTo(w.beamCharge, if char:GetAttribute("Beam") == true then 1 else 0, dt, 9)
	-- beam release: short hold of the firing pose
	w.beamFire = blendTo(w.beamFire, if now - (rig :: any).beamAt < 0.5 then 1 else 0, dt, 12)
	-- punch: fast out (0.07 s), slower back (0.2 s)
	local pt = now - rig.punchAt
	local punch = 0
	if pt < 0.07 then
		punch = pt / 0.07
	elseif pt < 0.3 then
		punch = 1 - (pt - 0.07) / 0.23
	end
	if rig.punchBig then
		punch = math.min(1, punch * 1.25)
	end
	w.punchR = if rig.punchSide == 1 then punch else 0
	w.punchL = if rig.punchSide == -1 then punch else 0
	local ft = now - rig.flinchAt
	w.flinch = if ft < 0.25 then 1 - ft / 0.25 else 0

	local shake = if w.charge > 0.5 then math.sin(now * 60) * 1.4 else 0
	for _, name in JOINTS do
		local m = rig.joints[name]
		if m then
			local cf = m.Transform
			local touched = false
			for _, poseName in POSE_ORDER do
				local weight = w[poseName]
				if weight > 0.01 then
					local target = POSES[poseName][name]
					if target then
						cf = cf:Lerp(target, weight)
						touched = true
					end
				end
			end
			if touched then
				if shake ~= 0 and (name == "RightShoulder" or name == "LeftShoulder") then
					cf *= CFrame.Angles(rad(shake), 0, 0)
				end
				m.Transform = cf
			end
		end
	end
end

---------------------------------------------------------------------------
-- Tag
---------------------------------------------------------------------------
local function updateTag(rig: Rig)
	local char = rig.char
	local power = char:GetAttribute("Power")
	local head = rig.head
	if not power or not head then
		return
	end
	local form = char:GetAttribute("Form") or 0
	local key = power .. ":" .. form
	if rig.tagPower == key then
		return
	end
	rig.tagPower = key
	local bb = rig.tag
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "KiwTag"
		bb.Size = UDim2.fromOffset(150, 38)
		bb.StudsOffset = Vector3.new(0, 3.1, 0)
		bb.MaxDistance = 120
		bb.AlwaysOnTop = false
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Power"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0.62)
		t.Font = Enum.Font.Bangers
		t.TextScaled = true
		local s = Instance.new("UIStroke")
		s.Thickness = 2.5
		s.Color = Color3.fromRGB(20, 14, 34)
		s.Parent = t
		t.Parent = bb
		local f = Instance.new("TextLabel")
		f.Name = "Form"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 0.38)
		f.Position = UDim2.fromScale(0, 0.62)
		f.Font = Enum.Font.GothamBlack
		f.TextScaled = true
		local s2 = s:Clone()
		s2.Thickness = 2
		s2.Parent = f
		f.Parent = bb
		bb.Adornee = head
		bb.Parent = head
		rig.tag = bb
	end
	local c1 = Fx.formColors(form)
	bb.Power.Text = "⚡ " .. Format.abbrev(power)
	bb.Power.TextColor3 = if form > 0 then c1:Lerp(WHITE, 0.35) else Color3.fromRGB(255, 236, 140)
	bb.Form.Text = if form > 0 then Lang.t("form." .. Config.Forms[form].id) else ""
	bb.Form.TextColor3 = c1
end

---------------------------------------------------------------------------
-- Rig tracking
---------------------------------------------------------------------------
local function addRig(char: Model)
	if rigs[char] then
		return
	end
	local root = char:WaitForChild("HumanoidRootPart", 8)
	local hum = char:WaitForChild("Humanoid", 8)
	if not root or not char.Parent then
		return
	end
	local rig: Rig = {
		beamAt = -10,
		char = char,
		hum = hum,
		root = root,
		head = char:FindFirstChild("Head"),
		joints = {},
		r15 = hum ~= nil and hum.RigType == Enum.HumanoidRigType.R15,
		tongues = {},
		bolts = {},
		boltAt = 0,
		auraOn = false,
		surge = 0,
		shownForm = 0,
		crest = {},
		hair = {},
		w = { fly = 0, hover = 0, charge = 0, block = 0, beamCharge = 0, beamFire = 0, punchR = 0, punchL = 0, flinch = 0 },
		punchAt = -10,
		punchSide = 1,
		punchBig = false,
		flinchAt = -10,
		marks = {},
	}
	local function scan()
		for _, d in char:GetDescendants() do
			if d:IsA("Motor6D") and table.find(JOINTS, d.Name) then
				rig.joints[d.Name] = d
			end
		end
		rig.head = char:FindFirstChild("Head")
	end
	scan()
	task.delay(1.5, scan) -- limbs can stream in after the root
	rigs[char] = rig
	local function bindId()
		local id = char:GetAttribute("FighterId")
		if id then
			byFighter[id] = rig
		end
	end
	bindId()
	char:GetAttributeChangedSignal("FighterId"):Connect(bindId)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			releaseAura(rig)
			clearCrest(rig)
			rigs[char] = nil
			for id, r in byFighter do
				if r == rig then
					byFighter[id] = nil
				end
			end
		end
	end)
end

local function rigOf(d): Rig?
	if d.i and byFighter[d.i] then
		return byFighter[d.i]
	end
	if d.u and d.u ~= 0 then
		local plr = Players:GetPlayerByUserId(d.u)
		if plr and plr.Character then
			return rigs[plr.Character]
		end
	end
	return nil
end
CharFx.rigOf = rigOf

-- Big transformation moment.
local function transformBurst(rig: Rig, form: number)
	local pos = rig.root.Position
	local c1, c2 = Fx.formColors(form)
	local ground = Vector3.new(pos.X, pos.Y - 2.8, pos.Z)
	rig.surge = 1.2
	-- light pillar
	local pillar = Fx.get("cyl")
	pillar.Color = c2
	pillar.Transparency = 0.4
	pillar.Size = Vector3.new(120, 3, 3)
	pillar.CFrame = CFrame.new(pos + Vector3.new(0, 56, 0)) * CFrame.Angles(0, 0, rad(90))
	Fx.tween(pillar, 0.5, { Size = Vector3.new(120, 16, 16), Transparency = 1 })
	task.delay(0.5, Fx.release, pillar)
	local pillar2 = Fx.get("cyl")
	pillar2.Color = c1
	pillar2.Transparency = 0.5
	pillar2.Size = Vector3.new(120, 6, 6)
	pillar2.CFrame = pillar.CFrame
	Fx.tween(pillar2, 0.7, { Size = Vector3.new(120, 26, 26), Transparency = 1 })
	task.delay(0.7, Fx.release, pillar2)
	-- see-through shells (a Neon ball starting at character size hid the character)
	Fx.shell(pos, 4, 22, c1, 0.5, 0.15)
	Fx.shell(pos, 3.5, 13, WHITE, 0.3, 0.3)
	if not Fx.lite then
		Fx.particles(pos, c2, 26, 38, 1.1, 0.6)
	end
	Fx.ring(ground, 3, 34, c1, 0.6, 0.8)
	Fx.ring(ground + Vector3.new(0, 0.1, 0), 2, 22, c2, 0.45, 0.5)
	Fx.sparks(pos, c2, 16, 70, 0.8)
	-- ground debris (particles / fading specks) and speed lines shooting up
	Fx.debris(ground, 7, c1:Lerp(Color3.fromRGB(230, 220, 200), 0.5), if Fx.lite then 5 else 10)
	for i = 1, (if Fx.lite then 5 else 10) do
		local a = i / 10 * math.pi * 2 + math.random() * 0.5
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = ground + dir * (2.5 + math.random() * 2)
		Fx.flash("block", CFrame.new(from + Vector3.new(0, 1, 0)), Vector3.new(0.22, 2.5, 0.22), c2, 0.35, { CFrame = CFrame.new(from + Vector3.new(0, 11, 0)), Size = Vector3.new(0.06, 6, 0.06), Transparency = 1 }, 0.15)
	end
	local cam = workspace.CurrentCamera
	local dist = if cam then (cam.CFrame.Position - pos).Magnitude else 0
	Fx.shake(math.clamp(1.6 - dist / 100, 0, 1.6))
	if rig.char == player.Character then
		Fx.kick(16)
	end
	Fx.sound("boom", 0.6, 0.55)
end

CharFx.transformBurst = transformBurst

function CharFx.swing(rig: Rig, big: boolean)
	rig.punchAt = os.clock()
	rig.punchSide = -rig.punchSide
	rig.punchBig = big
	-- swing arc in front of the fist (geometry)
	local cf = rig.root.CFrame * CFrame.new(rig.punchSide * 0.9, 0.6, -2.6)
	Fx.flash("blob", cf, Vector3.new(0.5, 0.5, 3.2), WHITE, 0.12, { Size = Vector3.new(0.15, 0.15, 6.5), Transparency = 1, CFrame = cf * CFrame.new(0, 0, -2) }, 0.3)
end

-- Instant feedback for the local player's own punch (the server echo arrives later).
function CharFx.punchNow()
	local char = player.Character
	local rig = char and rigs[char]
	if rig then
		CharFx.swing(rig, false)
	end
end

function CharFx.init()
	local function onPlayer(plr: Player)
		plr.CharacterAdded:Connect(function(char)
			task.spawn(addRig, char)
		end)
		if plr.Character then
			task.spawn(addRig, plr.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	-- server dummies
	local function watchDummies(folder: Instance)
		folder.ChildAdded:Connect(function(c)
			if c:IsA("Model") then
				task.spawn(addRig, c)
			end
		end)
		for _, c in folder:GetChildren() do
			if c:IsA("Model") then
				task.spawn(addRig, c)
			end
		end
	end
	local dummies = workspace:FindFirstChild("Dummies")
	if dummies then
		watchDummies(dummies)
	else
		workspace.ChildAdded:Connect(function(c)
			if c.Name == "Dummies" then
				watchDummies(c)
			end
		end)
	end

	CombatFx.on("swing", function(d)
		local rig = rigOf(d)
		if rig then
			local own = rig.char == player.Character
			-- the local player's punch is already playing (CharFx.punchNow): don't restart it
			if not own or os.clock() - rig.punchAt > 0.25 then
				CharFx.swing(rig, d.f == true)
			elseif d.f then
				rig.punchBig = true
			end
			if own and d.h == 0 then
				Fx.sound("swing", 0.12, 2.2)
			end
		end
	end)
	CombatFx.on("hit", function(d)
		local rig = byFighter[d.v]
		if rig and not d.b then
			rig.flinchAt = os.clock()
		end
	end)
	CombatFx.on("beam", function(d)
		local rig = rigOf(d)
		if rig then
			(rig :: any).beamAt = os.clock()
		end
	end)
	CombatFx.on("form", function(d)
		local rig = rigOf(d)
		if rig then
			applyForm(rig, d.f)
			if d.f > 0 then
				transformBurst(rig, d.f)
			else
				Fx.shell(rig.root.Position, 5, 3, Color3.fromRGB(200, 220, 255), 0.25, 0.4)
			end
		end
	end)
	CombatFx.on("dash", function(d)
		local rig = rigOf(d)
		if rig then
			-- afterimage: a few fading silhouettes (blobs) along the path
			local c1 = Fx.formColors(rig.char:GetAttribute("Form"))
			local from = d.p
			task.spawn(function()
				for i = 1, 4 do
					local at = from:Lerp(rig.root.Position, i / 4)
					Fx.flash("blob", CFrame.new(at), Vector3.new(3, 5.6, 3), c1, 0.28, { Size = Vector3.new(0.6, 6.5, 0.6), Transparency = 1 }, 0.35)
					task.wait(0.025)
				end
			end)
		end
	end)

	RunService.Stepped:Connect(function(_, dt)
		if Fx.frozen() then
			return
		end
		local now = os.clock()
		for _, rig in rigs do
			if rig.root.Parent then
				updatePose(rig, dt, now)
			end
		end
	end)

	local tagAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local now = os.clock()
		local camPos = cam.CFrame.Position
		tagAcc += dt
		local doTags = tagAcc > 0.3
		if doTags then
			tagAcc = 0
		end
		for char, rig in rigs do
			if not rig.root.Parent then
				continue
			end
			rig.surge = math.max(0, rig.surge - dt * 1.4)
			updateAura(rig, now, camPos)
			if doTags then
				local form = char:GetAttribute("Form") or 0
				if form ~= rig.shownForm then
					applyForm(rig, form)
				end
				local race = char:GetAttribute("Race")
				if race ~= rig.race then
					applyRace(rig, race)
				end
				updateTag(rig)
			end
		end
	end)
end

return CharFx
