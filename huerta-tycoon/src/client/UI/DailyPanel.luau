--!nonstrict
-- Daily reward: 7-day streak strip, claim button and countdown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local DailyPanel = {}

local function rewardText(r: any): (string, any)
	local parts: { any } = {}
	local emoji = "💵"
	if type(r.seeds) == "table" then
		for id, n in r.seeds do
			table.insert(parts, { key = "reward.seeds", args = { n = n, seed = { key = "seed." .. id } } })
			emoji = Theme.seedEmoji(id)
		end
	end
	if r.cash then
		table.insert(parts, Format.cash(r.cash))
	end
	-- "{list}" renders the parts joined with " + " in the current language
	return emoji, L("daily.reward", { list = { list = parts, sep = " + " } })
end

-- Is the daily reward claimable right now? (server flag, or the cooldown has passed since the last snapshot)
function DailyPanel.canClaim(): boolean
	local d = State.data
	if not d or type(d.daily) ~= "table" then
		return false
	end
	if d.daily.canClaim then
		return true
	end
	local nextAt = tonumber(d.daily.nextAt) or 0
	return nextAt > 0 and State.now() >= nextAt
end

function DailyPanel.build(root: Instance)
	local days = #Config.DailyRewards
	local p = C.panel(root, {
		Name = "DailyPanel",
		Title = L("panel.daily"),
		Icon = "🎁",
		Color = Theme.C.Orange,
		Size = UDim2.fromOffset(720, 420),
	})
	local body = p.content

	C.label(body, L("daily.subtitle"), UDim2.new(1, 0, 0, 28), {
		TextSize = 20,
		TextColor3 = Theme.C.Ink,
		Outline = false,
	})

	local strip: Frame = C.new("Frame", {
		Size = UDim2.new(1, 0, 0, 150),
		Position = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 1,
		Parent = body,
	})
	C.list(strip, false, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	type Cell = { card: Frame, check: TextLabel, scale: UIScale, border: UIStroke }
	local cells: { Cell } = {}
	for i, r in Config.DailyRewards do
		local emoji, txt = rewardText(r)
		local card = C.card(strip, UDim2.fromOffset(84, 136), nil, { LayoutOrder = i })
		local border = card:FindFirstChild("Border") :: UIStroke
		local scale = C.new("UIScale", { Parent = card })
		C.label(card, L("daily.day", { n = i }), UDim2.new(1, -6, 0, 24), {
			Position = UDim2.fromOffset(0, 6),
			TextSize = 18,
			TextColor3 = Theme.C.Ink,
			Outline = false,
		})
		C.icon(card, emoji, UDim2.new(1, 0, 0, 44), {
			Position = UDim2.fromOffset(0, 30),
			TextSize = 36,
			Outline = false,
		})
		C.label(card, txt, UDim2.new(1, -8, 0, 52), {
			Position = UDim2.fromOffset(4, 76),
			Font = Theme.FontAlt,
			TextSize = 13,
			TextColor3 = Theme.C.InkSoft,
			TextYAlignment = Enum.TextYAlignment.Top,
			Outline = false,
		})
		local check = C.label(card, "✅", UDim2.fromScale(1, 1), {
			TextSize = 48,
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Color3.fromRGB(220, 255, 220),
			Outline = false,
			Visible = false,
			ZIndex = 3,
		})
		C.corner(check, 16)
		cells[i] = { card = card, check = check, scale = scale, border = border }
	end

	local streakLbl = C.label(body, L("daily.streak", { n = 0 }), UDim2.new(1, 0, 0, 30), {
		Position = UDim2.fromOffset(0, 196),
		TextSize = 24,
		TextColor3 = Theme.C.Orange,
		Outline = 2,
	})

	local claimBtn = C.button({
		Parent = body,
		Text = L("daily.claim"),
		TextSize = 28,
		Color = Theme.C.Green,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 236),
		Size = UDim2.fromOffset(320, 64),
		OnClick = function()
			Net.request("ClaimDaily")
		end,
	})

	local currentIdx = 1

	local function refresh()
		local d = State.data
		if not d or type(d.daily) ~= "table" then
			return
		end
		local streak = d.daily.streak or 0
		local can = DailyPanel.canClaim()
		-- streak = days already claimed in a row; the next reward is (streak % days) + 1
		local claimedInCycle = streak % days
		if streak > 0 and claimedInCycle == 0 and not can then
			claimedInCycle = days
		end
		currentIdx = (streak % days) + 1
		I18n.set(streakLbl, "Text", L("daily.streak", { n = streak }))
		for i, cell in cells do
			local claimed = i <= claimedInCycle
			local isNext = can and i == currentIdx
			cell.check.Visible = claimed
			cell.card.BackgroundColor3 = if isNext then Color3.fromRGB(255, 244, 200) else Theme.C.Card
			cell.border.Color = if isNext then Theme.C.Gold elseif claimed then Theme.C.Green else Theme.darken(Theme.C.Panel, 0.25)
			cell.border.Thickness = if isNext then 5 else 3
		end
	end

	local function tick()
		local d = State.data
		if not d or type(d.daily) ~= "table" then
			return
		end
		local can = DailyPanel.canClaim()
		if can then
			C.setText(claimBtn, L("daily.claimDay", { n = currentIdx }))
			C.setEnabled(claimBtn, true)
		else
			C.setText(claimBtn, "⏱ " .. Format.time((tonumber(d.daily.nextAt) or 0) - State.now()))
			C.setEnabled(claimBtn, false)
		end
		for i, cell in cells do
			cell.scale.Scale = if can and i == currentIdx then 1 + math.abs(math.sin(os.clock() * 3)) * 0.06 else 1
		end
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
			tick()
		end
	end)

	return {
		frame = p.frame,
		closeButton = p.close,
		onOpen = function()
			refresh()
			tick()
		end,
		tick = tick,
	}
end

return DailyPanel
