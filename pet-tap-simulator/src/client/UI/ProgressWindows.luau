--!strict
-- Upgrades (gems), Rebirth, Teleport and Codes & Language windows.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local ProgressWindows = {}

local function request(action: string, payload: { [string]: any }?, successText: string?): (boolean, any)
	local ok, res = Net.request(action, payload)
	if ok then
		Theme.play("buy", 0.4, 1.1)
		if successText then
			Toasts.show(successText, "success")
		elseif type(res) == "table" and res.key then
			Toasts.show(Lang.msg(res), "success")
		end
	elseif res then
		Toasts.show(Lang.msg(res), "error")
	end
	return ok, res
end

local UPGRADE_ICONS = { TapPower = "👆", Luck = "🍀", PetSlots = "🐾", WalkSpeed = "👟", AutoTap = "🤖" }
local UPGRADE_ICON_NAMES = { TapPower = "fist", Luck = "luck", PetSlots = "paw", WalkSpeed = "rocket", AutoTap = "auto" }

local function upgrades()
	local w = Windows.create("Upgrades", "⬆️", "win.upgrades", Theme.Teal, Vector2.new(640, 500))
	local list = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = w.body }, { Theme.list(Enum.FillDirection.Vertical, 8) })
	type Row = { level: TextLabel, buy: TextButton, bar: Frame }
	local rows: { [string]: Row } = {}
	for i, u in Config.Upgrades do
		local row = Theme.panel({ Size = UDim2.new(1, 0, 0, 76), LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), Parent = list })
		Theme.icon(UPGRADE_ICONS[u.id] or "⭐", { Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(14, 11), Parent = row }, UPGRADE_ICON_NAMES[u.id])
		Theme.text({ Key = "upgrade." .. u.id .. ".name", Size = UDim2.new(1, -380, 0, 28), Position = UDim2.fromOffset(84, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 26, Parent = row })
		Theme.text({ Key = "upgrade." .. u.id .. ".desc", Size = UDim2.new(1, -380, 0, 20), Position = UDim2.fromOffset(84, 34), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 19, Parent = row })
		local barBg = Theme.new("Frame", { Size = UDim2.new(1, -380, 0, 10), Position = UDim2.fromOffset(84, 58), BackgroundColor3 = Theme.PaperDark, Parent = row }, { Theme.corner(5) })
		local bar = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Teal, Parent = barBg }, { Theme.corner(5) })
		local level = Theme.text({ Text = "", Size = UDim2.fromOffset(90, 30), Position = UDim2.new(1, -286, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 24, Parent = row })
		local id = u.id
		local buy = Theme.button({
			Text = "",
			Color = Theme.Teal,
			Size = UDim2.fromOffset(180, 56),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 24,
			Parent = row,
			OnClick = function()
				request("Upgrade", { id = id }, Lang.t("toast.upgraded", { name = Lang.t("upgrade." .. id .. ".name") }))
			end,
		})
		rows[u.id] = { level = level, buy = buy, bar = bar }
	end
	local function refresh()
		local s = Net.state
		if not s then
			return
		end
		for _, u in Config.Upgrades do
			local r = rows[u.id]
			local lvl = s.upgrades[u.id] or 0
			r.level.Text = Lang.t("upgrades.level", { lvl = lvl, max = u.maxLevel })
			r.bar.Size = UDim2.fromScale(lvl / u.maxLevel, 1)
			if lvl >= u.maxLevel then
				Theme.clearLead(r.buy:FindFirstChild("Label") :: TextLabel)
				Theme.setButton(r.buy, Lang.t("upgrades.max"), Theme.Grey)
			else
				local cost = Formulas.upgradeCost(u.id, lvl)
				Theme.setButton(r.buy, Theme.lead(r.buy:FindFirstChild("Label") :: TextLabel, "💎") .. Format.abbrev(cost), if s.gems >= cost then Theme.Teal else Theme.Grey)
			end
		end
	end
	w.onOpen = refresh
	Net.Changed:Connect(function()
		if Windows.isOpen("Upgrades") then
			refresh()
		end
	end)
end

local function rebirth()
	local w = Windows.create("Rebirth", "🔁", "win.rebirth", Theme.Purple, Vector2.new(600, 440))
	local body = w.body
	local info = Theme.text({ Text = "", RichText = true, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 0), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 28, Parent = body })
	-- two cards: what a rebirth takes (red) and what it gives (green)
	local function column(x: number, titleKey: string, color: Color3): TextLabel
		local card = Theme.panel({ Size = UDim2.new(0.5, -16, 0, 116), Position = UDim2.new(x, if x == 0 then 10 else 6, 0, 36), BackgroundColor3 = Theme.lighten(color, 0.82), Parent = body })
		Theme.text({ Key = titleKey, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 4), TextColor3 = Theme.darken(color, 0.15), Stroke = false, MaxTextSize = 24, Parent = card })
		return Theme.text({ Text = "", RichText = true, TextWrapped = true, Size = UDim2.new(1, -16, 1, -38), Position = UDim2.fromOffset(8, 34), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 21, Parent = card })
	end
	local loseText = column(0, "rebirth.lose", Theme.Red)
	local getText = column(0.5, "rebirth.get", Theme.Green)
	local barBg = Theme.new("Frame", { Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromOffset(20, 162), BackgroundColor3 = Theme.PaperDark, Parent = body }, { Theme.corner(17), Theme.stroke(3) })
	local bar = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = barBg }, { Theme.corner(18), Theme.gradient(Theme.lighten(Theme.Purple, 0.3), Theme.Purple) })
	local barText = Theme.text({ Text = "", Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1), MaxTextSize = 22, Parent = barBg })
	barText.AutoLocalize = false
	Theme.text({ Key = "rebirth.note", TextWrapped = true, Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 202), TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 19, Parent = body })
	local confirm = false
	local button: TextButton
	button = Theme.button({
		Key = "rebirth.button",
		Color = Theme.Purple,
		Size = UDim2.fromOffset(300, 70),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 36,
		Parent = body,
		OnClick = function()
			local s = Net.state
			if not s or s.taps < s.rebirthCost then
				Toasts.show(Lang.t("toast.not_enough_taps"), "error")
				return
			end
			if not confirm then
				confirm = true
				Theme.setButton(button, Lang.t("rebirth.confirm"), Theme.Orange)
				task.delay(3, function()
					confirm = false
					Theme.setButton(button, Lang.t("rebirth.button"), Theme.Purple)
				end)
				return
			end
			confirm = false
			Theme.setButton(button, Lang.t("rebirth.button"), Theme.Purple)
			local ok, err = Net.request("Rebirth")
			if not ok and err then
				Toasts.show(Lang.msg(err), "error")
			else
				Theme.play("buy", 0.6, 0.8)
			end
		end,
	})
	local function refresh()
		local s = Net.state
		if not s then
			return
		end
		local now = Formulas.rebirthMult(s.rebirths)
		local nxt = Formulas.rebirthMult(s.rebirths + 1)
		info.Text = Lang.t("rebirth.count", { n = "<b>" .. s.rebirths .. "</b>" })
		loseText.Text = "<b>" .. Lang.t("rebirth.lose_taps", { n = Format.abbrev(s.taps) }) .. "</b>"
		getText.Text = table.concat({
			"<b>" .. Lang.t("rebirth.mult", { from = "x" .. tostring(now), to = "x" .. tostring(nxt) }) .. "</b>",
			"💎 +" .. s.rebirthGems .. "   🎲 +" .. Config.TraitDice.rebirth,
		}, "\n")
		local pct = math.clamp(s.taps / s.rebirthCost, 0, 1)
		bar.Size = UDim2.fromScale(math.max(pct, 0.04), 1)
		barText.Text = Lang.t("rebirth.progress", { have = Format.abbrev(s.taps), need = Format.abbrev(s.rebirthCost) })
	end
	w.onOpen = refresh
	Net.Changed:Connect(function()
		if Windows.isOpen("Rebirth") then
			refresh()
		end
	end)
