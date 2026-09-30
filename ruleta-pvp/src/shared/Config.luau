--!strict
-- Spin Showdown: all content and numbers. Pure data (no Roblox APIs), so the standalone
-- tests (luau.exe) load the same file as the game.
--
-- POLICY GUARD RAILS (see DESIGN.md "Policy"):
--   * nothing is wagered: spinning is free, no stake, no chips, no payout table
--   * match rewards depend only on placement (like any PvP game)
--   * Robux buys cosmetics, coins (cosmetics only) and comfort; never anything that changes
--     a match (tests/unit_core.luau asserts this over every pass and product)
--   * there are no paid random items at all
local Config = {}

Config.GameName = "Spin Showdown"
Config.DataStoreName = "SpinShowdown_v1"
Config.AutosaveInterval = 90
Config.StudioGrantAllPasses = false
Config.AdminUserIds = {} :: { number }
Config.GroupId = 0

---------------------------------------------------------------------------
-- Wheel outcomes
---------------------------------------------------------------------------
export type Outcome = { id: string, icon: string, color: { number }, needsTarget: boolean, danger: number }
-- danger: 0 good for the spinner .. 3 deadly; drives the suspense presentation on the client.
Config.Outcomes = {
	{ id = "zap", icon = "⚡", color = { 255, 196, 40 }, needsTarget = true, danger = 1 },
	{ id = "double", icon = "💥", color = { 255, 120, 40 }, needsTarget = true, danger = 2 },
	{ id = "backfire", icon = "🔁", color = { 225, 60, 80 }, needsTarget = false, danger = 2 },
	{ id = "shield", icon = "🛡️", color = { 70, 160, 255 }, needsTarget = false, danger = 0 },
	{ id = "heal", icon = "💚", color = { 70, 210, 120 }, needsTarget = false, danger = 0 },
	{ id = "steal", icon = "🧲", color = { 170, 100, 255 }, needsTarget = true, danger = 1 },
	{ id = "reverse", icon = "🔄", color = { 60, 205, 200 }, needsTarget = false, danger = 0 },
	{ id = "wild", icon = "🎯", color = { 255, 105, 180 }, needsTarget = false, danger = 1 },
	{ id = "doom", icon = "💀", color = { 40, 30, 60 }, needsTarget = true, danger = 3 },
	{ id = "card", icon = "🃏", color = { 235, 235, 245 }, needsTarget = false, danger = 0 },
	{ id = "swap", icon = "🔀", color = { 120, 225, 90 }, needsTarget = true, danger = 1 },
	{ id = "meteor", icon = "☄️", color = { 255, 90, 50 }, needsTarget = false, danger = 2 },
	{ id = "gift", icon = "🎁", color = { 255, 150, 210 }, needsTarget = false, danger = 0 },
	{ id = "rescue", icon = "🚑", color = { 90, 230, 190 }, needsTarget = false, danger = 0 },
} :: { Outcome }
Config.OutcomeById = {} :: { [string]: Outcome }
for _, o in Config.Outcomes do
	Config.OutcomeById[o.id] = o
end

-- Slot layouts (clockwise). DOOM always sits between two BACKFIREs: aiming for it is a risk.
Config.Wheels = {
	classic = { "zap", "shield", "zap", "backfire", "doom", "backfire", "double", "heal", "zap", "steal", "wild", "reverse" },
	chaos = { "zap", "swap", "backfire", "doom", "backfire", "double", "meteor", "shield", "zap", "gift", "steal", "wild", "heal", "wild" },
	teams = { "zap", "shield", "zap", "backfire", "doom", "backfire", "double", "heal", "zap", "steal", "wild", "rescue" },
	duel = { "zap", "shield", "zap", "backfire", "doom", "backfire", "double", "heal", "zap", "steal", "wild", "card" },
	sudden = { "zap", "backfire", "double", "zap", "backfire", "doom", "backfire", "zap", "wild", "double", "zap", "shield" },
} :: { [string]: { string } }

