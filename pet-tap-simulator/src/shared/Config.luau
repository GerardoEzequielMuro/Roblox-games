--!strict
-- Tap Pets Simulator: every tunable number and every piece of content lives here.
-- PURE DATA: no Roblox APIs (colors are {r,g,b} arrays, materials are Enum.Material names)
-- so the economy simulation in sim/ can require this file with the standalone luau.exe.

local Config = {}

Config.GameName = "Tap Pets Simulator"
Config.DataStoreName = "TapPets_Profiles_v1"
Config.LeaderboardTapsStore = "TapPets_TotalTaps_v1"
Config.LeaderboardRebirthStore = "TapPets_Rebirths_v1"
Config.AutosaveInterval = 90
Config.LeaderboardUpdateInterval = 60

-- Studio convenience: when true AND running in Studio, every pass is treated as owned.
Config.StudioGrantAllPasses = false

---------------------------------------------------------------------------
-- Tapping
---------------------------------------------------------------------------
Config.BaseTap = 1
Config.MaxTapsPerSecond = 12 -- manual taps accepted per second (autoclicker cap)
Config.TapBurst = 6 -- extra taps allowed in a burst (network jitter)
Config.TapSendInterval = 0.25 -- client batches taps this often
Config.AutoTapRate = 5 -- taps/sec from the Auto Tap pass (in addition to manual)
-- Free Auto Tap: everyone gets this many taps/sec, but only while idle (no manual tap for
-- AutoTapIdleSeconds). Same rate as offline earnings, so active play is never slower and the
-- economy curve of an active player is unchanged. The "AutoTap" gem upgrade adds to it.
Config.AutoTapFreeRate = 1
Config.AutoTapIdleSeconds = 2
-- Auto Hatch is free at this pace (x1); the Auto Hatch pass hatches at HatchCooldown and x3.
Config.AutoHatchFreeCooldown = 4.5
-- Auto Rebirth unlocks after this many manual rebirths.
Config.AutoRebirthMinRebirths = 1

---------------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------------
export type Rarity = { name: string, order: number, color: { number }, broadcast: boolean }

Config.Rarities = {
	{ name = "Common", order = 1, color = { 200, 200, 210 }, broadcast = false },
	{ name = "Uncommon", order = 2, color = { 95, 210, 95 }, broadcast = false },
	{ name = "Rare", order = 3, color = { 70, 155, 255 }, broadcast = false },
	{ name = "Epic", order = 4, color = { 175, 95, 255 }, broadcast = false },
	{ name = "Legendary", order = 5, color = { 255, 190, 40 }, broadcast = true },
	{ name = "Mythic", order = 6, color = { 255, 70, 120 }, broadcast = true },
	{ name = "Secret", order = 7, color = { 20, 20, 30 }, broadcast = true },
} :: { Rarity }

Config.RarityByName = {} :: { [string]: Rarity }
for _, r in Config.Rarities do
	Config.RarityByName[r.name] = r
end

-- Luck multiplies the weight of every entry whose rarity order is >= this.
Config.LuckAffectsFromOrder = 3 -- Rare and above

---------------------------------------------------------------------------
-- Pet tiers (crafting)
---------------------------------------------------------------------------
export type Tier = { index: number, name: string, mult: number }
Config.Tiers = {
	[0] = { index = 0, name = "Normal", mult = 1 },
	[1] = { index = 1, name = "Golden", mult = 3 },
	[2] = { index = 2, name = "Rainbow", mult = 8 },
} :: { [number]: Tier }
Config.CraftCost = 5 -- pets of the same id+tier needed to craft the next tier
Config.BaseGoldenHatchChance = 0.01 -- 1% of hatches come out Golden
Config.MagicEggsGoldenChance = 0.10 -- with the Magic Eggs pass

-- Traits: a grade rolled onto one pet, multiplying that pet's power. Rolls cost Trait Dice,
-- a currency that is ONLY earned by playing (rebirths, daily quests, index pages) and is
-- never sold, so a trait roll is not a paid random item. Every roll gives a grade.
-- chance values are percentages and must sum to 100.
export type TraitGrade = { name: string, mult: number, chance: number, color: { number } }
Config.TraitGrades = {
	{ name = "D", mult = 1.05, chance = 45, color = { 170, 170, 185 } },
	{ name = "C", mult = 1.10, chance = 30, color = { 95, 210, 95 } },
	{ name = "B", mult = 1.20, chance = 17, color = { 70, 155, 255 } },
	{ name = "A", mult = 1.35, chance = 7, color = { 175, 95, 255 } },
	{ name = "S", mult = 1.60, chance = 1, color = { 255, 190, 40 } },
} :: { TraitGrade }
Config.TraitRollCost = 1 -- Trait Dice per roll
Config.TraitDice = { rebirth = 3, quest = 1, questBonus = 3, index = 5, start = 2 }

