--!nonstrict
-- Renders everything the server reports through the Fx remote: projectiles, beams, hits
-- (sparks, damage numbers, hit-stop, shake), shockwaves, boss telegraphs, enemy deaths.
-- All parts are pooled; one RenderStepped loop moves every projectile.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Net)
local Fx = require(script.Parent.Fx)

local CombatFx = {}

local player = Players.LocalPlayer
local myId = player.UserId
local WHITE = Color3.new(1, 1, 1)

-- kind -> listeners (CharFx, NpcRender, Hud hook in here)
local listeners: { [string]: { (any) -> () } } = {}
function CombatFx.on(kind: string, fn: (any) -> ())
	listeners[kind] = listeners[kind] or {}
	table.insert(listeners[kind], fn)
end

local function camDist(pos: Vector3): number
	local cam = workspace.CurrentCamera
	return if cam then (cam.CFrame.Position - pos).Magnitude else 0
end
local function visible(pos: Vector3): boolean
	return camDist(pos) < (if Fx.lite then 240 else 420)
end

---------------------------------------------------------------------------
-- Damage numbers (pooled BillboardGuis)
---------------------------------------------------------------------------
local numberPool: { BillboardGui } = {}
local numbersAlive = 0
local function damageNumber(pos: Vector3, text: string, color: Color3, big: boolean)
	if numbersAlive > 28 then
		return
	end
	local bb = table.remove(numberPool)
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "Dmg"
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.ResetOnSpawn = false
		local t = Instance.new("TextLabel")
		t.Name = "T"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.Bangers
		t.TextScaled = true
		local s = Instance.new("UIStroke")
		s.Thickness = 2.5
		s.Color = Color3.fromRGB(20, 12, 30)
		s.Parent = t
		local sc = Instance.new("UIScale")
		sc.Parent = t
		t.Parent = bb
	end
	numbersAlive += 1
	local t = bb.T
	local sc = t.UIScale
	bb.Size = if big then UDim2.fromOffset(190, 64) else UDim2.fromOffset(130, 44)
	local offset = Vector3.new((math.random() - 0.5) * 4, 2.5 + math.random() * 1.5, (math.random() - 0.5) * 4)
	bb.StudsOffsetWorldSpace = pos + offset
	t.Text = text
	t.TextColor3 = color
	t.TextTransparency = 0
	t.UIStroke.Transparency = 0
	t.Rotation = (math.random() - 0.5) * 16
	sc.Scale = 0.3
	bb.Parent = player:FindFirstChildOfClass("PlayerGui")
	TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = if big then 1.25 else 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = pos + offset + Vector3.new(0, 4.5, 0) }):Play()
	task.delay(0.45, function()
		TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(t.UIStroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end)
	task.delay(0.72, function()
		bb.Parent = nil
		numbersAlive -= 1
		table.insert(numberPool, bb)
	end)
end
CombatFx.damageNumber = damageNumber

---------------------------------------------------------------------------
-- Projectiles
---------------------------------------------------------------------------
type Shot = { id: number, pos: Vector3, dir: Vector3, speed: number, left: number, core: BasePart, glow: BasePart, tail: BasePart, radius: number, color: Color3, hidden: boolean }
local shots: { [number]: Shot } = {}
local shotCount = 0

local function shotColor(d): (Color3, Color3)
	if d.c == "sun" then
		return Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 250, 200)
	elseif type(d.c) == "table" then
		return Color3.fromRGB(d.c[1], d.c[2], d.c[3]), WHITE
	end
	local c1, c2 = Fx.formColors(d.f)
	return c1, c2
end

local function addShot(d)
	if shotCount > 60 then
		return
	end
	local c1, c2 = shotColor(d)
	local r = d.z
	local hidden = not visible(d.o)
	local s: Shot = {
		id = d.i,
		pos = d.o,
		dir = d.d,
		speed = d.s,
		left = d.r,
		radius = r,
		color = c1,
		hidden = hidden,
		core = Fx.get("ball"),
		glow = Fx.get("ball"),
		tail = Fx.get("blob"),
	}
	s.core.Size = Vector3.one * r * 0.9
	s.core.Color = c2
	s.glow.Size = Vector3.one * r * 1.7
	s.glow.Color = c1
	s.glow.Transparency = 0.45
	s.tail.Size = Vector3.new(r * 1.1, r * 1.1, r * 5)
	s.tail.Color = c1
	s.tail.Transparency = 0.35
	shots[d.i] = s
	shotCount += 1
	if not hidden then
		-- muzzle flash
		Fx.burst(d.o, r * 0.4, r * 1.6, c2, 0.14, 0.2)
		if d.u == myId then
			Fx.sound("blast", 0.25, 1.5 + math.random() * 0.3)
		end
	end
