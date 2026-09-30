--!strict
-- Client networking: remotes, the replicated profile snapshot, and change signals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request") :: RemoteFunction

local Net = {}

Net.state = nil :: { [string]: any }?
Net.receivedAt = os.clock()

local changed = Instance.new("BindableEvent")
Net.Changed = changed.Event

function Net.event(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end

-- Returns ok, result (result is a Locale message when ok == false).
function Net.request(action: string, payload: { [string]: any }?): (boolean, any)
	local ok, a, b = pcall(function()
		return Request:InvokeServer(action, payload)
	end)
	if not ok then
		return false, { key = "toast.connection" }
	end
	return a == true, b
end

-- Re-run every listener (e.g. after a language switch).
function Net.refresh()
	if Net.state then
		changed:Fire()
	end
end

function Net.get(key: string): any
	local s = Net.state
	return if s then s[key] else nil
end

function Net.owns(passKey: string): boolean
	local passes = Net.get("passes")
	return passes ~= nil and passes[passKey] == true
end

function Net.setting(key: string): any
	local s = Net.get("settings")
	return if s then s[key] else nil
end

-- Server clock (os.time based) corrected for when the snapshot arrived.
function Net.serverTime(): number
	local s = Net.state
	if not s then
		return os.time()
	end
	return s.serverTime + (os.clock() - Net.receivedAt)
end

Net.event("State").OnClientEvent:Connect(function(snapshot)
	Net.state = snapshot
	Net.receivedAt = os.clock()
	changed:Fire()
end)

-- Initial pull (the push may have happened before this script connected).
task.spawn(function()
	for _ = 1, 60 do
		if Net.state then
			return
		end
		local ok, snap = Net.request("GetState")
		if ok and snap and not Net.state then
			Net.state = snap
			Net.receivedAt = os.clock()
			changed:Fire()
			return
		end
		task.wait(0.5)
	end
end)

return Net
