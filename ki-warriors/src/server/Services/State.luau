--!strict
-- Derived stats, currency helpers and state replication.
--   State.dirty(player)      full snapshot (throttled)
--   State.touch(player)      only the fast numbers (stats, sparks, gems) at 5 Hz
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Collection = require(ReplicatedStorage.Shared.Collection)
local PlayRewards = require(ReplicatedStorage.Shared.PlayRewards)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)

local State = {}

State.ready = {} :: { [Player]: boolean }
State.passes = {} :: { [Player]: { [string]: boolean } }
State.sessionStart = {} :: { [Player]: number }
State.zone = {} :: { [Player]: { id: string, mult: number, locked: boolean }? }
State.friendBonus = {} :: { [Player]: number }
State.groupMember = {} :: { [Player]: boolean }
State.randomRestricted = {} :: { [Player]: boolean } -- PolicyService: paid random items
State.eventEffects = { trainMult = 1, sparkMult = 1 }
-- Other services add keys to the snapshot: extras[name] = function(player, profile) -> value
State.extras = {} :: { [string]: (Player, Data.Profile) -> any }

local fullDirty: { [Player]: boolean } = {}
local lightDirty: { [Player]: boolean } = {}

-- Claimed session gifts as { [index] = true } for the client.
function State.giftsClaimedMap(p: Data.Profile): { [number]: boolean }
	local out = {}
	for _, i in PlayRewards.list(p.giftPlay) do
		out[i] = true
	end
	return out
end

function State.init(player: Player)
	State.passes[player] = {}
	State.sessionStart[player] = os.time()
	State.friendBonus[player] = 0
end

function State.cleanup(player: Player)
	State.ready[player] = nil
	State.passes[player] = nil
	State.sessionStart[player] = nil
	State.zone[player] = nil
	State.friendBonus[player] = nil
	State.groupMember[player] = nil
	State.randomRestricted[player] = nil
	fullDirty[player] = nil
	lightDirty[player] = nil
end

function State.owns(player: Player, passKey: string): boolean
	local owned = State.passes[player]
	return owned ~= nil and owned[passKey] == true
end

-- Facts the earn-or-buy rules look at (Shared/Collection).
function State.collectionCtx(player: Player, p: Data.Profile): Collection.Ctx
	return {
		passes = State.passes[player] or {},
		bossKills = p.bossKills,
		rebirths = p.rebirths,
		pvpKills = p.pvp.kills,
		planet = State.bestPlanet(p),
		power = math.max(p.bestPower, Formulas.power(p.stats)),
	}
end

-- Adds what bundles imply and what progression has earned (DoubleBundle, TimeChamber...) to
-- the player's pass set, in place. Call after anything that changes passes or progress.
function State.refreshPasses(player: Player)
	local p = Data.get(player)
	local owned = State.passes[player]
	if not p or not owned then
		return
	end
	for key, value in Collection.expandPasses(owned, State.collectionCtx(player, p)) do
		if value then
			owned[key] = true
		end
	end
end

function State.power(p: Data.Profile): number
	return Formulas.power(p.stats)
end

function State.auraMult(p: Data.Profile): number
	local a = Config.AuraById[p.auraEquipped]
	return if a then a.mult else 1
end

function State.socialBonus(player: Player): number
	local b = State.friendBonus[player] or 0
	if player.MembershipType == Enum.MembershipType.Premium then
		b += Config.PremiumBonus
	end
	if State.groupMember[player] then
		b += Config.GroupBonus
	end
	return b
end

function State.trainContext(player: Player, p: Data.Profile, stat: string): Formulas.TrainContext
	local zone = State.zone[player]
	local race = Config.RaceById[p.race]
	return {
		zoneMult = if zone and not zone.locked then zone.mult else 1,
		gearTier = p.gear,
		rebirths = p.rebirths,
		upgradeLevel = p.upgrades.trainPower or 0,
		auraMult = State.auraMult(p),
		wishPower = p.wishPower,
		passDouble = State.owns(player, "DoubleTraining"),
		vip = State.owns(player, "VIP"),
		boost = p.boostLeft > 0,
		eventMult = State.eventEffects.trainMult,
		socialBonus = State.socialBonus(player),
		raceBonus = if race and race.bonus == stat then race.amount else 0,
	}
end

function State.gainPerRep(player: Player, p: Data.Profile, stat: string): number
	return Formulas.trainGain(State.trainContext(player, p, stat))
end

function State.autoRate(player: Player, p: Data.Profile): number
	return Formulas.autoRate(p.upgrades.autoSpeed or 0, State.owns(player, "TurboAuto"))
end

function State.bestPlanet(p: Data.Profile): number
	local best = 1
	for _, i in p.planets do
		best = math.max(best, i)
	end
	return best
end

function State.sparkMult(player: Player, p: Data.Profile): number
	local m = 1 + Formulas.upgradeValue("sparkGain", p.upgrades.sparkGain or 0)
	if State.owns(player, "DoubleSparks") then
		m *= 2
	end
	local race = Config.RaceById[p.race]
	if race and race.bonus == "sparks" then
		m *= 1 + race.amount
	end
	return m * State.eventEffects.sparkMult
