--!strict
-- Builds the world in code from the pure Layout.
--   buildLobby()   : the lobby island (once)
--   buildTower(t)  : one of the ten towers: core pillar, 100 stages, checkpoint pads, milestone
--                    banners, the shop at every world entrance, the summit room with its portal and
--                    gift, the base island (towers 2..10) and the scenery. Towers 2..10 are built
--                    and destroyed on demand by server/Towers.luau.
-- Runtime behaviour (moving parts, kill touches, fading platforms, lasers...) lives in
-- Obstacles.luau and is driven by CollectionService tags + attributes set here.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local TowerStyle = require(ReplicatedStorage.Shared.TowerStyle)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Scenery = require(script.Parent.Scenery)

local StageGenerator = {}

-- Something the player can activate: `kind` = shop | lounge | portal | home | rebirth | stall.
export type Prompt = { kind: string, id: string, prompt: ProximityPrompt }

export type Tower = {
	tower: number,
	map: Layout.Map,
	folder: Folder,
	pads: { [number]: BasePart }, -- by GLOBAL stage (tower 1 also has pad 0)
	padCFrames: { [number]: CFrame }, -- where to put a character standing on that pad
	baseCFrame: CFrame, -- standing on pad 0 (the lobby start pad / the tower's base island)
	prompts: { Prompt },
	portal: BasePart?, -- walk into it: next tower
}

export type Lobby = {
	lobbySpawn: CFrame,
	board: BasePart,
	fastBoard: BasePart,
	stageBoard: BasePart,
	stalls: { [string]: ProximityPrompt },
}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

---------------------------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------------------------
local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, diameter: number, height: number, center: Vector3, color: Color3, material: Enum.Material?): Part
	local p = newPart(parent, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function tag(inst: Instance, name: string)
	CollectionService:AddTag(inst, name)
end

local function billboard(parent: BasePart, text: string, sizeStuds: Vector2, color: Color3, maxDistance: number, offsetY: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(sizeStuds.X, sizeStuds.Y)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = maxDistance
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Adornee = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(30, 30, 50)
	label.Parent = bb
	bb.Parent = parent
	return bb
end

-- World text is localized on each client (client/World/WorldText.luau): the label keeps the English
-- text as a fallback and carries the key (+ JSON args) as attributes.
local function loc(label: Instance, key: string, args: { [string]: any }?)
	label:SetAttribute("LocKey", key)
	if args then
		label:SetAttribute("LocArgs", HttpService:JSONEncode(args))
	end
	if label:IsA("TextLabel") then
		label.Text = Locale.t("en", key, args)
	end
end
StageGenerator.loc = loc

local function locPrompt(prompt: ProximityPrompt, actionKey: string, objectKey: string)
	prompt:SetAttribute("LocAction", actionKey)
	prompt:SetAttribute("LocObject", objectKey)
	prompt.ActionText = Locale.t("en", actionKey)
	prompt.ObjectText = Locale.t("en", objectKey)
end

local function surfaceText(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?): TextLabel
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new()
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = sg
	sg.Parent = parent
	return label
end

-- CFrame of a slab whose TOP is at yRel, centred at (s, lat), facing along the stage.
local function stageCF(st: Layout.Stage, s: number, lat: number, yTop: number, thick: number): CFrame
	local x, y, z = Layout.toWorld(st, s, lat, yTop)
	local pos = Vector3.new(x, y - thick / 2, z)
	return CFrame.lookAt(pos, pos + Vector3.new(st.dirX, 0, st.dirZ))
end

local function latVector(st: Layout.Stage): Vector3
	local x0, _, z0 = Layout.toWorld(st, 0, 0, 0)
	local x1, _, z1 = Layout.toWorld(st, 0, 1, 0)
	return Vector3.new(x1 - x0, 0, z1 - z0)
end

local function darker(c: Color3): Color3
	return c:Lerp(Color3.new(0, 0, 0), 0.35)
end

local function vec(v: Layout.Vec): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

local function prompt(parent: Instance, actionKey: string, objectKey: string, hold: number, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	locPrompt(p, actionKey, objectKey)
	p.HoldDuration = hold
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------------------------
-- surfaces (nodes) and hazards
---------------------------------------------------------------------------------------------
local ICE = PhysicalProperties.new(0.9, 0, 0, 100, 1)

-- Per-stage random stream for purely visual choices (never touches the layout).
local dressRng: Layout.Rng = Layout.newRng(1)

-- A glyph painted on top of a special platform so its behaviour reads before you step on it:
-- arrows on movers, an hourglass on the ones that fade, "down" arrows on the ones that drop.
local function topIcon(part: BasePart, text: string, color: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Icon"
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 18
	sg.LightInfluence = 0
	sg.MaxDistance = 110
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.8, 0.8)
	label.Position = UDim2.fromScale(0.1, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0.1
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.fromRGB(30, 30, 50)
	label.Parent = sg
	sg.Parent = part
end

-- Track of a moving platform: shows where it travels, with a glowing stop at each end.
local function moverRails(model: Instance, part: BasePart, axisIsY: boolean, amp: number, accent: Color3)
	local size = part.Size
	local dark = Color3.fromRGB(55, 58, 72)
	if axisIsY then
		for _, side in { -1, 1 } do
			local x = side * (size.X / 2 + 0.45)
			Scenery.deco(model, Vector3.new(0.45, amp * 2 + size.Y + 1, 0.45), part.CFrame * CFrame.new(x, 0, 0), dark, Enum.Material.Metal).Name = "Rail"
			for _, e in { -1, 1 } do
				Scenery.deco(model, Vector3.new(0.8, 0.5, 0.8), part.CFrame * CFrame.new(x, e * (amp + size.Y / 2 + 0.5), 0), accent, Enum.Material.Neon).Name = "RailStop"
			end
		end
	else
		local y = -size.Y / 2 - 0.45
		Scenery.deco(model, Vector3.new(amp * 2 + size.X, 0.4, 0.6), part.CFrame * CFrame.new(0, y, 0), dark, Enum.Material.Metal).Name = "Rail"
		for _, e in { -1, 1 } do
			Scenery.deco(model, Vector3.new(0.6, 1.1, 1.1), part.CFrame * CFrame.new(e * (amp + size.X / 2), y, 0), accent, Enum.Material.Neon).Name = "RailStop"
		end
	end
end

local function buildNode(st: Layout.Stage, n: Layout.Node, model: Model, theme: Config.Theme, i: number): BasePart
	local cf = stageCF(st, n.s, n.lat, n.y, n.thick)
	local size = Vector3.new(n.width, n.thick, n.len)
	local color = if i % 2 == 0 then theme.alt else theme.platform
	if n.kind == "truss" then
		local bottom = n.yBottom or 0
		local height = math.max(2, math.ceil((n.y - bottom) / 2) * 2)
		local t = Instance.new("TrussPart")
		t.Anchored = true
		t.Size = Vector3.new(2, height, 2)
		local x, y, z = Layout.toWorld(st, n.s, n.lat, n.y - height / 2)
		t.CFrame = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x + st.dirX, y, z + st.dirZ))
		t.Color = theme.accent
		t.Material = Enum.Material.Metal
		t.Parent = model
		return t
	end
	local part = newPart(model, size, cf, color, theme.material)
	if n.kind == "platform" then
		Scenery.dressPlatform(model, part, theme, st.tower, st.theme, dressRng)
	elseif n.kind == "beam" then
		part.Color = theme.accent
		part.Material = Enum.Material.SmoothPlastic
	elseif n.kind == "ledge" then
		part.Color = theme.accent
	elseif n.kind == "moving" then
		-- lightened so an orange / pink accent can never be mistaken for a red kill brick
		part.Color = theme.accent:Lerp(Color3.new(1, 1, 1), 0.3)
		part.Material = Enum.Material.SmoothPlastic
		tag(part, "Mover")
		local axis = if n.moveAxis == "y" then Vector3.yAxis else latVector(st)
		part:SetAttribute("Axis", axis)
		part:SetAttribute("Amp", n.moveAmp or 4)
		part:SetAttribute("Period", n.movePeriod or 4)
		part:SetAttribute("Phase", n.movePhase or 0)
		part:SetAttribute("Stage", st.index)
		topIcon(part, if n.moveAxis == "y" then "▲ ▼" else "◀ ▶", Color3.fromRGB(255, 255, 255))
		moverRails(model, part, n.moveAxis == "y", n.moveAmp or 4, theme.pad)
	elseif n.kind == "disappear" then
		part.Color = theme.alt:Lerp(Color3.fromRGB(255, 255, 255), 0.35)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0.15
		tag(part, "Disappear")
		part:SetAttribute("Delay", n.delay or 0.6)
		topIcon(part, "⏳", Color3.fromRGB(255, 255, 255))
	elseif n.kind == "falling" then
		part.Color = Color3.fromRGB(215, 150, 80)
		part.Material = Enum.Material.WoodPlanks
		tag(part, "Falling")
		part:SetAttribute("Delay", n.delay or 0.5)
		topIcon(part, "▼ ▼", Color3.fromRGB(90, 50, 25))
	elseif n.kind == "ice" then
		part.Color = Color3.fromRGB(180, 230, 255)
		part.Material = Enum.Material.Ice
		part.CustomPhysicalProperties = ICE
	elseif n.kind == "conveyor" then
		part.Color = Color3.fromRGB(60, 62, 72)
		part.Material = Enum.Material.DiamondPlate
		local push = Vector3.new(st.dirX, 0, st.dirZ) * (n.pushS or 0) + latVector(st) * (n.pushLat or 0)
		part.AssemblyLinearVelocity = push
		part:SetAttribute("Push", push)
		tag(part, "Conveyor")
	elseif n.kind == "bounce" then
		part.Color = Color3.fromRGB(80, 255, 110)
		part.Material = Enum.Material.Neon
		tag(part, "Bounce")
		topIcon(part, "▲", Color3.fromRGB(255, 255, 255))
	elseif n.kind == "glass" then
		part.Color = Color3.fromRGB(200, 245, 255)
		part.Material = Enum.Material.Glass
		part.Transparency = 0.8
		tag(part, "Glass")
	end
	return part
end

local function killPart(model: Instance, size: Vector3, cf: CFrame): Part
	local p = newPart(model, size, cf, Config.KillColor, Enum.Material.Neon)
	p.Name = "Kill"
	p.CastShadow = false
	tag(p, "Kill")
	return p
end

local function buildHazard(st: Layout.Stage, h: Layout.Hazard, model: Model, theme: Config.Theme)
	if h.kind == "killstrip" or h.kind == "killcube" then
		killPart(model, Vector3.new(h.width, h.height, h.len), stageCF(st, h.s, h.lat, h.y + h.height, h.height))
	elseif h.kind == "spinner" then
		local x, y, z = Layout.toWorld(st, h.s, h.lat, h.y)
		local center = Vector3.new(x, y + h.height / 2, z)
		local hub = cylinder(model, 2.4, 3, center + Vector3.new(0, 0.5, 0), theme.accent, Enum.Material.Metal)
		hub.Name = "SpinnerHub"
		local bars = h.bars or 1
		for b = 1, bars do
			local bar = killPart(model, Vector3.new(h.len, h.height, h.width), CFrame.new(center))
			bar.Name = "SpinnerBar"
			tag(bar, "Spinner")
			bar:SetAttribute("Center", center)
			bar:SetAttribute("Speed", h.speed or 2)
			bar:SetAttribute("Angle0", (b - 1) * math.pi / bars)
			bar:SetAttribute("Stage", st.index)
		end
	elseif h.kind == "lava" then
		local lava = killPart(model, Vector3.new(h.width, h.height, h.len), stageCF(st, h.s, h.lat, h.y + h.height, h.height))
		lava.Name = "Lava"
		lava.Color = Color3.fromRGB(255, 90, 20)
		lava.Material = Enum.Material.CrackedLava
		tag(lava, "Lava")
		lava:SetAttribute("Bottom", st.from.y + h.y)
		lava:SetAttribute("MinTop", st.from.y + h.y + h.height)
		lava:SetAttribute("MaxTop", st.from.y + (h.maxRise or 4))
		lava:SetAttribute("Period", h.period or 10)
		lava:SetAttribute("Stage", st.index)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 120, 40)
		light.Range = 24
		light.Brightness = 2
		light.Shadows = false
		light.Parent = lava
		local embers = Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Texture = "rbxasset://textures/particles/fire_main.dds"
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 20))
		embers.Rate = 10
		embers.Lifetime = NumberRange.new(1.2, 2.2)
		embers.Speed = NumberRange.new(3, 7)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.Size = NumberSequence.new(0.9, 0.1)
		embers.LightEmission = 1
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Parent = lava
	elseif h.kind == "wall" then
		local wall = newPart(model, Vector3.new(h.width, h.height, h.len), stageCF(st, h.s, h.lat, h.y + h.height, h.height), theme.alt, theme.material)
		wall.Name = "Wall"
	elseif h.kind == "laser" then
		-- a gate of light across the walkway; Obstacles.luau switches it on and off and kills
		local cf = stageCF(st, h.s, h.lat, h.y + h.height, h.height)
		local beam = Scenery.deco(model, Vector3.new(h.width, h.height, h.len), cf, Config.KillColor, Enum.Material.Neon)
		beam.Name = "Laser"
		beam.Transparency = 0.3
		beam:SetAttribute("Period", h.period or 3)
		beam:SetAttribute("Duty", h.duty or 0.5)
		beam:SetAttribute("Phase", h.phase or 0)
		beam:SetAttribute("Stage", st.index)
		tag(beam, "Laser")
		local metal = Color3.fromRGB(55, 58, 72)
		for _, side in { -1, 1 } do
			Scenery.deco(model, Vector3.new(0.8, h.height + 0.8, 1.3), cf * CFrame.new(side * (h.width / 2 + 0.4), 0.4, 0), metal, Enum.Material.Metal).Name = "LaserPost"
			Scenery.deco(model, Vector3.new(0.5, 0.5, 1.4), cf * CFrame.new(side * (h.width / 2 + 0.4), h.height / 2 + 0.9, 0), Color3.fromRGB(255, 220, 60), Enum.Material.Neon).Name = "LaserLamp"
		end
	elseif h.kind == "wind" then
		-- invisible zone: each client pushes its own character sideways while inside
		-- (client/World/LocalFx.luau); streaks and chevrons show where it blows
		local cf = stageCF(st, h.s, h.lat, h.y + h.height, h.height)
		local zone = Scenery.deco(model, Vector3.new(h.width, h.height, h.len), cf, Color3.new(1, 1, 1))
		zone.Name = "Wind"
		zone.Transparency = 1
		local dir = latVector(st) * (if (h.push or 0) >= 0 then 1 else -1)
		zone:SetAttribute("Push", dir * math.abs(h.push or 0))
		zone:SetAttribute("Stage", st.index)
		tag(zone, "Wind")
		local streaks = Instance.new("ParticleEmitter")
		streaks.Name = "Streaks"
		streaks.Texture = SMOKE
		streaks.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		streaks.Rate = 9
		streaks.Lifetime = NumberRange.new(1, 1.6)
		streaks.Speed = NumberRange.new(0, 0)
		streaks.Acceleration = dir * 26
		streaks.Size = NumberSequence.new(0.5, 1.4)
		streaks.Squash = NumberSequence.new(1.6)
		streaks.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		streaks.Parent = zone
		-- chevrons hanging over the route, pointing where the wind blows (readable without particles)
		local routeY = st.rise * math.clamp((h.s - Layout.PAD_RADIUS) / (st.span - 2 * Layout.PAD_RADIUS), 0, 1) + 7.5
		local x, y, z = Layout.toWorld(st, h.s, 0, routeY)
		local at = Vector3.new(x, y, z)
		for k = -1, 1 do
			local tip = at + dir * (k * 2.6)
			local frame = CFrame.lookAt(tip, tip + dir)
			for _, side in { -1, 1 } do
				local bar = Scenery.deco(model, Vector3.new(0.35, 0.35, 1.8), frame * CFrame.Angles(0, side * math.rad(40), 0) * CFrame.new(0, 0, 0.9), Color3.fromRGB(235, 250, 255), Enum.Material.Neon)
				bar.Name = "WindArrow"
				bar:SetAttribute("Order", k + 1)
				tag(bar, "BeltArrow")
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- one builder per obstacle kind (common surfaces + that kind's own flavour)
---------------------------------------------------------------------------------------------
local function buildBasic(st: Layout.Stage, model: Model, theme: Config.Theme)
	for i, n in st.nodes do
		buildNode(st, n, model, theme, i)
	end
	for _, h in st.hazards do
		buildHazard(st, h, model, theme)
	end
end

local Builders: { [string]: (Layout.Stage, Model, Config.Theme) -> () } = {}
for _, kind in Layout.Kinds do
	Builders[kind] = buildBasic
end

function Builders.conveyor(st, model, theme)
	buildBasic(st, model, theme)
	-- neon chevrons on top of every belt, pointing where it pushes you
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and CollectionService:HasTag(child, "Conveyor") then
			local push = child:GetAttribute("Push") :: Vector3?
			if push and push.Magnitude > 0 then
				local dir = push.Unit
				local top = child.Position + Vector3.new(0, child.Size.Y / 2 + 0.06, 0)
				local reach = math.min(child.Size.X, child.Size.Z) * 0.3
				for _, offset in { -1, 0, 1 } do
					local tip = top + dir * (offset * reach * 1.4)
					local frame = CFrame.lookAt(tip, tip + dir)
					for _, side in { -1, 1 } do
						local bar = Scenery.deco(model, Vector3.new(0.35, 0.1, reach), frame * CFrame.Angles(0, side * math.rad(40), 0) * CFrame.new(0, 0, reach / 2), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
						bar.Name = "Arrow"
						-- the three chevrons light up one after another in the push direction
						-- (client/World/Juice.luau), so the belt reads as running
						bar:SetAttribute("Order", offset + 1)
						tag(bar, "BeltArrow")
					end
				end
			end
		end
	end
end

function Builders.bounce(st, model, theme)
	buildBasic(st, model, theme)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and CollectionService:HasTag(part, "Bounce") then
			local e = Instance.new("ParticleEmitter")
			e.Texture = SPARKLES
			e.Color = ColorSequence.new(Color3.fromRGB(120, 255, 140))
			e.Rate = 6
			e.Lifetime = NumberRange.new(0.6, 1)
			e.Speed = NumberRange.new(6, 10)
			e.SpreadAngle = Vector2.new(15, 15)
			e.EmissionDirection = Enum.NormalId.Top
			e.Parent = part
		end
	end
end

function Builders.lava(st, model, theme)
	buildBasic(st, model, theme)
	-- a see-through tank around the lava so the rising slab reads as "filling up" instead of a
	-- floating block (visual only: no collisions, touches or raycasts)
	for _, lava in model:GetChildren() do
		if lava:IsA("BasePart") and CollectionService:HasTag(lava, "Lava") then
			local bottom = lava:GetAttribute("Bottom") :: number
			local top = (lava:GetAttribute("MaxTop") :: number) + 0.6
			local h = top - bottom
			local cf = lava.CFrame.Rotation + Vector3.new(lava.Position.X, bottom + h / 2, lava.Position.Z)
			local size = lava.Size
			local floor = newPart(model, Vector3.new(size.X + 1, 1, size.Z + 1), cf * CFrame.new(0, -h / 2 - 0.5, 0), darker(theme.alt), theme.material)
			floor.Name = "LavaTankFloor"
			for _, side in { { size.X / 2 + 0.25, 0, 0.5, size.Z + 1 }, { -size.X / 2 - 0.25, 0, 0.5, size.Z + 1 }, { 0, size.Z / 2 + 0.25, size.X, 0.5 }, { 0, -size.Z / 2 - 0.25, size.X, 0.5 } } do
				local wall = Scenery.deco(model, Vector3.new(side[3], h, side[4]), cf * CFrame.new(side[1], 0, side[2]), Color3.fromRGB(255, 170, 120), Enum.Material.Glass)
				wall.Transparency = 0.7
				wall.Name = "LavaTankWall"
			end
		end
	end
end

StageGenerator.Builders = Builders

---------------------------------------------------------------------------------------------
-- pads and milestones
---------------------------------------------------------------------------------------------
-- `g` = global stage of the checkpoint (nil for the base pad of towers 2..10, which belongs to
-- the summit of the tower before). Saving pads get a flag; rest pads are dimmer and smaller in
-- presence: you stand on them, but a fall takes you back to the last flag.
local function buildPad(folder: Instance, g: number?, pos: Vector3, axis: Vector3, theme: Config.Theme, thick: number): Part
	local save = g == nil or g == 0 or Layout.isSave(g)
	local color = if save then theme.pad else theme.pad:Lerp(Color3.fromRGB(150, 155, 170), 0.55)
	local pad = cylinder(folder, Layout.PAD_RADIUS * 2, thick, pos - Vector3.new(0, thick / 2, 0), color, if save then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	local rim = cylinder(folder, Layout.PAD_RADIUS * 2 + 1.2, thick - 0.2, pos - Vector3.new(0, thick / 2 + 0.1, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	rim.Name = "PadRim"
	rim.CanTouch = false
	-- target look: a pale inlay and a glowing centre dot painted on the pad (non-solid, 0.1 stud),
	-- so the pad is a ring of light instead of one big glowing disc
	local inlay = Scenery.deco(folder, Vector3.new(0.1, Layout.PAD_RADIUS * 1.4, Layout.PAD_RADIUS * 1.4), CFrame.new(pos + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.pi / 2), theme.pad:Lerp(Color3.new(1, 1, 1), 0.78), Enum.Material.SmoothPlastic)
	inlay.Shape = Enum.PartType.Cylinder
	inlay.Name = "PadInlay"
	local dot = Scenery.deco(folder, Vector3.new(0.14, Layout.PAD_RADIUS * 0.5, Layout.PAD_RADIUS * 0.5), CFrame.new(pos + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, if save then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	dot.Shape = Enum.PartType.Cylinder
	dot.Name = "PadDot"
	if g == nil then
		pad.Name = "BasePad"
		return pad
	end
	pad.Name = "Checkpoint_" .. g
	pad:SetAttribute("Stage", g)
	pad:SetAttribute("Save", save)
	tag(pad, "Checkpoint")
	dot:SetAttribute("Stage", g)
	tag(dot, "PadDot")
	if g > 0 then
		-- the stage number floats over the pad edge (over the flag pole on saving pads), clear of
		-- the name tag of whoever is standing on the pad
		local out = Vector3.new(pos.X - axis.X, 0, pos.Z - axis.Z).Unit
		local foot = pos + out * (Layout.PAD_RADIUS - 0.7)
		local anchor = Scenery.deco(folder, Vector3.new(1, 1, 1), CFrame.new(foot + Vector3.new(0, if save then 11.4 else 6.5, 0)), Color3.new())
		anchor.Transparency = 1
		anchor.Name = "Sign_" .. g
		billboard(anchor, tostring(g), if save then Vector2.new(5, 3) else Vector2.new(3.6, 2.2), if save then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(215, 220, 235), 90, 0)
		if save then
			-- checkpoint flag on the outer edge of the pad. Each client raises it (and turns it
			-- green) for the pads that player has already reached (client/World/Juice.luau).
			local pole = Scenery.deco(folder, Vector3.new(9, 0.4, 0.4), CFrame.new(foot + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 245, 250), Enum.Material.Metal)
			pole.Shape = Enum.PartType.Cylinder
			pole.Name = "FlagPole"
			local knob = Scenery.deco(folder, Vector3.new(0.9, 0.9, 0.9), CFrame.new(foot + Vector3.new(0, 9.2, 0)), Color3.fromRGB(255, 205, 70), Enum.Material.Neon)
			knob.Shape = Enum.PartType.Ball
			knob.Name = "FlagKnob"
			local frame = CFrame.lookAt(foot, foot + out)
			local flag = Scenery.deco(folder, Vector3.new(3.4, 2.2, 0.2), frame * CFrame.new(1.9, 2.4, 0), Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic)
			flag.Name = "Flag_" .. g
			flag:SetAttribute("Stage", g)
			flag:SetAttribute("Low", frame * CFrame.new(1.9, 2.4, 0))
			flag:SetAttribute("High", frame * CFrame.new(1.9, 7.6, 0))
			tag(flag, "Flag")
		end
	end
	return pad
end

-- Banner + halo over the first pad of a world (every 10 stages).
local function buildMilestone(folder: Instance, g: number, pos: Vector3)
	local style = Layout.themeFor(g + 1)
	local ringRadius = 9
	local segments = 20
	local center = pos + Vector3.new(0, 11, 0)
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local p = Scenery.deco(folder, Vector3.new(1.2, 1.2, 3.2), CFrame.new(center + Vector3.new(math.cos(a) * ringRadius, 0, math.sin(a) * ringRadius)) * CFrame.Angles(0, -a, 0), Config.RebirthColors[(i % #Config.RebirthColors) + 1], Enum.Material.Neon)
		p.Name = "Halo"
	end
	local anchor = Scenery.deco(folder, Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 7, 0)), Color3.new())
	anchor.Transparency = 1
	anchor.Name = "Milestone_" .. g
	local bb = billboard(anchor, "", Vector2.new(28, 9), Color3.fromRGB(255, 240, 90), 300, 0)
	local label = bb:FindFirstChildOfClass("TextLabel") :: TextLabel
	loc(label, "sign.milestone", { n = g, w = g // 10 + 1, name = { key = "world." .. style } })
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 3
	light.Color = Color3.fromRGB(255, 240, 150)
	light.Shadows = false
	light.Parent = anchor
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLES
	e.Rate = 12
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 120, 220))
	e.Parent = anchor
end

-- The core pillar: one segment per world in that world's material, six pilasters, an accent band
-- at every world boundary. A Persistent model: the silhouette of the tower is always there, even
-- for the parts of it that are streamed out.
local function buildCore(folder: Instance, map: Layout.Map)
	local core = Instance.new("Model")
	core.Name = "Core"
	core.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local axis = vec(map.origin)
	for w = 1, 10 do
		local theme = Config.theme(map.tower, Layout.themeFor((map.tower - 1) * Layout.STAGES + (w - 1) * 10 + 1))
		local y0 = if w == 1 then 0 else map.pads[(w - 1) * 10].y
		local y1 = map.pads[w * 10].y
		local h = y1 - y0
		-- a 100-stud neon/glass pillar is blinding: the core uses a matte version of the theme
		local mat = if theme.material == Enum.Material.Neon or theme.material == Enum.Material.Glass then Enum.Material.SmoothPlastic else theme.material
		if mat == Enum.Material.Grass then
			mat = Enum.Material.Wood -- a giant tree trunk
		end
		local segment = cylinder(core, Layout.CORE_RADIUS * 2, h, axis + Vector3.new(0, y0 + h / 2, 0), theme.alt, mat)
		segment.Name = "Core_" .. w
		segment.CastShadow = false
		-- six pilasters, so the pillar reads as a tower instead of a flat tube
		for i = 0, 5 do
			local a = i * math.pi / 3 + math.pi / 6
			local pos = axis + Vector3.new(math.cos(a) * (Layout.CORE_RADIUS + 0.3), y0 + h / 2, math.sin(a) * (Layout.CORE_RADIUS + 0.3))
			local rib = Scenery.deco(core, Vector3.new(3, h, 1.8), CFrame.lookAt(pos, Vector3.new(axis.X, pos.Y, axis.Z)), theme.alt:Lerp(theme.accent, 0.35):Lerp(Color3.new(), 0.18), mat)
			rib.Name = "CoreRib"
		end
		local band = Scenery.deco(core, Vector3.new(2, Layout.CORE_RADIUS * 2 + 1, Layout.CORE_RADIUS * 2 + 1), CFrame.new(axis + Vector3.new(0, y1, 0)) * CFrame.Angles(0, 0, math.pi / 2), theme.accent, Enum.Material.Neon)
		band.Shape = Enum.PartType.Cylinder
		band.Name = "CoreBand_" .. w
	end
	core.Parent = folder
end

-- Clouds all the way up, tinted by the world they float in (dark smoke in the lava caves, green
-- smog around the factory, violet nebula puffs in space) and by the tower's mood.
local CLOUD_TINT: { { any } } = {
	{ { 255, 255, 255 }, 0.1 },
	{ { 255, 222, 240 }, 0.1 },
	{ { 235, 245, 255 }, 0.18 },
	{ { 255, 232, 200 }, 0.15 },
	{ { 70, 46, 46 }, 0.35 },
	{ { 190, 240, 245 }, 0.3 },
	{ { 140, 165, 100 }, 0.35 },
	{ { 255, 255, 255 }, 0.05 },
	{ { 110, 80, 200 }, 0.55 },
	{ { 255, 230, 240 }, 0.15 },
}

local function buildClouds(folder: Instance, map: Layout.Map, count: number)
	local rng = Layout.newRng(Config.MapSeed + 99 + map.tower * 17)
	local top = map.pads[Layout.STAGES].y
	local axis = vec(map.origin)
	local mood = TowerStyle.mood(map.tower)
	for _ = 1, count do
		local a = rng.range(0, math.pi * 2)
		local r = rng.range(150, 330)
		local y = rng.range(40, top + 60)
		local slot = 1
		for w = 1, 9 do
			if y > map.pads[w * 10].y then
				slot = w + 1
			end
		end
		local tint = CLOUD_TINT[Layout.themeFor((map.tower - 1) * Layout.STAGES + (slot - 1) * 10 + 1)]
		local color = Config.c3(TowerStyle.shift(tint[1], mood))
		local base = CFrame.new(axis + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
		local s = rng.range(22, 44)
		for j = 1, 3 do
			local k = if j == 1 then 1 else rng.range(0.5, 0.75)
			local p = Scenery.deco(folder, Vector3.new(s * k, s * 0.42 * k, s * 1.5 * k), base * CFrame.new(if j == 1 then 0 else rng.range(-3, 3), if j == 1 then 0 else s * 0.12, if j == 1 then 0 else (j * 2 - 5) * s * 0.42), color, Enum.Material.SmoothPlastic)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
			p.Transparency = tint[2] :: number
			p.Name = "Cloud"
		end
	end
end

---------------------------------------------------------------------------------------------
-- lobby
---------------------------------------------------------------------------------------------
local function buildStall(folder: Instance, nameKey: string, pos: Vector3, facing: Vector3, color: Color3, actionKey: string): ProximityPrompt
	local m = Instance.new("Model")
	m.Name = Locale.t("en", nameKey)
	local cf = CFrame.lookAt(pos, pos + facing)
	local counter = newPart(m, Vector3.new(10, 3.5, 3), cf * CFrame.new(0, 1.75, 0), Color3.fromRGB(250, 240, 225), Enum.Material.WoodPlanks)
	counter.Name = "Counter"
	for _, x in { -4.5, 4.5 } do
		newPart(m, Vector3.new(0.8, 9, 0.8), cf * CFrame.new(x, 4.5, 1.5), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	end
	-- striped awning
	for i = 0, 4 do
		local stripe = newPart(m, Vector3.new(2.2, 0.6, 5), cf * CFrame.new(-4.4 + i * 2.2, 9.3, 0.5) * CFrame.Angles(math.rad(-12), 0, 0), if i % 2 == 0 then color else Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
		stripe.Name = "Awning"
	end
	local sign = newPart(m, Vector3.new(9, 2.4, 0.4), cf * CFrame.new(0, 11, -1), color, Enum.Material.SmoothPlastic)
	sign.Name = "Sign"
	loc(surfaceText(sign, Enum.NormalId.Front, "", Color3.fromRGB(255, 255, 255)), nameKey)
	local p = prompt(counter, actionKey, nameKey, 0, 12)
	m.Parent = folder
	return p
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.5
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(120, 120, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	-- sky light fills the faces the sun doesn't reach (otherwise the sides of platforms go black)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.35
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.25
		atm.Haze = 1
		atm.Color = Color3.fromRGB(200, 225, 255)
		atm.Decay = Color3.fromRGB(150, 190, 255)
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky") -- default built-in skybox, no uploads
		sky.Parent = Lighting
	end
	-- post-processing (bloom, colour grading, sun rays) and the per-height look are client-side:
	-- see client/World/Atmos.luau + Shared/Ambience.luau
end

function StageGenerator.buildLobby(): Lobby
	setupLighting()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	local deco = Instance.new("Folder")
	deco.Name = "Decor"

	local floor = cylinder(folder, 300, 4, Vector3.new(0, -2, 0), Color3.fromRGB(120, 210, 100), Enum.Material.Grass)
	floor.Name = "LobbyFloor"
	floor.CastShadow = false
	local path = newPart(folder, Vector3.new(12, 0.3, 50), CFrame.new(0, 0.15, 90), Color3.fromRGB(250, 235, 200), Enum.Material.Sandstone)
	path.Name = "Path"

	local spawnPos = Vector3.new(0, 0.5, 115)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(spawnPos)
	spawn.Color = Color3.fromRGB(90, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Name = "LobbySpawn"
	spawn.Parent = folder
	local lobbySpawn = CFrame.lookAt(spawnPos + Vector3.new(0, 3.5, 0), Vector3.new(0, 4, 60))

	-- welcome arch over the tower start
	local start = Vector3.new(0, Layout.BASE_Y, Layout.RING_RADIUS)
	for _, x in { -8, 8 } do
		local post = newPart(folder, Vector3.new(2, 16, 2), CFrame.new(start + Vector3.new(x, 6, 4)), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
		post.Name = "ArchPost"
	end
	local beam = newPart(folder, Vector3.new(20, 4, 2), CFrame.new(start + Vector3.new(0, 15, 4)), Color3.fromRGB(255, 90, 120), Enum.Material.SmoothPlastic)
	beam.Name = "ArchSign"
	loc(surfaceText(beam, Enum.NormalId.Back, "", Color3.fromRGB(255, 255, 255)), "sign.start")
	loc(surfaceText(beam, Enum.NormalId.Front, "", Color3.fromRGB(255, 255, 255)), "sign.start")

	-- global boards (Leaderboard.luau fills them): Top Wins, Fastest Climb and Highest Stage
	local function boardAt(pos: Vector3, facing: Vector3, name: string): BasePart
		local b = newPart(folder, Vector3.new(16, 16, 1), CFrame.lookAt(pos, pos + facing), Color3.fromRGB(40, 45, 80), Enum.Material.SmoothPlastic)
		b.Name = name
		for _, dz in { -6, 6 } do
			newPart(folder, Vector3.new(1.2, 3, 1.2), b.CFrame * CFrame.new(dz, -9.5, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
		end
		return b
	end
	local board = boardAt(Vector3.new(-34, 11, 104), Vector3.new(1, 0, 0.35), "WinsBoard")
	local fastBoard = boardAt(Vector3.new(-28, 11, 86), Vector3.new(1, 0, 0.35), "FastestBoard")
	local stageBoard = boardAt(Vector3.new(-36, 11, 123), Vector3.new(1, 0, -0.1), "StageBoard")

	local stalls: { [string]: ProximityPrompt } = {}
	stalls.shop = buildStall(folder, "stall.shop", Vector3.new(32, 0, 92), Vector3.new(-1, 0, 0.2), Color3.fromRGB(255, 120, 170), "prompt.open_shop")
	stalls.store = buildStall(folder, "stall.store", Vector3.new(36, 0, 110), Vector3.new(-1, 0, 0), Color3.fromRGB(80, 200, 110), "prompt.open_store")
	stalls.rewards = buildStall(folder, "stall.rewards", Vector3.new(32, 0, 128), Vector3.new(-1, 0, -0.2), Color3.fromRGB(255, 190, 60), "prompt.claim")

	-- a few trees
	local rng = Layout.newRng(Config.MapSeed + 5)
	for _ = 1, 26 do
		local a = rng.range(0, math.pi * 2)
		local r = rng.range(80, 140)
		local base = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if (base - Vector3.new(8, 0, 108)).Magnitude > 44 and (base - Vector3.new(-28, 0, 86)).Magnitude > 14 and (base - Vector3.new(-36, 0, 123)).Magnitude > 14 then
			local h = rng.range(6, 10)
			local trunk = cylinder(folder, 1.6, h, base + Vector3.new(0, h / 2, 0), Color3.fromRGB(130, 90, 60), Enum.Material.Wood)
			trunk.Name = "Trunk"
			local top = newPart(folder, Vector3.new(8, 8, 8), CFrame.new(base + Vector3.new(0, h + 2.5, 0)), Color3.fromRGB(70, 180, 80):Lerp(Color3.fromRGB(255, 150, 200), rng.next() * 0.3), Enum.Material.Grass)
			top.Shape = Enum.PartType.Ball
			top.Name = "Leaves"
		end
	end

	Scenery.buildLobby(deco, start, lobbySpawn.Position)
	-- what waits at the top, shown before the first jump
	Scenery.buildGiftPreview(deco, CFrame.lookAt(start + Vector3.new(-13, -2, 9), start + Vector3.new(-13, -2, 60)), Gifts.List[1], loc)

	folder.Parent = Workspace
	deco.Parent = Workspace
	return { lobbySpawn = lobbySpawn, board = board, fastBoard = fastBoard, stageBoard = stageBoard, stalls = stalls }
end

---------------------------------------------------------------------------------------------
-- summit room (pad 100 of every tower): victory floor, rebirth pedestal, gift, portal
---------------------------------------------------------------------------------------------
local function buildSummit(folder: Instance, map: Layout.Map, prompts: { Prompt }): BasePart?
	local t = map.tower
	local axis = vec(map.origin)
	local p100 = vec(map.pads[Layout.STAGES])
	local outward = Vector3.new(p100.X - axis.X, 0, p100.Z - axis.Z).Unit
	local center = p100 + outward * 30
	local floor = cylinder(folder, 50, 2, center - Vector3.new(0, 1, 0), Color3.fromRGB(255, 225, 90), Enum.Material.SmoothPlastic)
	floor.Name = "VictoryFloor"
	-- rainbow pillars around the room
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * 22, 6, math.sin(a) * 22)
		local pillar = newPart(folder, Vector3.new(2, 12, 2), CFrame.new(pos), Config.RebirthColors[(i % #Config.RebirthColors) + 1], Enum.Material.Neon)
		pillar.Name = "VictoryPillar"
		pillar.CastShadow = false
		if i % 2 == 0 then
			local e = Instance.new("ParticleEmitter")
			e.Texture = SPARKLES
			e.Rate = 25
			e.Lifetime = NumberRange.new(2, 3)
			e.Speed = NumberRange.new(12, 20)
			e.SpreadAngle = Vector2.new(30, 30)
			e.Acceleration = Vector3.new(0, -12, 0)
			e.Size = NumberSequence.new(0.6)
			e.EmissionDirection = Enum.NormalId.Top
			e.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 120)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 170, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
			})
			e.Parent = pillar
		end
	end
	local signPos = center + outward * 20 + Vector3.new(0, 10, 0)
	local sign = newPart(folder, Vector3.new(26, 7, 1), CFrame.lookAt(signPos, center + Vector3.new(0, 10, 0)), Color3.fromRGB(255, 90, 140), Enum.Material.SmoothPlastic)
	sign.Name = "WinnerSign"
	local signLabel = surfaceText(sign, Enum.NormalId.Front, "", Color3.fromRGB(255, 255, 255))
	if t == 1 then
		loc(signLabel, "sign.winner")
	else
		loc(signLabel, "sign.tower_clear", { n = t, name = { key = "tower." .. TowerStyle.mood(t).key } })
	end
	local pedestal = cylinder(folder, 6, 3, center + Vector3.new(0, 1.5, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Marble)
	pedestal.Name = "RebirthPedestal"
	local orb = Scenery.deco(folder, Vector3.new(3, 3, 3), CFrame.new(center + Vector3.new(0, 5, 0)), Color3.fromRGB(255, 220, 90), Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	orb.Name = "RebirthOrb"
	table.insert(prompts, { kind = "rebirth", id = tostring(t), prompt = prompt(pedestal, "prompt.rebirth", "prompt.winner", 0.5, 12) })

	local frame = CFrame.lookAt(center, center - outward) -- -Z looks back at the tower, +X is to the right
	Scenery.buildVictory(folder, center, outward)
	-- the gift of this tower, on a plinth to the right
	Scenery.buildGiftPreview(folder, frame * CFrame.new(18, 0, -4) * CFrame.Angles(0, math.rad(-70), 0), Gifts.List[t], loc)

	local portal: BasePart? = nil
	if t < Layout.TOWERS then
		-- the way on: a portal to the base of the next tower, on the left
		local nextMood = TowerStyle.mood(t + 1)
		portal = Scenery.buildPortal(folder, frame * CFrame.new(-18, 0, -4) * CFrame.Angles(0, math.rad(70), 0), Config.c3(nextMood.core), "portal.next", { n = t + 1, name = { key = "tower." .. nextMood.key }, from = t * Layout.STAGES + 1, to = (t + 1) * Layout.STAGES }, loc)
		local p = portal :: BasePart
		p.Name = "Portal"
		p:SetAttribute("Tower", t)
		table.insert(prompts, { kind = "portal", id = tostring(t), prompt = prompt(p, "prompt.enter", "prompt.portal", 0, 14) })
	end
	if t == 1 then
		-- the Winner's Lounge: free items for everybody who got here
		for _, item in Scenery.buildLounge(folder, center, outward, loc) do
			table.insert(prompts, { kind = "lounge", id = item.id, prompt = prompt(item.part, "prompt.take", "perk." .. item.id .. ".name", 0.25, 9) })
		end
	end
	return portal
end

---------------------------------------------------------------------------------------------
function StageGenerator.buildTower(t: number): Tower
	local map = Layout.generate(Config.MapSeed, t)
	local axis = vec(map.origin)
	local first = (t - 1) * Layout.STAGES

	local root = Workspace:FindFirstChild("Towers")
	if not root then
		root = Instance.new("Folder")
		root.Name = "Towers"
		root.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = "Tower_" .. t
	folder:SetAttribute("Tower", t)
	local scenery = Instance.new("Folder")
	scenery.Name = "Decor"
	scenery.Parent = folder
	local padFolder = Instance.new("Folder")
	padFolder.Name = "Checkpoints"
	padFolder.Parent = folder
	-- parented first: what is built below replicates as it appears, instead of in one burst
	folder.Parent = root

	buildCore(scenery, map)
	buildClouds(scenery, map, if t == 1 then 64 else 36)
	local stats = Scenery.buildTower(scenery, map)
	folder:SetAttribute("SceneryParts", stats.parts)
	folder:SetAttribute("SceneryLights", stats.lights)
	folder:SetAttribute("SceneryEmitters", stats.emitters)
	task.wait()

	local prompts: { Prompt } = {}
	local pads: { [number]: BasePart } = {}
	local padCFrames: { [number]: CFrame } = {}
	local baseCFrame = CFrame.new()
	for k = 0, Layout.STAGES do
		local g = first + k
		local theme = Config.theme(t, Layout.themeFor(math.max(g, 1)))
		local pos = vec(map.pads[k])
		local isBase = k == 0 and t > 1
		local pad = buildPad(padFolder, if isBase then nil else g, pos, axis, theme, if k == 0 then 2 else Layout.PAD_THICK)
		local nextStage = map.stages[k + 1]
		local look = if nextStage then Vector3.new(nextStage.dirX, 0, nextStage.dirZ) else Vector3.new(pos.X - axis.X, 0, pos.Z - axis.Z).Unit
		local standing = CFrame.lookAt(pos + Vector3.new(0, 3.5, 0), pos + Vector3.new(0, 3.5, 0) + look)
		if k == 0 then
			baseCFrame = standing
		end
		if not isBase then
			pads[g] = pad
			padCFrames[g] = standing
		end
		if Layout.hasShop(k) then
			buildMilestone(padFolder, g, pos)
			-- the shop at the entrance of every world
			local out = Vector3.new(pos.X - axis.X, 0, pos.Z - axis.Z).Unit
			for _, item in Scenery.buildShop(folder, pos, out, theme, loc) do
				table.insert(prompts, { kind = "shop", id = item.id, prompt = prompt(item.part, "prompt.buy", "power." .. item.id .. ".name", 0.35, 8) })
			end
		end
	end
	task.wait()

	for i, st in map.stages do
		local model = Instance.new("Model")
		model.Name = ("Stage_%04d_%s"):format(st.index, st.kind)
		model:SetAttribute("Stage", st.index)
		model:SetAttribute("Kind", st.kind)
		local theme = Config.theme(t, st.theme)
		dressRng = Layout.newRng(Config.MapSeed * 131 + st.index)
		Builders[st.kind](st, model, theme)
		for _, c in st.coins do
			local x, y, z = Layout.toWorld(st, c.s, c.lat, c.y)
			local coin = Scenery.deco(model, Vector3.new(0.5, 2.4, 2.4), CFrame.new(x, y, z), Color3.fromRGB(255, 205, 40), Enum.Material.Neon)
			coin.Shape = Enum.PartType.Cylinder -- axis = X, so the coin stands up like a wheel
			coin.CanTouch = true
			coin.Name = "Coin"
			coin:SetAttribute("CoinId", c.id)
			coin:SetAttribute("Stage", st.index)
			tag(coin, "Coin")
		end
		model.Parent = folder
		if i % 12 == 0 then
			task.wait() -- spread the build over a few frames: no server hitch when a tower appears
		end
	end

	local portal = buildSummit(folder, map, prompts)
	if t > 1 then
		-- base island with the way back to the lobby
		local home = Scenery.buildBase(folder, vec(map.pads[0]), axis, t, loc)
		table.insert(prompts, { kind = "home", id = tostring(t), prompt = prompt(home, "prompt.enter", "prompt.lobby", 0, 12) })
		if t < Layout.TOWERS + 1 then
			local p0 = vec(map.pads[0])
			Scenery.buildGiftPreview(folder, CFrame.lookAt(p0 + Vector3.new(-13, -2, 9), p0 + Vector3.new(-13, -2, 60)), Gifts.List[t], loc)
		end
	end

	return {
		tower = t,
		map = map,
		folder = folder,
		pads = pads,
		padCFrames = padCFrames,
		baseCFrame = baseCFrame,
		prompts = prompts,
		portal = portal,
	}
end

return StageGenerator
