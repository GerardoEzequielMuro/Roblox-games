--!strict
-- Zones (gate purchase, teleport, anti-trespass), rebirth and gem upgrades.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

local Progression = {}

local zoneSpawns: { [number]: CFrame } = {}

function Progression.applyWalkSpeed(player: Player)
	local p = Data.get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if p and hum then
		hum.WalkSpeed = Config.BaseWalkSpeed + (p.upgrades.WalkSpeed or 0) * Config.UpgradeById.WalkSpeed.perLevel
	end
end

function Progression.teleport(player: Player, zone: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cf = zoneSpawns[zone]
	if root and cf then
		-- instance streaming: ask for the destination first so the player never lands in a void
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, 2)
		end)
		if char and char.Parent then
			(char :: Model):PivotTo(cf + Vector3.new(math.random(-6, 6), 0, 0))
		end
	end
end

-- Rebirth (manual request or Auto Rebirth). Returns ok, message.
function Progression.rebirth(player: Player): (boolean, Locale.Message?)
	local p = Data.get(player)
	if not p then
		return false, nil
	end
	local cost = Formulas.rebirthCost(p.rebirths)
	if p.taps < cost then
		return false, M("msg.need_rebirth", { n = Format.abbrev(cost) })
	end
	local gems = Formulas.rebirthGems(p.rebirths)
	p.taps = 0
	p.rebirths += 1
	State.addGems(player, gems)
	State.dirty(player)
	Hooks.fire("rebirth", player)
	Remotes.notify(player, M("msg.rebirth", { mult = tostring(Formulas.rebirthMult(p.rebirths)), gems = gems }), "success")
	for _, eggId in Formulas.eggsUnlockedAt(p.rebirths) do
		Remotes.notify(player, M("msg.egg_unlocked", { egg = M("egg." .. eggId), zone = M("zone." .. Config.Zones[Formulas.EggById[eggId].zone].id) }), "success")
	end
	return true, nil
end

function Progression.buyZone(player: Player, zone: number): (boolean, Locale.Message?)
	local p = Data.get(player)
	local z = Config.Zones[zone]
	if not p or not z then
		return false, M("msg.unknown_zone")
	end
	if State.hasZone(p, zone) then
		return false, M("msg.already_unlocked")
	end
	if not State.hasZone(p, zone - 1) then
		return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[zone - 1].id) })
	end
	if not State.spendTaps(player, z.cost) then
		return false, M("msg.need_taps", { n = Format.abbrev(z.cost) })
	end
	table.insert(p.zones, zone)
	State.dirty(player)
	Remotes.notify(player, M("msg.unlocked_zone", { zone = M("zone." .. z.id) }), "success")
	return true
end

function Progression.init(spawns: { [number]: CFrame }, gates: { [number]: BasePart })
	zoneSpawns = spawns

	for zone, barrier in gates do
		local prompt = barrier:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				local ok, err = Progression.buyZone(player, zone)
				if not ok and err then
					Remotes.notify(player, err, "error")
				end
			end)
		end
	end

	Remotes.handle("BuyZone", function(player, payload)
		if type(payload.zone) ~= "number" then
			return false, M("msg.unknown_zone")
		end
		return Progression.buyZone(player, payload.zone)
	end)

	Remotes.handle("Teleport", function(player, payload)
		local p = Data.get(player)
		if not p or type(payload.zone) ~= "number" or not State.hasZone(p, payload.zone) then
			return false, M("msg.zone_locked")
		end
		Progression.teleport(player, payload.zone)
		return true
	end)

	Remotes.handle("Rebirth", function(player)
		return Progression.rebirth(player)
	end)

	Remotes.handle("Upgrade", function(player, payload)
		local p = Data.get(player)
		local u = if type(payload.id) == "string" then Config.UpgradeById[payload.id] else nil
		if not p or not u then
			return false, M("msg.unknown_upgrade")
		end
		local level = p.upgrades[u.id] or 0
		if level >= u.maxLevel then
			return false, M("msg.maxed")
		end
		local cost = Formulas.upgradeCost(u.id, level)
		if not State.spendGems(player, cost) then
			return false, M("msg.not_enough_gems")
		end
		p.upgrades[u.id] = level + 1
		Hooks.fire("gemsSpent", player, cost)
		if u.id == "WalkSpeed" then
			Progression.applyWalkSpeed(player)
		end
		State.dirty(player)
		return true
	end)

	-- Anti-trespass: noclip/teleport exploits into locked zones get sent back.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if p and root and State.ready[player] then
					local zone = WorldBuilder.zoneAt(root.Position.Z)
					if not State.hasZone(p, zone) then
						Progression.teleport(player, State.maxZone(p))
						Remotes.notify(player, M("msg.zone_locked"), "error")
					end
				end
			end
		end
	end)

end

return Progression
