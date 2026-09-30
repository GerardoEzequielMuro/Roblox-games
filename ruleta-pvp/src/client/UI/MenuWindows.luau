--!strict
-- The lobby windows: Play (modes, duels, private tables, watch), Shop, Locker, Rewards,
-- Quests, Ranking, Invite and Settings. Every list is rebuilt from the server snapshot when
-- its window opens or the snapshot changes while it is open.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Audio = require(script.Parent.Parent.Audio)
local TableViews = require(script.Parent.Parent.Arena.TableViews)

local MenuWindows = {}
MenuWindows.onSpectate = nil :: ((string) -> ())?

local player = Players.LocalPlayer
local Z = 22

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Runs a request and toasts the answer.
local function call(action: string, payload: { [string]: any }?, okSound: string?): boolean
	local ok, res = Net.request(action, payload)
	if ok then
		if type(res) == "table" and res.key then
			Toasts.show(Lang.msg(res), "success")
		end
		if okSound then
			Audio.play(okSound, 0.5, 1.3)
		end
	elseif res then
		Toasts.show(Lang.msg(res), "error")
	end
	return ok
end

local function clear(parent: Instance)
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function card(parent: Instance, size: UDim2, order: number, color: Color3?): Frame
	return Theme.new("Frame", { Size = size, BackgroundColor3 = color or Theme.Panel2, LayoutOrder = order, ZIndex = Z, Parent = parent }, { Theme.corner(14) }) :: Frame
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	props.ZIndex = props.ZIndex or Z + 1
	return Theme.text(props)
end

local function button(parent: Instance, opts: Theme.ButtonOpts): TextButton
	opts.Parent = parent
	opts.ZIndex = opts.ZIndex or Z + 1
	local b = Theme.button(opts)
	local gloss = b:FindFirstChild("Gloss") :: GuiObject?
	if gloss then
		gloss.ZIndex = b.ZIndex
	end
	return b
end

local function section(parent: Instance, key: string, order: number): TextLabel
	return label(parent, { Key = key, Title = true, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, TextColor3 = Theme.Yellow, LayoutOrder = order })
end

-- A window whose body is one scrolling column.
local function listWindow(name: string, icon: string, color: Color3, size: Vector2?): (Windows.Window, ScrollingFrame)
	local w = Windows.create(name, icon, "win." .. name, color, size)
	local scroll = Windows.scroller(w.body, UDim2.fromScale(1, 1))
	Theme.list(Enum.FillDirection.Vertical, 8).Parent = scroll
	Theme.new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), Parent = scroll })
	return w, scroll
end

local refreshers: { [string]: () -> () } = {}
local function hook(name: string, w: Windows.Window, fn: () -> ())
	refreshers[name] = fn
	w.onOpen = fn
end

