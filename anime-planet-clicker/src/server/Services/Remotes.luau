--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers, with a
-- per-player token-bucket rate limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Security = require(ReplicatedStorage.Shared.Security)
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
export type Options = { interval: number?, exclusive: boolean? }
local handlers: { [string]: Handler } = {}
local options: { [string]: Options } = {}
local budget: { [Player]: Security.Bucket } = {}
local guards: { [Player]: Security.Guard } = {}
local RATE = 12 -- requests per second sustained
local BURST = 30

-- opts.interval: minimum seconds between two calls of this action by one player.
-- opts.exclusive: a second call while the first still yields (web calls) is refused.
function Remotes.handle(action: string, fn: Handler, opts: Options?)
	handlers[action] = fn
	if opts then
		options[action] = opts
	end
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
	guards[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if type(action) ~= "string" or #action > 40 then
		return false, M("msg.bad_request")
	end
	local now = os.clock()
	local b = budget[player]
	if not b then
		b = Security.newBucket(RATE, BURST, now)
		budget[player] = b
	end
	if not Security.take(b, now) then
		return false, M("msg.slow_down")
	end
	local fn = handlers[action]
	if not fn then
		return false, M("msg.unknown_action")
	end
	if payload ~= nil and (type(payload) ~= "table" or not Security.payloadOk(payload)) then
		return false, M("msg.bad_request")
	end
	local opts = options[action]
	local g: Security.Guard? = nil
	if opts then
		g = guards[player]
		if not g then
			g = Security.newGuard()
			guards[player] = g
		end
		if not Security.enter(g :: Security.Guard, action, now, opts.interval, opts.exclusive) then
			return false, M("msg.slow_down")
		end
	end
	local ok, a, b2 = pcall(fn, player, payload or {})
	if g then
		Security.leave(g, action)
	end
	if not ok then
		warn("[Remotes]", action, "error:", a)
		return false, M("msg.error")
	end
	return a, b2
end

folder.Parent = ReplicatedStorage

return Remotes
