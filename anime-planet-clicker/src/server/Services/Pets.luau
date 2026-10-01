--!strict
-- Pet inventory: add, equip / unequip / equip best, delete, lock, fuse into Golden / Prism,
-- Trait rolls (Ember Forge) and the inventory autos (auto best, auto fuse).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)

local Pets = {}

local rng = Random.new()

local function power(profile: Data.Profile, uid: string): number
	local pet = profile.pets[uid]
	if not pet then
		return 0
	end
	return Formulas.petPower(pet.id, pet.tier, State.maxZone(profile), pet.trait)
end

function Pets.hasRoom(profile: Data.Profile, count: number): boolean
	return State.petCount(profile) + count <= Config.MaxInventory
end

-- Adds a pet (auto-equips it if a slot is free). Returns the uid, or nil if the inventory is full.
-- force = true ignores the inventory cap (paid pets must never be lost).
function Pets.add(player: Player, petId: string, tier: number, force: boolean?): string?
	local p = Data.get(player)
	if not p or not Formulas.PetById[petId] then
		return nil
	end
	if not force and not Pets.hasRoom(p, 1) then
		return nil
	end
	local uid = "p" .. p.nextUid
	p.nextUid += 1
	p.pets[uid] = { id = petId, tier = tier, locked = false }
	p.discovered[petId] = true
	if #p.equipped < State.maxEquip(player, p) then
		table.insert(p.equipped, uid)
	end
	State.dirty(player)
	return uid
end

