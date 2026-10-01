--!strict
-- Pure tests: tutorial step machine, soft-lock recovery, progressive menu, loading progress, game-feel rules.
-- Run from the project root: luau tests/onboarding_test.luau
local O = require("../src/shared/Onboarding")
local F = require("../src/shared/Feel")

local checks, fails = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function facts(bp: number, crop: boolean, ripe: boolean, seeds: number): O.Facts
	return { backpackCount = bp, hasCrop = crop, ripe = ripe, seeds = seeds }
end

-- ===== step machine (derived only from state: resumes after rejoin, cannot get stuck on a stale step) =====
check(O.step(facts(0, false, false, 0)) == 1, "no seeds -> step 1")
check(O.step(facts(0, false, false, 3)) == 2, "seeds -> step 2")
check(O.step(facts(0, true, false, 2)) == 3, "crop planted -> step 3")
check(O.step(facts(0, true, true, 0)) == 3, "ripe crop -> step 3")
check(O.step(facts(1, false, false, 0)) == 4, "basket -> step 4")
check(O.step(facts(5, true, true, 3)) == 4, "basket wins over everything")
for bp = 0, 2 do
	for _, crop in { false, true } do
		for seeds = 0, 2 do
			local s = O.step(facts(bp, crop, false, seeds))
			check(s >= 1 and s <= O.STEPS, "step always in range")
		end
	end
end
check(O.textKey(1, facts(0, false, false, 0), false) == "tut.1", "text 1")
check(O.textKey(2, facts(0, false, false, 1), false) == "tut.2", "pick a seed text")
check(O.textKey(2, facts(0, false, false, 1), true) == "tut.2b", "tap a tile text")
check(O.textKey(3, facts(0, true, false, 0), false) == "tut.3w", "growing text")
check(O.textKey(3, facts(0, true, true, 0), false) == "tut.3", "ripe text")
check(O.textKey(4, facts(1, false, false, 0), false) == "tut.4", "sell text")

-- ===== recovery =====
check(O.alreadyPlayed(1) and not O.alreadyPlayed(0), "a player who already sold skips the tutorial on rejoin")
check(not O.stuck(10) and O.stuck(O.STUCK_AFTER), "stuck hint after the timeout")
check(not O.giveUp(60) and O.giveUp(O.GIVE_UP_AFTER), "tutorial ends by itself eventually")
check(O.targetFallback(true, true) == 1 and O.targetFallback(false, true) == 2 and O.targetFallback(false, false) == 0, "target fallback order")
check(O.STUCK_AFTER < O.GIVE_UP_AFTER, "the hint comes before giving up")

-- ===== progressive menu =====
check(O.menuTier(0, 0, false) == 0, "new player: tier 0")
check(O.menuTier(10, 0, false) == 1, "first sale: tier 1")
check(O.menuTier(0, 0, true) == 1, "skipped tutorial: tier 1")
check(O.menuTier(O.TIER2_EARNED, 0, false) == 2, "enough earned: tier 2")
check(O.menuTier(0, 1, true) == 2, "rebirthed: tier 2")
check(O.menuVisible("Shop", 0) and O.menuVisible("Daily", 0), "shop + daily always there")
check(not O.menuVisible("Store", 0) and not O.menuVisible("Rebirth", 1) and O.menuVisible("Rebirth", 2), "tiers gate the rest")
check(O.menuVisible("Language", 0), "unknown names are never hidden")
local last = -1
for tier = 0, 2 do
	local n = 0
	for name in O.MENU_TIER do
		if O.menuVisible(name, tier) then
			n += 1
		end
	end
	check(n > last, "menu only grows")
	last = n
end
check(last == 10, "every menu button is visible at tier 2")

-- ===== loading =====
check(O.loadProgress(0, 3, 0) == 0, "starts at 0")
check(O.loadProgress(3, 3, 1) >= 0.95, "all stages -> nearly full")
check(O.loadProgress(0, 3, O.LOAD_MAX) > 0.5, "time alone keeps the bar moving")
check(O.loadProgress(0, 3, 100) <= 0.95, "never full from time alone")
local prev = 0
for i = 0, 20 do
	local p = O.loadProgress(math.floor(i / 7), 3, i * 0.3)
	check(p >= prev - 1e-9, "progress never goes backwards")
	prev = p
end
check(not O.loadDone(true, 0.1), "no one-frame flash")
check(O.loadDone(true, O.LOAD_MIN), "ready -> dismiss after the minimum")
check(not O.loadDone(false, 2), "not ready yet keeps waiting")
check(O.loadDone(false, O.LOAD_MAX), "never blocks longer than LOAD_MAX")
check(O.LOAD_MAX <= 8, "a few seconds at most")

-- ===== game feel =====
check(select(1, F.shake(1, false, true)) == 0, "reduced motion: no shake")
check(select(1, F.shake(0, false, false)) == 0, "no power: no shake")
local a1, d1 = F.shake(0.5, false, false)
local a2 = F.shake(0.5, true, false)
check(a1 > 0 and d1 > 0 and d1 < 0.6, "shake is short")
check(a2 < a1, "lite shakes less")
check(F.shake(5, false, false) <= 0.3, "amplitude is capped (micro-shake)")
check(F.tier(1, false) == 0 and F.tier(2, false) == 1 and F.tier(8, false) == 2 and F.tier(25, false) == 3 and F.tier(1, true) == 2, "tiers")
check(F.tier(nil, nil) == 0, "nil -> plain")
check(not F.bigMoment(1) and F.bigMoment(2), "only rare+ is a big moment")
check(F.tierPower(0) == 0 and F.tierPower(3) > F.tierPower(2), "power grows with the tier")
check(F.popScale(0, 10) == 1.1 and F.popScale(1e12, 10) <= 1.6 and F.popScale(100, 10) > F.popScale(10, 10), "pop scale grows and is clamped")
local shown = 0
for _ = 1, 120 do
	shown = F.roll(shown, 1000, 1 / 60)
end
check(shown == 1000, "counter reaches the target")
check(F.roll(500, 1000, 1 / 60) > 500 and F.roll(500, 1000, 1 / 60) < 1000, "counter rolls gradually")
check(F.roll(0, 1000, 1 / 30) > 0 and math.abs(F.roll(0, 1000, 1 / 30) - F.roll(F.roll(0, 1000, 1 / 60), 1000, 1 / 60)) < 1, "roll is frame-rate independent")
check(F.room(10, 12, 5) == 2 and F.room(12, 12, 5) == 0 and F.room(20, 12, 5) == 0 and F.room(0, 12, 3) == 3, "effect cap")

print(string.format("onboarding_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	error("onboarding_test failed")
end
