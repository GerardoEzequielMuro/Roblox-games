--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers,
-- with a per-player token-bucket rate limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

-- Server -> client events
local events: { [string]: RemoteEvent } = {}
for _, name in { "State", "Notify", "Match", "Tables", "Hand", "Result", "LevelUp", "LiveEventUpdate", "AskNotifications", "Emote", "Party", "Challenge", "Core", "Unlock" } do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	events[name] = e
end

-- Client -> server Power Core tap batches (fire-and-forget; rate limited in CoreService)
local tapEvent = Instance.new("RemoteEvent")
tapEvent.Name = "CoreTap"
tapEvent.Parent = folder
Remotes.TapEvent = tapEvent

local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder

type Handler = (player: Player, payload: any) -> (boolean, any?)
local handlers: { [string]: Handler } = {}
local budget: { [Player]: { tokens: number, t: number } } = {}
local RATE = 12 -- requests per second sustained
local BURST = 30

function Remotes.handle(action: string, fn: Handler)
	handlers[action] = fn
end

-- Traffic counters (remote calls since the server started); the playtest reads them.
Remotes.stats = { out = 0, tapIn = 0, requestIn = 0 }

function Remotes.fire(name: string, player: Player, ...: any)
	if not player:IsA("Player") or player.Parent == nil then
		return
	end
	Remotes.stats.out += 1
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	Remotes.stats.out += 1
	events[name]:FireAllClients(...)
end

-- message: a Locale message ({ key, args }); the client renders it in the player's language.
function Remotes.notify(player: Player, message: Locale.Message, kind: string?)
	if not player:IsA("Player") or player.Parent == nil then
		return
	end
	Remotes.stats.out += 1
	events.Notify:FireClient(player, message, kind or "info")
end

function Remotes.forget(player: Player)
	budget[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	Remotes.stats.requestIn += 1
	if type(action) ~= "string" then
		return false, M("msg.bad_request")
	end
	local b = budget[player]
	local now = os.clock()
	if not b then
		b = { tokens = BURST, t = now }
		budget[player] = b
	end
	b.tokens = math.min(BURST, b.tokens + (now - b.t) * RATE)
	b.t = now
	if b.tokens < 1 then
		return false, M("msg.slow_down")
	end
	b.tokens -= 1
	local fn = handlers[action]
	if not fn then
		return false, M("msg.unknown_action")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return false, M("msg.bad_request")
	end
	local ok, a, b2 = pcall(fn, player, payload or {})
	if not ok then
		warn("[Remotes]", action, "error:", a)
		return false, M("msg.error")
	end
	return a, b2
end

folder.Parent = ReplicatedStorage

return Remotes
