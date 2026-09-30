--!strict
-- Model slots: lets real 3D models (Creator Store / Toolbox / Studio AI) replace the primitive props WITHOUT code.
-- Drop `<slot>.rbxm` (or `<slot>_1.rbxm`, `<slot>_2.rbxm` for variants) in assets/models/; Rojo maps that folder to
-- ServerStorage.ModelLibrary. With an empty library every slot runs its primitive `fallback`, exactly as before.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelFit = require(ReplicatedStorage.Shared.ModelFit)

local ModelSlots = {}

ModelSlots.LIBRARY = "ModelLibrary"
ModelSlots.DEFAULT_PART_CAP = 300 -- parts per single model
ModelSlots.TOTAL_PART_CAP = 6000 -- parts across every model the library puts in the world
ModelSlots.used = 0 -- parts placed so far
ModelSlots.placed = {} :: { [string]: number } -- slot -> how many models were placed

export type Options = {
	collide: string?, -- "solid": every part collidable (ground-like / walk-into props). "decor": nothing collides. Default "decor".
	collider: Vector3?, -- with "decor": invisible solid block, as fractions of the target size (e.g. a tree trunk), bottom-centered
	query: boolean?, -- CanQuery of the parts (default true for "solid", false for "decor")
	offset: Vector3?, -- where the model's bottom-center goes, in `cf` space (for props whose origin is not their center)
	maxParts: number?, -- cap for this slot (default DEFAULT_PART_CAP)
	name: string?, -- name of the placed model (default: slot name)
}

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[ModelSlots] " .. msg)
	end
end

local function library(): Instance?
	return ServerStorage:FindFirstChild(ModelSlots.LIBRARY)
end

local function usable(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("Model") or inst:IsA("BasePart"))
end

-- True when the library holds at least one model for this slot.
function ModelSlots.has(slotName: string): boolean
	local lib = library()
	if not lib then
		return false
	end
	return usable(lib:FindFirstChild(slotName)) or usable(lib:FindFirstChild(slotName .. "_1"))
end

-- Deletes every script inside the model (free Toolbox models can hide malicious code). Returns how many it removed.
local function stripScripts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
			n += 1
		end
	end
	return n
end

local function countParts(root: Instance): number
	local n = if root:IsA("BasePart") then 1 else 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Places a model for the slot, or runs the primitive `fallback` when the slot is empty / over budget / broken.
--   cf          ground-level frame of the prop (its front is -Z, like the primitives)
--   targetSize  the box (studs) the model is scaled to fit, keeping proportions
function ModelSlots.spawn(slotName: string, cf: CFrame, targetSize: Vector3, parent: Instance, fallback: () -> Instance?, opts: Options?): Instance?
	local lib = library()
	if not lib then
		return fallback()
	end
	local has = function(n: string): boolean
		return usable(lib:FindFirstChild(n))
	end
	local pick = ModelFit.choose(slotName, has, cf.X, cf.Z)
	if not pick then
		return fallback()
	end
	local template = lib:FindFirstChild(pick)
	if not template then
		return fallback()
	end
	local o: Options = opts or {}

	-- budget check on the template itself (no clone yet), scripts do not count
	local parts = countParts(template)
	local cap = o.maxParts or ModelSlots.DEFAULT_PART_CAP
	if not ModelFit.withinBudget(parts, cap, ModelSlots.used, ModelSlots.TOTAL_PART_CAP) then
		warnOnce(pick, string.format("%s has %d parts (slot cap %d, world %d/%d): using the primitive version", pick, parts, cap, ModelSlots.used, ModelSlots.TOTAL_PART_CAP))
		return fallback()
	end

	local clone = template:Clone()
	local stripped = stripScripts(clone)
	if stripped > 0 then
		warnOnce(pick .. "#scripts", string.format("%s contained %d script(s): removed (never run scripts from library models)", pick, stripped))
	end

	local model: Model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		clone.Parent = model
	end
	model.Name = o.name or slotName

	-- normalise: identity pivot, measure, scale uniformly to fit, re-measure
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	local factor = ModelFit.scaleFactor(size.X, size.Y, size.Z, targetSize.X, targetSize.Y, targetSize.Z)
	if factor ~= 1 then
		model:ScaleTo(model:GetScale() * factor)
	end
	local bbCF, bbSize = model:GetBoundingBox()
	local bottomCenter = bbCF.Position - Vector3.new(0, bbSize.Y / 2, 0)
	local offset = o.offset or Vector3.zero
	model:PivotTo(cf * CFrame.new(offset) * CFrame.new(-bottomCenter))

	-- physics: anchored always; collision parity with the primitive this slot replaces
	local solid = o.collide == "solid"
	local query = if o.query ~= nil then o.query else solid
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = solid
			d.CanQuery = query
			d.CanTouch = false
		end
	end
	if not solid and o.collider then
		local f = o.collider
		local size3 = Vector3.new(bbSize.X * f.X, bbSize.Y * f.Y, bbSize.Z * f.Z)
		local c = Instance.new("Part")
		c.Name = "Collider"
		c.Size = size3
		c.Transparency = 1
		c.Anchored = true
		c.CanCollide = true
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		c.CFrame = cf * CFrame.new(offset) * CFrame.new(0, size3.Y / 2, 0)
		c.Parent = model
	end

	model:SetAttribute("ModelSlot", pick)
	model.Parent = parent
	ModelSlots.used += parts
	ModelSlots.placed[slotName] = (ModelSlots.placed[slotName] or 0) + 1
	return model
end

return ModelSlots