end

local function removeShot(s: Shot)
	shots[s.id] = nil
	shotCount -= 1
	Fx.release(s.core)
	Fx.release(s.glow)
	Fx.release(s.tail)
end

local function endShot(d)
	local s = shots[d.i]
	local color = if s then s.color else Color3.fromRGB(110, 210, 255)
	local r = if s then s.radius else 4
	if s then
		removeShot(s)
	end
	if not visible(d.p) then
		return
	end
	if d.a and d.a > 0 then
		-- area explosion
		Fx.burst(d.p, 3, d.a, color, 0.45, 0.2)
		Fx.burst(d.p, 2, d.a * 0.6, WHITE, 0.3, 0.1)
		Fx.ring(Vector3.new(d.p.X, math.max(d.p.Y - 2, Config.GroundY + 0.4), d.p.Z), 2, d.a * 1.2, color, 0.5, 0.6)
		Fx.sparks(d.p, color, 14, 60, 0.9)
		Fx.shake(math.clamp(1.4 - camDist(d.p) / 120, 0, 1.4))
		Fx.sound("boom", 0.5, 0.8)
	else
		Fx.burst(d.p, r * 0.5, r * 1.8, color, 0.22, 0.2)
		Fx.burst(d.p, r * 0.3, r * 1.0, WHITE, 0.14, 0.1)
		if d.h then
			Fx.sparks(d.p, color, 6, 26, 0.45)
		end
	end
end

---------------------------------------------------------------------------
-- Beam
---------------------------------------------------------------------------
local function beam(d)
	if not visible(d.o) and not visible(d.o + d.d * d.l) then
		return
	end
	local c1, c2 = Fx.formColors(d.f)
	local len = d.l
	local r = d.z
	local mid = d.o + d.d * (len / 2)
	local axis = CFrame.lookAt(mid, mid + d.d) * CFrame.Angles(0, math.rad(90), 0)
	local hold = 0.28 + 0.25 * d.c
	-- outer glow, body, white core
	local outer = Fx.get("cyl")
	outer.Color = c1
	outer.Transparency = 0.55
	outer.Size = Vector3.new(len, r * 0.6, r * 0.6)
	outer.CFrame = axis
	local body = Fx.get("cyl")
	body.Color = c1
	body.Transparency = 0.15
	body.Size = Vector3.new(len, r * 0.3, r * 0.3)
	body.CFrame = axis
	local core = Fx.get("cyl")
	core.Color = c2:Lerp(WHITE, 0.5)
	core.Size = Vector3.new(len, r * 0.15, r * 0.15)
	core.CFrame = axis
	Fx.tween(outer, 0.09, { Size = Vector3.new(len, r * 1.7, r * 1.7) })
	Fx.tween(body, 0.09, { Size = Vector3.new(len, r * 1.1, r * 1.1) })
	Fx.tween(core, 0.09, { Size = Vector3.new(len, r * 0.55, r * 0.55) })
	-- head (at the hands) and tip
	local head = Fx.get("ball")
	head.Color = c1:Lerp(c2, 0.5)
	head.Transparency = 0.15
	head.Size = Vector3.one * r * 1.0
	head.CFrame = CFrame.new(d.o)
	Fx.tween(head, 0.1, { Size = Vector3.one * r * 1.6 })
	local tip = Fx.get("ball")
	tip.Color = c1
	tip.Transparency = 0.3
	tip.Size = Vector3.one * r * 2
	tip.CFrame = CFrame.new(d.o + d.d * len)
	Fx.tween(tip, 0.12, { Size = Vector3.one * r * 2.6 })
	-- rings racing down the beam
	for i = 1, (if Fx.lite then 2 else 4) do
		task.delay(i * 0.05, function()
			local from = d.o + d.d * 4
			local ring = Fx.get("cyl")
			ring.Color = c2
			ring.Transparency = 0.3
			ring.Size = Vector3.new(0.5, r * 2.2, r * 2.2)
			ring.CFrame = CFrame.lookAt(from, from + d.d) * CFrame.Angles(0, math.rad(90), 0)
			local to = d.o + d.d * math.min(len, 90)
			Fx.tween(ring, 0.3, { CFrame = CFrame.lookAt(to, to + d.d) * CFrame.Angles(0, math.rad(90), 0), Size = Vector3.new(0.3, r * 3.4, r * 3.4), Transparency = 1 }, Enum.EasingStyle.Linear)
			task.delay(0.3, Fx.release, ring)
		end)
	end
	task.delay(hold, function()
		local t = 0.18
		Fx.tween(outer, t, { Size = Vector3.new(len, 0.05, 0.05), Transparency = 1 })
		Fx.tween(body, t, { Size = Vector3.new(len, 0.05, 0.05), Transparency = 1 })
		Fx.tween(core, t, { Size = Vector3.new(len, 0.05, 0.05) })
		Fx.tween(head, t, { Size = Vector3.one * 0.2, Transparency = 1 })
		Fx.tween(tip, t, { Size = Vector3.one * 0.2, Transparency = 1 })
		task.wait(t)
		Fx.release(outer)
		Fx.release(body)
		Fx.release(core)
		Fx.release(head)
		Fx.release(tip)
	end)
	local near = math.clamp(1.3 - camDist(d.o) / 150, 0, 1.3)
	Fx.shake(near * (0.5 + d.c))
	if d.u == myId then
		Fx.kick(6 + 8 * d.c)
		Fx.sound("boom", 0.45, 1.3)
	end
