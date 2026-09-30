--!strict
-- Pure-Luau tests for the P0 helpers. Run from the project root:
--   ../huerta-tycoon/tools/luau.exe tests/p0_test.luau
local RunTime = require("../src/shared/RunTime")
local Referral = require("../src/shared/Referral")
local LiveEvents = require("../src/shared/LiveEvents")

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

-- RunTime ------------------------------------------------------------------------------------------
eq(RunTime.format(0), "00:00.000", "zero")
eq(RunTime.format(754567), "12:34.567", "12:34.567")
eq(RunTime.format(59999), "00:59.999", "just under a minute")
eq(RunTime.format(60000), "01:00.000", "one minute")
eq(RunTime.format(3723004), "1:02:03.004", "over an hour")
eq(RunTime.format(-5), "00:00.000", "negative")
eq(RunTime.format(nil), "00:00.000", "nil")
eq(RunTime.format(1234.9), "00:01.234", "fractional ms are floored")

-- Referral -----------------------------------------------------------------------------------------
eq(Referral.parse("ref:12345"), 12345, "valid")
eq(Referral.parse(Referral.make(987)), 987, "make/parse round trip")
eq(Referral.parse("ref:"), nil, "no digits")
eq(Referral.parse("ref:12a"), nil, "letters")
eq(Referral.parse(" ref:12"), nil, "leading space")
eq(Referral.parse("ref:12 "), nil, "trailing space")
eq(Referral.parse("REF:12"), nil, "case")
eq(Referral.parse("ref:0"), nil, "zero id")
eq(Referral.parse("ref:-4"), nil, "negative")
eq(Referral.parse(nil), nil, "nil")
eq(Referral.parse(42), nil, "number")
eq(Referral.parse("ref:" .. string.rep("9", 60)), nil, "too long")
eq(Referral.parse(""), nil, "empty")

-- LiveEvents ---------------------------------------------------------------------------------------
local defs: { LiveEvents.EventDef } = {
	{ id = "DoubleCoinsWeekend", kind = "weekly", fromWday = 7, toWday = 1, allDayUTC = true },
	{ id = "SkipSaleHour", kind = "daily", hourUTC = 20, duration = 3600 },
}
-- 2026-09-26 is a Saturday. 2026-09-26 00:00:00 UTC = 1790380800
local SAT0 = 1790380800
eq(LiveEvents.wdayOf(SAT0), 7, "2026-09-26 is Saturday (wday 7)")
eq(LiveEvents.wdayOf(SAT0 + 86400), 1, "next day is Sunday (wday 1)")
eq(LiveEvents.wdayOf(0), 5, "1970-01-01 was a Thursday")
local function active(id: string, t: number): boolean
	return LiveEvents.isActive(id, t, defs, nil)
end
check(not active("DoubleCoinsWeekend", SAT0 - 1), "Fri 23:59:59 -> weekend off")
check(active("DoubleCoinsWeekend", SAT0), "Sat 00:00:00 -> weekend on")
check(active("DoubleCoinsWeekend", SAT0 + 86400 + 86399), "Sun 23:59:59 -> weekend on")
check(not active("DoubleCoinsWeekend", SAT0 + 2 * 86400), "Mon 00:00:00 -> weekend off")
check(not active("DoubleCoinsWeekend", SAT0 - 3 * 86400), "Wednesday -> off")
local cur = LiveEvents.current(SAT0 + 3600, defs, nil)
eq(cur and cur.id, "DoubleCoinsWeekend", "current on Saturday")
eq(cur and cur.endsAt, SAT0 + 2 * 86400, "weekend ends Monday 00:00")
local wed = SAT0 - 3 * 86400
check(not active("SkipSaleHour", wed + 20 * 3600 - 1), "19:59:59 -> sale off")
check(active("SkipSaleHour", wed + 20 * 3600), "20:00:00 -> sale on")
check(active("SkipSaleHour", wed + 21 * 3600 - 1), "20:59:59 -> sale on")
check(not active("SkipSaleHour", wed + 21 * 3600), "21:00:00 -> sale off")
local sale = LiveEvents.current(wed + 20 * 3600 + 60, defs, nil)
eq(sale and sale.id, "SkipSaleHour", "current during the sale hour (weekday)")
eq(sale and sale.endsAt, wed + 21 * 3600, "sale ends 21:00")
eq(LiveEvents.current(wed + 12 * 3600, defs, nil), nil, "nothing on Wednesday noon")
local nx = LiveEvents.nextStart(wed + 12 * 3600, defs)
eq(nx and nx.id, "SkipSaleHour", "next event on Wednesday noon is the sale")
eq(nx and nx.startsAt, wed + 20 * 3600, "next sale today 20:00")
local nx2 = LiveEvents.nextStart(SAT0 - 3600, defs)
eq(nx2 and nx2.id, "DoubleCoinsWeekend", "Friday 23:00 -> weekend is next")
eq(nx2 and nx2.startsAt, SAT0, "weekend starts Saturday 00:00")
-- override (admin /event)
local ov = { id = "DoubleCoinsWeekend", endsAt = wed + 13 * 3600 }
check(LiveEvents.isActive("DoubleCoinsWeekend", wed + 12 * 3600, defs, ov), "override active")
check(not LiveEvents.isActive("DoubleCoinsWeekend", wed + 13 * 3600, defs, ov), "override expired")
eq((LiveEvents.current(wed + 12 * 3600, defs, ov) :: any).id, "DoubleCoinsWeekend", "override wins")
-- a Sunday-only and a wrapping Fri->Mon window
local custom: { LiveEvents.EventDef } = { { id = "X", kind = "weekly", fromWday = 6, toWday = 2, allDayUTC = true } }
check(LiveEvents.isActive("X", SAT0 - 1, custom, nil), "Fri 23:59 in Fri..Mon")
check(LiveEvents.isActive("X", SAT0 + 3 * 86400 - 1, custom, nil), "Mon 23:59 in Fri..Mon")
check(not LiveEvents.isActive("X", SAT0 + 3 * 86400, custom, nil), "Tue 00:00 out of Fri..Mon")

print(("%d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("p0 test FAILED")
end
print("p0 test PASSED")
