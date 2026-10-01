--!strict
-- Compact set of world coins already picked up. PURE Luau.
-- Coin ids are stage * 10 + j (j = 1..9). The set maps tostring(stage) -> bitmask of j, so a
-- profile with every coin taken is ~1000 small entries instead of one key per coin.
local CoinSet = {}

export type Set = { [string]: number }

local function split(id: number): (string, number)
	local stage = id // 10
	local j = id % 10
	return tostring(stage), if j >= 1 then bit32.lshift(1, j - 1) else 0
end

function CoinSet.has(set: Set, id: number): boolean
	local k, bit = split(id)
	return bit ~= 0 and bit32.band(set[k] or 0, bit) ~= 0
end

function CoinSet.add(set: Set, id: number)
	local k, bit = split(id)
	if bit ~= 0 then
		set[k] = bit32.bor(set[k] or 0, bit)
	end
end

function CoinSet.count(set: Set): number
	local n = 0
	for _, mask in set do
		for j = 0, 8 do
			if bit32.band(mask, bit32.lshift(1, j)) ~= 0 then
				n += 1
			end
		end
	end
	return n
end

-- Repairs a loaded value (old saves have none): only "stage" keys with a 9-bit integer mask survive.
function CoinSet.sanitize(raw: any, maxStage: number): Set
	local out: Set = {}
	if type(raw) ~= "table" then
		return out
	end
	for k, v in raw :: { [any]: any } do
		local stage = tonumber(k)
		local mask = tonumber(v)
		if stage and mask and stage >= 0 and stage <= maxStage and stage == math.floor(stage) and mask == mask and mask > 0 and mask < math.huge then
			local m = bit32.band(math.floor(mask), 511)
			if m ~= 0 then
				out[tostring(stage)] = m
			end
		end
	end
	return out
end

-- Every id in the set (to seed the session cache).
function CoinSet.ids(set: Set): { number }
	local out = {}
	for k, mask in set do
		for j = 0, 8 do
			if bit32.band(mask, bit32.lshift(1, j)) ~= 0 then
				table.insert(out, (tonumber(k) :: number) * 10 + j + 1)
			end
		end
	end
	return out
end

return CoinSet
