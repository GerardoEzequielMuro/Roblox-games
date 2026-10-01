--!strict
-- Retention rewards: daily streak, codes, and in-session play-time rewards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Security = require(ReplicatedStorage.Shared.Security)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local Rewards = {}

local codeFails: { [Player]: number } = {} -- wrong codes in a row
local codeLock: { [Player]: number } = {} -- os.clock() until which redeeming is paused

function Rewards.init()
	Players.PlayerRemoving:Connect(function(player)
		codeFails[player] = nil
		codeLock[player] = nil
	end)

	Remotes.handle("ClaimDaily", function(player)
		local p = Data.get(player)
		if not p then
			return false
		end
		local can, _, day = Session.dailyInfo(p)
		if not can then
			return false, Remotes.M("err.come_back")
		end
		p.daily.streak = day
		p.daily.lastClaim = os.time()
		local reward = Config.DailyRewards[math.min(day, #Config.DailyRewards)]
		if Session.hasPass(player, "VIP") then
			reward *= 2
		end
		reward *= Session.bonusMult(p)
		p.coins += reward
		p.totalCoins += reward
		local msg: { Remotes.Msg } = { Remotes.M("msg.daily", { day = day, coins = reward }) }
		-- day 7 of the streak, plus the stage-600 gift (a free skip with every daily reward)
		local skips = (if day % Config.DailyFreeSkipOnDay == 0 then 1 else 0) + Gifts.dailySkips(p.gifts)
		if skips > 0 then
			p.freeSkips += skips
			table.insert(msg, Remotes.M("msg.plus_free_skips", { n = skips }))
		end
		Session.push(player)
		return true, msg
	end)

	Remotes.handle("RedeemCode", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		local s = Session.get(player)
		local raw = Security.str(payload.code, 64) -- a longer string is never a code (and is not worth a gsub)
		if not s or not raw then
			return false, Remotes.M("err.invalid_code")
		end
		local now = os.clock()
		if now < (codeLock[player] or 0) then
			return false, Remotes.M("err.slow_down") -- too many wrong guesses: brute force is slow
		end
		local code = string.upper((string.gsub(raw, "%s", "")))
		local c = if #code > 0 and #code <= 24 then Config.Codes[code] else nil
		if not c then
			local fails = (codeFails[player] or 0) + 1
			codeFails[player] = fails
			if fails >= 5 then
				codeFails[player] = 0
				codeLock[player] = now + 60
			end
			return false, Remotes.M("err.invalid_code")
		end
		if c.expires and os.time() > c.expires then
			return false, Remotes.M("err.code_expired")
		end
		if p.codes[code] then
			return false, Remotes.M("err.already_redeemed")
		end
		p.codes[code] = true
		local coins = c.coins * Session.bonusMult(p)
		p.coins += coins
		p.totalCoins += coins
		local msg: { Remotes.Msg } = { Remotes.M("msg.code", { coins = coins }) }
		if c.freeSkips then
			p.freeSkips += c.freeSkips
			table.insert(msg, Remotes.M("msg.plus_free_skips", { n = c.freeSkips }))
		end
		Session.push(player)
		return true, msg
	end)

	-- Join-the-group reward (P0-7)
	Remotes.handle("ClaimGroupGift", function(player)
		local p = Data.get(player)
		if not p or Config.GroupId == 0 then
			return false, Remotes.M("err.not_available")
		end
		if p.groupGiftClaimed then
			return false, Remotes.M("err.already_claimed")
		end
		local ok, member = pcall(function()
			return player:IsInGroupAsync(Config.GroupId)
		end)
		if not ok then
			ok, member = pcall(function()
				return (player :: any):IsInGroup(Config.GroupId)
			end)
		end
		if not ok or not member then
			return false, Remotes.M("err.join_group_first")
		end
		local gift = Config.GroupGift
		p.groupGiftClaimed = true
		p.coins += gift.coins
		p.totalCoins += gift.coins
		p.freeSkips += gift.freeSkips
		p.trails[gift.trail] = true
		Session.push(player)
		return true, Remotes.M("msg.group_gift", { coins = gift.coins, n = gift.freeSkips })
	end)

	Remotes.handle("ClaimPlaytime", function(player, payload)
		local p = Data.get(player)
		local s = Session.get(player)
		if not p or not s then
			return false
		end
		local idx = Security.int(payload.index, 1, #Config.PlaytimeRewards)
		local r = idx and Config.PlaytimeRewards[idx]
		if not idx or not r then
			return false, Remotes.M("err.unknown_reward")
		end
		if s.playClaimed[idx] then
			return false, Remotes.M("err.already_claimed")
		end
		if os.clock() - s.joined < r.minutes * 60 then
			return false, Remotes.M("err.keep_playing")
		end
		s.playClaimed[idx] = true
		local got = Session.addCoins(player, r.coins)
		p.freeSkips += r.freeSkips
		Session.push(player)
		local msg: { Remotes.Msg } = { Remotes.M("msg.playtime", { coins = got }) }
		if r.freeSkips > 0 then
			table.insert(msg, Remotes.M("msg.plus_free_skips", { n = r.freeSkips }))
		end
		return true, msg
	end)
end

return Rewards
