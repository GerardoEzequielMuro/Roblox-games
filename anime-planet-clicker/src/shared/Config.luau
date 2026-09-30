--!nonstrict
-- Planet Crackers: every number and piece of content. Pure data (no Roblox APIs) so the
-- standalone tools in sim/ and tests/ can load it with luau.exe. Colors are { r, g, b }.
local Config = {}

Config.GameName = "Planet Crackers"
Config.DataStoreName = "PlanetCrackers_v1"
Config.ReferralStore = "PlanetCrackers_Referrals_v1"
Config.LeaderboardStores = { mined = "PC_LB_Mined_v1", rebirths = "PC_LB_Rebirths_v1", arena = "PC_LB_Arena_v1" }
Config.AutosaveInterval = 90
Config.LeaderboardUpdateInterval = 60

-- Creator Dashboard values (0 = not set up yet; the feature stays hidden)
Config.GroupId = 0
Config.AdminUserIds = {} :: { number }
Config.StudioGrantAllPasses = false

---------------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------------
Config.Rarities = {
	{ name = "Common", order = 1, color = { 190, 198, 210 } },
	{ name = "Uncommon", order = 2, color = { 96, 214, 120 } },
	{ name = "Rare", order = 3, color = { 70, 160, 255 } },
	{ name = "Epic", order = 4, color = { 176, 96, 255 } },
	{ name = "Legendary", order = 5, color = { 255, 190, 50 } },
	{ name = "Mythic", order = 6, color = { 255, 80, 110 } },
	{ name = "Secret", order = 7, color = { 40, 235, 225 } },
} :: { any }
Config.RarityByName = {} :: { [string]: { name: string, order: number, color: { number } } }
for _, r in Config.Rarities do
	Config.RarityByName[r.name] = r
end

-- Pet tiers: fuse FuseCount of a kind into the next tier.
Config.Tiers = {
	[0] = { mult = 1 },
	[1] = { mult = 3 }, -- Golden
	[2] = { mult = 8 }, -- Prism
}
Config.FuseCount = 5
Config.GoldenChance = 0.01 -- a capsule pet comes out Golden
Config.GoldenChancePass = 0.10

---------------------------------------------------------------------------
-- World layout (studs). Galaxies are separate floating stations on the X axis.
---------------------------------------------------------------------------
Config.ZoneSpacing = 900
Config.ZoneRadius = 96
Config.NodesPerZone = 12 -- regular planets
Config.ArenaCenter = { 0, 0, -760 }
Config.ArenaRadius = 58 -- inside = PvP on
Config.ArenaLobbyRadius = 84 -- platform edge; the ring outside the arena is safe

-- Galaxies. hp = Crust+Mantle+Core HP of a plain Rock planet. value = Stardust per HP mined.
-- gateHp = HP of the Gate Planet that blocks the way INTO this galaxy (it floats at the far
-- end of the previous one; damage = your mining power, progress is saved). hardness = index
-- of the first tool that mines here at full strength (weaker tools do Config.SoftDamage).
-- material = this galaxy's own drop, spent on the system that unlocks here (Config.Systems).
-- Gates, tool prices and the rebirth cost are timed with sim/pacing_sim.luau (free player);
-- tests/pacing_test.luau fails when a milestone leaves its window.
Config.Zones = {
	{ index = 1, id = "dawn", gateHp = 0, hp = 60, value = 1.0, crystal = 1, hardness = 1 },
	{ index = 2, id = "verdant", gateHp = 230000, hp = 11000, value = 1.5, crystal = 1, hardness = 4, material = "spores" },
	{ index = 3, id = "frost", gateHp = 2.6e+08, hp = 1.4e+07, value = 2.3, crystal = 2, hardness = 6, material = "cryo" },
	{ index = 4, id = "ember", gateHp = 1e+12, hp = 1.1e+11, value = 3.4, crystal = 2, hardness = 8, material = "embers" },
	{ index = 5, id = "storm", gateHp = 2.5e+16, hp = 3.3e+14, value = 5.0, crystal = 3, hardness = 10, material = "volt" },
	{ index = 6, id = "void", gateHp = 2.5e+20, hp = 3.1e+18, value = 7.5, crystal = 4, hardness = 12, material = "essence" },
} :: { any }
-- Planets on the outer ring are Dense: x DenseMult HP and ore.
Config.DenseMult = 10
Config.SoftDamage = 0.25 -- damage share when the tool is below the galaxy's hardness
Config.Materials = { "spores", "cryo", "embers", "volt", "essence" }
Config.MaterialZone = { spores = 2, cryo = 3, embers = 4, volt = 5, essence = 6 }
Config.GateCrystals = { 0, 25, 50, 100, 200, 400 } -- one-time reward for breaking the gate into galaxy i

-- Planet layers: share of the planet's HP, in the order they are mined.
Config.Layers = {
	{ id = "crust", share = 0.25, chunks = 1 },
	{ id = "mantle", share = 0.35, chunks = 1 },
	{ id = "core", share = 0.40, chunks = 2 },
} :: { any }

