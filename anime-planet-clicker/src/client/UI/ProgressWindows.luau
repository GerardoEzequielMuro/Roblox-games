--!strict
-- Rebirth, Warp (teleport), Auto (every auto toggle in one place) and Settings (language,
-- codes, toggles).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Themes = require(ReplicatedStorage.Shared.Themes)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)

local ProgressWindows = {}

---------------------------------------------------------------------------
-- Rebirth: what you lose (red) and what you gain (green), side by side
---------------------------------------------------------------------------
local function rebirthWindow()
	local w = Windows.create("Rebirth", "🔁", "win.rebirth", Theme.Teal, Vector2.new(640, 420))
	local body = w.body
	local function render()
		local s = Net.state
		if not s or not Windows.isOpen("Rebirth") then
			return
		end
		Kit.clear(body)
		local touch = Kit.touch
		-- touch (304 tall body): shorter panels, bar 30, buttons 56
		local panelH = if touch then 158 else 180
		local lose = Theme.panel({ Name = "Lose", Size = UDim2.new(0.5, -6, 0, panelH), BackgroundColor3 = Color3.fromRGB(110, 36, 50), Corner = 12, Parent = body })
		Theme.text({ Key = "rebirth.lose", Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 6), MaxTextSize = 24, TextColor3 = Color3.fromRGB(255, 150, 150), Parent = lose })
		Theme.text({ Key = "rebirth.lose_list", TextWrapped = true, Size = UDim2.new(1, -20, 1, -44), Position = UDim2.fromOffset(10, 38), MaxTextSize = 20, TextYAlignment = Enum.TextYAlignment.Top, Parent = lose })
		local gain = Theme.panel({ Name = "Gain", Size = UDim2.new(0.5, -6, 0, panelH), Position = UDim2.new(0.5, 6, 0, 0), BackgroundColor3 = Color3.fromRGB(30, 100, 60), Corner = 12, Parent = body })
		Theme.text({ Key = "rebirth.gain", Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 6), MaxTextSize = 24, TextColor3 = Color3.fromRGB(150, 255, 170), Parent = gain })
		local nowMult = 1 + Config.RebirthMult * s.rebirths
		local nextMult = 1 + Config.RebirthMult * (s.rebirths + 1)
		Theme.text({ Text = Lang.t("rebirth.gain_list", { now = string.format("%.1f", nowMult), next = string.format("%.1f", nextMult), crystals = s.rebirthCrystals }), TextWrapped = true, Size = UDim2.new(1, -20, 1, -44), Position = UDim2.fromOffset(10, 38), MaxTextSize = 20, TextYAlignment = Enum.TextYAlignment.Top, Parent = gain })
		Theme.text({ Text = Lang.t("rebirth.count", { n = s.rebirths }), Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, panelH + 6), MaxTextSize = 20, TextColor3 = Theme.Yellow, Parent = body })
		local frac = math.clamp(s.stardust / s.rebirthCost, 0, 1)
		local bar = Theme.bar(body, UDim2.new(1, 0, 0, if touch then 30 else 34), Theme.Teal)
		bar.frame.Position = UDim2.fromOffset(0, panelH + 34)
		local btnY = panelH + (if touch then 70 else 78)
		local btnH = if touch then Kit.TOUCH_BTN + 4 else 60
		bar:set(frac, Format.abbrev(s.stardust) .. " / " .. Format.abbrev(s.rebirthCost) .. " ✨")
		local can = s.stardust >= s.rebirthCost
		Theme.button({ Name = "DoRebirth", Key = "rebirth.button", Color = if can then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(300, btnH), Position = UDim2.new(0, 0, 0, btnY), TextSize = 30, Parent = body, OnClick = function()
			local ok, res = Net.request("Rebirth")
			if ok then
				Toasts.milestone(Lang.t("rebirth.done"), Lang.msg(res), Theme.Teal)
			else
				Toasts.show(Lang.msg(res), "error")
			end
		end })
		local _, paint = Kit.toggle(body, "auto.rebirth.name", 0, function()
			return s.auto.rebirth == true
		end, function(on)
			Kit.request("SetAuto", { key = "rebirth", on = on })
		end)
		local row = body:FindFirstChild("Toggle") :: Frame
		row.Size = UDim2.fromOffset(290, btnH)
		row.Position = UDim2.new(1, -290, 0, btnY)
		paint()
	end
	w.onOpen = render
	Net.Changed:Connect(function()
		render()
	end)
end

