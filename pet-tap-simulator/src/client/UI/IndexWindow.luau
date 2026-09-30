--!strict
-- Index / collection book: % discovered overall and per zone, silhouettes for unknown
-- pets, and a claimable reward for completing each zone's page.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local PetIcon = require(script.Parent.PetIcon)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local IndexWindow = {}

-- page 1..5 = zones, 6 = exclusive & secret
local function petsOnPage(page: number): { typeof(Config.Pets[1]) }
	local list = {}
	for _, p in Config.Pets do
		if (page <= #Config.Zones and p.zone == page) or (page > #Config.Zones and p.zone == 0) then
			table.insert(list, p)
		end
	end
	return list
end

function IndexWindow.init()
	local w = Windows.create("Index", "📖", "win.index", Theme.Blue, Vector2.new(820, 540), 450)
	local body = w.body
	local page = 1

	local tabs = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = body }, { Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) })
	local total = Theme.text({ Text = "", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 60), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 24, Parent = body })
	local grid = Theme.new("Frame", { BackgroundColor3 = Theme.PaperDark, Size = UDim2.new(1, 0, 1, -158), Position = UDim2.fromOffset(0, 92), Parent = body }, {
		Theme.corner(14),
		Theme.padding(10),
		Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(106, 120), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	local claim = Theme.button({
		Text = "",
		Color = Theme.Green,
		Size = UDim2.fromOffset(460, 56),
		Position = UDim2.new(0.5, 0, 1, -2),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 24,
		Parent = body,
		OnClick = function()
			local ok, res = Net.request("ClaimIndex", { zone = page })
			Toasts.show(Lang.msg(res), if ok then "success" else "error")
		end,
	})

	local tabButtons: { TextButton } = {}
	local refresh: () -> ()
	local names = {}
	for _, z in Config.Zones do
		table.insert(names, "zone." .. z.id)
	end
	table.insert(names, "index.special")
	for i, key in names do
		tabButtons[i] = Theme.button({
			Key = key,
			Color = Theme.Grey,
			Size = UDim2.fromOffset(if Root.isTouch then 116 else 124, 56),
			LayoutOrder = i,
			TextSize = 18,
			Parent = tabs,
			OnClick = function()
				page = i
				refresh()
			end,
		})
	end

	local builtKey = ""
	refresh = function()
		local s = Net.state
		if not s then
			return
		end
		local discovered = s.discovered
		-- overall %
		local have, all = 0, 0
		for _, p in Config.Pets do
			if p.rarity ~= "Secret" then
				all += 1
				if discovered[p.id] then
					have += 1
				end
			end
		end
		total.Text = Lang.t("index.total", { have = have, all = all, pct = math.floor(have / all * 100), bonus = math.floor(Config.IndexTapBonus * 100) })
		for i, b in tabButtons do
			local zone = Config.Zones[i]
			Theme.setButton(b, nil, if i == page then (if zone then Palette.rgb(zone.ground) else Theme.Purple) else Theme.Grey)
		end
		-- rebuild grid only when page/discoveries change
		local list = petsOnPage(page)
		local keyParts = { tostring(page), Lang.code }
		for _, p in list do
			table.insert(keyParts, if discovered[p.id] then "1" else "0")
		end
		local key = table.concat(keyParts)
		if key ~= builtKey then
			builtKey = key
			for _, c in grid:GetChildren() do
				if c:IsA("Frame") then
					c:Destroy()
				end
			end
			for i, p in list do
				local known = discovered[p.id] == true
				local rc = if p.rarity == "Secret" then Color3.fromRGB(90, 50, 130) else Palette.rarity(p.rarity)
				local cell = Theme.new("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), Parent = grid }, {
					Theme.corner(14),
					Theme.stroke(3),
					Theme.gradient(Theme.lighten(rc, 0.55), if known then Theme.darken(rc, 0.05) else Theme.Grey),
				})
				Theme.gloss(cell, 14, 0.7)
				local icon = PetIcon.new(p.id, 0, not known)
				icon.Size = UDim2.new(1, -6, 1, -32)
				icon.Position = UDim2.fromOffset(3, 1)
				icon.Parent = cell
				local plate = Theme.new("Frame", { Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -30), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = cell }, { Theme.corner(9) })
				Theme.text({ Text = if known then Lang.pet(p.id) else Lang.t("egg.unknown"), Size = UDim2.new(1, -6, 1, -2), Position = UDim2.fromOffset(3, 1), MaxTextSize = 18, Parent = plate })
			end
		end
		-- claim button
		if page <= #Config.Zones then
			claim.Visible = true
			local done = true
			for _, p in list do
				if not discovered[p.id] then
					done = false
				end
			end
			if s.indexClaimed[tostring(page)] then
				Theme.setButton(claim, "✓ " .. Lang.t("index.claimed"), Theme.Grey)
			elseif done then
				Theme.setButton(claim, Lang.t("index.claim", { gems = Config.IndexRewardGems[page] or 0, bonus = math.floor(Config.IndexTapBonus * 100) }), Theme.Green)
			else
				Theme.setButton(claim, Lang.t("index.find", { gems = Config.IndexRewardGems[page] or 0, bonus = math.floor(Config.IndexTapBonus * 100) }), Theme.Grey)
			end
		else
			claim.Visible = false
		end
	end
	w.onOpen = refresh
	Net.Changed:Connect(function(kind)
		if kind == "full" and Windows.isOpen("Index") then
			refresh()
		end
	end)
end

return IndexWindow
