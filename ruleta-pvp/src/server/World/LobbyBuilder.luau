--!strict
-- Builds the whole place from code: the floating lobby island, the Power Core, the ranking
-- boards and one stage per table (podiums, drum, truss, screens, entrance). No uploaded
-- assets. The look is baked into part colours and silhouettes so it still reads on the
-- lowest graphics setting; lights and post-processing are extras.
-- The wheels themselves, the beams and every effect are built by each client.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)

local LobbyBuilder = {}

export type Theme = { floor: Color3, floor2: Color3, trim: Color3, accent: Color3, prop: Color3 }
LobbyBuilder.Themes = {
	neon = { floor = Color3.fromRGB(24, 28, 66), floor2 = Color3.fromRGB(38, 46, 104), trim = Color3.fromRGB(0, 225, 255), accent = Color3.fromRGB(255, 70, 205), prop = Color3.fromRGB(90, 110, 255) },
	slime = { floor = Color3.fromRGB(20, 46, 40), floor2 = Color3.fromRGB(32, 78, 62), trim = Color3.fromRGB(160, 255, 80), accent = Color3.fromRGB(255, 225, 70), prop = Color3.fromRGB(70, 210, 120) },
	arcane = { floor = Color3.fromRGB(40, 24, 72), floor2 = Color3.fromRGB(66, 40, 118), trim = Color3.fromRGB(255, 200, 80), accent = Color3.fromRGB(200, 130, 255), prop = Color3.fromRGB(140, 90, 230) },
} :: { [string]: Theme }

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	for k, v in props do
		if k ~= "Parent" and k ~= "Tag" then
			(p :: any)[k] = v
		end
	end
	if props.Tag then
		CollectionService:AddTag(p, props.Tag)
	end
	p.Parent = props.Parent
	return p
end

-- Upright cylinder (Roblox cylinders lie along X).
local function disc(parent: Instance, cf: CFrame, radius: number, height: number, color: Color3, extra: { [string]: any }?): Part
	local props: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Parent = parent,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end

local function neon(props: { [string]: any }): Part
	props.Material = Enum.Material.Neon
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return part(props)
end

