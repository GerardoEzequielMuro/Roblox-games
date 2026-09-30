--!strict
-- Hatch cinematic. The egg drops in, shakes harder and harder while cracks glow in the
-- colour of what is inside, bursts into shards and confetti, and the pet spins in with its
-- rarity ribbon, odds and a NEW! badge for first discoveries. Legendary and above get a
-- coloured flash, a sunburst, a screen shake and extra confetti waves.
-- Supports 1 or 3 eggs at once, a faster "auto" variant, and a queue.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Quality = require(script.Parent.Parent.Quality)

local HatchCinematic = {}

type Result = { uid: string, id: string, tier: number, chance: number, rarity: string, new: boolean? }
type Job = { egg: string, results: { Result }, auto: boolean }

local queue: { Job } = {}
local playing = false
local onBusy: (boolean) -> () = function(_) end
local onBurst: (string) -> () = function(_) end
-- RenderStepped connections of the job being played (dropped if the job errors out)
local active: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(active, conn)
	return conn
end

local function dropConnections()
	for _, c in active do
		c:Disconnect()
	end
	table.clear(active)
end

function HatchCinematic.setBusyCallback(fn: (boolean) -> ())
	onBusy = fn
end

-- Called with the egg id at the moment the shells burst (world egg reacts).
function HatchCinematic.setBurstCallback(fn: (string) -> ())
	onBurst = fn
end

local SECRET = Color3.fromRGB(170, 60, 255)
local EGG_R = Vector3.new(2.75, 3.5, 2.75)

local function rarityColor(rarity: string): Color3
	return if rarity == "Secret" then SECRET else Palette.rarity(rarity)
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- Point on the front of the egg shell (the camera looks from -Z).
local function shellPoint(x: number, y: number): Vector3
	local k = math.max(0.02, 1 - (x / EGG_R.X) ^ 2 - (y / EGG_R.Y) ^ 2)
	return Vector3.new(x, y, -EGG_R.Z * math.sqrt(k) - 0.04)
end

local CRACKS = {
	{ { -1.5, 0.9 }, { -0.8, 0.3 }, { -0.2, 1.0 }, { 0.5, 0.2 }, { 1.1, 0.9 }, { 1.7, 0.4 } },
	{ { -1.0, -0.9 }, { -0.3, -0.3 }, { 0.4, -1.1 }, { 1.0, -0.5 } },
	{ { -0.2, 1.0 }, { 0.1, 1.9 }, { -0.3, 2.5 } },
}

type EggRig = { model: Model, cracks: { BasePart } }

local function buildEggModel(eggId: string, glow: Color3): EggRig
	local egg = Formulas.EggById[eggId]
	local model = Instance.new("Model")
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Size = EGG_R * 2
	shell.Color = Palette.rgb(egg.color)
	shell.Anchored = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	shell.Parent = model
	model.PrimaryPart = shell
	local rng = Random.new(7)
	for i = 1, 8 do
		local a = i * 2.2
		local y = rng:NextNumber(-2, 2.2)
		local rr = 2.75 * math.sqrt(1 - (y / 3.5) ^ 2)
		local spot = Instance.new("Part")
		spot.Shape = Enum.PartType.Ball
		spot.Size = Vector3.one * rng:NextNumber(1, 1.6)
		spot.Color = Palette.rgb(egg.spots)
		spot.Anchored = true
		spot.CFrame = CFrame.new(math.cos(a) * rr, y, math.sin(a) * rr)
		spot.Parent = model
	end
	local cracks: { BasePart } = {}
	for _, line in CRACKS do
		for i = 1, #line - 1 do
			local a = shellPoint(line[i][1], line[i][2])
			local b = shellPoint(line[i + 1][1], line[i + 1][2])
			local seg = Instance.new("Part")
			seg.Name = "Crack"
			seg.Anchored = true
			seg.Material = Enum.Material.Neon
			seg.Color = glow
			seg.Size = Vector3.new(0.16, 0.16, (a - b).Magnitude + 0.1)
			seg.CFrame = CFrame.lookAt((a + b) / 2, b)
			seg.Transparency = 1
			seg.Parent = model
			table.insert(cracks, seg)
		end
	end
	return { model = model, cracks = cracks }
