--!nonstrict
-- Upgrades: Config.Upgrades with level bars and next cost, plus "buy next tile".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local UpgradesPanel = {}

function UpgradesPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "UpgradesPanel",
		Title = L("panel.upgrades"),
		Icon = "⚡",
		IconName = "upgrade",
		Color = Theme.C.Blue,
		Size = UDim2.fromOffset(680, 520),
	})
	local list = C.scroller(p.content, UDim2.fromScale(1, 1))
	C.list(list, true, 10)

	type Row = { level: TextLabel, bar: C.Bar, buy: TextButton }
	local rows: { [string]: Row } = {}

	local function makeRow(order: number, emoji: string, name: any, desc: any, color: Color3, onBuy: () -> ()): Row
		local card = C.card(list, UDim2.new(1, 0, 0, 104), Theme.darken(color, 0.1), { LayoutOrder = order })
		local icon: Frame = C.new("Frame", {
			Size = UDim2.fromOffset(78, 78),
			Position = UDim2.fromOffset(12, 13),
			BackgroundColor3 = color,
			Parent = card,
		})
		C.corner(icon, 16)
		C.stroke(icon, 3, Theme.darken(color, 0.4))
		C.shade(icon)
		C.icon(icon, emoji, UDim2.fromScale(1, 1), { TextSize = 42, Outline = false })

		C.label(card, name, UDim2.fromOffset(240, 30), {
			Position = UDim2.fromOffset(104, 8),
			TextSize = 26,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Outline = false,
		})
		local level = C.label(card, "", UDim2.fromOffset(120, 26), {
			Position = UDim2.fromOffset(330, 10),
			TextSize = 20,
			TextColor3 = Theme.darken(color, 0.2),
			TextXAlignment = Enum.TextXAlignment.Left,
			Outline = false,
		})
		C.label(card, desc, UDim2.fromOffset(330, 20), {
			Position = UDim2.fromOffset(104, 40),
			Font = Theme.FontAlt,
			TextSize = 15,
			TextColor3 = Theme.C.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			Outline = false,
		})
		local bar = C.progressBar(card, UDim2.fromOffset(320, 18), color, { Position = UDim2.fromOffset(104, 70) })
		local buy = C.button({
			Parent = card,
			Text = "$0",
			TextSize = 22,
			Color = Theme.C.Green,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(150, 56),
			OnClick = onBuy,
		})
		return { level = level, bar = bar, buy = buy }
	end

	local colors = { Theme.C.Green, Theme.C.Gold, Theme.C.Teal, Theme.C.Orange }
	for i, u in Config.Upgrades do
		rows[u.id] = makeRow(i, Theme.UpgradeEmoji[u.id] or "⬆️", L("upgrade." .. u.id .. ".name"), L("upgrade." .. u.id .. ".desc"), colors[(i - 1) % #colors + 1], function()
			Net.request("BuyUpgrade", { id = u.id })
		end)
	end
	local tileRow = makeRow(100, "🟫", L("upgrades.tile"), L("upgrades.tileDesc"), Theme.C.Purple, function()
		Net.request("BuyTile")
	end)

	local function refresh()
		local d = State.data
		if not d then
			return
		end
		local cash = d.cash or 0
		local levels = d.upgrades or {}
		local costs = d.upgradeCosts or {}
		for _, u in Config.Upgrades do
			local row = rows[u.id]
			local lvl = levels[u.id] or 0
			row.level.Text = I18n.t("upgrades.level", { lvl = lvl, max = u.maxLevel })
			row.bar.set(lvl / u.maxLevel)
			local cost = costs[u.id]
			if cost == nil or lvl >= u.maxLevel then
				C.setText(row.buy, L("upgrades.max"))
				C.setEnabled(row.buy, false)
			else
				C.setText(row.buy, Format.cash(cost))
				C.setEnabled(row.buy, cash >= cost)
			end
		end
		local owned = d.tilesOwned or 0
		tileRow.level.Text = string.format("%d/%d", owned, Config.MaxTiles)
		tileRow.bar.set(owned / Config.MaxTiles)
		if owned >= Config.MaxTiles or not d.tileCost then
			C.setText(tileRow.buy, L("upgrades.max"))
			C.setEnabled(tileRow.buy, false)
		else
			C.setText(tileRow.buy, Format.cash(d.tileCost))
			C.setEnabled(tileRow.buy, cash >= d.tileCost)
		end
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return UpgradesPanel
