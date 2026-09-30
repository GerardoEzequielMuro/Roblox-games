--!strict
-- Rewards (7-day daily strip + play-time gifts) and Quests (3 per day + the all-done bonus).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local RewardsWindow = {}

local REWARD_ICON = { stardust = "✨", stardustMin = "✨", crystals = "💎", luck = "🍀", boost = "⚡", capsule = "🔮" }

local function rewardsWindow()
	local w = Windows.create("Rewards", "🎁", "win.rewards", Theme.Green, Vector2.new(760, 470))
	local body = w.body
	-- The window is rebuilt only when something changes state (a gift becomes ready, a
	-- claim); in between, the countdown labels are updated in place so a click is never lost.
	local tickers: { () -> () } = {}
	local signature = ""
	local function sign(): string
		local s = Net.state
		if not s then
			return ""
		end
		local since = os.clock() - Net.receivedAt
		local parts = { tostring(s.serverTime + since - s.daily.last >= Config.DailyCooldown), tostring(s.daily.streak), tostring(#s.giftsClaimed), Lang.code }
		for _, g in Config.Gifts do
			table.insert(parts, if g.minutes * 60 - (s.sessionElapsed + since) <= 0 then "1" else "0")
		end
		return table.concat(parts, "")
	end
	local function render()
		local s = Net.state
		if not s or not Windows.isOpen("Rewards") then
			return
		end
		local touch = Kit.touch
		-- touch: the window is 372 tall, so the page scrolls (the scroll position survives a rebuild)
		local keepY = 0
		local oldScroll = body:FindFirstChild("Scroll") :: ScrollingFrame?
		if oldScroll then
			keepY = oldScroll.CanvasPosition.Y
		end
		Kit.clear(body)
		local page: Instance = body
		if touch then
			local sf = Theme.new("ScrollingFrame", {
				Name = "Scroll",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Color3.fromRGB(120, 130, 190),
				CanvasSize = UDim2.fromOffset(0, 452),
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Parent = body,
			}) :: ScrollingFrame
			sf.CanvasPosition = Vector2.new(0, keepY)
			page = sf
		end
		table.clear(tickers)
		signature = sign()
		local since = os.clock() - Net.receivedAt
		local now = s.serverTime + since
		-- daily strip
		local stripY = if touch then 62 else 28
		Theme.text({ Text = Lang.t("rewards.daily", { n = s.daily.streak }), Size = UDim2.new(1, -220, 0, 24), Position = UDim2.fromOffset(0, if touch then 16 else 0), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = page })
		local strip = Theme.new("Frame", { Name = "Daily", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 104), Position = UDim2.fromOffset(0, stripY), Parent = page }, {
			Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		})
		local ready = now - s.daily.last >= Config.DailyCooldown
		local streak = if now - s.daily.last > Config.DailyBreak then 0 else s.daily.streak
		local today = streak % #Config.DailyRewards + 1
		for i, r in Config.DailyRewards do
			local isToday = i == today
			local done = i < today
			local color = if isToday and ready then Theme.Green elseif done then Theme.Grey else Theme.Blue
			local cell = Theme.new("Frame", { Name = "Day" .. i, Size = UDim2.fromOffset(98, 100), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = i, Parent = strip }, {
				Theme.corner(12), Theme.stroke(if isToday then 4 else 3, if isToday then Theme.Yellow else Theme.Ink), Theme.gradient(Theme.lighten(color, 0.1), Theme.darken(color, 0.4)),
			})
			Theme.text({ Text = Lang.t("rewards.day", { n = i }), Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 3), MaxTextSize = 16, Parent = cell })
			Theme.text({ Text = if done then "✔" else REWARD_ICON[r.kind], Stroke = done, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 22), MaxTextSize = 36, Parent = cell })
			Theme.text({ Text = Lang.rewardLabel(r), TextWrapped = true, Size = UDim2.new(1, -6, 0, 34), Position = UDim2.fromOffset(3, 63), MaxTextSize = 14, Parent = cell })
		end
		local dailyButton = Theme.button({ Name = "ClaimDaily", Text = if ready then Lang.t("rewards.claim") else Format.time(Config.DailyCooldown - (now - s.daily.last)), Color = if ready then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(200, if touch then Kit.TOUCH_BTN else 40), Position = UDim2.new(1, if touch then -208 else -200, 0, if touch then 0 else -8), TextSize = 20, Parent = page, OnClick = function()
			Kit.request("ClaimDaily")
		end })
		if not ready then
			table.insert(tickers, function()
				Theme.setButton(dailyButton, Format.time(Config.DailyCooldown - (s.serverTime + (os.clock() - Net.receivedAt) - s.daily.last)))
			end)
		end
		-- play-time gifts
		local giftsY = stripY + 112
		local giftH = if touch then 118 else 102
		Theme.text({ Key = "rewards.gifts", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, giftsY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = page })
		local gifts = Theme.new("Frame", { Name = "Gifts", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 2 * giftH + 8), Position = UDim2.fromOffset(0, giftsY + 28), Parent = page }, {
			Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(176, giftH), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local claimed = {}
		for _, i in s.giftsClaimed do
			claimed[i] = true
		end
		local elapsed = s.sessionElapsed + since
		for i, g in Config.Gifts do
			local left = g.minutes * 60 - elapsed
			local state = if claimed[i] then "done" elseif left <= 0 then "ready" else "wait"
			local color = if state == "ready" then Theme.Green elseif state == "done" then Theme.Grey else Theme.Purple
			local cell = Theme.new("Frame", { Name = "Gift" .. i, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = i, Parent = gifts }, {
				Theme.corner(12), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.1), Theme.darken(color, 0.4)),
			})
			Theme.text({ Text = REWARD_ICON[g.reward.kind], Stroke = false, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(6, 6), Parent = cell })
			Theme.text({ Text = Lang.rewardLabel(g.reward), TextWrapped = true, Size = UDim2.new(1, -56, 0, 40), Position = UDim2.fromOffset(50, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, Parent = cell })
			local giftButton = Theme.button({ Name = "Claim", Text = if state == "done" then "✔" elseif state == "ready" then Lang.t("rewards.claim") else Format.time(left), Color = if state == "ready" then Theme.Green else Theme.Grey, Size = UDim2.new(1, -12, 0, if touch then Kit.TOUCH_BTN else 38), Position = UDim2.new(0, 6, 1, if touch then -(Kit.TOUCH_BTN + 6) else -44), TextSize = 19, Parent = cell, OnClick = function()
				if state == "ready" then
					Kit.request("ClaimGift", { index = i })
				end
			end })
			if state == "wait" then
				table.insert(tickers, function()
					Theme.setButton(giftButton, Format.time(g.minutes * 60 - (s.sessionElapsed + (os.clock() - Net.receivedAt))))
				end)
			end
		end
	end
	w.onOpen = render
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			render()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Rewards") then
				if sign() ~= signature then
					render()
				else
					for _, fn in tickers do
						fn()
					end
				end
			end
		end
	end)