end

---------------------------------------------------------------------------
-- Hits
---------------------------------------------------------------------------
local function hit(d)
	local mine = d.a == myId
	local onMe = d.u == myId
	local pos: Vector3 = d.p
	if not mine and not onMe and not visible(pos) then
		return
	end
	local color = if onMe then Color3.fromRGB(255, 80, 80) elseif d.c then Color3.fromRGB(255, 226, 70) else WHITE
	if d.b then
		-- blocked: blue shield flash
		Fx.burst(pos, 2.4, 4.2, Color3.fromRGB(120, 200, 255), 0.2, 0.45)
	elseif d.k == "melee" or d.k == "npc" then
		-- impact star: two crossed stretched blobs + sparks
		local cf = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.random() * 6.28, math.random() * 6.28)
		Fx.flash("blob", cf, Vector3.new(1, 1, 6), WHITE, 0.14, { Size = Vector3.new(0.2, 0.2, 13), Transparency = 1 })
		Fx.flash("blob", cf * CFrame.Angles(0, math.rad(90), 0), Vector3.new(1, 1, 6), color, 0.14, { Size = Vector3.new(0.2, 0.2, 13), Transparency = 1 })
		Fx.burst(pos, 1, 3.4, color, 0.16, 0.35)
		Fx.sparks(pos, if d.c then Color3.fromRGB(255, 226, 70) else Color3.fromRGB(255, 240, 200), if d.f then 10 else 5, 28, 0.4)
		if d.f then
			Fx.ring(Vector3.new(pos.X, math.max(pos.Y - 2.5, Config.GroundY + 0.4), pos.Z), 2, 16, WHITE, 0.35, 0.5)
			Fx.burst(pos, 2, 9, WHITE, 0.25, 0.4)
		end
	else
		Fx.sparks(pos, color, 5, 24, 0.4)
	end
	if mine then
		Fx.hitStop(if d.f then 0.11 elseif d.c then 0.07 else 0.045)
		Fx.shake(if d.f then 0.9 elseif d.k == "melee" then 0.35 else 0.15)
		if d.k == "melee" then
			Fx.sound("punch", if d.f then 0.55 else 0.3, if d.f then 0.9 else 1.6 + math.random() * 0.4)
		end
	elseif onMe then
		Fx.shake(0.8)
		Fx.sound("punch", 0.4, 0.7)
	end
	if (mine or onMe) and d.d > 0 then
		local text = Format.abbrev(math.max(1, d.d))
		if d.c then
			text ..= "!"
		end
		if onMe then
			text = "-" .. text
		end
		damageNumber(pos, text, color, d.c or d.f or false)
	end
end