end

local function viewport(model: Model, dist: number): (ViewportFrame, Camera)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(200, 200, 215)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -2, 1.5)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1, -dist), Vector3.new(0, 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	return vp, cam
end

-- A turning fan of soft rays (rarity shine behind the pet, sunburst behind the row).
local function rays(parent: Instance, size: number, count: number, width: number, color: Color3, alpha: number, z: number): Frame
	local burst = Theme.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	}) :: Frame
	for k = 0, count - 1 do
		Theme.new("Frame", {
			Size = UDim2.new(0, width, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = k * (180 / count),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = burst,
		}, {
			Theme.new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, alpha), NumberSequenceKeypoint.new(1, 1) }),
			}),
		})
	end
	return burst
end

---------------------------------------------------------------------------
-- 2D confetti (one update loop per cinematic)
---------------------------------------------------------------------------
type Bit = { f: Frame, x: number, y: number, vx: number, vy: number, vr: number, life: number, t: number }

local function confetti(layer: Frame, bits: { Bit }, at: Vector2, colors: { Color3 }, count: number, power: number)
	local s = Root.scale
	for _ = 1, math.ceil(count * Quality.particles) do
		local a = math.random() * math.pi * 2
		local sp = (0.35 + math.random() * 0.65) * power * s
		local w = math.random(7, 13) * s
		local f = Theme.new("Frame", {
			Size = UDim2.fromOffset(w, w * (0.5 + math.random() * 0.6)),
			Position = UDim2.fromOffset(at.X, at.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 8,
			Parent = layer,
		}, { Theme.corner(2) }) :: Frame
		table.insert(bits, { f = f, x = at.X, y = at.Y, vx = math.cos(a) * sp, vy = math.sin(a) * sp - 260 * s, vr = math.random(-540, 540), life = 0.9 + math.random() * 0.6, t = 0 })
	end
end

local function stepConfetti(bits: { Bit }, dt: number)
	local g = 1100 * Root.scale
	for i = #bits, 1, -1 do
		local b = bits[i]
		b.t += dt
		if b.t >= b.life then
			b.f:Destroy()
			table.remove(bits, i)
		else
			b.vy += g * dt
			b.vx *= 1 - math.min(1, dt * 1.2)
			b.x += b.vx * dt
			b.y += b.vy * dt
			b.f.Position = UDim2.fromOffset(b.x, b.y)
			b.f.Rotation += b.vr * dt
			local left = b.life - b.t
			if left < 0.3 then
				b.f.BackgroundTransparency = 1 - left / 0.3
			end
		end
	end
end

---------------------------------------------------------------------------
type Shard = { part: BasePart, v: Vector3, spin: CFrame }
type Slot = {
	frame: Frame,
	holder: Frame,
	scale: UIScale,
	egg: EggRig,
	vp: ViewportFrame,
	cam: Camera,
	info: Frame,
	glow: Frame,
	color: Color3,
	order: number,
	shards: { Shard },
}

local function playJob(job: Job)
	local n = #job.results
	local auto = job.auto
	local overlay = Theme.new("TextButton", {
		Name = "Hatch",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 15, 35),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = Root.overlay,
	}) :: TextButton
	TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = if auto then 0.75 else 0.3 }):Play()
	local layer = Theme.new("Frame", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8, Parent = overlay }) :: Frame
	local row = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(n * 320, 450),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = overlay,
	}, { Theme.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) }) :: Frame
	Theme.new("UIScale", { Scale = Root.scale * (if auto then 0.7 else 1), Parent = row })

	local best = 1
	local bestColor = Color3.new(1, 1, 1)
	local slots: { Slot } = {}
	for i, r in job.results do
		local pet = Formulas.PetById[r.id]
		local rc = rarityColor(r.rarity)
		local order = Config.RarityByName[r.rarity].order
		if order > best then
			best = order
			bestColor = rc
		end
		local frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 440), LayoutOrder = i, Parent = row }) :: Frame
		local scale = Theme.new("UIScale", { Scale = 0.2, Parent = frame }) :: UIScale
		local glow = Theme.new("Frame", {
			Size = UDim2.fromOffset(210, 210),
			Position = UDim2.fromOffset(150, 150),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.lighten(rc, 0.25),
			BackgroundTransparency = 1,
			ZIndex = 1,
			Parent = frame,
		}, { Theme.corner(999) }) :: Frame
		local holder = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 300), ZIndex = 3, Parent = frame }) :: Frame
		local egg = buildEggModel(job.egg, Theme.lighten(rc, 0.35))
		local vp, cam = viewport(egg.model, 17)
		vp.ZIndex = 3
		vp.Parent = holder
		local info = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 130), Position = UDim2.fromOffset(0, 300), Visible = false, ZIndex = 5, Parent = frame }) :: Frame
		Theme.new("UIScale", { Parent = info })
		Theme.text({ Text = Lang.pet(pet.id, r.tier), Size = UDim2.fromOffset(300, 44), MaxTextSize = 38, Stroke = 3, ZIndex = 5, Parent = info })
		local ribbon = Theme.new("Frame", {
			Size = UDim2.fromOffset(230, 40),
			Position = UDim2.fromOffset(35, 46),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = info,
		}, { Theme.corner(20), Theme.stroke(3), Theme.gradient(Theme.lighten(rc, 0.3), Theme.darken(rc, 0.08)) })
		Theme.text({ Text = Lang.upper(Lang.rarity(r.rarity)), Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), MaxTextSize = 28, Stroke = 2.5, ZIndex = 6, Parent = ribbon })
		local stats = Theme.text({
			Text = Format.chance(r.chance) .. "  ·  " .. Lang.t("hatch.power", { n = Format.abbrev(Formulas.petPower(r.id, r.tier, #(Net.get("zones") or { 1 }))) }),
			Size = UDim2.fromOffset(300, 28),
			Position = UDim2.fromOffset(0, 92),
			TextColor3 = Theme.Yellow,
			MaxTextSize = 24,
			ZIndex = 5,
			Parent = info,
		})
		stats.AutoLocalize = false
		if r.new then
			local badge = Theme.new("Frame", {
				Name = "New",
				Size = UDim2.fromOffset(96, 40),
				Position = UDim2.fromOffset(226, 26),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 12,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Visible = false,
				ZIndex = 7,
				Parent = frame,
			}, { Theme.corner(14), Theme.stroke(3), Theme.gradient(Theme.lighten(Theme.Red, 0.25), Theme.Red), Theme.new("UIScale", {}) })
			Theme.text({ Key = "hatch.new", Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), MaxTextSize = 26, ZIndex = 8, Parent = badge })
		end
		table.insert(slots, { frame = frame, holder = holder, scale = scale, egg = egg, vp = vp, cam = cam, info = info, glow = glow, color = rc, order = order, shards = {} })
		task.delay((i - 1) * 0.07, function()
			TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
	end

	local bits: { Bit } = {}
	local alive = true
	local fxConn = track(RunService.RenderStepped:Connect(function(dt)
		stepConfetti(bits, dt)
	end))
	local function center(slot: Slot): Vector2
		return slot.holder.AbsolutePosition + slot.holder.AbsoluteSize / 2 - layer.AbsolutePosition
	end

	---------------------------------------------------------------------------
	-- Shake: wobble grows, cracks light up one by one, the glow behind the egg builds
	---------------------------------------------------------------------------
	Theme.play("hatch", 0.4)
	local shakeTime = if auto then 0.55 else 1.25
	local t0 = os.clock()
	local lit = 0
	local conn = track(RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local k = math.clamp(t / shakeTime, 0, 1)
		for i, s in slots do
			local amp = 0.06 + k * k * 0.42
			local wob = math.sin(t * (16 + k * 34) + i) * amp
			s.egg.model:PivotTo(CFrame.new(0, math.abs(wob) * 0.9 + math.abs(math.sin(t * 9 + i)) * k * 0.5, 0) * CFrame.Angles(math.sin(t * 23 + i) * amp * 0.25, 0, wob))
			local want = math.floor(k * 1.15 * #s.egg.cracks)
			for c = 1, math.min(want, #s.egg.cracks) do
				s.egg.cracks[c].Transparency = 0
			end
			s.glow.BackgroundTransparency = 1 - math.max(0, k - 0.35) * 0.95
			local g = 210 + k * 70 + math.sin(t * 20) * 8 * k
			s.glow.Size = UDim2.fromOffset(g, g)
		end
		local step = math.floor(k * 6)
		if step > lit then
			lit = step
			Theme.play("tap", 0.25, 0.8 + step * 0.12)
		end
	end))
	task.wait(shakeTime)
	conn:Disconnect()

	---------------------------------------------------------------------------
	-- Burst
	---------------------------------------------------------------------------
	local flashColor = if best >= 5 then Theme.lighten(bestColor, 0.55) else Color3.new(1, 1, 1)
	local flash = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = flashColor, BackgroundTransparency = if auto then 0.35 else 0, ZIndex = 50, Parent = overlay })
	TweenService:Create(flash, TweenInfo.new(if best >= 5 then 0.7 else 0.4), { BackgroundTransparency = 1 }):Play()
	if best >= 5 and not auto then
		local sun = rays(overlay, 1700, 9, 150, Theme.lighten(bestColor, 0.3), 0.72, 1)
		TweenService:Create(sun, TweenInfo.new(24, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundColor3 = Theme.darken(bestColor, 0.82), BackgroundTransparency = 0.18 }):Play()
	end
	onBurst(job.egg)

	local eggDef = Formulas.EggById[job.egg]
	local shellColor, spotColor = Palette.rgb(eggDef.color), Palette.rgb(eggDef.spots)
	local pets: { Model } = {}
	local offsets: { Vector3 } = {}
	local dists: { number } = {}
	for i, s in slots do
		s.egg.model:Destroy()
		local r = job.results[i]
		-- shell shards
		local rng = Random.new(i * 31)
		for k = 1, if auto then 6 else 11 do
			local shard: BasePart = Instance.new("WedgePart")
			shard.Anchored = true
			shard.Size = Vector3.new(rng:NextNumber(0.2, 0.35), rng:NextNumber(0.9, 1.7), rng:NextNumber(0.9, 1.7))
			shard.Color = if k % 4 == 0 then spotColor else shellColor
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 1), rng:NextNumber(-0.6, 0.3)).Unit
			shard.CFrame = CFrame.new(dir * 2) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
			shard.Parent = s.vp
			table.insert(s.shards, { part = shard, v = dir * rng:NextNumber(12, 22) + Vector3.new(0, 6, 0), spin = CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3)) })
		end
		local m = PetModel.build(r.id, r.tier, { lite = true })
		m.Parent = s.vp
		table.insert(pets, m)
		local cf, size = m:GetBoundingBox()
		local radius = size.Magnitude * 0.5
		table.insert(offsets, cf.Position)
		table.insert(dists, radius / math.tan(math.rad(s.cam.FieldOfView / 2)) * 0.96)
		-- rarity shine behind the pet
		local burst = rays(s.frame, 300, 6, 34, Theme.lighten(s.color, 0.35), 0.35, 0)
		burst.Position = UDim2.fromOffset(150, 150)
		TweenService:Create(burst, TweenInfo.new(9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		s.glow.BackgroundColor3 = s.color
		s.glow.BackgroundTransparency = 0.7
		s.glow.Size = UDim2.fromOffset(190, 190)
		Theme.new("UIStroke", { Thickness = 6, Color = Theme.lighten(s.color, 0.3), Transparency = 0.25, Parent = s.glow })
		TweenService:Create(s.glow, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.fromOffset(222, 222) }):Play()
		-- expanding ring
		local ring = Theme.new("Frame", { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(150, 150), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2, Parent = s.frame }, { Theme.corner(999) })
		local ringStroke = Theme.new("UIStroke", { Thickness = 10, Color = Theme.lighten(s.color, 0.45), Parent = ring })
		TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(420, 420) }):Play()
		TweenService:Create(ringStroke, TweenInfo.new(0.5), { Transparency = 1, Thickness = 1 }):Play()

		s.info.Visible = true
		Theme.pop(s.info, 1.5)
		local badge = s.frame:FindFirstChild("New") :: Frame?
		if badge then
			badge.Visible = true
			Theme.pop(badge, 2.4)
		end
		local colors = { s.color, Theme.lighten(s.color, 0.45), Color3.new(1, 1, 1), Theme.Yellow }
		confetti(layer, bits, center(s), colors, (if auto then 8 else 14) + s.order * (if auto then 2 else 5), 520 + s.order * 70)
	end
	Theme.play("buy", 0.5, 0.8 + best * 0.1)
	if best >= 5 then
		Theme.play("boom", if auto then 0.12 else 0.22, 1.25)
	end

	local spinStart = os.clock()
	local rowBase = row.Position
	local spin = track(RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - spinStart
		local e = backOut(math.clamp(t / 0.45, 0, 1))
		for i, m in pets do
			local s = slots[i]
			-- spins in, then sways
			local yaw = math.rad(24) + math.sin(t * 1.5) * 0.55 + (1 - math.clamp(t / 0.55, 0, 1)) ^ 2 * math.pi * 2
			m:PivotTo(CFrame.new(0, math.sin(t * 3) * 0.18, 0) * CFrame.Angles(0, yaw, 0))
			PetModel.updateRainbow(m, os.clock())
			local dist = dists[i] * (2.6 - 1.6 * e)
			local look = offsets[i]
			s.cam.CFrame = CFrame.lookAt(look + Vector3.new(0, dists[i] * 0.12, -dist), look)
			for k = #s.shards, 1, -1 do
				local sh = s.shards[k]
				sh.v += Vector3.new(0, -40, 0) * dt
				sh.part.CFrame = (sh.part.CFrame + sh.v * dt) * sh.spin
				if t > 0.8 then
					sh.part:Destroy()
					table.remove(s.shards, k)
				end
			end
		end
		if best >= 5 and not auto and t < 0.45 then
			local a = (1 - t / 0.45) * 14 * Root.scale
			row.Position = rowBase + UDim2.fromOffset((math.random() * 2 - 1) * a, (math.random() * 2 - 1) * a)
		else
			row.Position = rowBase
		end
	end))
	if best >= 5 and not auto then
		-- extra confetti waves for the big ones
		for wave = 1, if best >= 6 then 4 else 2 do
			task.delay(wave * 0.3, function()
				if not alive then
					return
				end
				for _, s in slots do
					if s.order >= 5 then
						confetti(layer, bits, center(s), { s.color, Theme.lighten(s.color, 0.5), Color3.new(1, 1, 1), Theme.Yellow }, 22, 760)
					end
				end
				Theme.play("tap", 0.25, 1.4 + wave * 0.1)
			end)
		end
	end

	local hold = if auto then 1.0 elseif best >= 5 then 3.4 else 2.1
	local skipped = false
	overlay.Activated:Connect(function()
		skipped = true
	end)
	local waited = 0
	while waited < hold and not (skipped and waited > 0.5) do
		waited += task.wait()
	end
	alive = false
	spin:Disconnect()
	fxConn:Disconnect()
	table.clear(active)
	local fade = TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = 1 })
	fade:Play()
	row.Visible = false
	layer.Visible = false
	fade.Completed:Wait()
	overlay:Destroy()
end

local function pump()
	if playing then
		return
	end
	playing = true
	onBusy(true)
	while #queue > 0 do
		local job = table.remove(queue, 1) :: Job
		local ok, err = pcall(function()
			playJob(job)
		end)
		if not ok then
			warn("[Hatch] cinematic error", err)
			dropConnections()
			for _, c in Root.overlay:GetChildren() do
				if c.Name == "Hatch" then
					c:Destroy()
				end
			end
		end
	end
	playing = false
	onBusy(false)
end

function HatchCinematic.play(eggId: string, results: { any }, auto: boolean?)
	if #results == 0 then
		return
	end
	-- auto-hatch jobs don't pile up: keep at most one waiting
	if auto and #queue > 0 then
		return
	end
	table.insert(queue, { egg = eggId, results = results :: any, auto = auto == true })
	task.spawn(pump)
end

function HatchCinematic.isPlaying(): boolean
	return playing
end

return HatchCinematic
