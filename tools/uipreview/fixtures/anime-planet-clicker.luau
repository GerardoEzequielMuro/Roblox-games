-- uipreview fixture: Planet Crackers (anime-planet-clicker)
-- "mid": a player ~3 h in: galaxy 3 unlocked, 2 rebirths, a drill, 14 pets, tutorial done.
-- Shape from src/server/Services/Data.luau (defaultProfile); missing keys are filled by
-- the game's own reconcile().
local DAY = 86400
return {
	userId = 90000001,
	profileStore = "PlanetCrackers_v1",
	midProfile = function(h)
		local Config = h.shared("Shared.Config")
		local now = h.now()
		local pets, equipped, discovered = {}, {}, {}
		local n = 0
		for _, pet in Config.Pets do
			if pet.zone <= 3 and n < 14 then
				n += 1
				local uid = "p" .. n
				pets[uid] = { id = pet.id, tier = if n % 5 == 0 then 1 else 0, locked = n <= 2 }
				discovered[pet.id] = true
				if #equipped < 4 then
					table.insert(equipped, uid)
				end
			end
		end
		local upgrades = {}
		for i, u in Config.Upgrades do
			upgrades[u.id] = math.min(u.max, (i * 3) % 11)
		end
		local mats = {}
		for i, m in Config.Materials do
			mats[m] = if i <= 2 then 140 * i else 0
		end
		return {
			version = 1,
			stardust = 2.45e6,
			crystals = 340,
			totalMined = 3.1e7,
			rebirths = 2,
			zones = { 1, 2, 3 },
			tool = Config.Tools[5].id,
			upgrades = upgrades,
			mats = mats,
			pets = pets,
			equipped = equipped,
			nextUid = n + 1,
			discovered = discovered,
			indexClaimed = {},
			mastery = { rock = 180, fury = 30, zephyr = 12 },
			masteryPaid = {},
			gate = {},
			cargo = { count = 17, value = 52000 },
			buffs = {},
			autoDelete = {},
			daily = { last = now - DAY - 600, streak = 4 },
			codes = {},
			purchases = {},
			anomalyWindow = 0,
			arenaPoints = 120,
			arenaKos = 7,
			tutorial = #Config.Tutorial + 1,
			settings = { sfx = true, lite = false, hidePets = false },
			lang = "",
			offlinePending = 0,
			offlineSeconds = 0,
			referredBy = 0,
			referralPaid = false,
			referralRewards = 0,
			starterBought = false,
			ads = { day = 0, count = 0 },
			notifAskedAt = now - 2 * DAY,
			groupGiftClaimed = false,
			totalOpened = 60,
			planetsBroken = 900,
			hits = 21000,
			savedAt = now - 5 * 3600,
			firstJoin = now - 6 * DAY,
			playTime = 3 * 3600,
		}
	end,
	windows = {
		pets = function(ctx)
			ctx.client("UI.Windows").open("Pets")
		end,
		upgrades = function(ctx)
			ctx.client("UI.Windows").open("Upgrades")
		end,
		store = function(ctx)
			ctx.client("UI.Windows").open("Store")
		end,
		rewards = function(ctx)
			ctx.client("UI.Windows").open("Rewards")
		end,
		quests = function(ctx)
			ctx.client("UI.Windows").open("Quests")
		end,
		index = function(ctx)
			ctx.client("UI.Windows").open("Index")
		end,
		rebirth = function(ctx)
			ctx.client("UI.Windows").open("Rebirth")
		end,
		teleport = function(ctx)
			ctx.client("UI.Windows").open("Teleport")
		end,
		auto = function(ctx)
			ctx.client("UI.Windows").open("Auto")
		end,
		settings = function(ctx)
			ctx.client("UI.Windows").open("Settings")
		end,
		invite = function(ctx)
			ctx.client("UI.Windows").open("Invite")
		end,
		capsule = function(ctx)
			ctx.client("UI.CapsulePanel").open("dawn")
		end,
	},
}
