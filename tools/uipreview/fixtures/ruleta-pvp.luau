-- uipreview fixture: Spin Showdown (ruleta-pvp)
-- "mid": level 14, 60 matches, a few cosmetics, tutorial done.
-- Shape from src/server/Services/Data.luau (defaultProfile); reconcile fills the rest.
local DAY = 86400
local function W(name)
	return function(ctx)
		ctx.client("UI.Windows").open(name)
	end
end
return {
	userId = 90000001,
	profileStore = "SpinShowdown_v1",
	midProfile = function(h)
		local Config = h.shared("Shared.Config")
		local now = h.now()
		local owned = {}
		local n = 0
		for _, c in Config.Cosmetics do
			if n < 6 and c.price and c.price.type == "coins" then
				owned[c.id] = true
				n += 1
			end
		end
		return {
			version = 1,
			coins = 2340,
			xp = 180,
			level = 14,
			trophies = 420,
			bestTrophies = 455,
			wins = 21,
			matches = 60,
			streak = 2,
			bestStreak = 5,
			elims = 74,
			owned = owned,
			daily = { last = now - DAY - 300, streak = 3 },
			codes = {},
			purchases = {},
			lang = "",
			referredBy = 0,
			referralPaid = false,
			referralRewards = 0,
			starterBought = false,
			groupGiftClaimed = false,
			notifAskedAt = now - 2 * DAY,
			tutorialDone = true,
			savedAt = now - 5 * 3600,
			firstJoin = now - 8 * DAY,
			playTime = 4 * 3600,
		}
	end,
	windows = {
		play = W("Play"),
		shop = W("Shop"),
		season = W("Season"),
		locker = W("Locker"),
		ranking = W("Ranking"),
		rewards = W("Rewards"),
		quests = W("Quests"),
		invite = W("Invite"),
		settings = W("Settings"),
		-- a real match against bots: QuickPlay, then let the server fill the table and deal
		match = function(ctx)
			local Net = ctx.client("Net")
			local ok, res = Net.request("QuickPlay", { mode = "classic" })
			ctx.log("QuickPlay -> " .. tostring(ok) .. " " .. tostring(res))
			ctx.wait(25)
		end,
	},
}
