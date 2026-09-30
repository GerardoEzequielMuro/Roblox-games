--!nonstrict
-- Codes: TextBox + Redeem.
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local Net = require(script.Parent.Net)
local Toasts = require(script.Parent.Toasts)

local CodesPanel = {}

function CodesPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "CodesPanel",
		Title = L("panel.codes"),
		Icon = "🎟️",
		Color = Theme.C.Teal,
		Size = UDim2.fromOffset(500, 330),
	})
	local body = p.content
	C.list(body, true, 14, Enum.HorizontalAlignment.Center)

	C.label(body, L("codes.enter"), UDim2.new(1, 0, 0, 30), {
		TextSize = 22,
		TextColor3 = Theme.C.Ink,
		Outline = false,
		LayoutOrder = 1,
	})

	local box: TextBox = C.new("TextBox", {
		Size = UDim2.new(1, -40, 0, 60),
		BackgroundColor3 = Theme.C.Card,
		Font = Theme.Font,
		TextSize = 28,
		TextColor3 = Theme.C.Ink,
		PlaceholderText = "",
		PlaceholderColor3 = Color3.fromRGB(180, 170, 160),
		Text = "",
		ClearTextOnFocus = false,
		LayoutOrder = 2,
		Parent = body,
	})
	C.corner(box, 16)
	I18n.set(box, "PlaceholderText", L("codes.placeholder"))
	C.fitText(box)
	C.stroke(box, 3, Theme.darken(Theme.C.Teal, 0.3))

	local function redeem()
		local code = string.upper((box.Text:gsub("%s+", "")))
		if code == "" then
			Toasts.show(L("codes.typeFirst"), "error")
			return
		end
		local ok = Net.request("RedeemCode", { code = code })
		if ok then
			box.Text = ""
		end
	end

	C.button({
		Parent = body,
		Text = L("codes.redeem"),
		TextSize = 28,
		Color = Theme.C.Green,
		Size = UDim2.fromOffset(260, 60),
		LayoutOrder = 3,
		OnClick = redeem,
	})
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)

	C.label(body, L("codes.follow"), UDim2.new(1, 0, 0, 20), {
		Font = Theme.FontAlt,
		TextSize = 14,
		TextColor3 = Theme.C.InkSoft,
		Outline = false,
		LayoutOrder = 4,
	})

	return { frame = p.frame, closeButton = p.close }
end

return CodesPanel
