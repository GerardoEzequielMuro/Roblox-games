--!strict
-- Pure-Luau tests for the first-session helpers. Run from the project root:
--   luau tests/onboarding_test.luau
local Onboarding = require("../src/shared/Onboarding")
local Rarity = require("../src/shared/Rarity")
local FeelMath = require("../src/shared/FeelMath")
local Sounds = require("../src/shared/Sounds")
local Gifts = require("../src/shared/Gifts")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end
local function eq(a: any, b: any, msg: string)
	check(a == b, ("%s: expected %s, got %s"):format(msg, tostring(b), tostring(a)))
end

local function input(over: { [string]: any }?): Onboarding.Input
	local i = {
		at = 0, skipped = false, elapsed = 10, deaths = 0, targetKnown = true,
		coins = 0, shopCoins = 20, shopSeen = false, crossed = false, sinceGoal = 0,
	} :: any
	for k, v in over or {} do
		i[k] = v
	end
	return i
end

-- step machine ---------------------------------------------------------------------------------
local v = Onboarding.view(input())
eq(v.step, "go", "brand new player: go")
eq(v.textKey, "guide.go", "go hint")
eq(v.arrow, true, "arrow when the target is known")
eq(Onboarding.view(input({ targetKnown = false })).arrow, false, "no arrow when the target is missing")
check(Onboarding.view(input({ targetKnown = false })).textKey ~= nil, "still a text hint without a target")
v = Onboarding.view(input({ at = 1 }))
eq(v.step, "climb", "stage 1: climb")
eq(v.textKey, "guide.next", "climb hint")
eq(Onboarding.view(input({ at = 2, deaths = 2 })).textKey, "guide.retry", "advice after repeated deaths")
eq(Onboarding.view(input({ at = 0, deaths = 5 })).textKey, "guide.retry", "advice at stage 0 too")
eq(Onboarding.view(input({ at = 2, deaths = 1 })).textKey, "guide.next", "one death is not advice")

-- it always ends --------------------------------------------------------------------------------
eq(Onboarding.view(input({ skipped = true })).step, "done", "skip ends it")
eq(Onboarding.view(input({ skipped = true, at = 1 })).textKey, nil, "skipped: no text")
eq(Onboarding.view(input({ at = Onboarding.GOAL })).step, "done", "goal reached: done")
eq(Onboarding.view(input({ at = 500 })).step, "done", "veteran rejoining: no guide")
eq(Onboarding.view(input({ at = 0, elapsed = Onboarding.TIMEOUT })).step, "done", "timeout ends the climb hints")
eq(Onboarding.view(input({ at = 0, elapsed = Onboarding.TIMEOUT - 1 })).step, "go", "just before the timeout")
-- no input can produce a hint forever: with enough time and any stage, the result is done
for at = 0, 6 do
	for _, deaths in { 0, 3 } do
		eq(Onboarding.view(input({ at = at, deaths = deaths, elapsed = 1e6, sinceGoal = 1e6 })).step, "done", "ends for at=" .. at)
	end
end
-- resume after a rejoin: same stage, fresh clock -> same step
eq(Onboarding.view(input({ at = 1, elapsed = 0 })).step, "climb", "rejoin resumes")

-- first purchase ----------------------------------------------------------------------------------
v = Onboarding.view(input({ at = 3, crossed = true, coins = 25 }))
eq(v.step, "shop", "enough coins right after the goal: shop")
eq(v.glow, "menu", "shop hint glows the menu")
eq(Onboarding.view(input({ at = 3, crossed = true, coins = 19 })).step, "done", "not enough coins")
eq(Onboarding.view(input({ at = 3, crossed = false, coins = 999 })).step, "done", "veteran never gets the shop hint")
eq(Onboarding.view(input({ at = 3, crossed = true, coins = 25, shopSeen = true })).step, "done", "shop already opened")
eq(Onboarding.view(input({ at = 3, crossed = true, coins = 25, sinceGoal = Onboarding.SHOP_TIMEOUT })).step, "done", "shop hint times out")
eq(Onboarding.view(input({ at = 3, crossed = true, coins = 25, skipped = true })).step, "done", "skip kills the shop hint")

