--!strict
-- Always-on HUD, in the minimal style of tower games (see DESIGN.md, "HUD"):
--   top centre    : the run timer, big and thin (+ best time / "not ranked" under it)
--   right edge    : the tower progress bar with the head of every player (Progress.luau)
--   bottom left   : Menu + coins + wins. Menu opens the grid of panels (shop, store, rewards,
--                   settings, invite, share, group gift, starter pack); active power-ups sit over it
--   bottom centre : the level bar (stage N of 1,000) and under it the action buttons:
--                   portal / abilities when you have them, Skip Stage, Skip 10, Checkpoint, Lobby
-- On touch screens the corner block moves under the Roblox buttons (the thumbstick owns the
-- bottom left) and the actions become a column on the right, above the jump button.
local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Powerups = require(ReplicatedStorage.Shared.Powerups)
local LocalFx = require(script.Parent.Parent.World.LocalFx)
local RunTime = require(ReplicatedStorage.Shared.RunTime)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Progress = require(script.Parent.Progress)
local Lang = require(script.Parent.Parent.Lang)
local Toast = require(script.Parent.Toast)

local Hud = {}

local productPrice: { [number]: number } = {}

local function fetchPrice(id: number, onPrice: (number) -> ())
	if id == 0 then
		return
	end
	if productPrice[id] then
		onPrice(productPrice[id])
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
		end)
		if ok and info and info.PriceInRobux then
			productPrice[id] = info.PriceInRobux
			onPrice(info.PriceInRobux)
		end
	end)
end
Hud.fetchPrice = fetchPrice

-- Cached Robux price of a product (nil until fetched / when the id is 0).
function Hud.priceOf(id: number): number?
	return productPrice[id]
end

Hud.topScale = 1 -- scale of the top-centre HUD rows (EventBar follows it)

-- Skip n stages: free skip first, then Robux product, then (Studio only, id 0) dev skip.
function Hud.skip(n: number)
	local s = Net.state
	if Rules.skipTarget(Layout :: any, s.at or s.stage or 0, n, s.base == true) == nil then
		Toast.show(Lang.t("toast.at_top"), "info")
		return
	end
	if n == 1 and (s.freeSkips or 0) > 0 then
		local ok, msg = Net.request("UseFreeSkip")
		if not ok and msg then
			Toast.show(msg, "error")
		end
		return
	end
	local id = if n == 10 then Config.Products.Skip10 else Config.Products.SkipStage
	if id ~= 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	elseif s.studio and Config.StudioFreeSkips then
		local ok, msg = Net.request("DevSkip", { n = n })
		if ok then
			Toast.show(Lang.t("toast.studio_skip"), "info")
		elseif msg then
			Toast.show(msg, "error")
		end
	end
end

-- "Minimal action" look: translucent dark glass, thin white outline, white text.
local GLASS = Color3.fromRGB(24, 28, 44)
local function glass(parent: Instance, size: UDim2, pos: UDim2): Frame
	local f = Kit.frame(parent, size, pos, GLASS)
	f.BackgroundTransparency = 0.4
	Kit.corner(f, 14)
	local st = Kit.stroke(f, Color3.new(1, 1, 1), 1.5)
	st.Transparency = 0.6
	return f
end

-- Counter in the bottom-left corner: icon + number on glass.
local function counter(parent: Instance, x: number, w: number): (TextLabel, Frame)
	local f = glass(parent, UDim2.fromOffset(w, 44), UDim2.fromOffset(x, 3))
	local icon = Kit.frame(f, UDim2.fromOffset(32, 32), UDim2.fromOffset(6, 6), nil)
	local label = Kit.bold(f, "0", UDim2.new(1, -52, 1, -10), UDim2.fromOffset(44, 5), Kit.C.white, nil, 26)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label, icon
end

local MENU_CELL = 80
local MENU_GAP = 12
local MENU_COLS = 3

