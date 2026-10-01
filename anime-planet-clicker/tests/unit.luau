-- Pure-logic unit tests (run from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/unit.luau
local Config = require("../src/shared/Config")
local F = require("../src/shared/Formulas")
local Layout = require("../src/shared/Layout")
local LiveEvents = require("../src/shared/LiveEvents")
local Quests = require("../src/shared/Quests")
local Referral = require("../src/shared/Referral")
local Format = require("../src/shared/Format")
local ModelFit = require("../src/shared/ModelFit")
local TutorialFlow = require("../src/shared/TutorialFlow")
local Juice = require("../src/shared/Juice")

local total, fails = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-9) * math.max(1, math.abs(b))
end

-- odds: what is shown is what is rolled, always exactly 100%
for _, cap in Config.Capsules do
	for _, luck in { 1, 1.3, 2, 3.7, 8 } do
		local sum, rare = 0, 0
		for _, o in F.odds(cap.id, luck) do
			sum += o.chance
			if Config.RarityByName[o.rarity].order >= 3 then
				rare += o.chance
			end
		end
		check("odds sum 100 " .. cap.id .. " luck " .. luck, math.abs(sum - 100) < 1e-9, sum)
		if luck > 1 then
			local base = 0
			for _, o in F.odds(cap.id, 1) do
				if Config.RarityByName[o.rarity].order >= 3 then
					base += o.chance
				end
			end
			check("luck raises the rare share " .. cap.id, rare >= base - 1e-9, rare)
		end
	end
