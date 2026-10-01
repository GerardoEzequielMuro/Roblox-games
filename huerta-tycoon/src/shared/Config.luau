--!strict
-- Crop Kingdom: every tunable number lives here.

-- Color3 only exists inside Roblox; tests/pricing_test.luau loads this file with plain Luau, where the stub is used.
local Color3: typeof(Color3) = Color3 or ({ fromRGB = function() return nil end } :: any)

local Config = {}

Config.GameName = "Crop Kingdom"
Config.DataStoreName = "CropKingdom_v1"
Config.LeaderboardStoreName = "CropKingdom_TotalEarned_v1"

Config.StartingCash = 25
Config.StartingSeeds = { carrot = 3 } :: { [string]: number }
Config.StartingTiles = 6
Config.MaxTiles = 30
Config.TileBaseCost = 80
Config.TileCostGrowth = 1.9

Config.BackpackBase = 25
Config.SellRadius = 22
Config.RestockInterval = 300 -- seconds
Config.AutosaveInterval = 90

-- Rarity -> display color
Config.Rarities = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(90, 200, 90),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 80, 120),
	Divine = Color3.fromRGB(80, 255, 230),
}

export type Seed = {
	id: string,
	name: string,
	rarity: string,
	price: number,
	growTime: number, -- seconds at 1x speed
	sellValue: number,
	regrowTime: number?, -- if set, plant stays after harvest and regrows
	stockChance: number, -- chance to appear on each restock
	stockMin: number,
	stockMax: number,
	fruitColor: Color3,
	stemColor: Color3,
	shape: string, -- "Ball" | "Long" | "Tree" | "Flower"
	fruitSize: number,
}

Config.Seeds = {
	{ id = "carrot", name = "Carrot", rarity = "Common", price = 10, growTime = 10, sellValue = 15, stockChance = 1, stockMin = 20, stockMax = 40, fruitColor = Color3.fromRGB(255, 130, 30), stemColor = Color3.fromRGB(60, 170, 60), shape = "Long", fruitSize = 1.2 },
	{ id = "tomato", name = "Tomato", rarity = "Common", price = 40, growTime = 30, sellValue = 55, stockChance = 1, stockMin = 10, stockMax = 20, fruitColor = Color3.fromRGB(230, 40, 40), stemColor = Color3.fromRGB(50, 150, 50), shape = "Ball", fruitSize = 1.4 },
	{ id = "corn", name = "Corn", rarity = "Uncommon", price = 150, growTime = 75, sellValue = 210, stockChance = 0.85, stockMin = 4, stockMax = 10, fruitColor = Color3.fromRGB(255, 220, 60), stemColor = Color3.fromRGB(90, 180, 70), shape = "Long", fruitSize = 1.6 },
	{ id = "blueberry", name = "Blueberry Bush", rarity = "Uncommon", price = 400, growTime = 90, sellValue = 170, regrowTime = 55, stockChance = 0.7, stockMin = 3, stockMax = 8, fruitColor = Color3.fromRGB(70, 90, 230), stemColor = Color3.fromRGB(40, 120, 60), shape = "Ball", fruitSize = 1.0 },
	{ id = "pumpkin", name = "Pumpkin", rarity = "Rare", price = 1200, growTime = 150, sellValue = 1900, stockChance = 0.7, stockMin = 2, stockMax = 6, fruitColor = Color3.fromRGB(255, 140, 20), stemColor = Color3.fromRGB(60, 140, 40), shape = "Ball", fruitSize = 2.4 },
	{ id = "watermelon", name = "Watermelon", rarity = "Rare", price = 3500, growTime = 240, sellValue = 5200, stockChance = 0.6, stockMin = 2, stockMax = 5, fruitColor = Color3.fromRGB(40, 150, 60), stemColor = Color3.fromRGB(70, 160, 60), shape = "Ball", fruitSize = 2.6 },
	{ id = "apple", name = "Apple Tree", rarity = "Epic", price = 10000, growTime = 300, sellValue = 2600, regrowTime = 110, stockChance = 0.55, stockMin = 1, stockMax = 3, fruitColor = Color3.fromRGB(220, 30, 50), stemColor = Color3.fromRGB(110, 70, 40), shape = "Tree", fruitSize = 0.9 },
	{ id = "dragonfruit", name = "Dragon Fruit", rarity = "Epic", price = 30000, growTime = 420, sellValue = 46000, stockChance = 0.42, stockMin = 1, stockMax = 3, fruitColor = Color3.fromRGB(255, 60, 170), stemColor = Color3.fromRGB(60, 160, 90), shape = "Ball", fruitSize = 1.9 },
	{ id = "mango", name = "Mango Tree", rarity = "Legendary", price = 100000, growTime = 600, sellValue = 26000, regrowTime = 220, stockChance = 0.36, stockMin = 1, stockMax = 2, fruitColor = Color3.fromRGB(255, 170, 40), stemColor = Color3.fromRGB(100, 65, 35), shape = "Tree", fruitSize = 1.1 },
	{ id = "starfruit", name = "Starfruit", rarity = "Legendary", price = 300000, growTime = 900, sellValue = 500000, stockChance = 0.3, stockMin = 1, stockMax = 2, fruitColor = Color3.fromRGB(255, 240, 90), stemColor = Color3.fromRGB(70, 170, 80), shape = "Flower", fruitSize = 1.8 },
	{ id = "moonmelon", name = "Moon Melon", rarity = "Mythic", price = 1200000, growTime = 1200, sellValue = 2100000, stockChance = 0.04, stockMin = 1, stockMax = 1, fruitColor = Color3.fromRGB(180, 200, 255), stemColor = Color3.fromRGB(90, 90, 160), shape = "Ball", fruitSize = 2.8 },
	{ id = "cosmiclotus", name = "Cosmic Lotus", rarity = "Divine", price = 5000000, growTime = 1800, sellValue = 3200000, regrowTime = 600, stockChance = 0.015, stockMin = 1, stockMax = 1, fruitColor = Color3.fromRGB(120, 255, 240), stemColor = Color3.fromRGB(40, 90, 120), shape = "Flower", fruitSize = 2.2 },
} :: { Seed }

