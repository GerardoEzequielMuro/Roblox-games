--!nocheck
-- Pacing guard for Sky Tower Obby (pure Luau). Run from the project root:
--   luau tests/pacing_test.luau
-- Runs the simulator of sim/pacing_model.luau (REAL Layout / Rules / Gifts / Powerups / Economy)
-- and FAILS when a key milestone drifts out of its target window, or the difficulty curve grows a
-- spike. Targets (obby version of "first reward < 10 s, first upgrade < 60 s, a new tier every
-- 5-15 min, first prestige 30-60 min"): see docs/handoff/obby-sky-tower.md, "Ronda 5".
local M = require("../sim/pacing_model")
local Layout = M.Layout
local Economy = M.Economy

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end
local function mmss(s: number): string
	return ("%d:%02d"):format(s // 60, s % 60)
end
local function within(name: string, v: number, lo: number, hi: number)
	check(v >= lo and v <= hi, ("%s = %s, expected %s .. %s"):format(name, mmss(v), mmss(lo), mmss(hi)))
end

-- Milestones of the free player (median of 21 simulated players, 14 days) ------------------------
local S = M.summary(21, 14)
within("first coin / reward", S.firstReward, 0, 10)
within("first play-time gift", S.firstPlaytimeGift, 0, 90)
within("stage 1 (first checkpoint)", S.stageAt[1], 0, 40)
within("first purchase", S.firstPurchase, 0, 60)
within("3rd purchase", S.thirdPurchase, 0, 330) -- obby spends on cosmetics only: ~5 min
check(S.purchasesFirstHour >= 6, ("purchases in the first hour = %d, expected >= 6"):format(S.purchasesFirstHour))
within("longest stretch without anything new (first hour)", S.maxDeadStretch, 0, 600)
within("world 2 entrance (stage 10)", S.stageAt[10], 90, 360) -- the tutorial world: quick wins
-- a new world every 1.5-12 min across tower 1 (first ~hour)
local prev = 0
for g = 10, 100, 10 do
	local dt = S.stageAt[g] - prev
	within(("time to cross the world ending at stage %d"):format(g), dt, 90, 720)
	prev = S.stageAt[g]
end
within("first summit (stage 100, first win)", S.stageAt[100], 30 * 60, 60 * 60)
-- session 2+: hours of goals left (tower 10 is far), nothing trivially finished
check(S.dayStage[1] < 300, ("day 1 (60 min) already reached stage %d"):format(S.dayStage[1]))
check(S.dayStage[14] < Layout.TOTAL, "a 30 min/day player finished all 1000 stages in two weeks")
check(S.dayStage[7] > S.dayStage[1] + 100, "a week of 30 min sessions should add well over 100 stages")
within("tower 2 summit (stage 200)", S.stageAt[200], 60 * 60, 150 * 60)
within("tower 5 summit (stage 500)", S.stageAt[500], 3 * 3600, 8 * 3600)

-- Difficulty curve (analytic expected seconds per stage, median-skill player) -------------------
local curve = M.curve()
local function band(a: number, b: number): number
	local s = 0
	for g = a, b do
		s += curve[g]
	end
	return s / (b - a + 1)
end
for g = 1, 10 do
	check(curve[g] <= 30, ("stage %d takes %.0f s in expectation (first 10 stages must be quick wins, <= 30 s)"):format(g, curve[g]))
end
check(band(1, 10) <= 25, "world 1 averages more than 25 s per stage")
for w = 2, 10 do
	local a, b = (w - 1) * 10 + 1, w * 10
	local ratio = band(a, b) / band(a - 10, a - 1)
	check(ratio <= 1.7, ("world %d is %.2fx harder than world %d (ramp must be smooth, <= 1.7x)"):format(w, ratio, w - 1))
	check(ratio >= 0.6, ("world %d is %.2fx of world %d (an easy dip of more than 40%%)"):format(w, ratio, w - 1))
end
for g = 1, Layout.STAGES do
	check(curve[g] <= 150, ("stage %d of tower 1 takes %.0f s in expectation (spike, must be <= 150 s; it used to reach 196 s)"):format(g, curve[g]))
end
local worst = 0
for g = 1, Layout.TOTAL do
	worst = math.max(worst, curve[g])
end
check(worst <= 350, ("hardest stage of the game takes %.0f s in expectation (<= 350 s; it used to reach 560 s)"):format(worst))
-- towers: the average stage never gets easier by more than 40% nor harder by more than 2x
local towerAvg = {}
for t = 1, Layout.TOWERS do
	towerAvg[t] = band((t - 1) * 100 + 1, t * 100)
	if t > 1 then
		local r = towerAvg[t] / towerAvg[t - 1]
		check(r <= 2 and r >= 0.6, ("tower %d averages %.2fx of tower %d"):format(t, r, t - 1))
	end
end
-- NOT easier than the original layout (owner: the parkour was too easy). Original averages of
-- the expected s/stage: worlds 7-10 of tower 1 = 47.2; towers 4-10 = 68-103 (inflated by 500 s outliers)
check((band(61, 70) + band(71, 80) + band(81, 90) + band(91, 100)) / 4 >= 44, "worlds 7-10 average under 44 s per stage (original: 47 s)")
check(towerAvg[1] >= 29, "tower 1 average under 29 s per stage (original: 29.8)")
for t = 4, 10 do
	check(towerAvg[t] >= 60, ("tower %d averages %.0f s per stage, under 60 (original median-stage difficulty)"):format(t, towerAvg[t]))
end
check(towerAvg[10] > 2 * towerAvg[1], "tower 10 should be clearly harder than tower 1")
local totalHours = 0
for g = 1, Layout.TOTAL do
	totalHours += curve[g] / 3600
end
check(totalHours >= 8 and totalHours <= 30, ("all 1000 stages take %.1f h in expectation (8 .. 30 h)"):format(totalHours))

-- Economy ladder: no price wall in the cosmetics shop -----------------------------------------------
local prices = {}
for _, it in M.catalog() do
	table.insert(prices, it.price)
end
check(prices[1] <= 25, "the cheapest cosmetic must be reachable in the first minute (<= 25 coins)")
for i = 2, #prices do
	check(prices[i] <= prices[i - 1] * 3, ("price wall: %d coins after %d"):format(prices[i], prices[i - 1]))
end
check(Economy.PlaytimeRewards[1].minutes <= 1, "the first play-time gift must open inside the first minute")

print(("pacing_test: %d checks, %d failures"):format(checks, failures))
print(("  first reward %s, first purchase %s, 3rd purchase %s, stage 10 %s, summit 1 %s"):format(mmss(S.firstReward), mmss(S.firstPurchase), mmss(S.thirdPurchase), mmss(S.stageAt[10]), mmss(S.stageAt[100])))
if failures > 0 then
	error("pacing test FAILED")
end
print("pacing test PASSED")
