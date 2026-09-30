--!strict
-- Window building blocks shared by every window: scrolling lists, tab strips, rows, cards,
-- price buttons and the "request + toast" helper.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local Kit = {}

-- Touch windows: every tappable control is at least this tall (design units; the window
-- scale is ~0.8 on a phone, so >= 44 px real).
Kit.TOUCH_BTN = 56
Kit.touch = Root.isTouch

Kit.CURRENCY_ICON = { stardust = "✨", crystals = "💎", spores = "🍄", cryo = "❄️", embers = "🔥", volt = "⚡", essence = "🌌" }
Kit.CURRENCY_COLOR = {
	stardust = Theme.Stardust,
	crystals = Theme.Crystals,
	spores = Color3.fromRGB(150, 235, 140),
	cryo = Color3.fromRGB(150, 215, 255),
	embers = Color3.fromRGB(255, 150, 70),
	volt = Color3.fromRGB(255, 235, 110),
	essence = Color3.fromRGB(230, 120, 255),
}

-- Vertical scrolling list that grows with its content.
function Kit.scroll(parent: Instance, size: UDim2, position: UDim2?, padding: number?): ScrollingFrame
	local sf = Theme.new("ScrollingFrame", {
		Name = "Scroll",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Theme.PaperDark,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(120, 130, 190),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}, { Theme.corner(12), Theme.padding(8) }) :: ScrollingFrame
	Theme.list(Enum.FillDirection.Vertical, padding or 6, Enum.HorizontalAlignment.Left).Parent = sf
	return sf
end

-- Scrolling grid.
function Kit.grid(parent: Instance, size: UDim2, position: UDim2?, cell: Vector2, gap: number?): ScrollingFrame
	local sf = Theme.new("ScrollingFrame", {
		Name = "Grid",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Theme.PaperDark,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(120, 130, 190),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}, { Theme.corner(12), Theme.padding(8) }) :: ScrollingFrame
	local g = gap or 8
	Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(cell.X, cell.Y), CellPadding = UDim2.fromOffset(g, g), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sf })
	return sf
end

function Kit.clear(container: Instance)
	for _, c in container:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- Coloured row card (the "upgrade row" of the reference games).
function Kit.row(parent: Instance, height: number, color: Color3, order: number?): Frame
	return Theme.new("Frame", {
		Name = "Row",
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order or 0,
		Parent = parent,
	}, { Theme.corner(12), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.06), Theme.darken(color, 0.34)) }) :: Frame
end

export type Tabs = { frame: Frame, select: (id: string) -> (), current: () -> string, buttons: { [string]: TextButton } }

-- Horizontal tab strip. entries = { { id, text, color, locked? } }.
function Kit.tabs(parent: Instance, size: UDim2, position: UDim2, entries: { { any } }, onSelect: (id: string) -> ()): Tabs
	local frame = Theme.new("Frame", { Name = "Tabs", Size = size, Position = position, BackgroundTransparency = 1, Parent = parent }, {
		Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	}) :: Frame
	local current = ""
	local buttons: { [string]: TextButton } = {}
	local colors: { [string]: Color3 } = {}
	local function select(id: string)
		current = id
		for bid, b in buttons do
			Theme.setButton(b, nil, if bid == id then colors[bid] else Theme.darken(colors[bid], 0.55))
		end
		onSelect(id)
	end
	local width = math.floor((size.X.Offset - 6 * (#entries - 1)) / #entries)
	for i, e in entries do
		local id = e[1] :: string
		colors[id] = e[3]
		buttons[id] = Theme.button({ Name = "Tab_" .. id, Text = e[2], Color = e[3], Size = UDim2.fromOffset(width, size.Y.Offset), LayoutOrder = i, Corner = 10, TextSize = 20, Parent = frame, OnClick = function()
			select(id)
		end })
	end
	return { frame = frame, select = select, current = function()
		return current
	end, buttons = buttons }
end

-- "123 ✨" for a cost in any currency.
function Kit.cost(currency: string, amount: number): string
	return Format.abbrev(amount) .. " " .. (Kit.CURRENCY_ICON[currency] or "")
end

-- Runs a Request and shows the server's message. Returns ok, result.
function Kit.request(action: string, payload: { [string]: any }?, okText: string?): (boolean, any)
	local ok, res = Net.request(action, payload)
	if ok then
		if okText then
			Toasts.show(okText, "success")
		elseif type(res) == "table" and type(res.key) == "string" then
			Toasts.show(Lang.msg(res), "success")
		end
		Theme.play("buy", 0.4, 1.15)
	elseif res ~= nil and res ~= "cooldown" then
		Toasts.show(Lang.msg(res), "error")
	end
	return ok, res
end

-- Toggle row: label + ON/OFF button.
function Kit.toggle(parent: Instance, labelKey: string, order: number, get: () -> boolean, set: (on: boolean) -> ()): (Frame, () -> ())
	local rowH = if Root.isTouch then 64 else 46
	local row = Theme.new("Frame", { Name = "Toggle", Size = UDim2.new(1, -8, 0, rowH), BackgroundColor3 = Theme.PaperLight, LayoutOrder = order, Parent = parent }, { Theme.corner(10), Theme.stroke(2) }) :: Frame
	Theme.text({ Key = labelKey, Size = UDim2.new(1, -120, 1, -10), Position = UDim2.fromOffset(12, 5), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = row })
	local b: TextButton
	local function paint()
		local on = get()
		Theme.setButton(b, Lang.t(if on then "hud.on" else "hud.off"), if on then Theme.Green else Theme.Grey)
	end
	b = Theme.button({ Name = "Switch", Text = "", Size = UDim2.fromOffset(92, if Root.isTouch then 56 else 36), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 20, Parent = row, OnClick = function()
		set(not get())
	end })
	paint()
	return row, paint
end

return Kit
