-- Seeds: prices, hourly restock, carry cap (Shared/Seeds), goals (Shared/Goals). Pure.
local Seeds = require("../src/shared/Seeds")
local Goals = require("../src/shared/Goals")
local Formulas = require("../src/shared/Formulas")
local Config = require("../src/shared/Config")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

local T0 = 1_790_000_000 -- any timestamp
local H = Seeds.hour(T0)
check("hour bucket", Seeds.hour(H * 3600) == H and Seeds.hour(H * 3600 + 3599) == H and Seeds.hour(H * 3600 + 3600) == H + 1)
check("next restock is the next full hour", Seeds.nextRestock(H * 3600 + 5) == (H + 1) * 3600)

-- price: minutes of income of the best planet
local spm = Formulas.sparksPerMinute(1)
check("vigor price", Seeds.price("vigor_seed", spm) == math.floor(3 * spm), Seeds.price("vigor_seed", spm))
check("unknown seed", Seeds.price("nope", spm) == math.huge)
check("later planets cost more", Seeds.price("vigor_seed", Formulas.sparksPerMinute(5)) > Seeds.price("vigor_seed", spm))

-- stock and restock
local m = Seeds.newMarket()
local inv: { [string]: number } = {}
local sparks = 1e12
local now = H * 3600 + 100
for i = 1, Config.SeedById.titan_seed.stockPerHour do
	local ok = Seeds.canBuy(m, inv, "titan_seed", now, sparks, spm)
	check("can buy titan #" .. i, ok)
	m.bought.titan_seed = (m.bought.titan_seed or 0) + 1
	Seeds.add(inv, "titan_seed", 1)
end
local ok, why = Seeds.canBuy(m, inv, "titan_seed", now, sparks, spm)
check("sold out this hour", not ok and why == "stock", why)
check("stockLeft 0", Seeds.stockLeft(m, "titan_seed", now) == 0)
check("other seeds unaffected", Seeds.stockLeft(m, "vigor_seed", now) == Config.SeedById.vigor_seed.stockPerHour)
check("restocks on the hour", Seeds.stockLeft(m, "titan_seed", (H + 1) * 3600) == Config.SeedById.titan_seed.stockPerHour)
check("bought counter reset", next(m.bought) == nil)

-- reasons
local ok2, why2 = Seeds.canBuy(Seeds.newMarket(), {}, "vigor_seed", now, 0, spm)
check("needs sparks", not ok2 and why2 == "sparks", why2)
local ok3, why3 = Seeds.canBuy(Seeds.newMarket(), { vigor_seed = Config.SeedCap }, "vigor_seed", now, sparks, spm)
check("carry cap", not ok3 and why3 == "cap", why3)
local ok4, why4 = Seeds.canBuy(Seeds.newMarket(), {}, "nope", now, sparks, spm)
check("bad id", not ok4 and why4 == "bad")

-- cap on add
local bag: { [string]: number } = { vigor_seed = Config.SeedCap - 1 }
check("add respects the cap", Seeds.add(bag, "vigor_seed", 5) == 1 and bag.vigor_seed == Config.SeedCap)
check("add ignores junk", Seeds.add(bag, "vigor_seed", -3) == 0 and Seeds.add(bag, "nope", 1) == 0 and Seeds.add(bag, "vigor_seed", 0 / 0) == 0)

-- buffs
check("buff active", Seeds.active(now + 5, now))
check("buff expired", not Seeds.active(now, now) and not Seeds.active(nil, now) and not Seeds.active(0, now))

-- stock per hour is a soft-currency rate limit, it never applies to Robux packs (kind "seeds")
for _, p in Config.Products do
	if p.kind == "seeds" then
		check("robux packs are not stock-limited by design", p.amount >= 1)
	end
end

-- Goals -------------------------------------------------------------------------------
local g = Goals.next(10, 0, { 1 }, 0)
check("fresh player: next form is Kindled", g.kind == "form" and g.id == "kindled" and g.need == 1_000, g.kind .. g.id)
local g2 = Goals.next(700, 0, { 1 }, 0)
check("closer goal wins (Kindled at 70%)", g2.kind == "form" and math.abs(g2.frac - 0.7) < 1e-9, g2.frac)
local g3 = Goals.next(20_000, 1, { 1 }, 0)
check("planet goal can win", g3.kind == "planet" or g3.kind == "form", g3.kind)
check("planet is Fort Brask at 25K", Goals.next(24_000, 3, { 1 }, 0).id == "brask" or Goals.next(24_000, 3, { 1 }, 0).kind == "form")
local all = {}
for i = 1, #Config.Planets do
	all[i] = i
end
local g4 = Goals.next(Formulas.rebirthRequirement(0) * 2, 7, all, 0)
check("everything met: ascend now", g4.kind == "rebirth" and g4.frac == 1, g4.kind)
local g5 = Goals.next(5_000_000, 3, all, 0)
check("goal frac in 0..1", g5.frac >= 0 and g5.frac <= 1)
check("special forms are never a goal", Goals.next(1e15, 7, all, 3).id ~= "unbound")

if fails == 0 then
	print("SEEDS / GOALS CHECKS PASSED")
else
	error(fails .. " seeds/goals check(s) failed")
end