local function menuButton(parent: Instance, order: number, name: string, text: string, icon: string, color: Color3, onClick: () -> ()): (TextButton, Frame)
	local b = Kit.button(parent, "", UDim2.fromOffset(MENU_CELL, MENU_CELL), UDim2.new(), color, onClick)
	b.Name = name
	b.LayoutOrder = order
	Kit.text(b, icon, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 2), Kit.C.white, nil, 38)
	Kit.bold(b, text, UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 1, -24), Kit.C.white, nil, 18)
	local badge = Kit.frame(b, UDim2.fromOffset(24, 24), UDim2.new(1, -10, 0, -10), Kit.C.red)
	Kit.corner(badge, 12)
	Kit.stroke(badge, Kit.C.white, 2)
	Kit.bold(badge, "!", UDim2.fromScale(1, 1), UDim2.new(), Kit.C.white, nil, 18)
	badge.Visible = false
	badge.ZIndex = 3
	return b, badge
end

local function invite()
	local player = Players.LocalPlayer
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not ok or not can then
		Toast.show(Lang.t("toast.invite_unavailable"), "info")
		return
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.LaunchData = Referral.make(player.UserId)
	options.PromptMessage = Lang.t("invite.prompt")
	local shown = pcall(function()
		SocialService:PromptGameInvite(player, options)
	end)
	if not shown then
		Toast.show(Lang.t("toast.invite_unavailable"), "info")
	end
end

local function joinGroup()
	task.spawn(function()
		pcall(function()
			GroupService:PromptJoinAsync(Config.GroupId)
		end)
		local ok, msg = Net.request("ClaimGroupGift")
		if msg then
			Toast.show(msg, if ok then "success" else "info")
		end
	end)
end

-- All sizes are design pixels; each region is scaled as one unit by Kit.
Hud.STATS_TOP = 4 -- design px from the top of the safe area
Hud.STATS_W = 300
Hud.STATS_H = 70
Hud.EVENT_TOP = Hud.STATS_TOP + Hud.STATS_H + 4 -- where the live-event pill goes
Hud.eventBarVisible = false
local relayout: () -> () = function() end
function Hud.setEventBarVisible(v: boolean)
	if Hud.eventBarVisible ~= v then
		Hud.eventBarVisible = v
		relayout()
	end
end

