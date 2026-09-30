--!nonstrict
-- Progress windows: Forms, Moves (techniques), Upgrades, Ascension, Travel and Warrior
-- (multiplier breakdown + race).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Controls = require(script.Parent.Parent.Controls)

local Panels = {}
local new = Theme.new

local lists: { [string]: ScrollingFrame } = {}
local function listOf(name: string, body: Frame, size: UDim2?, pos: UDim2?): ScrollingFrame
	local l = lists[name]
	if not l then
		l = Kit.scroll(body, size, pos)
		lists[name] = l
	end
	Kit.clear(l)
	return l
end

local function power(s): number
	return math.max(s.power or 0, s.bestPower or 0)
end

---------------------------------------------------------------------------
-- Forms
---------------------------------------------------------------------------
local function renderForms(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("forms", body)
	local char = game:GetService("Players").LocalPlayer.Character
	local current = (char and char:GetAttribute("Form")) or 0
	for i, f in Config.Forms do
		local color = Theme.rgb(f.color)
		local unlocked = i <= (s.forms or 0)
		local row = Kit.row(list, 66, i, color)
		Kit.chip(row, if unlocked then "🔥" else "🔒", if unlocked then color else Theme.Grey, 46, UDim2.fromOffset(20, 10))
		Kit.text(row, { Text = Lang.t("form." .. f.id), Size = UDim2.new(0.4, 0, 0, 26), Position = UDim2.fromOffset(76, 7), MaxTextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(color, 0.4) })
		Kit.text(row, { Text = Lang.t("forms.line", { mult = Format.abbrev(f.mult), drain = string.format("%g", f.drain * 100) }), Size = UDim2.new(0.55, 0, 0, 18), Position = UDim2.fromOffset(76, 36), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		if unlocked then
			local active = current == i
			Kit.button(row, Lang.t(if active then "forms.revert" else "forms.transform"), if active then Theme.Grey else Theme.Orange, 150, function()
				Controls.preferredForm = i
				Controls.transform(if active then 0 else i)
				Windows.close()
			end)
		else
			local need = Lang.t("forms.need", { power = Format.abbrev(f.reqPower) })
			if f.reqRebirths then
				need ..= " · " .. Lang.t(if f.reqRebirths == 1 then "forms.need_asc_one" else "forms.need_asc", { n = f.reqRebirths })
			end
			if f.special and not s.passes[f.special.pass] then
				need ..= "\n" .. Lang.t("special.need", { boss = Lang.t("npc." .. f.special.boss), have = math.min(f.special.count, (s.bossKills and s.bossKills[f.special.boss]) or 0), n = f.special.count, pass = Lang.t("pass." .. f.special.pass .. ".name") })
			end
			Kit.text(row, { Text = need, TextWrapped = true, Size = UDim2.new(0.34, 0, 0, 52), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Red })
		end
	end
end

---------------------------------------------------------------------------
-- Moves (techniques)
---------------------------------------------------------------------------
local function renderMoves(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("moves", body)
	Kit.header(list, "moves.techniques", 0)
	for i, t in Config.Techniques do
		local owned = s.techniques[t.id] == true
		local row = Kit.row(list, 74, i, Theme.Purple)
		Kit.chip(row, t.icon, if owned then Theme.Purple else Theme.Grey, 48, UDim2.fromOffset(20, 13))
		Kit.text(row, { Text = Lang.t("tech." .. t.id) .. "  [" .. t.key .. "]", Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(78, 8), MaxTextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.text(row, { Text = Lang.t("tech." .. t.id .. ".desc"), Size = UDim2.new(0.6, -10, 0, 34), Position = UDim2.fromOffset(78, 34), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Dim, Font = Theme.FontBold, TextWrapped = true })
		if owned then
			Kit.text(row, { Text = "✔ " .. Lang.t("ui.owned"), Size = UDim2.fromOffset(150, 30), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 18, TextColor3 = Theme.Green })
		elseif power(s) < t.reqPower then
			Kit.text(row, { Text = "🔒 " .. Lang.t("forms.need", { power = Format.abbrev(t.reqPower) }), Size = UDim2.fromOffset(170, 36), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 16, TextColor3 = Theme.Red })
		elseif t.special and not s.passes[t.special.pass] and ((s.bossKills and s.bossKills[t.special.boss]) or 0) < t.special.count then
			Kit.text(row, { Text = "🔒 " .. Lang.t("special.need", { boss = Lang.t("npc." .. t.special.boss), have = (s.bossKills and s.bossKills[t.special.boss]) or 0, n = t.special.count, pass = Lang.t("pass." .. t.special.pass .. ".name") }), TextWrapped = true, Size = UDim2.fromOffset(210, 54), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 14, TextColor3 = Theme.Red })
		else
			Kit.button(row, "⚡ " .. Format.abbrev(t.cost), if s.sparks >= t.cost then Theme.Green else Theme.Orange, 150, function()
				Kit.request("BuyTechnique", { id = t.id }, Lang.t("moves.learned", { move = Lang.t("tech." .. t.id) }))
			end)
		end
	end
	Kit.header(list, "moves.basics", 10)
	local basics = { { "👊", "act.punch", "LMB" }, { "🔵", "act.blast", "Q" }, { "☄️", "act.beam", "R" }, { "🛡️", "act.block", "F" }, { "💨", "act.dash", "E" }, { "🔋", "act.charge", "C" }, { "🔥", "act.form", "G" }, { "🕊️", "act.fly", "H" } }
	for i, b in basics do
		local row = Kit.row(list, 40, 10 + i)
		Kit.text(row, { Text = b[1], Stroke = false, Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(12, 5) })
		Kit.text(row, { Text = Lang.t(b[2]), Size = UDim2.new(0.3, 0, 0, 22), Position = UDim2.fromOffset(52, 9), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.text(row, { Text = Lang.t(b[2] .. ".desc"), Size = UDim2.new(0.62, -60, 0, 20), Position = UDim2.new(0.34, 0, 0, 10), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		if not Controls.isTouch then
			Kit.text(row, { Text = b[3], Font = Theme.Display, Size = UDim2.fromOffset(50, 24), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 22, TextColor3 = Theme.Yellow })
		end
	end
end

---------------------------------------------------------------------------
-- Upgrades (gems)
---------------------------------------------------------------------------
local function upgradeValue(u, level: number): string
	if u.id == "autoSpeed" then
		return string.format("+%g/s", u.perLevel * level)
	end
	return string.format("+%d%%", math.floor(u.perLevel * level * 100 + 0.5))
end

local function renderUpgrades(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("upgrades", body)
	for i, u in Config.Upgrades do
		local level = s.upgrades[u.id] or 0
		local row = Kit.row(list, 70, i, Theme.Cyan)
		Kit.chip(row, u.icon, Theme.Cyan, 46, UDim2.fromOffset(20, 12))
		Kit.text(row, { Text = Lang.t("upgrade." .. u.id .. ".name"), Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(76, 8), MaxTextSize = 21, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.text(row, { Text = Lang.t("upgrade." .. u.id .. ".desc") .. "  " .. upgradeValue(u, level) .. (if level < u.max then " → " .. upgradeValue(u, level + 1) else ""), Size = UDim2.new(0.62, -10, 0, 18), Position = UDim2.fromOffset(76, 34), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		Kit.text(row, { Text = Lang.t("ui.level", { n = level, max = u.max }), Size = UDim2.fromOffset(120, 14), Position = UDim2.fromOffset(76, 52), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Yellow })
		if level >= u.max then
			Kit.text(row, { Text = Lang.t("ui.max"), Font = Theme.Display, Size = UDim2.fromOffset(120, 30), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 26, TextColor3 = Theme.Green })
		else
			local cost = Formulas.upgradeCost(u.id, level)
			Kit.button(row, "💎 " .. Format.abbrev(cost), if s.gems >= cost then Theme.Green else Theme.Grey, 130, function()
				Kit.request("BuyUpgrade", { id = u.id })
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Ascension (rebirth)
---------------------------------------------------------------------------
local ascendUi: { [string]: any } = {}
local function renderAscend(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	if not ascendUi.built then
		ascendUi.built = true
		ascendUi.count = Kit.text(body, { Text = "", Font = Theme.Display, Size = UDim2.new(1, 0, 0, 44), MaxTextSize = 44, TextColor3 = Theme.Yellow })
		ascendUi.now = Kit.text(body, { Text = "", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 48), MaxTextSize = 20 })
		Kit.text(body, { Key = "ascend.keeps", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 78), MaxTextSize = 16, TextColor3 = Theme.Green, TextWrapped = true, Font = Theme.FontBold })
		Kit.text(body, { Key = "ascend.resets", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 120), MaxTextSize = 16, TextColor3 = Theme.Red, TextWrapped = true, Font = Theme.FontBold })
		ascendUi.holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 172), ZIndex = 22, Parent = body })
		ascendUi.button = Theme.button({ Key = "ascend.button", Color = Theme.Purple, Size = UDim2.fromOffset(260, 52), Position = UDim2.new(0.5, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 1), TextSize = 26, ZIndex = 23, Parent = body, OnClick = function()
			local ok = Kit.request("Rebirth", nil, Lang.t("ascend.done"))
			if ok then
				Windows.close()
			end
		end })
		for _, d in ascendUi.button:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 24
			end
		end
	end
	local req = s.rebirthReq or Formulas.rebirthRequirement(s.rebirths)
	ascendUi.count.Text = "🌟 " .. Lang.t(if s.rebirths == 1 then "ascend.count_one" else "ascend.count", { n = s.rebirths })
	ascendUi.now.Text = Lang.t("ascend.next", { cur = Format.abbrev((1 + s.rebirths) * 100), next = Format.abbrev((2 + s.rebirths) * 100), g = Config.Rebirth.gems })
	Kit.clear(ascendUi.holder)
	Kit.bar(ascendUi.holder, UDim2.fromScale(1, 1), UDim2.new(), Theme.Purple, s.power / req, Format.abbrev(s.power) .. " / " .. Format.abbrev(req))
	Theme.setButton(ascendUi.button, nil, if s.power >= req then Theme.Purple else Theme.Grey)
end

---------------------------------------------------------------------------
-- Travel
---------------------------------------------------------------------------
local PLANET_COLORS = { meadow = Theme.Green, desert = Theme.Yellow, volcano = Theme.Orange, wasteland = Theme.Red, ice = Theme.Cyan, ruins = Theme.Grey, candy = Theme.Pink, storm = Theme.Purple, future = Theme.Blue, void = Theme.Pink }
local function renderTravel(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("travel", body)
	for i, pl in Config.Planets do
		local color = PLANET_COLORS[pl.theme] or Theme.Blue
		local unlocked = table.find(s.planets, i) ~= nil
		local row = Kit.row(list, 72, i, color)
		Kit.chip(row, "🪐", color, 48, UDim2.fromOffset(20, 12))
		Kit.text(row, { Text = Lang.t("planet." .. pl.id) .. "  ·  " .. Lang.t("arc." .. pl.arc), Size = UDim2.new(0.62, 0, 0, 26), Position = UDim2.fromOffset(78, 8), MaxTextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		local zones = {}
		for _, z in pl.zones do
			table.insert(zones, Lang.t("zone." .. z.id) .. " x" .. Format.abbrev(z.mult))
		end
		Kit.text(row, { Text = table.concat(zones, "  ·  "), Size = UDim2.new(0.62, 0, 0, 18), Position = UDim2.fromOffset(78, 38), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		if s.planet == i then
			Kit.text(row, { Text = "📍 " .. Lang.t("travel.here"), Size = UDim2.fromOffset(150, 30), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 18, TextColor3 = Theme.Green })
		elseif unlocked then
			Kit.button(row, Lang.t("travel.go"), Theme.Green, 140, function()
				if Kit.request("Travel", { planet = i }) then
					Windows.close()
				end
			end)
		elseif power(s) < pl.reqPower then
			Kit.text(row, { Text = "🔒 " .. Lang.t("forms.need", { power = Format.abbrev(pl.reqPower) }), Size = UDim2.fromOffset(180, 36), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 16, TextColor3 = Theme.Red })
		else
			Kit.button(row, "⚡ " .. Format.abbrev(pl.cost), if s.sparks >= pl.cost then Theme.Green else Theme.Orange, 140, function()
				if Kit.request("Travel", { planet = i }) then
					Windows.close()
				end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Warrior: multiplier breakdown + race
---------------------------------------------------------------------------
local function renderWarrior(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local left = listOf("warriorLeft", body, UDim2.new(0.52, -6, 1, 0), UDim2.new())
	local right = listOf("warriorRight", body, UDim2.new(0.48, -6, 1, 0), UDim2.new(0.52, 6, 0, 0))
	-- one line per multiplier source; the ones at x1 show what is missing
	local stat = s.settings.stat
	Kit.header(left, "warrior.multipliers", 0, { stat = Lang.t("stat." .. stat) })
	local zone = Config.ZoneById[s.zone]
	local aura = Config.AuraById[s.auraEquipped]
	local race = Config.RaceById[s.race]
	local lines = {
		{ "warrior.m_zone", if zone and not s.zoneLocked then zone.mult else 1 },
		{ "warrior.m_weights", Formulas.gearMult(s.gear) },
		{ "warrior.m_ascension", 1 + s.rebirths },
		{ "warrior.m_upgrade", 1 + Formulas.upgradeValue("trainPower", s.upgrades.trainPower or 0) },
		{ "warrior.m_aura", if aura then aura.mult else 1 },
		{ "warrior.m_wish", 1 + (s.wishPower or 0) * 0.05 },
		{ "warrior.m_pass", (if s.passes.DoubleTraining then 2 else 1) * (if s.passes.VIP then 1 + Config.VipTrainBonus else 1) },
		{ "warrior.m_boost", if (s.boostLeft or 0) > 0 then 2 else 1 },
		{ "warrior.m_event", s.eventEffects and s.eventEffects.trainMult or 1 },
		{ "warrior.m_social", 1 + (s.socialBonus or 0) + (if race and race.bonus == stat then race.amount else 0) },
	}
	for i, l in lines do
		local row = Kit.row(left, 30, i)
		local on = l[2] > 1.0001
		Kit.text(row, { Text = Lang.t(l[1]), Size = UDim2.new(0.66, 0, 1, -10), Position = UDim2.fromOffset(12, 5), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if on then Theme.Text else Theme.Dim, Font = Theme.FontBold })
		Kit.text(row, { Text = "x" .. string.format("%g", math.floor(l[2] * 100 + 0.5) / 100), Font = Theme.Display, Size = UDim2.new(0.3, 0, 1, -6), Position = UDim2.new(1, -10, 0, 3), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 20, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if on then Theme.Green else Theme.Grey })
	end
	local total = Kit.row(left, 38, 50, Theme.Yellow)
	Kit.text(total, { Text = Lang.t("warrior.per_rep"), Size = UDim2.new(0.6, 0, 1, -10), Position = UDim2.fromOffset(18, 5), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
	Kit.text(total, { Text = "+" .. Format.abbrev(s.perRep[stat] or 1), Font = Theme.Display, Size = UDim2.new(0.34, 0, 1, -6), Position = UDim2.new(1, -10, 0, 3), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 26, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow })

	Kit.header(right, "warrior.race", 0)
	for i, r in Config.Races do
		local color = Theme.rgb(r.color)
		local mine = s.race == r.id
		local row = Kit.row(right, 58, i, color)
		Kit.text(row, { Text = Lang.t("race." .. r.id), Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(20, 7), MaxTextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(color, 0.3) })
		Kit.text(row, { Text = Lang.t("race.bonus." .. r.bonus, { n = math.floor(r.amount * 100) }), Size = UDim2.new(0.58, 0, 0, 16), Position = UDim2.fromOffset(20, 32), MaxTextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		if mine then
			Kit.text(row, { Text = "✔", Size = UDim2.fromOffset(40, 30), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 26, TextColor3 = Theme.Green })
		else
			local free = (s.raceChanges or 0) == 0
			Kit.button(row, if free then Lang.t("ui.free") else "💎 " .. Config.RaceChangeGems, if free or s.gems >= Config.RaceChangeGems then Theme.Green else Theme.Grey, 96, function()
				Kit.request("SetRace", { id = r.id })
			end, 36)
		end
	end
end

function Panels.init()
	Kit.window("Forms", "🔥", "menu.Forms", Theme.Orange, Vector2.new(640, 440), renderForms)
	Kit.window("Moves", "☄️", "menu.Moves", Theme.Blue, Vector2.new(660, 450), renderMoves)
	Kit.window("Upgrades", "💎", "menu.Upgrades", Theme.Cyan, Vector2.new(640, 440), renderUpgrades)
	Kit.window("Ascend", "🌟", "menu.Ascend", Theme.Purple, Vector2.new(560, 380), renderAscend)
	Kit.window("Travel", "🪐", "menu.Travel", Theme.Green, Vector2.new(640, 450), renderTravel)
	Kit.window("Warrior", "👤", "menu.Warrior", Theme.Red, Vector2.new(720, 470), renderWarrior)
end

return Panels
