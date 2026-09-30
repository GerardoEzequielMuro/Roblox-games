--!nonstrict
-- Rebirth: current rebirths, cost, bonus explanation, two-tap confirm.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)

local RebirthPanel = {}

function RebirthPanel.build(root: Instance)
	local p = C.panel(root, {
		Name = "RebirthPanel",
		Title = L("panel.rebirth"),
		Icon = "🔁",
		Color = Theme.C.Purple,
		Size = UDim2.fromOffset(540, 470),
	})
	local body: Frame = p.content
	C.list(body, true, 10, Enum.HorizontalAlignment.Center)

	local big = C.label(body, L("rebirth.count", { n = 0 }), UDim2.new(1, 0, 0, 50), {
		TextSize = 42,
		TextColor3 = Theme.C.Gold,
		Outline = 3,
		LayoutOrder = 1,
	})
	local bonus = C.label(body, "", UDim2.new(1, 0, 0, 30), {
		TextSize = 22,
		TextColor3 = Theme.C.Ink,
		RichText = true,
		Outline = false,
		LayoutOrder = 2,
	})
	C.label(
		body,
		L("rebirth.explain", { pct = math.floor(Config.RebirthBonus * 100) }),
		UDim2.new(1, -20, 0, 60),
		{
			Font = Theme.FontAlt,
			TextSize = 16,
			TextColor3 = Theme.C.InkSoft,
			Outline = false,
			LayoutOrder = 3,
		}
	)
	local bar = C.progressBar(body, UDim2.new(1, -40, 0, 34), Theme.C.Purple, { LayoutOrder = 4 })
	bar.label.TextSize = 18

	local armedUntil = 0
	local btn
	btn = C.button({
		Parent = body,
		Text = L("rebirth.button"),
		TextSize = 30,
		Color = Theme.C.Purple,
		Size = UDim2.fromOffset(300, 70),
		LayoutOrder = 5,
		OnClick = function()
			if os.clock() > armedUntil then
				armedUntil = os.clock() + 3
				C.setText(btn, L("rebirth.confirm"))
				C.setColor(btn, Theme.C.Red)
				task.delay(3.05, function()
					if os.clock() > armedUntil then
						C.setText(btn, L("rebirth.button"))
						C.setColor(btn, Theme.C.Purple)
					end
				end)
				return
			end
			armedUntil = 0
			C.setText(btn, L("rebirth.button"))
			C.setColor(btn, Theme.C.Purple)
			if Net.request("Rebirth") then
				require(script.Parent.Juice).confetti(40)
			end
		end,
	})

	local function refresh()
		local d = State.data
		if not d then
			return
		end
		local r = d.rebirths or 0
		local cost = d.rebirthCost or Formulas.rebirthCost(r)
		I18n.set(big, "Text", L("rebirth.count", { n = r }))
		I18n.set(bonus, "Text", L("rebirth.bonus", {
			now = string.format("<b>+%d%%</b>", math.floor(r * Config.RebirthBonus * 100)),
			next = string.format('<b><font color="#2E9B3A">+%d%%</font></b>', math.floor((r + 1) * Config.RebirthBonus * 100)),
		}))
		local cash = d.cash or 0
		bar.set(cash / math.max(1, cost))
		bar.label.Text = Format.cash(cash) .. " / " .. Format.cash(cost)
		C.setEnabled(btn, cash >= cost)
	end

	State.onChanged(function(kind)
		if kind == "state" then
			refresh()
		end
	end)

	return { frame = p.frame, closeButton = p.close, onOpen = refresh }
end

return RebirthPanel
