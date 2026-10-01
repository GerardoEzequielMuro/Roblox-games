--!strict
-- The HUD of a match: the strip of players with their lives, the turn banner and timer, the
-- live slot readout, your hand of cards, the target picker, SPIN / BRAKE, emotes, the
-- spectator bar and the results panel. It sends the player's choices to the server and
-- shows what the Director tells it; it never decides anything.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local TableViews = require(script.Parent.Parent.Arena.TableViews)

local MatchHud = {}

local player = Players.LocalPlayer
MatchHud.myId = "u" .. player.UserId
MatchHud.view = nil :: TableViews.View?
MatchHud.phase = "idle" -- "idle" | "decide" | "spin" | "brake"
MatchHud.myTurn = false
MatchHud.hand = {} :: { string }
MatchHud.spectating = false
MatchHud.pendingCard = nil :: string?
MatchHud.selectedTarget = nil :: string?
MatchHud.banners = 0
MatchHud.onLeave = nil :: (() -> ())?
MatchHud.onSpectateStep = nil :: ((number) -> ())?
MatchHud.onFreeCam = nil :: (() -> ())?
MatchHud.onPlayAgain = nil :: ((string) -> ())?
MatchHud.refresh = function() end :: () -> ()

local deadline = 0
local lastWarnSecs = -1
MatchHud.lastSecondBeats = 0 -- last-seconds warnings shown (playtest)
local decideTotal = 1
local brakeArmsAt = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
-- Touch: tappable pieces are sized for >= 44 px real at the ~0.75 phone HUD scale.
local T = Root.isTouch
local function pick(pc: any, touch: any): any
	if T then
		return touch
	end
	return pc
end

local root = Theme.new("Frame", { Name = "MatchHud", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = Root.gui }) :: Frame

-- players strip
local strip = Theme.new("Frame", {
	Name = "Players",
	Size = UDim2.fromOffset(960, 66),
	Position = UDim2.new(0.5, 0, 0, 4),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Parent = root,
}, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) }) :: Frame
Root.mount(strip, root)

type Chip = { frame: TextButton, stroke: UIStroke, name: TextLabel, hearts: TextLabel, extra: TextLabel, avatar: ImageLabel, avatarText: TextLabel, place: TextLabel, id: string }
local chips: { [string]: Chip } = {}

-- turn banner + timer
local turn = Theme.panel({ Name = "Turn", Size = UDim2.fromOffset(440, 40), Position = UDim2.new(0.5, 0, 0, 76), AnchorPoint = Vector2.new(0.5, 0), Corner = 20, Parent = root })
Root.mount(turn, root)
local turnText = Theme.text({ Name = "Text", Text = "", Title = true, Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 3), MaxTextSize = 26, Parent = turn })
local timerBack = Theme.new("Frame", { Name = "Timer", Size = UDim2.new(1, -28, 0, 5), Position = UDim2.new(0, 14, 1, -8), BackgroundColor3 = Theme.Ink, BorderSizePixel = 0, Parent = turn }, { Theme.corner(3) })
local timerFill = Theme.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Yellow, BorderSizePixel = 0, Parent = timerBack }, { Theme.corner(3) }) :: Frame
local turnStroke = turn:FindFirstChildOfClass("UIStroke")
local seconds = Theme.text({ Name = "Seconds", Text = "", Title = true, Size = UDim2.fromOffset(60, 30), Position = UDim2.new(1, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), MaxTextSize = 28, TextColor3 = Theme.Yellow, Stroke = 3, Parent = turn })

-- info chip (mode, round, modifier)
local info = Theme.panel({ Name = "Info", Size = UDim2.fromOffset(230, 56), Position = UDim2.new(0, 8, 0, 76), Corner = 14, Parent = root })
Root.mount(info, root)
local infoTitle = Theme.text({ Name = "Title", Text = "", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = info })
local infoSub = Theme.text({ Name = "Sub", Text = "", Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 29), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextColor3 = Theme.Dim, Parent = info })

-- live slot readout while the wheel turns
local readout = Theme.panel({ Name = "Readout", Size = UDim2.fromOffset(250, 66), Position = UDim2.new(0.5, 0, 0, 124), AnchorPoint = Vector2.new(0.5, 0), Corner = 18, Visible = false, Parent = root })
Root.mount(readout, root)
local readoutIcon = Theme.text({ Name = "Icon", Text = "", Stroke = false, Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(8, 6), Parent = readout })
local readoutName = Theme.text({ Name = "Name", Text = "", Title = true, Size = UDim2.new(1, -78, 0, 34), Position = UDim2.fromOffset(68, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 30, Parent = readout })
local readoutSub = Theme.text({ Name = "Sub", Text = "", Size = UDim2.new(1, -78, 0, 20), Position = UDim2.fromOffset(68, 40), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextColor3 = Theme.Dim, Parent = readout })
local readoutStroke = readout:FindFirstChildOfClass("UIStroke") :: UIStroke

-- big banner (outcomes, sudden death, winner)
local banner = Theme.new("Frame", { Name = "Banner", Size = UDim2.fromOffset(760, 150), Position = UDim2.fromScale(0.5, 0.34), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = root }) :: Frame
local bannerHolder = Root.mount(banner, root)
local bannerScale = Theme.new("UIScale", { Parent = banner }) :: UIScale
local bannerBack = Theme.new("Frame", { Name = "Back", Size = UDim2.new(1.6, 0, 0.62, 0), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 30, Parent = banner }, {
	Theme.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1) }) }),
}) :: Frame
local bannerMain = Theme.text({ Name = "Main", Text = "", Title = true, Size = UDim2.new(1, 0, 0.62, 0), Position = UDim2.fromScale(0, 0.1), MaxTextSize = 84, Stroke = 5, ZIndex = 31, Parent = banner })
local bannerSub = Theme.text({ Name = "Sub", Text = "", Size = UDim2.new(1, 0, 0.24, 0), Position = UDim2.fromScale(0, 0.74), MaxTextSize = 30, Stroke = 3, ZIndex = 31, Parent = banner })

