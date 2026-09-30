--!strict
-- The sky follows your height. Every world has a lighting profile (Shared/Ambience.luau: time of
-- day, atmosphere, colour grading, bloom, sun rays, stars); this module samples the camera height
-- a few times per second, blends the neighbouring profiles around each world boundary and eases
-- Lighting towards the result. Lighting changes made on a client are local, so every player sees
-- the sky of the world they are in.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ambience = require(ReplicatedStorage.Shared.Ambience)
local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local TowerStyle = require(ReplicatedStorage.Shared.TowerStyle)

local Atmos = {}

Atmos.world = 1 -- world LOOK (1..10, index of Ambience.Profiles / Config.Themes) that dominates at the camera
Atmos.tower = 1 -- tower the camera is at
local worldChanged = Instance.new("BindableEvent")
Atmos.worldChanged = worldChanged.Event -- fires (world)

local bounds: { number } = {}

-- Per tower: the heights of its world boundaries and its ten sky profiles in climbing order
-- (each world's profile seen through the tower's mood). Built the first time the camera gets there.
type TowerSky = { bounds: { number }, profiles: { Ambience.Profile }, styles: { number } }
local skies: { [number]: TowerSky } = {}

local function skyOf(tower: number): TowerSky
	local known = skies[tower]
	if known then
		return known
	end
	local map = Layout.generate(Config.MapSeed, tower)
	local padY: { [number]: number } = {}
	for k, p in map.pads do
		padY[k] = p.y
	end
	local mood = TowerStyle.mood(tower)
	local profiles, styles = {}, {}
	for slot = 1, 10 do
		local style = Layout.themeFor((tower - 1) * Layout.STAGES + (slot - 1) * 10 + 1)
		styles[slot] = style
		profiles[slot] = Ambience.grade(Ambience.Profiles[style], mood :: any)
	end
	local sky: TowerSky = { bounds = Ambience.bounds(padY), profiles = profiles, styles = styles }
	skies[tower] = sky
	return sky
end

-- Tower whose axis is nearest to a world X coordinate.
function Atmos.towerAt(x: number): number
	return math.clamp(math.floor(x / Layout.TOWER_SPACING + 0.5) + 1, 1, Layout.TOWERS)
end
local bloom: BloomEffect? = nil
local rays: SunRaysEffect? = nil
local effectsOn = true
local lite = false

local function c3(v: Ambience.RGB): Color3
	return Color3.fromRGB(math.floor(v[1] + 0.5), math.floor(v[2] + 0.5), math.floor(v[3] + 0.5))
end

local function ensure(className: string): Instance
	local found = Lighting:FindFirstChildOfClass(className)
	if found then
		return found
	end
	local inst = Instance.new(className)
	inst.Parent = Lighting
	return inst
end

-- World boundaries (heights), for other client modules.
function Atmos.bounds(): { number }
	return bounds
end

-- Bloom and sun rays can be switched off (Settings -> Effects) on slow devices.
local function applyEffects()
	local on = effectsOn and not lite
	if bloom then
		bloom.Enabled = on
	end
	if rays then
		rays.Enabled = on
	end
end

function Atmos.setEffects(on: boolean)
	effectsOn = on
	applyEffects()
end

-- Lite profile (Quality.isLite): no bloom / sun rays. The sky, the fog colour and the colour
-- grade stay: they are what tells the worlds apart.
function Atmos.setLite(on: boolean)
	lite = on
	applyEffects()
end

function Atmos.init()
	bounds = skyOf(1).bounds

	local atm = ensure("Atmosphere") :: Atmosphere
	local cc = ensure("ColorCorrectionEffect") :: ColorCorrectionEffect
	local bl = ensure("BloomEffect") :: BloomEffect
	local sr = ensure("SunRaysEffect") :: SunRaysEffect
	local sky = ensure("Sky") :: Sky
	bloom, rays = bl, sr
	bl.Enabled = effectsOn and not lite
	sr.Enabled = effectsOn and not lite
	sr.Spread = 0.6

	local function apply(p: Ambience.Profile)
		Lighting.ClockTime = p.clock
		Lighting.Brightness = p.brightness
		Lighting.ExposureCompensation = p.exposure
		Lighting.Ambient = c3(p.ambient)
		Lighting.OutdoorAmbient = c3(p.outdoor)
		atm.Density = p.density
		atm.Haze = p.haze
		atm.Glare = p.glare
		atm.Color = c3(p.atmColor)
		atm.Decay = c3(p.atmDecay)
		cc.TintColor = c3(p.tint)
		cc.Saturation = p.saturation
		cc.Contrast = p.contrast
		bl.Intensity = p.bloom
		bl.Size = p.bloomSize
		bl.Threshold = p.bloomThreshold
		sr.Intensity = p.rays
		sky.StarCount = math.floor(p.stars)
	end

	local current: Ambience.Profile = Ambience.Profiles[1]
	local applied: Ambience.Profile? = nil
	local sameTargetFor = 0
	local lastTarget: Ambience.Profile? = nil
	local acc = 0
	apply(current)
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 15 then
			return
		end
		local step = acc
		acc = 0
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local y = cam.CFrame.Position.Y
		local tower = Atmos.towerAt(cam.CFrame.Position.X)
		local sky = skyOf(tower)
		bounds = sky.bounds
		local target = Ambience.sample(y, sky.bounds, sky.profiles)
		local world = sky.styles[Ambience.worldAt(y, sky.bounds)]
		if world ~= Atmos.world or tower ~= Atmos.tower then
			Atmos.world = world
			Atmos.tower = tower
			worldChanged:Fire(world)
		end
		-- Outside the blend zones `target` is the profile table itself: once we have eased onto
		-- it for a while, snap and stop touching Lighting until the target changes.
		if target == lastTarget then
			sameTargetFor += step
		else
			sameTargetFor = 0
			lastTarget = target
		end
		if sameTargetFor > 3 then
			if applied ~= target then
				current = target
				applied = target
				apply(target)
			end
			return
		end
		current = Ambience.mix(current, target, 1 - math.exp(-step * 2.5))
		applied = nil
		apply(current)
	end)
end

return Atmos
