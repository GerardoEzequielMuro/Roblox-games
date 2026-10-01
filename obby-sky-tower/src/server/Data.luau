--!strict
-- Player profiles: DataStore load/save with a soft session lock, reconcile, autosave and BindToClose.
-- (Adapted from the huerta-tycoon Data service.)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Powerups = require(ReplicatedStorage.Shared.Powerups)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Security = require(ReplicatedStorage.Shared.Security)

local Data = {}

-- Schema version written by this build. A profile saved by a NEWER build is never loaded (and so
-- never overwritten): the session just runs unsaved instead of downgrading someone's data.
Data.VERSION = 2

export type Profile = {
	version: number,
	stage: number, -- saved checkpoint, 0..1000 (0 = lobby start)
	best: number, -- highest stage ever reached
	base: boolean, -- on a summit (stage 100, 200...): already took the portal to the next tower
	runTop: number, -- highest summit already rewarded in this run (Rules.summitRewarded; 0 after a rebirth)
	gifts: { [string]: boolean }, -- tower gifts owned, by gift id ("1".."10", Shared/Gifts)
	boosts: { [string]: number }, -- shop power-ups: id -> os.time() when it ends (Shared/Powerups)
	charges: { [string]: number }, -- shop charges: shield, pocket
	perks: { [string]: any }, -- Winner's Lounge: taken[id] = true, plus dash / triplejump (on/off), glow, jumpfx
	pocket: { stage: number, at: number, x: number, y: number, z: number }?, -- portable checkpoint
	wins: number,
	coins: number,
	totalCoins: number,
	freeSkips: number,
	trails: { [string]: boolean },
	equippedTrail: string, -- "" = none, "rebirth" = rebirth colour
	effects: { [string]: boolean },
	equippedEffect: string,
	pets: { [string]: boolean }, -- shoulder companions bought with coins (Config.Pets)
	equippedPet: string, -- "" = none
	shine: { [string]: number }, -- cosmetic upgrade levels 1..Config.ShineMax, key "trail:<id>" / "effect:<id>" / "pet:<id>"
	settings: { speedCoil: boolean, gravityCoil: boolean, effects: boolean },
	lang: string, -- "" = follow the account locale; else a Locale.LANGS code
	bestRunMs: number, -- fastest valid climb 0 -> 100 (0 = none)
	ads: { day: number, count: number }, -- rewarded-video skips watched today (UTC day number)
	referredBy: number, -- inviter UserId (0 = none)
	referralPaid: boolean, -- inviter already credited for this player
	referralRewards: number, -- rewards received as an inviter (capped)
	starterBought: boolean,
	boostEndsAt: number, -- os.time() when the x2 coins boost ends
	groupGiftClaimed: boolean,
	notifAskedAt: number,
	purchases: { string }, -- recent processed receipt ids (idempotent ProcessReceipt)
	daily: { lastClaim: number, streak: number },
	codes: { [string]: boolean },
	savedAt: number,
	firstJoin: number,
	playTime: number,
	lock: { job: string, t: number }?,
}

local store: DataStore? = nil
local storeOk = false
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
		storeOk = true
	else
		warn("[Data] DataStore unavailable, progress will NOT save:", result)
	end
end

Data.profiles = {} :: { [Player]: Profile }
local loadedOk: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {} -- an UpdateAsync for this player is in flight
local LOCK_TTL = 150
local SAVE_ATTEMPTS = 4
local SAVE_BACKOFF = 1 -- seconds, doubled after every failed attempt

local function defaultProfile(): Profile
	return {
		version = 2,
		stage = 0,
		best = 0,
		base = false,
		runTop = 0,
		gifts = {},
		boosts = {},
		charges = {},
		perks = {},
		wins = 0,
		coins = 0,
		totalCoins = 0,
		freeSkips = 0,
		trails = {},
		equippedTrail = "",
		effects = {},
		equippedEffect = "",
		pets = {},
		equippedPet = "",
		shine = {},
		-- coils start OFF: a new player meets the map with the plain classic jump
		settings = { speedCoil = false, gravityCoil = false, effects = true },
		lang = "",
		bestRunMs = 0,
		ads = { day = 0, count = 0 },
		referredBy = 0,
		referralPaid = false,
		referralRewards = 0,
		starterBought = false,
		boostEndsAt = 0,
		groupGiftClaimed = false,
		notifAskedAt = 0,
		purchases = {},
		daily = { lastClaim = 0, streak = 0 },
		codes = {},
		savedAt = os.time(),
		firstJoin = os.time(),
		playTime = 0,
	}
end
Data.defaultProfile = defaultProfile

