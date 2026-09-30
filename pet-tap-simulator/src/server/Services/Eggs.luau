--!strict
-- Egg hatching: server-side validation (zone owned, distance to egg, cooldown, price,
-- inventory room), weighted roll with luck, golden chance, rare-hatch broadcast, auto-hatch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Pets = require(script.Parent.Pets)
local Hooks = require(script.Parent.Hooks)

local Eggs = {}

export type HatchResult = { uid: string, id: string, tier: number, chance: number, rarity: string, new: boolean? }

local rng = Random.new()
local eggPositions: { [string]: Vector3 } = {}

local function broadcast(player: Player, r: HatchResult)
	local pet = Formulas.PetById[r.id]
	local rarity = Config.RarityByName[pet.rarity]
	if rarity and rarity.broadcast then
		Remotes.fireAll("Toast", {
			player = player.DisplayName,
			pet = pet.id,
			rarity = pet.rarity,
			tier = r.tier,
			chance = r.chance,
		})
	end
end

-- Rolls and grants `count` pets from an egg with no cost/distance checks.
local function rollInto(player: Player, eggId: string, count: number, force: boolean): { HatchResult }
	local p = Data.get(player) :: Data.Profile
	local luck = State.luck(player, p)
	local goldenChance = State.goldenChance(player)
	local results: { HatchResult } = {}
	for _ = 1, count do
		local petId, chance = Formulas.roll(eggId, luck, rng:NextNumber())
		local tier = if rng:NextNumber() < goldenChance then 1 else 0
		local isNew = not p.discovered[petId] -- first time this player sees the pet (NEW! badge)
		local uid = Pets.add(player, petId, tier, force)
		if uid then
			local r: HatchResult = { uid = uid, id = petId, tier = tier, chance = chance, rarity = Formulas.PetById[petId].rarity, new = isNew }
			table.insert(results, r)
			broadcast(player, r)
		end
	end
	p.totalHatched += #results
	State.dirty(player)
	Hooks.fire("hatched", player, results, eggId)
	return results
end

function Eggs.hatch(player: Player, eggId: string, count: number): (boolean, any)
	local p = Data.get(player)
	local egg = Formulas.EggById[eggId]
	if not p or not egg or egg.exclusive then
		return false, M("msg.unknown_egg")
	end
	if not Formulas.validHatchCount(count) then
		return false, M("msg.bad_amount")
	end
	if count > Formulas.maxHatch(State.passes[player] or {}) then
		return false, M(if count == Config.OctoHatchCount then "msg.need_x8" else "msg.need_x3")
	end
	if not State.hasZone(p, egg.zone) then
		return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[egg.zone].id) })
	end
	if not Formulas.eggUnlocked(eggId, p.rebirths) then
		return false, M("msg.egg_needs_rebirth", { n = Formulas.eggMinRebirths(eggId) })
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pos = eggPositions[eggId]
	if not root or not pos or (root.Position - pos).Magnitude > Config.EggRange then
		return false, M("msg.get_closer")
	end
	local now = os.clock()
	if now - (State.lastHatch[player] or 0) < Config.HatchCooldown - 0.2 then
		return false, "cooldown"
	end
	if not Pets.hasRoom(player, p, count) then
		return false, M("msg.inventory_full")
	end
	local cost = egg.price * count
	if not State.spendTaps(player, cost) then
		return false, M("msg.not_enough_taps")
	end
	State.lastHatch[player] = now
	return true, rollInto(player, eggId, count, false)
end

-- Exclusive (Robux / reward) Magic Egg: no taps, no distance, never blocked by a full inventory.
function Eggs.hatchExclusive(player: Player, count: number): { HatchResult }
	local results = rollInto(player, "magic", count, true)
	Remotes.fire("Hatched", player, { egg = "magic", results = results, auto = false })
	return results
end

function Eggs.init(positions: { [string]: Vector3 })
	eggPositions = positions

	Remotes.handle("Hatch", function(player, payload)
		if type(payload.egg) ~= "string" then
			return false, M("msg.unknown_egg")
		end
		-- anything that is not a known hatch size is rejected by Eggs.hatch
		local count = if payload.count == nil then 1 else payload.count
		return Eggs.hatch(player, payload.egg, count)
	end)

	Remotes.handle("SetAutoHatch", function(player, payload)
		if payload.egg == nil then
			State.autoHatch[player] = nil
			State.dirty(player)
			return true
		end
		local egg = if type(payload.egg) == "string" then Formulas.EggById[payload.egg] else nil
		if not egg or egg.exclusive then
			return false, M("msg.unknown_egg")
		end
		local pd = Data.get(player)
		if not pd or not Formulas.eggUnlocked(egg.id, pd.rebirths) then
			return false, M("msg.egg_needs_rebirth", { n = Formulas.eggMinRebirths(egg.id) })
		end
		State.autoHatch[player] = payload.egg
		State.dirty(player)
		return true
	end)

	-- Auto hatch loop
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local eggId = State.autoHatch[player]
				if eggId then
					-- free: x1 every AutoHatchFreeCooldown; Auto Hatch pass: full speed, at the biggest
					-- hatch size the player owns (x8 / x3) that they can pay for and have room for
					local fast = State.owns(player, "AutoHatch")
					if os.clock() - (State.lastHatch[player] or 0) >= (if fast then Config.HatchCooldown else Config.AutoHatchFreeCooldown) then
						local p = Data.get(player)
						local egg = Formulas.EggById[eggId]
						local count = 1
						if fast and p and egg then
							local room = State.maxInventory(player) - State.petCount(p)
							count = Formulas.autoHatchCount(Formulas.maxHatch(State.passes[player] or {}), p.taps, egg.price, room)
						end
						local ok, res = Eggs.hatch(player, eggId, count)
						if ok then
							Remotes.fire("Hatched", player, { egg = eggId, results = res, auto = true })
						elseif res ~= "cooldown" then
							State.lastHatch[player] = os.clock() -- back off a full cooldown
							-- out of room: stop instead of failing forever, and say why
							if type(res) == "table" and res.key == "msg.inventory_full" then
								State.autoHatch[player] = nil
								State.dirty(player)
								Remotes.notify(player, M("msg.autohatch_full"), "error")
							end
						end
					end
				end
			end
		end
	end)
end

return Eggs
