-- Unit tests for the pure P0 modules (run with luau.exe from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/unit_p0.luau
local Config = require("../src/shared/Config")
local Formulas = require("../src/shared/Formulas")
local LiveEvents = require("../src/shared/LiveEvents")
local Quests = require("../src/shared/Quests")
local Referral = require("../src/shared/Referral")

local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

---------------------------------------------------------------------------
-- LiveEvents schedule
---------------------------------------------------------------------------
-- 2026-09-23 is a Wednesday; midnight UTC = 1790121600
local WED = 1790121600
local lucky = Config.LiveEvents.recurring[1]
check("wday of reference is Wednesday", (os.date("!*t", WED) :: any).wday == 4)
local function ids(list)
	local out = {}
	for _, a in list do
		table.insert(out, a.id)
	end
	return table.concat(out, ",")
end
-- LuckyHour every 3 h at offset 0 for 15 min: WED is a multiple of 10800?
local start = WED - (WED - lucky.offset) % lucky.every
check("lucky active at its start", ids(LiveEvents.active(start, nil)):find("LuckyHour") ~= nil)
check("lucky active 1s before end", ids(LiveEvents.active(start + lucky.duration - 1, nil)):find("LuckyHour") ~= nil)
check("lucky over at end", ids(LiveEvents.active(start + lucky.duration, nil)):find("LuckyHour") == nil)
check("lucky over 1s before next", ids(LiveEvents.active(start + lucky.every - 1, nil)):find("LuckyHour") == nil)
local cur = LiveEvents.current(start + 60, nil)
check("current endsAt", cur ~= nil and cur.endsAt == start + lucky.duration, cur and cur.endsAt)
local nextAt, nextId = LiveEvents.nextStart(start + 1)
check("nextStart", nextAt == start + lucky.every and nextId == "LuckyHour", nextAt)
local nextAt2 = LiveEvents.nextStart(start)
check("nextStart strictly after now", nextAt2 == start + lucky.every, nextAt2)

-- Golden Weekend: Saturday + Sunday UTC
local SAT = WED + 3 * 86400
local SUN = WED + 4 * 86400
local MON = WED + 5 * 86400
local FRI_LATE = SAT - 1
check("weekend off on Friday 23:59:59", ids(LiveEvents.active(FRI_LATE + 0.5 - 0.5 - 3600, nil)):find("GoldenWeekend") == nil)
check("weekend on Saturday 00:00", ids(LiveEvents.active(SAT + 7200, nil)):find("GoldenWeekend") ~= nil)
check("weekend on Sunday 23:00", ids(LiveEvents.active(SUN + 82800 + 1800, nil)):find("GoldenWeekend") ~= nil)
check("weekend off Monday", ids(LiveEvents.active(MON + 7200, nil)):find("GoldenWeekend") == nil)
local we
for _, a in LiveEvents.active(SAT + 7200, nil) do
	if a.id == "GoldenWeekend" then
		we = a
	end
end
check("weekend ends Monday 00:00", we ~= nil and we.endsAt == MON, we and we.endsAt)

-- override
local ov = { id = "GoldenWeekend", endsAt = WED + 100000 }
local mid = start + lucky.duration + 600 -- no scheduled event (a Wednesday, between lucky hours)
check("no events mid-week gap", #LiveEvents.active(mid, nil) == 0, ids(LiveEvents.active(mid, nil)))
check("override active", LiveEvents.current(mid, ov) ~= nil and (LiveEvents.current(mid, ov) :: any).id == "GoldenWeekend")
check("override expires", #LiveEvents.active(ov.endsAt, ov) == 0 or ids(LiveEvents.active(ov.endsAt, ov)):find("GoldenWeekend") == nil)
check("unknown override ignored", #LiveEvents.active(mid, { id = "Nope", endsAt = mid + 50 }) == 0)
check("override first", ids(LiveEvents.active(start + 5, { id = "GoldenWeekend", endsAt = start + 999 })) == "GoldenWeekend,LuckyHour")

-- effects + odds with event luck
local fx = LiveEvents.effects(LiveEvents.active(start + 5, { id = "GoldenWeekend", endsAt = start + 999 }))
check("effects stack", fx.luckMult == 2 and fx.goldenMult == 2, fx.luckMult .. "/" .. fx.goldenMult)
check("luck with event", Formulas.luck(0, {}, false, 2) == 2)
check("luck event x super luck", Formulas.luck(0, {}, true, 2) == 4)
local base = Formulas.odds("basic", Formulas.luck(0, {}, false, 1))
local boosted = Formulas.odds("basic", Formulas.luck(0, {}, false, 2))
local sumB, sumE = 0, 0
for i, o in base do
	sumB += o.chance
	sumE += boosted[i].chance
end
check("odds renormalised", math.abs(sumB - 100) < 1e-9 and math.abs(sumE - 100) < 1e-9)
check("rare odds up with event luck", boosted[3].chance > base[3].chance and boosted[1].chance < base[1].chance)
check("golden chance x2", math.abs(Formulas.goldenChance(false, 2) - Config.BaseGoldenHatchChance * 2) < 1e-12)
check("golden chance capped", Formulas.goldenChance(true, 100) == 1)

---------------------------------------------------------------------------
-- Offline earnings
---------------------------------------------------------------------------
check("offline basic", Formulas.offlineEarnings(10, 3600, 8 * 3600) == math.floor(10 * Config.OfflineTapsPerSecond * 3600))
check("offline capped", Formulas.offlineEarnings(10, 99 * 3600, 8 * 3600) == math.floor(10 * Config.OfflineTapsPerSecond * 8 * 3600))
check("offline negative", Formulas.offlineEarnings(10, -50, 8 * 3600) == 0)
check("tap boost doubles", Formulas.tapValue({ petPower = 4, rebirths = 0, tapPowerLevel = 0, passes = {}, friends = 0, indexZonesDone = 0, tapBoost = true }) == 10)

---------------------------------------------------------------------------
-- Referral
---------------------------------------------------------------------------
check("parse ok", Referral.parse("ref:12345") == 12345)
check("parse roundtrip", Referral.parse(Referral.launchData(987654321)) == 987654321)
check("parse junk", Referral.parse("ref:abc") == nil and Referral.parse("xref:1") == nil and Referral.parse("ref:1 ") == nil)
check("parse zero", Referral.parse("ref:0") == nil)
check("parse non-string", Referral.parse(nil) == nil and Referral.parse(42) == nil)
check("parse too long", Referral.parse("ref:" .. string.rep("9", 60)) == nil)

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local d = 20354
local a1, a2 = Quests.forDay(d, 1), Quests.forDay(d, 1)
check("forDay deterministic", #a1 == Config.QuestsPerDay and a1[1].kind == a2[1].kind and a1[2].kind == a2[2].kind and a1[3].kind == a2[3].kind)
local allDistinct, varied = true, false
local firstKinds = Quests.forDay(0, 1)[1].kind
for day = 0, 200 do
	local seen = {}
	for _, q in Quests.forDay(day, 1) do
		if seen[q.kind] then
			allDistinct = false
		end
		seen[q.kind] = true
	end
	if Quests.forDay(day, 1)[1].kind ~= firstKinds then
		varied = true
	end
end
check("no duplicate kinds", allDistinct)
check("quests vary by day", varied)
local z1, z5 = Quests.forDay(d, 1), Quests.forDay(d, 5)
local scaled = true
for i, q in z1 do
	local def
	for _, p in Config.QuestPool do
		if p.kind == q.kind then
			def = p
		end
	end
	if q.target ~= def.targetByZone[1] or z5[i].target ~= def.targetByZone[5] or z5[i].kind ~= q.kind then
		scaled = false
	end
end
check("targets scale with zone", scaled)
check("resetsAt next midnight", Quests.resetsAt(WED + 5) == WED + 86400)

---------------------------------------------------------------------------
-- Auto tap rate
---------------------------------------------------------------------------
check("auto tap: free rate only while idle", Formulas.autoTapRate(0, false, true) == Config.AutoTapFreeRate and Formulas.autoTapRate(0, false, false) == 0)
check("auto tap: upgrade adds per level while idle", Formulas.autoTapRate(3, false, true) == Config.AutoTapFreeRate + 3 * Config.UpgradeById.AutoTap.perLevel and Formulas.autoTapRate(3, false, false) == 0)
check("auto tap: pass always counts", Formulas.autoTapRate(0, true, false) == Config.AutoTapRate and Formulas.autoTapRate(2, true, true) == Config.AutoTapRate + Config.AutoTapFreeRate + 2)
check("auto tap: best idle rate stays below an active player (6 taps/s)", Formulas.autoTapRate(Config.UpgradeById.AutoTap.maxLevel, false, true) < Config.RewardMinTapsPerSecond)
check("auto tap: free idle rate = offline rate", Config.AutoTapFreeRate == Config.OfflineTapsPerSecond)

---------------------------------------------------------------------------
-- Paid random items: displayed odds are numeric %, add up to exactly 100, never 0
---------------------------------------------------------------------------
local oddsBad = {}
for _, egg in Config.Eggs do
	for _, luck in { 1, 1.1, 1.6, 2, 3.2, 5, 6.4, 12.8 } do
		local shown = Formulas.displayOdds(egg.id, luck)
		local units, textSum = 0, 0
		for _, o in shown do
			units += o.units
			if o.units < 1 or not o.text:match("^%d+%.?%d*%%$") or o.text == "0%" then
				table.insert(oddsBad, egg.id .. " " .. o.pet .. " " .. o.text)
			end
			textSum += math.floor((tonumber((o.text:gsub("%%", ""))) :: number) * 10000 + 0.5)
		end
		if units ~= 1000000 or textSum ~= 1000000 or #shown ~= #egg.entries then
			table.insert(oddsBad, string.format("%s luck %.1f: %d units, text %d, %d entries", egg.id, luck, units, textSum, #shown))
		end
	end
end
check("displayed odds sum to exactly 100% for every egg and luck", #oddsBad == 0, table.concat(oddsBad, " | "))
local plain = Formulas.displayOdds("basic", 1)
check("displayed odds keep the config numbers at luck 1", plain[1].text == "60%" and plain[3].text == "8.999%" and plain[5].text == "0.001%", plain[1].text .. " " .. plain[3].text .. " " .. plain[5].text)
check("paid random: eggs, packs, luck and taps products", Formulas.isPaidRandomProduct("MagicEgg1") and Formulas.isPaidRandomProduct("StarterPack") and Formulas.isPaidRandomProduct("SuperLuck") and Formulas.isPaidRandomProduct("TapsSmall"))
check("paid random: gems are not", not Formulas.isPaidRandomProduct("GemsSmall") and not Formulas.isPaidRandomProduct("Nope"))
check("paid random: luck passes", Formulas.isPaidRandomPass("Lucky") and Formulas.isPaidRandomPass("MagicEggs") and Formulas.isPaidRandomPass("VIP") and not Formulas.isPaidRandomPass("AutoTap") and not Formulas.isPaidRandomPass("TripleHatch"))
-- no egg has an outcome that is "nothing"
local empty = false
for _, egg in Config.Eggs do
	for _, e in egg.entries do
		if not Formulas.PetById[e.pet] or e.chance <= 0 then
			empty = true
		end
	end
end
check("every egg outcome is a pet", not empty)

---------------------------------------------------------------------------
-- Traits
---------------------------------------------------------------------------
local traitSum, traitMono, prevMult = 0, true, 1
for _, g in Config.TraitGrades do
	traitSum += g.chance
	if g.mult <= prevMult then
		traitMono = false
	end
	prevMult = g.mult
end
check("trait odds sum to 100 and every grade is better than none", traitSum == 100 and traitMono, traitSum)
check("trait roll covers the whole range", Formulas.rollTrait(0) == 1 and Formulas.rollTrait(0.4499) == 1 and Formulas.rollTrait(0.45) == 2 and Formulas.rollTrait(0.9899) == 4 and Formulas.rollTrait(0.99) == 5 and Formulas.rollTrait(0.999999) == 5)
check("trait multiplies pet power, none leaves it alone", Formulas.petPower("dog", 0, 1) == 1 and Formulas.petPower("dog", 0, 1, nil) == 1 and math.abs(Formulas.petPower("bear", 1, 1, 5) - 9 * 3 * 1.6) < 1e-9 and Formulas.traitMult(99) == 1)
check("trait dice are not a product", Config.ProductByKey.TraitDice == nil)

---------------------------------------------------------------------------
-- Rebirth-gated eggs
---------------------------------------------------------------------------
check("gated egg: locked at 0 rebirths, open at its count", not Formulas.eggUnlocked("obsidian", 0) and Formulas.eggUnlocked("obsidian", 1) and Formulas.eggUnlocked("aurora", 2) and not Formulas.eggUnlocked("aurora", 1))
check("ungated egg: always open", Formulas.eggUnlocked("basic", 0) and Formulas.eggUnlocked("basalt", 0) and Formulas.eggMinRebirths("magma") == 0 and Formulas.eggMinRebirths("nope") == 0)
check("eggsUnlockedAt(1) is the obsidian egg, 0 unlocks nothing", #Formulas.eggsUnlockedAt(1) == 1 and Formulas.eggsUnlockedAt(1)[1] == "obsidian" and #Formulas.eggsUnlockedAt(0) == 0)
local gatedEveryRebirth = true
for r = 1, 4 do
	gatedEveryRebirth = gatedEveryRebirth and #Formulas.eggsUnlockedAt(r) >= 1
end
check("every rebirth from 1 to 4 opens at least one egg", gatedEveryRebirth)
check("gated pets do not move the power exclusive pets scale with", Formulas.petPower("sparklecat", 0, 3) == 1.5 * 15000 and Formulas.petPower("sparklecat", 0, 4) == 1.5 * 250000 and Formulas.petPower("sparklecat", 0, 5) == 1.5 * 4200000, Formulas.petPower("sparklecat", 0, 3))

print(string.format("%d unit checks, %d failures%s", total, fails, if fails == 0 then " -> UNIT TESTS PASSED" else ""))