Config.SeedById = {} :: { [string]: Seed }
Config.SeedOrder = {} :: { [string]: number }
for i, seed in Config.Seeds do
	Config.SeedById[seed.id] = seed
	Config.SeedOrder[seed.id] = i
end

export type Upgrade = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	perLevel: number,
	keepOnRebirth: boolean?, -- quality-of-life upgrades survive a rebirth
}

Config.Upgrades = {
	{ id = "GrowSpeed", name = "Fertilizer", description = "+10% grow speed per level", maxLevel = 10, baseCost = 500, costGrowth = 2.6, perLevel = 0.10 },
	{ id = "CropValue", name = "Market Stall", description = "+15% sell value per level", maxLevel = 10, baseCost = 800, costGrowth = 2.7, perLevel = 0.15 },
	{ id = "Luck", name = "Lucky Charm", description = "+12% mutation chance per level", maxLevel = 10, baseCost = 1500, costGrowth = 2.8, perLevel = 0.12 },
	{ id = "Backpack", name = "Bigger Basket", description = "+15 basket space per level", maxLevel = 10, baseCost = 300, costGrowth = 2.3, perLevel = 15 },
	-- Auto-farm unlock (see Config.AutoFarm): $5K, $45K, $405K. Kept through rebirths.
	{ id = "Farmhand", name = "Farmhand", description = "Auto-farm: Lv1 harvest, Lv2 plant, Lv3 sell", maxLevel = 3, baseCost = 5000, costGrowth = 9, perLevel = 1, keepOnRebirth = true },
} :: { Upgrade }

Config.UpgradeById = {} :: { [string]: Upgrade }
for _, u in Config.Upgrades do
	Config.UpgradeById[u.id] = u
end

-- ===== Auto-farm (Shared/AutoFarm has the rules; Services/AutoFarm runs them on the server) =====
-- Farmhand level unlocks the modes and sets the pace; the Auto Harvest pass unlocks all three at full speed.
Config.AutoFarm = {
	upgradeId = "Farmhand",
	passKey = "AutoHarvest",
	levelFor = { harvest = 1, plant = 2, sell = 3 },
	interval = { 5, 4, 3 }, -- seconds between work rounds at Farmhand Lv 1 / 2 / 3
	batch = { 2, 3, 4 }, -- tiles per round at Lv 1 / 2 / 3
	passInterval = 1,
	passBatch = 30,
	sellAtFill = 1, -- auto-sell when the basket is full
}

