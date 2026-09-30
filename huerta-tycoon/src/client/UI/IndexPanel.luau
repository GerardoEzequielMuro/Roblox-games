--!nonstrict
-- Crop x mutation Index: one row per seed with a chip per variant (Normal + every mutation), grey until found.
-- Completing a row lets you claim cash + a permanent cash bonus.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local IndexPanel = {}

local VARIANTS = { "Normal" }
for _, m in Config.Mutations do
	table.insert(VARIANTS, m.id)
end

local function rowOf(seedId: string): any
	local d = State.data
	return d and type(d.index) == "table" and d.index[seedId] or nil
end

function IndexPanel.claimableCount(): number
	local n = 0
	for _, seed in Config.Seeds do
		local r = rowOf(seed.id)
		if r and not r.claimed and r.found >= r.total then
			n += 1
		end
	end
	return n
end

function IndexPanel.build(root: Instance, openOdds: (() -> ())?)
	local p = C.panel(root, {
		Name = "IndexPanel",
		Title = L("panel.index"),
		Icon = "📖",
		Color = Theme.C.GreenDark,
		Size = UDim2.fromOffset(720, 520),
	})
	local header = C.label(p.content, "", UDim2.new(1, -190, 0, 30), {
		TextSize = 22,
		TextColor3 = Theme.C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Outline = false,
	})
	-- mutation chances in numbers, one tap away
	C.button({
		Name = "Odds",
		Parent = p.content,
		Text = L("odds.button"),
		TextSize = 17,
		Color = Theme.C.Purple,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, -12),
		Size = UDim2.fromOffset(176, 54),
		OnClick = function()
			if openOdds then
				openOdds()
			end
		end,
	})
	local list = C.scroller(p.content, UDim2.new(1, 0, 1, -50), UDim2.fromOffset(0, 50))
	C.list(list, true, 8)

	type Row = { card: Frame, chips: { [string]: TextLabel }, btn: TextButton, status: TextLabel }
	local rows: { [string]: Row } = {}
	for i, seed in Config.Seeds do
		local rc = Theme.rarityColor(seed.rarity)
		local card = C.card(list, UDim2.new(1, 0, 0, 72), Theme.darken(rc, 0.1), { LayoutOrder = i, Name = "Row_" .. seed.id })
		C.label(card, Theme.seedEmoji(seed.id), UDim2.fromOffset(52, 52), {
			Position = UDim2.fromOffset(8, 10),
			TextSize = 38,
			Outline = false,
		})
		C.label(card, L("seed." .. seed.id), UDim2.fromOffset(150, 28), {
			Position = UDim2.fromOffset(64, 22),
			TextSize = 20,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Outline = false,
		})
		local chipBox: Frame = C.new("Frame", {
			Position = UDim2.fromOffset(218, 14),
			Size = UDim2.fromOffset(6 * 44 + 5 * 4, 44),
			BackgroundTransparency = 1,
			Parent = card,
		})
		C.list(chipBox, false, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		local chips = {}
		for j, v in VARIANTS do
			local chip = C.label(chipBox, Theme.MutationEmoji[v] or "✨", UDim2.fromOffset(44, 44), {
				Name = v,
				BackgroundTransparency = 0,
				BackgroundColor3 = Theme.C.Grey,
				TextSize = 26,
				Outline = false,
				LayoutOrder = j,
			})
			C.corner(chip, 12)
			chips[v] = chip
		end
		local status = C.label(card, "", UDim2.fromOffset(120, 56), {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			TextSize = 22,
			TextColor3 = Theme.C.GreenDark,
			Outline = false,
		})
		local btn = C.button({
			Name = "Claim",
			Parent = card,
			Text = L("index.claim"),
			TextSize = 20,
			Color = Theme.C.Gold,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(120, 56),
			OnClick = function()
				Net.request("ClaimIndex", { seedId = seed.id })
			end,
		})
		rows[seed.id] = { card = card, chips = chips, btn = btn, status = status }
	end

	local function refresh()
		local d = State.data
		if not d or type(d.index) ~= "table" then
			return
		end
		local found, total = 0, 0
		for _, seed in Config.Seeds do
			local r = d.index[seed.id] or { found = 0, total = #VARIANTS, claimed = false, variants = {} }
			local row = rows[seed.id]
			found += r.found
			total += r.total
			local have = {}
			for _, v in r.variants or {} do
				have[v] = true
			end
			for v, chip in row.chips do
				local m = Config.MutationById[v]
				chip.BackgroundColor3 = if have[v] then (if m then m.color else Theme.C.Green) else Color3.fromRGB(205, 200, 192)
				chip.TextTransparency = if have[v] then 0 else 0.65
			end
			local complete = r.found >= r.total
			row.btn.Visible = complete and not r.claimed
			row.status.Visible = not row.btn.Visible
			row.status.Text = if r.claimed then "✅" else string.format("%d/%d", r.found, r.total)
		end
		local pct = if total > 0 then math.floor(found / total * 100) else 0
		I18n.set(header, "Text", L("index.header", { pct = pct, bonus = math.floor((d.indexBonus or 0) * 100 + 0.5) }))
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return IndexPanel
