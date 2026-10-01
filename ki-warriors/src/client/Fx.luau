--!nonstrict
-- Client effect toolkit: part pool, quality profile (lite for phones), camera shake / FOV
-- kicks, hit-stop clock and the colours of each form. Everything visual runs on the client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

local Fx = {}

local player = Players.LocalPlayer

-- Lite profile: phones/tablets by default, or the player's setting. Fewer particles, no
-- dynamic lights, shorter draw distances for effects.
local touchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Fx.lite = touchDevice or workspace:GetAttribute("ForceLite") == true
function Fx.refreshQuality()
	local setting = Net.setting("lite")
	Fx.lite = touchDevice or setting == true or workspace:GetAttribute("ForceLite") == true
end
Net.Changed:Connect(function(kind)
	if kind == "full" then
		Fx.refreshQuality()
	end
end)

Fx.folder = Instance.new("Folder")
Fx.folder.Name = "KiwFx"
Fx.folder.Parent = workspace

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------
local BASE = Color3.fromRGB(110, 210, 255) -- untransformed ki
local BASE2 = Color3.fromRGB(235, 250, 255)
function Fx.formColors(form: number?): (Color3, Color3, string)
	local f = Config.Forms[form or 0]
	if f then
		return Color3.fromRGB(f.color[1], f.color[2], f.color[3]), Color3.fromRGB(f.color2[1], f.color2[2], f.color2[3]), f.style
	end
	return BASE, BASE2, "flame"
end

function Fx.auraColor(auraId: string?): Color3?
	local a = auraId and Config.AuraById[auraId]
	if a then
		return Color3.fromRGB(a.color[1], a.color[2], a.color[3])
	end
	return nil
end

---------------------------------------------------------------------------
-- Pool
---------------------------------------------------------------------------
local pools: { [string]: { BasePart } } = {}
Fx.alive = 0 -- pooled parts currently in use (budget check)
Fx.created = 0

local function make(kind: string): BasePart
	local p: BasePart
	if kind == "ball" then
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Ball
		p = b
	elseif kind == "cyl" then
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Cylinder
		p = b
	elseif kind == "blob" then
		p = Instance.new("Part")
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	else
		p = Instance.new("Part")
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = "fx_" .. kind
	Fx.created += 1
	return p
end

-- kinds: "ball" | "cyl" | "block" | "blob"
function Fx.get(kind: string): BasePart
	local pool = pools[kind]
	local p = pool and table.remove(pool)
	if not p then
		p = make(kind)
	end
	p.Transparency = 0
	p.Material = Enum.Material.Neon
	p.Parent = Fx.folder
	Fx.alive += 1
	return p
end

-- Tweens still running on pooled parts: cancelled on release, so a finished effect can never
-- keep resizing / moving a part that was already handed to another effect.
local running: { [Instance]: { Tween } } = setmetatable({}, { __mode = "k" }) :: any

function Fx.release(p: BasePart)
	if not p or p.Parent == nil then
		return
	end
	local list = running[p]
	if list then
		running[p] = nil
		for _, t in list do
			t:Cancel()
		end
	end
	p.Parent = nil
	local kind = p.Name:sub(4)
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	Fx.alive -= 1
	if #pool < 80 then
		table.insert(pool, p)
	else
		p:Destroy()
	end
end

function Fx.tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	if obj.Parent == Fx.folder then
		local list = running[obj]
		if not list then
			list = {}
			running[obj] = list
		end
		table.insert(list, t)
		t.Completed:Once(function()
			local l = running[obj]
			if l then
				local i = table.find(l, t)
				if i then
					table.remove(l, i)
				end
			end
		end)
	end
	t:Play()
	return t
end

-- Pooled part that animates to `props` and returns to the pool.
function Fx.flash(kind: string, cf: CFrame, size: Vector3, color: Color3, time: number, props: { [string]: any }, trans: number?): BasePart
	local p = Fx.get(kind)
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = trans or 0
	Fx.tween(p, time, props)
	task.delay(time, Fx.release, p)
	return p
