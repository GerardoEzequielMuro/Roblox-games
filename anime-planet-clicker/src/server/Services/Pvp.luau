--!strict
-- The Meteor Arena: opt-in PvP. Everything outside the arena circle is safe; inside, players
-- zap each other with their mining tool. Arena HP is its own bar (nobody really dies): a KO
-- sends you back to the lobby ring and pays the winner. Damage depends on the two mining
-- powers but is clamped hard, and new players carry a Rookie Shield.
--   * spawn protection for the first seconds inside
--   * Rookie Shield: under Config.Pvp.rookieSeconds of play time, players cannot hurt you
--     until you attack one of them
--   * sparring drones (bots) keep the arena alive when nobody else is around
-- Combatants are generic (player / bot / dummy) so the playtest can stage a full fight.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Progression = require(script.Parent.Progression)
local Hooks = require(script.Parent.Hooks)

local Pvp = {}

local C = Config.Pvp

export type Combatant = {
	id: number, -- UserId for players, negative for bots and dummies
	kind: string, -- "player" | "bot" | "dummy"
	player: Player?,
	hp: number,
	power: number, -- bots / dummies (players use their live mining power)
	pos: Vector3, -- bots / dummies
	lastZap: number,
	lastDamaged: number,
	protectedUntil: number,
	aggro: boolean, -- attacked a player: the Rookie Shield is gone for this visit
	playTime: number, -- dummies only (players read the profile)
	inArena: boolean,
	respawnAt: number?,
	model: Model?,
	home: Vector3?,
}

local combatants: { [number]: Combatant } = {}
Pvp.combatants = combatants
local rng = Random.new()
local center = Vector3.new(Config.ArenaCenter[1], Config.ArenaCenter[2], Config.ArenaCenter[3])

local function positionOf(c: Combatant): Vector3?
	if c.player then
		local char = c.player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		return if root then root.Position else nil
	end
	return c.pos
end

local function powerOf(c: Combatant): number
	if c.player then
		local p = Data.get(c.player)
		return if p then State.basePower(c.player, p) else 1
	end
	return c.power
end

local function isRookie(c: Combatant): boolean
	if c.kind == "bot" then
		return false
	end
	local playTime = c.playTime
	if c.player then
		local p = Data.get(c.player)
		playTime = if p then p.playTime else 0
	end
	return playTime < C.rookieSeconds and not c.aggro
end
Pvp.isRookie = isRookie

local function push(c: Combatant)
	if c.player then
		Remotes.fire("Pvp", c.player, {
			kind = "self",
			hp = c.hp,
			max = C.maxHp,
			inArena = c.inArena,
			rookie = isRookie(c),
			protected = math.max(0, c.protectedUntil - os.clock()),
		})
	end
	if c.model then
		c.model:SetAttribute("Hp", c.hp)
	end
end

local function knockOut(attacker: Combatant, target: Combatant)
	local now = os.clock()
	if attacker.player then
		local p = Data.get(attacker.player)
		if p then
			local byPlayer = target.kind ~= "bot"
			local points = if byPlayer then C.koPoints else C.botPoints
			local stardust = State.income(attacker.player, p) * (if byPlayer then C.koStardustSeconds else C.botStardustSeconds)
			p.arenaPoints += points
			p.arenaKos += 1
			State.addStardust(attacker.player, math.max(25, stardust), false)
			State.dirty(attacker.player)
			Remotes.fire("Pvp", attacker.player, { kind = "ko", points = points, stardust = math.max(25, stardust), bot = not byPlayer })
			Hooks.fire("arenaKo", attacker.player, byPlayer)
		end
	end
	if target.player then
		target.hp = C.maxHp
		target.inArena = false
		target.aggro = false
		Remotes.fire("Pvp", target.player, { kind = "down", by = attacker.id })
		Progression.teleportTo(target.player, Layout.arenaSpawn())
	else
		target.hp = 0
		target.respawnAt = now + C.botRespawn
		if target.model then
			target.model:SetAttribute("Down", true)
		end
	end
	push(target)
end

