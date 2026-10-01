--!strict
-- Feedback ("juice") for the local player. Everything here is local and cosmetic:
--   * checkpoint pads: the ones you've reached turn green and raise their flag, the next one gets
--     a light beacon so you always know where to go;
--   * reaching a checkpoint: shockwave ring + sparkle burst on the pad, a small camera FOV kick;
--   * dying: red flash, a puff where you fell, a short camera shake; respawning: a white ring;
--   * a shield absorbing a hit: blue flash + ring; arriving through a portal: a white flash;
--   * coins burst into sparkles; kill bricks pulse so they never read as a platform; conveyor and
--     wind chevrons run; the lobby balloons bob; the rainbow glow cycles; jump effects.
-- The world is streamed (only the stretch of tower around you is loaded), so every list here
-- follows CollectionService added / removed signals and nothing assumes a part exists.
-- One RenderStep does all the per-frame work, and only for things near the camera.
-- No sounds: the game ships without uploaded assets.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Quality = require(game:GetService("ReplicatedStorage").Shared.Quality)
local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Rules = require(ReplicatedStorage.Shared.Rules)
local FeelMath = require(ReplicatedStorage.Shared.FeelMath)
local Net = require(script.Parent.Parent.Net)
local Sfx = require(script.Parent.Parent.Sfx)

local Juice = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local DONE = Color3.fromRGB(50, 215, 80)
local DONE_REST = Color3.fromRGB(140, 215, 150) -- rest pads you have passed: a paler green
local BASE_FOV = 70
local NEAR = Quality.NEAR -- studs from the camera within which cosmetic loops run
local lite = false -- lite profile: scenery particles and lights off, shorter radius

local player = Players.LocalPlayer
local enabled = true -- Settings -> Visual effects

local fxFolder: Folder? = nil
local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "LocalFx"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function ghost(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Parent = folder()
	return p
end

-- Cheap on mobile: at most CAP rings + bursts alive at once (fewer in the lite profile); extra
-- ones are dropped, the newest are what the player is looking at anyway.
local liveFx = 0
local function fxCap(): number
	return if lite then 5 else 12
end

-- Flat ring that grows and fades (a cylinder lying on the pad).
local function shockwave(pos: Vector3, color: Color3, from: number, to: number, duration: number)
	if FeelMath.budget(liveFx, 1, fxCap()) < 1 then
		return
	end
	liveFx += 1
	local ring = ghost(Vector3.new(0.3, from, from), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, to, to),
		Transparency = 1,
	}):Play()
	task.delay(duration + 0.1, function()
		liveFx -= 1
		ring:Destroy()
	end)
end
Juice.shockwave = shockwave

local function burst(pos: Vector3, texture: string, colors: ColorSequence, count: number, speed: number, size: number, life: number, gravity: number)
	if FeelMath.budget(liveFx, 1, fxCap()) < 1 then
		return
	end
	liveFx += 1
	if lite then
		count = math.ceil(count * 0.6)
	end
	local anchor = ghost(Vector3.new(1, 1, 1), CFrame.new(pos), Color3.new())
	anchor.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -gravity, 0)
	e.Size = NumberSequence.new(size, size * 0.15)
	e.LightEmission = 0.7
	e.Color = colors
	e.Parent = anchor
	e:Emit(count)
	task.delay(life + 0.3, function()
		liveFx -= 1
		anchor:Destroy()
	end)
end

-- Settings -> Visual effects. Off = no shockwaves / flashes / camera kicks, and the scenery's
-- particle emitters and point lights are switched off locally (the cheap way to help a slow phone).
-- The lite profile keeps what belongs to an obstacle (lava embers, wind streaks): that is
-- information, not dressing.
local function inStage(inst: Instance): boolean
	local a = inst.Parent
	while a and a ~= Workspace do
		if a:GetAttribute("Kind") ~= nil then
			return true
		end
		a = a.Parent
	end
	return false
end

