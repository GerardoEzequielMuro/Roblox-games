--!strict
-- Pooled world effects, all client side: lightning bolts, rings, shards, confetti, floating
-- texts and screen flashes. Built from parts and Beams first (they survive graphics level
-- 1), particles on top as an extra. One Heartbeat loop animates everything; pools never
-- grow past their cap.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Prefs = require(script.Parent.Parent.Prefs)

local Fx = {}

local folder = Instance.new("Folder")
folder.Name = "SpinFx"
folder.Parent = Workspace
Fx.folder = folder

local HIDDEN = CFrame.new(0, -400, 0)

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------
type Mote = { part: Part, vel: Vector3, spin: Vector3, life: number, max: number, gravity: number, shrink: boolean, size: Vector3 }
local POOL = 96
local POOL_LITE = 40
local motes: { Mote } = {}
local freeParts: { Part } = {}
local created = 0

local function makePart(): Part
	local p = Instance.new("Part")
	p.Name = "Mote"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Neon
	p.CFrame = HIDDEN
	p.Parent = folder
	return p
end

local function take(): Part?
	local p = table.remove(freeParts)
	if p then
		return p
	end
	local cap = if Prefs.lite() then POOL_LITE else POOL
	if created >= cap then
		return nil
	end
	created += 1
	return makePart()
end

local function give(p: Part)
	p.CFrame = HIDDEN
	p.Transparency = 0
	p.Shape = Enum.PartType.Block
	p.Material = Enum.Material.Neon
	table.insert(freeParts, p)
end

function Fx.poolSize(): number
	return created
end

function Fx.active(): number
	return #motes
end

-- Flying shards / confetti.
function Fx.shards(pos: Vector3, color: Color3, count: number, speed: number?, opts: { gravity: number?, life: number?, size: number?, up: number?, colors: { Color3 }? }?)
	local o: any = opts or {}
	local n = if Prefs.lite() then math.ceil(count / 2) else count
	for i = 1, n do
		local p = take()
		if not p then
			return
		end
		local s = (o.size or 0.5) * (0.6 + math.random() * 0.8)
		p.Size = Vector3.new(s, s, s * (0.4 + math.random() * 0.6))
		p.Color = if o.colors then o.colors[(i - 1) % #o.colors + 1] else color
		p.Transparency = 0
		p.CFrame = CFrame.new(pos)
		local dir = Vector3.new(math.random() - 0.5, (math.random() * 0.8) + (o.up or 0.3), math.random() - 0.5).Unit
		local life = (o.life or 1.1) * (0.7 + math.random() * 0.6)
		table.insert(motes, {
			part = p,
			vel = dir * (speed or 26) * (0.5 + math.random() * 0.8),
			spin = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5),
			life = life,
			max = life,
			gravity = o.gravity or 70,
			shrink = true,
			size = p.Size,
		})
	end
end

local CONFETTI = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 205, 60), Color3.fromRGB(80, 215, 120), Color3.fromRGB(0, 210, 245), Color3.fromRGB(170, 100, 255), Color3.fromRGB(255, 255, 255) }
function Fx.confetti(pos: Vector3, count: number, speed: number?)
	Fx.shards(pos, CONFETTI[1], count, speed or 34, { gravity = 38, life = 2.4, size = 0.55, up = 0.9, colors = CONFETTI })
end

RunService.Heartbeat:Connect(function(dt)
	if #motes == 0 then
		return
	end
	for i = #motes, 1, -1 do
		local m = motes[i]
		m.life -= dt
		if m.life <= 0 then
			give(m.part)
			table.remove(motes, i)
		else
			m.vel = Vector3.new(m.vel.X * (1 - dt * 0.8), m.vel.Y - m.gravity * dt, m.vel.Z * (1 - dt * 0.8))
			local cf = m.part.CFrame
			m.part.CFrame = CFrame.new(cf.Position + m.vel * dt) * (cf - cf.Position) * CFrame.Angles(m.spin.X * dt, m.spin.Y * dt, m.spin.Z * dt)
			if m.shrink then
				local k = math.clamp(m.life / m.max * 2.5, 0, 1)
				m.part.Size = m.size * k
			end
		end
	end
end)

-- A temporary part from the pool, returned after `life` seconds. nil when the pool is full.
function Fx.temp(life: number): Part?
	local p = take()
	if not p then
		return nil
	end
	task.delay(life, function()
		give(p)
	end)
	return p
end

-- Expanding ring on the ground.
function Fx.ring(pos: Vector3, color: Color3, r0: number, r1: number, duration: number)
	local p = Fx.temp(duration + 0.05)
	if not p then
		return
	end
	p.Shape = Enum.PartType.Cylinder
	p.Color = color
	p.Size = Vector3.new(0.25, r0 * 2, r0 * 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.1
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.25, r1 * 2, r1 * 2), Transparency = 1 }):Play()
end

-- A sphere that swells and fades (impacts, explosions).
function Fx.pulse(pos: Vector3, color: Color3, r0: number, r1: number, duration: number)
	local p = Fx.temp(duration + 0.05)
	if not p then
		return
	end
	p.Shape = Enum.PartType.Ball
	p.Color = color
	p.Size = Vector3.one * r0 * 2
	p.CFrame = CFrame.new(pos)
	p.Transparency = 0.15
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * r1 * 2, Transparency = 1 }):Play()
end

