--!strict
-- Session state that isn't persisted (passes, gifts, where the player sits) plus the only
-- functions allowed to change coins / xp / trophies, and the dirty-flag replication of the
-- profile to its owner.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local M = Locale.m

local State = {}

State.passes = {} :: { [Player]: { [string]: boolean } }
State.sessionStart = {} :: { [Player]: number }
State.giftsClaimed = {} :: { [Player]: { [number]: boolean } }
State.ready = {} :: { [Player]: boolean }
State.lastEmote = {} :: { [Player]: number }
-- Extra snapshot sections contributed by other services (quests, table, starter...).
State.extras = {} :: { [string]: (Player, Data.Profile) -> any }
-- Called when a player's level / wins / trophies / passes change (cosmetic unlock checks).
State.onProgress = {} :: { (Player) -> () }

local dirty: { [Player]: boolean } = {}

function State.init(player: Player)
	State.passes[player] = State.passes[player] or {}
	State.sessionStart[player] = os.clock()
	State.giftsClaimed[player] = {}
	State.lastEmote[player] = 0
end

function State.cleanup(player: Player)
	State.passes[player] = nil
	State.sessionStart[player] = nil
	State.giftsClaimed[player] = nil
	State.ready[player] = nil
	State.lastEmote[player] = nil
	dirty[player] = nil
end

-- Per-player bookkeeping tables still holding this player (leak check in the playtest).
function State.tracked(player: Player): number
	local n = 0
	for _, t in { State.passes, State.sessionStart, State.giftsClaimed, State.ready, State.lastEmote, dirty } :: { { [Player]: any } } do
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

-- Pass multipliers (events are added per match by the runner).
function State.coinMult(player: Player): number
	local mult = 1
	for _, pass in Config.Passes do
		if State.owns(player, pass.key) then
			mult *= pass.coinMult
		end
	end
	return mult
end

function State.xpMult(player: Player): number
	local mult = 1
	for _, pass in Config.Passes do
		if State.owns(player, pass.key) then
			mult *= pass.xpMult
		end
	end
	return mult
end

local function progressed(player: Player)
	for _, fn in State.onProgress do
		task.spawn(fn, player)
	end
end
State.progressed = progressed

---------------------------------------------------------------------------
-- Currency / progression helpers (server-authoritative)
---------------------------------------------------------------------------
function State.addCoins(player: Player, amount: number)
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return
	end
	p.coins += math.floor(amount)
	dirty[player] = true
end

function State.spendCoins(player: Player, amount: number): boolean
	local p = Data.get(player)
	if not p or amount ~= amount or amount < 0 or p.coins < amount then
		return false
	end
	p.coins -= math.floor(amount)
	dirty[player] = true
	return true
end

-- Returns levels gained.
function State.addXp(player: Player, amount: number): number
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return 0
	end
	local level, xp, gained = Progression.addXp(p.level, p.xp, amount)
	local from = p.level
	p.level, p.xp = level, xp
	if gained > 0 then
		local coins = 0
		for l = from + 1, level do
			coins += Progression.levelUpCoins(l)
		end
		p.coins += coins
		Remotes.fire("LevelUp", player, { level = level, coins = coins })
		progressed(player)
	end
	dirty[player] = true
	return gained
end

-- Trophies only ever go up inside a season.
function State.addTrophies(player: Player, amount: number)
	local p = Data.get(player)
	if not p or amount ~= amount or amount <= 0 then
		return
	end
	local before = Progression.league(p.trophies)
	p.trophies += math.floor(amount)
	p.bestTrophies = math.max(p.bestTrophies, p.trophies)
	local after = Progression.league(p.trophies)
	if after.id ~= before.id then
		Remotes.notify(player, M("msg.league_up", { league = M("league." .. after.id) }), "success")
		progressed(player)
	end
	dirty[player] = true
end

-- New calendar month: pay the league reward and carry half of the trophies.
function State.checkSeason(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local season = Progression.season(os.time())
	if p.season == season then
		return
	end
	if p.season ~= 0 and p.trophies > 0 then
		local reward = Progression.seasonReward(p.trophies)
		local league = Progression.league(p.trophies)
		p.trophies = Progression.seasonCarry(p.trophies)
		if reward > 0 then
			p.coins += reward
		end
		Remotes.notify(player, M("msg.season_end", { league = M("league." .. league.id), n = reward }), "success")
	end
	p.season = season
	dirty[player] = true
end

---------------------------------------------------------------------------
-- Replication
---------------------------------------------------------------------------
function State.dirty(player: Player)
	dirty[player] = true
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
	local league = Progression.league(p.trophies)
	local nextLeague = Progression.nextLeague(p.trophies)
	local snap: { [string]: any } = {
		coins = p.coins,
		xp = p.xp,
		level = p.level,
		xpNeed = Progression.xpForLevel(p.level),
		trophies = p.trophies,
		bestTrophies = p.bestTrophies,
		league = league.id,
		nextLeague = if nextLeague then { id = nextLeague.id, trophies = nextLeague.trophies } else nil,
		seasonEndsAt = Progression.seasonEndsAt(os.time()),
		wins = p.wins,
		matches = p.matches,
		streak = p.streak,
		bestStreak = p.bestStreak,
		elims = p.elims,
		equipped = p.equipped,
		emotes = p.emotes,
		emoteSlots = if State.owns(player, "EmotePack") then Config.EmoteSlotsPack else Config.EmoteSlots,
		passes = State.passes[player] or {},
		coinMult = State.coinMult(player),
		daily = { streak = p.daily.streak, last = p.daily.last },
		serverTime = os.time(),
		giftsClaimed = gifts,
		sessionElapsed = os.clock() - (State.sessionStart[player] or os.clock()),
		settings = p.settings,
		persistent = Data.isPersistent(player),
		lang = p.lang,
		tutorialDone = p.tutorialDone,
		codes = p.codes,
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
	end
	dirty[player] = nil
end

local function flush()
	for _, player in Players:GetPlayers() do
		if State.ready[player] and dirty[player] then
			State.sendFull(player)
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
	-- play time
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				if p and State.ready[player] then
					p.playTime += 10
				end
			end
		end
	end)
end

return State