---------------------------------------------------------------------------
-- Cards (dealt for free at the start of a match; never sold)
---------------------------------------------------------------------------
export type Card = { id: string, icon: string, color: { number }, weight: number, needsTarget: boolean }
Config.Cards = {
	{ id = "oracle", icon = "🔮", color = { 170, 100, 255 }, weight = 2, needsTarget = false },
	{ id = "skip", icon = "⏭️", color = { 60, 205, 200 }, weight = 2, needsTarget = false },
	{ id = "pass", icon = "👉", color = { 255, 150, 60 }, weight = 2, needsTarget = true },
	{ id = "shield", icon = "🛡️", color = { 70, 160, 255 }, weight = 2, needsTarget = false },
	{ id = "double", icon = "✖️", color = { 255, 90, 90 }, weight = 2, needsTarget = false },
	{ id = "magnet", icon = "🧲", color = { 255, 105, 180 }, weight = 1, needsTarget = true },
} :: { Card }
Config.CardById = {} :: { [string]: Card }
for _, c in Config.Cards do
	Config.CardById[c.id] = c
end
Config.MaxHand = 4
Config.MaxShields = 2

---------------------------------------------------------------------------
-- Round modifiers
---------------------------------------------------------------------------
export type Modifier = { id: string, icon: string, color: { number } }
Config.Modifiers = {
	{ id = "turbo", icon = "🌀", color = { 60, 205, 200 } }, -- wheel spins 1.8x faster
	{ id = "blackout", icon = "🌑", color = { 90, 80, 130 } }, -- slots shuffled and hidden until it lands
	{ id = "overcharge", icon = "🔥", color = { 255, 110, 50 } }, -- every hit +1
	{ id = "fragile", icon = "🧊", color = { 150, 210, 255 } }, -- shields do not block
	{ id = "gift", icon = "🎁", color = { 255, 150, 210 } }, -- everyone draws a card
} :: { Modifier }
Config.ModifierById = {} :: { [string]: Modifier }
for _, m in Config.Modifiers do
	Config.ModifierById[m.id] = m
end
Config.TurboMult = 1.8

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------
export type Mode = {
	id: string,
	icon: string,
	color: { number },
	wheel: string,
	lives: number,
	cards: number,
	teams: boolean,
	minPlayers: number,
	maxPlayers: number,
	fillTo: number, -- bots fill the table up to this many seats
	modifierEvery: number, -- a modifier on every Nth round (0 = never)
	modifierFrom: number,
	suddenAlive: number, -- sudden death when this many players are left (0 = off)
	suddenTurn: number, -- ...or at this turn, whichever comes first
}
Config.Modes = {
	{ id = "classic", icon = "🎡", color = { 70, 160, 255 }, wheel = "classic", lives = 3, cards = 2, teams = false, minPlayers = 2, maxPlayers = 8, fillTo = 5, modifierEvery = 3, modifierFrom = 3, suddenAlive = 2, suddenTurn = 40 },
	{ id = "chaos", icon = "🌪️", color = { 255, 105, 180 }, wheel = "chaos", lives = 3, cards = 3, teams = false, minPlayers = 2, maxPlayers = 8, fillTo = 6, modifierEvery = 1, modifierFrom = 2, suddenAlive = 2, suddenTurn = 44 },
	{ id = "teams", icon = "🤝", color = { 90, 220, 130 }, wheel = "teams", lives = 3, cards = 2, teams = true, minPlayers = 2, maxPlayers = 8, fillTo = 6, modifierEvery = 3, modifierFrom = 3, suddenAlive = 2, suddenTurn = 36 },
	{ id = "duel", icon = "⚔️", color = { 255, 150, 60 }, wheel = "duel", lives = 5, cards = 2, teams = false, minPlayers = 2, maxPlayers = 2, fillTo = 2, modifierEvery = 0, modifierFrom = 0, suddenAlive = 0, suddenTurn = 9 },
} :: { Mode }
Config.ModeById = {} :: { [string]: Mode }
for _, m in Config.Modes do
	Config.ModeById[m.id] = m
