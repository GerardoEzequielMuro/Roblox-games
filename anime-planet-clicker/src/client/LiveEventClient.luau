--!strict
-- Client mirror of the live-event state (LiveEventUpdate), with a Changed signal.
local Net = require(script.Parent.Net)

local LiveEventClient = {}

LiveEventClient.data = nil :: { [string]: any }?
LiveEventClient.receivedAt = os.clock()
local changed = Instance.new("BindableEvent")
LiveEventClient.Changed = changed.Event -- (data, startedIds)

-- Server-clock "now" estimate.
function LiveEventClient.now(): number
	local d = LiveEventClient.data
	if not d then
		return os.time()
	end
	return d.serverTime + (os.clock() - LiveEventClient.receivedAt)
end

-- Active events that haven't ended yet (by the estimated server clock).
function LiveEventClient.active(): { { id: string, endsAt: number } }
	local d = LiveEventClient.data
	local out = {}
	if d and d.active then
		local now = LiveEventClient.now()
		for _, a in d.active do
			if a.endsAt > now then
				table.insert(out, a)
			end
		end
	end
	return out
end

Net.event("LiveEventUpdate").OnClientEvent:Connect(function(data)
	LiveEventClient.data = data
	LiveEventClient.receivedAt = os.clock()
	changed:Fire(data, data.started or {})
end)

return LiveEventClient
