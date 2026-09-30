--!strict
-- Pure helpers behind the model slots (see src/server/World/ModelSlots.luau). No Roblox instances here, so
-- tests/modelslots_test.luau can run them with plain `luau`.
local ModelFit = {}

ModelFit.MAX_VARIANTS = 12

-- Uniform scale that makes a box (sx, sy, sz) fit inside the target box (tx, ty, tz) keeping proportions (the tightest axis wins).
-- Degenerate sizes (zero / negative / NaN) return 1 so a broken model never collapses to nothing.
function ModelFit.scaleFactor(sx: number, sy: number, sz: number, tx: number, ty: number, tz: number): number
	local f = math.huge
	local have = { sx, sy, sz }
	local want = { tx, ty, tz }
	for i = 1, 3 do
		if have[i] > 1e-4 and want[i] > 0 then
			f = math.min(f, want[i] / have[i])
		end
	end
	if f == math.huge or f ~= f then
		return 1
	end
	return f
end

-- Deterministic [0, 1) hash of a position on a 1-stud grid (no Random: the world's rng stream stays untouched).
function ModelFit.hash01(x: number, z: number): number
	local ix, iz = math.floor(x + 0.5), math.floor(z + 0.5)
	local h = (ix * 73856093 + iz * 19349663) % 2147483647
	h = (h * 1103515245 + 12345) % 2147483648
	return h / 2147483648
end

-- Variant index 1..count for a position (0 when there are no variants).
function ModelFit.pickVariant(count: number, x: number, z: number): number
	if count <= 0 then
		return 0
	end
	return math.min(count, math.floor(ModelFit.hash01(x, z) * count) + 1)
end

-- Names present in the library for a slot, in order: "slot" (if any) then "slot_1", "slot_2"... until the first gap.
function ModelFit.variantNames(slot: string, has: (string) -> boolean): { string }
	local out = {}
	if has(slot) then
		table.insert(out, slot)
	end
	for i = 1, ModelFit.MAX_VARIANTS do
		local n = slot .. "_" .. i
		if not has(n) then
			break
		end
		table.insert(out, n)
	end
	return out
end

-- Which library entry to use at a position, or nil when the slot is empty.
function ModelFit.choose(slot: string, has: (string) -> boolean, x: number, z: number): string?
	local names = ModelFit.variantNames(slot, has)
	local i = ModelFit.pickVariant(#names, x, z)
	return names[i]
end

-- Part-budget rule: the model is used only while it stays under its slot cap and the world-wide total.
function ModelFit.withinBudget(parts: number, slotCap: number, usedTotal: number, totalCap: number): boolean
	return parts > 0 and parts <= slotCap and usedTotal + parts <= totalCap
end

-- Deterministic yaw (radians) for slots whose primitive version used a random rotation.
function ModelFit.yaw(x: number, z: number): number
	return ModelFit.hash01(z + 17, x - 5) * math.pi * 2
end

return ModelFit
