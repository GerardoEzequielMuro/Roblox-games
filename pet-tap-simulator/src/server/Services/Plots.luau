--!strict
-- Pet Park: every player gets a plot behind the spawn plaza. Their equipped pets stand on
-- its pedestals (drawn by each client: ParkFx) and the chest holds what the pets collected
-- while the player was away - the same offline earnings as before, now something you can
-- walk up to, see and open. Nothing new is earned here, so the economy is unchanged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Format = require(ReplicatedStorage.Shared.Format)
local M = Locale.m
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Offline = require(script.Parent.Offline)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

local Plots = {}

local plots: { WorldBuilder.Plot } = {}
local owners: { [number]: Player } = {}

function Plots.of(player: Player): number?
	local i = player:GetAttribute("Plot")
	return if type(i) == "number" then i else nil
end

-- Gives the player the first free plot (none left: they simply have no plot this session).
function Plots.assign(player: Player): number?
	if Plots.of(player) then
		return Plots.of(player)
	end
	for i, plot in plots do
		if not owners[i] then
			owners[i] = player
			plot.model:SetAttribute("OwnerId", player.UserId)
			plot.model:SetAttribute("OwnerName", player.DisplayName)
			player:SetAttribute("Plot", i)
			return i
		end
	end
	return nil
end

function Plots.release(player: Player)
	for i, owner in owners do
		if owner == player then
			owners[i] = nil
			plots[i].model:SetAttribute("OwnerId", 0)
			plots[i].model:SetAttribute("OwnerName", "")
		end
	end
end

-- Plots in use (leak check in the playtest).
function Plots.used(): number
	local n = 0
	for _ in owners do
		n += 1
	end
	return n
end

-- Opens the player's own chest. Returns ok, message.
function Plots.collect(player: Player, index: number): (boolean, Locale.Message)
	if owners[index] ~= player then
		return false, M("msg.not_your_chest")
	end
	local amount = Offline.claim(player, 1)
	if amount <= 0 then
		return false, M("msg.nothing_to_claim")
	end
	return true, M("reward.taps", { n = Format.abbrev(amount) })
end

function Plots.init(list: { WorldBuilder.Plot })
	plots = list
	for i, plot in plots do
		local prompt = plot.chest:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				local ok, msg = Plots.collect(player, i)
				Remotes.notify(player, msg, if ok then "success" else "info")
			end)
		end
	end

	Remotes.handle("GoPark", function(player)
		local i = Plots.of(player)
		local plot = if i then plots[i] else nil
		local char = player.Character
		if not plot or not char then
			return false, M("msg.no_plot")
		end
		pcall(function()
			player:RequestStreamAroundAsync(plot.spawn.Position, 2)
		end)
		if char.Parent then
			char:PivotTo(plot.spawn)
		end
		return true
	end)

	State.extras.plot = function(player, _p)
		return Plots.of(player) or 0
	end
end

return Plots
