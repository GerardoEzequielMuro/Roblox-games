--!nonstrict
-- Client-side enemy models. The server only replicates one invisible root part per enemy
-- (workspace.Enemies); this module builds a procedural model for it (5 archetypes, coloured
-- from Config), smooths its movement and animates walk / windup / flinch. One loop for all.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local CombatFx = require(script.Parent.CombatFx)
local Lang = require(script.Parent.Lang)

local NpcRender = {}

local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(24, 18, 34)

type Visual = { [string]: any }
local visuals: { [BasePart]: Visual } = {}
local byFighter: { [number]: Visual } = {}
NpcRender.visuals = visuals

local holder = Instance.new("Folder")
holder.Name = "KiwEnemies"
holder.Parent = workspace

---------------------------------------------------------------------------
-- Model builder
---------------------------------------------------------------------------
local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function build(def): (Model, BasePart, { [string]: Weld }, { BasePart }, { BasePart })
	local s = def.scale or 1
	local c, acc = rgb(def.color), rgb(def.accent)
	local dark = c:Lerp(Color3.new(0, 0, 0), 0.35)
	local model = Instance.new("Model")
	model.Name = def.id
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.Transparency = 1
	pivot.Size = Vector3.new(1, 1, 1)
	pivot.Parent = model
	model.PrimaryPart = pivot
	local limbs: { [string]: Weld } = {}
	local spin: { BasePart } = {}
	local glow: { BasePart } = {}

	local function part(shape: string, size: Vector3, color: Color3, offset: CFrame, neon: boolean?, to: BasePart?, limb: string?): BasePart
		local p: BasePart
		if shape == "ball" then
			local b = Instance.new("Part")
			b.Shape = Enum.PartType.Ball
			p = b
		elseif shape == "blob" then
			p = Instance.new("Part")
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		elseif shape == "wedge" then
			p = Instance.new("WedgePart")
		elseif shape == "cyl" then
			local b = Instance.new("Part")
			b.Shape = Enum.PartType.Cylinder
			p = b
		else
			p = Instance.new("Part")
		end
		p.Size = size * s
		p.Color = color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local w = Instance.new("Weld")
		w.Part0 = to or pivot
		w.Part1 = p
		w.C0 = CFrame.new(offset.Position * s) * (offset - offset.Position)
		w.Parent = p
		p.Parent = model
		if limb then
			limbs[limb] = w
		end
		if neon then
			table.insert(glow, p)
		end
		return p
	end
	local function eyes(y: number, z: number, spread: number, size: number, angry: boolean?)
		for _, side in { -1, 1 } do
			part("ball", Vector3.one * size, WHITE, CFrame.new(side * spread, y, z))
			part("ball", Vector3.one * size * 0.5, DARK, CFrame.new(side * spread, y, z - size * 0.32))
			if angry then
				part("block", Vector3.new(size * 1.3, size * 0.28, 0.2), DARK, CFrame.new(side * spread, y + size * 0.55, z - size * 0.2) * CFrame.Angles(0, 0, math.rad(side * 22)))
			end
		end
	end

	local arch = def.arch
	if arch == "imp" then
		part("blob", Vector3.new(3, 3, 2.6), c, CFrame.new(0, -1.3, 0))
		part("blob", Vector3.new(2, 1.6, 0.4), c:Lerp(WHITE, 0.35), CFrame.new(0, -1.4, -1.15))
		part("ball", Vector3.one * 2.7, c, CFrame.new(0, 0.9, 0))
		eyes(1.0, -1.15, 0.55, 0.7, true)
		part("block", Vector3.new(0.9, 0.22, 0.2), DARK, CFrame.new(0, 0.25, -1.28))
		for _, side in { -1, 1 } do
			part("wedge", Vector3.new(0.4, 1.4, 0.7), acc, CFrame.new(side * 0.85, 2.3, 0) * CFrame.Angles(0, math.rad(side * 90), math.rad(-side * 12)), true)
			part("blob", Vector3.new(0.9, 1.8, 0.9), dark, CFrame.new(side * 1.75, -1.1, 0), false, nil, if side == 1 then "armR" else "armL")
			part("blob", Vector3.new(1.1, 1.0, 1.4), dark, CFrame.new(side * 0.75, -2.7, -0.1), false, nil, if side == 1 then "legR" else "legL")
		end
		part("block", Vector3.new(0.35, 0.35, 1.6), acc, CFrame.new(0, -1.6, 1.7) * CFrame.Angles(math.rad(30), 0, 0), true)
	elseif arch == "brute" then
		part("block", Vector3.new(3.6, 3.2, 2.1), c, CFrame.new(0, -0.2, 0))
		part("block", Vector3.new(2.6, 1.2, 1.9), dark, CFrame.new(0, -2.0, 0))
		part("block", Vector3.new(3.7, 0.5, 2.2), acc, CFrame.new(0, -1.3, 0))
		part("block", Vector3.new(1.8, 1.7, 1.7), c:Lerp(WHITE, 0.12), CFrame.new(0, 2.2, 0))
		eyes(2.35, -0.85, 0.42, 0.42, true)
		part("block", Vector3.new(1.1, 0.24, 0.2), DARK, CFrame.new(0, 1.75, -0.88))
		part("block", Vector3.new(1.9, 0.5, 1.8), acc, CFrame.new(0, 3.2, 0))
		for _, side in { -1, 1 } do
			part("block", Vector3.new(1.7, 1.2, 2.3), acc, CFrame.new(side * 2.5, 1.2, 0))
			local arm = part("block", Vector3.new(1.4, 3.4, 1.4), c, CFrame.new(side * 2.6, -0.6, 0), false, nil, if side == 1 then "armR" else "armL")
			part("block", Vector3.new(1.8, 1.4, 1.8), dark, CFrame.new(0, -1.9, 0), false, arm)
			part("block", Vector3.new(1.3, 1.9, 1.4), dark, CFrame.new(side * 0.85, -2.95, 0), false, nil, if side == 1 then "legR" else "legL")
		end
	elseif arch == "wisp" then
		local core = part("ball", Vector3.one * 2.2, acc, CFrame.new(0, 0, 0), true)
		local shell = part("ball", Vector3.one * 3.6, c, CFrame.new(0, 0, 0))
		shell.Transparency = 0.45
		shell.Material = Enum.Material.Glass
		part("ball", Vector3.one * 1.0, WHITE, CFrame.new(0, 0.1, -1.55))
		part("ball", Vector3.one * 0.5, DARK, CFrame.new(0, 0.1, -1.95))
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2
			local sh = part("block", Vector3.new(0.6, 2.2, 0.6), if i % 2 == 0 then acc else c, CFrame.new(math.cos(a) * 3, 0, math.sin(a) * 3) * CFrame.Angles(0.5, a, 0.4), true)
			table.insert(spin, sh)
		end
		part("wedge", Vector3.new(0.6, 2.2, 1.2), c, CFrame.new(0, -2.4, 0.3) * CFrame.Angles(math.rad(180), 0, 0))
		local _ = core
	elseif arch == "knight" then
		part("block", Vector3.new(2.8, 3, 1.7), c, CFrame.new(0, -0.1, 0))
		part("block", Vector3.new(1.5, 1.7, 0.3), acc, CFrame.new(0, 0.1, -0.9), true)
		part("block", Vector3.new(2.2, 1.0, 1.6), dark, CFrame.new(0, -1.9, 0))
		part("block", Vector3.new(1.7, 1.8, 1.7), c:Lerp(WHITE, 0.2), CFrame.new(0, 2.25, 0))
		part("block", Vector3.new(1.3, 0.34, 0.3), acc, CFrame.new(0, 2.35, -0.78), true)
		part("wedge", Vector3.new(0.4, 1.7, 1.6), acc, CFrame.new(0, 3.7, 0.1), true)
		part("block", Vector3.new(2.7, 3.6, 0.25), acc:Lerp(DARK, 0.45), CFrame.new(0, -0.6, 1.0) * CFrame.Angles(math.rad(-8), 0, 0))
		for _, side in { -1, 1 } do
			part("wedge", Vector3.new(1.4, 1.1, 2), c:Lerp(WHITE, 0.2), CFrame.new(side * 2.0, 1.6, 0) * CFrame.Angles(0, math.rad(side * 90), 0))
			local arm = part("block", Vector3.new(1.1, 3, 1.1), dark, CFrame.new(side * 2.0, -0.4, 0), false, nil, if side == 1 then "armR" else "armL")
			if side == 1 then
				part("block", Vector3.new(0.4, 0.5, 5), acc, CFrame.new(0, -1.5, -2.2), true, arm)
				part("block", Vector3.new(1.4, 0.5, 0.4), dark, CFrame.new(0, -1.5, -0.2), false, arm)
			else
				part("block", Vector3.new(0.4, 2.8, 2.4), c:Lerp(WHITE, 0.2), CFrame.new(-0.7, -0.9, -0.4), false, arm)
				part("block", Vector3.new(0.45, 1, 1), acc, CFrame.new(-0.75, -0.9, -0.4), true, arm)
			end
			part("block", Vector3.new(1.15, 2.1, 1.2), dark, CFrame.new(side * 0.7, -3.0, 0), false, nil, if side == 1 then "legR" else "legL")
		end
	else -- titan
		part("block", Vector3.new(4.2, 3.2, 2.4), c, CFrame.new(0, 0.1, 0))
		part("block", Vector3.new(3, 1.4, 2), dark, CFrame.new(0, -1.9, 0))
		local heart = part("ball", Vector3.one * 1.6, acc, CFrame.new(0, 0.3, -1.05), true)
		local _ = heart
		part("block", Vector3.new(1.9, 1.7, 1.8), c:Lerp(WHITE, 0.1), CFrame.new(0, 2.5, -0.1))
		eyes(2.7, -0.98, 0.45, 0.4, true)
		for i = -2, 2 do
			part("wedge", Vector3.new(0.4, 1.2 + (2 - math.abs(i)) * 0.5, 0.7), acc, CFrame.new(i * 0.42, 3.8 + (2 - math.abs(i)) * 0.22, 0) * CFrame.Angles(0, 0, math.rad(-i * 10)), true)
		end
		for _, side in { -1, 1 } do
			part("block", Vector3.new(2, 1.5, 2.8), acc:Lerp(dark, 0.3), CFrame.new(side * 3.0, 1.5, 0))
			part("wedge", Vector3.new(0.5, 1.6, 1.2), acc, CFrame.new(side * 3.2, 2.9, 0) * CFrame.Angles(0, 0, math.rad(-side * 24)), true)
			local arm = part("block", Vector3.new(1.8, 3.6, 1.8), c, CFrame.new(side * 3.1, -0.6, 0), false, nil, if side == 1 then "armR" else "armL")
			part("block", Vector3.new(2.3, 1.8, 2.3), dark, CFrame.new(0, -2.2, 0), false, arm)
			part("block", Vector3.new(2.35, 0.4, 2.35), acc, CFrame.new(0, -1.5, 0), true, arm)
			part("block", Vector3.new(1.5, 1.7, 1.6), dark, CFrame.new(side * 1.0, -3.0, 0), false, nil, if side == 1 then "legR" else "legL")
		end
		part("block", Vector3.new(3.4, 3.6, 0.3), acc:Lerp(DARK, 0.5), CFrame.new(0, -0.7, 1.35) * CFrame.Angles(math.rad(-10), 0, 0))
	end
	return model, pivot, limbs, spin, glow