-- Planet kinds. weight = spawn weight for a regular node (luck multiplies every kind with
-- rare = true). buff = timed boost when the core breaks. perm = permanent stat that grows
-- with Mastery of this kind (levels at Config.MasteryThresholds).
Config.PlanetKinds = {
	{ id = "rock", weight = 56, hpMult = 1, valueMult = 1, size = 9, rare = false, perm = "damage", color = { 150, 140, 135 } },
	{ id = "fury", weight = 10, hpMult = 1.4, valueMult = 1.2, size = 10, rare = true, buff = "damage", perm = "damage", color = { 235, 70, 70 } },
	{ id = "zephyr", weight = 10, hpMult = 1.2, valueMult = 1.2, size = 9, rare = true, buff = "speed", perm = "speed", color = { 80, 210, 255 } },
	{ id = "clover", weight = 8, hpMult = 1.3, valueMult = 1.2, size = 9.5, rare = true, buff = "luck", perm = "luck", color = { 90, 225, 120 } },
	{ id = "aurum", weight = 10, hpMult = 1.6, valueMult = 2.0, size = 10.5, rare = true, buff = "stardust", perm = "stardust", color = { 255, 200, 60 } },
	{ id = "prism", weight = 6, hpMult = 2.0, valueMult = 1.5, size = 10, rare = true, crystals = 1, materials = 3, perm = "crystals", color = { 200, 120, 255 } },
	-- one per galaxy, in the middle; long respawn, lots of HP, Crystals and a random buff
	{ id = "titan", weight = 0, hpMult = 120, valueMult = 1.6, size = 24, rare = true, crystals = 5, materials = 15, buff = "random", perm = "damage", boss = true, color = { 120, 110, 255 } },
	-- appears in every galaxy for AnomalyDuration at the top of each UTC hour; one break per window
	{ id = "anomaly", weight = 0, hpMult = 12, valueMult = 4, size = 15, rare = true, crystals = 12, materials = 40, buff = "all", perm = "crystals", special = true, color = { 60, 240, 220 } },
	-- the wall between galaxies (HP from Config.Zones[next].gateHp, no drops, no cargo)
	{ id = "gate", weight = 0, hpMult = 1, valueMult = 0, size = 30, rare = false, perm = "damage", special = true, color = { 235, 235, 245 } },
} :: { any }
Config.PlanetKindById = {} :: { [string]: any }
Config.PlanetKindIndex = {} :: { [string]: number }
for i, k in Config.PlanetKinds do
	Config.PlanetKindById[k.id] = k
	Config.PlanetKindIndex[k.id] = i
end
Config.PlanetRespawn = 5 -- seconds
Config.TitanRespawn = 75
Config.NodeTitan = 0
Config.NodeAnomaly = 13
Config.NodeGate = 14
Config.AnomalyEvery = 3600
Config.AnomalyDuration = 900

-- Timed buffs (each break refreshes it to `duration`; a buff does not stack with itself).
Config.Buffs = {
	damage = { duration = 45, mult = 1.5 },
	speed = { duration = 45, mult = 1.35 }, -- walk speed and hits per second
	luck = { duration = 60, mult = 2 },
	stardust = { duration = 45, mult = 2 },
}
Config.BuffOrder = { "damage", "speed", "luck", "stardust" }

-- Mastery: planets of a kind broken -> level; each level = +MasteryBonus of the kind's perm stat.
Config.MasteryThresholds = { 5, 25, 100, 400, 1500, 5000 }
Config.MasteryBonus = 0.03
Config.MasteryCrystals = { 5, 10, 20, 40, 80, 160 } -- one-time Crystals per level reached
Config.MasteryKinds = { "rock", "fury", "zephyr", "clover", "aurum", "prism", "titan", "anomaly" }

-- Cargo: every broken layer is ore in your hold (chunks per layer in Config.Layers). Ore
-- turns into Stardust when it is sold: walk onto the Refinery pad (instant, +CargoHandBonus)
-- or let the Cargo Drone fly it (automatic when the hold is full; the trip takes
-- DroneSeconds, and mining stops if the hold fills up again before the drone is back).
Config.CargoBase = 24
Config.CargoHandBonus = 0.2
Config.DroneSeconds = 7
Config.DroneSecondsMin = 2
Config.RefineryRadius = 11

---------------------------------------------------------------------------
-- Mining
---------------------------------------------------------------------------
Config.BaseHitsPerSecond = 6 -- manual cap (server token bucket)
Config.HitBurst = 5
Config.BaseRange = 30 -- studs (horizontal) from the character to the planet
Config.BaseWalkSpeed = 18
Config.CritChance = 0.04
Config.CritMult = 3
-- Autos (first-class system, all server-driven so they keep working AFK):
--   mine    free for everyone at AutoMineRateFree hits/s (+AutoRate upgrade), x AutoMinePassMult
--           and +AutoMinePassRange studs with the Auto Miner pass; picks the nearest planet itself
--   sell    the Cargo Drone sells a full hold by itself
--   open    keeps opening the chosen capsule while you stay in its galaxy (Fast Open pass = faster)
--   best    re-equips the strongest pets whenever the inventory changes
--   fuse    fuses FuseCount of a kind into Golden / Prism as soon as possible
--   rebirth rebirths as soon as it is affordable
--   upgrade buys the best affordable tool and Power levels
--   delete  rarities listed in AutoDeleteRarities can be auto-deleted on open
Config.AutoMineRateFree = 2
Config.AutoMinePassMult = 3
Config.AutoMinePassRange = 18
Config.AutoTick = 0.25 -- seconds; one server loop drives every auto for every player
Config.AutoDeleteRarities = { "Common", "Uncommon", "Rare" }
Config.AutoDefaults = { mine = false, sell = true, best = true, fuse = false, rebirth = false, upgrade = false }
Config.AutoKeys = { "mine", "sell", "best", "fuse", "rebirth", "upgrade" }
Config.FriendBoostPer = 0.1
Config.FriendBoostMax = 0.5
Config.PremiumBoost = 0.1 -- Roblox Plus / Premium members: +10% Stardust

