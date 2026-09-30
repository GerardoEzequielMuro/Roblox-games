--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers, with a
-- per-player token-bucket rate limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

-- Server -> client events
local events: { [string]: RemoteEvent } = {}
for _, name in { "State", "Currency", "Notify", "Toast", "Hatched", "Reward", "LiveEventUpdate", "AskNotifications", "Quests", "Mine", "Node", "Pvp", "Tutorial" } do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	events[name] = e
end

-- Client -> server fire-and-forget events (each has its own rate limit in its service)
local function inbound(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	return e
end
Remotes.HitEvent = inbound("Hit") -- (node: number, count: number)
Remotes.ZapEvent = inbound("Zap") -- (targetId: number)

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

function Remotes.fire(name: string, player: Player, ...: any)
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	events[name]:FireAllClients(...)
end

-- message: a Locale message ({ key, args }); the client renders it in the player's language.
function Remotes.notify(player: Player, message: Locale.Message, kind: string?)
	events.Notify:FireClient(player, message, kind or "info")
end

function Remotes.forget(player: Player)
	budget[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
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
