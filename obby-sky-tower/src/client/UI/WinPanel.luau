--!strict
-- Shown when you reach stage 100 (or use the pedestal in the victory room): take the portal,
-- rebirth (what you lose in red next to what you keep in green) or stay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Toast = require(script.Parent.Toast)

local WinPanel = {}

function WinPanel.init()
	local content = Kit.panel("win", "@panel.win", Kit.C.yellow)
	local title = Kit.bold(content, "", UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 0), Kit.C.yellow, nil, 46)
	-- what a rebirth costs and what it keeps, side by side: red = you lose, green = you keep
	local function column(name: string, x: number, color: Color3, headKey: string, listKey: string): Frame
		local card = Kit.frame(content, UDim2.new(0.5, -6, 0, 160), UDim2.new(x, if x > 0 then 6 else 0, 0, 56), color:Lerp(Color3.new(1, 1, 1), 0.82))
		card.Name = name
		Kit.corner(card, 16)
		Kit.stroke(card, color, 3)
		local head = Kit.frame(card, UDim2.new(1, 0, 0, 40), UDim2.new(), color)
		Kit.corner(head, 16)
		Kit.bold(head, headKey, UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), Kit.C.white, nil, 26)
		local list = Kit.text(card, listKey, UDim2.new(1, -24, 1, -88), UDim2.fromOffset(12, 46), Kit.C.ink, nil, 22)
		list.Name = "List"
		list.TextWrapped = true
		return card
	end
	column("Lose", 0, Kit.C.red, "@win.lose", "@win.lose_list")
	local gain = column("Gain", 0.5, Kit.C.green, "@win.gain", "@win.gain_list")
	local swatch = Kit.frame(gain, UDim2.new(1, -60, 0, 22), UDim2.new(0.5, 0, 1, -32), Kit.C.pink, Vector2.new(0.5, 0))
	swatch.Name = "NextTrail"
	Kit.corner(swatch, 11)
	Kit.stroke(swatch, Kit.C.ink, 2)
	Kit.button(content, "@win.rebirth", UDim2.fromOffset(330, 66), UDim2.new(0.5, -105, 1, -68), Kit.C.green, function()
		local ok, msg = Net.request("Rebirth")
		if ok then
			Kit.close()
		elseif msg then
			Toast.show(msg, "error")
		end
	end, Vector2.new(0.5, 0), 30)
	Kit.button(content, "@win.stay", UDim2.fromOffset(200, 66), UDim2.new(0.5, 170, 1, -68), Kit.C.grey, function()
		Kit.close()
	end, Vector2.new(0.5, 0), 28)
	-- the way on: 900 more stages behind the portal
	local portal = Kit.button(content, "@win.portal", UDim2.fromOffset(540, 56), UDim2.new(0.5, 0, 1, -134), Kit.C.purple, function()
		local ok, msg = Net.request("EnterPortal")
		if ok then
			Kit.close()
		elseif msg then
			Toast.show(msg, "info")
		end
	end, Vector2.new(0.5, 0), 28)
	portal.Name = "Portal"

	Kit.onOpen("win", function()
		local wins = Net.state.wins or 0
		local nextColor = Config.RebirthColors[((math.max(wins, 1) - 1) % #Config.RebirthColors) + 1]
		Kit.setText(title, "win.wins", { n = wins })
		swatch.BackgroundColor3 = nextColor
		local at = tonumber(Net.state.at) or 0
		portal.Visible = at > 0 and at % 100 == 0 and at < 1000 and Net.state.base ~= true
	end)
end

return WinPanel
