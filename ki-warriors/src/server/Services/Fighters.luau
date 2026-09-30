--!strict
-- Combatant registry and the one damage pipeline everything goes through.
-- A Fighter is a player, an enemy (NPC) or a "dummy" (a server-driven stand-in for another
-- player, used by the playtest and the showcase). The server owns HP, ki, forms, cooldowns.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)

local Fighters = {}

export type Fighter = {
	id: number,
	kind: string, -- "player" | "npc"
	player: Player?,
	dummy: boolean?,
	char: Model?,
	root: BasePart?,
	humanoid: Humanoid?,
	radius: number,
	alive: boolean,
	ki: number,
	form: number,
	blocking: boolean,
	charging: boolean,
	flying: boolean,
	invulnerableUntil: number,
	lastDamagedAt: number,
	lastAttackAt: number,
	combo: number,
	comboAt: number,
	cd: { [string]: number },
	beamStart: number?,
	inArena: boolean,
	-- npc
	def: any?,
	hp: number,
	maxHp: number,
	contributions: { [Player]: number }?,
	knock: Vector3?,
	npc: any?, -- AI state (Npcs service)
	-- dummy
	dstats: { [string]: number }?,
	dname: string?,
	protected: boolean?,
}

local nextId = 0
local list: { Fighter } = {}
local byPlayer: { [Player]: Fighter } = {}
local byId: { [number]: Fighter } = {}

Fighters.list = list
-- PvP rule, installed by the Arena service. Default: players can never hurt each other.
Fighters.pvpRule = function(_attacker: Fighter, _victim: Fighter): boolean
	return false
end
-- Extra damage multiplier against enemies (Titan Seed), installed by the Items service.
-- Never applied to players: PvP damage does not use `raw` at all.
Fighters.damageBoost = function(_attacker: Fighter?, _victim: Fighter): number
	return 1
end
Fighters.onNpcDeath = function(_f: Fighter, _killer: Fighter?) end
Fighters.onPlayerKill = function(_killer: Fighter, _victim: Fighter) end

local function new(kind: string): Fighter
	nextId += 1
	local f: Fighter = {
		id = nextId,
		kind = kind,
		radius = 2,
		alive = true,
		ki = 1,
		form = 0,
		blocking = false,
		charging = false,
		flying = false,
		invulnerableUntil = 0,
		lastDamagedAt = -100,
		lastAttackAt = -100,
		combo = 0,
		comboAt = -100,
		cd = {},
		inArena = false,
		hp = 0,
		maxHp = 0,
	}
	table.insert(list, f)
	byId[f.id] = f
	return f
end

function Fighters.ofPlayer(player: Player): Fighter?
	return byPlayer[player]
end

function Fighters.byId(id: number): Fighter?
	return byId[id]
end

function Fighters.remove(f: Fighter)
	f.alive = false
	byId[f.id] = nil
	local i = table.find(list, f)
	if i then
		table.remove(list, i)
	end
	if f.player and byPlayer[f.player] == f then
		byPlayer[f.player] = nil
	end
end

function Fighters.position(f: Fighter): Vector3?
	local root = f.root
	if root and root.Parent then
		return root.Position
	end
	return nil
end

