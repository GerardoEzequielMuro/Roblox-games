--!strict
-- Invite friends (game invite + share link, both carry "ref:<userId>" launch data) and the
-- one-time group-join gift.
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local InviteWindow = {}

local player = Players.LocalPlayer

local function inviteFriends()
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not ok or not can then
		Toasts.show(Lang.t("invite.unavailable"), "error")
		return
	end
	local shown = pcall(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.LaunchData = Referral.launchData(player.UserId)
		options.PromptMessage = Lang.t("invite.prompt", { gems = Config.ReferralInviteeGift.amount })
		SocialService:PromptGameInvite(player, options)
	end)
	if not shown then
		Toasts.show(Lang.t("invite.unavailable"), "error")
	end
end

function InviteWindow.init()
	local w = Windows.create("Invite", "💌", "win.invite", Theme.Pink, Vector2.new(600, 470))
	local body = w.body
	Theme.text({ Key = "invite.desc", Args = { gems = Config.ReferralInviteeGift.amount }, TextWrapped = true, Size = UDim2.new(1, -20, 0, 84), Position = UDim2.fromOffset(10, 0), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 24, Parent = body })
	local count = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 88), TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 20, Parent = body })
	local row = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 124), Parent = body }, {
		Theme.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	Theme.button({ Text = "", Key = "invite.button", Color = Theme.Green, Size = UDim2.fromOffset(250, 62), LayoutOrder = 1, TextSize = 26, Parent = row, OnClick = inviteFriends })
	Theme.button({
		Key = "invite.share",
		Color = Theme.Blue,
		Size = UDim2.fromOffset(250, 62),
		LayoutOrder = 2,
		TextSize = 26,
		Parent = row,
		OnClick = function()
			local ok, err = Net.request("ShareLink")
			if not ok then
				Toasts.show(Lang.msg(err), "error")
			end
		end,
	})

	-- group gift
	local group = Theme.panel({ Size = UDim2.new(1, -20, 0, 150), Position = UDim2.fromOffset(10, 204), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, Parent = body })
	Theme.text({ Text = "🐶", Stroke = false, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(14, 14), Parent = group })
	Theme.text({ Key = "group.desc", Args = { pet = { key = "pet." .. Config.GroupGiftPet } }, TextWrapped = true, Size = UDim2.new(1, -100, 0, 64), Position = UDim2.fromOffset(88, 14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 22, Parent = group })
	Theme.button({
		Key = "group.join",
		Color = Theme.Purple,
		Size = UDim2.fromOffset(260, 56),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 24,
		Parent = group,
		OnClick = function()
			pcall(function()
				(GroupService :: any):PromptJoinAsync(Config.GroupId)
			end)
			local ok, res = Net.request("ClaimGroupGift")
			Toasts.show(Lang.msg(res), if ok then "success" else "error")
		end,
	})

	local function refresh()
		local s = Net.state
		local social = s and s.social
		count.Text = Lang.t("invite.count", { n = if social then social.referralRewards else 0, max = Config.ReferralLifetimeCap })
		group.Visible = Config.GroupId ~= 0 and social ~= nil and not social.groupGiftClaimed
	end
	w.onOpen = refresh
	Net.Changed:Connect(function(kind)
		if kind == "full" and Windows.isOpen("Invite") then
			refresh()
		end
	end)
end

return InviteWindow
