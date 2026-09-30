--!strict
-- Battle pass maths (pure): which season is live, tiers from XP, what can be claimed. The
-- server stores one record per season: { xp, premium, free = {["3"]=true}, paid = {...} }.
local Config: any = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local BattlePass = {}

export type Record = { xp: number, premium: boolean, free: { [string]: boolean }, paid: { [string]: boolean } }

function BattlePass.newRecord(): Record
	return { xp = 0, premium = false, free = {}, paid = {} }
end

-- The season running at `now` (nil before the first / after the last one), and the next one.
function BattlePass.active(now: number): (any?, any?)
	local nextSeason = nil
	for _, season in Config.BattlePass.seasons do
		if now >= season.startsAt and now < season.endsAt then
			return season, nil
		end
		if season.startsAt > now and (nextSeason == nil or season.startsAt < nextSeason.startsAt) then
			nextSeason = season
		end
	end
	return nil, nextSeason
end

function BattlePass.tier(xp: number): number
	return math.clamp(math.floor(xp / Config.BattlePass.xpPerTier), 0, Config.BattlePass.tiers)
end

-- XP still missing for the next tier (0 when maxed) and the fraction inside the current tier.
function BattlePass.progress(xp: number): (number, number)
	local per = Config.BattlePass.xpPerTier
	if BattlePass.tier(xp) >= Config.BattlePass.tiers then
		return 0, 1
	end
	local inside = xp % per
	return per - inside, inside / per
end

function BattlePass.addXp(rec: Record, amount: number): number
	if amount ~= amount or amount <= 0 then
		return rec.xp
	end
	local cap = Config.BattlePass.xpPerTier * Config.BattlePass.tiers
	rec.xp = math.min(cap, rec.xp + math.floor(amount))
	return rec.xp
end

function BattlePass.reward(seasonId: string, track: string, tier: number): any?
	local r = Config.BattlePass.rewards[seasonId]
	return r and r[track][tier]
end

-- Can this tier of this track be claimed right now? Returns ok, reason.
function BattlePass.canClaim(rec: Record, seasonId: string, track: string, tier: number): (boolean, string?)
	if track ~= "free" and track ~= "premium" then
		return false, "bad"
	end
	if type(tier) ~= "number" or tier % 1 ~= 0 or tier < 1 or tier > Config.BattlePass.tiers then
		return false, "bad"
	end
	if BattlePass.tier(rec.xp) < tier then
		return false, "locked"
	end
	if track == "premium" and not rec.premium then
		return false, "premium"
	end
	local claimed = if track == "free" then rec.free else rec.paid
	if claimed[tostring(tier)] then
		return false, "claimed"
	end
	return true, nil
end

function BattlePass.markClaimed(rec: Record, track: string, tier: number)
	local claimed = if track == "free" then rec.free else rec.paid
	claimed[tostring(tier)] = true
end

-- Number of rewards waiting (for the menu badge).
function BattlePass.claimableCount(rec: Record, seasonId: string): number
	local n = 0
	for tier = 1, BattlePass.tier(rec.xp) do
		if BattlePass.canClaim(rec, seasonId, "free", tier) then
			n += 1
		end
		if BattlePass.canClaim(rec, seasonId, "premium", tier) then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Round 6: free pass XP for coming back (weekly challenges, daily first win) and the
-- catch-up multiplier. All pure; the server stores `Weekly` in the profile.
---------------------------------------------------------------------------
export type Weekly = { week: number, lastDay: number, prog: { [string]: number }, done: { [string]: boolean } }

function BattlePass.dayIndex(now: number): number
	return now // 86400
end

function BattlePass.weekIndex(now: number): number
	return math.floor((now - Config.BattlePass.seasons[1].startsAt) / Config.BattlePass.weekSeconds)
end

-- Seconds until the next weekly reset.
function BattlePass.weekResetIn(now: number): number
	local w = BattlePass.weekIndex(now) + 1
	return Config.BattlePass.seasons[1].startsAt + w * Config.BattlePass.weekSeconds - now
end

function BattlePass.newWeekly(week: number): Weekly
	return { week = week, lastDay = -1, prog = {}, done = {} }
end

-- The record of the current week: a stale one is replaced by a fresh one (progress is lost on purpose).
function BattlePass.rollWeekly(w: Weekly?, now: number): Weekly
	local week = BattlePass.weekIndex(now)
	if w == nil or w.week ~= week then
		return BattlePass.newWeekly(week)
	end
	return w
end

local function challenge(id: string): any?
	for _, c in Config.BattlePass.weekly do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- Adds progress to a challenge. Returns the XP to award when this call completes it (else nil).
function BattlePass.weeklyAdd(w: Weekly, id: string, n: number): number?
	local c = challenge(id)
	if not c or w.done[id] or n <= 0 then
		return nil
	end
	w.prog[id] = math.min(c.target, (w.prog[id] or 0) + n)
	if w.prog[id] >= c.target then
		w.done[id] = true
		return c.xp
	end
	return nil
end

-- "Play on N different days": counts a day once, however many times it is touched.
function BattlePass.weeklyTouchDay(w: Weekly, today: number): number?
	if w.lastDay == today then
		return nil
	end
	w.lastDay = today
	return BattlePass.weeklyAdd(w, "days", 1)
end

-- Tier a steady player would have now: tier `tiers` after paceFrac of the season.
function BattlePass.expectedTier(season: any, now: number): number
	local cu = Config.BattlePass.catchUp
	local span = season.days * 86400 * cu.paceFrac
	return math.clamp(math.floor(Config.BattlePass.tiers * (now - season.startsAt) / span), 0, Config.BattlePass.tiers)
end

-- XP multiplier while behind the expected tier (1 when on pace or ahead).
function BattlePass.catchUpMult(xp: number, season: any, now: number): number
	local cu = Config.BattlePass.catchUp
	local behind = BattlePass.expectedTier(season, now) - BattlePass.tier(xp)
	if BattlePass.tier(xp) >= Config.BattlePass.tiers then
		return 1
	elseif behind >= cu.deepGap then
		return cu.deepMult
	elseif behind >= cu.grace then
		return cu.mult
	end
	return 1
end

function BattlePass.boosted(amount: number, mult: number): number
	return math.max(1, math.floor(amount * mult + 0.5))
end

return BattlePass