-- Fill any keys added in later versions and sanitise values.
local function reconcile(p: any): Profile
	local def = defaultProfile() :: any
	-- saved before the once-per-run summit rule: the summits under the saved stage were paid
	if type(p.runTop) ~= "number" then
		p.runTop = Rules.runTopFromStage(Layout :: any, math.floor(tonumber(p.stage) or 0))
	end
	-- a corrupted / hand-edited entry must not break the loop below
	if type(p.settings) ~= "table" then
		p.settings = nil
	end
	-- saves from before the late-game cosmetics have no pets / shine; a corrupted entry is reset
	for _, k in { "pets", "shine" } do
		if type(p[k]) ~= "table" then
			p[k] = nil
		end
	end
	if type(p.equippedPet) ~= "string" then
		p.equippedPet = nil
	end
	for k, v in def do
		if p[k] == nil then
			p[k] = v
		end
	end
	for k, v in def.settings do
		if p.settings[k] == nil then
			p.settings[k] = v
		end
	end
	if (tonumber(p.version) or 1) < 2 then
		-- v1 profiles were created with both coils switched on by default
		p.settings.speedCoil = false
		p.settings.gravityCoil = false
		p.version = 2
	end
	p.stage = math.clamp(math.floor(tonumber(p.stage) or 0), 0, Layout.TOTAL)
	p.best = math.clamp(math.max(tonumber(p.best) or 0, p.stage), 0, Layout.TOTAL)
	p.runTop = math.clamp(math.floor(p.runTop), 0, Layout.TOTAL)
	for k, v in p.shine do
		local n = tonumber(v)
		p.shine[k] = if n then math.clamp(math.floor(n), 0, Config.ShineMax) else nil
	end
	-- gifts are earned by the best stage: nobody who got there is left without one
	for _, gift in Gifts.earned(p.best) do
		p.gifts[tostring(gift.id)] = true
		if gift.kind == "trail" then
			p.trails[gift.value] = true
		elseif gift.kind == "effect" then
			p.effects[gift.value] = true
		end
	end
	Powerups.sweep(p.boosts, os.time())
	local fixed = Security.sanitizeProfile(p)
	if fixed > 0 then
		warn("[Data] repaired", fixed, "invalid values in a loaded profile")
	end
	return p :: Profile
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

function Data.load(player: Player): Profile
	if not storeOk or not store then
		local p = defaultProfile()
		Data.profiles[player] = p
		loadedOk[player] = false
		return p
	end
	local ds = store :: DataStore
	local result: any = nil
	for attempt = 1, 6 do
		local lockedByOther = false
		local tooNew = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				local now = os.time()
				if old and old.lock and old.lock.job ~= game.JobId and now - old.lock.t < LOCK_TTL and attempt < 6 then
					lockedByOther = true
					return nil -- abort write
				end
				if old and (tonumber(old.version) or 1) > Data.VERSION then
					tooNew = true
					return nil -- saved by a newer build: do not touch it
				end
				local p = if old then reconcile(old) else defaultProfile()
				p.lock = { job = game.JobId, t = now }
				result = p
				return p
			end)
		end)
		if tooNew then
			warn("[Data] profile of", player.Name, "was saved by a newer version - session will not save")
			result = nil
			break
		end
		if ok and not lockedByOther and result then
			break
		end
		if not ok then
			warn("[Data] load failed for", player.Name, err)
		end
		result = nil
		task.wait(if lockedByOther then 5 else 2)
		if not player.Parent then
			break
		end
	end
	if not result then
		-- Never overwrite real data with a blank profile: keep this session unsaved.
		warn("[Data] could not load", player.Name, "- session will not save")
		result = defaultProfile()
		loadedOk[player] = false
	else
		loadedOk[player] = true
	end
	Data.profiles[player] = result
	return result
end

-- Request budget left for UpdateAsync (math.huge when it can't be read, e.g. in Studio mocks).
local function budgetLeft(): number
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return if ok and type(n) == "number" then n else math.huge
end

-- Saves the profile with UpdateAsync (never a blind SetAsync) under the soft session lock, with
-- retries and exponential backoff. Returns true when the data reached the DataStore.
--   release   : final save, drops the lock
--   important : waits for a save already in flight and for budget (purchases) instead of skipping
function Data.save(player: Player, release: boolean?, important: boolean?): boolean
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store then
		return false
	end
	if saving[player] then
		if not release and not important then
			return false -- an autosave / win save is already writing this profile
		end
		local t0 = os.clock()
		while saving[player] and os.clock() - t0 < 20 do
			task.wait(0.1)
		end
		if saving[player] or not loadedOk[player] then
			return false
		end
	end
	saving[player] = true
	local ds = store :: DataStore
	local done = false
	local lost = false
	local attempts = if release or important then SAVE_ATTEMPTS else 2
	for attempt = 1, attempts do
		if not release and not important and budgetLeft() < 2 then
			break -- autosave: leave the budget to loads and purchases, try again next interval
		end
		Security.sanitizeProfile(p) -- NaN / inf / negative currency never reach the store
		p.savedAt = os.time()
		p.lock = if release then nil else { job = game.JobId, t = os.time() }
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				if old and old.lock and old.lock.job ~= game.JobId and os.time() - old.lock.t < LOCK_TTL then
					lost = true
					return nil -- another server owns it now; don't clobber
				end
				if old and (tonumber(old.version) or 1) > Data.VERSION then
					lost = true
					return nil
				end
				return p
			end)
		end)
		if ok and lost then
			warn("[Data] lost the session lock of", player.Name, "- this session stops saving")
			loadedOk[player] = false
			break
		end
		if ok then
			done = true
			break
		end
		warn("[Data] save failed for", player.Name, "(attempt", attempt, "):", err)
		if attempt < attempts then
			task.wait(SAVE_BACKOFF * 2 ^ (attempt - 1))
		end
	end
	saving[player] = nil
	return done
end

function Data.release(player: Player)
	Data.save(player, true)
	Data.profiles[player] = nil
	loadedOk[player] = nil
	saving[player] = nil
end

function Data.isPersistent(player: Player): boolean
	return loadedOk[player] == true
end

function Data.get(player: Player): Profile?
	return Data.profiles[player]
end

function Data.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			-- spread the writes over the interval instead of one burst for the whole server
			local list = Players:GetPlayers()
			local gap = math.min(2, Config.AutosaveInterval / math.max(#list, 1) / 2)
			for _, player in list do
				if player.Parent then
					task.spawn(Data.save, player)
					task.wait(gap)
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				Data.save(player, true)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
end

return Data
