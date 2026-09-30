--!strict
-- Invite window (game invite + share link with "ref:<userId>" launch data, group gift) and
-- the one-at-a-time popup cards: offline mining, Starter Pack, notification opt-in.
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Hud = require(script.Parent.Hud)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)
local Ads = require(script.Parent.Parent.Ads)

local SocialWindows = {}

local player = Players.LocalPlayer

---------------------------------------------------------------------------
-- Popup cards
---------------------------------------------------------------------------
type ButtonSpec = { text: string, color: Color3, onClick: () -> () }
type Card = { frame: Frame, holder: Frame, close: () -> () }

local current: Card? = nil

function SocialWindows.card(icon: string, title: string, body: string, buttons: { ButtonSpec }, extra: ((Frame) -> ())?): Card
	if current then
		current.close()
	end
	local frame = Theme.panel({
		Name = "Popup",
		Size = UDim2.fromOffset(520, 320),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 60,
		Corner = 22,
		StrokeThickness = 4,
		Parent = Root.gui,
	})
	local holder = Root.mount(frame)
	holder.Name = "PopupHolder"
	holder.ZIndex = 60
	Theme.shadow(frame, 22)
	local card: Card
	local function close()
		if current == card then
			current = nil
		end
		holder:Destroy()
	end
	card = { frame = frame, holder = holder, close = close }
	current = card
	Theme.text({ Text = icon, Stroke = false, Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), Parent = frame })
	Theme.text({ Text = title, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 74), TextColor3 = Theme.Yellow, MaxTextSize = 34, Parent = frame })
	Theme.text({ Text = body, RichText = true, TextWrapped = true, Size = UDim2.new(1, -48, 0, 96), Position = UDim2.fromOffset(24, 118), MaxTextSize = 23, Parent = frame })
	local row = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -32, 0, 64), Position = UDim2.new(0, 16, 1, -80), Parent = frame }, {
		Theme.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	for i, spec in buttons do
		Theme.button({ Name = "Button" .. i, Text = spec.text, Color = spec.color, Size = UDim2.fromOffset(if #buttons > 1 then 220 else 300, 58), LayoutOrder = i, TextSize = 25, Parent = row, OnClick = spec.onClick })
	end
	Theme.button({ Name = "Close", Text = "X", Color = Theme.Red, Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, 14, 0, -14), AnchorPoint = Vector2.new(1, 0), Corner = 26, Parent = frame, OnClick = close })
	if extra then
		extra(frame)
	end
	Theme.pop(frame, 0.7)
	return card
end

function SocialWindows.closeCard()
	if current then
		current.close()
	end
end

local offlineShownFor = 0
local function showOffline()
	local s = Net.state
	local o = if s then s.offline else nil
	if not o or o.pending <= 0 or o.pending == offlineShownFor then
		return
	end
	offlineShownFor = o.pending
	local buttons: { ButtonSpec } = {
		{
			text = Lang.t("offline.claim"),
			color = Theme.Green,
			onClick = function()
				local ok, res = Net.request("ClaimOffline")
				Toasts.show(Lang.msg(res), if ok then "success" else "error")
				SocialWindows.closeCard()
			end,
		},
	}
	if Ads.canShow("AdOffline") then
		table.insert(buttons, {
			text = "📺 " .. Lang.t("ads.offline_button"),
			color = Theme.Orange,
			onClick = function()
				Ads.watch("AdOffline")
				SocialWindows.closeCard()
			end,
		})
	end
	SocialWindows.card("🛰️", Lang.t("offline.title"), Lang.t("offline.body", { time = Format.time(o.seconds), n = "<b>" .. Format.abbrev(o.pending) .. "</b>" }), buttons)
end

local function showStarter()
	local s = Net.state
	local st = if s then s.starter else nil
	if not s or not st or not st.available then
		return
	end
	local pct = math.floor((1 - st.price / st.fullPrice) * 100 + 0.5)
	local body = string.format(
		"%s\n<s>R$ %d</s>  <b>R$ %d</b>  ·  %s",
		Lang.t("product.StarterPack.desc", { crystals = Config.StarterPack.crystals, minutes = Config.StarterPack.boostMinutes, pet = Lang.pet(Config.StarterPack.pet) }),
		st.fullPrice,
		st.price,
		Lang.t("starter.ends", { time = Format.time(st.endsAt - (s.serverTime + os.clock() - Net.receivedAt)) })
	)
	SocialWindows.card("🎁", Lang.t("product.StarterPack.name"), body, {
		{
			text = Lang.t("starter.buy") .. "  R$ " .. st.price,
			color = Theme.Robux,
			onClick = function()
				Purchase.product("StarterPack")
			end,
		},
	}, function(frame)
		local tag = Theme.new("Frame", { Size = UDim2.fromOffset(96, 44), Position = UDim2.fromOffset(-12, 16), Rotation = -10, BackgroundColor3 = Theme.Red, Parent = frame }, { Theme.corner(12), Theme.stroke(3) })
		Theme.text({ Text = "-" .. pct .. "%", Parent = tag })
	end)
end

---------------------------------------------------------------------------
-- Invite window
---------------------------------------------------------------------------
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
		options.PromptMessage = Lang.t("invite.prompt", { n = Config.ReferralInviteeGift.amount })
		SocialService:PromptGameInvite(player, options)
	end)
	if not shown then
		Toasts.show(Lang.t("invite.unavailable"), "error")
	end
end

local function inviteWindow()
	local w = Windows.create("Invite", "💌", "win.invite", Theme.Pink, Vector2.new(600, 440))
	local body = w.body
	Theme.text({ Key = "invite.desc", Args = { n = Config.ReferralInviteeGift.amount }, TextWrapped = true, Size = UDim2.new(1, -20, 0, 84), Position = UDim2.fromOffset(10, 0), MaxTextSize = 23, Parent = body })
	local count = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 88), TextColor3 = Theme.Yellow, MaxTextSize = 20, Parent = body })
	local row = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 124), Parent = body }, {
		Theme.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	Theme.button({ Name = "InviteFriends", Key = "invite.button", Color = Theme.Green, Size = UDim2.fromOffset(250, 60), LayoutOrder = 1, TextSize = 24, Parent = row, OnClick = inviteFriends })
	Theme.button({ Name = "ShareLink", Key = "invite.share", Color = Theme.Blue, Size = UDim2.fromOffset(250, 60), LayoutOrder = 2, TextSize = 24, Parent = row, OnClick = function()
		local ok, err = Net.request("ShareLink")
		if not ok then
			Toasts.show(Lang.msg(err), "error")
		end
	end })
	local group = Theme.panel({ Name = "Group", Size = UDim2.new(1, -20, 0, 140), Position = UDim2.fromOffset(10, 204), BackgroundColor3 = Theme.PaperLight, Visible = false, Parent = body })
	Theme.text({ Text = "🛰️", Stroke = false, Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(12, 10), Parent = group })
	Theme.text({ Key = "group.desc", Args = { pet = { key = "pet." .. Config.GroupGiftPet } }, TextWrapped = true, Size = UDim2.new(1, -96, 0, 60), Position = UDim2.fromOffset(84, 10), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 21, Parent = group })
	Theme.button({ Name = "JoinGroup", Key = "group.join", Color = Theme.Purple, Size = UDim2.fromOffset(260, 52), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), TextSize = 22, Parent = group, OnClick = function()
		pcall(function()
			(GroupService :: any):PromptJoinAsync(Config.GroupId)
		end)
		local ok, res = Net.request("ClaimGroupGift")
		Toasts.show(Lang.msg(res), if ok then "success" else "error")
	end })
	local function refresh()
		local s = Net.state
		local social = if s then s.social else nil
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