-- Mining tools. kind picks the model, the swing and the effect (pick = swing + chips,
-- drill = sparks, laser = beam). power = damage per hit before multipliers.
Config.Tools = {
	{ id = "pick_rusty", kind = "pick", zone = 1, power = 1, cost = 0, color = { 160, 120, 90 } },
	{ id = "pick_iron", kind = "pick", zone = 1, power = 3, cost = 220, color = { 190, 200, 215 } },
	{ id = "pick_titanium", kind = "pick", zone = 1, power = 9, cost = 2600, color = { 110, 200, 255 } },
	{ id = "drill_spark", kind = "drill", zone = 2, power = 26, cost = 170000, color = { 255, 190, 60 } },
	{ id = "drill_twin", kind = "drill", zone = 2, power = 80, cost = 1.8e+07, color = { 110, 230, 140 } },
	{ id = "drill_plasma", kind = "drill", zone = 3, power = 240, cost = 3.2e+08, color = { 90, 170, 255 } },
	{ id = "drill_quake", kind = "drill", zone = 3, power = 760, cost = 5e+10, color = { 200, 120, 255 } },
	{ id = "laser_ruby", kind = "laser", zone = 4, power = 2400, cost = 3.7e+12, color = { 255, 70, 90 } },
	{ id = "laser_ion", kind = "laser", zone = 4, power = 7600, cost = 4.1e+13, color = { 80, 235, 255 } },
	{ id = "laser_nova", kind = "laser", zone = 5, power = 24000, cost = 1.7e+16, color = { 255, 220, 90 } },
	{ id = "laser_quasar", kind = "laser", zone = 5, power = 78000, cost = 1.8e+17, color = { 255, 120, 230 } },
	{ id = "laser_singularity", kind = "laser", zone = 6, power = 250000, cost = 2.3e+20, color = { 170, 110, 255 } },
} :: { any }
Config.ToolById = {} :: { [string]: any }
Config.ToolIndex = {} :: { [string]: number }
for i, t in Config.Tools do
	Config.ToolById[t.id] = t
	Config.ToolIndex[t.id] = i
end

-- Upgrades. currency = "stardust" | "crystals" | a material id. reset = lost on rebirth.
-- compound = each level multiplies (x(1 + per) per level) instead of adding.
-- system = the tab it lives in (Config.Systems).
Config.Upgrades = {
	{ id = "Power", system = "stats", currency = "stardust", base = 60, growth = 1.18, max = 400, per = 0.06, compound = true, reset = true },
	{ id = "Cargo", system = "stats", currency = "stardust", base = 200, growth = 1.9, max = 20, per = 12, reset = false },
	{ id = "HitSpeed", system = "stats", currency = "stardust", base = 500, growth = 2.6, max = 12, per = 0.5, reset = false },
	{ id = "MoveSpeed", system = "stats", currency = "stardust", base = 350, growth = 2.4, max = 8, per = 1.5, reset = false },
	{ id = "Range", system = "stats", currency = "stardust", base = 1500, growth = 3.2, max = 6, per = 2, reset = false },
	{ id = "Luck", system = "lab", currency = "crystals", base = 20, growth = 1.5, max = 15, per = 0.1, reset = false },
	{ id = "Magnet", system = "lab", currency = "crystals", base = 15, growth = 1.45, max = 20, per = 0.1, reset = false },
	{ id = "Crit", system = "lab", currency = "crystals", base = 25, growth = 1.5, max = 10, per = 0.02, reset = false },
	{ id = "AutoRate", system = "lab", currency = "crystals", base = 30, growth = 1.7, max = 8, per = 0.5, reset = false },
	{ id = "PetSlots", system = "lab", currency = "crystals", base = 60, growth = 3, max = 3, per = 1, reset = false },
	-- Frost Halo: temper the tool slot itself (+10% damage per level, survives rebirth)
	{ id = "Temper", system = "temper", currency = "cryo", base = 10, growth = 1.16, max = 60, per = 0.1, reset = false },
	-- Storm Reach: Overcharge. Hits build charge; full charge = damage x (OverchargeBase + per x level)
	{ id = "Capacitor", system = "overcharge", currency = "volt", base = 12, growth = 1.45, max = 12, per = 0.25, reset = false },
	{ id = "Insulation", system = "overcharge", currency = "volt", base = 20, growth = 1.8, max = 6, per = 0.5, reset = false }, -- extra seconds before the charge decays
	-- Void Crown: the Constellation
	{ id = "StarPower", system = "constellation", currency = "essence", base = 15, growth = 1.6, max = 12, per = 0.4, reset = false },
	{ id = "StarFortune", system = "constellation", currency = "essence", base = 15, growth = 1.6, max = 12, per = 0.2, reset = false },
	{ id = "StarLuck", system = "constellation", currency = "essence", base = 25, growth = 1.9, max = 6, per = 0.1, reset = false },
	{ id = "StarDrone", system = "constellation", currency = "essence", base = 40, growth = 2.2, max = 4, per = 1, reset = false }, -- seconds off the drone trip
	{ id = "StarSlot", system = "constellation", currency = "essence", base = 600, growth = 1, max = 1, per = 1, reset = false },
} :: { any }
Config.UpgradeById = {} :: { [string]: any }
for _, u in Config.Upgrades do
	Config.UpgradeById[u.id] = u
