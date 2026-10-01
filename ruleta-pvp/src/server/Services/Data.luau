--!strict
-- Player profiles: DataStore load/save with a soft session lock, reconcile, autosave
-- and BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Guard = require(ReplicatedStorage.Shared.Guard)
local SeasonPass = require(ReplicatedStorage.Shared.SeasonPass)

local Data = {}

export type Settings = {
	music: number,
	sfx: number,
	shake: boolean,
	flashes: boolean,
	lite: boolean,
	autoQueue: boolean,
	autoPlay: boolean,
	autoCharge: boolean,
}

export type Profile = {
	version: number,
	coins: number,
	xp: number,
	level: number,
	trophies: number,
	bestTrophies: number,
	season: number,
	wins: number,
	pvpWins: number, -- wins against other people (the boards count these, not bot-table wins)
	matches: number,
	streak: number,
	bestStreak: number,
	elims: number,
	owned: { [string]: boolean }, -- bought / granted cosmetics (rule-unlocked ones are derived)
	equipped: { [string]: string }, -- kind -> cosmetic id
	emotes: { string },
	daily: { last: number, streak: number },
	codes: { [string]: boolean },
	purchases: { string }, -- recent processed receipt PurchaseIds (idempotency)
	settings: Settings,
	lang: string, -- UI language code, "" = use the account locale
	quests: { day: number, list: { { kind: string, target: number, coins: number, xp: number } }, progress: { number }, claimed: { boolean }, bonusClaimed: boolean },
	weekly: { week: number, wins: number },
	sp: SeasonPass.State, -- season pass of the current season
	core: { taps: number, charges: number },
	referredBy: number,
	referralPaid: boolean,
	referralRewards: number,
	starterBought: boolean,
	groupGiftClaimed: boolean,
	notifAskedAt: number,
	tutorialDone: boolean,
	savedAt: number,
	firstJoin: number,
	playTime: number,
	giftState: { day: number, played: number, claimed: { [number]: boolean } }, -- session gifts: UTC day, seconds played that day, claimed indexes
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
local LOCK_TTL = 150
-- Profile schema version. Bump it and add a step to migrate() when a field changes meaning.
--   1 -> 2: pvpWins (board wins) starts at the old win count so nobody drops on the board.
local CURRENT_VERSION = 2
local SAVE_ATTEMPTS = 4 -- critical saves (leaving, purchases) retry with backoff
local MIN_AUTOSAVE_BUDGET = 8 -- skip an autosave when the UpdateAsync budget is this low
local saving: { [Player]: boolean } = {}

local function defaultSettings(): Settings
	return { music = 0.5, sfx = 0.8, shake = true, flashes = true, lite = false, autoQueue = false, autoPlay = false, autoCharge = false }
end

local function defaultProfile(): Profile
	return {
		version = CURRENT_VERSION,
		coins = 0,
		xp = 0,
		level = 1,
		trophies = 0,
		bestTrophies = 0,
		season = 0,
		wins = 0,
		pvpWins = 0,
		matches = 0,
		streak = 0,
		bestStreak = 0,
		elims = 0,
		owned = {},
		equipped = table.clone(Config.DefaultEquipped),
		emotes = table.clone(Config.DefaultEmotes),
		daily = { last = 0, streak = 0 },
		codes = {},
		purchases = {},
		settings = defaultSettings(),
		lang = "",
		quests = { day = -1, list = {}, progress = {}, claimed = {}, bonusClaimed = false },
		weekly = { week = 0, wins = 0 },
		sp = SeasonPass.fresh(0),
		core = { taps = 0, charges = 0 },
		referredBy = 0,
		referralPaid = false,
		referralRewards = 0,
		starterBought = false,
		groupGiftClaimed = false,
		notifAskedAt = 0,
		tutorialDone = false,
		savedAt = os.time(),
		firstJoin = os.time(),
		playTime = 0,
		giftState = { day = 0, played = 0, claimed = {} },
	}
end
Data.defaultProfile = defaultProfile

-- Fill keys added in later versions and drop content that no longer exists in Config.
local function migrate(p: any)
	local v = tonumber(p.version) or 1
	if v < 2 and p.pvpWins == nil then
		p.pvpWins = math.max(0, math.floor(tonumber(p.wins) or 0))
	end
	if v < CURRENT_VERSION then
		p.version = CURRENT_VERSION
	end
end
Data.migrate = migrate

local function reconcile(p: any): Profile
	-- a profile that somehow holds NaN / inf / functions never enters the game as is
	Guard.sanitize(p)
	migrate(p)
	local def = defaultProfile() :: any
	for k, v in def do
		if p[k] == nil or type(p[k]) ~= type(v) then
			p[k] = v
		end
	end
	for k, v in defaultSettings() :: any do
		if type(p.settings[k]) ~= type(v) then
			p.settings[k] = v
		end
	end
	for id in p.owned do
		if not Config.CosmeticById[id] then
			p.owned[id] = nil
		end
	end
	for kind, id in Config.DefaultEquipped do
		local cur = Config.CosmeticById[p.equipped[kind]]
		if not cur or cur.kind ~= kind then
			p.equipped[kind] = id
		end
	end
	local emotes = {}
	for _, id in p.emotes do
		local item = Config.CosmeticById[id]
		if item and item.kind == "emote" and not table.find(emotes, id) and #emotes < Config.EmoteSlotsPack then
			table.insert(emotes, id)
		end
	end
	p.emotes = emotes
	local sp = p.sp
	sp.season = math.floor(tonumber(sp.season) or 0)
	sp.points = math.clamp(math.floor(tonumber(sp.points) or 0), 0, SeasonPass.maxPoints())
	sp.premium = sp.premium == true
	if type(sp.claimed) ~= "table" then
		sp.claimed = {}
	end
	p.level = math.clamp(math.floor(tonumber(p.level) or 1), 1, Config.MaxLevel)
	p.coins = math.max(0, math.floor(tonumber(p.coins) or 0))
	p.trophies = math.max(0, math.floor(tonumber(p.trophies) or 0))
	p.xp = math.max(0, math.floor(tonumber(p.xp) or 0))
	p.wins = math.max(0, math.floor(tonumber(p.wins) or 0))
	p.pvpWins = math.clamp(math.floor(tonumber(p.pvpWins) or 0), 0, p.wins)
	p.matches = math.max(0, math.floor(tonumber(p.matches) or 0))
	return p :: Profile
end
Data.reconcile = reconcile

-- Errors that will not go away by retrying: Studio without "Enable Studio Access to API
-- Services", or an unpublished place. Retrying them only makes the player wait ~12 s.
local function isPermanent(err: any): boolean
	local msg = tostring(err)
	return string.find(msg, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(msg, "403", 1, true) ~= nil
		or string.find(msg, "must publish", 1, true) ~= nil
		or string.find(msg, "not allowed to access", 1, true) ~= nil
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

-- UpdateAsync budget left (assume "plenty" if the engine will not say).
local function budgetLeft(): number
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return if ok and type(n) == "number" then n else 100
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
	local tooNew = false
	for attempt = 1, 6 do
		local lockedByOther = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				local now = os.time()
				if type(old) == "table" and old.lock and old.lock.job ~= game.JobId and now - old.lock.t < LOCK_TTL and attempt < 6 then
					lockedByOther = true
					return nil -- abort write, another server still owns the session
				end
				if type(old) == "table" and (tonumber(old.version) or 1) > CURRENT_VERSION then
					-- written by a newer build: play on a copy, never write an older shape over it
					tooNew = true
					result = reconcile(old)
					return nil
				end
				local p = if type(old) == "table" then reconcile(old) else defaultProfile()
				p.lock = { job = game.JobId, t = now }
				result = p
				return p
			end)
		end)
		if ok and tooNew and result then
			break
		end
		if ok and not lockedByOther and result then
			break
		end
		if not ok then
			warn("[Data] load failed for", player.Name, err)
			if isPermanent(err) then
				-- no DataStore in this session at all: stop trying for everyone
				storeOk = false
				result = nil
				break
			end
		end
		result = nil
		if attempt == 6 then
			break
		end
		-- backoff: a locked session waits for the other server, a failed call for the budget
		task.wait(if lockedByOther then 5 else math.min(2 ^ attempt, 8))
		if not player.Parent then
			break
		end
	end
	if not result or tooNew then
		-- Never overwrite real data with a blank profile: keep this session unsaved.
		warn("[Data] could not load", player.Name, if tooNew then "(newer data version)" else "", "- session will not save")
		result = result or defaultProfile()
		loadedOk[player] = false
	else
		loadedOk[player] = true
	end
	Data.profiles[player] = result
	return result