-- One zap from attacker to target with every rule applied. Returns ok, reason / damage.
local function resolve(attacker: Combatant, target: Combatant): (boolean, any)
	local now = os.clock()
	if attacker == target then
		return false, "self"
	end
	if not attacker.inArena or attacker.respawnAt then
		return false, "attacker_outside"
	end
	if not target.inArena or target.respawnAt then
		return false, "target_outside"
	end
	if now - attacker.lastZap < (if attacker.kind == "bot" then C.botCooldown else C.cooldown) - 0.05 then
		return false, "cooldown"
	end
	local a, t = positionOf(attacker), positionOf(target)
	if not a or not t or (a - t).Magnitude > C.range + 4 then
		return false, "range"
	end
	attacker.lastZap = now
	attacker.protectedUntil = 0 -- attacking ends your own spawn protection
	if target.protectedUntil > now then
		return false, "protected"
	end
	local targetIsPerson = target.kind ~= "bot"
	if attacker.kind ~= "bot" and targetIsPerson then
		if isRookie(target) then
			return false, "rookie"
		end
		attacker.aggro = true -- a rookie who attacks a player drops the shield
	end
	local damage = if attacker.kind == "bot" then C.botDamage else Formulas.pvpDamage(powerOf(attacker), powerOf(target))
	target.hp = math.max(0, target.hp - damage)
	target.lastDamaged = now
	Remotes.fireAll("Pvp", { kind = "zap", a = attacker.id, t = target.id, dmg = damage, hp = target.hp })
	if target.hp <= 0 then
		knockOut(attacker, target)
	else
		push(target)
	end
	push(attacker)
	return true, damage
end
Pvp.resolve = resolve

local function combatantFor(player: Player): Combatant
	local c = combatants[player.UserId]
	if not c then
		c = { id = player.UserId, kind = "player", player = player, hp = C.maxHp, power = 1, pos = Vector3.zero, lastZap = 0, lastDamaged = 0, protectedUntil = 0, aggro = false, playTime = 0, inArena = false }
		combatants[player.UserId] = c
	end
	return c
end
Pvp.combatantFor = combatantFor

