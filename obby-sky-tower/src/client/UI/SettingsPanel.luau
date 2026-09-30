--!strict
-- Settings: coil toggles (speed / gravity; if the pass isn't owned the toggle offers it), the
-- visual-effects switch for slow devices, and the language picker.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Toast = require(script.Parent.Toast)
local Lang = require(script.Parent.Parent.Lang)
local Locale = require(ReplicatedStorage.Shared.Locale)

local SettingsPanel = {}

type Row = { key: string, pass: string?, title: string, desc: string }
local ROWS: { Row } = {
	{ key = "speedCoil", pass = "SpeedCoil", title = "@settings.speed", desc = "@settings.speed_desc" },
	{ key = "gravityCoil", pass = "GravityCoil", title = "@settings.gravity", desc = "@settings.gravity_desc" },
	{ key = "effects", pass = nil, title = "@settings.effects", desc = "@settings.effects_desc" },
}
local ROW_H = 64
local ROW_PITCH = 70
local LANG_TOP = #ROWS * ROW_PITCH -- 210
local LANG_H = 45
local LANG_PITCH = 49

local function isOn(row: Row): boolean
	local settings = Net.state.settings or {}
	-- effects default to on (profiles saved before the switch existed have no value yet)
	return if row.key == "effects" then settings.effects ~= false else settings[row.key] == true
end

function SettingsPanel.init()
	local content = Kit.panel("settings", "@panel.settings", Kit.C.grey)
	local buttons: { [string]: TextButton } = {}
	local cards: { Frame } = {}
	local labels: { TextLabel } = {}
	for i, row in ROWS do
		local card = Kit.frame(content, UDim2.new(1, 0, 0, ROW_H), UDim2.fromOffset(0, (i - 1) * ROW_PITCH), Kit.C.card)
		cards[i] = card
		Kit.corner(card, 16)
		Kit.stroke(card, Color3.fromRGB(220, 210, 235), 3)
		local t = Kit.text(card, row.title, UDim2.new(1, -196, 0, 30), UDim2.fromOffset(18, 4), Kit.C.ink, nil, 27)
		t.TextXAlignment = Enum.TextXAlignment.Left
		labels[#labels + 1] = t
		local d = Kit.text(card, row.desc, UDim2.new(1, -196, 0, 22), UDim2.fromOffset(18, 36), Color3.fromRGB(110, 105, 140), nil, 18)
		d.TextXAlignment = Enum.TextXAlignment.Left
		labels[#labels + 1] = d
		local pass = row.pass
		buttons[row.key] = Kit.button(card, "", UDim2.fromOffset(160, 50), UDim2.new(1, -10, 0.5, 0), Kit.C.green, function()
			if pass and not Net.hasPass(pass) then
				local id = Config.Passes[pass] or 0
				if id ~= 0 then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
				else
					Toast.show(Lang.t("toast.pass_not_on_sale"), "info")
				end
				return
			end
			local ok, msg = Net.request("SetSetting", { key = row.key, value = not isOn(row) })
			if not ok and msg then
				Toast.show(msg, "error")
			end
		end, Vector2.new(1, 0.5), 26)
		buttons[row.key].Name = "Toggle_" .. row.key
	end

	-- language picker: 4 x 3 grid of flag + native name (saved in the profile, applied live)
	local langTitle = Kit.text(content, "@settings.language", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, LANG_TOP - 1), Kit.C.ink, nil, 22)
	langTitle.TextXAlignment = Enum.TextXAlignment.Left
	local langButtons: { [string]: TextButton } = {}
	for i, code in Locale.LANGS do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local info = Locale.NATIVE[code]
		local b = Kit.button(content, info.flag .. " " .. info.name, UDim2.new(0.25, -6, 0, LANG_H), UDim2.new(col * 0.25, col * 2, 0, LANG_TOP + 22 + row * LANG_PITCH), Kit.C.blue, function()
			local ok, msg = Net.request("SetLanguage", { lang = code })
			if ok then
				Toast.show(Lang.t("toast.language", { name = info.name }), "success")
			elseif msg then
				Toast.show(msg, "error")
			end
		end, nil, 20)
		b.Name = "Lang_" .. code
		langButtons[code] = b
	end

	-- Touch: the panel is a wide, short box (see Kit.panel), so the coils sit side by side and
	-- the 12 languages go in 6 columns; every button is >= 54 design px tall.
	Kit.onLayout(function(touch)
		for i, card in cards do
			if touch then
				local half = i <= 2
				card.Size = UDim2.new(if half then 0.5 else 1, if half then -4 else 0, 0, ROW_H)
				card.Position = UDim2.new(if i == 2 then 0.5 else 0, if i == 2 then 4 else 0, 0, if i == 3 then ROW_PITCH else 0)
			else
				card.Size = UDim2.new(1, 0, 0, ROW_H)
				card.Position = UDim2.fromOffset(0, (i - 1) * ROW_PITCH)
			end
		end
		for i, row in ROWS do
			local b = buttons[row.key]
			b.Size = if touch then UDim2.fromOffset(132, 56) else UDim2.fromOffset(160, 50)
		end
		for i, l in labels do
			l.Size = UDim2.new(1, if touch then -(132 + 40) else -196, 0, l.Size.Y.Offset)
		end
		local top = if touch then 2 * ROW_PITCH + 6 else LANG_TOP
		langTitle.Position = UDim2.fromOffset(0, top - 1)
		for i, code in Locale.LANGS do
			local b = langButtons[code]
			local col, r = (i - 1) % (if touch then 6 else 4), (i - 1) // (if touch then 6 else 4)
			if touch then
				b.Size = UDim2.new(1 / 6, -6, 0, 54)
				b.Position = UDim2.new(col / 6, col, 0, top + 24 + r * 60)
			else
				b.Size = UDim2.new(0.25, -6, 0, LANG_H)
				b.Position = UDim2.new(col * 0.25, col * 2, 0, LANG_TOP + 22 + r * LANG_PITCH)
			end
		end
	end)

	local function refresh()
		for code, b in langButtons do
			b.BackgroundColor3 = if code == Lang.code then Kit.C.green else Kit.C.blue
		end
		for _, row in ROWS do
			local b = buttons[row.key]
			if row.pass and not Net.hasPass(row.pass) then
				Kit.setText(b, "settings.get_pass")
				b.BackgroundColor3 = Kit.C.yellow
			elseif isOn(row) then
				Kit.setText(b, "settings.on")
				b.BackgroundColor3 = Kit.C.green
			else
				Kit.setText(b, "settings.off")
				b.BackgroundColor3 = Kit.C.red
			end
		end
	end
	Kit.onOpen("settings", refresh)
	Net.changed:Connect(refresh)
	Lang.changed:Connect(refresh)
end

return SettingsPanel
