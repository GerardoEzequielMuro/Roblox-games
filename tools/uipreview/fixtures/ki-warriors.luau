-- uipreview fixture: Ki Warriors
-- "mid": ~3 h in: planet 3, 2 forms, 2 techniques, some auras, story past the tutorial.
-- Shape from src/server/Services/Data.luau (defaultProfile); reconcile fills the rest.
local DAY = 86400
local function W(name)
	return function(ctx)
		ctx.client("UI.Windows").open(name)
	end
end
return {
	userId = 90000001,
	profileStore = "KiWarriors_Profiles_v1",
	midProfile = function(h)
		local Config = h.shared("Shared.Config")
		local now = h.now()
		local stats = {}
		for i, s in Config.Stats do
			stats[s] = 12000 * i
		end
		local upgrades = {}
		for i, u in Config.Upgrades do
			upgrades[u.id] = i % 4
		end
		local auras = {}
		for i, a in Config.Auras do
			if i <= 5 then
				auras[a.id] = 1
			end
		end
		return {
			version = 1,
			stats = stats,
			sparks = 48200,
			gems = 135,
			bestPower = 420000,
			rebirths = 1,
			planet = 3,
			planets = { 1, 2, 3 },
			gear = 4,
			techniques = { [Config.Techniques[1].id] = true, [Config.Techniques[2].id] = true },
			forms = 2,
			auras = auras,
			auraEquipped = Config.Auras[4].id,
			spins = 2,
			freeSpinDay = 0,
			race = "terran",
			raceChanges = 0,
			upgrades = upgrades,
			story = { step = math.min(#Config.Story, Config.TutorialSteps + 7), progress = 3 },
			daily = { last = now - DAY - 900, streak = 3 },
			codes = {},
			purchases = {},
			boostLeft = 0,
			lang = "",
			offlineSeconds = 0,
			referredBy = 0,
			referralPaid = false,
			referralRewards = 0,
			starterBought = false,
			ads = { day = 0, count = 0 },
			notifAskedAt = now - 2 * DAY,
			groupGiftClaimed = false,
			wishes = 1,
			wishPower = 0,
			protectionOff = false,
			kills = 340,
			bossKills = {},
			totalReps = 52000,
			items = {},
			skins = {},
			skin = "",
			mounts = {},
			mount = "",
			bp = {},
			savedAt = now - 4 * 3600,
			firstJoin = now - 7 * DAY,
			playTime = 3 * 3600,
		}
	end,
	-- PLAYTEST only: Robux ids are 0 in the repo ("not live yet"); fake ids let the purchase flow run.
	playtestPatches = {
		["src/shared/Config.luau"] = function(Config)
			for i, p in Config.Passes do
				p.id = 7000 + i
			end
			for i, p in Config.Products do
				p.id = 8000 + i
			end
		end,
	},
	windows = {
		warrior = W("Warrior"),
		forms = W("Forms"),
		moves = W("Moves"),
		upgrades = W("Upgrades"),
		ascend = W("Ascend"),
		travel = W("Travel"),
		quests = W("Quests"),
		rewards = W("Rewards"),
		shop = W("Shop"),
		auras = W("Auras"),
		wish = W("Wish"),
		ranking = W("Ranking"),
		invite = W("Invite"),
		settings = W("Settings"),
		wardrobe = W("Wardrobe"),
		season = W("Season"),
	},
}
