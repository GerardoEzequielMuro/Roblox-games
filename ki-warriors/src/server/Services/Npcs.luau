--!strict
-- Enemies. The server owns a tiny invisible anchored "root" part per enemy (position, HP and
-- state as attributes) and runs every AI in ONE 10 Hz loop; clients build and animate the
-- visible model around each root (NpcRender). Only planets with players keep enemies spawned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Fighters = require(script.Parent.Fighters)
local Combat = require(script.Parent.Combat)

type Fighter = Fighters.Fighter
local AI = Config.NpcAi

local Npcs = {}

type Npc = {
	f: Fighter,
	def: any,
	planet: number,
	home: Vector3,
	roam: number, -- roam radius around home
	pos: Vector3,
	yaw: number,
	target: Fighter?,
	state: string, -- idle | chase | windup | recover | dead | return
	stateUntil: number,
	attack: string?, -- melee | ranged | slam | volley | charge
	attackDir: Vector3?,
	nextAttackAt: number,
	nextPatternAt: number,
	respawnAt: number,
	wanderTo: Vector3?,
	wanderAt: number,
	spawned: boolean,
	persistent: boolean?, -- world boss: not tied to planet activity, never respawns
	onDeath: ((Npc, Fighter?) -> ())?,
}

local folder: Folder
local npcs: { Npc } = {}
local byFighter: { [Fighter]: Npc } = {}
local activePlanets: { [number]: boolean } = {}
local rng = Random.new()

Npcs.list = npcs

function Npcs.activeCount(): number
	local n = 0
	for _, npc in npcs do
		if npc.spawned then
			n += 1
		end
	end
	return n
end

local function hoverHeight(def: any): number
	local s = def.scale or 1
	if def.arch == "wisp" then
		return 5.5 * s
	end
	return 3 * s
end

local function place(npc: Npc)
	local root = npc.f.root :: BasePart
	root.CFrame = CFrame.new(npc.pos) * CFrame.Angles(0, npc.yaw, 0)
end

local function setState(npc: Npc, state: string, duration: number?)
	npc.state = state
	npc.stateUntil = os.clock() + (duration or 0)
	local root = npc.f.root
	if root then
		root:SetAttribute("State", state)
	end
end

local function spawn(npc: Npc)
	local f = npc.f
	local root = f.root :: BasePart
	f.hp = f.maxHp
	f.alive = true
	f.contributions = {}
	f.knock = nil
	npc.pos = npc.home
	npc.target = nil
	npc.spawned = true
	npc.nextAttackAt = 0
	npc.nextPatternAt = os.clock() + 2
	root:SetAttribute("Hp", f.hp)
	root:SetAttribute("MaxHp", f.maxHp)
	setState(npc, "idle")
	place(npc)
	root.Parent = folder
end

local function despawn(npc: Npc)
	npc.spawned = false
	npc.f.alive = false
	local root = npc.f.root
	if root then
		root.Parent = nil
	end
end

-- Creates an enemy (not yet spawned). hp overrides the Config value (world boss).
function Npcs.create(npcId: string, planet: number, home: Vector3, roam: number, hp: number?): Npc
	local def = Config.Npcs[npcId]
	local s = def.scale or 1
	local root = Instance.new("Part")
	root.Name = npcId
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Transparency = 1
	root.Size = Vector3.new(3.5, 6, 3.5) * s
	local y = Config.GroundY + hoverHeight(def)
	local f = Fighters.addNpc(def, root, hp or def.hp)
	f.alive = false
	root:SetAttribute("Kind", npcId)
	root:SetAttribute("FighterId", f.id)
	local npc: Npc = {
		f = f,
		def = def,
		planet = planet,
		home = Vector3.new(home.X, y, home.Z),
		roam = roam,
		pos = Vector3.new(home.X, y, home.Z),
		yaw = rng:NextNumber(0, math.pi * 2),
		state = "dead",
		stateUntil = 0,
		nextAttackAt = 0,
		nextPatternAt = 0,
		respawnAt = 0,
		wanderAt = 0,
		spawned = false,
	}
	f.npc = npc
	table.insert(npcs, npc)
	byFighter[f] = npc
	return npc
end

function Npcs.spawn(npc: Npc)
	spawn(npc)
end

function Npcs.destroy(npc: Npc)
	despawn(npc)
	Fighters.remove(npc.f)
	byFighter[npc.f] = nil
	local i = table.find(npcs, npc)
	if i then
		table.remove(npcs, i)
	end
	local root = npc.f.root
	if root then
		root:Destroy()
	end
end

local function nearestPlayer(npc: Npc, range: number): Fighter?
	local best: Fighter? = nil
	local bestD = range
	for _, f in Fighters.list do
		if f.kind == "player" and not f.dummy and f.alive then
			local p = Fighters.position(f)
			if p then
				local d = (p - npc.pos).Magnitude
				if d < bestD and (p - npc.home).Magnitude < AI.leashRange + npc.roam then
					best, bestD = f, d
				end
			end
		end
	end
	return best
