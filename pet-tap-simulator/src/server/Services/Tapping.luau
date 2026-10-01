--!strict
-- Server-authoritative tapping. Clients send a tap COUNT every ~0.25s; the server clamps
-- it with a token bucket (Config.MaxTapsPerSecond) so autoclickers can't exceed the cap.
-- Also runs the Auto Tap pass, the Super Luck countdown and play time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Guard = require(script.Parent.Guard)

local Tapping = {}

type Bucket = { tokens: number, t: number }
local buckets: { [Player]: Bucket } = {}
local lastManual: { [Player]: number } = {} -- os.clock() of the last accepted manual tap
local tapValueCache: { [Player]: { v: number, t: number } } = {}
-- Tap EVENTS per second (the client sends one batch every Config.TapSendInterval): extra
-- batches beyond this are dropped before any work is done.
local eventLimiter = Guard.limiter(8, 16)

local function tapValue(player: Player, p: Data.Profile): number
	local c = tapValueCache[player]
	local now = os.clock()
	if c and now - c.t < 0.5 then
		return c.v
	end
	local v = State.tapValue(player, p)
	tapValueCache[player] = { v = v, t = now }
	return v
end

function Tapping.invalidate(player: Player)
	tapValueCache[player] = nil
end

function Tapping.forget(player: Player)
	buckets[player] = nil
	tapValueCache[player] = nil
	lastManual[player] = nil
	Guard.forget(eventLimiter, player)
end

-- Bookkeeping entries still held for this player (leak check).
function Tapping.tracked(player: Player): number
	local n = 0
	for _, t in { buckets, tapValueCache, lastManual, eventLimiter.buckets } :: { { [Player]: any } } do
		if t[player] ~= nil then
			n += 1
		end
	end
	return n
end

-- Auto taps per second right now (0 when the switch is off).
function Tapping.autoRate(player: Player, p: Data.Profile, now: number): number
	if not p.settings.autoTap then
		return 0
	end
	local last = lastManual[player] or State.sessionStart[player] or now
	return Formulas.autoTapRate(p.upgrades.AutoTap or 0, State.owns(player, "AutoTap"), now - last >= Config.AutoTapIdleSeconds)
end

local function onTap(player: Player, count: any)
	Remotes.stats.tapIn += 1
	if not Guard.num(count) or not player.Parent then
		return
	end
	count = math.floor(math.min(count, 10000))
	if count <= 0 then
		return
	end
	local p = Data.get(player)
	if not p or not State.ready[player] then
		return
	end
	local now = os.clock()
	if not Guard.allow(eventLimiter, player, now) then
		return
	end
	local b = buckets[player]
	local cap = Config.MaxTapsPerSecond + Config.TapBurst
	if not b then
		b = { tokens = cap, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(cap, b.tokens + (now - b.t) * Config.MaxTapsPerSecond)
	b.t = now
	local accepted = math.min(count, math.floor(b.tokens))
	if accepted <= 0 then
		return
	end
	b.tokens -= accepted
	lastManual[player] = now
	State.addTaps(player, accepted * tapValue(player, p))
	Hooks.fire("tapsAccepted", player, accepted)
end

function Tapping.init()
	Remotes.TapEvent.OnServerEvent:Connect(onTap)

	Remotes.handle("SetAutoTap", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		p.settings.autoTap = payload.on == true
		State.dirty(player)
		return true
	end)

	-- Auto Tap pass + timers
	task.spawn(function()
		local STEP = 0.2
		local acc = 0
		while true do
			task.wait(STEP)
			acc += STEP
			local wholeSecond = acc >= 1
			if wholeSecond then
				acc -= 1
			end
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				if p and State.ready[player] then
					local rate = Tapping.autoRate(player, p, os.clock())
					if rate > 0 then
						State.addTaps(player, rate * STEP * tapValue(player, p))
					end
					if wholeSecond then
						p.playTime += 1
						State.giftElapsed(player, p) -- keeps today's played time in the profile
						Hooks.fire("second", player, p)
						if p.tapBoostLeft > 0 then
							p.tapBoostLeft = math.max(0, p.tapBoostLeft - 1)
							if p.tapBoostLeft == 0 then
								Tapping.invalidate(player)
								State.dirty(player)
							end
						end
						if p.luckBoostLeft > 0 then
							p.luckBoostLeft = math.max(0, p.luckBoostLeft - 1)
							if p.luckBoostLeft == 0 then
								Remotes.notify(player, M("msg.super_luck_ended"), "info")
								State.dirty(player)
							end
						end
					end
				end
			end
		end
	end)
end

return Tapping