end

-- Once sudden death is on, every hit gets +1 every this many turns; nobody can stall.
Config.EscalateEvery = 6
Config.MaxTurns = 150 -- hard stop: most lives wins

---------------------------------------------------------------------------
-- Wheel physics (units: slots and seconds). Shared by server and client.
---------------------------------------------------------------------------
Config.Wheel = {
	speed = 7.0, -- slots per second while free-spinning
	travelTurns = 1.25, -- braking distance in wheel turns (before jitter)
	jitter = 1.25, -- +- slots of server-rolled brake jitter: skill matters, luck decides
	easePower = 2.6, -- deceleration curve: angle = travel * (1 - (1 - t/T)^p)
	minSpin = 0.7, -- seconds before the brake arms
	maxSpin = 6.0, -- auto-brake after this
}

-- Seconds. The server owns every timer; TimeScale (tests) divides them.
Config.Timing = {
	countdown = 12, -- table lobby countdown once a human sits down
	countdownFull = 4,
	intro = 4.0,
	decide = 14,
	decideBot = { 1.4, 2.8 },
	afkDecide = 1.6, -- auto-play toggle / AFK
	cardFx = 1.3,
	landPause = 1.1, -- hold on the landed slot before anything happens
	effect = 2.2,
	wildSweep = 3.0,
	elimination = 4.2,
	modifier = 2.6,
	sudden = 3.6,
	ending = 9.0,
	between = 1.0,
}

---------------------------------------------------------------------------
-- Tables in the lobby
---------------------------------------------------------------------------
-- kind "public": fixed mode, anyone sits. kind "flex": private tables and duels.
Config.Tables = {
	{ id = "t1", kind = "public", mode = "classic", theme = "neon" },
	{ id = "t2", kind = "public", mode = "chaos", theme = "slime" },
	{ id = "t3", kind = "public", mode = "teams", theme = "arcane" },
	{ id = "t4", kind = "public", mode = "classic", theme = "arcane" },
	{ id = "t5", kind = "flex", mode = "duel", theme = "neon" },
	{ id = "t6", kind = "flex", mode = "duel", theme = "slime" },
}
Config.Seats = 8
Config.TableRingRadius = 118 -- tables sit on a ring around the plaza
Config.SeatRadius = 17
Config.WheelRadius = 9.5

Config.BotNames = { "Bolt", "Pixel", "Nova", "Ziggy", "Mochi", "Turbo", "Widget", "Comet", "Noodle", "Sprocket", "Blip", "Gizmo", "Pogo", "Fizz", "Rocket", "Waffle", "Zed", "Dash", "Echo", "Bubbles" }
Config.BotColors = { { 255, 105, 97 }, { 255, 179, 71 }, { 253, 253, 120 }, { 119, 221, 119 }, { 120, 200, 255 }, { 177, 156, 217 }, { 255, 150, 210 }, { 120, 235, 215 } }
Config.TeamColors = { { 70, 160, 255 }, { 255, 95, 95 } }

---------------------------------------------------------------------------
-- Progression
---------------------------------------------------------------------------
Config.Leagues = {
	{ id = "bronze", icon = "🥉", trophies = 0, color = { 205, 127, 50 } },
	{ id = "silver", icon = "🥈", trophies = 100, color = { 200, 205, 215 } },
	{ id = "gold", icon = "🥇", trophies = 250, color = { 255, 205, 60 } },
	{ id = "platinum", icon = "💠", trophies = 500, color = { 110, 225, 215 } },
	{ id = "diamond", icon = "💎", trophies = 900, color = { 120, 180, 255 } },
	{ id = "champion", icon = "👑", trophies = 1500, color = { 255, 105, 180 } },
}
Config.MaxLevel = 100
Config.LevelCoins = 100 -- coins on every level up (+10 per level)
Config.StreakBonus = 0.1 -- +10% coins per consecutive win, capped below
Config.StreakBonusCap = 5

