--!strict
-- Reward granting shared by every source (daily streak, codes, play-time gifts, Index rows, referrals, group gift,
-- Starter Pack), plus the daily/codes/gifts/Index actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local CropIndex = require(ReplicatedStorage.Shared.CropIndex)
local Odds = require(ReplicatedStorage.Shared.Odds)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Validate = require(script.Parent.Parent.Security.Validate)
local RateLimit = require(script.Parent.Parent.Security.RateLimit)

local Rewards = {}

-- ===== Lucky Seed Pack roll (also used by the Robux product and the Starter Pack) =====
-- The pool and the weights live in Shared/Odds: the client shows exactly the chances rolled here.
local rng = Random.new()

function Rewards.luckySeed(): string
	return Odds.rollLucky(rng:NextNumber())
end

-- Rolls n lucky seeds into the profile; returns the seed ids.
function Rewards.luckyPack(s: Session.S, n: number): { string }
	local ids = {}
	for _ = 1, n * Odds.LuckyPerPack do
		local id = Rewards.luckySeed()
		s.profile.seeds[id] = (s.profile.seeds[id] or 0) + 1
		table.insert(ids, id)
	end
	Session.markDirty(s)
	return ids
end

-- "N minutes of your recent earnings" with a floor.
function Rewards.cashMinutes(s: Session.S, minutes: number): number
	return Gifts.cashFor(minutes, math.max(Session.earnRate(s), s.bestRate), Config.GiftCashFloorPerMinute)
end

-- Grants a Config.Reward-shaped table. Returns a list arg ("$500 + 5x Tomato") that Locale renders in the
-- player's language.
function Rewards.grant(s: Session.S, reward: any): any
	local parts: { any } = {}
	local cash = (reward.cash or 0) + (if reward.cashMinutes then Rewards.cashMinutes(s, reward.cashMinutes) else 0)
	if cash > 0 then
		Session.addCash(s, cash)
		table.insert(parts, Format.cash(cash))
	end
	if reward.seeds then
		for id, n in reward.seeds do
			if Config.SeedById[id] then
				s.profile.seeds[id] = (s.profile.seeds[id] or 0) + n
				table.insert(parts, R("reward.seeds", { n = n, seed = Locale.seedName(id) }))
			end
		end
	end
	if reward.boost then
		local b = reward.boost
		Session.addBoost(s, b.kind, b.mult, b.seconds)
		table.insert(parts, R(if b.kind == "cash" then "reward.boostCash" else "reward.boostGrowth", { mult = b.mult, min = math.floor(b.seconds / 60) }))
	end
	if reward.luckyPack and reward.luckyPack > 0 then
		local names = {}
		for _, id in Rewards.luckyPack(s, reward.luckyPack) do
			table.insert(names, Locale.seedName(id))
		end
		table.insert(parts, R("msg.luckyPack", { seeds = { list = names } }))
	end
	Session.markDirty(s)
	return { list = parts, sep = " + " }
end

-- ===== Daily streak =====
Remotes.handle("ClaimDaily", function(player)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	local info = Session.dailyInfo(s)
	if not info.canClaim then
		return false, R("err.comeBackIn", { time = Format.time(info.nextAt - os.time()) })
	end
	local streak = info.streak % #Config.DailyRewards + 1
	s.profile.daily.streak = streak
	s.profile.daily.lastClaim = os.time()
	local text = Rewards.grant(s, Config.DailyRewards[streak] :: any)
	return true, R("msg.dailyReward", { day = streak, reward = text })
end)

-- ===== Codes =====
-- Wrong guesses are limited per player (brute-forcing the code list): 6 misses in a minute lock redeeming for 2.
local codeStrikes: { [Player]: RateLimit.Strikes } = {}
function Rewards.forget(player: Player)
	codeStrikes[player] = nil
end

Remotes.handle("RedeemCode", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	local st = codeStrikes[player]
	if not st then
		st = RateLimit.newStrikes()
		codeStrikes[player] = st
	end
	local now = os.clock()
	if RateLimit.locked(st, now) then
		return false, R("err.slowDown")
	end
	local code = Validate.code(payload.code)
	local reward = if code then (Config.Codes :: any)[code] else nil
	if not reward or not code then
		RateLimit.strike(st, now, 6, 60, 120)
		return false, R("err.invalidCode")
	end
	if s.profile.codes[code] then
		return false, R("err.codeUsed")
	end
	s.profile.codes[code] = true
	return true, R("msg.codeRedeemed", { reward = Rewards.grant(s, reward) })
end)

-- ===== Session play-time gifts =====
Remotes.handle("ClaimGift", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	local index = Validate.integer(payload.index, 1, #Config.PlaytimeGifts)
	local ok, why = Gifts.canClaim(Config.PlaytimeGifts, index, s.sessionStart, os.time(), s.giftsClaimed)
	if not ok or not index then
		return false, R(if why == "early" then "err.giftEarly" elseif why == "claimed" then "err.giftClaimed" else "err.badRequest")
	end
	s.giftsClaimed[index] = true
	local text = Rewards.grant(s, Config.PlaytimeGifts[index])
	return true, R("msg.giftClaimed", { reward = text })
end)

-- ===== Crop x mutation Index =====
Remotes.handle("ClaimIndex", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	local seedKey = Validate.key(payload.seedId, Config.SeedById)
	local seed = if seedKey then Config.SeedById[seedKey] else nil
	if not seed then
		return false, R("err.unknownSeed")
	end
	if s.profile.indexClaimed[seed.id] then
		return false, R("err.giftClaimed")
	end
	if not CropIndex.rowComplete(s.profile.index[seed.id], Session.MUTATION_IDS) then
		return false, R("err.indexIncomplete")
	end
	s.profile.indexClaimed[seed.id] = true
	local cash = CropIndex.rowCash(seed.sellValue, Config.IndexRowCashMult)
	Session.addCash(s, cash)
	return true, R("msg.indexClaimed", { seed = Locale.seedName(seed.id), cash = Format.cash(cash), pct = math.floor(Config.IndexRowBonus * 100) })
end)

-- Records a harvested variant; returns true the first time it's found.
function Rewards.recordIndex(s: Session.S, seedId: string, mutation: string?): boolean
	local row = s.profile.index[seedId]
	if not row then
		row = {}
		s.profile.index[seedId] = row
	end
	local variant = mutation or CropIndex.NORMAL
	if row[variant] then
		return false
	end
	row[variant] = true
	Session.markDirty(s)
	local name = if mutation
		then R("index.variant", { mutation = R("mutation." .. mutation), seed = Locale.seedName(seedId) })
		else Locale.seedName(seedId)
	Remotes.notify(s.player, R("msg.indexNew", { name = name }), "rare")
	return true
end

return Rewards