-- bottom: hint, targets, hand, action
local bottom = Theme.new("Frame", { Name = "Bottom", Size = UDim2.fromOffset(900, 296), Position = UDim2.new(0.5, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Parent = root }) :: Frame
Root.mount(bottom, root)
local hint = Theme.text({ Name = "Hint", Text = "", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 0), MaxTextSize = 22, TextColor3 = Theme.Yellow, Stroke = 3, Parent = bottom })
local targets = Theme.new("Frame", { Name = "Targets", Size = UDim2.new(1, 0, 0, 66), Position = UDim2.fromOffset(0, 30), BackgroundTransparency = 1, Parent = bottom }, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) }) :: Frame
local handRow = Theme.new("Frame", { Name = "Hand", Size = UDim2.new(1, 0, 0, 122), Position = UDim2.fromOffset(0, 104), BackgroundTransparency = 1, Parent = bottom }, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) }) :: Frame
local action = Theme.button({ Name = "Action", Text = "", Title = true, Color = Theme.Green, Size = UDim2.fromOffset(280, 62), Position = UDim2.new(0.5, 0, 1, -2), AnchorPoint = Vector2.new(0.5, 1), TextSize = 40, Corner = 18, Parent = bottom })
MatchHud.actionButton = action -- the tutorial guide points at it
MatchHud.targetsFrame = targets
action.Visible = false
local actionKey = Theme.text({ Name = "Key", Text = "", Size = UDim2.fromOffset(90, 18), Position = UDim2.new(0.5, 150, 1, -24), AnchorPoint = Vector2.new(0, 0.5), MaxTextSize = 15, TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = bottom })

-- right: leave, auto-play, emotes
local side = Theme.new("Frame", { Name = "Side", Size = pick(UDim2.fromOffset(150, 230), UDim2.fromOffset(160, 214)), Position = UDim2.new(1, -8, 0, 76), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, Parent = root }, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right) }) :: Frame
Root.mount(side, root)
local leaveButton = Theme.button({ Name = "Leave", Key = "match.leave", Prefix = "🚪 ", Color = Theme.Red, Size = pick(UDim2.fromOffset(140, 44), UDim2.fromOffset(160, 62)), TextSize = 20, KeepSize = true, LayoutOrder = 1, Parent = side, OnClick = function()
	if MatchHud.onLeave then
		MatchHud.onLeave()
	end
end })
local autoButton = Theme.button({ Name = "AutoPlay", Text = "", Color = Theme.Grey, Size = pick(UDim2.fromOffset(140, 44), UDim2.fromOffset(160, 62)), TextSize = pick(17, 18), KeepSize = true, LayoutOrder = 2, Parent = side })
local emoteButton = Theme.button({ Name = "Emote", Text = "😀", Color = Theme.Purple, Size = pick(UDim2.fromOffset(60, 60), UDim2.fromOffset(64, 64)), Corner = 32, TextSize = 34, KeepSize = true, LayoutOrder = 3, Parent = side })
local emoteGrid = Theme.panel({ Name = "Emotes", Size = pick(UDim2.fromOffset(236, 124), UDim2.fromOffset(300, 152)), Position = pick(UDim2.new(1, -164, 0, 176), UDim2.new(1, -176, 0, 150)), AnchorPoint = Vector2.new(1, 0), Corner = 16, Visible = false, ZIndex = 12, Parent = root })
Root.mount(emoteGrid, root)
Theme.new("UIGridLayout", { CellSize = pick(UDim2.fromOffset(50, 50), UDim2.fromOffset(62, 62)), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = emoteGrid })

-- spectator bar
local spec = Theme.panel({ Name = "Spectate", Size = pick(UDim2.fromOffset(520, 58), UDim2.fromOffset(560, 78)), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), Corner = 18, Visible = false, Parent = root })
Root.mount(spec, root)
Theme.button({ Name = "Prev", Text = "◀", Color = Theme.Blue, Size = pick(UDim2.fromOffset(50, 42), UDim2.fromOffset(64, 62)), Position = UDim2.fromOffset(8, 8), TextSize = 24, KeepSize = true, Parent = spec, OnClick = function()
	if MatchHud.onSpectateStep then
		MatchHud.onSpectateStep(-1)
	end
end })
local specLabel = Theme.text({ Name = "Label", Key = "match.spectating", Prefix = "👁 ", Size = UDim2.fromOffset(190, 36), Position = pick(UDim2.fromOffset(64, 11), UDim2.fromOffset(80, 21)), MaxTextSize = 20, Parent = spec })
Theme.button({ Name = "Next", Text = "▶", Color = Theme.Blue, Size = pick(UDim2.fromOffset(50, 42), UDim2.fromOffset(64, 62)), Position = pick(UDim2.fromOffset(260, 8), UDim2.fromOffset(276, 8)), TextSize = 24, KeepSize = true, Parent = spec, OnClick = function()
	if MatchHud.onSpectateStep then
		MatchHud.onSpectateStep(1)
	end
end })
Theme.button({ Name = "Free", Key = "match.free_cam", Prefix = "🎥 ", Color = Theme.Purple, Size = pick(UDim2.fromOffset(190, 42), UDim2.fromOffset(190, 62)), Position = pick(UDim2.fromOffset(320, 8), UDim2.fromOffset(352, 8)), TextSize = 18, KeepSize = true, Parent = spec, OnClick = function()
	if MatchHud.onFreeCam then
		MatchHud.onFreeCam()
	end
end })

