-- Battle pass maths (Shared/BattlePass) and the reward tables. Pure.
local BattlePass = require("../src/shared/BattlePass")
local Config = require("../src/shared/Config")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

local B = Config.BattlePass
local s1, s2 = B.SeasonById.s1, B.SeasonById.s2

-- clock -------------------------------------------------------------------------------
check("s1 starts 2026-10-01 00:00 UTC", s1.startsAt == 1790812800, s1.startsAt)
check("s1 lasts 8 weeks", s1.endsAt - s1.startsAt == 56 * 86400)
check("s2 follows s1 exactly", s2.startsAt == s1.endsAt)
local before, upcoming = BattlePass.active(s1.startsAt - 1)
check("before s1: none, s1 is next", before == nil and upcoming ~= nil and upcoming.id == "s1")
check("at s1 start: s1", (BattlePass.active(s1.startsAt)).id == "s1")
check("last second of s1", (BattlePass.active(s1.endsAt - 1)).id == "s1")
check("at s1 end: s2", (BattlePass.active(s1.endsAt)).id == "s2")
local after, nextAfter = BattlePass.active(s2.endsAt)
check("after s2: nothing, nothing next", after == nil and nextAfter == nil)

-- tiers / xp --------------------------------------------------------------------------
local per = B.xpPerTier
check("tier 0", BattlePass.tier(0) == 0 and BattlePass.tier(per - 1) == 0)
check("tier 1", BattlePass.tier(per) == 1)
check("tier cap", BattlePass.tier(per * B.tiers * 5) == B.tiers)
local missing, frac = BattlePass.progress(per + 30)
check("progress missing", missing == per - 30, missing)
check("progress frac", math.abs(frac - 30 / per) < 1e-9, frac)
check("maxed progress", select(1, BattlePass.progress(per * B.tiers)) == 0 and select(2, BattlePass.progress(per * B.tiers)) == 1)
local rec = BattlePass.newRecord()
BattlePass.addXp(rec, 10)
check("addXp", rec.xp == 10)
BattlePass.addXp(rec, -5)
BattlePass.addXp(rec, 0 / 0)
check("addXp ignores bad numbers", rec.xp == 10)
BattlePass.addXp(rec, 1e9)
check("addXp caps at the last tier", rec.xp == per * B.tiers, rec.xp)

-- claiming ----------------------------------------------------------------------------
local r = BattlePass.newRecord()
r.xp = per * 3
check("free tier 3 claimable", select(1, BattlePass.canClaim(r, "s1", "free", 3)))
check("free tier 4 locked", select(2, BattlePass.canClaim(r, "s1", "free", 4)) == "locked")
check("premium needs the pass", select(2, BattlePass.canClaim(r, "s1", "premium", 1)) == "premium")
r.premium = true
check("premium claimable once bought", select(1, BattlePass.canClaim(r, "s1", "premium", 1)))
check("bad track", select(2, BattlePass.canClaim(r, "s1", "gold", 1)) == "bad")
check("bad tier", select(2, BattlePass.canClaim(r, "s1", "free", 0)) == "bad" and select(2, BattlePass.canClaim(r, "s1", "free", 1.5)) == "bad" and select(2, BattlePass.canClaim(r, "s1", "free", B.tiers + 1)) == "bad")
check("claimable count", BattlePass.claimableCount(r, "s1") == 6, BattlePass.claimableCount(r, "s1"))
BattlePass.markClaimed(r, "free", 2)
check("claimed twice refused", select(2, BattlePass.canClaim(r, "s1", "free", 2)) == "claimed")
check("claimed one less waiting", BattlePass.claimableCount(r, "s1") == 5)
check("premium claim is independent", select(1, BattlePass.canClaim(r, "s1", "premium", 2)))

-- reward tables -----------------------------------------------------------------------
local kinds = { sparks = true, gems = true, boost = true, spins = true, seed = true, skin = true, mount = true, aura = true }
for _, season in B.seasons do
	for _, track in { "free", "premium" } do
		for t = 1, B.tiers do
			local rw = B.rewards[season.id][track][t]
			check(season.id .. " " .. track .. " tier " .. t .. " exists", rw ~= nil)
			if rw then
				check("reward kind valid " .. season.id .. track .. t, kinds[rw.kind] == true, rw.kind)
				if rw.kind == "seed" then
					check("seed reward item exists", Config.SeedById[rw.item] ~= nil, rw.item)
				elseif rw.kind == "skin" then
					check("skin reward exists", Config.SkinById[rw.id] ~= nil, rw.id)
				elseif rw.kind == "mount" then
					check("mount reward exists", Config.MountById[rw.id] ~= nil, rw.id)
				elseif rw.kind == "aura" then
					check("aura reward exists", Config.AuraById[rw.id] ~= nil, rw.id)
				else
					check("reward amount positive", rw.amount > 0)
				end
			end
		end
	end
	check(season.id .. " premium ends with its skin", B.rewards[season.id].premium[B.tiers].kind == "skin")
	check(season.id .. " free track also ends with a cosmetic", B.rewards[season.id].free[B.tiers].kind == "aura" or B.rewards[season.id].free[B.tiers].kind == "mount")
	check(season.id .. " theme arc exists", Config.PlanetById ~= nil and season.arc >= 1)
