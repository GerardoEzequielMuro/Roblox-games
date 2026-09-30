--!strict
-- Planets (unlock / travel / spawn placement), techniques, gem upgrades, races and rebirth.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Collection = require(ReplicatedStorage.Shared.Collection)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Fighters = require(script.Parent.Fighters)
local M = Locale.m

local Progression = {}

-- Server teleports are whitelisted for the movement sanity check.
Progression.teleportedAt = {} :: { [Player]: number }

function Progression.spawnCFrame(planet: number): CFrame
	local cx, cy, cz = Config.planetCenter(planet)
	return CFrame.new(cx, cy + 6, cz + 18) * CFrame.Angles(0, math.rad(180), 0)
end

function Progression.teleport(player: Player, cf: CFrame)
	local char = player.Character
	if not char then
		return
	end
	Progression.teleportedAt[player] = os.clock()
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, 5)
		end)
		if char.Parent then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
			end
			char:PivotTo(cf)
			Progression.teleportedAt[player] = os.clock()
		end
	end)
end

function Progression.toPlanet(player: Player, planet: number)
	local p = Data.get(player)
	if not p then
		return
	end
	p.planet = planet
	local f = Fighters.ofPlayer(player)
	if f then
		f.invulnerableUntil = math.max(f.invulnerableUntil, os.clock() + 3)
	end
	Progression.teleport(player, Progression.spawnCFrame(planet))
	Hooks.fire("travel", player, planet)
	State.dirty(player)
end

function Progression.placeOnSpawn(player: Player)
	local p = Data.get(player)
	if p then
		Progression.teleport(player, Progression.spawnCFrame(p.planet))
	end
end

function Progression.doRebirth(player: Player): (boolean, any)
	local p = Data.get(player)
	if not p then
		return false, M("msg.error")
	end
	local need = Formulas.rebirthRequirement(p.rebirths)
	if State.power(p) < need then
		return false, M("msg.need_power")
	end
	p.rebirths += 1
	for _, s in Config.Stats do
		p.stats[s] = Config.StartStat
	end
	p.sparks = 0
	p.gear = 1
	p.planets = { 1 }
	p.bestPower = 0
	State.addGems(player, Config.Rebirth.gems)
	local f = Fighters.ofPlayer(player)
	if f then
		f.form = 0
		Fighters.setAttr(f, "Form", 0)
	end
	Progression.toPlanet(player, 1)
	Hooks.fire("rebirth", player, p.rebirths)
	Remotes.fireAll("Fx", "rebirth", { u = player.UserId, n = p.rebirths })
	State.dirty(player)
	return true, p.rebirths
end

function Progression.init()
	Remotes.handle("Travel", function(player, payload)
		local p = Data.get(player)
		local index = payload.planet
		if not p or type(index) ~= "number" or not Config.Planets[index] then
			return false, M("msg.bad_request")
		end
		local f = Fighters.ofPlayer(player)
		if not f or not f.alive then
			return false, M("msg.error")
		end
		if os.clock() - f.lastDamagedAt < 4 then
			return false, M("msg.in_combat")
		end
		local pl = Config.Planets[index]
		if not table.find(p.planets, index) then
			if math.max(State.power(p), p.bestPower) < pl.reqPower then
				return false, M("msg.need_power")
			end
			if not State.spendSparks(player, pl.cost) then
				return false, M("msg.need_sparks")
			end
			table.insert(p.planets, index)
			Remotes.fire("Combat", player, "planetUnlocked", index)
		end
		Progression.toPlanet(player, index)
		return true
	end)

	Remotes.handle("BuyTechnique", function(player, payload)
		local p = Data.get(player)
		local t = if type(payload.id) == "string" then Config.TechniqueById[payload.id] else nil
		if not p or not t then
			return false, M("msg.bad_request")
		end
		if p.techniques[t.id] then
			return false, M("msg.already_owned")
		end
		if math.max(State.power(p), p.bestPower) < t.reqPower then
			return false, M("msg.need_power")
		end
		-- dark / special techniques: beat the boss N times OR own the pass (earn or pay)
		if t.special and not Collection.specialOk(t.special, State.collectionCtx(player, p)) then
			return false, M("msg.need_special", { boss = M("npc." .. t.special.boss), n = t.special.count })
		end
		if not State.spendSparks(player, t.cost) then
			return false, M("msg.need_sparks")
		end
		p.techniques[t.id] = true
		Hooks.fire("techniqueBought", player, t.id)
		State.dirty(player)
		return true
	end)

	Remotes.handle("BuyUpgrade", function(player, payload)
		local p = Data.get(player)
		local u = if type(payload.id) == "string" then Config.UpgradeById[payload.id] else nil
		if not p or not u then
			return false, M("msg.bad_request")
		end
		local level = p.upgrades[u.id] or 0
		if level >= u.max then
			return false, M("msg.maxed")
		end
		if not State.spendGems(player, Formulas.upgradeCost(u.id, level)) then
			return false, M("msg.need_gems")
		end
		p.upgrades[u.id] = level + 1
		State.dirty(player)
		return true, level + 1
	end)

	Remotes.handle("SetRace", function(player, payload)
		local p = Data.get(player)
		local r = if type(payload.id) == "string" then Config.RaceById[payload.id] else nil
		if not p or not r then
			return false, M("msg.bad_request")
		end
		if p.race == r.id then
			return true
		end
		if p.raceChanges > 0 and not State.spendGems(player, Config.RaceChangeGems) then
			return false, M("msg.need_gems")
		end
		p.raceChanges += 1
		p.race = r.id
		local char = player.Character
		if char then
			char:SetAttribute("Race", r.id)
		end
		State.dirty(player)
		return true
	end)

	Remotes.handle("Rebirth", function(player)
		return Progression.doRebirth(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Progression.teleportedAt[player] = nil
	end)
end

return Progression
