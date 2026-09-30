--!strict
-- Player profiles: DataStore load/save with a soft session lock, reconcile, autosave
-- and BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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

local function defaultSettings(): Settings
	return { music = 0.5, sfx = 0.8, shake = true, flashes = true, lite = false, autoQueue = false, autoPlay = false, autoCharge = false }
end

local function defaultProfile(): Profile
	return {
		version = 1,
		coins = 0,
		xp = 0,
		level = 1,
		trophies = 0,
		bestTrophies = 0,
		season = 0,
		wins = 0,
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
	}
end
Data.defaultProfile = defaultProfile

-- Fill keys added in later versions and drop content that no longer exists in Config.
local function reconcile(p: any): Profile
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
	p.level = math.clamp(math.floor(tonumber(p.level) or 1), 1, Config.MaxLevel)
	p.coins = math.max(0, math.floor(tonumber(p.coins) or 0))
	p.trophies = math.max(0, math.floor(tonumber(p.trophies) or 0))
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
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				local now = os.time()
				if old and old.lock and old.lock.job ~= game.JobId and now - old.lock.t < LOCK_TTL and attempt < 6 then
					lockedByOther = true
					return nil -- abort write, another server still owns the session
				end
				local p = if old then reconcile(old) else defaultProfile()
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

function Data.save(player: Player, release: boolean?): boolean
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store then
		return false
	end
	local ds = store :: DataStore
	p.savedAt = os.time()
	p.lock = if release then nil else { job = game.JobId, t = os.time() }
	local wrote = false
	local ok, err = pcall(function()
		ds:UpdateAsync(key(player), function(old: any)
			if old and old.lock and old.lock.job ~= game.JobId and os.time() - old.lock.t < LOCK_TTL then
				return nil -- another server owns it now; don't clobber
			end
			wrote = true
			return p
		end)
	end)
	if not ok then
		warn("[Data] save failed for", player.Name, err)
		return false
	end
	return wrote
end

function Data.release(player: Player)
	Data.save(player, true)
	Data.profiles[player] = nil
	loadedOk[player] = nil
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