---------------------------------------------------------------------------
-- Cosmetics. unlock.type: default | coins | level | league | wins | streak | pass | code |
-- starter | daily | event
---------------------------------------------------------------------------
export type Cosmetic = { id: string, kind: string, icon: string, rarity: string, unlock: { type: string, n: number?, key: string? }, look: { [string]: any }? }
local function c(kind: string, id: string, icon: string, rarity: string, unlock: { type: string, n: number?, key: string? }, look: { [string]: any }?): Cosmetic
	return { id = id, kind = kind, icon = icon, rarity = rarity, unlock = unlock, look = look }
end
Config.Rarities = {
	{ id = "common", color = { 170, 178, 195 } },
	{ id = "rare", color = { 70, 160, 255 } },
	{ id = "epic", color = { 170, 100, 255 } },
	{ id = "legendary", color = { 255, 190, 50 } },
}
Config.RarityById = {} :: { [string]: { id: string, color: { number } } }
for _, r in Config.Rarities do
	Config.RarityById[r.id] = r
end
Config.CosmeticKinds = { "wheel", "table", "finisher", "emote", "title", "aura" }
Config.Cosmetics = {
	-- wheel skins: rim / hub colours, material, tint strength over the outcome colours
	c("wheel", "w_classic", "🎡", "common", { type = "default" }, { rim = { 40, 46, 80 }, hub = { 255, 205, 60 }, trim = { 255, 255, 255 }, material = "SmoothPlastic", tint = { 255, 255, 255 }, mix = 0 }),
	c("wheel", "w_neon", "🌈", "rare", { type = "coins", n = 600 }, { rim = { 20, 16, 40 }, hub = { 0, 240, 255 }, trim = { 255, 60, 220 }, material = "Neon", tint = { 255, 255, 255 }, mix = 0 }),
	c("wheel", "w_candy", "🍭", "rare", { type = "coins", n = 900 }, { rim = { 255, 140, 190 }, hub = { 255, 255, 255 }, trim = { 120, 220, 255 }, material = "SmoothPlastic", tint = { 255, 200, 230 }, mix = 0.35 }),
	c("wheel", "w_slime", "🧪", "rare", { type = "level", n = 5 }, { rim = { 40, 120, 50 }, hub = { 170, 255, 90 }, trim = { 220, 255, 140 }, material = "Glass", tint = { 150, 255, 120 }, mix = 0.3 }),
	c("wheel", "w_lava", "🌋", "epic", { type = "coins", n = 2200 }, { rim = { 50, 20, 15 }, hub = { 255, 120, 30 }, trim = { 255, 200, 60 }, material = "Slate", tint = { 255, 120, 60 }, mix = 0.3 }),
	c("wheel", "w_ice", "❄️", "epic", { type = "league", key = "gold" }, { rim = { 190, 225, 255 }, hub = { 255, 255, 255 }, trim = { 120, 190, 255 }, material = "Ice", tint = { 200, 230, 255 }, mix = 0.4 }),
	c("wheel", "w_galaxy", "🌌", "epic", { type = "daily" }, { rim = { 28, 18, 60 }, hub = { 200, 150, 255 }, trim = { 120, 220, 255 }, material = "Foil", tint = { 140, 110, 255 }, mix = 0.35 }),
	c("wheel", "w_arcade", "🕹️", "epic", { type = "starter" }, { rim = { 30, 30, 36 }, hub = { 255, 60, 90 }, trim = { 60, 255, 170 }, material = "Neon", tint = { 255, 255, 255 }, mix = 0 }),
	c("wheel", "w_wizard", "🧙", "legendary", { type = "pass", key = "LegendSkins" }, { rim = { 60, 30, 110 }, hub = { 255, 215, 90 }, trim = { 190, 140, 255 }, material = "Marble", tint = { 190, 150, 255 }, mix = 0.3 }),
	c("wheel", "w_cyber", "🤖", "legendary", { type = "pass", key = "LegendSkins" }, { rim = { 12, 14, 22 }, hub = { 0, 255, 170 }, trim = { 0, 200, 255 }, material = "DiamondPlate", tint = { 120, 255, 220 }, mix = 0.25 }),
	c("wheel", "w_royal", "👑", "legendary", { type = "pass", key = "LegendSkins" }, { rim = { 120, 20, 40 }, hub = { 255, 215, 90 }, trim = { 255, 235, 170 }, material = "Fabric", tint = { 255, 220, 160 }, mix = 0.25 }),
	c("wheel", "w_gold", "🏆", "legendary", { type = "pass", key = "VIP" }, { rim = { 200, 150, 30 }, hub = { 255, 240, 170 }, trim = { 255, 255, 255 }, material = "Foil", tint = { 255, 215, 90 }, mix = 0.45 }),
	c("wheel", "w_champion", "💫", "legendary", { type = "league", key = "champion" }, { rim = { 255, 105, 180 }, hub = { 255, 255, 255 }, trim = { 255, 215, 90 }, material = "Neon", tint = { 255, 170, 220 }, mix = 0.3 }),

	-- table skins: seat pods and the table ring
	c("table", "t_default", "🪑", "common", { type = "default" }, { base = { 52, 60, 110 }, accent = { 0, 220, 255 }, material = "SmoothPlastic" }),
	c("table", "t_carbon", "⬛", "rare", { type = "coins", n = 700 }, { base = { 30, 32, 38 }, accent = { 255, 70, 70 }, material = "DiamondPlate" }),
	c("table", "t_bubblegum", "🫧", "rare", { type = "coins", n = 1100 }, { base = { 255, 150, 200 }, accent = { 255, 255, 255 }, material = "SmoothPlastic" }),
	c("table", "t_jungle", "🌿", "rare", { type = "level", n = 8 }, { base = { 60, 120, 60 }, accent = { 220, 255, 120 }, material = "Wood" }),
	c("table", "t_frost", "🧊", "epic", { type = "wins", n = 25 }, { base = { 170, 215, 255 }, accent = { 255, 255, 255 }, material = "Ice" }),
	c("table", "t_royal", "🏰", "legendary", { type = "pass", key = "LegendSkins" }, { base = { 110, 20, 50 }, accent = { 255, 215, 90 }, material = "Fabric" }),
	c("table", "t_hologram", "🔷", "legendary", { type = "pass", key = "LegendSkins" }, { base = { 30, 60, 120 }, accent = { 120, 240, 255 }, material = "ForceField" }),

	-- finishers: how your victims leave the table (pure presentation)
	c("finisher", "f_hammer", "🔨", "common", { type = "default" }),
	c("finisher", "f_confetti", "🎉", "rare", { type = "starter" }),
	c("finisher", "f_rocket", "🚀", "rare", { type = "coins", n = 1200 }),
	c("finisher", "f_slime", "🟢", "rare", { type = "level", n = 10 }),
	c("finisher", "f_freeze", "🥶", "epic", { type = "coins", n = 2600 }),
	c("finisher", "f_ufo", "🛸", "epic", { type = "pass", key = "FinisherPack" }),
	c("finisher", "f_blackhole", "🕳️", "legendary", { type = "pass", key = "FinisherPack" }),
	c("finisher", "f_lightning", "🌩️", "legendary", { type = "pass", key = "FinisherPack" }),

	-- emotes: bubble + a small body move
	c("emote", "e_wave", "👋", "common", { type = "default" }, { move = "hop" }),
	c("emote", "e_laugh", "😂", "common", { type = "default" }, { move = "shake" }),
	c("emote", "e_gg", "🤝", "common", { type = "default" }, { move = "hop" }),
	c("emote", "e_sweat", "😅", "common", { type = "default" }, { move = "shake" }),
	c("emote", "e_cool", "😎", "rare", { type = "coins", n = 300 }, { move = "lean" }),
	c("emote", "e_cry", "😭", "rare", { type = "coins", n = 300 }, { move = "shake" }),
	c("emote", "e_angry", "😡", "rare", { type = "level", n = 3 }, { move = "stomp" }),
	c("emote", "e_clap", "👏", "rare", { type = "wins", n = 5 }, { move = "hop" }),
	c("emote", "e_skull", "💀", "epic", { type = "pass", key = "EmotePack" }, { move = "lean" }),
	c("emote", "e_heart", "💖", "epic", { type = "pass", key = "EmotePack" }, { move = "spin" }),
	c("emote", "e_dance", "🕺", "epic", { type = "pass", key = "EmotePack" }, { move = "spin" }),
	c("emote", "e_sleep", "😴", "epic", { type = "pass", key = "EmotePack" }, { move = "lean" }),
	c("emote", "e_fire", "🔥", "epic", { type = "pass", key = "EmotePack" }, { move = "stomp" }),
	c("emote", "e_clown", "🤡", "epic", { type = "pass", key = "EmotePack" }, { move = "spin" }),

	-- titles (text comes from the locale: "title.<id>")
	c("title", "ti_rookie", "🔰", "common", { type = "default" }),
	c("title", "ti_spinner", "🎡", "common", { type = "level", n = 2 }),
	c("title", "ti_survivor", "🩹", "rare", { type = "wins", n = 3 }),
	c("title", "ti_lucky", "🍀", "rare", { type = "coins", n = 800 }),
	c("title", "ti_hotstreak", "🔥", "epic", { type = "streak", n = 3 }),
	c("title", "ti_untouchable", "🛡️", "epic", { type = "wins", n = 50 }),
	c("title", "ti_master", "🧠", "legendary", { type = "level", n = 30 }),
	c("title", "ti_earlybird", "🐣", "rare", { type = "code" }),
	c("title", "ti_founder", "🏅", "epic", { type = "starter" }),
	c("title", "ti_graduate", "🎓", "common", { type = "event", key = "tutorial" }),
	c("title", "ti_silver", "🥈", "rare", { type = "league", key = "silver" }),
	c("title", "ti_gold", "🥇", "epic", { type = "league", key = "gold" }),
	c("title", "ti_diamond", "💎", "legendary", { type = "league", key = "diamond" }),
	c("title", "ti_champion", "👑", "legendary", { type = "league", key = "champion" }),
	c("title", "ti_vip", "⭐", "legendary", { type = "pass", key = "VIP" }),

	-- auras
	c("aura", "a_none", "🚫", "common", { type = "default" }),
	c("aura", "a_sparks", "✨", "rare", { type = "coins", n = 1000 }, { color = { 255, 230, 120 }, shape = "sparks" }),
	c("aura", "a_hearts", "💗", "rare", { type = "coins", n = 1400 }, { color = { 255, 120, 180 }, shape = "rise" }),
	c("aura", "a_frost", "❄️", "epic", { type = "level", n = 15 }, { color = { 170, 225, 255 }, shape = "orbit" }),
	c("aura", "a_flames", "🔥", "epic", { type = "coins", n = 3200 }, { color = { 255, 120, 40 }, shape = "rise" }),
	c("aura", "a_stars", "🌟", "epic", { type = "league", key = "platinum" }, { color = { 200, 160, 255 }, shape = "orbit" }),
	c("aura", "a_gold", "👑", "legendary", { type = "pass", key = "VIP" }, { color = { 255, 215, 90 }, shape = "orbit" }),
	c("aura", "a_core", "🔋", "rare", { type = "event", key = "core" }, { color = { 0, 240, 255 }, shape = "sparks" }),
} :: { Cosmetic }
Config.CosmeticById = {} :: { [string]: Cosmetic }
for _, item in Config.Cosmetics do
	Config.CosmeticById[item.id] = item