---------------------------------------------------------------------------
-- Shockwaves, telegraphs, deaths
---------------------------------------------------------------------------
local function shock(d)
	if not visible(d.p) then
		return
	end
	local c1 = if d.n then Color3.fromRGB(255, 90, 60) else Fx.formColors(d.f)
	local ground = Vector3.new(d.p.X, Config.GroundY + 0.5, d.p.Z)
	Fx.ring(ground, 2, d.r * 1.15, c1, 0.5, 1)
	Fx.ring(ground, 1, d.r * 0.8, WHITE, 0.35, 0.6)
	Fx.burst(d.p, 3, d.r * 0.7, c1, 0.4, 0.35)
	-- debris (particles / fading specks) plus speed lines along the ground
	local n = if Fx.lite then 6 else 12
	Fx.debris(ground, d.r, c1:Lerp(Color3.fromRGB(230, 220, 200), 0.5), n)
	for i = 1, n do
		local a = i / n * math.pi * 2 + math.random() * 0.4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = ground + dir * d.r * 0.2 + Vector3.new(0, 0.4, 0)
		Fx.flash("block", CFrame.lookAt(from, from + dir), Vector3.new(0.35, 0.2, d.r * 0.3), WHITE, 0.25, { CFrame = CFrame.lookAt(from + dir * d.r * 0.8, from + dir * d.r), Size = Vector3.new(0.1, 0.1, d.r * 0.5), Transparency = 1 }, 0.2)
	end
	Fx.shake(math.clamp(1.6 - camDist(d.p) / 110, 0, 1.6))
	Fx.sound("boom", 0.6, 0.7)
end

local function telegraph(d)
	if not visible(d.p) then
		return
	end
	local red = Color3.fromRGB(255, 60, 60)
	if d.k == "ring" then
		local cf = CFrame.new(d.p) * CFrame.Angles(0, 0, math.rad(90))
		Fx.flash("cyl", cf, Vector3.new(0.25, d.r * 2, d.r * 2), red, d.t, { Transparency = 0.55 }, 0.85)
		Fx.flash("cyl", cf + Vector3.new(0, 0.08, 0), Vector3.new(0.3, 1, 1), Color3.fromRGB(255, 160, 80), d.t, { Size = Vector3.new(0.3, d.r * 2, d.r * 2) }, 0.45)
	else
		local mid = d.p + d.d * (d.l / 2)
		local cf = CFrame.lookAt(mid, mid + d.d)
		Fx.flash("block", cf, Vector3.new(d.w * 2, 0.25, d.l), red, d.t, { Transparency = 0.55 }, 0.85)
		local start = d.p + d.d * 0.5
		Fx.flash("block", CFrame.lookAt(start, start + d.d), Vector3.new(d.w * 2, 0.3, 1), Color3.fromRGB(255, 160, 80), d.t, { Size = Vector3.new(d.w * 2, 0.3, d.l), CFrame = cf + Vector3.new(0, 0.08, 0) }, 0.45)
	end
end

local function npcDeath(d)
	if not visible(d.p) then
		return
	end
	local def = Config.Npcs[d.k]
	local c = if def then Color3.fromRGB(def.accent[1], def.accent[2], def.accent[3]) else WHITE
	local scale = if def then def.scale else 1
	Fx.burst(d.p, 2 * scale, 7 * scale, c, 0.35, 0.3)
	Fx.burst(d.p, 1 * scale, 4 * scale, WHITE, 0.2, 0.2)
	Fx.sparks(d.p, c, if d.b then 22 else 9, 34 * scale, 0.5 * scale)
	if d.b then
		Fx.ring(Vector3.new(d.p.X, Config.GroundY + 0.5, d.p.Z), 3, 50, c, 0.8, 1.2)
		Fx.shake(1.4)
		Fx.sound("boom", 0.7, 0.6)
	end
end

local function dodge(d)
	if visible(d.p) then
		Fx.burst(d.p, 1.5, 3, Color3.fromRGB(200, 240, 255), 0.18, 0.6)
	end
end

function CombatFx.shotCount(): number
	return shotCount
end

function CombatFx.init()
	local handlers = { shot = addShot, shotEnd = endShot, beam = beam, hit = hit, shock = shock, telegraph = telegraph, npcDeath = npcDeath, dodge = dodge }
	Net.event("Fx").OnClientEvent:Connect(function(kind, d)
		local h = handlers[kind]
		if h then
			h(d)
		end
		local ls = listeners[kind]
		if ls then
			for _, fn in ls do
				task.spawn(fn, d)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if Fx.frozen() then
			return
		end
		for _, s in shots do
			if s.left > 0 then
				local step = math.min(s.speed * dt, s.left)
				s.pos += s.dir * step
				s.left -= step
				if s.left <= 0 then
					-- the server's shotEnd normally arrives first; this is the fallback
					task.delay(0.3, function()
						if shots[s.id] == s then
							removeShot(s)
						end
					end)
				end
			end
			local cf = CFrame.lookAt(s.pos, s.pos + s.dir)
			s.core.CFrame = cf
			s.glow.CFrame = cf
			s.tail.CFrame = cf * CFrame.new(0, 0, s.radius * 2.2)
		end
	end)
end

return CombatFx
