--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers,
-- with a per-player token-bucket rate limit. Adapted from Crop Kingdom.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Guard = require(script.Parent.Guard)
local M = Locale.m

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

-- Server -> client events
local events: { [string]: RemoteEvent } = {}
for _, name in { "State", "Currency", "Notify", "Toast", "Hatched", "Reward", "LiveEventUpdate", "AskNotifications", "Quests" } do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	events[name] = e
end

-- Client -> server tap batches (fire-and-forget, its own rate limit lives in Tapping)
local tapEvent = Instance.new("RemoteEvent")
tapEvent.Name = "Tap"
tapEvent.Parent = folder
Remotes.TapEvent = tapEvent

local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder

type Handler = (player: Player, payload: any) -> (boolean, any?)
local handlers: { [string]: Handler } = {}
local actionLimiters: { [string]: Guard.Limiter } = {}
local globalLimiter = Guard.limiter(12, 30) -- requests per second sustained / burst, all actions
local MAX_ACTION_LEN = 32
local MAX_PAYLOAD_KEYS = 256
-- Players that already left: a late call must not re-create their bookkeeping (leak).
local departed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- perSecond / burst: optional extra per-player limit for this action alone (expensive or
-- brute-forceable ones: codes, ads, group check, craft, delete...). The global limit still applies.
function Remotes.handle(action: string, fn: Handler, perSecond: number?, burst: number?)
	handlers[action] = fn
	if perSecond then
		actionLimiters[action] = Guard.limiter(perSecond, burst or math.max(1, perSecond * 2))
	end
end

-- Sets (or replaces) the per-player limit of an already registered action.
function Remotes.limit(action: string, perSecond: number, burst: number)
	actionLimiters[action] = Guard.limiter(perSecond, burst)
end

-- Traffic counters (remote calls since the server started); the playtest reads them.
Remotes.stats = { out = 0, tapIn = 0, requestIn = 0 }

function Remotes.fire(name: string, player: Player, ...: any)
	Remotes.stats.out += 1
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	Remotes.stats.out += 1
	events[name]:FireAllClients(...)
end

-- message: a Locale message ({ key, args }); the client renders it in the player's language.
function Remotes.notify(player: Player, message: Locale.Message, kind: string?)
	Remotes.stats.out += 1
	events.Notify:FireClient(player, message, kind or "info")
end

function Remotes.forget(player: Player)
	departed[player] = true
	Guard.forget(globalLimiter, player)
	for _, l in actionLimiters do
		Guard.forget(l, player)
	end
end

-- Limiter entries still held for this player (leak check).
function Remotes.tracked(player: Player): number
	local n = if globalLimiter.buckets[player] then 1 else 0
	for _, l in actionLimiters do
		if l.buckets[player] then
			n += 1
		end
	end
	return n
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	Remotes.stats.requestIn += 1
	if departed[player] or not player.Parent then
		return false, M("msg.error")
	end
	if not Guard.str(action, MAX_ACTION_LEN) then
		return false, M("msg.bad_request")
	end
	local now = os.clock()
	if not Guard.allow(globalLimiter, player, now) then
		return false, M("msg.slow_down")
	end
	local fn = handlers[action :: string]
	if not fn then
		return false, M("msg.unknown_action")
	end
	local limiter = actionLimiters[action :: string]
	if limiter and not Guard.allow(limiter, player, now) then
		return false, M("msg.slow_down")
	end
	if payload ~= nil and not Guard.smallTable(payload, MAX_PAYLOAD_KEYS) then
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
