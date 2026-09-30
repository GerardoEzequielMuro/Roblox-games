--!strict
-- Sky Tower Obby: every tunable number and every Creator Dashboard ID lives here.
-- Any ID left at 0 hides that item (button/stall/badge is simply skipped).

local TowerStyle = require(script.Parent.TowerStyle)
local Rules = require(script.Parent.Rules)

local Config = {}

Config.GameName = "Sky Tower Obby"
Config.DataStoreName = "SkyTowerObby_v1"
Config.WinsBoardStore = "SkyTowerObby_Wins_v1"
Config.FastestBoardStore = "SkyTowerObby_Fastest_v1" -- OrderedDataStore: best run in ms (ascending)
Config.StageBoardStore = "SkyTowerObby_Stage_v1" -- OrderedDataStore: best stage of the 1,000 (descending)
Config.ReferralStore = "SkyTowerObby_Referrals_v1" -- DataStore: inviter id -> pending invitee rewards
Config.MapSeed = 777 -- same seed => identical tower on every server
Config.AutosaveInterval = 90

-- Monetization ---------------------------------------------------------------------------
Config.Products = {
	SkipStage = 0, -- Developer Product: skip 1 stage (top earner in obbies)
	Skip10 = 0, -- Developer Product: skip 10 stages
	Coins500 = 0, -- Developer Product: 500 coins
	Coins2500 = 0, -- Developer Product: 2,500 coins
	AdSkip = 0, -- Developer Product used only as the reward holder of the rewarded-video ad skip
	StarterPack = 0, -- Developer Product: first-24-hour starter pack (suggested 59 R$)
} :: { [string]: number }

Config.Passes = {
	SpeedCoil = 0, -- WalkSpeed 24 (toggle in Settings). Suggested 8 R$: the impulse buy of top obbies
	GravityCoil = 0, -- lower gravity while jumping (toggle in Settings)
	DoubleJump = 0, -- one extra jump in the air, for ever (the shop sells it for 5 minutes)
	InfiniteRevives = 0, -- unlimited pocket checkpoints (suggested 139 R$)
	VIP = 0, -- [VIP] chat tag, gold trail, +50% coins, bigger daily reward
	DoubleCoins = 0, -- x2 coins from every source
} :: { [string]: number }

Config.BadgeIds = {
	Winner = 0, -- awarded on reaching stage 100
	Stage50 = 0, -- optional: halfway there
	FirstRebirth = 0, -- optional
} :: { [string]: number }

-- In Studio only: when a product ID is 0 the Skip button still shows and skips for free,
-- so the whole loop can be tested without publishing.
Config.StudioFreeSkips = true
-- In Studio only: treat every pass whose ID is 0 as owned (to try coils / VIP without publishing).
-- Leave it off to play in Studio exactly as a new player would.
Config.StudioOwnsPasses = false

-- Skip offer after a death streak + rewarded-video ads (P0-1) -------------------------------
Config.SkipOfferAfterDeaths = 4 -- deaths/falls on the same stage before the "Stuck?" card (and every +4)
Config.SkipOfferCooldown = 90 -- seconds between two offers
Config.AdDailyCap = 6 -- rewarded-video ad skips per player per UTC day

-- Starter pack (P0-4) ---------------------------------------------------------------------------
Config.StarterPackWindow = 24 * 3600 -- on sale during the first 24 h after the first join
Config.StarterPackSkips = 3
Config.StarterBoostSeconds = 30 * 60 -- x2 coins boost
Config.StarterPackAnchorPrice = 169 -- crossed-out "value" shown on the offer (display only)

-- Invites / referrals (P0-3) ---------------------------------------------------------------------
Config.ReferralMaxRewards = 25 -- lifetime cap of inviter rewards
Config.ReferralInviteeGift = { coins = 50, freeSkips = 1 }
Config.ReferralInviterGift = { coins = 100, freeSkips = 1 }
Config.ReferralPayStage = 5 -- the invitee must reach this stage for the inviter to be paid

-- Group reward (P0-7). 0 = hidden. -----------------------------------------------------------------
Config.GroupId = 0
Config.GroupGift = { coins = 150, freeSkips = 1, trail = "group" }

-- Notification opt-in (P0-8) -----------------------------------------------------------------------
Config.NotifyAskCooldown = 7 * 86400

