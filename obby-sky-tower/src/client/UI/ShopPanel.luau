--!strict
-- Coins shop: trails and effects. Buying/equipping is validated by the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
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

-- One shop card: colour swatch, name, an optional small line (price / shine stars) and a button.
local function card(grid: Instance, order: number, name: Txt, colors: { Color3 }, buttonText: Txt, buttonColor: Color3, onClick: () -> (), sub: Txt?)
	local c = Kit.card(grid, order)
	local swatch = Kit.frame(c, UDim2.new(1, -20, 0, 70), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1))
	Kit.corner(swatch, 12)
	local g = Instance.new("UIGradient")
	g.Color = colorSeq(colors)
	g.Parent = swatch
	local label = Kit.text(c, "", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 82), Kit.C.ink, nil, 26)
	Kit.setText(label, name.key, name.args)
	if sub then
		local line = Kit.text(c, "", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 110), Kit.C.ink, nil, 20)
		Kit.setText(line, sub.key, sub.args)
	end
	local btn = Kit.button(c, "", UDim2.new(1, -20, 0, 54), UDim2.new(0, 10, 1, -62), buttonColor, onClick, nil, 24)
	Kit.setText(btn, buttonText.key, buttonText.args)
end

-- "★★☆" for a shine level (only shown once the item has at least one).
local function stars(level: number): string
	local max = Config.ShineMax
	return string.rep("★", level) .. string.rep("☆", max - level)
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
	local empty = Kit.text(content, "@shop.shine_empty", UDim2.new(1, -40, 0, 80), UDim2.fromOffset(20, 120), Kit.C.ink, nil, 26)
	empty.Visible = false

	-- Button + small line of a tier item (towers cleared gate the purchase) --------------------
	local function locked(best: number, tower: number?): boolean
		return tower ~= nil and tower > 0 and not Economy.towerCleared(best, tower)
	end
	local function shineSub(level: number): Txt?
		if level > 0 then
			return T("shop.shine_level", { stars = stars(level) })
		end
		return nil
	end

	local function rebuild()
		for _, c in grid:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local s = Net.state
		local best = (s.best or 0) :: number
		local owned = (s.trails or {}) :: { [string]: boolean }
		local ownedFx = (s.effects or {}) :: { [string]: boolean }
		local ownedPets = (s.pets or {}) :: { [string]: boolean }
		local shine = (s.shine or {}) :: { [string]: number }
		local function lvl(kind: string, id: string): number
			return shine[kind .. ":" .. id] or 0
		end
		for name, b in tabs do
			b.BackgroundColor3 = if name == tab then Kit.C.pink else Kit.C.grey
		end
		empty.Visible = false
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
					end, shineSub(lvl("trail", t.id)))
				elseif locked(best, t.tower) then
					card(grid, order, T("trail." .. t.id), t.colors, T("shop.locked", { n = t.tower }), Kit.C.grey, function() end, T("shop.price", { price = Kit.formatNumber(t.price) }))
				else
					card(grid, order, T("trail." .. t.id), t.colors, T("shop.price", { price = Kit.formatNumber(t.price) }), Kit.C.green, function()
						act("BuyTrail", t.id)
					end)
				end
			end
		elseif tab == "effects" then
			for i, e in Config.Effects do
				local equipped = s.equippedEffect == e.id
				local colors = { e.color, e.color:Lerp(Color3.new(1, 1, 1), 0.6) }
				if e.exclusive and not ownedFx[e.id] then
					-- tower gifts and lounge items are earned, never sold
					card(grid, i, T("effect." .. e.id), colors, T(if e.exclusive == "Gift" then "shop.gift_only" else "shop.lounge_only"), Kit.C.grey, function() end)
				elseif ownedFx[e.id] then
					card(grid, i, T("effect." .. e.id), colors, T(if equipped then "shop.unequip" else "shop.equip"), if equipped then Kit.C.grey else Kit.C.blue, function()
						act("EquipEffect", e.id)
					end, shineSub(lvl("effect", e.id)))
				elseif locked(best, e.tower) then
					card(grid, i, T("effect." .. e.id), colors, T("shop.locked", { n = e.tower }), Kit.C.grey, function() end, T("shop.price", { price = Kit.formatNumber(e.price) }))
				else
					card(grid, i, T("effect." .. e.id), colors, T("shop.price", { price = Kit.formatNumber(e.price) }), Kit.C.green, function()
						act("BuyEffect", e.id)
					end)
				end
			end
		elseif tab == "pets" then
			for i, pet in Config.Pets do
				local equipped = s.equippedPet == pet.id
				local colors = { pet.color, pet.accent }
				if ownedPets[pet.id] then
					card(grid, i, T("pet." .. pet.id), colors, T(if equipped then "shop.unequip" else "shop.equip"), if equipped then Kit.C.grey else Kit.C.blue, function()
						act("EquipPet", pet.id)
					end, shineSub(lvl("pet", pet.id)))
				elseif locked(best, pet.tower) then
					card(grid, i, T("pet." .. pet.id), colors, T("shop.locked", { n = pet.tower }), Kit.C.grey, function() end, T("shop.price", { price = Kit.formatNumber(pet.price) }))
				else
					card(grid, i, T("pet." .. pet.id), colors, T("shop.price", { price = Kit.formatNumber(pet.price) }), Kit.C.green, function()
						act("BuyPet", pet.id)
					end)
				end
			end
		else
			-- Shine: upgrade what you own (coins only, looks only)
			local order = 0
			local function shineCard(kind: string, id: string, colors: { Color3 })
				order += 1
				local level = lvl(kind, id)
				local cost = Economy.shineCost(level)
				local name = T(kind .. "." .. id)
				local sub = T("shop.shine_level", { stars = stars(level) })
				if cost then
					card(grid, order, name, colors, T("shop.upgrade", { price = Kit.formatNumber(cost) }), Kit.C.orange, function()
						local ok, msg = Net.request("UpgradeShine", { kind = kind, id = id })
						if msg then
							Toast.show(msg, if ok then "success" else "error")
						end
					end, sub)
				else
					card(grid, order, name, colors, T("shop.maxed"), Kit.C.grey, function() end, sub)
				end
			end
			for _, t in Config.Trails do
				if owned[t.id] and not t.pass then
					shineCard("trail", t.id, t.colors)
				end
			end
			for _, e in Config.Effects do
				if ownedFx[e.id] then
					shineCard("effect", e.id, { e.color, e.color:Lerp(Color3.new(1, 1, 1), 0.6) })
				end
			end
			for _, pet in Config.Pets do
				if ownedPets[pet.id] then
					shineCard("pet", pet.id, { pet.color, pet.accent })
				end
			end
			empty.Visible = order == 0
		end
	end

	local TAB_W, TAB_GAP = 112, 6
	local function addTab(name: string, label: string, index: number)
		tabs[name] = Kit.button(content, label, UDim2.fromOffset(TAB_W, 54), UDim2.fromOffset((index - 1) * (TAB_W + TAB_GAP), 0), Kit.C.grey, function()
			tab = name
			rebuild()
		end, nil, 26)
		tabs[name].Name = "Tab_" .. name
	end
	addTab("trails", "@shop.trails", 1)
	addTab("effects", "@shop.effects", 2)
	addTab("pets", "@shop.pets", 3)
	addTab("shine", "@shop.shine", 4)
	local coins = Kit.text(content, "", UDim2.fromOffset(150, 40), UDim2.new(1, 0, 0, 7), Kit.C.ink, Vector2.new(1, 0), 28)
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
