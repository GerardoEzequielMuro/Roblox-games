--!strict
-- Seeds: Vigor (heal), Titan (damage vs enemies), Spark (ki). Bought with Sparks (stock limit
-- per hour, restocks on the hour with a visible clock) or from the Robux seed packs (no
-- limit). Used from the Shop window or the quick keys. Never usable (or active) inside the PvP
-- arena: Fighters.damageBoost and the ki loop in Combat ignore them there.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Seeds = require(ReplicatedStorage.Shared.Seeds)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Fighters = require(script.Parent.Fighters)
local M = Locale.m

local Items = {}

local MAX_BUFF = 1800 -- a buff can be topped up to 30 minutes, no more

local function sparksPerMinute(p: Data.Profile): number
	return Formulas.sparksPerMinute(State.bestPlanet(p))
end

-- Robux packs: `each` of every seed, no carry cap.
function Items.grantPack(player: Player, each: number)
	local p = Data.get(player)
	if not p then
		return
	end
	for _, def in Config.Seeds do
		p.items[def.id] = (p.items[def.id] or 0) + each
	end
	State.dirty(player)
end

function Items.use(player: Player, id: string): (boolean, any)
	local p = Data.get(player)
	local def = Config.SeedById[id]
	local f = Fighters.ofPlayer(player)
	if not p or not def or not f then
		return false, M("msg.bad_request")
	end
	if not f.alive then
		return false, M("msg.error")
	end
	if f.inArena then
		return false, M("msg.seed_arena")
	end
	if (p.items[id] or 0) <= 0 then
		return false, M("msg.no_seed")
	end
	local now = os.time()
	if id == "vigor_seed" then
		if p.buffs.vigorReadyAt > now then
			return false, M("msg.seed_cooldown", { n = p.buffs.vigorReadyAt - now })
		end
		local h = f.humanoid
		if not h or h.Health <= 0 then
			return false, M("msg.error")
		end
		h.Health = h.MaxHealth
		f.ki = math.min(1, f.ki + def.kiGive)
		p.buffs.vigorReadyAt = now + def.cooldown
	elseif id == "titan_seed" then
		p.buffs.titan = math.min(now + MAX_BUFF, math.max(p.buffs.titan, now) + def.seconds)
	elseif id == "spark_seed" then
		f.ki = 1
		p.buffs.spark = math.min(now + MAX_BUFF, math.max(p.buffs.spark, now) + def.seconds)
	end
	p.items[id] -= 1
	State.dirty(player)
	Remotes.fire("Reward", player, { kind = "seed", amount = 1 })
	return true, M("msg.seed_used", { item = M("item." .. id) })
end

function Items.buy(player: Player, id: string): (boolean, any)
	local p = Data.get(player)
	if not p then
		return false, M("msg.error")
	end
	local now = os.time()
	local ok, why = Seeds.canBuy(p.market, p.items, id, now, p.sparks, sparksPerMinute(p))
	if not ok then
		if why == "stock" then
			return false, M("msg.seed_stock")
		elseif why == "cap" then
			return false, M("msg.seed_cap", { n = Config.SeedCap })
		elseif why == "sparks" then
			return false, M("msg.need_sparks")
		end
		return false, M("msg.bad_request")
	end
	if not State.spendSparks(player, Seeds.price(id, sparksPerMinute(p))) then
		return false, M("msg.need_sparks")
	end
	p.market.bought[id] = (p.market.bought[id] or 0) + 1
	Seeds.add(p.items, id, 1)
	State.dirty(player)
	return true, M("msg.seed_bought", { item = M("item." .. id) })
end

function Items.init()
	-- Titan Seed: more damage to enemies, never in the arena.
	Fighters.damageBoost = function(attacker: Fighters.Fighter?, _victim: Fighters.Fighter): number
		if attacker and attacker.player and not attacker.inArena then
			local p = Data.get(attacker.player)
			if p and Seeds.active(p.buffs.titan, os.time()) then
				return Config.SeedById.titan_seed.damageMult
			end
		end
		return 1
	end

	State.extras.seeds = function(_player, p)
		local now = os.time()
		local m = Seeds.sync(p.market, now)
		local shop = {}
		for _, def in Config.Seeds do
			shop[def.id] = { stock = Seeds.stockLeft(m, def.id, now), price = Seeds.price(def.id, sparksPerMinute(p)) }
		end
		return { items = p.items, buffs = p.buffs, shop = shop, nextRestock = Seeds.nextRestock(now), cap = Config.SeedCap }
	end

	Remotes.handle("BuySeed", function(player, payload)
		if type(payload.id) ~= "string" then
			return false, M("msg.bad_request")
		end
		return Items.buy(player, payload.id)
	end)
	Remotes.handle("UseSeed", function(player, payload)
		if type(payload.id) ~= "string" then
			return false, M("msg.bad_request")
		end
		return Items.use(player, payload.id)
	end)
end

return Items
