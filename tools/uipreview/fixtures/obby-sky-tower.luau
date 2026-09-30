-- uipreview fixture: Sky Tower Obby
-- "new": first join (no DataStore entry). "mid": the saved profile below, loaded by the
-- game's own Data.load/reconcile (shape from src/server/Data.luau defaultProfile).
local DAY = 86400
return {
	userId = 90000001,
	profileStore = "SkyTowerObby_v1",
	midProfile = function()
		local now = os.time()
		return {
			version = 2,
			stage = 238,
			best = 262,
			base = false,
			runTop = 238,
			gifts = {},
			boosts = {},
			charges = {},
			perks = {},
			wins = 2,
			coins = 1835,
			totalCoins = 5420,
			freeSkips = 1,
			trails = {},
			equippedTrail = "",
			effects = {},
			equippedEffect = "",
			settings = { speedCoil = true, gravityCoil = false, effects = true },
			lang = "",
			bestRunMs = 1843250,
			ads = { day = 0, count = 0 },
			referredBy = 0,
			referralPaid = false,
			referralRewards = 0,
			starterBought = false,
			boostEndsAt = 0,
			groupGiftClaimed = false,
			notifAskedAt = now - 3 * DAY,
			purchases = {},
			daily = { lastClaim = now - DAY - 3600, streak = 3 },
			codes = {},
			savedAt = now - 6 * 3600,
			firstJoin = now - 9 * DAY,
			playTime = 5 * 3600,
		}
	end,
	-- window name -> how to open it (called in the client, after boot)
	windows = {
		menu = function(ctx)
			ctx.click(ctx.find("MenuButton"))
		end,
		shop = function(ctx)
			ctx.client("UI.Kit").open("shop")
		end,
		store = function(ctx)
			ctx.client("UI.Kit").open("store")
		end,
		rewards = function(ctx)
			ctx.client("UI.Kit").open("rewards")
		end,
		settings = function(ctx)
			ctx.client("UI.Kit").open("settings")
		end,
		starter = function(ctx)
			ctx.client("UI.Kit").open("starter")
		end,
		travel = function(ctx)
			ctx.client("UI.Kit").open("travel")
		end,
		win = function(ctx)
			ctx.client("UI.Kit").open("win")
		end,
	},
}