---------------------------------------------------------------------------
-- Play
---------------------------------------------------------------------------
local function buildPlay()
	local w = Windows.create("Play", "▶", "win.Play", Theme.Green, Vector2.new(820, 450))
	local left = Theme.new("Frame", { Name = "Modes", Size = UDim2.new(0.52, -6, 1, 0), BackgroundTransparency = 1, ZIndex = Z, Parent = w.body }, { Theme.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	local right = Windows.scroller(w.body, UDim2.new(0.48, -6, 1, 0), UDim2.new(0.52, 6, 0, 0))
	Theme.list(Enum.FillDirection.Vertical, 8).Parent = right
	Theme.new("UIPadding", { PaddingRight = UDim.new(0, 12), Parent = right })
	local codeBox: TextBox? = nil

	hook("Play", w, function()
		clear(left)
		clear(right)
		local seatedAt = Net.get("table")
		for i, mode in Config.Modes do
			if mode.id ~= "duel" then
				local waiting = 0
				for _, view in TableViews.list do
					if view.kind == "public" and view.mode == mode.id and not view.playing then
						for _ in view.lobbySeats do
							waiting += 1
						end
					end
				end
				local c = card(left, UDim2.new(1, 0, 0, 108), i, Theme.Panel2)
				Theme.new("Frame", { Size = UDim2.new(0, 84, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = rgb(mode.color), ZIndex = Z + 1, Parent = c }, { Theme.corner(12) })
				label(c, { Text = mode.icon, Stroke = false, Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(20, 24), ZIndex = Z + 2 })
				label(c, { Key = "mode." .. mode.id .. ".name", Title = true, Size = UDim2.new(1, -250, 0, 28), Position = UDim2.fromOffset(102, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 26 })
				label(c, { Key = "mode." .. mode.id .. ".desc", Size = UDim2.new(1, -250, 0, 40), Position = UDim2.fromOffset(102, 38), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 15, TextColor3 = Theme.Dim, TextWrapped = true })
				label(c, { Text = "👥 " .. Lang.t("play.waiting", { n = waiting }), Size = UDim2.new(1, -250, 0, 18), Position = UDim2.fromOffset(102, 82), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 14, TextColor3 = if waiting > 0 then Theme.Green else Theme.Dim })
				button(c, { Name = "Play_" .. mode.id, Key = "hud.play", Title = true, Color = Theme.Green, Size = UDim2.fromOffset(130, 60), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 28, OnClick = function()
					task.spawn(function()
						if call("QuickPlay", { mode = mode.id }) then
							Windows.close()
						end
					end)
				end })
			end
		end
		if seatedAt then
			label(left, { Key = "play.already", Size = UDim2.new(1, 0, 0, 22), MaxTextSize = 16, TextColor3 = Theme.Yellow, LayoutOrder = 9 })
		end

		-- duels
		section(right, "play.duel", 1)
		local others = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				others += 1
				local c = card(right, UDim2.new(1, 0, 0, 46), 1 + others)
				label(c, { Text = other.DisplayName, Size = UDim2.new(1, -150, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18 })
				button(c, { Key = "play.challenge", Prefix = "⚔️ ", Icon = "sword", Color = Theme.Orange, Size = UDim2.fromOffset(128, 34), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 16, OnClick = function()
					task.spawn(function()
						if call("Challenge", { userId = other.UserId }) then
							Toasts.show(Lang.t("play.challenge_sent", { name = other.DisplayName }), "info")
						end
					end)
				end })
			end
		end
		if others == 0 then
			label(right, { Key = "play.no_players", Size = UDim2.new(1, 0, 0, 38), MaxTextSize = 15, TextColor3 = Theme.Dim, TextWrapped = true, LayoutOrder = 2 })
		end

		-- private tables
		section(right, "play.private", 20)
		local pc = card(right, UDim2.new(1, 0, 0, 96), 21)
		button(pc, { Name = "CreatePrivate", Key = "play.create", Prefix = "🔒 ", Icon = "lock", Color = Theme.Purple, Size = UDim2.new(1, -16, 0, 38), Position = UDim2.fromOffset(8, 8), TextSize = 18, OnClick = function()
			task.spawn(function()
				local ok, code = Net.request("CreatePrivate", { mode = "classic", fill = true })
				if ok then
					Toasts.show(Lang.t("play.created", { code = tostring(code) }), "success", 5)
					Windows.close()
				elseif code then
					Toasts.show(Lang.msg(code), "error")
				end
			end)
		end })
		local box = Theme.new("TextBox", { Name = "Code", Size = UDim2.new(1, -140, 0, 36), Position = UDim2.fromOffset(8, 52), BackgroundColor3 = Theme.Ink, TextColor3 = Theme.White, PlaceholderColor3 = Theme.Grey, Font = Theme.Font, TextSize = 20, Text = "", ClearTextOnFocus = false, ZIndex = Z + 1, Parent = pc }, { Theme.corner(10) }) :: TextBox
		Lang.bind(box, "play.code_hint", nil, "PlaceholderText")
		codeBox = box
		button(pc, { Name = "JoinPrivate", Key = "play.join", Color = Theme.Blue, Size = UDim2.fromOffset(118, 36), Position = UDim2.new(1, -8, 0, 52), AnchorPoint = Vector2.new(1, 0), TextSize = 17, OnClick = function()
			task.spawn(function()
				if codeBox and call("JoinPrivate", { code = codeBox.Text }) then
					Windows.close()
				end
			end)
		end })

		-- watch
		section(right, "play.watch", 40)
		local live = 0
		for i, view in TableViews.list do
			if view.playing then
				live += 1
				local c = card(right, UDim2.new(1, 0, 0, 46), 40 + i)
				local mode = Config.ModeById[view.mode]
				local alive = 0
				for _, p in view.players do
					if p.alive then
						alive += 1
					end
				end
				label(c, { Text = mode.icon .. " " .. Lang.t("mode." .. view.mode .. ".name") .. "  ·  " .. Lang.t("play.alive", { n = alive }), Size = UDim2.new(1, -130, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16 })
				button(c, { Name = "Watch_" .. view.id, Key = "play.watch_btn", Prefix = "👁 ", Color = Theme.Cyan, Size = UDim2.fromOffset(108, 34), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 16, OnClick = function()
					Windows.close()
					if MenuWindows.onSpectate then
						MenuWindows.onSpectate(view.id)
					end
				end })
			end
		end
		if live == 0 then
			label(right, { Key = "play.no_matches", Size = UDim2.new(1, 0, 0, 24), MaxTextSize = 15, TextColor3 = Theme.Dim, LayoutOrder = 41 })
		end
	end)
end

---------------------------------------------------------------------------
-- Shop (Robux): cosmetics, coins for cosmetics, comfort. Nothing here touches a match.
---------------------------------------------------------------------------
local function buyPass(key: string)
	local pass = Config.PassByKey[key]
	if not pass or pass.id == 0 then
		Toasts.show(Lang.t("toast.coming_soon", { item = Lang.t("pass." .. key .. ".name") }), "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.id)
end
local function buyProduct(key: string)
	local product = Config.ProductByKey[key]
	if not product or product.id == 0 then
		Toasts.show(Lang.t("toast.coming_soon", { item = Lang.t("product." .. key .. ".name") }), "info")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end
MenuWindows.buyPass = buyPass
MenuWindows.buyProduct = buyProduct

local function buildShop()
	local w, scroll = listWindow("Shop", "🛒", Theme.Green, Vector2.new(760, 450))
	hook("Shop", w, function()
		clear(scroll)
		local note = card(scroll, UDim2.new(1, 0, 0, 34), 0, Theme.Panel)
		label(note, { Key = "shop.fair", Prefix = "✅ ", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxTextSize = 15, TextColor3 = Theme.Green })
		local st = Net.get("starter")
		if type(st) == "table" and st.available then
			local c = card(scroll, UDim2.new(1, 0, 0, 96), 1, Theme.Pink:Lerp(Theme.Panel, 0.5))
			label(c, { Text = "🎁", Stroke = false, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(12, 16) })
			label(c, { Key = "product.StarterPack.name", Title = true, Size = UDim2.new(1, -280, 0, 28), Position = UDim2.fromOffset(88, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24 })
			label(c, { Key = "product.StarterPack.desc", Args = { coins = Format.commas(Config.StarterPack.coins) }, Size = UDim2.new(1, -280, 0, 34), Position = UDim2.fromOffset(88, 36), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 15, TextWrapped = true })
			label(c, { Text = "⏳ " .. Format.time(math.max(0, st.endsAt - Net.serverTime())), Size = UDim2.new(1, -280, 0, 18), Position = UDim2.fromOffset(88, 72), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 14, TextColor3 = Theme.Yellow })
			label(c, { Text = "R$ " .. st.fullPrice, Size = UDim2.fromOffset(160, 18), Position = UDim2.new(1, -172, 0, 10), MaxTextSize = 15, TextColor3 = Theme.Dim, RichText = true })
			button(c, { Name = "Buy_StarterPack", Text = "R$ " .. st.price, Title = true, Color = Theme.Purple, Size = UDim2.fromOffset(160, 52), Position = UDim2.new(1, -12, 0, 32), AnchorPoint = Vector2.new(1, 0), TextSize = 26, OnClick = function()
				buyProduct("StarterPack")
			end })
		end
		section(scroll, "shop.passes", 10)
		local grid = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 11, ZIndex = Z, Parent = scroll }) :: Frame
		Theme.new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 92), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, pass in Config.Passes do
			local owned = Net.owns(pass.key)
			local c = card(grid, UDim2.new(), i)
			label(c, { Text = pass.icon, Stroke = false, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(8, 8) })
			label(c, { Key = "pass." .. pass.key .. ".name", Title = true, Size = UDim2.new(1, -170, 0, 24), Position = UDim2.fromOffset(60, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 19 })
			label(c, { Key = "pass." .. pass.key .. ".desc", Size = UDim2.new(1, -170, 0, 52), Position = UDim2.fromOffset(60, 32), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 13, TextColor3 = Theme.Dim, TextWrapped = true })
			button(c, { Name = "Buy_" .. pass.key, Text = if owned then "✔" else "R$ " .. pass.price, Color = if owned then Theme.Grey else Theme.Purple, Size = UDim2.fromOffset(98, 40), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 18, OnClick = function()
				if not Net.owns(pass.key) then
					buyPass(pass.key)
				end
			end })
		end
		section(scroll, "shop.coins", 20)
		local row = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 21, ZIndex = Z, Parent = scroll }) :: Frame
		Theme.new("UIGridLayout", { CellSize = UDim2.new(0.2, -8, 0, 118), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
		local n = 0
		for _, product in Config.Products do
			if product.kind ~= "starter" then
				n += 1
				local c = card(row, UDim2.new(), n)
				label(c, { Text = product.icon, Stroke = false, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 4) })
				label(c, { Key = "product." .. product.key .. ".name", Title = true, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 42), MaxTextSize = 15 })
				label(c, { Text = if product.kind == "coins" then "🪙 " .. Format.commas(product.amount) else Lang.t("product." .. product.key .. ".desc", { n = product.amount }), Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 62), MaxTextSize = 13, TextColor3 = Theme.Yellow, TextWrapped = true })
				local tagKey = if product.key == "CoinsM" then "shop.popular" elseif product.key == "CoinsXL" then "shop.best" else nil
				if tagKey then
					local tag = Theme.new("Frame", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, -9), BackgroundColor3 = if tagKey == "shop.best" then Theme.Red else Theme.Orange, ZIndex = Z + 3, Parent = c }, { Theme.corner(9), Theme.stroke(2) })
					label(tag, { Key = tagKey, Size = UDim2.new(1, -6, 1, -2), Position = UDim2.fromOffset(3, 1), MaxTextSize = 12, ZIndex = Z + 4 })
				end
				button(c, { Name = "Buy_" .. product.key, Text = "R$ " .. product.price, Color = Theme.Purple, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.new(0, 6, 1, -36), TextSize = 16, OnClick = function()
					buyProduct(product.key)
				end })
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Locker
---------------------------------------------------------------------------
local lockerTab = "wheel"
local function unlockText(item: Config.Cosmetic): string
	local u = item.unlock
	if u.type == "coins" then
		return "🪙 " .. Format.commas(u.n or 0)
	elseif u.type == "level" then
		return "🔒 " .. Lang.t("unlock.level", { n = u.n })
	elseif u.type == "wins" then
		return "🔒 " .. Lang.t("unlock.wins", { n = u.n })
	elseif u.type == "streak" then
		return "🔒 " .. Lang.t("unlock.streak", { n = u.n })
	elseif u.type == "league" then
		return "🔒 " .. Lang.t("league." .. tostring(u.key))
	elseif u.type == "pass" then
		return "🔒 " .. Lang.t("pass." .. tostring(u.key) .. ".name")
	end
	return "🔒 " .. Lang.t("unlock." .. u.type)
end

local function buildLocker()
	local w = Windows.create("Locker", "🎨", "win.Locker", Theme.Purple, Vector2.new(800, 450))
	local tabs = Theme.new("Frame", { Name = "Tabs", Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = Z, Parent = w.body }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) }) :: Frame
	local scroll = Windows.scroller(w.body, UDim2.new(1, 0, 1, -48), UDim2.fromOffset(0, 48))
	Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(142, 132), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local ICONS = { wheel = "🎡", table = "🪑", finisher = "💥", emote = "😀", title = "🏷️", aura = "✨" }
	hook("Locker", w, function()
		clear(tabs)
		clear(scroll)
		for i, kind in Config.CosmeticKinds do
			button(tabs, { Name = "Tab_" .. kind, Text = ICONS[kind] .. " " .. Lang.t("locker." .. kind), Color = if kind == lockerTab then Theme.Purple else Theme.Panel2, Size = UDim2.fromOffset(122, 38), TextSize = 15, LayoutOrder = i, OnClick = function()
				lockerTab = kind
				refreshers.Locker()
			end })
		end
		local owned = Net.get("owned") or {}
		local equipped = Net.get("equipped") or {}
		local emotes = Net.get("emotes") or {}
		local n = 0
		for _, item in Config.Cosmetics do
			if item.kind == lockerTab then
				n += 1
				local has = owned[item.id] == true
				local rarity = rgb(Config.RarityById[item.rarity].color)
				local active = if item.kind == "emote" then table.find(emotes, item.id) ~= nil else equipped[item.kind] == item.id
				local c = Theme.new("Frame", { Name = item.id, BackgroundColor3 = Theme.Panel2, LayoutOrder = (if has then 0 else 100) + n, ZIndex = Z, Parent = scroll }, { Theme.corner(14), Theme.stroke(3, if active then Theme.Yellow else rarity:Lerp(Theme.Ink, 0.3)) }) :: Frame
				Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = rarity:Lerp(Theme.Panel, if has then 0.35 else 0.75), BorderSizePixel = 0, ZIndex = Z, Parent = c }, { Theme.corner(14) })
				label(c, { Text = item.icon, Stroke = false, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 7), TextTransparency = if has then 0 else 0.35 })
				label(c, { Text = Lang.t("cos." .. item.id), Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 62), MaxTextSize = 15 })
				label(c, { Text = Lang.t("rarity." .. item.rarity), Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 82), MaxTextSize = 11, TextColor3 = rarity:Lerp(Theme.White, 0.3) })
				if has then
					button(c, { Name = "Use", Text = if active then "✔ " .. Lang.t("locker.equipped") else Lang.t("locker.equip"), Color = if active then Theme.Grey else Theme.Blue, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.new(0, 6, 1, -34), TextSize = 14, OnClick = function()
						task.spawn(function()
							if item.kind == "emote" then
								local list = table.clone(Net.get("emotes") or {})
								local at = table.find(list, item.id)
								if at then
									table.remove(list, at)
								else
									local slots = Net.get("emoteSlots") or Config.EmoteSlots
									while #list >= slots do
										table.remove(list, 1)
									end
									table.insert(list, item.id)
								end
								call("SetEmotes", { ids = list })
							elseif not active then
								call("Equip", { id = item.id }, "card")
							end
						end)
					end })
				elseif item.unlock.type == "coins" then
					button(c, { Name = "Buy", Text = unlockText(item), Color = Theme.Green, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.new(0, 6, 1, -34), TextSize = 15, OnClick = function()
						task.spawn(call, "Buy", { id = item.id }, "heal")
					end })
				else
					local lock = label(c, { Text = unlockText(item), Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -32), MaxTextSize = 13, TextColor3 = Theme.Dim, TextWrapped = true })
					if item.unlock.type == "pass" then
						lock.TextColor3 = Theme.Green
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Rewards: 7-day calendar + session gifts (fixed, shown before claiming)
---------------------------------------------------------------------------
local function rewardText(r: { [string]: any }): string
	if r.kind == "coins" then
		return "🪙 " .. Format.commas(r.amount)
	elseif r.kind == "xp" then
		return "⭐ " .. Format.commas(r.amount)
	elseif r.kind == "item" and r.item then
		local item = Config.CosmeticById[r.item]
		return item.icon .. " " .. Lang.t("cos." .. r.item)
	end
	return "?"