Config.BaseEquipSlots = 3
Config.MaxInventory = 150
Config.StartingPet = "dog"

---------------------------------------------------------------------------
-- Pets. power = flat taps added to every tap (before multipliers).
-- Visual fields drive PetModel.build.
---------------------------------------------------------------------------
export type Pet = {
	id: string,
	name: string,
	rarity: string,
	power: number,
	body: string, -- "ball" | "block" | "tall"
	color: { number },
	accent: { number },
	ears: string, -- "cat" | "dog" | "bunny" | "bear" | "fox" | "none"
	extras: { string }, -- "wings" "horn" "horns" "tail" "beak" "crown" "antenna" "flames" "halo" "spikes" "scarf" "sprinkles" "glow"
	size: number,
	material: string?,
	zone: number, -- for the index book (0 = exclusive / secret)
	giftOnly: boolean?, -- never in an egg (e.g. the group gift)
}

local function P(id: string, name: string, rarity: string, power: number, body: string, color: { number }, accent: { number }, ears: string, extras: { string }, size: number, zone: number, material: string?): Pet
	return {
		id = id,
		name = name,
		rarity = rarity,
		power = power,
		body = body,
		color = color,
		accent = accent,
		ears = ears,
		extras = extras,
		size = size,
		zone = zone,
		material = material,
	}
end

