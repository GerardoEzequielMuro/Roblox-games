--!strict
-- The lobby HUD: profile chip (level, league), coins, live event chip, the menu, the big
-- PLAY button with the auto-queue toggle, the starter offer, the Power Core widget and the
-- panel shown while you wait at a table. Hidden while a match is on screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local TableViews = require(script.Parent.Parent.Arena.TableViews)

local Hud = {}

-- Touch layout: the HUD scale on a phone is ~0.75, so every tappable piece is sized for
-- >= 44 px real (58+ design px) and the pieces are rearranged to stay clear of the thumbstick
-- (bottom left) and the jump button (bottom right): the menu moves to the top centre, the
-- goals under the profile, the Power Core below the currencies. Holder positions are real
-- px (only sizes are scaled), so the y offsets below are real px.
local T = Root.isTouch
local function pick(pc: any, touch: any): any
	if T then
		return touch
	end
	return pc
end
local TAP = 62 -- design px that land at ~44 px real at the lowest usual phone scale

local player = Players.LocalPlayer
local root = Theme.new("Frame", { Name = "LobbyHud", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = Root.gui }) :: Frame
Hud.root = root
Hud.buttons = {} :: { [string]: TextButton }
Hud.badges = {} :: { [string]: Frame }
Hud.onCoreTap = nil :: (() -> ())?
Hud.liveEvent = nil :: { [string]: any }?

local function setting(key: string, value: any)
	task.spawn(function()
		local ok, err = Net.request("SetSetting", { key = key, value = value })
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end)
end
Hud.setting = setting

---------------------------------------------------------------------------
-- Profile chip
---------------------------------------------------------------------------
local profile = Theme.panel({ Name = "Profile", Size = UDim2.fromOffset(250, 62), Position = UDim2.new(0, 8, 0, 6), Corner = 16, Parent = root })
Root.mount(profile, root)
local avatar = Theme.new("ImageLabel", { Name = "Avatar", Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = Theme.Panel2, Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", math.max(1, player.UserId)), Parent = profile }, { Theme.corner(24), Theme.stroke(2, Theme.Cyan) })
local levelBadge = Theme.new("Frame", { Name = "Level", Size = pick(UDim2.fromOffset(26, 20), UDim2.fromOffset(30, 22)), Position = pick(UDim2.fromOffset(34, 40), UDim2.fromOffset(32, 40)), BackgroundColor3 = Theme.Yellow, ZIndex = 3, Parent = profile }, { Theme.corner(8), Theme.stroke(2) })
local levelText = Theme.text({ Text = "1", Size = UDim2.fromScale(1, 1), MaxTextSize = pick(15, 16), MinTextSize = pick(9, 13), ZIndex = 4, Parent = levelBadge })
local nameText = Theme.text({ Name = "Name", Text = player.DisplayName, Size = pick(UDim2.fromOffset(176, 20), UDim2.fromOffset(176, 22)), Position = pick(UDim2.fromOffset(64, 5), UDim2.fromOffset(64, 2)), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = pick(18, 19), Parent = profile })
local leagueText = Theme.text({ Name = "League", Text = "", Size = pick(UDim2.fromOffset(176, 16), UDim2.fromOffset(180, 20)), Position = pick(UDim2.fromOffset(64, 25), UDim2.fromOffset(64, 24)), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = pick(14, 16), MinTextSize = pick(9, 13), TextColor3 = Theme.Dim, Parent = profile })
local xpBack = Theme.new("Frame", { Name = "Xp", Size = UDim2.fromOffset(176, 10), Position = pick(UDim2.fromOffset(64, 45), UDim2.fromOffset(64, 48)), BackgroundColor3 = Theme.Ink, Parent = profile }, { Theme.corner(5) })
local xpFill = Theme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Cyan, Parent = xpBack }, { Theme.corner(5) }) :: Frame
local _unused = { avatar, nameText }

