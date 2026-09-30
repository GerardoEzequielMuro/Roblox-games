--!strict
-- Procedural mining tools (picks, drills, lasers). ToolModel.build(toolId) returns a Model
-- whose PrimaryPart "Handle" is gripped at its origin; the tool points along -Z and the
-- working end has an Attachment named "Tip". Everything else is welded to the Handle.
local Config = require(script.Parent.Config)
local Palette = require(script.Parent.Palette)

local ToolModel = {}

local V = Vector3.new
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local WOOD = Color3.fromRGB(128, 88, 60)
local DARK = Color3.fromRGB(44, 46, 62)

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end
local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function make(model: Model, handle: BasePart?, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
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
	if handle then
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = p
		w.Parent = p
	end
	p.Parent = model
	return p
end

-- Cylinder whose axis is Z.
local function tube(model: Model, handle: BasePart, name: string, length: number, diameter: number, z: number, color: Color3, material: Enum.Material?): BasePart
	return make(model, handle, name, "Cylinder", V(length, diameter, diameter), CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(90), 0), color, material)
end

function ToolModel.build(toolId: string): Model
	local def = Config.ToolById[toolId] or Config.Tools[1]
	local index = Config.ToolIndex[def.id] or 1
	local color = Palette.rgb(def.color)
	local model = Instance.new("Model")
	model.Name = "Tool_" .. def.id
	local handle = make(model, nil, "Handle", "Block", V(0.4, 0.4, 1.4), CFrame.new(), if def.kind == "pick" then WOOD else DARK)
	model.PrimaryPart = handle
	local tipZ = -3

	if def.kind == "pick" then
		-- shaft along -Z, head across X at the far end
		make(model, handle, "Shaft", "Block", V(0.32, 0.32, 3.2), CFrame.new(0, 0, -1.6), WOOD)
		make(model, handle, "Grip", "Block", V(0.42, 0.42, 0.7), CFrame.new(0, 0, 0.1), darken(color, 0.4))
		make(model, handle, "Collar", "Block", V(0.62, 0.62, 0.5), CFrame.new(0, 0, -3.0), darken(color, 0.25), METAL)
		make(model, handle, "Head", "Block", V(0.5, 1.5, 0.5), CFrame.new(0, 0, -3.0), color, METAL)
		for _, side in { -1, 1 } do
			make(model, handle, "Beak", "Wedge", V(0.42, 0.9, 0.5), CFrame.new(0, side * 1.15, -2.9) * CFrame.Angles(if side == 1 then 0 else math.rad(180), 0, 0) * CFrame.Angles(math.rad(-20), 0, 0), lighten(color, 0.25), METAL)
		end
		if index >= 3 then
			make(model, handle, "Gem", "Ball", V(0.42, 0.42, 0.42), CFrame.new(0, 0, -3.35), lighten(color, 0.5), NEON)
		end
		tipZ = -3.2
	elseif def.kind == "drill" then
		make(model, handle, "Body", "Block", V(1.0, 1.1, 1.8), CFrame.new(0, 0.1, -1.2), color)
		make(model, handle, "BodyBand", "Block", V(1.08, 0.3, 1.86), CFrame.new(0, 0.1, -1.2), darken(color, 0.35))
		make(model, handle, "Grip", "Block", V(0.4, 0.9, 0.4), CFrame.new(0, -0.55, -0.7), DARK)
		tube(model, handle, "Chuck", 0.5, 0.95, -2.3, DARK, METAL)
		-- the bit: stacked shrinking discs, spins (ToolFx turns "Bit")
		local bit = tube(model, handle, "Bit", 0.5, 0.78, -2.8, lighten(color, 0.4), METAL)
		tube(model, bit, "Bit2", 0.45, 0.56, -3.25, Color3.fromRGB(220, 225, 235), METAL)
		tube(model, bit, "Bit3", 0.4, 0.34, -3.65, lighten(color, 0.4), METAL)
		make(model, bit, "BitFin", "Block", V(0.9, 0.12, 0.5), CFrame.new(0, 0, -2.8), Color3.fromRGB(220, 225, 235), METAL)
		if index >= 5 then
			make(model, handle, "Tank", "Ball", V(0.62, 0.62, 0.62), CFrame.new(0, 0.85, -0.9), lighten(color, 0.45), NEON)
		end
		if index >= 7 then
			for _, side in { -1, 1 } do
				make(model, handle, "Exhaust", "Block", V(0.2, 0.2, 0.9), CFrame.new(side * 0.62, 0.3, -0.7), lighten(color, 0.5), NEON)
			end
		end
		tipZ = -3.9
	else -- laser
		make(model, handle, "Body", "Block", V(0.9, 1.0, 2.0), CFrame.new(0, 0.1, -1.1), Color3.fromRGB(232, 236, 245))
		make(model, handle, "Stripe", "Block", V(0.96, 0.26, 2.06), CFrame.new(0, 0.2, -1.1), color, NEON)
		make(model, handle, "Grip", "Block", V(0.4, 0.9, 0.4), CFrame.new(0, -0.55, -0.6), DARK)
		tube(model, handle, "Barrel", 1.5, 0.5, -2.8, DARK, METAL)
		for i = 0, 2 do
			tube(model, handle, "Coil", 0.16, 0.8, -2.3 - i * 0.45, color, NEON)
		end
		make(model, handle, "Lens", "Ball", V(0.6, 0.6, 0.6), CFrame.new(0, 0, -3.65), lighten(color, 0.5), NEON)
		if index >= 10 then
			for _, side in { -1, 1 } do
				make(model, handle, "Fin", "Wedge", V(0.14, 0.7, 1.2), CFrame.new(side * 0.55, 0.5, -1.0) * CFrame.Angles(0, 0, side * -0.5), color)
			end
		end
		if index >= 12 then
			make(model, handle, "Halo", "Cylinder", V(0.12, 1.5, 1.5), CFrame.new(0, 0, -3.2) * CFrame.Angles(0, math.rad(90), 0), lighten(color, 0.3), NEON)
		end
		tipZ = -3.9
	end
	handle.Transparency = if def.kind == "pick" then 0 else 1
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = V(0, 0, tipZ)
	tip.Parent = handle
	model:SetAttribute("Kind", def.kind)
	return model
end

return ToolModel
