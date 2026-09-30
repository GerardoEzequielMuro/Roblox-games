--!strict
-- Procedural mini planets, drawn by each client. PlanetModel.build(kindId, zone, opts)
-- returns a Model: an anchored "Root" at the centre and three nested layers welded to it
-- (Crust > Mantle > Core). Each layer owns a folder of relief (craters, continents, spikes,
-- crystals, rings...) that is hidden with it when the layer breaks.
--
-- The look comes from shape and baked colour (layers, relief, rings, moons), so it still
-- reads at graphics quality 1. opts.lite builds fewer relief parts.
local Config = require(script.Parent.Config)
local Palette = require(script.Parent.Palette)
local Themes = require(script.Parent.Themes)

local PlanetModel = {}

-- variant (0..1): per-planet colour jitter so a field of plain rocks is not a row of clones.
export type BuildOpts = { lite: boolean?, dense: boolean?, scale: number?, variant: number? }

local V = Vector3.new
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end
local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function make(parent: Instance, root: BasePart, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

-- CFrame on a sphere of radius r at direction d, with Y pointing away from the centre.
local function surface(d: Vector3, r: number): CFrame
	local u = d.Unit
	local pos = u * r
	local up = if math.abs(u.Y) > 0.95 then V(1, 0, 0) else V(0, 1, 0)
	local right = up:Cross(u).Unit
	local fwd = u:Cross(right)
	return CFrame.fromMatrix(pos, right, u, fwd)
end

-- Evenly spread directions (Fibonacci sphere), deterministic.
local function directions(n: number, seed: number): { Vector3 }
	local out = {}
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, n - 1 do
		local y = 1 - (i + 0.5) / n * 2
		local rad = math.sqrt(1 - y * y)
		local th = golden * i + seed
		table.insert(out, V(math.cos(th) * rad, y, math.sin(th) * rad))
	end
	return out
end

-- A flat ring around the planet (two crossed thin cylinders would z-fight; one disc reads fine).
local function ring(parent: Instance, root: BasePart, radius: number, width: number, tilt: CFrame, color: Color3, material: Enum.Material?)
	local outer = make(parent, root, "Ring", "Cylinder", V(0.22, radius * 2, radius * 2), tilt * CFrame.Angles(0, 0, math.rad(90)), color, material)
	outer.Transparency = 0.15
	local inner = make(parent, root, "RingGap", "Cylinder", V(0.3, (radius - width) * 2, (radius - width) * 2), tilt * CFrame.Angles(0, 0, math.rad(90)), darken(color, 0.45), SMOOTH)
	inner.Transparency = 0.35
end

-- Crust material of plain rock planets per galaxy (Part materials give the surface a grain
-- the flat SmoothPlastic never had; colours stay baked in, so graphics quality 1 still reads).
local ROCK_MATERIAL: { Enum.Material } = {
	Enum.Material.Sandstone, -- Dawn Belt
	Enum.Material.Slate, -- Verdant Nebula
	Enum.Material.Glacier, -- Frost Halo
	Enum.Material.Basalt, -- Ember Forge
	Enum.Material.Rock, -- Storm Reach
	Enum.Material.Slate, -- Void Crown
}
-- Special kinds with a signature surface (the rest stay smooth and bright).
local KIND_MATERIAL: { [string]: Enum.Material } = {
	fury = Enum.Material.Basalt,
	aurum = Enum.Material.Foil,
	titan = Enum.Material.Slate,
	gate = Enum.Material.DiamondPlate,
}
PlanetModel.ROCK_MATERIAL = ROCK_MATERIAL
PlanetModel.KIND_MATERIAL = KIND_MATERIAL

-- Small hue / saturation / brightness shift, t in 0..1 (0.5 = unchanged).
local function jitter(c: Color3, t: number): Color3
	local h, sat, v = c:ToHSV()
	local d = t - 0.5
	return Color3.fromHSV((h + d * 0.07) % 1, math.clamp(sat * (1 + d * 0.3), 0, 1), math.clamp(v * (1 + d * 0.22), 0, 1))
end
PlanetModel.jitter = jitter

type Relief = (folder: Instance, root: BasePart, r: number, color: Color3, accent: Color3, lite: boolean, seed: number) -> ()

local function craters(folder: Instance, root: BasePart, r: number, color: Color3, _accent: Color3, lite: boolean, seed: number)
	for i, d in directions(if lite then 4 else 8, seed) do
		local s = r * (0.28 + (i % 3) * 0.1)
		local cf = surface(d, r * 0.97)
		make(folder, root, "Crater", "Cylinder", V(r * 0.08, s, s), cf * CFrame.Angles(0, 0, math.rad(90)), darken(color, 0.3))
		if not lite then
			make(folder, root, "CraterRim", "Cylinder", V(r * 0.05, s * 1.28, s * 1.28), surface(d, r * 0.965) * CFrame.Angles(0, 0, math.rad(90)), lighten(color, 0.18))
		end
	end
end

local function continents(folder: Instance, root: BasePart, r: number, _color: Color3, accent: Color3, lite: boolean, seed: number)
	for i, d in directions(if lite then 3 else 6, seed + 1.3) do
		local s = r * (0.5 + (i % 3) * 0.12)
		make(folder, root, "Continent", "Ball", V(s, s, s), CFrame.new(d.Unit * r * 0.8), accent)
	end
end

local function spikes(folder: Instance, root: BasePart, r: number, _color: Color3, accent: Color3, lite: boolean, seed: number)
	for _, d in directions(if lite then 5 else 9, seed + 0.7) do
		local h = r * 0.5
		make(folder, root, "Spike", "Block", V(r * 0.2, h, r * 0.2), surface(d, r + h * 0.3) * CFrame.Angles(0, 0.6, 0), accent)
		if not lite then
			make(folder, root, "SpikeTip", "Block", V(r * 0.11, h * 0.5, r * 0.11), surface(d, r + h * 0.95) * CFrame.Angles(0, 0.6, 0), lighten(accent, 0.4))
		end
	end
end

local function bands(folder: Instance, root: BasePart, r: number, _color: Color3, accent: Color3, lite: boolean, _seed: number)
	for i = -1, 1 do
		if lite and i ~= 0 then
			continue
		end
		local y = i * r * 0.42
		local br = math.sqrt(r * r - y * y) * 1.02
		make(folder, root, "Band", "Cylinder", V(r * 0.2, br * 2, br * 2), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), if i == 0 then accent else lighten(accent, 0.35))
	end
