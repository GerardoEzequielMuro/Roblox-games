--!nonstrict
-- Notifications (personal toasts) and the big centre banner (unlocks, events, announcements).
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local Toasts = {}

local stack = Theme.new("Frame", {
	Name = "Toasts",
	BackgroundTransparency = 1,
	Size = if Root.isTouch then UDim2.fromOffset(400, 140) else UDim2.fromOffset(520, 220),
	Position = if Root.isTouch then UDim2.new(0.43, 0, 0.5, 0) else UDim2.new(0.5, 0, 0, 236),
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
local recent: { [string]: number } = {}
function Toasts.show(text: string, kind: string?, duration: number?)
	local now = os.clock()
	if recent[text] and now - recent[text] < 1.6 then
		return -- same message again: do not stack it
	end
	recent[text] = now
	order += 1
	local color = KIND_COLORS[kind or "info"] or Theme.Blue
	local f = Theme.new("Frame", {
		Size = if Root.isTouch then UDim2.fromOffset(380, 36) else UDim2.fromOffset(480, 40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = stack,
	}, { Theme.corner(12), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.15), Theme.darken(color, 0.25)) })
	local sc = Theme.new("UIScale", { Scale = 0.5, Parent = f })
	Theme.text({ Text = text, Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), MaxTextSize = 22, Parent = f })
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	if kind == "error" then
		Theme.play("click", 0.4, 0.6)
	end
	task.delay(duration or 2.6, function()
		local t = TweenService:Create(sc, TweenInfo.new(0.2), { Scale = 0 })
		t:Play()
		t.Completed:Wait()
		f:Destroy()
	end)
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

-- Big banner
local banner = Theme.new("Frame", {
	Name = "Announce",
	Size = if Root.isTouch then UDim2.fromOffset(460, 52) else UDim2.fromOffset(620, 60),
	Position = if Root.isTouch then UDim2.new(0.43, 0, 0.4, 0) else UDim2.new(0.5, 0, 0, 170),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
	ZIndex = 45,
	Parent = Root.gui,
}, { Theme.corner(14), Theme.stroke(4) })
Root.mount(banner).ClipsDescendants = false
local HIDDEN = UDim2.new(0.5, 0, 0.5, -140)
local SHOWN = UDim2.new(0.5, 0, 0.5, 0)
banner.Position = HIDDEN
local bannerGradient = Theme.new("UIGradient", { Rotation = 90, Parent = banner })
local bannerText = Theme.text({ Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), MaxTextSize = 28, RichText = true, Stroke = 3, Parent = banner })
bannerText.ZIndex = 46
local queue: { { text: string, color: Color3 } } = {}
local busy = false
Toasts.bannersShown = 0

local function nextBanner()
	if busy or #queue == 0 then
		return
	end
	busy = true
	local item = table.remove(queue, 1)
	Toasts.bannersShown += 1
	bannerText.Text = item.text
	bannerGradient.Color = ColorSequence.new(Theme.lighten(item.color, 0.25), Theme.darken(item.color, 0.3))
	banner.Visible = true
	banner.Position = HIDDEN
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = SHOWN }):Play()
	Theme.play("land", 0.4, 1.4)
	task.delay(3.2, function()
		local t = TweenService:Create(banner, TweenInfo.new(0.25), { Position = HIDDEN })
		t:Play()
		t.Completed:Wait()
		banner.Visible = false
		busy = false
		nextBanner()
	end)
end

function Toasts.banner(text: string, color: Color3)
	table.insert(queue, { text = text, color = color })
	while #queue > 5 do
		table.remove(queue, 1)
	end
	nextBanner()
end

function Toasts.init()
	Net.event("Notify").OnClientEvent:Connect(function(message, kind)
		Toasts.show(Lang.msg(message), kind)
	end)
	Net.event("Toast").OnClientEvent:Connect(function(data)
		if type(data) == "table" and data.key then
			Toasts.banner(Lang.t(data.key, data.args), if data.color then Theme.rgb(data.color) else Theme.Orange)
		end
	end)
end

return Toasts
