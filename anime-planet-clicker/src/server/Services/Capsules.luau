--!strict
-- Capsules (the "eggs"): server-side validation (galaxy owned, distance to the machine,
-- cooldown, price, inventory room), the roll itself with luck, Golden chance, rare-pet
-- broadcasts and Auto Open. The roll uses exactly the table Formulas.odds shows the player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Pets = require(script.Parent.Pets)
local Hooks = require(script.Parent.Hooks)

local Capsules = {}

export type OpenResult = { uid: string?, id: string, tier: number, chance: number, rarity: string, new: boolean?, deleted: boolean? }

local rng = Random.new()

local function broadcast(player: Player, r: OpenResult)
	local rarity = Config.RarityByName[r.rarity]
	if rarity and rarity.order >= Config.RarityByName.Legendary.order then
		Remotes.fireAll("Toast", { kind = "pet", player = player.DisplayName, pet = r.id, rarity = r.rarity, tier = r.tier, chance = r.chance })
	end
end

-- Rolls and grants `count` pets with no cost / distance checks.
local function rollInto(player: Player, capsuleId: string, count: number, force: boolean): { OpenResult }
	local p = Data.get(player) :: Data.Profile
	local luck = Formulas.luck(State.stats(player, p))
	local goldenChance = Formulas.goldenChance(State.owns(player, "GoldenCapsules"))
	local results: { OpenResult } = {}
	for _ = 1, count do
		local odd = Formulas.rollCapsule(capsuleId, luck, rng:NextNumber())
		local tier = if rng:NextNumber() < goldenChance then 1 else 0
		local isNew = not p.discovered[odd.id]
		-- Auto Delete: only plain (non-Golden) pets of the rarities the player ticked, never a new one
		if not force and tier == 0 and not isNew and p.autoDelete[odd.rarity] and table.find(Config.AutoDeleteRarities, odd.rarity) then
			table.insert(results, { id = odd.id, tier = tier, chance = odd.chance, rarity = odd.rarity, deleted = true })
			continue
		end
		local uid = Pets.add(player, odd.id, tier, force)
		if uid then
			local r: OpenResult = { uid = uid, id = odd.id, tier = tier, chance = odd.chance, rarity = odd.rarity, new = isNew }
			table.insert(results, r)
			broadcast(player, r)
		end
	end
	p.totalOpened += #results
	State.dirty(player)
	Hooks.fire("opened", player, results, capsuleId)
	Pets.afterChange(player)
	return results
end

local function cooldown(player: Player): number
	return if State.owns(player, "FastOpen") then Config.OpenCooldownFast else Config.OpenCooldown
end

-- near = must stand next to the machine (manual opens). Auto Open only needs the galaxy.
function Capsules.open(player: Player, capsuleId: string, count: number, near: boolean): (boolean, any)
	local p = Data.get(player)
	local cap = Formulas.CapsuleById[capsuleId]
	if not p or not cap or cap.exclusive then
		return false, M("msg.unknown_capsule")
	end
	local needPass = Config.OpenPassByCount[count]
	if not table.find(Config.OpenCounts, count) then
		return false, M("msg.bad_amount")
	end
	if needPass and not State.owns(player, needPass) then
		return false, M(if count == 8 then "msg.need_x8" else "msg.need_x3")
	end
	if not State.hasZone(p, cap.zone) then
		return false, M("msg.unlock_first", { zone = M("zone." .. Config.Zones[cap.zone].id) })
	end
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local pos = Layout.capsulePosition(capsuleId)
	if not root or not pos then
		return false, M("msg.get_closer")
	end
	if near then
		local dx, dz = root.Position.X - pos[1], root.Position.Z - pos[3]
		if dx * dx + dz * dz > Config.OpenDistance ^ 2 then
			return false, M("msg.get_closer")
		end
	elseif Layout.zoneAt(root.Position.X, root.Position.Z) ~= cap.zone then
		return false, M("msg.get_closer")
	end
	local now = os.clock()
	if now - (State.lastOpen[player] or 0) < cooldown(player) - 0.2 then
		return false, "cooldown"
	end
	if not Pets.hasRoom(p, count) then
		return false, M("msg.inventory_full")
	end
	if not State.spendStardust(player, cap.price * count) then
		return false, M("msg.not_enough", { item = M("currency.stardust") })
	end
	State.lastOpen[player] = now
	return true, rollInto(player, capsuleId, count, false)
end

-- Quantum Capsule (Robux / rewards): free, no distance, never blocked by a full inventory.
function Capsules.openExclusive(player: Player, count: number): { OpenResult }
	local results = rollInto(player, "quantum", count, true)
	Remotes.fire("Hatched", player, { capsule = "quantum", results = results, auto = false })
	return results
end

-- Auto Open (called by the Auto service every Config.AutoTick).
function Capsules.autoStep(player: Player, p: Data.Profile)
	local capsuleId = State.autoOpen[player]
	if not capsuleId then
		return
	end
	if os.clock() - (State.lastOpen[player] or 0) < cooldown(player) then
		return
	end
	local cap = Formulas.CapsuleById[capsuleId]
	local count = Formulas.bestOpenCount(State.passes[player] or {}, function(n: number): boolean
		return p.stardust >= cap.price * n and Pets.hasRoom(p, n)
	end)
	local ok, res = Capsules.open(player, capsuleId, count, false)
	if ok then
		Remotes.fire("Hatched", player, { capsule = capsuleId, results = res, auto = true })
	elseif res ~= "cooldown" then
		State.lastOpen[player] = os.clock() -- back off a full cooldown
		if type(res) == "table" and res.key == "msg.inventory_full" then
			-- out of room: stop instead of failing forever, and say why
			State.autoOpen[player] = nil
			State.dirty(player)
			Remotes.notify(player, M("msg.autoopen_full"), "error")
		end
	end
end

function Capsules.init()
	Remotes.handle("Open", function(player, payload)
		if type(payload.capsule) ~= "string" then
			return false, M("msg.unknown_capsule")
		end
		return Capsules.open(player, payload.capsule, if payload.count == 3 or payload.count == 8 then payload.count else 1, true)
	end)

	-- Starts Auto Open on a capsule (you must be at the machine to start it) or stops it.
	Remotes.handle("SetAutoOpen", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		if payload.capsule == nil then
			State.autoOpen[player] = nil
			State.dirty(player)
			return true
		end
		local cap = if type(payload.capsule) == "string" then Formulas.CapsuleById[payload.capsule] else nil
		if not cap or cap.exclusive or not State.hasZone(p, cap.zone) then
			return false, M("msg.unknown_capsule")
		end
		State.autoOpen[player] = cap.id
		State.dirty(player)
		return true
	end)

	Remotes.handle("SetAutoDelete", function(player, payload)
		local p = Data.get(player)
		local rarity = payload.rarity
		if not p or type(rarity) ~= "string" or not table.find(Config.AutoDeleteRarities, rarity) then
			return false, M("msg.bad_request")
		end
		(p.autoDelete :: any)[rarity] = if payload.on == true then true else nil
		State.dirty(player)
		return true
	end)
end

return Capsules
