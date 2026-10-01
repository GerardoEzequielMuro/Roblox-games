--!strict
-- Retention rewards: daily streak, free gifts by session time, codes, friend boost.
-- Rewards.grant is the single place that turns a { kind, amount } into something on the
-- profile (also used by quests, wishes, referrals and developer products).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Validate = require(script.Parent.Validate)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local M = Locale.m

local Rewards = {}
local codeTries: { [Player]: Validate.Bucket } = {}

export type Reward = { kind: string, amount: number, item: string?, id: string? }

-- kinds: sparks (minutes of income) | gems | boost (minutes of x2 training) | spins (aura spins)
--        | seed (item = seed id) | skin / mount / aura (id = cosmetic id, amount ignored)
function Rewards.grant(player: Player, reward: Reward): Locale.Message
	local p = Data.get(player)
	if not p then
		return M("msg.error")
	end
	if reward.kind == "sparks" then
		local amount = State.sparksForMinutes(p, reward.amount)
		State.addSparks(player, amount, false)
		Remotes.fire("Reward", player, { kind = "sparks", amount = amount })
		return M("reward.sparks", { n = Format.abbrev(amount) })
	elseif reward.kind == "gems" then
		State.addGems(player, reward.amount)
		Remotes.fire("Reward", player, { kind = "gems", amount = reward.amount })
		return M("reward.gems", { n = reward.amount })
	elseif reward.kind == "boost" then
		p.boostLeft += reward.amount * 60
		State.dirty(player)
		Remotes.fire("Reward", player, { kind = "boost", amount = reward.amount })
		return M("reward.boost", { n = reward.amount })
	elseif reward.kind == "spins" then
		p.spins += reward.amount
		State.dirty(player)
		Remotes.fire("Reward", player, { kind = "spins", amount = reward.amount })
		return M("reward.spins", { n = reward.amount })
	elseif reward.kind == "seed" and reward.item and Config.SeedById[reward.item] then
		-- rewards ignore the carry cap (only Sparks purchases are capped)
		p.items[reward.item] = (p.items[reward.item] or 0) + reward.amount
		State.dirty(player)
		Remotes.fire("Reward", player, { kind = "seed", amount = reward.amount })
		return M("reward.seed", { n = reward.amount, item = M("item." .. reward.item) })
	elseif (reward.kind == "skin" and reward.id and Config.SkinById[reward.id]) or (reward.kind == "mount" and reward.id and Config.MountById[reward.id]) then
		local owned = if reward.kind == "skin" then p.skins else p.mounts
		owned[reward.id] = true
		State.dirty(player)
		return M("reward." .. reward.kind, { name = M(reward.kind .. "." .. reward.id) })
	elseif reward.kind == "aura" and reward.id and Config.AuraById[reward.id] then
		p.auras[reward.id] = (p.auras[reward.id] or 0) + 1
		State.dirty(player)
		return M("reward.aura", { name = M("aura." .. reward.id) })
	end
	return M("msg.error")
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
		return false
	end
	friendCache[key] = isFriend == true
	return isFriend == true
end

function Rewards.refreshFriends()
	for _, player in Players:GetPlayers() do
		if State.ready[player] then
			local n = 0
			for _, other in Players:GetPlayers() do
				if other ~= player and areFriends(player, other) then
					n += 1
				end
			end
			local bonus = math.min(Config.FriendBoostMax, n * Config.FriendBoostPerFriend)
			if bonus ~= State.friendBonus[player] then
				State.friendBonus[player] = bonus
				State.dirty(player)
			end
		end
	end
end

function Rewards.dailyState(p: Data.Profile): { [string]: any }
	local now = os.time()
	local today = now // 86400
	local lastDay = p.daily.last // 86400
	return {
		canClaim = p.daily.last == 0 or today > lastDay,
		streak = if p.daily.last ~= 0 and today - lastDay > 1 then 0 else p.daily.streak,
		nextAt = (today + 1) * 86400,
	}
end

function Rewards.init()
	State.extras.dailyState = function(_player, p)
		return Rewards.dailyState(p)
	end

	Remotes.handle("ClaimDaily", function(player)
		local p = Data.get(player)
		if not p then
			return false, M("msg.error")
		end
		local st = Rewards.dailyState(p)
		if not st.canClaim then
			return false, M("msg.daily_wait")
		end
		local day = (st.streak % #Config.DailyRewards) + 1
		p.daily.streak = st.streak + 1
		p.daily.last = os.time()
		local text = Rewards.grant(player, Config.DailyRewards[day])
		if State.owns(player, "VIP") then
			State.addGems(player, Config.VipDailyGems)
		end
		State.dirty(player)
		task.spawn(Data.save, player)
		return true, text
	end)

	Remotes.handle("ClaimGift", function(player, payload)
		local i = Validate.int(payload.index, 1, #Config.Gifts)
		local gift = if i then Config.Gifts[i] else nil
		local claimed = State.giftsClaimed[player]
		if not i or not gift or not claimed then
			return false, M("msg.bad_request")
		end
		if claimed[i] then
			return false, M("msg.already_claimed")
		end
		local elapsed = os.time() - (State.sessionStart[player] or os.time())
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
		local raw = Validate.str(payload.code, 30)
		if not p or not raw then
			return false, M("msg.invalid_code")
		end
		-- guessing codes: 5 wrong tries, then one more every 12 s
		local bucket = codeTries[player]
		if not bucket then
			bucket = Validate.newBucket(1 / 12, 5, os.clock())
			codeTries[player] = bucket
		end
		local code = raw:upper():gsub("%s", "")
		local reward = Config.Codes[code]
		if not reward then
			if not Validate.take(bucket, os.clock(), 1) then
				return false, M("msg.slow_down")
			end
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

	Players.PlayerRemoving:Connect(function(player)
		codeTries[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			pcall(Rewards.refreshFriends)
		end
	end)
end

return Rewards
