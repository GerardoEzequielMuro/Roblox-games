--!strict
-- Draws the local player's planets for the galaxy they are standing in and plays every
-- mining effect. Planets are client-side only (the server just keeps their HP): models are
-- built here, spun and shaken in one RenderStepped, and debris / floating numbers come from
-- fixed pools, so nothing is created per hit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Palette = require(ReplicatedStorage.Shared.Palette)
local PlanetModel = require(ReplicatedStorage.Shared.PlanetModel)
local Themes = require(ReplicatedStorage.Shared.Themes)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Quality = require(script.Parent.Quality)

local PlanetField = {}

export type View = {
	n: number,
	kind: string,
	layer: number,
	hp: number,
	max: number,
	dense: boolean,
	alive: boolean,
	pos: Vector3,
	radius: number,
	model: Model?,
	gui: BillboardGui?,
	fill: Frame?,
	hpText: TextLabel?,
	shakeAt: number,
	dropAt: number, -- os.clock() when the respawn drop-in started
	spin: number,
	respawnAt: number?,
	variant: number, -- colour jitter (kept across rebuilds of the same planet)
}

PlanetField.zone = nil :: number?
PlanetField.views = {} :: { [number]: View }
PlanetField.loading = false
local changed = Instance.new("BindableEvent")
PlanetField.Changed = changed.Event -- (n: number?) a planet's state changed (nil = whole galaxy)
local broke = Instance.new("BindableEvent")
PlanetField.Broke = broke.Event -- (view, message) a core broke

local player = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "ClientPlanets"
folder.Parent = Workspace

local INK = Color3.fromRGB(16, 14, 32)

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------
type Chip = { part: Part, vel: Vector3, spin: Vector3, life: number, max: number }
local chips: { Chip } = {}
local chipIndex = 0
local CHIPS = 48

local function chipPart(): Part
	local p = Instance.new("Part")
	p.Name = "Chip"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = 1
	p.Parent = folder
	return p
end
for i = 1, CHIPS do
	chips[i] = { part = chipPart(), vel = Vector3.zero, spin = Vector3.zero, life = 0, max = 1 }
end

-- Throws `count` chunks of rock out of `pos`.
function PlanetField.burst(pos: Vector3, color: Color3, count: number, speed: number, size: number)
	if Quality.lite then
		count = math.ceil(count * 0.5)
	end
	for _ = 1, count do
		chipIndex = chipIndex % CHIPS + 1
		local c = chips[chipIndex]
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 + 0.1, math.random() - 0.5).Unit
		local s = size * (0.6 + math.random() * 0.8)
		c.part.Size = Vector3.new(s, s * (0.6 + math.random() * 0.6), s)
		c.part.Color = color:Lerp(Color3.new(1, 1, 1), math.random() * 0.2)
		c.part.CFrame = CFrame.new(pos + dir * size) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		c.part.Transparency = 0
		c.vel = dir * speed * (0.6 + math.random() * 0.7)
		c.spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
		c.max = 0.7 + math.random() * 0.5
		c.life = c.max
	end
end

-- Expanding shockwave ring (one shared part).
local ringPart = Instance.new("Part")
ringPart.Name = "Shockwave"
ringPart.Shape = Enum.PartType.Cylinder
ringPart.Anchored = true
ringPart.CanCollide = false
ringPart.CanQuery = false
ringPart.CanTouch = false
ringPart.CastShadow = false
ringPart.Material = Enum.Material.Neon
ringPart.Transparency = 1
ringPart.Size = Vector3.new(0.4, 2, 2)
ringPart.Parent = folder
local function shockwave(pos: Vector3, radius: number, color: Color3)
	ringPart.Color = color
	ringPart.Size = Vector3.new(0.5, radius, radius)
	ringPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ringPart.Transparency = 0.15
	TweenService:Create(ringPart, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, radius * 5, radius * 5), Transparency = 1 }):Play()
end

type Floater = { anchor: Part, gui: BillboardGui, label: TextLabel, stroke: UIStroke, life: number, max: number, rise: number, base: Vector3 }
local floaters: { Floater } = {}
local floaterIndex = 0
local FLOATERS = 20
for i = 1, FLOATERS do
	local anchor = Instance.new("Part")
	anchor.Name = "Floater"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(11, 2.4)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	floaters[i] = { anchor = anchor, gui = gui, label = label, stroke = stroke, life = 0, max = 1, rise = 6, base = Vector3.zero }
end

-- Text that floats up from a point in the world ("+1.2K", "CRIT!", drops).
function PlanetField.float(pos: Vector3, text: string, color: Color3, scale: number?, seconds: number?)
	floaterIndex = floaterIndex % FLOATERS + 1
	local f = floaters[floaterIndex]
	local s = scale or 1
	f.base = pos + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)
	f.anchor.CFrame = CFrame.new(f.base)
	f.gui.Size = UDim2.fromScale(11 * s, 2.4 * s)
	f.label.Text = text
	f.label.TextColor3 = color
	f.label.TextTransparency = 0
	f.stroke.Transparency = 0
	f.max = seconds or 0.9
	f.life = f.max
	f.rise = 5 + s * 2
	f.gui.Enabled = true
