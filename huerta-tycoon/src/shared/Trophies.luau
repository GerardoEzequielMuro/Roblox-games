--!strict
-- Crop sizes and the trophy shelf (pure rules, no Roblox services).
-- A crop can ripen Big or Giant: worth more when sold, or it can go on one of the plot's pedestals instead,
-- where it gives luck for as long as it stays there. That is the choice: cash now, or luck from now on.
local Trophies = {}

Trophies.SLOTS = 3

export type Size = { id: string, chance: number, valueMult: number, scale: number, luck: number }
-- Rolled from the rarest down. Fixed chances: luck boosts do not change them.
Trophies.Sizes = {
	{ id = "Giant", chance = 0.02, valueMult = 3, scale = 1.6, luck = 0.15 },
	{ id = "Big", chance = 0.08, valueMult = 1.5, scale = 1.25, luck = 0.05 },
} :: { Size }

Trophies.SizeById = {} :: { [string]: Size }
for _, sz in Trophies.Sizes do
	Trophies.SizeById[sz.id] = sz
end

export type Item = { seed: string, mut: string?, size: string? }

-- r is uniform in [0, 1). nil = normal size.
function Trophies.rollSize(r: number): string?
	local x = r
	for _, sz in Trophies.Sizes do
		if x < sz.chance then
			return sz.id
		end
		x -= sz.chance
	end
	return nil
end

-- Published chances (percent, adding up to 100), "Normal" last.
function Trophies.sizeTable(): { { id: string, pct: number } }
	local rows = {}
	local rest = 100
	for i, sz in Trophies.Sizes do
		local pct = math.floor(sz.chance * 10000 + 0.5) / 100
		rows[i] = { id = sz.id, pct = pct }
		rest -= pct
	end
	table.insert(rows, { id = "Normal", pct = math.floor(rest * 100 + 0.5) / 100 })
	return rows
end

function Trophies.valueMult(size: string?): number
	local sz = if size then Trophies.SizeById[size] else nil
	return if sz then sz.valueMult else 1
end

function Trophies.scale(size: string?): number
	local sz = if size then Trophies.SizeById[size] else nil
	return if sz then sz.scale else 1
end

-- Basket key. Normal-size crops keep the old "seed|mutation" form, so saves from before sizes still load.
function Trophies.key(seed: string, mut: string?, size: string?): string
	local k = seed .. "|" .. (mut or "")
	if size and Trophies.SizeById[size] then
		k ..= "|" .. size
	end
	return k
end

function Trophies.split(key: string): (string, string?, string?)
	local parts = string.split(key, "|")
	local seed = parts[1] or key
	local mut = parts[2]
	local size = parts[3]
	return seed, if mut and mut ~= "" then mut else nil, if size and Trophies.SizeById[size] then size else nil
end

-- Only special crops go on a pedestal.
function Trophies.eligible(mut: string?, size: string?): boolean
	return mut ~= nil or (size ~= nil and Trophies.SizeById[size] ~= nil)
end

-- Luck one trophy gives. mutationMult = that mutation's sell multiplier (nil when not mutated).
function Trophies.luckOf(size: string?, mutationMult: number?): number
	local luck = 0
	local sz = if size then Trophies.SizeById[size] else nil
	if sz then
		luck += sz.luck
	end
	if mutationMult then
		luck += math.clamp(mutationMult / 100, 0.02, 0.25)
	end
	return math.floor(luck * 1000 + 0.5) / 1000
end

function Trophies.totalLuck(list: { Item }, mutationMultOf: (string) -> number?): number
	local total = 0
	for i, item in list do
		if i > Trophies.SLOTS then
			break
		end
		total += Trophies.luckOf(item.size, if item.mut then mutationMultOf(item.mut) else nil)
	end
	return math.floor(total * 1000 + 0.5) / 1000
end

-- "ok", "full" or "plain".
function Trophies.canExhibit(count: number, mut: string?, size: string?): string
	if not Trophies.eligible(mut, size) then
		return "plain"
	elseif count >= Trophies.SLOTS then
		return "full"
	end
	return "ok"
end

return Trophies
