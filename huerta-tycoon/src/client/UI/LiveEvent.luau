--!nonstrict
-- Live event pill under the weather banner: "🎉 Harvest Festival · 12m 30s" while active, otherwise a small
-- "Next: Harvest Festival in 2d 4h" line.
local Format = require(game:GetService("ReplicatedStorage").Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local State = require(script.Parent.State)
local Layout = require(script.Parent.Layout)
local WildPatch = require(script.Parent.WildPatch)
local Weather = require(script.Parent.Weather)

local LiveEvent = {}

function LiveEvent.build(root: Instance)
	local pill: Frame = C.new("Frame", {
		Name = "EventPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(300, 24),
		BackgroundColor3 = Theme.C.Purple,
		BackgroundTransparency = 1,
		Parent = root,
	})
	C.round(pill)
	local stroke = C.stroke(pill, 2, Theme.darken(Theme.C.Purple, 0.4))
	local lbl = C.label(pill, "", UDim2.fromScale(1, 1), {
		TextSize = 14,
		TextWrapped = false,
	})
	C.padding(lbl, 1, 10)
	lbl:SetAttribute("MinText", 8) -- long lines shrink on tiny screens instead of being cut
	local fit = lbl:FindFirstChild("Fit")
	if fit then
		fit.MinTextSize = 8
	end
	Layout.onChanged(function()
		if Layout.compact then
			pill.AnchorPoint = Vector2.new(0, 0)
			pill.Position = UDim2.fromOffset(12, Weather.COMPACT_Y + Weather.CHIP_H + 4)
			pill.Size = UDim2.fromOffset(Weather.COMPACT_W, 24)
		elseif Layout.stacked then
			pill.AnchorPoint = Vector2.new(1, 0)
			pill.Position = UDim2.new(1, -12, 0, Weather.STACKED_Y + Weather.CHIP_H + 4)
			pill.Size = UDim2.fromOffset(Weather.CHIP_W - 30, 24)
		else
			pill.AnchorPoint = Vector2.new(1, 1)
			pill.Position = UDim2.new(1, -12, 1, -10 - Weather.CHIP_H - 4)
			pill.Size = UDim2.fromOffset(Weather.CHIP_W, 24)
		end
	end)

	local function tick()
		local ev = State.liveEvent
		local now = State.now()
		-- with no event running the pill alternates between the next event and the Wild Patch clock
		local showWild = State.data ~= nil and State.data.wild ~= nil and not ev.current and (ev.next == nil or math.floor(os.clock() / 5) % 2 == 1)
		if showWild then
			pill.BackgroundTransparency = 0.45
			stroke.Enabled = false
			lbl.TextSize = 13
			lbl.Text = WildPatch.hudText()
		elseif ev.current then
			pill.BackgroundTransparency = 0
			stroke.Enabled = true
			lbl.TextSize = 14
			lbl.Text = I18n.t("event.active", {
				name = { key = "event." .. ev.current.id .. ".name" },
				time = Format.time(math.max(0, ev.current.endsAt - now)),
			})
		elseif ev.next then
			pill.BackgroundTransparency = 0.45
			stroke.Enabled = false
			lbl.TextSize = 13
			lbl.Text = I18n.t("event.next", {
				name = { key = "event." .. ev.next.id .. ".name" },
				time = Format.time(math.max(0, ev.next.startsAt - now)),
			})
		else
			pill.BackgroundTransparency = 1
			stroke.Enabled = false
			lbl.Text = ""
		end
	end
	State.onChanged(function(kind)
		if kind == "event" then
			tick()
		end
	end)
	task.spawn(function()
		while true do
			tick()
			task.wait(0.5)
		end
	end)
end

return LiveEvent
