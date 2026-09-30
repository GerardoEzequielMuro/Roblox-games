--!nonstrict
-- Small building blocks shared by the menu windows: scrolling lists, rows, chips, section
-- headers, progress bars and "state" buttons. Keeps every window short and consistent.
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local Kit = {}
local new = Theme.new

-- Vertical scrolling list that sizes its canvas automatically.
function Kit.scroll(parent: Instance, size: UDim2?, pos: UDim2?, padding: number?): ScrollingFrame
	local sf = new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = size or UDim2.fromScale(1, 1),
		Position = pos or UDim2.new(),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Dim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 21,
		Parent = parent,
	}, {
		Theme.list(Enum.FillDirection.Vertical, padding or 8, Enum.HorizontalAlignment.Center),
		new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10) }),
	})
	return sf
end

function Kit.clear(container: Instance)
	for _, c in container:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- A dark row card. Returns the frame.
function Kit.row(parent: Instance, height: number, order: number?, accent: Color3?): Frame
	local f = new("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order or 0,
		ZIndex = 22,
		Parent = parent,
	}, { Theme.corner(12), Theme.stroke(2.5), Theme.gradient(Theme.lighten(Theme.PanelLight, 0.06), Theme.Panel) })
	if accent then
		new("Frame", { Size = UDim2.new(0, 6, 1, -14), Position = UDim2.fromOffset(6, 7), BackgroundColor3 = accent, BorderSizePixel = 0, ZIndex = 23, Parent = f }, { Theme.corner(3) })
	end
	return f
end

-- Text inside a row / card (ZIndex above the card).
function Kit.text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Theme.text(props)
	t.ZIndex = (props.ZIndex or 23)
	t.Parent = parent
	return t
end

-- Round chip with an emoji / short text.
function Kit.chip(parent: Instance, icon: string, color: Color3, size: number, pos: UDim2): Frame
	local f = new("Frame", { Name = "Chip", Size = UDim2.fromOffset(size, size), Position = pos, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 23, Parent = parent }, {
		Theme.corner(size),
		Theme.stroke(2.5),
		Theme.gradient(Theme.lighten(color, 0.35), Theme.darken(color, 0.15)),
	})
	local t = Theme.text({ Text = icon, Stroke = false, Size = UDim2.fromScale(0.64, 0.64), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = f })
	t.ZIndex = 24
	return f
end

function Kit.header(parent: Instance, key: string, order: number?, args: { [string]: any }?): TextLabel
	local t = Theme.text({ Key = key, Args = args, Size = UDim2.new(1, -8, 0, 22), MaxTextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Yellow, LayoutOrder = order or 0 })
	t.ZIndex = 22
	t.Parent = parent
	return t
end

-- Button placed at the right side of a row.
function Kit.button(parent: Instance, text: string, color: Color3, width: number, onClick: () -> (), height: number?): TextButton
	local b = Theme.button({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(width, height or 40),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 18,
		ZIndex = 23,
		Parent = parent,
		OnClick = onClick,
	})
	for _, d in b:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 24
		end
	end
	return b
end

function Kit.bar(parent: Instance, size: UDim2, pos: UDim2, color: Color3, frac: number, text: string?): Frame
	local bar, set = Theme.bar({ Size = size, Position = pos, Color = color, TextSize = 13, Parent = parent })
	bar.ZIndex = 23
	for _, d in bar:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 24
		end
	end
	local label = bar:FindFirstChild("Text")
	if label then
		label.ZIndex = 25
	end
	set(frac, text)
	return bar
end

-- Sends a request and shows the server message (or a success message) as a toast.
Kit.notify = nil :: any -- set by the menu (Toasts.show)
function Kit.request(action: string, payload: { [string]: any }?, okText: string?): (boolean, any)
	local ok, res = Net.request(action, payload)
	if Kit.notify then
		if not ok then
			Kit.notify(Lang.msg(res), "error")
		elseif okText then
			Kit.notify(okText, "success")
		elseif type(res) == "table" and res.key then
			Kit.notify(Lang.msg(res), "success")
		end
	end
	if ok then
		Theme.play("land", 0.4, 1.4)
	end
	return ok, res
end

-- Registers a window: builds the chrome and re-runs `render(body)` while it is open and
-- whenever the state or the language changes.
function Kit.window(name: string, icon: string, titleKey: string, color: Color3, size: Vector2?, render: (Frame) -> ()): any
	local w = Windows.create(name, icon, titleKey, color, size)
	local function refresh()
		if Windows.isOpen(name) then
			render(w.body)
		end
	end
	w.onOpen = function()
		render(w.body)
	end
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
	w.refresh = refresh
	return w
end

return Kit
