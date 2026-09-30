--!nonstrict
-- The menu: a short column of round buttons on the left on PC; on phones a single row at the
-- bottom, between the thumbstick and the combat buttons. "Warrior" and "More" fold out a
-- text sub-menu; the rest open their window. Buttons appear as the story unlocks them, so a new player starts with few.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Toasts = require(script.Parent.Toasts)
local Panels1 = require(script.Parent.Panels1)
local Panels2 = require(script.Parent.Panels2)
local Panels3 = require(script.Parent.Panels3)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Controls = require(script.Parent.Parent.Controls)
local WorldFx = require(script.Parent.Parent.WorldFx)

local Menu = {}
local new = Theme.new
local touch = Root.isTouch

local SIZE = 52 -- touch: 52 * 0.85 scale = 44 px
local GAP = if touch then 9 else 8
local buttons: { [string]: { frame: TextButton, badge: Frame, holder: Frame } } = {}
Menu.buttons = buttons
local sub: Frame? = nil
local subFor: string? = nil

-- name, icon, colour, story step from which it shows (0 = always), window or submenu entries
local ENTRIES = {
	{ name = "Warrior", icon = "👤", color = Theme.Red, from = 0, sub = { "Warrior", "Forms", "Moves", "Auras", "Wardrobe", "Upgrades", "Ascend" } },
	{ name = "Quests", icon = "📜", color = Theme.Orange, from = 0, window = "Quests" },
	{ name = "Rewards", icon = "🎁", color = Theme.Green, from = 0, window = "Rewards" },
	{ name = "Shop", icon = "🛒", color = Theme.Yellow, from = Config.TutorialSteps + 1, window = "Shop" },
	{ name = "Season", icon = "🎟️", color = Theme.Purple, from = Config.TutorialSteps + 1, window = "Season" },
	{ name = "More", icon = "🧭", color = Theme.Blue, from = 0, sub = { "Travel", "Ranking", "Invite", "Settings" } },
}
local SUB_ICONS = { Warrior = "👤", Forms = "🔥", Moves = "☄️", Auras = "🌀", Wardrobe = "🎽", Upgrades = "💎", Ascend = "🌟", Travel = "🪐", Ranking = "🏆", Invite = "💌", Settings = "⚙️" }

local function closeSub()
	if sub then
		sub:Destroy()
		sub = nil
		subFor = nil
	end
end

local function openSub(entry, anchor: GuiObject, anchorX: number)
	closeSub()
	subFor = entry.name
	local cellH = if touch then 52 else 34
	local rowH = cellH + 4
	local cols = if touch then 2 else 1
	local rows = math.ceil(#entry.sub / cols)
	local cellW = if touch then 122 else 166
	local h = rows * rowH + 6
	local f = Theme.panel({
		Name = "SubMenu",
		Size = UDim2.fromOffset(cols * (cellW + 4) + 6, h),
		-- touch: opens upwards from the bottom menu row, left-aligned with the row
		Position = if touch then UDim2.fromOffset(-anchorX, -(h + 10)) else UDim2.fromOffset(SIZE + 12, -6),
		ZIndex = 30,
		Parent = anchor,
	})
	new("UIScale", { Parent = f })
	for i, win in entry.sub do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local b = new("TextButton", { Name = "Sub_" .. win, Size = UDim2.fromOffset(cellW, cellH), Position = UDim2.fromOffset(5 + col * (cellW + 4), 5 + row * rowH), BackgroundColor3 = Theme.PanelLight, BackgroundTransparency = 0.4, AutoButtonColor = true, Text = "", ZIndex = 31, Parent = f }, { Theme.corner(8) })
		Theme.icon(SUB_ICONS[win] or "", { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 6, 0.5, -12), Parent = b }).ZIndex = 32
		local t = Theme.text({ Key = "menu." .. win, Size = UDim2.new(1, -40, 1, -10), Position = UDim2.fromOffset(36, 5), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Parent = b })
		t.ZIndex = 32
		b.Activated:Connect(function()
			Theme.play("click", 0.3)
			closeSub()
			Windows.open(win)
		end)
	end
	sub = f
end

