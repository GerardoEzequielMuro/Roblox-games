--!nonstrict
-- Windows: Wardrobe (saga skins, flying mounts, exclusive auras: each one earned by playing
-- or unlocked by a pass) and Season (battle pass: free + premium track, clock, XP bar).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local BattlePass = require(ReplicatedStorage.Shared.BattlePass)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)

local Panels = {}
local inStudio = RunService:IsStudio()
local ROBUX = Color3.fromRGB(168, 60, 240)

local lists: { [string]: ScrollingFrame } = {}
local function listOf(name: string, body: Frame): ScrollingFrame
	local l = lists[name]
	if not l then
		l = Kit.scroll(body)
		lists[name] = l
	end
	Kit.clear(l)
	return l
end

local function now(): number
	local s = Net.state
	if not s then
		return os.time()
	end
	return (s.serverTime or os.time()) + (os.clock() - Net.receivedAt)
end

-- "Defeat Bramble King 1/3 · or get Skin Pack" for a cosmetic's `earn` / `pass`.
local function requirement(def, s): string
	local parts = {}
	local req = def.earn
	if req then
		if req.boss then
			local have = math.min(req.count or 1, (s.bossKills and s.bossKills[req.boss]) or 0)
			table.insert(parts, Lang.t("req.boss", { boss = Lang.t("npc." .. req.boss), have = have, n = req.count or 1 }))
		end
		if req.rebirths then
			table.insert(parts, Lang.t("req.rebirths", { have = math.min(req.rebirths, s.rebirths or 0), n = req.rebirths }))
		end
		if req.pvpKills then
			table.insert(parts, Lang.t("req.pvp", { have = math.min(req.pvpKills, (s.pvp and s.pvp.kills) or 0), n = req.pvpKills }))
		end
	end
	local text = table.concat(parts, " · ")
	if def.pass then
		text = (if text ~= "" then text .. "  " else "") .. Lang.t("req.or_pass", { pass = Lang.t("pass." .. def.pass .. ".name") })
	end
	return text
end

---------------------------------------------------------------------------
-- Wardrobe
---------------------------------------------------------------------------
local function cosmeticRow(list, order: number, title: string, sub: string, color: Color3, owned: boolean, equipped: boolean, onEquip: () -> (), lockedText: string)
	local row = Kit.row(list, 58, order, color)
	Kit.chip(row, if owned then "✔" else "🔒", if owned then color else Theme.Grey, 40, UDim2.fromOffset(20, 9))
	Kit.text(row, { Text = title, Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(72, 6), MaxTextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(color, 0.3) })
	Kit.text(row, { Text = if owned then sub else lockedText, Size = UDim2.new(0.56, -10, 0, 26), Position = UDim2.fromOffset(72, 28), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = if owned then Theme.Dim else Theme.Red, Font = Theme.FontBold })
	if owned then
		Kit.button(row, Lang.t(if equipped then "ui.equipped" else "ui.equip"), if equipped then Theme.Grey else Theme.Green, 120, onEquip, 36)
	end
end

