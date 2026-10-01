-- uipreview fixture: Tap Pets Simulator (pet-tap-simulator)
-- "mid": ~2-3 h in: zones 1-3, 2 rebirths, 16 pets, some upgrades, HUD fully unlocked.
-- Shape from src/server/Services/Data.luau (defaultProfile); reconcile fills the rest.
local DAY = 86400
local function W(name)
	return function(ctx)
		ctx.client("UI.Windows").open(name)
	end
end
return {
	userId = 90000001,
	profileStore = "TapPets_Profiles_v1",
	midProfile = function(h)
		local Config = h.shared("Shared.Config")
		local now = h.now()
		local pets, equipped, discovered = {}, {}, {}
		local n = 0
		for _, pet in Config.Pets do
			if pet.zone <= 3 and n < 16 then
				n += 1
				local uid = "p" .. n
				pets[uid] = { id = pet.id, tier = if n % 6 == 0 then 1 else 0, locked = n <= 2 }
				discovered[pet.id] = true
				if #equipped < 4 then
					table.insert(equipped, uid)
				end
			end
		end
		local upgrades = {}
		for i, u in Config.Upgrades do
			upgrades[u.id] = (i * 2) % 7
		end
		return {
			version = 1,
			taps = 1.84e6,
			gems = 260,
			totalTaps = 2.6e7,
			rebirths = 2,
			zones = { 1, 2, 3 },
			pets = pets,
			equipped = equipped,
			nextUid = n + 1,
			upgrades = upgrades,
			discovered = discovered,
			indexClaimed = {},
			daily = { last = now - DAY - 600, streak = 4 },
			codes = {},
			purchases = {},
			luckBoostLeft = 0,
			settings = { autoTap = true, autoEquip = false, autoRebirth = false },
			lang = "",
			offlinePending = 0,
			offlineSeconds = 0,
			referredBy = 0,
			referralPaid = false,
			referralRewards = 0,
			starterBought = false,
			ads = { day = 0, count = 0 },
			tapBoostLeft = 0,
			notifAskedAt = now - 2 * DAY,
			groupGiftClaimed = false,
			totalHatched = 75,
			savedAt = now - 3 * 3600,
			firstJoin = now - 6 * DAY,
			playTime = 3 * 3600,
		}
	end,
	-- PLAYTEST only: the repo ships every Robux id as 0 ("not live yet"); give them fake ids so
	-- the purchase flow (prompt -> ProcessReceipt / gamepass finished) can be exercised.
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
		pets = W("Pets"),
		upgrades = W("Upgrades"),
		rebirth = W("Rebirth"),
		teleport = W("Teleport"),
		codes = W("Codes"),
		invite = W("Invite"),
		quests = W("Quests"),
		index = W("Index"),
		store = W("Store"),
		rewards = W("Rewards"),
		egg = function(ctx)
			ctx.client("UI.EggPanel").open("basic", Vector3.new(0, 0, 0))
		end,
	},
}
