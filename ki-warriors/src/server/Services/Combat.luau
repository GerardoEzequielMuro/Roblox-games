--!strict
-- Combat actions (server authoritative): melee combo, ki blasts, charged beam, block, dash,
-- ki charge, flight flag, transformations and techniques. Clients only send intents through
-- the Act remote; cooldowns, ki costs, hit detection and damage are decided here.
-- One Heartbeat loop steps every projectile; one 10 Hz loop handles ki / forms / healing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Fighters = require(script.Parent.Fighters)

type Fighter = Fighters.Fighter
local C = Config.Combat

local Combat = {}

-- Training hook (set by the Training service to avoid a require cycle).
Combat.onManualRep = function(_player: Player) end

local rng = Random.new()

---------------------------------------------------------------------------
-- Projectiles
---------------------------------------------------------------------------
type Projectile = {
	id: number,
	owner: Fighter,
	pos: Vector3,
	dir: Vector3,
	speed: number,
	left: number,
	radius: number,
	kind: string,
	damage: number,
	aoe: number?, -- explosion radius
	knock: number,
	fraction: number?,
}
local projectiles: { Projectile } = {}
local nextProjectile = 0
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Include

function Combat.projectileCount(): number
	return #projectiles
end

local function spawnProjectile(owner: Fighter, origin: Vector3, dir: Vector3, spec: { [string]: any }): Projectile
	nextProjectile += 1
	local pr: Projectile = {
		id = nextProjectile,
		owner = owner,
		pos = origin,
		dir = dir,
		speed = spec.speed,
		left = spec.range,
		radius = spec.radius,
		kind = spec.kind,
		damage = spec.damage,
		aoe = spec.aoe,
		knock = spec.knock or 0,
		fraction = spec.fraction,
	}
	table.insert(projectiles, pr)
	Remotes.fireAll("Fx", "shot", {
		i = pr.id,
		o = origin,
		d = dir,
		s = pr.speed,
		r = pr.left,
		z = pr.radius,
		k = pr.kind,
		f = owner.form,
		u = if owner.player then owner.player.UserId else 0,
		n = if owner.kind == "npc" then owner.id else 0,
		c = spec.color,
	})
	return pr
end
Combat.spawnProjectile = spawnProjectile

local function explode(pr: Projectile, at: Vector3, direct: Fighter?)
	local hitAny = false
	if pr.aoe then
		for _, v in Fighters.list do
			if Fighters.hostile(pr.owner, v) then
				local vp = Fighters.position(v)
				if vp and (vp - at).Magnitude <= pr.aoe + v.radius then
					Fighters.damage(pr.owner, v, pr.kind, pr.damage, { knock = pr.knock, from = at, fraction = pr.fraction })
					hitAny = true
				end
			end
		end
	elseif direct then
		local crit = pr.owner.kind == "player" and rng:NextNumber() < Combat.critChance(pr.owner)
		Fighters.damage(pr.owner, direct, pr.kind, pr.damage, { knock = pr.knock, crit = crit, fraction = pr.fraction })
		hitAny = true
	end
	Remotes.fireAll("Fx", "shotEnd", { i = pr.id, p = at, h = hitAny, a = pr.aoe or 0 })
end

local function stepProjectiles(dt: number)
	if #projectiles == 0 then
		return
	end
	local world = workspace:FindFirstChild("World")
	worldParams.FilterDescendantsInstances = if world then { world } else {}
	for i = #projectiles, 1, -1 do
		local pr = projectiles[i]
		local step = math.min(pr.speed * dt, pr.left)
		local a = pr.pos
		local b = a + pr.dir * step
		local done = false
		-- fighters
		local bestT: number? = nil
		local bestV: Fighter? = nil
		for _, v in Fighters.list do
			if v ~= pr.owner and v.alive and Fighters.hostile(pr.owner, v) then
				local vp = Fighters.position(v)
				if vp then
					local t = math.clamp((vp - a):Dot(pr.dir), 0, step)
					local closest = a + pr.dir * t
					if (vp - closest).Magnitude <= pr.radius + v.radius then
						if not bestT or t < bestT then
							bestT, bestV = t, v
						end
					end
				end
			end
		end
		if bestV and bestT then
			explode(pr, a + pr.dir * bestT, bestV)
			done = true
		else
			-- world geometry
			local hit = if world then workspace:Raycast(a, pr.dir * (step + 0.5), worldParams) else nil
			if hit then
				explode(pr, hit.Position, nil)
				done = true
			end
		end
		if not done then
			pr.pos = b
			pr.left -= step
			if pr.left <= 0.01 then
				explode(pr, b, nil)
				done = true
			end
		end
		if done then
			table.remove(projectiles, i)
		end
	end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function Combat.critChance(f: Fighter): number
	local chance = C.critChance
	if f.player then
		local p = Data.get(f.player)
		if p then
			chance += Formulas.upgradeValue("critChance", p.upgrades.critChance or 0)
		end
	end
	return chance