end
Config.DefaultEquipped = { wheel = "w_classic", table = "t_default", finisher = "f_hammer", title = "ti_rookie", aura = "a_none" }
Config.EmoteSlots = 4
Config.EmoteSlotsPack = 8
Config.DefaultEmotes = { "e_wave", "e_laugh", "e_gg", "e_sweat" }
Config.EmoteCooldown = 2.5

---------------------------------------------------------------------------
-- Monetization. IDs are 0 until the owner creates them in the Creator Dashboard
-- (items with ID 0 stay hidden). `affectsMatch` must stay false on every entry.
---------------------------------------------------------------------------
Config.Passes = {
	{ key = "VIP", id = 0, price = 299, icon = "⭐", affectsMatch = false, coinMult = 1.5, xpMult = 1.5 },
	{ key = "DoubleCoins", id = 0, price = 149, icon = "🪙", affectsMatch = false, coinMult = 2, xpMult = 1 },
	{ key = "LegendSkins", id = 0, price = 199, icon = "🎨", affectsMatch = false, coinMult = 1, xpMult = 1 },
	{ key = "FinisherPack", id = 0, price = 149, icon = "🛸", affectsMatch = false, coinMult = 1, xpMult = 1 },
	{ key = "EmotePack", id = 0, price = 79, icon = "🕺", affectsMatch = false, coinMult = 1, xpMult = 1 },
	{ key = "AutoCharge", id = 0, price = 99, icon = "🔋", affectsMatch = false, coinMult = 1, xpMult = 1 },
}
Config.PassByKey = {} :: { [string]: typeof(Config.Passes[1]) }
for _, p in Config.Passes do
	Config.PassByKey[p.key] = p