---------------------------------------------------------------------------
-- Currencies + event chip (top right)
---------------------------------------------------------------------------
local top = Theme.new("Frame", { Name = "Top", Size = pick(UDim2.fromOffset(330, 40), UDim2.fromOffset(340, 66)), Position = UDim2.new(1, -8, 0, 6), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, Parent = root }, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) }) :: Frame
Root.mount(top, root)
local _, trophyValue = Theme.pill({ Name = "Trophies", Icon = "🏆", Color = Theme.Pink, Size = pick(UDim2.fromOffset(124, 38), UDim2.fromOffset(112, 66)), LayoutOrder = 1, Parent = top })
local coinPill, coinValue = Theme.pill({ Name = "Coins", Icon = "🪙", Color = Theme.Yellow, Size = pick(UDim2.fromOffset(160, 38), UDim2.fromOffset(220, 66)), LayoutOrder = 2, RightPad = pick(0, 74), Parent = top })
Hud.coinPill = coinPill
Theme.button({ Name = "Plus", Text = "+", Color = Theme.Green, Size = pick(UDim2.fromOffset(30, 30), UDim2.fromOffset(TAP, TAP)), Position = UDim2.new(1, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Corner = pick(15, 31), TextSize = pick(22, 36), KeepSize = true, Parent = coinPill, OnClick = function()
	Windows.open("Shop")
end })

local eventChip = Theme.panel({ Name = "Event", Size = pick(UDim2.fromOffset(250, 32), UDim2.fromOffset(270, 34)), Position = pick(UDim2.new(1, -8, 0, 50), UDim2.new(1, -8, 0, 60)), AnchorPoint = Vector2.new(1, 0), Corner = 16, Visible = false, Parent = root })
local eventHolder = Root.mount(eventChip, root)
local eventText = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxTextSize = pick(16, 17), MinTextSize = pick(9, 13), Parent = eventChip })

-- next goals: trophies to the next league and points to the next season tier
local goalChip = Theme.panel({ Name = "Goals", Size = pick(UDim2.fromOffset(250, 46), UDim2.fromOffset(270, 54)), Position = pick(UDim2.new(1, -8, 0, 86), UDim2.new(0, 8, 0, 60)), AnchorPoint = pick(Vector2.new(1, 0), Vector2.zero), Corner = 14, Visible = false, Parent = root })
local goalHolder = Root.mount(goalChip, root)
local goalLeague = Theme.text({ Name = "League", Text = "", Size = UDim2.new(1, -16, 0, pick(19, 23)), Position = UDim2.fromOffset(8, pick(3, 2)), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = pick(14, 16), MinTextSize = pick(9, 13), TextColor3 = Theme.Dim, Parent = goalChip })
local goalSeason = Theme.text({ Name = "Season", Text = "", Size = UDim2.new(1, -16, 0, pick(19, 23)), Position = UDim2.fromOffset(8, pick(24, 28)), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = pick(14, 16), MinTextSize = pick(9, 13), TextColor3 = Theme.Dim, Parent = goalChip })

---------------------------------------------------------------------------
-- Menu (left)
---------------------------------------------------------------------------
local menu = Theme.new("Frame", { Name = "Menu", Size = pick(UDim2.fromOffset(140, 276), UDim2.fromOffset(306, 138)), Position = pick(UDim2.new(0, 8, 0, 76), UDim2.new(0.29, 0, 0, 6)), AnchorPoint = Vector2.zero, BackgroundTransparency = 1, Parent = root }) :: Frame
Root.mount(menu, root)
Theme.new("UIGridLayout", { CellSize = pick(UDim2.fromOffset(64, 62), UDim2.fromOffset(72, 66)), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
local MENU: { { any } } = {
	{ "Shop", "🛒", Theme.Green },
	{ "Season", "🏅", Theme.Blue },
	{ "Locker", "🎨", Theme.Purple },
	{ "Rewards", "🎁", Theme.Pink },
	{ "Quests", "📜", Theme.Orange },
	{ "Ranking", "🏆", Theme.Yellow },
	{ "Invite", "🤝", Theme.Cyan },
	{ "Settings", "⚙️", Theme.Grey },
}
for i, m in MENU do
	local name, icon, color = m[1] :: string, m[2] :: string, m[3] :: Color3
	local b = Theme.new("TextButton", { Name = name, BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", LayoutOrder = i, Parent = menu }, {
		Theme.corner(14),
		Theme.stroke(3),
		Theme.new("UIGradient", { Color = Theme.buttonFace(color), Rotation = 90 }),
	}) :: TextButton
	Theme.gloss(b, 14)
	Theme.icon({ Icon = icon, Size = UDim2.new(1, 0, 0, pick(34, 32)), Position = UDim2.fromOffset(0, 3), Parent = b })
	Theme.text({ Key = "menu." .. name, Size = UDim2.new(1, -4, 0, pick(17, 20)), Position = UDim2.new(0, 2, 1, pick(-24, -26)), MaxTextSize = pick(13, 16), MinTextSize = pick(9, 12), Parent = b })
	b.Activated:Connect(function()
		Theme.play("click", 0.35)
		Windows.toggle(name)
	end)
	Hud.buttons[name] = b
	Hud.badges[name] = Theme.badge(b)
end

---------------------------------------------------------------------------
-- PLAY + auto-queue (bottom centre)
---------------------------------------------------------------------------
local playBar = Theme.new("Frame", { Name = "PlayBar", Size = pick(UDim2.fromOffset(520, 92), UDim2.fromOffset(540, 92)), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Parent = root }) :: Frame
Root.mount(playBar, root)
local playButton = Theme.button({ Name = "Play", Key = "hud.play", Prefix = "▶ ", Title = true, Color = Theme.Green, Size = UDim2.fromOffset(300, 84), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), TextSize = 50, Corner = 24, Parent = playBar, OnClick = function()
	Windows.toggle("Play")
end })
Hud.buttons.Play = playButton
local playTip = Theme.panel({ Name = "PlayTip", Size = UDim2.fromOffset(300, 34), Position = UDim2.new(0.5, 0, 0, -32), AnchorPoint = Vector2.new(0.5, 0), Corner = 14, StrokeColor = Theme.Yellow, Visible = false, Parent = playBar })
Theme.text({ Key = "tut.first_match", Prefix = "👇 ", Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), MaxTextSize = pick(18, 19), TextColor3 = Theme.Yellow, Parent = playTip })
local autoQueue = Theme.button({ Name = "AutoQueue", Text = "", Color = Theme.Grey, Size = pick(UDim2.fromOffset(100, 56), UDim2.fromOffset(112, 66)), Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = pick(15, 17), KeepSize = true, Parent = playBar })
Hud.buttons.AutoQueue = autoQueue
autoQueue.Activated:Connect(function()
	Theme.play("click", 0.35)
	setting("autoQueue", not (Net.setting("autoQueue") == true))
end)

