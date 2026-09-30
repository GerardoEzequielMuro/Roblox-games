--!strict
-- Offline earnings: on join, time since the last save (capped at 8 h, 12 h with VIP) x tap
-- value x Config.OfflineTapsPerSecond becomes offlinePending, claimed with ClaimOffline.
-- An unclaimed amount is kept and only replaced by a larger one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local M = Locale.m

local Offline = {}

function Offline.capSeconds(player: Player): number
	return (if State.owns(player, "VIP") then Config.OfflineCapHoursVIP else Config.OfflineCapHours) * 3600
end

-- Call after passes and equipped pets are loaded (uses the live tap value).
function Offline.compute(player: Player, now: number?)
	local p = Data.get(player)
	if not p then
		return
	end
	local t = now or os.time()
	local cap = Offline.capSeconds(player)
	local seconds = math.clamp(t - (p.savedAt or t), 0, cap)
	if seconds < Config.OfflineMinSeconds then
		return
	end
	local amount = Formulas.offlineEarnings(State.tapValue(player, p), seconds, cap)
	if amount > (p.offlinePending or 0) then
		p.offlinePending = amount
		p.offlineSeconds = seconds
		State.dirty(player)
	end
end

-- Grants the pending taps (x mult). Returns the amount granted.
function Offline.claim(player: Player, mult: number?): number
	local p = Data.get(player)
	if not p or (p.offlinePending or 0) <= 0 then
		return 0
	end
	local amount = p.offlinePending * (mult or 1)
	p.offlinePending = 0
	p.offlineSeconds = 0
	State.addTaps(player, amount)
	State.dirty(player)
	return amount
end

function Offline.init()
	State.extras.offline = function(_player, p)
		return { pending = p.offlinePending or 0, seconds = p.offlineSeconds or 0 }
	end
	Remotes.handle("ClaimOffline", function(player)
		local amount = Offline.claim(player, 1)
		if amount <= 0 then
			return false, M("msg.nothing_to_claim")
		end
		return true, M("reward.taps", { n = Format.abbrev(amount) })
	end)
end

return Offline