-- Live events (P0-6): wday Sunday = 1 ... Saturday = 7 (os.date("!*t")) -----------------------------
Config.LiveEvents = {
	{ id = "DoubleCoinsWeekend", kind = "weekly", fromWday = 7, toWday = 1, allDayUTC = true },
	{ id = "SkipSaleHour", kind = "daily", hourUTC = 20, duration = 3600 },
} :: { any } -- see Shared/LiveEvents.luau (EventDef)
Config.AdminUserIds = {} :: { number } -- may use the /event <id> <minutes> chat command

-- Overhead titles by wins (P0-5) ---------------------------------------------------------------------
Config.Titles = {
	{ wins = 0, name = "Climber" },
	{ wins = 1, name = "Sky Walker" },
	{ wins = 5, name = "Cloud Runner" },
	{ wins = 15, name = "Tower Legend" },
	{ wins = 50, name = "Sky God" },
}

-- Gameplay ---------------------------------------------------------------------------------
-- The classic obby character. The map is calibrated against these (Shared/Layout.Physics); the
-- server enforces them on every character and tests/layout_test.luau refuses a higher jump.
Config.JumpPower = 50 -- 6.37 studs
Config.WalkSpeed = 16
Config.MaxStageJump = 3 -- a checkpoint more than this ahead of your current one is ignored
Config.CheckpointTouchRadius = 14 -- server check: root must really be near the pad
Config.FallLimit = 28 -- studs below your checkpoint => teleported back (no death)
Config.SpeedCoilWalkSpeed = 24
Config.GravityCoilFactor = 0.55 -- effective gravity multiplier with the gravity coil on
Config.BounceHeight = 24 -- must match Layout.Physics.bounceHeight
Config.GlassRevealDistance = 16

-- Coins --------------------------------------------------------------------------------------
Config.CoinsPerStage = Rules.coinsForStage -- 5 + 2 per world reached (capped at 55)
Config.CoinsPerTower = 250 -- bonus for every summit (stage 100, 200 ... 1000)
Config.CoinPickupValue = 3
Config.CoinsPerWin = 250
Config.VIPCoinBonus = 0.5 -- +50%

-- Rewards -------------------------------------------------------------------------------------
Config.DailyRewards = { 25, 40, 60, 80, 100, 150, 250 } -- by streak day (day 7+ repeats last)
Config.DailyFreeSkipOnDay = 7 -- streak day that also gives a free skip
Config.DailyCooldown = 20 * 3600 -- can claim again after 20 h
Config.DailyStreakWindow = 48 * 3600 -- miss this and the streak resets

export type PlaytimeReward = { minutes: number, coins: number, freeSkips: number }
Config.PlaytimeRewards = {
	{ minutes = 5, coins = 30, freeSkips = 0 },
	{ minutes = 15, coins = 75, freeSkips = 0 },
	{ minutes = 30, coins = 150, freeSkips = 1 },
	{ minutes = 60, coins = 300, freeSkips = 2 },
} :: { PlaytimeReward }

export type Code = { coins: number, freeSkips: number?, expires: number? }
Config.Codes = {
	RELEASE = { coins = 100 },
	SKYHIGH = { coins = 150, freeSkips = 1 },
	CLOUDS = { coins = 50 },
} :: { [string]: Code }

-- Cosmetics -----------------------------------------------------------------------------------
-- exclusive = only granted by something else ("StarterPack", "Group"); never sold for coins
-- exclusive "Gift" = tower gifts (Shared/Gifts), "Lounge" = free in the Winner's Lounge (Shared/Perks)
export type Trail = { id: string, name: string, price: number, colors: { Color3 }, pass: string?, exclusive: string? }
Config.Trails = {
	{ id = "white", name = "Cloud", price = 100, colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 230, 255) } },
	{ id = "mint", name = "Mint", price = 250, colors = { Color3.fromRGB(120, 255, 200), Color3.fromRGB(40, 200, 160) } },
	{ id = "fire", name = "Fire", price = 500, colors = { Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 60, 20) } },
	{ id = "ocean", name = "Ocean", price = 800, colors = { Color3.fromRGB(90, 200, 255), Color3.fromRGB(20, 60, 220) } },
	{ id = "candy", name = "Candy", price = 1200, colors = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(140, 220, 255) } },
	{ id = "toxic", name = "Toxic", price = 1800, colors = { Color3.fromRGB(180, 255, 40), Color3.fromRGB(30, 140, 30) } },
	{ id = "galaxy", name = "Galaxy", price = 3000, colors = { Color3.fromRGB(160, 80, 255), Color3.fromRGB(20, 10, 60) } },
	{
		id = "rainbow",
		name = "Rainbow",
		price = 6000,
		colors = {
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(255, 200, 40),
			Color3.fromRGB(60, 220, 90),
			Color3.fromRGB(60, 140, 255),
			Color3.fromRGB(190, 80, 255),
		},
	},
	{ id = "gold", name = "VIP Gold", price = 0, pass = "VIP", colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(230, 160, 20) } },
	{ id = "starter", name = "Starter Star", price = 0, exclusive = "StarterPack", colors = { Color3.fromRGB(255, 250, 150), Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 200, 255) } },
	{ id = "group", name = "Crew", price = 0, exclusive = "Group", colors = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(60, 120, 255) } },
	{ id = "summit", name = "Summit Flame", price = 0, exclusive = "Gift", colors = { Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 160, 40), Color3.fromRGB(255, 60, 30) } },
	{ id = "comet", name = "Comet", price = 0, exclusive = "Gift", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 220, 255), Color3.fromRGB(90, 60, 255) } },
	{ id = "lounge_neon", name = "Neon", price = 0, exclusive = "Lounge", colors = { Color3.fromRGB(0, 255, 230), Color3.fromRGB(255, 60, 220) } },
	{ id = "lounge_sunrise", name = "Sunrise", price = 0, exclusive = "Lounge", colors = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 140, 120), Color3.fromRGB(190, 110, 255) } },
} :: { Trail }