end

-- One new multiplier system per galaxy (each opens when its galaxy does).
Config.Systems = {
	{ id = "tools", zone = 1, icon = "⛏️" },
	{ id = "stats", zone = 1, icon = "📈" },
	{ id = "lab", zone = 1, icon = "💎" },
	{ id = "relics", zone = 2, icon = "🗿", material = "spores" },
	{ id = "temper", zone = 3, icon = "❄️", material = "cryo" },
	{ id = "traits", zone = 4, icon = "🔥", material = "embers" }, -- lives in the Pets window
	{ id = "overcharge", zone = 5, icon = "⚡", material = "volt" },
	{ id = "constellation", zone = 6, icon = "🌌", material = "essence" },
} :: { any }
Config.SystemById = {} :: { [string]: any }
for _, sy in Config.Systems do
	Config.SystemById[sy.id] = sy
end

-- Verdant Nebula: Relics. One relic per stat; a roll (RelicCost Spores) lands on a random
-- stat at a random grade. A higher grade replaces the relic; anything else becomes 1 Relic
-- Dust for that stat, and RelicDustPerGrade dust raises its grade by one. Spores cannot be
-- bought, so this is not a paid random item; the odds are shown anyway.
Config.RelicStats = { "damage", "speed", "luck", "stardust", "crystals" }
Config.RelicCost = 10
Config.RelicDustPerGrade = 8
Config.RelicGrades = {
	{ rarity = "Common", chance = 50, bonus = 0.05 },
	{ rarity = "Uncommon", chance = 28, bonus = 0.10 },
	{ rarity = "Rare", chance = 15, bonus = 0.20 },
	{ rarity = "Epic", chance = 5.5, bonus = 0.35 },
	{ rarity = "Legendary", chance = 1.4, bonus = 0.60 },
	{ rarity = "Mythic", chance = 0.1, bonus = 1.00 },
} :: { any }

-- Ember Forge: pet Traits. A roll (TraitCost Embers) on a pet; the pet keeps the better
-- trait and a roll that is not better refunds TraitRefund Embers.
Config.TraitCost = 8
Config.TraitRefund = 3
Config.Traits = {
	{ id = "sturdy", chance = 40, mult = 1.1, rarity = "Common" },
	{ id = "keen", chance = 30, mult = 1.25, rarity = "Uncommon" },
	{ id = "fierce", chance = 18, mult = 1.5, rarity = "Rare" },
	{ id = "radiant", chance = 9, mult = 2, rarity = "Epic" },
	{ id = "titanic", chance = 2.7, mult = 3, rarity = "Legendary" },
	{ id = "cosmic", chance = 0.3, mult = 5, rarity = "Mythic" },
} :: { any }
Config.TraitIndex = {} :: { [string]: number }
for i, t in Config.Traits do
	Config.TraitIndex[t.id] = i
end

-- Storm Reach: Overcharge
Config.OverchargeHits = 80 -- hits to fill the meter
Config.OverchargeBase = 1.5 -- damage multiplier at full charge with Capacitor level 0
Config.OverchargeDecay = 2.5 -- seconds without a hit before the charge starts to drop
Config.OverchargeDropPerSecond = 40

-- Rebirth: resets Stardust, the cargo, the tool and the Power upgrade; keeps galaxies, pets,
-- Crystals, materials, every other upgrade and Mastery.
Config.RebirthBaseCost = 1e12
Config.RebirthCostGrowth = 400
Config.RebirthMult = 0.5 -- +50% damage and Stardust per rebirth
Config.RebirthCrystalsBase = 40
Config.RebirthCrystalsPer = 20

---------------------------------------------------------------------------
-- Pets ("universal" companions). power = damage multiplier added while equipped
-- (damage x (1 + sum of pet power)). scale = exclusive pets: x best regular pet of the
-- owner's top galaxy. look drives PetModel.
---------------------------------------------------------------------------
Config.BaseEquipSlots = 3
Config.MaxInventory = 120
Config.StartingPet = "pebblepup"

