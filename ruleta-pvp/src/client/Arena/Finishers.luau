--!strict
-- Elimination finishers: how a player leaves the table. Pure presentation, cartoon style
-- (hammers, rockets, slime, UFOs); every one runs about 3.4 s, moves the victim only by
-- CFrame and cleans its props up. The attacker's equipped finisher is the one that plays.
local TweenService = game:GetService("TweenService")

local Fx = require(script.Parent.Fx)
local Avatars = require(script.Parent.Avatars)
local Cam = require(script.Parent.Cam)
local Mood = require(script.Parent.Mood)
local Audio = require(script.Parent.Parent.Audio)

local Finishers = {}
Finishers.played = {} :: { [string]: number }
Finishers.Duration = 3.4

local function prop(shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, life: number?): Part
	local p = Instance.new("Part")
	p.Name = "FinisherProp"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = Fx.folder
	task.delay(life or Finishers.Duration, function()
		p:Destroy()
	end)
	return p
end

local function tween(obj: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?)
	TweenService:Create(obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props):Play()
end

-- Launches the victim into the sky, spinning.
local function launch(model: Model?, base: CFrame, delay: number, height: number?)
	task.delay(delay, function()
		Avatars.drive(model, Finishers.Duration - delay, function(a)
			local k = 1 - (1 - a) ^ 2
			return base * CFrame.new(0, k * (height or 90), -k * 14) * CFrame.Angles(a * 14, a * 9, 0)
		end)
	end)
end

local PLAY: { [string]: (model: Model?, base: CFrame, color: Color3) -> () } = {}

-- Giant cartoon hammer: squash into the podium, then bounce out to the stars.
PLAY.f_hammer = function(model, base, color)
	local pivot = base * CFrame.new(0, 14, 5)
	local head = prop(Enum.PartType.Block, Vector3.new(7, 5, 5), pivot * CFrame.new(0, 2, 0), Color3.fromRGB(255, 84, 96))
	local band = prop(Enum.PartType.Block, Vector3.new(7.3, 1, 5.3), pivot * CFrame.new(0, 2, 0), Color3.fromRGB(255, 205, 60), Enum.Material.Neon)
	local handle = prop(Enum.PartType.Block, Vector3.new(1.2, 10, 1.2), pivot * CFrame.new(0, -4, 0), Color3.fromRGB(160, 110, 70))
	local function pose(angle: number)
		local cf = base * CFrame.new(0, 3, 9) * CFrame.Angles(angle, 0, 0)
		head.CFrame = cf * CFrame.new(0, 11, 0)
		band.CFrame = head.CFrame
		handle.CFrame = cf * CFrame.new(0, 5, 0)
	end
	task.spawn(function()
		-- wind up, then slam
		local t0 = os.clock()
		while os.clock() - t0 < 0.95 do
			local a = (os.clock() - t0) / 0.95
			local angle = if a < 0.6 then math.rad(25) * (a / 0.6) else math.rad(25) - math.rad(115) * ((a - 0.6) / 0.4) ^ 2
			pose(angle)
			task.wait()
		end
		pose(math.rad(-90))
		Audio.play("elim", 0.8, 0.8)
		Cam.shake(0.9)
		Fx.ring(base.Position - Vector3.new(0, 2.8, 0), Color3.fromRGB(255, 205, 60), 2, 14, 0.5)
		Fx.shards(base.Position, color, 16, 30)
		Fx.sparks(base.Position, Color3.fromRGB(255, 230, 120), 30)
	end)
	task.delay(0.95, function()
		Avatars.drive(model, 0.45, function(a)
			return base * CFrame.new(0, -5.5 * math.min(1, a * 4), 0)
		end)
	end)
	launch(model, base * CFrame.new(0, -5.5, 0), 1.45, 110)
end

-- Confetti pop.
PLAY.f_confetti = function(model, base, color)
	Avatars.react(model, base, "shake", 0.6)
	task.delay(0.6, function()
		Audio.play("elim", 0.6, 1.5)
		Fx.confetti(base.Position + Vector3.new(0, 1, 0), 40, 40)
		Fx.pulse(base.Position, color, 1, 9, 0.4)
		Cam.shake(0.5)
	end)
	launch(model, base, 0.6, 140)
end

