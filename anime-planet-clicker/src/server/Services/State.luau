--!strict
-- Session state that isn't persisted (passes, friends, gifts, overcharge, drone trip...) plus
-- the derived stats every service needs and the dirty-flag replication of the profile to
-- its owner. Currency only ever changes through the helpers here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)

local State = {}

State.passes = {} :: { [Player]: { [string]: boolean } }
State.inArena = {} :: { [Player]: boolean } -- standing in the Meteor Arena (paid speed is off there)
State.friends = {} :: { [Player]: number }
State.sessionStart = {} :: { [Player]: number }
State.giftsClaimed = {} :: { [Player]: { [number]: boolean } }
State.ready = {} :: { [Player]: boolean }
State.premium = {} :: { [Player]: boolean }
-- PolicyService: true = paid random items (and chance modifiers) must not be sold to this player
State.restricted = {} :: { [Player]: boolean }
State.charge = {} :: { [Player]: number } -- Overcharge hits (0..Config.OverchargeHits)
State.lastHit = {} :: { [Player]: number }
State.transit = {} :: { [Player]: { value: number, arriveAt: number }? } -- Cargo Drone in flight
State.autoOpen = {} :: { [Player]: string? }
State.lastOpen = {} :: { [Player]: number }
-- Multipliers from active live events (set by LiveEventService).
State.eventEffects = { stardustMult = 1, luckMult = 1, crystalMult = 1 }
-- Extra snapshot sections contributed by other services (quests, offline, starter...).
State.extras = {} :: { [string]: (Player, Data.Profile) -> any }

local dirtyFull: { [Player]: boolean } = {}
local dirtyCurrency: { [Player]: boolean } = {}
local statsCache: { [Player]: Formulas.Stats } = {}

function State.init(player: Player)
	State.passes[player] = State.passes[player] or {}
	State.friends[player] = 0
	State.sessionStart[player] = os.clock()
	State.giftsClaimed[player] = {}
	State.charge[player] = 0
	State.lastHit[player] = 0
	State.lastOpen[player] = 0
end

function State.cleanup(player: Player)
	for _, t in { State.passes, State.inArena, State.friends, State.sessionStart, State.giftsClaimed, State.ready, State.premium, State.restricted, State.charge, State.lastHit, State.transit, State.autoOpen, State.lastOpen, dirtyFull, dirtyCurrency, statsCache } :: { any } do
		t[player] = nil
	end
end

function State.owns(player: Player, passKey: string): boolean
	local p = State.passes[player]
	return p ~= nil and p[passKey] == true
end

function State.maxZone(profile: Data.Profile): number
	local m = 1
	for _, z in profile.zones do
		if z > m then
			m = z
		end
	end
	return m
end

function State.hasZone(profile: Data.Profile, zone: number): boolean
	return table.find(profile.zones, zone) ~= nil
end

function State.petPowerSum(profile: Data.Profile): number
	local maxZone = State.maxZone(profile)
	local sum = 0
	for _, uid in profile.equipped do
		local pet = profile.pets[uid]
		if pet then
			sum += Formulas.petPower(pet.id, pet.tier, maxZone, pet.trait)
		end
	end
	return sum
end

function State.indexZonesDone(profile: Data.Profile): number
	local n = 0
	for _ in profile.indexClaimed do
		n += 1
	end
	return n
end

function State.petCount(profile: Data.Profile): number
	local n = 0
	for _ in profile.pets do
		n += 1
	end
	return n
end

-- Everything the formulas need, cached until the profile is marked dirty. charge is left
-- at 0: Overcharge changes on every hit, so Mining multiplies it in itself.
function State.stats(player: Player, profile: Data.Profile): Formulas.Stats
	local cached = statsCache[player]
	if cached then
		return cached
	end
	local buffs = {}
	for id, left in profile.buffs do
		if left > 0 then
			buffs[id] = true
		end
	end
	local s: Formulas.Stats = {
		toolIndex = Config.ToolIndex[profile.tool] or 1,
		upgrades = profile.upgrades,
		petPower = State.petPowerSum(profile),
		rebirths = profile.rebirths,
		passes = State.passes[player] or {},
		buffs = buffs,
		mastery = Formulas.masteryBonus(profile.mastery),
		relics = Formulas.relicBonus(profile.relics),
		friends = State.friends[player] or 0,
		indexZones = State.indexZonesDone(profile),
		premium = State.premium[player] == true,
		eventStardust = State.eventEffects.stardustMult,
		eventLuck = State.eventEffects.luckMult,
		eventCrystals = State.eventEffects.crystalMult,
		charge = 0,
	}
	statsCache[player] = s
	return s
end

function State.invalidate(player: Player)
	statsCache[player] = nil
end

function State.invalidateAll()
	table.clear(statsCache)
end