function SocialWindows.init()
	inviteWindow()
	Hud.onStarterClick = showStarter

	local starterShown = false
	Net.Changed:Connect(function(kind)
		if kind ~= "full" then
			return
		end
		local s = Net.state
		if not s then
			return
		end
		showOffline()
		-- the Starter Pack offer pops once, after the tutorial is done
		if not starterShown and s.starter and s.starter.available and s.tutorial > #Config.Tutorial and s.playTime > 180 then
			starterShown = true
			task.delay(3, showStarter)
		end
	end)

	-- Notification opt-in, asked by the server after a big moment (first Legendary / rebirth)
	Net.event("AskNotifications").OnClientEvent:Connect(function()
		local ok, can = pcall(function()
			return (ExperienceNotificationService :: any):CanPromptOptInAsync()
		end)
		if not ok or not can then
			return
		end
		task.wait(3)
		SocialWindows.card("🔔", Lang.t("notif.title"), Lang.t("notif.body"), {
			{
				text = Lang.t("notif.yes"),
				color = Theme.Green,
				onClick = function()
					SocialWindows.closeCard()
					pcall(function()
						(ExperienceNotificationService :: any):PromptOptIn()
					end)
				end,
			},
			{ text = Lang.t("notif.no"), color = Theme.Grey, onClick = SocialWindows.closeCard },
		})
	end)
end

return SocialWindows
