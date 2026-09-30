--!strict
-- Client networking: Request wrapper, event hooks and the latest server State snapshot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(script.Parent.Lang)

local Net = {}

local folder = ReplicatedStorage:WaitForChild("Remotes")
local request = folder:WaitForChild("Request") :: RemoteFunction

-- Latest State pushed by the server (see server/Session.luau). Empty until the first push.
Net.state = {} :: { [string]: any }
Net.stateAt = 0
local changed = Instance.new("BindableEvent")
Net.changed = changed.Event -- fires (newState, previousState)

-- Returns ok, message (already translated; the server sends message keys), data.
function Net.request(action: string, payload: { [string]: any }?): (boolean, string?, any?)
	local ok, a, b, c = pcall(function()
		return request:InvokeServer(action, payload)
	end)
	if not ok then
		return false, Lang.t("err.connection")
	end
	return a == true, Lang.msg(b), c
end

function Net.on(eventName: string, fn: (...any) -> ())
	local e = folder:WaitForChild(eventName) :: RemoteEvent
	e.OnClientEvent:Connect(fn)
end

Net.on("State", function(s: { [string]: any })
	local prev = Net.state
	Net.state = s
	Net.stateAt = os.clock()
	changed:Fire(s, prev)
end)

-- Seconds played this session, extrapolated locally between pushes.
function Net.playSeconds(): number
	local base = Net.state.playSeconds
	if type(base) ~= "number" then
		return 0
	end
	return base + (os.clock() - Net.stateAt)
end

function Net.hasPass(name: string): boolean
	local passes = Net.state.passes
	return type(passes) == "table" and passes[name] == true
end

return Net
