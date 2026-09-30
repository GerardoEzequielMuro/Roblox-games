--!strict
-- One-at-a-time centered cards: offline earnings, Starter Pack offer, notification opt-in.
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Toasts = require(script.Parent.Toasts)
local Hud = require(script.Parent.Hud)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)
local Ads = require(script.Parent.Parent.Ads)

local Popups = {}

type ButtonSpec = { text: string, color: Color3, onClick: () -> () }
type Card = { frame: Frame, holder: Frame, close: () -> () }

local current: Card? = nil

-- A centered card with an icon, title, rich body text and up to 2 buttons. odds: a line of
-- numeric odds shown on a plate above the buttons (offers that contain a random item).
function Popups.card(icon: string, title: string, body: string, buttons: { ButtonSpec }, extra: ((Frame) -> ())?, odds: string?): Card
	if current then
		current.close()
	end
	local frame = Theme.panel({
		Name = "Popup",
		Size = UDim2.fromOffset(520, 320),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 60,
		Corner = 24,
		StrokeThickness = 4,
		Parent = Root.gui,
	})
	local holder = Root.mount(frame)
	holder.ZIndex = 60
	Theme.shadow(frame, 24)
	Theme.pop(frame, 0.7)
	local card: Card
	local function close()
		if current == card then
			current = nil
		end
		holder:Destroy()
	end
	card = { frame = frame, holder = holder, close = close }
	current = card
	Theme.icon(icon, { Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 61, Parent = frame })
	Theme.text({ Text = title, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 74), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 34, ZIndex = 61, Parent = frame })
	Theme.text({ Text = body, RichText = true, TextWrapped = true, Size = UDim2.new(1, -48, 0, if odds then 58 else 96), Position = UDim2.fromOffset(24, 118), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 24, ZIndex = 61, Parent = frame })
	if odds then
		local plate = Theme.new("Frame", { Name = "OddsPlate", Size = UDim2.new(1, -48, 0, 50), Position = UDim2.fromOffset(24, 180), BackgroundColor3 = Theme.PaperDark, ZIndex = 61, Parent = frame }, { Theme.corner(10), Theme.stroke(2, Theme.lighten(Theme.Ink, 0.5)) })
		local t = Theme.text({ Name = "Odds", Text = odds, TextWrapped = true, Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 17, Parent = plate })
		t.ZIndex = 62
		t.AutoLocalize = false
	end
	local row = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -32, 0, 64), Position = UDim2.new(0, 16, 1, -80), ZIndex = 61, Parent = frame }, {
		Theme.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	for i, spec in buttons do
		local b = Theme.button({
			Text = spec.text,
			Color = spec.color,
			Size = UDim2.fromOffset(if #buttons > 1 then 220 else 280, 60),
			LayoutOrder = i,
			TextSize = 26,
			Parent = row,
			OnClick = function()
				spec.onClick()
			end,
		})
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 62
			end
		end
		b.ZIndex = 62
	end
	local x = Theme.button({ Text = "X", Color = Theme.Red, Size = UDim2.fromOffset(54, 54), Position = UDim2.new(1, 14, 0, -14), AnchorPoint = Vector2.new(1, 0), Corner = 27, Parent = frame, OnClick = close })
	x.ZIndex = 63
	for _, d in x:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 64
		end
	end
	if extra then
		extra(frame)
	end
	Theme.pop(frame, 0.7)
	return card
end

---------------------------------------------------------------------------
-- Offline earnings
---------------------------------------------------------------------------
local offlineShownFor = 0
local function showOffline()
	local s = Net.state
	local o = s and s.offline
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
				if current then
					current.close()
				end
			end,
		},
	}
	if Ads.canShow("AdOffline") then
		table.insert(buttons, {
			text = "📺 " .. Lang.t("ads.offline_button"),
			color = Theme.Orange,
			onClick = function()
				Ads.watch("AdOffline")
				if current then
					current.close()
				end
			end,
		})
	end
	Popups.card("💤", Lang.t("offline.title"), Lang.t("offline.body", { time = Format.time(o.seconds), n = "<b>" .. Format.abbrev(o.pending) .. "</b>" }), buttons)
end

---------------------------------------------------------------------------
-- Starter Pack (first 24 h): popup after the 3rd hatch of the session, then a HUD button
---------------------------------------------------------------------------
local function showStarter()
	local s = Net.state
	local st = s and s.starter
	if not s or not st or not st.available then
		return
	end
	local pct = math.floor((1 - st.price / st.fullPrice) * 100 + 0.5)
	local body = string.format(
		"%s\n<s>R$ %d</s>  <b>R$ %d</b>  ·  %s",
		Lang.t("starter.body", { gems = Config.StarterPack.gems, min = Config.StarterPack.luckMinutes }),
		st.fullPrice,
		st.price,
		Lang.t("starter.ends", { time = Format.time(st.endsAt - (s.serverTime + os.clock() - Net.receivedAt)) })
	)
	Popups.card("🎉", Lang.t("starter.title"), body, {
		{
			text = Lang.t("starter.buy") .. "  R$" .. st.price,
			color = Theme.Green,
			onClick = function()
				Purchase.product("StarterPack")
			end,
		},
	}, function(frame)
		local tag = Theme.new("Frame", { Size = UDim2.fromOffset(96, 44), Position = UDim2.fromOffset(-12, 16), Rotation = -10, BackgroundColor3 = Theme.Red, ZIndex = 63, Parent = frame }, { Theme.corner(12), Theme.stroke(3) })
		local t = Theme.text({ Text = Lang.t("starter.discount", { pct = pct }), ZIndex = 64, Parent = tag })
		t.ZIndex = 64
	end, Purchase.oddsText("StarterPack"))
end

function Popups.init()
	Hud.onStarterClick = showStarter

	local sessionStartHatched: number? = nil
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
		sessionStartHatched = sessionStartHatched or s.totalHatched
		if not starterShown and s.starter and s.starter.available and s.totalHatched - (sessionStartHatched :: number) >= Config.StarterPack.popupAfterHatches then
			starterShown = true
			task.delay(4, showStarter) -- after the hatch cinematic
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
		Popups.card("🔔", Lang.t("notif.title"), Lang.t("notif.body"), {
			{
				text = Lang.t("notif.yes"),
				color = Theme.Green,
				onClick = function()
					if current then
						current.close()
					end
					pcall(function()
						(ExperienceNotificationService :: any):PromptOptIn()
					end)
				end,
			},
			{
				text = Lang.t("notif.no"),
				color = Theme.Grey,
				onClick = function()
					if current then
						current.close()
					end
				end,
			},
		})
	end)
end

return Popups
