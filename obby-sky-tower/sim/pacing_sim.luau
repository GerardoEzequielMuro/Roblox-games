--!nocheck
-- Pacing simulator for Sky Tower Obby. Pure Luau (no Roblox APIs). From the project root:
--   export PATH=/tmp/tools:$PATH; luau sim/pacing_sim.luau -a [seeds] [days]   (default 41 14)
-- Prints the difficulty curve by stage band (analytic expected seconds per stage), the milestone
-- timeline of a free player (median over `seeds` simulated players) and the day-by-day progress.
local M = require("./pacing_model")
local Layout = M.Layout
local args = { ... }
local SEEDS = tonumber(args[1]) or 41
local DAYS = tonumber(args[2]) or 14

local function fmt(sec: number): string
	if sec ~= sec or sec == math.huge then
		return "--"
	end
	local s = math.floor(sec + 0.5)
	if s >= 3600 then
		return ("%dh%02dm"):format(s // 3600, (s % 3600) // 60)
	end
	return ("%d:%02d"):format(s // 60, s % 60)
end

print("== Difficulty curve: expected seconds per stage (analytic, median-skill player) ==")
local curve = M.curve()
print("world  stages        avg s/stage   max s/stage   avg tries   kinds")
for w = 1, 100 do
	local a, b = (w - 1) * 10 + 1, w * 10
	local sum, mx, tries = 0, 0, 0
	for g = a, b do
		sum += curve[g]
		mx = math.max(mx, curve[g])
		local _, t = M.expected(g, M.skill(g - 1), M.hesitation(g - 1))
		tries += t
	end
	if w <= 12 or w % 5 == 0 then
		local kinds = {}
		for g = a, b do
			table.insert(kinds, M.stages()[g].kind:sub(1, 3))
		end
		print(("%3d    %4d-%4d     %6.1f        %6.1f       %5.2f      %s"):format(w, a, b, sum / 10, mx, tries / 10, table.concat(kinds, " ")))
	end
end

local summary, runs = M.summary(SEEDS, DAYS)
print(("\n== Free player timeline (median of %d simulated players, active play time) =="):format(SEEDS))
print(("first coin / reward            %s"):format(fmt(summary.firstReward)))
print(("first play-time gift (claim)  %s"):format(fmt(summary.firstPlaytimeGift)))
print(("stage 1 (first checkpoint)    %s"):format(fmt(summary.stageAt[1])))
print(("first purchase                %s"):format(fmt(summary.firstPurchase)))
print(("3rd purchase                  %s"):format(fmt(summary.thirdPurchase)))
print(("purchases in the first hour   %d"):format(summary.purchasesFirstHour))
print(("longest stretch w/o anything new in the first hour: %s"):format(fmt(summary.maxDeadStretch)))
print("\nworld entrances / summits")
for g = 10, Layout.TOTAL, 10 do
	if g <= 100 or g % 100 == 0 then
		print(("  stage %4d%s  %s"):format(g, if g % 100 == 0 then " (summit)" else "          ", fmt(summary.stageAt[g])))
	end
end
print("\nday-by-day (session 60 min on day 1, 30 min after): stage at the end of the day")
local row = {}
for d = 1, DAYS do
	table.insert(row, ("d%d:%d"):format(d, summary.dayStage[d]))
end
print("  " .. table.concat(row, "  "))

-- one typical run: first purchases and stuck events
local r = runs[math.ceil(#runs / 2)]
print("\nfirst purchases of a typical player:")
for i, p in r.purchases do
	if i <= 8 then
		print(("  %s  %s (%d coins)"):format(fmt(p.t), p.id, p.price))
	end
end
print(("skips used: %d (paid %d), deaths: %d, coins earned %d / spent %d"):format(r.skipsUsed, r.paidSkips, r.deaths, r.coinsEarned, r.coinsSpent))