Config.Pets = {
	-- Dawn Belt
	{ id = "pebblepup", rarity = "Common", zone = 1, power = 0.2, look = { body = "quad", color = { 176, 150, 128 }, accent = { 250, 236, 214 }, ears = "flop", tail = "stub", spots = true } },
	{ id = "dustbunny", rarity = "Uncommon", zone = 1, power = 0.45, look = { body = "quad", color = { 232, 220, 205 }, accent = { 255, 170, 190 }, ears = "long", tail = "puff" } },
	{ id = "cometcat", rarity = "Rare", zone = 1, power = 1.0, look = { body = "quad", color = { 90, 120, 220 }, accent = { 255, 235, 140 }, ears = "point", tail = "comet", glow = true } },
	{ id = "roverbot", rarity = "Epic", zone = 1, power = 2.6, look = { body = "bot", color = { 235, 240, 245 }, accent = { 255, 150, 40 }, antenna = true, wheels = true } },
	{ id = "solarfox", rarity = "Legendary", zone = 1, power = 8, look = { body = "quad", color = { 255, 150, 50 }, accent = { 255, 240, 170 }, ears = "point", tail = "flame", glow = true } },
	-- Verdant Nebula
	{ id = "mossslime", rarity = "Common", zone = 2, power = 1.6, look = { body = "slime", color = { 110, 200, 110 }, accent = { 60, 140, 80 }, sprout = true } },
	{ id = "sporemoth", rarity = "Uncommon", zone = 2, power = 3.4, look = { body = "orb", color = { 230, 215, 170 }, accent = { 120, 220, 170 }, wings = "moth", antenna = true, fly = true } },
	{ id = "vinelizard", rarity = "Rare", zone = 2, power = 7.5, look = { body = "quad", color = { 70, 170, 110 }, accent = { 220, 250, 120 }, ears = "fin", tail = "long", spikes = true } },
	{ id = "nebulaowl", rarity = "Epic", zone = 2, power = 19, look = { body = "bird", color = { 96, 80, 190 }, accent = { 120, 240, 220 }, wings = "feather", ears = "tuft", fly = true, glow = true } },
	{ id = "emeraldstag", rarity = "Legendary", zone = 2, power = 58, look = { body = "quad", color = { 40, 170, 120 }, accent = { 210, 255, 200 }, ears = "point", tail = "stub", horns = "antler", glow = true } },
	-- Frost Halo
	{ id = "icemite", rarity = "Common", zone = 3, power = 12, look = { body = "orb", color = { 190, 230, 255 }, accent = { 110, 170, 240 }, spikes = true, legs = true } },
	{ id = "snowseal", rarity = "Uncommon", zone = 3, power = 26, look = { body = "slime", color = { 240, 246, 255 }, accent = { 150, 190, 230 }, tail = "fin", whiskers = true } },
	{ id = "glaciercub", rarity = "Rare", zone = 3, power = 56, look = { body = "quad", color = { 215, 235, 250 }, accent = { 120, 200, 255 }, ears = "round", tail = "stub", spikes = true } },
	{ id = "aurorawisp", rarity = "Epic", zone = 3, power = 140, look = { body = "orb", color = { 130, 255, 210 }, accent = { 190, 130, 255 }, tail = "comet", fly = true, glow = true, neon = true } },
	{ id = "frostwyrm", rarity = "Legendary", zone = 3, power = 430, look = { body = "dragon", color = { 120, 190, 255 }, accent = { 235, 250, 255 }, wings = "bat", horns = "spike", tail = "long", fly = true, glow = true } },
	-- Ember Forge
	{ id = "cindernewt", rarity = "Uncommon", zone = 4, power = 90, look = { body = "quad", color = { 230, 110, 50 }, accent = { 255, 220, 90 }, ears = "fin", tail = "flame" } },
	{ id = "magmacrab", rarity = "Rare", zone = 4, power = 200, look = { body = "bot", color = { 190, 60, 40 }, accent = { 255, 170, 50 }, claws = true, legs = true, neonAccent = true } },
	{ id = "ashhound", rarity = "Epic", zone = 4, power = 440, look = { body = "quad", color = { 70, 64, 72 }, accent = { 255, 120, 40 }, ears = "point", tail = "flame", spikes = true, glow = true } },
	{ id = "forgegolem", rarity = "Legendary", zone = 4, power = 1200, look = { body = "bot", color = { 96, 84, 80 }, accent = { 255, 140, 40 }, arms = true, horns = "spike", neonAccent = true, glow = true } },
	{ id = "infernodrake", rarity = "Mythic", zone = 4, power = 3800, look = { body = "dragon", color = { 200, 40, 30 }, accent = { 255, 200, 70 }, wings = "bat", horns = "spike", tail = "flame", fly = true, glow = true } },
	-- Storm Reach
	{ id = "sparkmite", rarity = "Uncommon", zone = 5, power = 700, look = { body = "orb", color = { 255, 230, 90 }, accent = { 120, 110, 220 }, legs = true, antenna = true, neonAccent = true } },
	{ id = "thunderram", rarity = "Rare", zone = 5, power = 1500, look = { body = "quad", color = { 225, 225, 240 }, accent = { 255, 215, 70 }, ears = "round", tail = "puff", horns = "ram" } },
	{ id = "cloudray", rarity = "Epic", zone = 5, power = 3300, look = { body = "orb", color = { 150, 160, 235 }, accent = { 240, 245, 255 }, wings = "ray", tail = "long", fly = true } },
	{ id = "voltdrone", rarity = "Legendary", zone = 5, power = 9000, look = { body = "bot", color = { 60, 66, 90 }, accent = { 120, 240, 255 }, antenna = true, rotor = true, fly = true, neonAccent = true, glow = true } },
	{ id = "tempestgriffin", rarity = "Mythic", zone = 5, power = 28000, look = { body = "bird", color = { 245, 240, 225 }, accent = { 255, 210, 60 }, wings = "feather", ears = "tuft", tail = "long", fly = true, glow = true } },
	-- Void Crown
	{ id = "voidjelly", rarity = "Uncommon", zone = 6, power = 5200, look = { body = "slime", color = { 150, 90, 230 }, accent = { 255, 140, 230 }, tentacles = true, fly = true, neon = true } },
	{ id = "riftbat", rarity = "Rare", zone = 6, power = 11000, look = { body = "orb", color = { 60, 40, 90 }, accent = { 255, 90, 170 }, wings = "bat", ears = "point", fly = true } },
	{ id = "stareater", rarity = "Epic", zone = 6, power = 25000, look = { body = "quad", color = { 30, 30, 60 }, accent = { 120, 255, 240 }, ears = "fin", tail = "comet", spikes = true, spots = true, glow = true } },
	{ id = "quasarsphinx", rarity = "Legendary", zone = 6, power = 68000, look = { body = "quad", color = { 235, 200, 110 }, accent = { 90, 60, 200 }, ears = "point", tail = "long", wings = "feather", horns = "crown", fly = true, glow = true } },
	{ id = "nulldragon", rarity = "Mythic", zone = 6, power = 210000, look = { body = "dragon", color = { 28, 24, 48 }, accent = { 200, 90, 255 }, wings = "bat", horns = "crown", tail = "comet", fly = true, glow = true, neonAccent = true } },
	-- exclusive (Quantum Capsule / gifts): scale with the owner's progress
	{ id = "photonpixie", rarity = "Legendary", zone = 0, power = 0, scale = 1.5, look = { body = "orb", color = { 255, 245, 170 }, accent = { 255, 150, 220 }, wings = "moth", antenna = true, fly = true, glow = true, neon = true } },
	{ id = "warptiger", rarity = "Mythic", zone = 0, power = 0, scale = 2.5, look = { body = "quad", color = { 70, 220, 255 }, accent = { 30, 30, 70 }, ears = "round", tail = "long", spots = true, glow = true } },
	{ id = "celestialtitan", rarity = "Mythic", zone = 0, power = 0, scale = 5, look = { body = "bot", color = { 250, 250, 255 }, accent = { 255, 200, 60 }, arms = true, horns = "crown", wings = "feather", fly = true, glow = true, neonAccent = true } },
	{ id = "galaxyguardian", rarity = "Secret", zone = 0, power = 0, scale = 10, look = { body = "dragon", color = { 20, 60, 90 }, accent = { 40, 235, 225 }, wings = "feather", horns = "crown", tail = "comet", fly = true, glow = true, neonAccent = true } },
	{ id = "crewbeacon", rarity = "Epic", zone = 0, power = 0, scale = 1.2, look = { body = "bot", color = { 255, 120, 60 }, accent = { 255, 255, 255 }, antenna = true, rotor = true, fly = true, neonAccent = true } },
} :: { any }
Config.SecretPet = "galaxyguardian"
Config.SecretChance = 0.001 -- percent (1 in 100,000), inside every galaxy capsule
Config.GroupGiftPet = "crewbeacon"