end
NpcRender.build = build

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------
-- Name + health plate size in screen pixels. Offset sizing keeps it the same size at any
-- distance (scale sizing would grow into a wall as you walk up to it); it is also capped
-- to a fraction of the viewport so it stays small on phones and in small Studio windows.
local function plateSize(boss: boolean): UDim2
	local w, h = if boss then 170 else 96, if boss then 34 else 24
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local k = math.clamp(math.min(vp.X * (if boss then 0.16 else 0.09) / w, vp.Y * 0.05 / h), 0.55, 1)
	return UDim2.fromOffset(math.floor(w * k), math.floor(h * k))
end

local function healthBar(v: Visual)
	local def = v.def
	local s = def.scale or 1
	local bb = Instance.new("BillboardGui")
	bb.Name = "Hp"
	bb.Size = plateSize(def.boss == true)
	bb.StudsOffset = Vector3.new(0, 4.6 * s + 1.4, 0)
	bb.MaxDistance = if def.boss then 200 else 70
	bb.AlwaysOnTop = false
	bb.ClipsDescendants = true
	bb.ResetOnSpawn = false
	bb.LightInfluence = 0
	bb.Adornee = v.pivot
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.55)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = if def.boss then Color3.fromRGB(255, 210, 90) else WHITE
	name.Text = Lang.t("npc." .. def.id)
	local st = Instance.new("UIStroke")
	st.Thickness = 2.5
	st.Color = DARK
	st.Parent = name
	name.Parent = bb
	local back = Instance.new("Frame")
	back.BackgroundColor3 = DARK
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 0.36)
	back.Position = UDim2.fromScale(0, 0.6)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = DARK
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = if def.boss then Color3.fromRGB(255, 80, 90) else Color3.fromRGB(110, 230, 110)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	corner:Clone().Parent = fill
	fill.Parent = back
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.fromScale(1, 1)
	txt.Font = Enum.Font.GothamBold
	txt.TextScaled = true
	txt.TextColor3 = WHITE
	txt.ZIndex = 2
	local st2 = st:Clone()
	st2.Thickness = 1.5
	st2.Parent = txt
	txt.Parent = back
	back.Parent = bb
	bb.Parent = v.pivot
	v.gui = bb
	v.bar = fill
	v.barText = txt
	v.nameLabel = name
	v.barBack = back
	name.Visible = def.boss == true
	back.Visible = def.boss == true