end

local function unit(v: any): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local m = v.Magnitude
	if m ~= m or m < 0.01 or m > 1e6 then
		return nil
	end
	return v / m
end

local function canAct(f: Fighter): boolean
	if not f.alive then
		return false
	end
	local h = f.humanoid
	return h ~= nil and h.Health > 0 and f.root ~= nil and f.root.Parent ~= nil
end

local function stopCharging(f: Fighter)
	if f.charging then
		f.charging = false
		Fighters.setAttr(f, "Charging", false)
	end
end

local function facing(f: Fighter): Vector3
	local root = f.root :: BasePart
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

---------------------------------------------------------------------------
-- Melee
---------------------------------------------------------------------------
-- Returns the number of targets hit. aim (optional) overrides the facing direction.
function Combat.melee(f: Fighter, aim: Vector3?): number
	if not canAct(f) or f.blocking then
		return 0
	end
	if not Fighters.ready(f, "melee", C.meleeCooldown * 0.9) then
		return 0
	end
	stopCharging(f)
	local now = os.clock()
	local origin = Fighters.position(f) :: Vector3
	local look = aim or facing(f)
	local strength = Fighters.stat(f, "strength")
	local base = Formulas.meleeDamage(strength, f.form)
	local combo = if now - f.comboAt <= C.comboWindow then f.combo + 1 else 1
	local finisher = combo % C.comboFinisher == 0
	local hits = 0
	for _, v in Fighters.list do
		if hits >= 3 then
			break
		end
		if Fighters.hostile(f, v) then
			local vp = Fighters.position(v)
			if vp then
				local delta = vp - origin
				local dist = delta.Magnitude - v.radius
				if dist <= C.meleeRange then
					local flat = delta * Vector3.new(1, 0, 1)
					local dot = if flat.Magnitude > 0.1 then flat.Unit:Dot(look) else 1
					if dot >= C.meleeArc or dist < 4 then
						local crit = rng:NextNumber() < Combat.critChance(f)
						local dealt = Fighters.damage(f, v, "melee", base, {
							crit = crit,
							finisher = finisher,
							knock = if finisher then C.finisherKnockback else C.knockback,
						})
						if dealt > 0 then
							hits += 1
						end
					end
				end
			end
		end
	end
	if hits > 0 then
		f.combo = combo
		f.comboAt = now
	elseif now - f.comboAt > C.comboWindow then
		f.combo = 0
	end
	Remotes.fireAll("Fx", "swing", {
		u = if f.player then f.player.UserId else 0,
		i = f.id,
		c = if hits > 0 then combo else 0,
		f = finisher and hits > 0,
		h = hits,
	})
	if f.player and hits > 0 then
		Remotes.fire("Combat", f.player, "combo", combo)
	end
	return hits
end

---------------------------------------------------------------------------
-- Ki blast
---------------------------------------------------------------------------
function Combat.blast(f: Fighter, dir: Vector3, free: boolean?): boolean
	if not canAct(f) or f.blocking then
		return false
	end
	if not free then
		if f.ki + 1e-6 < C.blastCost or not Fighters.ready(f, "blast", C.blastCooldown * 0.9) then
			return false
		end
		Fighters.spendKi(f, C.blastCost)
	end
	stopCharging(f)
	local origin = (Fighters.position(f) :: Vector3) + dir * 2.5 + Vector3.new(0, 0.6, 0)
	spawnProjectile(f, origin, dir, {
		speed = C.blastSpeed,
		range = C.blastRange,
		radius = C.blastRadius,
		kind = "blast",
		damage = Formulas.blastDamage(Fighters.stat(f, "ki"), f.form),
		knock = 18,
	})
	if f.player then
		Hooks.fire("blast", f.player)
	end
	return true
end

