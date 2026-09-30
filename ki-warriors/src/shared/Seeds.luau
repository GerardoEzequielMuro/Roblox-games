--!strict
-- Seeds (pure): Sparks price, hourly restock of the shop stock, carry cap and buff maths.
-- Soft-currency stock is a rate limit that restocks on the hour (the clock is shown in the
-- shop); the Robux seed packs are never limited.
local Config: any = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Seeds = {}

export type Market = { hour: number, bought: { [string]: number } }

function Seeds.hour(now: number): number
	return now // 3600
end

function Seeds.nextRestock(now: number): number
	return (Seeds.hour(now) + 1) * 3600
end

function Seeds.newMarket(): Market
	return { hour = 0, bought = {} }
end

-- Rolls the record over to the current hour (stock comes back) and returns it.
function Seeds.sync(m: Market, now: number): Market
	local h = Seeds.hour(now)
	if m.hour ~= h then
		m.hour = h
		m.bought = {}
	end
	return m
end

function Seeds.stockLeft(m: Market, id: string, now: number): number
	local def = Config.SeedById[id]
	if not def then
		return 0
	end
	Seeds.sync(m, now)
	return math.max(0, def.stockPerHour - (m.bought[id] or 0))
end

-- sparksPerMinute: Formulas.sparksPerMinute(best planet).
function Seeds.price(id: string, sparksPerMinute: number): number
	local def = Config.SeedById[id]
	return if def then math.max(1, math.floor(def.minutes * sparksPerMinute)) else math.huge
end

-- Checks a Sparks purchase. Returns ok, reason ("bad" | "stock" | "cap" | "sparks").
function Seeds.canBuy(m: Market, inventory: { [string]: number }, id: string, now: number, sparks: number, sparksPerMinute: number): (boolean, string?)
	if not Config.SeedById[id] then
		return false, "bad"
	end
	if Seeds.stockLeft(m, id, now) <= 0 then
		return false, "stock"
	end
	if (inventory[id] or 0) >= Config.SeedCap then
		return false, "cap"
	end
	if sparks < Seeds.price(id, sparksPerMinute) then
		return false, "sparks"
	end
	return true, nil
end

-- Adds `n` seeds, respecting the carry cap. Returns how many were actually added.
function Seeds.add(inventory: { [string]: number }, id: string, n: number): number
	if not Config.SeedById[id] or n ~= n or n <= 0 then
		return 0
	end
	local have = inventory[id] or 0
	local added = math.max(0, math.min(math.floor(n), Config.SeedCap - have))
	inventory[id] = have + added
	return added
end

function Seeds.active(until_: number?, now: number): boolean
	return until_ ~= nil and until_ > now
end

return Seeds