end

local function add(root: BasePart)
	if visuals[root] then
		return
	end
	local def = Config.Npcs[(root:GetAttribute("Kind") or root.Name) :: any]
	if not def then
		return
	end
	local model, pivot, limbs, spin, glow = build(def)
	local rest = {}
	for name, w in limbs do
		rest[name] = w.C0
	end
	local v: Visual = {
		root = root,
		def = def,
		model = model,
		pivot = pivot,
		limbs = limbs,
		rest = rest,
		spin = spin,
		cf = root.CFrame,
		lastPos = root.Position,
		walk = math.random() * 6,
		speed = 0,
		flinchAt = -10,
		shownHp = -1,
		glow = glow,
	}
	pivot.CFrame = root.CFrame
	healthBar(v)
	model.Parent = holder
	visuals[root] = v
	local id = root:GetAttribute("FighterId")
	if id then
		byFighter[id] = v
	end
	-- spawn pop
	Fx.burst(root.Position, 1, 5 * (def.scale or 1), rgb(def.accent), 0.3, 0.5)
end

local function remove(root: BasePart)
	local v = visuals[root]
	if v then
		visuals[root] = nil
		for id, vv in byFighter do
			if vv == v then
				byFighter[id] = nil
			end
		end
		v.model:Destroy()
	end
