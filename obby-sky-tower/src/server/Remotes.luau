--!strict
-- Creates ReplicatedStorage.Remotes and routes Request(action, payload) to handlers, with a
-- per-player token-bucket rate limit. (Adapted from the huerta-tycoon Remotes service.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Security = require(ReplicatedStorage.Shared.Security)

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
local budget: { [Player]: Security.Bucket } = {}
local cooldowns: { [Player]: Security.Cooldowns } = {}
local intervals: { [string]: number } = {} -- action -> minimum seconds between two calls per player
local RATE = 8 -- requests per second sustained
local BURST = 16

-- Per-player minimum seconds between two calls of an action (tighter than the global bucket for
-- anything that moves money, teleports, opens a Roblox prompt or can be brute-forced).
local DEFAULT_INTERVALS: { [string]: number } = {
	BuyTrail = 0.3, BuyEffect = 0.3, BuyPet = 0.3, UpgradeShine = 0.3, BuyPower = 0.3,
	EquipTrail = 0.2, EquipEffect = 0.2, EquipPet = 0.2, SetLanguage = 0.5, SetSetting = 0.2,
	UseFreeSkip = 0.5, DevSkip = 0.5, Rebirth = 1.5, EnterPortal = 1, GoToLobby = 1, ReturnToCheckpoint = 1,
	PlacePocket = 1, TakePerk = 0.4, SetRoam = 0.4, Travel = 1.5,
	ClaimDaily = 1, RedeemCode = 2, ClaimGroupGift = 3, ClaimPlaytime = 0.5,
	WatchAd = 5, ShareLink = 3, GetState = 1,
}

-- `minInterval` (optional): server-side cooldown per player for this action. A call that comes
-- sooner is refused with err.slow_down and never reaches the handler.
function Remotes.handle(action: string, fn: Handler, minInterval: number?)
	handlers[action] = fn
	intervals[action] = minInterval or DEFAULT_INTERVALS[action]
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
	cooldowns[player] = nil
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if Security.str(action, Security.MAX_ACTION_LEN) == nil then
		return false, M("err.bad_request")
	end
	local now = os.clock()
	local b = budget[player]
	if not b then
		b = Security.newBucket(RATE, BURST, now)
		budget[player] = b
	end
	if not Security.take(b, now) then
		return false, M("err.slow_down")
	end
	local fn = handlers[action]
	if not fn then
		return false, M("err.unknown_action")
	end
	-- flat table of finite numbers / booleans / short strings, or nothing
	if not Security.payloadOk(payload) then
		return false, M("err.bad_request")
	end
	local interval = intervals[action]
	if interval then
		local cd = cooldowns[player]
		if not cd then
			cd = {}
			cooldowns[player] = cd
		end
		if not Security.cooldownOk(cd, action, now, interval) then
			return false, M("err.slow_down")
		end
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