-- Overcharge fraction (0 until Storm Reach is unlocked).
function State.chargeFraction(player: Player, profile: Data.Profile): number
	if not State.hasZone(profile, Config.SystemById.overcharge.zone) then
		return 0
	end
	return math.clamp((State.charge[player] or 0) / Config.OverchargeHits, 0, 1)
end

-- Damage of one hit right now (the number shown as "Mining Power").
function State.hitDamage(player: Player, profile: Data.Profile): number
	return Formulas.hitDamage(State.stats(player, profile)) * Formulas.overchargeMult(State.chargeFraction(player, profile), profile.upgrades.Capacitor or 0)
end

-- Mining power without Overcharge (PvP, rewards, offline).
function State.basePower(player: Player, profile: Data.Profile): number
	return Formulas.hitDamage(State.stats(player, profile))
end

-- Power in the Meteor Arena: no paid pass counts (x2 Damage, VIP, pet slot passes) and the
-- exclusive Robux pets are left out, so money never decides a PvP fight.
function State.pvpPower(player: Player, profile: Data.Profile): number
	local maxZone = State.maxZone(profile)
	local powers = {}
	for _, uid in profile.equipped do
		local pet = profile.pets[uid]
		local def = if pet then Formulas.PetById[pet.id] else nil
		if pet and def and def.scale == nil then
			table.insert(powers, Formulas.petPower(pet.id, pet.tier, maxZone, pet.trait))
		end
	end
	local freeSlots = Formulas.maxEquip(profile.upgrades, {})
	return Formulas.hitDamage(Formulas.pvpStats(State.stats(player, profile), Formulas.topPower(powers, freeSlots)))
end

-- Stardust per second of active mining: the yardstick for "minutes of income" rewards.
function State.income(player: Player, profile: Data.Profile): number
	local s = State.stats(player, profile)
	local zone = Formulas.incomeZone(s.toolIndex, State.maxZone(profile))
	return Formulas.income(Formulas.hitDamage(s), zone, Formulas.stardustMult(s))
end

function State.maxEquip(player: Player, profile: Data.Profile): number
	return Formulas.maxEquip(profile.upgrades, State.passes[player] or {})
end

---------------------------------------------------------------------------
-- Currency helpers (server-authoritative; the only way currency changes)
---------------------------------------------------------------------------
function State.addStardust(player: Player, amount: number, mined: boolean?)
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return
	end
	p.stardust += amount
	if mined then
		p.totalMined += amount
	end
	dirtyCurrency[player] = true
end

function State.spendStardust(player: Player, amount: number): boolean
	local p = Data.get(player)
	if not p or amount ~= amount or p.stardust < amount then
		return false
	end
	p.stardust -= amount
	dirtyCurrency[player] = true
	return true
end

function State.addCrystals(player: Player, amount: number)
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return
	end
	p.crystals += math.floor(amount)
	dirtyCurrency[player] = true
end

function State.addMaterial(player: Player, material: string, amount: number)
	local p = Data.get(player)
	if not p or p.mats[material] == nil or amount <= 0 then
		return
	end
	p.mats[material] += math.floor(amount)
	dirtyCurrency[player] = true
end

-- currency = "stardust" | "crystals" | a material id
function State.balance(profile: Data.Profile, currency: string): number
	if currency == "stardust" then
		return profile.stardust
	elseif currency == "crystals" then
		return profile.crystals
	end
	return profile.mats[currency] or 0
end

function State.spend(player: Player, currency: string, amount: number): boolean
	local p = Data.get(player)
	if not p or amount ~= amount or amount < 0 or State.balance(p, currency) < amount then
		return false
	end
	if currency == "stardust" then
		p.stardust -= amount
	elseif currency == "crystals" then
		p.crystals -= amount
	else
		p.mats[currency] -= amount
	end
	dirtyCurrency[player] = true
	return true
end

-- Timed buffs. refresh = planet buffs (set to at least `seconds`); otherwise the time stacks
-- (rewards and products).
function State.addBuff(player: Player, id: string, seconds: number, refresh: boolean?)
	local p = Data.get(player)
	if not p or not Config.Buffs[id] then
		return
	end
	local left = p.buffs[id] or 0
	p.buffs[id] = if refresh then math.max(left, seconds) else left + seconds
	State.dirty(player)
end

---------------------------------------------------------------------------
-- Replication
---------------------------------------------------------------------------
function State.dirty(player: Player)
	dirtyFull[player] = true
	statsCache[player] = nil
end

function State.dirtyCurrency(player: Player)
	dirtyCurrency[player] = true
end

