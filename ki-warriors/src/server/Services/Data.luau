--!strict
-- Player profiles: DataStore load/save with a soft session lock, reconcile, autosave
-- and BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Data = {}

export type Profile = {
	version: number,
	stats: { [string]: number },
	sparks: number,
	gems: number,
	bestPower: number,
	rebirths: number,
	planet: number, -- where the player is
	planets: { number }, -- unlocked planet indexes
	gear: number, -- tier index into Config.Gear
	techniques: { [string]: boolean },
	forms: number, -- highest form unlocked (kept through rebirths)
	auras: { [string]: number }, -- owned aura id -> copies
	auraEquipped: string, -- "" = none
	spins: number, -- free aura spins banked
	freeSpinDay: number,
	race: string,
	raceChanges: number,
	upgrades: { [string]: number },
	story: { step: number, progress: number },
	quests: { day: number, list: { any }, progress: { number }, claimed: { boolean }, bonusClaimed: boolean },
	daily: { last: number, streak: number },
	codes: { [string]: boolean },
	purchases: { string },
	boostLeft: number, -- seconds of x2 training (ticks while online)
	settings: { [string]: any },
	lang: string,
	offlinePending: { [string]: number }?, -- stat -> points waiting to be claimed
	offlineSeconds: number,
	referredBy: number,
	referralPaid: boolean,
	referralRewards: number,
	starterBought: boolean,
	ads: { day: number, count: number },
	notifAskedAt: number,
	groupGiftClaimed: boolean,
	relics: { found: { [string]: boolean }, seed: number, nextAt: number },
	wishes: number,
	wishPower: number,
	pvp: { rating: number, kills: number, deaths: number },
	protectionOff: boolean,
	kills: number,
	bossKills: { [string]: number },
	totalReps: number,
	items: { [string]: number }, -- seeds in the bag
	market: { hour: number, bought: { [string]: number } }, -- seeds bought with Sparks this hour
	buffs: { titan: number, spark: number, vigorReadyAt: number }, -- os.time() deadlines
	skins: { [string]: boolean },
	skin: string, -- equipped skin ("" = none)
	mounts: { [string]: boolean },
	mount: string,
	bp: { [string]: { xp: number, premium: boolean, free: { [string]: boolean }, paid: { [string]: boolean } } },
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

local function defaultSettings(): { [string]: any }
	return { stat = "strength", autoTrain = false, autoCharge = false, autoFight = false, music = true, sfx = true, lite = false, shake = true }
end

local function defaultProfile(): Profile
	local stats = {}
	for _, s in Config.Stats do
		stats[s] = Config.StartStat
	end
	local upgrades = {}
	for _, u in Config.Upgrades do
		upgrades[u.id] = 0
	end
	local p: Profile = {
		version = 1,
		stats = stats,
		sparks = 0,
		gems = 0,
		bestPower = 0,
		rebirths = 0,
		planet = 1,
		planets = { 1 },
		gear = 1,
		techniques = {},
		forms = 0,
		auras = {},
		auraEquipped = "",
		spins = 1,
		freeSpinDay = 0,
		race = "terran",
		raceChanges = 0,
		upgrades = upgrades,
		story = { step = 1, progress = 0 },
		quests = { day = -1, list = {}, progress = {}, claimed = {}, bonusClaimed = false },
		daily = { last = 0, streak = 0 },
		codes = {},
		purchases = {},
		boostLeft = 0,
		settings = defaultSettings(),
		lang = "",
		offlinePending = nil,
		offlineSeconds = 0,
		referredBy = 0,
		referralPaid = false,
		referralRewards = 0,
		starterBought = false,
		ads = { day = 0, count = 0 },
		notifAskedAt = 0,
		groupGiftClaimed = false,
		relics = { found = {}, seed = 0, nextAt = 0 },
		wishes = 0,
		wishPower = 0,
		pvp = { rating = Config.Pvp.startRating, kills = 0, deaths = 0 },
		protectionOff = false,
		kills = 0,
		bossKills = {},
		totalReps = 0,
		items = {},
		market = { hour = 0, bought = {} },
		buffs = { titan = 0, spark = 0, vigorReadyAt = 0 },
		skins = {},
		skin = "",
		mounts = {},
		mount = "",
		bp = {},
		savedAt = os.time(),
		firstJoin = os.time(),
		playTime = 0,
	}
	return p
end
Data.defaultProfile = defaultProfile

local function num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

-- Fill keys added in later versions and drop content that no longer exists in Config.
local function reconcile(p: any): Profile
	local def = defaultProfile() :: any
	for k, v in def do
		if p[k] == nil then
			p[k] = v
		end
	end
	if type(p.stats) ~= "table" then
		p.stats = def.stats
	end
	for _, s in Config.Stats do
		p.stats[s] = math.max(Config.StartStat, num(p.stats[s], Config.StartStat))
	end
	for _, u in Config.Upgrades do
		p.upgrades[u.id] = math.clamp(math.floor(num(p.upgrades[u.id], 0)), 0, u.max)
	end
	if type(p.settings) ~= "table" then
		p.settings = defaultSettings()
	end
	for k, v in defaultSettings() do
		if p.settings[k] == nil then
			p.settings[k] = v
		end
	end
	if not table.find(Config.Stats, p.settings.stat) then
		p.settings.stat = "strength"
	end
	p.gear = math.clamp(math.floor(num(p.gear, 1)), 1, #Config.Gear)
	p.forms = math.clamp(math.floor(num(p.forms, 0)), 0, #Config.Forms)
	p.planet = math.clamp(math.floor(num(p.planet, 1)), 1, #Config.Planets)
	if type(p.planets) ~= "table" or #p.planets == 0 then
		p.planets = { 1 }
	end
	if not table.find(p.planets, p.planet) then
		p.planet = 1
	end
	if not Config.RaceById[p.race] then
		p.race = "terran"
	end
	for id in p.auras do
		if not Config.AuraById[id] then
			p.auras[id] = nil
		end
	end
	if p.auraEquipped ~= "" and not p.auras[p.auraEquipped] then
		p.auraEquipped = ""
	end
	for id in p.techniques do
		if not Config.TechniqueById[id] then
			p.techniques[id] = nil
		end
	end
	p.story.step = math.clamp(math.floor(num(p.story.step, 1)), 1, #Config.Story + 1)
	p.sparks = math.max(0, num(p.sparks, 0))
	p.gems = math.max(0, math.floor(num(p.gems, 0)))
	if type(p.pvp) ~= "table" then
		p.pvp = def.pvp
	end
	if type(p.relics) ~= "table" or type(p.relics.found) ~= "table" then
		p.relics = def.relics
	end
	-- seeds, cosmetics and battle pass
	if type(p.items) ~= "table" then
		p.items = {}
	end
	for id in p.items do
		if not Config.SeedById[id] then
			p.items[id] = nil
		else
			p.items[id] = math.max(0, math.floor(num(p.items[id], 0)))
		end
	end
	if type(p.market) ~= "table" or type(p.market.bought) ~= "table" then
		p.market = def.market
	end
	p.market.hour = num(p.market.hour, 0)
	if type(p.buffs) ~= "table" then
		p.buffs = def.buffs
	end
	for _, k in { "titan", "spark", "vigorReadyAt" } do
		p.buffs[k] = num(p.buffs[k], 0)
	end
	local function cleanCosmetics(owned: string, equipped: string, known: { [string]: any })
		if type(p[owned]) ~= "table" then
			p[owned] = {}
		end
		for id in p[owned] do
			if not known[id] then
				p[owned][id] = nil
			end
		end
		if type(p[equipped]) ~= "string" or (p[equipped] ~= "" and not p[owned][p[equipped]]) then
			p[equipped] = ""
		end
	end
	cleanCosmetics("skins", "skin", Config.SkinById)
	cleanCosmetics("mounts", "mount", Config.MountById)
	if type(p.bp) ~= "table" then
		p.bp = {}
	end
	for id, rec in p.bp do
		if not Config.BattlePass.SeasonById[id] or type(rec) ~= "table" then
			p.bp[id] = nil
		else
			rec.xp = math.clamp(math.floor(num(rec.xp, 0)), 0, Config.BattlePass.xpPerTier * Config.BattlePass.tiers)
			rec.premium = rec.premium == true
			rec.free = if type(rec.free) == "table" then rec.free else {}
			rec.paid = if type(rec.paid) == "table" then rec.paid else {}
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