end
check("roll at 0 gives the rarest entry", F.rollCapsule("dawn", 1, 0).rarity == "Secret")
check("roll at 0.999 gives the most common entry", F.rollCapsule("dawn", 1, 0.999).id == "pebblepup")
check("exclusive capsule has no secret", #F.odds("quantum", 1) == 3)
check("relic table rolls", F.rollTable(Config.RelicGrades, 0) == #Config.RelicGrades and F.rollTable(Config.RelicGrades, 0.99) == 1)

-- planets
for z = 1, #Config.Zones do
	local sum = 0
	for l = 1, #Config.Layers do
		sum += F.layerHp(z, "rock", l)
	end
	check("layers add up to the planet HP, zone " .. z, near(sum, F.planetHp(z, "rock"), 0.02), sum)
end
check("gate is one slab with the next galaxy's gateHp", F.layerCount("gate") == 1 and F.layerHp(1, "gate", 1) == Config.Zones[2].gateHp)
check("last galaxy has no gate", F.planetHp(#Config.Zones, "gate") == 0)
check("rollKind never returns a special planet", (function()
	for i = 0, 999 do
		local k = F.rollKind(1 + i % 4, i / 1000)
		if Config.PlanetKindById[k].weight <= 0 then
			return false
		end
	end
	return true
end)())
check("luck makes buff planets more common", (function()
	local function rares(luck)
		local n = 0
		for i = 0, 999 do
			if F.rollKind(luck, i / 1000) ~= "rock" then
				n += 1
			end
		end
		return n
	end
	return rares(3) > rares(1)
end)())
check("hardness: first tool is soft in galaxy 2, the galaxy's own tool is not", F.hardness(3, 2) == Config.SoftDamage and F.hardness(4, 2) == 1 and F.hardness(1, 1) == 1)
check("incomeZone follows the tool", F.incomeZone(3, 6) == 1 and F.incomeZone(4, 6) == 2 and F.incomeZone(Config.Zones[6].hardness, 6) == 6 and F.incomeZone(Config.Zones[5].hardness, 6) == 5 and F.incomeZone(12, 2) == 2)

-- Asteroid Field tools: a run of tools inside a galaxy, never the first tool sold there
check("field tools: every galaxy's hardness tool is a headline tool, not a field", (function()
	for i = 2, #Config.Zones do
		local t = Config.Tools[Config.Zones[i].hardness]
		if t.zone ~= i or t.field then
			return false
		end
	end
	return true
end)())
check("field tools: at least 8, all lasers with a locale name in en", (function()
	local Locale = require("../src/shared/Locale")
	local en = Locale.pack("en")
	local n = 0
	for _, t in Config.Tools do
		if t.field then
			n += 1
			if t.kind ~= "laser" or not en["tool." .. t.id] then
				return false
			end
		end
	end
	return n >= 8
end)())
check("field tools: FieldCrystals is a positive whole number", Config.FieldCrystals > 0 and Config.FieldCrystals % 1 == 0)

-- stats
local s = F.blankStats()
local base = F.hitDamage(s)
check("base damage = first tool", base == Config.Tools[1].power)
s.upgrades = { Power = 10 }
check("Power compounds", near(F.hitDamage(s), base * 1.06 ^ 10, 1e-9))
s.upgrades = { Temper = 5 }
check("Temper adds 10% per level", near(F.hitDamage(s), base * 1.5))
s.upgrades = {}
s.petPower = 3
check("pets multiply", near(F.hitDamage(s), base * 4))
s.petPower = 0
s.rebirths = 2
check("rebirth: +50% damage and Stardust each", near(F.hitDamage(s), base * 2) and near(F.stardustMult(s), 2))
s.rebirths = 0
s.passes = { DoubleDamage = true, VIP = true }
check("passes stack", near(F.hitDamage(s), base * 2 * Config.VipDamage))
s.passes = {}
s.buffs = { damage = true, speed = true, luck = true, stardust = true }
check("buffs", near(F.hitDamage(s), base * 1.5) and near(F.luck(s), 2) and near(F.stardustMult(s), 2) and near(F.hitsPerSecond(s), Config.BaseHitsPerSecond * 1.35) and near(F.walkSpeed(s), Config.BaseWalkSpeed * 1.35))
s.buffs = {}
check("cargo capacity", F.cargoCapacity(s) == Config.CargoBase)
s.upgrades = { Cargo = 3, StarDrone = 9 }
check("cargo upgrade + drone floor", F.cargoCapacity(s) == Config.CargoBase + 36 and F.droneSeconds(s) == Config.DroneSecondsMin)
s.upgrades = { AutoRate = 2 }
check("auto rate: free, upgrade, pass", near(F.autoRate(s), 3) and (function()
	s.passes = { AutoMiner = true }
	local r = F.autoRate(s)
	s.passes = {}
	return near(r, 9)
end)())
check("overcharge multiplier", near(F.overchargeMult(0, 0), 1) and near(F.overchargeMult(1, 0), Config.OverchargeBase) and near(F.overchargeMult(1, 4), Config.OverchargeBase + 1) and near(F.overchargeMult(5, 0), Config.OverchargeBase))
check("mastery levels", F.masteryLevel(0) == 0 and F.masteryLevel(5) == 1 and F.masteryLevel(24) == 1 and F.masteryLevel(5000) == 6)
local mb = F.masteryBonus({ rock = 25, fury = 5, zephyr = 100 })
check("mastery bonus per stat", near(mb.damage, 0.09) and near(mb.speed, 0.09) and mb.luck == 0)
local rb = F.relicBonus({ damage = { grade = 3, dust = 0 }, luck = { grade = 6, dust = 1 }, speed = { grade = 0, dust = 4 } })
check("relic bonus", near(rb.damage, 0.2) and near(rb.luck, 1) and rb.speed == 0)
check("max equip", F.maxEquip({}, {}) == 3 and F.maxEquip({ PetSlots = 2, StarSlot = 1 }, { PetSlots = true }) == 8)
for _, u in Config.Upgrades do
	if u.max > 1 then
		check("upgrade cost grows: " .. u.id, F.upgradeCost(u.id, 1) > F.upgradeCost(u.id, 0) and F.upgradeCost(u.id, u.max - 1) > 0)
	end
end
check("pet power: tiers and traits", near(F.petPower("cometcat", 1, 1), 3) and near(F.petPower("cometcat", 2, 1), 8) and near(F.petPower("cometcat", 0, 1, "radiant"), 2))
check("exclusive pets scale with the best galaxy", F.petPower("photonpixie", 0, 1) == 8 * 1.5 and F.petPower("photonpixie", 0, 3) == 430 * 1.5)
check("rebirth cost grows", F.rebirthCost(1) == Config.RebirthBaseCost * Config.RebirthCostGrowth and F.rebirthCrystals(2) == 80)

-- pvp: the power gap is clamped hard
local C = Config.Pvp
check("pvp damage equal power", F.pvpDamage(100, 100) == C.baseDamage)
check("pvp damage clamp up", F.pvpDamage(1e30, 1) == math.floor(C.baseDamage * C.maxRatio + 0.5))
check("pvp damage clamp down", F.pvpDamage(1, 1e30) == math.floor(C.baseDamage * C.minRatio + 0.5))
check("a new player survives at least 4 hits from anyone", C.maxHp / F.pvpDamage(1e30, 1) > 4)

-- anomaly clock
local on, window, edge = F.anomaly(7200 + 10)
check("anomaly on at the top of the hour", on and window == 7200 and edge == 7200 + Config.AnomalyDuration)
on, window, edge = F.anomaly(7200 + Config.AnomalyDuration + 5)
check("anomaly off afterwards, next edge = next hour", not on and edge == 10800)
check("anomaly is a short window every hour", Config.AnomalyEvery == 3600 and Config.AnomalyDuration > 0 and Config.AnomalyDuration < Config.AnomalyEvery)
do -- one break per window: the window id a player stores changes every hour and never inside one
	local _, w1 = F.anomaly(36000 + 1)
	local _, w2 = F.anomaly(36000 + Config.AnomalyDuration - 1)
	local _, w3 = F.anomaly(36000 + Config.AnomalyEvery + 1)
	check("anomaly window id is stable inside a window and new next hour", w1 == w2 and w3 == w1 + Config.AnomalyEvery)
end
check("anomaly is a real boss (more HP and loot than a rock)", F.planetHp(1, "anomaly") > F.planetHp(1, "rock") * 5 and (Config.PlanetKindById.anomaly.crystals or 0) > 0)

-- gate wall: every galaxy after the first sits behind a wall that is harder than the last
for z = 2, #Config.Zones do
	check("gate wall into galaxy " .. z .. " exists", Config.Zones[z].gateHp > 0)
	if z > 2 then
		check("gate wall " .. z .. " harder than " .. (z - 1), Config.Zones[z].gateHp > Config.Zones[z - 1].gateHp)
	end
	check("gate wall " .. z .. " is many planets of the galaxy before", Config.Zones[z].gateHp > F.planetHp(z - 1, "rock") * 10)
end
check("special nodes do not collide", Config.NodeTitan ~= Config.NodeAnomaly and Config.NodeAnomaly ~= Config.NodeGate and Config.NodeGate > Config.NodesPerZone and Config.NodeAnomaly > Config.NodesPerZone and Config.NodeTitan == 0)
do -- every galaxy after the first opens its own multiplier system
	local seen: { [number]: boolean } = {}
	for _, sys in Config.Systems do
		seen[sys.zone] = true
	end
	local all = true
	for z = 2, #Config.Zones do
		all = all and seen[z] == true
	end
	check("one system per galaxy 2.." .. #Config.Zones, all)
end

-- layout
check("zoneAt", Layout.zoneAt(0, 0) == 1 and Layout.zoneAt(Config.ZoneSpacing * 3, 40) == 4 and Layout.zoneAt(Config.ZoneSpacing * 0.5, 0) == nil and Layout.zoneAt(-5000, 0) == nil)
check("arena", Layout.inArena(Config.ArenaCenter[1], Config.ArenaCenter[3]) and not Layout.inArena(Config.ArenaCenter[1], Config.ArenaCenter[3] - Config.ArenaRadius - 1) and Layout.onArenaPlatform(Config.ArenaCenter[1], Config.ArenaCenter[3] - Config.ArenaRadius - 10))
check("every capsule has a machine position", (function()
	for _, cap in Config.Capsules do
		if not Layout.capsulePosition(cap.id) then
			return false
		end
	end
	return true
end)())

-- live events
local day0 = 1767225600 -- 2026-01-01 00:00 UTC, a Thursday
local active = LiveEvents.active(day0 + 1800 + 60, nil)
check("Meteor Shower on schedule", #active >= 1 and active[1].id == "MeteorShower")
check("nothing between events on a weekday", #LiveEvents.active(day0 + 1800 + 16 * 60, nil) == 0)
check("Crystal Weekend on Saturday", (function()
	for _, a in LiveEvents.active(day0 + 2 * 86400 + 5 * 3600, nil) do
		if a.id == "CrystalWeekend" then
			return true
		end
	end
	return false
end)())
local fx = LiveEvents.effects(LiveEvents.active(day0 + 1800 + 60, nil))
check("event effects", fx.stardustMult == 2 and fx.luckMult == 1 and fx.crystalMult == 1)
check("admin override wins", LiveEvents.active(day0 + 40000, { id = "LuckyNebula", endsAt = day0 + 40300 })[1].id == "LuckyNebula")
local nextAt = LiveEvents.nextStart(day0)
check("next start is in the future", nextAt ~= nil and nextAt > day0)

-- quests: same 3 for everyone on a day, different days differ
local a1, a2 = Quests.forDay(20000, 1), Quests.forDay(20000, 1)
check("quests deterministic", #a1 == 3 and a1[1].kind == a2[1].kind and a1[3].kind == a2[3].kind)
check("quests distinct", a1[1].kind ~= a1[2].kind and a1[2].kind ~= a1[3].kind and a1[1].kind ~= a1[3].kind)
local differs = false
for d = 20001, 20010 do
	local b = Quests.forDay(d, 1)
	if b[1].kind ~= a1[1].kind or b[2].kind ~= a1[2].kind then
		differs = true
	end
end
check("quests rotate", differs)
check("quest targets scale with the galaxy", Quests.forDay(20000, 6)[1].target >= a1[1].target)

-- referral
check("referral parse", Referral.parse(Referral.launchData(12345)) == 12345 and Referral.parse("ref:0") == nil and Referral.parse("ref:12a") == nil and Referral.parse(nil) == nil and Referral.parse(string.rep("9", 60)) == nil)

-- format
check("abbrev", Format.abbrev(999) == "999" and Format.abbrev(1500) == "1.5K" and Format.abbrev(2.34e6) == "2.34M" and Format.abbrev(1e15) == "1Qa")
check("percent", Format.percent(55) == "55%" and Format.percent(2.9) == "2.9%" and Format.percent(0.099) == "0.099%" and Format.percent(0.001) == "0.001%" and Format.percent(53.4712) == "53.47%")
check("time", Format.time(59) == "59s" and Format.time(125) == "2m 05s" and Format.time(7260) == "2h 01m")

-- Round 2: pricing, paid-advantage-free PvP, batch opens, Star Surge
do
	local function price(key: string): number
		return (Config.PassByKey[key] or Config.ProductByKey[key]).price
	end
	check("research prices: passes", price("AutoMiner") == 175 and price("DoubleDamage") == 349 and price("DoubleStardust") == 349 and price("VIP") == 299 and price("PetSlots") == 249 and price("PetSlots2") == 649 and price("OpenEight") == 699 and price("Lucky") == 249 and price("SuperLucky") == 699 and price("GoldenCapsules") == 599)
	check("research prices: crystals ladder", price("CrystalsSmall") == 49 and price("CrystalsMedium") == 249 and price("CrystalsLarge") == 499 and price("CrystalsHuge") == 999)
	local prevRate = 0
	for _, key in { "CrystalsSmall", "CrystalsMedium", "CrystalsLarge", "CrystalsHuge" } do
		local rate = Config.ProductByKey[key].amount / Config.ProductByKey[key].price
		check("bigger crystal pack is a better rate: " .. key, rate > prevRate)
		prevRate = rate
	end
	check("starter pack list price is what the same content costs here", Config.StarterPack.fullPrice == math.ceil(150 * 49 / 100) + 149 and Config.StarterPack.fullPrice > Config.ProductByKey.StarterPack.price)
	check("max equip with both pet slot passes", F.maxEquip({}, { PetSlots = true, PetSlots2 = true }) == 3 + 2 + 4 and F.maxEquip({}, { PetSlots2 = true }) == 7)
	-- PvP: passes never change arena power or speed
	local base: any = { toolIndex = 3, upgrades = { Power = 10 }, petPower = 5, rebirths = 1, passes = {}, buffs = {}, mastery = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 }, relics = { damage = 0, speed = 0, luck = 0, stardust = 0, crystals = 0 }, friends = 0, indexZones = 0, premium = false, eventStardust = 1, eventLuck = 1, eventCrystals = 1, charge = 0 }
	local paid: any = table.clone(base)
	paid.passes = { DoubleDamage = true, VIP = true, PetSlots = true, PetSlots2 = true, Sprint = true }
	check("paid passes do raise normal damage", F.hitDamage(paid) > F.hitDamage(base) * 2.9)
	check("PvP stats ignore every paid pass", near(F.hitDamage(F.pvpStats(paid, 5)), F.hitDamage(base)) and near(F.hitDamage(F.pvpStats(paid, 5)), F.hitDamage(F.pvpStats(base, 5))))
	check("Sprint does not count in the arena", F.walkSpeed(paid, true) == F.walkSpeed(base, true) and F.walkSpeed(paid, false) == F.walkSpeed(base, false) + Config.SprintPassSpeed)
	check("arena pet power keeps only the best free slots", F.topPower({ 1, 9, 3, 7, 5 }, 3) == 21 and F.topPower({ 4 }, 3) == 4 and F.topPower({}, 3) == 0)
	-- batch opens
	local function all(_n: number): boolean
		return true
	end
	check("open count without passes is 1", F.bestOpenCount({}, all) == 1)
	check("open count x3 with TripleOpen", F.bestOpenCount({ TripleOpen = true }, all) == 3)
	check("open count x8 needs its own pass", F.bestOpenCount({ OpenEight = true }, all) == 8 and F.bestOpenCount({ TripleOpen = true, OpenEight = true }, all) == 8)
	check("open count falls back when it does not fit", F.bestOpenCount({ TripleOpen = true, OpenEight = true }, function(n)
		return n <= 3
	end) == 3 and F.bestOpenCount({ TripleOpen = true, OpenEight = true }, function(n)
		return n <= 1
	end) == 1)
	-- Star Surge: fixed weekly times, all servers, 45 min, twice a week
	local tue = (function()
		for t = 0, 7 * 86400 - 1, 3600 do
			if (os.date("!*t", 1000 * 86400 + t) :: any).wday == 3 then
				return 1000 * 86400 + t - (1000 * 86400 + t) % 86400 + 18 * 3600
			end
		end
		return 0
	end)()
	check("Star Surge starts Tuesday 18:00 UTC", (function()
		local on = LiveEvents.active(tue + 60, nil)
		local off = LiveEvents.active(tue + 50 * 60, nil)
		local function has(list: any, id: string): boolean
			for _, a in list do
				if a.id == id then
					return true
				end
			end
			return false
		end
		return has(on, "StarSurge") and not has(off, "StarSurge") and not has(LiveEvents.active(tue - 60, nil), "StarSurge")
	end)())
	check("Star Surge repeats the next Tuesday and on Saturday", (function()
		local function has(t: number): boolean
			for _, a in LiveEvents.active(t, nil) do
				if a.id == "StarSurge" then
					return true
				end
			end
			return false
		end
		return has(tue + 7 * 86400 + 60) and has(tue + 4 * 86400 + 60) and not has(tue + 2 * 86400 + 60)
	end)())
	check("Star Surge doubles Stardust", LiveEvents.effects({ { id = "StarSurge", endsAt = 0 } }).stardustMult == 2)
end

-- model slots: fit math, variant picker, budget
do
	check("fitScale limited by the tightest axis", near(ModelFit.fitScale({ 2, 10, 2 }, { 4, 5, 4 }), 0.5))
	check("fitScale scales up too", near(ModelFit.fitScale({ 1, 1, 1 }, { 3, 6, 9 }), 3))
	check("fitScale ignores flat axes", near(ModelFit.fitScale({ 4, 0, 2 }, { 2, 9, 9 }), 0.5))
	check("fitScale of an empty model is 1", ModelFit.fitScale({ 0, 0, 0 }, { 5, 5, 5 }) == 1)
	check("pickVariant single", ModelFit.pickVariant(1, 12, 34) == 1)
	local seen, stable = {}, true
	for i = 1, 200 do
		local v = ModelFit.pickVariant(3, i * 7.3, i * -11.9)
		seen[v] = true
		stable = stable and v == ModelFit.pickVariant(3, i * 7.3, i * -11.9) and v >= 1 and v <= 3
	end
	check("pickVariant deterministic, in range, uses every variant", stable and seen[1] and seen[2] and seen[3])
	local names = ModelFit.variantNames("tree", { tree = true, tree_1 = true, tree_3 = true, rock = true })
	check("variantNames lists base and numbered", #names == 3 and names[1] == "tree" and names[2] == "tree_1" and names[3] == "tree_3")
	check("variantNames empty when absent", #ModelFit.variantNames("x", { y = true }) == 0)
	check("withinBudget ok", ModelFit.withinBudget(100, 300, 0, 1200))
	check("withinBudget slot cap", not ModelFit.withinBudget(301, 300, 0, 1200))
	check("withinBudget total cap", not ModelFit.withinBudget(100, 300, 1150, 1200))
end

do
	-- singular forms: exactly 1 picks the "<key>.one" text, anything else the plural
	local Locale = require("../src/shared/Locale")
	check("plural en 2", Locale.t("en", "toast.deleted", { n = 2 }) == "Deleted 2 pets")
	check("singular en 1", Locale.t("en", "toast.deleted", { n = 1 }) == "Deleted 1 pet")
	check("singular es 1", Locale.t("es", "pets.fused_n", { n = 1 }) == "¡1 mascota fusionada!")
	check("singular falls back to the plain text (ja)", Locale.t("ja", "toast.deleted", { n = 1 }) == "ペットを1体削除した")
	check("fractional stays plural", Locale.t("en", "upgrade.HitSpeed.desc", { n = 0.5 }) == "+0.5 hits per second")
	check("1 hit per second", Locale.t("en", "upgrade.HitSpeed.desc", { n = 1 }) == "+1 hit per second")
end

-- tutorial helper (round 8)
do
	local function ctx(over: any): any
		local c = { step = "mine", elapsed = 0, cargo = 5, stardust = 1000, needDust = nil, targetFound = true }
		for k, v in over do
			c[k] = v
		end
		return c
	end
	check("tutorial: every Config step has a target", (function()
		for _, st in Config.Tutorial do
			if TutorialFlow.hint(ctx({ step = st.id })).target == "fallback" then
				return false
			end
		end
		return true
	end)())
	check("tutorial: sell with empty cargo points at the planets", TutorialFlow.hint(ctx({ step = "sell", cargo = 0 })).target == "planet")
	check("tutorial: sell with ore points at the refinery", TutorialFlow.hint(ctx({ step = "sell", cargo = 3 })).target == "refinery")
	check("tutorial: tool without Stardust detours", TutorialFlow.hint(ctx({ step = "tool", stardust = 5, needDust = 400 })).reasonKey == "tutorial.hint_dust")
	check("tutorial: tool with Stardust goes to the workshop", TutorialFlow.hint(ctx({ step = "tool", stardust = 500, needDust = 400 })).target == "workshop")
	check("tutorial: missing planet falls back", TutorialFlow.hint(ctx({ targetFound = false })).target == "fallback")
	check("tutorial: unknown step falls back", TutorialFlow.hint(ctx({ step = "zzz" })).target == "fallback")
	check("tutorial: no skip at first", not TutorialFlow.hint(ctx({ elapsed = 3 })).skip)
	check("tutorial: skip after a while", TutorialFlow.hint(ctx({ elapsed = TutorialFlow.SKIP_AFTER })).skip)
	check("tutorial: loud before skip", TutorialFlow.hint(ctx({ elapsed = TutorialFlow.NUDGE_AFTER })).loud and TutorialFlow.NUDGE_AFTER < TutorialFlow.SKIP_AFTER)
	check("tutorial: progress", TutorialFlow.progress(1, 6) == 0 and near(TutorialFlow.progress(4, 6), 0.5) and TutorialFlow.progress(7, 6) == 1 and TutorialFlow.progress(1, 0) == 0)
	local clock = TutorialFlow.newClock()
	check("tutorial: clock starts at 0", clock.tick("mine", 100) == 0)
	check("tutorial: clock counts", near(clock.tick("mine", 112), 12))
	check("tutorial: clock restarts on a new step", clock.tick("core", 113) == 0)
	check("tutorial: clock restarts after rejoin (nil step)", clock.tick(nil, 200) == 0 and clock.tick("core", 201) == 0)
end

-- game feel + loading (round 8)
do
	check("ease bounds", Juice.easeOutCubic(0) == 0 and Juice.easeOutCubic(1) == 1 and Juice.easeOutCubic(5) == 1 and near(Juice.easeOutBack(1), 1) and Juice.easeOutBack(0.7) > 1)
	local shown = 0
	for _ = 1, 400 do
		shown = Juice.rollStep(shown, 1234, 1 / 60)
	end
	check("roll-up reaches the target and snaps", shown == 1234)
	check("roll-up never overshoots", Juice.rollStep(0, 100, 10) <= 100)
	check("calm mode: no shake", Juice.shakeAmplitude("break", true, false) == 0)
	check("shake lite is weaker", Juice.shakeAmplitude("break", false, true) < Juice.shakeAmplitude("break", false, false))
	check("shake unknown kind is 0", Juice.shakeAmplitude("zzz", false, false) == 0)
	local x0, y0 = Juice.shakeOffset(0.5, 0.05, 0.3)
	local xe, ye = Juice.shakeOffset(0.5, 0.3, 0.3)
	check("shake decays to exactly 0", xe == 0 and ye == 0 and (x0 ~= 0 or y0 ~= 0))
	local a, l = Juice.mergeShake(0.6, 0.3, 0.1, 0.1)
	check("merge keeps the stronger shake", a == 0.6 and l == 0.3)
	a, l = Juice.mergeShake(0.1, 0.05, 0.6, 0.3)
	check("merge takes a bigger shake", a == 0.6 and l == 0.3)
	check("budget caps concurrent effects", Juice.budget(10, 45, 48, false) == 3 and Juice.budget(10, 48, 48, false) == 0 and Juice.budget(10, 0, 48, true) == 5)
	local none = { remotes = false, state = false, world = false }
	local all = { remotes = true, state = true, world = true }
	check("loading never finishes instantly", not Juice.loadDone(0.2, all))
	check("loading finishes when ready after the minimum", Juice.loadDone(Juice.LOAD_MIN, all))
	check("loading waits for state+world", not Juice.loadDone(3, { remotes = true, state = true, world = false }))
	check("loading gives up at the cap whatever fails", Juice.loadDone(Juice.LOAD_MAX, none))
	local prev = 0
	local mono = true
	for i = 0, 60 do
		local p = Juice.loadProgress(i / 10, none)
		if p < prev or p > 1 then
			mono = false
		end
		prev = p
	end
	check("loading progress is monotonic and bounded", mono and Juice.loadProgress(0, all) == 1)
	check("tip index wraps", Juice.tipIndex(0, 3) == 1 and Juice.tipIndex(4, 3) == 2 and Juice.tipIndex(7.9, 0) == 1)
end

print(string.format("UNIT: %d checks, %d failures", total, fails))
