--!strict
-- Pure-Luau unit tests for the P0 systems. Run from the project root: tools/luau.exe tests/p0_test.luau
local Gifts = require("../src/shared/Gifts")
local LiveEvents = require("../src/shared/LiveEvents")
local CropIndex = require("../src/shared/CropIndex")
local Referral = require("../src/shared/Referral")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- ===== Gifts =====
local GIFTS = { { minutes = 5 }, { minutes = 10 }, { minutes = 15 }, { minutes = 25 }, { minutes = 40 }, { minutes = 60 } }
local start = 1000000
do
	local v, n = Gifts.ready(GIFTS, start, start + 4 * 60 + 59, {})
	check(n == 0 and v[1].ready == false, "no gift before 5 min")
	v, n = Gifts.ready(GIFTS, start, start + 5 * 60, {})
	check(n == 1 and v[1].ready and not v[2].ready, "gift 1 ready at exactly 5 min")
	v, n = Gifts.ready(GIFTS, start, start + 61 * 60, { [1] = true, [3] = true })
	check(n == 4 and v[1].claimed and not v[1].ready and v[6].ready, "claimed gifts are not ready; 4 left at 61 min")
	check(select(1, Gifts.canClaim(GIFTS, 2, start, start + 600, {})) == true, "claim gift 2 at 10 min")
	check(select(2, Gifts.canClaim(GIFTS, 2, start, start + 599, {})) == "early", "gift 2 too early at 9:59")
	check(select(2, Gifts.canClaim(GIFTS, 2, start, start + 9999, { [2] = true })) == "claimed", "gift 2 twice")
	check(select(2, Gifts.canClaim(GIFTS, 7, start, start + 9999, {})) == "bad", "gift 7 doesn't exist")
	check(select(2, Gifts.canClaim(GIFTS, 1.5 :: any, start, start + 9999, {})) == "bad", "fractional index")
	check(select(2, Gifts.canClaim(GIFTS, "1" :: any, start, start + 9999, {})) == "bad", "string index")
	check(Gifts.secondsLeft(GIFTS[1], start, start + 60) == 240, "4 min left")
	check(Gifts.secondsLeft(GIFTS[1], start, start + 999) == 0, "0 when ready")
	check(Gifts.cashFor(2, 0, 100) == 200, "cash floor")
	check(Gifts.cashFor(2, 5000, 100) == 10000, "cash from earn rate")
end

