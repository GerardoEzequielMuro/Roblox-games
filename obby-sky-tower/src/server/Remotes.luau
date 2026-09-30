--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers, with a
-- per-player token-bucket rate limit. (Adapted from the huerta-tycoon Remotes service.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local EVENT_NAMES = {
	"State",
	"Notify",
	"Celebrate",
	"CoinCollected",
	"OpenPanel",
	"Win",
	"OfferSkip", -- P0-1: death streak on a stage -> "Stuck?" card
	"LiveEventUpdate", -- P0-6: (current {id, endsAt}?, next {id, startsAt}?)
	"AskNotifications", -- P0-8: ask for the notification opt-in
	"Gift", -- a tower gift was granted: { id, stage }
	"TowerEnter", -- arrived at the base of a tower through a portal: { tower }
	"Shield", -- a shield absorbed a hit: { left }
}
local events: { [string]: RemoteEvent } = {}
for _, name in EVENT_NAMES do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	events[name] = e
end

local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder

-- Messages are never English sentences: they are { key, args } specs (see Shared/Locale) that each
-- client translates into its own language. Remotes.M builds one.
export type Msg = { key: string, args: { [string]: any }? }
function Remotes.M(key: string, args: { [string]: any }?): Msg
	return { key = key, args = args }
end
local M = Remotes.M

type Handler = (player: Player, payload: any) -> (boolean, any?, any?)
local handlers: { [string]: Handler } = {}
local budget: { [Player]: { tokens: number, t: number } } = {}
local RATE = 8 -- requests per second sustained
local BURST = 16

function Remotes.handle(action: string, fn: Handler)
	handlers[action] = fn
end

function Remotes.fire(name: string, player: Player, ...: any)
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	events[name]:FireAllClients(...)
end

-- Toast on one client. `msg` = Remotes.M(key, args) (or a list of them).
function Remotes.notify(player: Player, msg: any, kind: string?)
	events.Notify:FireClient(player, msg, kind or "info")
end

function Remotes.forget(player: Player)
	budget[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if type(action) ~= "string" then
		return false, M("err.bad_request")
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
		return false, M("err.slow_down")
	end
	b.tokens -= 1
	local fn = handlers[action]
	if not fn then
		return false, M("err.unknown_action")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return false, M("err.bad_request")
	end
	local ok, a, b2, c = pcall(fn, player, payload or {})
	if not ok then
		warn("[Remotes]", action, "error:", a)
		return false, M("err.generic")
	end
	return a, b2, c
end

folder.Parent = ReplicatedStorage

return Remotes
