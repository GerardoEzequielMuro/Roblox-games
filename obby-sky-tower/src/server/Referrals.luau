--!strict
-- Invites and referral rewards (P0-3).
--   * Invitee joins with LaunchData "ref:<inviterId>" (game invite or share link) and is new
--     (best < 5): +1 free skip +50 coins, remembered in profile.referredBy.
--   * When that invitee first reaches Config.ReferralPayStage, an entry is appended to the
--     inviter's key in a DataStore (works across servers / while the inviter is offline).
--   * The inviter drains the key on join and every 120 s: +1 free skip +100 coins per entry,
--     lifetime cap Config.ReferralMaxRewards.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local Referrals = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.ReferralStore)
	end)
	if ok then
		store = result
	end
end

type Entry = { u: number, t: number }
local MAX_ENTRIES = 50

-- Applies an invite to a freshly loaded player. Returns true when the invitee gift was given.
function Referrals.applyInvite(player: Player, launchData: any): boolean
	local p = Data.get(player)
	local inviter = Referral.parse(launchData)
	if not p or not inviter or inviter == player.UserId then
		return false
	end
	if p.referredBy ~= 0 or p.best >= Config.ReferralPayStage then
		return false -- only new players, only once
	end
	p.referredBy = inviter
	local gift = Config.ReferralInviteeGift
	p.coins += gift.coins
	p.totalCoins += gift.coins
	p.freeSkips += gift.freeSkips
	Remotes.notify(player, Remotes.M("msg.invited_gift", { coins = gift.coins, n = gift.freeSkips }), "success")
	Session.push(player)
	return true
end

-- Called when the player reaches a new stage: credits the inviter once.
function Referrals.onStage(player: Player, stage: number)
	local p = Data.get(player)
	if not p or p.referredBy == 0 or p.referralPaid or stage < Config.ReferralPayStage then
		return
	end
	p.referralPaid = true
	local inviter = p.referredBy
	local ds = store
	if not ds then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ds:UpdateAsync(tostring(inviter), function(old: any)
				local list: { Entry } = if type(old) == "table" then old else {}
				for _, e in list do
					if e.u == player.UserId then
						return nil -- already queued
					end
				end
				if #list >= MAX_ENTRIES then
					return nil
				end
				table.insert(list, { u = player.UserId, t = os.time() })
				return list
			end)
		end)
		if not ok then
			warn("[Referrals] queue failed", err)
		end
	end)
end

-- Grants pending referral rewards to an online inviter.
function Referrals.drain(player: Player)
	local p = Data.get(player)
	local ds = store
	if not p or not ds or not Data.isPersistent(player) then
		return
	end
	local taken: { Entry } = {}
	local ok, err = pcall(function()
		ds:UpdateAsync(tostring(player.UserId), function(old: any)
			if type(old) ~= "table" or #old == 0 then
				taken = {}
				return nil
			end
			taken = old
			return {}
		end)
	end)
	if not ok then
		warn("[Referrals] drain failed", err)
		return
	end
	Referrals.grantInviter(player, #taken)
end

-- +gift per referred friend, respecting the lifetime cap. Returns how many were granted.
function Referrals.grantInviter(player: Player, count: number): number
	local p = Data.get(player)
	if not p or count <= 0 then
		return 0
	end
	local room = math.max(0, Config.ReferralMaxRewards - p.referralRewards)
	local n = math.min(count, room)
	if n <= 0 then
		return 0
	end
	local gift = Config.ReferralInviterGift
	p.referralRewards += n
	p.coins += gift.coins * n
	p.totalCoins += gift.coins * n
	p.freeSkips += gift.freeSkips * n
	Remotes.notify(player, Remotes.M("msg.referral_reward", { friends = n, coins = gift.coins * n, n = gift.freeSkips * n }), "success")
	Session.push(player)
	Data.save(player)
	return n
end

function Referrals.onJoin(player: Player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(joinData) == "table" then
		Referrals.applyInvite(player, joinData.LaunchData)
	end
	task.spawn(Referrals.drain, player)
end

function Referrals.init()
	-- "Share link": the link carries the same launch data as a game invite
	Remotes.handle("ShareLink", function(player)
		local ok, err = pcall(function()
			SocialService:PromptLinkSharingAsync(player, {
				LaunchData = Referral.make(player.UserId),
				ExpirationSeconds = 7 * 86400,
			})
		end)
		if not ok then
			warn("[Referrals] link sharing unavailable:", err)
			return false, Remotes.M("err.not_available")
		end
		return true
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in Players:GetPlayers() do
				task.spawn(Referrals.drain, player)
			end
		end
	end)
end

return Referrals