end

---------------------------------------------------------------------------
-- Planets
---------------------------------------------------------------------------
local function kindColor(kindId: string, zone: number): Color3
	if kindId == "rock" then
		return Themes.get(zone).rock
	end
	return Palette.rgb(Config.PlanetKindById[kindId].color)
end

local function layerColor(view: View, zone: number, layer: number): Color3
	local theme = Themes.get(zone)
	local base = kindColor(view.kind, zone)
	if layer == 1 then
		return base
	elseif layer == 2 then
		return if view.kind == "rock" then theme.rockMantle else base:Lerp(Color3.new(1, 1, 1), 0.25)
	end
	return if view.kind == "rock" then theme.rockCore else base:Lerp(Color3.new(1, 1, 1), 0.6)
end

local function updateGui(view: View)
	if view.fill and view.hpText then
		local frac = if view.max > 0 then math.clamp(view.hp / view.max, 0, 1) else 0
		view.fill.Size = UDim2.fromScale(frac, 1)
		view.hpText.Text = Format.abbrev(math.ceil(view.hp)) .. " / " .. Format.abbrev(view.max)
	end
	if view.gui then
		view.gui.Enabled = view.alive
	end
end

local function buildGui(view: View, zone: number, root: BasePart)
	local kind = Config.PlanetKindById[view.kind]
	local gui = Instance.new("BillboardGui")
	gui.Name = "PlanetGui"
	local wide = kind.boss or kind.special
	gui.Size = if wide then UDim2.fromScale(20, 5) else UDim2.fromScale(12, 3.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, view.radius + (if wide then 4.5 else 2.8), 0)
	gui.MaxDistance = if wide then 260 else 95
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.5)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	local c = kindColor(view.kind, zone):Lerp(Color3.new(1, 1, 1), 0.35)
	name.TextColor3 = c
	local text = Lang.planet(view.kind)
	if view.kind == "gate" and Config.Zones[zone + 1] then
		text = Lang.t("world.gate_to", { zone = Lang.zone(zone + 1) })
	elseif view.dense then
		text = Lang.t("planet.dense", { planet = text })
	end
	name.Text = text
	local st = Instance.new("UIStroke")
	st.Thickness = 2.5
	st.Color = INK
	st.Parent = name
	name.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(0.86, 0.34)
	bar.Position = UDim2.fromScale(0.07, 0.56)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 46)
	bar.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = bar
	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 2.5
	barStroke.Color = INK
	barStroke.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if view.kind == "gate" then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(90, 230, 110)
	fill.BorderSizePixel = 0
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.4, 0)
	fc.Parent = fill
	fill.Parent = bar
	local hp = Instance.new("TextLabel")
	hp.Name = "Hp"
	hp.BackgroundTransparency = 1
	hp.Size = UDim2.fromScale(1, 1)
	hp.Font = Enum.Font.FredokaOne
	hp.TextScaled = true
	hp.TextColor3 = Color3.new(1, 1, 1)
	hp.ZIndex = 2
	local hs = Instance.new("UIStroke")
	hs.Thickness = 2
	hs.Color = INK
	hs.Parent = hp
	hp.Parent = bar
	bar.Parent = gui
	gui.Parent = root
	view.gui = gui
	view.fill = fill
	view.hpText = hp
end

local function destroyView(view: View)
	if view.model then
		view.model:Destroy()
		view.model = nil
	end
	view.gui = nil
	view.fill = nil
	view.hpText = nil
end

local function buildModel(view: View, zone: number)
	if view.model then
		view.model:Destroy()
	end
	local model = PlanetModel.build(view.kind, zone, { lite = Quality.lite, dense = view.dense, variant = view.variant })
	view.radius = (model:GetAttribute("Radius") :: number?) or 4
	model:PivotTo(CFrame.new(view.pos))
	PlanetModel.setLayer(model, if view.alive then view.layer else 4)
	model.Parent = folder
	view.model = model
	buildGui(view, zone, model.PrimaryPart :: BasePart)
	updateGui(view)
end

local function applyNode(zone: number, data: any, dropIn: boolean)
	local n = data.n :: number
	local kind = Config.PlanetKinds[data.k]
	if not kind then
		return
	end
	local p = Layout.nodePosition(zone, n)
	local old = PlanetField.views[n]
	if old then
		destroyView(old)
	end
	local view: View = {
		n = n,
		kind = kind.id,
		layer = data.l,
		hp = data.h,
		max = data.m,
		dense = data.d == true,
		alive = data.r == nil,
		pos = Vector3.new(p[1], p[2], p[3]),
		radius = kind.size / 2,
		shakeAt = -10,
		dropAt = if dropIn then os.clock() else -10,
		spin = 0.25 + (n % 4) * 0.07,
		respawnAt = if data.r then os.clock() + data.r else nil,
		variant = math.random(),
	}
	PlanetField.views[n] = view
	buildModel(view, zone)
