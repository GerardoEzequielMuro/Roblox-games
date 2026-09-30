--!strict
-- Coin economy numbers (what the free player earns and what the cosmetics cost). PURE Luau, no
-- Roblox APIs, so sim/pacing_sim.luau and tests/pacing_test.luau can load the REAL numbers
-- (Config requires this module and re-exports every field, like it does with Shared/Pricing).
-- Robux prices are NOT here: they live in Shared/Pricing.
local Economy = {}

Economy.CoinsPerTower = 250 -- bonus for every summit (stage 100, 200 ... 1000)
Economy.CoinPickupValue = 3
Economy.CoinsPerWin = 250

Economy.DailyRewards = { 25, 40, 60, 80, 100, 150, 250 } -- by streak day (day 7+ repeats last)
Economy.DailyFreeSkipOnDay = 7 -- streak day that also gives a free skip
Economy.DailyCooldown = 20 * 3600 -- can claim again after 20 h
Economy.DailyStreakWindow = 48 * 3600 -- miss this and the streak resets

export type PlaytimeReward = { minutes: number, coins: number, freeSkips: number }
Economy.PlaytimeRewards = {
	{ minutes = 1, coins = 20, freeSkips = 0 }, -- first gift inside the first minute
	{ minutes = 5, coins = 30, freeSkips = 0 },
	{ minutes = 15, coins = 75, freeSkips = 0 },
	{ minutes = 30, coins = 150, freeSkips = 1 },
	{ minutes = 60, coins = 300, freeSkips = 2 },
} :: { PlaytimeReward }

export type Code = { coins: number, freeSkips: number?, expires: number? }
Economy.Codes = {
	RELEASE = { coins = 100 },
	SKYHIGH = { coins = 150, freeSkips = 1 },
	CLOUDS = { coins = 50 },
} :: { [string]: Code }

-- Coin prices of the cosmetics sold in the menu shop (Config.Trails / Config.Effects take them
-- from here; the free / exclusive ones have no entry).
Economy.TrailPrice = {
	white = 20,
	mint = 50,
	fire = 160,
	ocean = 350,
	candy = 650,
	toxic = 1200,
	galaxy = 3000,
	rainbow = 6000,
	-- tower tiers (Economy.TowerReq): the late-game coin sink
	blossom = 2500,
	tidal = 4500,
	nebula = 5000,
	sunforge = 8500,
	twilight = 9000,
	celestial = 15000,
} :: { [string]: number }

Economy.EffectPrice = {
	sparkles = 100,
	smoke = 400,
	stars = 900,
	flames = 2500,
	frost = 3000,
	embers = 4000,
	prism = 7000,
	goldenhour = 6500,
	voidaura = 12000,
} :: { [string]: number }

-- Shoulder companions (Config.Pets). One is worn at a time, on the left shoulder.
Economy.PetPrice = {
	sprite = 3500,
	bunny = 6000,
	drake = 10000,
	phoenix = 20000,
} :: { [string]: number }

-- Late-game coin sink (cosmetic only: nothing here makes the climb easier, so the speed leaderboard
-- stays fair). The tier items are sold for coins once you have CLEARED that many towers (best stage
-- >= tower * StagesPerTower), so there is always a next thing to save for up to tower 10.
Economy.StagesPerTower = 100
Economy.TowerReq = {
	["trail:blossom"] = 2,
	["pet:sprite"] = 2,
	["effect:frost"] = 3,
	["effect:embers"] = 3,
	["trail:nebula"] = 4,
	["trail:tidal"] = 5,
	["pet:bunny"] = 5,
	["effect:prism"] = 6,
	["effect:goldenhour"] = 7,
	["trail:sunforge"] = 7,
	["pet:drake"] = 8,
	["trail:twilight"] = 9,
	["effect:voidaura"] = 9,
	["trail:celestial"] = 10,
	["pet:phoenix"] = 10,
} :: { [string]: number }

-- Shine: upgrade any cosmetic you own (trail / effect / pet) up to 3 times, for coins. Purely
-- visual: a longer and wider trail, denser particles, a glowing pet.
Economy.ShineCost = { 1200, 3000, 6000 } :: { number }
Economy.ShineMax = 3

-- Has somebody with this best stage cleared `tower` towers?
function Economy.towerCleared(best: number, tower: number): boolean
	return best >= tower * Economy.StagesPerTower
end

-- Tower needed to buy `kind` ("trail" | "effect" | "pet") `id`; 0 = no requirement.
function Economy.towerReq(kind: string, id: string): number
	return Economy.TowerReq[kind .. ":" .. id] or 0
end

-- Next shine level's coin cost for an item now at `level` (nil = already at the maximum).
function Economy.shineCost(level: number): number?
	return Economy.ShineCost[math.floor(level) + 1]
end

return Economy