local function build()
	local cols = if touch then #ENTRIES else 1
	local rows = math.ceil(#ENTRIES / cols)
	local gap = GAP
	local dock = new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cols * (SIZE + gap), rows * (SIZE + 18 + gap)),
		-- touch: bottom row between the thumbstick (x < ~155) and the combat buttons
		Position = if touch then UDim2.new(0, 162, 1, -2) else UDim2.new(0, 12, 0.4, 0),
		AnchorPoint = if touch then Vector2.new(0, 1) else Vector2.new(0, 0.5),
		Parent = Root.gui,
	})
	local mounted = Root.mount(dock)
	mounted.ZIndex = 5
	if touch then
		-- tablets: the thumbstick is bigger and further in, so the row moves right with the scale
		local function place()
			mounted.Position = UDim2.new(0, 162 + math.max(0, Root.scale / 0.85 - 1) * 300, 1, -2)
		end
		place()
		Root.Changed:Connect(place)
	end
	if touch then
		-- hidden (still locked) entries collapse instead of leaving a hole in the row
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = dock })
	end
	for i, e in ENTRIES do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		-- earlier buttons draw above later ones so a badge (top-right) is not hidden by its neighbour
		local holder = new("Frame", { Name = "Holder_" .. e.name, ZIndex = #ENTRIES - i + 1, BackgroundTransparency = 1, LayoutOrder = i, Size = UDim2.fromOffset(SIZE, SIZE + 16), Position = if touch then UDim2.new() else UDim2.fromOffset(col * (SIZE + gap), row * (SIZE + 18 + gap)), Parent = dock })
		local b = new("TextButton", {
			Name = "Menu_" .. e.name,
			Size = UDim2.fromOffset(SIZE, SIZE),
			BackgroundColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
			Text = "",
			Parent = holder,
		}, {
			Theme.corner(SIZE),
			Theme.stroke(3, Theme.lighten(e.color, 0.2)),
			Theme.gradient(Theme.PanelLight, Theme.PanelDark),
		})
		Theme.icon(e.icon, { Size = UDim2.fromScale(0.58, 0.58), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = b })
		Theme.text({ Key = "menu." .. e.name, Size = UDim2.fromOffset(SIZE + gap, if touch then 16 else 14), Position = UDim2.new(0.5, 0, 1, 1), AnchorPoint = Vector2.new(0.5, 0), MaxTextSize = if touch then 14 else 12, Parent = b })
		local scale = new("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.08 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
		end)
		b.Activated:Connect(function()
			Theme.play("click", 0.3)
			if e.sub then
				if subFor == e.name then
					closeSub()
				else
					Windows.close()
					local before = 0
					for j = 1, i - 1 do
						if buttons[ENTRIES[j].name].holder.Visible then
							before += 1
						end
					end
					openSub(e, holder, before * (SIZE + gap))
				end
			else
				closeSub()
				Windows.toggle(e.window)
			end
		end)
		buttons[e.name] = { frame = b, badge = Theme.badge(b), holder = holder }
	end
end

local function refresh()
	local s = Net.state
	if not s then
		return
	end
	local step = s.story and s.story.step or 1
	for _, e in ENTRIES do
		buttons[e.name].holder.Visible = step >= e.from
	end
	-- badges: something to claim
	local rewards = false
	if s.dailyState and s.dailyState.canClaim then
		rewards = true
	end
	local elapsed = Panels2.now() - (s.sessionStart or 0)
	for i, g in Config.Gifts do
		if elapsed >= g.minutes * 60 and not (s.giftsClaimed and s.giftsClaimed[i]) then
			rewards = true
		end
	end
	buttons.Rewards.badge.Visible = rewards
	local quests = false
	if s.quests then
		for _, q in s.quests.list do
			if q.progress >= q.target and not q.claimed then
				quests = true
			end
		end
	end
	buttons.Quests.badge.Visible = quests
	buttons.Season.badge.Visible = s.season ~= nil and (s.season.claimable or 0) > 0
	local warrior = (s.auraSpin and (s.auraSpin.freeToday or (s.spins or 0) > 0)) or false
	buttons.Warrior.badge.Visible = warrior
end

function Menu.init()
	Kit.notify = Toasts.show
	Panels1.init()
	Panels2.init()
	Panels3.init()
	build()
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
	Lang.Changed:Connect(closeSub)
	Windows.Changed:Connect(function(name)
		-- a window owns the screen: no punching through it
		Controls.enabled = name == nil
		if name then
			closeSub()
		end
	end)
	WorldFx.onPrompt.TravelPrompt = function()
		Windows.open("Travel")
	end
	WorldFx.onPrompt.WishPrompt = function()
		Windows.open("Wish")
	end
	task.spawn(function()
		while true do
			task.wait(5)
			refresh()
		end
	end)
	refresh()
end

return Menu
