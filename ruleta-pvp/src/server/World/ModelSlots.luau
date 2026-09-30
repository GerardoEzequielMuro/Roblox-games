--!strict
-- Model slots: lets the owner drop real 3D models (Creator Store / Studio AI) into
-- assets/models/<slot>.rbxm without touching code. Rojo turns that folder into
-- ServerStorage.ModelLibrary. Every prop asks for a slot; if the library has a model
-- with that name it is used (scaled to the target box, bottom on the ground, anchored,
-- scripts stripped), otherwise the primitive fallback runs exactly as before.
-- The wheels, the tagged tables (TableRoot), the core and the boards are gameplay and
-- are never slots; only dressing around them is.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelFit = require(ReplicatedStorage.Shared.ModelFit)

local ModelSlots = {}

ModelSlots.MaxPartsPerSlot = 300
ModelSlots.MaxPartsTotal = 1000 -- all model props together (server part budget)

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

local function countParts(inst: Instance): number
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function isUsable(inst: Instance): boolean
	return inst:IsA("Model") or inst:IsA("BasePart")
end

-- Deletes every script of a cloned model (free models may carry malicious ones).
local function stripScripts(root: Instance, slot: string)
	local removed = 0
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, d in list do
		if d:IsA("LuaSourceContainer") and d ~= root then
			d:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		warnOnce("scripts:" .. slot, ("slot '%s': removed %d script(s) from the model"):format(slot, removed))
	end
end

local function setup(root: Instance, collide: boolean)
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, d in list do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = collide
			if not collide then
				d.CanQuery = false
				d.CanTouch = false
			end
		end
	end
end

export type Options = {
	collide: boolean?, -- keep parity with the primitive: walk-on / solid props stay collidable
	maxParts: number?,
}

-- Places a model of the slot (or the fallback) with its bottom-centre at cf.Position,
-- facing cf's rotation, fitted inside targetSize.
function ModelSlots.spawn(slotName: string, cf: CFrame, targetSize: Vector3, parent: Instance, fallback: (() -> Instance?)?, options: Options?): Instance?
	local lib = library()
	local template: Instance? = nil
	if lib then
		local names = {}
		for _, c in lib:GetChildren() do
			if isUsable(c) then
				table.insert(names, c.Name)
			end
		end
		local variants = ModelFit.variantNames(names, slotName)
		if #variants > 0 then
			local pick = variants[ModelFit.pickIndex(#variants, cf.Position.X, cf.Position.Z)]
			template = lib:FindFirstChild(pick)
		end
	end
	if template == nil then
		return if fallback then fallback() else nil
	end

	local cap = (options and options.maxParts) or ModelSlots.MaxPartsPerSlot
	local parts = countParts(template)
	if parts == 0 or not ModelFit.withinBudget(parts, cap, usedParts, ModelSlots.MaxPartsTotal) then
		warnOnce("budget:" .. slotName, ("slot '%s': model has %d parts (cap %d, total used %d/%d), using the primitive"):format(slotName, parts, cap, usedParts, ModelSlots.MaxPartsTotal))
		return if fallback then fallback() else nil
	end

	local collide = if options and options.collide ~= nil then options.collide else false
	local clone = template:Clone()
	stripScripts(clone, slotName)

	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new())
		local bbCF, bbSize = clone:GetBoundingBox()
		local s = ModelFit.fitScale(bbSize.X, bbSize.Y, bbSize.Z, targetSize.X, targetSize.Y, targetSize.Z)
		if s == nil then
			clone:Destroy()
			warnOnce("size:" .. slotName, ("slot '%s': model has an empty bounding box, using the primitive"):format(slotName))
			return if fallback then fallback() else nil
		end
		clone:ScaleTo(clone:GetScale() * s)
		bbCF, bbSize = clone:GetBoundingBox()
		local bottom = bbCF.Position - Vector3.new(0, bbSize.Y / 2, 0)
		clone:PivotTo(cf * CFrame.new(-bottom))
	else
		local part = clone :: BasePart
		local s = ModelFit.fitScale(part.Size.X, part.Size.Y, part.Size.Z, targetSize.X, targetSize.Y, targetSize.Z)
		if s == nil then
			clone:Destroy()
			return if fallback then fallback() else nil
		end
		part.Size = part.Size * s
		part.CFrame = cf * CFrame.new(0, part.Size.Y / 2, 0)
	end
	setup(clone, collide)
	usedParts += parts
	clone.Name = slotName
	clone.Parent = parent
	return clone
end

-- For the playtest / diagnostics.
function ModelSlots.usedParts(): number
	return usedParts
end

return ModelSlots
