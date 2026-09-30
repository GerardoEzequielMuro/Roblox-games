--!strict
-- The Winner's Lounge: free items for everybody who has reached stage 100, handed out in the room
-- at the top of tower 1. PURE Luau catalogue + rules (server/Lounge.luau applies them).
--
-- kind
--   travel  : the teleporter (to the start of any world you have already reached)
--   roam    : glider / cloud. "Explore mode": checkpoints do not count while one is on, and turning
--             it off returns you to your checkpoint, so they cannot be used to skip stages
--   ability : dash / triple jump. They do count for progress, but the run is "assisted"
--   glow    : body glow colours
--   jumpfx  : an effect every time you jump
--   trail / effect : free cosmetics (ids in Config.Trails / Config.Effects, exclusive = "Lounge")
local Perks = {}

-- `gift` = only for owners of that tower gift (the rainbow glow is the gift of stage 700).
export type Perk = { id: string, kind: string, icon: string, color: { number }?, gift: number? }

Perks.UNLOCK_STAGE = 100

Perks.List = {
	{ id = "teleport", kind = "travel", icon = "🌀" },
	{ id = "glider", kind = "roam", icon = "🪂" },
	{ id = "cloud", kind = "roam", icon = "☁" },
	{ id = "dash", kind = "ability", icon = "💨" },
	{ id = "triplejump", kind = "ability", icon = "🦘" },
	{ id = "glow_gold", kind = "glow", icon = "🟡", color = { 255, 205, 60 } },
	{ id = "glow_cyan", kind = "glow", icon = "🔵", color = { 90, 225, 255 } },
	{ id = "glow_pink", kind = "glow", icon = "🟣", color = { 255, 110, 210 } },
	{ id = "glow_green", kind = "glow", icon = "🟢", color = { 110, 240, 130 } },
	{ id = "glow_rainbow", kind = "glow", icon = "🌈", color = { 255, 120, 220 }, gift = 7 },
	{ id = "jumpfx_ring", kind = "jumpfx", icon = "⭕", color = { 255, 255, 255 } },
	{ id = "jumpfx_stars", kind = "jumpfx", icon = "⭐", color = { 255, 230, 90 } },
	{ id = "lounge_neon", kind = "trail", icon = "🎆" },
	{ id = "lounge_sunrise", kind = "trail", icon = "🌅" },
	{ id = "lounge_stars", kind = "effect", icon = "🌟" },
} :: { Perk }

local byId: { [string]: Perk } = {}
for _, p in Perks.List do
	byId[p.id] = p
end

function Perks.get(id: string): Perk?
	return byId[id]
end

function Perks.unlocked(best: number): boolean
	return best >= Perks.UNLOCK_STAGE
end

-- Dash: a short burst, then a cooldown.
Perks.DASH_SPEED = 70
Perks.DASH_TIME = 0.18
Perks.DASH_COOLDOWN = 2.5
-- Glider: falling speed is capped at this while it is open.
Perks.GLIDE_FALL_SPEED = 9
-- Cloud: flying speed.
Perks.CLOUD_SPEED = 40

-- Extra jumps available in the air.
function Perks.airJumps(tripleJumpOn: boolean, doubleJumpActive: boolean): number
	if tripleJumpOn then
		return 2
	elseif doubleJumpActive then
		return 1
	end
	return 0
end

-- Teleporter destinations: the lobby (0) and the first pad of every world already reached, i.e.
-- every multiple of 10 up to `best`. The summit of the last tower is included when reached.
function Perks.travelTargets(best: number): { number }
	local out = { 0 }
	local g = 10
	while g <= best do
		table.insert(out, g)
		g += 10
	end
	return out
end

function Perks.canTravel(best: number, target: number): boolean
	return Perks.unlocked(best) and target >= 0 and target % 10 == 0 and target <= best
end

return Perks