local function renderWardrobe(body: Frame)
	local s = Net.state
	if not s or not s.cosmetics then
		return
	end
	local c = s.cosmetics
	local list = listOf("wardrobe", body)
	-- collection counter: skins + mounts + exclusive auras owned
	local have, total = 0, 0
	for _, sk in Config.Skins do
		total += 1
		have += if c.skins[sk.id] then 1 else 0
	end
	for _, m in Config.Mounts do
		total += 1
		have += if c.mounts[m.id] then 1 else 0
	end
	for _, a in Config.Auras do
		if a.exclusive and (a.earn or a.pass) then
			total += 1
			have += if (s.auras[a.id] or 0) > 0 then 1 else 0
		end
	end
	Kit.header(list, "wardrobe.count", -1, { n = have, total = total })
	Kit.header(list, "wardrobe.skins", 0)
	for i, sk in Config.Skins do
		local owned = c.skins[sk.id] == true
		cosmeticRow(list, i, Lang.t("skin." .. sk.id), Lang.t("wardrobe.saga", { arc = Lang.t("arc." .. sk.arc) }), Theme.rgb(sk.main), owned, c.skin == sk.id, function()
			Kit.request("EquipSkin", { id = if c.skin == sk.id then "" else sk.id })
		end, requirement(sk, s))
	end
	Kit.header(list, "wardrobe.mounts", 20)
	for i, m in Config.Mounts do
		local owned = c.mounts[m.id] == true
		cosmeticRow(list, 20 + i, Lang.t("mount." .. m.id), Lang.t("wardrobe.mount_hint"), Theme.rgb(m.color), owned, c.mount == m.id, function()
			Kit.request("EquipMount", { id = if c.mount == m.id then "" else m.id })
		end, requirement(m, s))
	end
	Kit.header(list, "wardrobe.auras", 30)
	local order = 30
	for _, a in Config.Auras do
		if a.exclusive and (a.earn or a.pass) then
			order += 1
			local owned = (s.auras[a.id] or 0) > 0
			cosmeticRow(list, order, Lang.t("aura." .. a.id), Lang.t("rarity." .. a.rarity) .. " · " .. Lang.t("auras.bonus", { n = string.format("%g", a.mult) }), Theme.rgb(a.color), owned, s.auraEquipped == a.id, function()
				Kit.request("EquipAura", { id = if s.auraEquipped == a.id then "" else a.id })
			end, requirement(a, s))
		end
	end
	local note = Theme.text({ Key = "wardrobe.note", Size = UDim2.new(1, -8, 0, 34), MaxTextSize = 12, TextColor3 = Theme.Dim, LayoutOrder = 60, TextWrapped = true, Font = Theme.FontBold })
	note.ZIndex = 22
	note.Parent = list
end

