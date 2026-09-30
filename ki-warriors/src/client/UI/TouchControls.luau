--!nonstrict
-- On-screen combat buttons for phones and tablets. They sit in the right half of the screen,
-- around (never on top of) the Roblox jump button, and call the same Controls.* functions as
-- the keyboard. The thumbstick zone (bottom-left) is left completely free.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local Controls = require(script.Parent.Parent.Controls)
local Flight = require(script.Parent.Parent.Flight)

local TouchControls = {}
local new = Theme.new

type Btn = { frame: TextButton, cool: Frame, action: string }
local buttons: { [string]: Btn } = {}
TouchControls.buttons = buttons

-- Screen-space layout (fractions of the safe area). Jump button zone: x > 0.75, y > 0.65.
local LAYOUT = {
	punch = { 0.665, 0.835, 98 },
	block = { 0.555, 0.885, 64 },
	charge = { 0.575, 0.70, 64 },
	blast = { 0.72, 0.62, 70 },
	beam = { 0.83, 0.555, 70 },
	dash = { 0.94, 0.50, 64 },
	form = { 0.94, 0.355, 60 },
	fly = { 0.94, 0.215, 60 },
	down = { 0.845, 0.25, 54 },
	boost = { 0.755, 0.28, 54 },
	t_pulse_volley = { 0.845, 0.40, 56 },
	t_meteor_dive = { 0.745, 0.455, 56 },
	t_sunfall = { 0.645, 0.53, 56 },
	t_umbral_volley = { 0.645, 0.37, 52 },
	t_null_nova = { 0.545, 0.45, 52 },
	seed_vigor_seed = { 0.46, 0.70, 44 },
	seed_titan_seed = { 0.46, 0.80, 44 },
	seed_spark_seed = { 0.46, 0.90, 44 },
}
TouchControls.LAYOUT = LAYOUT

local function button(name: string, icon: string, color: Color3): Btn
	local spec = LAYOUT[name]
	local size = spec[3]
	local b = new("TextButton", {
		Name = "Touch_" .. name,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(spec[1], spec[2]),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(40, 40, 52),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		Parent = Root.gui,
	}, {
		Theme.corner(size),
		Theme.stroke(3, Color3.fromRGB(245, 245, 255)),
	})
	-- thin coloured inner ring: which move this is, without a loud button
	new("Frame", { Name = "Tint", Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = color, BackgroundTransparency = 0.72, BorderSizePixel = 0, Parent = b }, { Theme.corner(size) })
	Theme.icon(icon, { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = b }).ZIndex = 2
	local clip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 3, Parent = b }, { Theme.corner(size) })
	local cool = new("Frame", { Name = "Cool", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = color, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 3, Parent = clip })
	local sc = new("UIScale", { Parent = b })
	b.MouseButton1Down:Connect(function()
		sc.Scale = 0.9
	end)
	b.MouseButton1Up:Connect(function()
		sc.Scale = 1
	end)
	b.MouseLeave:Connect(function()
		sc.Scale = 1
	end)
	Root.mount(b)
	local entry = { frame = b, cool = cool, action = name }
	buttons[name] = entry
	return entry
end

local function hold(b: Btn, down: () -> (), up: () -> ())
	b.frame.MouseButton1Down:Connect(down)
	b.frame.MouseButton1Up:Connect(up)
	b.frame.MouseLeave:Connect(up)
end

function TouchControls.init()
	if not Root.isTouch then
		return
	end
	local punch = button("punch", "👊", Theme.Red)
	local punching = false
	hold(punch, function()
		punching = true
		Controls.punch()
	end, function()
		punching = false
	end)
	button("blast", "🔵", Theme.Cyan).frame.MouseButton1Down:Connect(Controls.blast)
	hold(button("beam", "☄️", Theme.Blue), Controls.beamBegin, Controls.beamEnd)
	hold(button("block", "🛡️", Theme.Green), function()
		Controls.block(true)
	end, function()
		Controls.block(false)
	end)
	hold(button("charge", "🔋", Theme.Purple), function()
		Controls.charge(true)
	end, function()
		Controls.charge(false)
	end)
	button("dash", "💨", Theme.Yellow).frame.MouseButton1Down:Connect(Controls.dash)
	button("form", "🔥", Theme.Orange).frame.Activated:Connect(function()
		Controls.transform()
	end)
	button("fly", "🕊️", Theme.Pink).frame.Activated:Connect(Controls.toggleFly)
	local down = button("down", "⬇️", Theme.Grey)
	hold(down, function()
		Flight.descend = true
	end, function()
		Flight.descend = false
	end)
	local boost = button("boost", "🚀", Theme.Grey)
	boost.frame.Activated:Connect(function()
		Flight.boost = not Flight.boost
		local tint = boost.frame:FindFirstChild("Tint") :: Frame
		tint.BackgroundColor3 = if Flight.boost then Theme.Yellow else Theme.Grey
		tint.BackgroundTransparency = if Flight.boost then 0.35 else 0.72
	end)
	for _, t in Config.Techniques do
		local b = button("t_" .. t.id, t.icon, Theme.Purple)
		b.frame.MouseButton1Down:Connect(function()
			Controls.technique(t.id)
		end)
	end

	for _, sd in Config.Seeds do
		local b = button("seed_" .. sd.id, sd.icon, Theme.rgb(sd.color))
		b.frame.Activated:Connect(function()
			Controls.useSeed(sd.id)
		end)
		local count = Theme.text({ Name = "Count", Text = "0", Size = UDim2.fromOffset(24, 16), Position = UDim2.new(1, 2, 1, 2), AnchorPoint = Vector2.new(1, 1), MaxTextSize = 15, Stroke = 2.5, Parent = b.frame })
		count.ZIndex = 5
	end

	local function refresh()
		local flying = Flight.active
		local downHolder: any, boostHolder: any = down.frame.Parent, boost.frame.Parent
		downHolder.Visible = flying
		boostHolder.Visible = flying
		local owned = Net.get("techniques") or {}
		for _, t in Config.Techniques do
			local holder: any = buttons["t_" .. t.id].frame.Parent
			holder.Visible = owned[t.id] == true
		end
		local seeds = Net.get("seeds")
		for _, sd in Config.Seeds do
			local b = buttons["seed_" .. sd.id]
			local n = if seeds then seeds.items[sd.id] or 0 else 0
			local holder: any = b.frame.Parent
			holder.Visible = n > 0
			local label = b.frame:FindFirstChild("Count") :: TextLabel?
			if label then
				label.Text = tostring(n)
			end
		end
	end
	Flight.Changed:Connect(refresh)
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
	refresh()

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if punching and (Controls.nextAt.melee or 0) <= now then
			Controls.punch()
		end
		for name, b in buttons do
			local action = if name == "punch" then "melee" else name
			local total = Controls.cooldownOf[action]
			if total then
				b.cool.Size = UDim2.fromScale(1, math.clamp(((Controls.nextAt[action] or 0) - now) / total, 0, 1))
			end
		end
	end)
end

return TouchControls
