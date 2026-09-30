--!strict
-- Tools, upgrades (every system that is "levels for a currency"), Relics, rebirth, warping
-- between galaxies, walk speed, the auto toggles, settings and the first-minute tutorial.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Pets = require(script.Parent.Pets)
local Mining = require(script.Parent.Mining)
local Rewards = require(script.Parent.Rewards)
local Hooks = require(script.Parent.Hooks)

local Progression = {}

local rng = Random.new()

function Progression.applyWalkSpeed(player: Player)
	local p = Data.get(player)
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if p and hum then
		local speed = Formulas.walkSpeed(State.stats(player, p), State.inArena[player] == true)
		if math.abs(hum.WalkSpeed - speed) > 0.01 then
			hum.WalkSpeed = speed
		end
	end
end

function Progression.teleportTo(player: Player, point: { number })
	local char = player.Character
	if not char then
		return
	end
	local pos = Vector3.new(point[1], point[2], point[3])
	pcall(function()
		player:RequestStreamAroundAsync(pos, 5)
	end)
	if player.Character == char then
		char:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.pi, 0)) -- face north, towards the planets
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

---------------------------------------------------------------------------
-- Tools and upgrades
---------------------------------------------------------------------------
function Progression.buyTool(player: Player, toolId: string): (boolean, any)
	local p = Data.get(player)
	local tool = Config.ToolById[toolId]
	if not p or not tool then
		return false, M("msg.unknown_tool")
	end
	local index = Config.ToolIndex[toolId]
	if index <= (Config.ToolIndex[p.tool] or 1) then
		return false, M("msg.tool_owned")
	end
	if not State.hasZone(p, tool.zone) then
		return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[tool.zone].id) })
	end
	if not State.spendStardust(player, tool.cost) then
		return false, M("msg.not_enough", { item = M("currency.stardust") })
	end
	p.tool = toolId
	State.dirty(player)
	Hooks.fire("toolBought", player, toolId)
	return true
end

function Progression.upgrade(player: Player, id: string): (boolean, any)
	local p = Data.get(player)
	local u = Config.UpgradeById[id]
	if not p or not u then
		return false, M("msg.unknown_upgrade")
	end
	local system = Config.SystemById[u.system]
	if not State.hasZone(p, system.zone) then
		return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[system.zone].id) })
	end
	local level = p.upgrades[id] or 0
	if level >= u.max then
		return false, M("msg.max_level")
	end
	local cost = Formulas.upgradeCost(id, level)
	if not State.spend(player, u.currency, cost) then
		return false, M("msg.not_enough", { item = M(if Config.MaterialZone[u.currency] then "material." .. u.currency else "currency." .. u.currency) })
	end
	p.upgrades[id] = level + 1
	State.dirty(player)
	if id == "MoveSpeed" then
		Progression.applyWalkSpeed(player)
	end
	Hooks.fire("upgraded", player, id)
	return true, level + 1
end