-- Trim the equipped list if slots shrank.
function Pets.clampEquipped(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local max = State.maxEquip(player, p)
	while #p.equipped > max do
		table.remove(p.equipped)
	end
end

function Pets.equipBest(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local uids = {}
	for uid in p.pets do
		table.insert(uids, uid)
	end
	table.sort(uids, function(a, b)
		local pa, pb = power(p, a), power(p, b)
		if pa == pb then
			return a < b
		end
		return pa > pb
	end)
	local max = State.maxEquip(player, p)
	local eq = {}
	for i = 1, math.min(max, #uids) do
		eq[i] = uids[i]
	end
	p.equipped = eq
	State.dirty(player)
end

local function removePet(p: Data.Profile, uid: string)
	p.pets[uid] = nil
	local i = table.find(p.equipped, uid)
	if i then
		table.remove(p.equipped, i)
	end
end
Pets.remove = removePet

-- Fuses FuseCount unlocked pets with the same id + tier as `uid` into one of the next tier.
function Pets.fuse(player: Player, uid: string, quiet: boolean?): (boolean, any)
	local p = Data.get(player)
	local base = if p then p.pets[uid] else nil
	if not p or not base then
		return false, M("msg.unknown_pet")
	end
	if base.tier >= 2 then
		return false, M("msg.already_prism")
	end
	local sameEquipped, sameFree = {}, {}
	for other, pet in p.pets do
		if pet.id == base.id and pet.tier == base.tier and (not pet.locked or other == uid) then
			if table.find(p.equipped, other) then
				table.insert(sameEquipped, other)
			else
				table.insert(sameFree, other)
			end
		end
	end
	if #sameEquipped + #sameFree < Config.FuseCount then
		return false, M("msg.need_fuse", { n = Config.FuseCount, tier = M("tier." .. base.tier) })
	end
	local used = {}
	for _, list in { sameFree, sameEquipped } do
		for _, other in list do
			if #used < Config.FuseCount then
				table.insert(used, other)
			end
		end
	end
	local wasEquipped = false
	local bestTrait: string? = nil
	for _, other in used do
		if table.find(p.equipped, other) then
			wasEquipped = true
		end
		local t = p.pets[other].trait
		if t and (not bestTrait or Config.TraitIndex[t] > Config.TraitIndex[bestTrait]) then
			bestTrait = t -- the fused pet keeps the best Trait of the five
		end
		removePet(p, other)
	end
	local newTier = base.tier + 1
	local newUid = Pets.add(player, base.id, newTier, true) :: string
	p.pets[newUid].trait = bestTrait
	if wasEquipped and not table.find(p.equipped, newUid) then
		table.insert(p.equipped, newUid)
	end
	if not quiet then
		Remotes.notify(player, M("msg.fused", { pet = M("pet.tiered", { tier = M("tier." .. newTier), pet = M("pet." .. base.id) }) }), "success")
	end
	State.dirty(player)
	Hooks.fire("fused", player, newTier)
	return true, newUid
end

-- Auto Fuse: fuse everything that can be fused (unlocked pets only).
function Pets.autoFuse(player: Player): number
	local p = Data.get(player)
	if not p then
		return 0
	end
	local fused = 0
	for _ = 1, 40 do
		local counts: { [string]: { n: number, uid: string } } = {}
		local candidate: string? = nil
		for uid, pet in p.pets do
			if pet.tier < 2 and not pet.locked then
				local key = pet.id .. ":" .. pet.tier
				local c = counts[key]
				if not c then
					c = { n = 0, uid = uid }
					counts[key] = c
				end
				c.n += 1
				if c.n >= Config.FuseCount then
					candidate = c.uid
					break
				end
			end
		end
		if not candidate then
			break
		end
		local ok = Pets.fuse(player, candidate, true)
		if not ok then
			break
		end
		fused += 1
	end
	return fused
end

-- Runs the inventory autos after pets were added.
function Pets.afterChange(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	if p.auto.fuse then
		Pets.autoFuse(player)
	end
	if p.auto.best then
		Pets.equipBest(player)
	end
end

function Pets.init()
	Remotes.handle("Equip", function(player, payload)
		local p = Data.get(player)
		local uid = payload.uid
		if not p or type(uid) ~= "string" or not p.pets[uid] then
			return false, M("msg.unknown_pet")
		end
		if table.find(p.equipped, uid) then
			return true
		end
		if #p.equipped >= State.maxEquip(player, p) then
			return false, M("msg.slots_full")
		end
		table.insert(p.equipped, uid)
		State.dirty(player)
		return true
	end)

	Remotes.handle("Unequip", function(player, payload)
		local p = Data.get(player)
		if not p or type(payload.uid) ~= "string" then
			return false, M("msg.unknown_pet")
		end
		local i = table.find(p.equipped, payload.uid)
		if i then
			table.remove(p.equipped, i)
			State.dirty(player)
		end
		return true
	end)

	Remotes.handle("EquipBest", function(player)
		Pets.equipBest(player)
		return true
	end)

	Remotes.handle("Lock", function(player, payload)
		local p = Data.get(player)
		if not p or type(payload.uid) ~= "string" or not p.pets[payload.uid] then
			return false, M("msg.unknown_pet")
		end
		p.pets[payload.uid].locked = payload.locked == true
		State.dirty(player)
		return true
	end)

	Remotes.handle("Delete", function(player, payload)
		local p = Data.get(player)
		if not p or type(payload.uids) ~= "table" or #payload.uids > 300 then
			return false, M("msg.bad_request")
		end
		local n = 0
		for _, uid in payload.uids do
			if n >= 200 then
				break
			end
			if type(uid) == "string" then
				local pet = p.pets[uid]
				if pet and not pet.locked then
					removePet(p, uid)
					n += 1
				end
			end
		end
		if n == 0 then
			return false, M("msg.nothing_deleted")
		end
		State.dirty(player)
		return true, n
	end)

	Remotes.handle("Fuse", function(player, payload)
		if type(payload.uid) ~= "string" then
			return false, M("msg.unknown_pet")
		end
		return Pets.fuse(player, payload.uid)
	end)

	Remotes.handle("FuseAll", function(player)
		local n = Pets.autoFuse(player)
		if n == 0 then
			return false, M("msg.nothing_to_fuse")
		end
		return true, n
	end)

	-- Ember Forge: roll a Trait on a pet. The pet keeps the better one.
	Remotes.handle("RollTrait", function(player, payload)
		local p = Data.get(player)
		local uid = payload.uid
		if not p or type(uid) ~= "string" or not p.pets[uid] then
			return false, M("msg.unknown_pet")
		end
		local system = Config.SystemById.traits
		if not State.hasZone(p, system.zone) then
			return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[system.zone].id) })
		end
		local pet = p.pets[uid]
		local current = if pet.trait then Config.TraitIndex[pet.trait] else 0
		if current >= #Config.Traits then
			return false, M("msg.trait_max")
		end
		if not State.spend(player, system.material, Config.TraitCost) then
			return false, M("msg.not_enough", { item = M("material." .. system.material) })
		end
		local rolled = Formulas.rollTable(Config.Traits, rng:NextNumber())
		local better = rolled > current
		if better then
			pet.trait = Config.Traits[rolled].id
		else
			State.addMaterial(player, system.material, Config.TraitRefund)
		end
		State.dirty(player)
		Hooks.fire("traitRolled", player)
		return true, { trait = Config.Traits[rolled].id, kept = better, refund = if better then 0 else Config.TraitRefund }
	end)
end

return Pets
