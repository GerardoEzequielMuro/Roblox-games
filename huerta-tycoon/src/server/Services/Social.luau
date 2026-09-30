--!strict
-- Referrals (share link / game invites), group join gift, link sharing and the notification opt-in ask.
--   Invitee: joins with LaunchData "ref:<inviterId>" while new -> welcome gift, profile.referredBy set.
--   After the invitee has played ReferralQualifySeconds in total, a pending credit is appended to the inviter's
--   key in the Referrals DataStore; the inviter's server drains it (on join and every 120 s) and grants a gift
--   per friend, capped at ReferralMaxRewards for life.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Rewards = require(script.Parent.Rewards)

local Social = {}

local store: DataStore? = nil
if game.PlaceId ~= 0 then
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(Config.ReferralStoreName)
	end)
	if ok then
		store = res
	end
end

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok and type(name) == "string" then name else "?"
	return nameCache[userId]
end

local function totalPlayTime(s: Session.S): number
	return s.profile.playTime + (os.time() - s.joinedAt)
end

-- ===== invitee side =====
-- launchData comes from player:GetJoinData().LaunchData (tests pass a fake one). Returns true if accepted.
function Social.onJoin(s: Session.S, launchData: string?): boolean
	local inviter = Referral.parse(launchData)
	local p = s.profile
	if not inviter or inviter == s.player.UserId or p.referredBy ~= 0 or totalPlayTime(s) >= Config.ReferralQualifySeconds then
		return false
	end
	p.referredBy = inviter
	local text = Rewards.grant(s, Config.ReferralInviteeGift)
	Remotes.notify(s.player, R("msg.referralWelcome", { reward = text }), "success")
	Session.markDirty(s)
	return true
end

-- Credits the inviter once the invitee qualifies. Returns true when the credit was written (or no store exists).
function Social.creditInviter(s: Session.S): boolean
	local p = s.profile
	if p.referredBy == 0 or p.referralPaid or totalPlayTime(s) < Config.ReferralQualifySeconds then
		return false
	end
	if not store then
		p.referralPaid = true -- Studio/unpublished: nothing to deliver
		return true
	end
	local me = s.player.UserId
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(tostring(p.referredBy), function(old: any)
			local list = if type(old) == "table" then old else {}
			for _, e in list do
				if type(e) == "table" and e.u == me then
					return list
				end
			end
			if #list < Config.ReferralPendingMax then
				table.insert(list, { u = me, t = os.time() })
			end
			return list
		end)
	end)
	if ok then
		p.referralPaid = true
		Session.markDirty(s)
	end
	return ok
end

-- ===== inviter side =====
function Social.drain(s: Session.S)
	if not store or s.profile.referralRewards >= Config.ReferralMaxRewards then
		return
	end
	local taken: { any } = {}
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(tostring(s.player.UserId), function(old: any)
			taken = if type(old) == "table" then old else {}
			if #taken == 0 then
				return nil -- nothing to change
			end
			return {}
		end)
	end)
	if not ok then
		return
	end
	for _, e in taken do
		if s.profile.referralRewards >= Config.ReferralMaxRewards then
			break
		end
		if type(e) == "table" and type(e.u) == "number" then
			s.profile.referralRewards += 1
			local text = Rewards.grant(s, Config.ReferralInviterGift)
			Remotes.notify(s.player, R("msg.referralReward", { name = nameOf(e.u), reward = text }), "rare")
		end
	end
	Session.markDirty(s)
end

-- ===== notification opt-in (client shows the card; Roblox shows the real prompt) =====
function Social.happyMoment(s: Session.S)
	local p = s.profile
	if os.time() - p.notifAskedAt <= Config.NotifAskCooldown then
		return
	end
	p.notifAskedAt = os.time()
	Session.markDirty(s)
	Remotes.fire("AskNotifications", s.player)
end

-- ===== actions =====
Remotes.handle("ShareLink", function(player)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	local ok = pcall(function()
		SocialService:PromptLinkSharingAsync(player, {
			LaunchData = Referral.encode(player.UserId),
			ExpirationSeconds = 7 * 86400,
		})
	end)
	if not ok then
		return false, R("err.shareUnavailable")
	end
	return true
end)

Remotes.handle("ClaimGroupGift", function(player)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	if Config.GroupId == 0 then
		return false, R("err.badRequest")
	end
	if s.profile.groupGiftClaimed then
		return false, R("err.giftClaimed")
	end
	local ok, member = pcall(player.IsInGroupAsync, player, Config.GroupId)
	if not ok then
		-- older API as a fallback (deprecated, still works)
		ok, member = pcall(function()
			return (player :: any):IsInGroup(Config.GroupId)
		end)
	end
	if not ok or not member then
		return false, R("err.notInGroup")
	end
	s.profile.groupGiftClaimed = true
	s.inGroup = true
	local text = Rewards.grant(s, Config.GroupJoinGift)
	return true, R("msg.groupGift", { reward = text })
end)

function Social.onPlayerJoined(s: Session.S)
	local ok, jd = pcall(function()
		return s.player:GetJoinData()
	end)
	if ok and type(jd) == "table" then
		Social.onJoin(s, jd.LaunchData)
	end
	task.spawn(Social.drain, s)
end

function Social.run()
	task.spawn(function()
		local t = 0
		while true do
			task.wait(30)
			t += 30
			for _, s in Session.sessions do
				task.spawn(Social.creditInviter, s)
				if t % 120 == 0 then
					task.spawn(Social.drain, s)
				end
			end
		end
	end)
end

return Social
