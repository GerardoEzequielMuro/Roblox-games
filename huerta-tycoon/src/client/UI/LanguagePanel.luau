--!nonstrict
-- Language picker: flag + native name for every supported language. Switching re-renders the UI live and is
-- saved on the server (SetLanguage) so the next session starts in the same language.
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local Net = require(script.Parent.Net)

local LanguagePanel = {}

function LanguagePanel.choose(code: string)
	if not I18n.Locale.Supported[code] then
		return
	end
	I18n.setLang(code)
	Net.request("SetLanguage", { lang = code }, { quiet = true, silentOk = true })
end

function LanguagePanel.build(root: Instance)
	local langs = I18n.Locale.Languages
	local cols = 3
	local rows = math.ceil(#langs / cols)
	local cellW, cellH, gap = 204, 60, 10
	local p = C.panel(root, {
		Name = "LanguagePanel",
		Title = L("panel.language"),
		Icon = "🌐",
		Color = Theme.C.Blue,
		Size = UDim2.fromOffset(cols * cellW + (cols - 1) * gap + 40, 71 + 12 + 34 + rows * (cellH + gap) + 24),
	})
	C.label(p.content, L("lang.subtitle"), UDim2.new(1, 0, 0, 28), {
		TextSize = 20,
		TextColor3 = Theme.C.Ink,
		Outline = false,
	})
	local grid: Frame = C.new("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		Parent = p.content,
	})
	C.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellW, cellH),
		CellPadding = UDim2.fromOffset(gap, gap),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local buttons: { [string]: TextButton } = {}
	for i, l in langs do
		local btn = C.button({
			Name = "Lang_" .. l.code,
			Parent = grid,
			-- native names are never translated
			Text = l.flag .. " " .. l.name,
			TextSize = 22,
			Color = Theme.C.Grey,
			LayoutOrder = i,
			OnClick = function()
				LanguagePanel.choose(l.code)
			end,
		})
		local lbl = btn:FindFirstChild("Label")
		if lbl then
			lbl.AutoLocalize = false
		end
		buttons[l.code] = btn
	end

	local function refresh()
		for code, btn in buttons do
			C.setColor(btn, if code == I18n.lang then Theme.C.Green else Theme.C.Blue)
		end
	end
	I18n.onChanged(refresh)
	refresh()

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return LanguagePanel
