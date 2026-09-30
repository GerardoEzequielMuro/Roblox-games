--!strict
-- Client networking: remotes, the replicated profile snapshot, and change signals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request") :: RemoteFunction

local Net = {}

Net.state = nil :: { [string]: any }?
Net.receivedAt = os.clock()

local changed = Instance.new("BindableEvent")
Net.Changed = changed.Event -- (kind: "full" | "currency")

function Net.event(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end

-- Returns ok, result (result is an error string when ok == false).
function Net.request(action: string, payload: { [string]: any }?): (boolean, any)
	local ok, a, b = pcall(function()
		return Request:InvokeServer(action, payload)
	end)
	if not ok then
		return false, { key = "toast.connection" }
	end
	return a == true, b
end

-- Fire-and-forget combat / training input.
local Act = Remotes:WaitForChild("Act") :: RemoteEvent
function Net.act(kind: string, arg: any?)
	Act:FireServer(kind, arg)
end

function Net.setting(key: string): any
	local s = Net.state
	return if s and s.settings then s.settings[key] else nil
end

-- Re-run every "full" listener (e.g. after a language switch).
function Net.refresh()
	if Net.state then
		changed:Fire("full")
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

Net.event("State").OnClientEvent:Connect(function(snapshot)
	Net.state = snapshot
	Net.receivedAt = os.clock()
	changed:Fire("full")
end)

Net.event("Numbers").OnClientEvent:Connect(function(c)
	local s = Net.state
	if s then
		for k, v in c do
			s[k] = v
		end
		changed:Fire("currency")
	end
end)

-- Initial pull (the push may have happened before this script connected).
task.spawn(function()
	for _ = 1, 40 do
		if Net.state then
			return
		end
		local ok, snap = Net.request("GetState")
		if ok and snap and not Net.state then
			Net.state = snap
			Net.receivedAt = os.clock()
			changed:Fire("full")
			return
		end
		task.wait(0.5)
	end
end)

return Net
