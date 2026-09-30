--!strict
-- Stacked toast notifications at the top of the screen.
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)

local Toast = {}

local region: Frame? = nil
local COLORS: { [string]: Color3 } = {
	info = Kit.C.blue,
	success = Kit.C.green,
	warn = Kit.C.orange,
	error = Kit.C.red,
	coins = Kit.C.yellow,
}

local function getRegion(): Frame
	if region then
		return region
	end
	local r = Kit.region("Toasts", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 100), Vector2.new(520, 220))
	r.ZIndex = 20
	Kit.onLayout(function()
		r.Position = UDim2.new(0.5, 0, 0, Kit.hudTop + Kit.cardInset + 6) -- under the timer (and the offer strip)
	end)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.Parent = r
	region = r
	return r
end

local order = 0
function Toast.show(text: string, kind: string?)
	local r = getRegion()
	order += 1
	local color = COLORS[kind or "info"] or Kit.C.blue
	local f = Kit.frame(r, UDim2.fromOffset(460, 50), UDim2.new(), color)
	f.LayoutOrder = order
	Kit.corner(f, 25)
	Kit.stroke(f, Kit.darker(color, 0.45), 3)
	Kit.gradient(f, Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 210))
	local label = Kit.bold(f, text, UDim2.new(1, -24, 1, -10), UDim2.fromOffset(12, 5), Kit.C.white, nil, 26)
	Kit.pop(f, 0.5)
	task.delay(3, function()
		local ti = TweenInfo.new(0.35)
		TweenService:Create(f, ti, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, ti, { TextTransparency = 1 }):Play()
		local st = f:FindFirstChildOfClass("UIStroke")
		if st then
			TweenService:Create(st, ti, { Transparency = 1 }):Play()
		end
		local ls = label:FindFirstChildOfClass("UIStroke")
		if ls then
			TweenService:Create(ls, ti, { Transparency = 1 }):Play()
		end
		task.wait(0.4)
		f:Destroy()
	end)
	-- keep at most 4
	local kids = {}
	for _, c in r:GetChildren() do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	if #kids > 4 then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
end

return Toast
