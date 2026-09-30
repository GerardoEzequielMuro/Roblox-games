--!strict
-- Daily streak (7 days) and free in-session timed gifts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local RewardsWindow = {}

local ICONS = { taps = "👆", gems = "💎", luck = "🍀", egg = "🔮" }
-- icon pack names (Taps as a currency are the coin, the Magic Egg is the egg)
local ICON_NAMES = { taps = "coin", gems = "gem", luck = "luck", egg = "egg" }

function RewardsWindow.init()
	local w = Windows.create("Rewards", "🎁", "win.rewards", Theme.Pink, Vector2.new(820, 520))
	local body = w.body

	-- Daily
	Theme.text({ Key = "rewards.daily", Size = UDim2.new(0.5, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 28, Parent = body })
	local dailyRow = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), Position = UDim2.fromOffset(0, 34), Parent = body }, {
		Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center),
	})
	type DayCard = { frame: Frame, stroke: UIStroke, check: TextLabel }
	local days: { DayCard } = {}
	for i, r in Config.DailyRewards do
		local f = Theme.panel({ Size = UDim2.fromOffset(100, 116), LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), Parent = dailyRow })
		Theme.text({ Key = "rewards.day", Args = { n = i }, Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 4), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 20, Parent = f })
		Theme.icon(ICONS[r.kind] or "⭐", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, 0, 0, 26), AnchorPoint = Vector2.new(0.5, 0), Parent = f }, ICON_NAMES[r.kind])
		Theme.text({ Key = "rewardlabel." .. r.kind, Args = { n = r.amount }, TextWrapped = true, Size = UDim2.new(1, -8, 0, 34), Position = UDim2.fromOffset(4, 76), TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 15, Parent = f })
		local check = Theme.text({ Text = "✓", TextColor3 = Theme.Green, Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -30, 0, -8), Visible = false, Parent = f })
		days[i] = { frame = f, stroke = f:FindFirstChildOfClass("UIStroke") :: UIStroke, check = check }
	end
	local dailyButton = Theme.button({
		Text = "",
		Color = Theme.Green,
		Size = UDim2.fromOffset(280, 56),
		Position = UDim2.new(0.5, 0, 0, 162),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 28,
		Parent = body,
		OnClick = function()
			local ok, res = Net.request("ClaimDaily")
			Toasts.show(Lang.msg(res), if ok then "success" else "error")
		end,
	})

	-- Gifts
	Theme.text({ Key = "rewards.gifts", Size = UDim2.new(0.8, 0, 0, 30), Position = UDim2.fromOffset(0, 228), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 28, Parent = body })
	local giftGrid = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 180), Position = UDim2.fromOffset(0, 264), Parent = body }, {
		Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(180, 82), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	local giftButtons: { TextButton } = {}
	for i in Config.Gifts do
		giftButtons[i] = Theme.button({
			Text = "",
			Color = Theme.Purple,
			LayoutOrder = i,
			TextSize = 20,
			Parent = giftGrid,
			OnClick = function()
				local ok, res = Net.request("ClaimGift", { index = i })
				if not ok then
					Toasts.show(Lang.msg(res), "error")
				end
			end,
		})
	end

	local function refresh()
		local s = Net.state
		if not s then
			return
		end
		local serverNow = s.serverTime + (os.clock() - Net.receivedAt)
		local sinceLast = serverNow - s.daily.last
		local streak = s.daily.streak
		if sinceLast > Config.DailyStreakWindow then
			streak = 0
		end
		local todayIndex = (streak % #Config.DailyRewards) + 1
		local ready = sinceLast >= Config.DailyCooldown
		local claimedThisCycle = streak % #Config.DailyRewards
		for i, d in days do
			d.check.Visible = i <= claimedThisCycle and not (ready and claimedThisCycle == 0)
			d.stroke.Color = if i == todayIndex and ready then Theme.Green else Theme.Ink
			d.stroke.Thickness = if i == todayIndex and ready then 5 else 3
		end
		Theme.setButton(dailyButton, if ready then Lang.t("rewards.claim_day", { n = todayIndex }) else Lang.t("rewards.next_in", { time = Format.time(Config.DailyCooldown - sinceLast) }), if ready then Theme.Green else Theme.Grey)

		local elapsed = s.sessionElapsed + (os.clock() - Net.receivedAt)
		local claimed = {}
		for _, i in s.giftsClaimed do
			claimed[i] = true
		end
		for i, g in Config.Gifts do
			local b = giftButtons[i]
			local icon = ICONS[g.reward.kind] or "🎁"
			local label = Lang.rewardLabel(g.reward)
			if claimed[i] then
				Theme.setButton(b, "✓ " .. label, Theme.Grey)
			else
				local left = g.minutes * 60 - elapsed
				if left <= 0 then
					Theme.setButton(b, icon .. " " .. Lang.t("rewards.claim") .. "\n" .. label, Theme.Green)
				else
					Theme.setButton(b, icon .. " " .. Format.time(left) .. "\n" .. label, Theme.Purple)
				end
			end
		end
	end
	w.onOpen = refresh
	refresh()
	Net.Changed:Connect(function(kind)
		if kind == "full" and Windows.isOpen("Rewards") then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Rewards") then
				refresh()
			end
		end
	end)
end

return RewardsWindow