end
check("s1 is the pink-demon arc (8), s2 the gods arc (9)", s1.arc == 8 and s2.arc == 9)

-- a player who does 3 daily quests + the bonus and plays 1 hour a day finishes the free pass
local perDay = B.xp.questClaim * 3 + B.xp.questBonus + B.xp.minutes * 12
check("1 h/day finishes all 30 tiers inside a season", perDay * s1.days >= B.xpPerTier * B.tiers, perDay * s1.days .. " vs " .. B.xpPerTier * B.tiers)
check("but not in a week (it is a season goal)", perDay * 7 < B.xpPerTier * B.tiers)

-- the free track alone never requires paying
local freeGems = 0
for t = 1, B.tiers do
	local rw = B.rewards.s1.free[t]
	if rw.kind == "gems" then
		freeGems += rw.amount
	end
end
check("free track has gems too", freeGems >= 30, freeGems)

-- Round 6: weekly challenges, first win and the catch-up multiplier ---------------------
local t0 = s1.startsAt
check("week index starts at 0 on the first season start", BattlePass.weekIndex(t0) == 0 and BattlePass.weekIndex(t0 + 7 * 86400 - 1) == 0 and BattlePass.weekIndex(t0 + 7 * 86400) == 1)
check("weeks before the first season are negative", BattlePass.weekIndex(t0 - 1) == -1)
check("week reset countdown", BattlePass.weekResetIn(t0 + 86400) == 6 * 86400 and BattlePass.weekResetIn(t0) == 7 * 86400)
local w = BattlePass.rollWeekly(nil, t0 + 10)
check("fresh weekly record", w.week == 0 and next(w.prog) == nil)
check("same week keeps the record", BattlePass.rollWeekly(w, t0 + 3 * 86400) == w)
check("new week replaces the record", BattlePass.rollWeekly(w, t0 + 8 * 86400) ~= w)
for _, c in B.weekly do
	check("challenge has target and xp " .. c.id, c.target > 0 and c.xp > 0)
end
local wk = BattlePass.newWeekly(0)
check("bosses: progress is not a completion", BattlePass.weeklyAdd(wk, "bosses", 1) == nil and wk.prog.bosses == 1)
check("bosses: completes once", BattlePass.weeklyAdd(wk, "bosses", 1) == 20 and wk.done.bosses == true)
check("bosses: no double pay", BattlePass.weeklyAdd(wk, "bosses", 5) == nil)
check("unknown challenge ignored", BattlePass.weeklyAdd(wk, "nope", 1) == nil)
check("days: same day counts once", BattlePass.weeklyTouchDay(wk, 100) == nil and BattlePass.weeklyTouchDay(wk, 100) == nil and wk.prog.days == 1)
check("days: third different day completes", BattlePass.weeklyTouchDay(wk, 101) == nil and BattlePass.weeklyTouchDay(wk, 102) == 20)
local perWeek = 0
for _, c in B.weekly do
	perWeek += c.xp
end
check("weekly XP is small next to the pass (under 1 tier a week, under 25% of a season)", perWeek <= B.xpPerTier and perWeek * 8 <= B.xpPerTier * B.tiers * 0.25, perWeek)
check("first win XP is small", B.firstWinXp > 0 and B.firstWinXp <= 10)

local dayN = function(d: number): number
	return s1.startsAt + d * 86400 + 12 * 3600
end
check("expected tier is 0 at the start", BattlePass.expectedTier(s1, s1.startsAt) == 0)
check("expected tier reaches the top at paceFrac of the season", BattlePass.expectedTier(s1, s1.startsAt + s1.days * 86400 * B.catchUp.paceFrac) == B.tiers)
check("expected tier never above the cap", BattlePass.expectedTier(s1, s1.endsAt) == B.tiers)
check("on pace: no multiplier", BattlePass.catchUpMult(per * 7, s1, dayN(10)) == 1)
check("ahead: no multiplier", BattlePass.catchUpMult(per * 25, s1, dayN(10)) == 1)
local exp20 = BattlePass.expectedTier(s1, dayN(20))
check("a little behind (grace): no multiplier", BattlePass.catchUpMult(per * (exp20 - B.catchUp.grace + 1), s1, dayN(20)) == 1)
check("behind: x" .. B.catchUp.mult, BattlePass.catchUpMult(per * (exp20 - B.catchUp.grace), s1, dayN(20)) == B.catchUp.mult)
check("far behind: x" .. B.catchUp.deepMult, BattlePass.catchUpMult(0, s1, dayN(40)) == B.catchUp.deepMult)
check("maxed pass: no multiplier", BattlePass.catchUpMult(per * B.tiers, s1, dayN(50)) == 1)
check("boosted rounds and never loses XP", BattlePass.boosted(10, 1.5) == 15 and BattlePass.boosted(1, 1.5) == 2 and BattlePass.boosted(1, 1) == 1)
check("multipliers are sane (1 < mult <= deepMult <= 2.5)", B.catchUp.mult > 1 and B.catchUp.mult <= B.catchUp.deepMult and B.catchUp.deepMult <= 2.5)

if fails == 0 then
	print(string.format("BATTLE PASS CHECKS PASSED (%d tiers x %d seasons, %d XP/tier)", B.tiers, #B.seasons, B.xpPerTier))
else
	error(fails .. " battle pass check(s) failed")
end
