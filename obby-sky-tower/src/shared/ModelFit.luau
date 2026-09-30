--!strict
-- Pure helpers for the model slots (no Roblox types, so they run in plain `luau` tests).
local ModelFit = {}

-- Uniform scale that makes `size` fit inside `target` (keeps proportions). Zero-size axes are ignored.
function ModelFit.fitScale(size: { number }, target: { number }): number
	local best = math.huge
	for i = 1, 3 do
		local s, t = size[i], target[i]
		if s and t and s > 1e-4 and t > 1e-4 then
			best = math.min(best, t / s)
		end
	end
	if best == math.huge then
		return 1
	end
	return best
end

-- Deterministic hash of a position (rounded to whole studs), always in 0..2^32-1.
function ModelFit.posHash(x: number, z: number): number
	local ix, iz = math.floor(x + 0.5), math.floor(z + 0.5)
	local h = (ix * 73856093 + iz * 19349663) % 4294967296
	h = (h * 2654435761) % 4294967296
	return h
end

-- Picks among `count` variants (1..count) from a position; same position -> same variant.
function ModelFit.pickVariant(count: number, x: number, z: number): number
	if count <= 1 then
		return 1
	end
	return (ModelFit.posHash(x, z) // 7) % count + 1
end

-- Usable names for a slot given the library's names (a set): "slot", "slot_1", "slot_2"... (gaps ok).
function ModelFit.variantNames(slot: string, has: { [string]: boolean }, maxVariants: number?): { string }
	local out: { string } = {}
	if has[slot] then
		table.insert(out, slot)
	end
	for i = 1, maxVariants or 12 do
		local n = slot .. "_" .. i
		if has[n] then
			table.insert(out, n)
		end
	end
	return out
end

-- A model of `parts` parts is allowed within the per-slot cap and the global budget.
function ModelFit.withinBudget(parts: number, slotCap: number, usedTotal: number, totalCap: number): boolean
	return parts > 0 and parts <= slotCap and usedTotal + parts <= totalCap
end

return ModelFit
