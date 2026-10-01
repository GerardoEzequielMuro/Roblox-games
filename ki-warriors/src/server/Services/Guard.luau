--!strict
-- Movement sanity (anti-teleport) and void rescue. Flight and dashes are real mechanics, so the
-- allowance is generous; what gets corrected is a jump no mechanic can produce (for example
-- warping to another planet without the gate). Server teleports are whitelisted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local State = require(script.Parent.State)
local Fighters = require(script.Parent.Fighters)
local Progression = require(script.Parent.Progression)
local Validate = require(script.Parent.Validate)

local Guard = {}

local STEP = 0.5
local lastGood: { [Player]: Vector3 } = {}
local lastAt: { [Player]: number } = {}
local budgets: { [Player]: Validate.MoveBudget } = {}
-- Sustained travel may exceed the best legit speed (boosted flight) by this factor before it
-- counts as a speed hack; dashes, knockback and latency spikes ride on the burst capacity.
local SPEED_SLACK = 1.4
Guard.corrections = {} :: { [Player]: number }

function Guard.count(player: Player): number
	return Guard.corrections[player] or 0
end

function Guard.init()
	Players.PlayerRemoving:Connect(function(player)
		lastGood[player] = nil
		lastAt[player] = nil
		budgets[player] = nil
		Guard.corrections[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(STEP)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				local f = Fighters.ofPlayer(player)
				local pos = f and Fighters.position(f)
				if not p or not f or not pos or not State.ready[player] or not f.alive then
					lastGood[player] = nil
					budgets[player] = nil
					continue
				end
				-- fell off the planet: back to the plaza
				if pos.Y < Config.GroundY - 160 then
					Progression.placeOnSpawn(player)
					lastGood[player] = nil
					budgets[player] = nil
					continue
				end
				local teleported = now - (Progression.teleportedAt[player] or -100) < 3
				local prev = lastGood[player]
				local fly = Formulas.flySpeed(p.stats.agility, State.owns(player, "FastFlight") and not f.inArena) * 1.7 -- boosted flight
				local maxSpeed = math.max(fly, Formulas.walkSpeed(p.stats.agility))
				local capacity = maxSpeed * 1.5 + Config.Combat.dashDistance * 2 + 90
				if teleported or not budgets[player] then
					budgets[player] = Validate.newMoveBudget(capacity)
				end
				if prev and not teleported then
					local fly0 = fly
					local allowed = math.max(fly0, 170) * STEP * 1.6 + Config.Combat.dashDistance + 40
					local delta = pos - prev
					-- one big jump (warp) or a sustained speed above anything a real setup reaches
					local dt = math.min(2, now - (lastAt[player] or now - STEP))
					local travelled = Vector3.new(delta.X, 0, delta.Z).Magnitude + math.max(0, delta.Y) -- falling is free
					local inBudget = Validate.moveStep(budgets[player], travelled, dt, maxSpeed, SPEED_SLACK, capacity)
					if delta.Magnitude > allowed or not inBudget then
						Guard.corrections[player] = (Guard.corrections[player] or 0) + 1
						Progression.teleport(player, CFrame.new(prev))
						lastAt[player] = now
						continue
					end
				end
				lastAt[player] = now
				lastGood[player] = pos
			end
		end
	end)
end

return Guard
