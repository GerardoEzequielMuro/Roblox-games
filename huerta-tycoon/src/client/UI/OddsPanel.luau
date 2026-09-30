--!nonstrict
-- "Chances" panel: every random outcome in numbers, straight from Shared/Odds (the same module the server rolls
-- with). Lucky Seed Pack contents + what a harvest can mutate into right now, with the player's own luck, the
-- current weather and any live event applied. Each list adds up to 100%.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Odds = require(ReplicatedStorage.Shared.Odds)
local Trophies = require(ReplicatedStorage.Shared.Trophies)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)

local OddsPanel = {}

-- "30%", "0.1%", "98.9%": never scientific notation, never more than 2 decimals.
function OddsPanel.fmt(pct: number): string
	local s = string.format("%.2f", pct)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s .. "%"
end

-- The mutation chances that apply to this player at this moment.
function OddsPanel.mutationRows(): { Odds.Row }
	local d = State.data
	local weather = State.weather.id
	local wdef = weather and Config.WeatherById[weather]
	local ev = State.liveEvent.current
	local evDef = ev and Config.LiveEventDefs[ev.id]
	return Odds.mutationTable(Config.Mutations, {
		luck = (d and d.mult and d.mult.luck) or 1,
		weather = weather,
		goldenMult = if wdef then wdef.goldenChanceMultiplier else 1,
		eventMult = (evDef and evDef.mutationMult) or 1,
	})
end

function OddsPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "OddsPanel",
		Title = L("panel.odds"),
		Icon = "🎲",
		Color = Theme.C.Purple,
		Size = UDim2.fromOffset(560, 500),
	})
	local list = C.scroller(p.content, UDim2.fromScale(1, 1))
	C.list(list, true, 6)

	local function heading(order: number, text: any): TextLabel
		return C.label(list, text, UDim2.new(1, 0, 0, 28), {
			TextSize = 20,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Outline = false,
			LayoutOrder = order,
		})
	end
	local function row(order: number, color: Color3): (TextLabel, TextLabel)
		local card = C.card(list, UDim2.new(1, 0, 0, 40), Theme.darken(color, 0.1), { LayoutOrder = order })
		local name = C.label(card, "", UDim2.new(1, -150, 1, 0), {
			Position = UDim2.fromOffset(12, 0),
			TextSize = 19,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Outline = false,
		})
		local pct = C.label(card, "", UDim2.fromOffset(120, 40), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			TextSize = 22,
			TextColor3 = Theme.darken(color, 0.35),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
			Outline = false,
		})
		return name, pct
	end

	heading(1, L("odds.lucky", { n = Odds.LuckyPerPack }))
	for i, r in Odds.luckyTable() do
		local seed = Config.SeedById[r.id]
		local name, pct = row(1 + i, Theme.rarityColor(seed and seed.rarity))
		I18n.set(name, "Text", L("seed." .. r.id, nil, Theme.seedEmoji(r.id) .. "  "))
		pct.Text = OddsPanel.fmt(r.pct)
	end

	local mutHeading = heading(20, "")
	local mutRows: { [string]: TextLabel } = {}
	for i, m in Config.Mutations do
		local name, pct = row(20 + i, m.color)
		I18n.set(name, "Text", L("mutation." .. m.id, nil, (Theme.MutationEmoji[m.id] or "✨") .. "  ", "  x" .. tostring(m.multiplier)))
		mutRows[m.id] = pct
	end
	local normalName, normalPct = row(30, Theme.C.Grey)
	I18n.set(normalName, "Text", L("odds.normal", nil, "🌱  "))
	mutRows.Normal = normalPct

	heading(32, L("odds.sizes"))
	for i, r in Trophies.sizeTable() do
		local name, pct = row(32 + i, if r.id == "Giant" then Theme.C.Gold elseif r.id == "Big" then Theme.C.Orange else Theme.C.Grey)
		if r.id == "Normal" then
			I18n.set(name, "Text", L("odds.normal", nil, "🌱  "))
		else
			local def = Trophies.SizeById[r.id]
			I18n.set(name, "Text", L("size." .. r.id, nil, "⭐  ", "  x" .. tostring(def.valueMult)))
		end
		pct.Text = OddsPanel.fmt(r.pct)
	end

	C.label(list, L("odds.note"), UDim2.new(1, 0, 0, 40), {
		Font = Theme.FontAlt,
		TextSize = 13,
		TextColor3 = Theme.C.InkSoft,
		Outline = false,
		LayoutOrder = 40,
	})

	local function refresh()
		local d = State.data
		I18n.set(mutHeading, "Text", L("odds.mutations", { luck = C.fmtMult((d and d.mult and d.mult.luck) or 1) }))
		for _, r in OddsPanel.mutationRows() do
			local lbl = mutRows[r.id]
			if lbl then
				lbl.Text = OddsPanel.fmt(r.pct)
			end
		end
	end

	State.onChanged(function(kind)
		if kind == "state" or kind == "weather" or kind == "event" then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return OddsPanel
