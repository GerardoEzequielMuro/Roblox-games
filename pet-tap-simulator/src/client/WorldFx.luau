--!strict
-- Local world effects:
--  * eggs spin and bob, and jump with a burst of sparkles when the player hatches one
--  * gates the player owns open (with a burst the moment they are bought)
--  * every zone has its own sky: clock, light, Atmosphere, clouds, colour grade and
--    drifting particles (pollen, sugar, snow, embers, stardust) around the camera
--  * world props tagged "TpsAnim" spin / bob (windmill, UFO, planets, balloons, lanterns)
--  * the "entering zone" banner
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Net = require(script.Parent.Net)
local Theme = require(script.Parent.UI.Theme)
local Root = require(script.Parent.UI.Root)
local Lang = require(script.Parent.Lang)
local Quality = require(script.Parent.Quality)

local WorldFx = {}

local C = Color3.fromRGB
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

---------------------------------------------------------------------------
-- Per-zone look
---------------------------------------------------------------------------
type ZoneLook = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	atmosphere: { Density: number, Offset: number, Haze: number, Glare: number, Color: Color3, Decay: Color3 },
	tint: Color3,
	saturation: number,
	contrast: number,
	cloudCover: number,
	cloudColor: Color3,
	weather: string,
}

local LOOKS: { ZoneLook } = {
	{ -- Spawn Meadow: clear summer afternoon
		clock = 14.2,
		brightness = 2.4,
		ambient = C(120, 120, 125),
		outdoor = C(150, 158, 160),
		atmosphere = { Density = 0.28, Offset = 0.1, Haze = 1.2, Glare = 0.2, Color = C(205, 225, 255), Decay = C(150, 190, 255) },
		tint = C(255, 252, 242),
		saturation = 0.12,
		contrast = 0.05,
		cloudCover = 0.55,
		cloudColor = C(255, 255, 255),
		weather = "pollen",
	},
	{ -- Candy Land: pink golden hour
		clock = 16.4,
		brightness = 2.5,
		ambient = C(150, 120, 140),
		outdoor = C(180, 150, 170),
		atmosphere = { Density = 0.32, Offset = 0.2, Haze = 1.8, Glare = 0.35, Color = C(255, 205, 232), Decay = C(255, 160, 210) },
		tint = C(255, 232, 246),
		saturation = 0.2,
		contrast = 0.04,
		cloudCover = 0.7,
		cloudColor = C(255, 195, 228),
		weather = "sugar",
	},
	{ -- Frost Peak: cold overcast noon, snowing
		clock = 11.2,
		brightness = 2,
		ambient = C(130, 145, 165),
		outdoor = C(160, 175, 195),
		atmosphere = { Density = 0.42, Offset = 0.25, Haze = 2.4, Glare = 0.1, Color = C(222, 236, 255), Decay = C(190, 215, 255) },
		tint = C(226, 240, 255),
		saturation = -0.05,
		contrast = 0.04,
		cloudCover = 0.86,
		cloudColor = C(235, 242, 255),
		weather = "snow",
	},
	{ -- Lava Caves: red dusk under smoke
		clock = 17.6,
		brightness = 2.2,
		ambient = C(170, 95, 75),
		outdoor = C(175, 105, 85),
		atmosphere = { Density = 0.36, Offset = 0.3, Haze = 2.2, Glare = 0.5, Color = C(255, 135, 75), Decay = C(150, 45, 20) },
		tint = C(255, 208, 184),
		saturation = 0.15,
		contrast = 0.12,
		cloudCover = 0.9,
		cloudColor = C(85, 50, 48),
		weather = "embers",
	},
	{ -- Cosmic Void: night, stars
		clock = 0,
		brightness = 2,
		ambient = C(150, 132, 215),
		outdoor = C(140, 124, 208),
		atmosphere = { Density = 0.3, Offset = 0, Haze = 1, Glare = 0, Color = C(95, 72, 165), Decay = C(40, 20, 90) },
		tint = C(218, 208, 255),
		saturation = 0.2,
		contrast = 0.08,
		cloudCover = 0.18,
		cloudColor = C(125, 95, 205),
		weather = "stardust",
	},
}

---------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------
type EggSpin = { id: string, shell: BasePart, base: CFrame, parts: { { part: BasePart, offset: CFrame } }, phase: number, burstAt: number, sparkle: ParticleEmitter? }