end
Config.Products = {
	{ key = "CoinsS", id = 0, price = 49, icon = "🪙", kind = "coins", amount = 1000, affectsMatch = false },
	{ key = "CoinsM", id = 0, price = 99, icon = "💰", kind = "coins", amount = 2500, affectsMatch = false },
	{ key = "CoinsL", id = 0, price = 249, icon = "🏦", kind = "coins", amount = 7500, affectsMatch = false },
	{ key = "CoinsXL", id = 0, price = 499, icon = "💎", kind = "coins", amount = 18000, affectsMatch = false },
	{ key = "StarterPack", id = 0, price = 49, icon = "🎁", kind = "starter", amount = 1, affectsMatch = false },
	{ key = "ServerParty", id = 0, price = 25, icon = "🎉", kind = "party", amount = 50, affectsMatch = false },
}
Config.ProductByKey = {} :: { [string]: typeof(Config.Products[1]) }
for _, p in Config.Products do
	Config.ProductByKey[p.key] = p
end
Config.StarterPack = { windowSeconds = 86400, fullPrice = 199, coins = 1500, items = { "w_arcade", "ti_founder", "f_confetti" } }

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
-- 7-day streak: fixed calendar, nothing random.
Config.DailyRewards = {
	{ kind = "coins", amount = 100 },
	{ kind = "coins", amount = 150 },
	{ kind = "coins", amount = 200 },
	{ kind = "xp", amount = 150 },
	{ kind = "coins", amount = 350 },
	{ kind = "coins", amount = 500 },
	{ kind = "item", amount = 1000, item = "w_galaxy" }, -- coins instead if already owned
}
-- Session gifts (minutes played this session).
Config.Gifts = {
	{ minutes = 5, reward = { kind = "coins", amount = 60 } },
	{ minutes = 10, reward = { kind = "coins", amount = 120 } },
	{ minutes = 15, reward = { kind = "xp", amount = 100 } },
	{ minutes = 25, reward = { kind = "coins", amount = 250 } },
	{ minutes = 40, reward = { kind = "coins", amount = 400 } },
	{ minutes = 60, reward = { kind = "coins", amount = 700 } },
}
Config.Codes = {
	SHOWDOWN = { kind = "coins", amount = 500 },
	WELCOME = { kind = "coins", amount = 250 },
	SPIN = { kind = "item", amount = 300, item = "ti_earlybird" },
} :: { [string]: { kind: string, amount: number, item: string? } }