-- Strapped to a rocket.
PLAY.f_rocket = function(model, base, _color)
	local body = prop(Enum.PartType.Cylinder, Vector3.new(7, 2.4, 2.4), base * CFrame.new(0, -1, 1.8) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(235, 240, 250))
	local nose = prop(Enum.PartType.Ball, Vector3.new(2.6, 2.6, 2.6), base * CFrame.new(0, 2.6, 1.8), Color3.fromRGB(255, 84, 96))
	local flame = prop(Enum.PartType.Ball, Vector3.new(2.2, 3.4, 2.2), base * CFrame.new(0, -5, 1.8), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	Avatars.react(model, base, "tremble", 0.9)
	task.delay(0.9, function()
		Audio.play("whoosh", 0.8, 0.7)
		Cam.shake(0.6)
		Fx.ring(base.Position - Vector3.new(0, 2.8, 0), Color3.fromRGB(255, 170, 40), 1, 12, 0.5)
		local t0 = os.clock()
		Avatars.drive(model, 2.4, function(a)
			local y = a * a * 160
			local cf = base * CFrame.new(math.sin(a * 30) * 0.4, y, 0)
			body.CFrame = cf * CFrame.new(0, -1, 1.8) * CFrame.Angles(0, 0, math.rad(90))
			nose.CFrame = cf * CFrame.new(0, 2.6, 1.8)
			flame.CFrame = cf * CFrame.new(0, -5 - math.random(), 1.8)
			if os.clock() - t0 > 0.05 then
				t0 = os.clock()
				Fx.shards(flame.Position, Color3.fromRGB(255, 200, 80), 2, 8, { life = 0.5, gravity = 20 })
			end
			return cf
		end)
	end)
	task.delay(2.9, function()
		Fx.pulse(nose.Position, Color3.fromRGB(255, 220, 120), 3, 26, 0.5)
		Fx.confetti(nose.Position, 24, 50)
	end)
end

-- A blob of slime drops and swallows the victim.
PLAY.f_slime = function(model, base, _color)
	local green = Color3.fromRGB(130, 245, 90)
	local blob = prop(Enum.PartType.Ball, Vector3.new(5, 5, 5), base * CFrame.new(0, 40, 0), green, Enum.Material.Neon)
	blob.Transparency = 0.15
	tween(blob, 0.7, { CFrame = base * CFrame.new(0, 0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Avatars.react(model, base, "tremble", 0.7)
	task.delay(0.7, function()
		Audio.play("heal", 0.8, 0.6)
		Cam.shake(0.5)
		Fx.shards(base.Position, green, 20, 22, { gravity = 60 })
		tween(blob, 0.35, { Size = Vector3.new(9, 8, 9) }, Enum.EasingStyle.Back)
		tween(blob, 1.2, { Size = Vector3.new(13, 0.6, 13), CFrame = base * CFrame.new(0, -2.8, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.5)
		Avatars.drive(model, 1.7, function(a)
			local k = math.clamp((a - 0.3) / 0.7, 0, 1)
			return base * CFrame.new(0, -8 * k, 0) * CFrame.Angles(0, k * 5, 0)
		end)
	end)
	task.delay(2.5, function()
		Fx.ring(base.Position - Vector3.new(0, 2.7, 0), green, 3, 12, 0.7)
	end)
end

-- Frozen solid, then shattered.
PLAY.f_freeze = function(model, base, _color)
	local ice = prop(Enum.PartType.Block, Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0, 0, 0), Color3.fromRGB(180, 230, 255), Enum.Material.Ice)
	ice.Transparency = 0.35
	tween(ice, 0.6, { Size = Vector3.new(5.5, 8, 5.5) }, Enum.EasingStyle.Back)
	Audio.play("shield", 0.6, 1.6)
	task.delay(1.2, function()
		Avatars.react(model, base, "shake", 0.5)
		for i = 1, 3 do
			tween(ice, 0.08, { CFrame = base * CFrame.new((i % 2 - 0.5) * 0.5, 0, 0) }, nil, nil, i * 0.12)
		end
	end)
	task.delay(1.9, function()
		Audio.play("elim", 0.7, 1.4)
		Cam.shake(0.7)
		ice.Transparency = 1
		Fx.shards(base.Position, Color3.fromRGB(200, 240, 255), 28, 36, { size = 0.8 })
		Fx.pulse(base.Position, Color3.fromRGB(220, 245, 255), 2, 12, 0.35)
		Avatars.drive(model, 1.4, function(a)
			return base * CFrame.new(0, -9 * a * a, 0)
		end)
	end)
end

-- Abducted.
PLAY.f_ufo = function(model, base, _color)
	local top = base * CFrame.new(0, 22, 0)
	local disc = prop(Enum.PartType.Cylinder, Vector3.new(1.6, 14, 14), top * CFrame.new(40, 12, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 160, 190))
	local dome = prop(Enum.PartType.Ball, Vector3.new(7, 5, 7), top * CFrame.new(40, 13.4, 0), Color3.fromRGB(120, 255, 220), Enum.Material.Neon)
	tween(disc, 0.8, { CFrame = top * CFrame.Angles(0, 0, math.rad(90)) })
	tween(dome, 0.8, { CFrame = top * CFrame.new(0, 1.4, 0) })
	task.delay(0.8, function()
		local beam = prop(Enum.PartType.Cylinder, Vector3.new(25, 6, 6), base * CFrame.new(0, 9, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 255, 230), Enum.Material.Neon, 1.9)
		beam.Transparency = 0.6
		Audio.play("whoosh", 0.7, 1.3)
		Avatars.drive(model, 1.6, function(a)
			return base * CFrame.new(0, a * a * 20, 0) * CFrame.Angles(0, a * 12, 0)
		end)
	end)
	task.delay(2.45, function()
		Fx.pulse(top.Position, Color3.fromRGB(150, 255, 230), 2, 10, 0.3)
		tween(disc, 0.7, { CFrame = top * CFrame.new(-60, 60, 80) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(dome, 0.7, { CFrame = top * CFrame.new(-60, 61.4, 80) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Avatars.drive(model, 0.7, function(a)
			return top * CFrame.new(-60 * a * a, 60 * a * a, 80 * a * a)
		end)
	end)
end

-- Swallowed by a tiny black hole.
PLAY.f_blackhole = function(model, base, _color)
	local centre = base * CFrame.new(0, 9, -3)
	local hole = prop(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), centre, Color3.fromRGB(8, 4, 20))
	local halo = prop(Enum.PartType.Cylinder, Vector3.new(0.3, 1, 1), centre * CFrame.Angles(0, 0, math.rad(70)), Color3.fromRGB(190, 120, 255), Enum.Material.Neon)
	tween(hole, 0.7, { Size = Vector3.new(6, 6, 6) }, Enum.EasingStyle.Back)
	tween(halo, 0.7, { Size = Vector3.new(0.3, 12, 12) }, Enum.EasingStyle.Back)
	Audio.play("whoosh", 0.7, 0.5)
	task.delay(0.7, function()
		Mood.flash(Color3.fromRGB(120, 60, 200), 0.25, 0.5)
		Avatars.drive(model, 1.9, function(a)
			local r = 7 * (1 - a) ^ 1.5
			local ang = a * 16
			local p = centre.Position + Vector3.new(math.cos(ang) * r, (1 - a) * -9 * (1 - a), math.sin(ang) * r)
			halo.CFrame = centre * CFrame.Angles(a * 8, 0, math.rad(70))
			return CFrame.new(p) * CFrame.Angles(a * 20, a * 15, 0)
		end)
	end)
	task.delay(2.6, function()
		Audio.play("elim", 0.7, 0.6)
		Cam.shake(0.6)
		tween(hole, 0.25, { Size = Vector3.new(0.2, 0.2, 0.2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(halo, 0.25, { Size = Vector3.new(0.3, 0.2, 0.2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Fx.ring(centre.Position, Color3.fromRGB(190, 120, 255), 1, 18, 0.5)
		Avatars.drive(model, 0.6, function()
			return base * CFrame.new(0, -60, 0)
		end)
	end)
end

-- Three strikes from the sky.
PLAY.f_lightning = function(model, base, _color)
	local yellow = Color3.fromRGB(255, 240, 140)
	Avatars.react(model, base, "tremble", 0.8)
	for i = 0, 2 do
		task.delay(0.35 + i * 0.4, function()
			local from = base.Position + Vector3.new(math.random(-12, 12), 70, math.random(-12, 12))
			Fx.bolt(from, base.Position, yellow, 1 + i * 0.4)
			Mood.flash(Color3.new(1, 1, 1), 0.35 + i * 0.15, 0.25)
			Audio.play("zap", 0.6 + i * 0.15, 1.3 - i * 0.2)
			Cam.shake(0.4 + i * 0.25)
			Fx.sparks(base.Position, yellow, 20)
		end)
	end
	task.delay(1.3, function()
		Fx.shards(base.Position, yellow, 20, 40)
		Fx.ring(base.Position - Vector3.new(0, 2.8, 0), yellow, 2, 16, 0.5)
		Avatars.drive(model, 2.1, function(a)
			local k = 1 - (1 - a) ^ 2
			return base * CFrame.new(0, k * 30 - a * a * 50, k * 120) * CFrame.Angles(a * 18, 0, a * 10)
		end)
	end)
end

Finishers.ids = { "f_hammer", "f_confetti", "f_rocket", "f_slime", "f_freeze", "f_ufo", "f_blackhole", "f_lightning" }

function Finishers.play(id: string, model: Model?, base: CFrame, color: Color3)
	local fn = PLAY[id] or PLAY.f_hammer
	Finishers.played[id] = (Finishers.played[id] or 0) + 1
	local ok, err = pcall(function()
		fn(model, base, color)
	end)
	if not ok then
		warn("[Finishers]", id, err)
	end
end

return Finishers