end

local function face(npc: Npc, toward: Vector3)
	local d = toward - npc.pos
	if math.abs(d.X) + math.abs(d.Z) > 0.05 then
		npc.yaw = math.atan2(-d.X, -d.Z)
	end
end

local function moveToward(npc: Npc, toward: Vector3, speed: number, dt: number): number
	local flat = (toward - npc.pos) * Vector3.new(1, 0, 1)
	local dist = flat.Magnitude
	if dist > 0.05 then
		local step = math.min(dist, speed * dt)
		npc.pos += flat.Unit * step
		face(npc, toward)
	end
	return dist
end

local function hit(npc: Npc, victim: Fighter, mult: number, knock: number)
	local def = npc.def
	Fighters.damage(npc.f, victim, "npc", def.dmg * mult, {
		knock = knock,
		fraction = if def.world then Config.WorldBoss.damageMultToPlayers * mult else nil,
	})
end

local function telegraph(kind: string, data: { [string]: any })
	data.k = kind
	Remotes.fireAll("Fx", "telegraph", data)
end

-- Starts an attack (windup). The damage lands in `resolve` when the windup ends.
local function startAttack(npc: Npc, attack: string, target: Fighter)
	local tp = Fighters.position(target) or npc.pos
	npc.attack = attack
	face(npc, tp)
	local enraged = npc.def.boss and npc.f.hp / npc.f.maxHp <= AI.enrageAt
	local speedUp = if enraged then 0.75 else 1
	if attack == "melee" then
		setState(npc, "windup", AI.meleeWindup * speedUp)
	elseif attack == "ranged" then
		setState(npc, "windup", AI.rangedWindup * speedUp)
	elseif attack == "slam" then
		setState(npc, "windup", AI.slamWindup * speedUp)
		telegraph("ring", { p = Vector3.new(npc.pos.X, Config.GroundY + 0.3, npc.pos.Z), r = AI.slamRadius * (npc.def.scale / 2.4), t = AI.slamWindup * speedUp })
	elseif attack == "volley" then
		setState(npc, "windup", 0.7 * speedUp)
	elseif attack == "charge" then
		local dir = (tp - npc.pos) * Vector3.new(1, 0, 1)
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, 1)
		npc.attackDir = dir
		setState(npc, "windup", AI.chargeWindup * speedUp)
		telegraph("line", { p = Vector3.new(npc.pos.X, Config.GroundY + 0.3, npc.pos.Z), d = dir, l = AI.chargeDistance, w = 9 * (npc.def.scale / 2.4), t = AI.chargeWindup * speedUp })
	end
	local root = npc.f.root
	if root then
		root:SetAttribute("Attack", attack)
	end
end

local function resolve(npc: Npc)
	local attack = npc.attack
	local def = npc.def
	local now = os.clock()
	local target = npc.target
	npc.attack = nil
	if attack == "melee" then
		if target and target.alive then
			local tp = Fighters.position(target)
			if tp and (tp - npc.pos).Magnitude <= AI.meleeRange + npc.f.radius + 3 then
				hit(npc, target, 1, 30)
			end
		end
		npc.nextAttackAt = now + AI.meleeCooldown
		setState(npc, "recover", 0.35)
	elseif attack == "ranged" then
		if target and target.alive then
			local tp = Fighters.position(target)
			if tp then
				local origin = npc.pos + Vector3.new(0, 1, 0)
				local dir = (tp - origin)
				if dir.Magnitude > 0.1 then
					Combat.spawnProjectile(npc.f, origin + dir.Unit * (npc.f.radius + 1), dir.Unit, {
						speed = AI.projectileSpeed,
						range = AI.rangedRange + 40,
						radius = 3,
						kind = "npc",
						damage = def.dmg,
						knock = 16,
						color = def.accent,
					})
				end
			end
		end
		npc.nextAttackAt = now + AI.rangedCooldown
		setState(npc, "recover", 0.3)
	elseif attack == "slam" then
		local radius = AI.slamRadius * (def.scale / 2.4)
		for _, f in Fighters.list do
			if f.kind == "player" and not f.dummy and f.alive then
				local p = Fighters.position(f)
				-- jumping or flying above the ring dodges it
				if p and ((p - npc.pos) * Vector3.new(1, 0, 1)).Magnitude <= radius and p.Y < Config.GroundY + 9 then
					hit(npc, f, AI.slamDamageMult, 70)
				end
			end
		end
		Remotes.fireAll("Fx", "shock", { p = Vector3.new(npc.pos.X, Config.GroundY + 0.5, npc.pos.Z), r = radius, n = npc.f.id })
		npc.nextPatternAt = now + AI.patternCooldown
		setState(npc, "recover", 0.8)
	elseif attack == "volley" then
		if target and target.alive then
			local tp = Fighters.position(target)
			if tp then
				local origin = npc.pos + Vector3.new(0, 2, 0)
				local base = CFrame.lookAt(origin, tp)
				for i = 1, AI.volleyShots do
					local a = (i - (AI.volleyShots + 1) / 2) * math.rad(9)
					local dir = (base * CFrame.Angles(0, a, 0)).LookVector
					Combat.spawnProjectile(npc.f, origin + dir * (npc.f.radius + 1), dir, {
						speed = AI.projectileSpeed * 0.9,
						range = 150,
						radius = 3.4,
						kind = "npc",
						damage = def.dmg * 0.8,
						knock = 20,
						color = def.accent,
						fraction = if def.world then Config.WorldBoss.damageMultToPlayers * 0.8 else nil,
					})
				end
			end
		end
		npc.nextPatternAt = now + AI.patternCooldown
		setState(npc, "recover", 0.6)
	elseif attack == "charge" then
		setState(npc, "charging", AI.chargeDistance / AI.chargeSpeed)
		npc.f.cd.chargeHit = 0
	end