-- starter pack offer
local starter = Theme.button({ Name = "Starter", Text = "", Color = Theme.Pink, Size = pick(UDim2.fromOffset(100, 56), UDim2.fromOffset(112, 66)), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextSize = pick(14, 16), KeepSize = true, Parent = playBar, OnClick = function()
	Windows.open("Shop")
end })
starter.Visible = false

---------------------------------------------------------------------------
-- Waiting at a table
---------------------------------------------------------------------------
local seated = Theme.panel({ Name = "Seated", Size = pick(UDim2.fromOffset(560, 116), UDim2.fromOffset(600, 140)), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), Corner = 20, StrokeThickness = 4, Visible = false, Parent = root })
Root.mount(seated, root)
local seatedTitle = Theme.text({ Name = "Title", Text = "", Title = true, Size = UDim2.new(1, -170, 0, 32), Position = UDim2.fromOffset(14, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 28, Parent = seated })
local seatedLine = Theme.text({ Name = "Line", Text = "", Size = UDim2.new(1, -170, 0, 22), Position = UDim2.fromOffset(14, 42), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, TextColor3 = Theme.Dim, Parent = seated })
Theme.button({ Name = "LeaveTable", Key = "match.leave", Prefix = "🚪 ", Color = Theme.Red, Size = pick(UDim2.fromOffset(140, 44), UDim2.fromOffset(150, TAP)), Position = UDim2.new(1, -12, 0, 10), AnchorPoint = Vector2.new(1, 0), TextSize = 19, KeepSize = true, Parent = seated, OnClick = function()
	task.spawn(Net.request, "LeaveTable")
end })
Theme.button({ Name = "InviteTable", Key = "invite.friends", Prefix = "👥 ", Icon = "group", Color = Theme.Blue, Size = pick(UDim2.fromOffset(140, 40), UDim2.fromOffset(150, TAP)), Position = pick(UDim2.new(1, -12, 0, 60), UDim2.new(1, -12, 0, 72)), AnchorPoint = Vector2.new(1, 0), TextSize = pick(15, 17), KeepSize = true, Parent = seated, OnClick = function()
	task.spawn(function()
		pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.LaunchData = Referral.launchData(player.UserId)
			game:GetService("SocialService"):PromptGameInvite(player, options)
		end)
	end)
end })
local hostRow = Theme.new("Frame", { Name = "Host", Size = pick(UDim2.new(1, -170, 0, 40), UDim2.new(1, -170, 0, TAP)), Position = pick(UDim2.fromOffset(12, 68), UDim2.fromOffset(12, 74)), BackgroundTransparency = 1, Parent = seated }, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) }) :: Frame
local codeText = Theme.text({ Name = "Code", Text = "", Title = true, Size = pick(UDim2.fromOffset(104, 36), UDim2.fromOffset(100, 40)), MaxTextSize = 24, TextColor3 = Theme.Yellow, LayoutOrder = 1, Parent = hostRow })
local modeButton = Theme.button({ Name = "Mode", Text = "", Color = Theme.Blue, Size = pick(UDim2.fromOffset(112, 38), UDim2.fromOffset(124, TAP)), TextSize = pick(17, 18), KeepSize = true, LayoutOrder = 2, Parent = hostRow })
local fillButton = Theme.button({ Name = "Fill", Text = "", Color = Theme.Grey, Size = pick(UDim2.fromOffset(76, 38), UDim2.fromOffset(80, TAP)), TextSize = pick(16, 17), KeepSize = true, LayoutOrder = 3, Parent = hostRow })
local startButton = Theme.button({ Name = "Start", Key = "table.start", Prefix = "▶ ", Color = Theme.Green, Size = pick(UDim2.fromOffset(84, 38), UDim2.fromOffset(92, TAP)), TextSize = pick(16, 17), KeepSize = true, LayoutOrder = 4, Parent = hostRow, OnClick = function()
	task.spawn(function()
		local ok, err = Net.request("StartPrivate")
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end)
end })
modeButton.Activated:Connect(function()
	local t = Net.get("table")
	if type(t) ~= "table" then
		return
	end
	local i = 1
	for k, m in Config.Modes do
		if m.id == t.mode then
			i = k
		end
	end
	local nextMode = Config.Modes[i % #Config.Modes + 1].id
	task.spawn(function()
		local ok, err = Net.request("PrivateOptions", { mode = nextMode })
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end)
end)
fillButton.Activated:Connect(function()
	local t = Net.get("table")
	if type(t) == "table" then
		task.spawn(Net.request, "PrivateOptions", { fill = not t.fill })
	end
end)

---------------------------------------------------------------------------
-- Power Core widget (right, only near the core)
---------------------------------------------------------------------------
local core = Theme.panel({ Name = "Core", Size = pick(UDim2.fromOffset(200, 168), UDim2.fromOffset(224, 200)), Position = pick(UDim2.new(1, -8, 0.5, -10), UDim2.new(1, -8, 0, 92)), AnchorPoint = pick(Vector2.new(1, 0.5), Vector2.new(1, 0)), Corner = 18, StrokeColor = Theme.Cyan, Visible = false, Parent = root })
local coreHolder = Root.mount(core, root)
Theme.text({ Key = "core.title", Prefix = "🔋 ", Title = true, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 6), MaxTextSize = 20, TextColor3 = Theme.Cyan, Parent = core })
local coreBack = Theme.new("Frame", { Name = "Bar", Size = UDim2.new(1, -24, 0, pick(16, 20)), Position = UDim2.fromOffset(12, 34), BackgroundColor3 = Theme.Ink, Parent = core }, { Theme.corner(8) })
local coreFill = Theme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Cyan, Parent = coreBack }, { Theme.corner(8) }) :: Frame
local coreText = Theme.text({ Name = "Count", Text = "0/25", Size = UDim2.fromScale(1, 1), MaxTextSize = pick(13, 16), MinTextSize = pick(9, 13), ZIndex = 3, Parent = coreBack })
local tapButton = Theme.button({ Name = "Tap", Key = "core.tap", Prefix = "⚡ ", Icon = "bolt", Title = true, Color = Theme.Cyan, Size = UDim2.new(1, -24, 0, pick(56, TAP)), Position = pick(UDim2.fromOffset(12, 56), UDim2.fromOffset(12, 60)), TextSize = 30, Corner = 16, KeepSize = true, Parent = core })
tapButton.Activated:Connect(function()
	if Hud.onCoreTap then
		Hud.onCoreTap()
	end
end)
Hud.buttons.CoreTap = tapButton
local autoCharge = Theme.button({ Name = "AutoCharge", Text = "", Color = Theme.Grey, Size = UDim2.new(1, -24, 0, pick(38, TAP)), Position = pick(UDim2.fromOffset(12, 120), UDim2.fromOffset(12, 124)), TextSize = pick(16, 17), KeepSize = true, Parent = core })
Hud.buttons.AutoCharge = autoCharge
autoCharge.Activated:Connect(function()
	Theme.play("click", 0.35)
	local c = Net.get("core")
	if type(c) == "table" and not c.autoUnlocked then
		Toasts.show(Lang.t("msg.auto_locked", { level = c.autoLevel }), "info")
		return
	end
	setting("autoCharge", not (Net.setting("autoCharge") == true))
end)

