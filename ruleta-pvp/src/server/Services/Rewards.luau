--!strict
-- Rewards that don't come from a match: the 7-day calendar, session gifts, codes, settings.
-- Every reward is fixed and shown before it is claimed; nothing here is random.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Cosmetics = require(script.Parent.Cosmetics)
local M = Locale.m

local Rewards = {}

export type Reward = { kind: string, amount: number, item: string? }

-- Applies a reward and returns the message to show.
function Rewards.grant(player: Player, reward: Reward): Locale.Message
	if reward.kind == "coins" then
		State.addCoins(player, reward.amount)
		return M("reward.coins", { n = reward.amount })
	elseif reward.kind == "xp" then
		State.addXp(player, reward.amount)
		return M("reward.xp", { n = reward.amount })
	elseif reward.kind == "item" and reward.item then
		if Cosmetics.grant(player, reward.item) then
			Cosmetics.refresh(player, true)
			return M("reward.item", { item = M("cos." .. reward.item) })
		end
		-- already owned: the coin value instead
		State.addCoins(player, reward.amount)
		return M("reward.coins", { n = reward.amount })
	end
	return M("msg.error")
end

local DAY = 86400

function Rewards.dailyState(p: Data.Profile, now: number): { canClaim: boolean, day: number, streak: number }
	local today = now // DAY
	local last = p.daily.last
	if last == today then
		return { canClaim = false, day = (p.daily.streak - 1) % #Config.DailyRewards + 1, streak = p.daily.streak }
	end
	local streak = if last == today - 1 then p.daily.streak + 1 else 1
	return { canClaim = true, day = (streak - 1) % #Config.DailyRewards + 1, streak = streak }
end

function Rewards.init()
	State.extras.dailyState = function(_player, p)
		return Rewards.dailyState(p, os.time())
	end

	Remotes.handle("ClaimDaily", function(player)
		local p = Data.get(player)
		if not p then
			return false, M("msg.error")
		end
		local st = Rewards.dailyState(p, os.time())
		if not st.canClaim then
			return false, M("msg.daily_tomorrow")
		end
		p.daily.last = os.time() // DAY
		p.daily.streak = st.streak
		local message = Rewards.grant(player, Config.DailyRewards[st.day] :: any)
		State.dirty(player)
		return true, message
	end)

	Remotes.handle("ClaimGift", function(player, payload)
		local p = Data.get(player)
		local index = payload.index
		local gift = if type(index) == "number" then Config.Gifts[index] else nil
		local claimed = State.giftsClaimed[player]
		if not p or not gift or not claimed then
			return false, M("msg.bad_request")
		end
		if claimed[index] then
			return false, M("msg.already_claimed")
		end
		local elapsed = os.clock() - (State.sessionStart[player] or os.clock())
		if elapsed < gift.minutes * 60 then
			return false, M("msg.gift_not_ready")
		end
		claimed[index] = true
		local message = Rewards.grant(player, gift.reward :: any)
		State.dirty(player)
		return true, message
	end)

	Remotes.handle("RedeemCode", function(player, payload)
		local p = Data.get(player)
		local code = payload.code
		if not p or type(code) ~= "string" or #code > 24 then
			return false, M("msg.code_invalid")
		end
		code = code:upper():gsub("%s", "")
		local reward = Config.Codes[code]
		if not reward then
			return false, M("msg.code_invalid")
		end
		if p.codes[code] then
			return false, M("msg.code_used")
		end
		p.codes[code] = true
		local message = Rewards.grant(player, reward :: any)
		State.dirty(player)
		return true, message
	end)

	-- Settings: volumes 0..1, toggles. Auto toggles are comfort only (see Tables / CoreService).
	Remotes.handle("SetSetting", function(player, payload)
		local p = Data.get(player)
		local key, value = payload.key, payload.value
		if not p or type(key) ~= "string" then
			return false, M("msg.bad_request")
		end
		local s = p.settings :: any
		if key == "music" or key == "sfx" then
			if type(value) ~= "number" or value ~= value then
				return false, M("msg.bad_request")
			end
			s[key] = math.clamp(value, 0, 1)
		elseif key == "shake" or key == "flashes" or key == "lite" or key == "autoQueue" or key == "autoPlay" then
			if type(value) ~= "boolean" then
				return false, M("msg.bad_request")
			end
			s[key] = value
		elseif key == "autoCharge" then
			if type(value) ~= "boolean" then
				return false, M("msg.bad_request")
			end
			if value and p.level < Config.Core.autoUnlockLevel and not State.owns(player, "AutoCharge") then
				return false, M("msg.auto_locked", { level = Config.Core.autoUnlockLevel })
			end
			s.autoCharge = value
		else
			return false, M("msg.bad_request")
		end
		State.dirty(player)
		return true
	end)
end

return Rewards