end

local function teleport()
	local w = Windows.create("Teleport", "🌀", "win.teleport", Theme.Yellow, Vector2.new(560, 500))
	local list = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = w.body }, { Theme.list(Enum.FillDirection.Vertical, 8) })
	local buttons: { TextButton } = {}
	local parkButton = Theme.button({
		Name = "Park",
		Text = "",
		Color = Theme.Purple,
		Size = UDim2.new(1, -10, 0, 60),
		LayoutOrder = 0,
		TextSize = 28,
		Parent = list,
		OnClick = function()
			local ok, err = Net.request("GoPark")
			if ok then
				Windows.close()
			elseif err then
				Toasts.show(Lang.msg(err), "error")
			end
		end,
	})
	for i, zone in Config.Zones do
		buttons[i] = Theme.button({
			Text = "",
			Color = Palette.rgb(zone.ground),
			Size = UDim2.new(1, -10, 0, 60),
			LayoutOrder = i,
			TextSize = 30,
			Parent = list,
			OnClick = function()
				local s = Net.state
				if not s then
					return
				end
				if table.find(s.zones, i) then
					local ok, err = Net.request("Teleport", { zone = i })
					if ok then
						Windows.close()
					elseif err then
						Toasts.show(Lang.msg(err), "error")
					end
				else
					request("BuyZone", { zone = i })
				end
			end,
		})
	end
	local function refresh()
		local s = Net.state
		if not s then
			return
		end
		Theme.setButton(parkButton, "🏡  " .. Lang.t("teleport.park"))
		for i, zone in Config.Zones do
			local owned = table.find(s.zones, i) ~= nil
			local prevOwned = i == 1 or table.find(s.zones, i - 1) ~= nil
			local name = Lang.zone(i)
			local text = if owned then ("✈️  " .. name) elseif prevOwned then ("🔒 " .. Lang.t("teleport.unlock", { zone = name, cost = Format.abbrev(zone.cost) })) else ("🔒 " .. name)
			Theme.setButton(buttons[i], text, if owned then Palette.rgb(zone.ground) elseif prevOwned and s.taps >= zone.cost then Theme.Green else Theme.Grey)
		end
	end
	w.onOpen = refresh
	Net.Changed:Connect(function()
		if Windows.isOpen("Teleport") then
			refresh()
		end
	end)