-- Other clients render this player's pets and tool from these attributes.
function State.replicateLook(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local parts = {}
	for _, uid in p.equipped do
		local pet = p.pets[uid]
		if pet then
			table.insert(parts, pet.id .. ":" .. pet.tier)
		end
	end
	player:SetAttribute("EquippedPets", table.concat(parts, ","))
	player:SetAttribute("Tool", p.tool)
	player:SetAttribute("VIP", State.owns(player, "VIP"))
	player:SetAttribute("Rebirths", p.rebirths)
end

function State.cargoInfo(player: Player, p: Data.Profile): { [string]: any }
	local transit = State.transit[player]
	return {
		count = p.cargo.count,
		value = p.cargo.value,
		cap = Formulas.cargoCapacity(State.stats(player, p)),
		transit = if transit then math.max(0, transit.arriveAt - os.clock()) else 0,
		transitValue = if transit then transit.value else 0,
		instant = State.owns(player, "InstantSell"),
	}
end

function State.snapshot(player: Player): { [string]: any }?
	local p = Data.get(player)
	if not p then
		return nil
	end
	local gifts = {}
	local claimed = State.giftsClaimed[player]
	if claimed then
		for i in claimed do
			table.insert(gifts, i)
		end
	end
	local s = State.stats(player, p)
	local maxZone = State.maxZone(p)
	local nextZone = Config.Zones[maxZone + 1]
	local snap: { [string]: any } = {
		stardust = p.stardust,
		crystals = p.crystals,
		totalMined = p.totalMined,
		rebirths = p.rebirths,
		zones = p.zones,
		maxZone = maxZone,
		tool = p.tool,
		fieldsFound = p.fieldsFound,
		upgrades = p.upgrades,
		mats = p.mats,
		relics = p.relics,
		pets = p.pets,
		equipped = p.equipped,
		discovered = p.discovered,
		indexClaimed = p.indexClaimed,
		mastery = p.mastery,
		gateLeft = if nextZone then (p.gate[tostring(maxZone + 1)] or nextZone.gateHp) else 0,
		cargo = State.cargoInfo(player, p),
		buffs = p.buffs,
		auto = p.auto,
		autoDelete = p.autoDelete,
		autoOpen = State.autoOpen[player],
		passes = State.passes[player] or {},
		maxEquip = State.maxEquip(player, p),
		maxInventory = Config.MaxInventory,
		damage = Formulas.hitDamage(s),
		petPower = s.petPower,
		luck = Formulas.luck(s),
		hitsPerSecond = Formulas.hitsPerSecond(s),
		autoRate = Formulas.autoRate(s),
		walkSpeed = Formulas.walkSpeed(s),
		range = Formulas.range(s),
		crit = Formulas.critChance(s),
		stardustMult = Formulas.stardustMult(s),
		income = State.income(player, p),
		droneSeconds = Formulas.droneSeconds(s),
		rebirthCost = Formulas.rebirthCost(p.rebirths),
		rebirthCrystals = Formulas.rebirthCrystals(p.rebirths),
		goldenChance = Formulas.goldenChance(State.owns(player, "GoldenCapsules")),
		daily = { streak = p.daily.streak, last = p.daily.last },
		serverTime = os.time(),
		giftsClaimed = gifts,
		sessionElapsed = os.clock() - (State.sessionStart[player] or os.clock()),
		friends = State.friends[player] or 0,
		persistent = Data.isPersistent(player),
		lang = p.lang,
		settings = p.settings,
		tutorial = p.tutorial,
		arenaPoints = p.arenaPoints,
		arenaKos = p.arenaKos,
		restricted = State.restricted[player] == true,
		anomalyWindow = p.anomalyWindow,
		totalOpened = p.totalOpened,
		planetsBroken = p.planetsBroken,
		playTime = p.playTime,
		charge = State.chargeFraction(player, p),
		events = State.eventEffects,
	}
	for key, fn in State.extras do
		local ok, v = pcall(fn, player, p)
		if ok then
			snap[key] = v
		else
			warn("[State] snapshot extra", key, v)
		end
	end
	return snap
end

function State.sendFull(player: Player)
	local snap = State.snapshot(player)
	if snap then
		Remotes.fire("State", player, snap)
		State.replicateLook(player)
	end
	dirtyFull[player] = nil
	dirtyCurrency[player] = nil
end

local function flush()
	for _, player in Players:GetPlayers() do
		if State.ready[player] then
			if dirtyFull[player] then
				State.sendFull(player)
			elseif dirtyCurrency[player] then
				dirtyCurrency[player] = nil
				local p = Data.get(player)
				if p then
					Remotes.fire("Currency", player, {
						stardust = p.stardust,
						crystals = p.crystals,
						totalMined = p.totalMined,
						mats = p.mats,
						cargo = State.cargoInfo(player, p),
						charge = State.chargeFraction(player, p),
					})
				end
			end
		end
	end
end

function State.start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(function()
				flush()
			end)
			if not ok then
				warn("[State] flush error", err)
			end
		end
	end)
end

return State