-- strength, ki, defense of a fighter (NPCs don't use these)
function Fighters.stat(f: Fighter, name: string): number
	if f.dstats then
		return f.dstats[name] or 0
	end
	if f.player then
		local p = Data.get(f.player)
		return if p then p.stats[name] or 0 else 0
	end
	return 0
end

function Fighters.power(f: Fighter): number
	if f.dstats then
		return Formulas.power(f.dstats)
	end
	if f.player then
		local p = Data.get(f.player)
		return if p then Formulas.power(p.stats) else 0
	end
	return 0
end

function Fighters.maxHp(f: Fighter): number
	if f.kind == "npc" then
		return f.maxHp
	end
	return Formulas.maxHp(Fighters.stat(f, "defense"))
end

function Fighters.hp(f: Fighter): number
	if f.kind == "npc" then
		return f.hp
	end
	local h = f.humanoid
	return if h then h.Health else 0
end

local function setAttr(f: Fighter, name: string, value: any)
	local char = f.char
	if char and char:GetAttribute(name) ~= value then
		char:SetAttribute(name, value)
	end
end
Fighters.setAttr = setAttr

-- Keeps Humanoid.MaxHealth in line with Defense, preserving the health fraction.
function Fighters.syncHealth(f: Fighter)
	local h = f.humanoid
	if not h or f.kind ~= "player" then
		return
	end
	local want = Fighters.maxHp(f)
	if math.abs(h.MaxHealth - want) >= 1 then
		local frac = if h.MaxHealth > 0 then h.Health / h.MaxHealth else 1
		h.MaxHealth = want
		if h.Health > 0 then
			h.Health = math.max(1, want * frac)
		end
	end
end

function Fighters.bindCharacter(f: Fighter, char: Model)
	f.char = char
	f.root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	f.humanoid = char:WaitForChild("Humanoid", 10) :: Humanoid?
	f.alive = true
	f.ki = 1
	f.form = 0
	f.blocking = false
	f.charging = false
	f.flying = false
	f.beamStart = nil
	f.combo = 0
	f.invulnerableUntil = os.clock() + Config.Combat.respawnInvulnerable
	local h = f.humanoid
	if h then
		h.MaxHealth = Fighters.maxHp(f)
		h.Health = h.MaxHealth
		h.Died:Connect(function()
			f.alive = false
			f.form = 0
			f.charging = false
			f.blocking = false
			Hooks.fire("playerDied", f)
		end)
	end
	char:SetAttribute("FighterId", f.id)
	char:SetAttribute("Ki", 1)
	char:SetAttribute("Form", 0)
	char:SetAttribute("Charging", false)
	char:SetAttribute("Blocking", false)
	char:SetAttribute("Flying", false)
	char:SetAttribute("Beam", false)
end

function Fighters.addPlayer(player: Player): Fighter
	local existing = byPlayer[player]
	if existing then
		return existing
	end
	local f = new("player")
	f.player = player
	byPlayer[player] = f
	return f
end

function Fighters.addNpc(def: any, root: BasePart, hp: number): Fighter
	local f = new("npc")
	f.def = def
	f.root = root
	f.hp = hp
	f.maxHp = hp
	f.radius = 2.2 * (def.scale or 1)
	f.contributions = {}
	return f
end

-- A server-driven player stand-in. `model` needs a Humanoid and a HumanoidRootPart.
function Fighters.addDummy(model: Model, stats: { [string]: number }, name: string?): Fighter
	local f = new("player")
	f.dummy = true
	f.dstats = stats
	f.dname = name or model.Name
	f.char = model
	f.root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	f.humanoid = model:FindFirstChildOfClass("Humanoid")
	local h = f.humanoid
	if h then
		h.MaxHealth = Fighters.maxHp(f)
		h.Health = h.MaxHealth
		h.Died:Connect(function()
			f.alive = false
		end)
	end
	model:SetAttribute("FighterId", f.id)
	model:SetAttribute("Form", 0)
	model:SetAttribute("Ki", 1)
	return f
end

-- Can `attacker` hurt `victim` at all?
function Fighters.hostile(attacker: Fighter, victim: Fighter): boolean
	if attacker == victim or not victim.alive then
		return false
	end
	if attacker.kind == "npc" then
		return victim.kind == "player" and not victim.dummy
	end
	if victim.kind == "npc" then
		return true
	end
	return Fighters.pvpRule(attacker, victim)
end

export type DamageOpts = {
	crit: boolean?,
	finisher: boolean?,
	knock: number?, -- knockback speed
	from: Vector3?, -- knockback origin (defaults to the attacker)
	fraction: number?, -- NPC -> player: damage as a fraction of max HP (world boss)
	pvpScale: number?,
	silent: boolean?,
}

-- Applies damage. Returns the amount dealt (0 = blocked by rules / invulnerable).
function Fighters.damage(attacker: Fighter?, victim: Fighter, kind: string, raw: number, opts: DamageOpts?): number
	local o: DamageOpts = opts or {}
	local now = os.clock()
	if not victim.alive then
		return 0
	end
	if attacker and not Fighters.hostile(attacker, victim) then
		return 0
	end
	local vpos = Fighters.position(victim)
	if not vpos then
		return 0
	end
	if victim.invulnerableUntil > now then
		if not o.silent then
			Remotes.fireAll("Fx", "dodge", { p = vpos, v = victim.id })
		end
		return 0
	end

	local dmg = raw
	local blocked = false
	if victim.kind == "npc" then
		dmg *= Fighters.damageBoost(attacker, victim)
		if o.crit then
			dmg *= Config.Combat.critMult
		end
		if o.finisher then
			dmg *= Config.Combat.finisherMult
		end
		dmg = math.min(dmg, victim.hp)
		victim.hp -= dmg
		if attacker and attacker.player and victim.contributions then
			victim.contributions[attacker.player] = (victim.contributions[attacker.player] or 0) + dmg
		end
		local root = victim.root
		if root then
			root:SetAttribute("Hp", victim.hp)
		end
	else
		blocked = victim.blocking
		if attacker and attacker.kind == "player" then
			-- PvP: fraction of the victim's bar, nudged by the power ratio
			dmg = Formulas.pvpDamage(kind, Fighters.power(attacker), Fighters.power(victim), Fighters.maxHp(victim), o.pvpScale)
			if o.finisher then
				dmg *= 1.6
			end
			if blocked then
				dmg *= 1 - Config.Combat.blockReduction
			end
		elseif o.fraction then
			dmg = Fighters.maxHp(victim) * o.fraction
			if blocked then
				dmg *= 1 - Config.Combat.blockReduction
			end
		else
			dmg = Formulas.mitigate(raw, victim.form, blocked)
		end
		local h = victim.humanoid
		if not h or h.Health <= 0 then
			return 0
		end
		dmg = math.min(dmg, h.Health)
		h.Health -= dmg
	end
	victim.lastDamagedAt = now
	if attacker then
		attacker.lastAttackAt = now
	end

	-- knockback
	local speed = o.knock or 0
	if speed > 0 and not blocked then
		local from = o.from or (attacker and Fighters.position(attacker)) or vpos
		local dir = (vpos - from) * Vector3.new(1, 0, 1)
		dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.new(0, 0, 1)
		local vel = dir * speed + Vector3.new(0, speed * 0.45, 0)
		if victim.kind == "npc" then
			if not (victim.def and victim.def.boss) then
				victim.knock = vel
			end
		elseif victim.dummy then
			local root = victim.root
			if root then
				root.AssemblyLinearVelocity = vel
			end
		elseif victim.player then
			Remotes.fire("Knock", victim.player, vel)
		end
	end

	if not o.silent then
		Remotes.fireAll("Fx", "hit", {
			p = vpos,
			d = dmg,
			k = kind,
			c = o.crit == true,
			f = o.finisher == true,
			b = blocked,
			a = if attacker and attacker.player then attacker.player.UserId else 0,
			v = victim.id,
			u = if victim.player then victim.player.UserId else 0,
		})
	end
	Hooks.fire("damage", attacker, victim, dmg, kind)

	-- death
	if victim.kind == "npc" then
		if victim.hp <= 0 then
			victim.alive = false
			Fighters.onNpcDeath(victim, attacker)
		end
	else
		local h = victim.humanoid
		if h and h.Health <= 0 then
			victim.alive = false
			if attacker and attacker.kind == "player" then
				Fighters.onPlayerKill(attacker, victim)
			end
		end
	end
	return dmg
end

-- Spend ki (fraction of the bar). Returns false when there isn't enough.
function Fighters.spendKi(f: Fighter, cost: number): boolean
	if f.ki + 1e-6 < cost then
		return false
	end
	f.ki = math.max(0, f.ki - cost)
	return true
end

function Fighters.ready(f: Fighter, name: string, cooldown: number): boolean
	local now = os.clock()
	if (f.cd[name] or 0) > now then
		return false
	end
	f.cd[name] = now + cooldown
	return true
end

function Fighters.init()
	Players.PlayerRemoving:Connect(function(player)
		local f = byPlayer[player]
		if f then
			Fighters.remove(f)
		end
	end)
	-- keep max HP in line with Defense
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, f in list do
				if f.kind == "player" and not f.dummy and f.alive and f.player and State.ready[f.player] then
					Fighters.syncHealth(f)
				end
			end
		end
	end)
end

return Fighters
