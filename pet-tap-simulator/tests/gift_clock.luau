-- Pure test of the "minutes since joining" gifts persistence (luau tests/gift_clock.luau).
local GiftClock = require("../src/shared/GiftClock")

local fails, total = 0, 0
local function check(name: string, cond: boolean)
	total += 1
	if not cond then
		fails += 1
		print("FAIL " .. name)
	end
end

local DAY = GiftClock.DAY_SECONDS
local t0 = 20000 * DAY + 3600 -- some UTC day, 01:00

-- old saves: no field / wrong types fall back to safe defaults
local d = GiftClock.sanitize(nil)
check("nil -> default", d.day == 0 and d.played == 0 and next(d.claimed) == nil)
local bad = GiftClock.sanitize({ day = "x", played = -5, claimed = { ["1"] = true, ["z"] = true, ["2"] = 7 } })
check("bad fields", bad.day == 0 and bad.played == 0 and bad.claimed["1"] == true and bad.claimed["z"] == nil and bad.claimed["2"] == nil)
check("nan played", GiftClock.sanitize({ played = 0 / 0 }).played == 0)

-- session 1: play 130 s, claim gift 1 (1 min) and 2 (2 min)
local g = GiftClock.sanitize(nil)
check("first roll starts the day", GiftClock.roll(g, t0) == true and g.day == GiftClock.dayKey(t0))
check("gift not ready at 59 s", not GiftClock.ready(59 - 1.5, 1))
check("gift ready at 60 s", GiftClock.ready(60, 1))
g.played = 130
GiftClock.markClaimed(g, 1)
GiftClock.markClaimed(g, 2)

-- rejoin the same day (profile round-trips through the DataStore: plain keys, JSON-like)
local saved = GiftClock.sanitize(table.clone(g))
check("rejoin same day: no reset", GiftClock.roll(saved, t0 + 600) == false)
check("rejoin same day: still claimed", GiftClock.isClaimed(saved, 1) and GiftClock.isClaimed(saved, 2))
check("rejoin same day: cannot re-claim (claimed list)", #GiftClock.claimedList(saved) == 2)
check("rejoin same day: time continues", saved.played == 130)
check("rejoin same day: next gift timer continues", GiftClock.ready(saved.played + 20, 2.5) and not GiftClock.ready(saved.played, 3))
check("not claimed gift stays open", not GiftClock.isClaimed(saved, 3))

-- next day resets everything
check("new day resets", GiftClock.roll(saved, t0 + DAY) == true)
check("new day: claims cleared", next(saved.claimed) == nil and #GiftClock.claimedList(saved) == 0)
check("new day: played cleared", saved.played == 0)
check("new day: can claim again", not GiftClock.isClaimed(saved, 1))

-- crossing midnight within the same session
local m = GiftClock.sanitize(nil)
GiftClock.roll(m, 5 * DAY + DAY - 10)
GiftClock.markClaimed(m, 1)
check("before midnight same day", GiftClock.roll(m, 5 * DAY + DAY - 1) == false and GiftClock.isClaimed(m, 1))
check("after midnight resets", GiftClock.roll(m, 6 * DAY) == true and not GiftClock.isClaimed(m, 1))

-- claimed list is ordered
local o = GiftClock.sanitize(nil)
for _, i in { 3, 1, 2 } do
	GiftClock.markClaimed(o, i)
end
local l = GiftClock.claimedList(o)
check("ordered list", l[1] == 1 and l[2] == 2 and l[3] == 3)

print(("gift_clock: %d checks, %d failed"):format(total, fails))
if fails > 0 then
	error("gift_clock failed")
end
