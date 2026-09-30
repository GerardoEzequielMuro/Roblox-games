--!nonstrict
-- The menu: a short column of round buttons on the left (2 columns on phones, between the
-- vitals and the thumbstick). "Warrior" and "More" fold out a text sub-menu; the rest open
-- their window. Buttons appear as the story unlocks them, so a new player starts with few.
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
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Controls = require(script.Parent.Parent.Controls)
local WorldFx = require(script.Parent.Parent.WorldFx)

local Menu = {}
local new = Theme.new
local touch = Root.isTouch

local SIZE = if touch then 46 else 52
local buttons: { [string]: { frame: TextButton, badge: Frame, holder: Frame } } = {}
Menu.buttons = buttons
local sub: Frame? = nil
local subFor: string? = nil

-- name, icon, colour, story step from which it shows (0 = always), window or submenu entries
local ENTRIES = {
	{ name = "Warrior", icon = "👤", color = Theme.Red, from = 0, sub = { "Warrior", "Forms", "Moves", "Auras", "Upgrades", "Ascend" } },
	{ name = "Quests", icon = "📜", color = Theme.Orange, from = 0, window = "Quests" },
	{ name = "Rewards", icon = "🎁", color = Theme.Green, from = 0, window = "Rewards" },
	{ name = "Shop", icon = "🛒", color = Theme.Yellow, from = Config.TutorialSteps + 1, window = "Shop" },
	{ name = "More", icon = "🧭", color = Theme.Blue, from = 0, sub = { "Travel", "Ranking", "Invite", "Settings" } },
}
local SUB_ICONS = { Warrior = "👤", Forms = "🔥", Moves = "☄️", Auras = "🌀", Upgrades = "💎", Ascend = "🌟", Travel = "🪐", Ranking = "🏆", Invite = "💌", Settings = "⚙️" }

local function closeSub()
	if sub then
		sub:Destroy()
		sub = nil
		subFor = nil
	end
end

local function openSub(entry, anchor: GuiObject)
	closeSub()
	subFor = entry.name
	local h = #entry.sub * 38 + 10
	local f = Theme.panel({
		Name = "SubMenu",
		Size = UDim2.fromOffset(176, h),
		Position = UDim2.fromOffset(SIZE + 12, -6),
		ZIndex = 30,
		Parent = anchor,
	})
	new("UIScale", { Parent = f })
	for i, win in entry.sub do
		local b = new("TextButton", { Name = "Sub_" .. win, Size = UDim2.new(1, -10, 0, 34), Position = UDim2.fromOffset(5, 5 + (i - 1) * 38), BackgroundColor3 = Theme.PanelLight, BackgroundTransparency = 0.4, AutoButtonColor = true, Text = "", ZIndex = 31, Parent = f }, { Theme.corner(8) })
		Theme.text({ Text = SUB_ICONS[win] or "", Stroke = false, Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(6, 5), Parent = b }).ZIndex = 32
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
	local cols = if touch then 3 else 1
	local rows = math.ceil(#ENTRIES / cols)
	local gap = 8
	local dock = new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cols * (SIZE + gap), rows * (SIZE + 18 + gap)),
		Position = if touch then UDim2.new(0, 8, 0, 190) else UDim2.new(0, 12, 0.4, 0),
		AnchorPoint = if touch then Vector2.zero else Vector2.new(0, 0.5),
		Parent = Root.gui,
	})
	Root.mount(dock).ZIndex = 5
	for i, e in ENTRIES do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local holder = new("Frame", { Name = "Holder_" .. e.name, BackgroundTransparency = 1, Size = UDim2.fromOffset(SIZE, SIZE + 16), Position = UDim2.fromOffset(col * (SIZE + gap), row * (SIZE + 18 + gap)), Parent = dock })
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
		Theme.text({ Text = e.icon, Stroke = false, Size = UDim2.fromScale(0.58, 0.58), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = b })
		Theme.text({ Key = "menu." .. e.name, Size = UDim2.fromOffset(SIZE + 14, 14), Position = UDim2.new(0.5, 0, 1, 1), AnchorPoint = Vector2.new(0.5, 0), MaxTextSize = 12, Parent = b })
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
					openSub(e, holder)
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
	local warrior = (s.auraSpin and (s.auraSpin.freeToday or (s.spins or 0) > 0)) or false
	buttons.Warrior.badge.Visible = warrior
end

function Menu.init()
	Kit.notify = Toasts.show
	Panels1.init()
	Panels2.init()
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