local eggList: { EggSpin } = {}

-- Egg models are streamed whole (Atomic), so they come and go as the player moves between
-- zones. The shell's resting CFrame is an attribute, because this script moves the shell.
local addEgg: (model: Instance) -> ()
function addEgg(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local shell = model:FindFirstChild("Shell") :: BasePart?
	if not shell then
		-- the model arrived before its parts: try again when the shell shows up
		task.spawn(function()
			if model:WaitForChild("Shell", 10) then
				addEgg(model)
			end
		end)
		return
	end
	local id = (model:GetAttribute("EggId") :: string?) or ""
	for _, e in eggList do
		if e.shell == shell then
			return
		end
	end
	local rest = shell:GetAttribute("Rest")
	local base = if typeof(rest) == "CFrame" then rest else shell.CFrame
	local parts = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Spot" then
			local off = d:GetAttribute("Offset")
			table.insert(parts, { part = d, offset = if typeof(off) == "CFrame" then off else base:ToObjectSpace(d.CFrame) })
		end
	end
	local sparkle = shell:FindFirstChild("Sparkle")
	table.insert(eggList, {
		id = id,
		shell = shell,
		base = base,
		parts = parts,
		phase = #id * 0.7,
		burstAt = -10,
		sparkle = if sparkle and sparkle:IsA("ParticleEmitter") then sparkle else nil,
	})
end

local function removeEgg(model: Instance)
	for i = #eggList, 1, -1 do
		if eggList[i].shell.Parent == model or not eggList[i].shell.Parent then
			table.remove(eggList, i)
		end
	end
end

local function collectEggs()
	local world = Workspace:WaitForChild("World", 30)
	local eggs = world and world:WaitForChild("Eggs", 30)
	if not eggs then
		return
	end
	for _, model in eggs:GetChildren() do
		addEgg(model)
	end
	eggs.ChildAdded:Connect(addEgg)
	eggs.ChildRemoved:Connect(removeEgg)
end

-- Eggs currently tracked (streamed in).
function WorldFx.eggCount(): number
	return #eggList
end

-- The world egg jumps and throws sparkles (called when its shell bursts in the cinematic).
function WorldFx.eggBurst(eggId: string)
	for _, e in eggList do
		if e.id == eggId then
			e.burstAt = os.clock()
			if e.sparkle then
				e.sparkle:Emit(36)
			end
		end
	end
end

local function zoneAt(z: number): number
	local L = Config.ZoneLength
	return math.clamp(math.floor((z + L / 2) / L) + 1, 1, #Config.Zones)
end

---------------------------------------------------------------------------
-- Tagged props
---------------------------------------------------------------------------
type Animated = { inst: PVInstance, base: CFrame, axis: Vector3?, speed: number, bobAmp: number, bobSpeed: number, phase: number }

local animated: { Animated } = {}

local function addAnimated(inst: Instance)
	if not inst:IsA("PVInstance") then
		return
	end
	for _, a in animated do
		if a.inst == inst then
			return
		end
	end
	local axis = inst:GetAttribute("SpinAxis")
	local rest = inst:GetAttribute("Rest")
	table.insert(animated, {
		inst = inst,
		base = if typeof(rest) == "CFrame" then rest else inst:GetPivot(),
		axis = if typeof(axis) == "Vector3" then axis else nil,
		speed = (inst:GetAttribute("SpinSpeed") :: number?) or 0,
		bobAmp = (inst:GetAttribute("BobAmp") :: number?) or 0,
		bobSpeed = (inst:GetAttribute("BobSpeed") :: number?) or 1,
		phase = #animated * 0.9,
	})
end

---------------------------------------------------------------------------
-- Weather: emitters in a box that follows the camera
---------------------------------------------------------------------------
local function weatherEmitters(): ({ [string]: ParticleEmitter }, BasePart, BasePart)
	local function box(name: string, size: Vector3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = size
		p.Parent = Workspace
		return p
	end
	local sky = box("WeatherSky", Vector3.new(110, 1, 110)) -- above the camera: things that fall
	local near = box("WeatherNear", Vector3.new(90, 36, 90)) -- around the camera: things that float
	local k = Quality.particles
	local function make(parent: BasePart, texture: string, color: ColorSequence, rate: number, size: number, life: number, speed: number, dir: Enum.NormalId, accel: Vector3, emission: number): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Texture = texture
		e.Color = color
		e.Rate = rate * k
		e.Lifetime = NumberRange.new(life * 0.7, life)
		e.Speed = NumberRange.new(speed * 0.6, speed)
		e.EmissionDirection = dir
		e.Acceleration = accel
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, size), NumberSequenceKeypoint.new(0.85, size), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.15), NumberSequenceKeypoint.new(0.8, 0.25), NumberSequenceKeypoint.new(1, 1) })
		e.LightEmission = emission
		e.RotSpeed = NumberRange.new(-60, 60)
		e.Rotation = NumberRange.new(0, 360)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Enabled = false
		e.Parent = parent
		return e
	end
	local list: { [string]: ParticleEmitter } = {
		pollen = make(near, SPARKLES, ColorSequence.new(C(255, 250, 200)), 7, 0.45, 6, 1.2, Enum.NormalId.Top, Vector3.new(0.6, 0.2, 0), 0.6),
		sugar = make(near, SPARKLES, ColorSequence.new(C(255, 170, 215), C(190, 235, 255)), 12, 0.6, 5, 2, Enum.NormalId.Bottom, Vector3.new(0.5, -0.6, 0), 0.7),
		snow = make(sky, SMOKE, ColorSequence.new(C(255, 255, 255)), 85, 0.42, 5.5, 13, Enum.NormalId.Bottom, Vector3.new(2.5, 0, 0.8), 0.4),
		embers = make(near, FIRE, ColorSequence.new(C(255, 170, 60), C(255, 80, 20)), 30, 0.5, 3.2, 6, Enum.NormalId.Top, Vector3.new(1, 3, 0), 1),
		stardust = make(near, SPARKLES, ColorSequence.new(C(200, 225, 255), C(215, 170, 255)), 16, 0.55, 4.5, 0.6, Enum.NormalId.Top, Vector3.new(0, 0.1, 0), 1),
	}
	return list, sky, near
