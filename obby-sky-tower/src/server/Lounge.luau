--!strict
-- The Winner's Lounge (the terrace beyond the summit room of tower 1): free items for everybody
-- whose best stage is 100 or more. Catalogue and rules: Shared/Perks.
--   travel  : opens the teleporter panel; "Travel" moves your checkpoint to the start of a world
--             you have already reached (the run becomes assisted)
--   roam    : glider / cloud = explore mode. Pads don't count while it is on and switching it off
--             puts you back on your checkpoint, so it cannot be used to skip stages
--   ability : dash / triple jump, on or off (they count for progress; the run is assisted)
--   glow / jumpfx / trail / effect : cosmetics
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Perks = require(ReplicatedStorage.Shared.Perks)
local Security = require(ReplicatedStorage.Shared.Security)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Towers = require(script.Parent.Towers)
local Checkpoints = require(script.Parent.Checkpoints)
local Cosmetics = require(script.Parent.Cosmetics)

local Lounge = {}

local M = Remotes.M

-- Explore mode on / off. `id` = "glider" | "cloud" | "" (off).
function Lounge.setRoam(player: Player, id: string): (boolean, any?)
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return false
	end
	if id == "" then
		if s.roam then
			s.roam = nil
			player:SetAttribute("Roam", nil)
			Session.push(player)
			Checkpoints.teleportAsync(player) -- back where your progress is
			return true, M("msg.roam_off")
		end
		return true
	end
	local perk = Perks.get(id)
	if not perk or perk.kind ~= "roam" or not Perks.unlocked(p.best) or p.perks[id] ~= true then
		return false, M("err.lounge_locked")
	end
	s.roam = id
	player:SetAttribute("Roam", id)
	Session.assist(player, "roam")
	Session.push(player)
	return true, M("msg.roam_on")
end

-- Takes (or toggles) a lounge item.
function Lounge.take(player: Player, id: string): (boolean, any?)
	local p = Data.get(player)
	local s = Session.get(player)
	local perk = Perks.get(id)
	if not p or not s or not perk then
		return false, M("err.not_available")
	end
	if not Perks.unlocked(p.best) then
		return false, M("err.lounge_locked")
	end
	if perk.gift and not p.gifts[tostring(perk.gift)] then
		return false, M("err.need_gift", { n = perk.gift * 100 })
	end
	local name = M("perk." .. id .. ".name")
	if perk.kind == "travel" then
		Remotes.fire("OpenPanel", player, "travel")
		return true
	elseif perk.kind == "roam" then
		p.perks[id] = true
		if s.roam == id then
			return Lounge.setRoam(player, "")
		end
		return Lounge.setRoam(player, id)
	elseif perk.kind == "ability" then
		p.perks[id] = not (p.perks[id] == true)
		Cosmetics.applyCoils(player)
		Session.refreshHelp(player)
		Session.push(player)
		return true, M(if p.perks[id] then "msg.perk_on" else "msg.perk_off", { name = name })
	elseif perk.kind == "glow" or perk.kind == "jumpfx" then
		p.perks[perk.kind] = if p.perks[perk.kind] == id then "" else id
		Cosmetics.applyExtras(player)
		Session.push(player)
		return true, M(if p.perks[perk.kind] == id then "msg.perk_on" else "msg.perk_off", { name = name })
	elseif perk.kind == "trail" then
		p.trails[id] = true
		p.equippedTrail = id
		Cosmetics.applyTrail(player)
		Session.push(player)
		return true, M("msg.perk_on", { name = name })
	elseif perk.kind == "effect" then
		p.effects[id] = true
		p.equippedEffect = id
		Cosmetics.applyEffect(player)
		Session.push(player)
		return true, M("msg.perk_on", { name = name })
	end
	return false, M("err.not_available")
end

function Lounge.init()
	Towers.onBuilt(function(tower)
		for _, pr in tower.prompts do
			if pr.kind == "lounge" then
				pr.prompt.Triggered:Connect(function(player)
					local ok, msg = Lounge.take(player, pr.id)
					if msg then
						Remotes.notify(player, msg, if ok then "success" else "info")
					end
				end)
			end
		end
	end)
	Remotes.handle("TakePerk", function(player, payload)
		return Lounge.take(player, (Security.str(payload.id, 48) or ""))
	end)
	Remotes.handle("SetRoam", function(player, payload)
		return Lounge.setRoam(player, (Security.str(payload.id, 48) or ""))
	end)
	Remotes.handle("Travel", function(player, payload)
		local p = Data.get(player)
		local target = Security.int(payload.stage, 0, 1000)
		if not p or not target or not Perks.canTravel(p.best, target) then
			return false, M("err.travel_locked")
		end
		if target == 0 then
			-- the "Lobby" button: go there and KEEP the checkpoint (travel(0) used to save stage 0,
			-- wiping the player's progress)
			return Checkpoints.goToLobby(player)
		end
		Checkpoints.travel(player, target)
		return true
	end)
end

return Lounge
