--!strict
-- Model slots: real 3D models (Creator Store / Toolbox / Studio AI) replace primitive props
-- WITHOUT touching code. Drop `<slot>.rbxm` (or `<slot>_1.rbxm`, `<slot>_2.rbxm`...) into
-- assets/models/; Rojo maps that folder to ServerStorage.ModelLibrary. No file for the slot ->
-- `fallback()` runs, exactly the old primitive build (an empty library changes nothing).
--
-- Safety: every Script / LocalScript / ModuleScript inside a cloned model is deleted (free models
-- can carry malicious code). A model over the per-slot part cap, or past the total budget, is
-- skipped and the primitive build is used. Server-built props only: this game builds all its
-- world props on the server, so the library lives in ServerStorage (clients never see it).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModelFit = require(ReplicatedStorage.Shared.ModelFit)

local ModelSlots = {}

ModelSlots.SlotPartCap = 300 -- parts of one model
ModelSlots.TotalPartCap = 2000 -- parts of every model placed (scenery budget is 4200)
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

local function libraryNames(lib: Instance): { [string]: boolean }
	local has: { [string]: boolean } = {}
	for _, c in lib:GetChildren() do
		if isUsable(c) then
			has[c.Name] = true
		end
	end
	return has
end

function ModelSlots.hasSlot(slotName: string): boolean
	local lib = library()
	return lib ~= nil and #ModelFit.variantNames(slotName, libraryNames(lib)) > 0
end

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

-- collide: true keeps the whole model solid (fallback was solid); false = decorative (no
-- collision, no touch, no queries, no shadows: same as Scenery.deco).
local function prepare(root: Instance, collide: boolean)
	local function fix(p: BasePart)
		p.Anchored = true
		p.CanCollide = collide
		p.CanTouch = false
		p.CanQuery = collide
		p.CastShadow = false
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

export type Options = { collide: boolean?, variantKey: Vector3?, name: string?, maxParts: number? }

-- cf: the BOTTOM CENTRE of the prop (rotation = facing), i.e. where the primitive's lowest point
-- was. targetSize: bounding box the model is scaled to fit (uniform, proportions kept).
-- parent may be nil (the caller parents it after setting attributes). Returns the placed model/part, or whatever fallback() returns when the slot has no usable model.
function ModelSlots.spawn(slotName: string, cf: CFrame, targetSize: Vector3, parent: Instance?, fallback: () -> Instance?, opts: Options?): Instance?
	local o: Options = opts or {}
	local lib = library()
	if not lib then
		return fallback()
	end
	local names = ModelFit.variantNames(slotName, libraryNames(lib))
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
	if not ModelFit.withinBudget(parts, math.min(o.maxParts or ModelSlots.SlotPartCap, ModelSlots.SlotPartCap), usedParts, ModelSlots.TotalPartCap) then
		warnOnce(pick, ("%s has %d parts (cap %d, used %d/%d): using the primitive build"):format(pick, parts, math.min(o.maxParts or ModelSlots.SlotPartCap, ModelSlots.SlotPartCap), usedParts, ModelSlots.TotalPartCap))
		return fallback()
	end

	local clone = template:Clone()
	local removed = stripScripts(clone)
	if removed > 0 then
		warnOnce(pick .. "#scripts", ("%s: removed %d script(s) found inside the model"):format(pick, removed))
	end
	prepare(clone, o.collide == true)

	if clone:IsA("Model") then
		local size = clone:GetExtentsSize()
		local scale = ModelFit.fitScale({ size.X, size.Y, size.Z }, { targetSize.X, targetSize.Y, targetSize.Z })
		clone:ScaleTo(clone:GetScale() * scale)
		-- bounding-box bottom centre -> cf
		local bbCF, bbSize = clone:GetBoundingBox()
		local pivotOffset = bbCF:ToObjectSpace(clone:GetPivot())
		clone:PivotTo(cf * CFrame.new(0, bbSize.Y / 2, 0) * pivotOffset)
	else
		local bp = clone :: BasePart
		local size = bp.Size
		local scale = ModelFit.fitScale({ size.X, size.Y, size.Z }, { targetSize.X, targetSize.Y, targetSize.Z })
		bp.Size = size * scale
		bp.CFrame = cf * CFrame.new(0, bp.Size.Y / 2, 0)
	end
	if o.name then
		clone.Name = o.name
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
