--!strict
-- Server-authoritative mining. Planets are per-player (nobody can steal your planet): the
-- server keeps each player's nodes for the galaxies they visit, the client only draws them.
--   * clients send (node, hit count) batches; a token bucket caps them at the player's
--     hits-per-second stat, and the character has to be in range of the planet
--   * Auto Mine is driven from here (Mining.autoStep), no remote involved
--   * broken layers go into the cargo hold; the hold is sold at the Refinery or by the drone
--   * the Gate Planet's HP is saved; breaking it unlocks the next galaxy
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Security = require(ReplicatedStorage.Shared.Security)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local Mining = {}

export type Node = { kind: string, layer: number, hp: number, dense: boolean, respawnAt: number? }

local nodes: { [Player]: { [number]: { [number]: Node } } } = {}
local buckets: { [Player]: Security.Bucket } = {}
local eventBuckets: { [Player]: Security.Bucket } = {} -- how often the Hit event itself may fire
local autoAcc: { [Player]: number } = {}
local focus: { [Player]: number? } = {} -- zone * 100 + node the player last hit by hand
local lastFullNotice: { [Player]: number } = {}
local rng = Random.new()

Mining.nodes = nodes

local function layerMax(zone: number, node: Node): number
	local hp = Formulas.layerHp(zone, node.kind, node.layer)
	return if node.dense then hp * Config.DenseMult else hp
end
Mining.layerMax = layerMax

local function serialize(zone: number, n: number, node: Node): { [string]: any }
	return {
		z = zone,
		n = n,
		k = Config.PlanetKindIndex[node.kind],
		l = node.layer,
		h = node.hp,
		m = layerMax(zone, node),
		d = node.dense,
		r = if node.respawnAt then math.max(0, node.respawnAt - os.clock()) else nil,
	}
end

local function newRegular(player: Player, p: Data.Profile, zone: number, n: number): Node
	local luck = Formulas.luck(State.stats(player, p))
	local node: Node = { kind = Formulas.rollKind(luck, rng:NextNumber()), layer = 1, hp = 0, dense = n > 5 }
	node.hp = layerMax(zone, node)
	return node
end

-- Gate and Anomaly come and go with progress and the clock.
local function syncSpecial(player: Player, p: Data.Profile, zone: number, list: { [number]: Node }): boolean
	local changed = false
	local maxZone = State.maxZone(p)
	local nextZone = Config.Zones[zone + 1]
	local wantGate = zone == maxZone and nextZone ~= nil
	if wantGate and not list[Config.NodeGate] then
		list[Config.NodeGate] = { kind = "gate", layer = 1, hp = p.gate[tostring(zone + 1)] or nextZone.gateHp, dense = false }
		changed = true
	elseif not wantGate and list[Config.NodeGate] then
		list[Config.NodeGate] = nil
		changed = true
	end
	local active, window = Formulas.anomaly(os.time())
	local wantAnomaly = active and p.anomalyWindow ~= window
	if wantAnomaly and not list[Config.NodeAnomaly] then
		local node: Node = { kind = "anomaly", layer = 1, hp = 0, dense = false }
		node.hp = layerMax(zone, node)
		list[Config.NodeAnomaly] = node
		changed = true
	elseif not wantAnomaly and list[Config.NodeAnomaly] then
		list[Config.NodeAnomaly] = nil
		changed = true
	end
	return changed
end

local function ensureZone(player: Player, p: Data.Profile, zone: number): { [number]: Node }
	local mine = nodes[player]
	if not mine then
		mine = {}
		nodes[player] = mine
	end
	local existing = mine[zone]
	if existing then
		syncSpecial(player, p, zone, existing)
		return existing
	end
	local list: { [number]: Node } = {}
	local titan: Node = { kind = "titan", layer = 1, hp = 0, dense = false }
	titan.hp = layerMax(zone, titan)
	list[Config.NodeTitan] = titan
	for n = 1, Config.NodesPerZone do
		list[n] = newRegular(player, p, zone, n)
	end
	mine[zone] = list
	syncSpecial(player, p, zone, list)
	return list
end
Mining.ensureZone = ensureZone

