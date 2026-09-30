--!strict
-- Builds the whole world from code: one themed planet per Config.Planets entry (ground, painted
-- patches, rim mountains, plaza, warp gate, training zones, enemy camps, boss arena, props,
-- landmarks) plus the PvP coliseum, wish altar and world-boss crater on planet 1.
-- Looks are carried by colour, shape and silhouette (no textures, no uploaded assets), so the
-- world still reads at graphics quality 1 where shadows, glow and post-processing are off.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local WorldBuilder = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

type Theme = {
	ground: Color3,
	groundMat: Enum.Material,
	patchA: Color3,
	patchB: Color3,
	path: Color3,
	plaza: Color3,
	plazaTrim: Color3,
	rock: Color3,
	cliffLow: Color3,
	cliffMid: Color3,
	cliffTop: Color3,
	accent: Color3, -- bright (crystals, lamps)
	accent2: Color3,
	foliage: { Color3 },
	trunk: Color3,
	prop: string,
}

local Themes: { [string]: Theme } = {
	meadow = {
		ground = Color3.fromRGB(96, 178, 84),
		groundMat = Enum.Material.Grass,
		patchA = Color3.fromRGB(124, 200, 98),
		patchB = Color3.fromRGB(74, 150, 78),
		path = Color3.fromRGB(226, 198, 142),
		plaza = Color3.fromRGB(188, 172, 140),
		plazaTrim = Color3.fromRGB(255, 176, 64),
		rock = Color3.fromRGB(140, 142, 152),
		cliffLow = Color3.fromRGB(84, 120, 96),
		cliffMid = Color3.fromRGB(112, 156, 112),
		cliffTop = Color3.fromRGB(186, 222, 150),
		accent = Color3.fromRGB(90, 230, 255),
		accent2 = Color3.fromRGB(255, 214, 72),
		foliage = { Color3.fromRGB(64, 160, 72), Color3.fromRGB(96, 190, 84), Color3.fromRGB(255, 150, 190) },
		trunk = Color3.fromRGB(122, 84, 58),
		prop = "tree",
	},
	volcano = {
		ground = Color3.fromRGB(84, 58, 56),
		groundMat = Enum.Material.Basalt,
		patchA = Color3.fromRGB(116, 70, 56),
		patchB = Color3.fromRGB(54, 40, 44),
		path = Color3.fromRGB(150, 116, 100),
		plaza = Color3.fromRGB(70, 60, 66),
		plazaTrim = Color3.fromRGB(255, 120, 40),
		rock = Color3.fromRGB(60, 46, 48),
		cliffLow = Color3.fromRGB(48, 34, 38),
		cliffMid = Color3.fromRGB(92, 50, 44),
		cliffTop = Color3.fromRGB(255, 120, 40),
		accent = Color3.fromRGB(255, 130, 30),
		accent2 = Color3.fromRGB(255, 220, 90),
		foliage = { Color3.fromRGB(40, 30, 34), Color3.fromRGB(70, 44, 40), Color3.fromRGB(255, 100, 40) },
		trunk = Color3.fromRGB(40, 30, 32),
		prop = "spire",
	},
	ice = {
		ground = Color3.fromRGB(214, 234, 250),
		groundMat = Enum.Material.Snow,
		patchA = Color3.fromRGB(246, 250, 255),
		patchB = Color3.fromRGB(170, 210, 242),
		path = Color3.fromRGB(136, 184, 226),
		plaza = Color3.fromRGB(150, 186, 222),
		plazaTrim = Color3.fromRGB(90, 200, 255),
		rock = Color3.fromRGB(150, 190, 225),
		cliffLow = Color3.fromRGB(86, 136, 196),
		cliffMid = Color3.fromRGB(150, 200, 240),
		cliffTop = Color3.fromRGB(250, 252, 255),
		accent = Color3.fromRGB(120, 235, 255),
		accent2 = Color3.fromRGB(200, 160, 255),
		foliage = { Color3.fromRGB(60, 130, 140), Color3.fromRGB(240, 250, 255), Color3.fromRGB(110, 200, 230) },
		trunk = Color3.fromRGB(90, 80, 100),
		prop = "pine",
	},
	storm = {
		ground = Color3.fromRGB(104, 116, 150),
		groundMat = Enum.Material.Slate,
		patchA = Color3.fromRGB(134, 140, 180),
		patchB = Color3.fromRGB(74, 84, 120),
		path = Color3.fromRGB(210, 212, 230),
		plaza = Color3.fromRGB(80, 90, 130),
		plazaTrim = Color3.fromRGB(255, 232, 90),
		rock = Color3.fromRGB(70, 78, 108),
		cliffLow = Color3.fromRGB(50, 56, 88),
		cliffMid = Color3.fromRGB(92, 100, 150),
		cliffTop = Color3.fromRGB(200, 210, 245),
		accent = Color3.fromRGB(255, 236, 100),
		accent2 = Color3.fromRGB(120, 230, 255),
		foliage = { Color3.fromRGB(90, 100, 150), Color3.fromRGB(150, 160, 210), Color3.fromRGB(255, 236, 100) },
		trunk = Color3.fromRGB(60, 64, 90),
		prop = "pylon",
	},
	desert = {
		ground = Color3.fromRGB(226, 190, 120),
		groundMat = Enum.Material.Sand,
		patchA = Color3.fromRGB(240, 210, 146),
		patchB = Color3.fromRGB(200, 160, 100),
		path = Color3.fromRGB(150, 120, 90),
		plaza = Color3.fromRGB(124, 130, 120),
		plazaTrim = Color3.fromRGB(230, 70, 50),
		rock = Color3.fromRGB(170, 130, 96),
		cliffLow = Color3.fromRGB(150, 96, 70),
		cliffMid = Color3.fromRGB(200, 136, 90),
		cliffTop = Color3.fromRGB(246, 214, 150),
		accent = Color3.fromRGB(255, 190, 60),
		accent2 = Color3.fromRGB(230, 70, 50),
		foliage = { Color3.fromRGB(70, 150, 96), Color3.fromRGB(110, 180, 110), Color3.fromRGB(255, 120, 150) },
		trunk = Color3.fromRGB(96, 104, 110),
		prop = "cactus",
	},
	wasteland = {
		ground = Color3.fromRGB(176, 112, 84),
		groundMat = Enum.Material.Ground,
		patchA = Color3.fromRGB(200, 136, 100),
		patchB = Color3.fromRGB(140, 86, 72),
		path = Color3.fromRGB(110, 80, 96),
		plaza = Color3.fromRGB(110, 96, 120),
		plazaTrim = Color3.fromRGB(120, 230, 255),
		rock = Color3.fromRGB(130, 84, 70),
		cliffLow = Color3.fromRGB(104, 60, 64),
		cliffMid = Color3.fromRGB(170, 96, 80),
		cliffTop = Color3.fromRGB(240, 170, 120),
		accent = Color3.fromRGB(120, 230, 255),
		accent2 = Color3.fromRGB(255, 90, 200),
		foliage = { Color3.fromRGB(120, 70, 66), Color3.fromRGB(170, 110, 90), Color3.fromRGB(120, 230, 255) },
		trunk = Color3.fromRGB(90, 60, 60),
		prop = "spire",
	},
	ruins = {
		ground = Color3.fromRGB(108, 116, 118),
		groundMat = Enum.Material.Concrete,
		patchA = Color3.fromRGB(130, 140, 140),
		patchB = Color3.fromRGB(84, 92, 96),
		path = Color3.fromRGB(60, 66, 74),
		plaza = Color3.fromRGB(74, 82, 90),
		plazaTrim = Color3.fromRGB(120, 255, 140),
		rock = Color3.fromRGB(90, 96, 100),
		cliffLow = Color3.fromRGB(52, 58, 66),
		cliffMid = Color3.fromRGB(86, 96, 104),
		cliffTop = Color3.fromRGB(150, 164, 170),
		accent = Color3.fromRGB(120, 255, 140),
		accent2 = Color3.fromRGB(255, 80, 80),
		foliage = { Color3.fromRGB(70, 78, 86), Color3.fromRGB(110, 120, 126), Color3.fromRGB(120, 255, 140) },
		trunk = Color3.fromRGB(50, 56, 62),
		prop = "tower",
	},
	candy = {
		ground = Color3.fromRGB(255, 190, 220),
		groundMat = Enum.Material.SmoothPlastic,
		patchA = Color3.fromRGB(255, 220, 236),
		patchB = Color3.fromRGB(180, 236, 232),
		path = Color3.fromRGB(255, 250, 230),
		plaza = Color3.fromRGB(150, 226, 220),
		plazaTrim = Color3.fromRGB(255, 120, 190),
		rock = Color3.fromRGB(210, 170, 240),
		cliffLow = Color3.fromRGB(230, 130, 190),
		cliffMid = Color3.fromRGB(255, 170, 210),
		cliffTop = Color3.fromRGB(255, 250, 250),
		accent = Color3.fromRGB(120, 240, 230),
		accent2 = Color3.fromRGB(255, 240, 120),
		foliage = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(120, 230, 220), Color3.fromRGB(255, 240, 120) },
		trunk = Color3.fromRGB(255, 250, 245),
		prop = "lolly",
	},
	future = {
		ground = Color3.fromRGB(70, 66, 80),
		groundMat = Enum.Material.Concrete,
		patchA = Color3.fromRGB(96, 88, 104),
		patchB = Color3.fromRGB(48, 44, 58),
		path = Color3.fromRGB(120, 110, 120),
		plaza = Color3.fromRGB(56, 56, 70),
		plazaTrim = Color3.fromRGB(120, 255, 170),
		rock = Color3.fromRGB(60, 56, 70),
		cliffLow = Color3.fromRGB(36, 32, 44),
		cliffMid = Color3.fromRGB(80, 60, 70),
		cliffTop = Color3.fromRGB(230, 120, 100),
		accent = Color3.fromRGB(120, 255, 170),
		accent2 = Color3.fromRGB(255, 90, 90),
		foliage = { Color3.fromRGB(56, 52, 66), Color3.fromRGB(96, 90, 104), Color3.fromRGB(255, 90, 90) },
		trunk = Color3.fromRGB(40, 38, 48),
		prop = "tower",
	},
	void = {
		ground = Color3.fromRGB(44, 30, 76),
		groundMat = Enum.Material.Slate,
		patchA = Color3.fromRGB(72, 42, 120),
		patchB = Color3.fromRGB(24, 16, 44),
		path = Color3.fromRGB(120, 86, 190),
		plaza = Color3.fromRGB(34, 24, 60),
		plazaTrim = Color3.fromRGB(255, 80, 210),
		rock = Color3.fromRGB(30, 20, 52),
		cliffLow = Color3.fromRGB(18, 12, 34),
		cliffMid = Color3.fromRGB(56, 34, 100),
		cliffTop = Color3.fromRGB(255, 80, 210),
		accent = Color3.fromRGB(255, 80, 210),
		accent2 = Color3.fromRGB(90, 240, 255),
		foliage = { Color3.fromRGB(80, 40, 140), Color3.fromRGB(255, 80, 210), Color3.fromRGB(90, 240, 255) },
		trunk = Color3.fromRGB(24, 16, 40),
		prop = "shard",
	},
}
WorldBuilder.Themes = Themes

---------------------------------------------------------------------------
-- Part helpers
---------------------------------------------------------------------------
local partCount = 0

local function base(parent: Instance, className: string): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	p.Parent = parent
	partCount += 1
	return p
end

type Opts = { mat: Enum.Material?, collide: boolean?, shadow: boolean?, trans: number?, name: string?, anim: string? }

