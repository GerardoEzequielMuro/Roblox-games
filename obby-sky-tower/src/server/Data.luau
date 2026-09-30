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

local Data = {}

export type Profile = {
	version: number,
	stage: number, -- saved checkpoint, 0..1000 (0 = lobby start)
	best: number, -- highest stage ever reached
	base: boolean, -- on a summit (stage 100, 200...): already took the portal to the next tower
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
local LOCK_TTL = 150

local function defaultProfile(): Profile
	return {
		version = 2,
		stage = 0,
		best = 0,
		base = false,
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

function Data.save(player: Player, release: boolean?)
	local p = Data.profiles[player]
	if not p or not loadedOk[player] or not store then
		return
	end
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
	if not ok then
		warn("[Data] save failed for", player.Name, err)
	end
end

function Data.release(player: Player)
	Data.save(player, true)
	Data.profiles[player] = nil
	loadedOk[player] = nil
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
