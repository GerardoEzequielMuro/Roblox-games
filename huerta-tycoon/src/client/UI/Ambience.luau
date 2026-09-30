--!nonstrict
-- Client-side life for the world the server builds: spinning windmill/gears/gems, bobbing shop markers, drifting
-- hot-air balloons, rainbow crops, a "pop" when a crop changes stage, and pollen + leaves in the air on clear days.
-- Everything here is local and cosmetic: the server never waits on it.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local C = require(script.Parent.Components)
local State = require(script.Parent.State)
local Perf = require(script.Parent.Perf)

local Ambience = {}

local POP_TIME = 0.34
local POP_RANGE = 170
Ambience.POP_TIME = POP_TIME

-- Scale curve of the crop pop: starts small, overshoots a little, settles on exactly 1.
function Ambience.popScale(a: number): number
	if a >= 1 then
		return 1
	end
	a = math.max(a, 0)
	local c1, c3 = 1.70158, 2.70158
	local back = 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	return 0.55 + 0.45 * back
end

type Spin = { inst: Instance, base: CFrame, speed: number, axis: string }
local spins: { Spin } = {}
local bobs: { BillboardGui } = {}
local floats: { { model: Model, base: CFrame, phase: number } } = {}
local rainbows: { BasePart } = {}
local pops: { { model: Model, t0: number } } = {}
Ambience.counts = { spins = 0, bobs = 0, floats = 0, pops = 0 }

