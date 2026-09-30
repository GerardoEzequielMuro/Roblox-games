--!strict
-- The Workshop: every "spend a currency for power" system in one window, one tab per
-- system. Tools / Stats / Lab are there from the start; Relics, Temper, Overcharge and the
-- Constellation unlock with their galaxy (locked tabs say where).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Kit = require(script.Parent.Kit)
local PetIcon = require(script.Parent.PetIcon)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local UpgradesWindow = {}

local TABS = { "tools", "stats", "lab", "relics", "temper", "overcharge", "constellation" }
local TAB_COLORS = {
	tools = Theme.Orange, stats = Theme.Red, lab = Theme.Crystals, relics = Color3.fromRGB(110, 200, 120),
	temper = Color3.fromRGB(110, 180, 255), overcharge = Theme.Yellow, constellation = Theme.Purple,
}
local UPGRADE_ICON = {
	Power = "💪", Cargo = "🎒", HitSpeed = "⚡", MoveSpeed = "👟", Range = "📡", Luck = "🍀", Magnet = "🧲", Crit = "🎯",
	AutoRate = "🤖", PetSlots = "🐾", Temper = "❄️", Capacitor = "🔋", Insulation = "🧤", StarPower = "🌟", StarFortune = "💫",
	StarLuck = "🍀", StarDrone = "🚀", StarSlot = "🐾",
}
local STAT_ICON = { damage = "💥", speed = "💨", luck = "🍀", stardust = "✨", crystals = "💎" }

local window: Windows.Window
local content: Frame
local balance: TextLabel
local tabs: Kit.Tabs
local busy = false

-- What one more level gives, as text ("+6% damage", "+12 cargo").
local FLAT = { Cargo = true, HitSpeed = true, MoveSpeed = true, Range = true, AutoRate = true, PetSlots = true, Insulation = true, StarDrone = true, StarSlot = true }
local function effect(u: any, level: number): string
	local n: any
	if u.id == "Capacitor" then
		n = string.format("%.2f", Config.OverchargeBase + u.per * level)
	elseif u.compound then
		n = Format.abbrev(((1 + u.per) ^ level - 1) * 100)
	elseif FLAT[u.id] then
		n = u.per * level
	else
		n = math.floor(u.per * level * 100 + 0.5)
	end
	return Lang.t("upgrade." .. u.id .. ".desc", { n = n })
end

local function buy(id: string, times: number)
	if busy then
		return
	end
	busy = true
	local bought = 0
	for _ = 1, times do
		local ok, res = Net.request("Upgrade", { id = id })
		if not ok then
			if bought == 0 then
				Toasts.show(Lang.msg(res), "error")
			end
			break
		end
		bought += 1
		task.wait(0.09)
	end
	if bought > 0 then
		Theme.play("buy", 0.4, 1.2)
		Toasts.show(Lang.t("toast.upgraded", { name = Lang.t("upgrade." .. id .. ".name"), n = bought }), "success")
	end
	busy = false
end

