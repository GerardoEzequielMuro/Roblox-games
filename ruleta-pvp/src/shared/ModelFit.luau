--!strict
-- Pure maths behind the model slots (no Roblox API, so it runs in plain `luau`):
-- how much to scale a dropped-in model to fit a target box, and which variant
-- (slot, slot_1, slot_2...) a prop at a given position gets.
local ModelFit = {}

-- Uniform scale that makes a box of size (sx, sy, sz) fit inside the target box
-- keeping proportions. Returns nil when either box is degenerate.
function ModelFit.fitScale(sx: number, sy: number, sz: number, tx: number, ty: number, tz: number): number?
	if sx <= 1e-4 or sy <= 1e-4 or sz <= 1e-4 then
		return nil
	end
	if tx <= 0 or ty <= 0 or tz <= 0 then
		return nil
	end
	return math.min(tx / sx, ty / sy, tz / sz)
end

-- "tree" -> 0, "tree_3" -> 3, anything else -> nil.
function ModelFit.variantIndex(name: string, slot: string): number?
	if name == slot then
		return 0
	end
	local prefix = slot .. "_"
	if name:sub(1, #prefix) ~= prefix then
		return nil
	end
	local rest = name:sub(#prefix + 1)
	if rest == "" or rest:find("^%d+$") == nil then
		return nil
	end
	return tonumber(rest)
end

-- Given every child name of the library, the variants of a slot ordered by index
-- (slot, slot_1, slot_2, ...). Duplicated names are collapsed.
function ModelFit.variantNames(names: { string }, slot: string): { string }
	local found: { { idx: number, name: string } } = {}
	local seen: { [string]: boolean } = {}
	for _, n in names do
		local idx = ModelFit.variantIndex(n, slot)
		if idx ~= nil and not seen[n] then
			seen[n] = true
			table.insert(found, { idx = idx, name = n })
		end
	end
	table.sort(found, function(a, b)
		if a.idx ~= b.idx then
			return a.idx < b.idx
		end
		return a.name < b.name
	end)
	local out = {}
	for _, f in found do
		table.insert(out, f.name)
	end
	return out
end

-- Deterministic 1-based pick from `count` variants by world position, so the same
-- prop always gets the same model but neighbours differ.
function ModelFit.pickIndex(count: number, x: number, z: number): number
	if count <= 1 then
		return 1
	end
	local ix = math.floor(x * 10 + 0.5) % 1000003
	local iz = math.floor(z * 10 + 0.5) % 999983
	local h = (ix * 73856093 + iz * 19349663) % 2147483647
	return h % count + 1
end

-- Whether a model of `parts` parts may be used given the per-slot cap and what is
-- left of the global model budget.
function ModelFit.withinBudget(parts: number, perSlotCap: number, usedTotal: number, totalCap: number): boolean
	return parts <= perSlotCap and usedTotal + parts <= totalCap
end

return ModelFit
