--!nonstrict
-- World presentation on the client: per-planet sky and lighting (tweened when you travel),
-- animated props (parts tagged with the KiwAnim attribute by the WorldBuilder), localized
-- signs / prompts, and prompt routing. Post-processing is an extra on top: the planets are
-- coloured to read without it.
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Fx = require(script.Parent.Fx)

local WorldFx = {}

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local SKIES = {
	meadow = { clock = 13.6, brightness = 2.1, ambient = c(120, 130, 150), outdoor = c(150, 160, 175), top = c(255, 250, 235), fog = c(190, 225, 255), density = 0.26, haze = 1.2, stars = 0, tint = c(255, 255, 255), sat = 0.18 },
	volcano = { clock = 17.75, brightness = 2.2, ambient = c(140, 84, 70), outdoor = c(170, 100, 80), top = c(255, 160, 90), fog = c(255, 140, 90), density = 0.34, haze = 2.2, stars = 0, tint = c(255, 236, 224), sat = 0.2 },
	ice = { clock = 8.2, brightness = 2.4, ambient = c(130, 150, 190), outdoor = c(160, 185, 220), top = c(230, 245, 255), fog = c(210, 235, 255), density = 0.3, haze = 1.4, stars = 0, tint = c(236, 246, 255), sat = 0.1 },
	storm = { clock = 18.4, brightness = 1.9, ambient = c(110, 110, 160), outdoor = c(130, 130, 190), top = c(190, 190, 255), fog = c(150, 140, 210), density = 0.36, haze = 2, stars = 1500, tint = c(236, 232, 255), sat = 0.12 },
	desert = { clock = 15.6, brightness = 2.4, ambient = c(150, 130, 110), outdoor = c(180, 160, 130), top = c(255, 236, 200), fog = c(255, 220, 170), density = 0.3, haze = 1.8, stars = 0, tint = c(255, 246, 232), sat = 0.14 },
	wasteland = { clock = 18.05, brightness = 2.1, ambient = c(130, 96, 120), outdoor = c(160, 110, 130), top = c(255, 170, 150), fog = c(230, 130, 140), density = 0.34, haze = 2, stars = 800, tint = c(255, 236, 236), sat = 0.16 },
	ruins = { clock = 6.4, brightness = 1.7, ambient = c(100, 116, 116), outdoor = c(120, 140, 136), top = c(190, 220, 200), fog = c(130, 160, 150), density = 0.4, haze = 2.4, stars = 0, tint = c(226, 246, 236), sat = -0.05 },
	candy = { clock = 11.5, brightness = 2.2, ambient = c(170, 140, 170), outdoor = c(200, 170, 200), top = c(255, 230, 245), fog = c(255, 200, 230), density = 0.26, haze = 1.2, stars = 0, tint = c(255, 244, 250), sat = 0.22 },
	future = { clock = 18.35, brightness = 1.8, ambient = c(110, 84, 100), outdoor = c(140, 96, 110), top = c(255, 130, 120), fog = c(150, 70, 90), density = 0.38, haze = 2.2, stars = 2500, tint = c(255, 232, 232), sat = 0.1 },
	void = { clock = 0.3, brightness = 1.6, ambient = c(90, 64, 150), outdoor = c(110, 80, 180), top = c(200, 140, 255), fog = c(60, 30, 110), density = 0.3, haze = 1.6, stars = 5000, tint = c(240, 226, 255), sat = 0.2 },
}

local atmosphere: Atmosphere
local sky: Sky
local grade: ColorCorrectionEffect
local current: string? = nil

local function applySky(theme: string, instant: boolean?)
	local s = SKIES[theme] or SKIES.meadow
	if current == theme then
		return
	end
	current = theme
	local time = if instant then 0 else 1.2
	local info = TweenInfo.new(time, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = s.clock, Brightness = s.brightness, Ambient = s.ambient, OutdoorAmbient = s.outdoor, ColorShift_Top = s.top }):Play()
	TweenService:Create(atmosphere, info, { Color = s.fog, Decay = s.fog:Lerp(Color3.new(0, 0, 0), 0.3), Density = s.density, Haze = s.haze }):Play()
	TweenService:Create(grade, info, { TintColor = s.tint, Saturation = s.sat }):Play()
	sky.StarCount = s.stars
end

function WorldFx.themeOf(planet: number): string
	local pl = Config.Planets[planet]
	return if pl then pl.theme else "meadow"
end

---------------------------------------------------------------------------
-- Animated props
---------------------------------------------------------------------------
type Prop = { part: BasePart, kind: string, base: CFrame, size: Vector3, phase: number, amp: number, segs: { BasePart }?, radius: number?, shown: boolean? }
local RING_SEGMENTS = 18
local ringFolder = Instance.new("Folder")
ringFolder.Name = "KiwRings"
ringFolder.Parent = workspace

local function buildRing(p: Prop)
	local radius = p.part:GetAttribute("KiwRadius") or 8
	local thick = p.part:GetAttribute("KiwThick") or 0.8
	local segs = {}
	local n = if Fx.lite then 12 else RING_SEGMENTS
	local len = 2 * math.pi * radius / n * 1.08
	for _ = 1, n do
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = p.part.Color
		seg.Size = Vector3.new(len, thick, thick)
		seg.Parent = ringFolder
		table.insert(segs, seg)
	end
	p.segs = segs
	p.radius = radius
