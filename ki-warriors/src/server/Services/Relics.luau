--!strict
-- Astral Seals: six per-player collectibles scattered over the planets the player has
-- unlocked. Each player has their own set (only you see and collect yours).
-- With all six, the Wish Altar grants one wish; the set then reappears after a cooldown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Fighters = require(script.Parent.Fighters)
local Rewards = require(script.Parent.Rewards)
local M = Locale.m

local Relics = {}

local altar = Vector3.zero

-- The six spots of a set: deterministic from the profile seed and the unlocked planets.
function Relics.spots(p: Data.Profile): { { planet: number, pos: Vector3 } }
	local candidates = {}
	for _, index in p.planets do
		local pl = Config.Planets[index]
		if pl then
			local cx, cy, cz = Config.planetCenter(index)
			for _, o in pl.relicSpots do
				table.insert(candidates, { planet = index, pos = Vector3.new(cx + o[1], cy + 4, cz + o[3]) })
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.planet ~= b.planet then
			return a.planet < b.planet
		end
		if a.pos.X ~= b.pos.X then
			return a.pos.X < b.pos.X
		end
		return a.pos.Z < b.pos.Z
	end)
	local rng = Random.new(p.relics.seed * 7919 + 17)
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local out = {}
	for i = 1, math.min(Config.Relics.count, #candidates) do
		out[i] = candidates[i]
	end
	return out
end

function Relics.count(p: Data.Profile): number
	local n = 0
	for _ in p.relics.found do
		n += 1
	end
	return n
end

function Relics.snapshot(p: Data.Profile): { [string]: any }
	local list = {}
	local now = os.time()
	local available = now >= p.relics.nextAt
	if available then
		for i, spot in Relics.spots(p) do
			table.insert(list, { i = i, planet = spot.planet, pos = spot.pos, found = p.relics.found[tostring(i)] == true })
		end
	end
	return { list = list, found = Relics.count(p), total = Config.Relics.count, nextAt = p.relics.nextAt, serverTime = now, wishes = p.wishes, wishPower = p.wishPower }
end

-- Marks every seal as found (Wish Now product, tests).
function Relics.completeSet(player: Player): boolean
	local p = Data.get(player)
	if not p then
		return false
	end
	p.relics.nextAt = 0
	for i = 1, Config.Relics.count do
		p.relics.found[tostring(i)] = true
	end
	State.dirty(player)
	return true
end

function Relics.skipCooldown(player: Player): boolean
	local p = Data.get(player)
	if p then
		p.relics.nextAt = 0
		State.dirty(player)
	end
	return true
end

function Relics.init(world: { [string]: any })
	altar = world.altarCenter or Vector3.zero

	State.extras.relics = function(_player, p)
		return Relics.snapshot(p)
	end

	Remotes.handle("CollectRelic", function(player, payload)
		local p = Data.get(player)
		local f = Fighters.ofPlayer(player)
		local i = payload.i
		if not p or not f or type(i) ~= "number" then
			return false, M("msg.bad_request")
		end
		if os.time() < p.relics.nextAt then
			return false, M("msg.not_ready")
		end
		local spot = Relics.spots(p)[i]
		local pos = Fighters.position(f)
		if not spot or not pos then
			return false, M("msg.bad_request")
		end
		if p.relics.found[tostring(i)] then
			return false, M("msg.already_claimed")
		end
		if (pos - spot.pos).Magnitude > Config.Relics.pickupRadius + 8 then
			return false, M("msg.too_far")
		end
		p.relics.found[tostring(i)] = true
		Hooks.fire("relic", player, i)
		State.dirty(player)
		return true, Relics.count(p)
	end)

	Remotes.handle("Wish", function(player, payload)
		local p = Data.get(player)
		local f = Fighters.ofPlayer(player)
		if not p or not f or type(payload.id) ~= "string" then
			return false, M("msg.bad_request")
		end
		local wish = nil
		for _, w in Config.Wishes do
			if w.id == payload.id then
				wish = w
			end
		end
		if not wish then
			return false, M("msg.bad_request")
		end
		if Relics.count(p) < Config.Relics.count then
			return false, M("msg.need_seals", { n = Config.Relics.count - Relics.count(p) })
		end
		local pos = Fighters.position(f)
		if not pos or (pos - altar).Magnitude > Config.WishAltar.radius + 24 then
			return false, M("msg.go_to_altar")
		end
		if wish.id == "power" and p.wishPower >= Config.WishPowerMax then
			return false, M("msg.maxed")
		end
		local text
		if wish.sparkMinutes then
			text = Rewards.grant(player, { kind = "sparks", amount = wish.sparkMinutes })
		elseif wish.gems then
			text = Rewards.grant(player, { kind = "gems", amount = wish.gems })
		elseif wish.boostMinutes then
			text = Rewards.grant(player, { kind = "boost", amount = wish.boostMinutes })
		elseif wish.spins then
			text = Rewards.grant(player, { kind = "spins", amount = wish.spins })
		else
			p.wishPower += 1
			text = M("reward.wish_power", { n = math.floor(p.wishPower * 5) })
		end
		p.wishes += 1
		p.relics.found = {}
		p.relics.seed += 1
		p.relics.nextAt = os.time() + Config.Relics.resetSeconds
		Hooks.fire("wish", player, wish.id)
		Remotes.fireAll("Fx", "wish", { p = altar, u = player.UserId })
		Remotes.fireAll("Toast", { key = "toast.wish_made", args = { player = player.DisplayName }, color = { 255, 214, 90 } })
		State.dirty(player)
		task.spawn(Data.save, player)
		return true, text
	end)
end

return Relics