end

local QUEST_ICON = { planets = "🪐", hits = "⛏️", capsules = "🧬", buffs = "⚡", titan = "👑", fuse = "🌟", arena = "⚔️", sell = "🚀", minutes = "⏱️" }

local function questsWindow()
	local w = Windows.create("Quests", "📜", "win.quests", Theme.Yellow, Vector2.new(640, 440))
	local body = w.body
	local function render()
		local s = Net.state
		local q = if s then s.quests else nil
		if not s or not q or not Windows.isOpen("Quests") then
			return
		end
		Kit.clear(body)
		local resets = q.resetsAt - (q.serverTime + (os.clock() - Net.receivedAt))
		Theme.text({ Text = Lang.t("quests.resets", { time = Format.time(resets) }), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, TextColor3 = Color3.fromRGB(200, 210, 235), Parent = body })
		local allClaimed = #q.list > 0
		for i, quest in q.list do
			local done = quest.progress >= quest.target
			if not quest.claimed then
				allClaimed = false
			end
			local touch = Kit.touch
			local rowH = if touch then 64 else 76
			local row = Kit.row(body, rowH, if quest.claimed then Theme.Grey elseif done then Theme.Green else Theme.Blue, i)
			row.Name = "Quest" .. i
			row.Position = UDim2.fromOffset(0, (if touch then 26 else 28) + (i - 1) * (rowH + (if touch then 6 else 8)))
			row.Size = UDim2.new(1, 0, 0, rowH)
			local iconSize = if touch then 46 else 54
			local icon = Theme.icon(row, QUEST_ICON[quest.kind] or "📜", Theme.Yellow, iconSize)
			icon.Position = UDim2.fromOffset(8, (rowH - iconSize) // 2)
			Theme.text({ Text = Lang.t("quest." .. quest.kind, { n = Format.commas(quest.target) }), Size = UDim2.new(1, -250, 0, 26), Position = UDim2.fromOffset(72, if touch then 5 else 8), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 21, Parent = row })
			local bar = Theme.bar(row, UDim2.new(1, -250, 0, if touch then 22 else 24), Theme.Green)
			bar.frame.Position = UDim2.fromOffset(72, if touch then 36 else 42)
			bar:set(quest.progress / quest.target, Format.commas(quest.progress) .. " / " .. Format.commas(quest.target))
			Theme.button({ Name = "Claim", Text = if quest.claimed then "✔" else ("+" .. quest.crystals .. " 💎"), Color = if quest.claimed then Theme.Grey elseif done then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(150, if touch then Kit.TOUCH_BTN else 50), Position = UDim2.new(1, -160, 0.5, if touch then -Kit.TOUCH_BTN // 2 else -25), TextSize = 22, Parent = row, OnClick = function()
				if not quest.claimed then
					Kit.request("ClaimQuest", { i = i })
				end
			end })
		end
		local bonus = Kit.row(body, 64, if q.bonusClaimed then Theme.Grey else Theme.Purple, 9)
		bonus.Name = "Bonus"
		bonus.Position = UDim2.new(0, 0, 1, -66)
		bonus.Size = UDim2.new(1, 0, 0, 64)
		Theme.text({ Text = "🔮 " .. Lang.t("quests.bonus"), Size = UDim2.new(1, -190, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, TextWrapped = true, Parent = bonus })
		Theme.button({ Name = "ClaimBonus", Text = if q.bonusClaimed then "✔" else Lang.t("rewards.claim"), Color = if allClaimed and not q.bonusClaimed then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(150, if Kit.touch then Kit.TOUCH_BTN else 46), Position = UDim2.new(1, -160, 0.5, if Kit.touch then -Kit.TOUCH_BTN // 2 else -23), TextSize = 22, Parent = bonus, OnClick = function()
			if not q.bonusClaimed then
				Kit.request("ClaimQuestBonus")
			end
		end })
	end
	w.onOpen = render
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			render()
		end
	end)
	Net.event("Quests").OnClientEvent:Connect(function()
		task.defer(render)
	end)
end

function RewardsWindow.init()
	rewardsWindow()
	questsWindow()
end

return RewardsWindow
