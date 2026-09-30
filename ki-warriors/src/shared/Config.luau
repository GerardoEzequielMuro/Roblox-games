--!strict
-- Ki Warriors: all content and numbers. Pure data (no Roblox APIs), also loaded by the
-- luau.exe unit tests and the economy simulation.
local Config = {}

Config.GameName = "Ki Warriors"
Config.DataStoreName = "KiWarriors_Profiles_v1"
Config.ReferralStore = "KiWarriors_Referrals_v1"
Config.BoardStores = { power = "KiWarriors_Power_v1", rebirths = "KiWarriors_Rebirths_v1", arena = "KiWarriors_Arena_v1" }
Config.AutosaveInterval = 90
Config.LeaderboardUpdateInterval = 120

-- Owner fills these after publishing (0 = hidden / disabled).
Config.GroupId = 0
Config.AdminUserIds = {} :: { number }
Config.StudioGrantAllPasses = false

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
Config.Stats = { "strength", "ki", "defense", "agility", "jump" }
Config.StatInfo = {
	strength = { icon = "👊", color = { 255, 96, 72 } },
	ki = { icon = "✨", color = { 72, 190, 255 } },
	defense = { icon = "🛡️", color = { 110, 225, 120 } },
	agility = { icon = "💨", color = { 255, 214, 72 } },
	jump = { icon = "🦘", color = { 196, 130, 255 } },
}
Config.StartStat = 5
-- Power level weights
Config.PowerWeights = { strength = 1, ki = 1, defense = 1, agility = 0.5, jump = 0.5 }

-- Training reps: manual (click / Punch button) and automatic.
Config.Train = {
	baseGain = 1, -- stat points per rep before multipliers
	manualPerSecond = 8, -- server cap (token bucket)
	manualBurst = 5,
	autoPerSecond = 1.5, -- free auto-train
	autoUpgradePerLevel = 0.5, -- gem upgrade "autoSpeed"
	turboMult = 2, -- TurboAuto pass
}

-- Server-driven helpers (never active inside the PvP arena)
Config.Auto = {
	fightPerSecond = 1.1, -- auto-attacks per second (TurboAuto doubles it)
	fightRange = 80, -- looks for enemies this far from the player
	chargeBelow = 0.2, -- auto-charge starts under this much ki...
	chargeUntil = 0.98, -- ...and stops here
}

---------------------------------------------------------------------------
-- World: planets laid out on a grid. All offsets are relative to the planet centre.
---------------------------------------------------------------------------
Config.PlanetSpacing = 4200
Config.GroundY = 0

local function polar(deg: number, r: number): { number }
	local a = math.rad(deg)
	return { math.floor(math.cos(a) * r + 0.5), 0, math.floor(math.sin(a) * r + 0.5) }
end

-- Ten planets, one per story arc (see DESIGN.md for the arc list). Each one is described in a
-- few lines; layout (where the zones, camps and boss sit) is shared, and enemy numbers are
-- generated from the power level a player has when they arrive.
--   power  = power needed to enter          cost = Sparks to unlock
--   zones  = { id, style }  (A = cheap multiplier, B = the big one, needs 6x the entry power)
--   zoneB  = multiplier of the second zone (the first one is a third of it)
--   npcs   = small, mid, boss: { id, archetype, ai, colour, accent }
local ARCS: { any } = {
	{ id = "verdia", arc = 1, theme = "meadow", power = 0, zoneB = 12, zones = { { "gravity_dome", "dome" }, { "thunder_falls", "falls" } },
		npcs = { { id = "thornling", arch = "imp", ai = "melee", color = { 96, 190, 80 }, accent = { 255, 120, 160 } }, { id = "raider", arch = "brute", ai = "melee", color = { 176, 124, 84 }, accent = { 220, 60, 50 } }, { id = "bramble_king", arch = "titan", ai = "boss", color = { 70, 130, 60 }, accent = { 255, 190, 60 } } } },
	{ id = "brask", arc = 3, theme = "desert", power = 25_000, zoneB = 40, zones = { { "sand_pit", "pit" }, { "iron_yard", "forge" } },
		npcs = { { id = "legion_grunt", arch = "knight", ai = "melee", color = { 150, 140, 96 }, accent = { 230, 60, 50 } }, { id = "legion_gunner", arch = "brute", ai = "ranged", color = { 96, 104, 110 }, accent = { 255, 170, 40 } }, { id = "marshal_krome", arch = "titan", ai = "boss", color = { 84, 96, 70 }, accent = { 255, 200, 60 } } } },
	{ id = "kaldera", arc = 4, theme = "volcano", power = 1_000_000, zoneB = 250, zones = { { "magma_forge", "forge" }, { "ash_crucible", "crucible" } },
		npcs = { { id = "cinder_imp", arch = "imp", ai = "ranged", color = { 230, 90, 40 }, accent = { 255, 210, 80 } }, { id = "magma_brute", arch = "brute", ai = "melee", color = { 70, 50, 50 }, accent = { 255, 110, 30 } }, { id = "forge_tyrant", arch = "titan", ai = "boss", color = { 60, 40, 40 }, accent = { 255, 80, 20 } } } },
	{ id = "mesa", arc = 5, theme = "wasteland", power = 40_000_000, zoneB = 1_000, zones = { { "crater_field", "pit" }, { "pod_wreck", "eye" } },
		npcs = { { id = "storm_scout", arch = "wisp", ai = "ranged", color = { 120, 130, 200 }, accent = { 255, 90, 200 } }, { id = "storm_elite", arch = "knight", ai = "melee", color = { 70, 60, 110 }, accent = { 120, 230, 255 } }, { id = "prince_vael", arch = "titan", ai = "boss", color = { 236, 236, 246 }, accent = { 70, 110, 255 } } } },
	{ id = "frostreach", arc = 6, theme = "ice", power = 1_500_000_000, zoneB = 8_000, zones = { { "glacier_cavern", "cavern" }, { "aurora_spire", "spire" } },
		npcs = { { id = "frost_wisp", arch = "wisp", ai = "ranged", color = { 170, 230, 255 }, accent = { 255, 255, 255 } }, { id = "glacier_guard", arch = "knight", ai = "melee", color = { 120, 170, 220 }, accent = { 220, 250, 255 } }, { id = "rime_empress", arch = "titan", ai = "boss", color = { 200, 230, 255 }, accent = { 120, 200, 255 } } } },
	{ id = "nullcity", arc = 7, theme = "ruins", power = 60_000_000_000, zoneB = 45_000, zones = { { "scrap_lab", "anvil" }, { "core_chamber", "singularity" } },
		npcs = { { id = "drone_unit", arch = "wisp", ai = "ranged", color = { 150, 160, 170 }, accent = { 120, 255, 140 } }, { id = "steel_unit", arch = "knight", ai = "melee", color = { 60, 70, 84 }, accent = { 255, 70, 70 } }, { id = "chimera_prime", arch = "titan", ai = "boss", color = { 60, 130, 70 }, accent = { 210, 255, 90 } } } },
	{ id = "bubble", arc = 8, theme = "candy", power = 2_500_000_000_000, zoneB = 300_000, zones = { { "sugar_springs", "falls" }, { "dream_pool", "dome" } },
		npcs = { { id = "gum_blob", arch = "imp", ai = "melee", color = { 120, 230, 220 }, accent = { 255, 250, 140 } }, { id = "candy_golem", arch = "brute", ai = "melee", color = { 250, 160, 210 }, accent = { 255, 255, 255 } }, { id = "glutt", arch = "titan", ai = "boss", color = { 90, 210, 200 }, accent = { 255, 120, 190 } } } },
	{ id = "zephyra", arc = 9, theme = "storm", power = 100_000_000_000_000, zoneB = 4_000_000, zones = { { "storm_eye", "eye" }, { "timeless_vault", "vault" } },
		npcs = { { id = "gale_drone", arch = "wisp", ai = "ranged", color = { 210, 215, 230 }, accent = { 255, 230, 90 } }, { id = "storm_knight", arch = "knight", ai = "melee", color = { 90, 100, 150 }, accent = { 120, 230, 255 } }, { id = "tempest_warden", arch = "titan", ai = "boss", color = { 60, 70, 120 }, accent = { 255, 240, 120 } } } },
	{ id = "tomorrow", arc = 12, theme = "future", power = 4_000_000_000_000_000, zoneB = 70_000_000, zones = { { "time_rift", "vault" }, { "judge_court", "spire" } },
		npcs = { { id = "echo_soldier", arch = "knight", ai = "melee", color = { 90, 80, 100 }, accent = { 255, 80, 90 } }, { id = "null_wraith", arch = "wisp", ai = "ranged", color = { 40, 40, 60 }, accent = { 190, 255, 120 } }, { id = "arbiter_null", arch = "titan", ai = "boss", color = { 120, 130, 110 }, accent = { 120, 255, 170 } } } },
	{ id = "rift", arc = 13, theme = "void", power = 150_000_000_000_000_000, zoneB = 600_000_000, zones = { { "void_anvil", "anvil" }, { "singularity", "singularity" } },
		npcs = { { id = "void_spawn", arch = "imp", ai = "ranged", color = { 60, 30, 110 }, accent = { 255, 90, 220 } }, { id = "rift_stalker", arch = "knight", ai = "melee", color = { 30, 20, 50 }, accent = { 160, 90, 255 } }, { id = "hollow_star", arch = "titan", ai = "boss", color = { 20, 10, 40 }, accent = { 255, 255, 255 } } } },
}

