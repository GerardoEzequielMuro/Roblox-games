--!strict
-- Daily quests: 3 progress bars with gem rewards + a Magic Egg bonus for finishing all three.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Hud = require(script.Parent.Hud)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local QuestsWindow = {}

local ICONS = { hatch = "🥚", taps = "👆", craft = "⭐", gems = "💎", playMinutes = "⏱️", rarity = "🟣" }

function QuestsWindow.init()
	local w = Windows.create("Quests", "📜", "win.quests", Theme.Orange, Vector2.new(640, 500), 400)
	local body = w.body
	local resets = Theme.text({ Text = "", Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 22, Parent = body })
	local list = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -34), Position = UDim2.fromOffset(0, 34), Parent = body }, { Theme.list(Enum.FillDirection.Vertical, 10) })

	type Row = { frame: Frame, icon: TextLabel, text: TextLabel, bar: Frame, barText: TextLabel, button: TextButton }
	local rows: { Row } = {}
	local function makeRow(order: number, onClick: () -> ()): Row
		local frame = Theme.panel({ Size = UDim2.new(1, 0, 0, 84), LayoutOrder = order, BackgroundColor3 = Color3.new(1, 1, 1), Parent = list })
		local icon = Theme.text({ Text = "", Stroke = false, Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(12, 16), Parent = frame })
		local text = Theme.text({ Text = "", Size = UDim2.new(1, -270, 0, 30), Position = UDim2.fromOffset(74, 8), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 24, Parent = frame })
		local barBg = Theme.new("Frame", { Size = UDim2.new(1, -270, 0, 26), Position = UDim2.fromOffset(74, 46), BackgroundColor3 = Theme.PaperDark, Parent = frame }, { Theme.corner(13), Theme.stroke(2) })
		local bar = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = barBg }, { Theme.corner(13), Theme.gradient(Theme.lighten(Theme.Orange, 0.3), Theme.Orange) })
		local barText = Theme.text({ Text = "", Size = UDim2.fromScale(1, 0.85), Position = UDim2.fromScale(0, 0.08), MaxTextSize = 18, Parent = barBg })
		barText.AutoLocalize = false
		local button = Theme.button({ Text = "", Color = Theme.Grey, Size = UDim2.fromOffset(170, 56), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 22, Parent = frame, OnClick = onClick })
		return { frame = frame, icon = icon, text = text, bar = bar, barText = barText, button = button }
	end
	local function claimResult(ok: boolean, res: any)
		Toasts.show(Lang.msg(res), if ok then "success" else "error")
	end
	for i = 1, 3 do
		rows[i] = makeRow(i, function()
			claimResult(Net.request("ClaimQuest", { i = i }))
		end)
	end
	local bonus = makeRow(4, function()
		claimResult(Net.request("ClaimQuestBonus"))
	end)

	local function gemLead(b: TextButton): string
		return Theme.lead(b:FindFirstChild("Label") :: TextLabel, "💎")
	end
	local function refresh()
		Hud.refreshQuestBadge()
		if not Windows.isOpen("Quests") then
			return
		end
		local s = Net.state
		local q = s and s.quests
		if not q then
			return
		end
		local allClaimed = true
		for i, row in rows do
			local quest = q.list[i]
			row.frame.Visible = quest ~= nil
			if quest then
				Theme.setIcon(row.icon, ICONS[quest.kind] or "⭐")
				row.text.Text = Lang.t("quest." .. quest.kind, { n = Format.abbrev(quest.target) })
				row.bar.Size = UDim2.fromScale(math.clamp(quest.progress / quest.target, 0.03, 1), 1)
				row.barText.Text = Format.abbrev(quest.progress) .. " / " .. Format.abbrev(quest.target)
				if quest.claimed then
					Theme.clearLead(row.button:FindFirstChild("Label") :: TextLabel)
					Theme.setButton(row.button, "✓ " .. Lang.t("quests.done"), Theme.Grey)
				elseif quest.progress >= quest.target then
					Theme.setButton(row.button, gemLead(row.button) .. quest.gems .. "  " .. Lang.t("quests.claim"), Theme.Green)
				else
					Theme.setButton(row.button, gemLead(row.button) .. quest.gems, Theme.Grey)
				end
				if not quest.claimed then
					allClaimed = false
				end
			end
		end
		local done = 0
		for _, quest in q.list do
			if quest.claimed then
				done += 1
			end
		end
		Theme.setIcon(bonus.icon, "🔮", "egg")
		bonus.text.Text = Lang.t("quests.bonus")
		bonus.bar.Size = UDim2.fromScale(math.clamp(done / math.max(1, #q.list), 0.03, 1), 1)
		bonus.barText.Text = done .. " / " .. #q.list
		if q.bonusClaimed then
			Theme.setButton(bonus.button, "✓ " .. Lang.t("quests.done"), Theme.Grey)
		else
			Theme.setButton(bonus.button, Lang.t("quests.claim"), if allClaimed then Theme.Purple else Theme.Grey)
		end
		local now = q.serverTime + (os.clock() - Net.receivedAt)
		resets.Text = Theme.lead(resets, "⏰") .. Lang.t("quests.resets", { time = Format.time(q.resetsAt - now) })
	end
	w.onOpen = refresh
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
	-- lightweight progress pushes from the server
	Net.event("Quests").OnClientEvent:Connect(function(q)
		local s = Net.state
		if s and q then
			s.quests = q
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Quests") then
				refresh()
			end
		end
	end)
end

return QuestsWindow
