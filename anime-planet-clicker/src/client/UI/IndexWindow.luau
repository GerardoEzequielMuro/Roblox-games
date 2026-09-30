--!strict
-- The Index: every pet by galaxy (silhouettes and "???" until found, with its capsule
-- chance; finishing a galaxy's page pays Crystals and a permanent damage bonus) and the
-- planet Mastery page (planets broken per type -> permanent bonuses).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local PetIcon = require(script.Parent.PetIcon)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local IndexWindow = {}

local STAT_ICON = { damage = "💥", speed = "💨", luck = "🍀", stardust = "✨", crystals = "💎" }

-- Base chance of a pet in its capsule (luck 1), for the index cards.
local function baseChance(petId: string): number?
	for _, cap in Config.Capsules do
		for _, o in Formulas.odds(cap.id, 1) do
			if o.id == petId then
				return o.chance
			end
		end
	end
	return nil
end

local function petCell(parent: Instance, pet: any, known: boolean, order: number)
	local color = Palette.rarity(pet.rarity)
	local cell = Theme.new("Frame", { Name = "Pet_" .. pet.id, Size = UDim2.fromOffset(104, 122), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Parent = parent }, {
		Theme.corner(10), Theme.stroke(3), Theme.gradient(if known then Theme.lighten(color, 0.25) else Color3.fromRGB(70, 74, 100), if known then Theme.darken(color, 0.5) else Color3.fromRGB(30, 32, 52)),
	})
	local vp = PetIcon.new(pet.id, 0, not known)
	vp.Size = UDim2.new(1, -6, 0, 70)
	vp.Position = UDim2.fromOffset(3, 3)
	vp.Parent = cell
	Theme.text({ Text = if known then Lang.pet(pet.id) else "???", Size = UDim2.new(1, -6, 0, 22), Position = UDim2.fromOffset(3, 72), MaxTextSize = 14, TextWrapped = true, Parent = cell })
	local chance = baseChance(pet.id)
	Theme.text({ Text = Lang.rarity(pet.rarity) .. (if chance then ("  " .. Format.percent(chance)) else ""), TextColor3 = Theme.lighten(color, 0.5), Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 98), MaxTextSize = 13, Parent = cell })
end

local function petsTab(content: Frame, s: { [string]: any })
	local list = Kit.scroll(content, UDim2.fromScale(1, 1), nil, 8)
	local found, total = 0, 0
	for _, pet in Config.Pets do
		total += 1
		if s.discovered[pet.id] then
			found += 1
		end
	end
	Theme.text({ Text = Lang.t("index.found", { n = found, max = total, pct = math.floor(found / total * 100) }), Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 0, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, TextColor3 = Theme.Yellow, Parent = list })
	for zone = 1, #Config.Zones + 1 do -- the last section holds the exclusives
		local pets = {}
		for _, pet in Config.Pets do
			if (zone <= #Config.Zones and pet.zone == zone) or (zone > #Config.Zones and pet.zone == 0) then
				table.insert(pets, pet)
			end
		end
		local have = 0
		for _, pet in pets do
			if s.discovered[pet.id] then
				have += 1
			end
		end
		local section = Theme.new("Frame", { Name = "Section" .. zone, Size = UDim2.new(1, -8, 0, 172), BackgroundColor3 = Theme.Paper, LayoutOrder = zone, Parent = list }, { Theme.corner(12), Theme.stroke(2) })
		local title = if zone <= #Config.Zones then Lang.zone(zone) else Lang.t("index.exclusive")
		Theme.text({ Text = title .. "   " .. have .. "/" .. #pets, Size = UDim2.new(1, -230, 0, 28), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = section })
		if zone <= #Config.Zones then
			local claimed = s.indexClaimed[tostring(zone)] == true
			local complete = have == #pets
			Theme.button({ Name = "Claim", Text = if claimed then ("✔ +" .. math.floor(Config.IndexBoostPerZone * 100) .. "% 💥") else ("+" .. Config.IndexRewardCrystals[zone] .. " 💎  +" .. math.floor(Config.IndexBoostPerZone * 100) .. "% 💥"), Color = if claimed then Theme.Grey elseif complete then Theme.Green else Theme.darken(Theme.Blue, 0.4), Size = UDim2.fromOffset(210, 32), Position = UDim2.new(1, -220, 0, 5), TextSize = 17, Parent = section, OnClick = function()
				if not claimed then
					Kit.request("ClaimIndex", { zone = zone })
				end
			end })
		end
		local row = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 124), Position = UDim2.fromOffset(8, 40), Parent = section }, {
			Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		})
		for i, pet in pets do
			petCell(row, pet, s.discovered[pet.id] == true, i)
		end
	end
