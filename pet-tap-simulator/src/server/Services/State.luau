--!strict
-- Session state that isn't persisted (passes, friends, gifts, auto-hatch...) plus the
-- derived stats every service needs (tap value, luck, equip slots) and the dirty-flag
-- replication of the profile to its owner.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local GiftClock = require(ReplicatedStorage.Shared.GiftClock)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)

local State = {}

State.passes = {} :: { [Player]: { [string]: boolean } }
State.friends = {} :: { [Player]: number }
State.sessionStart = {} :: { [Player]: number }
-- Seconds played today at the moment this session started (profile.gifts.played at load).
State.giftBase = {} :: { [Player]: number }
State.autoHatch = {} :: { [Player]: string? }
State.lastHatch = {} :: { [Player]: number }
State.ready = {} :: { [Player]: boolean }
-- PolicyService: true when the player can't buy paid random items (or until we know).
State.paidRandomRestricted = {} :: { [Player]: boolean }
-- Multipliers from active live events (set by LiveEventService).
State.eventEffects = { luckMult = 1, goldenMult = 1 }
-- Extra snapshot sections contributed by other services (quests, offline, starter...).
State.extras = {} :: { [string]: (Player, Data.Profile) -> any }

local dirtyFull: { [Player]: boolean } = {}
local dirtyCurrency: { [Player]: boolean } = {}
local lastCurrency: { [Player]: number } = {}
-- Currency-only updates go out at most this often per player (the client counts up
-- smoothly and predicts its own taps, so 2 a second reads the same as 5).
local CURRENCY_INTERVAL = 0.5

function State.init(player: Player)
	State.passes[player] = State.passes[player] or {}
	State.friends[player] = 0
	State.sessionStart[player] = os.clock()
	State.lastHatch[player] = 0
end

-- Gifts ("minutes since joining"): claims and time played today live in profile.gifts, so a
-- rejoin the same day keeps both. The session clock only adds the time since joining.
function State.gifts(player: Player, profile: Data.Profile): GiftClock.Gifts
	local g = profile.gifts
	if State.giftBase[player] == nil then
		GiftClock.roll(g, os.time())
		State.giftBase[player] = g.played
	end
	return g
end

-- Seconds played today (persisted part + this session). A new UTC day starts the count over.
function State.giftElapsed(player: Player, profile: Data.Profile): number
	local g = State.gifts(player, profile)
	if GiftClock.roll(g, os.time()) then
		State.giftBase[player] = 0
		State.sessionStart[player] = os.clock()
		State.dirty(player)
	end
	local elapsed = (State.giftBase[player] or 0) + os.clock() - (State.sessionStart[player] or os.clock())
	g.played = math.max(g.played, elapsed)
	return elapsed
end

function State.cleanup(player: Player)
	State.passes[player] = nil
	State.friends[player] = nil
	State.sessionStart[player] = nil
	State.giftBase[player] = nil
	State.autoHatch[player] = nil
	State.lastHatch[player] = nil
	State.ready[player] = nil
	State.paidRandomRestricted[player] = nil
	dirtyFull[player] = nil
	dirtyCurrency[player] = nil
	lastCurrency[player] = nil
end

-- Per-player bookkeeping tables still holding this player (leak check in the playtest).
function State.tracked(player: Player): number
	local n = 0
	for _, t in { State.passes, State.friends, State.sessionStart, State.giftBase, State.autoHatch, State.lastHatch, State.ready, State.paidRandomRestricted, dirtyFull, dirtyCurrency, lastCurrency } :: { { [Player]: any } } do
		if t[player] ~= nil then
			n += 1
		end
	end
	return n
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

function State.maxEquip(player: Player, profile: Data.Profile): number
	return Formulas.maxEquip(profile.upgrades.PetSlots or 0, State.passes[player] or {})
end

function State.maxInventory(player: Player): number
	return Formulas.maxInventory(State.passes[player] or {})
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

function State.tapValue(player: Player, profile: Data.Profile): number
	return Formulas.tapValue({
		petPower = State.petPowerSum(profile),
		rebirths = profile.rebirths,
		tapPowerLevel = profile.upgrades.TapPower or 0,
		passes = State.passes[player] or {},
		friends = State.friends[player] or 0,
		indexZonesDone = State.indexZonesDone(profile),
		tapBoost = profile.tapBoostLeft > 0,
	})