-- Capsules. chances are percentages that sum to 100 (the Secret is carved out at runtime so
-- the table the player sees always adds up to exactly 100%).
Config.Capsules = {
	{ id = "dawn", zone = 1, price = 120, pets = { { "pebblepup", 55 }, { "dustbunny", 30 }, { "cometcat", 12 }, { "roverbot", 2.9 }, { "solarfox", 0.1 } } },
	{ id = "verdant", zone = 2, price = 66000, pets = { { "mossslime", 55 }, { "sporemoth", 30 }, { "vinelizard", 12 }, { "nebulaowl", 2.9 }, { "emeraldstag", 0.1 } } },
	{ id = "frost", zone = 3, price = 1.3e+08, pets = { { "icemite", 55 }, { "snowseal", 30 }, { "glaciercub", 12 }, { "aurorawisp", 2.9 }, { "frostwyrm", 0.1 } } },
	{ id = "ember", zone = 4, price = 1.5e+12, pets = { { "cindernewt", 58 }, { "magmacrab", 30 }, { "ashhound", 11 }, { "forgegolem", 0.98 }, { "infernodrake", 0.02 } } },
	{ id = "storm", zone = 5, price = 6.6e+15, pets = { { "sparkmite", 58 }, { "thunderram", 30 }, { "cloudray", 11 }, { "voltdrone", 0.98 }, { "tempestgriffin", 0.02 } } },
	{ id = "void", zone = 6, price = 9.3e+19, pets = { { "voidjelly", 58 }, { "riftbat", 30 }, { "stareater", 11 }, { "quasarsphinx", 0.98 }, { "nulldragon", 0.02 } } },
	-- Robux only (products QuantumCapsule1/3) or earned (gifts, quests); sits in the Dawn Belt plaza
	{ id = "quantum", zone = 1, price = 0, exclusive = true, pets = { { "photonpixie", 70 }, { "warptiger", 29 }, { "celestialtitan", 1 } } },
} :: { any }
Config.OpenCooldown = 2.2
Config.OpenCooldownFast = 0.9 -- Fast Open pass
Config.OpenDistance = 18