Config.Pets = {
	-- Zone 1: Spawn Meadow
	P("dog", "Dog", "Common", 1, "ball", { 205, 150, 95 }, { 120, 80, 50 }, "dog", { "tail" }, 1, 1),
	P("cat", "Cat", "Uncommon", 2, "ball", { 150, 150, 160 }, { 255, 170, 190 }, "cat", { "tail" }, 1, 1),
	P("bunny", "Bunny", "Rare", 4, "ball", { 250, 250, 250 }, { 255, 170, 200 }, "bunny", {}, 1, 1),
	P("bear", "Bear", "Epic", 9, "block", { 140, 90, 55 }, { 220, 180, 130 }, "bear", {}, 1.15, 1),
	P("piggy", "Piggy", "Common", 5, "ball", { 255, 170, 190 }, { 240, 120, 150 }, "cat", { "tail" }, 1, 1),
	P("chick", "Chick", "Uncommon", 9, "ball", { 255, 225, 70 }, { 255, 150, 30 }, "none", { "beak", "wings" }, 0.9, 1),
	P("fox", "Fox", "Rare", 18, "ball", { 255, 130, 40 }, { 255, 245, 235 }, "fox", { "tail" }, 1, 1),
	P("owl", "Owl", "Epic", 40, "tall", { 150, 110, 80 }, { 250, 220, 160 }, "cat", { "beak", "wings" }, 1.1, 1),
	P("unicorn", "Unicorn", "Legendary", 120, "ball", { 255, 255, 255 }, { 255, 140, 230 }, "dog", { "horn", "wings" }, 1.25, 1),

	-- Zone 2: Candy Land
	P("gummybear", "Gummy Bear", "Common", 22, "block", { 255, 80, 90 }, { 255, 160, 170 }, "bear", {}, 1, 2, "Glass"),
	P("lollipup", "Lollipup", "Uncommon", 40, "ball", { 255, 120, 200 }, { 120, 220, 255 }, "dog", { "tail", "sprinkles" }, 1, 2),
	P("cupcakecat", "Cupcake Cat", "Rare", 80, "tall", { 255, 200, 230 }, { 170, 110, 70 }, "cat", { "sprinkles", "tail" }, 1.05, 2),
	P("candydragon", "Candy Dragon", "Epic", 170, "ball", { 120, 230, 170 }, { 255, 120, 180 }, "none", { "horns", "wings", "tail" }, 1.2, 2),
	P("donutdog", "Donut Dog", "Common", 60, "ball", { 230, 170, 110 }, { 255, 120, 190 }, "dog", { "sprinkles" }, 1, 2),
	P("marshbunny", "Marshmallow Bunny", "Uncommon", 110, "block", { 255, 245, 250 }, { 255, 200, 220 }, "bunny", {}, 1, 2),
	P("cottonfox", "Cotton Candy Fox", "Epic", 330, "ball", { 170, 210, 255 }, { 255, 170, 220 }, "fox", { "tail", "glow" }, 1.1, 2),
	P("jellyphoenix", "Jelly Phoenix", "Legendary", 900, "tall", { 255, 90, 160 }, { 255, 220, 80 }, "none", { "wings", "beak", "crown" }, 1.3, 2, "Glass"),

	-- Zone 3: Frost Peak
	P("penguin", "Penguin", "Common", 260, "tall", { 40, 45, 60 }, { 250, 250, 255 }, "none", { "beak", "scarf" }, 1, 3),
	P("snowfox", "Snow Fox", "Uncommon", 480, "ball", { 245, 250, 255 }, { 160, 210, 255 }, "fox", { "tail" }, 1, 3),
	P("polarbear", "Polar Bear", "Rare", 950, "block", { 250, 250, 255 }, { 200, 220, 240 }, "bear", { "scarf" }, 1.2, 3),
	P("icewolf", "Ice Wolf", "Epic", 2000, "ball", { 150, 200, 255 }, { 230, 245, 255 }, "fox", { "tail", "spikes" }, 1.2, 3, "Ice"),
	P("arcticowl", "Arctic Owl", "Uncommon", 1300, "tall", { 240, 245, 255 }, { 140, 170, 210 }, "cat", { "beak", "wings" }, 1, 3),
	P("yeti", "Yeti", "Rare", 2600, "block", { 235, 240, 250 }, { 110, 170, 230 }, "bear", { "horns" }, 1.25, 3),
	P("frostphoenix", "Frost Phoenix", "Epic", 5400, "tall", { 120, 200, 255 }, { 255, 255, 255 }, "none", { "wings", "beak", "glow" }, 1.25, 3, "Ice"),
	P("icedragon", "Ice Dragon", "Legendary", 15000, "ball", { 170, 230, 255 }, { 60, 120, 220 }, "none", { "horns", "wings", "tail", "spikes" }, 1.4, 3, "Ice"),

	-- Zone 4: Lava Caves
	P("lavapup", "Lava Pup", "Uncommon", 7000, "ball", { 60, 45, 45 }, { 255, 110, 30 }, "dog", { "tail", "flames" }, 1, 4),
	P("embercat", "Ember Cat", "Rare", 14000, "ball", { 255, 90, 30 }, { 255, 210, 60 }, "cat", { "tail", "flames" }, 1.05, 4),
	P("magmagolem", "Magma Golem", "Epic", 30000, "block", { 70, 55, 50 }, { 255, 120, 20 }, "none", { "spikes", "glow" }, 1.35, 4, "Basalt"),
	P("firedragon", "Fire Dragon", "Legendary", 80000, "ball", { 220, 40, 30 }, { 255, 180, 40 }, "none", { "horns", "wings", "tail", "flames" }, 1.4, 4),
	P("hellhound", "Hellhound", "Mythic", 250000, "ball", { 30, 25, 30 }, { 255, 50, 20 }, "fox", { "horns", "tail", "flames", "glow" }, 1.5, 4),

	-- Zone 5: Cosmic Void
	P("mooncat", "Moon Cat", "Uncommon", 110000, "ball", { 230, 230, 245 }, { 150, 140, 255 }, "cat", { "tail", "halo" }, 1, 5),
	P("starbunny", "Star Bunny", "Rare", 220000, "ball", { 255, 235, 120 }, { 140, 110, 255 }, "bunny", { "glow" }, 1.05, 5, "Neon"),
	P("alienpup", "Alien Pup", "Epic", 480000, "ball", { 120, 255, 140 }, { 60, 60, 90 }, "dog", { "antenna", "tail" }, 1.15, 5),
	P("nebulaowl", "Nebula Owl", "Legendary", 1300000, "tall", { 120, 70, 200 }, { 255, 120, 220 }, "cat", { "wings", "beak", "halo", "glow" }, 1.35, 5),
	P("galaxydragon", "Galaxy Dragon", "Mythic", 4200000, "ball", { 40, 30, 90 }, { 120, 220, 255 }, "none", { "horns", "wings", "tail", "halo", "glow" }, 1.6, 5),

	-- Exclusive (Robux) Magic Egg
	P("sparklecat", "Sparkle Cat", "Legendary", 0, "ball", { 255, 220, 250 }, { 120, 240, 255 }, "cat", { "tail", "halo", "glow" }, 1.2, 0),
	P("crystalunicorn", "Crystal Unicorn", "Mythic", 0, "ball", { 200, 240, 255 }, { 255, 150, 255 }, "dog", { "horn", "wings", "glow" }, 1.4, 0, "Glass"),
	P("celestialdragon", "Celestial Dragon", "Mythic", 0, "ball", { 255, 250, 230 }, { 255, 200, 60 }, "none", { "horns", "wings", "tail", "halo", "crown", "glow" }, 1.7, 0),

	-- Secret (1 in 100,000 from every world egg)
	P("shadowdragon", "Shadow Dragon", "Secret", 0, "ball", { 20, 15, 30 }, { 170, 60, 255 }, "none", { "horns", "wings", "tail", "spikes", "crown", "glow" }, 1.8, 0, "Neon"),
} :: { Pet }

