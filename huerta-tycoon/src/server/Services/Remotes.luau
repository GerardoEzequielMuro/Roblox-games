--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers, with per-player rate limiting.
-- i18n: handlers and notify() take Locale refs ({key, args}); they are translated here into each recipient's
-- language, so clients only ever receive text in their own language (plain strings still pass through).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locale = require(ReplicatedStorage.Shared.Locale)

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local events: { [string]: RemoteEvent } = {}
for _, name in { "StateUpdate", "StockUpdate", "WeatherUpdate", "Notify", "HarvestFx", "LiveEventUpdate", "AskNotifications" } do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	events[name] = e
end

local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder

type Handler = (player: Player, payload: any) -> (boolean, any?, any?)
local handlers: { [string]: Handler } = {}
local budget: { [Player]: { tokens: number, t: number } } = {}
local RATE = 20 -- requests per second sustained
local BURST = 40

function Remotes.handle(action: string, fn: Handler)
	handlers[action] = fn
end

-- Traffic counters for the performance test (events fired per name, requests handled).
Remotes.sent = {} :: { [string]: number }
Remotes.requests = 0

function Remotes.fire(name: string, player: Player, ...: any)
	Remotes.sent[name] = (Remotes.sent[name] or 0) + 1
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	Remotes.sent[name] = (Remotes.sent[name] or 0) + #Players:GetPlayers()
	events[name]:FireAllClients(...)
end

-- Language of a player; Session replaces this with the profile/auto-detected language.
Remotes.langOf = function(player: Player): string
	local ok, id = pcall(function()
		return player.LocaleId
	end)
	return Locale.resolve(if ok then id else nil)
end

function Remotes.tr(player: Player, msg: any): string?
	return Locale.tr(Remotes.langOf(player), msg)
end

-- msg: Locale ref or plain string
function Remotes.notify(player: Player, msg: any, kind: string?)
	Remotes.sent.Notify = (Remotes.sent.Notify or 0) + 1
	events.Notify:FireClient(player, Remotes.tr(player, msg), kind or "info")
end

-- Server-wide message, translated per recipient.
function Remotes.notifyAll(msg: any, kind: string?)
	for _, player in Players:GetPlayers() do
		Remotes.notify(player, msg, kind)
	end
end

function Remotes.forget(player: Player)
	budget[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if type(action) ~= "string" then
		return false, Remotes.tr(player, Locale.ref("err.badRequest"))
	end
	Remotes.requests += 1
	local b = budget[player]
	local now = os.clock()
	if not b then
		b = { tokens = BURST, t = now }
		budget[player] = b
	end
	b.tokens = math.min(BURST, b.tokens + (now - b.t) * RATE)
	b.t = now
	if b.tokens < 1 then
		return false, Remotes.tr(player, Locale.ref("err.slowDown"))
	end
	b.tokens -= 1
	local fn = handlers[action]
	if not fn then
		return false, Remotes.tr(player, Locale.ref("err.unknownAction"))
	end
	if payload ~= nil and type(payload) ~= "table" then
		return false, Remotes.tr(player, Locale.ref("err.badRequest"))
	end
	local ok, a, b2, c = pcall(fn, player, payload or {})
	if not ok then
		warn("[Remotes]", action, "error:", a)
		return false, Remotes.tr(player, Locale.ref("err.generic"))
	end
	return a, Remotes.tr(player, b2), c
end

folder.Parent = ReplicatedStorage

return Remotes
