--!nonstrict
-- Trophy Shelf panel: the 3 pedestals of your plot and the special crops in your basket that could go on them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Trophies)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local TrophiesPanel = {}

-- "Giant Golden Pumpkin" in the current language.
function TrophiesPanel.itemName(seedId: string, mutation: string?, size: string?): string
	local parts = {}
	if size then
		table.insert(parts, I18n.t("size." .. size))
	end
	if mutation then
		table.insert(parts, I18n.t("mutation." .. mutation))
	end
	table.insert(parts, I18n.t("seed." .. seedId))
	return table.concat(parts, " ")
end

local function luckText(size: string?, mutation: string?): string
	local m = if mutation then Config.MutationById[mutation] else nil
	return string.format("🍀 +%d%%", math.floor(Rules.luckOf(size, if m then m.multiplier else nil) * 100 + 0.5))
end

-- Basket stacks that can go on a pedestal.
function TrophiesPanel.candidates(): { any }
	local out = {}
	local d = State.data
	if d and type(d.backpack) == "table" then
		for _, it in d.backpack do
			if Rules.eligible(it.mutation, it.size) then
				table.insert(out, it)
			end
		end
	end
	return out
end

function TrophiesPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "TrophiesPanel",
		Title = L("panel.trophies"),
		Icon = "🏆",
		Color = Theme.C.Gold,
		Size = UDim2.fromOffset(640, 500),
	})
	local body = p.content
	local bonus = C.label(body, "", UDim2.new(1, 0, 0, 28), {
		TextSize = 22,
		TextColor3 = Theme.C.GreenDark,
		Outline = false,
	})
	C.label(body, L("trophies.hint"), UDim2.new(1, 0, 0, 34), {
		Position = UDim2.fromOffset(0, 28),
		Font = Theme.FontAlt,
		TextSize = 13,
		TextColor3 = Theme.C.InkSoft,
		Outline = false,
	})

	-- the 3 pedestals
	local slots: { { card: Frame, name: TextLabel, luck: TextLabel, btn: TextButton } } = {}
	local slotRow: Frame = C.new("Frame", {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 132),
		BackgroundTransparency = 1,
		Parent = body,
	})
	C.list(slotRow, false, 10, Enum.HorizontalAlignment.Center)
	for i = 1, Rules.SLOTS do
		local card = C.card(slotRow, UDim2.fromOffset(190, 132), Theme.darken(Theme.C.Gold, 0.15), { LayoutOrder = i, Name = "Slot" .. i })
		local name = C.label(card, "", UDim2.new(1, -12, 0, 40), {
			Position = UDim2.fromOffset(6, 6),
			TextSize = 17,
			TextColor3 = Theme.C.Ink,
			Outline = false,
		})
		local luck = C.label(card, "", UDim2.new(1, 0, 0, 22), {
			Position = UDim2.fromOffset(0, 46),
			TextSize = 18,
			TextColor3 = Theme.C.GreenDark,
			Outline = false,
		})
		local btn = C.button({
			Name = "TakeBack",
			Parent = card,
			Text = L("trophies.remove"),
			TextSize = 16,
			Color = Theme.C.Orange,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -16, 0, 54),
			OnClick = function()
				Net.request("Unexhibit", { slot = i })
			end,
		})
		slots[i] = { card = card, name = name, luck = luck, btn = btn }
	end

	local list = C.scroller(body, UDim2.new(1, 0, 1, -208), UDim2.fromOffset(0, 208))
	C.list(list, true, 6)
	local empty = C.label(list, L("trophies.none"), UDim2.new(1, 0, 0, 60), {
		TextSize = 17,
		TextColor3 = Theme.C.InkSoft,
		Outline = false,
		LayoutOrder = 999,
	})
	local rows: { Frame } = {}

	local function refresh()
		local d = State.data
		if not d then
			return
		end
		local trophies = if type(d.trophies) == "table" then d.trophies else {}
		I18n.set(bonus, "Text", L("trophies.bonus", { pct = math.floor((d.trophyLuck or 0) * 100 + 0.5) }))
		for i, slot in slots do
			local t = trophies[i]
			if t then
				slot.name.Text = Theme.seedEmoji(t.seedId) .. " " .. TrophiesPanel.itemName(t.seedId, t.mutation, t.size)
				slot.luck.Text = luckText(t.size, t.mutation)
				slot.btn.Visible = true
			else
				I18n.set(slot.name, "Text", L("trophies.empty"))
				slot.luck.Text = ""
				slot.btn.Visible = false
			end
		end
		for _, r in rows do
			r:Destroy()
		end
		table.clear(rows)
		local full = #trophies >= Rules.SLOTS
		local cands = TrophiesPanel.candidates()
		for i, it in cands do
			local seed = Config.SeedById[it.seedId]
			local card = C.card(list, UDim2.new(1, 0, 0, 66), Theme.darken(Theme.rarityColor(seed and seed.rarity), 0.1), { LayoutOrder = i })
			C.label(card, string.format("%s %s  x%d", Theme.seedEmoji(it.seedId), TrophiesPanel.itemName(it.seedId, it.mutation, it.size), it.count), UDim2.new(1, -270, 1, 0), {
				Position = UDim2.fromOffset(12, 0),
				TextSize = 18,
				TextColor3 = Theme.C.Ink,
				TextXAlignment = Enum.TextXAlignment.Left,
				Outline = false,
			})
			C.label(card, luckText(it.size, it.mutation), UDim2.fromOffset(90, 66), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -168, 0, 0),
				TextSize = 18,
				TextColor3 = Theme.C.GreenDark,
				Outline = false,
			})
			local btn = C.button({
				Name = "Exhibit",
				Parent = card,
				Text = L("trophies.exhibit"),
				TextSize = 18,
				Color = Theme.C.Gold,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(150, 54),
				OnClick = function()
					Net.request("Exhibit", { key = it.key })
				end,
			})
			C.setEnabled(btn, not full)
			table.insert(rows, card)
		end
		empty.Visible = #cands == 0
	end

	State.onChanged(function(kind)
		if kind == "state" and p.frame.Visible then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return TrophiesPanel
