--!strict
-- Stat training: manual reps (every punch is a rep of the selected stat, token bucket),
-- automatic reps, training zones (multiplier while standing inside with enough power) and
-- the movement stats (walk speed / jump power from Agility and Jump).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Fighters = require(script.Parent.Fighters)
local Combat = require(script.Parent.Combat)
local M = Locale.m

local Training = {}

local bucket: { [Player]: { tokens: number, t: number } } = {}
local autoAcc: { [Player]: number } = {}

-- Adds n reps of a stat. Returns the points gained.
function Training.rep(player: Player, stat: string, n: number): number
	local p = Data.get(player)
	if not p or n <= 0 or p.stats[stat] == nil then
		return 0
	end
	local gain = State.gainPerRep(player, p, stat) * n
	p.stats[stat] += gain
	p.totalReps += n
	local power = State.power(p)
	if power > p.bestPower then
		p.bestPower = power
		Combat.refreshForms(player)
	end
	local zone = State.zone[player]
	Hooks.fire("reps", player, n, stat, if zone and not zone.locked then zone.id else "")
	State.touch(player)
	return gain
end

-- One manual rep (called for every punch the client sends), capped by a token bucket.
function Training.manual(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local b = bucket[player]
	local now = os.clock()
	if not b then
		b = { tokens = Config.Train.manualBurst, t = now }
		bucket[player] = b
	end
	b.tokens = math.min(Config.Train.manualBurst, b.tokens + (now - b.t) * Config.Train.manualPerSecond)
	b.t = now
	if b.tokens < 1 then
		return
	end
	b.tokens -= 1
	Training.rep(player, p.settings.stat, 1)
end

-- Zone the player is standing in (on their current planet).
local function findZone(player: Player, p: Data.Profile): { id: string, mult: number, locked: boolean }?
	local f = Fighters.ofPlayer(player)
	local pos = f and Fighters.position(f)
	if not pos then
		return nil
	end
	local pl = Config.Planets[p.planet]
	local cx, _, cz = Config.planetCenter(p.planet)
	for _, z in pl.zones do
		local dx, dz = pos.X - (cx + z.offset[1]), pos.Z - (cz + z.offset[3])
		if dx * dx + dz * dz <= z.radius * z.radius and pos.Y < 140 then
			return { id = z.id, mult = z.mult, locked = math.max(State.power(p), p.bestPower) < z.reqPower }
		end
	end
	return nil
end

function Training.applyMovement(player: Player)
	local p = Data.get(player)
	local f = Fighters.ofPlayer(player)
	local h = f and f.humanoid
	if not p or not f or not h or h.Health <= 0 then
		return
	end
	local speed = if f.charging or f.beamStart then 0 else Formulas.walkSpeed(p.stats.agility)
	if f.blocking then
		speed *= 0.45
	end
	if math.abs(h.WalkSpeed - speed) > 0.05 then
		h.WalkSpeed = speed
	end
	local jump = Formulas.jumpPower(p.stats.jump)
	h.UseJumpPower = true
	if math.abs(h.JumpPower - jump) > 0.05 then
		h.JumpPower = jump
	end
	local char = f.char
	if char then
		local fly = Formulas.flySpeed(p.stats.agility, State.owns(player, "FastFlight") and not f.inArena) -- normalized in the PvP arena
		if char:GetAttribute("FlySpeed") ~= fly then
			char:SetAttribute("FlySpeed", fly)
		end
		local power = State.power(p)
		if char:GetAttribute("Power") ~= power then
			char:SetAttribute("Power", power)
		end
	end
end

function Training.forget(player: Player)
	bucket[player] = nil
	autoAcc[player] = nil
end

function Training.init()
	Combat.onManualRep = Training.manual

	Remotes.handle("SetStat", function(player, payload)
		local p = Data.get(player)
		local stat = payload.stat
		if not p or type(stat) ~= "string" or not table.find(Config.Stats, stat) then
			return false, M("msg.bad_request")
		end
		p.settings.stat = stat
		State.dirty(player)
		return true
	end)

	Remotes.handle("SetSetting", function(player, payload)
		local p = Data.get(player)
		local key, value = payload.key, payload.value
		if not p or type(key) ~= "string" or type(value) ~= "boolean" then
			return false, M("msg.bad_request")
		end
		if key ~= "autoTrain" and key ~= "autoCharge" and key ~= "autoFight" and key ~= "music" and key ~= "sfx" and key ~= "lite" and key ~= "shake" then
			return false, M("msg.bad_request")
		end
		p.settings[key] = value
		State.dirty(player)
		return true
	end)

	Remotes.handle("BuyGear", function(player)
		local p = Data.get(player)
		if not p then
			return false, M("msg.error")
		end
		local nextTier = Config.Gear[p.gear + 1]
		if not nextTier then
			return false, M("msg.maxed")
		end
		if not State.spendSparks(player, nextTier.cost) then
			return false, M("msg.need_sparks")
		end
		p.gear += 1
		Hooks.fire("gear", player, p.gear)
		State.dirty(player)
		return true, p.gear
	end)

	-- zones + movement (4 Hz), auto-train (accumulated per player)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				if not p or not State.ready[player] then
					continue
				end
				local zone = findZone(player, p)
				local prev = State.zone[player]
				if (zone and zone.id) ~= (prev and prev.id) or (zone and prev and zone.locked ~= prev.locked) then
					State.zone[player] = zone
					State.dirty(player)
					if zone and zone.locked then
						Remotes.notify(player, M("msg.zone_locked", { zone = M("zone." .. zone.id), power = Format.abbrev(Config.ZoneById[zone.id].reqPower) }), "error")
					end
				end
				Training.applyMovement(player)
				if p.settings.autoTrain then
					local f = Fighters.ofPlayer(player)
					if f and f.alive then
						local acc = (autoAcc[player] or 0) + dt * State.autoRate(player, p)
						local n = math.floor(acc)
						autoAcc[player] = acc - n
						if n > 0 then
							Training.rep(player, p.settings.stat, n)
						end
					end
				end
			end
		end
	end)
end

return Training