export type Effect = { id: string, name: string, price: number, kind: string, color: Color3, exclusive: string? }
Config.Effects = {
	{ id = "sparkles", name = "Sparkles", price = 400, kind = "Sparkles", color = Color3.fromRGB(255, 240, 120) },
	{ id = "stars", name = "Star Aura", price = 1500, kind = "Aura", color = Color3.fromRGB(140, 220, 255) },
	{ id = "smoke", name = "Smoke", price = 900, kind = "Smoke", color = Color3.fromRGB(230, 230, 240) },
	{ id = "flames", name = "Flames", price = 2500, kind = "Fire", color = Color3.fromRGB(255, 120, 30) },
	{ id = "aurora", name = "Aurora", price = 0, kind = "Aura", color = Color3.fromRGB(120, 255, 200), exclusive = "Gift" },
	{ id = "lounge_stars", name = "Starlight", price = 0, kind = "Aura", color = Color3.fromRGB(255, 240, 160), exclusive = "Lounge" },
} :: { Effect }

-- Rebirth trails: one colour per win, cycling.
Config.RebirthColors = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 170, 50),
	Color3.fromRGB(255, 240, 80),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(255, 110, 220),
}

-- Worlds / themes: one per 10 stages -----------------------------------------------------------
export type Theme = {
	name: string,
	platform: Color3,
	alt: Color3,
	accent: Color3,
	material: Enum.Material,
	pad: Color3,
	sky: Color3, -- fog / ambient tint used by the client while you are in this world
}

local MATERIALS = {
	Enum.Material.Grass,
	Enum.Material.SmoothPlastic,
	Enum.Material.Ice,
	Enum.Material.Sandstone,
	Enum.Material.Basalt,
	Enum.Material.Slate,
	Enum.Material.DiamondPlate,
	Enum.Material.SmoothPlastic,
	Enum.Material.Neon,
	Enum.Material.Glass,
}
local WORLD_NAMES = { "Grassy Hills", "Candy Land", "Frozen Peaks", "Desert Ruins", "Lava Caves", "Ocean Reef", "Toxic Factory", "Cloud Kingdom", "Neon Space", "Rainbow Summit" }

local function c3(v: { number }): Color3
	return Color3.fromRGB(v[1], v[2], v[3])
end
Config.c3 = c3

-- The theme of world look `style` (1..10) as tower `tower` (1..10) paints it: the palettes and
-- the per-tower colour shift live in Shared/TowerStyle (pure, unit-tested).
local themeCache: { [number]: Theme } = {}
function Config.theme(tower: number, style: number): Theme
	local key = tower * 100 + style
	local cached = themeCache[key]
	if cached then
		return cached
	end
	local pal = TowerStyle.palette(tower, style)
	local theme: Theme = {
		name = WORLD_NAMES[style],
		platform = c3(pal.platform),
		alt = c3(pal.alt),
		accent = c3(pal.accent),
		material = MATERIALS[style],
		pad = c3(pal.pad),
		sky = c3(pal.sky),
	}
	themeCache[key] = theme
	return theme
end

-- Tower 1 (the original Sky Tower), by world.
Config.Themes = {} :: { Theme }
for style = 1, #TowerStyle.Worlds do
	Config.Themes[style] = Config.theme(1, style)
end

Config.KillColor = c3(TowerStyle.KILL)

return Config