end

local function step(v: Visual, dt: number, now: number, camPos: Vector3)
	local root = v.root
	local def = v.def
	local s = def.scale or 1
	local target = root.CFrame
	-- smooth the 10 Hz server movement
	local alpha = 1 - math.exp(-dt * 13)
	v.cf = v.cf:Lerp(target, alpha)
	local pos = v.cf.Position
	local moved = (pos - v.lastPos).Magnitude / math.max(dt, 1e-3)
	v.lastPos = pos
	v.speed += (moved - v.speed) * math.min(1, dt * 8)
	local far = (camPos - pos).Magnitude > (if Fx.lite then 130 else 220)
	local state = root:GetAttribute("State")
	local cf = v.cf
	local moving = v.speed > 2
	if moving then
		v.walk += dt * (6 + v.speed * 0.35)
	end
	if not far then
		-- body motion
		local bob = if def.arch == "wisp" then math.sin(now * 2.2 + v.walk) * 0.7 * s else (if moving then math.abs(math.sin(v.walk)) * 0.35 * s else math.sin(now * 2 + v.walk) * 0.08 * s)
		local lean = 0
		if state == "windup" then
			-- rear back, then the server resolves the hit
			lean = 0.32
			local k = math.sin(now * 40) * 0.05
			cf *= CFrame.new(k, 0, 0.6 * s)
		elseif state == "recover" then
			lean = -0.42
			cf *= CFrame.new(0, 0, -1.4 * s)
		elseif state == "charging" then
			lean = -0.5
		end
		local ft = now - v.flinchAt
		if ft < 0.16 then
			local k = 1 - ft / 0.16
			cf *= CFrame.new(0, 0, 0.9 * k * s) * CFrame.Angles(0.3 * k, 0, 0)
		end
		cf = cf * CFrame.new(0, bob, 0) * CFrame.Angles(lean, 0, 0)
		local swing = if moving then math.sin(v.walk) * 0.7 else 0
		local attackArm = if state == "windup" then -2.2 elseif state == "recover" then 1.1 else 0
		for name, w in v.limbs do
			local rest = v.rest[name]
			local a = 0
			if name == "legR" then
				a = swing
			elseif name == "legL" then
				a = -swing
			elseif name == "armR" then
				a = -swing * 0.8 + attackArm
			elseif name == "armL" then
				a = swing * 0.8 + (if def.boss then attackArm else 0)
			end
			-- rotate around the top of the limb
			local half = (w.Part1 :: BasePart).Size.Y / 2
			w.C0 = rest * CFrame.new(0, half, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, -half, 0)
		end
		for i, sh in v.spin do
			local w = sh:FindFirstChildOfClass("Weld")
			if w then
				local a = now * 1.6 + i * math.pi / 2
				w.C0 = CFrame.new(math.cos(a) * 3 * s, math.sin(now * 2 + i) * 0.6 * s, math.sin(a) * 3 * s) * CFrame.Angles(0.5, a, 0.4)
			end
		end
	end
	v.pivot.CFrame = cf
	-- health bar: the name only up close, the bar only once hurt (bosses always show both),
	-- so a camp of enemies is not a wall of labels
	local hp = root:GetAttribute("Hp") or 0
	local max = root:GetAttribute("MaxHp") or 1
	if hp ~= v.shownHp and v.bar then
		v.shownHp = hp
		v.bar.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		v.barText.Text = Format.abbrev(hp)
	end
	if not def.boss and v.nameLabel then
		local d = (camPos - pos).Magnitude
		local showName = d < 34
		local showBar = hp < max or d < 22
		if showName ~= v.nameLabel.Visible then
			v.nameLabel.Visible = showName
		end
		if showBar ~= v.barBack.Visible then
			v.barBack.Visible = showBar
		end
	end