local RELIC_SPOTS = { polar(118, 120), polar(255, 120), polar(12, 110), polar(270, 250), polar(182, 290), polar(305, 290), polar(72, 300), polar(228, 215) }

Config.Planets = {} :: { any }
Config.Npcs = {} :: { [string]: any }
for index, a in ARCS do
	local first = index == 1
	-- the level of a player who just arrived (planet 1 starts from the base stats)
	local P = if first then 30 else a.power
	local radius = if first then 380 else 340
	local small, mid, boss = a.npcs[1], a.npcs[2], a.npcs[3]
	local sparks = if first then 4 else P * 0.016
	local function npc(def, scale: number, hp: number, dmg: number, reward: number, extra: { [string]: any }?)
		local n: { [string]: any } = {
			id = def.id,
			planet = index,
			arch = def.arch,
			ai = def.ai,
			color = def.color,
			accent = def.accent,
			scale = scale,
			hp = math.floor(hp),
			dmg = math.floor(dmg),
			sparks = math.floor(reward),
			speed = 14 + math.min(index, 6),
			respawn = 6,
		}
		if extra then
			for k, v in extra do
				n[k] = v
			end
		end
		Config.Npcs[n.id] = n
	end
	if first then
		npc(small, 1, 40, 3, 8)
		npc(mid, 1.05, 350, 10, 50, { respawn = 8 })
		npc(boss, 2.4, 6_000, 35, 1_200, { respawn = 45, boss = true, gems = 5, speed = 13 })
	else
		npc(small, 1.1 + index * 0.02, P * 1.6, P * 0.06, sparks)
		npc(mid, 1.2 + index * 0.02, P * 12, P * 0.15, sparks * 6, { respawn = 8 })
		npc(boss, 2.4 + index * 0.05, P * 240, P * 0.4, sparks * 200, { respawn = 45, boss = true, gems = 5 + index * 3 })
	end
	local pl = {
		id = a.id,
		index = index,
		arc = a.arc,
		reqPower = a.power,
		cost = if first then 0 else math.floor(a.power * 0.2),
		radius = radius,
		theme = a.theme,
		zones = {
			{ id = a.zones[1][1], style = a.zones[1][2], mult = math.max(4, math.floor(a.zoneB / 3)), reqPower = if first then 150 else a.power, offset = polar(200, 170), radius = 38 },
			{ id = a.zones[2][1], style = a.zones[2][2], mult = a.zoneB, reqPower = if first then 5_000 else a.power * 6, offset = polar(340, 175), radius = 38 },
		},
		camps = {
			{ npc = small.id, offset = polar(150, if first then 235 else 225), radius = 46, count = 6 },
			{ npc = mid.id, offset = polar(35, if first then 250 else 235), radius = 48, count = 5 },
		},
		boss = { npc = boss.id, offset = polar(90, if first then 285 else 255), radius = 62 },
		relicSpots = RELIC_SPOTS,
	}
	table.insert(Config.Planets, pl)
end
Config.PlanetById = {} :: { [string]: any }
Config.ZoneById = {} :: { [string]: any }
for _, pl in Config.Planets do
	Config.PlanetById[pl.id] = pl
	for _, z in pl.zones do
		z.planet = pl.index
		Config.ZoneById[z.id] = z
	end
end

-- Special places on planet 1 (Verdia)
Config.Arena = { planet = 1, offset = polar(270, 285), radius = 62, wall = 70 }
Config.WishAltar = { planet = 1, offset = polar(300, 105), radius = 16 }
Config.WorldBossSite = { planet = 1, offset = polar(232, 300), radius = 60 }
Config.MasterSpot = { planet = 1, offset = { 26, 0, 34 } } -- quest giver statue/NPC in the plaza
Config.PlazaRadius = 70