local function finish(p: BasePart, color: Color3, o: Opts?)
	p.Color = color
	if o then
		if o.mat then
			p.Material = o.mat
		end
		if o.collide == false then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
		if o.shadow then
			p.CastShadow = true
		end
		if o.trans then
			p.Transparency = o.trans
		end
		if o.name then
			p.Name = o.name
		end
		if o.anim then
			p:SetAttribute("KiwAnim", o.anim)
		end
	end
end

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, o: Opts?): BasePart
	local p = base(parent, "Part")
	p.Size = size
	p.CFrame = cf
	finish(p, color, o)
	return p
end

-- Upright cylinder: centre position, radius, height.
local function cyl(parent: Instance, pos: Vector3, radius: number, height: number, color: Color3, o: Opts?): BasePart
	local p = base(parent, "Part") :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	finish(p, color, o)
	return p
end

-- Cylinder along any axis (cf's X axis is the cylinder axis after the helper's rotation).
local function rod(parent: Instance, cf: CFrame, radius: number, length: number, color: Color3, o: Opts?): BasePart
	local p = base(parent, "Part") :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, radius * 2, radius * 2)
	p.CFrame = cf
	finish(p, color, o)
	return p
end

local function ball(parent: Instance, pos: Vector3, radius: number, color: Color3, o: Opts?): BasePart
	local p = base(parent, "Part") :: Part
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	p.CFrame = CFrame.new(pos)
	finish(p, color, o)
	return p
end

-- Ellipsoid (built-in sphere mesh stretched to the part size).
local function blob(parent: Instance, cf: CFrame, size: Vector3, color: Color3, o: Opts?): BasePart
	local p = base(parent, "Part")
	p.Size = size
	p.CFrame = cf
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	finish(p, color, o)
	return p
end

local function _wedge(parent: Instance, cf: CFrame, size: Vector3, color: Color3, o: Opts?): BasePart
	local p = base(parent, "WedgePart")
	p.Size = size
	p.CFrame = cf
	finish(p, color, o)
	return p
end

local NEON: Opts = { mat = Enum.Material.Neon, collide = false }
local DECOR: Opts = { collide = false }

-- A floating ring. The server only places an invisible marker; each client builds the ring
-- from thin segments and animates it (WorldFx), so it costs one replicated part.
local function ring(parent: Instance, pos: Vector3, radius: number, thick: number, color: Color3, motion: string, phase: number?)
	local p = base(parent, "Part")
	p.Name = "Ring"
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = color
	p:SetAttribute("KiwAnim", "ring")
	p:SetAttribute("KiwRadius", radius)
	p:SetAttribute("KiwThick", thick)
	p:SetAttribute("KiwMotion", motion)
	p:SetAttribute("KiwPhase", phase or 0)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.2
	l.Shadows = false
	l.Parent = parent
end

