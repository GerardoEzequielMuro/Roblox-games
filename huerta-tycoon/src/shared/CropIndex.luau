--!strict
-- Crop x mutation Index: pure math (no Roblox services).
local CropIndex = {}

CropIndex.NORMAL = "Normal"

-- Every variant a seed row needs: Normal + each mutation id.
function CropIndex.variants(mutationIds: { string }): { string }
	local out = { CropIndex.NORMAL }
	for _, id in mutationIds do
		table.insert(out, id)
	end
	return out
end

-- (found, total) for a seed row.
function CropIndex.count(found: { [string]: boolean }?, mutationIds: { string }): (number, number)
	local n = 0
	local vars = CropIndex.variants(mutationIds)
	for _, v in vars do
		if found and found[v] then
			n += 1
		end
	end
	return n, #vars
end

function CropIndex.rowComplete(found: { [string]: boolean }?, mutationIds: { string }): boolean
	local n, total = CropIndex.count(found, mutationIds)
	return n == total
end

-- Permanent cash bonus (additive fraction) from claimed rows.
function CropIndex.bonus(claimedRows: number, totalRows: number, rowBonus: number, allBonus: number): number
	local b = claimedRows * rowBonus
	if totalRows > 0 and claimedRows >= totalRows then
		b += allBonus
	end
	return b
end

function CropIndex.rowCash(sellValue: number, mult: number): number
	return math.floor(sellValue * mult)
end

return CropIndex
