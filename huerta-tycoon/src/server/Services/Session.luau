--!strict
-- Runtime per-player session: multipliers, cash, basket and the state snapshot sent to the client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local CropIndex = require(ReplicatedStorage.Shared.CropIndex)
local AutoFarmRules = require(ReplicatedStorage.Shared.AutoFarm)
local Wild = require(ReplicatedStorage.Shared.Wild)
local TrophyRules = require(ReplicatedStorage.Shared.Trophies)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)

local Session = {}

export type S = {
	player: Player,
	profile: Data.Profile,
	plotIndex: number,
	stock: { [string]: number },
	passes: { [string]: boolean },
	premium: boolean,
	inGroup: boolean,
	friendsInServer: number,
	earnLog: { { t: number, amount: number } },
	bestRate: number, -- best $/min observed (for cash packs)
	dirty: boolean,
	joinedAt: number,
	leaderstats: Folder?,
	autoLang: string?, -- language the client auto-detected (Hello payload)
	sessionStart: number, -- play-time gifts count from here (not saved)
	giftsClaimed: { [number]: boolean },
	boosts: { [string]: { mult: number, endsAt: number } }, -- "growth" | "cash" timed boosts (not saved)
	autoAt: number, -- os.clock() of the last auto-farm round (not saved)
	paidRandomAllowed: boolean, -- PolicyService: false where paid random items are restricted (and until we know)
	rev: number, -- snapshot counter: the client ignores a snapshot older than the one it already has
}

Session.sessions = {} :: { [Player]: S }

function Session.get(player: Player): S?
	return Session.sessions[player]
end

function Session.create(player: Player, profile: Data.Profile): S
	local passes = {}
	for _, pass in Config.GamePasses do
		passes[pass.key] = false
	end
	local s: S = {
		player = player,
		profile = profile,
		plotIndex = 0,
		stock = {},
		passes = passes,
		premium = player.MembershipType == Enum.MembershipType.Premium,
		inGroup = false,
		friendsInServer = 0,
		earnLog = {},
		bestRate = 0,
		dirty = true,
		joinedAt = os.time(),
		leaderstats = nil,
		autoLang = nil,
		sessionStart = os.time(),
		giftsClaimed = {},
		boosts = {},
		autoAt = 0,
		paidRandomAllowed = false,
		rev = 0,
	}
	Session.sessions[player] = s

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = ls
	local reb = Instance.new("IntValue")
	reb.Name = "Rebirths"
	reb.Parent = ls
	ls.Parent = player
	s.leaderstats = ls
	return s
end

-- Effective UI language: saved choice > client-detected > Player.LocaleId.
function Session.lang(s: S): string
	local p = s.profile.lang
	if type(p) == "string" and Locale.Supported[p] then
		return p
	end
	if s.autoLang and Locale.Supported[s.autoLang] then
		return s.autoLang
	end
	local ok, id = pcall(function()
		return s.player.LocaleId
	end)
	return Locale.resolve(if ok then id else nil)
end

local defaultLangOf = Remotes.langOf
Remotes.langOf = function(player: Player): string
	local s = Session.sessions[player]
	return if s then Session.lang(s) else defaultLangOf(player)
end

function Session.remove(player: Player)
	Session.sessions[player] = nil
end

-- ===== timed boosts =====
function Session.boostMult(s: S, kind: string): number
	local b = s.boosts[kind]
	if b and b.endsAt > os.time() then
		return b.mult
	end
	return 1
end

-- Adds a timed boost; stacking the same kind extends the time (keeps the higher multiplier).
function Session.addBoost(s: S, kind: string, mult: number, seconds: number)
	local now = os.time()
	local b = s.boosts[kind]
	if b and b.endsAt > now then
		b.endsAt += seconds
		b.mult = math.max(b.mult, mult)
	else
		s.boosts[kind] = { mult = mult, endsAt = now + seconds }
	end
	s.dirty = true
end

-- ===== Index =====
local MUTATION_IDS: { string } = {}
for _, m in Config.Mutations do
	table.insert(MUTATION_IDS, m.id)
end
Session.MUTATION_IDS = MUTATION_IDS