end

-- One write of the profile. Returns ok, lockLost.
local function writeOnce(player: Player, p: Profile, release: boolean?): (boolean, boolean)
	local ds = store :: DataStore
	local wrote = false
	local lost = false
	local ok, err = pcall(function()
		ds:UpdateAsync(key(player), function(old: any)
			if type(old) == "table" and old.lock and old.lock.job ~= game.JobId and os.time() - old.lock.t < LOCK_TTL then
				lost = true
				return nil -- another server owns it now; don't clobber
			end
			if type(old) == "table" and (tonumber(old.version) or 1) > CURRENT_VERSION then
				lost = true
				return nil -- a newer build saved after we loaded: leave its data alone
			end
			p.savedAt = os.time()
			p.lock = if release then nil else { job = game.JobId, t = os.time() }
			Guard.sanitize(p) -- never persist NaN / inf
			wrote = true
			return p
		end)
	end)
	if not ok then
		warn("[Data] save failed for", player.Name, err)
		if isPermanent(err) then
			storeOk = false
		end
		return false, false
	end
	return wrote, lost
end

-- Saves the profile. `release` also drops the session lock (leaving). Critical saves (leaving,
-- purchases) retry with backoff and wait for budget; autosaves try once and skip when the
-- budget is nearly gone. Returns true when the data reached the DataStore.
function Data.save(player: Player, release: boolean?, critical: boolean?): boolean
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store or not storeOk then
		return false
	end
	-- one save at a time per player (an autosave and a purchase may overlap)
	local waited = 0
	while saving[player] do
		if not critical and not release then
			return false
		end
		task.wait(0.1)
		waited += 0.1
		if waited > 15 or Data.profiles[player] ~= p then
			return false
		end
	end
	saving[player] = true
	local attempts = if critical or release then SAVE_ATTEMPTS else 1
	local saved = false
	for attempt = 1, attempts do
		if not storeOk then
			break
		end
		if attempt == 1 and not critical and not release and budgetLeft() < MIN_AUTOSAVE_BUDGET then
			break
		end
		-- wait (bounded) for budget before a critical write
		local tw = 0
		while (critical or release) and budgetLeft() < 1 and tw < 6 do
			task.wait(0.5)
			tw += 0.5
		end
		local ok, lost = writeOnce(player, p, release)
		if ok then
			saved = true
			break
		end
		if lost then
			-- the session now belongs to another server (or a newer build): stop writing
			loadedOk[player] = false
			warn("[Data] lost the session lock for", player.Name)
			if not release and player.Parent then
				player:Kick("Your data is open on another server. Please rejoin.")
			end
			break
		end
		if attempt < attempts then
			task.wait(math.min(2 ^ attempt, 8))
		end
	end
	saving[player] = nil
	return saved
end

function Data.release(player: Player)
	if Data.profiles[player] == nil then
		return -- already released (PlayerRemoving and BindToClose can both get here)
	end
	Data.save(player, true, true)
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

-- Per-player tables still holding this player (leak check in the playtest).
function Data.tracked(player: Player): number
	return (if Data.profiles[player] then 1 else 0) + (if loadedOk[player] ~= nil then 1 else 0) + (if saving[player] then 1 else 0)
end

function Data.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			-- spread the writes over the interval instead of one burst
			local list = Players:GetPlayers()
			local gap = math.min(1, (Config.AutosaveInterval * 0.5) / math.max(#list, 1))
			for i, player in list do
				task.delay((i - 1) * gap, function()
					if player.Parent and Data.profiles[player] then
						Data.save(player)
					end
				end)
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
				Data.save(player, true, true)
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