-- Planets sit on a 4-wide grid so coordinates stay small however many arcs are added.
Config.PlanetGridWidth = 4
function Config.planetCenter(index: number): (number, number, number)
	local i = index - 1
	return (i % Config.PlanetGridWidth) * Config.PlanetSpacing, Config.GroundY, (i // Config.PlanetGridWidth) * Config.PlanetSpacing
end

---------------------------------------------------------------------------
-- Training gear (weights). Bought with Sparks; multiplies every rep.
---------------------------------------------------------------------------
Config.Gear = {
	{ mult = 1, cost = 0 },
	{ mult = 1.5, cost = 40 },
	{ mult = 2.2, cost = 350 },
	{ mult = 3.2, cost = 2_500 },
	{ mult = 4.5, cost = 18_000 },
	{ mult = 6.5, cost = 130_000 },
	{ mult = 9, cost = 1_000_000 },
	{ mult = 13, cost = 9_000_000 },
	{ mult = 18, cost = 80_000_000 },
	{ mult = 25, cost = 700_000_000 },
	{ mult = 35, cost = 6_000_000_000 },
	{ mult = 50, cost = 50_000_000_000 },
	{ mult = 70, cost = 400_000_000_000 },
}

---------------------------------------------------------------------------
-- Transformations. Combat multiplier, ki drain (% of the bar per second).
---------------------------------------------------------------------------
Config.Forms = {
	{ id = "kindled", reqPower = 1_000, mult = 2, drain = 0.015, color = { 255, 170, 60 }, color2 = { 255, 236, 150 }, style = "flame" },
	{ id = "blazing", reqPower = 50_000, mult = 5, drain = 0.02, color = { 255, 70, 50 }, color2 = { 255, 190, 90 }, style = "flame" },
	{ id = "tempest", reqPower = 20_000_000, mult = 15, drain = 0.025, color = { 70, 220, 255 }, color2 = { 230, 250, 255 }, style = "lightning" },
	{ id = "eclipse", reqPower = 100_000_000, mult = 50, drain = 0.03, color = { 150, 70, 255 }, color2 = { 30, 10, 60 }, style = "shadow" },
	-- Round 6: two forms between Eclipse (~47 min) and Nova (~2.4 h) so the stretch where the
	-- player is saving for Frostreach always has a next goal. Same pattern as the others.
	{ id = "corona", reqPower = 600_000_000, mult = 80, drain = 0.032, color = { 255, 150, 40 }, color2 = { 255, 245, 190 }, style = "flame" },
	{ id = "solstice", reqPower = 1_250_000_000, mult = 130, drain = 0.034, color = { 255, 215, 90 }, color2 = { 120, 60, 255 }, style = "prism" },
	{ id = "nova", reqPower = 15_000_000_000, mult = 200, drain = 0.035, color = { 255, 250, 220 }, color2 = { 255, 200, 80 }, style = "lightning" },
	{ id = "celestial", reqPower = 1_500_000_000_000, mult = 1_000, drain = 0.04, color = { 120, 255, 220 }, color2 = { 255, 140, 240 }, style = "prism" },
	{ id = "primordial", reqPower = 200_000_000_000_000, reqRebirths = 3, mult = 5_000, drain = 0.045, color = { 255, 255, 255 }, color2 = { 255, 60, 120 }, style = "prism" },
	-- Special form (film arc P1). Same power and ascension requirement as Primordial; on top of
	-- that you either beat Korrath in the world-boss rotation 3 times (earn) or own the
	-- UnboundForm pass (skips only that kill requirement). Useless in PvP (PvP ignores forms).
	{ id = "unbound", reqPower = 200_000_000_000_000, reqRebirths = 3, mult = 8_000, drain = 0.05, color = { 120, 255, 130 }, color2 = { 255, 255, 255 }, style = "lightning", special = { boss = "korrath", count = 3, pass = "UnboundForm" } },
} :: { any }
for i, f in Config.Forms do
	f.index = i
end
Config.FormById = {} :: { [string]: any }
for _, f in Config.Forms do
	Config.FormById[f.id] = f
end
Config.FormDefenseExponent = 0.5 -- damage taken is divided by mult ^ this

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------
Config.Combat = {
	baseHp = 100,
	hpPerDefense = 4,
	-- melee
	meleeCooldown = 0.3,
	meleeRange = 9,
	meleeArc = 0.2, -- min dot(facing, toTarget)
	meleeBase = 4,
	meleePerStrength = 1,
	comboWindow = 1.1,
	comboFinisher = 4, -- every 4th hit
	finisherMult = 2.2,
	-- ki (fractions of the bar)
	kiRegen = 0.03,
	kiChargeRegen = 0.34,
	blastCost = 0.04,
	blastCooldown = 0.28,
	blastSpeed = 190,
	blastRange = 210,
	blastRadius = 4.5,
	blastBase = 3,
	blastPerKi = 0.8,
	beamMaxCharge = 2.2,
	beamMinCharge = 0.25,
	beamCostMin = 0.1,
	beamCostMax = 0.32,
	beamCooldown = 1.4,
	beamRange = 190,
	beamRadius = 6,
	beamBase = 12,
	beamPerKi = 5,
	blockReduction = 0.75,
	dashCost = 0.05,
	dashCooldown = 1.1,
	dashDistance = 26,
	dashIFrames = 0.3,
	critChance = 0.05,
	critMult = 2,
	-- PvP uses fractions of the victim's max HP, scaled by the power ratio
	pvp = { melee = 0.04, blast = 0.03, beam = 0.2, tech = 0.16, ratioExp = 0.35, ratioMin = 0.4, ratioMax = 2.5 },
	respawnInvulnerable = 4,
	outOfCombatHeal = 0.05, -- fraction of max HP per second after 6 s without damage
	outOfCombatDelay = 6,
	knockback = 38,
	finisherKnockback = 85,
}

-- Techniques (slots Z / X / V). Costs are fractions of the ki bar.
Config.Techniques = {
	{ id = "pulse_volley", key = "Z", cost = 1_200, reqPower = 2_000, kiCost = 0.16, cooldown = 5, icon = "🌠", shape = "volley", shots = 5, dmgMult = 0.8 },
	{ id = "meteor_dive", key = "X", cost = 200_000, reqPower = 100_000, kiCost = 0.22, cooldown = 9, icon = "☄️", shape = "dive", radius = 22, dmgMult = 5 },
	{ id = "sunfall", key = "V", cost = 8_000_000, reqPower = 10_000_000, kiCost = 0.4, cooldown = 16, icon = "🌞", shape = "orb", radius = 30, speed = 70, dmgMult = 14, color = "sun" },
	-- Dark branch ("evil attacks"). Learned with Sparks like the others; `special` = earn it by
	-- beating that boss N times OR own the DarkArts pass (skips only the boss requirement).
	-- Disabled inside the PvP arena so they can never be a paid edge there.
	{ id = "umbral_volley", key = "N", cost = 15_000_000, reqPower = 5_000_000, kiCost = 0.2, cooldown = 6, icon = "🌑", shape = "volley", shots = 7, dmgMult = 1.1, dark = true, color = { 120, 50, 210 }, special = { boss = "forge_tyrant", count = 3, pass = "DarkArts" } },
	{ id = "null_nova", key = "M", cost = 4_500_000_000, reqPower = 1_500_000_000, kiCost = 0.45, cooldown = 18, icon = "🕳️", shape = "orb", radius = 34, speed = 64, dmgMult = 22, dark = true, color = { 150, 60, 230 }, special = { boss = "rime_empress", count = 3, pass = "DarkArts" } },
} :: { any }
Config.TechniqueById = {} :: { [string]: any }
for _, t in Config.Techniques do
	Config.TechniqueById[t.id] = t
end

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------
-- Regular enemies and bosses are generated with the planets above. Here: the event bosses.
-- HP is scaled to the strongest player in the server when one spawns.
Config.Npcs.astral_titan = { id = "astral_titan", planet = 1, arch = "titan", scale = 3.6, hp = 25_000, dmg = 30, sparks = 0, speed = 12, ai = "boss", color = { 40, 60, 140 }, accent = { 120, 255, 230 }, respawn = 0, boss = true, world = true }
Config.Npcs.korrath = { id = "korrath", planet = 1, arch = "titan", scale = 4, hp = 25_000, dmg = 30, sparks = 0, speed = 14, ai = "boss", color = { 70, 150, 90 }, accent = { 190, 255, 120 }, respawn = 0, boss = true, world = true }
Config.Npcs.chrome_tyrant = { id = "chrome_tyrant", planet = 1, arch = "titan", scale = 3.4, hp = 25_000, dmg = 30, sparks = 0, speed = 13, ai = "boss", color = { 190, 196, 210 }, accent = { 255, 70, 120 }, respawn = 0, boss = true, world = true }
Config.Npcs.mirrorborn = { id = "mirrorborn", planet = 1, arch = "titan", scale = 3.2, hp = 25_000, dmg = 30, sparks = 0, speed = 15, ai = "boss", color = { 250, 250, 255 }, accent = { 255, 170, 60 }, respawn = 0, boss = true, world = true }
Config.NpcAi = {
	aggroRange = 46,
	leashRange = 95,
	meleeRange = 8,
	meleeWindup = 0.55,
	meleeCooldown = 1.5,
	rangedRange = 60,
	rangedKeep = 34,
	rangedWindup = 0.5,
	rangedCooldown = 2.2,
	projectileSpeed = 95,
	tickRate = 10,
	-- boss patterns
	slamRadius = 26,
	slamWindup = 1.25,
	slamDamageMult = 2.2,
	volleyShots = 6,
	chargeWindup = 0.9,
	chargeSpeed = 95,
	chargeDistance = 70,
	patternCooldown = 3.2,
	enrageAt = 0.4, -- HP fraction: faster patterns
}

Config.WorldBoss = {
	npc = "astral_titan",
	rotation = { "astral_titan", "korrath", "chrome_tyrant", "mirrorborn" }, -- one per half hour, in order
	every = 1800, -- seconds (UTC aligned): spawns at :00 and :30
	duration = 300,
	hpPerMelee = 450, -- HP = max(base hp, this x the strongest player's melee damage)
	maxPlayersScale = 0.35, -- +35% HP per extra player
	-- reward per contribution tier (fraction of total damage dealt by the player)
	tiers = {
		{ min = 0.25, gems = 30, sparkMinutes = 12 },
		{ min = 0.05, gems = 15, sparkMinutes = 6 },
		{ min = 0.0001, gems = 6, sparkMinutes = 2 },
	},
	damageMultToPlayers = 0.14, -- each hit deals this fraction of the victim's max HP
}

---------------------------------------------------------------------------
-- PvP arena
---------------------------------------------------------------------------
Config.Pvp = {
	protectSeconds = 600, -- new players can't be hit (or hit others) until this much play time...
	protectPower = 2_000, -- ...or this much power, whichever comes first; can be switched off
	startRating = 1000,
	winRating = 22,
	lossRating = 14,
	minRating = 0,
	repeatKillSeconds = 120, -- same victim within this window gives no rating
	killSparkMinutes = 0.5,
	-- Arena Rush: a short tournament window where kills score points
	rush = { every = 1200, duration = 180, offset = 600, prizes = { { gems = 20 }, { gems = 12 }, { gems = 6 } }, minScore = 1 },
}

---------------------------------------------------------------------------
-- Rebirth (Ascension)
---------------------------------------------------------------------------
Config.Rebirth = {
	basePower = 40_000_000,
	growth = 40,
	multPerRebirth = 1, -- training multiplier = 1 + rebirths * this
	gems = 25, -- gems per ascension
}

-- Permanent upgrades bought with Gems
Config.Upgrades = {
	{ id = "trainPower", max = 25, baseCost = 10, costGrowth = 1.35, perLevel = 0.1, icon = "💪" },
	{ id = "sparkGain", max = 20, baseCost = 10, costGrowth = 1.35, perLevel = 0.1, icon = "⚡" },
	{ id = "autoSpeed", max = 7, baseCost = 15, costGrowth = 1.7, perLevel = 0.5, icon = "🤖" },
	{ id = "kiRegen", max = 10, baseCost = 12, costGrowth = 1.45, perLevel = 0.1, icon = "🔋" },
	{ id = "critChance", max = 10, baseCost = 15, costGrowth = 1.5, perLevel = 0.02, icon = "🎯" },
} :: { any }
Config.UpgradeById = {} :: { [string]: any }
for _, u in Config.Upgrades do
	Config.UpgradeById[u.id] = u
end

-- Races: cosmetic marks + a small bonus. First change is free, then costs gems.
Config.Races = {
	{ id = "terran", bonus = "sparks", amount = 0.1, color = { 255, 200, 120 } },
	{ id = "voltari", bonus = "strength", amount = 0.1, color = { 255, 230, 90 } },
	{ id = "lumen", bonus = "ki", amount = 0.1, color = { 120, 220, 255 } },
	{ id = "drakhar", bonus = "defense", amount = 0.1, color = { 230, 90, 90 } },
} :: { any }
Config.RaceById = {} :: { [string]: any }
for _, r in Config.Races do
	Config.RaceById[r.id] = r
end
Config.RaceChangeGems = 40

---------------------------------------------------------------------------
-- Auras (spin). The odds are shown in the UI exactly as listed here.
---------------------------------------------------------------------------
Config.Rarities = {
	{ name = "Common", order = 1, color = { 190, 196, 210 } },
	{ name = "Uncommon", order = 2, color = { 110, 220, 120 } },
	{ name = "Rare", order = 3, color = { 80, 170, 255 } },
	{ name = "Epic", order = 4, color = { 190, 110, 255 } },
	{ name = "Legendary", order = 5, color = { 255, 196, 60 } },
	{ name = "Mythic", order = 6, color = { 255, 80, 120 } },
} :: { any }
Config.RarityByName = {} :: { [string]: any }
for _, r in Config.Rarities do
	Config.RarityByName[r.name] = r
end
-- weight = chance in percent (the list adds up to 100)
Config.Auras = {
	{ id = "breeze", rarity = "Common", weight = 22, mult = 1.1, color = { 200, 235, 255 } },
	{ id = "ember", rarity = "Common", weight = 20, mult = 1.1, color = { 255, 150, 80 } },
	{ id = "moss", rarity = "Common", weight = 18, mult = 1.1, color = { 130, 220, 110 } },
	{ id = "tide", rarity = "Uncommon", weight = 13, mult = 1.25, color = { 70, 150, 255 } },
	{ id = "dusk", rarity = "Uncommon", weight = 12, mult = 1.25, color = { 190, 110, 230 } },
	{ id = "volt", rarity = "Rare", weight = 6, mult = 1.5, color = { 255, 240, 90 } },
	{ id = "frostfire", rarity = "Rare", weight = 4, mult = 1.5, color = { 140, 255, 250 } },
	{ id = "crimson", rarity = "Epic", weight = 2.5, mult = 2, color = { 255, 50, 70 } },
	{ id = "abyss", rarity = "Epic", weight = 1.5, mult = 2, color = { 90, 40, 200 } },
	{ id = "solar", rarity = "Legendary", weight = 0.9, mult = 3, color = { 255, 210, 60 } },
	{ id = "starlight", rarity = "Mythic", weight = 0.1, mult = 5, color = { 255, 255, 255 } },
	-- not in the spin
	{ id = "starter_flame", rarity = "Epic", weight = 0, mult = 2, color = { 255, 120, 200 }, exclusive = true },
	{ id = "vip_gold", rarity = "Legendary", weight = 0, mult = 2.5, color = { 255, 215, 60 }, exclusive = true },
	{ id = "group_wave", rarity = "Rare", weight = 0, mult = 1.5, color = { 90, 230, 200 }, exclusive = true },
	-- Epic / Legendary auras that are not in the spin. Each one can be bought (AuraPack pass,
	-- DarkArts for Umbral) or earned: `earn` uses the same rules as Collection.earned.
	{ id = "nebula", rarity = "Epic", weight = 0, mult = 2, color = { 170, 90, 255 }, exclusive = true, pass = "AuraPack", earn = { rebirths = 1 } },
	{ id = "gilded", rarity = "Legendary", weight = 0, mult = 3, color = { 255, 200, 70 }, exclusive = true, pass = "AuraPack", earn = { rebirths = 3 } },
	{ id = "umbral", rarity = "Epic", weight = 0, mult = 2, color = { 110, 40, 190 }, exclusive = true, pass = "DarkArts", earn = { boss = "forge_tyrant", count = 5 } },
} :: { any }
Config.AuraById = {} :: { [string]: any }
for _, a in Config.Auras do
	Config.AuraById[a.id] = a
end
Config.AuraSpin = { gems = 25, freePerDay = 1, luckyMult = 2 } -- LuckyAura pass doubles Rare+ weights

---------------------------------------------------------------------------
-- Wish relics ("Astral Seals"): per-player collectibles; all 6 = one wish at the altar.
---------------------------------------------------------------------------
Config.Relics = {
	count = 6,
	resetSeconds = 900, -- after a wish, a new set appears 15 minutes later
	pickupRadius = 9,
	colors = { { 255, 90, 90 }, { 255, 170, 60 }, { 255, 235, 90 }, { 110, 230, 120 }, { 90, 180, 255 }, { 190, 120, 255 } },
}
Config.Wishes = {
	{ id = "sparks", sparkMinutes = 30 },
	{ id = "gems", gems = 60 },
	{ id = "boost", boostMinutes = 45 },
	{ id = "auras", spins = 3 },
	{ id = "power", wishPower = 0.05 }, -- permanent +5% training (max 20 stacks)
} :: { any }
Config.WishPowerMax = 20

---------------------------------------------------------------------------
-- Story (linear quest chain; the first steps are the tutorial)
-- kinds: reps(stat?) | blasts | charge | fly | defeat(npc) | power | zone(zone) | gear | form | boss(npc)
--        | travel(planet) | technique | relic | rebirth | beam | dash
---------------------------------------------------------------------------
Config.Story = {
	{ kind = "reps", target = 10, sparks = 15, guide = "none" },
	{ kind = "charge", target = 1, sparks = 15, guide = "none" },
	{ kind = "blasts", target = 3, sparks = 20, guide = "none" },
	{ kind = "fly", target = 1, sparks = 20, guide = "none" },
	{ kind = "defeat", npc = "thornling", target = 3, sparks = 40, gems = 5, guide = "camp" },
	{ kind = "gear", target = 2, sparks = 30, guide = "none" },
	{ kind = "power", target = 150, sparks = 60, guide = "none" },
	{ kind = "zone", zone = "gravity_dome", target = 40, sparks = 150, gems = 5, guide = "zone" },
	{ kind = "power", target = 1_000, sparks = 300, guide = "none" },
	{ kind = "form", target = 1, sparks = 400, gems = 5, guide = "none" },
	{ kind = "defeat", npc = "raider", target = 5, sparks = 600, guide = "camp" },
	{ kind = "beam", target = 3, sparks = 500, guide = "none" },
	{ kind = "technique", target = 1, sparks = 800, guide = "none" },
	{ kind = "zone", zone = "thunder_falls", target = 100, sparks = 2_500, gems = 5, guide = "zone" },
	{ kind = "relic", target = 1, sparks = 2_000, gems = 5, guide = "relic" },
	{ kind = "boss", npc = "bramble_king", target = 1, sparks = 4_000, gems = 10, guide = "boss" },
} :: { any }
-- every later arc: travel there, clear the small enemies, train, clear the elites, train in
-- the big zone, beat the boss. The first ascension comes after arc 4.
for index = 2, #Config.Planets do
	local pl = Config.Planets[index]
	local s1 = Config.Npcs[pl.camps[1].npc].sparks
	table.insert(Config.Story, { kind = "travel", planet = index, target = 1, sparks = s1 * 20, gems = 10, guide = "none" })
	table.insert(Config.Story, { kind = "defeat", npc = pl.camps[1].npc, target = 8, sparks = s1 * 30, guide = "camp" })
	table.insert(Config.Story, { kind = "zone", zone = pl.zones[1].id, target = 150, sparks = s1 * 40, gems = 5, guide = "zone" })
	table.insert(Config.Story, { kind = "defeat", npc = pl.camps[2].npc, target = 6, sparks = s1 * 80, guide = "camp" })
	table.insert(Config.Story, { kind = "zone", zone = pl.zones[2].id, target = 300, sparks = s1 * 120, gems = 5, guide = "zone" })
	table.insert(Config.Story, { kind = "boss", npc = pl.boss.npc, target = 1, sparks = s1 * 400, gems = 10 + index * 2, guide = "boss" })
	if index == 4 then
		table.insert(Config.Story, { kind = "rebirth", target = 1, sparks = 0, gems = 25, guide = "none" })
	end
end
Config.TutorialSteps = 5 -- story steps that count as the first-minute tutorial

-- Daily quests: 3 per UTC day, same kinds for everyone; targets scale with the best planet.
Config.QuestsPerDay = 3
Config.QuestPool = {
	{ kind = "reps", targetByPlanet = { 600, 900, 1_200, 1_500, 1_800 }, gems = 8 },
	{ kind = "defeat", targetByPlanet = { 25, 35, 45, 55, 65 }, gems = 8 },
	{ kind = "boss", targetByPlanet = { 1, 1, 2, 2, 3 }, gems = 12 },
	{ kind = "blasts", targetByPlanet = { 60, 80, 100, 120, 140 }, gems = 6 },
	{ kind = "minutes", targetByPlanet = { 15, 15, 20, 20, 20 }, gems = 8 },
	{ kind = "relic", targetByPlanet = { 2, 2, 3, 3, 3 }, gems = 10 },
	{ kind = "arena", targetByPlanet = { 1, 1, 2, 2, 3 }, gems = 12 },
} :: { any }
Config.QuestBonusGems = 15

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
-- kinds: sparks (minutes of income), gems, boost (minutes of x2 training), spins (aura spins)
Config.DailyRewards = {
	{ kind = "sparks", amount = 5 },
	{ kind = "gems", amount = 10 },
	{ kind = "boost", amount = 15 },
	{ kind = "gems", amount = 20 },
	{ kind = "spins", amount = 2 },
	{ kind = "gems", amount = 35 },
	{ kind = "spins", amount = 5 },
} :: { any }
Config.Gifts = {
	{ minutes = 2, reward = { kind = "sparks", amount = 3 } },
	{ minutes = 5, reward = { kind = "gems", amount = 5 } },
	{ minutes = 10, reward = { kind = "boost", amount = 10 } },
	{ minutes = 15, reward = { kind = "gems", amount = 10 } },
	{ minutes = 25, reward = { kind = "spins", amount = 1 } },
	{ minutes = 40, reward = { kind = "gems", amount = 20 } },
	{ minutes = 60, reward = { kind = "spins", amount = 3 } },
} :: { any }
Config.Codes = {
	RELEASE = { kind = "gems", amount = 25 },
	KIWARRIOR = { kind = "boost", amount = 15 },
	AURA = { kind = "spins", amount = 2 },
	["1KLIKES"] = { kind = "gems", amount = 50 },
} :: { [string]: any }
Config.FriendBoostPerFriend = 0.1
Config.FriendBoostMax = 0.3
Config.PremiumBonus = 0.1
Config.GroupBonus = 0.1
Config.GroupGiftAura = "group_wave"

-- Offline training: auto-train keeps going at a reduced rate while away.
Config.Offline = { minSeconds = 120, capSeconds = 4 * 3600, vipCapSeconds = 8 * 3600, rate = 0.25 }

-- Referrals
Config.ReferralMinPlaySeconds = 600
Config.ReferralInviteeGift = { kind = "gems", amount = 25 }
Config.ReferralInviterGift = { kind = "gems", amount = 50 }
Config.ReferralLifetimeCap = 50
Config.ReferralLinkSeconds = 7 * 86400
Config.NotifAskInterval = 7 * 86400

---------------------------------------------------------------------------
-- Live events (UTC schedule, identical in every server)
---------------------------------------------------------------------------
Config.LiveEvents = {
	recurring = {
		{ id = "PowerHour", every = 3 * 3600, offset = 0, duration = 900 },
	},
	weekly = {
		{ id = "SparkWeekend", fromWday = 7, toWday = 1 }, -- Saturday..Sunday UTC
	},
}
Config.LiveEventDefs = {
	PowerHour = { trainMult = 2, icon = "🔥", color = { 255, 120, 60 } },
	SparkWeekend = { sparkMult = 2, icon = "⚡", color = { 255, 214, 72 } },
	AdminRage = { trainMult = 3, sparkMult = 2, icon = "👑", color = { 255, 80, 200 } },
} :: { [string]: any }
Config.LiveEventMaxMinutes = 120

---------------------------------------------------------------------------
-- Monetization (ids = 0 until the owner creates them in the Creator Dashboard)
-- Prices follow docs/research/top-juegos-y-precios.md section 4.5. RULES: nothing here is
-- random; every paid power item (`earn` / `special`) can also be earned by playing; the PvP
-- arena ignores every paid effect (see Combat.arenaNormalized). Crossed-out prices shown in
-- the shop are always the real sum of the parts (tests/pricing_check.luau verifies it).
---------------------------------------------------------------------------
Config.Passes = {
	{ key = "VIP", id = 0, price = 299, icon = "👑" },
	{ key = "DoubleTraining", id = 0, price = 249, icon = "💪" },
	{ key = "DoubleSparks", id = 0, price = 249, icon = "⚡" },
	-- Bundle of the two 2x passes: owning it counts as owning both (see Collection.expandPasses).
	{ key = "DoubleBundle", id = 0, price = 449, icon = "💪", implies = { "DoubleTraining", "DoubleSparks" } },
	{ key = "TurboAuto", id = 0, price = 249, icon = "🤖" },
	{ key = "KiMastery", id = 0, price = 199, icon = "🔋" },
	{ key = "LuckyAura", id = 0, price = 249, icon = "🍀" },
	{ key = "RelicRadar", id = 0, price = 299, icon = "🧭" },
	{ key = "FastFlight", id = 0, price = 79, icon = "🚀" },
	-- Time Chamber: offline training runs at chamberRate and stores up to chamberCapSeconds.
	-- Earn it for free with `earn` (2 ascensions).
	{ key = "TimeChamber", id = 0, price = 499, icon = "⏳", earn = { rebirths = 2 }, earnable = true },
	-- Special form / dark attacks: skip only the boss-kill requirement (see Forms / Techniques).
	{ key = "UnboundForm", id = 0, price = 599, icon = "🌟", earnable = true },
	{ key = "DarkArts", id = 0, price = 399, icon = "🌑", earnable = true },
	-- Cosmetic packs (skins, mount, epic/legendary auras). Every item in them is also earnable.
	{ key = "SkinPack", id = 0, price = 299, icon = "🎽", earnable = true },
	{ key = "MountPack", id = 0, price = 149, icon = "🌤️", earnable = true },
	{ key = "AuraPack", id = 0, price = 199, icon = "🌀", earnable = true },
} :: { any }
Config.PassByKey = {} :: { [string]: any }
for _, p in Config.Passes do
	Config.PassByKey[p.key] = p
end
Config.VipTrainBonus = 0.2
Config.VipDailyGems = 10
Config.KiMasteryDrain = 0.5
Config.KiMasteryRegen = 1.5
Config.FastFlightMult = 1.5
Config.TimeChamber = { rate = 0.5, capSeconds = 12 * 3600 } -- offline rate (free: Config.Offline.rate) and cap

Config.Products = {
	{ key = "StarterPack", id = 0, price = 99, kind = "starter", amount = 1, icon = "🎁" },
	{ key = "Sparks1", id = 0, price = 49, kind = "sparks", amount = 20, icon = "⚡" },
	{ key = "Sparks2", id = 0, price = 99, kind = "sparks", amount = 50, icon = "⚡" },
	{ key = "Sparks3", id = 0, price = 199, kind = "sparks", amount = 120, icon = "⚡" },
	{ key = "Sparks4", id = 0, price = 399, kind = "sparks", amount = 300, icon = "⚡" },
	{ key = "Gems1", id = 0, price = 49, kind = "gems", amount = 60, icon = "💎" },
	{ key = "Gems2", id = 0, price = 129, kind = "gems", amount = 190, icon = "💎" },
	{ key = "Gems3", id = 0, price = 299, kind = "gems", amount = 480, icon = "💎" },
	{ key = "Gems4", id = 0, price = 699, kind = "gems", amount = 1_300, icon = "💎" },
	{ key = "Boost30", id = 0, price = 49, kind = "boost", amount = 30, icon = "🔥" },
	{ key = "WishNow", id = 0, price = 199, kind = "wish", amount = 1, icon = "🌠" },
	-- Seeds (consumables, also bought with Sparks in the shop): 1 of each / 5 of each.
	{ key = "SeedSampler", id = 0, price = 25, kind = "seeds", amount = 1, icon = "🌱" },
	{ key = "SeedCase", id = 0, price = 99, kind = "seeds", amount = 5, icon = "🌱" },
	-- Battle pass: premium track of a season (one product per season) and a tier skip.
	{ key = "BattlePassS1", id = 0, price = 399, kind = "bp", season = "s1", amount = 1, icon = "🎟️" },
	{ key = "BattlePassS2", id = 0, price = 399, kind = "bp", season = "s2", amount = 1, icon = "🎟️" },
	{ key = "TierSkip", id = 0, price = 49, kind = "bpskip", amount = 1, icon = "⬆️" },
} :: { any }
Config.ProductByKey = {} :: { [string]: any }
for _, p in Config.Products do
	Config.ProductByKey[p.key] = p
end

-- Cheapest Robux price of one Gem / one Spark-minute in the shop (conservative: the "value"
-- of the Starter Pack is computed with the best rate a player could get elsewhere).
local function cheapest(kind: string): number
	local best = math.huge
	for _, p in Config.Products do
		if p.kind == kind then
			best = math.min(best, p.price / p.amount)
		end
	end
	return best
end
-- Starter Pack (first 24 h of a player, once). `fullPrice` is what the same contents cost if
-- bought one by one in the shop; the aura is free on top.
Config.StarterPack = { windowSeconds = 86400, gems = 200, boostMinutes = 30, sparkMinutes = 50, aura = "starter_flame", fullPrice = 0 }
Config.StarterPack.fullPrice = math.floor(Config.StarterPack.gems * cheapest("gems") + 0.5) + math.floor(Config.StarterPack.boostMinutes / Config.ProductByKey.Boost30.amount * Config.ProductByKey.Boost30.price + 0.5) + math.floor(Config.StarterPack.sparkMinutes * cheapest("sparks") + 0.5)
---------------------------------------------------------------------------
-- Seeds: consumables. Bought with Sparks (price = minutes of income on the player's best
-- planet, limited per hour by `stockPerHour`, restocking on the hour) or from the Robux packs
-- above (which ignore the hourly limit). Never usable inside the PvP arena.
--   vigor_seed: heals to full HP and gives ki back        titan_seed: +damage vs enemies
--   spark_seed: fills ki and boosts ki regen for a while
---------------------------------------------------------------------------
Config.Seeds = {
	{ id = "vigor_seed", icon = "🌿", color = { 110, 225, 120 }, minutes = 3, stockPerHour = 6, cooldown = 15, kiGive = 0.5 },
	{ id = "titan_seed", icon = "🌱", color = { 255, 96, 72 }, minutes = 8, stockPerHour = 3, seconds = 600, damageMult = 1.5 },
	{ id = "spark_seed", icon = "🌾", color = { 72, 190, 255 }, minutes = 6, stockPerHour = 4, seconds = 600, regenMult = 2.5 },
} :: { any }
Config.SeedById = {} :: { [string]: any }
for _, sd in Config.Seeds do
	Config.SeedById[sd.id] = sd
end
Config.SeedCap = 30 -- most of one seed a player can carry

---------------------------------------------------------------------------
-- Cosmetics. Skins (one per saga / arc) are procedural pieces on the avatar: kit = which
-- pieces, main / accent = colours. Mounts are a puff under the feet while flying. Every
-- item is earned (`earn`, same rules as Collection.earned) or unlocked by a pass; purely
-- visual, no stats.
---------------------------------------------------------------------------
Config.Skins = {
	{ id = "wanderer", arc = 1, kit = { "band", "belt" }, main = { 60, 140, 255 }, accent = { 255, 210, 80 }, earn = { boss = "bramble_king", count = 1 } },
	{ id = "contender", arc = 2, kit = { "belt", "pads" }, main = { 255, 150, 40 }, accent = { 255, 255, 255 }, earn = { pvpKills = 5 } },
	{ id = "legion_breaker", arc = 3, kit = { "pads", "belt", "band" }, main = { 90, 110, 80 }, accent = { 230, 60, 50 }, earn = { boss = "marshal_krome", count = 1 } },
	{ id = "emberguard", arc = 4, kit = { "cape", "pads" }, main = { 60, 40, 40 }, accent = { 255, 110, 30 }, earn = { boss = "forge_tyrant", count = 1 } },
	{ id = "storm_armor", arc = 5, kit = { "pads", "band" }, main = { 70, 110, 255 }, accent = { 236, 236, 246 }, earn = { boss = "prince_vael", count = 1 } },
	{ id = "lumen_elder", arc = 6, kit = { "cape", "band" }, main = { 200, 230, 255 }, accent = { 120, 200, 255 }, earn = { boss = "rime_empress", count = 1 } },
	{ id = "unit_zero", arc = 7, kit = { "pads", "belt" }, main = { 60, 130, 70 }, accent = { 210, 255, 90 }, earn = { boss = "chimera_prime", count = 1 } },
	{ id = "glutt_hood", arc = 8, kit = { "cape", "band" }, main = { 250, 160, 210 }, accent = { 90, 210, 200 }, earn = { boss = "glutt", count = 5 } },
	{ id = "sky_warden", arc = 9, kit = { "cape", "pads", "band" }, main = { 60, 70, 120 }, accent = { 255, 240, 120 }, earn = { boss = "tempest_warden", count = 1 } },
	{ id = "timewalker", arc = 12, kit = { "cape", "belt" }, main = { 120, 130, 110 }, accent = { 120, 255, 170 }, earn = { boss = "arbiter_null", count = 1 } },
	{ id = "silent_titan", arc = 13, kit = { "cape", "pads", "belt", "band" }, main = { 20, 10, 40 }, accent = { 255, 255, 255 }, earn = { boss = "hollow_star", count = 1 } },
} :: { any }
for _, sk in Config.Skins do
	sk.pass = "SkinPack"
end
Config.SkinById = {} :: { [string]: any }
for _, sk in Config.Skins do
	Config.SkinById[sk.id] = sk
end
Config.Mounts = {
	{ id = "zephyr_puff", color = { 255, 255, 255 }, earn = { boss = "bramble_king", count = 1 }, pass = "MountPack" },
	{ id = "thunderhead", color = { 70, 60, 110 }, earn = { boss = "tempest_warden", count = 1 }, pass = "MountPack" },
} :: { any }
Config.MountById = {} :: { [string]: any }
for _, m in Config.Mounts do
	Config.MountById[m.id] = m
end

---------------------------------------------------------------------------
-- Battle pass (seasons). A free track and a premium track (one Robux product per season,
-- no random boxes, nothing missable in the free track). XP comes from playing; the season
-- has a real start / end shown as a clock. `startsAt` is UTC epoch seconds.
-- s1 = 2026-10-01 00:00 UTC, 8 weeks each; add later seasons here.
---------------------------------------------------------------------------
Config.BattlePass = {
	tiers = 30,
	xpPerTier = 90,
	skipRefundGems = 60, -- a tier skip bought while no season runs (rare race) pays back Gems
	xp = { questClaim = 10, questBonus = 10, minutes = 1, bossKill = 6, worldBoss = 12, arenaWin = 8, relic = 2 }, -- minutes: per 5 min played
	-- Round 6: free ways to earn pass XP that reward coming back (all server-side, no grinding).
	firstWinXp = 6, -- first enemy defeated (or arena win) of each UTC day
	weekly = { -- 3 challenges, reset every 7 days counted from the first season start
		{ id = "days", target = 3, xp = 20 }, -- play on 3 different days
		{ id = "quests", target = 5, xp = 20 }, -- claim 5 daily quests
		{ id = "bosses", target = 2, xp = 20 }, -- defeat 2 bosses
	},
	weekSeconds = 7 * 86400,
	-- Catch-up: when the tier is below the tier a steady player would have on this day of the
	-- season (tier 30 on day `paceFrac` * season length), all pass XP is multiplied.
	catchUp = { paceFrac = 0.8, grace = 2, mult = 1.5, deepGap = 6, deepMult = 2 },
	seasons = {
		{ id = "s1", arc = 8, product = "BattlePassS1", startsAt = 1790812800, days = 56, color = { 250, 130, 200 }, freeMid = { kind = "mount", id = "zephyr_puff", amount = 1 }, freeFinal = { kind = "aura", id = "nebula", amount = 1 }, premiumFinal = { kind = "skin", id = "glutt_hood", amount = 1 } },
		{ id = "s2", arc = 9, product = "BattlePassS2", startsAt = 1790812800 + 56 * 86400, days = 56, color = { 90, 130, 255 }, freeMid = { kind = "aura", id = "umbral", amount = 1 }, freeFinal = { kind = "mount", id = "thunderhead", amount = 1 }, premiumFinal = { kind = "skin", id = "sky_warden", amount = 1 } },
	} :: { any },
}
Config.BattlePass.SeasonById = {} :: { [string]: any }
Config.BattlePass.rewards = {} :: { [string]: { free: { [number]: any }, premium: { [number]: any } } }
for _, season in Config.BattlePass.seasons do
	Config.BattlePass.SeasonById[season.id] = season
	season.endsAt = season.startsAt + season.days * 86400
	local free, premium = {}, {}
	for t = 1, Config.BattlePass.tiers do
		local m = t % 3
		if t == 10 then
			free[t] = { kind = "spins", amount = 3 }
		elseif t == 20 then
			free[t] = season.freeMid
		elseif t == Config.BattlePass.tiers then
			free[t] = season.freeFinal
		elseif m == 1 then
			free[t] = { kind = "sparks", amount = 4 + t // 3 }
		elseif m == 2 then
			free[t] = { kind = "gems", amount = 5 }
		else
			free[t] = { kind = "seed", item = "vigor_seed", amount = 1 }
		end
		if t == Config.BattlePass.tiers then
			premium[t] = season.premiumFinal
		elseif t == 10 then
			premium[t] = { kind = "spins", amount = 5 }
		elseif t == 20 then
			premium[t] = { kind = "sparks", amount = 30 }
		elseif t % 2 == 1 then
			premium[t] = { kind = "gems", amount = 10 }
		elseif t % 4 == 2 then
			premium[t] = { kind = "boost", amount = 20 }
		else
			premium[t] = { kind = "seed", item = if t % 8 == 0 then "spark_seed" else "titan_seed", amount = 2 }
		end
	end
	Config.BattlePass.rewards[season.id] = { free = free, premium = premium }
end

-- Rewarded video placements -> developer product ids
Config.AdProducts = { AdBoost = 0, AdSpin = 0 }
Config.AdDailyCap = 4
Config.AdBoostMinutes = 10

-- Performance budgets (checked by the playtest)
Config.Budget = {
	worldParts = 14000, -- server-built BaseParts (10 planets; only the near one is streamed in)
	npcs = 90, -- active (only planets with players keep their enemies spawned)
	clientFxParts = 260, -- pooled effect parts alive at once
	luaHeapMb = 60, -- client Lua heap (gcinfo)
	serverLuaHeapMb = 80,
}

return Config