local function applyToScenery(inst: Instance)
	if inst:IsA("ParticleEmitter") then
		inst.Enabled = enabled and not (lite and not inStage(inst))
	elseif inst:IsA("PointLight") then
		inst.Enabled = enabled and not (lite and not inStage(inst))
	end
end

local function refreshScenery()
	for _, name in { "Decor", "Towers", "Lobby" } do
		local root = Workspace:FindFirstChild(name)
		if root then
			for _, d in root:GetDescendants() do
				applyToScenery(d)
			end
		end
	end
end

function Juice.setEffects(on: boolean)
	enabled = on
	refreshScenery()
end

-- Lite profile (Quality.isLite): the hit feedback stays, the scenery dressing goes.
function Juice.setLite(on: boolean)
	lite = on
	NEAR = if on then Quality.NEAR_LITE else Quality.NEAR
	refreshScenery()
end

---------------------------------------------------------------------------------------------
-- screen flash (own ScreenGui under the HUD, covers the whole screen)
---------------------------------------------------------------------------------------------
local flashFrame: Frame? = nil
local function flash(color: Color3, from: number, duration: number)
	local f = flashFrame
	if not f then
		local gui = Instance.new("ScreenGui")
		gui.Name = "SkyTowerFx"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = -1
		gui.Parent = player:WaitForChild("PlayerGui")
		local frame = Instance.new("Frame")
		frame.Name = "Flash"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Active = false
		frame.Parent = gui
		f = frame
		flashFrame = frame
	end
	local frame = f :: Frame
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = from
	TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end
Juice.flash = flash

---------------------------------------------------------------------------------------------
-- camera: FOV kick + shake
---------------------------------------------------------------------------------------------
local shakeUntil = 0
local shakePower = 0
local shakeDur = 0.35

-- Camera micro-shake for big moments. Off with "Visual effects" (reduced motion); a bigger shake
-- never gets replaced by a smaller one that is still running.
function Juice.shake(power: number, duration: number?)
	if not enabled or power <= 0 then
		return
	end
	local dur = duration or 0.35
	local now = os.clock()
	if now < shakeUntil and FeelMath.shake(shakePower, shakeDur - (shakeUntil - now), shakeDur) > power then
		return
	end
	shakePower = power
	shakeDur = dur
	shakeUntil = now + dur
end
local function fovKick(amount: number)
	local cam = Workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	cam.FieldOfView = BASE_FOV + amount
	TweenService:Create(cam, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = BASE_FOV }):Play()
end

