--!strict
-- Social features:
--   * referrals: invitee gift on join, inviter credited once the invitee finishes a few matches
--     (DataStore keyed by inviter, drained on join and every 120 s)
--   * share-link prompt, group-join gift, notification opt-in ask (after the first win)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local M = Locale.m

local Social = {}

local live = game.PlaceId ~= 0 -- DataStores only work in a published place
local NOTIF_ASK_INTERVAL = 7 * 86400
local LINK_SECONDS = 7 * 86400

local refStore: DataStore? = nil
if live then
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName .. "_referrals")
	end)
	if ok then
		refStore = store
	end
end

-- Invitee side, on join. Returns true when the invitee gift was granted.
function Social.applyReferral(player: Player, launchData: any): boolean
	local p = Data.get(player)
	local inviter = Referral.parse(launchData)
	if not p or not inviter or inviter == player.UserId or p.referredBy ~= 0 or p.matches > 0 then
		return false
	end
	p.referredBy = inviter
	State.addCoins(player, Config.Referral.invitedCoins)
	Remotes.notify(player, M("msg.referral_welcome", { n = Config.Referral.invitedCoins }), "success")
	State.dirty(player)
	return true
end

-- Invitee side: after Config.Referral.matchesToCredit finished matches, credit the inviter once.
function Social.onMatchFinished(player: Player)
	local p = Data.get(player)
	if not p or p.referredBy == 0 or p.referralPaid or p.matches < Config.Referral.matchesToCredit then
		return
	end
	p.referralPaid = true
	local store = refStore
	if not store then
		return
	end
	local inviter, me = p.referredBy, player.UserId
	task.spawn(function()
		local ok, err = pcall(function()
			store:UpdateAsync(tostring(inviter), function(old: any)
				local list = if type(old) == "table" then old else {}
				for _, e in list do
					if e.u == me then
						return list
					end
				end
				table.insert(list, { u = me, t = os.time() })
				while #list > 50 do
					table.remove(list, 1)
				end
				return list
			end)
		end)
		if not ok then
			warn("[Social] referral credit failed", err)
		end
	end)
end

-- Inviter side: pays `count` pending referrals (lifetime cap). Returns how many were paid.
function Social.payInviter(player: Player, count: number): number
	local p = Data.get(player)
	if not p then
		return 0
	end
	local paid = 0
	for _ = 1, count do
		if p.referralRewards >= Config.Referral.maxRewards then
			break
		end
		p.referralRewards += 1
		paid += 1
		State.addCoins(player, Config.Referral.inviterCoins)
		Remotes.notify(player, M("msg.referral_reward", { n = Config.Referral.inviterCoins }), "success")
	end
	State.dirty(player)
	return paid
end

local function drainReferrals(player: Player)
	local store = refStore
	if not store or not Data.isPersistent(player) then
		return
	end
	local taken: { any } = {}
	local ok = pcall(function()
		store:UpdateAsync(tostring(player.UserId), function(old: any)
			if type(old) ~= "table" or #old == 0 then
				return nil
			end
			taken = old
			return {}
		end)
	end)
	if ok and #taken > 0 then
		Social.payInviter(player, #taken)
	end
end

-- Asked at most weekly, after a win (a happy moment).
function Social.maybeAskNotifications(player: Player)
	local p = Data.get(player)
	if not p or os.time() - p.notifAskedAt <= NOTIF_ASK_INTERVAL then
		return
	end
	p.notifAskedAt = os.time()
	Remotes.fire("AskNotifications", player)
end

function Social.onJoin(player: Player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(joinData) == "table" then
		Social.applyReferral(player, joinData.LaunchData)
	end
	task.spawn(drainReferrals, player)
end

function Social.init()
	Remotes.handle("ShareLink", function(player)
		local ok, err = pcall(function()
			(SocialService :: any):PromptLinkSharingAsync(player, {
				LaunchData = Referral.launchData(player.UserId),
				ExpirationSeconds = LINK_SECONDS,
			})
		end)
		if not ok then
			warn("[Social] link sharing unavailable:", err)
			return false, M("msg.share_unavailable")
		end
		return true
	end)

	Remotes.handle("ClaimGroupGift", function(player)
		local p = Data.get(player)
		if not p or Config.GroupId == 0 then
			return false, M("msg.group_unavailable")
		end
		if p.groupGiftClaimed then
			return false, M("msg.already_claimed")
		end
		local ok, member = pcall(function()
			return (player :: any):IsInGroupAsync(Config.GroupId)
		end)
		if not ok then
			ok, member = pcall(function()
				return (player :: any):IsInGroup(Config.GroupId) -- older engines
			end)
		end
		if not ok or not member then
			return false, M("msg.join_group_first")
		end
		p.groupGiftClaimed = true
		State.addCoins(player, Config.GroupGift.coins)
		State.dirty(player)
		return true, M("reward.coins", { n = Config.GroupGift.coins })
	end)

	State.extras.social = function(_player, p)
		return { groupGiftClaimed = p.groupGiftClaimed, referralRewards = p.referralRewards, referredBy = p.referredBy, group = Config.GroupId ~= 0 }
	end

	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in Players:GetPlayers() do
				if State.ready[player] then
					task.spawn(drainReferrals, player)
				end
			end
		end
	end)
end

return Social