end

local function placeRing(p: Prop, frame: CFrame)
	local segs = p.segs :: { BasePart }
	local n = #segs
	local r = p.radius :: number
	for i, seg in segs do
		local a = i / n * math.pi * 2
		seg.CFrame = frame * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0)
	end
end
local props: { [BasePart]: Prop } = {}

local function track(inst: Instance)
	if inst:IsA("BasePart") then
		local kind = inst:GetAttribute("KiwAnim")
		if kind and not props[inst] then
			local p: Prop = { part = inst, kind = kind, base = inst.CFrame, size = inst.Size, phase = inst:GetAttribute("KiwPhase") or 0, amp = inst:GetAttribute("KiwAmp") or 1 }
			props[inst] = p
			if kind == "ring" then
				buildRing(p)
				placeRing(p, p.base)
			end
		end
	end
end

local function animate(now: number, camPos: Vector3)
	local range = if Fx.lite then 260 else 480
	for part, p in props do
		if not part.Parent then
			if p.segs then
				for _, seg in p.segs do
					seg:Destroy()
				end
			end
			props[part] = nil
			continue
		end
		if (p.base.Position - camPos).Magnitude > range then
			continue
		end
		local t = now + p.phase
		local kind = p.kind
		if kind == "ring" then
			placeRing(p, CFrame.new(p.base.Position) * CFrame.Angles(math.sin(t * 0.7) * 0.55, t * 0.6, math.cos(t * 0.5) * 0.55))
		elseif kind == "bob" then
			part.CFrame = p.base + Vector3.new(0, math.sin(t * 1.4) * 0.8 * p.amp, 0)
		elseif kind == "spin" then
			part.CFrame = p.base * CFrame.Angles(t * 0.9, 0, 0)
		elseif kind == "spinbob" then
			part.CFrame = (p.base + Vector3.new(0, math.sin(t * 1.2) * 1.2, 0)) * CFrame.Angles(0, t * 0.8, 0)
		elseif kind == "orbit" then
			part.CFrame = CFrame.new(p.base.Position) * CFrame.Angles(math.sin(t * 0.7) * 0.5, t * 0.6, math.cos(t * 0.5) * 0.5) * CFrame.Angles(0, 0, math.rad(90))
		elseif kind == "pulse" then
			part.Size = p.size * (1 + math.sin(t * 3) * 0.08)
		elseif kind == "flag" then
			part.CFrame = p.base * CFrame.Angles(0, math.sin(t * 2.4) * 0.22, 0)
		elseif kind == "flame" then
			part.Size = p.size * Vector3.new(1 + math.sin(t * 9) * 0.08, 1 + math.sin(t * 7) * 0.16, 1 + math.cos(t * 8) * 0.08)
		elseif kind == "water" then
			part.Transparency = 0.12 + math.sin(t * 5) * 0.06
		elseif kind == "clock" then
			part.CFrame = p.base * CFrame.Angles(0, 0, -t * 1.5)
		end
	end
end

---------------------------------------------------------------------------
-- Localized world text + prompts
---------------------------------------------------------------------------
local labels: { [TextLabel]: boolean } = {}
local prompts: { [ProximityPrompt]: boolean } = {}
local function renderLabel(l: TextLabel)
	local key = l:GetAttribute("LocKey")
	if key then
		l.Text = Lang.t(key, { n = l:GetAttribute("LocN") })
	end
end
local function renderPrompt(p: ProximityPrompt)
	local a, o = p:GetAttribute("LocAction"), p:GetAttribute("LocObject")
	if a then
		p.ActionText = Lang.t(a)
	end
	if o then
		p.ObjectText = Lang.t(o)
	end
end
local function trackText(inst: Instance)
	if inst:IsA("TextLabel") and inst:GetAttribute("LocKey") then
		labels[inst] = true
		renderLabel(inst)
	elseif inst:IsA("ProximityPrompt") then
		prompts[inst] = true
		renderPrompt(inst)
	end
end

-- prompt name -> callback (windows register here)
WorldFx.onPrompt = {} :: { [string]: () -> () }

function WorldFx.init()
	-- lighting rig (all built-in; nothing here is required for the game to read well)
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Offset = 0.1
	atmosphere.Glare = 0.2
	atmosphere.Parent = Lighting
	sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 14
	sky.Parent = Lighting
	grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast = 0.06
	grade.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 22
	bloom.Threshold = 1.7
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GeographicLatitude = 28
	Lighting.ExposureCompensation = -0.12

	applySky(WorldFx.themeOf(Net.get("planet") or 1), true)
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			applySky(WorldFx.themeOf(Net.get("planet") or 1))
		end
	end)

	task.spawn(function()
		local world = workspace:WaitForChild("World")
		world.DescendantAdded:Connect(function(d)
			track(d)
			trackText(d)
		end)
		world.DescendantRemoving:Connect(function(d)
			labels[d] = nil
			prompts[d] = nil
		end)
		for _, d in world:GetDescendants() do
			track(d)
			trackText(d)
		end
	end)
	Lang.Changed:Connect(function()
		for l in labels do
			renderLabel(l)
		end
		for p in prompts do
			renderPrompt(p)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local cb = WorldFx.onPrompt[prompt.Name]
		if cb then
			cb()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			animate(os.clock(), cam.CFrame.Position)
		end
	end)
end

return WorldFx