function Session.indexBonus(s: S): number
	local claimed = 0
	for _, seed in Config.Seeds do
		if s.profile.indexClaimed[seed.id] then
			claimed += 1
		end
	end
	return CropIndex.bonus(claimed, #Config.Seeds, Config.IndexRowBonus, Config.IndexAllBonus)
end

-- ===== multipliers =====
function Session.cashMult(s: S): number
	local p = s.profile
	local m = 1 + p.rebirths * Config.RebirthBonus + Session.indexBonus(s)
	m *= 1 + p.upgrades.CropValue * Config.UpgradeById.CropValue.perLevel
	if s.passes.DoubleCash then
		m *= Config.PassBonuses.DoubleCashMult
	end
	if s.passes.VIP then
		m *= Config.PassBonuses.VipCash
	end
	if s.premium then
		m *= Config.PremiumCashMult
	end
	if s.inGroup then
		m *= Config.GroupCashMult
	end
	m *= 1 + math.min(Config.FriendBonusMax, s.friendsInServer * Config.FriendBonusPerFriend)
	m *= Session.boostMult(s, "cash")
	return m
end

-- Growth multiplier without weather (weather is applied by Garden's tick).
function Session.growthMult(s: S): number
	local m = 1 + s.profile.upgrades.GrowSpeed * Config.UpgradeById.GrowSpeed.perLevel
	if s.passes.VIP then
		m *= Config.PassBonuses.VipGrowth
	end
	if s.passes.DoubleGrow then
		m *= Config.PassBonuses.DoubleGrowMult
	end
	m *= Session.boostMult(s, "growth")
	return m
end

-- Luck from the crops on the plot's pedestals (0.15 = +15%).
function Session.trophyLuck(s: S): number
	return TrophyRules.totalLuck(s.profile.trophies or {}, function(id: string): number?
		local m = Config.MutationById[id]
		return if m then m.multiplier else nil
	end)
end

function Session.luckMult(s: S): number
	local m = (1 + s.profile.upgrades.Luck * Config.UpgradeById.Luck.perLevel) * (1 + Session.trophyLuck(s))
	if s.passes.SuperLuck then
		m *= Config.PassBonuses.SuperLuckMult
	end
	return m
end

function Session.backpackCap(s: S): number
	return Formulas.backpackCap(s.profile.upgrades.Backpack, s.passes.BigBasket == true)
end

function Session.backpackCount(s: S): number
	local n = 0
	for _, c in s.profile.backpack do
		n += c
	end
	return n
end

function Session.itemValue(s: S, seedId: string, mutation: string?, size: string?): number
	local seed = Config.SeedById[seedId]
	if not seed then
		return 0
	end
	local v = seed.sellValue * TrophyRules.valueMult(size)
	if mutation and Config.MutationById[mutation] then
		v *= Config.MutationById[mutation].multiplier
	end
	return math.floor(v * Session.cashMult(s))
end

-- Basket keys are "seed|mutation" or "seed|mutation|size" (Shared/Trophies).
function Session.splitKey(k: string): (string, string?, string?)
	return TrophyRules.split(k)
end

function Session.basketKey(seedId: string, mutation: string?, size: string?): string
	return TrophyRules.key(seedId, mutation, size)
end

function Session.backpackValue(s: S): number
	local total = 0
	for k, c in s.profile.backpack do
		local seedId, mut, size = Session.splitKey(k)
		total += Session.itemValue(s, seedId, mut, size) * c
	end
	return total
end

-- ===== cash =====
function Session.addCash(s: S, amount: number, fromSale: boolean?)
	if amount ~= amount or amount == math.huge or amount == -math.huge then
		return -- never let NaN/inf reach the profile (it would poison every later comparison and the save)
	end
	amount = math.floor(amount)
	s.profile.cash += amount
	if amount > 0 then
		s.profile.totalEarned += amount
		if fromSale then
			local now = os.time()
			table.insert(s.earnLog, { t = now, amount = amount })
			while #s.earnLog > 0 and now - s.earnLog[1].t > 300 do
				table.remove(s.earnLog, 1)
			end
			local sum = 0
			for _, e in s.earnLog do
				sum += e.amount
			end
			local minutes = math.max(1, math.min(5, (now - s.joinedAt) / 60))
			s.bestRate = math.max(s.bestRate, sum / minutes)
		end
	end
	Session.markDirty(s)
end

function Session.trySpend(s: S, amount: number): boolean
	-- reject NaN/inf/negative amounts: `cash < NaN` is false, which used to turn a purchase into free cash NaN
	if amount ~= amount or amount < 0 or amount == math.huge or s.profile.cash < amount then
		return false
	end
	s.profile.cash -= amount
	Session.markDirty(s)
	return true
end

function Session.earnRate(s: S): number
	local now = os.time()
	local sum = 0
	for _, e in s.earnLog do
		if now - e.t <= 300 then
			sum += e.amount
		end
	end
	local minutes = math.max(1, math.min(5, (now - s.joinedAt) / 60))
	return math.floor(sum / minutes)
end

function Session.markDirty(s: S)
	s.dirty = true
end

-- Auto-farm status: what is unlocked, what the player switched on, what actually runs and at which pace.
export type AutoInfo = {
	level: number,
	pass: boolean,
	allowed: AutoFarmRules.Toggles,
	wanted: AutoFarmRules.Toggles,
	on: AutoFarmRules.Toggles,
	seed: string,
	interval: number,
	batch: number,
}
function Session.autoInfo(s: S): AutoInfo
	local rules = Config.AutoFarm
	local level = s.profile.upgrades[rules.upgradeId] or 0
	local pass = s.passes[rules.passKey] == true
	local saved = AutoFarmRules.sanitize(s.profile.auto)
	local wanted = { harvest = saved.harvest, plant = saved.plant, sell = saved.sell }
	return {
		level = level,
		pass = pass,
		allowed = AutoFarmRules.allowed(rules, level, pass),
		wanted = wanted,
		on = AutoFarmRules.effective(rules, wanted, level, pass),
		seed = saved.seed,
		interval = AutoFarmRules.interval(rules, level, pass),
		batch = AutoFarmRules.batch(rules, level, pass),
	}
end

-- ===== snapshot =====
function Session.dailyInfo(s: S): { streak: number, canClaim: boolean, nextAt: number }
	local d = s.profile.daily
	local now = os.time()
	local nextAt = d.lastClaim + Config.DailyCooldown
	local streak = d.streak
	if now - d.lastClaim > Config.DailyStreakWindow then
		streak = 0
	end
	return { streak = streak, canClaim = now >= nextAt, nextAt = nextAt }
end

local function productId(key: string): number
	for _, prod in Config.DevProducts do
		if prod.key == key then
			return prod.id
		end
	end
	return 0
end

function Session.starterInfo(s: S): { available: boolean, endsAt: number }
	local endsAt = s.profile.firstJoin + Config.StarterPackWindow
	local available = productId("StarterPack") ~= 0 and not s.profile.starterBought and os.time() < endsAt
	return { available = available, endsAt = endsAt }
end

function Session.adsLeft(s: S): number
	local a = s.profile.ads
	local today = os.time() // 86400
	local used = if a.day == today then a.count else 0
	return math.max(0, Config.AdDailyCap - used)
end

function Session.buildState(s: S): { [string]: any }
	local p = s.profile
	local now = os.time()
	local gifts = Gifts.ready(Config.PlaytimeGifts, s.sessionStart, now, s.giftsClaimed)
	local index = {}
	for _, seed in Config.Seeds do
		local found, total = CropIndex.count(p.index[seed.id], MUTATION_IDS)
		local variants = {}
		local row = p.index[seed.id]
		if row then
			for v in pairs(row) do
				table.insert(variants, v)
			end
		end
		index[seed.id] = { found = found, total = total, claimed = p.indexClaimed[seed.id] == true, variants = variants }
	end
	local boosts = {}
	for kind, b in s.boosts do
		if b.endsAt > now then
			boosts[kind] = { mult = b.mult, endsAt = b.endsAt }
		end
	end
	local upgradeCosts = {}
	for _, u in Config.Upgrades do
		local lvl = p.upgrades[u.id] or 0
		upgradeCosts[u.id] = if lvl < u.maxLevel then Formulas.upgradeCost(u.id, lvl) else nil
	end
	local backpack = {}
	for k, c in p.backpack do
		if c > 0 then
			local seedId, mut, size = Session.splitKey(k)
			table.insert(backpack, { key = k, seedId = seedId, mutation = mut, size = size, count = c, value = Session.itemValue(s, seedId, mut, size) * c })
		end
	end
	table.sort(backpack, function(a, b)
		return a.value > b.value
	end)
	s.rev += 1
	local trophies = {}
	for i, item in (p.trophies or {}) :: { any } do
		trophies[i] = { seedId = item.seed, mutation = item.mut, size = item.size }
	end
	local wildCycle = Wild.cycle(now)
	local wildClaimed = {}
	for i = 1, Wild.NODES do
		if not Wild.canClaim(p.wild, wildCycle, i) then
			table.insert(wildClaimed, i)
		end
	end
	return {
		rev = s.rev,
		trophies = trophies,
		trophyLuck = Session.trophyLuck(s),
		wild = { nextAt = Wild.nextAt(now), left = Wild.left(p.wild, wildCycle), claimed = wildClaimed },
		cash = p.cash,
		totalEarned = p.totalEarned,
		rebirths = p.rebirths,
		tilesOwned = p.tilesOwned,
		tileCost = if p.tilesOwned < Config.MaxTiles then Formulas.tileCost(p.tilesOwned) else nil,
		upgrades = p.upgrades,
		upgradeCosts = upgradeCosts,
		seeds = p.seeds,
		backpack = backpack,
		backpackCount = Session.backpackCount(s),
		backpackCap = Session.backpackCap(s),
		backpackValue = Session.backpackValue(s),
		passes = s.passes,
		mult = { cash = Session.cashMult(s), growth = Session.growthMult(s), luck = Session.luckMult(s) },
		rebirthCost = Formulas.rebirthCost(p.rebirths),
		daily = Session.dailyInfo(s),
		plotIndex = s.plotIndex,
		tutorialDone = p.tutorialDone,
		lang = Session.lang(s),
		sessionStart = s.sessionStart,
		gifts = gifts,
		boosts = boosts,
		index = index,
		indexBonus = Session.indexBonus(s),
		starter = Session.starterInfo(s),
		groupGift = { available = Config.GroupId ~= 0 and not p.groupGiftClaimed, member = s.inGroup },
		adsLeft = Session.adsLeft(s),
		auto = Session.autoInfo(s),
		policy = { paidRandom = s.paidRandomAllowed },
		referralRewards = p.referralRewards,
		earnRate = Session.earnRate(s),
		friends = s.friendsInServer,
		saving = Data.isPersistent(s.player),
	}
end

local function push(s: S)
	s.dirty = false
	local ls = s.leaderstats
	if ls then
		(ls:FindFirstChild("Cash") :: StringValue).Value = require(ReplicatedStorage.Shared.Format).cash(s.profile.cash);
		(ls:FindFirstChild("Rebirths") :: IntValue).Value = s.profile.rebirths
	end
	Remotes.fire("StateUpdate", s.player, Session.buildState(s))
end

function Session.pushNow(s: S)
	push(s)
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then
		return
	end
	acc = 0
	local now = os.time()
	for player, s in Session.sessions do
		-- expired boosts change the multipliers: drop them and resend
		for kind, b in s.boosts do
			if b.endsAt <= now then
				s.boosts[kind] = nil
				s.dirty = true
			end
		end
		if s.dirty and player.Parent then
			push(s)
		end
	end
end)

-- friends boost refresh
local function refreshFriends()
	local list = Players:GetPlayers()
	for _, a in list do
		local s = Session.sessions[a]
		if s then
			local n = 0
			for _, b in list do
				if a ~= b then
					local ok, isFriend = pcall(a.IsFriendsWith, a, b.UserId)
					if ok and isFriend then
						n += 1
					end
				end
			end
			if s.friendsInServer ~= n then
				s.friendsInServer = n
				Session.markDirty(s)
			end
		end
	end
end
Session.refreshFriends = refreshFriends

return Session