end

function NpcRender.visualOf(fighterId: number): Visual?
	return byFighter[fighterId]
end

-- Nearest living enemy to a point (auto-aim, auto-fight walking).
function NpcRender.nearest(pos: Vector3, range: number, dir: Vector3?, minDot: number?): (BasePart?, number)
	local best, bestD = nil, range
	for root, v in visuals do
		local p = root.Position
		local d = (p - pos).Magnitude
		if d < bestD then
			if not dir or (p - pos).Unit:Dot(dir) >= (minDot or 0) then
				best, bestD = root, d
			end
		end
	end
	return best, bestD
end

function NpcRender.init()
	local function watch(folder: Instance)
		folder.ChildAdded:Connect(function(c)
			if c:IsA("BasePart") then
				task.defer(add, c)
			end
		end)
		folder.ChildRemoved:Connect(function(c)
			if c:IsA("BasePart") then
				remove(c)
			end
		end)
		for _, c in folder:GetChildren() do
			if c:IsA("BasePart") then
				add(c)
			end
		end
	end
	task.spawn(function()
		watch(workspace:WaitForChild("Enemies"))
	end)
	CombatFx.on("hit", function(d)
		local v = byFighter[d.v]
		if v then
			v.flinchAt = os.clock()
		end
	end)
	Lang.Changed:Connect(function()
		for _, v in visuals do
			local name = v.gui and v.gui:FindFirstChildOfClass("TextLabel")
			if name then
				name.Text = Lang.t("npc." .. v.def.id)
			end
		end
	end)
	-- keep the plates small when the window / phone orientation changes
	local function resizePlates()
		for _, v in visuals do
			if v.gui then
				v.gui.Size = plateSize(v.def.boss == true)
			end
		end
	end
	local function hookCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(resizePlates)
		end
		resizePlates()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	hookCamera()
	RunService.RenderStepped:Connect(function(dt)
		if Fx.frozen() then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local now = os.clock()
		local camPos = cam.CFrame.Position
		for root, v in visuals do
			if root.Parent then
				step(v, dt, now, camPos)
			end
		end
	end)
	local _ = Players
end

return NpcRender