end

local function crystals(folder: Instance, root: BasePart, r: number, _color: Color3, accent: Color3, lite: boolean, seed: number)
	for i, d in directions(if lite then 5 else 10, seed + 2.1) do
		local h = r * (0.4 + (i % 3) * 0.16)
		make(folder, root, "Crystal", "Block", V(r * 0.2, h, r * 0.2), surface(d, r + h * 0.22) * CFrame.Angles(0.2, i, 0.25), if i % 2 == 0 then accent else lighten(accent, 0.45), NEON)
	end
end

local function blobs(folder: Instance, root: BasePart, r: number, _color: Color3, accent: Color3, lite: boolean, seed: number)
	for i, d in directions(if lite then 4 else 7, seed + 0.4) do
		local s = r * (0.42 + (i % 2) * 0.16)
		make(folder, root, "Blob", "Ball", V(s, s, s), CFrame.new(d.Unit * r * 0.9), accent)
	end
end

local function plates(folder: Instance, root: BasePart, r: number, color: Color3, accent: Color3, lite: boolean, seed: number)
	for i, d in directions(if lite then 6 else 12, seed + 3) do
		local s = r * 0.62
		make(folder, root, "Plate", "Block", V(s, r * 0.12, s), surface(d, r * 0.98) * CFrame.Angles(0, i * 0.7, 0), if i % 3 == 0 then accent else darken(color, 0.18))
	end
end

-- Per kind: relief of the crust and of the mantle, extras around the planet.
local KINDS: { [string]: { crust: { Relief }, mantle: { Relief }, ringed: boolean?, moons: number? } } = {
	rock = { crust = { craters, continents }, mantle = { plates } },
	fury = { crust = { spikes, craters }, mantle = { spikes } },
	zephyr = { crust = { bands }, mantle = { bands }, ringed = true },
	clover = { crust = { blobs, craters }, mantle = { blobs } },
	aurum = { crust = { plates, crystals }, mantle = { plates }, ringed = true },
	prism = { crust = { crystals }, mantle = { crystals } },
	titan = { crust = { plates, spikes, craters }, mantle = { plates, crystals }, ringed = true, moons = 2 },
	anomaly = { crust = { crystals, bands }, mantle = { crystals }, ringed = true, moons = 1 },
	gate = { crust = { plates, bands }, mantle = {}, ringed = true },
}

