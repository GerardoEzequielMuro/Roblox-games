--!strict
-- Every random outcome a player can pay for (directly, or with cash that Robux can buy), in one place, so the
-- numbers the game SHOWS are the numbers the server ROLLS. Roblox's paid-random-items rules need the chances as
-- numeric percentages that add up to exactly 100, visible before spending, and no outcome may be "nothing".
local Odds = {}

-- ===== Lucky Seed Pack: 3 seeds, each rolled separately from this pool (Rare or better) =====
Odds.LuckyPerPack = 3
Odds.LuckyPool = {
	{ id = "pumpkin", weight = 30 },
	{ id = "watermelon", weight = 25 },
	{ id = "apple", weight = 18 },
	{ id = "dragonfruit", weight = 14 },
	{ id = "mango", weight = 9 },
	{ id = "starfruit", weight = 4 },
} :: { { id: string, weight: number } }

export type Row = { id: string, pct: number }

-- Percentages with `decimals` places that add up to exactly 100 (largest-remainder rounding).
function Odds.percentages(weights: { number }, decimals: number?): { number }
	local scale = 10 ^ (decimals or 1)
	local total = 0
	for _, w in weights do
		total += math.max(w, 0)
	end
	local out: { number } = {}
	if total <= 0 then
		for i = 1, #weights do
			out[i] = 0
		end
		return out
	end
	local units = math.round(100 * scale)
	local used = 0
	local rest: { { i: number, frac: number } } = {}
	for i, w in weights do
		local exact = math.max(w, 0) / total * units
		local whole = math.floor(exact + 1e-9)
		out[i] = whole
		used += whole
		rest[i] = { i = i, frac = exact - whole }
	end
	table.sort(rest, function(a, b)
		if a.frac == b.frac then
			return a.i < b.i
		end
		return a.frac > b.frac
	end)
	local k = 1
	while used < units do
		out[rest[k].i] += 1
		used += 1
		k = k % #rest + 1
	end
	for i in out do
		out[i] /= scale
	end
	return out
end

function Odds.luckyTable(): { Row }
	local weights: { number } = {}
	for i, e in Odds.LuckyPool do
		weights[i] = e.weight
	end
	local pcts = Odds.percentages(weights, 1)
	local rows: { Row } = {}
	for i, e in Odds.LuckyPool do
		rows[i] = { id = e.id, pct = pcts[i] }
	end
	return rows
end

-- The roll itself: r is uniform in [0, 1).
function Odds.rollLucky(r: number): string
	local total = 0
	for _, e in Odds.LuckyPool do
		total += e.weight
	end
	local x = math.clamp(r, 0, 0.999999999) * total
	for _, e in Odds.LuckyPool do
		x -= e.weight
		if x < 0 then
			return e.id
		end
	end
	return Odds.LuckyPool[#Odds.LuckyPool].id
end

-- ===== Mutations: rolled from the rarest down, first success wins =====
export type Mutation = { id: string, baseChance: number, weather: string? }
export type Ctx = {
	luck: number, -- upgrades, passes, rebirth bonuses...
	weather: string?, -- current weather id
	goldenMult: number, -- Golden Hour multiplier (1 outside it)
	eventMult: number, -- live event multiplier (1 outside events)
	exposure: boolean?, -- the periodic "sitting out in the weather" roll (weather mutations only, 1/6 chance)
}

-- Chance of ONE mutation's own roll succeeding (0 when its weather is not active).
function Odds.mutationChance(m: any, ctx: Ctx): number
	if ctx.exposure and not m.weather then
		return 0
	end
	if m.weather and m.weather ~= ctx.weather then
		return 0
	end
	local chance = m.baseChance * ctx.luck * ctx.eventMult
	if m.id == "Golden" then
		chance *= ctx.goldenMult
	end
	if ctx.exposure then
		chance /= 6
	end
	return math.clamp(chance, 0, 1)
end

-- Final chance of each outcome of a harvest, "Normal" included, adding up to exactly 100.
function Odds.mutationTable(mutations: { any }, ctx: Ctx): { Row }
	local weights: { number } = {}
	local remaining = 1
	for i, m in mutations do
		local c = Odds.mutationChance(m, ctx)
		weights[i] = remaining * c
		remaining *= 1 - c
	end
	weights[#mutations + 1] = remaining
	local pcts = Odds.percentages(weights, 2)
	local rows: { Row } = {}
	for i, m in mutations do
		rows[i] = { id = m.id, pct = pcts[i] }
	end
	rows[#mutations + 1] = { id = "Normal", pct = pcts[#mutations + 1] }
	return rows
end

-- Store items that are (or modify) a paid random outcome: hidden where Roblox restricts them.
Odds.RandomItems = { LuckyPack = true, SuperLuck = true } :: { [string]: boolean }

function Odds.canOffer(key: string, paidRandomAllowed: boolean): boolean
	return paidRandomAllowed or not Odds.RandomItems[key]
end

return Odds
