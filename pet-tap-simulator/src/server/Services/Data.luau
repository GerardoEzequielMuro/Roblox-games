--!strict
-- Player profiles: DataStore load/save with a soft session lock, reconcile, autosave
-- and BindToClose. Adapted from Crop Kingdom.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local GiftClock = require(ReplicatedStorage.Shared.GiftClock)
local Guard = require(script.Parent.Guard)

local Data = {}

export type PetEntry = { id: string, tier: number, locked: boolean, trait: number? }

export type Profile = {
	version: number,
	taps: number,
	gems: number,
	dice: number, -- Trait Dice (earned by playing, never sold)
	totalTaps: number,
	rebirths: number,
	zones: { number }, -- unlocked zone indexes
	pets: { [string]: PetEntry }, -- uid -> pet
	equipped: { string }, -- uids
	nextUid: number,
	upgrades: { [string]: number },
	discovered: { [string]: boolean },
	indexClaimed: { [string]: boolean }, -- tostring(zone) -> claimed
	daily: { last: number, streak: number },
	codes: { [string]: boolean },
	purchases: { string }, -- recent processed receipt PurchaseIds (idempotency)
	luckBoostLeft: number, -- seconds of Super Luck remaining (ticks while online)
	settings: { autoTap: boolean, autoEquip: boolean, autoRebirth: boolean },
	lang: string, -- UI language code, "" = use the account locale
	offlinePending: number, -- taps collected while away, waiting to be claimed
	offlineSeconds: number,
	referredBy: number, -- inviter user id (0 = none)
	referralPaid: boolean, -- inviter credited after our first 10 minutes
	referralRewards: number, -- inviter-side rewards received (lifetime cap)
	starterBought: boolean,
	ads: { day: number, count: number },
	tapBoostLeft: number, -- seconds of rewarded-video x2 taps
	quests: { day: number, list: { { kind: string, target: number, gems: number } }, progress: { number }, claimed: { boolean }, bonusClaimed: boolean },
	notifAskedAt: number,
	groupGiftClaimed: boolean,
	totalHatched: number,
	savedAt: number,
	firstJoin: number,
	playTime: number,
	gifts: GiftClock.Gifts, -- session gifts: UTC day, seconds played that day, claimed indexes
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
local nextSave: { [Player]: number } = {}
local saving: { [Player]: boolean } = {} -- a write is in flight (writes per player never overlap)
local LOCK_TTL = 150
local SAVE_ATTEMPTS = 3 -- normal saves (autosave, receipts)
local RELEASE_ATTEMPTS = 5 -- leaving / server shutdown: worth trying harder
local shutdownDeadline = math.huge -- os.clock() by which BindToClose must be done

-- Profile schema version. Add a step { [oldVersion] = function(profile) ... end } below when a
-- release changes the shape of saved data; reconcile() runs them in order on load.
Data.VERSION = 1
local MIGRATIONS: { [number]: (any) -> () } = {}
local CURRENCY_KEYS = { "taps", "gems", "dice", "totalTaps", "rebirths", "nextUid", "luckBoostLeft", "tapBoostLeft", "offlinePending", "offlineSeconds", "referralRewards", "totalHatched", "playTime" }

-- True when saving is possible at all (false in Studio without API access, or if the store failed).
function Data.canPersist(): boolean
	return storeOk
end

-- DataStore budget left for UpdateAsync (1 when it cannot be read).
local function updateBudget(): number
	local n = 1
	pcall(function()
		n = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return n
end

-- Waits (bounded) until the write budget has room. Returns false when it never did.
local function waitBudget(maxWait: number): boolean
	local t0 = os.clock()
	while updateBudget() <= 0 do
		if os.clock() - t0 >= maxWait or os.clock() > shutdownDeadline then
			return false
		end
		task.wait(0.5)
	end
	return true
end

local function defaultProfile(): Profile
	local upgrades = {}
	for _, u in Config.Upgrades do
		upgrades[u.id] = 0
	end
	local p: Profile = {
		version = Data.VERSION,
		taps = 0,
		gems = 0,
		dice = Config.TraitDice.start,
		totalTaps = 0,
		rebirths = 0,
		zones = { 1 },
		pets = {},
		equipped = {},
		nextUid = 1,
		upgrades = upgrades,
		discovered = {},
		indexClaimed = {},
		daily = { last = 0, streak = 0 },
		codes = {},
		purchases = {},
		luckBoostLeft = 0,
		settings = { autoTap = true, autoEquip = false, autoRebirth = false },
		lang = "",
		offlinePending = 0,
		offlineSeconds = 0,
		referredBy = 0,
		referralPaid = false,
		referralRewards = 0,
		starterBought = false,
		ads = { day = 0, count = 0 },
		tapBoostLeft = 0,
		quests = { day = -1, list = {}, progress = {}, claimed = {}, bonusClaimed = false },
		notifAskedAt = 0,
		groupGiftClaimed = false,
		totalHatched = 0,
		savedAt = os.time(),
		firstJoin = os.time(),
		playTime = 0,
		gifts = GiftClock.default(),
	}
	-- starter pet, equipped
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
	if type(p) ~= "table" then
		return def :: Profile
	end
	Guard.scrub(p) -- NaN / inf from an old bug or a corrupt write never enter the session
	for k, v in def do
		if p[k] == nil then
			p[k] = v
		end
	end
	Guard.fixTypes(p, def, Guard.deepCopy) -- wrong-typed fields fall back to the default
	Guard.migrate(p, MIGRATIONS, Data.VERSION)
	p.gifts = GiftClock.sanitize(p.gifts)
	Guard.clampNonNegative(p, CURRENCY_KEYS)
	for _, u in Config.Upgrades do
		local lv = p.upgrades[u.id]
		p.upgrades[u.id] = if Guard.int(lv, 0, u.maxLevel) then lv else math.clamp(math.floor(tonumber(lv) or 0), 0, u.maxLevel)
	end
	local zones, seenZone = {}, {}
	for _, z in p.zones do
		if Guard.int(z, 1, #Config.Zones) and not seenZone[z] then
			seenZone[z] = true
			table.insert(zones, z)
		end
	end
	if not seenZone[1] then
		table.insert(zones, 1, 1)
	end
	p.zones = zones
	for uid, pet in p.pets do
		if type(pet) ~= "table" or not Formulas.PetById[pet.id] then
			p.pets[uid] = nil
		else
			pet.tier = math.clamp(tonumber(pet.tier) or 0, 0, 2)
			pet.locked = pet.locked == true
			local trait = tonumber(pet.trait)
			pet.trait = if trait and Config.TraitGrades[trait] then trait else nil
		end
	end
	local eq, seenEq = {}, {}
	for _, uid in p.equipped do
		if type(uid) == "string" and p.pets[uid] and not seenEq[uid] then
			seenEq[uid] = true
			table.insert(eq, uid)
		end
	end
	p.equipped = eq
	if type(p.settings) ~= "table" then
		p.settings = {}
	end
	for k, v in def.settings do
		if type(p.settings[k]) ~= "boolean" then
			p.settings[k] = v
		end
	end
	return p :: Profile
end

Data.reconcile = reconcile

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
		waitBudget(10)
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				local now = os.time()
				if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= game.JobId and now - (tonumber(old.lock.t) or 0) < LOCK_TTL and attempt < 6 then
					lockedByOther = true
					return nil -- abort write, another server still owns the session
				end
				local p = if type(old) == "table" then reconcile(old) else defaultProfile()
				p.lock = { job = game.JobId, t = now }
				result = p
				return p
			end)
		end)
		if ok and not lockedByOther and result then
			break
		end
		if not ok then
			warn("[Data] load failed for", player.Name, err)
		end
		result = nil
		if RunService:IsStudio() and not ok then
			break -- Studio without API access: fail fast, play unsaved
		end
		task.wait(if lockedByOther then 5 else Guard.backoff(attempt, 2, 10))
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

-- Writes the profile with UpdateAsync (never a blind overwrite): it aborts if another server
-- holds a fresh session lock, retries with exponential backoff, waits for write budget, and
-- never lets two writes for the same player overlap. Returns true when the data was written.
function Data.save(player: Player, release: boolean?): boolean
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store then
		return false
	end
	if saving[player] then
		local t0 = os.clock()
		while saving[player] and os.clock() - t0 < 20 do
			task.wait(0.1)
		end
		if saving[player] or Data.profiles[player] ~= p then
			return false
		end
	end
	saving[player] = true
	local ds = store :: DataStore
	local attempts = if RunService:IsStudio() then 1 elseif release then RELEASE_ATTEMPTS else SAVE_ATTEMPTS
	local wrote = false
	for attempt = 1, attempts do
		if attempt > 1 and os.clock() > shutdownDeadline then
			break
		end
		if not waitBudget(if release then 10 else 5) and attempt > 1 then
			break
		end
		local fixed = Guard.scrub(p) -- never save NaN / inf
		Guard.clampNonNegative(p :: any, CURRENCY_KEYS)
		if fixed > 0 then
			warn("[Data] scrubbed", fixed, "non-finite values before saving", player.Name)
		end
		p.savedAt = os.time()
		p.lock = if release then nil else { job = game.JobId, t = os.time() }
		local aborted = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= game.JobId and os.time() - (tonumber(old.lock.t) or 0) < LOCK_TTL then
					aborted = true
					return nil -- another server owns it now; don't clobber
				end
				wrote = true
				return p
			end)
		end)
		if ok then
			break -- written, or deliberately aborted by the lock check (retrying cannot help)
		end
		wrote = false
		warn("[Data] save failed for", player.Name, "attempt", attempt, err)
		if aborted or attempt >= attempts then
			break
		end
		task.wait(Guard.backoff(attempt, 1, 8))
	end
	saving[player] = nil
	return wrote
end

function Data.release(player: Player)
	Data.save(player, true)
	Data.profiles[player] = nil
	loadedOk[player] = nil
	nextSave[player] = nil
	saving[player] = nil
end

-- Per-player bookkeeping tables still holding this player (leak check in the playtest).
function Data.tracked(player: Player): number
	local n = 0
	for _, t in { Data.profiles, loadedOk, nextSave, saving } :: { { [Player]: any } } do
		if t[player] ~= nil then
			n += 1
		end
	end
	return n
end

function Data.get(player: Player): Profile?
	return Data.profiles[player]
end

function Data.isPersistent(player: Player): boolean
	return loadedOk[player] == true
end

function Data.startAutosave()
	-- Staggered: each player is saved once per AutosaveInterval, spread over the interval by
	-- the order they joined, and only while the DataStore write budget has room. No burst
	-- of writes every 90 s, however many players are in the server.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local due = nextSave[player]
				if not due then
					nextSave[player] = now + Config.AutosaveInterval
				elseif now >= due and Data.profiles[player] and not saving[player] then
					if updateBudget() > 0 then
						nextSave[player] = now + Config.AutosaveInterval
						task.spawn(Data.save, player)
						break -- at most one save per second
					end
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		shutdownDeadline = os.clock() + 25
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