-- A world text that every client translates (tag "LocText", attribute LocKey).
local function sign(parent: BasePart, face: Enum.NormalId, key: string, color: Color3, args: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = ""
	label:SetAttribute("LocKey", key)
	if args then
		label:SetAttribute("LocIcon", args)
	end
	CollectionService:AddTag(label, "LocText")
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(12, 10, 28)
	st.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = parent
end

local function buildLighting()
	Lighting.ClockTime = 19.4
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(96, 88, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 118, 176)
	Lighting.ColorShift_Top = Color3.fromRGB(170, 150, 255)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.FogColor = Color3.fromRGB(34, 26, 70)
	Lighting.FogStart = 240
	Lighting.FogEnd = 1400
	for _, c in Lighting:GetChildren() do
		if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("PostEffect") then
			c:Destroy()
		end
	end
	local sky = Instance.new("Sky")
	sky.StarCount = 3000
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.28
	atmo.Offset = 0.2
	atmo.Color = Color3.fromRGB(130, 110, 210)
	atmo.Decay = Color3.fromRGB(60, 40, 120)
	atmo.Glare = 0
	atmo.Haze = 1.6
	atmo.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 22
	bloom.Threshold = 1.1
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Saturation = 0.12
	cc.Contrast = 0.06
	cc.Parent = Lighting
end

local function buildIsland(root: Instance, tableCount: number)
	local floorA = Color3.fromRGB(30, 32, 74)
	local floorB = Color3.fromRGB(44, 48, 108)
	disc(root, CFrame.new(0, -3, 0), Layout.IslandRadius, 6, floorA, { Name = "Island" })
	-- underside
	disc(root, CFrame.new(0, -12, 0), Layout.IslandRadius * 0.82, 12, Color3.fromRGB(20, 20, 50), { Name = "Under1", CanCollide = false })
	disc(root, CFrame.new(0, -28, 0), Layout.IslandRadius * 0.5, 20, Color3.fromRGB(14, 14, 38), { Name = "Under2", CanCollide = false })
	-- plaza and inlays (thin discs stacked 0.04 apart so they never z-fight)
	disc(root, CFrame.new(0, 0.03, 0), 64, 0.06, floorB, { Name = "Plaza", CanCollide = false })
	disc(root, CFrame.new(0, 0.07, 0), 50, 0.06, floorA, { Name = "PlazaInner", CanCollide = false })
	disc(root, CFrame.new(0, 0.11, 0), 48.5, 0.06, Color3.fromRGB(0, 225, 255), { Name = "PlazaRing", Material = Enum.Material.Neon, CanCollide = false })
	disc(root, CFrame.new(0, 0.15, 0), 47.4, 0.06, floorB, { Name = "PlazaFill", CanCollide = false })
	disc(root, CFrame.new(0, 0.19, 0), 22, 0.06, Color3.fromRGB(255, 70, 205), { Name = "CoreRing", Material = Enum.Material.Neon, CanCollide = false })
	disc(root, CFrame.new(0, 0.23, 0), 20.8, 0.06, floorA, { Name = "CoreFloor", CanCollide = false })
	-- edge glow
	for i = 1, 36 do
		local a = i / 36 * math.pi * 2
		local pos = Vector3.new(math.sin(a) * (Layout.IslandRadius - 1.5), 0.6, math.cos(a) * (Layout.IslandRadius - 1.5))
		neon({ Name = "Edge", Size = Vector3.new(24, 1.2, 1.2), CFrame = CFrame.lookAt(pos, Vector3.new(0, 0.6, 0)), Color = if i % 2 == 0 then Color3.fromRGB(0, 225, 255) else Color3.fromRGB(255, 70, 205), Parent = root })
		-- invisible wall
		part({ Name = "Wall", Size = Vector3.new(28, 40, 1), CFrame = CFrame.lookAt(pos + Vector3.new(0, 19, 0), Vector3.new(0, pos.Y + 19, 0)), Transparency = 1, CanQuery = false, Parent = root })
	end
	-- paths to the tables
	for i = 1, tableCount do
		local cf = Layout.tableCFrame(i, tableCount)
		local mid = cf.Position * 0.62
		local theme = LobbyBuilder.Themes[Config.Tables[i].theme]
		part({ Name = "Path", Size = Vector3.new(14, 0.08, 40), CFrame = CFrame.lookAt(Vector3.new(mid.X, 0.04, mid.Z), Vector3.new(0, 0.04, 0)), Color = floorB, CanCollide = false, Parent = root })
		for side = -1, 1, 2 do
			local edge = CFrame.lookAt(Vector3.new(mid.X, 0.1, mid.Z), Vector3.new(0, 0.1, 0)) * CFrame.new(side * 7.4, 0, 0)
			neon({ Name = "PathEdge", Size = Vector3.new(0.6, 0.12, 40), CFrame = edge, Color = theme.trim, Parent = root })
			-- lamp post
			local post = edge * CFrame.new(side * 1.6, 0, 0)
			part({ Name = "Post", Size = Vector3.new(0.8, 12, 0.8), CFrame = post * CFrame.new(0, 6, 0), Color = Color3.fromRGB(52, 56, 120), Parent = root })
			local bulb = neon({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = post * CFrame.new(0, 12.6, 0), Color = theme.trim, Parent = root })
			local light = Instance.new("PointLight")
			light.Color = theme.trim
			light.Range = 22
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = bulb
		end
	end
	-- far planets: silhouettes against the sky
	local planets: { { any } } = {
		{ Vector3.new(420, 210, -520), 150, Color3.fromRGB(255, 120, 170) },
		{ Vector3.new(-560, 140, 300), 110, Color3.fromRGB(110, 200, 255) },
		{ Vector3.new(-300, 320, -640), 70, Color3.fromRGB(255, 215, 120) },
		{ Vector3.new(640, 90, 420), 90, Color3.fromRGB(170, 130, 255) },
	}
	for i, pl in planets do
		local pos, size, color = pl[1] :: Vector3, pl[2] :: number, pl[3] :: Color3
		part({ Name = "Planet" .. i, Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = pos, Color = color, CanCollide = false, CanQuery = false, Parent = root })
		if i % 2 == 1 then
			disc(root, CFrame.new(pos) * CFrame.Angles(math.rad(24), 0, math.rad(12)), size * 0.95, 1.5, color:Lerp(Color3.new(1, 1, 1), 0.45), { Name = "PlanetRing" .. i, CanCollide = false, CanQuery = false, Transparency = 0.25 })
		end
	end
end

local function buildCore(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "PowerCore"
	folder.Parent = root
	local navy = Color3.fromRGB(52, 56, 120)
	disc(folder, CFrame.new(0, 0.9, 0), 9, 1.4, navy, { Name = "Base1" })
	disc(folder, CFrame.new(0, 2.2, 0), 7, 1.2, Color3.fromRGB(70, 76, 160), { Name = "Base2" })
	disc(folder, CFrame.new(0, 3.3, 0), 5, 1, Color3.fromRGB(0, 225, 255), { Name = "Base3", Material = Enum.Material.Neon })
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local base = Vector3.new(math.sin(a) * 6.4, 0, math.cos(a) * 6.4)
		part({ Name = "Arm", Size = Vector3.new(1.2, 9, 1.2), CFrame = CFrame.lookAt(base + Vector3.new(0, 6, 0), Vector3.new(0, 14, 0)) * CFrame.Angles(math.rad(90), 0, 0), Color = navy, Parent = folder })
	end
	local core = neon({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one * Layout.CoreRadius * 2, Position = Layout.CorePos, Color = Color3.fromRGB(0, 235, 255), Tag = "PowerCore", Parent = folder })
	core.CanQuery = true
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(0, 235, 255)
	light.Range = 40
	light.Brightness = 2
	light.Shadows = false
	light.Parent = core
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = Config.Core.range + 8
	click.Parent = core
	-- title plate
	local plate = part({ Name = "CoreSign", Size = Vector3.new(12, 2.6, 0.4), CFrame = CFrame.new(0, 19.5, 0), Color = Color3.fromRGB(20, 20, 50), CanCollide = false, Parent = folder })
	sign(plate, Enum.NormalId.Front, "world.core", Color3.fromRGB(0, 235, 255))
	sign(plate, Enum.NormalId.Back, "world.core", Color3.fromRGB(0, 235, 255))
end

local function buildSpawns(root: Instance)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + math.pi / 6
		local s = Instance.new("SpawnLocation")
		s.Name = "Spawn" .. i
		s.Anchored = true
		s.Size = Vector3.new(6, 0.4, 6)
		s.Transparency = 1
		s.CanCollide = false
		s.CanQuery = false
		s.Neutral = true
		s.Duration = 0
		s.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * Layout.SpawnRadius, 0.5, math.cos(a) * Layout.SpawnRadius), Vector3.new(0, 0.5, 0))
		s.Parent = root
	end
