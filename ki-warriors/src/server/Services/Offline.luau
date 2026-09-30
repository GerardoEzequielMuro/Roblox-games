--!strict
-- Offline training: while away, the selected stat keeps training at a fraction of the
-- auto-train rate (capped at 4 h, 8 h with VIP). On join the gain waits as offlinePending
-- and is claimed with ClaimOffline. An unclaimed amount is only replaced by a larger one.
-- The Time Chamber (pass, or earned with 2 ascensions) raises the rate and the cap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Combat = require(script.Parent.Combat)
local M = Locale.m

local Offline = {}

-- Time Chamber (pass, or 2 ascensions): faster offline training and a longer store.
function Offline.rate(player: Player): number
	return if State.owns(player, "TimeChamber") then Config.TimeChamber.rate else Config.Offline.rate
end

function Offline.capSeconds(player: Player): number
	local cap = if State.owns(player, "VIP") then Config.Offline.vipCapSeconds else Config.Offline.capSeconds
	if State.owns(player, "TimeChamber") then
		cap = math.max(cap, Config.TimeChamber.capSeconds)
	end
	return cap
end

-- Call after passes are loaded (uses the live per-rep gain, without a training zone).
function Offline.compute(player: Player, now: number?)
	local p = Data.get(player)
	if not p then
		return
	end
	local t = now or os.time()
	local seconds = math.clamp(t - (p.savedAt or t), 0, Offline.capSeconds(player))
	if seconds < Config.Offline.minSeconds then
		return
	end
	local stat = p.settings.stat
	local gain = State.gainPerRep(player, p, stat) * State.autoRate(player, p) * Offline.rate(player) * seconds
	local pending = p.offlinePending
	local current = if pending then pending[stat] or 0 else 0
	if gain > current then
		p.offlinePending = { [stat] = gain }
		p.offlineSeconds = seconds
		State.dirty(player)
	end
end

function Offline.onJoin(player: Player)
	Offline.compute(player)
end

-- Test hook: pretend the last save was `seconds` ago.
function Offline.fake(player: Player, seconds: number): any
	local p = Data.get(player)
	if not p then
		return nil
	end
	p.savedAt = os.time() - seconds
	p.offlinePending = nil
	Offline.compute(player)
	return { pending = p.offlinePending, seconds = p.offlineSeconds, cap = Offline.capSeconds(player), perRep = State.gainPerRep(player, p, p.settings.stat), rate = State.autoRate(player, p), offlineRate = Offline.rate(player) }
end

function Offline.init()
	State.extras.offline = function(_player, p)
		return { pending = p.offlinePending, seconds = p.offlineSeconds or 0 }
	end
	Remotes.handle("ClaimOffline", function(player)
		local p = Data.get(player)
		local pending = p and p.offlinePending
		if not p or not pending then
			return false, M("msg.nothing_to_claim")
		end
		local total = 0
		for stat, amount in pending do
			if p.stats[stat] then
				p.stats[stat] += amount
				total += amount
			end
		end
		p.offlinePending = nil
		p.offlineSeconds = 0
		local power = State.power(p)
		if power > p.bestPower then
			p.bestPower = power
			Combat.refreshForms(player)
		end
		State.dirty(player)
		return true, M("reward.offline", { n = Format.abbrev(total) })
	end)
end

return Offline