Config.RebirthBaseCost = 750000
Config.RebirthCostGrowth = 4
Config.RebirthBonus = 0.5 -- +50% cash per rebirth (additive)

export type Mutation = {
	id: string,
	name: string,
	multiplier: number,
	baseChance: number,
	weather: string?, -- only rolls during this weather
	color: Color3,
}

-- Rolled from the rarest down; first success wins.
Config.Mutations = {
	{ id = "Rainbow", name = "Rainbow", multiplier = 40, baseChance = 0.001, color = Color3.fromRGB(255, 100, 255) },
	{ id = "Shocked", name = "Shocked", multiplier = 8, baseChance = 0.05, weather = "Thunderstorm", color = Color3.fromRGB(120, 220, 255) },
	{ id = "Golden", name = "Golden", multiplier = 10, baseChance = 0.01, color = Color3.fromRGB(255, 205, 40) },
	{ id = "Frozen", name = "Frozen", multiplier = 3, baseChance = 0.2, weather = "Snow", color = Color3.fromRGB(170, 230, 255) },
	{ id = "Wet", name = "Wet", multiplier = 2, baseChance = 0.25, weather = "Rain", color = Color3.fromRGB(80, 140, 255) },
} :: { Mutation }

Config.MutationById = {} :: { [string]: Mutation }
for _, m in Config.Mutations do
	Config.MutationById[m.id] = m
end

export type Weather = {
	id: string,
	name: string,
	description: string,
	growthMultiplier: number,
	goldenChanceMultiplier: number,
	weight: number,
}

Config.Weathers = {
	{ id = "Rain", name = "Rain", description = "Crops grow 1.5x faster and can turn Wet (2x)", growthMultiplier = 1.5, goldenChanceMultiplier = 1, weight = 40 },
	{ id = "Snow", name = "Snowfall", description = "Growth slows, but crops can turn Frozen (3x)", growthMultiplier = 0.8, goldenChanceMultiplier = 1, weight = 25 },
	{ id = "Thunderstorm", name = "Thunderstorm", description = "Crops grow 2x faster and can get Shocked (8x)", growthMultiplier = 2, goldenChanceMultiplier = 1, weight = 20 },
	{ id = "GoldenHour", name = "Golden Hour", description = "Golden mutation chance x5!", growthMultiplier = 1.2, goldenChanceMultiplier = 5, weight = 15 },
} :: { Weather }

Config.WeatherById = {} :: { [string]: Weather }
for _, w in Config.Weathers do
	Config.WeatherById[w.id] = w
end
Config.WeatherGapMin = 300
Config.WeatherGapMax = 480
Config.WeatherDurationMin = 90
Config.WeatherDurationMax = 150

-- ===== Monetization =====
-- Replace the 0s with the IDs you create in the Creator Dashboard.
-- An ID of 0 hides that item from the in-game store.
export type Pass = { key: string, id: number, name: string, description: string, priceHint: number }
Config.GamePasses = {
	-- Prices follow docs/research/top-juegos-y-precios.md (2.3 and 4.1). priceHint is only a fallback label:
	-- the store shows the real price from MarketplaceService (GetProductInfo).
	{ key = "DoubleCash", id = 0, name = "2x Cash", description = "Double money from every sale, forever.", priceHint = 349 },
	{ key = "DoubleGrow", id = 0, name = "2x Grow Speed", description = "Every crop grows twice as fast, forever.", priceHint = 399 },
	{ key = "AutoHarvest", id = 0, name = "Auto Harvest", description = "Ripe crops go straight to your basket.", priceHint = 199 },
	{ key = "SellAnywhere", id = 0, name = "Sell Anywhere", description = "Sell your basket from anywhere on the map.", priceHint = 149 },
	{ key = "VIP", id = 0, name = "VIP", description = "+50% grow speed, +25% cash, VIP chat tag.", priceHint = 399 },
	{ key = "SuperLuck", id = 0, name = "Super Luck", description = "2x mutation chance on every harvest.", priceHint = 299 },
	{ key = "BigBasket", id = 0, name = "Big Basket", description = "+100 basket space.", priceHint = 99 },
} :: { Pass }

