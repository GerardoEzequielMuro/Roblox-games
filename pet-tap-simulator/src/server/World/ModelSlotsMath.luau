--!strict
-- Pure helpers for ModelSlots (no Roblox API, so they run under plain `luau`):
-- the fit-to-box scale, the deterministic variant picker and the part-budget check.
local M = {}

-- Uniform scale so a model of size (sx, sy, sz) fits inside the target box (tx, ty, tz),
-- keeping its proportions: the tightest axis wins. Degenerate sizes return 1.
function M.fitScale(sx: number, sy: number, sz: number, tx: number, ty: number, tz: number): number
	local best = math.huge
	for _, pair in { { sx, tx }, { sy, ty }, { sz, tz } } do
		local s, t = pair[1], pair[2]
		if s > 1e-4 and t > 0 then
			best = math.min(best, t / s)
		end
	end
	if best == math.huge then
		return 1
	end
	return best
end

-- Deterministic integer hash of a world position (studs are rounded to 1/4).
function M.hash(x: number, z: number): number
	local ix = math.floor(x * 4 + 0.5)
	local iz = math.floor(z * 4 + 0.5)
	local h = (ix * 73856093 + iz * 19349663) % 2147483647
	if h < 0 then
		h += 2147483647
	end
	return h
end

-- Picks one of `count` variants (1..count) from a position: same place, same model; a
-- forest spreads over all the variants that exist.
function M.pickVariant(count: number, x: number, z: number): number
	if count <= 1 then
		return 1
	end
	return M.hash(x, z) % count + 1
end

-- Slot names in lookup order: "tree", "tree_1", "tree_2", ... up to maxVariants.
function M.variantNames(slot: string, maxVariants: number): { string }
	local out = { slot }
	for i = 1, maxVariants do
		table.insert(out, slot .. "_" .. i)
	end
	return out
end

-- Part budget: a model is used only when it is within the per-slot cap and the running
-- total for the whole world stays under the global cap.
function M.withinBudget(parts: number, perSlotCap: number, used: number, totalCap: number): boolean
	return parts > 0 and parts <= perSlotCap and used + parts <= totalCap
end

return M