-- One-time gift for joining the Roblox group (not in any egg).
do
	local pup = P("grouppup", "Group Pup", "Legendary", 0, "ball", { 120, 200, 255 }, { 255, 255, 255 }, "dog", { "tail", "scarf" }, 1.1, 0)
	pup.giftOnly = true
	table.insert(Config.Pets, pup)
end

---------------------------------------------------------------------------
-- Zones. Laid out along +Z; zone i spans Z in [(i-1)*ZoneLength - ZoneLength/2, ...].
---------------------------------------------------------------------------
export type Zone = {
	index: number,
	id: string,
	name: string,
	cost: number, -- taps to open the gate INTO this zone
	ground: { number },
	groundMaterial: string,
	path: { number },
	pathMaterial: string,
	wall: { number },
	sky: { number }, -- client color-correction tint while inside
	decor: string,
}

Config.ZoneLength = 220
Config.ZoneWidth = 170

Config.Zones = {
	{ index = 1, id = "meadow", name = "Spawn Meadow", cost = 0, ground = { 110, 200, 80 }, groundMaterial = "Grass", path = { 235, 215, 160 }, pathMaterial = "Sand", wall = { 150, 105, 70 }, sky = { 255, 255, 255 }, decor = "meadow" },
	{ index = 2, id = "candy", name = "Candy Land", cost = 27000, ground = { 255, 180, 215 }, groundMaterial = "SmoothPlastic", path = { 255, 245, 190 }, pathMaterial = "SmoothPlastic", wall = { 255, 110, 170 }, sky = { 255, 225, 245 }, decor = "candy" },
	{ index = 3, id = "frost", name = "Frost Peak", cost = 2600000, ground = { 235, 245, 255 }, groundMaterial = "Snow", path = { 170, 215, 255 }, pathMaterial = "Ice", wall = { 120, 170, 220 }, sky = { 220, 240, 255 }, decor = "frost" },
	{ index = 4, id = "lava", name = "Lava Caves", cost = 420000000, ground = { 70, 55, 55 }, groundMaterial = "Basalt", path = { 255, 110, 30 }, pathMaterial = "CrackedLava", wall = { 45, 35, 35 }, sky = { 255, 210, 190 }, decor = "lava" },
	{ index = 5, id = "cosmic", name = "Cosmic Void", cost = 6000000000, ground = { 45, 35, 90 }, groundMaterial = "Slate", path = { 130, 90, 255 }, pathMaterial = "Neon", wall = { 25, 20, 60 }, sky = { 215, 205, 255 }, decor = "cosmic" },
} :: { Zone }

---------------------------------------------------------------------------
-- Eggs. chance values are percentages and must sum to 100.
---------------------------------------------------------------------------
export type EggEntry = { pet: string, chance: number }
export type Egg = {
	id: string,
	name: string,
	zone: number, -- 0 = exclusive (spawn, robux)
	price: number, -- taps (0 for exclusive)
	color: { number },
	spots: { number },
	offsetX: number, -- position inside the zone (X across, Z along)
	offsetZ: number,
	entries: { EggEntry },
	exclusive: boolean?,
}