local function track(tag: string, add: (Instance) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(add, inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		task.defer(add, inst)
	end)
end

local function removeFrom(list: { any }, pred: (any) -> boolean)
	for i = #list, 1, -1 do
		if pred(list[i]) then
			table.remove(list, i)
		end
	end
end

local function cameraPos(): Vector3?
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

local function queuePop(model: Instance)
	if not model:IsA("Model") or model.Name ~= "Crop" then
		return
	end
	-- let the whole model replicate before touching it: a part that arrives mid-pop would end up mis-scaled
	task.wait()
	task.wait()
	if not model.Parent then
		return
	end
	local expected = model:GetAttribute("Parts")
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	if type(expected) ~= "number" or n ~= expected then
		return
	end
	local cam = cameraPos()
	if cam and (model:GetPivot().Position - cam).Magnitude > POP_RANGE then
		return
	end
	table.insert(pops, { model = model, t0 = os.clock() })
	Ambience.counts.pops += 1
end

-- A crop closer to the camera than this turns see-through (a Giant plant used to fill half the screen).
Ambience.FADE_RANGE = 10
Ambience.FADE_ALPHA = 0.78
local faded: { [Instance]: any } = {}
Ambience.fadedNow = 0

function Ambience.shouldFade(distance: number): boolean
	return distance < Ambience.FADE_RANGE
end

local function setFade(crop: Instance, on: boolean)
	for _, d in crop:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.LocalTransparencyModifier = if on then Ambience.FADE_ALPHA else 0
		end
	end
end

local function updateFade()
	local cam = cameraPos()
	local d = State.data
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and d and d.plotIndex and plots:FindFirstChild("Plot_" .. tostring(d.plotIndex))
	local tiles = plot and plot:FindFirstChild("Tiles")
	if not cam or not tiles then
		return
	end
	local seen: { [Instance]: boolean } = {}
	local count = 0
	for _, tile in tiles:GetChildren() do
		local crop = tile:FindFirstChild("Crop")
		if crop and tile:IsA("BasePart") then
			-- measure to the middle of the plant, not to the soil
			local want = Ambience.shouldFade((tile.Position + Vector3.new(0, 3, 0) - cam).Magnitude)
			seen[crop] = true
			if want then
				count += 1
			end
			if (faded[crop] == true) ~= want then
				faded[crop] = if want then true else nil
				setFade(crop, want)
			end
		end
	end
	for crop in faded do
		if not seen[crop] then
			faded[crop] = nil
		end
	end
	Ambience.fadedNow = count
end

function Ambience.init()
	local started = os.clock()
	task.spawn(function()
		while true do
			task.wait(0.12)
			pcall(updateFade)
		end
	end)

	track("CK_Spin", function(inst)
		local saved = inst:GetAttribute("BasePivot")
		local base = if typeof(saved) == "CFrame" then saved elseif inst:IsA("Model") then inst:GetPivot() elseif inst:IsA("BasePart") then inst.CFrame else nil
		if base then
			table.insert(spins, { inst = inst, base = base, speed = tonumber(inst:GetAttribute("SpinSpeed")) or 1, axis = tostring(inst:GetAttribute("SpinAxis") or "Z") })
			Ambience.counts.spins = #spins
		end
	end)
	track("CK_Bob", function(inst)
		if inst:IsA("BillboardGui") then
			table.insert(bobs, inst)
			Ambience.counts.bobs = #bobs
		end
	end)
	track("CK_Float", function(inst)
		if inst:IsA("Model") then
			local saved = inst:GetAttribute("BasePivot")
			table.insert(floats, { model = inst, base = if typeof(saved) == "CFrame" then saved else inst:GetPivot(), phase = tonumber(inst:GetAttribute("FloatPhase")) or 0 })
			Ambience.counts.floats = #floats
		end
	end)
	track("CK_Rainbow", function(inst)
		if inst:IsA("BasePart") then
			table.insert(rainbows, inst)
		end
	end)

	-- crop models are replaced by the server on every growth stage: greet each new one with a pop
	local function watchPlots(plots: Instance)
		plots.DescendantAdded:Connect(function(d)
			if d.Name == "Crop" and not Perf.lite and os.clock() - started > 4 then
				task.spawn(queuePop, d)
			end
		end)
	end
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		watchPlots(plots)
	else
		task.spawn(function()
			watchPlots(workspace:WaitForChild("Plots"))
		end)
	end

	-- pollen + drifting leaves around the camera while the sky is clear
	local air: Part = C.new("Part", {
		Name = "ClientAmbienceAir",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(70, 14, 70),
		Parent = workspace,
	})
	local pollen: ParticleEmitter = C.new("ParticleEmitter", {
		Name = "Pollen",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 250, 210)),
		LightEmission = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.22), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(0.4, 1.4),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.5, 0.15, 0.3),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Rate = 14,
		Parent = air,
	})
	local leaves: ParticleEmitter = C.new("ParticleEmitter", {
		Name = "Leaves",
		Texture = "rbxasset://textures/particles/SquareParticle.png",
		Color = ColorSequence.new(Color3.fromRGB(120, 200, 90), Color3.fromRGB(230, 200, 90)),
		Size = NumberSequence.new(0.22),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1), NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = Vector3.new(1.2, -0.4, 0.6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Rate = 3,
		Parent = air,
	})
	local function refreshAir()
		local clear = (State.weather.id == nil or State.weather.id == "GoldenHour") and not Perf.lite
		pollen.Enabled = clear
		leaves.Enabled = clear
	end
	State.onChanged(function(kind)
		if kind == "weather" then
			refreshAir()
		end
	end)
	refreshAir()

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local cam = cameraPos()
		if cam then
			air.CFrame = CFrame.new(cam + Vector3.new(0, 4, 0))
		end

		for i = #pops, 1, -1 do
			local p = pops[i]
			local a = (now - p.t0) / POP_TIME
			local baseScale = tonumber(p.model:GetAttribute("BaseScale")) or 1
			local ok = p.model.Parent ~= nil and pcall(p.model.ScaleTo, p.model, baseScale * Ambience.popScale(a))
			if not ok or a >= 1 then
				table.remove(pops, i)
			end
		end

		for _, b in bobs do
			b.StudsOffset = Vector3.new(0, math.sin(now * 2.2) * 0.6, 0)
		end

		-- the rest runs at ~30 Hz (10 Hz on lite devices): nobody can tell and it spares the CFrame writes
		acc += dt
		if acc < 1 / Perf.budget(Perf.lite).floatHz then
			return
		end
		acc = 0
		for _, s in spins do
			local angle = now * s.speed
			local inst = s.inst
			if not inst.Parent then
				continue
			end
			if inst:IsA("Model") then
				inst:PivotTo(s.base * CFrame.Angles(0, 0, angle))
			elseif s.axis == "World" then
				(inst :: BasePart).CFrame = CFrame.new(s.base.Position) * CFrame.Angles(0, angle, 0) * s.base.Rotation
			else
				(inst :: BasePart).CFrame = s.base * CFrame.Angles(angle, 0, 0)
			end
		end
		for _, f in floats do
			if f.model.Parent then
				local t = now * 0.25 + f.phase
				f.model:PivotTo(f.base * CFrame.new(math.sin(t * 0.6) * 14, math.sin(t) * 5, math.cos(t * 0.45) * 14))
			end
		end
		if #rainbows > 0 then
			removeFrom(rainbows, function(p)
				return p.Parent == nil
			end)
			for i, p in rainbows do
				p.Color = Color3.fromHSV((now * 0.4 + i * 0.07) % 1, 0.7, 1)
			end
		end
	end)

	-- forget things the server removed
	task.spawn(function()
		while true do
			task.wait(10)
			removeFrom(spins, function(s)
				return s.inst.Parent == nil
			end)
			removeFrom(bobs, function(b)
				return b.Parent == nil
			end)
			removeFrom(floats, function(f)
				return f.model.Parent == nil
			end)
		end
	end)
end

return Ambience