export type Product = { key: string, id: number, name: string, description: string, priceHint: number }
Config.DevProducts = {
	-- ordered by price: the cheap impulse buys come first in the store
	{ key = "InstantGrowOne", id = 0, name = "Instant Grow (1)", description = "The crop that would take longest to grow is ripe right now.", priceHint = 9 },
	{ key = "Restock", id = 0, name = "Restock Shop", description = "Reroll your seed shop stock instantly.", priceHint = 39 },
	{ key = "CashSmall", id = 0, name = "Cash Pouch", description = "10 minutes of your best earnings.", priceHint = 49 },
	{ key = "InstantGrow", id = 0, name = "Instant Grow", description = "Every crop in your garden is ripe right now.", priceHint = 79 },
	{ key = "LuckyPack", id = 0, name = "Lucky Seed Pack", description = "3 random seeds, Rare or better guaranteed.", priceHint = 99 },
	{ key = "CashLarge", id = 0, name = "Cash Chest", description = "1 hour of your best earnings.", priceHint = 199 },
	{ key = "CashMedium", id = 0, name = "Cash Vault", description = "160 minutes of your best earnings.", priceHint = 499 },
	{ key = "CashHuge", id = 0, name = "Cash Hoard", description = "330 minutes of your best earnings.", priceHint = 999 },
	-- one-time offer during the first 24 h (own popup; never listed in the Robux store)
	-- fixed contents on purpose: a pack with a random item inside would itself count as a paid random item
	{ key = "StarterPack", id = 0, name = "Starter Pack", description = "6 rare seeds and 30 min of 2x cash", priceHint = 15 },
} :: { Product }

-- Rewarded-video ad products: used only as the ad reward (never shown in the Robux store). id 0 = no ad button.
Config.AdProducts = {
	{ key = "AdRestock", id = 0, name = "Free Restock", description = "Watch a short video to restock your seed shop right now.", priceHint = 0 },
} :: { Product }
Config.AdDailyCap = 5

Config.StarterPackWindow = 86400
Config.StarterPackGrant = { seeds = { pumpkin = 2, watermelon = 2, dragonfruit = 1, apple = 1 }, cashBoostSeconds = 1800, cashBoostMult = 2 }
Config.StarterPackListPrice = 49 -- crossed-out "was" price shown in the popup (impulse price: 15 R$ = -70%)

Config.PassBonuses = {
	DoubleCashMult = 2,
	DoubleGrowMult = 2,
	VipGrowth = 1.5,
	VipCash = 1.25,
	SuperLuckMult = 2,
	BigBasketBonus = 100,
}
Config.PremiumCashMult = 1.1
Config.FriendBonusPerFriend = 0.1
Config.FriendBonusMax = 0.5
Config.GroupId = 0 -- set to your Roblox group ID for the +10% group bonus
Config.GroupCashMult = 1.1

-- Cash packs are sized from the player's recent earning rate, with a floor.
-- Value per Robux grows with the pack (ladder 49 / 199 / 499 / 999 R$ = +0 / +48 / +57 / +62 % minutes per R$ vs the
-- smallest pack). Each pack pays the largest of: minutes of best earn rate, a share of current cash, the floor.
Config.CashPackMinutes = { CashSmall = 10, CashLarge = 60, CashMedium = 160, CashHuge = 330 }
Config.CashPackFloor = { CashSmall = 500, CashLarge = 5000, CashMedium = 25000, CashHuge = 60000 }
Config.CashPackCashShare = { CashSmall = 0.1, CashLarge = 0.5, CashMedium = 0.75, CashHuge = 1 }
-- Instant Grow (1) bought with nothing growing still has to give something: this many minutes of earn rate
Config.InstantGrowOneFallbackMinutes = 3

-- ===== First-minute gift: given once when the tutorial ends (buy -> plant -> harvest -> sell done, or skipped) =====
Config.TutorialGift = { cash = 60, seeds = { tomato = 3 } }

-- ===== Daily rewards (streak day -> reward) =====
Config.DailyRewards = {
	{ cash = 100 },
	{ cash = 300 },
	{ seeds = { corn = 3 } },
	{ cash = 1500 },
	{ seeds = { pumpkin = 2 } },
	{ cash = 8000 },
	{ seeds = { apple = 1 }, cash = 20000 },
} :: { { cash: number?, seeds: { [string]: number }? } }
Config.DailyCooldown = 20 * 3600
Config.DailyStreakWindow = 48 * 3600