end
MenuWindows.rewardText = rewardText

local function buildRewards()
	local w, scroll = listWindow("Rewards", "🎁", Theme.Pink, Vector2.new(760, 430))
	hook("Rewards", w, function()
		clear(scroll)
		local s = Net.state
		if not s then
			return
		end
		section(scroll, "rewards.daily", 1)
		local daily = s.dailyState or { canClaim = false, day = 1, streak = 0 }
		local row = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1, LayoutOrder = 2, ZIndex = Z, Parent = scroll }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) }) :: Frame
		for i, r in Config.DailyRewards do
			local done = if daily.canClaim then i < daily.day else i <= daily.day
			local today = daily.canClaim and i == daily.day
			local c = Theme.new("Frame", { Name = "Day" .. i, Size = UDim2.fromOffset(95, 104), BackgroundColor3 = if today then Theme.Pink:Lerp(Theme.Panel, 0.3) else Theme.Panel2, LayoutOrder = i, ZIndex = Z, Parent = row }, { Theme.corner(12), Theme.stroke(3, if today then Theme.Yellow else Theme.Ink) })
			label(c, { Text = Lang.t("rewards.day", { n = i }), Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 4), MaxTextSize = 14, TextColor3 = Theme.Dim })
			label(c, { Text = if done then "✅" else rewardText(r), Size = UDim2.new(1, -8, 0, 46), Position = UDim2.fromOffset(4, 26), MaxTextSize = 20, TextWrapped = true })
			if today then
				button(c, { Name = "ClaimDaily", Key = "rewards.claim", Color = Theme.Green, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -30), TextSize = 14, OnClick = function()
					task.spawn(call, "ClaimDaily", nil, "heal")
				end })
			end
		end
		section(scroll, "rewards.gifts", 3)
		local grow = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, LayoutOrder = 4, ZIndex = Z, Parent = scroll }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) }) :: Frame
		local elapsed = s.sessionElapsed + (os.clock() - Net.receivedAt)
		for i, g in Config.Gifts do
			local claimed = table.find(s.giftsClaimed, i) ~= nil
			local ready = elapsed >= g.minutes * 60
			local c = Theme.new("Frame", { Name = "Gift" .. i, Size = UDim2.fromOffset(112, 96), BackgroundColor3 = if ready and not claimed then Theme.Green:Lerp(Theme.Panel, 0.45) else Theme.Panel2, LayoutOrder = i, ZIndex = Z, Parent = grow }, { Theme.corner(12), Theme.stroke(3) })
			label(c, { Text = if claimed then "✅" else "🎁", Stroke = false, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 4) })
			label(c, { Text = rewardText(g.reward), Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 36), MaxTextSize = 15, TextColor3 = Theme.Yellow })
			if claimed then
				label(c, { Key = "rewards.claimed", Size = UDim2.new(1, -6, 0, 22), Position = UDim2.new(0, 3, 1, -26), MaxTextSize = 13, TextColor3 = Theme.Dim })
			elseif ready then
				button(c, { Name = "ClaimGift" .. i, Key = "rewards.claim", Color = Theme.Green, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -30), TextSize = 14, OnClick = function()
					task.spawn(call, "ClaimGift", { index = i }, "heal")
				end })
			else
				label(c, { Text = "⏳ " .. Format.time(g.minutes * 60 - elapsed), Size = UDim2.new(1, -6, 0, 22), Position = UDim2.new(0, 3, 1, -26), MaxTextSize = 13, TextColor3 = Theme.Dim })
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local function buildQuests()
	local w, scroll = listWindow("Quests", "📜", Theme.Orange, Vector2.new(640, 400))
	hook("Quests", w, function()
		clear(scroll)
		local q = Net.get("quests")
		if type(q) ~= "table" then
			return
		end
		label(scroll, { Text = "⏳ " .. Lang.t("quests.resets", { time = Format.time(math.max(0, q.resetsAt - Net.serverTime())) }), Size = UDim2.new(1, 0, 0, 20), MaxTextSize = 15, TextColor3 = Theme.Dim, LayoutOrder = 0 })
		local allClaimed = true
		for i, quest in q.list do
			local progress = q.progress[i] or 0
			local done = progress >= quest.target
			local claimed = q.claimed[i] == true
			allClaimed = allClaimed and claimed
			local c = card(scroll, UDim2.new(1, 0, 0, 72), i)
			label(c, { Text = Lang.t("quest." .. quest.kind, { n = quest.target }), Size = UDim2.new(1, -170, 0, 24), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 19 })
			local back = Theme.new("Frame", { Size = UDim2.new(1, -170, 0, 16), Position = UDim2.fromOffset(12, 38), BackgroundColor3 = Theme.Ink, ZIndex = Z + 1, Parent = c }, { Theme.corner(8) })
			Theme.new("Frame", { Size = UDim2.fromScale(math.clamp(progress / quest.target, 0, 1), 1), BackgroundColor3 = if done then Theme.Green else Theme.Orange, ZIndex = Z + 2, Parent = back }, { Theme.corner(8) })
			label(back, { Text = math.min(progress, quest.target) .. "/" .. quest.target, MaxTextSize = 12, ZIndex = Z + 3 })
			label(c, { Text = "🪙 " .. quest.coins .. "   ⭐ " .. quest.xp, Size = UDim2.fromOffset(150, 18), Position = UDim2.new(1, -158, 0, 6), MaxTextSize = 14, TextColor3 = Theme.Yellow })
			button(c, { Name = "ClaimQuest" .. i, Text = if claimed then "✔" else Lang.t("rewards.claim"), Color = if claimed or not done then Theme.Grey else Theme.Green, Size = UDim2.fromOffset(140, 34), Position = UDim2.new(1, -12, 1, -42), AnchorPoint = Vector2.new(1, 0), TextSize = 16, OnClick = function()
				if done and not claimed then
					task.spawn(call, "ClaimQuest", { index = i }, "heal")
				end
			end })
		end
		local b = card(scroll, UDim2.new(1, 0, 0, 56), 10, Theme.Orange:Lerp(Theme.Panel, 0.6))
		label(b, { Text = "🎯 " .. Lang.t("quests.bonus") .. "   🪙 " .. q.bonus.coins .. "  ⭐ " .. q.bonus.xp, Size = UDim2.new(1, -170, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17 })
		button(b, { Name = "ClaimBonus", Text = if q.bonusClaimed then "✔" else Lang.t("rewards.claim"), Color = if allClaimed and not q.bonusClaimed then Theme.Green else Theme.Grey, Size = UDim2.fromOffset(140, 36), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 16, OnClick = function()
			if allClaimed and not q.bonusClaimed then
				task.spawn(call, "ClaimQuestBonus", nil, "heal")
			end
		end })
	end)
end

---------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------
local boardTab = "season"
MenuWindows.boards = nil :: { [string]: any }?
local function buildRanking()
	local w = Windows.create("Ranking", "🏆", "win.Ranking", Theme.Yellow, Vector2.new(700, 440))
	local head = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = Theme.Panel2, ZIndex = Z, Parent = w.body }, { Theme.corner(14) }) :: Frame
	local tabs = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 86), BackgroundTransparency = 1, ZIndex = Z, Parent = w.body }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) }) :: Frame
	local scroll = Windows.scroller(w.body, UDim2.new(1, 0, 1, -132), UDim2.fromOffset(0, 132))
	Theme.list(Enum.FillDirection.Vertical, 4).Parent = scroll
	local function render()
		clear(head)
		clear(tabs)
		clear(scroll)
		local s = Net.state
		if not s then
			return
		end
		local icon = ""
		for _, l in Config.Leagues do
			if l.id == s.league then
				icon = l.icon
			end
		end
		label(head, { Text = icon, Stroke = false, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 11) })
		label(head, { Text = Lang.t("league." .. s.league) .. "  ·  🏆 " .. s.trophies, Title = true, Size = UDim2.new(1, -260, 0, 26), Position = UDim2.fromOffset(74, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22 })
		local nextL = s.nextLeague
		local back = Theme.new("Frame", { Size = UDim2.new(1, -260, 0, 14), Position = UDim2.fromOffset(74, 40), BackgroundColor3 = Theme.Ink, ZIndex = Z + 1, Parent = head }, { Theme.corner(7) })
		local frac = 1
		if nextL then
			local cur = 0
			for _, l in Config.Leagues do
				if l.id == s.league then
					cur = l.trophies
				end
			end
			frac = math.clamp((s.trophies - cur) / math.max(1, nextL.trophies - cur), 0, 1)
		end
		Theme.new("Frame", { Size = UDim2.fromScale(frac, 1), BackgroundColor3 = Theme.Pink, ZIndex = Z + 2, Parent = back }, { Theme.corner(7) })
		label(head, { Text = if nextL then Lang.t("rank.next", { league = Lang.t("league." .. nextL.id), n = nextL.trophies }) else Lang.t("rank.top"), Size = UDim2.new(1, -260, 0, 16), Position = UDim2.fromOffset(74, 57), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 13, TextColor3 = Theme.Dim })
		label(head, { Text = "⏳ " .. Lang.t("rank.season_ends", { time = Format.time(math.max(0, s.seasonEndsAt - Net.serverTime())) }), Size = UDim2.fromOffset(176, 18), Position = UDim2.new(1, -184, 0, 10), MaxTextSize = 13, TextColor3 = Theme.Yellow })
		label(head, { Text = "🏅 " .. Lang.t("rank.record", { wins = s.wins, matches = s.matches, streak = s.bestStreak }), Size = UDim2.fromOffset(176, 36), Position = UDim2.new(1, -184, 0, 32), MaxTextSize = 13, TextColor3 = Theme.Dim, TextWrapped = true })
		for i, kind in { "season", "wins", "weekly" } do
			button(tabs, { Name = "Board_" .. kind, Key = "rank." .. kind, Color = if kind == boardTab then Theme.Yellow else Theme.Panel2, Size = UDim2.fromOffset(180, 36), TextSize = 16, LayoutOrder = i, OnClick = function()
				boardTab = kind
				render()
			end })
		end
		local data = MenuWindows.boards
		local rows = if data then data.rows[boardTab] else nil
		if not rows or #rows == 0 then
			label(scroll, { Key = "rank.empty", Size = UDim2.new(1, 0, 0, 40), MaxTextSize = 17, TextColor3 = Theme.Dim })
			return
		end
		local medals = { "🥇", "🥈", "🥉" }
		for i, r in rows do
			local c = card(scroll, UDim2.new(1, -12, 0, 34), i, if r.userId == player.UserId then Theme.Yellow:Lerp(Theme.Panel, 0.65) else Theme.Panel2)
			label(c, { Text = medals[i] or ("#" .. i), Size = UDim2.fromOffset(44, 26), Position = UDim2.fromOffset(6, 4), MaxTextSize = 20 })
			label(c, { Text = r.name, Size = UDim2.new(1, -190, 1, -8), Position = UDim2.fromOffset(56, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18 })
			label(c, { Text = Format.commas(r.value), Title = true, Size = UDim2.fromOffset(120, 26), Position = UDim2.new(1, -128, 0, 4), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 20, TextColor3 = Theme.Yellow })
		end
	end
	hook("Ranking", w, function()
		render()
		task.spawn(function()
			local ok, data = Net.request("GetBoards")
			if ok and type(data) == "table" then
				MenuWindows.boards = data
				if Windows.isOpen("Ranking") then
					render()
				end
			end
		end)
	end)
	refreshers.Ranking = render
end

---------------------------------------------------------------------------
-- Invite (friends, share link, group, codes)
---------------------------------------------------------------------------
local function buildInvite()
	local w, scroll = listWindow("Invite", "🤝", Theme.Cyan, Vector2.new(620, 420))
	local codeBox: TextBox? = nil
	hook("Invite", w, function()
		clear(scroll)
		local social = Net.get("social") or {}
		local c = card(scroll, UDim2.new(1, 0, 0, 104), 1)
		label(c, { Key = "invite.title", Title = true, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20 })
		label(c, { Key = "invite.desc", Args = { you = Config.Referral.inviterCoins, friend = Config.Referral.invitedCoins }, Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 30), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 14, TextColor3 = Theme.Dim, TextWrapped = true })
		button(c, { Name = "InviteFriends", Key = "invite.friends", Prefix = "👥 ", Icon = "group", Color = Theme.Green, Size = UDim2.new(0.5, -14, 0, 34), Position = UDim2.new(0, 10, 1, -40), TextSize = 16, OnClick = function()
			task.spawn(function()
				local ok = pcall(function()
					local options = Instance.new("ExperienceInviteOptions")
					options.InviteMessageId = ""
					options.LaunchData = Referral.launchData(player.UserId)
					SocialService:PromptGameInvite(player, options)
				end)
				if not ok then
					Toasts.show(Lang.t("msg.share_unavailable"), "error")
				end
			end)
		end })
		button(c, { Name = "ShareLink", Key = "invite.share", Prefix = "🔗 ", Color = Theme.Blue, Size = UDim2.new(0.5, -14, 0, 34), Position = UDim2.new(0.5, 4, 1, -40), TextSize = 16, OnClick = function()
			task.spawn(call, "ShareLink")
		end })
		label(scroll, { Text = "🎉 " .. Lang.t("invite.count", { n = social.referralRewards or 0, max = Config.Referral.maxRewards }), Size = UDim2.new(1, 0, 0, 20), MaxTextSize = 15, TextColor3 = Theme.Dim, LayoutOrder = 2 })
		if social.group then
			local g = card(scroll, UDim2.new(1, 0, 0, 52), 3)
			label(g, { Key = "invite.group", Args = { n = Config.GroupGift.coins }, Size = UDim2.new(1, -170, 1, -12), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, TextWrapped = true })
			button(g, { Name = "GroupGift", Text = if social.groupGiftClaimed then "✔" else Lang.t("rewards.claim"), Color = if social.groupGiftClaimed then Theme.Grey else Theme.Green, Size = UDim2.fromOffset(140, 36), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 16, OnClick = function()
				task.spawn(call, "ClaimGroupGift", nil, "heal")
			end })
		end
		section(scroll, "invite.codes", 4)
		local k = card(scroll, UDim2.new(1, 0, 0, 52), 5)
		local box = Theme.new("TextBox", { Name = "CodeBox", Size = UDim2.new(1, -170, 0, 36), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = Theme.Ink, TextColor3 = Theme.White, PlaceholderColor3 = Theme.Grey, Font = Theme.Font, TextSize = 20, Text = "", ClearTextOnFocus = false, ZIndex = Z + 1, Parent = k }, { Theme.corner(10) }) :: TextBox
		Lang.bind(box, "invite.code_hint", nil, "PlaceholderText")
		codeBox = box
		button(k, { Name = "Redeem", Key = "invite.redeem", Color = Theme.Green, Size = UDim2.fromOffset(146, 36), Position = UDim2.new(1, -8, 0, 8), AnchorPoint = Vector2.new(1, 0), TextSize = 17, OnClick = function()
			task.spawn(function()
				if codeBox and call("RedeemCode", { code = codeBox.Text }, "heal") then
					codeBox.Text = ""
				end
			end)
		end })
	end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function buildSettings()
	local w, scroll = listWindow("Settings", "⚙️", Theme.Grey, Vector2.new(620, 440))
	local function set(key: string, value: any)
		task.spawn(call, "SetSetting", { key = key, value = value })
	end
	hook("Settings", w, function()
		clear(scroll)
		local s = Net.get("settings") or {}
		local order = 0
		for _, key in { "music", "sfx" } do
			order += 1
			local c = card(scroll, UDim2.new(1, 0, 0, 44), order)
			label(c, { Key = "set." .. key, Size = UDim2.new(1, -230, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20 })
			local v = math.floor((s[key] or 0.5) * 10 + 0.5)
			label(c, { Text = string.rep("▮", v) .. string.rep("▯", 10 - v), Size = UDim2.fromOffset(120, 24), Position = UDim2.new(1, -176, 0.5, -12), MaxTextSize = 16, TextColor3 = Theme.Cyan })
			button(c, { Name = key .. "Down", Text = "−", Color = Theme.Blue, Size = UDim2.fromOffset(36, 34), Position = UDim2.new(1, -218, 0.5, -17), TextSize = 22, OnClick = function()
				set(key, math.max(0, (v - 1) / 10))
			end })
			button(c, { Name = key .. "Up", Text = "+", Color = Theme.Blue, Size = UDim2.fromOffset(36, 34), Position = UDim2.new(1, -44, 0.5, -17), TextSize = 22, OnClick = function()
				set(key, math.min(1, (v + 1) / 10))
			end })
		end
		for _, key in { "shake", "flashes", "lite", "autoQueue", "autoPlay", "autoCharge" } do
			order += 1
			local row = Theme.toggle({
				Name = "Toggle_" .. key,
				Key = "set." .. key,
				LayoutOrder = order,
				Parent = scroll,
				Get = function()
					local cur = Net.get("settings") or {}
					return cur[key] == true
				end,
				Set = function(value)
					set(key, value)
				end,
			})
			row.ZIndex = Z
			for _, d in row:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = Z + 1
				end
			end
		end
		section(scroll, "set.language", 20)
		local grid = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 21, ZIndex = Z, Parent = scroll }) :: Frame
		Theme.new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 38), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, l in Locale.Languages do
			button(grid, { Name = "Lang_" .. l.code, Text = l.name, Color = if Lang.code == l.code then Theme.Green else Theme.Panel2, TextSize = 15, LayoutOrder = i, OnClick = function()
				task.spawn(function()
					if call("SetLanguage", { lang = l.code }) then
						Lang.set(l.code)
						Toasts.show(Lang.t("toast.language", { name = l.name }), "info")
					end
				end)
			end })
		end
	end)
end

function MenuWindows.init()
	buildPlay()
	buildShop()
	buildLocker()
	buildRewards()
	buildQuests()
	buildRanking()
	buildInvite()
	buildSettings()
	-- keep the open window fresh (never while typing, and the Play list at most once a second)
	local UserInputService = game:GetService("UserInputService")
	Net.Changed:Connect(function()
		local cur = Windows.current()
		local fn = if cur then refreshers[cur] else nil
		if fn and UserInputService:GetFocusedTextBox() == nil then
			fn()
		end
	end)
	local lastPlay = 0
	TableViews.Changed:Connect(function()
		if Windows.isOpen("Play") and os.clock() - lastPlay > 1 and UserInputService:GetFocusedTextBox() == nil then
			lastPlay = os.clock()
			refreshers.Play()
		end
	end)
end

return MenuWindows
