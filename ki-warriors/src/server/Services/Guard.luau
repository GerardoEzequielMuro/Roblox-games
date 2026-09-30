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

local Guard = {}

local STEP = 0.5
local lastGood: { [Player]: Vector3 } = {}
Guard.corrections = {} :: { [Player]: number }

function Guard.count(player: Player): number
	return Guard.corrections[player] or 0
end

function Guard.init()
	Players.PlayerRemoving:Connect(function(player)
		lastGood[player] = nil
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
					continue
				end
				-- fell off the planet: back to the plaza
				if pos.Y < Config.GroundY - 160 then
					Progression.placeOnSpawn(player)
					lastGood[player] = nil
					continue
				end
				local teleported = now - (Progression.teleportedAt[player] or -100) < 3
				local prev = lastGood[player]
				if prev and not teleported then
					local fly = Formulas.flySpeed(p.stats.agility, State.owns(player, "FastFlight")) * 1.7
					local allowed = math.max(fly, 170) * STEP * 1.6 + Config.Combat.dashDistance + 40
					if (pos - prev).Magnitude > allowed then
						Guard.corrections[player] = (Guard.corrections[player] or 0) + 1
						Progression.teleport(player, CFrame.new(prev))
						continue
					end
				end
				lastGood[player] = pos
			end
		end
	end)
end

return Guard
