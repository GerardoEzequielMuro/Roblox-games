--!strict
-- Retention: daily streak, codes, free in-session gifts, index (collection) rewards and
-- the friend boost. Rewards.grant is also used by Monetization for developer products.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Guard = require(script.Parent.Guard)
local Eggs = require(script.Parent.Eggs)

local Rewards = {}

type Reward = { kind: string, amount: number, label: string? }

-- Applies a reward and returns a short description of what was given.
function Rewards.grant(player: Player, reward: { kind: string, amount: number, label: string? }): Locale.Message
	local p = Data.get(player)
	if not p then
		return M("msg.error")
	end
	if reward.kind == "taps" then
		local amount = Formulas.tapsForMinutes(reward.amount, State.tapValue(player, p))
		State.addTaps(player, amount, false)
		Remotes.fire("Reward", player, { kind = "taps", amount = amount })
		return M("reward.taps", { n = Format.abbrev(amount) })
	elseif reward.kind == "gems" then
		State.addGems(player, reward.amount)
		Remotes.fire("Reward", player, { kind = "gems", amount = reward.amount })
		return M("reward.gems", { n = reward.amount })
	elseif reward.kind == "luck" then
		p.luckBoostLeft += reward.amount * 60
		State.dirty(player)
		Remotes.fire("Reward", player, { kind = "luck", amount = reward.amount })
		return M("reward.luck", { n = reward.amount })
	elseif reward.kind == "egg" then
		Eggs.hatchExclusive(player, reward.amount)
		return if reward.amount > 1 then M("reward.eggs", { n = reward.amount }) else M("reward.egg1")
	end
	return M("msg.error")
end

-- Every non-secret, non-exclusive pet that belongs to a zone's index page.
function Rewards.zonePets(zone: number): { string }
	local list = {}
	for _, pet in Config.Pets do
		if pet.zone == zone then
			table.insert(list, pet.id)
		end
	end
	return list
end

-- Friendship is looked up once per pair (web call) and cached for the server's lifetime.
local friendCache: { [string]: boolean } = {}
local friendCount = 0
local function areFriends(a: Player, b: Player): boolean
	local lo, hi = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = lo .. ":" .. hi
	local cached = friendCache[key]
	friendCount += if cached == nil then 1 else 0
	if friendCount > 3000 then
		table.clear(friendCache) -- bounded: pairs of everyone who ever shared this server
		friendCount = 0
	end
	if cached ~= nil then
		return cached
	end
	local ok, isFriend = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	if not ok then
		return false -- retry next refresh
	end
	friendCache[key] = isFriend == true
	return isFriend == true
end

local function countFriends(player: Player): number
	local n = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and areFriends(player, other) then
			n += 1
		end
	end
	return n
end

function Rewards.refreshFriends()
	for _, player in Players:GetPlayers() do
		if State.ready[player] then
			local n = countFriends(player)
			if n ~= State.friends[player] then
				State.friends[player] = n
				State.dirty(player)
			end
		end
	end
end

function Rewards.init()
	Remotes.handle("ClaimDaily", function(player)
		local p = Data.get(player)
		if not p then
			return false
		end
		local now = os.time()
		if now - p.daily.last < Config.DailyCooldown then
			return false, M("msg.daily_wait", { time = Format.time(Config.DailyCooldown - (now - p.daily.last)) })
		end
		if now - p.daily.last > Config.DailyStreakWindow then
			p.daily.streak = 0
		end
		local day = (p.daily.streak % #Config.DailyRewards) + 1
		p.daily.streak += 1
		p.daily.last = now
		local text = Rewards.grant(player, Config.DailyRewards[day])
		State.dirty(player)
		Data.save(player)
		return true, text
	end)

	Remotes.handle("ClaimGift", function(player, payload)
		local i = payload.index
		local gift = if Guard.int(i, 1, #Config.Gifts) then Config.Gifts[i] else nil
		local claimed = State.giftsClaimed[player]
		if not gift or not claimed then
			return false, M("msg.unknown_gift")
		end
		if claimed[i] then
			return false, M("msg.already_claimed")
		end
		local elapsed = os.clock() - (State.sessionStart[player] or os.clock())
		if elapsed + 1 < gift.minutes * 60 then
			return false, M("msg.not_ready")
		end
		claimed[i] = true
		local text = Rewards.grant(player, gift.reward)
		State.dirty(player)
		return true, text
	end)

	Remotes.handle("RedeemCode", function(player, payload)
		local p = Data.get(player)
		if not p or not Guard.str(payload.code, 30) then
			return false, M("msg.invalid_code")
		end
		local code = payload.code:upper():gsub("%s", "")
		local reward = Config.Codes[code]
		if not reward then
			return false, M("msg.invalid_code")
		end
		if p.codes[code] then
			return false, M("msg.already_redeemed")
		end
		p.codes[code] = true
		local text = Rewards.grant(player, reward)
		State.dirty(player)
		return true, text
	end)

	Remotes.handle("ClaimIndex", function(player, payload)
		local p = Data.get(player)
		local zone = payload.zone
		if not p or not Guard.int(zone, 1, #Config.Zones) or not Config.Zones[zone] then
			return false, M("msg.unknown_zone")
		end
		local key = tostring(zone)
		if p.indexClaimed[key] then
			return false, M("msg.already_claimed")
		end
		for _, id in Rewards.zonePets(zone) do
			if not p.discovered[id] then
				return false, M("msg.index_incomplete", { zone = M("zone." .. Config.Zones[zone].id) })
			end
		end
		p.indexClaimed[key] = true
		Hooks.fire("indexClaimed", player, zone)
		local gems = Config.IndexRewardGems[zone] or 0
		State.addGems(player, gems)
		State.dirty(player)
		return true, M("msg.index_claimed", { gems = gems, pct = math.floor(Config.IndexTapBonus * 100) })
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			pcall(Rewards.refreshFriends)
		end
	end)
end

return Rewards