function PlanetModel.build(kindId: string, zone: number, opts: BuildOpts?): Model
	local kind = Config.PlanetKindById[kindId] or Config.PlanetKinds[1]
	local theme = Themes.get(zone)
	local lite = opts ~= nil and opts.lite == true
	local dense = opts ~= nil and opts.dense == true
	local size = kind.size * (if opts and opts.scale then opts.scale else 1) * (if dense then 1.18 else 1)
	local r = size / 2
	local seed = (zone * 7 + #kindId * 3) % 10

	local model = Instance.new("Model")
	model.Name = "Planet_" .. kind.id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	-- colours: plain rock follows the galaxy; special kinds keep their signature colour
	local base = Palette.rgb(kind.color)
	local crustColor, mantleColor, coreColor
	if kind.id == "rock" then
		crustColor, mantleColor, coreColor = theme.rock, theme.rockMantle, theme.rockCore
	elseif kind.id == "gate" then
		crustColor, mantleColor, coreColor = darken(theme.rim, 0.1), theme.accent, theme.accent2
	else
		crustColor, mantleColor, coreColor = base, lighten(base, 0.25):Lerp(theme.rockMantle, 0.35), lighten(base, 0.6)
	end
	local variant = if opts and opts.variant then math.clamp(opts.variant, 0, 1) else 0.5
	if not (kind :: any).boss and not (kind :: any).special and kind.id ~= "gate" then
		crustColor = jitter(crustColor, variant)
	end
	if dense then
		crustColor = darken(crustColor, 0.22)
	end
	local crustMaterial = if kind.id == "rock" then (ROCK_MATERIAL[zone] or SMOOTH) else (KIND_MATERIAL[kind.id] or SMOOTH)
	local accent = if kind.id == "rock" then darken(theme.rock, 0.22):Lerp(theme.accent, 0.25) elseif kind.id == "gate" then theme.accent else darken(base, 0.35)

	local def = KINDS[kind.id] or KINDS.rock
	local layers = { { "Crust", 1, crustColor, crustMaterial }, { "Mantle", 0.72, mantleColor, if kind.id == "rock" and zone == 4 then Enum.Material.CrackedLava else SMOOTH }, { "Core", 0.44, coreColor, NEON } } :: { { any } }
	for i, l in layers do
		local lr = r * l[2]
		local folder = Instance.new("Folder")
		folder.Name = l[1]
		folder.Parent = model
		make(folder, root, "Shell", "Ball", V(lr * 2, lr * 2, lr * 2), CFrame.new(), l[3], l[4])
		if i == 1 then
			for _, relief in def.crust do
				relief(folder, root, lr, crustColor, accent, lite, seed)
			end
			if dense then
				-- dense planets wear a heavy equator belt
				make(folder, root, "Belt", "Cylinder", V(lr * 0.3, lr * 2.08, lr * 2.08), CFrame.Angles(0, 0, math.rad(90)), theme.accent2)
			end
		elseif i == 2 then
			for _, relief in def.mantle do
				relief(folder, root, lr, mantleColor, lighten(mantleColor, 0.35), true, seed + 1)
			end
		else
			-- core: a bright nugget inside a cage, so it is more than a glowing ball
			for _, d in directions(if lite then 4 else 6, seed) do
				make(folder, root, "Facet", "Block", V(lr * 0.7, lr * 0.7, lr * 0.7), CFrame.new(d.Unit * lr * 0.62) * CFrame.Angles(d.X, d.Y, d.Z), lighten(coreColor, 0.35), NEON)
			end
		end
	end

	local extras = Instance.new("Folder")
	extras.Name = "Extras"
	extras.Parent = model
	if def.ringed and not (lite and kind.id == "zephyr") then
		ring(extras, root, r * 1.75, r * 0.34, CFrame.Angles(math.rad(18), 0, math.rad(12)), if kind.id == "gate" then theme.accent2 else lighten(base, 0.35), if kind.id == "anomaly" or kind.id == "gate" then NEON else SMOOTH)
	end
	if kind.id == "gate" then
		-- the lock: a bright bar across the front
		make(extras, root, "Seal", "Block", V(r * 0.5, r * 2.2, r * 0.3), CFrame.new(0, 0, -r * 0.95), theme.accent2, NEON)
		make(extras, root, "SealCross", "Block", V(r * 2.2, r * 0.5, r * 0.3), CFrame.new(0, 0, -r * 0.95), theme.accent2, NEON)
	end
	for i = 1, (def.moons or 0) do
		local moon = make(extras, root, "Moon", "Ball", V(r * 0.36, r * 0.36, r * 0.36), CFrame.new(r * (1.5 + i * 0.35), r * 0.3 * (if i % 2 == 0 then -1 else 1), 0), lighten(crustColor, 0.3))
		moon:SetAttribute("Moon", i)
	end

	model:SetAttribute("Radius", r)
	model:SetAttribute("Kind", kind.id)
	return model
end

-- Shows the planet at `layer` (1 = whole, 2 = mantle, 3 = core; 4 = nothing).
function PlanetModel.setLayer(model: Model, layer: number)
	for i, name in { "Crust", "Mantle", "Core" } do
		local folder = model:FindFirstChild(name)
		if folder then
			local t = if i < layer then 1 else 0
			for _, p in folder:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = t
				end
			end
		end
	end
	local extras = model:FindFirstChild("Extras")
	if extras then
		for _, p in extras:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = if layer > 3 then 1 elseif p.Name == "RingGap" then 0.35 elseif p.Name == "Ring" then 0.15 else 0
			end
		end
	end
end

-- Radius of the visible layer.
function PlanetModel.layerRadius(model: Model, layer: number): number
	local r = (model:GetAttribute("Radius") :: number?) or 4
	return r * (if layer <= 1 then 1 elseif layer == 2 then 0.72 else 0.44)
end

function PlanetModel.partCount(model: Model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return PlanetModel
