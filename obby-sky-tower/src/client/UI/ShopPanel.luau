--!strict
-- Coins shop: trails and effects. Buying/equipping is validated by the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Toast = require(script.Parent.Toast)
local Lang = require(script.Parent.Parent.Lang)

local ShopPanel = {}

local function colorSeq(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	for i, c in colors do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(kps)
end

type Txt = { key: string, args: { [string]: any }? }
local function T(key: string, args: { [string]: any }?): Txt
	return { key = key, args = args }
end

local function card(grid: Instance, order: number, name: Txt, colors: { Color3 }, buttonText: Txt, buttonColor: Color3, onClick: () -> ())
	local c = Kit.card(grid, order)
	local swatch = Kit.frame(c, UDim2.new(1, -20, 0, 70), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1))
	Kit.corner(swatch, 12)
	local g = Instance.new("UIGradient")
	g.Color = colorSeq(colors)
	g.Parent = swatch
	local label = Kit.text(c, "", UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 84), Kit.C.ink, nil, 26)
	Kit.setText(label, name.key, name.args)
	local btn = Kit.button(c, "", UDim2.new(1, -20, 0, 54), UDim2.new(0, 10, 1, -62), buttonColor, onClick, nil, 24)
	Kit.setText(btn, buttonText.key, buttonText.args)
end

local function act(action: string, id: string)
	local ok, msg = Net.request(action, { id = id })
	if msg then
		Toast.show(msg, if ok then "success" else "error")
	end
end

function ShopPanel.init()
	local content = Kit.panel("shop", "@panel.shop", Kit.C.pink)
	local tab = "trails"
	local grid = Kit.grid(content, Vector2.new(180, 200), UDim2.new(1, 0, 1, -64), UDim2.fromOffset(0, 64))
	local tabs: { [string]: TextButton } = {}

	local function rebuild()
		for _, c in grid:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local s = Net.state
		local owned = (s.trails or {}) :: { [string]: boolean }
		local ownedFx = (s.effects or {}) :: { [string]: boolean }
		for name, b in tabs do
			b.BackgroundColor3 = if name == tab then Kit.C.pink else Kit.C.grey
		end
		if tab == "trails" then
			local order = 0
			if (s.wins or 0) > 0 then
				local w = s.wins :: number
				local col = Config.RebirthColors[((w - 1) % #Config.RebirthColors) + 1]
				local equipped = s.equippedTrail == "rebirth"
				card(grid, order, T("shop.rebirth", { n = w }), { col, col:Lerp(Color3.new(1, 1, 1), 0.5) }, T(if equipped then "shop.unequip" else "shop.equip"), if equipped then Kit.C.grey else Kit.C.blue, function()
					act("EquipTrail", "rebirth")
				end)
			end
			for i, t in Config.Trails do
				order = i
				local equipped = s.equippedTrail == t.id
				if t.pass then
					local has = Net.hasPass(t.pass)
					card(grid, order, T("trail." .. t.id), t.colors, T(if not has then "shop.vip_only" elseif equipped then "shop.unequip" else "shop.equip"), if has then (if equipped then Kit.C.grey else Kit.C.blue) else Kit.C.yellow, function()
						if has then
							act("EquipTrail", t.id)
						else
							Kit.open("store")
						end
					end)
				elseif t.exclusive and not owned[t.id] then
					-- Starter Pack / group exclusives are never sold for coins
					local starter = t.exclusive == "StarterPack"
					local label = if starter then "shop.starter_only" elseif t.exclusive == "Gift" then "shop.gift_only" elseif t.exclusive == "Lounge" then "shop.lounge_only" else "shop.group_only"
					card(grid, order, T("trail." .. t.id), t.colors, T(label), Kit.C.grey, function()
						local st = Net.state.starter
						if starter and type(st) == "table" and st.available then
							Kit.open("starter")
						end
					end)
				elseif owned[t.id] then
					card(grid, order, T("trail." .. t.id), t.colors, T(if equipped then "shop.unequip" else "shop.equip"), if equipped then Kit.C.grey else Kit.C.blue, function()
						act("EquipTrail", t.id)
					end)
				else
					card(grid, order, T("trail." .. t.id), t.colors, T("shop.price", { price = Kit.formatNumber(t.price) }), Kit.C.green, function()
						act("BuyTrail", t.id)
					end)
				end
			end
		else
			for i, e in Config.Effects do
				local equipped = s.equippedEffect == e.id
				local colors = { e.color, e.color:Lerp(Color3.new(1, 1, 1), 0.6) }
				if e.exclusive and not ownedFx[e.id] then
					-- tower gifts and lounge items are earned, never sold
					card(grid, i, T("effect." .. e.id), colors, T(if e.exclusive == "Gift" then "shop.gift_only" else "shop.lounge_only"), Kit.C.grey, function() end)
				elseif ownedFx[e.id] then
					card(grid, i, T("effect." .. e.id), colors, T(if equipped then "shop.unequip" else "shop.equip"), if equipped then Kit.C.grey else Kit.C.blue, function()
						act("EquipEffect", e.id)
					end)
				else
					card(grid, i, T("effect." .. e.id), colors, T("shop.price", { price = Kit.formatNumber(e.price) }), Kit.C.green, function()
						act("BuyEffect", e.id)
					end)
				end
			end
		end
	end

	tabs.trails = Kit.button(content, "@shop.trails", UDim2.fromOffset(160, 54), UDim2.fromOffset(0, 0), Kit.C.pink, function()
		tab = "trails"
		rebuild()
	end)
	tabs.effects = Kit.button(content, "@shop.effects", UDim2.fromOffset(160, 54), UDim2.fromOffset(172, 0), Kit.C.grey, function()
		tab = "effects"
		rebuild()
	end)
	local coins = Kit.text(content, "", UDim2.fromOffset(250, 40), UDim2.new(1, 0, 0, 3), Kit.C.ink, Vector2.new(1, 0), 30)
	coins.TextXAlignment = Enum.TextXAlignment.Right

	Kit.onOpen("shop", rebuild)
	Lang.changed:Connect(function()
		if Kit.current() == "shop" then
			rebuild()
		end
	end)
	Net.changed:Connect(function()
		Kit.setText(coins, "shop.price", { price = Kit.formatNumber(Net.state.coins or 0) })
		if Kit.current() == "shop" then
			rebuild()
		end
	end)
end

return ShopPanel
