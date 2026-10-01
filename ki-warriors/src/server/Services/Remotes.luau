--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers,
-- with a per-player token-bucket rate limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Validate = require(script.Parent.Validate)
local M = Locale.m

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

-- Server -> client events
local events: { [string]: RemoteEvent } = {}
for _, name in { "State", "Numbers", "Notify", "Toast", "Reward", "LiveEventUpdate", "AskNotifications", "Quests", "Fx", "Combat", "Knock", "WorldBoss", "Arena" } do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	events[name] = e
end

-- Client -> server combat / training inputs (fire-and-forget; every kind has its own
-- cooldown or token bucket in Combat / Training)
local actEvent = Instance.new("RemoteEvent")
actEvent.Name = "Act"
actEvent.Parent = folder
Remotes.ActEvent = actEvent

local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder

type Handler = (player: Player, payload: any) -> (boolean, any?)
local handlers: { [string]: Handler } = {}
local budget: { [Player]: Validate.Bucket } = {}
local RATE = 12 -- requests per second sustained
local BURST = 30
-- Minimum seconds between two calls of the same action per player (on top of the bucket).
-- Actions that open web prompts, spend real resources or roll random results get a floor.
local ACTION_COOLDOWN: { [string]: number } = {
	GetState = 0.5,
	GetBoards = 5,
	SetLanguage = 0.5,
	Travel = 1.5,
	Rebirth = 2,
	SetRace = 1,
	RedeemCode = 1.5,
	ShareLink = 5,
	WatchAd = 3,
	SpinAura = 0.4,
	Wish = 2,
	ClaimOffline = 1,
	ClaimPassAll = 1,
	SetProtection = 1,
	EquipAura = 0.25,
	EquipSkin = 0.25,
	EquipMount = 0.25,
	UseSeed = 0.2,
	SkipStep = 1,
}
local lastCall: { [Player]: { [string]: number } } = {}

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
	lastCall[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if type(action) ~= "string" then
		return false, M("msg.bad_request")
	end
	if #action > 32 then
		return false, M("msg.bad_request")
	end
	local b = budget[player]
	local now = os.clock()
	if not b then
		b = Validate.newBucket(RATE, BURST, now)
		budget[player] = b
	end
	if not Validate.take(b, now, 1) then
		return false, M("msg.slow_down")
	end
	local fn = handlers[action]
	if not fn then
		return false, M("msg.unknown_action")
	end
	-- every payload is a flat table of primitives (no NaN/inf, no nesting, capped strings)
	if payload ~= nil and not Validate.payload(payload) then
		return false, M("msg.bad_request")
	end
	local floor = ACTION_COOLDOWN[action]
	if floor then
		local last = lastCall[player]
		if not last then
			last = {}
			lastCall[player] = last
		end
		if not Validate.cooldown(last, action, now, floor) then
			return false, M("msg.slow_down")
		end
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
