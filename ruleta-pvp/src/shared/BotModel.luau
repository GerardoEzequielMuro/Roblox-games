--!strict
-- The bots' bodies: a chunky cartoon robot made of a dozen anchored parts. Built by the
-- server when a bot takes a seat; clients animate it (hops, shakes, the finisher) by
-- pivoting the model locally.
local BotModel = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

-- `root` is where a character's HumanoidRootPart would be (3 studs above the floor).
function BotModel.build(color: Color3, root: CFrame, variant: number): Model
	local model = Instance.new("Model")
	model.Name = "Bot"
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.45)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.5)
	local rootPart = part(model, "Root", Vector3.new(2, 2, 1), root, color)
	rootPart.Transparency = 1
	model.PrimaryPart = rootPart
	-- hover base and body
	part(model, "Base", Vector3.new(0.7, 2.6, 2.6), root * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90)), dark, nil, Enum.PartType.Cylinder)
	part(model, "Glow", Vector3.new(0.25, 2, 2), root * CFrame.new(0, -2.9, 0) * CFrame.Angles(0, 0, math.rad(90)), light, Enum.Material.Neon, Enum.PartType.Cylinder)
	part(model, "Body", Vector3.new(2.6, 2.6, 1.9), root * CFrame.new(0, -0.7, 0), color)
	part(model, "Belly", Vector3.new(1.5, 1.1, 0.2), root * CFrame.new(0, -0.8, -0.95), light)
	-- head: three silhouettes
	local headSize = if variant % 3 == 0 then Vector3.new(2.6, 2, 2.2) elseif variant % 3 == 1 then Vector3.new(2.3, 2.3, 2.3) else Vector3.new(3, 1.7, 2.1)
	local head = part(model, "Head", headSize, root * CFrame.new(0, 1.75, 0), color, nil, if variant % 3 == 1 then Enum.PartType.Ball else Enum.PartType.Block)
	head.Name = "Head"
	part(model, "Visor", Vector3.new(headSize.X * 0.78, headSize.Y * 0.5, 0.2), root * CFrame.new(0, 1.8, -headSize.Z / 2 + 0.02), Color3.fromRGB(18, 20, 44))
	part(model, "EyeL", Vector3.new(0.42, 0.55, 0.12), root * CFrame.new(-0.5, 1.85, -headSize.Z / 2 - 0.08), Color3.fromRGB(120, 255, 240), Enum.Material.Neon)
	part(model, "EyeR", Vector3.new(0.42, 0.55, 0.12), root * CFrame.new(0.5, 1.85, -headSize.Z / 2 - 0.08), Color3.fromRGB(120, 255, 240), Enum.Material.Neon)
	-- antenna
	part(model, "Antenna", Vector3.new(0.2, 1.1, 0.2), root * CFrame.new(0, 1.75 + headSize.Y / 2 + 0.5, 0), dark)
	part(model, "Bulb", Vector3.new(0.7, 0.7, 0.7), root * CFrame.new(0, 1.75 + headSize.Y / 2 + 1.2, 0), light, Enum.Material.Neon, Enum.PartType.Ball)
	-- arms
	part(model, "ArmL", Vector3.new(0.7, 2, 0.7), root * CFrame.new(-1.75, -0.6, 0) * CFrame.Angles(0, 0, math.rad(-10)), dark)
	part(model, "ArmR", Vector3.new(0.7, 2, 0.7), root * CFrame.new(1.75, -0.6, 0) * CFrame.Angles(0, 0, math.rad(10)), dark)
	part(model, "HandL", Vector3.new(0.95, 0.95, 0.95), root * CFrame.new(-1.95, -1.75, 0), light, nil, Enum.PartType.Ball)
	part(model, "HandR", Vector3.new(0.95, 0.95, 0.95), root * CFrame.new(1.95, -1.75, 0), light, nil, Enum.PartType.Ball)
	return model
end

BotModel.PartCount = 15

return BotModel