Config.QuestsPerDay = 3
Config.QuestBonus = { coins = 200, xp = 100 }
Config.QuestPool = {
	{ kind = "play", target = 3, coins = 120, xp = 60 },
	{ kind = "win", target = 1, coins = 200, xp = 100 },
	{ kind = "zaps", target = 5, coins = 120, xp = 60 },
	{ kind = "cards", target = 4, coins = 100, xp = 50 },
	{ kind = "top3", target = 2, coins = 140, xp = 70 },
	{ kind = "elims", target = 2, coins = 160, xp = 80 },
	{ kind = "spins", target = 10, coins = 100, xp = 50 },
	{ kind = "charge", target = 200, coins = 90, xp = 40 },
	{ kind = "chaos", target = 1, coins = 110, xp = 60 },
	{ kind = "teams", target = 1, coins = 110, xp = 60 },
}

Config.Tutorial = { coins = 200, item = "ti_graduate" }
Config.Referral = { invitedCoins = 300, inviterCoins = 500, maxRewards = 25 }
Config.GroupGift = { coins = 400 }

---------------------------------------------------------------------------
-- Lobby clicker: the Power Core. Tapping charges it; a full charge pays cosmetic coins.
-- It never touches a match.
---------------------------------------------------------------------------
Config.Core = {
	tapsPerCharge = 25,
	coinsPerCharge = 1,
	maxTapsPerSecond = 8,
	burst = 6,
	range = 26, -- studs from the core
	autoRate = 3, -- taps per second while Auto Charge is ON
	autoRateVip = 5,
	autoUnlockLevel = 5, -- or the AutoCharge pass
	auraAtCharges = 200, -- lifetime charges for the "a_core" aura
}