end

-- Expanding ring on the ground (flat cylinder).
function Fx.ring(pos: Vector3, fromR: number, toR: number, color: Color3, time: number, thickness: number?)
	local h = thickness or 0.4
	Fx.flash("cyl", CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(h, fromR * 2, fromR * 2), color, time, { Size = Vector3.new(h * 0.5, toR * 2, toR * 2), Transparency = 1 }, 0.25)
end

-- Expanding sphere shell.
function Fx.burst(pos: Vector3, fromR: number, toR: number, color: Color3, time: number, trans: number?)
	Fx.flash("ball", CFrame.new(pos), Vector3.one * fromR * 2, color, time, { Size = Vector3.one * toR * 2, Transparency = 1 }, trans or 0.3)
end

-- Expanding see-through shell (ForceField material: bright rim, clear centre). Used for bursts
-- that start around a character, where a Neon ball would hide the character completely.
function Fx.shell(pos: Vector3, fromR: number, toR: number, color: Color3, time: number, trans: number?)
	local p = Fx.flash("ball", CFrame.new(pos), Vector3.one * fromR * 2, color, time, { Size = Vector3.one * toR * 2, Transparency = 1 }, trans or 0.2)
	p.Material = Enum.Material.ForceField
end

-- Shards flying out of a point (geometry sparks: visible at any graphics quality).
function Fx.sparks(pos: Vector3, color: Color3, count: number, speed: number, size: number?)
	local n = if Fx.lite then math.ceil(count / 2) else count
	local s = size or 0.5
	for _ = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		if dir.Magnitude < 0.05 then
			dir = Vector3.yAxis
		end
		dir = dir.Unit
		local len = s * (2 + math.random() * 3)
		local from = pos + dir * 0.6
		local to = pos + dir * speed * (0.18 + math.random() * 0.2)
		Fx.flash("block", CFrame.lookAt(from, to), Vector3.new(s * 0.45, s * 0.45, len), color, 0.22 + math.random() * 0.12, { CFrame = CFrame.lookAt(to, to + dir), Size = Vector3.new(0.05, 0.05, len * 0.3), Transparency = 1 })
	end
end

-- One-shot particle burst at a point (no parts kept alive: an Attachment on Terrain with
-- a ParticleEmitter that emits once and is destroyed after its longest lifetime).
-- Uses the emitter's built-in default texture, no uploaded assets.
function Fx.particles(pos: Vector3, color: Color3, count: number, speed: number, size: number?, life: number?)
	local lifetime = life or 0.45
	local att = Instance.new("Attachment")
	att.Position = pos -- Terrain sits at the origin, so this is the world position
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.Drag = 4
	e.Acceleration = Vector3.new(0, -12, 0)
	local sz = size or 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = att
	att.Parent = workspace.Terrain
	e:Emit(count)
	task.delay(lifetime + 0.1, function()
		att:Destroy()
	end)
end

-- Ground debris for impacts. It used to be grey Slate cubes flying up, which read as "dark
-- cubes floating" around fights. Now: a particle puff in the ground colour (full quality) or
-- a few small bright specks that shrink and fade out completely (lite / quality 1).
function Fx.debris(ground: Vector3, radius: number, color: Color3, count: number)
	if not Fx.lite then
		Fx.particles(ground + Vector3.new(0, 0.6, 0), color, count * 2, 10 + radius * 0.6, 0.9, 0.5)
		return
	end
	local speck = color:Lerp(Color3.new(1, 1, 1), 0.5)
	for i = 1, math.ceil(count / 2) do
		local a = i / count * math.pi * 4 + math.random() * 0.4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = ground + dir * radius * 0.3 + Vector3.new(0, 0.3, 0)
		local to = ground + dir * radius * (0.6 + math.random() * 0.3) + Vector3.new(0, 1.5 + math.random() * 2, 0)
		Fx.flash("block", CFrame.new(from), Vector3.new(0.35, 0.35, 0.35), speck, 0.35, { CFrame = CFrame.new(to), Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }, 0.1)
	end
