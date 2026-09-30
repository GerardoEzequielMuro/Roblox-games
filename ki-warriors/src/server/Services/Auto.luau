--!strict
-- Server-driven helpers: auto-charge (refills ki while standing still) and auto-fight (attacks
-- the nearest enemy of the zone at a capped rate; the client only walks towards the target the
-- server picked). Auto-train lives in Training. None of them runs inside the PvP arena.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local State = require(script.Parent.State)
local Fighters = require(script.Parent.Fighters)
local Combat = require(script.Parent.Combat)

type Fighter = Fighters.Fighter
local A = Config.Auto
local C = Config.Combat

local Auto = {}

local nextAttack: { [Player]: number } = {}
local autoCharging: { [Player]: boolean } = {}
Auto.attacks = {} :: { [Player]: number } -- auto-attacks performed (playtest / rate checks)

local function nearestEnemy(f: Fighter, pos: Vector3): (Fighter?, number)
	local best: Fighter? = nil
	local bestD = A.fightRange
	for _, v in Fighters.list do
		if v.kind == "npc" and v.alive then
			local vp = Fighters.position(v)
			if vp then
				local d = (vp - pos).Magnitude - v.radius
				if d < bestD then
					best, bestD = v, d
				end
			end
		end
	end
	return best, bestD
end

local function setTarget(f: Fighter, pos: Vector3?)
	local char = f.char
	if char then
		char:SetAttribute("AutoTarget", pos)
	end
end

local function step(player: Player, now: number)
	local p = Data.get(player)
	local f = Fighters.ofPlayer(player)
	if not p or not f or not f.alive or not f.humanoid then
		return
	end
	local pos = Fighters.position(f)
	if not pos then
		return
	end
	if f.inArena then
		-- no helpers in PvP
		if autoCharging[player] then
			autoCharging[player] = nil
			Combat.setCharge(f, false)
		end
		setTarget(f, nil)
		return
	end
	local moving = f.humanoid.MoveDirection.Magnitude > 0.05
	local resting = autoCharging[player] == true

	-- auto-charge
	if p.settings.autoCharge then
		if resting then
			if f.ki >= A.chargeUntil or now - f.lastDamagedAt < 0.6 or not f.charging then
				autoCharging[player] = nil
				resting = false
				Combat.setCharge(f, false)
			end
		elseif f.ki < A.chargeBelow and not f.charging and not f.blocking and not f.beamStart and now - f.lastDamagedAt > 1.5 and (not moving or p.settings.autoFight) then
			autoCharging[player] = true
			resting = true
			Combat.setCharge(f, true)
		end
	elseif resting then
		autoCharging[player] = nil
		resting = false
		Combat.setCharge(f, false)
	end

	-- auto-fight
	if p.settings.autoFight and not resting then
		local target, dist = nearestEnemy(f, pos)
		if target then
			local tp = Fighters.position(target) :: Vector3
			setTarget(f, tp)
			if now >= (nextAttack[player] or 0) then
				local rate = A.fightPerSecond * (if State.owns(player, "TurboAuto") then Config.Train.turboMult else 1)
				local did = false
				if dist <= C.meleeRange - 1.5 then
					local aim = (tp - pos) * Vector3.new(1, 0, 1)
					did = Combat.melee(f, if aim.Magnitude > 0.1 then aim.Unit else nil) >= 0
				elseif f.ki >= C.blastCost + 0.02 then
					local dir = tp - (pos + Vector3.new(0, 0.6, 0))
					if dir.Magnitude > 0.1 then
						did = Combat.blast(f, dir.Unit)
					end
				end
				if did then
					nextAttack[player] = now + 1 / rate
					Auto.attacks[player] = (Auto.attacks[player] or 0) + 1
				end
			end
		else
			setTarget(f, nil)
		end
	else
		setTarget(f, nil)
	end
end

function Auto.init()
	Players.PlayerRemoving:Connect(function(player)
		nextAttack[player] = nil
		autoCharging[player] = nil
		Auto.attacks[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				if State.ready[player] then
					step(player, now)
				end
			end
		end
	end)
end

return Auto