---------------------------------------------------------------------------
-- Live events (UTC). DoubleXP every 3 h for 20 min; Chaos Weekend Sat-Sun.
---------------------------------------------------------------------------
Config.LiveEventDefs = {
	DoubleXP = { icon = "⚡", color = { 255, 205, 60 }, xpMult = 2, coinMult = 1, mode = "" },
	ChaosWeekend = { icon = "🌪️", color = { 255, 105, 180 }, xpMult = 1, coinMult = 2, mode = "chaos" },
	CoinRush = { icon = "🪙", color = { 90, 220, 130 }, xpMult = 1, coinMult = 2, mode = "" }, -- admin only
} :: { [string]: { icon: string, color: { number }, xpMult: number, coinMult: number, mode: string } }
Config.LiveEvents = {
	recurring = { { id = "DoubleXP", every = 3 * 3600, offset = 0, duration = 20 * 60 } },
	weekly = { { id = "ChaosWeekend", fromWday = 7, toWday = 1 } },
}

Config.LeaderboardSize = 10
Config.LeaderboardRefresh = 120

---------------------------------------------------------------------------
-- Audio. 0 = silent. Only the rbxasset entries ship with every Roblox install; the rest are
-- for the owner to fill with audio he has rights to (see LANZAMIENTO.md).
---------------------------------------------------------------------------
Config.Audio = {
	music = { lobby = 0, match = 0, sudden = 0, win = 0 },
	sfx = { tick = 0, heartbeat = 0, whoosh = 0, zap = 0, shield = 0, heal = 0, doom = 0, elim = 0, win = 0, card = 0, click = 0 },
	builtin = {
		tick = "rbxasset://sounds/volume_slider.ogg",
		click = "rbxasset://sounds/volume_slider.ogg",
		zap = "rbxasset://sounds/impact_explosion_03.mp3",
		elim = "rbxasset://sounds/impact_explosion_03.mp3",
		heal = "rbxasset://sounds/impact_water.mp3",
		shield = "rbxasset://sounds/action_jump_land.mp3",
		card = "rbxasset://sounds/action_jump.mp3",
		whoosh = "rbxasset://sounds/action_swim.mp3",
		heartbeat = "rbxasset://sounds/action_footsteps_plastic.mp3",
	},
}

-- Client budgets, asserted by the playtest.
Config.Budget = {
	serverParts = 2600,
	clientParts = 900, -- parts the client adds (wheels, fx pools)
	clientPartsLite = 520,
	emitters = 40,
}

return Config
