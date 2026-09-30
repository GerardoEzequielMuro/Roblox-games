--!nonstrict
-- Windows: Quests (story + daily), Rewards (daily streak, play-time gifts, codes), Shop,
-- Auras (spin with its odds), Wish, Ranking, Invite and Settings.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)
local Ads = require(script.Parent.Parent.Ads)
local Story = require(script.Parent.Parent.StoryText)

local Panels = {}
local new = Theme.new
local player = Players.LocalPlayer

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

local function now(): number
	local s = Net.state
	if not s then
		return os.time()
	end
	return (s.serverTime or os.time()) + (os.clock() - Net.receivedAt)
end
Panels.now = now

local function rewardText(r): string
	return Lang.rewardLabel(r)
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local function renderQuests(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("quests", body)
	-- story
	Kit.header(list, "quests.story", 0)
	local step = Config.Story[s.story.step]
	local card = Kit.row(list, 78, 1, Theme.Orange)
	if step then
		Kit.text(card, { Text = Story.text(step), Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 6), MaxTextSize = 20, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.bar(card, UDim2.new(0.62, -20, 0, 20), UDim2.fromOffset(20, 36), Theme.Orange, s.story.progress / step.target, Format.abbrev(s.story.progress) .. " / " .. Format.abbrev(step.target))
		local parts = {}
		if step.sparks and step.sparks > 0 then
			table.insert(parts, "⚡ " .. Format.abbrev(step.sparks))
		end
		if step.gems and step.gems > 0 then
			table.insert(parts, "💎 " .. step.gems)
		end
		Kit.text(card, { Text = table.concat(parts, "   "), Font = Theme.Display, Size = UDim2.new(0.34, 0, 0, 26), Position = UDim2.new(1, -14, 0, 32), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow })
		Kit.text(card, { Text = Lang.t("quests.chapter", { n = s.story.step, total = #Config.Story }), Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.fromOffset(20, 60), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
	else
		Kit.text(card, { Key = "quests.story_done", Size = UDim2.new(1, -40, 1, -20), Position = UDim2.fromOffset(20, 10), MaxTextSize = 22 })
	end
	-- daily
	local q = s.quests
	if q then
		Kit.header(list, "quests.daily", 10, { time = Format.time(math.max(0, q.resetsAt - now())) })
		local allClaimed = true
		for i, quest in q.list do
			local done = quest.progress >= quest.target
			local row = Kit.row(list, 58, 10 + i, Theme.Cyan)
			Kit.text(row, { Text = Lang.t("quest." .. quest.kind, { n = Format.abbrev(quest.target) }), Size = UDim2.new(0.6, 0, 0, 22), Position = UDim2.fromOffset(20, 6), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
			Kit.bar(row, UDim2.new(0.6, -20, 0, 18), UDim2.fromOffset(20, 32), Theme.Cyan, quest.progress / quest.target, Format.abbrev(quest.progress) .. " / " .. Format.abbrev(quest.target))
			if quest.claimed then
				Kit.text(row, { Text = "✔", Size = UDim2.fromOffset(40, 30), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 26, TextColor3 = Theme.Green })
			else
				allClaimed = false
				Kit.button(row, "💎 " .. quest.gems, if done then Theme.Green else Theme.Grey, 110, function()
					Kit.request("ClaimQuest", { i = i })
				end, 38)
			end
		end
		local bonus = Kit.row(list, 50, 30, Theme.Yellow)
		Kit.text(bonus, { Key = "quests.bonus", Size = UDim2.new(0.6, 0, 1, -16), Position = UDim2.fromOffset(20, 8), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
		if q.bonusClaimed then
			Kit.text(bonus, { Text = "✔", Size = UDim2.fromOffset(40, 30), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), MaxTextSize = 26, TextColor3 = Theme.Green })
		else
			Kit.button(bonus, "💎 " .. q.bonus, if allClaimed then Theme.Green else Theme.Grey, 110, function()
				Kit.request("ClaimQuestBonus")
			end, 38)
		end
	end
end

---------------------------------------------------------------------------
-- Rewards: daily streak, gifts, codes
---------------------------------------------------------------------------
local codeBox: TextBox? = nil
local function renderRewards(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("rewards", body)
	local daily = s.dailyState
	if daily then
		Kit.header(list, "rewards.daily", -2)
		Kit.header(list, "rewards.streak", -1, { n = daily.streak })
		local strip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 1, ZIndex = 22, Parent = list }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local today = (daily.streak % #Config.DailyRewards) + 1
		for i, r in Config.DailyRewards do
			local claimed = i < today or (i == today and not daily.canClaim and daily.streak > 0 and false)
			local isToday = i == today
			local color = if isToday and daily.canClaim then Theme.Green elseif claimed then Theme.Grey else Theme.PanelLight
			local c = new("TextButton", { Size = UDim2.fromOffset(86, 88), BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 22, Parent = strip }, {
				Theme.corner(10),
				Theme.stroke(if isToday then 3.5 else 2.5, if isToday then Theme.Yellow else Theme.Ink),
				Theme.gradient(Theme.lighten(color, 0.12), Theme.darken(color, 0.25)),
			})
			Kit.text(c, { Text = Lang.t("rewards.day", { n = i }), Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 4), MaxTextSize = 13 })
			Kit.text(c, { Text = Lang.t("rewardicon." .. r.kind), Stroke = false, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 20), MaxTextSize = 30 })
			Kit.text(c, { Text = if claimed then "✔" else rewardText(r), Size = UDim2.new(1, -6, 0, 28), Position = UDim2.fromOffset(3, 56), MaxTextSize = 13, TextWrapped = true, TextColor3 = if claimed then Theme.Green else Theme.Text })
			if isToday and daily.canClaim then
				c.Activated:Connect(function()
					Kit.request("ClaimDaily")
				end)
			end
		end
		if not daily.canClaim then
			local t = Theme.text({ Text = Lang.t("rewards.next_in", { time = Format.time(math.max(0, daily.nextAt - now())) }), Size = UDim2.new(1, 0, 0, 16), MaxTextSize = 13, TextColor3 = Theme.Dim, LayoutOrder = 2, Font = Theme.FontBold })
			t.ZIndex = 22
			t.Parent = list
		end
	end
	-- gifts by play time this session
	Kit.header(list, "rewards.gifts", 10)
	local elapsed = now() - (s.sessionStart or now())
	local gifts = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 86), LayoutOrder = 11, ZIndex = 22, Parent = list }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	for i, g in Config.Gifts do
		local claimed = s.giftsClaimed and s.giftsClaimed[i] == true
		local ready = elapsed >= g.minutes * 60
		local color = if claimed then Theme.Grey elseif ready then Theme.Green else Theme.PanelLight
		local c = new("TextButton", { Name = "Gift" .. i, Size = UDim2.fromOffset(86, 82), BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 22, Parent = gifts }, {
			Theme.corner(10),
			Theme.stroke(2.5),
			Theme.gradient(Theme.lighten(color, 0.12), Theme.darken(color, 0.25)),
		})
		Kit.text(c, { Text = Lang.t("rewardicon." .. g.reward.kind), Stroke = false, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 4), MaxTextSize = 28 })
		Kit.text(c, { Text = rewardText(g.reward), Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 34), MaxTextSize = 12, TextWrapped = true })
		Kit.text(c, { Text = if claimed then "✔" elseif ready then Lang.t("ui.claim") else Format.time(g.minutes * 60 - elapsed), Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 62), MaxTextSize = 14, TextColor3 = if ready and not claimed then Theme.Yellow else Theme.Dim })
		if ready and not claimed then
			c.Activated:Connect(function()
				Kit.request("ClaimGift", { index = i })
			end)
		end
	end
	-- codes
	Kit.header(list, "rewards.codes", 20)
	local row = Kit.row(list, 54, 21)
	local saved = if codeBox then codeBox.Text else ""
	codeBox = new("TextBox", { Name = "CodeBox", Size = UDim2.new(1, -170, 0, math.max(36, Theme.minButtonH)), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.PanelDark, Font = Theme.FontBold, TextSize = 20, TextColor3 = Theme.Text, PlaceholderText = Lang.t("rewards.code_hint"), PlaceholderColor3 = Theme.Dim, Text = saved, ClearTextOnFocus = false, ZIndex = 23, Parent = row }, { Theme.corner(8), Theme.stroke(2) })
	Kit.button(row, Lang.t("rewards.redeem"), Theme.Green, 140, function()
		local box = codeBox
		if box and box.Text ~= "" then
			local ok = Kit.request("RedeemCode", { code = box.Text })
			if ok then
				box.Text = ""
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------
local inStudio = RunService:IsStudio()
local function card(parent: Instance, order: number, icon: string, color: Color3, title: string, desc: string, price: string, priceColor: Color3, onBuy: () -> (), tag: string?): Frame
	local f = new("Frame", { Size = UDim2.fromOffset(330, 92), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, ZIndex = 22 }, {
		Theme.corner(12),
		Theme.stroke(2.5),
		Theme.gradient(Theme.lighten(Theme.PanelLight, 0.06), Theme.Panel),
	})
	Kit.chip(f, icon, color, 56, UDim2.fromOffset(10, 18))
	Kit.text(f, { Text = title, Size = UDim2.new(1, -190, 0, 24), Position = UDim2.fromOffset(74, 8), MaxTextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
	Kit.text(f, { Text = desc, Size = UDim2.new(1, -190, 0, 50), Position = UDim2.fromOffset(74, 34), MaxTextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = Theme.Dim, Font = Theme.FontBold })
	Kit.button(f, price, priceColor, 102, onBuy, 40)
	if tag then
		local t = new("Frame", { Size = UDim2.fromOffset(84, 20), Position = UDim2.new(1, -6, 0, -6), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Theme.Red, ZIndex = 25, Parent = f }, { Theme.corner(8), Theme.stroke(2) })
		Kit.text(t, { Text = tag, Size = UDim2.new(1, -4, 1, -2), Position = UDim2.fromOffset(2, 1), MaxTextSize = 12, ZIndex = 26 })
	end
	f.Parent = parent
	return f
end

local ROBUX = Color3.fromRGB(168, 60, 240)
local function grid(list: Instance, order: number): Frame
	return new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = 22, Parent = list }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(330, 92), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
end

local function renderShop(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("shop", body)
	local shown = 0
	-- starter pack (first 24 h)
	local starter = s.starter
	if starter and (starter.available or (inStudio and not Purchase.productAvailable("StarterPack"))) then
		shown += 1
		local row = Kit.row(list, 84, 0, Theme.Pink)
		Kit.chip(row, "🎁", Theme.Pink, 56, UDim2.fromOffset(20, 14))
		Kit.text(row, { Text = Lang.t("product.StarterPack.name"), Size = UDim2.new(0.5, 0, 0, 26), Position = UDim2.fromOffset(88, 6), MaxTextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Yellow })
		Kit.text(row, { Text = Lang.t("product.StarterPack.desc", { n = Config.StarterPack.gems, minutes = Config.StarterPack.boostMinutes, spark = Config.StarterPack.sparkMinutes, aura = Lang.t("aura." .. Config.StarterPack.aura) }), Size = UDim2.new(0.62, 0, 0, 30), Position = UDim2.fromOffset(88, 32), MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = Theme.Text, Font = Theme.FontBold })
		Kit.text(row, { Text = Lang.t("shop.ends_in", { time = Format.time(math.max(0, starter.endsAt - now())) }), Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.fromOffset(88, 64), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Red })
		-- the crossed-out number is what the same contents cost if bought one by one in this shop
		Kit.text(row, { Text = Lang.t("shop.value", { price = "<s>" .. starter.fullPrice .. "</s>" }), RichText = true, Size = UDim2.fromOffset(190, 16), Position = UDim2.new(1, -12, 0, 6), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 13, TextColor3 = Theme.Dim })
		Kit.button(row, utf8.char(0xE002) .. " " .. starter.price, ROBUX, 120, function()
			Purchase.product("StarterPack")
		end)
	end
	-- passes
	local passes = {}
	for _, p in Config.Passes do
		local restricted = p.key == "LuckyAura" and s.randomRestricted
		if (Purchase.passAvailable(p.key) or inStudio) and not restricted then
			table.insert(passes, p)
		end
	end
	if #passes > 0 then
		Kit.header(list, "shop.passes", 10)
		local g = grid(list, 11)
		for i, p in passes do
			shown += 1
			local owned = s.passes[p.key] == true
			local apart = 0
			for _, k in p.implies or {} do
				apart += Config.PassByKey[k].price
			end
			local desc = Lang.t("pass." .. p.key .. ".desc", { price = apart })
			if p.earnable then
				desc ..= " " .. Lang.t("shop.earnable")
			end
			card(g, i, p.icon, Theme.Yellow, Lang.t("pass." .. p.key .. ".name"), desc, if owned then "✔" else utf8.char(0xE002) .. " " .. p.price, if owned then Theme.Grey else ROBUX, function()
				if not owned then
					Purchase.pass(p.key)
				end
			end)
		end
	end
	-- products
	local products = {}
	for _, p in Config.Products do
		if p.kind ~= "starter" and p.kind ~= "bp" and p.kind ~= "bpskip" and (Purchase.productAvailable(p.key) or inStudio) then
			table.insert(products, p)
		end
	end
	if #products > 0 then
		Kit.header(list, "shop.products", 20)
		local g = grid(list, 21)
		for i, p in products do
			shown += 1
			local color = if p.kind == "gems" then Theme.Cyan elseif p.kind == "sparks" then Theme.Yellow elseif p.kind == "boost" then Theme.Orange else Theme.Purple
			local tag = if p.key == "Gems3" or p.key == "Sparks3" then Lang.t("shop.best") else nil
			card(g, i, p.icon, color, Lang.t("product." .. p.key .. ".name"), Lang.t("product." .. p.key .. ".desc", { n = Format.abbrev(p.amount) }), utf8.char(0xE002) .. " " .. p.price, ROBUX, function()
				Purchase.product(p.key)
			end, tag)
		end
	end
	-- seeds: bought with Sparks (limited stock that restocks on the hour), used from here or J / K / L
	local seeds = s.seeds
	if seeds then
		shown += 1
		local left = seeds.nextRestock - now()
		if left <= 0 then
			Net.pull()
		end
		Kit.header(list, "shop.seeds", 23, { time = Format.time(math.max(0, left)) })
		for i, def in Config.Seeds do
			local info = seeds.shop[def.id]
			local have = seeds.items[def.id] or 0
			local row = Kit.row(list, 64, 23 + i, Theme.rgb(def.color))
			Kit.chip(row, def.icon, Theme.rgb(def.color), 44, UDim2.fromOffset(20, 10))
			Kit.text(row, { Text = Lang.t("item." .. def.id) .. "  x" .. have, Size = UDim2.new(0.42, 0, 0, 22), Position = UDim2.fromOffset(76, 6), MaxTextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
			Kit.text(row, { Text = Lang.t("seed." .. def.id .. ".desc", { n = def.seconds and def.seconds // 60 or 0, pct = def.damageMult and math.floor((def.damageMult - 1) * 100 + 0.5) or 0, x = def.regenMult or 0, ki = def.kiGive and math.floor(def.kiGive * 100) or 0 }), Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(76, 28), MaxTextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = Theme.Dim, Font = Theme.FontBold })
			local buy = Kit.button(row, "⚡ " .. Format.abbrev(info.price) .. "  " .. info.stock .. "/" .. def.stockPerHour, if info.stock > 0 and s.sparks >= info.price then Theme.Green else Theme.Grey, 150, function()
				Kit.request("BuySeed", { id = def.id })
			end, 38)
			buy.Position = UDim2.new(1, -96, 0.5, 0)
			local use = Kit.button(row, Lang.t("seed.use"), if have > 0 then Theme.Orange else Theme.Grey, 80, function()
				Kit.request("UseSeed", { id = def.id })
			end, 38)
			use.Position = UDim2.new(1, -10, 0.5, 0)
		end
	end
	-- rewarded video
	if Ads.canShow("AdBoost") then
		shown += 1
		local row = Kit.row(list, 56, 30, Theme.Green)
		Kit.text(row, { Text = Lang.t("shop.ad_boost", { n = Config.AdBoostMinutes }), Size = UDim2.new(0.66, 0, 1, -16), Position = UDim2.fromOffset(20, 8), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.button(row, "▶ " .. Lang.t("shop.watch"), Theme.Green, 140, function()
			Ads.watch("AdBoost")
		end)
	end
	if shown == 0 then
		local t = Theme.text({ Key = "shop.empty", Size = UDim2.new(1, 0, 0, 60), MaxTextSize = 22, TextColor3 = Theme.Dim })
		t.ZIndex = 22
		t.Parent = list
	end
end

---------------------------------------------------------------------------
-- Auras (spin with its odds on screen)
---------------------------------------------------------------------------
local lastSpin: { id: string, new: boolean }? = nil
local function renderAuras(body: Frame)
	local s = Net.state
	if not s or not s.auraSpin then
		return
	end
	local left = listOf("aurasLeft", body, UDim2.new(0.5, -6, 1, 0), UDim2.new())
	local right = listOf("aurasRight", body, UDim2.new(0.5, -6, 1, 0), UDim2.new(0.5, 6, 0, 0))
	local spin = s.auraSpin
	-- spin box
	local box = Kit.row(left, 150, 1, Theme.Purple)
	local result = lastSpin
	if result then
		local a = Config.AuraById[result.id]
		local rarity = Config.RarityByName[a.rarity]
		Kit.text(box, { Text = Lang.t("aura." .. a.id), Font = Theme.Display, Size = UDim2.new(1, -30, 0, 34), Position = UDim2.fromOffset(20, 6), MaxTextSize = 32, TextColor3 = Theme.lighten(Theme.rgb(a.color), 0.2) })
		Kit.text(box, { Text = Lang.t("rarity." .. a.rarity) .. " · x" .. string.format("%g", a.mult) .. (if result.new then "  " .. Lang.t("ui.new") else ""), Size = UDim2.new(1, -30, 0, 20), Position = UDim2.fromOffset(20, 40), MaxTextSize = 16, TextColor3 = Theme.rgb(rarity.color) })
	else
		Kit.text(box, { Key = "auras.spin_title", Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(20, 8), MaxTextSize = 24 })
		Kit.text(box, { Key = "auras.spin_hint", Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(20, 38), MaxTextSize = 14, TextColor3 = Theme.Dim, Font = Theme.FontBold, TextWrapped = true })
	end
	local free = (if spin.freeToday then 1 else 0) + (s.spins or 0)
	local function doSpin(paid: boolean)
		local ok, res = Net.request("SpinAura", { paid = paid })
		if ok then
			lastSpin = res
			Theme.play("boom", 0.4, 1.5)
		elseif Kit.notify then
			Kit.notify(Lang.msg(res), "error")
		end
	end
	local freeBtn = Theme.button({ Name = "SpinFree", Text = Lang.t("auras.free", { n = free }), Color = if free > 0 then Theme.Green else Theme.Grey, Size = UDim2.new(0.5, -22, 0, 46), Position = UDim2.new(0, 16, 1, -10), AnchorPoint = Vector2.new(0, 1), TextSize = 18, ZIndex = 23, Parent = box, OnClick = function()
		doSpin(false)
	end })
	for _, d in freeBtn:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 24
		end
	end
	if not s.randomRestricted then
		local paidBtn = Theme.button({ Name = "SpinPaid", Text = "💎 " .. spin.cost, Color = if s.gems >= spin.cost then Theme.Cyan else Theme.Grey, Size = UDim2.new(0.5, -22, 0, 46), Position = UDim2.new(1, -12, 1, -10), AnchorPoint = Vector2.new(1, 1), TextSize = 20, ZIndex = 23, Parent = box, OnClick = function()
			doSpin(true)
		end })
		for _, d in paidBtn:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 24
			end
		end
	end
	-- owned
	Kit.header(left, "auras.owned", 5)
	local owned = {}
	for id, n in s.auras do
		local a = Config.AuraById[id]
		if a then
			table.insert(owned, { a = a, n = n })
		end
	end
	table.sort(owned, function(x, y)
		return x.a.mult > y.a.mult
	end)
	if #owned == 0 then
		local t = Theme.text({ Key = "auras.none", Size = UDim2.new(1, 0, 0, 30), MaxTextSize = 15, TextColor3 = Theme.Dim, LayoutOrder = 6, Font = Theme.FontBold })
		t.ZIndex = 22
		t.Parent = left
	end
	for i, o in owned do
		local a = o.a
		local row = Kit.row(left, 44, 6 + i, Theme.rgb(a.color))
		Kit.text(row, { Text = Lang.t("aura." .. a.id) .. (if o.n > 1 then " x" .. o.n else ""), Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(20, 4), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(Theme.rgb(a.color), 0.3) })
		Kit.text(row, { Text = Lang.t("auras.bonus", { n = string.format("%g", a.mult) }), Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.fromOffset(20, 26), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Dim, Font = Theme.FontBold })
		local on = s.auraEquipped == a.id
		Kit.button(row, Lang.t(if on then "ui.equipped" else "ui.equip"), if on then Theme.Grey else Theme.Green, 110, function()
			Kit.request("EquipAura", { id = if on then "" else a.id })
		end, 34)
	end
	-- odds: every outcome with its percentage (they add up to 100)
	Kit.header(right, if spin.lucky then "auras.odds_lucky" else "auras.odds", 0)
	for i, o in spin.odds do
		local a = Config.AuraById[o.id]
		local rarity = Config.RarityByName[a.rarity]
		local row = Kit.row(right, 30, i, Theme.rgb(rarity.color))
		row.Name = "Odds_" .. o.id
		Kit.text(row, { Text = Lang.t("aura." .. a.id), Size = UDim2.new(0.42, 0, 1, -8), Position = UDim2.fromOffset(18, 4), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.lighten(Theme.rgb(a.color), 0.3) })
		Kit.text(row, { Text = Lang.t("rarity." .. a.rarity) .. " x" .. string.format("%g", a.mult), Size = UDim2.new(0.32, 0, 1, -12), Position = UDim2.new(0.44, 0, 0, 6), MaxTextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.rgb(rarity.color), Font = Theme.FontBold })
		Kit.text(row, { Name = "Pct", Text = Format.chance(o.pct), Font = Theme.Display, Size = UDim2.new(0.22, 0, 1, -6), Position = UDim2.new(1, -10, 0, 3), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow })
	end
	local note = Theme.text({ Key = if s.randomRestricted then "auras.restricted" else "auras.note", Size = UDim2.new(1, -8, 0, 34), MaxTextSize = 12, TextColor3 = Theme.Dim, LayoutOrder = 50, TextWrapped = true, Font = Theme.FontBold })
	note.ZIndex = 22
	note.Parent = right
end

---------------------------------------------------------------------------
-- Wish
---------------------------------------------------------------------------
local WISH_ICONS = { sparks = "⚡", gems = "💎", boost = "🔥", auras = "🌀", power = "🌟" }
local function renderWish(body: Frame)
	local s = Net.state
	if not s or not s.relics then
		return
	end
	local list = listOf("wish", body)
	local r = s.relics
	local ready = r.found >= r.total
	local head = Kit.row(list, 56, 0, Theme.Yellow)
	if now() < r.nextAt then
		Kit.text(head, { Text = Lang.t("wish.cooldown", { time = Format.time(r.nextAt - now()) }), Size = UDim2.new(1, -40, 1, -16), Position = UDim2.fromOffset(20, 8), MaxTextSize = 18 })
	else
		Kit.text(head, { Text = Lang.t("wish.found", { n = r.found, total = r.total }), Size = UDim2.new(0.5, 0, 1, -16), Position = UDim2.fromOffset(20, 8), MaxTextSize = 20, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.bar(head, UDim2.new(0.42, 0, 0, 20), UDim2.new(0.54, 0, 0.5, -10), Theme.Yellow, r.found / r.total, r.found .. " / " .. r.total)
	end
	for i, w in Config.Wishes do
		local row = Kit.row(list, 54, i, Theme.Purple)
		Kit.chip(row, WISH_ICONS[w.id] or "🌠", Theme.Purple, 40, UDim2.fromOffset(18, 7))
		local maxed = w.id == "power" and (s.wishPower or 0) >= Config.WishPowerMax
		Kit.text(row, { Text = Lang.t("wish." .. w.id, { n = w.sparkMinutes or w.gems or w.boostMinutes or w.spins or 5 }), Size = UDim2.new(1, -230, 1, -14), Position = UDim2.fromOffset(68, 7), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
		Kit.button(row, Lang.t(if maxed then "ui.max" else "wish.choose"), if ready and not maxed then Theme.Green else Theme.Grey, 130, function()
			if Kit.request("Wish", { id = w.id }) then
				Windows.close()
			end
		end, 38)
	end
	if Purchase.productAvailable("WishNow") and not ready and now() >= r.nextAt then
		local row = Kit.row(list, 50, 40, Theme.Pink)
		Kit.text(row, { Text = Lang.t("product.WishNow.desc", { n = 1 }), Size = UDim2.new(0.62, 0, 1, -14), Position = UDim2.fromOffset(20, 7), MaxTextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
		Kit.button(row, utf8.char(0xE002) .. " " .. Config.ProductByKey.WishNow.price, ROBUX, 120, function()
			Purchase.product("WishNow")
		end, 36)
	end
end

---------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------
local boardTab = "power"
local boardRows: { [string]: { any } }? = nil
local function renderRanking(body: Frame)
	local list = listOf("ranking", body, UDim2.new(1, 0, 1, -50), UDim2.fromOffset(0, 50))
	local tabs = body:FindFirstChild("Tabs")
	if not tabs then
		tabs = new("Frame", { Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), ZIndex = 22, Parent = body }, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	end
	Kit.clear(tabs)
	for i, id in { "power", "rebirths", "arena" } do
		local b = Theme.button({ Text = Lang.t("board." .. id), Color = if boardTab == id then Theme.Orange else Theme.Grey, Size = UDim2.fromOffset(160, 40), TextSize = 16, LayoutOrder = i, ZIndex = 23, Parent = tabs, OnClick = function()
			boardTab = id
			renderRanking(body)
		end })
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 24
			end
		end
	end
	local rows = boardRows and boardRows[boardTab] or {}
	if #rows == 0 then
		local t = Theme.text({ Key = "world.board_empty", Size = UDim2.new(1, 0, 0, 50), MaxTextSize = 20, TextColor3 = Theme.Dim })
		t.ZIndex = 22
		t.Parent = list
	end
	local medals = { Theme.Yellow, Color3.fromRGB(220, 225, 235), Color3.fromRGB(230, 150, 90) }
	for i, r in rows do
		local row = Kit.row(list, 36, i, medals[i])
		Kit.text(row, { Text = "#" .. i, Font = Theme.Display, Size = UDim2.fromOffset(44, 24), Position = UDim2.fromOffset(16, 6), MaxTextSize = 22, TextColor3 = medals[i] or Theme.Text })
		Kit.text(row, { Text = r.name, Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(66, 7), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.text(row, { Text = r.value, Font = Theme.Display, Size = UDim2.new(0.3, 0, 0, 24), Position = UDim2.new(1, -12, 0, 6), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow })
	end
end

---------------------------------------------------------------------------
-- Invite
---------------------------------------------------------------------------
local function renderInvite(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("invite", body)
	local info = Theme.text({ Text = Lang.t("invite.info", { you = rewardText(Config.ReferralInviterGift), friend = rewardText(Config.ReferralInviteeGift) }), Size = UDim2.new(1, -8, 0, 56), MaxTextSize = 16, TextWrapped = true, LayoutOrder = 0, Font = Theme.FontBold })
	info.ZIndex = 22
	info.Parent = list
	local r1 = Kit.row(list, 56, 1, Theme.Green)
	Kit.text(r1, { Key = "invite.friends", Size = UDim2.new(0.6, 0, 1, -16), Position = UDim2.fromOffset(20, 8), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
	Kit.button(r1, Lang.t("invite.button"), Theme.Green, 150, function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				local options = Instance.new("ExperienceInviteOptions")
				options.LaunchData = "ref:" .. player.UserId
				SocialService:PromptGameInvite(player, options)
			end)
		elseif Kit.notify then
			Kit.notify(Lang.t("msg.share_unavailable"), "error")
		end
	end)
	local r2 = Kit.row(list, 56, 2, Theme.Cyan)
	Kit.text(r2, { Key = "invite.link", Size = UDim2.new(0.6, 0, 1, -16), Position = UDim2.fromOffset(20, 8), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
	Kit.button(r2, Lang.t("invite.share"), Theme.Cyan, 150, function()
		Kit.request("ShareLink")
	end)
	local social = s.social
	if social and social.groupId ~= 0 then
		local r3 = Kit.row(list, 56, 3, Theme.Purple)
		Kit.text(r3, { Text = Lang.t("invite.group", { aura = Lang.t("aura." .. Config.GroupGiftAura), pct = math.floor(Config.GroupBonus * 100) }), Size = UDim2.new(0.6, 0, 1, -12), Position = UDim2.fromOffset(20, 6), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
		Kit.button(r3, Lang.t(if social.groupGiftClaimed then "ui.claimed" else "ui.claim"), if social.groupGiftClaimed then Theme.Grey else Theme.Purple, 150, function()
			Kit.request("ClaimGroupGift")
		end)
	end
	local count = Theme.text({ Text = Lang.t("invite.count", { n = social and social.referralRewards or 0, max = Config.ReferralLifetimeCap }), Size = UDim2.new(1, 0, 0, 18), MaxTextSize = 14, TextColor3 = Theme.Dim, LayoutOrder = 9, Font = Theme.FontBold })
	count.ZIndex = 22
	count.Parent = list
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function renderSettings(body: Frame)
	local s = Net.state
	if not s then
		return
	end
	local list = listOf("settings", body)
	local function toggle(order: number, key: string, locKey: string, value: boolean, onClick: () -> ())
		local row = Kit.row(list, 44, order)
		row.Name = "Setting_" .. key
		Kit.text(row, { Key = locKey, Size = UDim2.new(0.66, 0, 1, -14), Position = UDim2.fromOffset(16, 7), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left })
		Kit.button(row, Lang.t(if value then "hud.on" else "hud.off"), if value then Theme.Green else Theme.Grey, 90, onClick, 32)
	end
	local Controls = require(script.Parent.Parent.Controls)
	for i, key in { "sfx", "shake", "lite" } do
		toggle(i, key, "settings." .. key, s.settings[key] == true, function()
			Controls.toggleSetting(key)
		end)
	end
	if s.arena then
		toggle(5, "protection", "settings.protection", not s.protectionOff, function()
			Kit.request("SetProtection", { off = not s.protectionOff })
		end)
	end
	Kit.header(list, "settings.language", 10)
	local g = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 11, ZIndex = 22, Parent = list }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(158, math.max(38, Theme.minButtonH)), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	for i, l in Locale.Languages do
		local on = Lang.code == l.code
		local b = Theme.button({ Name = "Lang_" .. l.code, Text = l.name, Color = if on then Theme.Green else Theme.Blue, TextSize = 16, LayoutOrder = i, ZIndex = 23, Parent = g, OnClick = function()
			Net.request("SetLanguage", { lang = l.code })
		end })
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 24
			end
		end
	end
end

function Panels.init()
	Kit.window("Quests", "📜", "menu.Quests", Theme.Orange, Vector2.new(680, 460), renderQuests)
	Kit.window("Rewards", "🎁", "menu.Rewards", Theme.Green, Vector2.new(720, 470), renderRewards)
	Kit.window("Shop", "🛒", "menu.Shop", Theme.Green, Vector2.new(760, 480), renderShop)
	Kit.window("Auras", "🌀", "menu.Auras", Theme.Purple, Vector2.new(740, 470), renderAuras)
	Kit.window("Wish", "🌠", "menu.Wish", Theme.Yellow, Vector2.new(620, 450), renderWish)
	local ranking = Kit.window("Ranking", "🏆", "menu.Ranking", Theme.Orange, Vector2.new(560, 450), renderRanking)
	local baseOpen = ranking.onOpen
	ranking.onOpen = function()
		baseOpen()
		task.spawn(function()
			local ok, rows = Net.request("GetBoards")
			if ok then
				boardRows = rows
				ranking.refresh()
			end
		end)
	end
	Kit.window("Invite", "💌", "menu.Invite", Theme.Pink, Vector2.new(560, 400), renderInvite)
	Kit.window("Settings", "⚙️", "menu.Settings", Theme.Blue, Vector2.new(580, 460), renderSettings)
	-- timers on the open window tick once a second
	task.spawn(function()
		while true do
			task.wait(1)
			for _, name in { "Rewards", "Quests", "Shop", "Wish" } do
				if Windows.isOpen(name) then
					local box = codeBox
					if not (name == "Rewards" and box and box:IsFocused()) then
						Net.refresh()
					end
				end
			end
		end
	end)
	local _ = GuiService
end

return Panels
