--!nonstrict
-- Session play-time gifts: 6 cards (locked countdown / CLAIM / claimed). Readiness is computed locally from the
-- server's sessionStart so the countdown ticks without server pushes; the server re-validates every claim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local GiftsPanel = {}

-- Loc value describing a gift's reward.
function GiftsPanel.describe(g: any): any
	local parts: { any } = {}
	if g.cashMinutes then
		table.insert(parts, { key = "gift.cashMinutes", args = { n = g.cashMinutes } })
	end
	if g.cash then
		table.insert(parts, Format.cash(g.cash))
	end
	if g.seeds then
		for id, n in g.seeds do
			table.insert(parts, { key = "reward.seeds", args = { n = n, seed = { key = "seed." .. id } } })
		end
	end
	if g.boost then
		table.insert(parts, {
			key = if g.boost.kind == "cash" then "reward.boostCash" else "reward.boostGrowth",
			args = { mult = g.boost.mult, min = math.floor(g.boost.seconds / 60) },
		})
	end
	if g.luckyPack then
		table.insert(parts, { key = "product.LuckyPack.name" })
	end
	return L("daily.reward", { list = { list = parts, sep = " + " } })
end

local function emojiFor(g: any): string
	if g.luckyPack then
		return "🎲"
	elseif g.boost then
		return "⚡"
	elseif g.seeds then
		for id in g.seeds do
			return Theme.seedEmoji(id)
		end
	end
	return "💵"
end

local function claimedMap(): { [number]: boolean }
	local out = {}
	local d = State.data
	if d and type(d.gifts) == "table" then
		for i, g in d.gifts do
			if g.claimed then
				out[i] = true
			end
		end
	end
	return out
end

function GiftsPanel.readyCount(): number
	local d = State.data
	if not d or type(d.sessionStart) ~= "number" then
		return 0
	end
	local _, n = Gifts.ready(Config.PlaytimeGifts, d.sessionStart, State.now(), claimedMap())
	return n
end

function GiftsPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "GiftsPanel",
		Title = L("panel.gifts"),
		Icon = "⏰",
		Color = Theme.C.Red,
		Size = UDim2.fromOffset(700, 470),
	})
	C.label(p.content, L("gifts.subtitle"), UDim2.new(1, 0, 0, 28), {
		TextSize = 20,
		TextColor3 = Theme.C.Ink,
		Outline = false,
	})
	local grid: Frame = C.new("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		Parent = p.content,
	})
	C.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(204, 164),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	type Cell = { card: Frame, btn: TextButton, border: UIStroke }
	local cells: { Cell } = {}
	for i, g in Config.PlaytimeGifts do
		local card = C.card(grid, UDim2.new(), Theme.darken(Theme.C.Red, 0.1), { LayoutOrder = i, Name = "Gift" .. i })
		local border = card:FindFirstChild("Border") :: UIStroke
		C.label(card, emojiFor(g), UDim2.new(0, 50, 0, 44), {
			Position = UDim2.fromOffset(8, 6),
			TextSize = 36,
			Outline = false,
		})
		C.label(card, L("gifts.minutes", { n = g.minutes }), UDim2.new(1, -66, 0, 30), {
			Position = UDim2.fromOffset(60, 12),
			TextSize = 22,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Outline = false,
		})
		C.label(card, GiftsPanel.describe(g), UDim2.new(1, -16, 0, 40), {
			Position = UDim2.fromOffset(8, 54),
			Font = Theme.FontAlt,
			TextSize = 15,
			TextColor3 = Theme.C.InkSoft,
			Outline = false,
		})
		local btn = C.button({
			Name = "Claim",
			Parent = card,
			Text = "",
			TextSize = 22,
			Color = Theme.C.Green,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 56),
			OnClick = function()
				Net.request("ClaimGift", { index = i })
			end,
		})
		cells[i] = { card = card, btn = btn, border = border }
	end

	local function tick()
		local d = State.data
		if not d or type(d.sessionStart) ~= "number" then
			return
		end
		local now = State.now()
		local views = Gifts.ready(Config.PlaytimeGifts, d.sessionStart, now, claimedMap())
		for i, v in views do
			local cell = cells[i]
			if v.claimed then
				C.setText(cell.btn, L("gifts.claimed"))
				C.setEnabled(cell.btn, false)
				cell.border.Color = Theme.C.Green
			elseif v.ready then
				C.setText(cell.btn, L("gifts.claim"))
				C.setEnabled(cell.btn, true)
				cell.border.Color = Theme.C.Gold
			else
				C.setText(cell.btn, "⏱ " .. Format.time(Gifts.secondsLeft(Config.PlaytimeGifts[i], d.sessionStart, now)))
				C.setEnabled(cell.btn, false)
				cell.border.Color = Theme.darken(Theme.C.Panel, 0.25)
			end
		end
	end

	State.onChanged(function(kind)
		if kind == "state" then
			tick()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = tick, tick = tick }
end

return GiftsPanel