---------------------------------------------------------------------------
-- Season (battle pass)
---------------------------------------------------------------------------
local function rewardCell(row, x: number, w: number, reward, state: string, color: Color3, onClaim: () -> ())
	local cell = Theme.new("Frame", { Size = UDim2.new(w, -8, 1, -10), Position = UDim2.new(x, 4, 0, 5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 23, Parent = row }, {
		Theme.corner(8),
		Theme.stroke(2, if state == "ready" then Theme.Yellow else Theme.Ink),
		Theme.gradient(Theme.lighten(color, 0.05), Theme.darken(color, 0.3)),
	})
	Kit.text(cell, { Text = Lang.rewardLabel(reward), Size = UDim2.new(1, -90, 1, -8), Position = UDim2.fromOffset(8, 4), MaxTextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
	if state == "claimed" then
		Kit.text(cell, { Text = "✔", Size = UDim2.fromOffset(36, 30), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 24, TextColor3 = Theme.Green })
	elseif state == "ready" then
		Kit.button(cell, Lang.t("ui.claim"), Theme.Green, 76, onClaim, 32)
	else
		Kit.text(cell, { Text = "🔒", Size = UDim2.fromOffset(36, 30), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 22, TextColor3 = Theme.Dim })
	end
end

local function renderSeason(body: Frame)
	local s = Net.state
	if not s or not s.season then
		return
	end
	local se = s.season
	local list = listOf("season", body)
	if se.none then
		local row = Kit.row(list, 90, 1, Theme.Blue)
		Kit.text(row, { Text = if se.nextAt then Lang.t("season.next", { name = Lang.t("season." .. se.nextId), time = Format.time(math.max(0, se.nextAt - now())) }) else Lang.t("season.over"), Size = UDim2.new(1, -40, 1, -20), Position = UDim2.fromOffset(20, 10), MaxTextSize = 22, TextWrapped = true })
		return
	end
	local def = Config.BattlePass.SeasonById[se.id]
	local color = Theme.rgb(def.color)
	-- header card: name, clock, tier bar, buy / skip
	local head = Kit.row(list, 128, 1, color)
	Kit.text(head, { Text = Lang.t("season." .. se.id), Font = Theme.Display, Size = UDim2.new(0.55, 0, 0, 30), Position = UDim2.fromOffset(20, 6), MaxTextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(color, 0.35) })
	Kit.text(head, { Text = Lang.t("season.ends_in", { time = Format.time(math.max(0, se.endsAt - now())) }), Size = UDim2.new(0.4, 0, 0, 18), Position = UDim2.new(1, -16, 0, 10), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow })
	Kit.text(head, { Text = Lang.t("season.tier", { n = se.tier, max = Config.BattlePass.tiers }), Size = UDim2.new(0.3, 0, 0, 20), Position = UDim2.fromOffset(20, 40), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left })
	local barText = if se.tier >= Config.BattlePass.tiers then Lang.t("ui.max") else Lang.t("season.xp_next", { n = se.missing })
	Kit.bar(head, UDim2.new(0.6, -20, 0, 20), UDim2.fromOffset(20, 62), color, se.frac, barText)
	Kit.text(head, { Text = Lang.t("season.how", { q = Config.BattlePass.xp.questClaim, b = Config.BattlePass.xp.bossKill, w = Config.BattlePass.xp.worldBoss, a = Config.BattlePass.xp.arenaWin, m = Config.BattlePass.xp.minutes }), Size = UDim2.new(0.64, -20, 0, 30), Position = UDim2.fromOffset(20, 90), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = Theme.Dim, Font = Theme.FontBold })
	local product = Config.ProductByKey[def.product]
	local buy = Kit.button(head, if se.premium then "✔ " .. Lang.t("season.premium_on") else utf8.char(0xE002) .. " " .. product.price .. "  " .. Lang.t("season.premium"), if se.premium then Theme.Grey else ROBUX, 210, function()
		if not se.premium then
			Purchase.product(def.product)
		end
	end, 36)
	buy.Position = UDim2.new(1, -10, 0, 56)
	buy.AnchorPoint = Vector2.new(1, 0)
	local skipProduct = Config.ProductByKey.TierSkip
	if (Purchase.productAvailable("TierSkip") or inStudio) and se.tier < Config.BattlePass.tiers then
		local skip = Kit.button(head, utf8.char(0xE002) .. " " .. skipProduct.price .. "  " .. Lang.t("season.skip"), ROBUX, 210, function()
			Purchase.product("TierSkip")
		end, 30)
		skip.Position = UDim2.new(1, -10, 0, 96)
		skip.AnchorPoint = Vector2.new(1, 0)
	end
	-- claim all
	if se.claimable > 0 then
		local row = Kit.row(list, 46, 2, Theme.Green)
		Kit.text(row, { Text = Lang.t("season.waiting", { n = se.claimable }), Size = UDim2.new(0.6, 0, 1, -10), Position = UDim2.fromOffset(20, 5), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.button(row, Lang.t("season.claim_all"), Theme.Green, 150, function()
			Kit.request("ClaimPassAll")
		end, 34)
	end
	-- Round 6: daily first win + catch-up bonus, and the weekly challenges
	if se.weekly then
		local daily = Kit.row(list, 66, 3, Theme.Yellow)
		Kit.text(daily, { Text = Lang.t("season.firstwin", { n = se.firstWinXp }), Size = UDim2.new(0.5, -20, 0, 24), Position = UDim2.fromOffset(20, 8), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.text(daily, { Text = Lang.t(if se.firstWinReady then "season.firstwin_ready" else "season.firstwin_done"), Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.fromOffset(20, 36), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if se.firstWinReady then Theme.Dim else Theme.Green, Font = Theme.FontBold })
		if (se.catchUp or 1) > 1 then
			Kit.text(daily, { Text = Lang.t("season.catchup", { m = string.format("%g", se.catchUp) }), Size = UDim2.new(0.46, -10, 0, 24), Position = UDim2.new(1, -14, 0, 8), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Green })
			Kit.text(daily, { Text = Lang.t("season.catchup_hint"), Size = UDim2.new(0.46, -10, 0, 30), Position = UDim2.new(1, -14, 0, 32), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		end
		local card = Kit.row(list, 38 + #se.weekly * 34, 4, Theme.Cyan)
		Kit.text(card, { Text = Lang.t("season.weekly_title"), Font = Theme.Display, Size = UDim2.new(0.4, 0, 0, 26), Position = UDim2.fromOffset(20, 6), MaxTextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(Theme.Cyan, 0.3) })
		Kit.text(card, { Text = Lang.t("season.weekly_reset", { time = Format.time(math.max(0, se.weekResetIn - (os.clock() - Net.receivedAt))) }), Size = UDim2.new(0.4, 0, 0, 18), Position = UDim2.new(1, -14, 0, 10), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow })
		for i, c in se.weekly do
			local y = 38 + (i - 1) * 34
			Kit.text(card, { Text = Lang.t("weekly." .. c.id, { n = c.target }), Size = UDim2.new(0.48, -20, 0, 28), Position = UDim2.fromOffset(20, y), MaxTextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if c.done then Theme.Green else Color3.new(1, 1, 1) })
			Kit.bar(card, UDim2.new(0.32, 0, 0, 22), UDim2.new(0.5, 0, 0, y + 3), if c.done then Theme.Green else Theme.Cyan, c.have / c.target, if c.done then "✔" else c.have .. "/" .. c.target)
			Kit.text(card, { Text = "+" .. c.xp .. " XP", Size = UDim2.new(0.14, -14, 0, 28), Position = UDim2.new(1, -14, 0, y), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if c.done then Theme.Dim else Theme.Yellow })
		end
	end
	-- column titles
	local titles = Kit.row(list, 28, 5)
	Kit.text(titles, { Text = Lang.t("season.free"), Size = UDim2.new(0.4, 0, 1, -6), Position = UDim2.new(0.18, 0, 0, 3), MaxTextSize = 15, TextColor3 = Theme.Green })
	Kit.text(titles, { Text = Lang.t("season.premium_track"), Size = UDim2.new(0.4, 0, 1, -6), Position = UDim2.new(0.6, 0, 0, 3), MaxTextSize = 15, TextColor3 = Theme.Yellow })
	for tier = 1, Config.BattlePass.tiers do
		local row = Kit.row(list, 50, 10 + tier)
		local reached = se.tier >= tier
		Kit.text(row, { Text = tostring(tier), Font = Theme.Display, Size = UDim2.new(0.1, 0, 1, -10), Position = UDim2.new(0.02, 0, 0, 5), MaxTextSize = 24, TextColor3 = if reached then Theme.Yellow else Theme.Dim })
		for col, track in { "free", "premium" } do
			local reward = BattlePass.reward(se.id, track, tier)
			local claimed = (if track == "free" then se.free else se.paid)[tostring(tier)] == true
			local state = if claimed then "claimed" elseif reached and (track == "free" or se.premium) then "ready" else "locked"
			rewardCell(row, if col == 1 then 0.13 else 0.565, 0.435, reward, state, if track == "free" then Theme.Panel else Theme.darken(color, 0.1), function()
				Kit.request("ClaimPass", { track = track, tier = tier })
			end)
		end
	end
end

function Panels.init()
	Kit.window("Wardrobe", "🎽", "menu.Wardrobe", Theme.Pink, Vector2.new(720, 470), renderWardrobe)
	Kit.window("Season", "🎟️", "menu.Season", Theme.Purple, Vector2.new(760, 500), renderSeason)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Season") then
				Net.refresh()
			end
		end
	end)
	local _ = Players
end

return Panels
