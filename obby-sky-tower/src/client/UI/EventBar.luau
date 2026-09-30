--!strict
-- Live-event pill under the run timer (P0-6): "2x Coins Weekend · ends in 1:02:03", or the
-- starter-pack x2 coins boost; plus a banner when an event starts.
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)
local Celebrate = require(script.Parent.Celebrate)

local EventBar = {}

type Active = { id: string, endsAt: number }
local current: Active? = nil
local upcoming: { id: string, startsAt: number }? = nil

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

function EventBar.current(): Active?
	return current
end

function EventBar.init()
	local W = 360
	local bar = Kit.region("EventBar", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 150), Vector2.new(W, 38))
	bar.Visible = false
	local body = Kit.frame(bar, UDim2.fromScale(1, 1), UDim2.new(), Kit.C.orange)
	body.Name = "Body"
	Kit.corner(body, 19)
	Kit.stroke(body, Kit.darker(Kit.C.orange, 0.45), 3)
	Kit.gradient(body, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 210, 160), 0)
	local label = Kit.bold(body, "", UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), Kit.C.white, nil, 24)
	label.Name = "Text"
	Kit.onLayout(function()
		local s = Hud.topScale or 1
		Kit.setScale(bar, s)
		bar.Position = UDim2.new(0.5, 0, 0, math.floor(Hud.EVENT_TOP * s))
	end)

	local function tick()
		local now = Workspace:GetServerTimeNow()
		local ev = current
		if ev and ev.endsAt <= now then
			ev = nil
		end
		local boostEnds = tonumber(Net.state.boostEndsAt) or 0
		if ev then
			body.BackgroundColor3 = if ev.id == "SkipSaleHour" then Kit.C.blue else Kit.C.orange
			Kit.setText(label, "event.ends", { name = { key = "event." .. ev.id }, time = clock(ev.endsAt - now) })
		elseif boostEnds > now then
			body.BackgroundColor3 = Kit.C.green
			Kit.setText(label, "boost.active", { time = clock(boostEnds - now) })
		end
		local show = ev ~= nil or boostEnds > now
		bar.Visible = show
		Hud.setEventBarVisible(show)
	end

	Net.on("LiveEventUpdate", function(cur: any, nxt: any)
		local prevId = current and current.id
		current = if type(cur) == "table" and type(cur.id) == "string" then cur else nil
		upcoming = if type(nxt) == "table" then nxt else nil
		if current and current.id ~= prevId then
			Celebrate.show(Lang.t("event.started", { name = { key = "event." .. current.id } }), nil, false)
		end
		tick()
	end)
	task.spawn(function()
		while true do
			tick()
			task.wait(1)
		end
	end)
end

function EventBar.upcoming()
	return upcoming
end

return EventBar