end

local function buildBoards(root: Instance, tableCount: number)
	local kinds = { "wins", "season", "weekly" }
	for i, kind in kinds do
		local a = ((i - 1) * 2 + 0.5) / tableCount * math.pi * 2
		local pos = Vector3.new(math.sin(a) * 58, 0, math.cos(a) * 58)
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		part({ Name = "BoardLegL", Size = Vector3.new(1, 5, 1), CFrame = cf * CFrame.new(-6.5, 2.5, 0), Color = Color3.fromRGB(52, 56, 120), Parent = root })
		part({ Name = "BoardLegR", Size = Vector3.new(1, 5, 1), CFrame = cf * CFrame.new(6.5, 2.5, 0), Color = Color3.fromRGB(52, 56, 120), Parent = root })
		neon({ Name = "BoardFrame", Size = Vector3.new(15.2, 11.2, 0.5), CFrame = cf * CFrame.new(0, 10, 0.2), Color = ({ Color3.fromRGB(255, 205, 60), Color3.fromRGB(255, 70, 205), Color3.fromRGB(0, 225, 255) })[i], Parent = root })
		local board = part({ Name = "Board_" .. kind, Size = Vector3.new(14.4, 10.4, 0.6), CFrame = cf * CFrame.new(0, 10, 0), Color = Color3.fromRGB(18, 18, 46), Tag = "Board", Parent = root })
		board:SetAttribute("Kind", kind)
	end
