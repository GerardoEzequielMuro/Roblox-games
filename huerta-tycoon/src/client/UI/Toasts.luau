--!nonstrict
-- Stacked toast notifications at the top-center. "rare" toasts are bigger with an animated rainbow.
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)

local Toasts = {}

local MAX_VISIBLE = 5
local container: Frame? = nil
local order = 0
local lastText, lastAt = "", 0
local active: { Frame } = {}

function Toasts.build(root: Instance)
	container = C.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(640, 400),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = root,
	})
	C.list(container :: Frame, true, 6, Enum.HorizontalAlignment.Center)
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(120, 230, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 190, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 180)),
})

local function remove(toast: Frame, fadeTime: number)
	local i = table.find(active, toast)
	if i then
		table.remove(active, i)
	end
	if toast.Parent then
		C.fadeOut(toast, fadeTime)
		task.delay(fadeTime + 0.05, function()
			toast:Destroy()
		end)
	end
end

function Toasts.show(text: any, kind: string?)
	if container == nil then
		return
	end
	text = I18n.str(text)
	if text == "" then
		return
	end
	kind = if kind and Theme.ToastColors[kind] then kind else "info"
	-- Collapse duplicates (e.g. a server Notify and a Request reply with the same text).
	local now = os.clock()
	if text == lastText and now - lastAt < 1.2 then
		return
	end
	lastText, lastAt = text, now

	local rare = kind == "rare"
	if kind == "error" then
		local okS, Sound = pcall(require, script.Parent.Sound)
		if okS then
			Sound.play("error")
		end
	end
	if rare then
		-- rare harvests and live events deserve a party (Juice is required lazily: it loads after Toasts)
		local ok, Juice = pcall(require, script.Parent.Juice)
		if ok then
			Juice.confetti(24)
		end
	end
	local color = Theme.ToastColors[kind]
	order += 1

	local toast: Frame = C.new("Frame", {
		Name = "Toast",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = if rare then Color3.new(1, 1, 1) else color,
		LayoutOrder = order,
	})
	C.corner(toast, 16)
	C.stroke(toast, if rare then 4 else 3, if rare then Color3.new(1, 1, 1) else Theme.darken(color, 0.45))
	C.padding(toast, if rare then 12 else 8, if rare then 22 else 18)
	local grad
	if rare then
		grad = C.gradient(toast, RAINBOW, nil, 0)
	else
		C.shade(toast)
	end
	local lbl = C.label(toast, text, UDim2.fromOffset(0, 0), {
		AutomaticSize = Enum.AutomaticSize.XY,
		TextSize = if rare then 30 else 22,
		TextWrapped = false,
		Outline = if rare then 3 else 2,
	})
	C.new("UISizeConstraint", { MaxSize = Vector2.new(600, math.huge), Parent = lbl })
	lbl.TextWrapped = true
	local sc = C.new("UIScale", { Scale = 0.4, Parent = toast })
	toast.Parent = container
	C.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	table.insert(active, toast)

	while #active > MAX_VISIBLE do
		remove(active[1], 0.15)
	end

	local conn
	if grad then
		conn = RunService.RenderStepped:Connect(function()
			if not toast.Parent then
				conn:Disconnect()
				return
			end
			grad.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.3, 0)
			grad.Rotation = (os.clock() * 60) % 360
		end)
	end

	task.delay(if rare then 5 else 3, function()
		remove(toast, 0.4)
		task.delay(0.5, function()
			if conn then
				conn:Disconnect()
			end
		end)
	end)
end

return Toasts
