--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers,
-- with a per-player token-bucket rate limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Guard = require(ReplicatedStorage.Shared.Guard)
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
-- Minimum seconds between two calls of the same action by one player (0 = only the global
-- bucket applies). Keeps web-call handlers, code guessing and prompt spam in check.
local cooldowns: { [string]: number } = {
	GetState = 0.5,
	GetTables = 0.5,
	GetMatch = 0.25,
	GetBoards = 1,
	SetLanguage = 0.5,
	QuickPlay = 0.5,
	JoinTable = 0.5,
	LeaveTable = 0.3,
	CreatePrivate = 1,
	JoinPrivate = 0.6, -- room codes are 4 letters: no guessing at 12 per second
	PrivateOptions = 0.2,
	StartPrivate = 1,
	Challenge = 3,
	AnswerChallenge = 0.3,
	Buy = 0.3,
	Equip = 0.15,
	SetEmotes = 0.5,
	ClaimDaily = 0.5,
	ClaimGift = 0.3,
	RedeemCode = 1.5,
	ClaimQuest = 0.2,
	ClaimQuestBonus = 0.5,
	ClaimSeason = 0.2,
	ClaimSeasonAll = 0.5,
	ShareLink = 5, -- opens a Roblox prompt
	ClaimGroupGift = 3, -- web call
}
-- Weak keys: a request that lands in the instant between PlayerRemoving and the player
-- leaving cannot pin the Player in memory.
local budget: { [Player]: Guard.Bucket } = setmetatable({}, { __mode = "k" }) :: any
local lastUse: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local RATE = 12 -- requests per second sustained
local BURST = 30
local MAX_STRING = 128 -- longest string any legit payload carries
local MAX_ENTRIES = 64 -- most entries in a payload (or a list inside it)

-- Shallow check of a payload: no NaN / inf, no oversized strings, no huge lists. Handlers
-- still validate the meaning of every field; this is the common floor.
local function payloadOk(payload: any): boolean
	local n = 0
	for k, v in payload do
		n += 1
		if n > MAX_ENTRIES or (type(k) ~= "string" and type(k) ~= "number") then
			return false
		end
		if type(k) == "string" and #k > 32 then
			return false
		end
		local vt = type(v)
		if vt == "number" then
			if not Guard.isNumber(v) then
				return false
			end
		elseif vt == "string" then
			if #v > MAX_STRING then
				return false
			end
		elseif vt == "table" then
			local m = 0
			for _, x in v do
				m += 1
				if m > MAX_ENTRIES then
					return false
				end
				local xt = type(x)
				if xt == "table" or (xt == "string" and #x > MAX_STRING) or (xt == "number" and not Guard.isNumber(x)) then
					return false
				end
			end
		elseif vt ~= "boolean" then
			return false -- Instances, functions... are never part of a request
		end
	end
	return true
end
Remotes.payloadOk = payloadOk

function Remotes.handle(action: string, fn: Handler, cooldown: number?)
	handlers[action] = fn
	if cooldown then
		cooldowns[action] = cooldown
	end
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
	lastUse[player] = nil
end

-- Per-player tables still holding this player (leak check in the playtest).
function Remotes.tracked(player: Player): number
	return (if budget[player] then 1 else 0) + (if lastUse[player] then 1 else 0)
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	Remotes.stats.requestIn += 1
	-- a request that lands after PlayerRemoving must not re-create the per-player tables
	if not player.Parent then
		return false, M("msg.bad_request")
	end
	if type(action) ~= "string" or #action > 32 then
		return false, M("msg.bad_request")
	end
	local now = os.clock()
	local b = budget[player]
	if not b then
		b = Guard.newBucket(RATE, BURST, now)
		budget[player] = b
	end
	if not Guard.take(b, now, 1) then
		return false, M("msg.slow_down")
	end
	local fn = handlers[action]
	if not fn then
		return false, M("msg.unknown_action")
	end
	local gap = cooldowns[action] or 0
	if gap > 0 then
		local last = lastUse[player]
		if not last then
			last = {}
			lastUse[player] = last
		end
		if not Guard.cooldownReady(last, action, now, gap) then
			return false, M("msg.slow_down")
		end
	end
	if payload ~= nil and type(payload) ~= "table" then
		return false, M("msg.bad_request")
	end
	if payload ~= nil and not payloadOk(payload) then
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