end

local function buildTable(root: Instance, index: number, count: number): { origin: CFrame, folder: Folder, prompt: ProximityPrompt }
	local def = Config.Tables[index]
	local theme = LobbyBuilder.Themes[def.theme]
	local origin = Layout.tableCFrame(index, count)
	local folder = Instance.new("Folder")
	folder.Name = "Table_" .. def.id
	folder.Parent = root

	local function at(theta: number, r: number, y: number): Vector3
		return origin:PointToWorldSpace(Layout.polar(theta, r, y))
	end
	local up = origin.Position

	-- stage
	local stage = disc(folder, origin * CFrame.new(0, Layout.StageTop / 2, 0), Layout.StageRadius, Layout.StageTop, theme.floor, { Name = "Stage", Tag = "TableRoot" })
	stage:SetAttribute("TableId", def.id)
	stage:SetAttribute("Index", index)
	disc(folder, origin * CFrame.new(0, Layout.StageTop + 0.03, 0), Layout.StageRadius - 0.6, 0.06, theme.trim, { Name = "StageRim", Material = Enum.Material.Neon, CanCollide = false })
	disc(folder, origin * CFrame.new(0, Layout.StageTop + 0.07, 0), Layout.StageRadius - 1.4, 0.06, theme.floor2, { Name = "StageTop", CanCollide = false })
	disc(folder, origin * CFrame.new(0, Layout.StageTop + 0.11, 0), 14.2, 0.06, theme.accent, { Name = "InnerRing", Material = Enum.Material.Neon, CanCollide = false })
	disc(folder, origin * CFrame.new(0, Layout.StageTop + 0.15, 0), 13.5, 0.06, theme.floor, { Name = "InnerFloor", CanCollide = false })
	-- the drum the wheel sits on
	disc(folder, origin * CFrame.new(0, (Layout.DrumTop + Layout.StageTop) / 2, 0), Layout.DrumRadius, Layout.DrumTop - Layout.StageTop, theme.floor2, { Name = "Drum" })
	disc(folder, origin * CFrame.new(0, Layout.DrumTop - 0.35, 0), Layout.DrumRadius + 0.35, 0.3, theme.trim, { Name = "DrumBand", Material = Enum.Material.Neon, CanCollide = false })
	disc(folder, origin * CFrame.new(0, Layout.StageTop + 0.5, 0), Layout.DrumRadius + 0.9, 0.5, theme.floor, { Name = "DrumFoot", CanCollide = false })

	-- podiums
	for seat = 1, Config.Seats do
		local cf = Layout.podiumCFrame(origin, seat, Config.Seats)
		disc(folder, cf * CFrame.new(0, -(Layout.PodiumTop - Layout.StageTop) / 2, 0), 2.7, Layout.PodiumTop - Layout.StageTop, theme.floor2, { Name = "Podium" .. seat })
		local top = disc(folder, cf * CFrame.new(0, 0.03, 0), 2.45, 0.08, theme.trim, { Name = "PodiumTop" .. seat, Material = Enum.Material.Neon, CanCollide = false, Tag = "PodiumTop" })
		top:SetAttribute("TableId", def.id)
		top:SetAttribute("Seat", seat)
		-- desk in front of the player (towards the wheel): name + lives, drawn by the client
		local desk = part({ Name = "Desk" .. seat, Size = Vector3.new(4.6, 2.5, 0.5), CFrame = cf * CFrame.new(0, 1.25 - 0.1, -2.7) * CFrame.Angles(math.rad(-14), 0, 0), Color = Color3.fromRGB(16, 16, 40), Tag = "PodiumDesk", Parent = folder })
		desk:SetAttribute("TableId", def.id)
		desk:SetAttribute("Seat", seat)
		neon({ Name = "DeskTrim" .. seat, Size = Vector3.new(4.9, 0.25, 0.7), CFrame = desk.CFrame * CFrame.new(0, 1.3, 0), Color = theme.accent, Parent = folder })
	end

	-- truss: 4 pillars + a ring of 12 beams + a lamp per seat
	local steel = Color3.fromRGB(58, 62, 130)
	for i = 1, 4 do
		local theta = (i - 0.5) / 4 * math.pi * 2
		local base = at(theta, Layout.StageRadius - 1.6, 0)
		part({ Name = "Pillar" .. i, Size = Vector3.new(1.6, Layout.TrussY + 1, 1.6), CFrame = CFrame.new(base + Vector3.new(0, (Layout.TrussY + 1) / 2, 0)) * origin.Rotation, Color = steel, Parent = folder })
		neon({ Name = "PillarGlow" .. i, Size = Vector3.new(0.5, Layout.TrussY - 3, 1.8), CFrame = CFrame.new(base + Vector3.new(0, Layout.TrussY / 2, 0)) * origin.Rotation, Color = theme.trim, Parent = folder })
		-- arm from the pillar to the ring
		local armFrom = base + Vector3.new(0, Layout.TrussY, 0)
		local armTo = at(theta, Layout.TrussRadius, Layout.TrussY)
		part({ Name = "Arm" .. i, Size = Vector3.new(1, 1, (armFrom - armTo).Magnitude + 1), CFrame = CFrame.lookAt((armFrom + armTo) / 2, armTo), Color = steel, CanCollide = false, Parent = folder })
	end
	for i = 1, 12 do
		local a0, a1 = (i - 1) / 12 * math.pi * 2, i / 12 * math.pi * 2
		local p0, p1 = at(a0, Layout.TrussRadius, Layout.TrussY), at(a1, Layout.TrussRadius, Layout.TrussY)
		part({ Name = "Truss" .. i, Size = Vector3.new(1, 1, (p0 - p1).Magnitude + 0.6), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = steel, CanCollide = false, Parent = folder })
		neon({ Name = "TrussGlow" .. i, Size = Vector3.new(0.4, 0.4, (p0 - p1).Magnitude), CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.new(0, -0.7, 0), Color = if i % 2 == 0 then theme.trim else theme.accent, Parent = folder })
	end
	for seat = 1, Config.Seats do
		local theta = Layout.seatAngle(seat, Config.Seats)
		local head = at(theta, Layout.TrussRadius - 0.4, Layout.TrussY - 1.3)
		local target = Layout.seatCFrame(origin, seat, Config.Seats).Position
		local lamp = part({ Name = "Lamp" .. seat, Size = Vector3.new(1.8, 1.8, 2.6), CFrame = CFrame.lookAt(head, target), Color = Color3.fromRGB(30, 32, 70), CanCollide = false, Tag = "SeatLamp", Parent = folder })
		lamp:SetAttribute("TableId", def.id)
		lamp:SetAttribute("Seat", seat)
		neon({ Name = "LampLens" .. seat, Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), CFrame = lamp.CFrame * CFrame.new(0, 0, -1.2), Color = Color3.fromRGB(255, 250, 220), Parent = folder })
	end

	-- four screens over the wheel (the client writes on them)
	local hub = part({ Name = "ScreenHub", Size = Vector3.new(7.6, 4.6, 7.6), CFrame = origin * CFrame.new(0, Layout.ScreenY, 0), Color = Color3.fromRGB(14, 14, 36), CanCollide = false, Tag = "TableScreen", Parent = folder })
	hub:SetAttribute("TableId", def.id)
	neon({ Name = "ScreenTop", Size = Vector3.new(8.2, 0.4, 8.2), CFrame = hub.CFrame * CFrame.new(0, 2.5, 0), Color = theme.trim, Parent = folder })
	neon({ Name = "ScreenBottom", Size = Vector3.new(8.2, 0.4, 8.2), CFrame = hub.CFrame * CFrame.new(0, -2.5, 0), Color = theme.accent, Parent = folder })
	part({ Name = "ScreenRod", Size = Vector3.new(0.6, Layout.TrussY - Layout.ScreenY - 2, 0.6), CFrame = origin * CFrame.new(0, (Layout.TrussY + Layout.ScreenY + 2.5) / 2, 0), Color = steel, CanCollide = false, Parent = folder })
	for i = 1, 4 do
		local theta = (i - 0.5) / 4 * math.pi * 2
		local p0, p1 = at(theta, Layout.TrussRadius, Layout.TrussY), up + Vector3.new(0, Layout.TrussY, 0)
		part({ Name = "Spoke" .. i, Size = Vector3.new(0.6, 0.6, (p0 - p1).Magnitude), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = steel, CanCollide = false, Parent = folder })
	end

	-- entrance arch on the lobby side, with the mode sign
	local archZ = -(Layout.StageRadius + 1.5)
	part({ Name = "ArchL", Size = Vector3.new(1.8, 13, 1.8), CFrame = origin * CFrame.new(-8, 6.5, archZ), Color = steel, Parent = folder })
	part({ Name = "ArchR", Size = Vector3.new(1.8, 13, 1.8), CFrame = origin * CFrame.new(8, 6.5, archZ), Color = steel, Parent = folder })
	neon({ Name = "ArchGlowL", Size = Vector3.new(2.1, 11, 0.5), CFrame = origin * CFrame.new(-8, 6.2, archZ - 0.8), Color = theme.trim, Parent = folder })
	neon({ Name = "ArchGlowR", Size = Vector3.new(2.1, 11, 0.5), CFrame = origin * CFrame.new(8, 6.2, archZ - 0.8), Color = theme.trim, Parent = folder })
	local banner = part({ Name = "Banner", Size = Vector3.new(19, 4.6, 1), CFrame = origin * CFrame.new(0, 14.6, archZ), Color = Color3.fromRGB(16, 16, 42), CanCollide = false, Parent = folder })
	neon({ Name = "BannerTrim", Size = Vector3.new(19.6, 5.2, 0.5), CFrame = origin * CFrame.new(0, 14.6, archZ + 0.1), Color = theme.accent, Parent = folder })
	local mode = Config.ModeById[def.mode]
	local key = if def.kind == "flex" then "world.table_flex" else "mode." .. def.mode .. ".name"
	local icon = if def.kind == "flex" then "🔒" else mode.icon
	sign(banner, Enum.NormalId.Front, key, Color3.new(1, 1, 1), icon)
	banner:SetAttribute("TableId", def.id)
	CollectionService:AddTag(banner, "TableBanner")
	-- ramp so people can walk up and watch
	part({ Name = "Ramp", Size = Vector3.new(14, 0.4, 5), CFrame = origin * CFrame.new(0, Layout.StageTop / 2 - 0.05, archZ - 1) * CFrame.Angles(math.rad(-11), 0, 0), Color = theme.floor2, Parent = folder })

	-- sit-down prompt
	local anchor = part({ Name = "JoinAnchor", Size = Vector3.new(2, 2, 2), CFrame = origin * CFrame.new(0, 4, archZ + 3), Transparency = 1, CanCollide = false, CanQuery = false, Parent = folder })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JoinPrompt"
	prompt.ObjectText = ""
	prompt.ActionText = "Play"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("LocKey", "world.prompt_play")
	prompt:SetAttribute("TableId", def.id)
	CollectionService:AddTag(prompt, "LocPrompt")
	prompt.Parent = anchor

	-- theme props around the stage
	for i = 1, 6 do
		local theta = (i + 0.5) / 7 * math.pi * 2
		local base = at(theta, Layout.StageRadius + 4.5, 0)
		if def.theme == "neon" then
			part({ Name = "Pylon" .. i, Size = Vector3.new(2.2, 9 + (i % 3) * 3, 2.2), CFrame = CFrame.new(base + Vector3.new(0, (9 + (i % 3) * 3) / 2, 0)) * CFrame.Angles(0, theta, 0), Color = theme.prop, Parent = folder })
			neon({ Name = "PylonCap" .. i, Size = Vector3.new(2.6, 0.8, 2.6), CFrame = CFrame.new(base + Vector3.new(0, 9 + (i % 3) * 3 + 0.4, 0)) * CFrame.Angles(0, theta, 0), Color = if i % 2 == 0 then theme.trim else theme.accent, Parent = folder })
		elseif def.theme == "slime" then
			disc(folder, CFrame.new(base + Vector3.new(0, 3, 0)), 2.4, 6, Color3.fromRGB(190, 230, 235), { Name = "Vat" .. i, Material = Enum.Material.Glass, Transparency = 0.35 })
			disc(folder, CFrame.new(base + Vector3.new(0, 2.4, 0)), 2.1, 4.4, theme.trim, { Name = "Goo" .. i, Material = Enum.Material.Neon, CanCollide = false })
			disc(folder, CFrame.new(base + Vector3.new(0, 6.3, 0)), 2.7, 0.7, theme.prop, { Name = "VatLid" .. i, CanCollide = false })
			neon({ Name = "Bubble" .. i, Shape = Enum.PartType.Ball, Size = Vector3.one * (1 + i % 3 * 0.5), Position = base + Vector3.new(0.8, 8 + i % 3, 0.4), Color = theme.accent, Parent = folder })
		else
			part({ Name = "Crystal" .. i, Size = Vector3.new(2.4, 8 + (i % 3) * 2.5, 2.4), CFrame = CFrame.new(base + Vector3.new(0, 3.6, 0)) * CFrame.Angles(math.rad(12 + i * 5), theta, math.rad(8)), Color = theme.accent, Material = Enum.Material.Glass, Transparency = 0.15, Parent = folder })
			neon({ Name = "Rune" .. i, Size = Vector3.one * 1.6, CFrame = CFrame.new(base + Vector3.new(0, 11 + (i % 2) * 2, 0)) * CFrame.Angles(math.rad(45), theta, math.rad(45)), Color = theme.trim, Parent = folder })
		end
	end

	return { origin = origin, folder = folder, prompt = prompt }
end

export type World = { tables: { [string]: { origin: CFrame, folder: Folder, prompt: ProximityPrompt, index: number } }, corePos: Vector3 }

function LobbyBuilder.build(): World
	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "World"
	buildLighting()
	local count = #Config.Tables
	buildIsland(root, count)
	buildCore(root)
	buildSpawns(root)
	buildBoards(root, count)
	local world: World = { tables = {}, corePos = Layout.CorePos }
	for i, def in Config.Tables do
		local t = buildTable(root, i, count)
		world.tables[def.id] = { origin = t.origin, folder = t.folder, prompt = t.prompt, index = i }
	end
	-- bots live here (created by the Tables service)
	local bots = Instance.new("Folder")
	bots.Name = "Bots"
	bots.Parent = root
	root.Parent = workspace
	return world
end

return LobbyBuilder