local function hrpOf(player: Player): BasePart?
	local char = player.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Horizontal distance from the character to the planet's surface.
local function distanceTo(pos: Vector3, zone: number, n: number, node: Node): number
	local np = Layout.nodePosition(zone, n)
	local dx, dz = pos.X - np[1], pos.Z - np[3]
	local size = Config.PlanetKindById[node.kind].size
	return math.sqrt(dx * dx + dz * dz) - size / 2
end

---------------------------------------------------------------------------
-- Cargo
---------------------------------------------------------------------------
-- Sells the hold right now. byHand = on the Refinery pad (bonus).
function Mining.sell(player: Player, p: Data.Profile, byHand: boolean): number
	if p.cargo.count <= 0 then
		return 0
	end
	local value = p.cargo.value * (if byHand then 1 + Config.CargoHandBonus else 1)
	p.cargo.count = 0
	p.cargo.value = 0
	State.addStardust(player, value, true)
	Remotes.fire("Reward", player, { kind = "sold", amount = value, hand = byHand })
	Hooks.fire("sold", player, value, byHand)
	return value
end

-- Sends the Cargo Drone with the current hold. False when it is already flying or the hold is empty.
function Mining.sendDrone(player: Player, p: Data.Profile): boolean
	if State.transit[player] or p.cargo.count <= 0 then
		return false
	end
	local seconds = Formulas.droneSeconds(State.stats(player, p))
	State.transit[player] = { value = p.cargo.value, arriveAt = os.clock() + seconds }
	p.cargo.count = 0
	p.cargo.value = 0
	State.dirtyCurrency(player)
	Remotes.fire("Reward", player, { kind = "drone", seconds = seconds })
	return true
end

local function landDrone(player: Player)
	local transit = State.transit[player]
	if not transit then
		return
	end
	State.transit[player] = nil
	State.addStardust(player, transit.value, true)
	Remotes.fire("Reward", player, { kind = "sold", amount = transit.value, hand = false })
	Hooks.fire("sold", player, transit.value, false)
end

local function addOre(player: Player, p: Data.Profile, chunks: number, value: number)
	if State.owns(player, "InstantSell") then
		State.addStardust(player, value, true)
		Hooks.fire("sold", player, value, false)
		return
	end
	p.cargo.count += chunks
	p.cargo.value += value
	State.dirtyCurrency(player)
end

local function cargoFull(player: Player, p: Data.Profile): boolean
	if State.owns(player, "InstantSell") then
		return false
	end
	return p.cargo.count >= Formulas.cargoCapacity(State.stats(player, p))
end
Mining.cargoFull = cargoFull

---------------------------------------------------------------------------
-- Breaking things
---------------------------------------------------------------------------
local function masteryUp(player: Player, p: Data.Profile, kindId: string)
	local count = (p.mastery[kindId] or 0) + 1
	p.mastery[kindId] = count
	local level = Formulas.masteryLevel(count)
	local paid = p.masteryPaid[kindId] or 0
	if level > paid then
		p.masteryPaid[kindId] = level
		local crystals = Config.MasteryCrystals[level] or 0
		State.addCrystals(player, crystals)
		State.dirty(player)
		Remotes.notify(player, M("msg.mastery_up", { planet = M("planet." .. kindId), level = level, crystals = crystals }), "success")
	end
end

local function unlockNextZone(player: Player, p: Data.Profile, zone: number)
	local nextIndex = zone + 1
	if not Config.Zones[nextIndex] or State.hasZone(p, nextIndex) then
		return
	end
	table.insert(p.zones, nextIndex)
	p.gate[tostring(nextIndex)] = nil
	local crystals = Config.GateCrystals[nextIndex] or 0
	State.addCrystals(player, crystals)
	State.dirty(player)
	Remotes.notify(player, M("msg.zone_unlocked", { zone = M("zone." .. Config.Zones[nextIndex].id), crystals = crystals }), "success")
	Remotes.fireAll("Toast", { kind = "gate", player = player.DisplayName, zone = nextIndex })
	Hooks.fire("zoneUnlocked", player, nextIndex)
end