---------------------------------------------------------------------------
-- Sparring drones
---------------------------------------------------------------------------
local function buildBot(index: number): Model
	local model = Instance.new("Model")
	model.Name = "ArenaBot" .. index
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = offset
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local body = part("Body", Vector3.new(4.4, 4.4, 4.4), CFrame.new(), Color3.fromRGB(70, 76, 96), Enum.Material.Metal, Enum.PartType.Ball)
	part("Visor", Vector3.new(2.6, 1.1, 0.6), CFrame.new(0, 0.35, -1.95), Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
	part("Band", Vector3.new(0.7, 5.2, 5.2), CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 170, 50), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	part("FinL", Vector3.new(0.5, 2.4, 1.6), CFrame.new(-2.6, 0.4, 0.4) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(235, 238, 245), Enum.Material.SmoothPlastic)
	part("FinR", Vector3.new(0.5, 2.4, 1.6), CFrame.new(2.6, 0.4, 0.4) * CFrame.Angles(0, 0, math.rad(-20)), Color3.fromRGB(235, 238, 245), Enum.Material.SmoothPlastic)
	part("Muzzle", Vector3.new(1, 1, 1.8), CFrame.new(0, -0.9, -2.1), Color3.fromRGB(40, 44, 60), Enum.Material.Metal)
	model.PrimaryPart = body
	-- StreamingEnabled: the drone streams in whole or not at all (never a floating visor)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("BotId", -index)
	model:SetAttribute("Hp", C.botHp)
	model:SetAttribute("MaxHp", C.botHp)
	return model
end

local function botHome(index: number): Vector3
	local a = (index - 1) / math.max(1, C.bots) * math.pi * 2 + 0.6
	return center + Vector3.new(math.cos(a) * 26, 6, math.sin(a) * 26)
end

local function stepBots(dt: number)
	local now = os.clock()
	for _, bot in combatants do
		if bot.kind ~= "bot" then
			continue
		end
		if bot.respawnAt then
			if bot.respawnAt <= now then
				bot.respawnAt = nil
				bot.hp = C.botHp
				bot.pos = bot.home or bot.pos
				if bot.model then
					bot.model:SetAttribute("Down", nil)
				end
				push(bot)
			else
				continue
			end
		end
		-- nearest fighter that is not protected
		local target: Combatant?, best = nil, math.huge
		for _, c in combatants do
			if c.kind ~= "bot" and c.inArena and c.protectedUntil <= now then
				local pos = positionOf(c)
				if pos then
					local d = (pos - bot.pos).Magnitude
					if d < best then
						target, best = c, d
					end
				end
			end
		end
		local goal = bot.home or bot.pos
		local look = bot.pos + Vector3.new(0, 0, -1)
		if target then
			local tp = positionOf(target) :: Vector3
			look = tp
			local flat = Vector3.new(tp.X, bot.pos.Y, tp.Z)
			goal = if best > 14 then flat else bot.pos
			if best <= C.range then
				resolve(bot, target)
			end
		end
		local delta = goal - bot.pos
		if delta.Magnitude > 0.5 then
			bot.pos += delta.Unit * math.min(delta.Magnitude, C.botSpeed * dt)
		end
		-- stay inside the arena circle
		local off = Vector3.new(bot.pos.X - center.X, 0, bot.pos.Z - center.Z)
		if off.Magnitude > Config.ArenaRadius - 6 then
			off = off.Unit * (Config.ArenaRadius - 6)
			bot.pos = Vector3.new(center.X + off.X, bot.pos.Y, center.Z + off.Z)
		end
		if bot.model then
			local bob = math.sin(now * 2 + bot.id) * 0.6
			local lookFlat = Vector3.new(look.X, bot.pos.Y + bob, look.Z)
			local at = bot.pos + Vector3.new(0, bob, 0)
			if (lookFlat - at).Magnitude > 0.1 then
				bot.model:PivotTo(CFrame.lookAt(at, lookFlat))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
local function stepPlayers(dt: number): boolean
	local now = os.clock()
	local anyone = false
	for _, player in Players:GetPlayers() do
		if not State.ready[player] then
			continue
		end
		local c = combatantFor(player)
		local pos = positionOf(c)
		local inside = pos ~= nil and Layout.inArena(pos.X, pos.Z)
		if pos and Layout.onArenaPlatform(pos.X, pos.Z) then
			anyone = true
		end
		if inside and not c.inArena then
			c.inArena = true
			c.hp = C.maxHp
			c.protectedUntil = now + C.spawnProtection
			c.aggro = false
			push(c)
		elseif not inside and c.inArena then
			c.inArena = false
			c.hp = C.maxHp
			c.aggro = false
			push(c)
		elseif inside and c.hp < C.maxHp and now - c.lastDamaged > C.regenDelay then
			c.hp = math.min(C.maxHp, c.hp + C.regenPerSecond * dt)
			push(c)
		end
	end
	for _, c in combatants do
		if c.kind == "dummy" and c.inArena then
			anyone = true
		end
	end
	return anyone
end

-- Test helper: a stand-in for a second player (same rules as a real one).
function Pvp.spawnDummy(id: number, position: Vector3, power: number, playTime: number): Combatant
	local c: Combatant = { id = id, kind = "dummy", hp = C.maxHp, power = power, pos = position, lastZap = 0, lastDamaged = 0, protectedUntil = 0, aggro = false, playTime = playTime, inArena = Layout.inArena(position.X, position.Z) }
	combatants[id] = c
	return c
end

function Pvp.removeDummy(id: number)
	local c = combatants[id]
	if c and c.kind == "dummy" then
		combatants[id] = nil
	end
end

function Pvp.forget(player: Player)
	combatants[player.UserId] = nil
end

function Pvp.init(parent: Instance?)
	for i = 1, C.bots do
		local model = buildBot(i)
		local home = botHome(i)
		model:PivotTo(CFrame.new(home))
		model.Parent = parent or workspace
		combatants[-i] = { id = -i, kind = "bot", hp = C.botHp, power = 1, pos = home, home = home, lastZap = rng:NextNumber(), lastDamaged = 0, protectedUntil = 0, aggro = false, playTime = 0, inArena = true, model = model }
	end

	Remotes.ZapEvent.OnServerEvent:Connect(function(player: Player, targetId: any)
		if type(targetId) ~= "number" or targetId ~= targetId or not State.ready[player] then
			return
		end
		local target = combatants[math.floor(targetId)]
		if not target then
			return
		end
		local ok, reason = resolve(combatantFor(player), target)
		if not ok and (reason == "rookie" or reason == "protected") then
			Remotes.fire("Pvp", player, { kind = "blocked", reason = reason, t = target.id })
		end
	end)

	State.extras.pvp = function(player, _p)
		local c = combatantFor(player)
		return { hp = c.hp, max = C.maxHp, inArena = c.inArena, rookie = isRookie(c), rookieSeconds = C.rookieSeconds }
	end

	-- one loop; it idles while nobody is on the arena platform
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.2)
			local now = os.clock()
			local dt = math.min(now - last, 0.5)
			last = now
			local ok, err = pcall(function()
				if stepPlayers(dt) then
					stepBots(dt)
				end
			end)
			if not ok then
				warn("[Pvp]", err)
			end
		end
	end)
end

function Pvp.message(reason: string): Locale.Message
	return M("pvp." .. reason)
end

return Pvp