---------------------------------------------------------------------------
-- Beam (hold to charge, release to fire)
---------------------------------------------------------------------------
function Combat.beamStart(f: Fighter): boolean
	if not canAct(f) or f.blocking or f.beamStart then
		return false
	end
	if (f.cd.beam or 0) > os.clock() or f.ki < C.beamCostMin then
		return false
	end
	stopCharging(f)
	f.beamStart = os.clock()
	Fighters.setAttr(f, "Beam", true)
	return true
end

-- charge (optional, 0..1) lets the server fire a beam for a dummy / auto-play.
function Combat.beamRelease(f: Fighter, dir: Vector3, forcedCharge: number?): (boolean, number)
	local started = f.beamStart
	f.beamStart = nil
	Fighters.setAttr(f, "Beam", false)
	if not canAct(f) then
		return false, 0
	end
	local held: number
	if forcedCharge then
		held = forcedCharge * C.beamMaxCharge
	elseif started then
		held = os.clock() - started
	else
		return false, 0
	end
	if held < C.beamMinCharge then
		return false, 0
	end
	local charge = math.clamp(held / C.beamMaxCharge, 0, 1)
	local cost = Formulas.beamCost(charge)
	if f.ki < cost then
		-- fire what the bar allows
		charge = math.clamp((f.ki - C.beamCostMin) / (C.beamCostMax - C.beamCostMin), 0, charge)
		cost = math.min(f.ki, Formulas.beamCost(charge))
	end
	if f.ki < C.beamCostMin - 1e-6 then
		return false, 0
	end
	Fighters.spendKi(f, cost)
	f.cd.beam = os.clock() + C.beamCooldown
	local origin = (Fighters.position(f) :: Vector3) + dir * 3 + Vector3.new(0, 0.4, 0)
	local radius = C.beamRadius * (0.6 + 0.4 * charge)
	local damage = Formulas.beamDamage(Fighters.stat(f, "ki"), f.form, charge)
	local hits = 0
	for _, v in Fighters.list do
		if Fighters.hostile(f, v) then
			local vp = Fighters.position(v)
			if vp then
				local t = (vp - origin):Dot(dir)
				if t >= -2 and t <= C.beamRange then
					local closest = origin + dir * math.max(t, 0)
					if (vp - closest).Magnitude <= radius + v.radius then
						local dealt = Fighters.damage(f, v, "beam", damage, { knock = 55 * (0.5 + charge), from = origin, pvpScale = 0.3 + 0.7 * charge })
						if dealt > 0 then
							hits += 1
						end
					end
				end
			end
		end
	end
	Remotes.fireAll("Fx", "beam", {
		o = origin,
		d = dir,
		l = C.beamRange,
		z = radius,
		c = charge,
		f = f.form,
		u = if f.player then f.player.UserId else 0,
		i = f.id,
	})
	if f.player then
		Hooks.fire("beam", f.player, hits)
	end
	return true, hits
end

---------------------------------------------------------------------------
-- Block / charge / dash / fly
---------------------------------------------------------------------------
function Combat.setBlock(f: Fighter, on: boolean)
	if not canAct(f) then
		on = false
	end
	f.blocking = on
	if on then
		stopCharging(f)
	end
	Fighters.setAttr(f, "Blocking", on)
end

function Combat.setCharge(f: Fighter, on: boolean)
	if not canAct(f) or f.blocking then
		on = false
	end
	if on and not f.charging and f.player then
		Hooks.fire("charge", f.player)
	end
	f.charging = on
	Fighters.setAttr(f, "Charging", on)
end

function Combat.dash(f: Fighter): boolean
	if not canAct(f) or f.ki < C.dashCost then
		return false
	end
	if not Fighters.ready(f, "dash", C.dashCooldown * 0.9) then
		return false
	end
	Fighters.spendKi(f, C.dashCost)
	stopCharging(f)
	f.invulnerableUntil = math.max(f.invulnerableUntil, os.clock() + C.dashIFrames)
	Remotes.fireAll("Fx", "dash", { u = if f.player then f.player.UserId else 0, i = f.id, p = Fighters.position(f) })
	if f.player then
		Hooks.fire("dash", f.player)
	end
	return true
end

function Combat.setFly(f: Fighter, on: boolean)
	if not canAct(f) then
		on = false
	end
	if on and not f.flying and f.player then
		Hooks.fire("fly", f.player)
	end
	f.flying = on
	Fighters.setAttr(f, "Flying", on)
