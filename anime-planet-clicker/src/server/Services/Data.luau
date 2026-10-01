--!strict
-- Player profiles: DataStore load/save with a soft session lock, reconcile, autosave and
-- BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Security = require(ReplicatedStorage.Shared.Security)

local Data = {}

export type PetEntry = { id: string, tier: number, locked: boolean, trait: string? }
export type Quest = { kind: string, target: number, crystals: number }

export type Profile = {
	version: number,
	stardust: number,
	crystals: number,
	totalMined: number, -- lifetime Stardust earned by mining (leaderboard)
	rebirths: number,
	zones: { number }, -- unlocked galaxy indexes
	tool: string,
	upgrades: { [string]: number },
	mats: { [string]: number }, -- galaxy materials
	relics: { [string]: { grade: number, dust: number } },
	pets: { [string]: PetEntry },
	equipped: { string },
	nextUid: number,
	discovered: { [string]: boolean },
	indexClaimed: { [string]: boolean }, -- tostring(zone)
	mastery: { [string]: number }, -- planet kind -> planets broken
	masteryPaid: { [string]: number }, -- planet kind -> highest level already rewarded
	gate: { [string]: number }, -- tostring(zone the gate leads to) -> HP left
	cargo: { count: number, value: number },
	buffs: { [string]: number }, -- buff id -> seconds left (ticks while online)
	auto: { [string]: boolean },
	autoDelete: { [string]: boolean }, -- rarity -> delete on open
	daily: { last: number, streak: number },
	codes: { [string]: boolean },
	purchases: { string },
	quests: { day: number, list: { Quest }, progress: { number }, claimed: { boolean }, bonusClaimed: boolean },
	anomalyWindow: number, -- start time of the last Anomaly this player broke
	arenaPoints: number,
	arenaKos: number,
	tutorial: number, -- index of the current step in Config.Tutorial (#steps + 1 = done)
	settings: { sfx: boolean, lite: boolean, hidePets: boolean },
	lang: string,
	offlinePending: number,
	offlineSeconds: number,
	referredBy: number,
	referralPaid: boolean,
	referralRewards: number,
	starterBought: boolean,
	fieldsFound: { [string]: boolean }, -- Asteroid Field tool id -> its first-time Crystals were paid
	ads: { day: number, count: number },
	notifAskedAt: number,
	groupGiftClaimed: boolean,
	totalOpened: number,
	planetsBroken: number,
	hits: number,
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
local saving: { [Player]: boolean } = {} -- one UpdateAsync per player at a time
local inflight = 0 -- saves running right now (BindToClose waits for them)
local closeDeadline: number? = nil -- os.clock() limit once the server is shutting down
local LOCK_TTL = 150

-- Profile layout version. A change to the shape that reconcile() cannot fill by itself gets a
-- migration here: Data.migrations[n] upgrades a version n profile to n + 1 in place.
Data.VERSION = 1
Data.migrations = {} :: { [number]: (any) -> () }

local function defaultProfile(): Profile
	local upgrades = {}
	for _, u in Config.Upgrades do
		upgrades[u.id] = 0
	end
	local mats = {}
	for _, m in Config.Materials do
		mats[m] = 0
	end
	local relics = {}
	for _, stat in Config.RelicStats do
		relics[stat] = { grade = 0, dust = 0 }
	end
	local p: Profile = {
		version = Data.VERSION,
		stardust = 0,
		crystals = 0,
		totalMined = 0,
		rebirths = 0,
		zones = { 1 },
		tool = Config.Tools[1].id,
		upgrades = upgrades,
		mats = mats,
		relics = relics,
		pets = {},
		equipped = {},
		nextUid = 1,
		discovered = {},
		indexClaimed = {},
		mastery = {},
		masteryPaid = {},
		gate = {},
		cargo = { count = 0, value = 0 },
		buffs = {},
		auto = table.clone(Config.AutoDefaults),
		autoDelete = {},
		daily = { last = 0, streak = 0 },
		codes = {},
		purchases = {},
		quests = { day = -1, list = {}, progress = {}, claimed = {}, bonusClaimed = false },
		anomalyWindow = 0,
		arenaPoints = 0,
		arenaKos = 0,
		tutorial = 1,
		settings = { sfx = true, lite = false, hidePets = false },
		lang = "",
		offlinePending = 0,
		offlineSeconds = 0,
		referredBy = 0,
		referralPaid = false,
		referralRewards = 0,
		starterBought = false,
		fieldsFound = {},
		ads = { day = 0, count = 0 },
		notifAskedAt = 0,
		groupGiftClaimed = false,
		totalOpened = 0,
		planetsBroken = 0,
		hits = 0,
		savedAt = os.time(),
		firstJoin = os.time(),
		playTime = 0,
	}
	p.pets.p1 = { id = Config.StartingPet, tier = 0, locked = false }
	p.equipped = { "p1" }
	p.nextUid = 2
	p.discovered[Config.StartingPet] = true
	return p
end
Data.defaultProfile = defaultProfile

-- Fill keys added in later versions and drop content that no longer exists in Config.
local function reconcile(p: any): Profile
	local def = defaultProfile() :: any
	for k, v in def do
		if p[k] == nil then
			p[k] = v
		end
	end
	for _, key in { "upgrades", "mats", "relics", "auto", "settings", "cargo" } do
		if type(p[key]) ~= "table" then
			p[key] = def[key]
		end
		for k, v in def[key] do
			if p[key][k] == nil then
				p[key][k] = v
			end
		end
	end
	if not Config.ToolById[p.tool] then
		p.tool = Config.Tools[1].id
	end
	if type(p.fieldsFound) ~= "table" then
		p.fieldsFound = {}
	end
	-- saves from before the Asteroid Field tools: whatever the player already passed is found
	-- (no back-pay), so only the fields ahead of them pay out
	if p.fieldsFound and next(p.fieldsFound) == nil then
		for i = 1, Config.ToolIndex[p.tool] or 1 do
			local t = Config.Tools[i]
			if t.field then
				p.fieldsFound[t.id] = true
			end
		end
	end
	for uid, pet in p.pets do
		if type(pet) ~= "table" or not Formulas.PetById[pet.id] then
			p.pets[uid] = nil
		else
			pet.tier = math.clamp(tonumber(pet.tier) or 0, 0, 2)
			pet.locked = pet.locked == true
			if pet.trait ~= nil and not Config.TraitIndex[pet.trait] then
				pet.trait = nil
			end
		end
	end
	local eq = {}
	for _, uid in p.equipped do
		if p.pets[uid] then
			table.insert(eq, uid)
		end
	end
	p.equipped = eq
	return p :: Profile
end
Data.reconcile = reconcile

-- True for DataStore errors that no retry can fix (Studio API access off, place not published).
function Data.isAccessDenied(err: any): boolean
	local s = tostring(err)
	return string.find(s, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(s, "HTTP 403", 1, true) ~= nil
		or string.find(s, "publish", 1, true) ~= nil
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

-- Waits (up to `maxWait` s) for DataStore request budget; true when there is some.
local function waitBudget(requestType: Enum.DataStoreRequestType, maxWait: number): boolean
	local t0 = os.clock()
	while true do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		if not ok or budget >= 1 then
			return true
		end
		if os.clock() - t0 >= maxWait then
			return false
		end
		task.wait(1)
	end
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
		local newer = false
		waitBudget(Enum.DataStoreRequestType.UpdateAsync, 5)
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				local now = os.time()
				if old ~= nil and type(old) ~= "table" then
					newer = true -- unreadable: never replace it with a blank profile
					return nil
				end
				if old and old.lock and old.lock.job ~= game.JobId and now - old.lock.t < LOCK_TTL and attempt < 6 then
					lockedByOther = true
					return nil -- abort write, another server still owns the session
				end
				if old and Security.migrate(old, Data.VERSION, Data.migrations) == "newer" then
					newer = true -- saved by a newer build: leave it alone
					return nil
				end
				local p = if old then reconcile(old) else defaultProfile()
				p.lock = { job = game.JobId, t = now }
				result = p
				return (Security.sanitize(p))
			end)
		end)
		if ok and newer then
			warn("[Data] save of", player.Name, "is from a newer version or unreadable - session will not save")
			result = nil
			break
		end
		if ok and not lockedByOther and result then
			break
		end
		if not ok then
			warn("[Data] load failed for", player.Name, err)
			-- Studio without "Enable Studio Access to API Services": every retry fails the same
			-- way, so stop now instead of holding the player on "loading" for ~12 s.
			if Data.isAccessDenied(err) then
				result = nil
				break
			end
		end
		result = nil
		task.wait(if lockedByOther then 5 else Security.backoff(attempt, 1.5, 8))
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

-- Saves the profile with UpdateAsync (never a blind SetAsync): the callback refuses to write
-- when another server took the session lock. The value is a sanitized copy (no NaN / inf),
-- rebuilt on every attempt. Final saves (release) retry with backoff. wait = queue behind a
-- running save instead of skipping (purchases). Returns true when the
-- data reached the store.
function Data.save(player: Player, release: boolean?, wait: boolean?): boolean
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store then
		return false
	end
	if saving[player] then
		if not release and not wait then
			return false -- autosave: the running save is close enough
		end
		local t0 = os.clock()
		while saving[player] and os.clock() - t0 < 20 do
			task.wait(0.1)
		end
		if saving[player] then
			return false
		end
	end
	saving[player] = true
	inflight += 1
	local ds = store :: DataStore
	local wrote = false
	local attempts = if release then 4 else 2
	for attempt = 1, attempts do
		if closeDeadline and os.clock() >= closeDeadline then
			break
		end
		if not waitBudget(Enum.DataStoreRequestType.UpdateAsync, if release then 6 else 0) then
			break -- out of budget: the next autosave will try again
		end
		p.savedAt = os.time()
		p.lock = if release then nil else { job = game.JobId, t = os.time() }
		local copy, fixed = Security.sanitize(p)
		if fixed > 0 then
			warn("[Data] repaired", fixed, "invalid values (NaN/inf) while saving", player.Name)
		end
		wrote = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				if type(old) == "table" and old.lock and old.lock.job ~= game.JobId and os.time() - old.lock.t < LOCK_TTL then
					return nil -- another server owns it now; don't clobber
				end
				if type(old) == "table" and type(old.version) == "number" and old.version > Data.VERSION then
					return nil -- a newer build wrote this; don't downgrade it
				end
				wrote = true
				return copy
			end)
		end)
		if ok then
			break
		end
		warn("[Data] save failed for", player.Name, err)
		if Data.isAccessDenied(err) then
			break
		end
		if attempt < attempts then
			task.wait(Security.backoff(attempt))
		end
	end
	saving[player] = nil
	inflight -= 1
	return wrote
end

function Data.release(player: Player)
	Data.save(player, true)
	Data.profiles[player] = nil
	loadedOk[player] = nil
	saving[player] = nil
end

function Data.get(player: Player): Profile?
	return Data.profiles[player]
end

function Data.isPersistent(player: Player): boolean
	return loadedOk[player] == true
end

function Data.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(Data.save, player)
				task.wait(0.2) -- spread the requests instead of one burst
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		closeDeadline = os.clock() + 24
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				Data.save(player, true)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		-- also wait for the PlayerRemoving releases that are still saving
		while (pending > 0 or inflight > 0) and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
end

return Data