---------------------------------------------------------------------------
-- PvP arena
---------------------------------------------------------------------------
Config.Pvp = {
	maxHp = 100,
	baseDamage = 14,
	ratioExponent = 0.2, -- damage x (attackerPower / defenderPower) ^ exponent
	minRatio = 0.6,
	maxRatio = 1.7,
	cooldown = 0.45, -- seconds between zaps
	range = 26,
	regenDelay = 5,
	regenPerSecond = 8,
	spawnProtection = 4, -- seconds of immunity after entering the arena
	rookieSeconds = 600, -- play time under this = Rookie Shield (no damage from players until you attack one)
	koPoints = 10,
	botPoints = 3,
	koStardustSeconds = 45, -- reward = this many seconds of your mining income
	botStardustSeconds = 12,
	bots = 2,
	botHp = 80,
	botDamage = 7,
	botCooldown = 1.3,
	botRespawn = 8,
	botSpeed = 11,
}

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
-- Reward kinds: stardust / crystals (flat), stardustMin (minutes of your mining income),
-- luck (minutes of the Luck buff), boost (minutes of x2 Stardust), capsule (Quantum Capsule
-- opens), material (amount of your best galaxy's material).
Config.DailyCooldown = 20 * 3600
Config.DailyBreak = 48 * 3600
Config.DailyRewards = {
	{ kind = "stardustMin", amount = 5 },
	{ kind = "crystals", amount = 20 },
	{ kind = "luck", amount = 15 },
	{ kind = "stardustMin", amount = 15 },
	{ kind = "crystals", amount = 50 },
	{ kind = "boost", amount = 20 },
	{ kind = "capsule", amount = 1 },
} :: { any }
Config.Gifts = {
	{ minutes = 3, reward = { kind = "stardustMin", amount = 3 } },
	{ minutes = 7, reward = { kind = "crystals", amount = 10 } },
	{ minutes = 12, reward = { kind = "luck", amount = 10 } },
	{ minutes = 18, reward = { kind = "stardustMin", amount = 10 } },
	{ minutes = 25, reward = { kind = "crystals", amount = 25 } },
	{ minutes = 35, reward = { kind = "boost", amount = 15 } },
	{ minutes = 45, reward = { kind = "crystals", amount = 40 } },
	{ minutes = 60, reward = { kind = "capsule", amount = 1 } },
} :: { any }
Config.Codes = {
	LAUNCH = { kind = "crystals", amount = 50 },
	CRACK = { kind = "stardustMin", amount = 10 },
	LUCKY = { kind = "luck", amount = 15 },
	PLANETS = { kind = "boost", amount = 10 },
	TITAN = { kind = "crystals", amount = 25 },
} :: { [string]: { kind: string, amount: number } }
Config.IncomeHitsPerSecond = 5 -- "minutes of income" rewards assume this many hits per second

-- Pet index: finishing a galaxy's page = Crystals + a permanent +10% damage.
Config.IndexRewardCrystals = { 50, 100, 200, 400, 800, 1600 }
Config.IndexBoostPerZone = 0.1

-- Daily quests: QuestsPerDay per UTC day, targets by best galaxy.
Config.QuestsPerDay = 3
Config.QuestPool = {
	{ kind = "planets", targetByZone = { 40, 60, 80, 100, 120, 150 }, crystals = 20 },
	{ kind = "hits", targetByZone = { 1500, 2500, 3500, 4500, 5500, 7000 }, crystals = 20 },
	{ kind = "capsules", targetByZone = { 15, 25, 35, 45, 60, 75 }, crystals = 25 },
	{ kind = "buffs", targetByZone = { 8, 10, 12, 14, 16, 20 }, crystals = 25 },
	{ kind = "titan", targetByZone = { 1, 2, 2, 3, 3, 4 }, crystals = 40 },
	{ kind = "fuse", targetByZone = { 1, 1, 2, 2, 3, 3 }, crystals = 40 },
	{ kind = "arena", targetByZone = { 2, 3, 3, 4, 4, 5 }, crystals = 35 },
	{ kind = "sell", targetByZone = { 10, 12, 14, 16, 18, 20 }, crystals = 20 },
	{ kind = "minutes", targetByZone = { 15, 15, 20, 20, 25, 25 }, crystals = 30 },
} :: { any }
Config.QuestBonus = { kind = "capsule", amount = 1 }

-- Live events. recurring: active while (now - offset) % every < duration (UTC seconds).
Config.LiveEventDefs = {
	MeteorShower = { stardustMult = 2 },
	LuckyNebula = { luckMult = 2 },
	CrystalWeekend = { crystalMult = 2 },
	StarSurge = { stardustMult = 2, crystalMult = 1.5 },
} :: { [string]: { stardustMult: number?, luckMult: number?, crystalMult: number? } }
Config.LiveEvents = {
	recurring = {
		{ id = "MeteorShower", every = 3 * 3600, offset = 1800, duration = 15 * 60 },
		{ id = "LuckyNebula", every = 3 * 3600, offset = 7200, duration = 15 * 60 },
		-- Star Surge: a fixed weekly date, 45 min, for everybody on every server, twice a week.
		-- The unix epoch is a Thursday 00:00 UTC, so Tue 18:00 UTC = 5 d 18 h and Sat 18:00 UTC = 2 d 18 h.
		{ id = "StarSurge", every = 7 * 86400, offset = 5 * 86400 + 18 * 3600, duration = 45 * 60 },
		{ id = "StarSurge", every = 7 * 86400, offset = 2 * 86400 + 18 * 3600, duration = 45 * 60 },
	},
	weekly = {
		{ id = "CrystalWeekend", fromWday = 7, toWday = 1 }, -- Saturday + Sunday (UTC)
	},
}
Config.LiveEventMaxMinutes = 60

-- Referrals
Config.ReferralMinPlaySeconds = 600
Config.ReferralInviteeGift = { kind = "crystals", amount = 50 }
Config.ReferralInviterGift = { kind = "capsule", amount = 1 }
Config.ReferralLifetimeCap = 25
Config.ReferralLinkSeconds = 7 * 86400
Config.NotifAskInterval = 7 * 86400

-- Offline mining: pets keep working while you are away.
Config.OfflineHitsPerSecond = 0.5
Config.OfflineCapHours = 6
Config.OfflineCapHoursVIP = 12
Config.OfflineMinSeconds = 300

-- Tutorial (first minute). The step is stored in the profile; each step pays a reward.
Config.Tutorial = {
	{ id = "mine", reward = { kind = "stardust", amount = 40 } }, -- break a planet's crust
	{ id = "core", reward = { kind = "stardust", amount = 80 } }, -- crack a core
	{ id = "sell", reward = { kind = "stardust", amount = 120 } }, -- sell cargo at the Refinery
	{ id = "capsule", reward = { kind = "crystals", amount = 10 } }, -- open a capsule
	{ id = "tool", reward = { kind = "crystals", amount = 15 } }, -- buy a better tool
	{ id = "auto", reward = { kind = "crystals", amount = 25 } }, -- switch Auto Mine on
} :: { any }

---------------------------------------------------------------------------
-- Monetization. Create these in Creator Dashboard and paste the IDs (0 = hidden).
-- random = true marks paid random items under Roblox's policy: a random outcome, a currency
-- that buys capsules, or a chance modifier. They are hidden and refused for players whose
-- PolicyService says ArePaidRandomItemsRestricted (those players still earn everything by playing).
---------------------------------------------------------------------------
Config.Passes = {
	{ key = "AutoMiner", id = 0, price = 175, icon = "🤖" },
	{ key = "DoubleDamage", id = 0, price = 349, icon = "💥" },
	{ key = "DoubleStardust", id = 0, price = 349, icon = "✨" },
	{ key = "VIP", id = 0, price = 299, icon = "👑" },
	{ key = "InstantSell", id = 0, price = 199, icon = "🚀" },
	{ key = "PetSlots", id = 0, price = 249, icon = "🐾" },
	{ key = "PetSlots2", id = 0, price = 649, icon = "🐾" },
	{ key = "TripleOpen", id = 0, price = 199, icon = "🧬" },
	{ key = "OpenEight", id = 0, price = 699, icon = "🧬" },
	{ key = "FastOpen", id = 0, price = 99, icon = "⏩" },
	{ key = "Sprint", id = 0, price = 49, icon = "👟" },
	{ key = "Lucky", id = 0, price = 249, icon = "🍀", random = true },
	{ key = "SuperLucky", id = 0, price = 699, icon = "🌈", random = true },
	{ key = "GoldenCapsules", id = 0, price = 599, icon = "🌟", random = true },
} :: { any }
Config.PassByKey = {} :: { [string]: any }
for _, p in Config.Passes do
	Config.PassByKey[p.key] = p
end
Config.VipDamage = 1.5
Config.VipCargo = 0.5
Config.LuckyPassLuck = 0.5
Config.SuperLuckyPassLuck = 1.0
Config.PetSlotsPass = 2
Config.PetSlots2Pass = 4 -- the second tier, on top of the first (+6 in total with both)
-- Capsules per open: 1 is free; 3 needs TripleOpen, 8 needs OpenEight (Stardust cost x count).
Config.OpenCounts = { 1, 3, 8 }
Config.OpenPassByCount = { [3] = "TripleOpen", [8] = "OpenEight" } :: { [number]: string }
Config.SprintPassSpeed = 6

Config.Products = {
	{ key = "StardustSmall", id = 0, price = 49, kind = "stardustMin", amount = 30, icon = "✨", random = true },
	{ key = "StardustMedium", id = 0, price = 199, kind = "stardustMin", amount = 180, icon = "✨", random = true },
	{ key = "StardustLarge", id = 0, price = 599, kind = "stardustMin", amount = 720, icon = "✨", random = true },
	{ key = "CrystalsSmall", id = 0, price = 49, kind = "crystals", amount = 100, icon = "💎" },
	{ key = "CrystalsMedium", id = 0, price = 249, kind = "crystals", amount = 600, icon = "💎" },
	{ key = "CrystalsLarge", id = 0, price = 499, kind = "crystals", amount = 1400, icon = "💎" },
	{ key = "CrystalsHuge", id = 0, price = 999, kind = "crystals", amount = 3200, icon = "💎" },
	{ key = "LuckBoost", id = 0, price = 99, kind = "luck", amount = 30, icon = "🍀", random = true },
	{ key = "QuantumCapsule1", id = 0, price = 149, kind = "capsule", amount = 1, icon = "🔮", random = true },
	{ key = "QuantumCapsule3", id = 0, price = 399, kind = "capsule", amount = 3, icon = "🔮", random = true },
	{ key = "StarterPack", id = 0, price = 99, kind = "starter", amount = 1, icon = "🎁", hidden = true },
} :: { any }
Config.ProductByKey = {} :: { [string]: any }
for _, p in Config.Products do
	Config.ProductByKey[p.key] = p
end
-- Starter Pack: fixed contents (no random item and no luck, so it is not a paid random
-- item), first 24 h only.
-- fullPrice (the crossed-out "list price") is what the same content costs in this shop: the
-- Crystals at the small-pack rate plus one Quantum Capsule (the only other paid way to that
-- pet). The 30 min boost is counted as free. Computed so it can never drift from the prices.
Config.StarterPack = { windowSeconds = 24 * 3600, fullPrice = 0, crystals = 150, boostMinutes = 30, pet = "photonpixie" }
do
	local small, quantum = Config.ProductByKey.CrystalsSmall, Config.ProductByKey.QuantumCapsule1
	Config.StarterPack.fullPrice = math.ceil(Config.StarterPack.crystals * small.price / small.amount) + quantum.price
end
-- Rewarded video placements (dev product ids; 0 = hidden)
Config.AdProducts = { AdBoost = 0, AdOffline = 0 }
Config.AdDailyCap = 5
Config.AdBoostMinutes = 15

return Config
