--!strict
-- THE name table. Every proper name the player can see (game, currencies, planets, training
-- zones, forms, techniques, enemies, bosses, auras, races, characters, items) lives here, by
-- key, and is shared by all 12 languages. Code, Config and tests only use the neutral keys.
-- Renaming something = editing one line in this file (a locale pack may override a key if a
-- language needs its own spelling).
--
-- All of these are ORIGINAL names. Do not replace them with names, characters or terms from
-- an existing anime, manga or game: that gets a Roblox experience taken down.
return {
	["game.title"] = "Ki Warriors",

	-- currencies
	["currency.sparks"] = "Sparks",
	["currency.gems"] = "Gems",

	-- characters
	["npc.master"] = "Master Oru",

	-- planets (arcs)
	["planet.verdia"] = "Verdia",
	["planet.brask"] = "Fort Brask",
	["planet.kaldera"] = "Kaldera",
	["planet.mesa"] = "Cracked Mesa",
	["planet.frostreach"] = "Frostreach",
	["planet.nullcity"] = "Null City",
	["planet.bubble"] = "Bubble Realm",
	["planet.zephyra"] = "Zephyra",
	["planet.tomorrow"] = "Broken Tomorrow",
	["planet.rift"] = "The Rift",

	-- story arcs (the saga each planet tells)
	["arc.1"] = "The First Seals",
	["arc.2"] = "Sky Coliseum Cup",
	["arc.3"] = "The Iron Legion",
	["arc.4"] = "The Horned King",
	["arc.5"] = "Storm Invaders",
	["arc.6"] = "Tyrant of the Ice World",
	["arc.7"] = "The Perfect Machine",
	["arc.8"] = "The Dream Eater",
	["arc.9"] = "The Sleeping God",
	["arc.10"] = "Gilded Return",
	["arc.11"] = "Twin Worlds Tournament",
	["arc.12"] = "The False Judge",
	["arc.13"] = "Last Realm Standing",

	-- training zones
	["zone.gravity_dome"] = "Gravity Dome",
	["zone.thunder_falls"] = "Thunder Falls",
	["zone.sand_pit"] = "Sand Pit",
	["zone.iron_yard"] = "Iron Yard",
	["zone.crater_field"] = "Crater Field",
	["zone.pod_wreck"] = "Pod Wreck",
	["zone.scrap_lab"] = "Scrap Lab",
	["zone.core_chamber"] = "Core Chamber",
	["zone.sugar_springs"] = "Sugar Springs",
	["zone.dream_pool"] = "Dream Pool",
	["zone.time_rift"] = "Time Rift",
	["zone.judge_court"] = "Court of Echoes",
	["zone.magma_forge"] = "Magma Forge",
	["zone.ash_crucible"] = "Ash Crucible",
	["zone.glacier_cavern"] = "Glacier Cavern",
	["zone.aurora_spire"] = "Aurora Spire",
	["zone.storm_eye"] = "Storm Eye",
	["zone.timeless_vault"] = "Timeless Vault",
	["zone.void_anvil"] = "Void Anvil",
	["zone.singularity"] = "Singularity",

	-- transformations
	["form.kindled"] = "Kindled",
	["form.blazing"] = "Blazing",
	["form.tempest"] = "Tempest",
	["form.eclipse"] = "Eclipse",
	["form.corona"] = "Corona",
	["form.solstice"] = "Solstice",
	["form.nova"] = "Nova",
	["form.celestial"] = "Celestial",
	["form.primordial"] = "Primordial",
	["form.unbound"] = "Unbound",

	-- techniques
	["tech.ki_blast"] = "Ki Blast",
	["tech.star_lance"] = "Star Lance",
	["tech.pulse_volley"] = "Pulse Volley",
	["tech.meteor_dive"] = "Meteor Dive",
	["tech.sunfall"] = "Sunfall",
	["tech.umbral_volley"] = "Umbral Barrage",
	["tech.null_nova"] = "Null Nova",

	-- enemies and bosses
	["npc.thornling"] = "Thornling",
	["npc.raider"] = "Dust Raider",
	["npc.bramble_king"] = "Bramble King",
	["npc.legion_grunt"] = "Legion Grunt",
	["npc.legion_gunner"] = "Legion Gunner",
	["npc.marshal_krome"] = "Marshal Krome",
	["npc.storm_scout"] = "Storm Scout",
	["npc.storm_elite"] = "Storm Elite",
	["npc.prince_vael"] = "Prince Vael",
	["npc.drone_unit"] = "Drone Unit",
	["npc.steel_unit"] = "Steel Unit",
	["npc.chimera_prime"] = "Chimera Prime",
	["npc.gum_blob"] = "Gum Blob",
	["npc.candy_golem"] = "Candy Golem",
	["npc.glutt"] = "Glutt the Dream Eater",
	["npc.echo_soldier"] = "Echo Soldier",
	["npc.null_wraith"] = "Null Wraith",
	["npc.arbiter_null"] = "Arbiter Null",
	["npc.korrath"] = "Korrath the Unbound",
	["npc.chrome_tyrant"] = "Chrome Tyrant",
	["npc.mirrorborn"] = "Mirrorborn",
	["npc.cinder_imp"] = "Cinder Imp",
	["npc.magma_brute"] = "Magma Brute",
	["npc.forge_tyrant"] = "Mordrak, the Horned King",
	["npc.frost_wisp"] = "Frost Wisp",
	["npc.glacier_guard"] = "Glacier Guard",
	["npc.rime_empress"] = "Rime Empress",
	["npc.gale_drone"] = "Gale Drone",
	["npc.storm_knight"] = "Storm Knight",
	["npc.tempest_warden"] = "Tempest Warden",
	["npc.void_spawn"] = "Void Spawn",
	["npc.rift_stalker"] = "Rift Stalker",
	["npc.hollow_star"] = "The Hollow Star",
	["npc.astral_titan"] = "Astral Titan",

	-- auras
	["aura.breeze"] = "Breeze",
	["aura.ember"] = "Ember",
	["aura.moss"] = "Moss",
	["aura.tide"] = "Tide",
	["aura.dusk"] = "Dusk",
	["aura.volt"] = "Volt",
	["aura.frostfire"] = "Frostfire",
	["aura.crimson"] = "Crimson",
	["aura.abyss"] = "Abyss",
	["aura.solar"] = "Solar",
	["aura.starlight"] = "Starlight",
	["aura.starter_flame"] = "Starter Flame",
	["aura.vip_gold"] = "VIP Gold",
	["aura.group_wave"] = "Wave",
	["aura.nebula"] = "Nebula",
	["aura.gilded"] = "Gilded",
	["aura.umbral"] = "Umbral",

	-- saga skins (one per arc)
	["skin.wanderer"] = "Wanderer",
	["skin.contender"] = "Contender",
	["skin.legion_breaker"] = "Legion Breaker",
	["skin.emberguard"] = "Emberguard",
	["skin.storm_armor"] = "Storm Armor",
	["skin.lumen_elder"] = "Lumen Elder",
	["skin.unit_zero"] = "Unit Zero",
	["skin.glutt_hood"] = "Glutt Hood",
	["skin.sky_warden"] = "Sky Warden",
	["skin.timewalker"] = "Timewalker",
	["skin.silent_titan"] = "Silent Titan",

	-- flying mounts
	["mount.zephyr_puff"] = "Zephyr Puff",
	["mount.thunderhead"] = "Thunderhead",

	-- battle pass seasons
	["season.s1"] = "Dream Eater Season",
	["season.s2"] = "Sleeping God Season",

	-- races
	["race.terran"] = "Terran",
	["race.voltari"] = "Voltari",
	["race.lumen"] = "Lumen",
	["race.drakhar"] = "Drakhar",

	-- items
	["item.seal"] = "Astral Seal",
	["item.seals"] = "Astral Seals",
	["item.vigor_seed"] = "Vigor Seed",
	["item.titan_seed"] = "Titan Seed",
	["item.spark_seed"] = "Spark Seed",
	["npc.wishkeeper"] = "Astra, the Wish Comet",
} :: { [string]: string }