end

---------------------------------------------------------------------------
-- Transformations
---------------------------------------------------------------------------
-- Unlocks forms by power (kept through rebirths). Returns the highest unlocked index.
function Combat.refreshForms(player: Player): number
	local p = Data.get(player)
	if not p then
		return 0
	end
	local best = Formulas.bestForm(math.max(p.bestPower, State.power(p)), p.rebirths)
	if best > p.forms then
		local first = p.forms + 1
		p.forms = best
		State.dirty(player)
		for i = first, best do
			Remotes.fire("Combat", player, "formUnlocked", i)
			Hooks.fire("formUnlocked", player, i)
		end
	end
	return p.forms
end

function Combat.setForm(f: Fighter, index: number): boolean
	if not canAct(f) then
		return false
	end
	local maxForm = #Config.Forms
	if f.player then
		maxForm = Combat.refreshForms(f.player)
	end
	if index ~= index or index < 0 or index > maxForm or index % 1 ~= 0 then
		return false
	end
	if index == f.form then
		return true
	end
	if index > 0 then
		if f.ki < 0.05 or not Fighters.ready(f, "form", 0.8) then
			return false
		end
	end
	f.form = index
	Fighters.setAttr(f, "Form", index)
	Remotes.fireAll("Fx", "form", { u = if f.player then f.player.UserId else 0, i = f.id, f = index, p = Fighters.position(f) })
	if f.player and index > 0 then
		Hooks.fire("form", f.player, index)
	end
	return true
end

---------------------------------------------------------------------------
-- Techniques
---------------------------------------------------------------------------
function Combat.technique(f: Fighter, id: string, dir: Vector3): boolean
	local t = Config.TechniqueById[id]
	if not t or not canAct(f) or f.blocking then
		return false
	end
	if f.player then
		local p = Data.get(f.player)
		if not p or not p.techniques[id] then
			return false
		end
	end
	if f.ki < t.kiCost or (f.cd["t_" .. id] or 0) > os.clock() then
		return false
	end
	f.cd["t_" .. id] = os.clock() + t.cooldown
	Fighters.spendKi(f, t.kiCost)
	stopCharging(f)
	local kiStat = Fighters.stat(f, "ki")
	Remotes.fireAll("Fx", "tech", { u = if f.player then f.player.UserId else 0, i = f.id, t = id, p = Fighters.position(f), d = dir })
	if id == "pulse_volley" then
		task.spawn(function()
			for n = 1, t.shots do
				if not canAct(f) then
					break
				end
				local spread = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), math.rad(rng:NextNumber(-7, 7)), 0)
				local origin = (Fighters.position(f) :: Vector3) + dir * 2.5 + Vector3.new(0, 0.8, 0)
				spawnProjectile(f, origin, spread.LookVector, {
					speed = C.blastSpeed * 1.15,
					range = C.blastRange,
					radius = C.blastRadius,
					kind = "tech",
					damage = Formulas.blastDamage(kiStat, f.form) * t.dmgMult,
					knock = 14,
				})
				if n < t.shots then
					task.wait(0.09)
				end
			end
		end)
	elseif id == "meteor_dive" then
		task.delay(0.4, function()
			if not canAct(f) then
				return
			end
			local at = Fighters.position(f) :: Vector3
			local damage = Formulas.meleeDamage(Fighters.stat(f, "strength"), f.form) * t.dmgMult
			for _, v in Fighters.list do
				if Fighters.hostile(f, v) then
					local vp = Fighters.position(v)
					if vp and (vp - at).Magnitude <= t.radius + v.radius then
						Fighters.damage(f, v, "tech", damage, { knock = 90, from = at })
					end
				end
			end
			Remotes.fireAll("Fx", "shock", { p = at, r = t.radius, f = f.form })
		end)
	elseif id == "sunfall" then
		local origin = (Fighters.position(f) :: Vector3) + Vector3.new(0, 9, 0) + dir * 3
		spawnProjectile(f, origin, dir, {
			speed = t.speed,
			range = 170,
			radius = 9,
			kind = "tech",
			damage = Formulas.blastDamage(kiStat, f.form) * t.dmgMult,
			aoe = t.radius,
			knock = 80,
			color = "sun",
		})
	end
	if f.player then
		Hooks.fire("technique", f.player, id)
	end
	return true