function Hud.init()
	local stats = Kit.region("Stats", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, Hud.STATS_TOP), Vector2.new(Hud.STATS_W, Hud.STATS_H))
	-- run timer (P0-2): big thin digits; grey + "not ranked" once the run used help
	local timer = Kit.frame(stats, UDim2.fromScale(1, 1), UDim2.new(), nil)
	timer.Name = "RunTimer"
	local timerLabel = Kit.text(timer, "00:00.000", UDim2.new(1, 0, 0, 50), UDim2.new(), Kit.C.white, nil, 48)
	timerLabel.Name = "Time"
	timerLabel.Font = Enum.Font.Gotham
	local timerStroke = Kit.stroke(timerLabel, Kit.C.ink, 1.5)
	timerStroke.Transparency = 0.35
	local timerNote = Kit.bold(timer, "", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 50), Color3.fromRGB(240, 240, 255), nil, 15)
	timerNote.Name = "Note"

	-- bottom-left corner: Menu + coins + wins
	local CORNER_W = 342
	local corner = Kit.region("Corner", Vector2.new(0, 1), UDim2.new(0, 12, 1, -12), Vector2.new(CORNER_W, 50))
	local menuOpen = false
	local left: Frame
	local function setMenu(open: boolean)
		menuOpen = open
		left.Visible = open
	end
	local menuBtn = Kit.button(corner, "@hud.menu", UDim2.fromOffset(116, 50), UDim2.new(), Color3.fromRGB(62, 68, 96), function()
		setMenu(not menuOpen)
	end, nil, 26)
	menuBtn.Name = "MenuButton"
	local menuBadge = Kit.frame(menuBtn, UDim2.fromOffset(24, 24), UDim2.new(1, -8, 0, -10), Kit.C.red)
	menuBadge.Name = "Badge"
	Kit.corner(menuBadge, 12)
	Kit.stroke(menuBadge, Kit.C.white, 2)
	Kit.bold(menuBadge, "!", UDim2.fromScale(1, 1), UDim2.new(), Kit.C.white, nil, 18)
	menuBadge.Visible = false
	menuBadge.ZIndex = 3
	local coinLabel, coinIcon = counter(corner, 124, 128)
	Kit.coin(coinIcon, 30, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local winsLabel, winsIcon = counter(corner, 258, 84)
	Kit.text(winsIcon, "🏆", UDim2.fromScale(1, 1), UDim2.new(), Kit.C.white, nil, 24)

	left = Kit.region("Menu", Vector2.new(0, 1), UDim2.new(0, 12, 1, -120), Vector2.new(MENU_COLS * MENU_CELL + (MENU_COLS - 1) * MENU_GAP, MENU_CELL))
	left.Visible = false
	Kit.panelChanged:Connect(function()
		if Kit.current() ~= nil then
			setMenu(false)
		end
	end)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(MENU_CELL, MENU_CELL)
	grid.CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = MENU_COLS
	grid.Parent = left
	local starterBtn = menuButton(left, 0, "Starter", "@hud.starter", "🎁", Kit.C.red, function()
		Kit.toggle("starter")
	end)
	local starterPulse = Instance.new("UIScale")
	starterPulse.Parent = starterBtn:FindFirstChildOfClass("TextLabel")
	TweenService:Create(starterPulse, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 }):Play()
	starterBtn.Visible = false
	menuButton(left, 1, "Shop", "@hud.shop", "🛍", Kit.C.pink, function()
		Kit.toggle("shop")
	end)
	menuButton(left, 2, "Store", "@hud.store", "💎", Kit.C.green, function()
		Kit.toggle("store")
	end)
	local _, rewardsBadge = menuButton(left, 3, "Rewards", "@hud.rewards", "🎁", Kit.C.orange, function()
		Kit.toggle("rewards")
	end)
	menuButton(left, 4, "Settings", "@hud.settings", "⚙", Kit.C.grey, function()
		Kit.toggle("settings")
	end)
	menuButton(left, 5, "Invite", "@hud.invite", "👋", Kit.C.blue, invite)
	menuButton(left, 6, "Share", "@hud.share", "🔗", Kit.C.purple, function()
		local ok, msg = Net.request("ShareLink")
		if not ok and msg then
			Toast.show(msg, "info")
		end
	end)
	local groupBtn = menuButton(left, 7, "Group", "@hud.group", "⭐", Kit.C.yellow, joinGroup)
	groupBtn.Visible = false

	-- action buttons: a row under the level bar (PC) or a column on the right (touch). Optional
	-- buttons (portal, abilities) join the ones that are always there.
	local ACT_W = 184
	local ROW_H = 56
	local ACT_GAP = 6
	local right = Kit.region("Actions", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -10), Vector2.new(ACT_W, ROW_H))
	local actList = Instance.new("UIListLayout")
	actList.SortOrder = Enum.SortOrder.LayoutOrder
	actList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	actList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actList.Padding = UDim.new(0, ACT_GAP)
	actList.Parent = right
	-- height of each button when the actions are a column
	local columnHeight: { [GuiObject]: number } = {}

	local portalBtn = Kit.button(right, "@hud.portal", UDim2.fromOffset(ACT_W, 56), UDim2.new(), Kit.C.purple, function()
		local ok, msg = Net.request("EnterPortal")
		if not ok and msg then
			Toast.show(msg, "info")
		end
	end, nil, 26)
	portalBtn.Name = "Portal"
	portalBtn.LayoutOrder = 1
	portalBtn.Visible = false
	columnHeight[portalBtn] = 56

	local exploreBtn = Kit.button(right, "@hud.explore_off", UDim2.fromOffset(ACT_W, 52), UDim2.new(), Kit.C.red, function()
		local _, msg = Net.request("SetRoam", { id = "" })
		if msg then
			Toast.show(msg, "info")
		end
	end, nil, 22)
	exploreBtn.Name = "StopExploring"
	exploreBtn.LayoutOrder = 2
	exploreBtn.Visible = false
	columnHeight[exploreBtn] = 52

	local abilityRow = Kit.frame(right, UDim2.fromOffset(ACT_W, 52), UDim2.new(), nil)
	abilityRow.Name = "Abilities"
	abilityRow.LayoutOrder = 3
	abilityRow.Visible = false
	columnHeight[abilityRow] = 52
	local dashBtn = Kit.button(abilityRow, "@hud.dash", UDim2.new(0, 88, 1, 0), UDim2.fromOffset(0, 0), Kit.C.blue, function()
		LocalFx.dash()
	end, nil, 22)
	dashBtn.Name = "Dash"
	local pocketBtn = Kit.button(abilityRow, "@hud.pocket", UDim2.new(0, 88, 1, 0), UDim2.fromOffset(96, 0), Kit.C.orange, function()
		local ok, msg = Net.request("PlacePocket")
		if msg then
			Toast.show(msg, if ok then "success" else "info")
		end
	end, nil, 22)
	pocketBtn.Name = "Pocket"

	local skip = Kit.button(right, "", UDim2.fromOffset(ACT_W, 74), UDim2.new(), Kit.C.green, function()
		Hud.skip(1)
	end)
	skip.Name = "SkipStage"
	skip.LayoutOrder = 4
	columnHeight[skip] = 74
	local skipTitle = Kit.bold(skip, "@hud.skip", UDim2.fromScale(1, 0.52), UDim2.fromScale(0, 0.02), Kit.C.white, nil, 28)
	local skipSub = Kit.bold(skip, "", UDim2.fromScale(1, 0.36), UDim2.fromScale(0, 0.56), Color3.fromRGB(255, 255, 200), nil, 19)

	local skip10 = Kit.button(right, "@hud.skip10", UDim2.fromOffset(ACT_W, 50), UDim2.new(), Kit.C.blue, function()
		Hud.skip(10)
	end, nil, 24)
	skip10.Name = "Skip10"
	skip10.LayoutOrder = 5
	columnHeight[skip10] = 50
	local bottomRow = Kit.frame(right, UDim2.fromOffset(ACT_W, 50), UDim2.new(), nil)
	bottomRow.Name = "Bottom"
	bottomRow.LayoutOrder = 6
	columnHeight[bottomRow] = 50
	local back = Kit.button(bottomRow, "@hud.checkpoint", UDim2.new(0, 116, 1, 0), UDim2.fromOffset(0, 0), Kit.C.orange, function()
		Net.request("ReturnToCheckpoint")
	end, nil, 20)
	back.Name = "Checkpoint"
	Kit.singleLine(back, 20)
	local lobby = Kit.button(bottomRow, "@hud.lobby", UDim2.new(0, 62, 1, 0), UDim2.fromOffset(122, 0), Kit.C.grey, function()
		Net.request("GoToLobby")
	end, nil, 20)
	lobby.Name = "Lobby"
	Kit.singleLine(lobby, 20)

	-- Shapes the action list as a row (PC) or a column (touch); returns its design size.
	local function shapeActions(asRow: boolean): Vector2
		actList.FillDirection = if asRow then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		local n, tall = 0, 0
		for c, h in columnHeight do
			c.Size = UDim2.fromOffset(ACT_W, if asRow then ROW_H else h)
			if c.Visible then
				n += 1
				tall += h
			end
		end
		local size = if asRow
			then Vector2.new(math.max(1, n) * ACT_W + math.max(0, n - 1) * ACT_GAP, ROW_H)
			else Vector2.new(ACT_W, tall + math.max(0, n - 1) * ACT_GAP)
		right.Size = UDim2.fromOffset(size.X, size.Y)
		return size
	end
	local function actionsShown(): number
		local n = 0
		for c in columnHeight do
			if c.Visible then
				n += 1
			end
		end
		return n
	end

	-- active power-ups: small chips over the menu grid (icon + time left, or charges)
	local chips = Kit.region("Boosts", Vector2.new(0, 1), UDim2.new(0, 12, 1, -70), Vector2.new(MENU_COLS * MENU_CELL + (MENU_COLS - 1) * MENU_GAP, 34))
	local chipList = Instance.new("UIListLayout")
	chipList.FillDirection = Enum.FillDirection.Horizontal
	chipList.SortOrder = Enum.SortOrder.LayoutOrder
	chipList.Padding = UDim.new(0, 6)
	chipList.Parent = chips
	local chipFor: { [string]: TextLabel } = {}
	for i, item in Powerups.List do
		if item.kind ~= "instant" then
			local color = Color3.fromRGB(item.color[1], item.color[2], item.color[3])
			local chip = Kit.frame(chips, UDim2.fromOffset(78, 34), UDim2.new(), Kit.darker(color, 0.25))
			chip.Name = "Chip_" .. item.id
			chip.LayoutOrder = i
			chip.Visible = false
			Kit.corner(chip, 17)
			Kit.stroke(chip, Kit.C.ink, 2)
			Kit.text(chip, item.icon, UDim2.fromOffset(28, 28), UDim2.fromOffset(4, 3), Kit.C.white, nil, 22)
			local label = Kit.bold(chip, "", UDim2.new(1, -36, 1, -8), UDim2.fromOffset(32, 4), Kit.C.white, nil, 18)
			label.TextXAlignment = Enum.TextXAlignment.Left
			chipFor[item.id] = label
		end
	end

	local side = Kit.gui():FindFirstChild("Progress") :: Frame?
	local level = Kit.gui():FindFirstChild("LevelBar") :: Frame?
	local function menuHeight(): number
		local n = 0
		for _, c in left:GetChildren() do
			if c:IsA("GuiButton") and c.Visible then
				n += 1
			end
		end
		local rows = math.max(1, math.ceil(n / MENU_COLS))
		return rows * MENU_CELL + (rows - 1) * MENU_GAP
	end
	Kit.onLayout(function(touch, area, scale)
		local mh = menuHeight()
		left.Size = UDim2.fromOffset(left.Size.X.Offset, mh)
		local shown = actionsShown()
		if touch then
			-- corner block under the Roblox buttons; the thumbstick owns the bottom left
			local top = math.floor(area.Y * 0.16)
			local cs = math.min(scale, area.X * 0.34 / CORNER_W)
			corner.AnchorPoint = Vector2.new(0, 0)
			corner.Position = UDim2.new(0, 12, 0, top)
			Kit.setScale(corner, cs)
			chips.AnchorPoint = Vector2.new(0, 0)
			chips.Position = UDim2.new(0, 12, 0, top + math.floor(56 * cs))
			Kit.setScale(chips, cs)
			-- the open menu may cover the thumbstick zone: it is a popup, it closes on a choice
			local gridTop = top + math.floor(96 * cs)
			left.AnchorPoint = Vector2.new(0, 0)
			left.Position = UDim2.new(0, 12, 0, gridTop)
			Kit.setScale(left, math.min(scale, (area.Y * 0.95 - gridTop) / mh))
			-- side bar: right edge, above the jump button (which owns the bottom 35%)
			local ss = scale * 0.85
			if side then
				side.AnchorPoint = Vector2.new(1, 0)
				side.Position = UDim2.new(1, -6, 0, math.floor(area.Y * 0.12))
				side.Size = UDim2.fromOffset(Progress.SIDE_W, math.floor(area.Y * 0.5 / ss))
				Kit.setScale(side, ss)
			end
			-- action column: left of the side bar, bottom at 64% of the height, shrunk to fit
			local size = shapeActions(false)
			local bottom = math.floor(area.Y * 0.64)
			right.AnchorPoint = Vector2.new(1, 1)
			right.Position = UDim2.new(1, -12 - math.floor(Progress.SIDE_W * ss), 0, bottom)
			Kit.setScale(right, math.min(scale, (bottom - 8) / math.max(size.Y, 1)))
			-- level bar: the free band between the thumbstick and the jump button
			if level then
				level.Size = UDim2.fromOffset(420, Progress.LEVEL_H)
				level.Position = UDim2.new(0.53, 0, 1, -6)
				Kit.setScale(level, math.min(scale, area.X * 0.4 / 420))
			end
		else
			corner.AnchorPoint = Vector2.new(0, 1)
			corner.Position = UDim2.new(0, 12, 1, -12)
			Kit.setScale(corner, scale)
			chips.AnchorPoint = Vector2.new(0, 1)
			chips.Position = UDim2.new(0, 12, 1, -12 - math.floor(58 * scale))
			Kit.setScale(chips, scale)
			-- the grid opens over the corner block, under the chat window
			left.AnchorPoint = Vector2.new(0, 1)
			left.Position = UDim2.new(0, 12, 1, -12 - math.floor(100 * scale))
			Kit.setScale(left, math.min(scale, (area.Y * 0.55) / mh))
			if side then
				side.AnchorPoint = Vector2.new(1, 0.5)
				side.Position = UDim2.new(1, -6, 0.5, 0)
				side.Size = UDim2.fromOffset(Progress.SIDE_W, math.floor(area.Y * 0.7 / scale))
				Kit.setScale(side, scale)
			end
			-- actions: a centred row on the bottom edge, never wider than the level bar
			local size = shapeActions(true)
			local rs = math.min(scale, area.X * 0.6 / size.X)
			right.AnchorPoint = Vector2.new(0.5, 1)
			right.Position = UDim2.new(0.5, 0, 1, -10)
			Kit.setScale(right, rs)
			if level then
				local ls = math.min(scale, area.X * 0.6 / Progress.LEVEL_W)
				level.Size = UDim2.fromOffset(Progress.LEVEL_W, Progress.LEVEL_H)
				level.Position = UDim2.new(0.5, 0, 1, -10 - (if shown > 0 then math.floor(ROW_H * rs) + 8 else 0))
				Kit.setScale(level, ls)
			end
		end
		Kit.setScale(stats, scale)
		stats.Position = UDim2.new(0.5, 0, 0, math.floor(Hud.STATS_TOP * scale))
		Hud.topScale = scale
		local rows = Hud.EVENT_TOP + (if Hud.eventBarVisible then 44 else 0)
		Kit.hudTop = math.floor(rows * scale)
	end)
	relayout = function()
		Kit.relayout()
	end

	local skipPrice: number? = nil
	fetchPrice(Config.Products.SkipStage, function(p)
		skipPrice = p
	end)
	local skip10Price: number? = nil
	fetchPrice(Config.Products.Skip10, function(p)
		skip10Price = p
	end)

	local function refresh()
		local s = Net.state
		local at = s.at or s.stage or 0
		Kit.setRaw(coinLabel, Kit.formatNumber(s.coins or 0))
		Kit.setRaw(winsLabel, ("%d"):format(s.wins or 0))
		local free = s.freeSkips or 0
		local onBase = s.base == true
		local studio = s.studio == true
		local view = Rules.skipButton(Layout :: any, at, onBase, free, Config.Products.SkipStage, studio, Config.StudioFreeSkips)
		local before = actionsShown()
		skip.Visible = view.visible
		Kit.setText(skipTitle, view.title)
		if view.sub == "hud.skips_left" then
			Kit.setText(skipSub, view.sub, { n = free })
		elseif view.sub == "hud.robux" and skipPrice then
			Kit.setText(skipSub, "hud.price", { price = skipPrice })
		elseif view.sub ~= "" then
			Kit.setText(skipSub, view.sub)
		else
			Kit.setRaw(skipSub, "")
		end
		skip10.Visible = Rules.skip10Visible(Layout :: any, at, onBase, Config.Products.Skip10, studio, Config.StudioFreeSkips)
		if skip10Price then
			Kit.setText(skip10, "hud.skip10_price", { price = skip10Price })
		else
			Kit.setText(skip10, "hud.skip10")
		end
		-- on a summit the way on is the portal
		portalBtn.Visible = Rules.isSummit(Layout :: any, at) and not onBase and at < Layout.TOTAL
		exploreBtn.Visible = s.roam ~= nil
		local charges = if type(s.charges) == "table" then s.charges else {}
		local hasDash = Players.LocalPlayer:GetAttribute("Dash") == true
		local hasPocket = (tonumber(charges.pocket) or 0) > 0 or Net.hasPass("InfiniteRevives")
		abilityRow.Visible = hasDash or hasPocket
		dashBtn.Visible = hasDash
		pocketBtn.Visible = hasPocket
		pocketBtn.Position = UDim2.fromOffset(if hasDash then 96 else 0, 0)
		if actionsShown() ~= before then
			Kit.relayout()
		end
		-- power-up chips
		local now = os.time()
		local boosts = if type(s.boosts) == "table" then s.boosts else {}
		for id, label in chipFor do
			local item = Powerups.get(id) :: Powerups.Item
			local chip = label.Parent :: Frame
			if item.kind == "timed" then
				local left = Powerups.remaining(boosts, id, now)
				chip.Visible = left > 0
				if left > 0 then
					Kit.setRaw(label, Kit.formatTime(left))
				end
			else
				local n = tonumber(charges[id]) or 0
				chip.Visible = n > 0
				if n > 0 then
					Kit.setRaw(label, "x" .. n)
				end
			end
		end
		local playClaimable = false
		local claimed = {}
		for _, i in (s.playClaimed or {}) :: { number } do
			claimed[i] = true
		end
		for i, r in Config.PlaytimeRewards do
			if not claimed[i] and Net.playSeconds() >= r.minutes * 60 then
				playClaimable = true
			end
		end
		rewardsBadge.Visible = (s.daily and s.daily.canClaim) or playClaimable
		-- menu extras: starter pack while on sale, group gift while unclaimed
		local starterOn = type(s.starter) == "table" and s.starter.available == true
		local groupOn = s.groupGift == true
		if starterBtn.Visible ~= starterOn or groupBtn.Visible ~= groupOn then
			starterBtn.Visible = starterOn
			groupBtn.Visible = groupOn
			Kit.relayout()
		end
		-- something waits behind the Menu button
		menuBadge.Visible = rewardsBadge.Visible or starterOn or groupOn
		-- timer look
		local run = s.run
		local ranked = type(run) ~= "table" or run.valid ~= false
		timerLabel.TextColor3 = if ranked then Kit.C.white else Color3.fromRGB(190, 195, 210)
		if ranked then
			if type(run) == "table" and (run.best or 0) > 0 then
				Kit.setText(timerNote, "run.best", { time = RunTime.format(run.best) })
			else
				Kit.setRaw(timerNote, "")
			end
		else
			Kit.setText(timerNote, "run.unranked")
		end
	end

	-- run clock: server time based, so it survives respawns and matches the ranked result
	task.spawn(function()
		while true do
			local run = Net.state.run
			local ms = 0
			if type(run) == "table" then
				if run.finalMs then
					ms = run.finalMs
				elseif run.start then
					ms = (Workspace:GetServerTimeNow() - run.start) * 1000
				end
			end
			Kit.setRaw(timerLabel, RunTime.format(ms))
			task.wait(0.1)
		end
	end)

	Net.changed:Connect(function(new, prev)
		refresh()
		if prev.coins and new.coins and new.coins > prev.coins then
			Kit.pop(coinLabel.Parent :: Frame, 0.85)
		end
	end)
	Lang.changed:Connect(refresh)
	task.spawn(function()
		while true do
			-- once a second while a timed power-up is counting down, otherwise every 5 s
			local ticking = false
			local boosts = Net.state.boosts
			if type(boosts) == "table" then
				for _, endsAt in boosts do
					if endsAt > os.time() then
						ticking = true
					end
				end
			end
			task.wait(if ticking then 1 else 5)
			refresh()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Dash"):Connect(refresh)
	refresh()
end

return Hud
