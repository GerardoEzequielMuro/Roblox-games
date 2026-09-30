--!nocheck
-- Tuner for the pacing targets: bisects each zone gate cost (scaling that zone's egg prices with
-- it, same ratio as today) and then RebirthBaseCost so the median free player hits the target
-- play times below. Prints values to paste into Config.luau. Run: luau sim/pacing_tune.luau
local Core = require("./pacing_core")
local Config = require("../src/shared/Config")

local TARGET = { zone2 = 4.5 * 60, zone3 = 15 * 60, zone4 = 30 * 60, rebirth1 = 45 * 60, zone5 = 75 * 60 }
local SEEDS = 5
local sessions = Core.firstSession(130)

-- Egg prices follow a gate: their own zone's gate, or the NEXT gate when the egg costs more
-- than its own gate (Sprinkle Egg), so prices stay ordered while gates move.
local eggRatio, eggAnchor = {}, {}
for _, egg in Config.Eggs do
	if egg.zone >= 2 and not egg.minRebirths then -- rebirth-gated eggs are priced by hand (they follow the rebirth cost, not a gate)
		local own = egg.price / Config.Zones[egg.zone].cost
		local anchor = if own > 1 and Config.Zones[egg.zone + 1] then egg.zone + 1 else egg.zone
		eggAnchor[egg.id] = anchor
		eggRatio[egg.id] = egg.price / Config.Zones[anchor].cost
	end
end
local function round2(x: number): number
	return tonumber(string.format("%.2g", x)) :: number
end
local function setGate(z: number, cost: number)
	cost = round2(cost)
	Config.Zones[z].cost = cost
	for _, egg in Config.Eggs do
		if eggAnchor[egg.id] == z then
			egg.price = round2(cost * eggRatio[egg.id])
		end
	end
end
local function measure(key: string): number
	local agg = Core.aggregate(SEEDS, sessions)
	return agg.med[key] or 1e9
end
local function bisect(key: string, get: () -> number, set: (number) -> ())
	local lo, hi = get() / 8, get() * 8
	for _ = 1, 10 do
		local mid = math.sqrt(lo * hi)
		set(mid)
		if measure(key) < TARGET[key] then
			lo = mid
		else
			hi = mid
		end
	end
	set(math.sqrt(lo * hi))
end

for pass = 1, 2 do
	for z = 2, 4 do
		bisect("zone" .. z, function()
			return Config.Zones[z].cost
		end, function(v)
			setGate(z, v)
		end)
	end
	bisect("rebirth1", function()
		return Config.RebirthBaseCost
	end, function(v)
		Config.RebirthBaseCost = round2(v)
	end)
	bisect("zone5", function()
		return Config.Zones[5].cost
	end, function(v)
		setGate(5, v)
	end)
	print("-- pass " .. pass)
end
for _, z in Config.Zones do
	print(string.format("zone %d %-8s cost = %.0f", z.index, z.id, z.cost))
end
for _, egg in Config.Eggs do
	print(string.format("egg %-9s price = %.0f", egg.id, egg.price))
end
print(string.format("RebirthBaseCost = %.0f", Config.RebirthBaseCost))
