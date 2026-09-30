--!strict
-- Small notifications (stacked toasts) and the wide banner used for live events.
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local Toasts = {}

local stack = Theme.new("Frame", {
	Name = "Toasts",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(520, 220),
	Position = UDim2.new(0.5, 0, 0, 92),
	AnchorPoint = Vector2.new(0.5, 0),
	ZIndex = 40,
	Parent = Root.gui,
}, { Theme.list(Enum.FillDirection.Vertical, 6) })
Root.mount(stack)

local KIND_COLORS = {
	info = Theme.Blue,
	success = Theme.Green,
	error = Theme.Red,
}

local order = 0
Toasts.shown = 0
function Toasts.show(text: string, kind: string?, duration: number?)
	order += 1
	Toasts.shown += 1
	local color = KIND_COLORS[kind or "info"] or Theme.Blue
	local f = Theme.new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(480, 40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		ZIndex = 40,
		Parent = stack,
	}, { Theme.corner(20), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.15), Theme.darken(color, 0.1)) })
	local sc = Theme.new("UIScale", { Scale = 0.5, Parent = f })
	local label = Theme.text({ Text = text, Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), MaxTextSize = 22, Parent = f })
	label.ZIndex = 41
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(duration or 2.8, function()
		local t = TweenService:Create(sc, TweenInfo.new(0.2), { Scale = 0 })
		t:Play()
		t.Completed:Wait()
		f:Destroy()
	end)
	-- keep the stack short
	local frames = {}
	for _, c in stack:GetChildren() do
		if c:IsA("Frame") then
			table.insert(frames, c)
		end
	end
	if #frames > 4 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end
end

function Toasts.init()
	Net.event("Notify").OnClientEvent:Connect(function(message, kind)
		Toasts.show(Lang.msg(message), kind)
	end)
end

return Toasts
