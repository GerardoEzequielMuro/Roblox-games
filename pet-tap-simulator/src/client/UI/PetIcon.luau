--!strict
-- ViewportFrame thumbnails of procedural pets (inventory, index, egg odds, hatch reveal).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetModel = require(ReplicatedStorage.Shared.PetModel)

local PetIcon = {}

-- Points the viewport camera at the model's bounding box from the front (the pet faces -Z).
-- fill: 1 = the bounding sphere just fits; bigger values zoom out.
function PetIcon.frame(cam: Camera, model: Model, fill: number?)
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude * 0.5
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * (fill or 0.84)
	local center = cf.Position
	cam.CFrame = CFrame.lookAt(center + Vector3.new(0, radius * 0.22, -dist), center)
end

-- silhouette = true renders the pet as a black shape (undiscovered in the index).
function PetIcon.new(petId: string, tier: number?, silhouette: boolean?, yaw: number?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(190, 190, 205)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -2, 1.5)
	if silhouette then
		vp.ImageColor3 = Color3.new(0, 0, 0)
	end
	local model = PetModel.build(petId, tier or 0, { lite = true })
	model:PivotTo(CFrame.Angles(0, math.rad(yaw or 28), 0))
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	PetIcon.frame(cam, model)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

return PetIcon
