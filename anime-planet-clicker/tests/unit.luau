-- Pure-logic unit tests (run from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/unit.luau
local Config = require("../src/shared/Config")
local F = require("../src/shared/Formulas")
local Layout = require("../src/shared/Layout")
local LiveEvents = require("../src/shared/LiveEvents")
local Quests = require("../src/shared/Quests")
local Referral = require("../src/shared/Referral")
local Format = require("../src/shared/Format")

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
check("incomeZone follows the tool", F.incomeZone(3, 6) == 1 and F.incomeZone(4, 6) == 2 and F.incomeZone(12, 6) == 6 and F.incomeZone(12, 2) == 2)

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

print(string.format("UNIT: %d checks, %d failures", total, fails))
