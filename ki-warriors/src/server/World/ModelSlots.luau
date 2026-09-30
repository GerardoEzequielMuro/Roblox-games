--!strict
-- Model slots: lets real 3D models (Creator Store / Toolbox / Studio AI) replace the primitive
-- props of the world WITHOUT touching code. Drop `<slot>.rbxm` (or `<slot>_1.rbxm`, `_2`... for
-- variants) into assets/models/; Rojo maps that folder to ServerStorage.ModelLibrary.
-- With an empty library every call just runs its fallback (the current primitive build).
--
-- Safety: every Script/LocalScript/ModuleScript inside a cloned model is deleted (free models
-- can carry malicious scripts). Models over the part cap are skipped (fallback is used).
-- Client-side props: this game builds all world props on the SERVER (the client only animates
-- them), so the library lives in ServerStorage and is not replicated to players.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelFit = require(ReplicatedStorage.Shared.ModelFit)

local ModelSlots = {}

ModelSlots.PART_CAP = 300 -- default max BaseParts of one model

export type Opts = {
	collide: boolean?, -- keep the prop walk-on / solid (must match the primitive it replaces); default false
	maxParts: number?, -- per-slot part cap (default PART_CAP)
	budgetLeft: number?, -- parts still available in the world budget
	onPlaced: ((inst: Instance, parts: number) -> ())?,
}

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

function ModelSlots.has(slotName: string): boolean
	local lib = library()
	if not lib then
		return false
	end
	local names = {}
	for _, c in lib:GetChildren() do
		table.insert(names, c.Name)
	end
	return #ModelFit.collectVariants(names, slotName) > 0
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
ModelSlots.countParts = countParts

-- Deletes every script; returns how many were removed.
local function stripScripts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			n += 1
			d:Destroy()
		end
	end
	return n
end

local function prepare(inst: Instance, collide: boolean)
	local function setup(p: BasePart)
		p.Anchored = true
		p.CanCollide = collide
		if not collide then
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	if inst:IsA("BasePart") then
		setup(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			setup(d)
		end
	end
end

function ModelSlots.spawn(slotName: string, cf: CFrame, targetSize: Vector3, parent: Instance, fallback: () -> Instance?, opts: Opts?): Instance?
	local lib = library()
	if lib then
		local names = {}
		for _, c in lib:GetChildren() do
			table.insert(names, c.Name)
		end
		local variants = ModelFit.collectVariants(names, slotName)
		if #variants > 0 then
			local pos = cf.Position
			local pick = variants[ModelFit.pickVariant(#variants, pos.X, pos.Y, pos.Z)]
			local template = lib:FindFirstChild(pick)
			if template and (template:IsA("Model") or template:IsA("BasePart")) then
				local o: Opts = opts or {}
				local parts = countParts(template)
				local cap = o.maxParts or ModelSlots.PART_CAP
				if parts == 0 then
					warnOnce(pick, pick .. " no tiene partes; uso el modelo primitivo")
				elseif not ModelFit.withinBudget(parts, cap, o.budgetLeft) then
					warnOnce(pick, string.format("%s tiene %d partes (tope %d / presupuesto %s); uso el modelo primitivo", pick, parts, cap, tostring(o.budgetLeft)))
				else
					local inst: Instance = template:Clone()
					local removed = stripScripts(inst)
					if removed > 0 then
						warnOnce(pick .. "#scripts", string.format("%s traia %d script(s): eliminados por seguridad", pick, removed))
					end
					prepare(inst, o.collide == true)
					inst.Name = slotName
					inst:SetAttribute("ModelSlot", pick)
					-- fit: uniform scale to the target box, bottom-centre of the box sits on cf
					local ts = { targetSize.X, targetSize.Y, targetSize.Z }
					if inst:IsA("Model") then
						local _, size = inst:GetBoundingBox()
						inst:ScaleTo(inst:GetScale() * ModelFit.fitScale({ size.X, size.Y, size.Z }, ts))
						local bbCf, bbSize = inst:GetBoundingBox()
						local pivotInBox = bbCf:ToObjectSpace(inst:GetPivot())
						inst:PivotTo(cf * CFrame.new(0, bbSize.Y / 2, 0) * pivotInBox)
					else
						local part = inst :: BasePart
						part.Size = part.Size * ModelFit.fitScale({ part.Size.X, part.Size.Y, part.Size.Z }, ts)
						part.CFrame = cf * CFrame.new(0, part.Size.Y / 2, 0)
					end
					inst.Parent = parent
					if o.onPlaced then
						o.onPlaced(inst, parts)
					end
					return inst
				end
			else
				warnOnce(pick, pick .. " debe ser un Model o una parte (MeshPart/Part); uso el modelo primitivo")
			end
		end
	end
	return fallback()
end

return ModelSlots