end

local function planetsTab(content: Frame, s: { [string]: any })
	local list = Kit.scroll(content, UDim2.fromScale(1, 1), nil, 6)
	local bonus = Formulas.masteryBonus(s.mastery)
	local parts = {}
	for _, stat in Config.RelicStats do
		table.insert(parts, STAT_ICON[stat] .. " +" .. math.floor((bonus :: any)[stat] * 100 + 0.5) .. "%")
	end
	Theme.text({ Text = Lang.t("index.mastery_total") .. "   " .. table.concat(parts, "   "), Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 0, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 19, TextColor3 = Theme.Yellow, Parent = list })
	for i, kindId in Config.MasteryKinds do
		local kind = Config.PlanetKindById[kindId]
		local count = s.mastery[kindId] or 0
		local level = Formulas.masteryLevel(count)
		local color = Palette.rgb(kind.color)
		local row = Kit.row(list, 72, color, i)
		row.Name = "Mastery_" .. kindId
		local tile = Theme.new("Frame", { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = Theme.PaperDark, Parent = row }, { Theme.corner(10), Theme.stroke(2) })
		PetIcon.planet(kindId, s.maxZone, count == 0).Parent = tile
		Theme.text({ Text = Lang.planet(kindId) .. "  ·  " .. Lang.t("index.mastery_level", { n = level }), Size = UDim2.new(1, -300, 0, 24), Position = UDim2.fromOffset(74, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 21, Parent = row })
		local buffText = if kind.buff and kind.buff ~= "random" and kind.buff ~= "all" then ("⚡ " .. Lang.t("buff." .. kind.buff) .. "   ") else ""
		Theme.text({ Text = buffText .. STAT_ICON[kind.perm] .. " +" .. math.floor(level * Config.MasteryBonus * 100 + 0.5) .. "% " .. Lang.t("stat." .. kind.perm), Size = UDim2.new(1, -300, 0, 20), Position = UDim2.fromOffset(74, 32), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17, TextColor3 = Color3.fromRGB(255, 240, 170), Parent = row })
		local nextAt = Config.MasteryThresholds[level + 1]
		local bar = Theme.bar(row, UDim2.fromOffset(210, 28), Theme.Green)
		bar.frame.Position = UDim2.new(1, -220, 0.5, -14)
		if nextAt then
			bar:set(count / nextAt, Format.commas(count) .. " / " .. Format.commas(nextAt))
		else
			bar:set(1, Lang.t("upgrades.max"))
		end
	end
end

function IndexWindow.init()
	local w = Windows.create("Index", "📖", "win.index", Theme.Blue, Vector2.new(780, 490))
	local content = Theme.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = w.body }) :: Frame
	local tabs: Kit.Tabs
	local function render()
		local s = Net.state
		if not s or not Windows.isOpen("Index") then
			return
		end
		Kit.clear(content)
		if tabs.current() == "planets" then
			planetsTab(content, s)
		else
			petsTab(content, s)
		end
	end
	tabs = Kit.tabs(w.body, UDim2.fromOffset(420, 40), UDim2.fromOffset(0, 0), { { "pets", "🐾", Theme.Pink }, { "planets", "🪐", Theme.Orange } }, function()
		render()
	end)
	local function names()
		Theme.setButton(tabs.buttons.pets, "🐾 " .. Lang.t("index.tab_pets"))
		Theme.setButton(tabs.buttons.planets, "🪐 " .. Lang.t("index.tab_planets"))
	end
	w.onOpen = function()
		names()
		if tabs.current() == "" then
			tabs.select("pets")
		else
			render()
		end
	end
	local lastKey = ""
	Net.Changed:Connect(function(kind)
		local s = Net.state
		if kind == "full" and s and Windows.isOpen("Index") then
			-- only rebuild when the index itself changed (viewports are not free)
			local n = 0
			for _ in s.discovered do
				n += 1
			end
			local m = 0
			for _, c in s.mastery do
				m += c
			end
			local c = 0
			for _ in s.indexClaimed do
				c += 1
			end
			local key = n .. ":" .. m .. ":" .. c .. ":" .. Lang.code
			if key ~= lastKey then
				lastKey = key
				names()
				render()
			end
		end
	end)
end

return IndexWindow