---------------------------------------------------------------------------
-- Warp
---------------------------------------------------------------------------
local function teleportWindow()
	local w = Windows.create("Teleport", "🌀", "win.teleport", Theme.Purple, Vector2.new(620, 470))
	local list = Kit.scroll(w.body, UDim2.fromScale(1, 1))
	local function render()
		local s = Net.state
		if not s or not Windows.isOpen("Teleport") then
			return
		end
		Kit.clear(list)
		for i, zone in Config.Zones do
			local theme = Themes.get(i)
			local owned = table.find(s.zones, i) ~= nil
			local touch = Kit.touch
			local rowH = if touch then 68 else 62
			local row = Kit.row(list, rowH, if owned then theme.skyHorizon else Theme.Grey, i)
			row.Name = "Zone" .. i
			local icon = Theme.icon(row, if owned then "🪐" else "🔒", theme.accent, 46)
			icon.Position = UDim2.fromOffset(8, (rowH - 46) // 2)
			Theme.text({ Text = i .. ". " .. Lang.zone(i), Size = UDim2.new(1, -250, 0, 26), Position = UDim2.fromOffset(64, rowH // 2 - 26), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = row })
			local system
			for _, sy in Config.Systems do
				if sy.zone == i and i > 1 then
					system = sy
				end
			end
			local sub = if system then (system.icon .. " " .. Lang.t("system." .. system.id .. ".name")) else ("⛏️ " .. Lang.t("system.tools.name"))
			Theme.text({ Text = sub, Size = UDim2.new(1, -250, 0, 20), Position = UDim2.fromOffset(64, rowH // 2 + 2), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = row })
			if owned then
				Theme.button({ Name = "Go", Key = "teleport.go", Color = Theme.Green, Size = UDim2.fromOffset(150, if touch then Kit.TOUCH_BTN else 46), Position = UDim2.new(1, -160, 0.5, if touch then -Kit.TOUCH_BTN // 2 else -23), TextSize = 24, Parent = row, OnClick = function()
					local ok = Kit.request("Teleport", { zone = i })
					if ok then
						Windows.close()
					end
				end })
			elseif i == s.maxZone + 1 then
				local done = 1 - s.gateLeft / zone.gateHp
				local bar = Theme.bar(row, UDim2.fromOffset(170, 30), Theme.Red)
				bar.frame.Position = UDim2.new(1, -180, 0.5, -15)
				bar:set(done, Lang.t("teleport.gate", { pct = math.floor(done * 100) }))
			else
				Theme.text({ Key = "teleport.locked", Size = UDim2.fromOffset(170, 30), Position = UDim2.new(1, -180, 0.5, -15), MaxTextSize = 18, TextColor3 = Color3.fromRGB(220, 220, 235), Parent = row })
			end
		end
		local touch = Kit.touch
		local rowH = if touch then 68 else 62
		local arena = Kit.row(list, rowH, Theme.Red, 99)
		arena.Name = "Arena"
		local icon = Theme.icon(arena, "⚔️", Theme.Red, 46)
		icon.Position = UDim2.fromOffset(8, (rowH - 46) // 2)
		Theme.text({ Key = "world.arena", Size = UDim2.new(1, -250, 0, 26), Position = UDim2.fromOffset(64, rowH // 2 - 26), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = arena })
		Theme.text({ Text = "🏆 " .. Lang.t("teleport.arena_points", { n = s.arenaPoints }), Size = UDim2.new(1, -250, 0, 20), Position = UDim2.fromOffset(64, rowH // 2 + 2), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = arena })
		Theme.button({ Name = "Go", Key = "teleport.go", Color = Theme.Orange, Size = UDim2.fromOffset(150, if touch then Kit.TOUCH_BTN else 46), Position = UDim2.new(1, -160, 0.5, if touch then -Kit.TOUCH_BTN // 2 else -23), TextSize = 24, Parent = arena, OnClick = function()
			local ok = Kit.request("Teleport", { arena = true })
			if ok then
				Windows.close()
			end
		end })
	end
	w.onOpen = render
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			render()
		end
	end)
end

---------------------------------------------------------------------------
-- Auto: every auto with a clear ON / OFF and one line of what it does
---------------------------------------------------------------------------
local AUTO_ICONS = { mine = "⛏️", sell = "🚀", best = "⭐", fuse = "🌟", rebirth = "🔁", upgrade = "📈" }
local function autoWindow()
	local w = Windows.create("Auto", "🤖", "win.auto", Theme.Blue, Vector2.new(640, 470))
	local list = Kit.scroll(w.body, UDim2.fromScale(1, 1))
	local function render()
		local s = Net.state
		if not s or not Windows.isOpen("Auto") then
			return
		end
		Kit.clear(list)
		local touch = Kit.touch
		local rowH = if touch then 68 else 62
		local btnH = if touch then Kit.TOUCH_BTN else 44
		local btnY = if touch then -Kit.TOUCH_BTN // 2 else -22
		local titleY, descY = rowH // 2 - 26, rowH // 2 + 2
		for i, key in Config.AutoKeys do
			local row = Theme.new("Frame", { Name = "Auto_" .. key, Size = UDim2.new(1, -8, 0, rowH), BackgroundColor3 = Theme.PaperLight, LayoutOrder = i, Parent = list }, { Theme.corner(10), Theme.stroke(2) })
			Theme.text({ Text = AUTO_ICONS[key] .. " " .. Lang.t("auto." .. key .. ".name"), Size = UDim2.new(1, -130, 0, 26), Position = UDim2.fromOffset(12, titleY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = row })
			local desc = Lang.t("auto." .. key .. ".desc", { rate = string.format("%.1f", s.autoRate) })
			Theme.text({ Text = desc, Size = UDim2.new(1, -130, 0, 22), Position = UDim2.fromOffset(12, descY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextColor3 = Color3.fromRGB(200, 210, 235), Parent = row })
			local on = s.auto[key] == true
			Theme.button({ Name = "Switch", Text = Lang.t(if on then "hud.on" else "hud.off"), Color = if on then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(100, btnH), Position = UDim2.new(1, -110, 0.5, btnY), TextSize = 22, Parent = row, OnClick = function()
				Kit.request("SetAuto", { key = key, on = not on })
			end })
		end
		-- Auto Open status (started at a capsule machine)
		local openRow = Theme.new("Frame", { Name = "Auto_open", Size = UDim2.new(1, -8, 0, rowH), BackgroundColor3 = Theme.PaperLight, LayoutOrder = 20, Parent = list }, { Theme.corner(10), Theme.stroke(2) })
		Theme.text({ Text = "🧬 " .. Lang.t("auto.open.name"), Size = UDim2.new(1, -130, 0, 26), Position = UDim2.fromOffset(12, titleY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = openRow })
		Theme.text({ Text = if s.autoOpen then Lang.t("auto.open.running", { capsule = Lang.capsule(s.autoOpen) }) else Lang.t("auto.open.desc"), Size = UDim2.new(1, -130, 0, 22), Position = UDim2.fromOffset(12, descY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextColor3 = Color3.fromRGB(200, 210, 235), Parent = openRow })
		Theme.button({ Name = "Switch", Text = Lang.t(if s.autoOpen then "hud.on" else "hud.off"), Color = if s.autoOpen then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(100, btnH), Position = UDim2.new(1, -110, 0.5, btnY), TextSize = 22, Parent = openRow, OnClick = function()
			if s.autoOpen then
				Kit.request("SetAutoOpen", {})
			else
				Toasts.show(Lang.t("toast.autoopen_hint"), "info")
			end
		end })
		-- faster Auto Mine: the pass
		if not Net.owns("AutoMiner") then
			local pass = Theme.new("Frame", { Name = "Pass", Size = UDim2.new(1, -8, 0, rowH), BackgroundColor3 = Color3.fromRGB(74, 40, 120), LayoutOrder = 30, Parent = list }, { Theme.corner(10), Theme.stroke(2) })
			Theme.text({ Text = "🤖 " .. Lang.t("pass.AutoMiner.name"), Size = UDim2.new(1, -180, 0, 26), Position = UDim2.fromOffset(12, titleY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = pass })
			Theme.text({ Key = "pass.AutoMiner.desc", Size = UDim2.new(1, -180, 0, 22), Position = UDim2.fromOffset(12, descY), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextColor3 = Color3.fromRGB(220, 200, 250), Parent = pass })
			Theme.button({ Name = "Buy", Text = "R$ " .. Config.PassByKey.AutoMiner.price, Color = Theme.Robux, Size = UDim2.fromOffset(150, btnH), Position = UDim2.new(1, -160, 0.5, btnY), TextSize = 22, Parent = pass, OnClick = function()
				Purchase.pass("AutoMiner")
			end })
		end
	end
	w.onOpen = render
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			render()
		end
	end)
end

---------------------------------------------------------------------------
-- Settings: language, codes, toggles
---------------------------------------------------------------------------
local function settingsWindow()
	local touch = Kit.touch
	-- touch: three columns (codes | toggles | languages) in a 780-wide window, 56-unit controls
	local w = Windows.create("Settings", "⚙️", "win.settings", Theme.Grey, Vector2.new(if touch then 780 else 680, 470))
	local body = w.body
	local colW = if touch then 240 else 300
	local btnH = if touch then Kit.TOUCH_BTN else 44
	local langW = if touch then 188 else 184
	-- codes
	Theme.text({ Key = "settings.codes", Size = UDim2.fromOffset(colW, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = body })
	local box = Theme.new("TextBox", {
		Name = "CodeBox",
		Size = UDim2.fromOffset(colW, btnH),
		Position = UDim2.fromOffset(0, 28),
		BackgroundColor3 = Theme.PaperDark,
		Font = Theme.Font,
		TextSize = 22,
		TextColor3 = Theme.White,
		PlaceholderColor3 = Color3.fromRGB(140, 150, 190),
		Text = "",
		ClearTextOnFocus = false,
		Parent = body,
	}, { Theme.corner(10), Theme.stroke(3) }) :: TextBox
	Lang.bind(box, "settings.code_placeholder", nil, "PlaceholderText")
	Theme.button({ Name = "Redeem", Key = "settings.redeem", Color = Theme.Green, Size = UDim2.fromOffset(if touch then colW else 150, btnH), Position = if touch then UDim2.fromOffset(0, 28 + btnH + 6) else UDim2.fromOffset(308, 28), TextSize = 22, Parent = body, OnClick = function()
		local ok = Kit.request("RedeemCode", { code = box.Text })
		if ok then
			box.Text = ""
		end
	end })
	-- toggles
	local toggles = Theme.new("Frame", { Name = "Toggles", BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 204), Position = if touch then UDim2.fromOffset(252, 0) else UDim2.fromOffset(0, 84), Parent = body }, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) })
	local paints: { () -> () } = {}
	for i, key in { "sfx", "lite", "hidePets" } do
		local _, paint = Kit.toggle(toggles, "settings." .. key, i, function()
			local s = Net.state
			return s ~= nil and s.settings[key] == true
		end, function(on)
			Net.request("SetSetting", { key = key, on = on })
		end)
		table.insert(paints, paint)
	end
	Theme.button({ Name = "SkipTutorial", Key = "settings.skip_tutorial", Color = Theme.Grey, Size = UDim2.fromOffset(colW, if touch then Kit.TOUCH_BTN else 40), Position = if touch then UDim2.fromOffset(0, 28 + 2 * (btnH + 6)) else UDim2.fromOffset(0, 250), TextSize = 18, Parent = body, OnClick = function()
		Kit.request("SkipTutorial", nil, Lang.t("settings.tutorial_skipped"))
	end })
	-- languages
	Theme.text({ Key = "settings.language", Size = UDim2.fromOffset(langW - 4, 24), Position = UDim2.new(1, -langW, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = body })
	local langs = Kit.scroll(body, UDim2.new(0, langW, 1, -30), UDim2.new(1, -langW, 0, 28), 4)
	local buttons: { [string]: TextButton } = {}
	local function paintLangs()
		local pref = Net.get("lang")
		for code, b in buttons do
			Theme.setButton(b, nil, if (code == "" and pref == "") or (code ~= "" and code == Lang.code and pref ~= "") then Theme.Green else Theme.Blue)
		end
		for _, paint in paints do
			paint()
		end
		Theme.muted = Net.state ~= nil and Net.state.settings.sfx == false
	end
	buttons[""] = Theme.button({ Name = "Lang_auto", Key = "settings.lang_auto", Size = UDim2.new(1, -12, 0, if touch then Kit.TOUCH_BTN else 32), LayoutOrder = 0, TextSize = 17, Corner = 8, Parent = langs, OnClick = function()
		Net.request("SetLanguage", { lang = "" })
	end })
	for i, l in Locale.Languages do
		buttons[l.code] = Theme.button({ Name = "Lang_" .. l.code, Text = l.name, Size = UDim2.new(1, -12, 0, if touch then Kit.TOUCH_BTN else 32), LayoutOrder = i, TextSize = 17, Corner = 8, Parent = langs, OnClick = function()
			local ok = Net.request("SetLanguage", { lang = l.code })
			if ok then
				Toasts.show(Locale.t(l.code, "toast.language", { name = l.name }), "success")
			end
		end })
	end
	w.onOpen = paintLangs
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			paintLangs()
		end
	end)
	Lang.Changed:Connect(paintLangs)
end

function ProgressWindows.init()
	rebirthWindow()
	teleportWindow()
	autoWindow()
	settingsWindow()
end

return ProgressWindows
