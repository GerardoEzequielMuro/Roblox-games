--!nonstrict
-- Weather banner (top-center) + client-side weather VFX and lighting moods.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Layout = require(script.Parent.Layout)

local Weather = {}
Weather.CHIP_W = 270
Weather.CHIP_H = 46
Weather.STACKED_Y = 8 + 3 * 54 + 2 * 8 + 8 -- below the stacked action column
Weather.COMPACT_Y = 78 + 58 + 8 -- below the stats card and the folded menu row
Weather.COMPACT_W = 236

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local currentId: string? = "__init"
local skyPart: Part? = nil
local groundPart: Part? = nil
local emitters: { [string]: ParticleEmitter } = {}
local cc: ColorCorrectionEffect? = nil
local flashCC: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
local clouds: Clouds? = nil
local original: { [string]: any } = {}
local flashToken = 0

-- ========== Lighting ==========

local function setupLighting()
	original.ClockTime = Lighting.ClockTime
	original.Brightness = Lighting.Brightness
	original.Ambient = Lighting.Ambient
	original.OutdoorAmbient = Lighting.OutdoorAmbient
	original.ExposureCompensation = Lighting.ExposureCompensation

	cc = Lighting:FindFirstChild("WeatherColorCorrection") :: ColorCorrectionEffect?
	if not cc then
		cc = C.new("ColorCorrectionEffect", { Name = "WeatherColorCorrection", Parent = Lighting })
	end
	flashCC = C.new("ColorCorrectionEffect", { Name = "WeatherFlash", Brightness = 0, Parent = Lighting })

	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = C.new("Atmosphere", {
			Name = "WeatherAtmosphere",
			Density = 0,
			Offset = 0,
			Haze = 0,
			Glare = 0,
			Color = Color3.fromRGB(199, 199, 199),
			Decay = Color3.fromRGB(106, 112, 125),
			Parent = Lighting,
		})
	end
	clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		original.CloudCover = clouds.Cover
		original.CloudDensity = clouds.Density
		original.CloudColor = clouds.Color
	end
	local a = atmosphere :: Atmosphere
	original.AtmoDensity = a.Density
	original.AtmoHaze = a.Haze
	original.AtmoColor = a.Color
	original.AtmoDecay = a.Decay
end

type Mood = {
	lighting: { [string]: any },
	cc: { [string]: any },
	atmo: { [string]: any },
	clouds: { [string]: any }?,
}

local function moodFor(id: string?): Mood
	local neutralCC = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 }
	if id == "Rain" then
		return {
			lighting = { ClockTime = 13, Brightness = 1.4, Ambient = Color3.fromRGB(90, 95, 110), OutdoorAmbient = Color3.fromRGB(110, 115, 130), ExposureCompensation = -0.2 },
			cc = { TintColor = Color3.fromRGB(205, 215, 235), Saturation = -0.25, Contrast = 0.05, Brightness = -0.03 },
			atmo = { Density = 0.45, Haze = 2, Color = Color3.fromRGB(170, 180, 195), Decay = Color3.fromRGB(110, 120, 135) },
			clouds = { Cover = 0.85, Density = 0.75, Color = Color3.fromRGB(150, 156, 170) },
		}
	elseif id == "Snow" then
		return {
			lighting = { ClockTime = 12, Brightness = 2, Ambient = Color3.fromRGB(150, 160, 180), OutdoorAmbient = Color3.fromRGB(170, 180, 200), ExposureCompensation = 0.1 },
			cc = { TintColor = Color3.fromRGB(225, 238, 255), Saturation = -0.15, Contrast = 0, Brightness = 0.02 },
			atmo = { Density = 0.42, Haze = 2.5, Color = Color3.fromRGB(230, 238, 250), Decay = Color3.fromRGB(190, 205, 225) },
			clouds = { Cover = 0.8, Density = 0.6, Color = Color3.fromRGB(228, 234, 244) },
		}
	elseif id == "Thunderstorm" then
		return {
			lighting = { ClockTime = 17.2, Brightness = 0.8, Ambient = Color3.fromRGB(60, 60, 85), OutdoorAmbient = Color3.fromRGB(75, 75, 100), ExposureCompensation = -0.4 },
			cc = { TintColor = Color3.fromRGB(170, 175, 215), Saturation = -0.3, Contrast = 0.12, Brightness = -0.05 },
			atmo = { Density = 0.55, Haze = 3, Color = Color3.fromRGB(110, 110, 140), Decay = Color3.fromRGB(70, 70, 95) },
			clouds = { Cover = 0.95, Density = 0.9, Color = Color3.fromRGB(92, 94, 112) },
		}
	elseif id == "GoldenHour" then
		return {
			lighting = { ClockTime = 17.6, Brightness = 2.6, Ambient = Color3.fromRGB(150, 110, 70), OutdoorAmbient = Color3.fromRGB(170, 130, 90), ExposureCompensation = 0.15 },
			cc = { TintColor = Color3.fromRGB(255, 222, 170), Saturation = 0.25, Contrast = 0.08, Brightness = 0.02 },
			atmo = { Density = 0.35, Haze = 1.5, Color = Color3.fromRGB(255, 200, 140), Decay = Color3.fromRGB(255, 150, 80) },
			clouds = { Cover = 0.45, Density = 0.4, Color = Color3.fromRGB(255, 214, 170) },
		}
	end
	return {
		lighting = {
			ClockTime = original.ClockTime,
			Brightness = original.Brightness,
			Ambient = original.Ambient,
			OutdoorAmbient = original.OutdoorAmbient,
			ExposureCompensation = original.ExposureCompensation,
		},
		cc = neutralCC,
		atmo = { Density = original.AtmoDensity, Haze = original.AtmoHaze, Color = original.AtmoColor, Decay = original.AtmoDecay },
		clouds = if original.CloudCover then { Cover = original.CloudCover, Density = original.CloudDensity, Color = original.CloudColor } else nil,
	}