-- A board with localized text lines. lines: { { key = "zone.x" } | { text = "x4" } }
local function sign(parent: Instance, cf: CFrame, size: Vector3, color: Color3, lines: { { key: string?, text: string?, color: Color3?, n: string? } }): BasePart
	local board = block(parent, cf, size, color, { name = "Sign" })
	board.CanCollide = false
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		gui.Brightness = 1
		gui.Parent = board
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = gui
		for i, line in lines do
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, 0, if i == 1 then 0.5 else 0.5 / math.max(1, #lines - 1), 0)
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.TextColor3 = line.color or Color3.new(1, 1, 1)
			t.Text = line.text or ""
			t.LayoutOrder = i
			if line.key then
				t:SetAttribute("LocKey", line.key)
				if line.n then
					t:SetAttribute("LocN", line.n)
				end
			end
			local s = Instance.new("UIStroke")
			s.Thickness = 3
			s.Color = Color3.fromRGB(20, 16, 36)
			s.Parent = t
			t.Parent = gui
		end
	end
	return board
end

-- Small two-post sign (eye level, never bigger than a doorway).
local function standSign(parent: Instance, pos: Vector3, facing: Vector3, color: Color3, lines: { any }, width: number?)
	local w = math.min(width or 12, 12)
	local look = CFrame.lookAt(pos, pos + facing)
	for _, side in { -1, 1 } do
		block(parent, look * CFrame.new(side * (w / 2 - 0.4), 2.6, 0), Vector3.new(0.7, 5.2, 0.7), Color3.fromRGB(60, 52, 70), DECOR)
	end
	sign(parent, look * CFrame.new(0, 5.6, 0), Vector3.new(w, 3, 0.5), color, lines)
end

-- Entrance gate: two pillars and a name board high overhead, where a path reaches a place.
-- It marks the spot from far away without covering what is inside.
local function gate(parent: Instance, pos: Vector3, facing: Vector3, color: Color3, glow: Color3, lines: { any })
	local look = CFrame.lookAt(pos, pos + facing)
	local stone = Color3.fromRGB(70, 62, 86)
	for _, side in { -1, 1 } do
		block(parent, look * CFrame.new(side * 8, 6, 0), Vector3.new(2.4, 12, 2.4), stone, { collide = true })
		block(parent, look * CFrame.new(side * 8, 0.6, 0), Vector3.new(3.4, 1.2, 3.4), stone:Lerp(Color3.new(0, 0, 0), 0.2), DECOR)
		block(parent, look * CFrame.new(side * 8, 12.6, 0), Vector3.new(3, 1.2, 3), glow, NEON)
	end
	sign(parent, look * CFrame.new(0, 12.4, 0), Vector3.new(13.6, 3.4, 0.8), color, lines)
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------
local function tree(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	cyl(parent, pos + Vector3.new(0, 4 * s, 0), 0.9 * s, 8 * s, th.trunk, DECOR)
	local c = th.foliage[rng:NextInteger(1, #th.foliage)]
	blob(parent, CFrame.new(pos + Vector3.new(0, 10 * s, 0)), Vector3.new(9, 7.5, 9) * s, c, DECOR)
	blob(parent, CFrame.new(pos + Vector3.new(2 * s, 13 * s, 1 * s)), Vector3.new(6, 5, 6) * s, c:Lerp(Color3.new(1, 1, 1), 0.16), DECOR)
	blob(parent, CFrame.new(pos + Vector3.new(-2.4 * s, 8.4 * s, -1.4 * s)), Vector3.new(5.5, 4.5, 5.5) * s, c:Lerp(Color3.new(0, 0, 0), 0.14), DECOR)
end

local function pine(parent: Instance, pos: Vector3, s: number, th: Theme)
	cyl(parent, pos + Vector3.new(0, 2 * s, 0), 0.7 * s, 4 * s, th.trunk, DECOR)
	for i = 0, 2 do
		local r = (4.2 - i * 1.2) * s
		cyl(parent, pos + Vector3.new(0, (4.4 + i * 2.6) * s, 0), r, 2.4 * s, th.foliage[1]:Lerp(th.foliage[2], i * 0.12), DECOR)
		cyl(parent, pos + Vector3.new(0, (5.7 + i * 2.6) * s, 0), r * 0.82, 0.5 * s, th.foliage[2], DECOR)
	end
end

local function spire(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	local tilt = CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-10, 10)))
	local cf = CFrame.new(pos) * tilt
	block(parent, cf * CFrame.new(0, 3 * s, 0), Vector3.new(3.4, 6, 3.4) * s, th.foliage[1], DECOR)
	block(parent, cf * CFrame.new(0, 7.5 * s, 0), Vector3.new(2.4, 4, 2.4) * s, th.foliage[2], DECOR)
	block(parent, cf * CFrame.new(0, 10.4 * s, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.3, 2.2, 1.3) * s, th.foliage[3], NEON)
end

local function pylon(parent: Instance, pos: Vector3, s: number, th: Theme)
	cyl(parent, pos + Vector3.new(0, 5 * s, 0), 0.8 * s, 10 * s, th.trunk, DECOR)
	cyl(parent, pos + Vector3.new(0, 10.6 * s, 0), 1.6 * s, 0.8 * s, th.foliage[2], DECOR)
	ball(parent, pos + Vector3.new(0, 12.4 * s, 0), 1.1 * s, th.accent, NEON)
end

local function shard(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	local c = if rng:NextNumber() < 0.5 then th.accent else th.accent2
	local cf = CFrame.new(pos + Vector3.new(0, (3 + rng:NextNumber(0, 5)) * s, 0)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5))
	local p = block(parent, cf, Vector3.new(1.6, 7, 1.6) * s, c, { mat = Enum.Material.Neon, collide = false, anim = "bob" })
	p:SetAttribute("KiwPhase", rng:NextNumber(0, 6.28))
	block(parent, cf * CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(2.2, 3.2, 2.2) * s, th.foliage[1], DECOR)
end

local function cactus(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	local c = th.foliage[rng:NextInteger(1, 2)]
	cyl(parent, pos + Vector3.new(0, 4 * s, 0), 1.1 * s, 8 * s, c, DECOR)
	ball(parent, pos + Vector3.new(0, 8 * s, 0), 1.1 * s, c, DECOR)
	for _, side in { -1, 1 } do
		local h = rng:NextNumber(2.4, 4) * s
		block(parent, CFrame.new(pos + Vector3.new(side * 1.9 * s, 3.6 * s, 0)), Vector3.new(1.8, 1, 1) * s, c, DECOR)
		cyl(parent, pos + Vector3.new(side * 2.6 * s, 3.6 * s + h / 2, 0), 0.7 * s, h, c, DECOR)
	end
	ball(parent, pos + Vector3.new(0, 9.3 * s, 0), 0.5 * s, th.foliage[3], DECOR)
end

-- broken tower / street lamp for the city themes
local function tower(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	local h = rng:NextNumber(10, 22) * s
	local yaw = CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-5, 5)))
	local cf = CFrame.new(pos) * yaw
	block(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(5, h, 5) * Vector3.new(s, 1, s), th.foliage[1], { collide = true })
	block(parent, cf * CFrame.new(0, h + 1.2, 0.6) * CFrame.Angles(math.rad(14), 0, math.rad(8)), Vector3.new(4, 2.4, 3.4) * s, th.foliage[2], DECOR)
	for k = 1, 3 do
		block(parent, cf * CFrame.new(0, h * k / 4, -2.55 * s), Vector3.new(3, 0.6, 0.2) * s, if k % 2 == 0 then th.accent2 else th.accent, NEON)
	end
end

local function lolly(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	local c = th.foliage[rng:NextInteger(1, 3)]
	cyl(parent, pos + Vector3.new(0, 4.5 * s, 0), 0.45 * s, 9 * s, th.trunk, DECOR)
	local disc = rod(parent, CFrame.new(pos + Vector3.new(0, 10.5 * s, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), 3.4 * s, 1.2 * s, c, DECOR)
	rod(parent, disc.CFrame, 2.2 * s, 1.3 * s, Color3.new(1, 1, 1), DECOR)
	rod(parent, disc.CFrame, 1.1 * s, 1.4 * s, c, DECOR)
end

local function rock(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random)
	local cf = CFrame.new(pos + Vector3.new(0, 1.2 * s, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
	block(parent, cf, Vector3.new(4.5, 3, 3.6) * s, th.rock, { collide = true })
	block(parent, cf * CFrame.new(1.2 * s, 1.4 * s, 0.4 * s) * CFrame.Angles(0.3, 0.6, 0.2), Vector3.new(2.6, 2, 2.4) * s, th.rock:Lerp(Color3.new(1, 1, 1), 0.14), DECOR)
end

local function crystal(parent: Instance, pos: Vector3, s: number, color: Color3, rng: Random)
	for i = 1, 3 do
		local a = rng:NextNumber(0, 6.28)
		local h = (3 + rng:NextNumber(0, 4)) * s
		local cf = CFrame.new(pos + Vector3.new(math.cos(a) * s, h / 2 - 0.4, math.sin(a) * s)) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), a, rng:NextNumber(-0.35, 0.35))
		block(parent, cf, Vector3.new(1.1 * s, h, 1.1 * s), color:Lerp(Color3.new(1, 1, 1), i * 0.1), NEON)
	end
end

local function lamp(parent: Instance, pos: Vector3, th: Theme)
	cyl(parent, pos + Vector3.new(0, 4, 0), 0.35, 8, Color3.fromRGB(50, 46, 62), DECOR)
	local b = ball(parent, pos + Vector3.new(0, 8.6, 0), 0.8, th.accent2, NEON)
	light(b, th.accent2, 18, 0.7)
end

local function scatterProp(parent: Instance, pos: Vector3, th: Theme, rng: Random)
	local s = rng:NextNumber(0.85, 1.5)
	if th.prop == "tree" then
		tree(parent, pos, s, th, rng)
	elseif th.prop == "pine" then
		pine(parent, pos, s, th)
	elseif th.prop == "spire" then
		spire(parent, pos, s, th, rng)
	elseif th.prop == "pylon" then
		pylon(parent, pos, s * 0.9, th)
	elseif th.prop == "cactus" then
		cactus(parent, pos, s, th, rng)
	elseif th.prop == "tower" then
		tower(parent, pos, s, th, rng)
	elseif th.prop == "lolly" then
		lolly(parent, pos, s, th, rng)
	else
		shard(parent, pos, s, th, rng)
	end
end

-- Mountain with a smooth profile: five tiers from a dark base to a bright cap, plus foothills.
-- The colour bands are baked into the parts, so it reads without shadows or fog.
local function mountain(parent: Instance, pos: Vector3, r: number, h: number, th: Theme, rng: Random)
	local tiers = { { 1, 0, 0.3 }, { 0.8, 0.3, 0.22 }, { 0.6, 0.52, 0.18 }, { 0.4, 0.7, 0.16 }, { 0.23, 0.86, 0.12 } }
	for i, t in tiers do
		local k = (i - 1) / 4
		local color = if k < 0.6 then th.cliffLow:Lerp(th.cliffMid, k / 0.6) else th.cliffMid:Lerp(th.cliffTop, (k - 0.6) / 0.4)
		local extra = if i == 1 then 12 else 0
		cyl(parent, pos + Vector3.new(0, h * (t[2] + t[3] / 2) - extra / 2, 0), r * t[1], h * t[3] + extra, color, { collide = i <= 2 })
	end
	blob(parent, CFrame.new(pos + Vector3.new(0, h * 0.99, 0)), Vector3.new(r * 0.36, h * 0.16, r * 0.36), th.cliffTop, DECOR)
	for _ = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local hill = pos + Vector3.new(math.cos(a) * r * 0.95, 0, math.sin(a) * r * 0.95)
		blob(parent, CFrame.new(hill + Vector3.new(0, h * 0.06, 0)) * CFrame.Angles(0, a, 0), Vector3.new(r * 1.2, h * 0.42, r * 0.9), th.cliffLow:Lerp(th.cliffMid, rng:NextNumber(0.3, 0.8)), DECOR)
	end
end

-- Walkable two-step plateau with something on top.
local function terrace(parent: Instance, pos: Vector3, r: number, th: Theme, rng: Random)
	local side = th.cliffMid:Lerp(th.path, 0.35)
	cyl(parent, pos + Vector3.new(0, 1.1, 0), r, 2.2, side, { collide = true })
	cyl(parent, pos + Vector3.new(0, 2.3, 0), r - 0.6, 0.3, th.patchA, { mat = th.groundMat, collide = false })
	local off = Vector3.new(rng:NextNumber(-0.25, 0.25) * r, 0, rng:NextNumber(-0.25, 0.25) * r)
	cyl(parent, pos + off + Vector3.new(0, 3.4, 0), r * 0.56, 2.2, side:Lerp(Color3.new(1, 1, 1), 0.08), { collide = true })
	cyl(parent, pos + off + Vector3.new(0, 4.6, 0), r * 0.56 - 0.5, 0.3, th.patchA:Lerp(Color3.new(1, 1, 1), 0.12), { mat = th.groundMat, collide = false })
	return pos + off + Vector3.new(0, 4.7, 0)
end

local GLOWY = { volcano = true, storm = true, void = true, ruins = true, future = true, wasteland = true }

local function bush(parent: Instance, pos: Vector3, s: number, th: Theme, rng: Random, theme: string)
	local c = th.foliage[rng:NextInteger(1, 2)]
	blob(parent, CFrame.new(pos + Vector3.new(0, 1 * s, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(4.2, 2.6, 3.4) * s, c, DECOR)
	blob(parent, CFrame.new(pos + Vector3.new(1.3 * s, 1.7 * s, 0.4 * s)), Vector3.new(2.4, 2, 2.4) * s, c:Lerp(Color3.new(1, 1, 1), 0.14), DECOR)
	if GLOWY[theme] then
		ball(parent, pos + Vector3.new(-0.8 * s, 2.3 * s, 0.6 * s), 0.45 * s, th.accent, NEON)
	end
end

local function flowers(parent: Instance, pos: Vector3, th: Theme, rng: Random, theme: string)
	local colors = { th.accent2, th.accent, Color3.fromRGB(255, 255, 255), th.foliage[3] }
	for _ = 1, 4 do
		local p = pos + Vector3.new(rng:NextNumber(-2.4, 2.4), 0, rng:NextNumber(-2.4, 2.4))
		local c = colors[rng:NextInteger(1, #colors)]
		ball(parent, p + Vector3.new(0, 0.55, 0), rng:NextNumber(0.4, 0.62), c, if GLOWY[theme] then NEON else DECOR)
	end
end

local LAKE_COLORS: { [string]: { Color3 } } = {
	meadow = { Color3.fromRGB(64, 160, 236), Color3.fromRGB(120, 205, 250) },
	volcano = { Color3.fromRGB(255, 96, 24), Color3.fromRGB(255, 190, 70) },
	ice = { Color3.fromRGB(150, 210, 245), Color3.fromRGB(225, 245, 255) },
	storm = { Color3.fromRGB(108, 96, 200), Color3.fromRGB(170, 160, 245) },
	void = { Color3.fromRGB(14, 8, 30), Color3.fromRGB(255, 80, 210) },
	desert = { Color3.fromRGB(60, 190, 200), Color3.fromRGB(150, 236, 230) },
	wasteland = { Color3.fromRGB(90, 60, 140), Color3.fromRGB(150, 110, 220) },
	ruins = { Color3.fromRGB(60, 130, 80), Color3.fromRGB(140, 240, 150) },
	candy = { Color3.fromRGB(255, 150, 200), Color3.fromRGB(255, 220, 240) },
	future = { Color3.fromRGB(40, 60, 70), Color3.fromRGB(120, 255, 170) },
}
local function lake(parent: Instance, pos: Vector3, r: number, th: Theme, rng: Random, theme: string)
	local colors = LAKE_COLORS[theme] or LAKE_COLORS.meadow
	local hot = theme == "volcano"
	cyl(parent, pos + Vector3.new(0, 0.14, 0), r + 2.2, 0.2, th.path:Lerp(th.rock, 0.4), DECOR)
	cyl(parent, pos + Vector3.new(0, 0.2, 0), r, 0.2, colors[1], if hot then NEON else DECOR)
	if theme == "void" then
		cyl(parent, pos + Vector3.new(0, 0.26, 0), r * 0.96, 0.1, colors[2], NEON)
		cyl(parent, pos + Vector3.new(0, 0.3, 0), r * 0.9, 0.1, colors[1], DECOR)
	else
		blob(parent, CFrame.new(pos + Vector3.new(-r * 0.2, 0.3, r * 0.1)), Vector3.new(r * 1.1, 0.3, r * 0.7), colors[2], if hot then NEON else DECOR)
		blob(parent, CFrame.new(pos + Vector3.new(r * 0.35, 0.32, -r * 0.3)), Vector3.new(r * 0.5, 0.3, r * 0.34), colors[2]:Lerp(Color3.new(1, 1, 1), 0.3), if hot then NEON else DECOR)
	end
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		rock(parent, pos + Vector3.new(math.cos(a) * (r + 1.5), 0, math.sin(a) * (r + 1.5)), rng:NextNumber(0.6, 1.1), th, rng)
	end
end

-- Sky dressing made of parts (so it survives minimum graphics): clouds, ash, auroras, moons.
local function skyFeature(parent: Instance, pos: Vector3, theme: string, th: Theme, rng: Random, i: number)
	if theme == "void" then
		local r = rng:NextNumber(12, 26)
		local c = ({ th.accent, th.accent2, Color3.fromRGB(150, 90, 255), Color3.fromRGB(255, 170, 90) })[i % 4 + 1]
		local moon = ball(parent, pos, r, c:Lerp(Color3.fromRGB(30, 20, 60), 0.35), { collide = false, anim = "bob" })
		moon:SetAttribute("KiwPhase", i)
		moon:SetAttribute("KiwAmp", 3)
		ball(parent, pos + Vector3.new(r * 0.35, r * 0.3, -r * 0.4), r * 0.62, c, DECOR)
		if i % 3 == 0 then
			ring(parent, pos, r * 1.7, 1.2, c:Lerp(Color3.new(1, 1, 1), 0.4), "orbit", i)
		end
		return
	end
	local SKY_MAIN = { volcano = Color3.fromRGB(70, 56, 60), storm = Color3.fromRGB(74, 78, 118), wasteland = Color3.fromRGB(230, 150, 130), ruins = Color3.fromRGB(96, 108, 112), candy = Color3.fromRGB(255, 214, 236), future = Color3.fromRGB(90, 60, 70), desert = Color3.fromRGB(255, 246, 226) }
	local SKY_UNDER = { volcano = Color3.fromRGB(255, 120, 50), storm = Color3.fromRGB(120, 124, 170), wasteland = Color3.fromRGB(180, 96, 110), ruins = Color3.fromRGB(70, 84, 86), candy = Color3.fromRGB(180, 240, 236), future = Color3.fromRGB(230, 90, 80), desert = Color3.fromRGB(250, 214, 170) }
	local main = SKY_MAIN[theme] or Color3.fromRGB(250, 252, 255)
	local under = SKY_UNDER[theme] or Color3.fromRGB(214, 228, 245)
	local w = rng:NextNumber(60, 110)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, 3.14), 0)
	local cloud = blob(parent, CFrame.new(pos) * yaw, Vector3.new(w, w * 0.2, w * 0.5), main, { collide = false, anim = "bob" })
	cloud:SetAttribute("KiwPhase", i * 1.7)
	cloud:SetAttribute("KiwAmp", 2)
	blob(parent, CFrame.new(pos) * yaw * CFrame.new(w * 0.22, w * 0.07, w * 0.04), Vector3.new(w * 0.5, w * 0.2, w * 0.36), main, DECOR)
	blob(parent, CFrame.new(pos) * yaw * CFrame.new(-w * 0.24, -w * 0.03, -w * 0.05), Vector3.new(w * 0.56, w * 0.14, w * 0.34), under, DECOR)
	if theme == "storm" and i % 2 == 0 then
		local bolt = block(parent, CFrame.new(pos + Vector3.new(0, -w * 0.22, 0)) * CFrame.Angles(0, 0, math.rad(12)), Vector3.new(1.4, w * 0.3, 1.4), th.accent, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		bolt:SetAttribute("KiwPhase", i)
	elseif theme == "ice" and i % 2 == 0 then
		-- aurora ribbon
		local c = if i % 4 == 0 then Color3.fromRGB(120, 255, 200) else Color3.fromRGB(190, 140, 255)
		local rib = block(parent, CFrame.new(pos + Vector3.new(0, 40, 0)) * yaw * CFrame.Angles(0, 0, math.rad(8)), Vector3.new(w * 2.2, 14, 1), c, { mat = Enum.Material.Neon, collide = false, trans = 0.55, anim = "bob" })
		rib:SetAttribute("KiwPhase", i * 0.7)
		rib:SetAttribute("KiwAmp", 4)
	end
end

-- One giant landmark per theme, beyond the rim: what you see first when you land.
local function landmark(parent: Instance, pos: Vector3, theme: string, th: Theme, rng: Random)
	if theme == "meadow" then
		-- world tree
		cyl(parent, pos + Vector3.new(0, 80, 0), 17, 170, th.trunk, { collide = true })
		cyl(parent, pos + Vector3.new(0, 10, 0), 24, 22, th.trunk:Lerp(Color3.new(0, 0, 0), 0.15), { collide = true })
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			blob(parent, CFrame.new(pos + Vector3.new(math.cos(a) * 26, 6, math.sin(a) * 26)) * CFrame.Angles(0, -a, math.rad(20)), Vector3.new(34, 16, 14), th.trunk:Lerp(Color3.new(0, 0, 0), 0.08), DECOR)
		end
		local greens = { Color3.fromRGB(58, 150, 70), Color3.fromRGB(84, 182, 84), Color3.fromRGB(120, 206, 100), Color3.fromRGB(255, 160, 196) }
		local spots = { { 0, 190, 0, 150 }, { 60, 170, 20, 110 }, { -58, 172, -24, 116 }, { 14, 214, -46, 96 }, { -20, 222, 40, 90 }, { 40, 232, 30, 70 }, { -70, 150, 50, 70 } }
		for i, sp in spots do
			blob(parent, CFrame.new(pos + Vector3.new(sp[1], sp[2], sp[3])), Vector3.new(sp[4], sp[4] * 0.62, sp[4]), greens[(i - 1) % 3 + 1], DECOR)
		end
		blob(parent, CFrame.new(pos + Vector3.new(30, 250, -10)), Vector3.new(60, 34, 60), greens[4], DECOR)
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2 + 0.5
			local orb = ball(parent, pos + Vector3.new(math.cos(a) * 62, 116 + (i % 2) * 14, math.sin(a) * 62), 2.6, th.accent2, { mat = Enum.Material.Neon, collide = false, anim = "bob" })
			orb:SetAttribute("KiwPhase", i)
			orb:SetAttribute("KiwAmp", 3)
		end
	elseif theme == "volcano" then
		local tiers = { { 150, 0, 60 }, { 118, 60, 50 }, { 88, 110, 44 }, { 60, 154, 38 }, { 40, 192, 30 } }
		for i, t in tiers do
			cyl(parent, pos + Vector3.new(0, t[2] + t[3] / 2 - 10, 0), t[1], t[3] + 10, th.cliffLow:Lerp(th.cliffMid, (i - 1) / 5), { collide = i <= 2 })
		end
		cyl(parent, pos + Vector3.new(0, 223, 0), 32, 2, th.accent, NEON)
		local lava = blob(parent, CFrame.new(pos + Vector3.new(0, 236, 0)), Vector3.new(44, 40, 44), th.accent2, { mat = Enum.Material.Neon, collide = false, anim = "flame" })
		light(lava, th.accent, 60, 3)
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.4
			local top = pos + Vector3.new(math.cos(a) * 36, 214, math.sin(a) * 36)
			local bottom = pos + Vector3.new(math.cos(a) * 146, 6, math.sin(a) * 146)
			local mid = (top + bottom) / 2
			block(parent, CFrame.lookAt(mid, bottom), Vector3.new(9, 3, (top - bottom).Magnitude), th.accent, NEON)
		end
		for i = 1, 3 do
			local smoke = blob(parent, CFrame.new(pos + Vector3.new(i * 16 - 30, 270 + i * 30, i * 10)), Vector3.new(70 + i * 22, 36 + i * 8, 70 + i * 22), Color3.fromRGB(60, 50, 54), { collide = false, anim = "bob" })
			smoke:SetAttribute("KiwPhase", i * 2)
			smoke:SetAttribute("KiwAmp", 5)
		end
	elseif theme == "ice" then
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2
			local d = if i % 3 == 0 then 0 else rng:NextNumber(30, 78)
			local h = if i % 3 == 0 then 260 else rng:NextNumber(110, 200)
			local w = if i % 3 == 0 then 40 else rng:NextNumber(18, 30)
			local p = pos + Vector3.new(math.cos(a) * d, h / 2 - 6, math.sin(a) * d)
			local tilt = CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), a, math.rad(rng:NextNumber(-10, 10)))
			block(parent, CFrame.new(p) * tilt, Vector3.new(w, h, w), Color3.fromRGB(150, 205, 245):Lerp(Color3.fromRGB(235, 248, 255), i / 9), { collide = i % 3 == 0 })
			block(parent, CFrame.new(p) * tilt * CFrame.new(0, h / 2 + w * 0.3, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(w * 0.62, w * 0.9, w * 0.62), th.accent, NEON)
		end
	elseif theme == "storm" then
		cyl(parent, pos + Vector3.new(0, 130, 0), 16, 270, Color3.fromRGB(60, 66, 100), { collide = true })
		cyl(parent, pos + Vector3.new(0, 14, 0), 30, 28, Color3.fromRGB(48, 54, 86), { collide = true })
		for i = 1, 4 do
			cyl(parent, pos + Vector3.new(0, 40 + i * 50, 0), 20, 5, th.accent, NEON)
		end
		local orb = ball(parent, pos + Vector3.new(0, 284, 0), 18, th.accent, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		light(orb, th.accent, 60, 3)
		for i = 1, 3 do
			ring(parent, pos + Vector3.new(0, 284, 0), 34 + i * 16, 2.4, if i % 2 == 0 then th.accent2 else th.accent, "orbit", i * 1.4)
		end
	elseif theme == "desert" then
		-- the Legion fortress: a stepped tower with searchlights
		local steel, red = Color3.fromRGB(96, 104, 110), Color3.fromRGB(230, 70, 50)
		local sizes = { { 150, 60 }, { 110, 50 }, { 76, 46 }, { 48, 50 } }
		local y = 0
		for i, sz in sizes do
			block(parent, CFrame.new(pos + Vector3.new(0, y + sz[2] / 2, 0)), Vector3.new(sz[1], sz[2], sz[1]), steel:Lerp(Color3.new(0, 0, 0), 0.25 - i * 0.05), { collide = i <= 2 })
			block(parent, CFrame.new(pos + Vector3.new(0, y + sz[2] - 3, 0)), Vector3.new(sz[1] + 3, 4, sz[1] + 3), red, NEON)
			y += sz[2]
		end
		cyl(parent, pos + Vector3.new(0, y + 30, 0), 4, 60, steel, DECOR)
		local beacon = ball(parent, pos + Vector3.new(0, y + 64, 0), 9, th.accent, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		light(beacon, th.accent, 60, 3)
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.78
			block(parent, CFrame.new(pos + Vector3.new(math.cos(a) * 96, 40, math.sin(a) * 96)), Vector3.new(26, 80, 26), steel:Lerp(Color3.new(0, 0, 0), 0.3), DECOR)
			block(parent, CFrame.new(pos + Vector3.new(math.cos(a) * 96, 82, math.sin(a) * 96)), Vector3.new(30, 5, 30), red, NEON)
		end
	elseif theme == "wasteland" then
		-- crashed invader pods and a needle mesa
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			local d = if i == 1 then 0 else 90
			local h = if i == 1 then 240 else rng:NextNumber(90, 160)
			local w = if i == 1 then 60 else rng:NextNumber(36, 50)
			local p = pos + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			cyl(parent, p + Vector3.new(0, h * 0.3, 0), w, h * 0.6, th.cliffLow, { collide = i == 1 })
			cyl(parent, p + Vector3.new(0, h * 0.72, 0), w * 0.62, h * 0.26, th.cliffMid, DECOR)
			cyl(parent, p + Vector3.new(0, h * 0.92, 0), w * 0.8, h * 0.14, th.cliffTop, DECOR)
		end
		for i = 1, 3 do
			local p = pos + Vector3.new(i * 50 - 100, 150 + i * 36, -30 + i * 20)
			local pod = ball(parent, p, 20, Color3.fromRGB(236, 236, 246), { collide = false, anim = "bob" })
			pod:SetAttribute("KiwPhase", i * 2)
			pod:SetAttribute("KiwAmp", 3)
			ball(parent, p + Vector3.new(0, 0, -13), 9, th.accent2, NEON)
			ring(parent, p, 30, 1.6, th.accent, "orbit", i)
		end
	elseif theme == "ruins" then
		-- dead skyline with one tower still lit
		for i = 1, 11 do
			local a = i / 11 * math.pi * 2
			local d = if i == 1 then 0 else rng:NextNumber(60, 150)
			local h = if i == 1 then 320 else rng:NextNumber(90, 230)
			local w = if i == 1 then 56 else rng:NextNumber(30, 56)
			local p = pos + Vector3.new(math.cos(a) * d, h / 2 - 8, math.sin(a) * d)
			local tilt = if i % 4 == 0 then CFrame.Angles(math.rad(7), a, math.rad(5)) else CFrame.Angles(0, a, 0)
			block(parent, CFrame.new(p) * tilt, Vector3.new(w, h, w), Color3.fromRGB(60, 68, 78):Lerp(Color3.fromRGB(110, 122, 130), rng:NextNumber()), { collide = i == 1 })
			for k = 1, 3 do
				block(parent, CFrame.new(p) * tilt * CFrame.new(0, h * (k / 4 - 0.4), w / 2 + 0.3), Vector3.new(w * 0.7, 3, 0.4), if i == 1 then th.accent else th.accent2:Lerp(Color3.fromRGB(40, 40, 50), 0.5), NEON)
			end
		end
		local eye = ball(parent, pos + Vector3.new(0, 336, 0), 16, th.accent, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		light(eye, th.accent, 60, 3)
	elseif theme == "candy" then
		-- a castle of cake tiers with a bubble on top
		local tiers = { { r = 130, h = 60, c = Color3.fromRGB(255, 170, 210) }, { r = 100, h = 50, c = Color3.fromRGB(180, 240, 236) }, { r = 70, h = 46, c = Color3.fromRGB(255, 240, 150) }, { r = 44, h = 40, c = Color3.fromRGB(255, 130, 190) } }
		local y = 0
		for _, t in tiers do
			cyl(parent, pos + Vector3.new(0, y + t.h / 2, 0), t.r, t.h, t.c, { collide = true })
			cyl(parent, pos + Vector3.new(0, y + t.h, 0), t.r + 2, 6, Color3.fromRGB(255, 252, 250), DECOR)
			for i = 1, 8 do
				local a = i / 8 * math.pi * 2
				ball(parent, pos + Vector3.new(math.cos(a) * t.r, y + t.h - 2, math.sin(a) * t.r), 6, Color3.fromRGB(255, 252, 250), DECOR)
			end
			y += t.h
		end
		local bubble = ball(parent, pos + Vector3.new(0, y + 40, 0), 34, Color3.fromRGB(150, 240, 236), { collide = false, anim = "bob", trans = 0.35 })
		bubble:SetAttribute("KiwAmp", 4)
		ball(parent, pos + Vector3.new(10, y + 52, -22), 8, Color3.new(1, 1, 1), DECOR)
	elseif theme == "future" then
		-- a broken clock tower under a torn sky
		block(parent, CFrame.new(pos + Vector3.new(0, 120, 0)) * CFrame.Angles(0, 0, math.rad(4)), Vector3.new(60, 250, 60), Color3.fromRGB(50, 46, 60), { collide = true })
		local face = rod(parent, CFrame.new(pos + Vector3.new(-31, 210, 0)), 24, 2, Color3.fromRGB(230, 226, 220), NEON)
		local hand = block(parent, CFrame.new(face.Position + Vector3.new(-1.4, 0, 0)), Vector3.new(0.8, 20, 2), Color3.fromRGB(40, 36, 50), { collide = false, anim = "clock" })
		hand.Name = "Hand"
		for i = 1, 7 do
			local a = i / 7 * math.pi * 2
			local p = pos + Vector3.new(math.cos(a) * rng:NextNumber(70, 130), rng:NextNumber(120, 300), math.sin(a) * rng:NextNumber(70, 130))
			local chunk = block(parent, CFrame.new(p) * CFrame.Angles(a, a * 2, 0.6), Vector3.new(22, 12, 18) * rng:NextNumber(0.6, 1.3), Color3.fromRGB(60, 54, 70), { collide = false, anim = "bob" })
			chunk:SetAttribute("KiwPhase", i)
			chunk:SetAttribute("KiwAmp", 4)
		end
		-- the tear in the sky
		block(parent, CFrame.new(pos + Vector3.new(40, 330, 0)) * CFrame.Angles(0, 0, math.rad(-24)), Vector3.new(8, 190, 2), th.accent2, NEON)
		block(parent, CFrame.new(pos + Vector3.new(40, 330, 0.2)) * CFrame.Angles(0, 0, math.rad(-24)), Vector3.new(2.5, 170, 2.4), Color3.new(1, 1, 1), NEON)
	else
		-- shattered moon
		local moonPos = pos + Vector3.new(0, 250, 0)
		ball(parent, moonPos, 74, Color3.fromRGB(70, 44, 120), DECOR)
		ball(parent, moonPos + Vector3.new(-16, 10, 22), 58, Color3.fromRGB(104, 66, 170), DECOR)
		ball(parent, moonPos + Vector3.new(34, -20, 40), 26, th.accent, NEON)
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2
			local p = moonPos + Vector3.new(math.cos(a) * (96 + (i % 3) * 22), rng:NextNumber(-40, 40), math.sin(a) * (96 + (i % 3) * 22))
			local sh = block(parent, CFrame.new(p) * CFrame.Angles(a, a * 2, 1), Vector3.new(16, 26, 12) * rng:NextNumber(0.6, 1.4), Color3.fromRGB(60, 38, 104), { collide = false, anim = "bob" })
			sh:SetAttribute("KiwPhase", i)
			sh:SetAttribute("KiwAmp", 4)
		end
		ring(parent, moonPos, 130, 3, th.accent, "orbit", 1)
		ring(parent, moonPos, 150, 2, th.accent2, "orbit", 3)
	end
end

---------------------------------------------------------------------------
-- Training zones
---------------------------------------------------------------------------
local ZoneColors: { [string]: Color3 } = {
	pit = Color3.fromRGB(255, 170, 60),
	dome = Color3.fromRGB(180, 110, 255),
	falls = Color3.fromRGB(80, 190, 255),
	forge = Color3.fromRGB(255, 120, 40),
	crucible = Color3.fromRGB(255, 70, 70),
	cavern = Color3.fromRGB(120, 230, 255),
	spire = Color3.fromRGB(150, 255, 200),
	eye = Color3.fromRGB(255, 236, 100),
	vault = Color3.fromRGB(255, 255, 255),
	anvil = Color3.fromRGB(255, 80, 210),
	singularity = Color3.fromRGB(140, 90, 255),
}

local function buildZone(parent: Instance, center: Vector3, zone: any, th: Theme, toward: Vector3)
	local c = ZoneColors[zone.style] or th.accent
	local r = zone.radius
	local f = Instance.new("Folder")
	f.Name = "Zone_" .. zone.id
	f.Parent = parent
	-- stepped pad with a bright rim and a painted inner disc
	cyl(f, center + Vector3.new(0, 0.35, 0), r + 3, 0.7, th.rock, { collide = true })
	cyl(f, center + Vector3.new(0, 0.8, 0), r, 0.5, Color3.fromRGB(44, 38, 62), { collide = true })
	cyl(f, center + Vector3.new(0, 1.0, 0), r - 1.5, 0.2, c, NEON).Name = "Rim"
	cyl(f, center + Vector3.new(0, 1.06, 0), r - 3.2, 0.2, Color3.fromRGB(56, 48, 80), DECOR)
	cyl(f, center + Vector3.new(0, 1.12, 0), r * 0.55, 0.2, c:Lerp(Color3.fromRGB(40, 34, 60), 0.45), DECOR)
	cyl(f, center + Vector3.new(0, 1.18, 0), r * 0.3, 0.2, c:Lerp(Color3.new(1, 1, 1), 0.25), NEON)
	-- pylons around the pad, joined by a floating ring
	local n = 8
	for i = 1, n do
		local a = i / n * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * (r + 0.5), 0, math.sin(a) * (r + 0.5))
		block(f, CFrame.new(p + Vector3.new(0, 6, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(2.6, 12, 2.6), Color3.fromRGB(58, 50, 84), { collide = true })
		block(f, CFrame.new(p + Vector3.new(0, 12.6, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(3.4, 1.2, 3.4), c, NEON)
		local orb = ball(f, p + Vector3.new(0, 15, 0), 1.2, c:Lerp(Color3.new(1, 1, 1), 0.3), { mat = Enum.Material.Neon, collide = false, anim = "bob" })
		orb:SetAttribute("KiwPhase", i)
		if i % 2 == 0 then
			light(orb, c, 26, 1.4)
		end
	end
	-- centrepiece per style
	local top = center + Vector3.new(0, 1.2, 0)
	local style = zone.style
	if style == "dome" then
		-- gravity dome: translucent shell + heavy rings that spin
		blob(f, CFrame.new(center + Vector3.new(0, 1, 0)), Vector3.new(r * 2 - 4, r * 1.3, r * 2 - 4), c, { mat = Enum.Material.ForceField, collide = false, trans = 0.35 })
		for i = 1, 3 do
			ring(f, top + Vector3.new(0, 6 + i * 5, 0), r * (0.75 - i * 0.14), 1, c:Lerp(Color3.new(1, 1, 1), i * 0.15), "orbit", i * 2)
		end
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.4
			local p = top + Vector3.new(math.cos(a) * r * 0.62, 0, math.sin(a) * r * 0.62)
			cyl(f, p + Vector3.new(0, 1.2, 0), 2.6, 2.4, Color3.fromRGB(40, 40, 52), { collide = true })
			cyl(f, p + Vector3.new(0, 2.7, 0), 1.2, 0.8, Color3.fromRGB(90, 90, 110), DECOR)
		end
	elseif style == "pit" then
		-- sparring pit: training posts and hanging weights around a sunken centre
		cyl(f, top + Vector3.new(0, 0.1, 0), r * 0.5, 0.3, th.path, DECOR)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			local p = top + Vector3.new(math.cos(a) * r * 0.55, 0, math.sin(a) * r * 0.55)
			cyl(f, p + Vector3.new(0, 3.5, 0), 0.9, 7, th.trunk, { collide = true })
			block(f, CFrame.new(p + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(5.6, 0.9, 0.9), th.trunk, DECOR)
			ball(f, p + Vector3.new(0, 6.6, 0), 1.3, c, NEON)
			if i % 2 == 0 then
				cyl(f, p + Vector3.new(math.cos(a) * 4, 1.2, math.sin(a) * 4), 2.2, 2.4, Color3.fromRGB(44, 44, 56), { collide = true })
			end
		end
		local flag = block(f, CFrame.new(top + Vector3.new(0, 14, 0)), Vector3.new(0.4, 10, 7), c, { collide = false, anim = "flag" })
		cyl(f, top + Vector3.new(0, 10, 0), 0.6, 20, th.trunk, DECOR)
		local _ = flag
	elseif style == "falls" then
		-- cliff with a waterfall and lightning rods
		local back = CFrame.lookAt(top, top + toward) * CFrame.new(0, 0, r * 0.72)
		block(f, back * CFrame.new(0, 16, 4), Vector3.new(44, 34, 10), th.cliffLow, { collide = true })
		block(f, back * CFrame.new(0, 34, 5), Vector3.new(36, 6, 12), th.cliffMid, { collide = true })
		block(f, back * CFrame.new(-15, 22, 0), Vector3.new(10, 44, 9), th.cliffMid, { collide = true })
		block(f, back * CFrame.new(15, 20, 0), Vector3.new(10, 40, 9), th.cliffMid, { collide = true })
		local water = block(f, back * CFrame.new(0, 16, -1.2), Vector3.new(18, 33, 1.2), Color3.fromRGB(110, 210, 255), { mat = Enum.Material.Neon, collide = false, trans = 0.15, name = "Waterfall", anim = "water" })
		block(f, back * CFrame.new(-4, 16, -1.9), Vector3.new(2.4, 33, 0.4), Color3.fromRGB(220, 245, 255), NEON)
		block(f, back * CFrame.new(5, 16, -1.9), Vector3.new(1.6, 33, 0.4), Color3.fromRGB(220, 245, 255), NEON)
		light(water, Color3.fromRGB(110, 210, 255), 40, 1.5)
		cyl(f, top + Vector3.new(0, 0.1, 0) + (back.Position - top) * 0.8, 13, 0.3, Color3.fromRGB(90, 190, 250), NEON)
		for _, side in { -1, 1 } do
			local p = (back * CFrame.new(side * 15, 44, 0)).Position
			cyl(f, p + Vector3.new(0, 5, 0), 0.4, 10, Color3.fromRGB(70, 70, 90), DECOR)
			ball(f, p + Vector3.new(0, 10.6, 0), 1.4, Color3.fromRGB(255, 240, 120), { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		end
	elseif style == "forge" or style == "crucible" then
		cyl(f, top + Vector3.new(0, 1.5, 0), r * 0.34, 3, Color3.fromRGB(40, 34, 38), { collide = true })
		cyl(f, top + Vector3.new(0, 3.1, 0), r * 0.3, 0.4, c, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2
			local p = top + Vector3.new(math.cos(a) * r * 0.6, 0, math.sin(a) * r * 0.6)
			block(f, CFrame.new(p + Vector3.new(0, 4, 0)) * CFrame.Angles(0, -a, math.rad(12)), Vector3.new(3, 8, 3), Color3.fromRGB(50, 40, 44), { collide = true })
			block(f, CFrame.new(p + Vector3.new(0, 8.6, 0)) * CFrame.Angles(0, -a, math.rad(12)), Vector3.new(2, 2, 2), c, NEON)
		end
		local flame = blob(f, CFrame.new(top + Vector3.new(0, 8, 0)), Vector3.new(7, 11, 7), c:Lerp(Color3.fromRGB(255, 240, 150), 0.4), { mat = Enum.Material.Neon, collide = false, anim = "flame" })
		light(flame, c, 46, 2)
	elseif style == "cavern" or style == "spire" then
		for i = 1, 7 do
			local a = i / 7 * math.pi * 2
			local h = 12 + (i % 3) * 7
			local p = top + Vector3.new(math.cos(a) * r * 0.66, h / 2, math.sin(a) * r * 0.66)
			block(f, CFrame.new(p) * CFrame.Angles(math.rad((i % 2) * 8 - 4), a, math.rad(6)), Vector3.new(4, h, 4), Color3.fromRGB(150, 210, 245):Lerp(c, 0.3), { collide = true })
			block(f, CFrame.new(p + Vector3.new(0, h / 2 + 1.5, 0)) * CFrame.Angles(0, a + 0.78, 0), Vector3.new(2.4, 3.4, 2.4), c, NEON)
		end
		local core = block(f, CFrame.new(top + Vector3.new(0, 10, 0)) * CFrame.Angles(0.6, 0.78, 0.4), Vector3.new(5, 5, 5), c, { mat = Enum.Material.Neon, collide = false, anim = "spin" })
		light(core, c, 46, 2)
	elseif style == "eye" then
		for i = 1, 3 do
			ring(f, top + Vector3.new(0, 5 + i * 7, 0), r * (0.9 - i * 0.2), 1.2, if i % 2 == 0 then th.accent2 else c, "orbit", i * 3)
		end
		local eye = ball(f, top + Vector3.new(0, 16, 0), 4, c, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		light(eye, c, 50, 2)
	elseif style == "vault" then
		-- the timeless vault: a white room with a giant clock face
		for _, side in { -1, 1 } do
			block(f, CFrame.lookAt(top, top + toward) * CFrame.new(side * r * 0.7, 12, r * 0.5), Vector3.new(4, 24, r), Color3.fromRGB(240, 240, 250), { collide = true })
		end
		local clock = cyl(f, top + Vector3.new(0, 20, 0), 12, 1, Color3.fromRGB(250, 250, 255), { mat = Enum.Material.Neon, collide = false })
		clock.CFrame = CFrame.lookAt(top + Vector3.new(0, 20, 0) - toward * r * 0.7, top + Vector3.new(0, 20, 0)) * CFrame.Angles(0, math.rad(90), 0)
		local hand = block(f, CFrame.lookAt(top + Vector3.new(0, 20, 0) - toward * (r * 0.7 - 1), top + Vector3.new(0, 20, 0)), Vector3.new(1, 10, 0.6), Color3.fromRGB(40, 40, 60), { collide = false, anim = "clock" })
		hand.Name = "Hand"
		light(clock, Color3.new(1, 1, 1), 50, 2)
	else -- anvil / singularity
		local core = ball(f, top + Vector3.new(0, 14, 0), 5, Color3.fromRGB(10, 6, 20), { collide = false, anim = "pulse" })
		for i = 1, 3 do
			ring(f, top + Vector3.new(0, 14, 0), 8 + i * 3, 0.8, if i % 2 == 0 then th.accent2 else c, "orbit", i * 2.1)
		end
		light(core, c, 50, 2)
		block(f, CFrame.new(top + Vector3.new(0, 2, 0)), Vector3.new(10, 4, 6), Color3.fromRGB(30, 22, 50), { collide = true })
	end
	-- sign on the side that faces the plaza
	local signPos = center + toward * (r + 9)
	gate(f, Vector3.new(signPos.X, 0, signPos.Z), toward, c:Lerp(Color3.fromRGB(30, 24, 50), 0.55), c, {
		{ key = "zone." .. zone.id },
		{ text = "x" .. Format.abbrev(zone.mult) .. "  ·  " .. Format.abbrev(zone.reqPower) .. "+", color = Color3.fromRGB(255, 226, 90) },
	})
end

---------------------------------------------------------------------------
-- Camps and boss arenas
---------------------------------------------------------------------------
local function buildCamp(parent: Instance, center: Vector3, camp: any, th: Theme, toward: Vector3, rng: Random)
	local def = Config.Npcs[camp.npc]
	local c = rgb(def.color)
	local acc = rgb(def.accent)
	local f = Instance.new("Folder")
	f.Name = "Camp_" .. camp.npc
	f.Parent = parent
	cyl(f, center + Vector3.new(0, 0.12, 0), camp.radius, 0.2, th.patchB:Lerp(c, 0.18), DECOR)
	cyl(f, center + Vector3.new(0, 0.18, 0), camp.radius * 0.6, 0.2, th.patchB:Lerp(c, 0.32), DECOR)
	-- totems with the enemy colours + banners
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2 + 0.3
		local p = center + Vector3.new(math.cos(a) * camp.radius * 0.92, 0, math.sin(a) * camp.radius * 0.92)
		block(f, CFrame.new(p + Vector3.new(0, 5, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(2.2, 10, 2.2), th.trunk, { collide = true })
		block(f, CFrame.new(p + Vector3.new(0, 8.4, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(3, 2.4, 3), c, DECOR)
		block(f, CFrame.new(p + Vector3.new(0, 11, 0)) * CFrame.Angles(0, -a + 0.78, 0), Vector3.new(1.6, 1.6, 1.6), acc, NEON)
		local flag = block(f, CFrame.new(p + Vector3.new(0, 6.2, 0)) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, 2.2), Vector3.new(0.3, 4.4, 3.2), acc, { collide = false, anim = "flag" })
		flag:SetAttribute("KiwPhase", i)
	end
	for _ = 1, 4 do
		local a = rng:NextNumber(0, 6.28)
		local r = camp.radius * rng:NextNumber(0.3, 0.8)
		rock(f, center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:NextNumber(0.7, 1.3), th, rng)
	end
	local signPos = center + toward * (camp.radius + 6)
	gate(f, Vector3.new(signPos.X, 0, signPos.Z), toward, Color3.fromRGB(110, 40, 48), acc, {
		{ key = "npc." .. camp.npc },
		{ key = "world.enemy_hp", n = Format.abbrev(def.hp), color = Color3.fromRGB(255, 200, 200) },
	})
end

local function buildBossArena(parent: Instance, center: Vector3, boss: any, th: Theme, toward: Vector3)
	local def = Config.Npcs[boss.npc]
	local acc = rgb(def.accent)
	local f = Instance.new("Folder")
	f.Name = "Boss_" .. boss.npc
	f.Parent = parent
	local r = boss.radius
	cyl(f, center + Vector3.new(0, 0.2, 0), r + 4, 0.4, th.rock, { collide = true })
	cyl(f, center + Vector3.new(0, 0.5, 0), r, 0.3, Color3.fromRGB(38, 30, 46), { collide = true })
	cyl(f, center + Vector3.new(0, 0.62, 0), r * 0.97, 0.2, acc, NEON)
	cyl(f, center + Vector3.new(0, 0.7, 0), r * 0.93, 0.2, Color3.fromRGB(46, 36, 56), DECOR)
	cyl(f, center + Vector3.new(0, 0.76, 0), r * 0.5, 0.2, acc:Lerp(Color3.fromRGB(30, 24, 40), 0.6), DECOR)
	cyl(f, center + Vector3.new(0, 0.82, 0), r * 0.47, 0.2, Color3.fromRGB(52, 40, 62), DECOR)
	-- claw-like pillars leaning in
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * (r + 1), 0, math.sin(a) * (r + 1))
		local h = if i % 2 == 0 then 30 else 20
		local cf = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)) * CFrame.Angles(math.rad(-14), 0, 0)
		block(f, cf * CFrame.new(0, h / 2, 0), Vector3.new(5, h, 5), th.cliffLow, { collide = true })
		block(f, cf * CFrame.new(0, h + 2, 0) * CFrame.Angles(math.rad(-24), 0, 0), Vector3.new(3.4, 7, 3.4), th.cliffMid, DECOR)
		local tip = block(f, cf * CFrame.new(0, h + 6, -1.6) * CFrame.Angles(math.rad(-30), 0, math.rad(45)), Vector3.new(1.8, 1.8, 1.8), acc, { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
		tip:SetAttribute("KiwPhase", i)
		if i % 2 == 0 then
			light(tip, acc, 30, 1.5)
		end
	end
	local signPos = center + toward * (r + 10)
	gate(f, Vector3.new(signPos.X, 0, signPos.Z), toward, Color3.fromRGB(90, 20, 40), acc, {
		{ key = "npc." .. boss.npc },
		{ key = "world.boss", color = Color3.fromRGB(255, 210, 90) },
	})
	local _ = def
end

---------------------------------------------------------------------------
-- Plaza, warp gate
---------------------------------------------------------------------------
local function buildPlaza(parent: Instance, center: Vector3, pl: any, th: Theme)
	local f = Instance.new("Folder")
	f.Name = "Plaza"
	f.Parent = parent
	local R = Config.PlazaRadius
	cyl(f, center + Vector3.new(0, 0.2, 0), R, 0.4, th.plaza:Lerp(Color3.new(0, 0, 0), 0.25), { collide = true })
	cyl(f, center + Vector3.new(0, 0.5, 0), R - 3, 0.3, th.plaza, { collide = true })
	cyl(f, center + Vector3.new(0, 0.66, 0), R - 8, 0.2, th.plazaTrim, NEON)
	cyl(f, center + Vector3.new(0, 0.72, 0), R - 10, 0.2, th.plaza:Lerp(Color3.new(1, 1, 1), 0.12), DECOR)
	-- painted sunburst
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local mid = center + Vector3.new(math.cos(a) * (R * 0.5), 0.84, math.sin(a) * (R * 0.5))
		block(f, CFrame.new(mid) * CFrame.Angles(0, -a, 0), Vector3.new(R * 0.62, 0.2, 2.2), th.plaza:Lerp(th.plazaTrim, if i % 2 == 0 then 0.55 else 0.25), DECOR)
	end
	cyl(f, center + Vector3.new(0, 0.9, 0), 17, 0.3, th.plazaTrim:Lerp(th.plaza, 0.4), DECOR)
	-- monument: a floating ki crystal over a stepped base
	cyl(f, center + Vector3.new(0, 1.6, 0), 12, 1.6, th.rock, { collide = true })
	cyl(f, center + Vector3.new(0, 3.0, 0), 8.5, 1.4, th.plaza, { collide = true })
	cyl(f, center + Vector3.new(0, 4.2, 0), 5.5, 1.2, th.plazaTrim, { collide = true })
	local core = block(f, CFrame.new(center + Vector3.new(0, 15, 0)) * CFrame.Angles(math.rad(35), 0, math.rad(45)), Vector3.new(5.5, 5.5, 5.5), th.accent, { mat = Enum.Material.Neon, collide = false, anim = "spinbob", name = "KiCrystal" })
	light(core, th.accent, 50, 1.6)
	block(f, CFrame.new(center + Vector3.new(0, 15, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(2.6, 13, 2.6), th.accent:Lerp(th.plazaTrim, 0.35), { collide = false, anim = "spinbob" })
	for i = 1, 2 do
		ring(f, center + Vector3.new(0, 15, 0), 8 + i * 2.5, 0.7, th.plazaTrim, "orbit", i * 1.7)
	end
	-- lamps and banner poles around the rim
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + math.rad(22.5)
		lamp(f, center + Vector3.new(math.cos(a) * (R - 5), 0.7, math.sin(a) * (R - 5)), th)
	end
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * (R + 2), 0, math.sin(a) * (R + 2))
		cyl(f, p + Vector3.new(0, 9, 0), 0.5, 18, Color3.fromRGB(60, 52, 70), DECOR)
		local flag = block(f, CFrame.new(p + Vector3.new(0, 13, 0)) * CFrame.Angles(0, -a + math.rad(90), 0) * CFrame.new(0, 0, 2.6), Vector3.new(0.3, 8, 4.4), if i % 2 == 0 then th.plazaTrim else th.accent, { collide = false, anim = "flag" })
		flag:SetAttribute("KiwPhase", i * 0.9)
	end
	-- spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(center + Vector3.new(0, 0.4, 22))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = pl.index == 1
	spawn.Parent = f
	partCount += 1

	-- warp gate
	local gatePos = center + Vector3.new(-34, 0.8, 30)
	local gate = Instance.new("Model")
	gate.Name = "WarpGate"
	gate.Parent = f
	cyl(gate, gatePos + Vector3.new(0, 0.6, 0), 9, 1.2, th.rock, { collide = true })
	cyl(gate, gatePos + Vector3.new(0, 1.3, 0), 7.4, 0.3, th.accent2, NEON)
	local n = 14
	for i = 1, n do
		local a = i / n * math.pi * 2
		local p = gatePos + Vector3.new(0, 9.5 + math.sin(a) * 7.4, math.cos(a) * 7.4)
		block(gate, CFrame.new(p) * CFrame.Angles(a, 0, 0), Vector3.new(2.2, 2.2, 3.6), if i % 2 == 0 then th.plaza else th.accent2, if i % 2 == 0 then DECOR else NEON)
	end
	local disc = rod(gate, CFrame.new(gatePos + Vector3.new(0, 9.5, 0)), 6.4, 0.5, th.accent, { mat = Enum.Material.Neon, collide = false, trans = 0.25, name = "Portal", anim = "pulse" })
	light(disc, th.accent, 40, 2)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TravelPrompt"
	prompt.ActionText = "Travel"
	prompt.ObjectText = "Warp Gate"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.B
	prompt:SetAttribute("LocAction", "world.travel")
	prompt:SetAttribute("LocObject", "world.warp_gate")
	prompt.Parent = disc
	standSign(f, gatePos + Vector3.new(0, -0.8, 12), Vector3.new(1, 0, 0.2), Color3.fromRGB(40, 60, 110), { { key = "world.warp_gate" }, { key = "planet." .. pl.id, color = Color3.fromRGB(255, 226, 90) } }, 16)
end

---------------------------------------------------------------------------
-- Planet
---------------------------------------------------------------------------
local function buildPlanet(world: Instance, pl: any, info: { [string]: any })
	local th = Themes[pl.theme]
	local cx, cy, cz = Config.planetCenter(pl.index)
	local center = Vector3.new(cx, cy, cz)
	local rng = Random.new(1000 + pl.index * 77)
	local f = Instance.new("Folder")
	f.Name = "Planet_" .. pl.id
	f.Parent = world
	local R = pl.radius

	-- ground: a thick disc, a darker skirt, painted patches
	cyl(f, center + Vector3.new(0, -8, 0), R, 16, th.ground, { mat = th.groundMat, collide = true, name = "Ground" })
	cyl(f, center + Vector3.new(0, -30, 0), R * 0.82, 30, th.cliffLow, { collide = false })
	cyl(f, center + Vector3.new(0, -58, 0), R * 0.5, 30, th.cliffLow:Lerp(Color3.new(0, 0, 0), 0.3), { collide = false })
	cyl(f, center + Vector3.new(0, 0.04, 0), R - 14, 0.1, th.ground:Lerp(th.patchA, 0.35), { mat = th.groundMat, collide = false })

	local pois: { { pos: Vector3, r: number } } = { { pos = center, r = Config.PlazaRadius + 10 } }
	local function at(offset: { number }): Vector3
		return center + Vector3.new(offset[1], 0, offset[3])
	end
	for _, z in pl.zones do
		table.insert(pois, { pos = at(z.offset), r = z.radius + 12 })
	end
	for _, c in pl.camps do
		table.insert(pois, { pos = at(c.offset), r = c.radius + 8 })
	end
	table.insert(pois, { pos = at(pl.boss.offset), r = pl.boss.radius + 12 })
	if pl.index == Config.Arena.planet then
		table.insert(pois, { pos = at(Config.Arena.offset), r = Config.Arena.wall + 16 })
		table.insert(pois, { pos = at(Config.WishAltar.offset), r = Config.WishAltar.radius + 14 })
		table.insert(pois, { pos = at(Config.WorldBossSite.offset), r = Config.WorldBossSite.radius + 8 })
	end

	local function free(p: Vector3, pad: number): boolean
		for _, poi in pois do
			if ((p - poi.pos) * Vector3.new(1, 0, 1)).Magnitude < poi.r + pad then
				return false
			end
		end
		return true
	end

	-- painted ground patches (flat discs in two tones)
	for i = 1, 34 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(40, R - 50)
		local p = center + Vector3.new(math.cos(a) * r, 0.1 + i * 0.004, math.sin(a) * r)
		local size = rng:NextNumber(16, 46)
		local p1 = blob(f, CFrame.new(p), Vector3.new(size * 2, 0.5, size * rng:NextNumber(1.2, 2)), if i % 2 == 0 then th.patchA else th.patchB, DECOR)
		p1.CFrame = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0)
	end

	-- paths from the plaza to every point of interest
	for i = 2, #pois do
		local poi = pois[i]
		local d = (poi.pos - center) * Vector3.new(1, 0, 1)
		local from = Config.PlazaRadius - 4
		local len = d.Magnitude - poi.r + 14 - from
		if len > 4 then
			local mid = center + d.Unit * (from + len / 2) + Vector3.new(0, 0.22, 0)
			block(f, CFrame.lookAt(mid, mid + d.Unit), Vector3.new(11, 0.24, len), th.path, DECOR)
			block(f, CFrame.lookAt(mid + Vector3.new(0, 0.05, 0), mid + d.Unit + Vector3.new(0, 0.05, 0)), Vector3.new(6.5, 0.24, len), th.path:Lerp(Color3.new(1, 1, 1), 0.18), DECOR)
			-- lantern posts along the way, alternating sides
			local side = d.Unit:Cross(Vector3.yAxis)
			local n = math.floor(len / 34)
			for k = 1, n do
				local p = center + d.Unit * (from + k * len / (n + 1)) + side * (if k % 2 == 0 then 7.5 else -7.5)
				cyl(f, p + Vector3.new(0, 1.6, 0), 0.35, 3.2, Color3.fromRGB(60, 52, 70), DECOR)
				ball(f, p + Vector3.new(0, 3.7, 0), 0.7, if k % 2 == 0 then th.accent else th.accent2, NEON)
			end
		end
	end

	buildPlaza(f, center, pl, th)

	for _, z in pl.zones do
		local zc = at(z.offset)
		buildZone(f, zc, z, th, ((center - zc) * Vector3.new(1, 0, 1)).Unit)
	end
	for _, c in pl.camps do
		local cc = at(c.offset)
		buildCamp(f, cc, c, th, ((center - cc) * Vector3.new(1, 0, 1)).Unit, rng)
	end
	do
		local bc = at(pl.boss.offset)
		buildBossArena(f, bc, pl.boss, th, ((center - bc) * Vector3.new(1, 0, 1)).Unit)
	end

	-- rim mountains
	local nM = 22
	for i = 1, nM do
		local a = i / nM * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local r = R + rng:NextNumber(10, 40)
		local h = rng:NextNumber(70, 150)
		mountain(f, center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:NextNumber(40, 62), h, th, rng)
	end

	-- a lake and a few walkable plateaus
	local function spot(minR: number, maxR: number, pad: number): Vector3?
		for _ = 1, 60 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(minR, maxR)
			local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if free(p, pad) then
				return p
			end
		end
		return nil
	end
	local lakePos = spot(Config.PlazaRadius + 50, R - 90, 34)
	if lakePos then
		lake(f, lakePos, 26, th, rng, pl.theme)
		table.insert(pois, { pos = lakePos, r = 30 })
	end
	for _ = 1, 5 do
		local p = spot(Config.PlazaRadius + 40, R - 70, 24)
		if p then
			local top = terrace(f, p, rng:NextNumber(14, 20), th, rng)
			table.insert(pois, { pos = p, r = 22 })
			if rng:NextNumber() < 0.5 then
				crystal(f, top, 1.6, if rng:NextNumber() < 0.5 then th.accent else th.accent2, rng)
			else
				scatterProp(f, top, th, rng)
			end
		end
	end

	-- scattered props
	local placed = 0
	local tries = 0
	while placed < 64 and tries < 500 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(Config.PlazaRadius + 14, R - 30)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if free(p, 6) then
			placed += 1
			if placed % 6 == 0 then
				rock(f, p, rng:NextNumber(0.8, 1.8), th, rng)
			elseif placed % 9 == 0 then
				crystal(f, p, rng:NextNumber(0.9, 1.6), if placed % 2 == 0 then th.accent else th.accent2, rng)
			else
				scatterProp(f, p, th, rng)
			end
		end
	end
	-- undergrowth: bushes and flower clusters
	for i = 1, 46 do
		local p = spot(Config.PlazaRadius + 8, R - 26, 3)
		if p then
			if i % 2 == 0 then
				bush(f, p, rng:NextNumber(0.8, 1.5), th, rng, pl.theme)
			else
				flowers(f, p, th, rng, pl.theme)
			end
		end
	end

	-- landmarks: floating islands with a crystal, high above the rim
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.6
		local p = center + Vector3.new(math.cos(a) * (R * 0.72), 95 + i * 14, math.sin(a) * (R * 0.72))
		local island = blob(f, CFrame.new(p), Vector3.new(60, 24, 60), th.cliffMid, { collide = false, anim = "bob" })
		island:SetAttribute("KiwPhase", i * 1.3)
		island:SetAttribute("KiwAmp", 2.5)
		cyl(f, p + Vector3.new(0, 7, 0), 27, 4, th.ground, { mat = th.groundMat, collide = true })
		cyl(f, p + Vector3.new(0, 9.2, 0), 25.5, 0.4, th.patchA, { mat = th.groundMat, collide = false })
		crystal(f, p + Vector3.new(0, 9, 0), 2.4, if i % 2 == 0 then th.accent else th.accent2, rng)
		scatterProp(f, p + Vector3.new(12, 9, -8), th, rng)
	end

	-- the giant landmark beyond the rim + sky dressing
	do
		local a = math.rad(315)
		landmark(f, center + Vector3.new(math.cos(a) * (R + 150), 0, math.sin(a) * (R + 150)), pl.theme, th, rng)
		for i = 1, 10 do
			local sa = i / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local sr = rng:NextNumber(R * 0.35, R * 1.25)
			skyFeature(f, center + Vector3.new(math.cos(sa) * sr, rng:NextNumber(190, 300), math.sin(sa) * sr), pl.theme, th, rng, i)
		end
	end

	info.centers[pl.index] = center
end

---------------------------------------------------------------------------
-- Planet 1 specials: coliseum, wish altar, world boss crater, master, boards
---------------------------------------------------------------------------
local function buildArena(world: Instance, info: { [string]: any })
	local A = Config.Arena
	local center = info.centers[A.planet] + Vector3.new(A.offset[1], 0, A.offset[3])
	local toward = ((info.centers[A.planet] - center) * Vector3.new(1, 0, 1)).Unit
	local f = Instance.new("Folder")
	f.Name = "Arena"
	f.Parent = world
	local r, w = A.radius, A.wall
	local red, gold, stone = Color3.fromRGB(230, 70, 70), Color3.fromRGB(255, 200, 70), Color3.fromRGB(222, 210, 190)
	cyl(f, center + Vector3.new(0, 0.3, 0), w + 12, 0.6, stone:Lerp(Color3.new(0, 0, 0), 0.3), { collide = true })
	cyl(f, center + Vector3.new(0, 0.9, 0), r, 1, Color3.fromRGB(236, 220, 176), { collide = true, name = "ArenaFloor" })
	cyl(f, center + Vector3.new(0, 1.42, 0), r - 1, 0.1, red, DECOR)
	cyl(f, center + Vector3.new(0, 1.45, 0), r - 3.5, 0.1, Color3.fromRGB(240, 226, 186), DECOR)
	cyl(f, center + Vector3.new(0, 1.48, 0), r * 0.5, 0.1, gold, DECOR)
	cyl(f, center + Vector3.new(0, 1.51, 0), r * 0.5 - 2, 0.1, Color3.fromRGB(240, 226, 186), DECOR)
	cyl(f, center + Vector3.new(0, 1.54, 0), 9, 0.1, red, DECOR)
	-- stands: wall segments with gates on four sides
	local n = 28
	for i = 1, n do
		local a = i / n * math.pi * 2
		local gap = i % 7 == 0
		local p = center + Vector3.new(math.cos(a) * w, 0, math.sin(a) * w)
		local cf = CFrame.lookAt(p, Vector3.new(center.X, 0, center.Z))
		if not gap then
			block(f, cf * CFrame.new(0, 5, 0), Vector3.new(16.5, 10, 5), stone, { collide = true })
			block(f, cf * CFrame.new(0, 12, 4), Vector3.new(16.5, 6, 5), stone:Lerp(Color3.new(0, 0, 0), 0.12), { collide = true })
			block(f, cf * CFrame.new(0, 17, 8), Vector3.new(16.5, 6, 5), stone:Lerp(Color3.new(0, 0, 0), 0.22), { collide = true })
			block(f, cf * CFrame.new(0, 10.4, -0.2), Vector3.new(16.5, 1, 5.6), if i % 2 == 0 then red else gold, DECOR)
			-- crowd: bright blobs on the stands (cheap, and they sell "people are watching")
			for k = -1, 1 do
				blob(f, cf * CFrame.new(k * 5, 16.8, 3.6), Vector3.new(2.6, 3.2, 2.6), Color3.fromHSV(((i * 3 + k) % 10) / 10, 0.6, 0.95), { collide = false, anim = "bob" }):SetAttribute("KiwPhase", i + k)
			end
		else
			for _, side in { -1, 1 } do
				block(f, cf * CFrame.new(side * 7, 9, 0), Vector3.new(3, 18, 5), gold, { collide = true })
			end
			block(f, cf * CFrame.new(0, 19, 0), Vector3.new(17, 3, 5), red, { collide = true })
		end
		if i % 4 == 0 then
			local pole = cf * CFrame.new(0, 28, 9)
			cyl(f, pole.Position, 0.5, 18, Color3.fromRGB(60, 52, 70), DECOR)
			local flag = block(f, pole * CFrame.new(3, 6, 0), Vector3.new(5.4, 4, 0.3), if i % 8 == 0 then red else gold, { collide = false, anim = "flag" })
			flag:SetAttribute("KiwPhase", i)
		end
	end
	local signPos = center + toward * (w + 20)
	gate(f, Vector3.new(signPos.X, 0, signPos.Z), toward, Color3.fromRGB(150, 36, 46), gold, { { key = "world.arena" }, { key = "world.arena_pvp", color = Color3.fromRGB(255, 226, 90) } })
	info.arenaCenter = center + Vector3.new(0, 1.5, 0)
end

local function buildAltar(world: Instance, info: { [string]: any })
	local W = Config.WishAltar
	local center = info.centers[W.planet] + Vector3.new(W.offset[1], 0, W.offset[3])
	local f = Instance.new("Folder")
	f.Name = "WishAltar"
	f.Parent = world
	local navy, gold = Color3.fromRGB(36, 40, 88), Color3.fromRGB(255, 214, 90)
	cyl(f, center + Vector3.new(0, 0.5, 0), W.radius + 4, 1, Color3.fromRGB(70, 74, 120), { collide = true })
	cyl(f, center + Vector3.new(0, 1.3, 0), W.radius, 0.8, navy, { collide = true })
	cyl(f, center + Vector3.new(0, 1.74, 0), W.radius - 1.5, 0.1, gold, NEON)
	cyl(f, center + Vector3.new(0, 1.78, 0), W.radius - 2.6, 0.1, navy, DECOR)
	-- monolith with a star window
	block(f, CFrame.new(center + Vector3.new(0, 12, 0)), Vector3.new(7, 22, 3), navy:Lerp(Color3.new(0, 0, 0), 0.3), { collide = true, name = "Monolith" })
	local star = block(f, CFrame.new(center + Vector3.new(0, 16, 0)) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(4, 4, 3.4), gold, { mat = Enum.Material.Neon, collide = false, anim = "pulse", name = "Star" })
	light(star, gold, 40, 2)
	block(f, CFrame.new(center + Vector3.new(0, 23.6, 0)), Vector3.new(9, 1.4, 4), gold, NEON)
	-- six seal pedestals
	for i = 1, Config.Relics.count do
		local a = i / Config.Relics.count * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * (W.radius - 4), 1.7, math.sin(a) * (W.radius - 4))
		cyl(f, p + Vector3.new(0, 1.5, 0), 1.5, 3, Color3.fromRGB(80, 84, 130), { collide = true })
		local slot = cyl(f, p + Vector3.new(0, 3.1, 0), 1.2, 0.3, rgb(Config.Relics.colors[i]):Lerp(Color3.fromRGB(30, 30, 50), 0.6), DECOR)
		slot.Name = "SealSlot" .. i
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WishPrompt"
	prompt.ActionText = "Make a wish"
	prompt.ObjectText = "Wish Altar"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.B
	prompt:SetAttribute("LocAction", "world.make_wish")
	prompt:SetAttribute("LocObject", "world.wish_altar")
	prompt.Parent = star
	local toward = ((info.centers[W.planet] - center) * Vector3.new(1, 0, 1)).Unit
	standSign(f, Vector3.new(center.X, 0, center.Z) + toward * (W.radius + 8), toward, navy, { { key = "world.wish_altar" }, { key = "world.wish_hint", color = gold } }, 18)
	info.altarCenter = center + Vector3.new(0, 1.8, 0)
end

local function buildCrater(world: Instance, info: { [string]: any })
	local S = Config.WorldBossSite
	local center = info.centers[S.planet] + Vector3.new(S.offset[1], 0, S.offset[3])
	local f = Instance.new("Folder")
	f.Name = "WorldBossSite"
	f.Parent = world
	local dark, glow = Color3.fromRGB(40, 44, 78), Color3.fromRGB(120, 255, 230)
	cyl(f, center + Vector3.new(0, 0.16, 0), S.radius, 0.3, dark, DECOR)
	cyl(f, center + Vector3.new(0, 0.2, 0), S.radius * 0.72, 0.3, dark:Lerp(Color3.new(0, 0, 0), 0.3), DECOR)
	cyl(f, center + Vector3.new(0, 0.24, 0), S.radius * 0.4, 0.3, Color3.fromRGB(18, 20, 40), DECOR)
	local rng = Random.new(99)
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * S.radius, 0, math.sin(a) * S.radius)
		local h = rng:NextNumber(8, 20)
		block(f, CFrame.lookAt(p, Vector3.new(center.X, 0, center.Z)) * CFrame.Angles(math.rad(22), 0, 0) * CFrame.new(0, h / 2, 0), Vector3.new(7, h, 6), dark, { collide = true })
		if i % 2 == 0 then
			block(f, CFrame.new(p + Vector3.new(0, h + 1, 0)) * CFrame.Angles(0.6, a, 0.6), Vector3.new(2, 2, 2), glow, { mat = Enum.Material.Neon, collide = false, anim = "pulse" }):SetAttribute("KiwPhase", i)
		end
	end
	local toward = ((info.centers[S.planet] - center) * Vector3.new(1, 0, 1)).Unit
	local signPos = center + toward * (S.radius + 12)
	gate(f, Vector3.new(signPos.X, 0, signPos.Z), toward, Color3.fromRGB(30, 50, 110), glow, { { key = "world.worldboss_site" }, { key = "world.worldboss", color = glow } })
	info.worldBossCenter = center
end

local function buildBoards(world: Instance, info: { [string]: any })
	local center = info.centers[1]
	local f = Instance.new("Folder")
	f.Name = "Boards"
	f.Parent = world
	local boards = {}
	local defs = { { id = "power", key = "board.power", color = Color3.fromRGB(255, 120, 60) }, { id = "rebirths", key = "board.rebirths", color = Color3.fromRGB(170, 110, 255) }, { id = "arena", key = "board.arena", color = Color3.fromRGB(230, 70, 70) } }
	for i, d in defs do
		local a = math.rad(200 + i * 22)
		local p = center + Vector3.new(math.cos(a) * (Config.PlazaRadius - 9), 0.7, math.sin(a) * (Config.PlazaRadius - 9))
		local cf = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
		for _, side in { -1, 1 } do
			block(f, cf * CFrame.new(side * 6.5, 7, 0), Vector3.new(1.2, 14, 1.2), Color3.fromRGB(50, 44, 66), { collide = true })
		end
		block(f, cf * CFrame.new(0, 15, 0), Vector3.new(15, 2.6, 1.4), d.color, NEON)
		local board = block(f, cf * CFrame.new(0, 7.6, 0), Vector3.new(12.4, 12.4, 0.8), Color3.fromRGB(26, 22, 44), { collide = true, name = "Board_" .. d.id })
		local gui = Instance.new("SurfaceGui")
		gui.Name = "BoardGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0.13, 0)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = d.color:Lerp(Color3.new(1, 1, 1), 0.4)
		title:SetAttribute("LocKey", d.key)
		title.Parent = gui
		local list = Instance.new("Frame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.Size = UDim2.new(0.92, 0, 0.84, 0)
		list.Position = UDim2.new(0.04, 0, 0.14, 0)
		list.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
		boards[d.id] = board
	end
	info.boards = boards
end

-- The quest giver: a chunky robed master with a staff (static figure).
local function buildMaster(world: Instance, info: { [string]: any })
	local o = Config.MasterSpot.offset
	local pos = info.centers[1] + Vector3.new(o[1], 0.75, o[3])
	local f = Instance.new("Model")
	f.Name = "Master"
	f.Parent = world
	local robe, skin, sash = Color3.fromRGB(240, 120, 50), Color3.fromRGB(240, 200, 160), Color3.fromRGB(50, 80, 170)
	local cf = CFrame.lookAt(pos, Vector3.new(info.centers[1].X, pos.Y, info.centers[1].Z + 22))
	cyl(f, pos + Vector3.new(0, 0.3, 0), 3.2, 0.6, Color3.fromRGB(90, 84, 110), { collide = true })
	blob(f, cf * CFrame.new(0, 2.6, 0), Vector3.new(4.2, 4.6, 3.4), robe, DECOR)
	block(f, cf * CFrame.new(0, 2.4, -0.1), Vector3.new(4.3, 0.7, 3.5), sash, DECOR)
	ball(f, (cf * CFrame.new(0, 5.6, 0)).Position, 1.5, skin, DECOR)
	blob(f, cf * CFrame.new(0, 4.9, -1.1), Vector3.new(1.6, 2, 0.8), Color3.fromRGB(245, 245, 250), DECOR) -- beard
	blob(f, cf * CFrame.new(0, 6.7, 0.2), Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(245, 245, 250), DECOR) -- top knot
	for _, side in { -1, 1 } do
		blob(f, cf * CFrame.new(side * 2.3, 3.2, -0.3), Vector3.new(1.3, 2.8, 1.3), robe:Lerp(Color3.new(0, 0, 0), 0.1), DECOR)
		block(f, cf * CFrame.new(side * 0.5, 5.8, -1.4), Vector3.new(0.35, 0.2, 0.1), Color3.fromRGB(30, 26, 40), DECOR)
	end
	rod(f, cf * CFrame.new(2.9, 3.6, -0.8) * CFrame.Angles(0, 0, math.rad(90)), 0.22, 8, Color3.fromRGB(120, 84, 58), DECOR)
	local orb = ball(f, (cf * CFrame.new(2.9, 7.9, -0.8)).Position, 0.8, Color3.fromRGB(90, 230, 255), { mat = Enum.Material.Neon, collide = false, anim = "pulse" })
	light(orb, Color3.fromRGB(90, 230, 255), 18, 1.5)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(220, 60)
	bb.StudsOffset = Vector3.new(0, 10, 0)
	bb.MaxDistance = 120
	bb.AlwaysOnTop = false
	bb.Adornee = orb
	bb.Parent = orb
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 226, 90)
	t:SetAttribute("LocKey", "npc.master")
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = Color3.fromRGB(20, 16, 36)
	s.Parent = t
	t.Parent = bb
	info.masterPos = pos
end

function WorldBuilder.build(): { [string]: any }
	partCount = 0
	local world = Instance.new("Folder")
	world.Name = "World"
	local info: { [string]: any } = { centers = {} }
	for _, pl in Config.Planets do
		buildPlanet(world, pl, info)
	end
	buildArena(world, info)
	buildAltar(world, info)
	buildCrater(world, info)
	buildBoards(world, info)
	buildMaster(world, info)
	world.Parent = workspace
	info.partCount = partCount
	world:SetAttribute("PartCount", partCount)
	return info
end

return WorldBuilder