end

-- scaled = true applies the player's Spark multipliers (enemy drops); false = exact amount.
function State.addSparks(player: Player, amount: number, scaled: boolean?): number
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return 0
	end
	if scaled then
		amount *= State.sparkMult(player, p)
	end
	amount = math.floor(amount + 0.5)
	p.sparks += amount
	lightDirty[player] = true
	return amount
end

function State.spendSparks(player: Player, amount: number): boolean
	local p = Data.get(player)
	if not p or amount ~= amount or amount < 0 or amount == math.huge or p.sparks < amount then
		return false
	end
	p.sparks -= amount
	lightDirty[player] = true
	return true
end

function State.addGems(player: Player, amount: number)
	local p = Data.get(player)
	if p and amount == amount and amount > 0 then
		p.gems += math.floor(amount)
		lightDirty[player] = true
	end
end

function State.spendGems(player: Player, amount: number): boolean
	local p = Data.get(player)
	if not p or amount ~= amount or amount < 0 or amount == math.huge or p.gems < amount then
		return false
	end
	p.gems -= amount
	lightDirty[player] = true
	return true
end

-- "Minutes of Sparks" rewards scale with the best planet the player has reached.
function State.sparksForMinutes(p: Data.Profile, minutes: number): number
	return math.floor(Formulas.sparksPerMinute(State.bestPlanet(p)) * minutes)
end

function State.snapshot(player: Player): { [string]: any }
	local p = Data.get(player) :: Data.Profile
	State.refreshPasses(player)
	local perRep = {}
	for _, s in Config.Stats do
		perRep[s] = State.gainPerRep(player, p, s)
	end
	local zone = State.zone[player]
	local snap: { [string]: any } = {
		stats = p.stats,
		power = State.power(p),
		bestPower = p.bestPower,
		sparks = p.sparks,
		gems = p.gems,
		rebirths = p.rebirths,
		planet = p.planet,
		planets = p.planets,
		gear = p.gear,
		techniques = p.techniques,
		forms = p.forms,
		auras = p.auras,
		auraEquipped = p.auraEquipped,
		spins = p.spins,
		race = p.race,
		raceChanges = p.raceChanges,
		upgrades = p.upgrades,
		story = p.story,
		settings = p.settings,
		lang = p.lang,
		boostLeft = p.boostLeft,
		passes = State.passes[player] or {},
		perRep = perRep,
		zone = if zone then zone.id else "",
		zoneLocked = if zone then zone.locked else false,
		autoRate = State.autoRate(player, p),
		sparkMult = State.sparkMult(player, p),
		socialBonus = State.socialBonus(player),
		eventEffects = State.eventEffects,
		rebirthReq = Formulas.rebirthRequirement(p.rebirths),
		daily = p.daily,
		codes = p.codes,
		playTime = p.playTime,
		sessionStart = os.time() - math.floor(p.giftPlay.secs), -- "started playing today" as if it were one session: the client counts from here
		giftsClaimed = State.giftsClaimedMap(p),
		wishes = p.wishes,
		wishPower = p.wishPower,
		pvp = p.pvp,
		protectionOff = p.protectionOff,
		kills = p.kills,
		bossKills = p.bossKills,
		totalReps = p.totalReps,
		firstJoin = p.firstJoin,
		serverTime = os.time(),
		persistent = Data.isPersistent(player),
		randomRestricted = State.randomRestricted[player] == true,
	}
	for name, fn in State.extras do
		local ok, value = pcall(fn, player, p)
		if ok then
			snap[name] = value
		else
			warn("[State] extra", name, value)
		end
	end
	return snap
end

function State.sendFull(player: Player)
	if State.ready[player] and Data.get(player) then
		fullDirty[player] = nil
		lightDirty[player] = nil
		Remotes.fire("State", player, State.snapshot(player))
	end
end

function State.dirty(player: Player)
	fullDirty[player] = true
end

function State.touch(player: Player)
	lightDirty[player] = true
end

function State.start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, player in Players:GetPlayers() do
				if not State.ready[player] then
					continue
				end
				if fullDirty[player] then
					State.sendFull(player)
				elseif lightDirty[player] then
					lightDirty[player] = nil
					local p = Data.get(player)
					if p then
						Remotes.fire("Numbers", player, { stats = p.stats, power = State.power(p), sparks = p.sparks, gems = p.gems, boostLeft = p.boostLeft, totalReps = p.totalReps })
					end
				end
			end
		end
	end)
	-- play time + timed boost
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				if p and State.ready[player] then
					p.playTime += 1
					PlayRewards.tick(p.giftPlay, os.time(), 1)
					if p.boostLeft > 0 then
						p.boostLeft = math.max(0, p.boostLeft - 1)
						if p.boostLeft == 0 then
							fullDirty[player] = true
						end
					end
				end
			end
		end
	end)
end

return State