-- rarity ------------------------------------------------------------------------------------------
local lastRank = 0
for _, g in Gifts.List do
	local t = Rarity.ofGift(g.id)
	check(t.rank >= lastRank, "rarity never goes down the chain (gift " .. g.id .. ")")
	lastRank = t.rank
	check(#t.color == 3, "tier colour has 3 channels")
end
eq(Rarity.ofGift(1).id, "common", "gift 1 common")
eq(Rarity.ofGift(10).id, "legendary", "gift 10 legendary")
check(Rarity.ofGift(10).shake > Rarity.ofGift(1).shake, "bigger tiers shake more")

-- feel maths ----------------------------------------------------------------------------------------
eq(FeelMath.roll(0, 100, 0, 0.5), 0, "roll starts at from")
eq(FeelMath.roll(0, 100, 0.5, 0.5), 100, "roll ends at to")
eq(FeelMath.roll(0, 100, 9, 0.5), 100, "roll past the end is exactly to")
eq(FeelMath.roll(100, 40, 1, 1), 40, "roll down ends at to")
local mid = FeelMath.roll(0, 100, 0.25, 0.5)
check(mid > 0 and mid < 100, "roll mid-way is between")
local prev = -1
for k = 0, 20 do
	local x = FeelMath.roll(0, 1000, k / 20 * 0.6, 0.6)
	check(x >= prev, "roll is monotonic")
	prev = x
end
eq(FeelMath.roll(5, 1234, 0.1, 0), 1234, "zero duration jumps to the value")
eq(FeelMath.rollDuration(5, 5), 0, "no change: no roll")
check(FeelMath.rollDuration(0, 1e12) <= 0.8, "roll duration is capped")
check(FeelMath.rollDuration(0, 1) >= 0.25, "roll duration has a floor")
eq(FeelMath.easeOutBack(1), 1, "back ease ends at 1")
check(FeelMath.easeOutBack(0.7) > 1, "back ease overshoots")
local sx, sy = FeelMath.squash(0, 0.2)
check(math.abs(sx - 1) < 1e-9 and math.abs(sy - 1) < 1e-9, "squash starts at rest")
sx, sy = FeelMath.squash(1, 0.2)
check(math.abs(sx - 1) < 0.01 and math.abs(sy - 1) < 0.01, "squash settles at rest")
sx, sy = FeelMath.squash(0.2, 0.2)
check((sx - 1) * (sy - 1) < 0, "squash: one axis grows while the other shrinks")
eq(FeelMath.budget(0, 10, 6), 6, "budget caps a burst")
eq(FeelMath.budget(6, 3, 6), 0, "budget full")
eq(FeelMath.budget(4, 3, 6), 2, "budget partial")
eq(FeelMath.budget(9, 3, 6), 0, "budget never negative")
eq(FeelMath.shake(0.5, 0, 1), 0.5, "shake starts at power")
eq(FeelMath.shake(0.5, 1, 1), 0, "shake ends")
eq(FeelMath.shake(0.5, 2, 1), 0, "no shake after the end")

-- sounds: no invented ids ----------------------------------------------------------------------------
for name, id in Sounds.ids do
	eq(id, "", "sound id stays empty: " .. name)
	eq(Sounds.assetFor(name), nil, "empty id is a no-op: " .. name)
end
eq(Sounds.assetFor("nope"), nil, "unknown sound")
Sounds.ids.coin = "rbxassetid://12345"
eq(Sounds.assetFor("coin"), "rbxassetid://12345", "a real id works")
Sounds.ids.coin = "abc"
eq(Sounds.assetFor("coin"), nil, "garbage id is ignored")
Sounds.ids.coin = ""

print(("onboarding_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("onboarding_test failed")
end
