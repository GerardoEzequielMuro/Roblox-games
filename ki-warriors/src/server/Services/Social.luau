--!strict
-- Social features:
--   * referrals: invitee gift on join, inviter credited after the first 10 minutes of the
--     invitee (DataStore keyed by inviter), drained on join and every 120 s
--   * share-link prompt, group-join gift aura, notification opt-in ask
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
local Rewards = require(script.Parent.Rewards)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local Social = {}

local live = game.PlaceId ~= 0 -- DataStores only work in a published place

local refStore: DataStore? = nil
if live then
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.ReferralStore)
	end)
	if ok then
		refStore = store
	end
end

-- Invitee side, on join. Returns true when the invitee gift was granted.
function Social.applyReferral(player: Player, launchData: any): boolean
	local p = Data.get(player)
	local inviter = Referral.parse(launchData)
	if not p or not inviter or inviter == player.UserId or p.referredBy ~= 0 or p.playTime >= Config.ReferralMinPlaySeconds then
		return false
	end
	p.referredBy = inviter
	Rewards.grant(player, Config.ReferralInviteeGift :: any)
	Remotes.notify(player, M("msg.referral_welcome"), "success")
	State.dirty(player)
	return true
end

-- Invitee side: after 10 minutes of play, credit the inviter once.
local function creditInviter(player: Player)
	local p = Data.get(player)
	if not p or p.referredBy == 0 or p.referralPaid or p.playTime < Config.ReferralMinPlaySeconds then
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
Social.creditInviter = creditInviter

-- Inviter side: take the pending entries and grant one reward per friend (lifetime cap).
local function drainReferrals(player: Player)
	local p = Data.get(player)
	local store = refStore
	if not p or not store or not Data.isPersistent(player) then
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
	if not ok then
		return
	end
	for _ in taken do
		if p.referralRewards >= Config.ReferralLifetimeCap then
			break
		end
		p.referralRewards += 1
		Rewards.grant(player, Config.ReferralInviterGift :: any)
		Remotes.notify(player, M("msg.referral_reward"), "success")
	end
end

-- Notification opt-in ask (after the first form or the first ascension, at most weekly).
local function maybeAskNotifications(player: Player)
	local p = Data.get(player)
	if not p or os.time() - p.notifAskedAt <= Config.NotifAskInterval then
		return
	end
	p.notifAskedAt = os.time()
	Remotes.fire("AskNotifications", player)
end
Social.maybeAskNotifications = maybeAskNotifications

function Social.onReady(player: Player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(joinData) == "table" then
		Social.applyReferral(player, joinData.LaunchData)
	end
	task.spawn(drainReferrals, player)
	if Config.GroupId ~= 0 then
		task.spawn(function()
			local okGroup, member = pcall(function()
				return (player :: any):IsInGroupAsync(Config.GroupId)
			end)
			if okGroup and member then
				State.groupMember[player] = true
				State.dirty(player)
			end
		end)
	end
end

function Social.init()
	Hooks.on("form", function(player: Player, index: number)
		if index >= 2 then
			maybeAskNotifications(player)
		end
	end)
	Hooks.on("rebirth", function(player: Player)
		maybeAskNotifications(player)
	end)
	-- server-wide announcement of a rare milestone: one of the three strongest forms
	Hooks.on("formUnlocked", function(player: Player, index: number)
		if index >= 6 then
			Remotes.fireAll("Toast", { key = "toast.form_rare", args = { player = player.DisplayName, form = { key = "form." .. Config.Forms[index].id } }, color = Config.Forms[index].color })
		end
	end)

	Remotes.handle("ShareLink", function(player)
		local ok, err = pcall(function()
			(SocialService :: any):PromptLinkSharingAsync(player, {
				LaunchData = Referral.launchData(player.UserId),
				ExpirationSeconds = Config.ReferralLinkSeconds,
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
		if not ok or not member then
			return false, M("msg.join_group_first")
		end
		p.groupGiftClaimed = true
		State.groupMember[player] = true
		p.auras[Config.GroupGiftAura] = (p.auras[Config.GroupGiftAura] or 0) + 1
		State.dirty(player)
		return true, M("msg.group_gift", { aura = M("aura." .. Config.GroupGiftAura) })
	end)

	State.extras.social = function(_player, p)
		return { groupGiftClaimed = p.groupGiftClaimed, referralRewards = p.referralRewards, referredBy = p.referredBy, groupId = Config.GroupId }
	end

	-- referral upkeep
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(30)
			acc += 30
			for _, player in Players:GetPlayers() do
				if State.ready[player] then
					creditInviter(player)
					if acc >= 120 then
						task.spawn(drainReferrals, player)
					end
				end
			end
			if acc >= 120 then
				acc = 0
			end
		end
	end)
end

return Social
