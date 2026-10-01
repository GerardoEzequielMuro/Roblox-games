--!strict
-- Shop zones on the way up (one at the entrance of every world): pedestals that sell advantages
-- for coins. Catalogue and purchase rules: Shared/Powerups (pure, unit-tested). This module takes
-- the payment on the saved profile, applies the effect and makes the run "assisted" (not ranked).
--
--   speed / gravity / doublejump / magnet : timed (the end time is saved, so they survive a rejoin)
--   shield  : charges. A kill brick / laser / lava hit spends one instead of killing you
--   pocket  : charges. "Place" drops a portable checkpoint where you stand (until the next save)
--   skip    : instant, skips the next stage
-- Nothing here is random and nothing is sold for Robux directly: the Robux versions are the game
-- passes (SpeedCoil, GravityCoil, DoubleJump, InfiniteRevives) and the SkipStage product.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Powerups = require(ReplicatedStorage.Shared.Powerups)
local Security = require(ReplicatedStorage.Shared.Security)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Towers = require(script.Parent.Towers)
local Obstacles = require(script.Parent.Obstacles)
local Checkpoints = require(script.Parent.Checkpoints)
local Cosmetics = require(script.Parent.Cosmetics)

local Shops = {}

Shops.SHIELD_SECONDS = 1.6 -- grace after a shield absorbs a hit (time to step off the kill brick)
Shops.MAGNET_RADIUS = 16
Shops.MAGNET_TICK = 0.3

local M = Remotes.M

-- Buys `id` with coins for `player`. Returns ok, message.
function Shops.buy(player: Player, id: string): (boolean, any?)
	local p = Data.get(player)
	local s = Session.get(player)
	local item = Powerups.get(id)
	if not p or not s or not item then
		return false, M("err.not_for_sale")
	end
	if id == "skip" and not Checkpoints.canSkip(player) then
		return false, M("err.at_top") -- nothing to skip here: don't take the coins
	end
	local ok, err = Powerups.buy(p :: any, id, os.time())
	if not ok then
		return false, M(err or "err.generic")
	end
	if id == "skip" then
		Checkpoints.skip(player, 1, "coins")
	elseif id == "shield" or id == "pocket" then
		Session.push(player)
	else
		Cosmetics.applyCoils(player)
		Session.refreshHelp(player)
		Session.push(player)
	end
	return true, M("msg.bought", { name = M("power." .. id .. ".name") })
end

-- Portable checkpoint: where the character stands right now, if it is standing on something.
function Shops.placePocket(player: Player): (boolean, any?)
	local p = Data.get(player)
	local s = Session.get(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not p or not s or not char or not root or not hum or hum.Health <= 0 then
		return false, M("err.not_available")
	end
	if s.inLobby or s.roam or math.max(s.at, p.stage) <= 0 then
		return false, M("err.pocket_here")
	end
	if not Checkpoints.nearProgress(player, 100) then
		return false, M("err.pocket_here") -- not near your pad: no portable checkpoint out there
	end
	local unlimited = Session.hasPass(player, "InfiniteRevives")
	if not unlimited and (p.charges.pocket or 0) <= 0 then
		return false, M("err.no_charges")
	end
	-- must be standing on solid ground that is not a hazard or something that moves away
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
	if not hit or not hit.Instance.CanCollide or hit.Instance.Name == "Kill" or hit.Instance.Name == "Lava" then
		return false, M("err.pocket_here")
	end
	if not unlimited then
		Powerups.use(p :: any, "pocket")
	end
	local pos = root.Position + Vector3.new(0, 0.5, 0)
	p.pocket = { stage = p.stage, at = math.max(s.at, p.stage), x = pos.X, y = pos.Y, z = pos.Z }
	Session.assist(player, "powerup")
	Session.push(player)
	return true, M("msg.pocket_placed")
end

function Shops.init()
	-- a shield turns a lethal hit into a short grace period
	Obstacles.absorb = function(player: Player): boolean
		local p = Data.get(player)
		local s = Session.get(player)
		if not p or not s or not Powerups.use(p :: any, "shield") then
			return false
		end
		s.shieldUntil = os.clock() + Shops.SHIELD_SECONDS
		Session.assist(player, "powerup")
		Remotes.fire("Shield", player, { left = p.charges.shield or 0 })
		Session.push(player)
		return true
	end

	Towers.onBuilt(function(tower)
		for _, pr in tower.prompts do
			if pr.kind == "shop" then
				pr.prompt.Triggered:Connect(function(player)
					local ok, msg = Shops.buy(player, pr.id)
					Remotes.notify(player, msg, if ok then "success" else "error")
				end)
			end
		end
	end)

	Remotes.handle("BuyPower", function(player, payload)
		return Shops.buy(player, (Security.str(payload.id, 48) or ""))
	end)
	Remotes.handle("PlacePocket", function(player)
		return Shops.placePocket(player)
	end)

	-- one loop for every timed effect: expiry (1 s) and the coin magnet (0.3 s)
	task.spawn(function()
		local sinceExpiry = 0
		while true do
			task.wait(Shops.MAGNET_TICK)
			sinceExpiry += Shops.MAGNET_TICK
			local now = os.time()
			local checkExpiry = sinceExpiry >= 1
			if checkExpiry then
				sinceExpiry = 0
			end
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				local s = Session.get(player)
				if not p or not s then
					continue
				end
				if checkExpiry and Powerups.sweep(p.boosts, now) > 0 then
					Cosmetics.applyCoils(player)
					Session.push(player)
				end
				if Powerups.active(p.boosts, "magnet", now) and not s.inLobby then
					local here = math.max(s.at, p.stage)
					for stage = here, here + 2 do
						for _, coin in Obstacles.coinsOf(stage) do
							Obstacles.collectCoin(player, coin, Shops.MAGNET_RADIUS)
						end
					end
				end
			end
		end
	end)
end

return Shops