-- Core broken: drops, buff, mastery, respawn. Returns the drops for the client.
local function breakPlanet(player: Player, p: Data.Profile, zone: number, n: number, node: Node, list: { [number]: Node }): { [string]: any }
	local kind = Config.PlanetKindById[node.kind]
	local z = Config.Zones[zone]
	local stats = State.stats(player, p)
	local drops: { [string]: any } = {}
	if node.kind == "gate" then
		list[n] = nil
		unlockNextZone(player, p, zone)
		drops.gate = zone + 1
		return drops
	end
	if kind.crystals then
		local crystals = math.floor(kind.crystals * z.crystal * Formulas.crystalMult(stats) + 0.5)
		State.addCrystals(player, crystals)
		drops.cr = crystals
	end
	local material = (z :: any).material
	if material then
		local amount = (kind.materials or 1) * (if node.dense then 2 else 1)
		State.addMaterial(player, material, amount)
		drops.mat = amount
		drops.matId = material
	end
	local buff = kind.buff
	if buff == "random" then
		buff = Config.BuffOrder[rng:NextInteger(1, #Config.BuffOrder)]
	end
	if buff == "all" then
		for _, id in Config.BuffOrder do
			State.addBuff(player, id, Config.Buffs[id].duration * 4, true)
		end
		drops.buff = "all"
	elseif buff then
		State.addBuff(player, buff, Config.Buffs[buff].duration * (if kind.boss then 2 else 1), true)
		drops.buff = buff
		Hooks.fire("buff", player, buff)
	end
	masteryUp(player, p, node.kind)
	p.planetsBroken += 1
	Hooks.fire("planetBroken", player, node.kind, zone)
	if node.kind == "anomaly" then
		local _, window = Formulas.anomaly(os.time())
		p.anomalyWindow = window
		list[n] = nil
		State.dirty(player)
	else
		node.respawnAt = os.clock() + (if kind.boss then Config.TitanRespawn else Config.PlanetRespawn)
	end
	return drops
end

-- Applies `hits` hits to a node. Everything that reaches this point is already validated.
local function apply(player: Player, p: Data.Profile, zone: number, n: number, hits: number, auto: boolean)
	local list = ensureZone(player, p, zone)
	local node = list[n]
	if not node or node.respawnAt then
		return
	end
	local isGate = node.kind == "gate"
	if not isGate and cargoFull(player, p) then
		local now = os.clock()
		if now - (lastFullNotice[player] or 0) > 1 then
			lastFullNotice[player] = now
			Remotes.fire("Mine", player, { z = zone, n = n, full = true })
		end
		return
	end
	local stats = State.stats(player, p)
	local hard = Formulas.hardness(stats.toolIndex, zone)
	local per = State.hitDamage(player, p) * hard
	local critChance = Formulas.critChance(stats)
	local dealt, crits, layersBroken = 0, 0, 0
	local oreValue, oreChunks = 0, 0
	local drops: { [string]: any }? = nil
	local mult = Formulas.stardustMult(stats)
	for _ = 1, hits do
		local d = per
		if rng:NextNumber() < critChance then
			d *= Config.CritMult
			crits += 1
		end
		dealt += math.min(d, node.hp)
		node.hp -= d
		if node.hp <= 0 then
			layersBroken += 1
			if not isGate then
				local value = Formulas.layerValue(zone, node.kind, node.layer) * (if node.dense then Config.DenseMult else 1) * mult
				oreValue += value
				oreChunks += Config.Layers[node.layer].chunks
			end
			if node.layer >= Formulas.layerCount(node.kind) then
				node.hp = 0
				drops = breakPlanet(player, p, zone, n, node, list)
				break
			end
			node.layer += 1
			node.hp = layerMax(zone, node)
			Hooks.fire("layerBroken", player, zone)
			if not isGate and p.cargo.count + oreChunks >= Formulas.cargoCapacity(stats) and not State.owns(player, "InstantSell") then
				break -- the hold is full: the rest of the batch is lost
			end
		end
	end
	if isGate and list[n] then
		p.gate[tostring(zone + 1)] = node.hp
	end
	if oreChunks > 0 then
		addOre(player, p, oreChunks, oreValue)
	end
	p.hits += hits
	State.charge[player] = math.min(Config.OverchargeHits, (State.charge[player] or 0) + hits)
	State.lastHit[player] = os.clock()
	Hooks.fire("hits", player, hits)
	player:SetAttribute("MineNode", zone * 100 + n)
	Remotes.fire("Mine", player, {
		z = zone,
		n = n,
		k = Config.PlanetKindIndex[node.kind],
		l = node.layer,
		h = math.max(0, node.hp),
		m = if list[n] and not node.respawnAt then layerMax(zone, node) else 0,
		dmg = dealt,
		c = crits,
		b = layersBroken,
		sd = oreValue,
		drops = drops,
		soft = hard < 1,
		a = auto,
		r = if node.respawnAt then node.respawnAt - os.clock() else nil,
	})
end

---------------------------------------------------------------------------
-- Manual hits
---------------------------------------------------------------------------
local function onHit(player: Player, n: any, count: any)
	if not Security.isFinite(n) or not Security.isFinite(count) then
		return -- also drops NaN and inf
	end
	n = math.floor(n)
	count = math.floor(count)
	if count <= 0 or n < 0 or n > Config.NodeGate then
		return
	end
	-- cap on the event rate itself (the legit client sends a few batches per second), so a
	-- flood of tiny events cannot burn server time before the hit bucket below
	local now0 = os.clock()
	local eb = eventBuckets[player]
	if not eb then
		eb = Security.newBucket(40, 80, now0)
		eventBuckets[player] = eb
	end
	if not Security.take(eb, now0) then
		return
	end
	local p = Data.get(player)
	local hrp = hrpOf(player)
	if not p or not hrp or not State.ready[player] then
		return
	end
	local zone = Layout.zoneAt(hrp.Position.X, hrp.Position.Z)
	if not zone or not State.hasZone(p, zone) then
		return
	end
	local list = ensureZone(player, p, zone)
	local node = list[n]
	if not node or node.respawnAt then
		return
	end
	local stats = State.stats(player, p)
	if distanceTo(hrp.Position, zone, n, node) > Formulas.range(stats) + 6 then
		return
	end
	local now = os.clock()
	local rate = Formulas.hitsPerSecond(stats)
	local b = buckets[player]
	if not b then
		b = Security.newBucket(rate, rate + Config.HitBurst, now)
		buckets[player] = b
	end
	b.rate, b.burst = rate, rate + Config.HitBurst -- follows upgrades and buffs
	local accepted = Security.takeUpTo(b, now, count)
	if accepted <= 0 then
		return
	end
	focus[player] = zone * 100 + n
	apply(player, p, zone, n, accepted, false)
end

---------------------------------------------------------------------------
-- Auto Mine (called by the Auto service every Config.AutoTick)
---------------------------------------------------------------------------
-- The planet Auto Mine works on: the one the player last hit by hand while it is alive and
-- in range, otherwise the nearest live planet in range (never the Gate on its own).
local function autoTarget(player: Player, p: Data.Profile, zone: number, pos: Vector3, list: { [number]: Node }, range: number): number?
	local f = focus[player]
	if f and f // 100 == zone then
		local n = f % 100
		local node = list[n]
		if node and not node.respawnAt and distanceTo(pos, zone, n, node) <= range then
			return n
		end
	end
	local best: number?, bestDist = nil, math.huge
	for n, node in list do
		if not node.respawnAt and node.kind ~= "gate" then
			local d = distanceTo(pos, zone, n, node)
			if d <= range and d < bestDist then
				best, bestDist = n, d
			end
		end
	end
	return best
end

function Mining.autoStep(player: Player, p: Data.Profile, dt: number)
	if not p.auto.mine then
		autoAcc[player] = 0
		return
	end
	local hrp = hrpOf(player)
	if not hrp then
		return
	end
	local zone = Layout.zoneAt(hrp.Position.X, hrp.Position.Z)
	if not zone or not State.hasZone(p, zone) then
		return
	end
	local stats = State.stats(player, p)
	local acc = (autoAcc[player] or 0) + Formulas.autoRate(stats) * dt
	local hits = math.floor(acc)
	autoAcc[player] = acc - hits
	if hits <= 0 then
		return
	end
	local list = ensureZone(player, p, zone)
	local n = autoTarget(player, p, zone, hrp.Position, list, Formulas.range(stats, true))
	if n then
		apply(player, p, zone, n, hits, true)
	end
end

-- Respawns, the drone, hand sales at the Refinery, Overcharge decay. Called every AutoTick.
function Mining.step(player: Player, p: Data.Profile, dt: number)
	local now = os.clock()
	local mine = nodes[player]
	if mine then
		for zone, list in mine do
			for n, node in list do
				if node.respawnAt and node.respawnAt <= now then
					local fresh: Node
					if node.kind == "titan" then
						fresh = { kind = "titan", layer = 1, hp = 0, dense = false }
						fresh.hp = layerMax(zone, fresh)
					else
						fresh = newRegular(player, p, zone, n)
					end
					list[n] = fresh
					Remotes.fire("Node", player, serialize(zone, n, fresh))
				end
			end
		end
	end
	local transit = State.transit[player]
	if transit and transit.arriveAt <= now then
		landDrone(player)
	end
	local hrp = hrpOf(player)
	if p.cargo.count > 0 and hrp then
		local zone = Layout.zoneAt(hrp.Position.X, hrp.Position.Z)
		if zone then
			local r = Layout.refineryPosition(zone)
			local dx, dz = hrp.Position.X - r[1], hrp.Position.Z - r[3]
			if dx * dx + dz * dz <= Config.RefineryRadius ^ 2 then
				Mining.sell(player, p, true)
			end
		end
		if p.cargo.count > 0 and p.auto.sell and cargoFull(player, p) then
			Mining.sendDrone(player, p)
		end
	end
	-- Overcharge decay
	local charge = State.charge[player] or 0
	if charge > 0 and now - (State.lastHit[player] or 0) > Formulas.overchargeDecay(p.upgrades.Insulation or 0) then
		State.charge[player] = math.max(0, charge - Config.OverchargeDropPerSecond * dt)
		if State.hasZone(p, Config.SystemById.overcharge.zone) then
			State.dirtyCurrency(player)
		end
	end
	if player:GetAttribute("MineNode") and now - (State.lastHit[player] or 0) > 1.5 then
		player:SetAttribute("MineNode", nil)
	end
end

-- Test / internal entry point: hits without the range and rate checks.
function Mining.applyHits(player: Player, zone: number, n: number, hits: number)
	local p = Data.get(player)
	if p then
		apply(player, p, zone, n, hits, false)
	end
end

function Mining.forget(player: Player)
	landDrone(player) -- a drone in flight still delivers
	nodes[player] = nil
	buckets[player] = nil
	eventBuckets[player] = nil
	autoAcc[player] = nil
	focus[player] = nil
	lastFullNotice[player] = nil
end

-- Rebirth: the planets of every galaxy come back fresh.
function Mining.reset(player: Player)
	nodes[player] = nil
	focus[player] = nil
end

function Mining.init()
	Remotes.HitEvent.OnServerEvent:Connect(onHit)

	-- Every planet of a galaxy, for the client to draw (called when it enters the galaxy
	-- and when the Anomaly window opens or closes).
	Remotes.handle("GetNodes", function(player, payload)
		local p = Data.get(player)
		local zone = payload.zone
		if not p or type(zone) ~= "number" or not Config.Zones[zone] or not State.hasZone(p, zone) then
			return false, M("msg.unknown_zone")
		end
		local list = ensureZone(player, p, zone)
		local out = {}
		for n, node in list do
			table.insert(out, serialize(zone, n, node))
		end
		return true, out
	end, { interval = 0.2 })

	Remotes.handle("SellCargo", function(player)
		local p = Data.get(player)
		if not p then
			return false
		end
		if p.cargo.count <= 0 then
			return false, M("msg.cargo_empty")
		end
		if not Mining.sendDrone(player, p) then
			return false, M("msg.drone_busy")
		end
		return true
	end)
end

return Mining