function Hud.setCoreVisible(near: boolean)
	core.Visible = near and root.Visible
end

function Hud.coreProgress(taps: number, need: number)
	coreFill.Size = UDim2.fromScale(math.clamp(taps / need, 0, 1), 1)
	coreText.Text = taps .. "/" .. need
end

-- Touch: the stacked pieces follow the HUD scale (holder positions are real px), so on a big
-- tablet the goals chip still starts below the profile chip and the core below the chips.
if T then
	local function stack()
		local s = Root.scale
		local below = 6 + math.ceil(66 * s) + 4
		goalHolder.Position = UDim2.new(0, 8, 0, below)
		eventHolder.Position = UDim2.new(1, -8, 0, below)
		coreHolder.Position = UDim2.new(1, -8, 0, below + math.ceil(34 * s) + 4)
	end
	Root.Changed:Connect(stack)
	stack()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local shownCoins = -1
local function refresh()
	local s = Net.state
	if not s then
		return
	end
	levelText.Text = tostring(s.level)
	xpFill.Size = UDim2.fromScale(math.clamp(s.xp / math.max(1, s.xpNeed), 0, 1), 1)
	local icon = ""
	for _, l in Config.Leagues do
		if l.id == s.league then
			icon = l.icon
		end
	end
	leagueText.Text = icon .. " " .. Lang.t("league." .. s.league) .. (if s.streak > 1 then "   🔥" .. s.streak else "")
	trophyValue.Text = Format.abbrev(s.trophies)
	-- next goals (always close and visible)
	local nextLeague = s.nextLeague
	local season = s.season
	goalLeague.Text = if type(nextLeague) == "table" then "🏆 " .. Lang.t("goal.league", { n = math.max(0, nextLeague.trophies - s.trophies), league = Lang.t("league." .. nextLeague.id) }) else "👑 " .. Lang.t("goal.top_league")
	if type(season) == "table" then
		goalSeason.Text = if season.tier >= Config.SeasonPass.tiers then "🏅 " .. Lang.t("season.maxed") else "🏅 " .. Lang.t("goal.season", { n = season.need - season.into, tier = season.tier + 1 })
	else
		goalSeason.Text = ""
	end
	goalChip.Visible = true
	if shownCoins ~= s.coins then
		if shownCoins >= 0 and s.coins > shownCoins then
			Theme.pop(coinPill, 1.12)
		end
		shownCoins = s.coins
		coinValue.Text = Format.abbrev(s.coins)
	end
	-- auto toggles
	local q = s.settings.autoQueue == true
	Theme.setButton(autoQueue, "🔁 " .. Lang.t("hud.auto_queue") .. "\n" .. (if q then "ON" else "OFF"), if q then Theme.Green else Theme.Grey)
	local c = s.core
	if type(c) == "table" then
		local on = s.settings.autoCharge == true and c.autoUnlocked
		Theme.setButton(autoCharge, if c.autoUnlocked then ("🤖 " .. Lang.t("core.auto") .. ": " .. (if on then "ON" else "OFF")) else ("🔒 " .. Lang.t("core.auto_locked", { level = c.autoLevel })), if on then Theme.Green else Theme.Grey)
		Hud.coreProgress(c.taps, c.need)
	end
	-- first match nudge
	playTip.Visible = s.tutorialDone == false
	-- starter offer
	local st = s.starter
	starter.Visible = type(st) == "table" and st.available == true
	-- badges
	local daily = s.dailyState
	local giftReady = false
	for i, g in Config.Gifts do
		if s.sessionElapsed + (os.clock() - Net.receivedAt) >= g.minutes * 60 and not table.find(s.giftsClaimed, i) then
			giftReady = true
		end
	end
	local seasonNow = s.season
	Hud.badges.Season.Visible = type(seasonNow) == "table" and (seasonNow.claimable or 0) > 0
	Hud.badges.Rewards.Visible = (type(daily) == "table" and daily.canClaim == true) or giftReady
	local quests = s.quests
	local questReady = false
	if type(quests) == "table" then
		for i, quest in quests.list do
			if quests.progress[i] >= quest.target and not quests.claimed[i] then
				questReady = true
			end
		end
	end
	Hud.badges.Quests.Visible = questReady
	-- seated panel
	local t = s.table
	local view = if type(t) == "table" then TableViews.byId[t.id] else nil
	local waiting = view ~= nil and not view.playing
	seated.Visible = waiting
	playBar.Visible = not waiting
	if waiting and view and type(t) == "table" then
		local mode = Config.ModeById[view.mode]
		seatedTitle.Text = mode.icon .. " " .. Lang.t("mode." .. view.mode .. ".name")
		local count = 0
		for _ in view.lobbySeats do
			count += 1
		end
		if view.status == "countdown" then
			seatedLine.Text = Lang.t("table.starting", { n = math.max(0, math.ceil(view.countdownEnds - Workspace:GetServerTimeNow())) }) .. "  ·  " .. Lang.t("table.players", { n = count, max = view.max })
		elseif t.code then
			seatedLine.Text = Lang.t("table.players", { n = count, max = view.max }) .. "  ·  " .. Lang.t(if t.host then "table.host_hint" else "table.wait_host")
		else
			seatedLine.Text = Lang.t("table.players", { n = count, max = view.max })
		end
		hostRow.Visible = t.code ~= nil
		if t.code then
			codeText.Text = "🔑 " .. t.code
			modeButton.Visible = t.host == true
			fillButton.Visible = t.host == true
			startButton.Visible = t.host == true and view.status == "open"
			Theme.setButton(modeButton, mode.icon .. " " .. Lang.t("mode." .. view.mode .. ".name"), Theme.Blue)
			Theme.setButton(fillButton, "🤖 " .. (if t.fill then "ON" else "OFF"), if t.fill then Theme.Green else Theme.Grey)
		end
	end