-- ===== LiveEvents =====
local SCHED = {
	weekly = { { id = "HarvestFestival", wday = 7, hourUTC = 18, minute = 0, duration = 1800 } },
	recurring = { { id = "LuckyHour", every = 10800, offset = 0, duration = 600 } },
}
-- 2026-09-26 is a Saturday. Build UTC timestamps without relying on the local timezone.
local function utc(y: number, mo: number, d: number, h: number, mi: number, sec: number?): number
	-- days from civil (Howard Hinnant)
	local yy = if mo <= 2 then y - 1 else y
	local era = (if yy >= 0 then yy else yy - 399) // 400
	local yoe = yy - era * 400
	local mp = (mo + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + h * 3600 + mi * 60 + (sec or 0)
end
do
	check((os.date("!*t", utc(2026, 9, 26, 12, 0)) :: any).wday == 7, "helper: 2026-09-26 is Saturday")
	local satEvent = utc(2026, 9, 26, 18, 0)
	-- before: 17:59:59 Saturday -> recurring LuckyHour? 18:00 is a multiple of 3h (UTC) -> check phase math
	local c = LiveEvents.current(satEvent - 1, SCHED, nil)
	check(c == nil or c.id ~= "HarvestFestival", "festival not active 1 s before start")
	c = LiveEvents.current(satEvent, SCHED, nil)
	check(c ~= nil and c.id == "HarvestFestival" and c.endsAt == satEvent + 1800, "festival active at start (beats LuckyHour overlap)")
	c = LiveEvents.current(satEvent + 1799, SCHED, nil)
	check(c ~= nil and c.id == "HarvestFestival", "festival active at last second")
	c = LiveEvents.current(satEvent + 1800, SCHED, nil)
	check(c == nil, "festival over at +1800 (18:30 is outside LuckyHour 18:00-18:10)")
	-- overlap: LuckyHour runs 18:00-18:10 UTC too; weekly must win
	c = LiveEvents.current(satEvent + 300, SCHED, nil)
	check(c ~= nil and c.id == "HarvestFestival", "weekly beats recurring when overlapping")
	-- recurring on a weekday
	local wed = utc(2026, 9, 23, 3, 5)
	c = LiveEvents.current(wed, SCHED, nil)
	check(c ~= nil and c.id == "LuckyHour" and c.endsAt == utc(2026, 9, 23, 3, 10), "LuckyHour 03:00-03:10 UTC")
	check(LiveEvents.current(utc(2026, 9, 23, 3, 10), SCHED, nil) == nil, "LuckyHour ends at 03:10")
	-- next start across the Saturday boundary
	local n = LiveEvents.nextStart(utc(2026, 9, 26, 16, 30), SCHED)
	check(n ~= nil and n.id == "HarvestFestival" and n.startsAt == satEvent, "next = festival at 18:00 (tie with LuckyHour, weekly wins)")
	n = LiveEvents.nextStart(satEvent + 60, SCHED)
	check(n ~= nil and n.id == "LuckyHour" and n.startsAt == utc(2026, 9, 26, 21, 0), "after festival starts, next is LuckyHour 21:00")
	local sun = utc(2026, 9, 27, 1, 0)
	check(LiveEvents.weeklyStart(sun, SCHED.weekly[1]) == satEvent, "Sunday: last festival start was Saturday 18:00")
	check(LiveEvents.weeklyStart(satEvent - 1, SCHED.weekly[1]) == satEvent - 7 * 86400, "just before: last week's")
	-- override honored until it expires
	local ov = { id = "LuckyHour", endsAt = wed + 1000 }
	c = LiveEvents.current(utc(2026, 9, 23, 5, 0), SCHED, ov)
	check(c == nil, "expired override ignored")
	c = LiveEvents.current(wed + 999, SCHED, { id = "HarvestFestival", endsAt = wed + 1000 })
	check(c ~= nil and c.id == "HarvestFestival" and c.endsAt == wed + 1000, "override wins while active")
	c = LiveEvents.current(wed + 1000, SCHED, { id = "HarvestFestival", endsAt = wed + 1000 })
	check(c == nil or c.id ~= "HarvestFestival", "override expires at endsAt")
end

-- ===== CropIndex =====
do
	local MUTS = { "Rainbow", "Shocked", "Golden", "Frozen", "Wet" }
	check(#CropIndex.variants(MUTS) == 6, "6 variants per seed")
	check(not CropIndex.rowComplete(nil, MUTS), "empty row incomplete")
	local found = { Normal = true, Rainbow = true, Shocked = true, Golden = true, Frozen = true }
	check(not CropIndex.rowComplete(found, MUTS), "missing Wet -> incomplete")
	local f, t = CropIndex.count(found, MUTS)
	check(f == 5 and t == 6, "5/6")
	found.Wet = true
	check(CropIndex.rowComplete(found, MUTS), "all 6 -> complete")
	check(not CropIndex.rowComplete({ Rainbow = true, Shocked = true, Golden = true, Frozen = true, Wet = true }, MUTS), "Normal required")
	check(math.abs(CropIndex.bonus(3, 12, 0.02, 0.1) - 0.06) < 1e-9, "3 rows = +6%")
	check(math.abs(CropIndex.bonus(12, 12, 0.02, 0.1) - 0.34) < 1e-9, "all rows = +24% + 10%")
	check(CropIndex.rowCash(15, 50) == 750, "row cash")
end

-- ===== Referral =====
do
	check(Referral.parse(nil) == nil, "nil")
	check(Referral.parse("") == nil, "empty")
	check(Referral.parse("ref:") == nil, "no digits")
	check(Referral.parse("ref:abc") == nil, "letters")
	check(Referral.parse("ref:123") == 123, "ref:123")
	check(Referral.parse("ref:123x") == nil, "trailing junk")
	check(Referral.parse("xref:123") == nil, "leading junk")
	check(Referral.parse("ref:0") == nil, "zero")
	check(Referral.parse(123 :: any) == nil, "not a string")
	check(Referral.parse(Referral.encode(98765)) == 98765, "encode/parse round trip")
end

print(string.format("p0_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("p0_test failed")
end
