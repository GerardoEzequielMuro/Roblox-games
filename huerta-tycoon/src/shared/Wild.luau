--!strict
-- The Wild Patch: a shared corner of the map where rare seeds regrow every hour (pure rules, no Roblox services).
-- The hour ("cycle") and what grows in it come from the clock alone, so every server shows the same patch and
-- nothing has to be stored globally. Each player may pick every node once per cycle; it is free.
local Wild = {}

Wild.PERIOD = 3600
Wild.NODES = 6
Wild.Pool = {
	{ id = "pumpkin", weight = 30 },
	{ id = "watermelon", weight = 25 },
	{ id = "apple", weight = 18 },
	{ id = "dragonfruit", weight = 14 },
	{ id = "mango", weight = 8 },
	{ id = "starfruit", weight = 4 },
	{ id = "moonmelon", weight = 1 },
} :: { { id: string, weight: number } }

export type Saved = { cycle: number, claimed: { [string]: boolean } }

function Wild.cycle(now: number): number
	return math.floor(now / Wild.PERIOD)
end

function Wild.nextAt(now: number): number
	return (Wild.cycle(now) + 1) * Wild.PERIOD
end

-- The seeds growing in a cycle (same answer on every server). Lehmer generator: stays exact in doubles.
function Wild.nodes(cycle: number): { string }
	local total = 0
	for _, e in Wild.Pool do
		total += e.weight
	end
	local x = (cycle * 7919 + 104729) % 2147483646 + 1
	local out: { string } = {}
	for i = 1, Wild.NODES do
		x = (x * 48271) % 2147483647
		x = (x * 48271) % 2147483647
		local r = (x / 2147483647) * total
		local pick = Wild.Pool[#Wild.Pool].id
		for _, e in Wild.Pool do
			r -= e.weight
			if r < 0 then
				pick = e.id
				break
			end
		end
		out[i] = pick
	end
	return out
end

local function validIndex(index: any): boolean
	return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= Wild.NODES
end

-- Saved picks only count for the cycle they were made in.
function Wild.claimedIn(saved: any, cycle: number): { [string]: boolean }
	if type(saved) == "table" and saved.cycle == cycle and type(saved.claimed) == "table" then
		return saved.claimed
	end
	return {}
end

function Wild.canClaim(saved: any, cycle: number, index: any): boolean
	return validIndex(index) and Wild.claimedIn(saved, cycle)[tostring(index)] ~= true
end

-- Returns the saved record with this pick added (a fresh record when the cycle changed).
function Wild.claim(saved: any, cycle: number, index: number): Saved
	local claimed: { [string]: boolean } = {}
	for k, v in Wild.claimedIn(saved, cycle) do
		claimed[k] = v
	end
	claimed[tostring(index)] = true
	return { cycle = cycle, claimed = claimed }
end

function Wild.left(saved: any, cycle: number): number
	local n = 0
	local claimed = Wild.claimedIn(saved, cycle)
	for i = 1, Wild.NODES do
		if not claimed[tostring(i)] then
			n += 1
		end
	end
	return n
end

return Wild