-- ===== Session play-time gifts (reset every session) =====
-- cashMinutes = N minutes of the player's recent earn rate (floor: GiftCashFloorPerMinute per minute)
export type Reward = {
	cash: number?,
	cashMinutes: number?,
	seeds: { [string]: number }?,
	boost: { kind: string, mult: number, seconds: number }?,
	luckyPack: number?,
}
Config.PlaytimeGifts = {
	{ minutes = 5, cashMinutes = 2 },
	{ minutes = 10, seeds = { corn = 3 } },
	{ minutes = 15, cashMinutes = 5 },
	{ minutes = 25, boost = { kind = "growth", mult = 2, seconds = 600 } },
	{ minutes = 40, seeds = { pumpkin = 2 } },
	{ minutes = 60, luckyPack = 1 },
} :: { any }
Config.GiftCashFloorPerMinute = 100

-- ===== Live events (weekly + recurring, UTC) =====
-- wday uses os.date("!*t") numbering: Sunday = 1 ... Saturday = 7. Weekly beats recurring when they overlap.
Config.LiveEvents = {
	weekly = {
		{ id = "HarvestFestival", wday = 7, hourUTC = 18, minute = 0, duration = 1800 },
	},
	recurring = {
		{ id = "LuckyHour", every = 10800, offset = 0, duration = 600 },
	},
}
Config.LiveEventDefs = {
	HarvestFestival = { weather = "GoldenHour", mutationMult = 3, growthMult = 2, guaranteedRareRestock = true },
	LuckyHour = { mutationMult = 2 },
} :: { [string]: { weather: string?, mutationMult: number?, growthMult: number?, guaranteedRareRestock: boolean? } }
Config.AdminUserIds = {} :: { number }
Config.LiveEventMaxMinutes = 60

-- ===== Crop x mutation Index =====
Config.IndexRowCashMult = 50 -- row reward = seed.sellValue * this
Config.IndexRowBonus = 0.02 -- permanent +2% cash per claimed row
Config.IndexAllBonus = 0.10 -- extra +10% when every row is claimed

-- ===== Referrals (share link / game invites) =====
Config.ReferralStoreName = "CropKingdom_Referrals_v1"
Config.ReferralInviteeGift = { seeds = { corn = 5, pumpkin = 1 } }
Config.ReferralInviterGift = { cashMinutes = 10, seeds = { watermelon = 1 } }
Config.ReferralMaxRewards = 25
Config.ReferralQualifySeconds = 600 -- invitee must play this long (total) before the inviter is rewarded
Config.ReferralPendingMax = 50

-- ===== Group join gift (needs GroupId) =====
Config.GroupJoinGift = { seeds = { corn = 5, blueberry = 2 } }

-- ===== Notification opt-in =====
Config.NotifAskCooldown = 7 * 86400

-- ===== Audio (client UI/Sound) =====
-- Paste Roblox audio asset IDs here. 0 = that sound stays silent (the game ships with no audio assets).
Config.Sounds = {
	click = 0, -- any button
	harvest = 0, -- a crop goes to the basket
	harvestRare = 0, -- a mutated or Giant crop
	sell = 0, -- basket sold
	error = 0, -- something was refused
	fanfare = 0, -- confetti moments: new tile, rebirth, rare toast
	reveal = 0, -- rare drop banner (mutation / giant)
	unlock = 0, -- a menu button or feature unlocks
	step = 0, -- a tutorial step is done
	music = 0, -- looping background track
}
Config.SoundVolume = { click = 0.4, harvest = 0.5, harvestRare = 0.7, sell = 0.6, error = 0.4, fanfare = 0.7, reveal = 0.8, unlock = 0.6, step = 0.5, music = 0.25 }

-- ===== Seeds for Robux (second button on each Seed Shop row) =====
-- One developer product per seed you want to sell directly. 0 = no Robux button on that row.
Config.SeedProducts = {
	carrot = 0,
	tomato = 0,
	corn = 0,
	blueberry = 0,
	pumpkin = 0,
	watermelon = 0,
	apple = 0,
	dragonfruit = 0,
	mango = 0,
	starfruit = 0,
	moonmelon = 0,
	cosmiclotus = 0,
} :: { [string]: number }

-- ===== Codes =====
Config.Codes = ({
	RELEASE = { cash = 500, seeds = { tomato = 5 } },
	GROWBIG = { seeds = { corn = 5 } },
	THANKYOU = { cash = 2500 },
} :: any) :: { [string]: { cash: number?, seeds: { [string]: number }? } }

return Config
