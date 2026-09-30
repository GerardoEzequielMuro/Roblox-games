--!strict
-- Account progression maths (pure; unit-tested with luau.exe): levels, leagues, seasons and
-- what a finished match pays. Rewards depend on placement only. Nothing is staked, and
-- trophies never go down: a player who loses keeps everything they had before sitting down.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Progression = {}

function Progression.xpForLevel(level: number): number
	return 100 + 40 * (level - 1)
end

-- Applies xp to (level, xp). Returns the new level, the leftover xp and levels gained.
function Progression.addXp(level: number, xp: number, gain: number): (number, number, number)
	local gained = 0
	xp += math.max(0, math.floor(gain))
	while level < Config.MaxLevel and xp >= Progression.xpForLevel(level) do
		xp -= Progression.xpForLevel(level)
		level += 1
		gained += 1
	end
	if level >= Config.MaxLevel then
		xp = math.min(xp, Progression.xpForLevel(level))
	end
	return level, xp, gained
end

function Progression.levelUpCoins(level: number): number
	return Config.LevelCoins + 10 * level
end

function Progression.league(trophies: number): (typeof(Config.Leagues[1]), number)
	local best, index = Config.Leagues[1], 1
	for i, l in Config.Leagues do
		if trophies >= l.trophies then
			best, index = l, i
		end
	end
	return best, index
end

function Progression.nextLeague(trophies: number): typeof(Config.Leagues[1])?
	local _, i = Progression.league(trophies)
	return Config.Leagues[i + 1]
end

-- Seasons are calendar months (UTC). Id = year * 12 + month - 1.
function Progression.season(now: number): number
	local d = os.date("!*t", now) :: any
	return d.year * 12 + d.month - 1
end

-- Unix time of 00:00 UTC on a civil date (os.time(table) is local time outside Roblox).
local function utc(y: number, mo: number, d: number): number
	y = if mo <= 2 then y - 1 else y
	local era = y // 400
	local yoe = y - era * 400
	local doy = (153 * (mo + (if mo > 2 then -3 else 9)) + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return (era * 146097 + doe - 719468) * 86400
end
Progression.utc = utc

function Progression.seasonEndsAt(now: number): number
	local d = os.date("!*t", now) :: any
	local y, mo = d.year, d.month + 1
	if mo > 12 then
		y, mo = y + 1, 1
	end
	return utc(y, mo, 1)
end

-- New season: keep half of the trophies (rounded down to the league floor at most).
function Progression.seasonCarry(trophies: number): number
	return math.floor(trophies / 2)
end

-- Coins paid at the end of a season for the league reached.
function Progression.seasonReward(trophies: number): number
	local _, i = Progression.league(trophies)
	return (i - 1) * 300
end

export type MatchResult = { coins: number, xp: number, trophies: number }
export type Mults = { coin: number?, xp: number?, streak: number?, humans: number? }

-- place: 1 = winner. n: players at the start. Teams and duels pay win/lose.
function Progression.matchRewards(modeId: string, place: number, n: number, mults: Mults?): MatchResult
	local mode = Config.ModeById[modeId]
	local won = place == 1
	local coins, xp, trophies
	if mode and (mode.teams or mode.maxPlayers == 2) then
		coins = if won then 80 else 30
		xp = if won then 80 else 35
		trophies = if won then 18 else 3
	else
		coins = 20 + 10 * (n - place) + (if won then 50 else 0)
		xp = 30 + 8 * (n - place) + (if won then 40 else 0)
		trophies = if won then 14 + 2 * n elseif place <= math.ceil(n / 2) then 2 + 2 * (math.ceil(n / 2) - place + 1) else 1
	end
	local mu: Mults = mults or {}
	local streak = math.min(Config.StreakBonusCap, math.max(0, mu.streak or 0))
	coins = math.floor(coins * (mu.coin or 1) * (1 + Config.StreakBonus * streak) + 0.5)
	xp = math.floor(xp * (mu.xp or 1) + 0.5)
	-- a table of bots is practice: half the trophies
	if (mu.humans or 2) <= 1 then
		trophies = math.ceil(trophies / 2)
	end
	return { coins = coins, xp = xp, trophies = trophies }
end

-- Does the player meet an unlock rule? (coins items are bought, not auto-unlocked)
export type UnlockCtx = { level: number, wins: number, bestStreak: number, bestTrophies: number, passes: { [string]: boolean } }
function Progression.unlocked(unlock: { type: string, n: number?, key: string? }, ctx: UnlockCtx): boolean
	local t = unlock.type
	if t == "default" then
		return true
	elseif t == "level" then
		return ctx.level >= (unlock.n or 0)
	elseif t == "wins" then
		return ctx.wins >= (unlock.n or 0)
	elseif t == "streak" then
		return ctx.bestStreak >= (unlock.n or 0)
	elseif t == "league" then
		for _, l in Config.Leagues do
			if l.id == unlock.key then
				return ctx.bestTrophies >= l.trophies
			end
		end
		return false
	elseif t == "pass" then
		return ctx.passes[unlock.key or ""] == true
	end
	return false -- coins / code / starter / daily / event: granted explicitly
end

return Progression