end

local function codes()
	local w = Windows.create("Codes", "🎟️", "win.codes", Theme.Red, Vector2.new(580, 500))
	local body = w.body
	local box = Theme.new("TextBox", {
		Size = UDim2.new(1, -200, 0, 60),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		Font = Theme.Font,
		TextScaled = true,
		TextColor3 = Theme.Ink,
		ClearTextOnFocus = false,
		Parent = body,
	}, { Theme.corner(14), Theme.stroke(3), Theme.padding(10) }) :: TextBox
	Lang.bind(box, "codes.placeholder", nil, "PlaceholderText")
	Theme.button({
		Key = "codes.redeem",
		Color = Theme.Green,
		Size = UDim2.fromOffset(180, 60),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 30,
		Parent = body,
		OnClick = function()
			local ok = request("RedeemCode", { code = box.Text })
			if ok then
				box.Text = ""
			end
		end,
	})
	Theme.text({ Key = "codes.follow", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 72), TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 20, Parent = body })

	-- Language picker
	Theme.text({ Text = "🌐", Stroke = false, Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 110), Parent = body })
	Theme.text({ Key = "settings.language", Size = UDim2.new(1, -60, 0, 32), Position = UDim2.fromOffset(42, 110), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 28, Parent = body })
	local grid = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Position = UDim2.fromOffset(0, 150), Parent = body }, {
		Theme.new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, 56), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local langButtons: { [string]: TextButton } = {}
	for i, l in Locale.Languages do
		local code = l.code
		local b = Theme.button({
			Text = l.flag .. " " .. l.name,
			Color = Theme.Grey,
			LayoutOrder = i,
			TextSize = 22,
			Corner = 12,
			Parent = grid,
			OnClick = function()
				if code == Lang.code then
					return
				end
				local s = Net.state
				if s then
					s.lang = code -- optimistic: the server confirms with the next snapshot
				end
				Lang.set(code)
				Toasts.show(Lang.t("toast.language", { name = l.name }), "success")
				local ok, err = Net.request("SetLanguage", { lang = code })
				if not ok and err then
					Toasts.show(Lang.msg(err), "error")
				end
			end,
		})
		-- names are shown in their own language: never auto-translate them
		b.AutoLocalize = false
		langButtons[code] = b
	end
	local function refresh()
		for code, b in langButtons do
			Theme.setButton(b, nil, if code == Lang.code then Theme.Green else Theme.Blue)
		end
	end
	w.onOpen = refresh
	Lang.Changed:Connect(refresh)
	refresh()
end

function ProgressWindows.init()
	upgrades()
	rebirth()
	teleport()
	codes()
end

return ProgressWindows