-- Jagged lightning between two points, drawn with thin neon parts; flickers twice.
function Fx.bolt(from: Vector3, to: Vector3, color: Color3, thickness: number?)
	local segs = if Prefs.lite() then 4 else 7
	local th = thickness or 0.45
	local parts: { Part } = {}
	for _ = 1, segs do
		local p = Fx.temp(0.5)
		if p then
			p.Color = color
			table.insert(parts, p)
		end
	end
	local function lay()
		local prev = from
		local n = #parts
		for i, p in parts do
			local a = i / n
			local target = from:Lerp(to, a)
			if i < n then
				target += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
			end
			p.Size = Vector3.new(th, th, (target - prev).Magnitude)
			p.CFrame = CFrame.lookAt((prev + target) / 2, target)
			prev = target
		end
	end
	task.spawn(function()
		for flick = 1, 3 do
			lay()
			for _, p in parts do
				p.Transparency = if flick == 2 then 0.5 else 0
			end
			task.wait(0.07)
		end
		for _, p in parts do
			TweenService:Create(p, TweenInfo.new(0.18), { Transparency = 1 }):Play()
		end
	end)
end

-- A straight beam of light that fades (aim lasers, meteor trails).
function Fx.line(from: Vector3, to: Vector3, color: Color3, thickness: number, duration: number)
	local p = Fx.temp(duration + 0.05)
	if not p then
		return
	end
	p.Color = color
	p.Size = Vector3.new(thickness, thickness, (to - from).Magnitude)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Transparency = 0.1
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(thickness * 0.2, thickness * 0.2, (to - from).Magnitude) }):Play()
end

---------------------------------------------------------------------------
-- Particle extra (skipped in lite): one shared emitter host, moved to where it is needed
---------------------------------------------------------------------------
-- Built-in textures that ship with every Roblox client (no uploaded assets).
local TEXTURES = {
	sparks = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}
local emitterHost: Part? = nil
local emitters: { [string]: ParticleEmitter } = {}
local function getEmitter(kind: string): (Part, ParticleEmitter)
	local host = emitterHost
	if not host then
		local h = Instance.new("Part")
		h.Name = "EmitterHost"
		h.Anchored = true
		h.CanCollide = false
		h.CanQuery = false
		h.CanTouch = false
		h.Transparency = 1
		h.Size = Vector3.one
		h.Parent = folder
		emitterHost = h
		host = h
	end
	local hostPart = host :: Part
	local e = emitters[kind]
	if e then
		return hostPart, e
	end
	local created = Instance.new("ParticleEmitter")
	created.Name = "Emitter_" .. kind
	created.Enabled = false
	created.Rate = 0
	created.Texture = TEXTURES[kind] or TEXTURES.sparks
	if kind == "smoke" then
		-- a soft dark puff that hangs for a moment (eliminations, doom)
		created.Lifetime = NumberRange.new(0.8, 1.4)
		created.Speed = NumberRange.new(4, 10)
		created.SpreadAngle = Vector2.new(180, 180)
		created.Drag = 2.5
		created.LightEmission = 0.2
		created.Rotation = NumberRange.new(0, 360)
		created.RotSpeed = NumberRange.new(-40, 40)
		created.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
		created.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	else
		created.Lifetime = NumberRange.new(0.4, 0.9)
		created.Speed = NumberRange.new(10, 26)
		created.SpreadAngle = Vector2.new(180, 180)
		created.Drag = 3
		created.LightEmission = 1
		created.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		created.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	end
	created.Parent = hostPart
	emitters[kind] = created
	return hostPart, created
end

function Fx.sparks(pos: Vector3, color: Color3, count: number)
	if Prefs.lite() then
		return
	end
	local host, e = getEmitter("sparks")
	host.CFrame = CFrame.new(pos)
	e.Color = ColorSequence.new(color)
	e:Emit(count)
end

-- Elimination reveal: a hot spark burst plus a dark puff, both from built-in textures.
function Fx.burst(pos: Vector3, color: Color3, count: number)
	if Prefs.lite() then
		return
	end
	local host, spark = getEmitter("sparks")
	local _, smoke = getEmitter("smoke")
	host.CFrame = CFrame.new(pos)
	spark.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3), color)
	spark:Emit(count)
	smoke.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.6))
	smoke:Emit(math.max(4, count // 4))
end

function Fx.emitterCount(): number
	local n = 0
	for _ in emitters do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------
-- Floating world text ("-1", "BLOCKED") from a small pool of BillboardGuis
---------------------------------------------------------------------------
local textPool: { BillboardGui } = {}
local TEXT_POOL = 8
local textNext = 0

function Fx.floatText(pos: Vector3, text: string, color: Color3, size: number?)
	textNext = textNext % TEXT_POOL + 1
	local bb: BillboardGui = textPool[textNext]
	if not bb then
		local host = Instance.new("Part")
		host.Name = "TextHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.Transparency = 1
		host.Size = Vector3.one
		host.Parent = folder
		local gui = Instance.new("BillboardGui")
		gui.Name = "FloatText"
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = host
		gui.MaxDistance = 400
		bb = gui
		local created = Instance.new("TextLabel")
		created.Name = "T"
		created.BackgroundTransparency = 1
		created.Size = UDim2.fromScale(1, 1)
		created.Font = Enum.Font.LuckiestGuy
		created.TextScaled = true
		created.Parent = gui
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromRGB(10, 10, 28)
		st.Parent = created
		gui.Parent = host
		textPool[textNext] = gui
	end
	local anchor = (bb.Parent :: any) :: Part
	local label = bb:FindFirstChild("T") :: TextLabel
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	local s = size or 5
	anchor.CFrame = CFrame.new(pos)
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	stroke.Transparency = 0
	bb.Size = UDim2.fromScale(s * 2.4, s)
	bb.StudsOffset = Vector3.zero
	bb.Enabled = true
	TweenService:Create(bb, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.85), { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.85), { Transparency = 1 }):Play()
end

function Fx.textPoolSize(): number
	return #textPool
end

return Fx
