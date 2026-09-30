--!strict
-- The Shop: Starter Pack offer on top (while it lasts), passes as 2-per-row cards with a
-- one-line benefit, then repeatable products. Robux prices are purple. Anything Roblox
-- counts as a paid random item is left out for players where those are restricted.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)

local StoreWindow = {}

local PASS_COLORS = {
	AutoMiner = Theme.Blue, DoubleDamage = Theme.Red, DoubleStardust = Theme.Yellow, VIP = Theme.Orange, InstantSell = Theme.Teal,
	PetSlots = Theme.Pink, TripleOpen = Theme.Purple, FastOpen = Theme.Blue, Sprint = Theme.Green, Lucky = Theme.Green,
	SuperLucky = Theme.Purple, GoldenCapsules = Theme.Yellow, PetSlots2 = Theme.Pink, OpenEight = Theme.Purple,
}

local function card(parent: Instance, order: number, icon: string, color: Color3, name: string, desc: string, priceText: string, owned: boolean, live: boolean, onClick: () -> ()): Frame
	local f = Theme.new("Frame", { Name = "Card", BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Parent = parent }, {
		Theme.corner(12), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.05), Theme.darken(color, 0.45)),
	}) :: Frame
	local tile = Theme.icon(f, icon, color, 60)
	tile.Position = UDim2.fromOffset(8, 8)
	Theme.text({ Text = name, Size = UDim2.new(1, -84, 0, 26), Position = UDim2.fromOffset(76, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = f })
	Theme.text({ Text = desc, TextWrapped = true, Size = UDim2.new(1, -84, 0, 36), Position = UDim2.fromOffset(76, 32), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 16, TextColor3 = Color3.fromRGB(235, 240, 250), Parent = f })
	Theme.button({ Name = "Buy", Text = if owned then ("✔ " .. Lang.t("store.owned")) elseif live then priceText else Lang.t("store.soon"), Color = if owned then Theme.Green elseif live then Theme.Robux else Theme.Grey, Size = UDim2.new(1, -16, 0, 36), Position = UDim2.new(0, 8, 1, -44), TextSize = 20, Parent = f, OnClick = function()
		if not owned then
			onClick()
		end
	end })
	return f
end

function StoreWindow.init()
	local w = Windows.create("Store", "🛒", "win.store", Theme.Green, Vector2.new(780, 490))
	local grid = Kit.grid(w.body, UDim2.fromScale(1, 1), nil, Vector2.new(362, 122), 8)
	local function render()
		local s = Net.state
		if not s or not Windows.isOpen("Store") then
			return
		end
		Kit.clear(grid)
		local order = 0
		local st = s.starter
		if st and st.available then
			order += 1
			local c = card(grid, order, "🎁", Theme.Orange, Lang.t("product.StarterPack.name") .. "  -" .. math.floor((1 - st.price / st.fullPrice) * 100 + 0.5) .. "%", Lang.t("product.StarterPack.desc", { crystals = Config.StarterPack.crystals, minutes = Config.StarterPack.boostMinutes, pet = Lang.pet(Config.StarterPack.pet) }), "R$ " .. st.price, false, true, function()
				Hud.onStarterClick()
			end)
			c.Name = "StarterCard"
		end
		for _, pass in Config.Passes do
			if Purchase.allowed(pass) then
				order += 1
				local c = card(grid, order, pass.icon, PASS_COLORS[pass.key] or Theme.Blue, Lang.t("pass." .. pass.key .. ".name"), Lang.t("pass." .. pass.key .. ".desc"), "R$ " .. pass.price, Net.owns(pass.key), Purchase.passAvailable(pass.key), function()
					Purchase.pass(pass.key)
				end)
				c.Name = "Pass_" .. pass.key
			end
		end
		for _, product in Config.Products do
			if not product.hidden and Purchase.allowed(product) then
				order += 1
				local desc = Lang.t("product." .. product.key .. ".desc", { n = product.amount, value = Format.abbrev(s.income * 60 * product.amount) })
				local c = card(grid, order, product.icon, if product.kind == "crystals" then Theme.Crystals elseif product.kind == "capsule" then Theme.Purple elseif product.kind == "luck" then Theme.Green else Theme.Yellow, Lang.t("product." .. product.key .. ".name"), desc, "R$ " .. product.price, false, Purchase.productAvailable(product.key), function()
					Purchase.product(product.key)
				end)
				c.Name = "Product_" .. product.key
			end
		end
		-- PvP is free of paid advantages (enforced on the server: State.pvpPower / walkSpeed)
		local pvp = Theme.new("Frame", { Name = "PvpNote", BackgroundColor3 = Theme.PaperLight, LayoutOrder = 998, Parent = grid }, { Theme.corner(12), Theme.stroke(2) })
		Theme.text({ Key = "store.pvp_note", TextWrapped = true, Size = UDim2.new(1, -20, 1, -16), Position = UDim2.fromOffset(10, 8), MaxTextSize = 18, Parent = pvp })
		if s.restricted then
			local note = Theme.new("Frame", { Name = "RestrictedNote", BackgroundColor3 = Theme.PaperLight, LayoutOrder = 999, Parent = grid }, { Theme.corner(12), Theme.stroke(2) })
			Theme.text({ Key = "store.restricted_note", TextWrapped = true, Size = UDim2.new(1, -20, 1, -16), Position = UDim2.fromOffset(10, 8), MaxTextSize = 18, Parent = note })
		end
	end
	w.onOpen = render
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			render()
		end
	end)
end

return StoreWindow
