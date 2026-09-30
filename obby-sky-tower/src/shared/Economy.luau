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
} :: { [string]: number }

Economy.EffectPrice = {
	sparkles = 100,
	smoke = 400,
	stars = 900,
	flames = 2500,
} :: { [string]: number }

return Economy
