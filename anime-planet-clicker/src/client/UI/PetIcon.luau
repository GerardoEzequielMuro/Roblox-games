--!strict
-- ViewportFrame thumbnails of the procedural models (pets, planets, tools).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetModel = require(ReplicatedStorage.Shared.PetModel)
local PlanetModel = require(ReplicatedStorage.Shared.PlanetModel)
local ToolModel = require(ReplicatedStorage.Shared.ToolModel)

local PetIcon = {}

-- Points the viewport camera at the model's bounding box from the front (-Z).
function PetIcon.frame(cam: Camera, model: Model, fill: number?, side: Vector3?)
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude * 0.5
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * (fill or 0.84)
	local center = cf.Position
	local dir = (side or Vector3.new(0, 0.22, -1)).Unit
	cam.CFrame = CFrame.lookAt(center + dir * dist, center)
end

local function viewport(silhouette: boolean?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(190, 190, 205)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -2, 1.5)
	if silhouette then
		vp.ImageColor3 = Color3.new(0, 0, 0)
	end
	return vp
end

local function finish(vp: ViewportFrame, model: Model, fill: number?, side: Vector3?): ViewportFrame
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	PetIcon.frame(cam, model, fill, side)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- silhouette = true renders the pet as a black shape (undiscovered in the index).
function PetIcon.new(petId: string, tier: number?, silhouette: boolean?, yaw: number?): ViewportFrame
	local vp = viewport(silhouette)
	local model = PetModel.build(petId, tier or 0, { lite = true })
	model:PivotTo(CFrame.Angles(0, math.rad(yaw or 28), 0))
	return finish(vp, model)
end

function PetIcon.planet(kindId: string, zone: number, silhouette: boolean?): ViewportFrame
	local vp = viewport(silhouette)
	local model = PlanetModel.build(kindId, zone, { lite = false })
	model:PivotTo(CFrame.Angles(0.3, 0.6, 0.15))
	return finish(vp, model, 0.8)
end

function PetIcon.tool(toolId: string, silhouette: boolean?): ViewportFrame
	local vp = viewport(silhouette)
	local model = ToolModel.build(toolId)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(35)))
	return finish(vp, model, 0.72, Vector3.new(0, 0.1, -1))
end

return PetIcon
