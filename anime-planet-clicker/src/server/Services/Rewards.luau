--!strict
-- Retention: daily streak, codes, free in-session gifts, pet index rewards and the friend
-- boost. Rewards.grant is also used by quests, the tutorial and developer products.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local GiftClock = require(ReplicatedStorage.Shared.GiftClock)
local M = Locale.m
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Capsules = require(script.Parent.Capsules)

local Rewards = {}

export type Reward = { kind: string, amount: number }

-- Applies a reward and returns a short description of what was given.
function Rewards.grant(player: Player, reward: Reward): Locale.Message
	local p = Data.get(player)
	if not p then
		return M("msg.error")
	end
	local kind, amount = reward.kind, reward.amount
	if kind == "stardust" or kind == "stardustMin" then
		local value = if kind == "stardust" then amount else math.max(50, State.income(player, p) * 60 * amount)
		State.addStardust(player, value, false)
		Remotes.fire("Reward", player, { kind = "stardust", amount = value })
		return M("reward.stardust", { n = Format.abbrev(value) })
	elseif kind == "crystals" then
		State.addCrystals(player, amount)
		Remotes.fire("Reward", player, { kind = "crystals", amount = amount })
		return M("reward.crystals", { n = amount })
	elseif kind == "luck" then
		State.addBuff(player, "luck", amount * 60)
		Remotes.fire("Reward", player, { kind = "luck", amount = amount })
		return M("reward.luck", { n = amount })
	elseif kind == "boost" then
		State.addBuff(player, "stardust", amount * 60)
		Remotes.fire("Reward", player, { kind = "boost", amount = amount })
		return M("reward.boost", { n = amount })
	elseif kind == "capsule" then
		Capsules.openExclusive(player, amount)
		return if amount > 1 then M("reward.capsules", { n = amount }) else M("reward.capsule1")
	end
	return M("msg.error")
end

-- Every regular pet that belongs to a galaxy's index page.
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
local function areFriends(a: Player, b: Player): boolean
	local lo, hi = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = lo .. ":" .. hi
	local cached = friendCache[key]
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

function Rewards.refreshFriends()
	local players = Players:GetPlayers()
	for _, player in players do
		if State.ready[player] then
			local n = 0
			for _, other in players do
				if other ~= player and areFriends(player, other) then
					n += 1
				end
			end
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
		if now - p.daily.last > Config.DailyBreak then
			p.daily.streak = 0
		end
		local day = (p.daily.streak % #Config.DailyRewards) + 1
		p.daily.streak += 1
		p.daily.last = now
		local text = Rewards.grant(player, Config.DailyRewards[day])
		State.dirty(player)
		task.spawn(Data.save, player)
		return true, text
	end)

	Remotes.handle("ClaimGift", function(player, payload)
		local i = payload.index
		local gift = if type(i) == "number" then Config.Gifts[i] else nil
		local p = Data.get(player)
		if not gift or not p then
			return false, M("msg.unknown_gift")
		end
		local elapsed = State.giftElapsed(player, p)
		if GiftClock.isClaimed(p.gifts, i) then
			return false, M("msg.already_claimed")
		end
		if not GiftClock.ready(elapsed, gift.minutes) then
			return false, M("msg.not_ready")
		end
		GiftClock.markClaimed(p.gifts, i)
		local text = Rewards.grant(player, gift.reward)
		State.dirty(player)
		task.spawn(Data.save, player)
		return true, text
	end)

	Remotes.handle("RedeemCode", function(player, payload)
		local p = Data.get(player)
		if not p or type(payload.code) ~= "string" or #payload.code > 30 then
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
	end, { interval = 1 })

	Remotes.handle("ClaimIndex", function(player, payload)
		local p = Data.get(player)
		local zone = payload.zone
		if not p or type(zone) ~= "number" or not Config.Zones[zone] then
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
		local crystals = Config.IndexRewardCrystals[zone] or 0
		State.addCrystals(player, crystals)
		State.dirty(player)
		return true, M("msg.index_claimed", { crystals = crystals, pct = math.floor(Config.IndexBoostPerZone * 100) })
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			pcall(Rewards.refreshFriends)
		end
	end)
end

return Rewards
