-- Pure tests for the tutorial step machine and the juice helpers (run from the game folder):
--   luau tests/onboarding.luau
local Config = require("../src/shared/Config")
local HudUnlock = require("../src/shared/HudUnlock")
local Onboarding = require("../src/shared/Onboarding")
local Juice = require("../src/shared/Juice")

local fails, total = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name .. (if detail ~= nil then " :: " .. tostring(detail) else ""))
	end
end

local price = Config.Eggs[1].price
local new = { totalHatched = 0, zones = { 1 }, rebirths = 0, taps = 0 }

-- step order for a brand-new player
local s = Onboarding.step(new, {})
check("new -> tap", s.id == "tap" and s.pulse == "tap" and not s.beam and s.skippable, s.id)
s = Onboarding.step({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = price - 1 }, {})
check("almost -> still tap", s.id == "tap")
s = Onboarding.step({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = price }, { nearEgg = false })
check("can buy, far -> walk with beam", s.id == "walk" and s.beam, s.id)
s = Onboarding.step({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = price }, { nearEgg = true })
check("can buy, near -> hatch with egg pulse", s.id == "hatch" and s.pulse == "egg" and not s.beam, s.id)
s = Onboarding.step({ totalHatched = 1, zones = { 1 }, rebirths = 0, taps = 0 }, {})
check("first pet -> more", s.id == "more" and s.args.have == 1 and s.args.n == Onboarding.HATCH_GOAL)
s = Onboarding.step({ totalHatched = Onboarding.HATCH_GOAL, zones = { 1 }, rebirths = 0, taps = 0 }, {})
check("goal reached -> done", s.id == "done" and not s.skippable)

-- no soft-lock: skip ends it from every step, veterans never see it, missing target falls back
for _, snap in {
	new,
	{ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = price },
	{ totalHatched = 3, zones = { 1 }, rebirths = 0, taps = price },
} do
	check("skip ends the tutorial", Onboarding.step(snap, { skipped = true }).id == "done")
end
check("rebirthed veteran: done", Onboarding.step({ totalHatched = 0, zones = { 1 }, rebirths = 1, taps = 0 }, {}).id == "done")
check("zone 2 veteran: done", Onboarding.step({ totalHatched = 0, zones = { 1, 2 }, rebirths = 0, taps = 0 }, {}).id == "done")
s = Onboarding.step({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = price }, { targetOk = false })
check("missing egg target -> text only, no beam", s.id == "find" and not s.beam)
s = Onboarding.step({ totalHatched = 2, zones = { 1 }, rebirths = 0, taps = price }, { targetOk = false })
check("missing target on 'more' -> no beam", s.id == "more" and not s.beam)
-- empty / partial snapshots never error
check("empty snapshot", Onboarding.step({}, nil).id == "tap")

-- help variant after idling
s = Onboarding.step(new, { idle = Onboarding.HELP_AFTER })
check("idle -> help text", s.help and s.key == "ftue.tap_help", s.key)
s = Onboarding.step(new, { idle = Onboarding.HELP_AFTER - 1 })
check("not idle yet", not s.help and s.key == "ftue.tap")

-- every step key is short (3-6 words in English is checked in locale_check via the keys)
local en = require("../src/shared/Locales/en")
for _, k in { "ftue.tap", "ftue.tap_help", "ftue.walk", "ftue.find_egg", "ftue.hatch", "ftue.more", "ftue.skip", "ftue.unlocked" } do
	local text = en[k]
	check("en has " .. k, type(text) == "string")
	if type(text) == "string" then
		local clean = text:gsub("{[^}]*}", "x")
		local words = 0
		for _ in clean:gmatch("%S+") do
			words += 1
		end
		check(k .. " is 1-6 words", words >= 1 and words <= 6, words)
	end
end

-- idle tracker
local t = Onboarding.newTracker(0)
check("tracker starts at 0", Onboarding.idle(t, "tap", 5, 0) == 0)
check("tracker counts", Onboarding.idle(t, "tap", 5, 10) == 10)
check("progress resets", Onboarding.idle(t, "tap", 6, 12) == 0)
check("step change resets", Onboarding.idle(t, "walk", 6, 20) == 0 and Onboarding.idle(t, "walk", 6, 25) == 5)
check("progressOf grows with taps", Onboarding.progressOf({ taps = 10 }) < Onboarding.progressOf({ taps = 11 }))
check("progressOf grows with hatches", Onboarding.progressOf({ totalHatched = 1 }) < Onboarding.progressOf({ totalHatched = 2 }))

-- unlock diff
local v0 = HudUnlock.visible({ totalHatched = 0, zones = { 1 }, rebirths = 0, taps = 0 })
local v1 = HudUnlock.visible({ totalHatched = 1, zones = { 1 }, rebirths = 0, taps = 0 })
check("first snapshot: nothing new", #Onboarding.newlyUnlocked(nil, v1) == 0)
local n1 = Onboarding.newlyUnlocked(v0, v1)
check("first egg unlocks 3 buttons", #n1 == 3, #n1)
check("no repeat", #Onboarding.newlyUnlocked(v1, v1) == 0)

-- juice
check("envelope start", Juice.envelope(0, 1) == 1)
check("envelope end", Juice.envelope(1, 1) == 0 and Juice.envelope(2, 1) == 0 and Juice.envelope(0.5, 0) == 0)
check("envelope monotonic", Juice.envelope(0.2, 1) > Juice.envelope(0.6, 1))
check("reduced motion: no shake", Juice.shakeAmplitude(1, true, false) == 0)
check("shake capped", Juice.shakeAmplitude(99, false, false) == Juice.MAX_SHAKE)
check("lite calmer", Juice.shakeAmplitude(1, false, true) < Juice.shakeAmplitude(1, false, false))
local mx = 0
for i = 0, 100 do
	local x, y = Juice.shakeOffset(i / 100 * 0.4, 0.4, Juice.MAX_SHAKE, 3)
	mx = math.max(mx, math.abs(x), math.abs(y))
end
check("offset within cap", mx <= Juice.MAX_SHAKE + 1e-9, mx)
local ex, ey = Juice.shakeOffset(0.5, 0.4, 0.4, 1)
check("offset zero after end", ex == 0 and ey == 0)
check("burst cap", Juice.allowBurst(10, 20, 24, 1) == 4 and Juice.allowBurst(10, 24, 24, 1) == 0 and Juice.allowBurst(10, 30, 24, 1) == 0)
check("burst lite", Juice.allowBurst(10, 0, 24, 0.5) == 5 and Juice.allowBurst(10, 0, 24, 0) == 0)
check("roll converges", Juice.roll(0, 100, 1, 9) <= 100 and Juice.roll(99.5, 100, 0.01) == 100)
check("roll never overshoots", Juice.roll(0, 100, 10) == 100)
check("squash settles", Juice.squash(1, 0.3) == 1 and math.abs(Juice.squash(0.99, 0.3) - 1) < 0.01)
check("squash moves", Juice.squash(0.17, 0.3) ~= 1)

print(("onboarding/juice: %d checks, %d failed"):format(total, fails))
if fails > 0 then
	error("tests failed")
end
