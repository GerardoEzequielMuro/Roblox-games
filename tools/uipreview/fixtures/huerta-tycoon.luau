-- uipreview fixture: Crop Kingdom (huerta-tycoon)
-- "mid": ~2 h in, 1 rebirth, 18 tiles, several seeds, a partial index, crops growing.
-- Shape from src/server/Services/Data.luau (Profile type / defaultProfile).
local DAY = 86400
return {
	userId = 90000001,
	profileStore = "CropKingdom_v1",
	midProfile = function(h)
		local now = h.now()
		local tiles = {}
		local plant = { "corn", "corn", "pumpkin", "tomato", "blueberry", "watermelon", "carrot", "pumpkin", "corn", "tomato", "apple", "blueberry" }
		for i, seed in plant do
			tiles[tostring(i)] = { seed = seed, progress = (i * 0.17) % 1, mut = if i == 3 then "Wet" elseif i == 8 then "Golden" else nil }
		end
		return {
			version = 1,
			cash = 184250,
			totalEarned = 2.3e6,
			rebirths = 1,
			tilesOwned = 18,
			upgrades = { GrowSpeed = 4, CropValue = 3, Luck = 2, Backpack = 5, Farmhand = 1 },
			seeds = { carrot = 14, tomato = 9, corn = 6, blueberry = 3, pumpkin = 4, watermelon = 2, apple = 1 },
			backpack = { ["corn|Normal"] = 11, ["pumpkin|Wet"] = 2, ["tomato|Normal"] = 7 },
			tiles = tiles,
			purchases = {},
			daily = { lastClaim = now - DAY - 1800, streak = 5 },
			codes = {},
			tutorialDone = true,
			lang = "",
			index = {
				carrot = { Normal = true, Wet = true },
				tomato = { Normal = true },
				corn = { Normal = true, Golden = true },
				blueberry = { Normal = true },
				pumpkin = { Normal = true, Wet = true },
			},
			indexClaimed = {},
			referredBy = 0,
			referralPaid = false,
			referralRewards = 0,
			starterBought = false,
			groupGiftClaimed = false,
			notifAskedAt = now - 2 * DAY,
			ads = { day = 0, count = 0 },
			auto = { harvest = true, plant = false, sell = false, seed = "" },
			wild = { cycle = 0, claimed = {} },
			trophies = { { seed = "pumpkin", mut = "Wet", size = "Big" } },
			savedAt = now - 3 * 3600,
			firstJoin = now - 5 * DAY,
			playTime = 2 * 3600,
		}
	end,
	windows = {
		shop = function(ctx)
			ctx.client("UI.Panels").open("Shop")
		end,
		upgrades = function(ctx)
			ctx.client("UI.Panels").open("Upgrades")
		end,
		rebirth = function(ctx)
			ctx.client("UI.Panels").open("Rebirth")
		end,
		store = function(ctx)
			ctx.client("UI.Panels").open("Store")
		end,
		odds = function(ctx)
			ctx.client("UI.Panels").open("Odds")
		end,
		daily = function(ctx)
			ctx.client("UI.Panels").open("Daily")
		end,
		codes = function(ctx)
			ctx.client("UI.Panels").open("Codes")
		end,
		language = function(ctx)
			ctx.client("UI.Panels").open("Language")
		end,
		gifts = function(ctx)
			ctx.client("UI.Panels").open("Gifts")
		end,
		index = function(ctx)
			ctx.client("UI.Panels").open("Index")
		end,
		invite = function(ctx)
			ctx.client("UI.Panels").open("Invite")
		end,
		trophies = function(ctx)
			ctx.client("UI.Panels").open("Trophies")
		end,
		auto = function(ctx)
			ctx.client("UI.Panels").open("Auto")
		end,
		starter = function(ctx)
			ctx.client("UI.Panels").open("Starter")
		end,
	},
}
