--!strict
-- PvP: only inside the Sky Coliseum. Everywhere else players cannot hurt each other.
--   * new-player protection (play time / power), which the player can switch off
--   * rating (win / loss, no farming the same victim), kills pay Sparks from the system
--   * Arena Rush: a short tournament window on a UTC schedule; top 3 scores get Gems
-- Installs Fighters.pvpRule and Fighters.onPlayerKill.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Fighters = require(script.Parent.Fighters)
local M = Locale.m

type Fighter = Fighters.Fighter
local P = Config.Pvp

local Arena = {}

local center = Vector3.zero
local lastKill: { [string]: number } = {} -- "killerId>victimKey" -> os.clock()
local rushScores: { [Player]: number } = {}
local rushOverride: number? = nil -- test / admin: rush active until this os.time()
local rushWasActive = false
local rushEndsAt = 0

function Arena.inside(pos: Vector3): boolean
	local d = (pos - center) * Vector3.new(1, 0, 1)
	return d.Magnitude <= Config.Arena.radius and pos.Y < center.Y + 140 and pos.Y > center.Y - 20
end

-- New players are shielded until they have played a while or grown past a power level.
function Arena.protected(f: Fighter): boolean
	if f.dummy then
		return f.protected == true
	end
	local player = f.player
	local p = player and Data.get(player)
	if not p then
		return true
	end
	if p.protectionOff then
		return false
	end
	return p.playTime < P.protectSeconds and math.max(State.power(p), p.bestPower) < P.protectPower
end

function Arena.rushActive(now: number): (boolean, number)
	if rushOverride and rushOverride > now then
		return true, rushOverride
	end
	local r = P.rush
	local phase = (now - r.offset) % r.every
	if phase < r.duration then
		return true, now - phase + r.duration
	end
	return false, now - phase + r.every
end

local function victimKey(v: Fighter): string
	return if v.player then tostring(v.player.UserId) else "d:" .. tostring(v.dname)
end

local function payload(): { [string]: any }
	local now = os.time()
	local active, at = Arena.rushActive(now)
	local top = {}
	for player, score in rushScores do
		table.insert(top, { name = player.DisplayName, id = player.UserId, score = score })
	end
	table.sort(top, function(a, b)
		return a.score > b.score
	end)
	while #top > 5 do
		table.remove(top)
	end
	return { rush = active, at = at, top = top, serverTime = now }
end

local function broadcast()
	Remotes.fireAll("Arena", payload())
end

local function endRush()
	local list = {}
	for player, score in rushScores do
		if player.Parent and score >= P.rush.minScore then
			table.insert(list, { player = player, score = score })
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	for i, entry in list do
		local prize = P.rush.prizes[i]
		if not prize then
			break
		end
		State.addGems(entry.player, prize.gems)
		Remotes.notify(entry.player, M("msg.rush_prize", { place = i, n = prize.gems }), "success")
	end
	if list[1] then
		Remotes.fireAll("Toast", { key = "toast.rush_winner", args = { player = list[1].player.DisplayName, score = list[1].score }, color = { 230, 70, 70 } })
	end
	table.clear(rushScores)
end

-- Test / admin: run a Rush for `seconds` starting now.
function Arena.forceRush(_player: Player?, seconds: number?): boolean
	rushOverride = os.time() + (seconds or 60)
	return true
end

function Arena.endRushNow(_player: Player?): boolean
	rushOverride = nil
	if rushWasActive then
		rushWasActive = false
		endRush()
		broadcast()
	end
	return true
end

local function onKill(killer: Fighter, victim: Fighter)
	local kp = killer.player and Data.get(killer.player)
	local vp = victim.player and Data.get(victim.player)
	local now = os.clock()
	local key = (if killer.player then tostring(killer.player.UserId) else "d:" .. tostring(killer.dname)) .. ">" .. victimKey(victim)
	local fresh = now - (lastKill[key] or -1e9) >= P.repeatKillSeconds
	lastKill[key] = now
	if vp and victim.player then
		vp.pvp.deaths += 1
		if fresh then
			vp.pvp.rating = math.max(P.minRating, vp.pvp.rating - P.lossRating)
		end
		State.dirty(victim.player)
		Remotes.notify(victim.player, M("msg.arena_lost", { player = if killer.player then killer.player.DisplayName else tostring(killer.dname) }), "error")
	end
	if kp and killer.player then
		kp.pvp.kills += 1
		local gained = 0
		if fresh then
			kp.pvp.rating += P.winRating
			gained = State.addSparks(killer.player, State.sparksForMinutes(kp, P.killSparkMinutes), false)
			local active = Arena.rushActive(os.time())
			if active then
				rushScores[killer.player] = (rushScores[killer.player] or 0) + 1
				broadcast()
			end
		end
		Hooks.fire("arenaWin", killer.player, fresh)
		State.dirty(killer.player)
		Remotes.fire("Combat", killer.player, "arenaKill", {
			name = if victim.player then victim.player.DisplayName else tostring(victim.dname),
			rating = kp.pvp.rating,
			sparks = gained,
			fresh = fresh,
		})
	end
	Remotes.fireAll("Fx", "ko", { p = Fighters.position(victim), u = if victim.player then victim.player.UserId else 0 })
end

function Arena.onReady(player: Player)
	Remotes.fire("Arena", player, payload())
end

function Arena.init(world: { [string]: any })
	center = world.arenaCenter or Vector3.zero

	Fighters.pvpRule = function(a: Fighter, v: Fighter): boolean
		if not a.inArena or not v.inArena then
			return false
		end
		return not Arena.protected(a) and not Arena.protected(v)
	end
	Fighters.onPlayerKill = onKill

	State.extras.arena = function(player, p)
		local f = Fighters.ofPlayer(player)
		return {
			protected = if f then Arena.protected(f) else true,
			protectionLeft = math.max(0, P.protectSeconds - p.playTime),
			protectPower = P.protectPower,
		}
	end

	Remotes.handle("SetProtection", function(player, payload)
		local p = Data.get(player)
		if not p or type(payload.off) ~= "boolean" then
			return false, M("msg.bad_request")
		end
		local f = Fighters.ofPlayer(player)
		if f and f.inArena and not payload.off then
			return false, M("msg.leave_arena_first")
		end
		p.protectionOff = payload.off
		State.dirty(player)
		return true
	end)

	-- who is inside (5 Hz) + rush window
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.2)
			acc += 0.2
			for _, f in Fighters.list do
				if f.kind == "player" then
					local pos = Fighters.position(f)
					local inside = pos ~= nil and f.alive and Arena.inside(pos)
					if inside ~= f.inArena then
						f.inArena = inside
						Fighters.setAttr(f, "InArena", inside)
						local player = f.player
						if player then
							State.dirty(player)
							if inside then
								if Arena.protected(f) then
									Remotes.notify(player, M("msg.arena_protected", { power = Format.abbrev(P.protectPower) }), "info")
								else
									Remotes.notify(player, M("msg.arena_enter"), "error")
								end
							else
								Remotes.notify(player, M("msg.arena_leave"), "success")
							end
						end
					end
				end
			end
			if acc >= 1 then
				acc = 0
				local active, at = Arena.rushActive(os.time())
				if active ~= rushWasActive then
					rushWasActive = active
					if active then
						rushEndsAt = at
						table.clear(rushScores)
						Remotes.fireAll("Toast", { key = "toast.rush_start", color = { 230, 70, 70 } })
					else
						endRush()
					end
					broadcast()
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		rushScores[player] = nil
	end)
	local _ = rushEndsAt
end

return Arena
