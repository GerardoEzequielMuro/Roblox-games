--!strict
-- Session gifts persist per UTC day (leaving and rejoining must not re-arm them).
--   luau tests/playrewards_check.luau
local PlayRewards = require("../src/shared/PlayRewards")
local Config = require("../src/shared/Config")

local fails = 0
local function check(c: boolean, msg: string)
	if not c then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local D0 = 20000 * 86400
local gift = Config.Gifts[1]
local play = PlayRewards.sanitize(nil) -- old save without the field
PlayRewards.tick(play, D0 + 10, 0)
check(not PlayRewards.claim(play, 1, gift.minutes), "not ready at 0 s")
for i = 1, gift.minutes * 60 do
	PlayRewards.tick(play, D0 + 10 + i, 1)
end
check(PlayRewards.claim(play, 1, gift.minutes), "ready after the minutes")
-- rejoin the same day: the saved profile keeps the claim and the played time
local saved = PlayRewards.sanitize({ day = play.day, secs = play.secs, claimed = { ["1"] = true } })
PlayRewards.tick(saved, D0 + 5000, 0)
local ok, why = PlayRewards.claim(saved, 1, gift.minutes)
check(not ok and why == "claimed", "rejoin the same day cannot re-claim")
check(saved.secs == play.secs, "timer continues after the rejoin")
check(PlayRewards.claim(saved, 2, 0), "other gifts still claimable when ready")
-- a new UTC day resets timer and claims
PlayRewards.tick(saved, D0 + 86400 + 1, 1)
check(saved.secs == 1 and #PlayRewards.list(saved) == 0, "new day resets")
check(not PlayRewards.claim(saved, 1, gift.minutes), "new day: the timer must be earned again")
-- the server's story text math: client-side power gate numbers exist
check(Config.Techniques[1].reqPower == 2_000, "first technique power")

if fails > 0 then
	error("playrewards check FAILED")
end
print("PLAYREWARDS CHECKS PASSED")
