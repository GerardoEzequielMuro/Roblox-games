-- First-session logic checks (run from the game folder: luau tests/onboarding_check.luau)
local O = require("../src/shared/Onboarding")
local Config = require("../src/shared/Config")

local fails = 0
local function check(cond: boolean, msg: string)
	if not cond then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- skip rules
local T = Config.TutorialSteps
check(O.canSkip(1, "reps", T), "first step skippable")
check(O.canSkip(T, "defeat", T), "tutorial defeat skippable")
check(not O.canSkip(T + O.SKIP_EXTRA + 1, "reps", T), "late steps not skippable")
check(not O.canSkip(10, "form", T), "form never skippable")
check(not O.canSkip(0, "reps", T), "index 0 invalid")
check(not O.canSkip(2, "boss", T), "boss not skippable")
-- every tutorial step in Config is skippable or reachable by normal play (no unskippable early dead end)
for i = 1, T + O.SKIP_EXTRA do
	local s = Config.Story[i]
	check(O.canSkip(i, s.kind, T), "tutorial step " .. i .. " (" .. s.kind .. ") must be skippable")
end

-- stuck levels + tracker
check(O.stuckLevel(0) == 0 and O.stuckLevel(19.9) == 0, "stuck 0")
check(O.stuckLevel(20) == 1 and O.stuckLevel(44) == 1, "stuck 1")
check(O.stuckLevel(45) == 2 and O.stuckLevel(999) == 2, "stuck 2")
local t, idle = O.track(nil, 1, 0, 100)
check(idle == 0, "first track idle 0")
t, idle = O.track(t, 1, 0, 130)
check(idle == 30 and O.stuckLevel(idle) == 1, "idle grows")
t, idle = O.track(t, 1, 1, 131)
check(idle == 0, "progress resets idle")
t, idle = O.track(t, 2, 0, 140)
check(idle == 0, "new step resets idle")
t, idle = O.track(t, 2, 0, 100) -- clock going backwards never gives negative idle
check(idle == 0, "no negative idle")

-- pointers
check(O.pointerName("reps", true) == "Touch_punch" and O.pointerName("reps", false) == "Slot_melee", "reps pointer")
check(O.pointerName("gear", false) == "Gear", "gear pointer")
check(O.pointerName("defeat", false) == nil, "world steps have no HUD pointer")
for i = 1, T + O.SKIP_EXTRA do
	local k = Config.Story[i].kind
	check(O.pointerName(k, true) ~= nil or Config.Story[i].guide ~= "none", "tutorial step " .. i .. " (" .. k .. ") must have a pointer or a guide")
end

-- loading never hangs
local f, close = O.loadingProgress(0, { false, false, false })
check(not close and f < 0.2, "start of load open")
f, close = O.loadingProgress(0.3, { true, true, true })
check(not close, "min time respected")
f, close = O.loadingProgress(0.8, { true, true, true })
check(close and f == 1, "closes when ready")
f, close = O.loadingProgress(2, { true, false, false })
check(not close and f > 0.3 and f < 1, "waits for a missing stage")
f, close = O.loadingProgress(O.LOAD_MAX, { false, false, false })
check(close and f == 1, "hard cap closes even if nothing loaded")
f, close = O.loadingProgress(10, {})
check(close and f == 1, "no stages closes")
local last = 0
for i = 0, 40 do
	local ff = O.loadingProgress(i * 0.1, { i > 10, i > 20, false })
	check(ff >= last - 1e-9, "progress monotonic")
	last = ff
end

-- roll
check(O.rollValue(0, 100, 0) == 0, "roll start")
check(O.rollValue(0, 100, 0.5) == 100, "roll end")
check(O.rollValue(0, 100, 0.1) > 20 and O.rollValue(0, 100, 0.1) < 100, "roll ease out")
check(O.rollValue(100, 40, 0.25) < 100 and O.rollValue(100, 40, 0.25) > 40, "roll down")
check(O.rollValue(5, 5, 0.1) == 5, "roll same")

-- combo tiers
local F = Config.Combat.comboFinisher
check(O.comboTier(1, F).tier == 0 and O.comboTier(1, F).key == nil, "hit 1 plain")
check(O.comboTier(3, F).key == "combo.start", "hit 3 callout")
check(O.comboTier(F, F).finisher and O.comboTier(F, F).shake > 0, "finisher shakes")
check(not O.comboTier(F + 1, F).finisher, "non finisher")
check(O.comboTier(F * 3, F).key == "combo.t3", "big finisher")
check(O.comboTier(F * 2, F).shake > O.comboTier(F, F).shake, "shake grows with tier")
check(O.comboTier(F * 3, F).scale > O.comboTier(2, F).scale, "scale grows")

-- transform plan
local p = O.transformPlan(false, false, true)
check(p.windup > 0 and p.kick > 0 and p.shake > 0 and p.bars, "first form: full show")
local r = O.transformPlan(false, true, true)
check(r.zoom == 0 and r.kick == 0 and r.shake == 0 and r.flash < p.flash, "reduced motion: no camera, soft flash")
check(O.transformPlan(true, false, false).shells < p.shells, "lite: fewer shells")
check(not O.transformPlan(false, false, false).bars, "later forms: no letterbox")

if fails > 0 then
	error(fails .. " onboarding check(s) failed")
end
print("ONBOARDING CHECKS PASSED")