-- card showcase (a card being played)
local cardShow = Theme.new("Frame", { Name = "CardShow", Size = UDim2.fromOffset(190, 250), Position = UDim2.fromScale(0.5, 0.46), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Panel, Visible = false, ZIndex = 32, Parent = root }, { Theme.corner(20), Theme.stroke(5, Theme.White) }) :: Frame
Root.mount(cardShow, root)
local cardScale = Theme.new("UIScale", { Parent = cardShow }) :: UIScale
local cardBand = Theme.new("Frame", { Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Theme.Purple, BorderSizePixel = 0, ZIndex = 32, Parent = cardShow }, { Theme.corner(20) }) :: Frame
local cardIcon = Theme.text({ Text = "", Stroke = false, Size = UDim2.fromScale(0.7, 0.4), Position = UDim2.fromScale(0.15, 0.05), ZIndex = 33, Parent = cardShow })
local cardName = Theme.text({ Text = "", Title = true, Size = UDim2.new(1, -16, 0.16, 0), Position = UDim2.new(0, 8, 0.5, 0), MaxTextSize = 30, ZIndex = 33, Parent = cardShow })
local cardDesc = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0.22, 0), Position = UDim2.new(0, 10, 0.67, 0), MaxTextSize = 17, TextColor3 = Theme.Dim, TextWrapped = true, ZIndex = 33, Parent = cardShow })
local cardWho = Theme.text({ Text = "", Size = UDim2.new(1, -16, 0.09, 0), Position = UDim2.new(0, 8, 0.9, 0), MaxTextSize = 16, TextColor3 = Theme.Yellow, ZIndex = 33, Parent = cardShow })

-- results
local results = Theme.panel({ Name = "Results", Size = UDim2.fromOffset(500, 414), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Corner = 24, StrokeThickness = 5, Visible = false, ZIndex = 40, Parent = Root.gui })
-- lives outside the match HUD: it stays up after the table sends you back to the lobby
Root.mount(results)
Theme.shadow(results, 24)
local resultsScale = Theme.new("UIScale", { Parent = results }) :: UIScale
local resultsHead = Theme.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = Theme.Yellow, BorderSizePixel = 0, ZIndex = 40, Parent = results }, { Theme.corner(24) }) :: Frame
local resultsTitle = Theme.text({ Name = "Title", Text = "", Title = true, Size = UDim2.new(1, -30, 0, 52), Position = UDim2.fromOffset(15, 8), MaxTextSize = 50, Stroke = 4, ZIndex = 41, Parent = results })
local resultsSub = Theme.text({ Name = "Sub", Text = "", Size = UDim2.new(1, -30, 0, 26), Position = UDim2.fromOffset(15, 62), MaxTextSize = 22, ZIndex = 41, Parent = results })
local resultRows = Theme.new("Frame", { Name = "Rows", Size = UDim2.new(1, -40, 0, 216), Position = UDim2.fromOffset(20, 108), BackgroundTransparency = 1, ZIndex = 41, Parent = results }, { Theme.list(Enum.FillDirection.Vertical, 6) }) :: Frame
local againButton = Theme.button({ Name = "Again", Key = "match.play_again", Prefix = "▶ ", Color = Theme.Green, Size = pick(UDim2.fromOffset(250, 60), UDim2.fromOffset(250, 66)), Position = UDim2.new(0, 20, 1, pick(-76, -82)), TextSize = 28, KeepSize = true, Title = true, ZIndex = 41, Parent = results })
local lobbyButton = Theme.button({ Name = "Lobby", Key = "match.to_lobby", Color = Theme.Blue, Size = pick(UDim2.fromOffset(196, 60), UDim2.fromOffset(196, 66)), Position = UDim2.new(1, -20, 1, pick(-76, -82)), AnchorPoint = Vector2.new(1, 0), TextSize = 22, KeepSize = true, ZIndex = 41, Parent = results })
local lastResult: { [string]: any }? = nil

-- tutorial / coach line
local coach = Theme.panel({ Name = "Coach", Size = UDim2.fromOffset(560, 54), Position = UDim2.new(0.5, 0, 0, 196), AnchorPoint = Vector2.new(0.5, 0), Corner = 16, StrokeColor = Theme.Yellow, Visible = false, ZIndex = 14, Parent = root })
Root.mount(coach, root)
local coachText = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, -70, 1, -12), Position = UDim2.fromOffset(60, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, TextWrapped = true, ZIndex = 15, Parent = coach })
Theme.text({ Text = "💡", Stroke = false, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(10, 7), ZIndex = 15, Parent = coach })

