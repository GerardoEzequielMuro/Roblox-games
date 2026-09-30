--!strict
-- Model slots: lets real 3D models (Creator Store / Toolbox / Studio AI) replace the primitive
-- props WITHOUT touching code. Drop `<slot>.rbxm` (or `<slot>_1.rbxm`, `<slot>_2.rbxm`...) into
-- assets/models/; Rojo maps that folder to ServerStorage.ModelLibrary. No file -> fallback().
-- Every Script/LocalScript/ModuleScript inside a cloned model is deleted (free models can be
-- malicious). Models over the per-slot part cap, or past the global budget, use the fallback.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModelFit = require(ReplicatedStorage.Shared.ModelFit)

local ModelSlots = {}

ModelSlots.SlotPartCap = 300
ModelSlots.TotalPartCap = 1200
local usedParts = 0
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[ModelSlots] " .. msg)
	end
end

local function library(): Instance?
	return ServerStorage:FindFirstChild("ModelLibrary")
end

local function isUsable(i: Instance): boolean
	return i:IsA("Model") or i:IsA("BasePart")
end

-- Names present in the library (Model / BasePart children only).
local function libraryNames(): { [string]: boolean }
	local has: { [string]: boolean } = {}
	local lib = library()
	if lib then
		for _, c in lib:GetChildren() do
			if isUsable(c) then
				has[c.Name] = true
			end
		end
	end
	return has
end

function ModelSlots.hasSlot(slotName: string): boolean
	return #ModelFit.variantNames(slotName, libraryNames()) > 0
end

local function stripScripts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
			n += 1
		end
	end
	if root:IsA("LuaSourceContainer") then
		n += 1
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

-- collide: true keeps every part collidable (walk-on/solid fallback); false makes it decorative.
local function prepare(root: Instance, collide: boolean)
	local function fix(p: BasePart)
		p.Anchored = true
		p.CanCollide = collide
		p.CanTouch = false
		p.CanQuery = collide
		p.Massless = true
	end
	if root:IsA("BasePart") then
		fix(root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			fix(d)
		end
	end
end

export type Options = { collide: boolean?, variantKey: Vector3?, yaw: number? }

-- Places the model (or part) so its bottom-centre sits at cf.Position and it fits targetSize.
-- cf: where the primitive's BOTTOM centre was (rotation = facing). Returns the instance, or the
-- result of fallback() when there is no (usable) model for the slot.
function ModelSlots.spawn(slotName: string, cf: CFrame, targetSize: Vector3, parent: Instance, fallback: () -> Instance?, opts: Options?): Instance?
	local o: Options = opts or {}
	local lib = library()
	if not lib then
		return fallback()
	end
	local names = ModelFit.variantNames(slotName, libraryNames())
	if #names == 0 then
		return fallback()
	end
	local key = o.variantKey or cf.Position
	local pick = names[ModelFit.pickVariant(#names, key.X, key.Z)]
	local template = lib:FindFirstChild(pick)
	if not template or not isUsable(template) then
		return fallback()
	end
	local parts = countParts(template)
	if not ModelFit.withinBudget(parts, ModelSlots.SlotPartCap, usedParts, ModelSlots.TotalPartCap) then
		warnOnce(pick, string.format("%s has %d parts (slot cap %d, used %d/%d): using the primitive build", pick, parts, ModelSlots.SlotPartCap, usedParts, ModelSlots.TotalPartCap))
		return fallback()
	end

	local clone = template:Clone()
	local removed = stripScripts(clone)
	if removed > 0 then
		warnOnce(pick .. "#scripts", string.format("%s: removed %d script(s) found inside the model", pick, removed))
	end
	if clone:IsA("LuaSourceContainer") then
		clone:Destroy()
		return fallback()
	end
	local collide = o.collide == true
	prepare(clone, collide)

	local size: Vector3
	if clone:IsA("Model") then
		size = clone:GetExtentsSize()
	else
		size = (clone :: BasePart).Size
	end
	local scale = ModelFit.fitScale({ size.X, size.Y, size.Z }, { targetSize.X, targetSize.Y, targetSize.Z })
	local finalHeight: number
	if clone:IsA("Model") then
		clone:ScaleTo(clone:GetScale() * scale)
		finalHeight = clone:GetExtentsSize().Y
		-- bounding-box centre -> bottom centre at cf.Position
		local bbCF, bbSize = clone:GetBoundingBox()
		local pivotOffset = bbCF:ToObjectSpace(clone:GetPivot())
		local target = cf * CFrame.new(0, bbSize.Y / 2, 0)
		clone:PivotTo(target * pivotOffset)
	else
		local bp = clone :: BasePart
		bp.Size = size * scale
		finalHeight = bp.Size.Y
		bp.CFrame = cf * CFrame.new(0, finalHeight / 2, 0)
	end
	clone:SetAttribute("ModelSlot", pick)
	clone.Parent = parent
	usedParts += parts
	return clone
end

function ModelSlots.usedParts(): number
	return usedParts
end

return ModelSlots
