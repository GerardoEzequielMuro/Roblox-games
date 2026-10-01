--!strict
-- The Power Core: the lobby clicker. Tapping it (or leaving Auto Charge on) fills a charge;
-- every full charge pays a fixed amount of cosmetic coins. It only works in the lobby, near
-- the core, and has nothing to do with a match. Server-authoritative: taps are rate limited
-- by a token bucket, auto taps are generated here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Guard = require(ReplicatedStorage.Shared.Guard)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Cosmetics = require(script.Parent.Cosmetics)
local QuestService = require(script.Parent.QuestService)

local CoreService = {}

local C = Config.Core
local corePos = Vector3.zero
local bucket: { [Player]: Guard.Bucket } = {}
-- Is the player sitting at a table? (set by Tables; the core is a lobby activity)
CoreService.isSeated = function(_player: Player): boolean
	return false
end

function CoreService.autoUnlocked(player: Player): boolean
	local p = Data.get(player)
	return p ~= nil and (p.level >= C.autoUnlockLevel or State.owns(player, "AutoCharge"))
end

function CoreService.inRange(player: Player): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	local d = hrp.Position - corePos
	return Vector3.new(d.X, 0, d.Z).Magnitude <= C.range
end

-- Adds taps to the player's core. Returns the coins paid.
function CoreService.apply(player: Player, taps: number, auto: boolean): number
	local p = Data.get(player)
	if not p or taps <= 0 then
		return 0
	end
	p.core.taps += taps
	local charges = p.core.taps // C.tapsPerCharge
	p.core.taps -= charges * C.tapsPerCharge
	local coins = 0
	if charges > 0 then
		p.core.charges += charges
		coins = charges * C.coinsPerCharge
		State.addCoins(player, coins)
		if p.core.charges >= C.auraAtCharges and Cosmetics.grant(player, "a_core") then
			Cosmetics.refresh(player, true)
			Remotes.fire("Unlock", player, "a_core")
		end
	end
	QuestService.add(player, "charge", taps)
	Remotes.fire("Core", player, { taps = p.core.taps, charges = p.core.charges, coins = coins, added = taps, auto = auto })
	return coins
end

function CoreService.forget(player: Player)
	bucket[player] = nil
end

function CoreService.tracked(player: Player): number
	return if bucket[player] then 1 else 0
end

function CoreService.init(position: Vector3)
	corePos = position

	State.extras.core = function(player, p)
		return { taps = p.core.taps, charges = p.core.charges, need = C.tapsPerCharge, autoUnlocked = CoreService.autoUnlocked(player), autoLevel = C.autoUnlockLevel }
	end

	Remotes.TapEvent.OnServerEvent:Connect(function(player: Player, count: any)
		if not Guard.isNumber(count) or count < 1 then
			return
		end
		if not player.Parent or not State.ready[player] or CoreService.isSeated(player) or not CoreService.inRange(player) then
			return
		end
		-- plausibility: no more than the best a hand can do (C.maxTapsPerSecond, small burst);
		-- the rest of a batch is dropped, not queued
		local now = os.clock()
		local b = bucket[player]
		if not b then
			b = Guard.newBucket(C.maxTapsPerSecond, C.burst, now)
			bucket[player] = b
		end
		local accepted = Guard.takeUpTo(b, now, count)
		if accepted < 1 then
			return
		end
		CoreService.apply(player, accepted, false)
	end)

	-- Auto Charge: one loop for everyone, once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				if p and State.ready[player] and p.settings.autoCharge and CoreService.autoUnlocked(player) and not CoreService.isSeated(player) and CoreService.inRange(player) then
					CoreService.apply(player, if State.owns(player, "VIP") then C.autoRateVip else C.autoRate, true)
				end
			end
		end
	end)
end

return CoreService
