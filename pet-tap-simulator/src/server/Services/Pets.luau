--!strict
-- Pet inventory: add, equip / unequip / equip best, delete, lock, craft Golden/Rainbow.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Guard = require(script.Parent.Guard)

local Pets = {}
Pets.giveDice = function(_player: Player, _n: number) end
local traitRng = Random.new()

local function power(profile: Data.Profile, uid: string): number
	local pet = profile.pets[uid]
	if not pet then
		return 0
	end
	return Formulas.petPower(pet.id, pet.tier, State.maxZone(profile), pet.trait)
end

function Pets.hasRoom(player: Player, profile: Data.Profile, count: number): boolean
	return State.petCount(profile) + count <= State.maxInventory(player)
end

-- Adds a pet (auto-equips it if a slot is free). Returns the uid, or nil if the inventory is full.
-- force = true ignores the inventory cap (paid pets must never be lost).
function Pets.add(player: Player, petId: string, tier: number, force: boolean?): string?
	local p = Data.get(player)
	if not p or not Formulas.PetById[petId] then
		return nil
	end
	if not force and not Pets.hasRoom(player, p, 1) then
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

-- Trim equipped list if slots shrank (e.g. pass revoked in Studio testing).
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

function Pets.init()
	Remotes.handle("Equip", function(player, payload)
		local p = Data.get(player)
		local uid = payload.uid
		if not p or not Guard.uid(uid) or not p.pets[uid] then
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
		if not p or not Guard.uid(payload.uid) then
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
		if not p or not Guard.uid(payload.uid) or not p.pets[payload.uid] then
			return false, M("msg.unknown_pet")
		end
		p.pets[payload.uid].locked = payload.locked == true
		State.dirty(player)
		return true
	end)

	Remotes.handle("Delete", function(player, payload)
		local p = Data.get(player)
		if not p or not Guard.array(payload.uids, 400) then
			return false, M("msg.bad_request")
		end
		local n = 0
		for _, uid in payload.uids do
			if n >= 200 then
				break
			end
			if Guard.uid(uid) then
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

	-- Trait roll: spends Trait Dice, always gives a grade (it replaces the old one).
	Remotes.handle("RollTrait", function(player, payload)
		local p = Data.get(player)
		local pet = if p and Guard.uid(payload.uid) then p.pets[payload.uid] else nil
		if not p or not pet then
			return false, M("msg.unknown_pet")
		end
		if p.dice < Config.TraitRollCost then
			return false, M("msg.no_dice")
		end
		p.dice -= Config.TraitRollCost
		local grade = Formulas.rollTrait(traitRng:NextNumber())
		pet.trait = grade
		State.dirty(player)
		Hooks.fire("traitRolled", player, grade)
		return true, grade
	end)

	-- Trait Dice come from playing: rebirths, daily quests, index pages
	local function giveDice(player: Player, n: number)
		local p = Data.get(player)
		if p and n > 0 then
			p.dice += n
			State.dirty(player)
			Remotes.notify(player, M("msg.got_dice", { n = n }), "success")
		end
	end
	Pets.giveDice = giveDice
	Hooks.on("rebirth", function(player: Player)
		giveDice(player, Config.TraitDice.rebirth)
	end)
	Hooks.on("questClaimed", function(player: Player, bonus: boolean)
		giveDice(player, if bonus then Config.TraitDice.questBonus else Config.TraitDice.quest)
	end)
	Hooks.on("indexClaimed", function(player: Player)
		giveDice(player, Config.TraitDice.index)
	end)

	-- Craft: consumes CraftCost unlocked pets with the same id+tier as payload.uid.
	Remotes.handle("Craft", function(player, payload)
		local p = Data.get(player)
		if not p or not Guard.uid(payload.uid) then
			return false, M("msg.unknown_pet")
		end
		local base = p.pets[payload.uid]
		if not base then
			return false, M("msg.unknown_pet")
		end
		if base.tier >= 2 then
			return false, M("msg.already_rainbow")
		end
		local sameEquipped, sameFree = {}, {}
		for uid, pet in p.pets do
			if pet.id == base.id and pet.tier == base.tier and (not pet.locked or uid == payload.uid) then
				if table.find(p.equipped, uid) then
					table.insert(sameEquipped, uid)
				else
					table.insert(sameFree, uid)
				end
			end
		end
		if #sameEquipped + #sameFree < Config.CraftCost then
			return false, M("msg.need_craft", { n = Config.CraftCost, tier = M("tier." .. base.tier) })
		end
		-- use unequipped copies first
		local used = {}
		for _, uid in sameFree do
			if #used < Config.CraftCost then
				table.insert(used, uid)
			end
		end
		for _, uid in sameEquipped do
			if #used < Config.CraftCost then
				table.insert(used, uid)
			end
		end
		local wasEquipped = false
		for _, uid in used do
			if table.find(p.equipped, uid) then
				wasEquipped = true
			end
			removePet(p, uid)
		end
		local newTier = base.tier + 1
		local uid = Pets.add(player, base.id, newTier, true) :: string
		if wasEquipped and not table.find(p.equipped, uid) then
			table.insert(p.equipped, uid)
		end
		Remotes.notify(player, M("msg.crafted", { pet = M("pet.tiered", { tier = M("tier." .. newTier), pet = M("pet." .. base.id) }) }), "success")
		State.dirty(player)
		Hooks.fire("crafted", player, newTier)
		return true, uid
	end)
end

return Pets