---------------------------------------------------------------------------
-- Players strip
---------------------------------------------------------------------------
local function buildChip(p: TableViews.PlayerView): Chip
	local frame = Theme.new("TextButton", {
		Name = "Chip_" .. p.id,
		Size = UDim2.fromOffset(112, 62),
		BackgroundColor3 = Theme.Panel,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = p.seat,
		Parent = strip,
	}, { Theme.corner(12) }) :: TextButton
	local stroke = Theme.stroke(3, Theme.Ink)
	stroke.Parent = frame
	local avatar = Theme.new("ImageLabel", { Name = "Avatar", Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = p.color, BorderSizePixel = 0, Parent = frame }, { Theme.corner(17) }) :: ImageLabel
	local avatarText = Theme.text({ Text = if p.bot then "🤖" else "", Stroke = false, Size = UDim2.fromScale(0.74, 0.74), Position = UDim2.fromScale(0.13, 0.13), Parent = avatar })
	if not p.bot and p.userId > 0 then
		avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", p.userId)
	end
	local name = Theme.text({ Name = "Name", Text = p.name, Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(43, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 15, Parent = frame })
	local hearts = Theme.text({ Name = "Hearts", Text = "", Stroke = false, Size = UDim2.new(1, -48, 0, 16), Position = UDim2.fromOffset(43, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 13, Parent = frame })
	local extra = Theme.text({ Name = "Extra", Text = "", Size = UDim2.new(1, -10, 0, 16), Position = UDim2.fromOffset(5, 43), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 13, TextColor3 = Theme.Dim, Parent = frame })
	local place = Theme.text({ Name = "Place", Text = "", Title = true, Size = UDim2.fromScale(1, 1), MaxTextSize = 30, TextColor3 = Theme.Red, Visible = false, ZIndex = 3, Parent = frame })
	local chip: Chip = { frame = frame, stroke = stroke, name = name, hearts = hearts, extra = extra, avatar = avatar, avatarText = avatarText, place = place, id = p.id }
	frame.Activated:Connect(function()
		MatchHud.pickTarget(p.id)
	end)
	return chip
end

local function teamColor(view: TableViews.View, p: TableViews.PlayerView): Color3
	if Config.ModeById[view.mode].teams then
		return rgb(Config.TeamColors[p.team] or Config.TeamColors[1])
	end
	return p.color
end

local function refreshStrip()
	local view = MatchHud.view
	if not view then
		return
	end
	for id, chip in chips do
		if not view.players[id] then
			chip.frame:Destroy()
			chips[id] = nil
		end
	end
	local n = #view.order
	local w = if n > 6 then 112 else 128
	for _, id in view.order do
		local p = view.players[id]
		local chip = chips[id]
		if not chip then
			chip = buildChip(p)
			chips[id] = chip
		end
		chip.frame.Size = UDim2.fromOffset(if view.spinner == id then w + 14 else w, 62)
		chip.avatar.BackgroundColor3 = teamColor(view, p)
		chip.hearts.Text = if p.alive then TableViews.heartsText(p.lives, view.maxLives) else ""
		chip.extra.Text = if p.alive then ((if p.shields > 0 then string.rep("🛡️", p.shields) .. " " else "") .. "🃏" .. p.cards .. (if id == MatchHud.myId then "  ⭐" else "")) else ""
		chip.place.Visible = not p.alive
		chip.place.Text = if p.place > 0 then "#" .. p.place else "❌"
		chip.frame.BackgroundColor3 = if not p.alive then Color3.fromRGB(30, 30, 44) elseif id == MatchHud.myId then Theme.Panel2 else Theme.Panel
		chip.name.TextTransparency = if p.alive then 0 else 0.6
		chip.avatar.ImageTransparency = if p.alive then 0 else 0.6
		chip.stroke.Color = if view.spinner == id then Theme.Yellow elseif view.target == id then Theme.Red else Theme.Ink
		chip.stroke.Thickness = if view.spinner == id or view.target == id then 4 else 3
	end
end

---------------------------------------------------------------------------
-- Targets, hand, action button
---------------------------------------------------------------------------
local function act(kind: string, payload: { [string]: any }?)
	local data: { [string]: any } = payload or {}
	data.kind = kind
	task.spawn(function()
		local ok, err = Net.request("Act", data)
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end)
end
MatchHud.act = act

local function me(): TableViews.PlayerView?
	local view = MatchHud.view
	return if view then view.players[MatchHud.myId] else nil
end

-- Who can be picked right now (for the spin, or for the card waiting for a target).
local function validTargets(): { TableViews.PlayerView }
	local view = MatchHud.view
	local mine = me()
	local list = {}
	if not view or not mine then
		return list
	end
	local teams = Config.ModeById[view.mode].teams
	for _, id in view.order do
		local p = view.players[id]
		if p.alive and id ~= MatchHud.myId then
			local ok = true
			if MatchHud.pendingCard == "magnet" then
				ok = p.cards > 0
			elseif MatchHud.pendingCard == nil and teams and p.team == mine.team then
				ok = false
			end
			if ok then
				table.insert(list, p)
			end
		end
	end
	return list
end

function MatchHud.pickTarget(id: string)
	if not (MatchHud.myTurn and MatchHud.phase == "decide") then
		return
	end
	local okTarget = false
	for _, p in validTargets() do
		okTarget = okTarget or p.id == id
	end
	if not okTarget then
		return
	end
	Theme.play("click", 0.4, 1.2)
	if MatchHud.pendingCard then
		act("card", { card = MatchHud.pendingCard, target = id })
		MatchHud.pendingCard = nil
	else
		MatchHud.selectedTarget = id
		act("target", { target = id })
	end
	MatchHud.refresh()
end

local function refreshTargets()
	for _, c in targets:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local view = MatchHud.view
	local show = view ~= nil and MatchHud.myTurn and MatchHud.phase == "decide"
	targets.Visible = show
	if not show or not view then
		return
	end
	local list = validTargets()
	local w = math.min(150, math.floor((880 - (#list - 1) * 8) / math.max(1, #list)))
	for i, p in list do
		local selected = MatchHud.pendingCard == nil and (view.target == p.id or MatchHud.selectedTarget == p.id)
		local b = Theme.button({
			Name = "Target_" .. p.id,
			Text = (if MatchHud.pendingCard then "👉 " else "🎯 ") .. p.name .. "\n" .. TableViews.heartsText(p.lives, p.lives) .. (if p.shields > 0 then " 🛡️" else ""),
			Color = if selected then Theme.Red else teamColor(view, p):Lerp(Theme.Panel2, 0.45),
			Size = UDim2.fromOffset(w, 64),
			TextSize = 17,
			LayoutOrder = i,
			Parent = targets,
			OnClick = function()
				MatchHud.pickTarget(p.id)
			end,
		})
		if selected then
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = Theme.White
			end
		end
	end
end

local function cardUsable(card: string): boolean
	local view = MatchHud.view
	local mine = me()
	if not view or not mine or not (MatchHud.myTurn and MatchHud.phase == "decide") or MatchHud.cardPlayed then
		return false
	end
	if card == "shield" and mine.shields >= Config.MaxShields then
		return false
	end
	return true
end

local function refreshHand()
	for _, c in handRow:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for i, card in MatchHud.hand do
		local def = Config.CardById[card]
		if def then
			local usable = cardUsable(card)
			local selected = MatchHud.pendingCard == card
			local color = rgb(def.color)
			local b = Theme.new("TextButton", {
				Name = "Card_" .. card,
				Size = if T then UDim2.fromOffset(100, if selected then 124 else 112) else UDim2.fromOffset(84, if selected then 120 else 108),
				BackgroundColor3 = if usable then Theme.Panel else Color3.fromRGB(30, 30, 44),
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = i,
				Parent = handRow,
			}, { Theme.corner(14), Theme.stroke(if selected then 5 else 3, if selected then Theme.White elseif usable then color else Theme.Ink) }) :: TextButton
			Theme.new("Frame", { Size = UDim2.new(1, 0, 0.56, 0), BackgroundColor3 = if usable then color else color:Lerp(Color3.fromRGB(30, 30, 44), 0.7), BorderSizePixel = 0, Parent = b }, { Theme.corner(14) })
			Theme.text({ Text = def.icon, Stroke = false, Size = UDim2.fromScale(0.7, 0.42), Position = UDim2.fromScale(0.15, 0.07), TextTransparency = if usable then 0 else 0.4, Parent = b })
			Theme.text({ Text = Lang.t("card." .. card .. ".name"), Title = true, Size = UDim2.new(1, -8, 0.19, 0), Position = UDim2.new(0, 4, 0.56, 0), MaxTextSize = pick(17, 19), TextTransparency = if usable then 0 else 0.4, Parent = b })
			Theme.text({ Text = Lang.t("card." .. card .. ".short"), Size = UDim2.new(1, -8, pick(0.2, 0.25), 0), Position = UDim2.new(0, 4, pick(0.78, 0.75), 0), MaxTextSize = pick(12, 14), MinTextSize = pick(9, 12), TextColor3 = Theme.Dim, TextWrapped = true, Parent = b })
			-- the rule of the card, bottom centre, while the pointer is on it
			b.MouseEnter:Connect(function()
				hint.Text = def.icon .. " " .. Lang.t("card." .. card .. ".name") .. ": " .. Lang.t("card." .. card .. ".desc")
			end)
			b.MouseLeave:Connect(function()
				MatchHud.refresh()
			end)
			b.Activated:Connect(function()
				if not cardUsable(card) then
					Toasts.show(Lang.t(if MatchHud.cardPlayed then "msg.card_limit" else "match.cards_on_turn"), "info")
					return
				end
				Theme.play("card", 0.4)
				if def.needsTarget then
					MatchHud.pendingCard = if MatchHud.pendingCard == card then nil else card
					MatchHud.refresh()
				else
					MatchHud.pendingCard = nil
					act("card", { card = card })
				end
			end)
		end
	end
end

local function refreshAction()
	local show = MatchHud.myTurn and (MatchHud.phase == "decide" or MatchHud.phase == "spin")
	action.Visible = show
	actionKey.Visible = show and not Root.isTouch
	if MatchHud.phase == "decide" then
		Theme.setButton(action, "🌀 " .. Lang.t("match.spin"), Theme.Green)
		actionKey.Text = "[" .. Lang.t("match.key_space") .. "]"
	elseif MatchHud.phase == "spin" then
		Theme.setButton(action, "✋ " .. Lang.t("match.brake"), Theme.Yellow)
		actionKey.Text = "[" .. Lang.t("match.key_space") .. "]"
	end
	local text = ""
	if MatchHud.myTurn and MatchHud.phase == "decide" then
		local pending = MatchHud.pendingCard
		text = if pending then Config.CardById[pending].icon .. " " .. Lang.t("card." .. pending .. ".desc") .. "  ·  " .. Lang.t("match.hint_card_target") else Lang.t("match.hint_decide")
	elseif MatchHud.myTurn and MatchHud.phase == "spin" then
		text = Lang.t("match.hint_brake")
	end
	hint.Text = text
end

local function press()
	if not MatchHud.myTurn then
		return
	end
	if MatchHud.phase == "decide" then
		MatchHud.phase = "idle"
		act("spin")
		refreshAction()
	elseif MatchHud.phase == "spin" then
		local now = Workspace:GetServerTimeNow()
		if now < brakeArmsAt then
			return
		end
		MatchHud.phase = "brake"
		MatchHud.brakePressed = (MatchHud.brakePressed or 0) + 1
		act("brake", { at = now })
		refreshAction()
	end
end
MatchHud.press = press
MatchHud.brakePressed = 0
MatchHud.cardPlayed = false
action.Activated:Connect(press)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not root.Visible then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		press()
	end
end)

---------------------------------------------------------------------------
-- Emotes, auto-play
---------------------------------------------------------------------------
local function refreshEmotes()
	for _, c in emoteGrid:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local list = Net.get("emotes") or Config.DefaultEmotes
	emoteGrid.Size = UDim2.fromOffset(236, if #list > 4 then 124 else 68)
	for i, id in list do
		local item = Config.CosmeticById[id]
		if item then
			local b = Theme.button({ Name = id, Text = item.icon, Color = Theme.Panel2, Size = UDim2.fromOffset(50, 50), TextSize = 30, Corner = 12, LayoutOrder = i, ZIndex = 13, Parent = emoteGrid, OnClick = function()
				emoteGrid.Visible = false
				task.spawn(Net.request, "Emote", { id = id })
			end })
			b.ZIndex = 13
		end
	end
end
emoteButton.Activated:Connect(function()
	emoteGrid.Visible = not emoteGrid.Visible
	if emoteGrid.Visible then
		refreshEmotes()
	end
end)

-- afkAuto: the server started playing my turns because I let the timer run out twice
-- (my own toggle is off). The button then reads ON, and pressing it hands the turns back.
MatchHud.afkAuto = false
local function refreshAuto()
	local on = Net.setting("autoPlay") == true or MatchHud.afkAuto
	Theme.setButton(autoButton, "🤖 " .. Lang.t("hud.auto_play") .. ": " .. (if on then "ON" else "OFF"), if on then Theme.Green else Theme.Grey)
	local st = autoButton:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if MatchHud.afkAuto then Theme.Yellow else Theme.Ink
	end
end
autoButton.Activated:Connect(function()
	Theme.play("click", 0.35)
	if MatchHud.afkAuto and Net.setting("autoPlay") ~= true then
		MatchHud.afkAuto = false
		act("back")
		refreshAuto()
		return
	end
	local on = Net.setting("autoPlay") == true
	task.spawn(Net.request, "SetSetting", { key = "autoPlay", value = not on })
end)

---------------------------------------------------------------------------
-- Public API (called by the Director)
---------------------------------------------------------------------------
MatchHud.refresh = function()
	local view = MatchHud.view
	if not view then
		return
	end
	refreshStrip()
	refreshTargets()
	refreshHand()
	refreshAction()
	refreshAuto()
	local mode = Config.ModeById[view.mode]
	infoTitle.Text = mode.icon .. " " .. Lang.t("mode." .. view.mode .. ".name") .. "  ·  " .. Lang.t("match.round", { n = view.round })
	if view.sudden then
		infoSub.Text = "💀 " .. Lang.t("match.sudden") .. (if view.dmgBonus > 0 then "  +" .. view.dmgBonus else "")
		infoSub.TextColor3 = Theme.Red
	elseif view.modifier then
		infoSub.Text = Config.ModifierById[view.modifier].icon .. " " .. Lang.t("mod." .. view.modifier .. ".name") .. ": " .. Lang.t("mod." .. view.modifier .. ".desc")
		infoSub.TextColor3 = Theme.Yellow
	else
		infoSub.Text = Lang.t("match.no_modifier")
		infoSub.TextColor3 = Theme.Dim
	end
	local mine = me()
	local watching = MatchHud.spectating or (mine ~= nil and not mine.alive)
	spec.Visible = watching and not results.Visible
	bottom.Visible = not watching
	emoteButton.Visible = not MatchHud.spectating
	autoButton.Visible = not MatchHud.spectating
end

function MatchHud.show(view: TableViews.View, spectating: boolean)
	MatchHud.view = view
	MatchHud.spectating = spectating
	MatchHud.phase = "idle"
	MatchHud.myTurn = false
	MatchHud.pendingCard = nil
	MatchHud.selectedTarget = nil
	MatchHud.afkAuto = false
	if spectating then
		MatchHud.hand = {}
	end
	results.Visible = false
	readout.Visible = false
	banner.Visible = false
	coach.Visible = false
	root.Visible = true
	Root.hidePlayerList = true
	Root.apply()
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	MatchHud.refresh()
end

function MatchHud.hide()
	root.Visible = false
	MatchHud.view = nil
	MatchHud.phase = "idle"
	MatchHud.myTurn = false
	emoteGrid.Visible = false
	for id, chip in chips do
		chip.frame:Destroy()
		chips[id] = nil
	end
	Root.hidePlayerList = false
	Root.apply()
	pcall(function()
		GuiService.TouchControlsEnabled = true
	end)
end

function MatchHud.isVisible(): boolean
	return root.Visible
end

function MatchHud.setHand(cards: { string })
	MatchHud.hand = cards
	if root.Visible then
		refreshHand()
	end
end

-- Whose turn it is. `passedFrom` = the spin was passed with a card.
function MatchHud.turn(spinnerId: string, passedFrom: string?)
	local view = MatchHud.view
	if not view then
		return
	end
	local p = view.players[spinnerId]
	MatchHud.myTurn = spinnerId == MatchHud.myId
	MatchHud.phase = "idle"
	MatchHud.pendingCard = nil
	MatchHud.selectedTarget = nil
	MatchHud.cardPlayed = passedFrom ~= nil
	readout.Visible = false
	local name = if p then p.name else "?"
	turnText.Text = if MatchHud.myTurn then "⭐ " .. Lang.t("match.your_turn") else Lang.t("match.turn_of", { name = name })
	turnText.TextColor3 = if MatchHud.myTurn then Theme.Yellow else Theme.White
	local st = turn:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if MatchHud.myTurn then Theme.Yellow else Theme.Ink
	end
	if MatchHud.myTurn then
		Theme.pop(turn, 1.25)
	end
	MatchHud.refresh()
end

function MatchHud.decide(e: { [string]: any })
	MatchHud.phase = "decide"
	MatchHud.myTurn = e.spinner == MatchHud.myId and not e.auto
	if e.spinner == MatchHud.myId then
		local was = MatchHud.afkAuto
		MatchHud.afkAuto = e.auto == true and Net.setting("autoPlay") ~= true
		if MatchHud.afkAuto and not was then
			Theme.pop(autoButton, 1.3)
		end
	end
	MatchHud.cardPlayed = e.snapshot.cardPlayed or e.snapshot.passed
	deadline = e.deadline
	decideTotal = math.max(0.1, e.duration)
	MatchHud.refresh()
end

function MatchHud.spinning(e: { [string]: any }, mine: boolean)
	MatchHud.phase = if mine then "spin" else "idle"
	MatchHud.myTurn = mine
	MatchHud.pendingCard = nil
	brakeArmsAt = e.t0 + e.minSpin
	deadline = e.t0 + e.maxSpin
	decideTotal = math.max(0.1, e.maxSpin)
	readout.Visible = true
	readoutSub.Text = ""
	MatchHud.refresh()
end

function MatchHud.braking()
	MatchHud.phase = "brake"
	deadline = 0
	MatchHud.refresh()
end

-- The slot under the pointer right now (and, with the Oracle card, where a brake would land).
function MatchHud.readout(outcome: string?, sub: string?, hot: boolean?)
	if not outcome then
		readout.Visible = false
		return
	end
	readout.Visible = true
	local def = Config.OutcomeById[outcome]
	readoutIcon.Text = if def then def.icon else "❓"
	readoutName.Text = if def then Lang.upper(Lang.t("out." .. outcome)) else "???"
	local color = if def then rgb(def.color) else Theme.Line
	if def and def.id == "doom" then
		color = Theme.Red
	end
	readoutStroke.Color = color
	readoutName.TextColor3 = color:Lerp(Theme.White, 0.45)
	if sub ~= nil then
		readoutSub.Text = sub
	end
	if hot then
		Theme.pop(readout, 1.12)
	end
end

function MatchHud.readoutHidden()
	readout.Visible = true
	readoutIcon.Text = "❓"
	readoutName.Text = "???"
	readoutStroke.Color = Theme.Line
end

-- Slam banner. style: "slam" (default), "soft".
function MatchHud.banner(main: string, sub: string?, color: Color3?, seconds: number?, style: string?)
	MatchHud.banners += 1
	banner.Visible = true
	bannerHolder.Visible = true
	bannerMain.Text = main
	bannerMain.TextColor3 = color or Theme.White
	bannerSub.Text = sub or ""
	bannerBack.BackgroundColor3 = (color or Theme.White):Lerp(Theme.Ink, 0.88)
	bannerMain.TextTransparency = 0
	bannerSub.TextTransparency = 0
	bannerBack.BackgroundTransparency = 0.3
	for _, l in { bannerMain, bannerSub } do
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = 0
		end
	end
	if style == "soft" then
		bannerScale.Scale = 0.85
		TweenService:Create(bannerScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	else
		bannerScale.Scale = 2.6
		TweenService:Create(bannerScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
	end
	local mine = MatchHud.banners
	task.delay(seconds or 1.8, function()
		if MatchHud.banners ~= mine then
			return
		end
		local info = TweenInfo.new(0.25)
		TweenService:Create(bannerMain, info, { TextTransparency = 1 }):Play()
		TweenService:Create(bannerSub, info, { TextTransparency = 1 }):Play()
		TweenService:Create(bannerBack, info, { BackgroundTransparency = 1 }):Play()
		for _, l in { bannerMain, bannerSub } do
			local st = l:FindFirstChildOfClass("UIStroke")
			if st then
				TweenService:Create(st, info, { Transparency = 1 }):Play()
			end
		end
		task.wait(0.27)
		if MatchHud.banners == mine then
			banner.Visible = false
		end
	end)
end

-- A card being played, shown big for a moment.
function MatchHud.showCard(card: string, who: string, targetName: string?)
	local def = Config.CardById[card]
	if not def then
		return
	end
	cardBand.BackgroundColor3 = rgb(def.color)
	cardIcon.Text = def.icon
	cardName.Text = Lang.t("card." .. card .. ".name")
	cardDesc.Text = Lang.t("card." .. card .. ".desc")
	cardWho.Text = who .. (if targetName then " → " .. targetName else "")
	cardShow.Visible = true
	cardShow.Rotation = -14
	cardScale.Scale = 0.2
	TweenService:Create(cardScale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(cardShow, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Rotation = 3 }):Play()
	task.delay(1.0, function()
		local t = TweenService:Create(cardScale, TweenInfo.new(0.18), { Scale = 0 })
		t:Play()
		t.Completed:Wait()
		cardShow.Visible = false
	end)
end

function MatchHud.coach(text: string?)
	coach.Visible = text ~= nil
	if text then
		coachText.Text = text
		Theme.pop(coach, 1.08)
	end
end

-- `rollTo`: the number rolls up from 0 (eased, staggered by row) and the row pops when it lands.
local function resultRow(icon: string, label: string, value: string, color: Color3, order: number, rollTo: number?, suffix: string?)
	local row = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Panel2, LayoutOrder = order, ZIndex = 41, Parent = resultRows }, { Theme.corner(10) })
	Theme.text({ Text = icon, Stroke = false, Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(8, 4), ZIndex = 42, Parent = row })
	Theme.text({ Text = label, Size = UDim2.new(0.55, -44, 1, -10), Position = UDim2.fromOffset(44, 5), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, ZIndex = 42, Parent = row })
	local valueLabel = Theme.text({ Text = value, Title = true, Size = UDim2.new(0.45, -12, 1, -8), Position = UDim2.new(0.55, 0, 0, 4), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 24, TextColor3 = color, ZIndex = 42, Parent = row })
	if rollTo and rollTo > 0 then
		local tail = suffix or ""
		local function fmt(n: number): string
			return "+" .. Format.commas(n) .. tail
		end
		valueLabel.Text = fmt(0)
		task.delay(0.25 + order * 0.14, function()
			if valueLabel.Parent then
				Theme.roll(valueLabel, 0, rollTo, 0.7, fmt)
				Theme.pop(row, 1.08)
				Theme.play("tick", 0.3, 1.2 + order * 0.15)
			end
		end)
	end
end

-- The reward screen. `final` = the match is over (otherwise you were eliminated and can watch).
function MatchHud.showResult(r: { [string]: any }, final: boolean)
	lastResult = r
	for _, c in resultRows:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local color = if r.won then Theme.Yellow elseif r.place <= 3 then Theme.Cyan else Theme.Purple
	resultsHead.BackgroundColor3 = color
	resultsTitle.Text = if r.won then "🏆 " .. Lang.t("result.victory") else Lang.t("result.place", { n = r.place, total = r.n })
	resultsSub.Text = if r.won and r.streak > 1 then "🔥 " .. Lang.t("result.streak", { n = r.streak }) elseif r.won then Lang.t("result.winner_sub") else Lang.t("result.loser_sub")
	resultRow("🪙", Lang.t("result.coins"), "+" .. Format.commas(r.coins) .. (if (r.eventCoin or 1) > 1 then "  ×" .. r.eventCoin else ""), Theme.Yellow, 1, r.coins, if (r.eventCoin or 1) > 1 then "  ×" .. r.eventCoin else "")
	resultRow("⭐", Lang.t("result.xp"), "+" .. Format.commas(r.xp) .. (if r.levelUp then "  ⬆ " .. Lang.t("result.level", { n = r.level }) else ""), Theme.Cyan, 2, r.xp, if r.levelUp then "  ⬆ " .. Lang.t("result.level", { n = r.level }) else "")
	resultRow("🏆", Lang.t("result.trophies"), "+" .. r.trophies, Theme.Pink, 3, r.trophies)
	if (r.seasonPoints or 0) > 0 then
		resultRow("🏅", Lang.t("result.season"), "+" .. r.seasonPoints, Theme.Green, 4)
	end
	if r.tutorial then
		resultRow("🎓", Lang.t("result.tutorial"), "+" .. Format.commas(r.tutorialCoins), Theme.Green, 5, r.tutorialCoins)
	end
	Theme.setButton(againButton, (if final then "▶ " .. Lang.t("match.play_again") else "👁 " .. Lang.t("match.keep_watching")), if final then Theme.Green else Theme.Purple)
	results.Visible = true
	spec.Visible = false
	resultsScale.Scale = 0.5
	TweenService:Create(resultsScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	againButton:SetAttribute("Final", final)
end

function MatchHud.resultVisible(): boolean
	return results.Visible
end

againButton.Activated:Connect(function()
	Theme.play("click", 0.35)
	results.Visible = false
	if againButton:GetAttribute("Final") then
		local mode = if lastResult then lastResult.mode else "classic"
		if MatchHud.onPlayAgain then
			MatchHud.onPlayAgain(mode)
		end
	else
		MatchHud.refresh()
	end
end)
lobbyButton.Activated:Connect(function()
	Theme.play("click", 0.35)
	results.Visible = false
	if MatchHud.onLeave then
		MatchHud.onLeave()
	end
end)

function MatchHud.closeResult()
	results.Visible = false
end

function MatchHud.init()
	Net.event("Hand").OnClientEvent:Connect(function(_tableId, cards)
		MatchHud.setHand(cards)
	end)
	Net.Changed:Connect(function()
		if root.Visible then
			refreshAuto()
		end
	end)
	Lang.Changed:Connect(function()
		if root.Visible then
			MatchHud.refresh()
		end
	end)
	-- timer bar: one loop
	RunService.RenderStepped:Connect(function()
		if not root.Visible then
			return
		end
		if deadline > 0 and (MatchHud.phase == "decide" or MatchHud.phase == "spin" or MatchHud.view ~= nil) then
			local left = math.clamp((deadline - Workspace:GetServerTimeNow()) / decideTotal, 0, 1)
			timerFill.Size = UDim2.fromScale(left, 1)
			timerFill.BackgroundColor3 = if left < 0.3 then Theme.Red else Theme.Yellow
			timerBack.Visible = true
			local secs = math.max(0, math.ceil(deadline - Workspace:GetServerTimeNow()))
			seconds.Text = if MatchHud.phase == "decide" and secs < 100 then tostring(secs) else ""
			seconds.TextColor3 = if left < 0.3 then Theme.Red else Theme.Yellow
			-- last seconds of my own decision: each second thumps (pop, tick, red rim)
			if MatchHud.phase == "decide" and MatchHud.myTurn and secs <= 3 and secs > 0 and secs ~= lastWarnSecs then
				lastWarnSecs = secs
				MatchHud.lastSecondBeats += 1
				Theme.pop(seconds, 1.6)
				Theme.play("tick", 0.55, 1.9 - secs * 0.15)
				if turnStroke then
					turnStroke.Color = Theme.Red
					TweenService:Create(turnStroke, TweenInfo.new(0.6), { Color = Theme.Yellow }):Play()
				end
			elseif secs > 3 then
				lastWarnSecs = -1
			end
		else
			timerBack.Visible = false
			seconds.Text = ""
		end
	end)
	specLabel.TextXAlignment = Enum.TextXAlignment.Center
	leaveButton.Visible = true
end

return MatchHud
