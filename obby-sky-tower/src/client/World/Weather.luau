--!strict
-- Ambient particles around the camera, one look per world: pollen over the meadow, sugar
-- sparkles, snow, blowing sand, rising embers, bubbles, toxic spores, glitter above the clouds,
-- stardust in space, rainbow sparkles at the summit. One emitter in a box that follows the
-- camera; the settings are swapped when the world changes (Atmos.worldChanged).
-- Textures are the ones that ship with Roblox (rbxasset://), no uploads.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Quality = require(game:GetService("ReplicatedStorage").Shared.Quality)
local Atmos = require(script.Parent.Atmos)

local Weather = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

export type Look = {
	texture: string,
	colors: { Color3 },
	size: { number }, -- start, end
	rate: number,
	life: number,
	speed: number,
	drift: Vector3, -- acceleration: gravity for snow, lift for embers and bubbles, wind for sand
	up: boolean, -- emit upwards (embers, bubbles) instead of downwards
	emission: number, -- LightEmission
	transparency: number,
	spin: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- One look per world, in tower order. Rates are low on purpose: at most ~80 particles alive.
Weather.Looks = {
	{ texture = SMOKE, colors = { rgb(255, 250, 200), rgb(230, 255, 190) }, size = { 0.18, 0.1 }, rate = 9, life = 7, speed = 1.2, drift = Vector3.new(0.6, 0.15, 0.3), up = false, emission = 0.4, transparency = 0.35, spin = 20 }, -- pollen
	{ texture = SPARKLES, colors = { rgb(255, 190, 230), rgb(190, 235, 255) }, size = { 0.5, 0.1 }, rate = 10, life = 5, speed = 1.5, drift = Vector3.new(0, -0.6, 0), up = false, emission = 0.7, transparency = 0.2, spin = 60 }, -- sugar sparkles
	{ texture = SMOKE, colors = { rgb(255, 255, 255), rgb(235, 245, 255) }, size = { 0.28, 0.22 }, rate = 16, life = 6, speed = 5, drift = Vector3.new(0.8, -1.2, 0.4), up = false, emission = 0.2, transparency = 0.1, spin = 40 }, -- snow
	{ texture = SMOKE, colors = { rgb(245, 215, 160), rgb(230, 190, 130) }, size = { 0.5, 1.6 }, rate = 8, life = 5, speed = 3, drift = Vector3.new(5, 0.2, 1.5), up = false, emission = 0.1, transparency = 0.72, spin = 30 }, -- blowing sand
	{ texture = FIRE, colors = { rgb(255, 210, 90), rgb(255, 80, 20) }, size = { 0.32, 0.05 }, rate = 14, life = 4.5, speed = 4, drift = Vector3.new(0.4, 2.2, 0), up = true, emission = 1, transparency = 0.05, spin = 90 }, -- embers
	{ texture = SPARKLES, colors = { rgb(225, 250, 255), rgb(170, 235, 245) }, size = { 0.25, 0.6 }, rate = 11, life = 6, speed = 3, drift = Vector3.new(0, 1.4, 0), up = true, emission = 0.5, transparency = 0.35, spin = 10 }, -- bubbles
	{ texture = SMOKE, colors = { rgb(190, 255, 90), rgb(120, 190, 50) }, size = { 0.22, 0.5 }, rate = 10, life = 6, speed = 1.5, drift = Vector3.new(0.5, 0.5, 0.2), up = true, emission = 0.6, transparency = 0.4, spin = 30 }, -- spores
	{ texture = SPARKLES, colors = { rgb(255, 250, 225), rgb(255, 225, 140) }, size = { 0.4, 0.08 }, rate = 9, life = 5, speed = 1, drift = Vector3.new(0.3, -0.3, 0.2), up = false, emission = 0.8, transparency = 0.2, spin = 50 }, -- glitter
	{ texture = SPARKLES, colors = { rgb(120, 255, 240), rgb(255, 110, 230) }, size = { 0.35, 0.05 }, rate = 12, life = 5, speed = 0.6, drift = Vector3.new(0, 0, 0), up = false, emission = 1, transparency = 0.1, spin = 80 }, -- stardust
	{ texture = SPARKLES, colors = { rgb(255, 225, 120), rgb(255, 140, 210) }, size = { 0.55, 0.1 }, rate = 12, life = 5, speed = 1.5, drift = Vector3.new(0.2, -0.5, 0.2), up = false, emission = 0.9, transparency = 0.15, spin = 70 }, -- rainbow sparkles
} :: { Look }

local emitter: ParticleEmitter? = nil
local on = true
local rateScale = 1
local current: Look? = nil

local function apply(e: ParticleEmitter, look: Look)
	e.Texture = look.texture
	e.Color = ColorSequence.new(look.colors[1], look.colors[2] or look.colors[1])
	e.Size = NumberSequence.new(look.size[1], look.size[2])
	current = look
	e.Rate = look.rate * rateScale
	e.Lifetime = NumberRange.new(look.life * 0.7, look.life)
	e.Speed = NumberRange.new(look.speed * 0.5, look.speed)
	e.Acceleration = look.drift
	e.EmissionDirection = if look.up then Enum.NormalId.Top else Enum.NormalId.Bottom
	e.LightEmission = look.emission
	e.RotSpeed = NumberRange.new(-look.spin, look.spin)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, look.transparency),
		NumberSequenceKeypoint.new(0.8, look.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
end

function Weather.setEffects(enabled: boolean)
	on = enabled
	if emitter then
		emitter.Enabled = enabled
	end
end

-- Lite profile: half of the ambient particles.
function Weather.setLite(lite: boolean)
	rateScale = if lite then Quality.WEATHER_RATE_LITE else 1
	if emitter and current then
		emitter.Rate = current.rate * rateScale
	end
end

function Weather.init()
	local box = Instance.new("Part")
	box.Name = "WeatherBox"
	box.Anchored = true
	box.CanCollide = false
	box.CanTouch = false
	box.CanQuery = false
	box.CastShadow = false
	box.Transparency = 1
	box.Size = Vector3.new(90, 46, 90)
	box.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Name = "Weather"
	e.SpreadAngle = Vector2.new(35, 35)
	e.Rotation = NumberRange.new(0, 360)
	e.Enabled = on
	e.Parent = box
	emitter = e
	apply(e, Weather.Looks[math.clamp(Atmos.world, 1, #Weather.Looks)])
	Atmos.worldChanged:Connect(function(world: number)
		apply(e, Weather.Looks[math.clamp(world, 1, #Weather.Looks)])
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local cam = Workspace.CurrentCamera
		if cam then
			box.CFrame = CFrame.new(cam.CFrame.Position + cam.CFrame.LookVector * Vector3.new(18, 0, 18))
		end
	end)
end

return Weather
