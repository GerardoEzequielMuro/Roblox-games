--!nonstrict
-- Invite friends (game invite with referral LaunchData), share link (server prompts link sharing) and the
-- join-the-group gift (only when Config.GroupId is set and not claimed yet).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local GroupService = game:GetService("GroupService")

local Config = require(ReplicatedStorage.Shared.Config)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)
local Toasts = require(script.Parent.Toasts)

local player = Players.LocalPlayer

local InvitePanel = {}

function InvitePanel.invite()
	local okCan, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if not okCan or not can then
		Toasts.show(L("invite.unavailable"), "error")
		return
	end
	pcall(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.LaunchData = Referral.encode(player.UserId)
		options.PromptMessage = I18n.t("invite.promptMessage")
		SocialService:PromptGameInvite(player, options)
	end)
end

function InvitePanel.joinGroup()
	if Config.GroupId == 0 then
		return
	end
	pcall(function()
		GroupService:PromptJoinAsync(Config.GroupId)
	end)
	Net.request("ClaimGroupGift")
end

function InvitePanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "InvitePanel",
		Title = L("panel.invite"),
		Icon = "👋",
		Color = Theme.C.Blue,
		Size = UDim2.fromOffset(560, 440),
	})
	local body = p.content
	C.list(body, true, 12, Enum.HorizontalAlignment.Center)
	C.label(body, L("invite.subtitle"), UDim2.new(1, -20, 0, 60), {
		TextSize = 22,
		TextColor3 = Theme.C.Ink,
		Outline = false,
		LayoutOrder = 1,
	})
	C.button({
		Name = "InviteFriends",
		Parent = body,
		Text = L("invite.button"),
		TextSize = 24,
		Color = Theme.C.Green,
		Size = UDim2.fromOffset(360, 60),
		LayoutOrder = 2,
		OnClick = InvitePanel.invite,
	})
	C.button({
		Name = "ShareLink",
		Parent = body,
		Text = L("invite.share"),
		TextSize = 24,
		Color = Theme.C.Blue,
		Size = UDim2.fromOffset(360, 60),
		LayoutOrder = 3,
		OnClick = function()
			Net.request("ShareLink", nil, { silentOk = true })
		end,
	})
	local groupBtn = C.button({
		Name = "JoinGroup",
		Parent = body,
		Text = L("invite.group"),
		TextSize = 22,
		Color = Theme.C.Purple,
		Size = UDim2.fromOffset(360, 60),
		LayoutOrder = 4,
		OnClick = InvitePanel.joinGroup,
	})
	groupBtn.Visible = false
	local note = C.label(body, "", UDim2.new(1, -20, 0, 40), {
		Font = Theme.FontAlt,
		TextSize = 15,
		TextColor3 = Theme.C.InkSoft,
		Outline = false,
		LayoutOrder = 5,
	})

	local function refresh()
		local d = State.data
		local gg = d and d.groupGift
		groupBtn.Visible = Config.GroupId ~= 0 and type(gg) == "table" and gg.available == true
		I18n.set(note, "Text", L("invite.note", { n = d and d.referralRewards or 0, max = Config.ReferralMaxRewards }))
	end
	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return InvitePanel
