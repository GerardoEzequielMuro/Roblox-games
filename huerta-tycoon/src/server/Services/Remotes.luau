--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers, with per-player rate limiting.
-- i18n: handlers and notify() take Locale refs ({key, args}); they are translated here into each recipient's
-- language, so clients only ever receive text in their own language (plain strings still pass through).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locale = require(ReplicatedStorage.Shared.Locale)
local Validate = require(script.Parent.Parent.Security.Validate)
local RateLimit = require(script.Parent.Parent.Security.RateLimit)

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
local budget: { [Player]: RateLimit.Bucket } = {}
local cooldowns: { [Player]: RateLimit.Cooldowns } = {}
local RATE = 20 -- requests per second sustained
local BURST = 40
-- Minimum seconds between two calls of the same action by one player (on top of the global bucket). Only for
-- actions a real client calls rarely; the farming actions are limited by the bucket and by their own state checks.
local ACTION_COOLDOWN: { [string]: number } = {
	Hello = 0.5,
	GoHome = 1,
	SetLanguage = 0.5,
	ShareLink = 3,
	WatchAd = 3,
	ClaimGroupGift = 2,
	RedeemCode = 1,
}
Remotes.ACTION_COOLDOWN = ACTION_COOLDOWN

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
	cooldowns[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if type(action) ~= "string" or #action > Validate.MAX_ACTION_LEN then
		return false, Remotes.tr(player, Locale.ref("err.badRequest"))
	end
	if not player.Parent then
		return false -- already leaving: do not create per-player state that nobody would clean up
	end
	Remotes.requests += 1
	local now = os.clock()
	local b = budget[player]
	if not b then
		b = RateLimit.newBucket(BURST, now)
		budget[player] = b
	end
	if not RateLimit.take(b, now, RATE, BURST) then
		return false, Remotes.tr(player, Locale.ref("err.slowDown"))
	end
	local fn = handlers[action]
	if not fn then
		return false, Remotes.tr(player, Locale.ref("err.unknownAction"))
	end
	if not Validate.payload(payload) then
		return false, Remotes.tr(player, Locale.ref("err.badRequest"))
	end
	local gap = ACTION_COOLDOWN[action]
	if gap then
		local cd = cooldowns[player]
		if not cd then
			cd = {}
			cooldowns[player] = cd
		end
		if not RateLimit.ready(cd, action, now, gap) then
			return false, Remotes.tr(player, Locale.ref("err.slowDown"))
		end
	end
	local ok, a, b2, c = pcall(fn, player, payload or {})
	if not ok then
		warn("[Remotes]", action, "error:", a)
		return false, Remotes.tr(player, Locale.ref("err.generic"))
	end
	return a == true, Remotes.tr(player, b2), c
end

folder.Parent = ReplicatedStorage

return Remotes