end

---------------------------------------------------------------------------
function WorldFx.init()
	-- Eggs + tagged props + weather boxes, all in one render step
	local weather, skyBox, nearBox = weatherEmitters()
	task.spawn(function()
		collectEggs()
		Workspace:WaitForChild("World", 30)
		for _, inst in CollectionService:GetTagged("TpsAnim") do
			addAnimated(inst)
		end
		CollectionService:GetInstanceAddedSignal("TpsAnim"):Connect(addAnimated)
		-- streamed out: forget it (it is added again, at rest, when it streams back in)
		CollectionService:GetInstanceRemovedSignal("TpsAnim"):Connect(function(inst: Instance)
			for i = #animated, 1, -1 do
				if (animated[i].inst :: Instance) == inst then
					table.remove(animated, i)
				end
			end
		end)
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for _, e in eggList do
			if not e.shell.Parent then
				continue
			end
			local hop = 0
			local since = t - e.burstAt
			if since < 0.6 then
				hop = math.sin(since / 0.6 * math.pi) * 2.2
			end
			local cf = e.base * CFrame.new(0, math.sin(t * 1.6 + e.phase) * 0.35 + hop, 0) * CFrame.Angles(0, t * 0.6 + e.phase + (if since < 0.6 then (1 - math.cos(since / 0.6 * math.pi)) * math.pi else 0), 0)
			e.shell.CFrame = cf
			for _, sp in e.parts do
				sp.part.CFrame = cf * sp.offset
			end
		end
		local animRange = if Quality.lite then 260 else 520
		for _, a in animated do
			if a.inst.Parent and (a.base.Position - camPos).Magnitude < animRange then
				local cf = a.base
				if a.bobAmp ~= 0 then
					cf = CFrame.new(0, math.sin(t * a.bobSpeed + a.phase) * a.bobAmp, 0) * cf
				end
				if a.axis then
					cf *= CFrame.fromAxisAngle(a.axis, t * a.speed)
				end
				a.inst:PivotTo(cf)
			end
		end
		skyBox.CFrame = CFrame.new(camPos + Vector3.new(0, 34, 0))
		nearBox.CFrame = CFrame.new(camPos + Vector3.new(0, 6, 0))
	end)

	-- Gates
	local known: { [number]: boolean }? = nil
	local function refreshGates()
		local s = Net.state
		local world = Workspace:FindFirstChild("World")
		local gates = world and world:FindFirstChild("Gates")
		if not s or not gates then
			return
		end
		local first = known == nil
		local now: { [number]: boolean } = {}
		for _, gate in gates:GetChildren() do
			local barrier = gate:FindFirstChild("Barrier") :: BasePart?
			if barrier then
				local zone = barrier:GetAttribute("Zone") :: number
				local open = table.find(s.zones, zone) ~= nil
				now[zone] = open
				barrier.CanCollide = not open
				barrier.Transparency = if open then 1 else 0.2
				for _, d in barrier:GetChildren() do
					if d:IsA("SurfaceGui") then
						d.Enabled = not open
					elseif d:IsA("ProximityPrompt") then
						d.Enabled = not open
					end
				end
				-- just bought: burst of sparkles where the barrier was
				if open and not first and known and not known[zone] then
					local burst = barrier:FindFirstChild("Unlock")
					if burst and burst:IsA("ParticleEmitter") then
						burst:Emit(90)
					end
					Theme.play("boom", 0.2, 1.4)
				end
			end
		end
		known = now
	end
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refreshGates()
		end
	end)
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 30)
		local gates = world and world:WaitForChild("Gates", 30)
		refreshGates()
		if gates then
			-- gates stream in as the player gets near them
			gates.ChildAdded:Connect(function()
				task.defer(refreshGates)
			end)
		end
	end)

	-- Lite profile: no real-time shadows or post-processing (they are a bonus, never the
	-- base of the look), half the weather.
	local function applyProfile()
		Lighting.GlobalShadows = Quality.shadows
		for _, fx in Lighting:GetChildren() do
			if fx:IsA("BloomEffect") or fx:IsA("SunRaysEffect") or fx:IsA("DepthOfFieldEffect") then
				fx.Enabled = Quality.shadows
			end
		end
	end
	applyProfile()
	Quality.Changed:Connect(applyProfile)

	-- Ambience + banner
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ZoneTint"
	cc.Parent = Lighting
	local banner = Theme.text({
		Text = "",
		Size = UDim2.fromOffset(700, 80),
		Position = UDim2.fromScale(0.5, 0.26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 72,
		Stroke = 4,
		TextTransparency = 1,
		Parent = Root.gui,
	})
	Root.mount(banner)
	local bannerStroke = banner:FindFirstChildOfClass("UIStroke") :: UIStroke
	bannerStroke.Transparency = 1
	local currentZone = 0

	local clock = Instance.new("NumberValue")
	clock.Value = Lighting.ClockTime
	clock.Changed:Connect(function(v)
		Lighting.ClockTime = v % 24
	end)

	local function applyLook(z: number, seconds: number)
		local look = LOOKS[z] or LOOKS[1]
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine)
		TweenService:Create(Lighting, info, { Brightness = look.brightness, Ambient = look.ambient, OutdoorAmbient = look.outdoor }):Play()
		-- the clock takes the short way round (18:00 -> 00:00 goes through the evening, not back through noon)
		local from = Lighting.ClockTime
		local to = look.clock
		if to - from > 12 then
			from += 24
		elseif from - to > 12 then
			to += 24
		end
		clock.Value = from
		TweenService:Create(clock, info, { Value = to }):Play()
		TweenService:Create(cc, info, { TintColor = look.tint, Saturation = look.saturation, Contrast = look.contrast }):Play()
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			TweenService:Create(atm, info, look.atmosphere :: any):Play()
		end
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
		if clouds then
			TweenService:Create(clouds, info, { Cover = look.cloudCover, Color = look.cloudColor }):Play()
		end
		for name, e in weather do
			e.Enabled = name == look.weather
		end
	end

	task.spawn(function()
		while true do
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local z = zoneAt(root.Position.Z)
				if z ~= currentZone then
					local first = currentZone == 0
					currentZone = z
					local zone = Config.Zones[z]
					applyLook(z, if first then 0 else 2.5)
					if not first then
						banner.Text = Lang.upper(Lang.zone(z))
						banner.TextColor3 = Theme.lighten(Palette.rgb(zone.ground), 0.3)
						Theme.pop(banner, 1.3)
						TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
						TweenService:Create(bannerStroke, TweenInfo.new(0.4), { Transparency = 0 }):Play()
						task.delay(2, function()
							if currentZone == z then
								TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
								TweenService:Create(bannerStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
							end
						end)
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

return WorldFx