end

local function reward(npc: Npc, killer: Fighter?)
	local def = npc.def
	local contributions: { [Player]: number } = npc.f.contributions or {}
	for player in contributions do
		local p = Data.get(player)
		if p and player.Parent then
			local gained = 0
			if def.sparks > 0 then
				gained = State.addSparks(player, def.sparks, true)
			end
			if def.gems then
				State.addGems(player, def.gems)
			end
			p.kills += 1
			if def.boss then
				p.bossKills[def.id] = (p.bossKills[def.id] or 0) + 1
				State.dirty(player)
			end
			Remotes.fire("Combat", player, "kill", { n = def.id, s = gained, g = def.gems or 0, b = def.boss == true })
			Hooks.fire("npcKilled", player, def.id, def)
		end
	end
	local _ = killer
end

local function die(npc: Npc, killer: Fighter?)
	Remotes.fireAll("Fx", "npcDeath", { i = npc.f.id, p = npc.pos, k = npc.def.id, b = npc.def.boss == true })
	if npc.onDeath then
		npc.onDeath(npc, killer)
	else
		reward(npc, killer)
	end
	npc.state = "dead"
	npc.respawnAt = os.clock() + npc.def.respawn
	npc.spawned = false
	local root = npc.f.root
	if root then
		root.Parent = nil
	end
end

