--!strict
-- Model slots: lets real 3D models (Creator Store / Toolbox / Studio AI) replace the
-- primitive-built props WITHOUT touching code. Drop `tree.rbxm`, `tree_1.rbxm`, ... into
-- assets/models/ (Rojo maps that folder to ServerStorage.ModelLibrary). If a slot has no
-- model, `fallback` (the current primitive build) runs unchanged.
local ServerStorage = game:GetService("ServerStorage")

local Math = require(script.Parent.ModelSlotsMath)

local ModelSlots = {}

ModelSlots.MAX_VARIANTS = 16
ModelSlots.DEFAULT_SLOT_CAP = 300 -- parts per model; above this the primitive is used
ModelSlots.TOTAL_CAP = 1500 -- parts from library models in the whole world

export type Options = {
	collide: boolean?, -- keep collision parity with the primitive (default false)
	maxParts: number?, -- per-slot part cap (default DEFAULT_SLOT_CAP)
}

local used = 0
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[ModelSlots] " .. msg)
	end
end

-- Called at the start of every world build.
function ModelSlots.resetBudget()
	used = 0
end

function ModelSlots.partsUsed(): number
	return used
end

local function library(): Instance?
	return ServerStorage:FindFirstChild("ModelLibrary")
end

-- Templates present for a slot ("tree", "tree_1", ...), only Models and BaseParts.
local function templates(slot: string): { Instance }
	local lib = library()
	local out: { Instance } = {}
	if not lib then
		return out
	end
	for _, name in Math.variantNames(slot, ModelSlots.MAX_VARIANTS) do
		local child = lib:FindFirstChild(name)
		if child and (child:IsA("Model") or child:IsA("BasePart")) then
			table.insert(out, child)
		end
	end
	return out
end

function ModelSlots.has(slot: string): boolean
	return #templates(slot) > 0
end

-- Free Toolbox models can hide scripts: delete every one (and warn).
local function stripScripts(inst: Instance, slot: string): number
	local removed = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
			removed += 1
		end
	end
	if inst:IsA("LuaSourceContainer") then
		removed += 1
	end
	if removed > 0 then
		warnOnce("scripts:" .. slot, string.format("slot '%s' contained %d script(s); removed them", slot, removed))
	end
	return removed
end

local function countParts(inst: Instance): number
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function configureParts(inst: Instance, collide: boolean)
	local function apply(p: BasePart)
		p.Anchored = true
		p.CanCollide = collide
		p.CanQuery = collide
		p.CanTouch = false -- the world budget: nothing touchable
		p.CastShadow = false -- the world budget: shadow casters
		p.Massless = true
		if collide and p:IsA("MeshPart") then
			p.CollisionFidelity = Enum.CollisionFidelity.Box
		end
	end
	if inst:IsA("BasePart") then
		apply(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			apply(d)
		elseif d:IsA("Constraint") or d:IsA("WeldConstraint") then
			d:Destroy() -- anchored and static: joints only cause trouble
		end
	end
end

-- Scales `inst` to fit targetSize (uniform) and rests its bottom-centre on cf.Position,
-- facing cf's rotation.
local function place(inst: Instance, cf: CFrame, targetSize: Vector3)
	if inst:IsA("Model") then
		local _, size = inst:GetBoundingBox()
		local k = Math.fitScale(size.X, size.Y, size.Z, targetSize.X, targetSize.Y, targetSize.Z)
		inst:ScaleTo(inst:GetScale() * k)
		local boxCf, boxSize = inst:GetBoundingBox()
		local pivotToBox = inst:GetPivot():ToObjectSpace(boxCf)
		local wantBox = cf * CFrame.new(0, boxSize.Y / 2, 0)
		inst:PivotTo(wantBox * pivotToBox:Inverse())
	else
		local part = inst :: BasePart
		local k = Math.fitScale(part.Size.X, part.Size.Y, part.Size.Z, targetSize.X, targetSize.Y, targetSize.Z)
		part.Size = part.Size * k
		part.CFrame = cf * CFrame.new(0, part.Size.Y / 2, 0)
	end
end

-- Spawns the model for `slotName` (or a variant picked from the position) at cf, fitted to
-- targetSize (studs, bottom on cf.Position). With no usable model (none in the library,
-- too many parts, budget spent) it calls `fallback` and returns whatever that returns.
function ModelSlots.spawn(slotName: string, cf: CFrame, targetSize: Vector3, parent: Instance, fallback: () -> Instance?, options: Options?): Instance?
	local list = templates(slotName)
	if #list == 0 then
		return fallback()
	end
	local collide = options ~= nil and options.collide == true
	local cap = if options ~= nil and options.maxParts ~= nil then options.maxParts else ModelSlots.DEFAULT_SLOT_CAP
	local template = list[Math.pickVariant(#list, cf.Position.X, cf.Position.Z)]
	local clone = template:Clone()
	stripScripts(clone, slotName)
	local parts = countParts(clone)
	if not Math.withinBudget(parts, cap, used, ModelSlots.TOTAL_CAP) then
		warnOnce("budget:" .. template.Name, string.format("slot '%s' skipped (%d parts; cap %d, world total %d/%d); using the primitive", template.Name, parts, cap, used, ModelSlots.TOTAL_CAP))
		clone:Destroy()
		return fallback()
	end
	used += parts
	configureParts(clone, collide)
	place(clone, cf, targetSize)
	clone.Name = slotName
	clone:SetAttribute("ModelSlot", slotName)
	if clone:IsA("Model") then
		clone.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	clone.Parent = parent
	return clone
end

return ModelSlots
