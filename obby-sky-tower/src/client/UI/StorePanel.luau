--!strict
-- Robux store: developer products and game passes. IDs of 0 are hidden.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)

local StorePanel = {}

type Item = { key: string, name: string, desc: string, icon: string, color: Color3, isPass: boolean }

local ITEMS: { Item } = {
	{ key = "SkipStage", name = "Skip Stage", desc = "Jump to the next checkpoint", icon = "⏭", color = Kit.C.green, isPass = false },
	{ key = "Skip10", name = "Skip 10 Stages", desc = "Leap 10 checkpoints ahead", icon = "🚀", color = Kit.C.blue, isPass = false },
	{ key = "DoubleJump5", name = "Double Jump 5 min", desc = "Extra air jump for 5 minutes", icon = "⏫", color = Kit.C.green, isPass = false },
	{ key = "VIP", name = "VIP", desc = "[VIP] tag, gold trail, +50% coins, 2x daily", icon = "👑", color = Kit.C.yellow, isPass = true },
	{ key = "SpeedCoil", name = "Speed Coil", desc = "Run 50% faster (toggle)", icon = "⚡", color = Kit.C.orange, isPass = true },
	{ key = "GravityCoil", name = "Gravity Coil", desc = "Floaty low-gravity jumps (toggle)", icon = "🪐", color = Kit.C.purple, isPass = true },
	{ key = "Fusion", name = "Fusion Coil", desc = "Speed + Gravity coils in one", icon = "🌀", color = Kit.C.blue, isPass = true },
	{ key = "DoubleJump", name = "Double Jump", desc = "One extra jump in the air, for ever", icon = "⏫", color = Kit.C.green, isPass = true },
	{ key = "InfiniteRevives", name = "Infinite Revives", desc = "Unlimited pocket checkpoints", icon = "📍", color = Kit.C.orange, isPass = true },
	{ key = "DoubleCoins", name = "2x Coins", desc = "Double coins forever", icon = "💰", color = Kit.C.yellow, isPass = true },
	{ key = "Coins500", name = "500 Coins", desc = "Coin pack", icon = "💰", color = Kit.C.pink, isPass = false },
	{ key = "Coins2500", name = "2,500 Coins", desc = "Big coin pack", icon = "💰", color = Kit.C.pink, isPass = false },
	{ key = "Coins7000", name = "7,000 Coins", desc = "Mega coin pack", icon = "💰", color = Kit.C.pink, isPass = false },
}

local prices: { [number]: number } = {}

local function idOf(item: Item): number
	if item.isPass then
		return Config.Passes[item.key] or 0
	end
	if item.key == "SkipStage" then
		-- 19 R$ up to level 300, 29 R$ above (falls back to the other id while one is not created)
		local s = Net.state
		return Pricing.skipProductId(Config.Products, s.at or s.stage or 0)
	end
	return Config.Products[item.key] or 0
end

-- Already yours (or pointless to sell): passes you own, Fusion when you own both coils, and the
-- 5-minute double jump when the permanent pass is yours.
local function isOwned(item: Item): boolean
	if item.key == "Fusion" then
		return Net.hasPass("Fusion") or (Net.hasPass("SpeedCoil") and Net.hasPass("GravityCoil"))
	end
	if item.key == "DoubleJump5" then
		return Net.hasPass("DoubleJump")
	end
	return item.isPass and Net.hasPass(item.key)
end

function StorePanel.init()
	local content = Kit.panel("store", "@panel.store", Kit.C.green)
	local grid = Kit.grid(content, Vector2.new(280, 132))
	local empty = Kit.text(content, "@store.empty", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.3), Kit.C.ink, nil, 28)

	local function rebuild()
		for _, c in grid:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local count = 0
		for i, item in ITEMS do
			local id = idOf(item)
			if id ~= 0 then
				count += 1
				local c = Kit.card(grid, i)
				local iconBg = Kit.frame(c, UDim2.fromOffset(80, 80), UDim2.fromOffset(12, 20), item.color)
				Kit.corner(iconBg, 18)
				Kit.icon(iconBg, item.icon, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1), Kit.C.white, nil, 50)
				local title = Kit.text(c, "@store." .. item.key .. ".name", UDim2.fromOffset(170, 30), UDim2.fromOffset(102, 10), Kit.C.ink, nil, 26)
				title.TextXAlignment = Enum.TextXAlignment.Left
				local desc = Kit.text(c, "@store." .. item.key .. ".desc", UDim2.fromOffset(170, 30), UDim2.fromOffset(102, 40), Color3.fromRGB(110, 105, 140), nil, 16)
				desc.TextXAlignment = Enum.TextXAlignment.Left
				local owned = isOwned(item)
				local btn = Kit.button(c, "", UDim2.fromOffset(166, 52), UDim2.fromOffset(102, 72), if owned then Kit.C.grey else Kit.C.green, function()
					if owned then
						return
					end
					if item.isPass then
						MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
					else
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
					end
				end, nil, 22)
				if owned then
					Kit.setText(btn, "store.owned")
				elseif prices[id] then
					Kit.setText(btn, "hud.price", { price = prices[id] })
				else
					Kit.setText(btn, "store.buy")
				end
				if not prices[id] and not owned then
					task.spawn(function()
						local ok, info = pcall(function()
							return MarketplaceService:GetProductInfo(id, if item.isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
						end)
						if ok and info and info.PriceInRobux then
							prices[id] = info.PriceInRobux
							Kit.setText(btn, "hud.price", { price = info.PriceInRobux })
						end
					end)
				end
			end
		end
		empty.Visible = count == 0
	end

	Kit.onOpen("store", rebuild)
	Net.changed:Connect(function()
		if Kit.current() == "store" then
			rebuild()
		end
	end)
end

return StorePanel