local SECRET = 0.001 -- percent (1 in 100,000)

Config.Eggs = {
	{ id = "basic", name = "Basic Egg", zone = 1, price = 200, color = { 250, 245, 230 }, spots = { 120, 200, 90 }, offsetX = -30, offsetZ = 30, entries = {
		{ pet = "dog", chance = 60 }, { pet = "cat", chance = 30 }, { pet = "bunny", chance = 8.999 }, { pet = "bear", chance = 1 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "spotted", name = "Spotted Egg", zone = 1, price = 3000, color = { 255, 230, 150 }, spots = { 200, 120, 60 }, offsetX = 30, offsetZ = 30, entries = {
		{ pet = "piggy", chance = 55 }, { pet = "chick", chance = 32 }, { pet = "fox", chance = 10.5 }, { pet = "owl", chance = 2.399 }, { pet = "unicorn", chance = 0.1 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "candy", name = "Candy Egg", zone = 2, price = 16000, color = { 255, 140, 200 }, spots = { 120, 220, 255 }, offsetX = -30, offsetZ = 20, entries = {
		{ pet = "gummybear", chance = 58 }, { pet = "lollipup", chance = 30 }, { pet = "cupcakecat", chance = 10 }, { pet = "candydragon", chance = 1.999 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "sprinkle", name = "Sprinkle Egg", zone = 2, price = 140000, color = { 255, 250, 200 }, spots = { 255, 90, 160 }, offsetX = 30, offsetZ = 20, entries = {
		{ pet = "donutdog", chance = 60 }, { pet = "marshbunny", chance = 33 }, { pet = "cottonfox", chance = 6.899 }, { pet = "jellyphoenix", chance = 0.1 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "frost", name = "Frost Egg", zone = 3, price = 260000, color = { 200, 235, 255 }, spots = { 255, 255, 255 }, offsetX = -30, offsetZ = 20, entries = {
		{ pet = "penguin", chance = 60 }, { pet = "snowfox", chance = 30 }, { pet = "polarbear", chance = 8.5 }, { pet = "icewolf", chance = 1.499 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "glacier", name = "Glacier Egg", zone = 3, price = 2100000, color = { 120, 190, 255 }, spots = { 230, 250, 255 }, offsetX = 30, offsetZ = 20, entries = {
		{ pet = "arcticowl", chance = 62 }, { pet = "yeti", chance = 30 }, { pet = "frostphoenix", chance = 7.9 }, { pet = "icedragon", chance = 0.099 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "magma", name = "Magma Egg", zone = 4, price = 12000000, color = { 80, 40, 30 }, spots = { 255, 120, 20 }, offsetX = 0, offsetZ = 25, entries = {
		{ pet = "lavapup", chance = 60 }, { pet = "embercat", chance = 30 }, { pet = "magmagolem", chance = 9.4 }, { pet = "firedragon", chance = 0.58 }, { pet = "hellhound", chance = 0.019 }, { pet = "shadowdragon", chance = SECRET },
	} },
	{ id = "cosmic", name = "Cosmic Egg", zone = 5, price = 180000000, color = { 60, 40, 140 }, spots = { 255, 240, 120 }, offsetX = 0, offsetZ = 25, entries = {
		{ pet = "mooncat", chance = 60 }, { pet = "starbunny", chance = 30 }, { pet = "alienpup", chance = 9.4 }, { pet = "nebulaowl", chance = 0.58 }, { pet = "galaxydragon", chance = 0.019 }, { pet = "shadowdragon", chance = SECRET },
	} },
	-- Robux-only egg, sits in spawn. Hatched via developer product, never with taps.
	{ id = "magic", name = "Magic Egg", zone = 0, price = 0, exclusive = true, color = { 190, 120, 255 }, spots = { 255, 240, 120 }, offsetX = 45, offsetZ = -72, entries = {
		{ pet = "sparklecat", chance = 70 }, { pet = "crystalunicorn", chance = 29 }, { pet = "celestialdragon", chance = 1 },
	} },
} :: { Egg }

-- Exclusive pets don't have taps-based power: they scale with the best world pet.
Config.ExclusivePowerFactor = {
	sparklecat = 1.5, -- x the power of the strongest non-exclusive pet the player could get from their best zone
	crystalunicorn = 2.5,
	celestialdragon = 5,
	shadowdragon = 10,
	grouppup = 1.2,
}

Config.EggRange = 16 -- studs; server rejects hatches from further away
Config.HatchCooldown = 2.4 -- seconds between hatches (manual or auto)

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
Config.RebirthBaseCost = 63000000
Config.RebirthCostGrowth = 8
Config.RebirthMultPer = 0.5 -- each rebirth adds +50% to every tap
Config.RebirthGemsBase = 30
Config.RebirthGemsPer = 15

---------------------------------------------------------------------------
-- Gem upgrades
---------------------------------------------------------------------------
export type Upgrade = { id: string, name: string, description: string, maxLevel: number, baseCost: number, costGrowth: number, perLevel: number }
Config.Upgrades = {
	{ id = "TapPower", name = "Tap Power", description = "+25% taps per level", maxLevel = 25, baseCost = 10, costGrowth = 1.45, perLevel = 0.25 },
	{ id = "Luck", name = "Luck", description = "+10% luck per level", maxLevel = 15, baseCost = 20, costGrowth = 1.55, perLevel = 0.10 },
	{ id = "PetSlots", name = "Pet Slots", description = "+1 equipped pet per level", maxLevel = 3, baseCost = 60, costGrowth = 3, perLevel = 1 },
	{ id = "WalkSpeed", name = "Walk Speed", description = "+3 walk speed per level", maxLevel = 5, baseCost = 8, costGrowth = 1.8, perLevel = 3 },
	{ id = "AutoTap", name = "Auto Tap", description = "+1 auto tap per second per level", maxLevel = 3, baseCost = 25, costGrowth = 2.2, perLevel = 1 },
} :: { Upgrade }
Config.UpgradeById = {} :: { [string]: Upgrade }
for _, u in Config.Upgrades do
	Config.UpgradeById[u.id] = u
end
Config.BaseWalkSpeed = 20

---------------------------------------------------------------------------
-- Monetization. IDs of 0 hide the item from the store (create them in the
-- Creator Dashboard and paste the IDs here; see DESIGN.md for prices).
---------------------------------------------------------------------------
export type Pass = { key: string, name: string, description: string, id: number, price: number, color: { number } }
Config.Passes = {
	{ key = "AutoTap", name = "Auto Tap", description = "Taps for you, 5 times a second, forever.", id = 0, price = 149, color = { 90, 200, 255 } },
	{ key = "TripleHatch", name = "x3 Hatch", description = "Open 3 eggs at once.", id = 0, price = 199, color = { 255, 170, 60 } },
	{ key = "AutoHatch", name = "Auto Hatch", description = "Keeps hatching the egg you stand next to.", id = 0, price = 249, color = { 255, 120, 200 } },
	{ key = "Lucky", name = "Lucky", description = "+50% luck on every egg.", id = 0, price = 199, color = { 110, 220, 110 } },
	{ key = "VIP", name = "VIP", description = "x1.5 taps, +10% luck and a VIP tag.", id = 0, price = 299, color = { 255, 215, 60 } },
	{ key = "PetSlots", name = "+3 Pet Slots", description = "Equip 3 more pets.", id = 0, price = 299, color = { 175, 110, 255 } },
	{ key = "DoubleTaps", name = "Double Taps", description = "Every tap is worth x2.", id = 0, price = 399, color = { 255, 90, 90 } },
	{ key = "MagicEggs", name = "Magic Eggs", description = "10x more Golden pets from eggs.", id = 0, price = 349, color = { 255, 200, 40 } },
} :: { Pass }
Config.PassByKey = {} :: { [string]: Pass }
for _, p in Config.Passes do
	Config.PassByKey[p.key] = p
end
Config.PassEffects = {
	VIPTapMult = 1.5,
	VIPLuck = 0.10,
	LuckyLuck = 0.5,
	DoubleTapsMult = 2,
	ExtraSlots = 3,
}

-- kind: "taps" (reward = minutes of your current tap income), "gems", "luck" (boost minutes), "egg" (exclusive egg hatches)
export type Product = { key: string, name: string, description: string, id: number, price: number, kind: string, amount: number, color: { number } }
Config.Products = {
	{ key = "TapsSmall", name = "Pile of Taps", description = "30 minutes of taps, instantly.", id = 0, price = 49, kind = "taps", amount = 30, color = { 90, 200, 255 } },
	{ key = "TapsMedium", name = "Bag of Taps", description = "3 hours of taps, instantly.", id = 0, price = 199, kind = "taps", amount = 180, color = { 60, 150, 255 } },
	{ key = "TapsLarge", name = "Vault of Taps", description = "12 hours of taps, instantly.", id = 0, price = 599, kind = "taps", amount = 720, color = { 40, 100, 230 } },
	{ key = "GemsSmall", name = "100 Gems", description = "Spend on upgrades.", id = 0, price = 49, kind = "gems", amount = 100, color = { 110, 230, 200 } },
	{ key = "GemsMedium", name = "600 Gems", description = "Best value for upgrades.", id = 0, price = 249, kind = "gems", amount = 600, color = { 60, 200, 170 } },
	{ key = "SuperLuck", name = "Super Luck (15 min)", description = "x2 luck for 15 minutes.", id = 0, price = 99, kind = "luck", amount = 15, color = { 110, 220, 110 } },
	{ key = "MagicEgg1", name = "Magic Egg", description = "Hatch 1 exclusive Magic Egg.", id = 0, price = 149, kind = "egg", amount = 1, color = { 190, 120, 255 } },
	{ key = "MagicEgg3", name = "3 Magic Eggs", description = "Hatch 3 exclusive Magic Eggs.", id = 0, price = 399, kind = "egg", amount = 3, color = { 150, 80, 230 } },
	-- first-24h offer; never listed in the store grid (kind "starter")
	{ key = "StarterPack", name = "Starter Pack", description = "1 Magic Egg, 150 Gems and 30 min Super Luck", id = 0, price = 99, kind = "starter", amount = 1, color = { 255, 150, 60 } },
} :: { Product }
Config.ProductByKey = {} :: { [string]: Product }
for _, p in Config.Products do
	Config.ProductByKey[p.key] = p
end
Config.BoostLuckMult = 2 -- Super Luck boost / luck rewards multiply luck by this

-- Paid random items (Roblox rules, 26/05/2026): anything bought with Robux - or with a
-- currency that can be bought with Robux - that gives a random result, plus every paid
-- probability modifier. Players whose PolicyService info says ArePaidRandomItemsRestricted
-- can't buy these: eggs and packs that contain one, luck, and Taps (eggs cost Taps, so for
-- them Taps must not be purchasable). Odds are always shown in % before spending.
Config.PaidRandomProductKinds = { egg = true, starter = true, luck = true, taps = true }
Config.PaidRandomPasses = { Lucky = true, MagicEggs = true, VIP = true }

-- Product kinds that never show in the store grid.
Config.HiddenProductKinds = { starter = true }
Config.StarterPack = { gems = 150, luckMinutes = 30, eggs = 1, windowSeconds = 86400, fullPrice = 399, popupAfterHatches = 3 }

-- Rewarded video ads: developer product IDs per placement (0 = off).
Config.AdProducts = { AdBoost = 0, AdOffline = 0 }
Config.AdBoostMinutes = 15
Config.AdOfflineFallbackMinutes = 10 -- minutes of taps if nothing is pending
Config.AdDailyCap = 5 -- videos per day, shared across placements
Config.AdBoostMult = 2 -- tap multiplier while tapBoostLeft > 0

---------------------------------------------------------------------------
-- Offline earnings
---------------------------------------------------------------------------
Config.OfflineCapHours = 8
Config.OfflineCapHoursVIP = 12
Config.OfflineTapsPerSecond = 1.0 -- taps/s of your tap value while away
Config.OfflineMinSeconds = 300

---------------------------------------------------------------------------
-- Live events (UTC schedule; admins can force one with /event <id> <minutes>)
---------------------------------------------------------------------------
Config.LiveEvents = {
	recurring = { { id = "LuckyHour", every = 10800, offset = 0, duration = 900 } },
	weekly = { { id = "GoldenWeekend", fromWday = 7, toWday = 1, allDayUTC = true } }, -- os.date("!*t").wday: Sunday = 1, Saturday = 7
}
Config.LiveEventDefs = {
	LuckyHour = { luckMult = 2 },
	GoldenWeekend = { goldenMult = 2 },
} :: { [string]: { luckMult: number?, goldenMult: number? } }
Config.AdminUserIds = {} :: { number }
Config.LiveEventMaxMinutes = 60

---------------------------------------------------------------------------
-- Social: referrals, group gift, notification opt-in
---------------------------------------------------------------------------
Config.ReferralStore = "TapPets_Referrals_v1"
Config.ReferralInviteeGift = { kind = "gems", amount = 50 }
Config.ReferralInviterGift = { kind = "egg", amount = 1 }
Config.ReferralMinPlaySeconds = 600
Config.ReferralLifetimeCap = 25
Config.ReferralLinkSeconds = 7 * 86400
Config.GroupId = 0 -- Roblox group for the join gift (0 = hidden)
Config.GroupGiftPet = "grouppup"
Config.NotifAskInterval = 7 * 86400

---------------------------------------------------------------------------
-- Daily quests: 3 per UTC day from this pool; targets scale with your best zone.
---------------------------------------------------------------------------
export type QuestDef = { kind: string, targetByZone: { number }, gems: number }
Config.QuestPool = {
	{ kind = "hatch", targetByZone = { 10, 15, 20, 25, 30 }, gems = 30 },
	{ kind = "taps", targetByZone = { 300, 500, 700, 900, 1200 }, gems = 25 },
	{ kind = "craft", targetByZone = { 1, 1, 1, 1, 1 }, gems = 50 },
	{ kind = "gems", targetByZone = { 10, 20, 40, 60, 100 }, gems = 20 },
	{ kind = "playMinutes", targetByZone = { 10, 15, 20, 25, 30 }, gems = 30 },
	{ kind = "rarity", targetByZone = { 1, 1, 1, 1, 1 }, gems = 60 },
} :: { QuestDef }
Config.QuestsPerDay = 3
Config.QuestBonus = { kind = "egg", amount = 1 }

---------------------------------------------------------------------------
-- Retention
---------------------------------------------------------------------------
export type Reward = { kind: string, amount: number, label: string }

-- 7-day streak; claim every 20h, streak breaks after 48h.
Config.DailyCooldown = 20 * 3600
Config.DailyStreakWindow = 48 * 3600
Config.DailyRewards = {
	{ kind = "taps", amount = 5, label = "5 min of Taps" },
	{ kind = "gems", amount = 25, label = "25 Gems" },
	{ kind = "taps", amount = 15, label = "15 min of Taps" },
	{ kind = "luck", amount = 15, label = "15 min Super Luck" },
	{ kind = "gems", amount = 60, label = "60 Gems" },
	{ kind = "taps", amount = 45, label = "45 min of Taps" },
	{ kind = "egg", amount = 1, label = "Magic Egg!" },
} :: { Reward }

-- Free in-session gifts (minutes since joining).
export type Gift = { minutes: number, reward: Reward }
Config.Gifts = {
	{ minutes = 5, reward = { kind = "taps", amount = 2, label = "2 min of Taps" } },
	{ minutes = 10, reward = { kind = "gems", amount = 10, label = "10 Gems" } },
	{ minutes = 15, reward = { kind = "taps", amount = 5, label = "5 min of Taps" } },
	{ minutes = 20, reward = { kind = "luck", amount = 5, label = "5 min Super Luck" } },
	{ minutes = 30, reward = { kind = "gems", amount = 25, label = "25 Gems" } },
	{ minutes = 40, reward = { kind = "taps", amount = 10, label = "10 min of Taps" } },
	{ minutes = 50, reward = { kind = "gems", amount = 40, label = "40 Gems" } },
	{ minutes = 60, reward = { kind = "egg", amount = 1, label = "Magic Egg!" } },
} :: { Gift }

Config.Codes = {
	RELEASE = { kind = "gems", amount = 50, label = "50 Gems" },
	TAPTAP = { kind = "taps", amount = 10, label = "10 min of Taps" },
	LUCKY = { kind = "luck", amount = 15, label = "15 min Super Luck" },
	PETS = { kind = "gems", amount = 25, label = "25 Gems" },
} :: { [string]: Reward }

-- Completing a zone's index (every non-secret pet of that zone) gives gems and a permanent tap bonus.
Config.IndexRewardGems = { 50, 100, 200, 400, 800 }
Config.IndexTapBonus = 0.10 -- +10% taps per completed zone index

Config.FriendBoostPer = 0.10
Config.FriendBoostMax = 0.50

-- Minimum taps/second assumed when converting "minutes of taps" rewards (new players).
Config.RewardMinTapsPerSecond = 6

return Config