end

---------------------------------------------------------------------------
-- Camera: shake + FOV kick (one RenderStepped for both)
---------------------------------------------------------------------------
local shake = 0
local fovKick = 0
local baseFov = 70
function Fx.shake(amount: number)
	if Net.setting("shake") == false then
		return
	end
	shake = math.min(1.6, math.max(shake, amount))
end
function Fx.kick(amount: number)
	if Net.setting("shake") == false then
		return
	end
	fovKick = math.max(fovKick, amount)
end
-- "Reduced motion": the player turned camera shake off. Camera moves, big flashes and zooms
-- are skipped or softened wherever this is checked.
function Fx.reduced(): boolean
	return Net.setting("shake") == false
end
-- Smooth FOV dolly (negative = zoom in) that eases in over `inTime` and back out over `outTime`.
local zoomNow, zoomGoal, zoomHoldUntil = 0, 0, 0
function Fx.zoom(delta: number, hold: number)
	if Fx.reduced() then
		return
	end
	zoomGoal = delta
	zoomHoldUntil = os.clock() + hold
end
Fx.fovBoost = 0 -- sustained (flight boost), set by Flight
Fx.firstForm = false -- set by the HUD while the player has never transformed (bigger show)

-- Hit-stop: a very short freeze of local animation (poses / enemy models / shots) that sells
-- the impact. Other modules read Fx.frozen().
local frozenUntil = 0
function Fx.hitStop(seconds: number)
	frozenUntil = math.max(frozenUntil, os.clock() + seconds)
end
function Fx.frozen(): boolean
	return os.clock() < frozenUntil
end

RunService:BindToRenderStep("KiwCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		if shake > 0.01 then
			local s = shake * 0.7
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, (math.random() - 0.5) * s * 0.5)
			shake = math.max(0, shake - dt * 3.2)
		elseif hum.CameraOffset.Magnitude > 0 then
			hum.CameraOffset = Vector3.zero
			shake = 0
		end
	end
	fovKick = math.max(0, fovKick - dt * 40)
	if zoomGoal ~= 0 and os.clock() > zoomHoldUntil then
		zoomGoal = 0
	end
	zoomNow += (zoomGoal - zoomNow) * math.min(1, dt * (if zoomGoal ~= 0 then 6 else 12))
	if math.abs(zoomNow) < 0.01 and zoomGoal == 0 then
		zoomNow = 0
	end
	local want = baseFov + fovKick + Fx.fovBoost + zoomNow
	if cam.CameraType ~= Enum.CameraType.Scriptable and math.abs(cam.FieldOfView - want) > 0.05 then
		cam.FieldOfView += (want - cam.FieldOfView) * math.min(1, dt * 10)
	end
end)

---------------------------------------------------------------------------
-- Sounds (built-in rbxasset sounds only)
---------------------------------------------------------------------------
local SoundService = game:GetService("SoundService")
local SOUND_IDS = {
	punch = "rbxasset://sounds/impact_explosion_03.mp3",
	swing = "rbxasset://sounds/action_jump.mp3",
	blast = "rbxasset://sounds/action_get_up.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	click = "rbxasset://sounds/volume_slider.ogg",
	land = "rbxasset://sounds/action_jump_land.mp3",
	splash = "rbxasset://sounds/impact_water.mp3",
}
local sounds: { [string]: Sound } = {}
function Fx.sound(name: string, volume: number?, pitch: number?)
	if Net.setting("sfx") == false then
		return
	end
	local id = SOUND_IDS[name]
	if not id then
		return
	end
	local snd = sounds[name]
	if not snd then
		snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Parent = SoundService
		sounds[name] = snd
	end
	snd.Volume = volume or 0.4
	snd.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(snd)
end

return Fx
