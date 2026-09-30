--!strict
-- Player profiles: DataStore load/save with a soft session lock, autosave and BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Data = {}

export type Profile = {
	version: number,
	cash: number,
	totalEarned: number,
	rebirths: number,
	tilesOwned: number,
	upgrades: { [string]: number },
	seeds: { [string]: number },
	backpack: { [string]: number }, -- "seedId|mutation" -> count
	tiles: { [string]: { seed: string, progress: number, mut: string?, rg: boolean? } }, -- key = tostring(tileIndex)
	purchases: { string }, -- recent processed receipt ids
	daily: { lastClaim: number, streak: number },
	codes: { [string]: boolean },
	tutorialDone: boolean,
	lang: string, -- chosen UI language ("" = auto from the device locale)
	index: { [string]: { [string]: boolean } }, -- seedId -> variant ("Normal" or mutation id) -> found
	indexClaimed: { [string]: boolean },
	referredBy: number, -- inviter UserId (0 = none)
	referralPaid: boolean, -- inviter already credited for this player
	referralRewards: number, -- rewards received as an inviter (capped)
	starterBought: boolean,
	groupGiftClaimed: boolean,
	notifAskedAt: number,
	ads: { day: number, count: number },
	auto: { harvest: boolean, plant: boolean, sell: boolean, seed: string }, -- auto-farm switches + seed to replant
	wild: { cycle: number, claimed: { [string]: boolean } }, -- Wild Patch nodes picked in that hourly cycle
	trophies: { { seed: string, mut: string?, size: string? } }, -- crops on the plot's pedestals (luck)
	savedAt: number,
	firstJoin: number,
	playTime: number,
	lock: { job: string, t: number }?,
}

local store: DataStore? = nil
local storeOk = false
if game.PlaceId == 0 then
	warn("[Data] unpublished place: running without DataStores")
else
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

local function defaultProfile(): Profile
	local seeds: { [string]: number } = {}
	for id, n in Config.StartingSeeds :: { [string]: number } do
		seeds[id] = n
	end
	local upgrades: { [string]: number } = {}
	for _, u in Config.Upgrades do
		upgrades[u.id] = 0
	end
	return {
		version = 1,
		cash = Config.StartingCash,
		totalEarned = 0,
		rebirths = 0,
		tilesOwned = Config.StartingTiles,
		upgrades = upgrades,
		seeds = seeds,
		backpack = {},
		tiles = {},
		purchases = {},
		daily = { lastClaim = 0, streak = 0 },
		codes = {},
		tutorialDone = false,
		lang = "",
		index = {},
		indexClaimed = {},
		referredBy = 0,
		referralPaid = false,
		referralRewards = 0,
		starterBought = false,
		groupGiftClaimed = false,
		notifAskedAt = 0,
		ads = { day = 0, count = 0 },
		auto = { harvest = true, plant = false, sell = false, seed = "" },
		wild = { cycle = 0, claimed = {} },
		trophies = {},
		savedAt = os.time(),
		firstJoin = os.time(),
		playTime = 0,
	}
end
Data.defaultProfile = defaultProfile

-- Fill any keys added in later versions.
local function reconcile(p: any): Profile
	local def = defaultProfile() :: any
	for k, v in def do
		if p[k] == nil then
			p[k] = v
		end
	end
	for _, u in Config.Upgrades do
		if p.upgrades[u.id] == nil then
			p.upgrades[u.id] = 0
		end
	end
	-- drop seeds/tiles that no longer exist in Config
	for id in p.seeds do
		if not Config.SeedById[id] then
			p.seeds[id] = nil
		end
	end
	for k, t in p.tiles do
		if not Config.SeedById[t.seed] then
			p.tiles[k] = nil
		end
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
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player), function(old: any)
				local now = os.time()
				if old and old.lock and old.lock.job ~= game.JobId and now - old.lock.t < LOCK_TTL and attempt < 6 then
					lockedByOther = true
					return nil -- abort write
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

-- One write at a time per player: a purchase receipt, the autosave and the leave-save can all ask at once, and
-- parallel UpdateAsync calls on the same key only queue up and burn the request budget.
local saving: { [Player]: boolean } = {}
Data.saves = 0 -- writes attempted (for the tests)

function Data.save(player: Player, release: boolean?)
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store then
		return
	end
	while saving[player] do
		task.wait(0.1)
	end
	saving[player] = true
	Data.saves += 1
	local ds = store :: DataStore
	p.savedAt = os.time()
	p.lock = if release then nil else { job = game.JobId, t = os.time() }
	local ok, err = pcall(function()
		ds:UpdateAsync(key(player), function(old: any)
			if old and old.lock and old.lock.job ~= game.JobId and os.time() - old.lock.t < LOCK_TTL then
				return nil -- another server owns it now; don't clobber
			end
			return p
		end)
	end)
	saving[player] = nil
	if not ok then
		warn("[Data] save failed for", player.Name, err)
	end
end

function Data.release(player: Player)
	Data.save(player, true)
	Data.profiles[player] = nil
	loadedOk[player] = nil
	saving[player] = nil
end

-- Seconds between two players' autosaves: everyone is saved once per interval, spread evenly instead of all
-- in the same second (pure: unit-tested in the playtest).
function Data.autosaveGap(interval: number, playerCount: number): number
	return interval / math.max(playerCount, 1)
end

function Data.isPersistent(player: Player): boolean
	return loadedOk[player] == true
end

function Data.startAutosave()
	task.spawn(function()
		while true do
			local players = Players:GetPlayers()
			if #players == 0 then
				task.wait(Config.AutosaveInterval)
			end
			local gap = Data.autosaveGap(Config.AutosaveInterval, #players)
			for _, player in players do
				task.wait(gap)
				if player.Parent then
					task.spawn(Data.save, player)
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
