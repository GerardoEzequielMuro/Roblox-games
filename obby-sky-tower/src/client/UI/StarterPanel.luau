--!strict
-- Starter Pack (P0-4): one-time popup when a first-day player reaches stage 3, and a panel behind
-- the pulsing menu button while the pack is on sale (product id set, not bought, first 24 h).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)

local StarterPanel = {}

local popupShown = false

local function available(): boolean
	local st = Net.state.starter
	return type(st) == "table" and st.available == true
end

function StarterPanel.init()
	local content = Kit.panel("starter", "@starter.title", Kit.C.red)
	local badge = Kit.frame(content, UDim2.fromOffset(150, 150), UDim2.fromOffset(10, 10), Kit.C.yellow)
	Kit.corner(badge, 75)
	Kit.stroke(badge, Kit.darker(Kit.C.yellow, 0.45), 4)
	badge.Rotation = -8
	Kit.bold(badge, "@starter.discount", UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.25), Kit.C.white, nil, 56)
	local was = Kit.text(content, "", UDim2.new(1, -190, 0, 36), UDim2.fromOffset(180, 16), Color3.fromRGB(150, 140, 170), nil, 30)
	was.TextXAlignment = Enum.TextXAlignment.Left
	local items = Kit.text(content, "", UDim2.new(1, -190, 0, 96), UDim2.fromOffset(180, 58), Kit.C.ink, nil, 28)
	items.TextXAlignment = Enum.TextXAlignment.Left
	items.TextWrapped = true
	local ends = Kit.text(content, "", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 190), Kit.C.red, nil, 28)
	local buy = Kit.button(content, "", UDim2.fromOffset(340, 76), UDim2.new(0.5, 0, 1, -86), Kit.C.green, function()
		if Config.Products.StarterPack ~= 0 then
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, Config.Products.StarterPack)
		end
	end, Vector2.new(0.5, 0), 34)
	buy.Name = "Buy"

	local function refresh()
		Kit.setText(was, "starter.was", { price = Config.StarterPackAnchorPrice })
		Kit.setText(items, "starter.items", { n = Config.StarterPackSkips, minutes = Config.StarterBoostSeconds // 60 })
		local price = Hud.priceOf(Config.Products.StarterPack)
		if price then
			Kit.setText(buy, "starter.buy", { price = price })
		else
			Kit.setText(buy, "starter.buy_noprice")
		end
		local st = Net.state.starter
		local left = if type(st) == "table" then (tonumber(st.endsAt) or 0) - os.time() else 0
		Kit.setText(ends, "starter.ends", { time = Kit.formatTime(left) })
	end
	Kit.onOpen("starter", refresh)
	Hud.fetchPrice(Config.Products.StarterPack, function()
		refresh()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Kit.current() == "starter" then
				if not available() then
					Kit.close()
				else
					refresh()
				end
			end
		end
	end)
	-- one-time popup at stage 3 during the first day
	Net.changed:Connect(function(new)
		if popupShown or not available() then
			return
		end
		local st = new.starter
		if (new.stage or 0) >= 3 and type(st) == "table" and st.firstSession and Kit.current() == nil then
			popupShown = true
			Kit.open("starter")
		end
	end)
end

return StarterPanel
