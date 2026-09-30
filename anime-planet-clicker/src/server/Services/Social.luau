--!strict
-- Social features:
--   * cross-server rare-pet announcements (MessagingService "PC_RarePet")
--   * referrals: invitee gift on join, inviter credited after the invitee's first 10 minutes
--     (DataStore Config.ReferralStore keyed by inviter), drained on join and every 120 s
--   * share-link prompt, group-join gift pet, notification opt-in ask
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Rewards = require(script.Parent.Rewards)
local Pets = require(script.Parent.Pets)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local Social = {}

local live = game.PlaceId ~= 0 -- MessagingService / DataStores only work in a published place

---------------------------------------------------------------------------
-- Cross-server rare hatches
---------------------------------------------------------------------------
local RARE_TOPIC = "PC_RarePet"
local outbox: { any } = {}
local inbox: { any } = {}

local function isGlobalWorthy(r: any): boolean
	return r.rarity == "Mythic" or r.rarity == "Secret" or r.tier == 2
end

function Social.queueGlobal(player: Player, r: any)
	if not live then
		return
	end
	table.insert(outbox, { n = player.DisplayName, p = r.id, t = r.tier, r = r.rarity, o = Format.chance(r.chance), j = game.JobId })
	while #outbox > 10 do
		table.remove(outbox, 1)
	end
end

---------------------------------------------------------------------------
-- Referrals
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Notification opt-in ask (after the first Legendary+ pet or rebirth, at most weekly)
---------------------------------------------------------------------------
local function maybeAskNotifications(player: Player)
	local p = Data.get(player)
	if not p or os.time() - p.notifAskedAt <= Config.NotifAskInterval then
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
	Hooks.on("opened", function(player: Player, results: { any })
		local legendary = false
		for _, r in results do
			if r.deleted then
				continue
			end
			if isGlobalWorthy(r) then
				Social.queueGlobal(player, r)
			end
			local rarity = Config.RarityByName[r.rarity]
			if rarity and rarity.order >= Config.RarityByName.Legendary.order then
				legendary = true
			end
		end
		if legendary then
			maybeAskNotifications(player)
		end
	end)
	Hooks.on("rebirth", function(player: Player)
		local p = Data.get(player)
		if p and p.rebirths == 1 then
			maybeAskNotifications(player)
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
		if not ok then
			ok, member = pcall(function()
				return (player :: any):IsInGroup(Config.GroupId) -- older engines
			end)
		end
		if not ok or not member then
			return false, M("msg.join_group_first")
		end
		if not Pets.hasRoom(p, 1) then
			return false, M("msg.free_a_slot")
		end
		p.groupGiftClaimed = true
		Pets.add(player, Config.GroupGiftPet, 0, true)
		State.dirty(player)
		return true, M("msg.group_gift", { pet = M("pet." .. Config.GroupGiftPet) })
	end)

	State.extras.social = function(_player, p)
		return { groupGiftClaimed = p.groupGiftClaimed, referralRewards = p.referralRewards, referredBy = p.referredBy }
	end

	if live then
		task.spawn(function()
			pcall(function()
				MessagingService:SubscribeAsync(RARE_TOPIC, function(message)
					local d = message.Data
					if type(d) ~= "table" or d.j == game.JobId or type(d.p) ~= "string" or not Formulas.PetById[d.p] then
						return
					end
					table.insert(inbox, d)
					while #inbox > 5 do
						table.remove(inbox, 1)
					end
				end)
			end)
		end)
		-- publish at most one message every 2 s
		task.spawn(function()
			while true do
				task.wait(2)
				local msg = table.remove(outbox, 1)
				if msg then
					pcall(function()
						MessagingService:PublishAsync(RARE_TOPIC, msg)
					end)
				end
			end
		end)
		-- show incoming ones one every 4 s
		task.spawn(function()
			while true do
				task.wait(4)
				local d = table.remove(inbox, 1)
				if d then
					Remotes.fireAll("Toast", { kind = "pet", player = tostring(d.n), pet = d.p, rarity = Formulas.PetById[d.p].rarity, tier = tonumber(d.t) or 0, chanceText = tostring(d.o), global = true })
				end
			end
		end)
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