-- A list of tagged parts that follows streaming (parts come and go).
local function tracked(tagName: string, onAdded: ((BasePart) -> ())?): { BasePart }
	local list: { BasePart } = {}
	local function add(inst: Instance)
		if inst:IsA("BasePart") then
			table.insert(list, inst)
			if onAdded then
				onAdded(inst)
			end
		end
	end
	for _, inst in CollectionService:GetTagged(tagName) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(inst)
		local i = table.find(list, inst :: any)
		if i then
			list[i] = list[#list]
			list[#list] = nil
		end
	end)
	return list
end

-- Top-centre of the pad of global stage g, from the layout (the pad itself may not be streamed in).
local maps: { [number]: Layout.Map } = {}
local function mapOf(tower: number): Layout.Map
	local m = maps[tower]
	if not m then
		m = Layout.generate(Config.MapSeed, tower)
		maps[tower] = m
	end
	return m
end
local function padTop(g: number): Vector3
	local spot = Rules.padOf(Layout :: any, g)
	local v = mapOf(spot.tower).pads[spot.pad]
	return Vector3.new(v.x, v.y, v.z)
end
Juice.padTop = padTop

---------------------------------------------------------------------------------------------
function Juice.init()
	-- pads, flags, centre dots ------------------------------------------------------------------
	-- keyed by stage; the original colour is remembered the first time a part streams in
	local pads: { [number]: BasePart } = {}
	local flags: { [number]: BasePart } = {}
	local dots: { [number]: BasePart } = {}
	local baseColor: { [BasePart]: Color3 } = {}
	local dirty = true
	local function keep(map: { [number]: BasePart })
		return function(inst: BasePart)
			local k = inst:GetAttribute("Stage")
			if type(k) == "number" then
				map[k] = inst
				baseColor[inst] = inst.Color
				dirty = true
				inst.Destroying:Once(function()
					if map[k] == inst then
						map[k] = nil
					end
					baseColor[inst] = nil
				end)
			end
		end
	end
	tracked("Checkpoint", keep(pads))
	tracked("Flag", keep(flags))
	tracked("PadDot", keep(dots))

	-- beacon on the next pad: a soft column of light + a ring that breathes
	local beam = ghost(Vector3.new(46, 3.2, 3.2), CFrame.new(0, -500, 0), Color3.fromRGB(255, 250, 190))
	beam.Shape = Enum.PartType.Cylinder
	beam.Transparency = 0.72
	beam.Name = "NextBeacon"
	local ring = ghost(Vector3.new(0.25, 14, 14), CFrame.new(0, -500, 0), Color3.fromRGB(255, 250, 190))
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.5
	ring.Name = "NextRing"
	local beaconAt: Vector3? = nil

	local shownAt = -1
	local function paint(k: number, at: number, animate: boolean)
		local reached = k >= 1 and k <= at
		local pad = pads[k]
		if pad then
			local rest = pad:GetAttribute("Save") == false
			pad.Color = if reached then (if rest then DONE_REST else DONE) else baseColor[pad] or pad.Color
		end
		local dot = dots[k]
		if dot then
			dot.Color = if reached then DONE else baseColor[dot] or dot.Color
		end
		local flag = flags[k]
		if flag then
			local target = flag:GetAttribute(if reached then "High" else "Low")
			flag.Color = if reached then DONE else baseColor[flag] or flag.Color
			if typeof(target) == "CFrame" then
				if animate and reached and k == at then
					TweenService:Create(flag, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = target }):Play()
				else
					flag.CFrame = target
				end
			end
		end
	end
	local function showProgress(at: number, animate: boolean)
		if dirty then
			-- something streamed in: repaint everything that is loaded
			dirty = false
			for k in pads do
				paint(k, at, false)
			end
			for k in flags do
				paint(k, at, false)
			end
			for k in dots do
				paint(k, at, false)
			end
		elseif at ~= shownAt then
			for k = math.max(1, math.min(at, shownAt)), math.max(at, shownAt) do
				paint(k, at, animate)
			end
		end
		shownAt = at
		-- the next pad: across a portal it is the first pad of the next tower, and only once you
		-- stand on that tower's base
		local s = Net.state
		local nextStage = at + 1
		if nextStage <= Layout.TOTAL and Rules.canReach(Layout :: any, at, nextStage, 1, s.base == true) then
			local top = padTop(nextStage)
			beaconAt = top
			beam.CFrame = CFrame.new(top + Vector3.new(0, 23, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		else
			beaconAt = nil
			beam.CFrame = CFrame.new(0, -500, 0)
			ring.CFrame = CFrame.new(0, -500, 0)
		end
	end
	local function currentAt(): number
		local s = Net.state
		return if type(s.at) == "number" then s.at elseif type(s.stage) == "number" then s.stage else 0
	end
	Net.changed:Connect(function()
		showProgress(currentAt(), true)
	end)
	showProgress(currentAt(), false)

	-- checkpoint reached -----------------------------------------------------------------------
	Net.on("Celebrate", function(data: { [string]: any })
		local k = tonumber(data.stage) or 0
		if not enabled or k <= 0 then
			return
		end
		local top = padTop(k) + Vector3.new(0, 0.2, 0)
		local theme = Config.theme(Layout.towerOf(k), Layout.themeFor(k))
		local big = data.world ~= nil or k % Layout.STAGES == 0
		shockwave(top, Color3.new(1, 1, 1), 4, if big then 46 else 28, 0.55)
		task.delay(0.12, function()
			shockwave(top, theme.accent, 4, if big then 60 else 36, 0.7)
		end)
		burst(top + Vector3.new(0, 1.5, 0), SPARKLES, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.4, theme.accent),
			ColorSequenceKeypoint.new(1, DONE),
		}), if big then 70 else 36, if big then 34 else 24, 1.1, 1.2, 45)
		fovKick(if big then 12 else 7)
		if big then
			Juice.shake(0.3, 0.4)
		end
		Sfx.play(if big then "worldUp" else "checkpoint")
	end)
	Net.on("TowerEnter", function()
		if enabled then
			flash(Color3.new(1, 1, 1), 0.15, 0.9)
			fovKick(16)
		end
	end)
	Net.on("Shield", function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and enabled then
			flash(Color3.fromRGB(120, 170, 255), 0.6, 0.5)
			shockwave(root.Position - Vector3.new(0, 2, 0), Color3.fromRGB(120, 170, 255), 3, 18, 0.5)
		end
	end)

	-- coins --------------------------------------------------------------------------------------
	local coinById: { [number]: BasePart } = {}
	tracked("Coin", function(inst)
		local id = inst:GetAttribute("CoinId")
		if type(id) == "number" then
			coinById[id] = inst
			inst.Destroying:Once(function()
				if coinById[id] == inst then
					coinById[id] = nil
				end
			end)
		end
	end)
	Net.on("CoinCollected", function(id: number)
		local coin = coinById[id]
		if coin and enabled then
			burst(coin.Position, SPARKLES, ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 180, 40)), 16, 14, 0.8, 0.7, 30)
		end
		Sfx.play("coin")
	end)

	-- death / respawn / jump effect -----------------------------------------------------------------
	local function onCharacter(char: Model)
		local hum = char:WaitForChild("Humanoid", 10)
		local root = char:WaitForChild("HumanoidRootPart", 10)
		if not hum or not root or not hum:IsA("Humanoid") or not root:IsA("BasePart") then
			return
		end
		if enabled then
			-- arrival ring (first spawn and every respawn)
			task.delay(0.15, function()
				if root.Parent then
					shockwave(root.Position - Vector3.new(0, 2.6, 0), Color3.fromRGB(200, 240, 255), 3, 16, 0.5)
				end
			end)
		end
		hum.Died:Once(function()
			if not enabled then
				return
			end
			local pos = root.Position
			flash(Color3.fromRGB(255, 40, 60), 0.55, 0.6)
			burst(pos, SMOKE, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 220)), 14, 9, 3.2, 0.9, -4)
			burst(pos, SPARKLES, ColorSequence.new(Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 120)), 26, 26, 0.9, 0.8, 60)
			Juice.shake(0.45, 0.35)
			Sfx.play("death")
		end)
		-- lounge jump effects: a ring or a puff of stars under your feet on every jump
		hum.StateChanged:Connect(function(_, new)
			if new ~= Enum.HumanoidStateType.Jumping or not enabled then
				return
			end
			local fx = hum:GetAttribute("JumpFx")
			if fx == "jumpfx_ring" then
				shockwave(root.Position - Vector3.new(0, 2.6, 0), Color3.new(1, 1, 1), 2, 11, 0.4)
			elseif fx == "jumpfx_stars" then
				burst(root.Position - Vector3.new(0, 2.4, 0), SPARKLES, ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 255, 255)), 12, 10, 0.8, 0.6, 20)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- per-frame: beacon pulse, kill-brick pulse, running chevrons, camera shake, balloons, rainbow ---
	local kills: { BasePart } = {}
	tracked("Kill", function(inst)
		-- lava keeps its own colour; spinner bars and strips pulse
		if inst.Name ~= "Lava" then
			table.insert(kills, inst)
			inst.Destroying:Once(function()
				local i = table.find(kills, inst)
				if i then
					kills[i] = kills[#kills]
					kills[#kills] = nil
				end
			end)
		end
	end)
	local hot = Color3.fromRGB(255, 130, 110)

	-- conveyor / wind chevrons: a running light in the push direction
	local arrows = tracked("BeltArrow")
	local arrowBase: { [BasePart]: Color3 } = {}
	local arrowLit = Color3.fromRGB(255, 255, 210)
	local arrowStep = -1

	type Bobber = { model: Model, home: CFrame, phase: number }
	local bobbers: { Bobber } = {}
	task.spawn(function()
		local deco = Workspace:WaitForChild("Decor", 30)
		local lobby = deco and deco:WaitForChild("LobbyScenery", 30)
		if lobby then
			local function add(m: Instance)
				local phase = m:GetAttribute("Bob")
				if m:IsA("Model") and type(phase) == "number" then
					table.insert(bobbers, { model = m, home = m:GetPivot(), phase = phase })
				end
			end
			for _, m in lobby:GetChildren() do
				add(m)
			end
			lobby.ChildAdded:Connect(add)
		end
	end)

	-- effects that arrive while "Visual effects" is off stay off
	for _, name in { "Decor", "Towers", "Lobby" } do
		task.spawn(function()
			local root = Workspace:WaitForChild(name, 60)
			if root then
				root.DescendantAdded:Connect(function(d)
					if not enabled or lite then
						applyToScenery(d)
					end
				end)
			end
		end)
	end

	local slowAcc = 0
	RunService:BindToRenderStep("SkyTowerJuice", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local t = os.clock()
		local cam = Workspace.CurrentCamera
		if beaconAt then
			local s = 13 + math.sin(t * 3) * 2.2
			ring.Size = Vector3.new(0.25, s, s)
			ring.CFrame = CFrame.new(beaconAt + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Transparency = 0.45 + math.sin(t * 3) * 0.2
			beam.Transparency = 0.74 + math.sin(t * 2) * 0.08
		end
		if cam and t < shakeUntil then
			local k = FeelMath.shake(shakePower, shakeDur - (shakeUntil - t), shakeDur)
			cam.CFrame *= CFrame.Angles((math.random() - 0.5) * 0.06 * k, (math.random() - 0.5) * 0.06 * k, 0)
		end
		slowAcc += dt
		if slowAcc < 1 / 12 or not cam then
			return
		end
		slowAcc = 0
		if dirty then
			showProgress(currentAt(), false)
		end
		local camPos = cam.CFrame.Position
		local near2 = NEAR * NEAR
		local pulse = 0.5 + 0.5 * math.sin(t * 5)
		local color = Config.KillColor:Lerp(hot, pulse * 0.75)
		for _, k in kills do
			local d = k.Position - camPos
			if d.X * d.X + d.Y * d.Y + d.Z * d.Z < near2 then
				k.Color = color
			end
		end
		local step = math.floor(t * 6) % 3
		if step ~= arrowStep then
			arrowStep = step
			for _, a in arrows do
				local d = a.Position - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z < near2 then
					local base = arrowBase[a]
					if not base then
						base = a.Color
						arrowBase[a] = base
						a.Destroying:Once(function()
							arrowBase[a] = nil
						end)
					end
					a.Color = if a:GetAttribute("Order") == step then arrowLit else base:Lerp(Color3.new(0, 0, 0), 0.12)
				end
			end
		end
		for i = #bobbers, 1, -1 do
			local b = bobbers[i]
			if b.model.Parent then
				b.model:PivotTo(b.home + Vector3.new(0, math.sin(t * 0.5 + b.phase * 2) * 3, 0))
			else
				table.remove(bobbers, i)
			end
		end
		-- rainbow glow (the stage-700 gift) on any character near the camera
		for _, other in Players:GetPlayers() do
			local char = other.Character
			local glow = char and char:FindFirstChild("SkyGlow")
			if glow and glow:IsA("Highlight") and glow:GetAttribute("Rainbow") then
				local c = Color3.fromHSV((t * 0.25) % 1, 0.75, 1)
				glow.FillColor = c
				glow.OutlineColor = c
			end
		end
	end)
end

return Juice