end

local function applyMood(id: string?, time: number)
	local mood = moodFor(id)
	C.tween(Lighting, time, mood.lighting, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if cc then
		C.tween(cc, time, mood.cc, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	if atmosphere then
		C.tween(atmosphere, time, mood.atmo, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	if clouds and mood.clouds then
		C.tween(clouds, time, mood.clouds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end

-- ========== Particles ==========

local function makePart(name: string, size: Vector3): Part
	return C.new("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = size,
		Parent = workspace,
	})
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e: ParticleEmitter = C.new("ParticleEmitter", {
		Texture = SPARKLE,
		Enabled = false,
		LockedToPart = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Parent = parent,
	})
	for k, v in props do
		(e :: any)[k] = v
	end
	return e
end

local function setupParticles()
	skyPart = makePart("ClientWeatherSky", Vector3.new(90, 1, 90))
	groundPart = makePart("ClientWeatherGround", Vector3.new(60, 16, 60))
	local sky = skyPart :: Part
	local ground = groundPart :: Part

	emitters.Rain = emitter(sky, {
		Color = ColorSequence.new(Color3.fromRGB(150, 190, 255)),
		Size = NumberSequence.new(0.14),
		Squash = NumberSequence.new(3),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Transparency = NumberSequence.new(0.25),
		LightEmission = 0.3,
		Lifetime = NumberRange.new(0.7, 0.9),
		Speed = NumberRange.new(85, 100),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(4, 4),
		Rate = 500,
	})
	emitters.Snow = emitter(sky, {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.4,
		Lifetime = NumberRange.new(6, 8),
		Speed = NumberRange.new(6, 10),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(25, 25),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Acceleration = Vector3.new(1.5, 0, 0.8),
		Rate = 140,
	})
	emitters.Gold = emitter(ground, {
		Color = ColorSequence.new(Color3.fromRGB(255, 205, 60), Color3.fromRGB(255, 240, 150)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(0.5, 2),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Rate = 45,
	})

	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local pos = cam.CFrame.Position
		sky.CFrame = CFrame.new(pos + Vector3.new(0, 35, 0))
		ground.CFrame = CFrame.new(pos + Vector3.new(0, -2, 0))
	end)
end

local function flashLoop(token: number)
	while flashToken == token do
		task.wait(math.random(40, 100) / 10)
		if flashToken ~= token or not flashCC then
			return
		end
		local f = flashCC :: ColorCorrectionEffect
		local strikes = if math.random() < 0.4 then 2 else 1
		for _ = 1, strikes do
			f.Brightness = 0.55
			f.TintColor = Color3.fromRGB(220, 230, 255)
			C.tween(f, 0.35, { Brightness = 0 })
			task.wait(0.12)
		end
	end
end

-- ========== Public ==========

function Weather.apply(id: string?)
	if id == currentId then
		return
	end
	local first = currentId == "__init"
	currentId = id
	applyMood(id, if first then 0.5 else 3)

	local rain = emitters.Rain
	rain.Enabled = id == "Rain" or id == "Thunderstorm"
	rain.Rate = if id == "Thunderstorm" then 900 else 500
	rain.Speed = if id == "Thunderstorm" then NumberRange.new(100, 120) else NumberRange.new(85, 100)
	emitters.Snow.Enabled = id == "Snow"
	emitters.Gold.Enabled = id == "GoldenHour"

	flashToken += 1
	if flashCC then
		flashCC.Brightness = 0
	end
	if id == "Thunderstorm" then
		task.spawn(flashLoop, flashToken)
	end
end

function Weather.build(root: Instance)
	setupLighting()
	setupParticles()

	local banner: Frame = C.new("Frame", {
		Name = "WeatherBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(Weather.CHIP_W, Weather.CHIP_H),
		BackgroundColor3 = Theme.WeatherColor.Clear,
		Parent = root,
	})
	C.corner(banner, 16)
	local bStroke = C.stroke(banner, 3, Theme.darken(Theme.WeatherColor.Clear, 0.5))
	C.shade(banner)
	local bScale = C.new("UIScale", { Parent = banner })
	-- narrower on touch so it clears the stats card (left) and the action column (right)
	Layout.onChanged(function()
		if Layout.compact then
			-- phones: left column, under the folded menu and above the thumbstick zone
			banner.AnchorPoint = Vector2.new(0, 0)
			banner.Position = UDim2.fromOffset(12, Weather.COMPACT_Y)
			banner.Size = UDim2.fromOffset(Weather.COMPACT_W, Weather.CHIP_H)
		elseif Layout.stacked then
			-- tablets: under the action buttons, top-right (the bottom-right corner belongs to the jump button)
			banner.AnchorPoint = Vector2.new(1, 0)
			banner.Position = UDim2.new(1, -12, 0, Weather.STACKED_Y)
			banner.Size = UDim2.fromOffset(Weather.CHIP_W - 30, Weather.CHIP_H)
		else
			banner.AnchorPoint = Vector2.new(1, 1)
			banner.Position = UDim2.new(1, -12, 1, -10)
			banner.Size = UDim2.fromOffset(Weather.CHIP_W, Weather.CHIP_H)
		end
	end)

	local icon = C.label(banner, "☀️", UDim2.fromOffset(36, 36), {
		Position = UDim2.fromOffset(6, 5),
		TextSize = 26,
		Outline = false,
	})
	local title = C.label(banner, L("weather.clear"), UDim2.new(1, -118, 0, 20), {
		Position = UDim2.fromOffset(46, 3),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
	local desc = C.label(banner, "", UDim2.new(1, -118, 0, 22), {
		Position = UDim2.fromOffset(46, 22),
		Font = Theme.FontAlt,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Outline = 1.5,
	})
	local timer = C.label(banner, "", UDim2.fromOffset(66, 40), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 3),
		TextSize = 18,
		TextColor3 = Theme.C.Yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})

	local function refresh()
		local w = State.weather
		local def = w.id and Config.WeatherById[w.id]
		local color = if def then Theme.WeatherColor[def.id] or Theme.WeatherColor.Clear else Theme.WeatherColor.Clear
		banner.BackgroundColor3 = color
		bStroke.Color = Theme.darken(color, 0.5)
		if def then
			icon.Text = Theme.WeatherEmoji[def.id] or "🌦️"
			I18n.set(title, "Text", L("weather." .. def.id .. ".name"))
			I18n.set(desc, "Text", L("weather." .. def.id .. ".desc"))
		else
			icon.Text = "☀️"
			I18n.set(title, "Text", L("weather.clear"))
			I18n.set(desc, "Text", L("weather.clearDesc"))
		end
		Weather.apply(if def then def.id else nil)
		bScale.Scale = 1.15
		C.tween(bScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	local function tick()
		local w = State.weather
		local now = State.now()
		if w.id then
			timer.Text = Format.time(w.endsAt - now)
		elseif w.nextAt > 0 then
			timer.Text = ""
			I18n.set(desc, "Text", I18n.t("weather.next", { time = Format.time(w.nextAt - now) }))
		else
			timer.Text = ""
		end
	end

	State.onChanged(function(kind)
		if kind == "weather" then
			refresh()
			tick()
		end
	end)
	refresh()

	task.spawn(function()
		while true do
			tick()
			task.wait(0.25)
		end
	end)
end

return Weather
