--!nonstrict
-- Bottom seed hotbar: one slot per owned seed type; tap or press 1-9 to select.
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Layout = require(script.Parent.Layout)

local Hotbar = {}
Hotbar.frame = nil :: Frame?

local SLOT_W, SLOT_H, GAP = 64, 70, 6
local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local ownedOrder: { string } = {}

local function ownedSeeds(): { string }
	local list = {}
	local d = State.data
	if d and type(d.seeds) == "table" then
		for id, n in d.seeds do
			if n > 0 and Config.SeedById[id] then
				table.insert(list, id)
			end
		end
	end
	table.sort(list, function(a, b)
		return (Config.SeedOrder[a] or 99) < (Config.SeedOrder[b] or 99)
	end)
	return list
end

function Hotbar.build(root: Instance)
	local frame: Frame = C.new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(260, SLOT_H + 10),
		BackgroundColor3 = Theme.C.Dark,
		BackgroundTransparency = 0.25,
		Parent = root,
	})
	Hotbar.frame = frame
	C.corner(frame, 20)
	C.stroke(frame, 3, Theme.C.Stroke, 0.3)

	local scroller: ScrollingFrame = C.new("ScrollingFrame", {
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(6, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		Parent = frame,
	})
	C.list(scroller, false, GAP, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	C.padding(scroller, 6, 4)

	local emptyLbl = C.label(frame, L("hotbar.empty"), UDim2.fromScale(1, 1), {
		TextSize = 20,
		Visible = false,
	})

	local selectedLbl = C.label(frame, "", UDim2.new(1, 0, 0, 18), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -1),
		TextSize = 14,
		TextWrapped = false,
	})

	-- PC: bottom-center, up to 720 wide. Touch: centered at x = 55% and at most 38% of the width, so it stays
	-- between the thumbstick (left 35%) and the jump button (right 25%); extra slots scroll horizontally.
	local function place()
		local n = #ownedOrder
		local want = n * (SLOT_W + GAP) + 28
		if Layout.stacked then
			local maxW = math.max(SLOT_W * 3 + 40, math.floor(Layout.canvas.X * 0.38))
			frame.AnchorPoint = Vector2.new(0.5, 1)
			frame.Position = UDim2.new(0.55, 0, 1, -8)
			frame.Size = UDim2.fromOffset(math.clamp(want, SLOT_W * 3 + 40, maxW), SLOT_H + 10)
		else
			frame.AnchorPoint = Vector2.new(0.5, 1)
			frame.Position = UDim2.new(0.5, 0, 1, -8)
			frame.Size = UDim2.fromOffset(math.clamp(want, 260, 510), SLOT_H + 10)
		end
	end
	Layout.onChanged(place)

	local slots: { [string]: { btn: TextButton, count: TextLabel, scale: UIScale, border: UIStroke } } = {}
	local signature = ""

	local function updateSelection()
		local sel = State.selectedSeed
		for id, s in slots do
			local on = id == sel
			s.border.Thickness = if on then 5 else 3
			s.border.Color = if on then Theme.C.White else Theme.darken(Theme.rarityColor(Config.SeedById[id].rarity), 0.35)
			C.tween(s.scale, 0.15, { Scale = if on then 1.1 else 1 }, Enum.EasingStyle.Back)
		end
		local seed = sel and Config.SeedById[sel]
		I18n.set(selectedLbl, "Text", if seed then L("hotbar.selected", { seed = { key = "seed." .. seed.id } }, Theme.seedEmoji(sel) .. " ") else "")
	end

	local function rebuild()
		for _, s in slots do
			s.btn:Destroy()
		end
		table.clear(slots)
		for i, id in ownedOrder do
			local seed = Config.SeedById[id]
			local rc = Theme.rarityColor(seed.rarity)
			local btn: TextButton = C.new("TextButton", {
				Name = id,
				Size = UDim2.fromOffset(SLOT_W, SLOT_H - 8),
				BackgroundColor3 = Theme.lighten(rc, 0.35),
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = i,
				Parent = scroller,
			})
			C.corner(btn, 14)
			local border = C.stroke(btn, 3, Theme.darken(rc, 0.35))
			C.gradient(btn, Color3.new(1, 1, 1), Theme.lighten(rc, 0.1), 90)
			local scale = C.new("UIScale", { Parent = btn })
			C.label(btn, Theme.seedEmoji(id), UDim2.new(1, 0, 1, -6), { TextSize = 30, Outline = false })
			local count = C.label(btn, "x0", UDim2.fromOffset(40, 22), {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -3, 1, -1),
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			if i <= 9 then
				C.label(btn, tostring(i), UDim2.fromOffset(20, 20), {
					Position = UDim2.fromOffset(4, 2),
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
				})
			end
			btn.Activated:Connect(function()
				State.setSelected(id)
			end)
			slots[id] = { btn = btn, count = count, scale = scale, border = border }
		end
		emptyLbl.Visible = #ownedOrder == 0
		place()
	end

	local function refresh()
		local list = ownedSeeds()
		local sig = table.concat(list, ",")
		if sig ~= signature then
			signature = sig
			ownedOrder = list
			rebuild()
		end
		for id, s in slots do
			s.count.Text = "x" .. tostring(State.seedCount(id))
		end
		-- keep a usable selection
		local sel = State.selectedSeed
		if (not sel or State.seedCount(sel) <= 0) and #ownedOrder > 0 then
			State.setSelected(ownedOrder[1])
		elseif sel and #ownedOrder == 0 then
			State.setSelected(nil)
		end
		updateSelection()
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
		elseif kind == "selected" then
			updateSelection()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		local idx = KEYS[input.KeyCode]
		if idx and ownedOrder[idx] then
			State.setSelected(ownedOrder[idx])
		end
	end)
end

return Hotbar