end

local function clear()
	for _, view in PlanetField.views do
		destroyView(view)
	end
	table.clear(PlanetField.views)
end

local loadToken = 0
-- Fetches the galaxy's planets from the server and rebuilds the field.
function PlanetField.load(zone: number?)
	loadToken += 1
	local token = loadToken
	if not zone then
		PlanetField.zone = nil
		clear()
		changed:Fire(nil)
		return
	end
	PlanetField.loading = true
	local ok, list = Net.request("GetNodes", { zone = zone })
	if token ~= loadToken then
		return
	end
	PlanetField.loading = false
	clear()
	PlanetField.zone = zone
	if ok and type(list) == "table" then
		for _, data in list do
			applyNode(zone, data, false)
		end
	end
	changed:Fire(nil)
end

function PlanetField.reload()
	local zone = PlanetField.zone
	if zone then
		task.spawn(PlanetField.load, zone)
	end
end

-- Planet hit by a ray (camera click), nearest first.
function PlanetField.pick(origin: Vector3, direction: Vector3): View?
	local dir = direction.Unit
	local best: View?, bestT = nil, math.huge
	for _, view in PlanetField.views do
		if view.alive then
			local oc = view.pos - origin
			local t = oc:Dot(dir)
			if t > 0 then
				local d2 = oc:Dot(oc) - t * t
				local r = view.radius * 1.15
				if d2 <= r * r and t < bestT then
					best, bestT = view, t
				end
			end
		end
	end
	return best
end

-- Horizontal distance from a point to the planet's surface (what the server checks).
function PlanetField.distance(view: View, pos: Vector3): number
	local dx, dz = pos.X - view.pos.X, pos.Z - view.pos.Z
	return math.sqrt(dx * dx + dz * dz) - Config.PlanetKindById[view.kind].size / 2
end

function PlanetField.nearest(pos: Vector3, range: number, includeGate: boolean?): View?
	local best: View?, bestD = nil, math.huge
	for _, view in PlanetField.views do
		if view.alive and (includeGate or view.kind ~= "gate") then
			local d = PlanetField.distance(view, pos)
			if d <= range and d < bestD then
				best, bestD = view, d
			end
		end
	end
	return best
end

-- Local feedback for a hit the client just sent (before the server answers).
function PlanetField.punch(view: View)
	view.shakeAt = os.clock()
	local zone = PlanetField.zone or 1
	PlanetField.burst(view.pos + Vector3.new(0, 0, 0), layerColor(view, zone, view.layer), 2, 16, view.radius * 0.16)
end

local function onMine(msg: any)
	local zone = PlanetField.zone
	if not zone or msg.z ~= zone or msg.full then
		return
	end
	local view = PlanetField.views[msg.n]
	if not view then
		return
	end
	local oldLayer = view.layer
	if msg.dmg and msg.dmg > 0 then
		local crit = (msg.c or 0) > 0
		PlanetField.float(view.pos + Vector3.new(0, view.radius * 0.4, 0), (if crit then "💥 " else "") .. Format.abbrev(msg.dmg), if msg.soft then Color3.fromRGB(170, 170, 185) elseif crit then Color3.fromRGB(255, 220, 70) else Color3.new(1, 1, 1), if crit then 1.25 else 0.9)
		if msg.a then
			view.shakeAt = os.clock()
		end
	end
	if msg.b and msg.b > 0 then
		-- layers cracked open: chunks of the layer that broke fly off
		for layer = oldLayer, math.min(oldLayer + msg.b - 1, 3) do
			PlanetField.burst(view.pos, layerColor(view, zone, layer), 10, 34, view.radius * 0.3 * (if layer == 1 then 1 elseif layer == 2 then 0.75 else 0.5))
		end
		if msg.sd and msg.sd > 0 then
			PlanetField.float(view.pos + Vector3.new(0, view.radius + 1, 0), "+" .. Format.abbrev(msg.sd) .. " ⛏️", Color3.fromRGB(110, 240, 130), 1.1, 1.2)
		end
	end
	view.layer = msg.l
	view.hp = msg.h
	if msg.m and msg.m > 0 then
		view.max = msg.m
	end
	local drops = msg.drops
	if drops then
		view.alive = false
		view.respawnAt = if msg.r then os.clock() + msg.r else nil
		shockwave(view.pos, view.radius * 1.2, layerColor(view, zone, 3))
		PlanetField.burst(view.pos, layerColor(view, zone, 3), 16, 46, view.radius * 0.3)
		local y = view.radius + 3
		if drops.cr then
			PlanetField.float(view.pos + Vector3.new(0, y, 0), "+" .. drops.cr .. " 💎", Color3.fromRGB(90, 220, 255), 1.2, 1.4)
			y += 2.4
		end
		if drops.mat then
			PlanetField.float(view.pos + Vector3.new(0, y, 0), "+" .. drops.mat .. " " .. Lang.t("material." .. drops.matId), Color3.fromRGB(230, 170, 255), 1.1, 1.4)
			y += 2.4
		end
		if drops.buff then
			local c = if drops.buff == "all" then Color3.fromRGB(60, 240, 220) else (Palette.Buff :: any)[drops.buff]
			PlanetField.float(view.pos + Vector3.new(0, y, 0), "⚡ " .. Lang.t("buff." .. drops.buff), c, 1.3, 1.6)
		end
		if view.model then
			PlanetModel.setLayer(view.model, 4)
		end
		broke:Fire(view, msg)
	elseif view.model and view.layer ~= oldLayer then
		PlanetModel.setLayer(view.model, view.layer)
	end
	updateGui(view)
	changed:Fire(view.n)