end

function State.luck(player: Player, profile: Data.Profile): number
	return Formulas.luck(profile.upgrades.Luck or 0, State.passes[player] or {}, profile.luckBoostLeft > 0, State.eventEffects.luckMult)
end

function State.goldenChance(player: Player): number
	return Formulas.goldenChance(State.owns(player, "MagicEggs"), State.eventEffects.goldenMult)
end

function State.petCount(profile: Data.Profile): number
	local n = 0
	for _ in profile.pets do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------
-- Currency helpers (server-authoritative; the only way currency changes)
---------------------------------------------------------------------------
function State.addTaps(player: Player, amount: number, countsTowardTotal: boolean?)
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return
	end
	p.taps += amount
	if countsTowardTotal ~= false then
		p.totalTaps += amount
	end
	dirtyCurrency[player] = true
end

function State.spendTaps(player: Player, amount: number): boolean
	local p = Data.get(player)
	if not p or p.taps < amount then
		return false
	end
	p.taps -= amount
	dirtyCurrency[player] = true
	return true
end

function State.addGems(player: Player, amount: number)
	local p = Data.get(player)
	if not p then
		return
	end
	p.gems += amount
	dirtyCurrency[player] = true
end

function State.spendGems(player: Player, amount: number): boolean
	local p = Data.get(player)
	if not p or p.gems < amount then
		return false
	end
	p.gems -= amount
	dirtyCurrency[player] = true
	return true
end

---------------------------------------------------------------------------
-- Replication
---------------------------------------------------------------------------
function State.dirty(player: Player)
	dirtyFull[player] = true
end

-- Other clients render this player's pets from this attribute: "petId:tier,petId:tier"
function State.replicateEquipped(player: Player)
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
	player:SetAttribute("VIP", State.owns(player, "VIP"))
end

function State.snapshot(player: Player): { [string]: any }?
	local p = Data.get(player)
	if not p then
		return nil
	end
	local elapsed = State.giftElapsed(player, p)
	local gifts = GiftClock.claimedList(p.gifts)
	local snap: { [string]: any } = {
		taps = p.taps,
		gems = p.gems,
		dice = p.dice,
		totalTaps = p.totalTaps,
		rebirths = p.rebirths,
		zones = p.zones,
		pets = p.pets,
		equipped = p.equipped,
		upgrades = p.upgrades,
		discovered = p.discovered,
		indexClaimed = p.indexClaimed,
		passes = State.passes[player] or {},
		maxEquip = State.maxEquip(player, p),
		maxInventory = State.maxInventory(player),
		tapValue = State.tapValue(player, p),
		luck = State.luck(player, p),
		luckBoostLeft = p.luckBoostLeft,
		rebirthCost = Formulas.rebirthCost(p.rebirths),
		rebirthGems = Formulas.rebirthGems(p.rebirths),
		daily = { streak = p.daily.streak, last = p.daily.last },
		serverTime = os.time(),
		giftsClaimed = gifts,
		sessionElapsed = elapsed, -- seconds played today (name kept for the client)
		autoTap = p.settings.autoTap,
		autoHatch = State.autoHatch[player],
		friends = State.friends[player] or 0,
		totalHatched = p.totalHatched,
		persistent = Data.isPersistent(player),
		lang = p.lang,
		tapBoostLeft = p.tapBoostLeft,
		goldenChance = State.goldenChance(player),
		paidRandomRestricted = State.paidRandomRestricted[player] ~= false,
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
		State.replicateEquipped(player)
	end
	dirtyFull[player] = nil
	dirtyCurrency[player] = nil
	lastCurrency[player] = os.clock()
end

local function flush()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if State.ready[player] then
			if dirtyFull[player] then
				State.sendFull(player)
			elseif dirtyCurrency[player] and now - (lastCurrency[player] or 0) >= CURRENCY_INTERVAL then
				dirtyCurrency[player] = nil
				lastCurrency[player] = now
				local p = Data.get(player)
				if p then
					Remotes.fire("Currency", player, { taps = p.taps, gems = p.gems, totalTaps = p.totalTaps })
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