local function think(npc: Npc, dt: number, now: number)
	local def = npc.def
	local f = npc.f
	-- knockback
	local knock = f.knock
	if knock then
		npc.pos += Vector3.new(knock.X, 0, knock.Z) * dt
		f.knock = if knock.Magnitude > 6 then knock * 0.55 else nil
	end

	if npc.state == "windup" then
		if npc.target then
			local tp = Fighters.position(npc.target)
			if tp and npc.attack ~= "charge" and npc.attack ~= "slam" then
				face(npc, tp)
			end
		end
		if now >= npc.stateUntil then
			resolve(npc)
		end
		return
	elseif npc.state == "charging" then
		local dir = npc.attackDir or Vector3.new(0, 0, 1)
		npc.pos += dir * AI.chargeSpeed * dt
		for _, v in Fighters.list do
			if v.kind == "player" and not v.dummy and v.alive and (v.cd["charged" .. f.id] or 0) < now then
				local p = Fighters.position(v)
				if p and (p - npc.pos).Magnitude <= 8 * (def.scale / 2.4) + 3 then
					v.cd["charged" .. f.id] = now + 1
					hit(npc, v, 1.6, 80)
				end
			end
		end
		if now >= npc.stateUntil then
			npc.nextPatternAt = now + AI.patternCooldown
			setState(npc, "recover", 0.7)
		end
		return
	elseif npc.state == "recover" then
		if now >= npc.stateUntil then
			setState(npc, "chase")
		end
		return
	end

	-- target upkeep
	local target = npc.target
	if target then
		local tp = Fighters.position(target)
		if not target.alive or not tp or (tp - npc.home).Magnitude > AI.leashRange + npc.roam then
			npc.target = nil
			target = nil
		end
	end
	if not target then
		-- whoever hit us last, or whoever walks in
		target = nearestPlayer(npc, AI.aggroRange * (if def.boss then 1.4 else 1))
		if not target and next(f.contributions or {}) then
			target = nearestPlayer(npc, AI.leashRange)
		end
		npc.target = target
	end

	if not target then
		-- go home, heal, wander a little
		local homeDist = ((npc.home - npc.pos) * Vector3.new(1, 0, 1)).Magnitude
		if homeDist > npc.roam then
			moveToward(npc, npc.home, def.speed, dt)
			if npc.state ~= "return" then
				setState(npc, "return")
			end
		else
			if npc.state ~= "idle" then
				setState(npc, "idle")
				if f.hp < f.maxHp then
					f.hp = f.maxHp
					f.contributions = {}
					local root = f.root
					if root then
						root:SetAttribute("Hp", f.hp)
					end
				end
			end
			if not def.boss then
				if now >= npc.wanderAt then
					npc.wanderAt = now + rng:NextNumber(3, 7)
					local a = rng:NextNumber(0, math.pi * 2)
					local r = rng:NextNumber(0, npc.roam)
					npc.wanderTo = npc.home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				end
				if npc.wanderTo then
					if moveToward(npc, npc.wanderTo, def.speed * 0.35, dt) < 1 then
						npc.wanderTo = nil
					end
				end
			end
		end
		return
	end

	if npc.state ~= "chase" then
		setState(npc, "chase")
	end
	local tp = Fighters.position(target) :: Vector3
	local flatDist = ((tp - npc.pos) * Vector3.new(1, 0, 1)).Magnitude
	local dist3 = (tp - npc.pos).Magnitude
	local enraged = def.boss and f.hp / f.maxHp <= AI.enrageAt

	if def.ai == "boss" then
		if now >= npc.nextPatternAt then
			local roll = rng:NextNumber()
			local pattern = if flatDist < AI.slamRadius * 0.8 and roll < 0.55 then "slam" elseif roll < 0.5 then "volley" else "charge"
			if flatDist > 80 then
				pattern = "volley"
			end
			npc.nextPatternAt = now + AI.patternCooldown * (if enraged then 0.7 else 1) + 1.5
			startAttack(npc, pattern, target)
			return
		end
		if dist3 <= AI.meleeRange + f.radius and now >= npc.nextAttackAt then
			startAttack(npc, "melee", target)
			return
		end
		if flatDist > AI.meleeRange + f.radius - 2 then
			moveToward(npc, tp, def.speed * (if enraged then 1.25 else 1), dt)
		else
			face(npc, tp)
		end
	elseif def.ai == "ranged" then
		if flatDist > AI.rangedRange then
			moveToward(npc, tp, def.speed, dt)
		elseif flatDist < AI.rangedKeep * 0.6 then
			-- back off
			local away = npc.pos + (npc.pos - tp) * Vector3.new(1, 0, 1)
			moveToward(npc, away, def.speed * 0.7, dt)
			face(npc, tp)
		else
			face(npc, tp)
		end
		if dist3 <= AI.rangedRange + 25 and now >= npc.nextAttackAt then
			startAttack(npc, "ranged", target)
		end
	else
		if dist3 <= AI.meleeRange + f.radius then
			face(npc, tp)
			if now >= npc.nextAttackAt then
				startAttack(npc, "melee", target)
			end
		else
			moveToward(npc, tp, def.speed, dt)
		end
	end
end

local function refreshActivePlanets()
	local active: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p and State.ready[player] then
			active[p.planet] = true
		end
	end
	activePlanets = active
end

function Npcs.init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace

	Fighters.onNpcDeath = function(f: Fighter, killer: Fighter?)
		local npc = byFighter[f]
		if npc then
			die(npc, killer)
		end
	end

	for _, pl in Config.Planets do
		local cx, _, cz = Config.planetCenter(pl.index)
		for _, camp in pl.camps do
			for i = 1, camp.count do
				local a = (i / camp.count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
				local r = camp.radius * rng:NextNumber(0.25, 0.85)
				local home = Vector3.new(cx + camp.offset[1] + math.cos(a) * r, 0, cz + camp.offset[3] + math.sin(a) * r)
				Npcs.create(camp.npc, pl.index, home, 12)
			end
		end
		local b = pl.boss
		Npcs.create(b.npc, pl.index, Vector3.new(cx + b.offset[1], 0, cz + b.offset[3]), 6)
	end

	task.spawn(function()
		local last = os.clock()
		local acc = 0
		while true do
			task.wait(1 / AI.tickRate)
			local now = os.clock()
			local dt = math.min(now - last, 0.3)
			last = now
			acc += dt
			if acc >= 1 then
				acc = 0
				refreshActivePlanets()
			end
			for _, npc in npcs do
				if npc.persistent then
					if npc.spawned then
						think(npc, dt, now)
						place(npc)
					end
					continue
				end
				local active = activePlanets[npc.planet] == true
				if npc.spawned then
					if not active then
						despawn(npc)
						npc.respawnAt = 0
					else
						think(npc, dt, now)
						if npc.spawned then
							place(npc)
						end
					end
				elseif active and now >= npc.respawnAt then
					spawn(npc)
				end
			end
		end
	end)
end

return Npcs
