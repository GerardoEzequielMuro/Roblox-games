--!nonstrict
-- Auto-Farm panel: three switches (harvest / plant / sell). The server decides what is unlocked and does the
-- work on its own timer; this panel only shows the state and asks for a switch to be flipped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.AutoFarm)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local AutoPanel = {}

local MODES = {
	{ id = "harvest", icon = "🧺", color = Theme.C.Green },
	{ id = "plant", icon = "🌱", color = Theme.C.Teal },
	{ id = "sell", icon = "💰", color = Theme.C.Gold },
}

-- Status from the last server snapshot (safe defaults before the first one arrives).
function AutoPanel.info(): any
	local d = State.data
	local a = d and d.auto
	if type(a) ~= "table" then
		local off = { harvest = false, plant = false, sell = false }
		return { level = 0, pass = false, allowed = off, wanted = off, on = off, seed = "", interval = 0, batch = 0 }
	end
	return a
end

-- Is anything actually running?
function AutoPanel.active(): boolean
	local on = AutoPanel.info().on
	return on.harvest or on.plant or on.sell
end

-- Tell the server which seed to replant: the one selected in the hotbar.
local lastSeedSent: string? = nil
local function syncSeed()
	local seed = State.selectedSeed
	local info = AutoPanel.info()
	if seed and Config.SeedById[seed] and info.allowed.plant and info.wanted.plant and info.seed ~= seed and lastSeedSent ~= seed then
		lastSeedSent = seed
		task.spawn(function()
			Net.request("SetAutoSeed", { seedId = seed }, { quiet = true, silentOk = true })
		end)
	end
end

function AutoPanel.build(root: Instance, openUpgrades: (() -> ())?)
	local p = C.panel(root, {
		Name = "AutoPanel",
		Title = L("auto.title"),
		Icon = "🤖",
		Color = Theme.C.Teal,
		Size = UDim2.fromOffset(600, 430),
	})
	local body = p.content
	C.list(body, true, 8, Enum.HorizontalAlignment.Center)

	local rows: { [string]: { toggle: TextButton, desc: TextLabel, card: Frame } } = {}
	for i, m in MODES do
		local card = C.card(body, UDim2.new(1, 0, 0, 84), Theme.darken(m.color, 0.1), { LayoutOrder = i })
		local icon: Frame = C.new("Frame", {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(12, 12),
			BackgroundColor3 = m.color,
			Parent = card,
		})
		C.corner(icon, 14)
		C.stroke(icon, 3, Theme.darken(m.color, 0.4))
		C.shade(icon)
		C.label(icon, m.icon, UDim2.fromScale(1, 1), { TextSize = 34, Outline = false })
		C.label(card, L("auto." .. m.id), UDim2.new(1, -270, 0, 28), {
			Position = UDim2.fromOffset(84, 10),
			TextSize = 24,
			TextColor3 = Theme.C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Outline = false,
		})
		local desc = C.label(card, "", UDim2.new(1, -270, 0, 36), {
			Position = UDim2.fromOffset(84, 40),
			Font = Theme.FontAlt,
			TextSize = 14,
			TextColor3 = Theme.C.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Outline = false,
		})
		local toggle = C.button({
			Name = "Toggle_" .. m.id,
			Parent = card,
			Text = "",
			TextSize = 20,
			Color = Theme.C.Grey,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(164, 56),
			OnClick = function()
				local info = AutoPanel.info()
				if not info.allowed[m.id] then
					if openUpgrades then
						openUpgrades()
					end
					return
				end
				local turnOn = not info.wanted[m.id]
				local ok = Net.request("SetAuto", { mode = m.id, on = turnOn }, { silentOk = true })
				if ok and m.id == "plant" and turnOn then
					lastSeedSent = nil
					task.delay(0.4, syncSeed)
				end
			end,
		})
		rows[m.id] = { toggle = toggle, desc = desc, card = card }
	end

	local speed = C.label(body, "", UDim2.new(1, 0, 0, 22), {
		TextSize = 17,
		TextColor3 = Theme.C.Ink,
		Outline = false,
		LayoutOrder = 10,
	})
	C.label(body, L("auto.passHint"), UDim2.new(1, 0, 0, 20), {
		Font = Theme.FontAlt,
		TextSize = 13,
		TextColor3 = Theme.C.InkSoft,
		Outline = false,
		LayoutOrder = 11,
	})

	local function refresh()
		local info = AutoPanel.info()
		for _, m in MODES do
			local row = rows[m.id]
			if info.allowed[m.id] then
				local on = info.wanted[m.id] == true
				C.setColor(row.toggle, if on then Theme.C.Green else Theme.C.Red)
				C.setText(row.toggle, L(if on then "auto.stateOn" else "auto.stateOff"))
			else
				C.setColor(row.toggle, Theme.C.Purple)
				C.setText(row.toggle, L("auto.locked", { n = Rules.requiredLevel(Config.AutoFarm, m.id) }))
			end
			if m.id == "plant" then
				local seed = if info.seed ~= "" then info.seed else State.selectedSeed
				local name = if seed and Config.SeedById[seed] then { key = "seed." .. seed } else { key = "auto.noSeed" }
				I18n.set(row.desc, "Text", L("auto.plantDesc", { seed = name }))
			else
				I18n.set(row.desc, "Text", L("auto." .. m.id .. "Desc"))
			end
		end
		if info.allowed.harvest then
			I18n.set(speed, "Text", L("auto.speed", { sec = info.interval, n = info.batch }))
		else
			I18n.set(speed, "Text", L("auto.unlockHint"))
		end
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
			syncSeed()
		elseif kind == "selected" then
			lastSeedSent = nil
			syncSeed()
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return AutoPanel
