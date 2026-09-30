--!strict
-- The lounge teleporter: one button per world you have already reached (the first pad of every
-- 10 stages, up to your best stage) plus the lobby. Opened by the teleporter pedestal in the
-- Winner's Lounge; the server validates the destination (Shared/Perks.canTravel).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Toast = require(script.Parent.Toast)
local Progress = require(script.Parent.Progress)

local TravelPanel = {}

function TravelPanel.init()
	local content = Kit.panel("travel", "@panel.travel", Kit.C.purple)
	local grid = Kit.grid(content, Vector2.new(140, 60))
	local builtFor = -1

	local function rebuild()
		local best = tonumber(Net.state.best) or 0
		if best == builtFor then
			return
		end
		builtFor = best
		for _, c in grid:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
		for i, target in Perks.travelTargets(best) do
			local color = Kit.C.grey
			if target > 0 then
				color = Progress.WORLD_COLORS[Layout.themeFor(math.min(target + 1, Layout.TOTAL))]
			end
			local b = Kit.button(grid, "", UDim2.fromOffset(140, 60), UDim2.new(), color, function()
				local ok, msg = Net.request("Travel", { stage = target })
				if ok then
					Kit.close()
				elseif msg then
					Toast.show(msg, "info")
				end
			end, nil, 20)
			b.Name = "To_" .. target
			b.LayoutOrder = i
			if target == 0 then
				Kit.setText(b, "travel.lobby")
			else
				Kit.setText(b, "travel.world", { n = target // 10 + 1, stage = target })
			end
		end
	end
	Kit.onOpen("travel", rebuild)
	Net.changed:Connect(function()
		if Kit.current() == "travel" then
			rebuild()
		end
	end)
end

return TravelPanel
