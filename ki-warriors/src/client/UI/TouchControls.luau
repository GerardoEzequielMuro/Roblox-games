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

-- Layout: centre of each button as { dx, dy, size }: distance in px from the bottom-right
-- corner of the safe area (bottom-LEFT for the seeds, flag `left`), measured on a typical
-- landscape phone (750x330 usable px, UI scale 0.85; sizes are design px, x0.85 on screen).
-- Everything is >= 44 px and keeps clear of the Roblox jump button (x > 700, y > 240 from the
-- top-left), the thumbstick (x < 155, y > 190) and the menu row along the bottom
-- (x 162-458). On tablets the offsets grow with the UI scale (see place()).
--   row y=300 .. 138 (from the top): rows of the right-hand cluster, columns 722/668/614/560/506
local LAYOUT = {
	punch = { 109, 57, 100 },
	block = { 190, 32, 56 },
	charge = { 190, 86, 56 },
	blast = { 136, 140, 56 },
	beam = { 82, 140, 56 },
	dash = { 28, 140, 56 },
	form = { 28, 194, 56 },
	fly = { 82, 194, 56 },
	down = { 244, 86, 54 },
	boost = { 244, 32, 54 },
	t_pulse_volley = { 190, 140, 54 },
	t_meteor_dive = { 244, 140, 54 },
	t_sunfall = { 244, 194, 54 },
	t_umbral_volley = { 190, 194, 54 },
	t_null_nova = { 136, 194, 54 },
	-- seeds: a row above the bottom menu, from the left (dx = distance from the left edge)
	seed_vigor_seed = { 189, 92, 54, true },
	seed_titan_seed = { 245, 92, 54, true },
	seed_spark_seed = { 301, 92, 54, true },
}
TouchControls.LAYOUT = LAYOUT

local holders: { [string]: Frame } = {}
local PHONE_SCALE = 0.85

-- (Re)positions every button; bigger UI scales (tablets) spread the cluster out with the buttons.
local function place()
	local k = math.max(1, Root.scale / PHONE_SCALE)
	-- tablets: the jump button sits further in and is bigger, so the cluster also moves left/up
	local extraX, extraY = (k - 1) * 300, (k - 1) * 150
	for name, holder in holders do
		local spec = LAYOUT[name]
		if spec[4] then
			holder.Position = UDim2.new(0, spec[1] * k, 1, -spec[2] * k)
		else
			holder.Position = UDim2.new(1, -(spec[1] * k + extraX), 1, -(spec[2] * k + extraY))
		end
	end
end

local function button(name: string, icon: string, color: Color3): Btn
	local spec = LAYOUT[name]
	local size = spec[3]
	local b = new("TextButton", {
		Name = "Touch_" .. name,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(),
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
	holders[name] = Root.mount(b)
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
	place()
	Root.Changed:Connect(place)

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