local function upgradeRow(parent: Instance, u: any, order: number, s: { [string]: any })
	local level = s.upgrades[u.id] or 0
	local maxed = level >= u.max
	local color = TAB_COLORS[u.system] or Theme.Blue
	local row = Kit.row(parent, 78, color, order)
	row.Name = "Upgrade_" .. u.id
	local icon = Theme.icon(row, UPGRADE_ICON[u.id] or "⬆️", color, 56)
	icon.Position = UDim2.fromOffset(10, 11)
	Theme.text({ Text = Lang.t("upgrade." .. u.id .. ".name"), Size = UDim2.new(1, -330, 0, 26), Position = UDim2.fromOffset(76, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = row })
	Theme.text({ Text = effect(u, level), Size = UDim2.new(1, -330, 0, 20), Position = UDim2.fromOffset(76, 32), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = row })
	Theme.text({ Text = Lang.t("upgrades.level", { n = level, max = u.max }), Size = UDim2.new(1, -330, 0, 18), Position = UDim2.fromOffset(76, 54), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextColor3 = Color3.fromRGB(215, 225, 245), Parent = row })
	if maxed then
		Theme.text({ Key = "upgrades.max", Size = UDim2.fromOffset(230, 40), Position = UDim2.new(1, -244, 0.5, -20), MaxTextSize = 28, TextColor3 = Theme.Yellow, Parent = row })
		return
	end
	local cost = Formulas.upgradeCost(u.id, level)
	local can = (if u.currency == "stardust" then s.stardust elseif u.currency == "crystals" then s.crystals else (s.mats[u.currency] or 0)) >= cost
	Theme.button({ Name = "Buy1", Text = "+1\n" .. Kit.cost(u.currency, cost), Color = if can then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(124, 60), Position = UDim2.new(1, -244, 0.5, -30), TextSize = 19, Parent = row, OnClick = function()
		task.spawn(buy, u.id, 1)
	end })
	Theme.button({ Name = "BuyMax", Text = Lang.t("upgrades.buy_max"), Color = if can then Theme.Blue else Theme.Grey, Size = UDim2.fromOffset(104, 60), Position = UDim2.new(1, -114, 0.5, -30), TextSize = 20, Parent = row, OnClick = function()
		task.spawn(buy, u.id, 25)
	end })
end

local function lockedTab(system: any)
	local zone = Config.Zones[system.zone]
	local touch = Kit.touch
	local lockSize = if touch then 56 else 90
	local y = if touch then 6 else 40
	Theme.text({ Text = "🔒", Stroke = false, Size = UDim2.fromOffset(lockSize, lockSize), Position = UDim2.new(0.5, -lockSize // 2, 0, y), Parent = content })
	y += lockSize + 10
	Theme.text({ Text = Lang.t("upgrades.locked", { zone = Lang.t("zone." .. zone.id) }), Size = UDim2.new(1, -60, 0, if touch then 36 else 40), Position = UDim2.fromOffset(30, y), MaxTextSize = 30, TextColor3 = Theme.Yellow, Parent = content })
	y += if touch then 42 else 50
	Theme.text({ Text = Lang.t("system." .. system.id .. ".desc"), TextWrapped = true, Size = UDim2.new(1, -120, 0, if touch then 70 else 80), Position = UDim2.fromOffset(60, y), MaxTextSize = 22, Parent = content })
end

local function toolsTab(s: { [string]: any })
	local list = Kit.scroll(content, UDim2.fromScale(1, 1))
	local touch = Kit.touch
	local current = Config.ToolIndex[s.tool] or 1
	for i, tool in Config.Tools do
		local color = Palette.rgb(tool.color)
		local owned = i <= current
		local row = Kit.row(list, if touch then 68 else 70, if owned then Theme.darken(color, 0.35) else color, i)
		row.Name = "Tool_" .. tool.id
		local tile = Theme.new("Frame", { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(8, 6), BackgroundColor3 = Theme.PaperDark, Parent = row }, { Theme.corner(10), Theme.stroke(2) })
		PetIcon.tool(tool.id).Parent = tile
		-- Asteroid Field tools carry a comet and, until found, their first-time Crystals
		local field = tool.field == true
		local bonus = if field and not (s.fieldsFound and s.fieldsFound[tool.id]) and not owned then "   ·   💎 +" .. Config.FieldCrystals else ""
		Theme.text({ Text = (if field then "☄️ " else "") .. Lang.tool(tool.id), Size = UDim2.new(1, -300, 0, 28), Position = UDim2.fromOffset(76, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = row })
		Theme.text({ Text = "💪 " .. Lang.t("tools.power", { n = Format.abbrev(tool.power) }) .. "   ·   " .. Lang.zone(tool.zone) .. bonus, Size = UDim2.new(1, -300, 0, 22), Position = UDim2.fromOffset(76, 38), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = row })
		if i == current then
			Theme.text({ Key = "tools.equipped", Size = UDim2.fromOffset(200, 36), Position = UDim2.new(1, -212, 0.5, -18), MaxTextSize = 24, TextColor3 = Theme.Green, Parent = row })
		elseif owned then
			Theme.text({ Text = "✔", Size = UDim2.fromOffset(200, 36), Position = UDim2.new(1, -212, 0.5, -18), MaxTextSize = 30, TextColor3 = Theme.Grey, Parent = row })
		elseif not table.find(s.zones, tool.zone) then
			Theme.text({ Text = "🔒 " .. Lang.zone(tool.zone), Size = UDim2.fromOffset(200, 36), Position = UDim2.new(1, -212, 0.5, -18), MaxTextSize = 20, TextColor3 = Theme.Grey, Parent = row })
		else
			local can = s.stardust >= tool.cost
			Theme.button({ Name = "Buy", Text = Kit.cost("stardust", tool.cost), Color = if can then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(190, if touch then Kit.TOUCH_BTN else 52), Position = UDim2.new(1, -204, 0.5, if touch then -Kit.TOUCH_BTN // 2 else -26), TextSize = 24, Parent = row, OnClick = function()
				Kit.request("BuyTool", { id = tool.id }, Lang.t("toast.tool_bought", { tool = Lang.tool(tool.id) }))
			end })
		end
	end
	-- start at the tool the player can buy next
	list.CanvasPosition = Vector2.new(0, math.max(0, (current - 1) * 76 - 40))
end

local function relicsTab(s: { [string]: any })
	local touch = Kit.touch
	-- touch: the stat rows scroll and the odds panel is compact (the window is 372 tall)
	local left: Instance
	if touch then
		left = Kit.scroll(content, UDim2.new(1, -220, 1, 0))
	else
		left = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 1, 0), Parent = content }, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) })
	end
	for i, stat in Config.RelicStats do
		local relic = s.relics[stat] or { grade = 0, dust = 0 }
		local grade = Config.RelicGrades[relic.grade]
		local color = if grade then Palette.rarity(grade.rarity) else Theme.Grey
		local row = Kit.row(left, 54, color, i)
		row.Name = "Relic_" .. stat
		local icon = Theme.icon(row, STAT_ICON[stat], color, 42)
		icon.Position = UDim2.fromOffset(8, 6)
		Theme.text({ Text = Lang.t("stat." .. stat), Size = UDim2.new(0.5, -60, 0, 24), Position = UDim2.fromOffset(58, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = row })
		Theme.text({ Text = if grade then (Lang.rarity(grade.rarity) .. "  +" .. math.floor(grade.bonus * 100) .. "%") else Lang.t("relics.none"), Size = UDim2.new(0.5, -60, 0, 20), Position = UDim2.fromOffset(58, 28), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = row })
		local bar = Theme.bar(row, UDim2.fromOffset(150, 20), Theme.Teal)
		bar.frame.Position = UDim2.new(1, -162, 0.5, -10)
		bar:set(relic.dust / Config.RelicDustPerGrade, Lang.t("relics.dust", { n = relic.dust, max = Config.RelicDustPerGrade }))
	end
	local right = Theme.panel({ Size = UDim2.new(0, 210, 1, 0), Position = UDim2.new(1, -210, 0, 0), BackgroundColor3 = Theme.PaperDark, Corner = 12, StrokeThickness = 2, Parent = content })
	Theme.text({ Key = "relics.odds", Size = UDim2.new(1, -12, 0, if touch then 20 else 24), Position = UDim2.fromOffset(6, 2), MaxTextSize = 20, Parent = right })
	local lineH = if touch then 18 else 22
	for i, g in Config.RelicGrades do
		Theme.text({ Text = Lang.rarity(g.rarity), TextColor3 = Palette.rarity(g.rarity), Size = UDim2.new(0.6, 0, 0, lineH - 2), Position = UDim2.fromOffset(10, 6 + i * lineH), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17, Parent = right })
		Theme.text({ Text = Format.chance(g.chance), Size = UDim2.new(0.4, -14, 0, lineH - 2), Position = UDim2.new(0.6, 0, 0, 6 + i * lineH), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 17, Parent = right })
	end
	local can = (s.mats.spores or 0) >= Config.RelicCost
	Theme.button({ Name = "Roll", Text = Lang.t("relics.roll") .. "\n" .. Kit.cost("spores", Config.RelicCost), Color = if can then Theme.Green else Theme.Grey, Size = UDim2.new(1, -16, 0, if touch then Kit.TOUCH_BTN else 62), Position = UDim2.new(0, 8, 1, if touch then -(Kit.TOUCH_BTN + 8) else -132), TextSize = 22, Parent = right, OnClick = function()
		local ok, res = Net.request("RollRelic")
		if not ok then
			Toasts.show(Lang.msg(res), "error")
			return
		end
		local g = Config.RelicGrades[res.grade]
		Toasts.show(Lang.t(if res.upgraded then "relics.result_up" else "relics.result_dust", { stat = Lang.t("stat." .. res.stat), rarity = Lang.rarity(g.rarity) }), if res.upgraded then "success" else "info")
		Theme.play("buy", 0.4, if res.upgraded then 1.4 else 1)
	end })
	if not touch then
		Theme.text({ Key = "relics.help", TextWrapped = true, Size = UDim2.new(1, -16, 0, 60), Position = UDim2.new(0, 8, 1, -66), MaxTextSize = 15, TextColor3 = Color3.fromRGB(200, 210, 235), Parent = right })
	end
end

local function render()
	local s = Net.state
	if not s or not Windows.isOpen("Upgrades") then
		return
	end
	local id = tabs.current()
	Kit.clear(content)
	local system = Config.SystemById[id]
	-- balance line: the currencies this tab spends
	local parts = { Kit.cost("stardust", s.stardust), Kit.cost("crystals", s.crystals) }
	if system.material then
		table.insert(parts, Kit.cost(system.material, s.mats[system.material] or 0) .. " " .. Lang.t("material." .. system.material))
	end
	balance.Text = table.concat(parts, "     ")
	if not table.find(s.zones, system.zone) then
		lockedTab(system)
		return
	end
	if id == "tools" then
		toolsTab(s)
	elseif id == "relics" then
		relicsTab(s)
	else
		local list = Kit.scroll(content, UDim2.fromScale(1, 1))
		local order = 0
		for _, u in Config.Upgrades do
			if u.system == id then
				order += 1
				upgradeRow(list, u, order, s)
			end
		end
	end
end

-- Opens the window on a tab (the system stations in the world use this).
function UpgradesWindow.open(tab: string?)
	Windows.open("Upgrades")
	if tab and Config.SystemById[tab] and tab ~= "traits" then
		tabs.select(tab)
	end
end

function UpgradesWindow.init()
	window = Windows.create("Upgrades", "⛏️", "win.upgrades", Theme.Orange, Vector2.new(780, 490))
	local entries = {}
	for _, id in TABS do
		table.insert(entries, { id, Config.SystemById[id].icon, TAB_COLORS[id] })
	end
	local tabH = if Kit.touch then Kit.TOUCH_BTN else 40
	tabs = Kit.tabs(window.body, UDim2.fromOffset(752, tabH), UDim2.fromOffset(0, 0), entries, function()
		render()
	end)
	balance = Theme.text({ Name = "Balance", Text = "", Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, tabH + 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = window.body })
	balance.AutoLocalize = false
	content = Theme.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -(tabH + 32)), Position = UDim2.fromOffset(0, tabH + 32), Parent = window.body })
	-- tab tooltips: the system name under the strip when selected is in the header title
	local function tabNames()
		for _, id in TABS do
			local b = tabs.buttons[id]
			local s = Net.state
			local locked = s ~= nil and not table.find(s.zones, Config.SystemById[id].zone)
			Theme.setButton(b, (if locked then "🔒" else Config.SystemById[id].icon) .. " " .. Lang.t("system." .. id .. ".short"))
		end
	end
	window.onOpen = function()
		tabNames()
		if tabs.current() == "" then
			tabs.select("tools")
		else
			render()
		end
	end
	Net.Changed:Connect(function(kind)
		if kind == "full" and Windows.isOpen("Upgrades") then
			tabNames()
			render()
		end
	end)
end

return UpgradesWindow