-- Verdant Nebula: one Relic roll.
function Progression.rollRelic(player: Player): (boolean, any)
	local p = Data.get(player)
	if not p then
		return false
	end
	local system = Config.SystemById.relics
	if not State.hasZone(p, system.zone) then
		return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[system.zone].id) })
	end
	if not State.spend(player, system.material, Config.RelicCost) then
		return false, M("msg.not_enough", { item = M("material." .. system.material) })
	end
	local stat = Config.RelicStats[rng:NextInteger(1, #Config.RelicStats)]
	local grade = Formulas.rollTable(Config.RelicGrades, rng:NextNumber())
	local relic = p.relics[stat]
	local upgraded = false
	if grade > relic.grade then
		relic.grade = grade
		relic.dust = 0
		upgraded = true
	elseif relic.grade < #Config.RelicGrades then
		relic.dust += 1
		if relic.dust >= Config.RelicDustPerGrade then
			relic.dust = 0
			relic.grade += 1
			upgraded = true
		end
	else
		-- a maxed relic can't take dust: the roll is refunded
		State.addMaterial(player, system.material, Config.RelicCost)
	end
	State.dirty(player)
	return true, { stat = stat, grade = grade, upgraded = upgraded, now = relic.grade, dust = relic.dust }
end

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
function Progression.rebirth(player: Player): (boolean, any)
	local p = Data.get(player)
	if not p then
		return false
	end
	local cost = Formulas.rebirthCost(p.rebirths)
	if p.stardust < cost then
		return false, M("msg.not_enough", { item = M("currency.stardust") })
	end
	local crystals = Formulas.rebirthCrystals(p.rebirths)
	p.rebirths += 1
	p.stardust = 0
	p.cargo.count = 0
	p.cargo.value = 0
	State.transit[player] = nil
	p.tool = Config.Tools[1].id
	for _, u in Config.Upgrades do
		if u.reset then
			p.upgrades[u.id] = 0
		end
	end
	State.addCrystals(player, crystals)
	Mining.reset(player)
	State.dirty(player)
	Hooks.fire("rebirth", player)
	return true, M("msg.rebirth_done", { n = p.rebirths, crystals = crystals })
end

---------------------------------------------------------------------------
-- Autos that spend Stardust (called once a second by the Auto service)
---------------------------------------------------------------------------
function Progression.autoUpgrade(player: Player, p: Data.Profile)
	-- best tool the wallet can pay for
	local current = Config.ToolIndex[p.tool] or 1
	for i = #Config.Tools, current + 1, -1 do
		local tool = Config.Tools[i]
		if State.hasZone(p, tool.zone) and p.stardust >= tool.cost then
			Progression.buyTool(player, tool.id)
			break
		end
	end
	for _ = 1, 10 do
		local level = p.upgrades.Power or 0
		if level >= Config.UpgradeById.Power.max or p.stardust < Formulas.upgradeCost("Power", level) then
			break
		end
		Progression.upgrade(player, "Power")
	end
end

function Progression.autoRebirth(player: Player, p: Data.Profile)
	if p.stardust >= Formulas.rebirthCost(p.rebirths) then
		local ok, msg = Progression.rebirth(player)
		if ok then
			Remotes.notify(player, msg, "success")
		end
	end
end

---------------------------------------------------------------------------
-- Tutorial
---------------------------------------------------------------------------
local function satisfied(player: Player, p: Data.Profile, id: string): boolean
	if id == "tool" then
		return (Config.ToolIndex[p.tool] or 1) > 1
	elseif id == "auto" then
		return p.auto.mine == true
	elseif id == "capsule" then
		return p.totalOpened > 0
	end
	return false
end

function Progression.tutorialAdvance(player: Player, id: string)
	local p = Data.get(player)
	if not p then
		return
	end
	local step = Config.Tutorial[p.tutorial]
	if not step or step.id ~= id then
		return
	end
	while true do
		local done = Config.Tutorial[p.tutorial]
		p.tutorial += 1
		local text = Rewards.grant(player, done.reward)
		Remotes.fire("Tutorial", player, { done = done.id, step = p.tutorial, reward = text })
		local nextStep = Config.Tutorial[p.tutorial]
		if not nextStep or not satisfied(player, p, nextStep.id) then
			break
		end
	end
	State.dirty(player)
end

function Progression.init()
	Remotes.handle("BuyTool", function(player, payload)
		if type(payload.id) ~= "string" then
			return false, M("msg.unknown_tool")
		end
		return Progression.buyTool(player, payload.id)
	end)

	Remotes.handle("Upgrade", function(player, payload)
		if type(payload.id) ~= "string" then
			return false, M("msg.unknown_upgrade")
		end
		return Progression.upgrade(player, payload.id)
	end)

	Remotes.handle("RollRelic", function(player)
		return Progression.rollRelic(player)
	end)

	Remotes.handle("Rebirth", function(player)
		return Progression.rebirth(player)
	end)

	Remotes.handle("Teleport", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		if payload.arena == true then
			Progression.teleportTo(player, Layout.arenaSpawn())
			return true
		end
		local zone = payload.zone
		if type(zone) ~= "number" or not Config.Zones[zone] then
			return false, M("msg.unknown_zone")
		end
		if not State.hasZone(p, zone) then
			return false, M("msg.zone_locked", { zone = M("zone." .. Config.Zones[zone].id) })
		end
		Progression.teleportTo(player, Layout.spawnPoint(zone))
		return true
	end)

	Remotes.handle("SetAuto", function(player, payload)
		local p = Data.get(player)
		local key = payload.key
		if not p or type(key) ~= "string" or not table.find(Config.AutoKeys, key) then
			return false, M("msg.bad_request")
		end
		p.auto[key] = payload.on == true
		State.dirty(player)
		if key == "best" and p.auto.best then
			Pets.equipBest(player)
		elseif key == "fuse" and p.auto.fuse then
			Pets.afterChange(player)
		elseif key == "mine" and p.auto.mine then
			Progression.tutorialAdvance(player, "auto")
		end
		return true
	end)

	Remotes.handle("SetSetting", function(player, payload)
		local p = Data.get(player)
		local key = payload.key
		if not p or type(key) ~= "string" or (p.settings :: any)[key] == nil then
			return false, M("msg.bad_request")
		end
		(p.settings :: any)[key] = payload.on == true
		State.dirty(player)
		return true
	end)

	Remotes.handle("SkipTutorial", function(player)
		local p = Data.get(player)
		if not p then
			return false
		end
		p.tutorial = #Config.Tutorial + 1
		State.dirty(player)
		return true
	end)

	Hooks.on("layerBroken", function(player: Player)
		Progression.tutorialAdvance(player, "mine")
	end)
	Hooks.on("planetBroken", function(player: Player)
		Progression.tutorialAdvance(player, "mine")
		Progression.tutorialAdvance(player, "core")
	end)
	Hooks.on("sold", function(player: Player)
		Progression.tutorialAdvance(player, "sell")
	end)
	Hooks.on("opened", function(player: Player)
		Progression.tutorialAdvance(player, "capsule")
	end)
	Hooks.on("toolBought", function(player: Player)
		Progression.tutorialAdvance(player, "tool")
	end)
end

return Progression