end

local function onNode(data: any)
	local zone = PlanetField.zone
	if not zone or data.z ~= zone then
		return
	end
	applyNode(zone, data, true)
	changed:Fire(data.n)
end

local function currentZone(): number?
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root then
		return nil
	end
	local zone = Layout.zoneAt(root.Position.X, root.Position.Z)
	local s = Net.state
	if zone and s and table.find(s.zones, zone) then
		return zone
	end
	return nil
end
PlanetField.currentZone = currentZone

function PlanetField.init()
	Net.event("Mine").OnClientEvent:Connect(onMine)
	Net.event("Node").OnClientEvent:Connect(onNode)

	-- which galaxy am I in?
	task.spawn(function()
		while true do
			local zone = currentZone()
			if zone ~= PlanetField.zone and not PlanetField.loading and Net.state then
				PlanetField.load(zone)
			end
			task.wait(0.3)
		end
	end)
	-- the gate disappears / the next galaxy's planets exist after an unlock or a rebirth
	local lastZones, lastRebirths = 0, 0
	Net.Changed:Connect(function(kind)
		local s = Net.state
		if kind == "full" and s then
			if #s.zones ~= lastZones or s.rebirths ~= lastRebirths then
				local first = lastZones == 0
				lastZones, lastRebirths = #s.zones, s.rebirths
				if not first then
					PlanetField.reload()
				end
			end
		end
	end)
	Quality.Changed:Connect(function()
		local zone = PlanetField.zone
		if zone then
			for _, view in PlanetField.views do
				buildModel(view, zone)
			end
		end
	end)
	Lang.Changed:Connect(function()
		PlanetField.reload()
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for _, view in PlanetField.views do
			local model = view.model
			if model and view.alive then
				local root = model.PrimaryPart :: BasePart
				local offset = Vector3.new(0, math.sin(now * 1.1 + view.n) * 0.35, 0)
				local st = now - view.shakeAt
				if st < 0.18 then
					local k = (1 - st / 0.18) * math.min(0.6, view.radius * 0.07)
					offset += Vector3.new(math.sin(now * 90) * k, math.cos(now * 70) * k, math.sin(now * 110) * k)
				end
				local dropT = now - view.dropAt
				if dropT < 0.45 then
					local a = 1 - dropT / 0.45
					offset += Vector3.new(0, a * a * 26, 0)
				end
				root.CFrame = CFrame.new(view.pos + offset) * CFrame.Angles(0.18, now * view.spin + view.n, 0.1)
			end
		end
		for _, c in chips do
			if c.life > 0 then
				c.life -= dt
				if c.life <= 0 then
					c.part.Transparency = 1
				else
					c.vel += Vector3.new(0, -70 * dt, 0)
					local cf = c.part.CFrame
					c.part.CFrame = CFrame.new(cf.Position + c.vel * dt) * (cf - cf.Position) * CFrame.Angles(c.spin.X * dt, c.spin.Y * dt, c.spin.Z * dt)
					if c.life < 0.25 then
						c.part.Transparency = 1 - c.life / 0.25
					end
				end
			end
		end
		for _, f in floaters do
			if f.life > 0 then
				f.life -= dt
				if f.life <= 0 then
					f.gui.Enabled = false
				else
					local a = 1 - f.life / f.max
					f.anchor.CFrame = CFrame.new(f.base + Vector3.new(0, a * f.rise, 0))
					local fade = math.clamp((a - 0.6) / 0.4, 0, 1)
					f.label.TextTransparency = fade
					f.stroke.Transparency = fade
				end
			end
		end
	end)
end

return PlanetField