end
Hud.refresh = refresh

local function refreshEvent()
	local d = Hud.liveEvent
	if not d then
		eventChip.Visible = false
		return
	end
	local now = Net.serverTime()
	if d.current and d.current.endsAt > now then
		local def = Config.LiveEventDefs[d.current.id]
		eventChip.Visible = true
		eventText.Text = def.icon .. " " .. Lang.t("event." .. d.current.id) .. "  " .. Format.time(d.current.endsAt - now)
		eventText.TextColor3 = Theme.rgb(def.color)
	elseif d.nextAt and d.nextId then
		local def = Config.LiveEventDefs[d.nextId]
		eventChip.Visible = true
		eventText.Text = def.icon .. " " .. Lang.t("event.next", { event = Lang.t("event." .. d.nextId), time = Format.time(math.max(0, d.nextAt - now)) })
		eventText.TextColor3 = Theme.Dim
	else
		eventChip.Visible = false
	end
end

function Hud.setVisible(on: boolean)
	root.Visible = on
	if not on then
		core.Visible = false
	end
end

function Hud.init()
	Net.Changed:Connect(refresh)
	TableViews.Changed:Connect(function(id)
		local t = Net.get("table")
		if type(t) == "table" and t.id == id then
			refresh()
		end
	end)
	Net.event("LiveEventUpdate").OnClientEvent:Connect(function(d)
		Hud.liveEvent = d
		refreshEvent()
		if type(d.started) == "table" then
			for _, id in d.started do
				Toasts.show(Config.LiveEventDefs[id].icon .. " " .. Lang.t("event.started", { event = Lang.t("event." .. id) }), "success", 4)
			end
		end
	end)
	Net.event("LevelUp").OnClientEvent:Connect(function(d)
		Toasts.show("⬆ " .. Lang.t("toast.level_up", { n = d.level, coins = d.coins }), "success", 4)
		Theme.play("heal", 0.5, 1.4)
		Theme.pop(profile, 1.15)
	end)
	Net.event("Unlock").OnClientEvent:Connect(function(id)
		local item = Config.CosmeticById[id]
		if item then
			Toasts.show("🔓 " .. Lang.t("toast.unlocked", { item = item.icon .. " " .. Lang.t("cos." .. id) }), "success", 4)
		end
	end)
	-- once a second: timers on the chips
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		if not root.Visible then
			return
		end
		refreshEvent()
		local s = Net.state
		if s then
			local st = s.starter
			if type(st) == "table" and st.available then
				Theme.setButton(starter, "🎁 " .. Lang.t("hud.starter") .. "\n" .. Format.time(math.max(0, st.endsAt - Net.serverTime())), Theme.Pink)
			end
			if seated.Visible then
				refresh()
			end
		end
	end)
	refresh()
end

return Hud