end

---------------------------------------------------------------------------
-- Ki / forms / healing loop (10 Hz)
---------------------------------------------------------------------------
local function tick(dt: number)
	local now = os.clock()
	for _, f in Fighters.list do
		if f.kind ~= "player" or not f.alive then
			continue
		end
		local player = f.player
		local regen = C.kiRegen
		local drainMult = 1
		if player then
			local p = Data.get(player)
			if p then
				regen *= 1 + Formulas.upgradeValue("kiRegen", p.upgrades.kiRegen or 0)
			end
			if State.owns(player, "KiMastery") then
				regen *= Config.KiMasteryRegen
				drainMult = Config.KiMasteryDrain
			end
		end
		local delta = 0
		if f.charging then
			delta += C.kiChargeRegen * (regen / C.kiRegen) * dt
		elseif not f.beamStart and f.form == 0 then
			-- a form burns ki: no passive regen while transformed (charging still works)
			delta += regen * dt
		end
		if f.form > 0 then
			local form = Config.Forms[f.form]
			delta -= form.drain * drainMult * dt
		end
		f.ki = math.clamp(f.ki + delta, 0, 1)
		if f.form > 0 and f.ki <= 0 then
			f.form = 0
			Fighters.setAttr(f, "Form", 0)
			Remotes.fireAll("Fx", "form", { u = if player then player.UserId else 0, i = f.id, f = 0, p = Fighters.position(f) })
			if player then
				Remotes.notify(player, { key = "msg.form_out_of_ki" }, "info")
			end
		end
		-- replicate the bar in 2% steps
		local shown = math.floor(f.ki * 50 + 0.5) / 50
		Fighters.setAttr(f, "Ki", shown)
		-- out-of-combat healing
		local h = f.humanoid
		if h and h.Health > 0 and h.Health < h.MaxHealth and now - f.lastDamagedAt > C.outOfCombatDelay then
			h.Health = math.min(h.MaxHealth, h.Health + h.MaxHealth * C.outOfCombatHeal * dt)
		end
	end
end

---------------------------------------------------------------------------
-- Act remote
---------------------------------------------------------------------------
local budget: { [Player]: { tokens: number, t: number } } = {}
local ACT_RATE, ACT_BURST = 40, 60

local function onAct(player: Player, kind: any, a: any)
	if type(kind) ~= "string" or not State.ready[player] then
		return
	end
	local b = budget[player]
	local now = os.clock()
	if not b then
		b = { tokens = ACT_BURST, t = now }
		budget[player] = b
	end
	b.tokens = math.min(ACT_BURST, b.tokens + (now - b.t) * ACT_RATE)
	b.t = now
	if b.tokens < 1 then
		return
	end
	b.tokens -= 1
	local f = Fighters.ofPlayer(player)
	if not f then
		return
	end
	if kind == "melee" then
		local aim = unit(a)
		if aim then
			local flat = aim * Vector3.new(1, 0, 1)
			aim = if flat.Magnitude > 0.05 then flat.Unit else nil
		end
		Combat.melee(f, aim)
		Combat.onManualRep(player)
	elseif kind == "blast" then
		local dir = unit(a)
		if dir then
			Combat.blast(f, dir)
		end
	elseif kind == "beamStart" then
		Combat.beamStart(f)
	elseif kind == "beamRelease" then
		local dir = unit(a)
		if dir then
			Combat.beamRelease(f, dir)
		else
			f.beamStart = nil
			Fighters.setAttr(f, "Beam", false)
		end
	elseif kind == "block" then
		Combat.setBlock(f, a == true)
	elseif kind == "charge" then
		Combat.setCharge(f, a == true)
	elseif kind == "dash" then
		Combat.dash(f)
	elseif kind == "fly" then
		Combat.setFly(f, a == true)
	elseif kind == "form" then
		if type(a) == "number" then
			Combat.setForm(f, a)
		end
	elseif kind == "tech" then
		if type(a) == "table" and type(a.id) == "string" then
			local dir = unit(a.dir)
			if dir then
				Combat.technique(f, a.id, dir)
			end
		end
	end
end

function Combat.init()
	Remotes.ActEvent.OnServerEvent:Connect(onAct)
	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
	end)
	RunService.Heartbeat:Connect(stepProjectiles)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			tick(now - last)
			last = now
		end
	end)
end

return Combat
