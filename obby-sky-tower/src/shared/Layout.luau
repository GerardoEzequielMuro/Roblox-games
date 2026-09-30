--!strict
-- Sky Tower layout math. PURE Luau: no Roblox APIs (no Vector3, CFrame, Random, game),
-- so it can be unit-tested with the standalone luau.exe (see tests/layout_test.luau).
--
-- The game is 1,000 stages: ten towers of 100. Each tower is a hexagonal spiral: checkpoint pad k
-- (0..100) sits on a circle of radius RING_RADIUS at angle START_ANGLE + k * 60deg, and climbs by
-- a per-stage rise. Every stage is a straight run of SPAN studs between two pads, described in a
-- local frame:
--   s   = distance along the stage direction (0 = previous pad centre, SPAN = next pad centre)
--   lat = sideways offset (positive = towards the tower centre)
--   y   = height relative to the previous pad top
-- "nodes" are the surfaces the player must stand on, in order. "hazards" are everything else.
--
-- Stage numbers are GLOBAL (1..1000): tower t holds stages (t-1)*100+1 .. t*100, and its pad k is
-- the checkpoint of global stage (t-1)*100+k. Towers stand TOWER_SPACING studs apart along +X and
-- are only built while somebody is climbing them (server/Towers.luau).

local Layout = {}

Layout.STAGES = 100 -- per tower
Layout.TOWERS = 10
Layout.TOTAL = Layout.STAGES * Layout.TOWERS
Layout.TOWER_SPACING = 2400
Layout.SIDES = 6
Layout.RING_RADIUS = 60
Layout.START_ANGLE = math.pi / 2
Layout.BASE_Y = 2 -- top of pad 0 of every tower
Layout.PAD_RADIUS = 6
Layout.PAD_THICK = 1.2
Layout.MAX_LAT_EXTENT = 9.5 -- |lat| + width/2 of any node stays inside this (keeps clear of the core pillar)
Layout.CORE_RADIUS = 22
Layout.DEFAULT_SEED = 777
-- Shop decks: a wooden terrace on the OUTER side of the first pad of every world (pads 10, 20 ..
-- 90 of each tower), reached by a short bridge. Sizes live here so the layout test can prove no
-- deck ever touches the route (tests/layout_test.luau).
Layout.SHOP_NEAR = 7.5 -- pad centre -> near edge of the deck
Layout.SHOP_DEPTH = 14
Layout.SHOP_WIDTH = 23
Layout.SHOP_HEADROOM = 7.5 -- clear height over the deck (a character is 5 studs tall)

-- True for the pads (slot inside the tower) that carry a shop deck.
function Layout.hasShop(slot: number): boolean
	return slot > 0 and slot % 10 == 0 and slot < Layout.STAGES
end

-- Classic obby character: JumpPower 50 (a 6.37 stud jump), WalkSpeed 16, gravity 196.2.
-- server/init enforces these on every character and tests/layout_test.luau fails if the jump is
-- ever raised: the whole map is calibrated against it.
local JUMP_POWER = 50
local GRAVITY = 196.2
Layout.Physics = {
	walkSpeed = 16,
	jumpPower = JUMP_POWER,
	gravity = GRAVITY,
	jumpHeight = JUMP_POWER * JUMP_POWER / (2 * GRAVITY), -- 6.371
	bounceHeight = 24, -- apex height a bounce pad launches you to (client applies the velocity)
}
Layout.MAX_JUMP_POWER = 50 -- tests refuse anything higher

-- A single hop never climbs more than this (70% of the jump apex), whatever the difficulty.
Layout.MAX_STEP = 4.4
-- No jump ever uses more than this share of the physical reach (edge to edge at WalkSpeed).
Layout.MAX_REACH = 0.93

-- Obstacle library, in unlock order.
Layout.Kinds = {
	"jumps",
	"killbricks",
	"beam",
	"conveyor",
	"truss",
	"bounce",
	"disappear",
	"moving",
	"spinner",
	"ice",
	"glass",
	"falling",
	"laser",
	"lava",
	"wallhop",
	"wind",
	"mixed",
}

-- Global stage at which each kind enters the random pool.
Layout.Unlock = {
	jumps = 1,
	killbricks = 1,
	beam = 2,
	conveyor = 3,
	truss = 4,
	bounce = 6,
	disappear = 8,
	moving = 9,
	spinner = 11,
	ice = 14,
	glass = 17,
	falling = 21,
	laser = 24,
	lava = 28,
	wallhop = 31,
	wind = 36,
	mixed = 41,
} :: { [string]: number }

-- Hand-picked kinds for the first stages so the tutorial curve is smooth.
Layout.Fixed = {
	[1] = "jumps",
	[2] = "killbricks",
	[3] = "beam",
	[4] = "truss",
	[5] = "jumps",
	[6] = "bounce",
	[7] = "conveyor",
	[8] = "disappear",
	[9] = "moving",
	[10] = "killbricks",
} :: { [number]: string }

export type Vec = { x: number, y: number, z: number }

export type Node = {
	kind: string, -- platform | beam | moving | disappear | ice | conveyor | bounce | glass | falling | truss | ledge
	s: number,
	lat: number,
	y: number, -- top surface height (relative)
	len: number, -- along s
	width: number, -- along lat
	thick: number,
	yBottom: number?, -- truss only: bottom of the climbable part
	moveAxis: string?, -- moving only: "lat" | "y"
	moveAmp: number?,
	movePeriod: number?,
	movePhase: number?,
	pushLat: number?, -- conveyor velocity (lateral component)
	pushS: number?, -- conveyor velocity (along s, negative = pushes back)
	delay: number?, -- disappear / falling: seconds after touch
}

export type Hazard = {
	kind: string, -- killstrip | killcube | spinner | lava | wall | laser | wind
	s: number,
	lat: number,
	y: number, -- bottom (relative)
	len: number,
	width: number,
	height: number,
	speed: number?, -- spinner rad/s
	bars: number?, -- spinner bar count
	period: number?, -- lava / laser cycle seconds
	maxRise: number?, -- lava: top height at peak (relative)
	duty: number?, -- laser: share of the period the beam is ON
	phase: number?, -- laser: 0..1 offset into the period
	push: number?, -- wind: lateral speed (studs/s, sign = direction along lat)
}

export type Coin = { id: number, s: number, lat: number, y: number }

export type Stage = {
	index: number, -- global stage number (1..1000)
	slot: number, -- 1..100 inside its tower
	tower: number,
	kind: string,
	theme: number, -- look of the world this stage belongs to (index into Config.Themes)
	difficulty: number,
	reach: number, -- share of the physical jump reach this stage aims for
	from: Vec,
	to: Vec,
	dirX: number,
	dirZ: number,
	span: number,
	rise: number,
	nodes: { Node },
	hazards: { Hazard },
	coins: { Coin },
	maxRel: number, -- highest structure top, relative to from.y
}

export type Map = {
	seed: number,
	tower: number,
	origin: Vec, -- world position of the tower axis at y = 0
	pads: { [number]: Vec }, -- 0..STAGES (top-centre of each checkpoint pad), world coordinates
	stages: { Stage }, -- 1..STAGES (stage i has global index (tower-1)*100+i)
}

---------------------------------------------------------------------------------------------
-- Deterministic RNG (Park-Miller). Products stay < 2^53 so it is bit-exact everywhere.
---------------------------------------------------------------------------------------------
export type Rng = {
	next: () -> number,
	range: (a: number, b: number) -> number,
	int: (a: number, b: number) -> number,
}

function Layout.newRng(seed: number): Rng
	local state = (math.floor(math.abs(seed)) % 2147483646) + 1
	local function nextValue(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	return {
		next = nextValue,
		range = function(a: number, b: number): number
			return a + (b - a) * nextValue()
		end,
		int = function(a: number, b: number): number
			return math.min(b, a + math.floor(nextValue() * (b - a + 1)))
		end,
	}
end

---------------------------------------------------------------------------------------------
-- Physics helpers
---------------------------------------------------------------------------------------------
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
Layout.lerp = lerp

-- Time in the air when jumping (apex jumpH) and landing dh studs higher. nil = unreachable.
function Layout.airTime(dh: number, jumpH: number?): number?
	local P = Layout.Physics
	local h = jumpH or P.jumpHeight
	local v0 = math.sqrt(2 * P.gravity * h)
	local disc = v0 * v0 - 2 * P.gravity * dh
	if disc < 0 then
		return nil
	end
	return (v0 + math.sqrt(disc)) / P.gravity
end

-- Max horizontal edge-to-edge distance you can clear at WalkSpeed, landing dh higher.
function Layout.maxGap(dh: number, jumpH: number?): number
	local t = Layout.airTime(dh, jumpH)
	if not t then
		return 0
	end
	return Layout.Physics.walkSpeed * t
end

---------------------------------------------------------------------------------------------
-- Difficulty. Two curves over the GLOBAL stage number g (1..1000):
--   difficulty(g) 0..1 : sizes and speeds (platform size, mover speed, fade delay, kill bricks...)
--   reach(g)           : share of the physical jump reach the gaps aim for
-- Easy for the first ten stages (don't lose the newcomer), properly hard from the middle of
-- tower 1, and creeping towards the limit over towers 2..10.
---------------------------------------------------------------------------------------------
function Layout.towerOf(g: number): number
	return math.clamp((math.max(g, 1) - 1) // Layout.STAGES + 1, 1, Layout.TOWERS)
end

-- 1..100: position of global stage g inside its tower.
function Layout.slotOf(g: number): number
	return (math.max(g, 1) - 1) % Layout.STAGES + 1
end

function Layout.difficulty(g: number): number
	local base
	if g <= Layout.STAGES then
		base = 0.8 * ((g - 1) / (Layout.STAGES - 1)) ^ 0.55
	else
		base = 0.78 + 0.22 * ((g - Layout.STAGES) / (Layout.TOTAL - Layout.STAGES)) ^ 0.7
	end
	-- a small saw-tooth inside every 10-stage world: each world ends harder than it starts
	local inWorld = ((g - 1) % 10) / 9
	return math.clamp(base + inWorld * 0.04, 0, 1)
end

function Layout.reach(g: number): number
	if g <= 10 then
		return lerp(0.42, 0.58, (g - 1) / 9)
	elseif g <= 50 then
		return lerp(0.6, 0.84, (g - 11) / 39)
	elseif g <= Layout.STAGES then
		return lerp(0.84, 0.93, ((g - 51) / 49) ^ 0.8)
	end
	return lerp(0.93, 0.93, ((g - Layout.STAGES - 1) / (Layout.TOTAL - Layout.STAGES - 1)) ^ 0.6)
end

-- Checkpoint spacing: every pad saves up to stage 50; after that only some do (the others are rest
-- pads: you stand on them, but a fall takes you back to the last saving pad). Milestone pads
-- (every 10 stages: world entrances, shops) always save.
function Layout.isSave(g: number): boolean
	if g <= 50 or g % 10 == 0 then
		return true
	elseif g <= 300 then
		return g % 2 == 0
	end
	local r = g % 10
	return r == 3 or r == 6
end

-- Which of the ten world looks global stage g uses. Tower 1 plays them in order; every later
-- tower starts three worlds further round, so no two towers open the same way.
function Layout.themeFor(g: number): number
	local stage = math.max(g, 1)
	local world = (Layout.slotOf(stage) - 1) // 10
	return (world + (Layout.towerOf(stage) - 1) * 3) % 10 + 1
end

-- 1..10: which world (10-stage block) of its tower global stage g is in.
function Layout.worldSlot(g: number): number
	return (Layout.slotOf(g) - 1) // 10 + 1
end

function Layout.towerOrigin(tower: number): Vec
	return { x = (tower - 1) * Layout.TOWER_SPACING, y = 0, z = 0 }
end

---------------------------------------------------------------------------------------------
-- Node / hazard helpers
---------------------------------------------------------------------------------------------
type Ctx = { rng: Rng, d: number, reach: number, span: number, rise: number, s0: number, s1: number }

-- Gap the generator aims for on a hop that climbs dh: `reach` of the physical limit, with a
-- little noise, never above MAX_REACH. Returns a huge number when the hop is too tall.
local function gapFor(c: Ctx, dh: number, scale: number?): number
	if dh > Layout.MAX_STEP then
		return 1e6
	end
	local limit = Layout.maxGap(math.max(dh, 0))
	if limit < 2.5 then
		return 1e6
	end
	local share = (c.reach + c.rng.range(-0.025, 0.025)) * (scale or 1)
	return math.clamp(limit * share, 1.2, limit * Layout.MAX_REACH)
end

local function node(kind: string, s: number, lat: number, y: number, len: number, width: number): Node
	return { kind = kind, s = s, lat = lat, y = y, len = len, width = width, thick = 1.2 }
end

local function clampLat(lat: number, width: number): number
	local lim = Layout.MAX_LAT_EXTENT - width / 2
	return math.clamp(lat, -lim, lim)
end

type ChainOpts = {
	kind: string,
	s0: number, -- where the run starts (edge of the previous surface)
	s1: number, -- where it ends (edge of the next surface)
	y0: number, -- height of the surface before the run
	y1: number, -- height of the surface after the run
	desiredLen: number,
	minLen: number,
	width: number,
	latAmp: number,
	gapScale: number?,
	maxN: number?,
}

-- Fills [s0, s1] with n platforms separated by equal gaps, climbing linearly from y0 to y1.
-- Picks n so platform length is closest to desiredLen. Returns nodes and the gap used.
local function chain(c: Ctx, o: ChainOpts): ({ Node }, number)
	local rng = c.rng
	local span = o.s1 - o.s0
	local bestN, bestG, bestL, bestScore = 0, 0, 0, math.huge
	local fallN, fallG, fallL = 0, 0, 0
	for n = 1, o.maxN or 14 do
		local dh = (o.y1 - o.y0) / (n + 1)
		local g = gapFor(c, dh, o.gapScale)
		local L = (span - (n + 1) * g) / n
		if L >= o.minLen then
			local score = math.abs(L - o.desiredLen)
			if score < bestScore then
				bestN, bestG, bestL, bestScore = n, g, L, score
			end
		end
		-- safety net: the platform count whose (shrunk) gaps still fit with the shortest platforms
		if g < 1e5 and fallN == 0 then
			local gFit = math.min(g, (span - n * o.minLen) / (n + 1))
			if gFit >= 1 then
				fallN, fallG, fallL = n, gFit, (span - (n + 1) * gFit) / n
			end
		end
	end
	if bestN == 0 then
		bestN, bestG, bestL = fallN, fallG, fallL
	end
	if bestN == 0 then
		-- cannot happen with the spans and rises used by the kinds below; keep the stage walkable
		bestN, bestG = 6, 1.5
		bestL = (span - (bestN + 1) * bestG) / bestN
	end
	local nodes = {}
	local dh = (o.y1 - o.y0) / (bestN + 1)
	local prevLat = 0
	for j = 1, bestN do
		local s = o.s0 + bestG * j + bestL * (j - 0.5)
		-- zig-zag: alternate side, bounded so lateral step never exceeds the platform width
		local lat = 0
		if o.latAmp > 0 then
			local side = if j % 2 == 0 then 1 else -1
			lat = side * rng.range(o.latAmp * 0.4, o.latAmp)
			lat = math.clamp(lat, prevLat - o.width, prevLat + o.width)
		end
		lat = clampLat(lat, o.width)
		prevLat = lat
		table.insert(nodes, node(o.kind, s, lat, o.y0 + dh * j, bestL, o.width))
	end
	return nodes, bestG
end

-- A kill cube on one half of a platform (stay on the safe side).
local function killCube(n: Node, side: number): Hazard
	return { kind = "killcube", s = n.s, lat = n.lat + side * n.width * 0.25, y = n.y, len = math.min(1.6, n.len * 0.4), width = n.width * 0.4, height = 1.6 }
end

---------------------------------------------------------------------------------------------
-- Stage kinds. Each returns nodes + hazards for a stage of the given span/rise.
-- (StageGenerator has the matching Roblox builder for every kind.)
---------------------------------------------------------------------------------------------
type KindResult = { nodes: { Node }, hazards: { Hazard } }

local Kinds: { [string]: (Ctx) -> KindResult } = {}

-- Classic jumps over gaps; later on, every other platform carries a kill cube.
function Kinds.jumps(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(6, 2.6, c.d),
		minLen = 2.4,
		width = lerp(6, 2.5, c.d),
		latAmp = 3,
	})
	local hazards: { Hazard } = {}
	if c.d > 0.35 then
		for i, n in nodes do
			if i % 2 == 0 and n.len >= 3.4 and n.width >= 3.4 then
				table.insert(hazards, killCube(n, if (i // 2) % 2 == 0 then 1 else -1))
			end
		end
	end
	return { nodes = nodes, hazards = hazards }
end

-- Floor pieces separated by neon-red kill strips (jump the strip or die).
function Kinds.killbricks(c: Ctx): KindResult
	local nodes, g = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(7, 3.4, c.d),
		minLen = 3,
		width = 8,
		latAmp = 0,
		gapScale = lerp(0.85, 0.95, c.d),
	})
	local hazards: { Hazard } = {}
	local prevEnd, prevY = c.s0, 0
	for i, n in nodes do
		local startS = n.s - n.len / 2
		local low = math.min(prevY, n.y)
		table.insert(hazards, {
			kind = "killstrip",
			s = (prevEnd + startS) / 2,
			lat = 0,
			y = low - 1.2,
			len = g,
			width = 8,
			height = 1.2,
		})
		prevEnd, prevY = n.s + n.len / 2, n.y
		-- kill cubes on the platforms themselves: every other one from early on, all of them later
		if n.len >= 3.2 and ((c.d > 0.2 and i % 2 == 0) or c.d > 0.6) then
			table.insert(hazards, killCube(n, if i % 2 == 0 then 1 else -1))
		end
	end
	table.insert(hazards, {
		kind = "killstrip",
		s = (prevEnd + c.s1) / 2,
		lat = 0,
		y = math.min(prevY, c.rise) - 1.2,
		len = g,
		width = 8,
		height = 1.2,
	})
	return { nodes = nodes, hazards = hazards }
end

-- Long narrow beams.
function Kinds.beam(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "beam",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(11, 14, c.d),
		minLen = 6,
		width = lerp(2.4, 1, c.d),
		latAmp = lerp(1.2, 2.2, c.d),
		gapScale = lerp(0.6, 0.92, c.d),
	})
	return { nodes = nodes, hazards = {} }
end

-- Conveyor belts pushing you backwards or sideways.
function Kinds.conveyor(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "conveyor",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(10, 12, c.d),
		minLen = 6,
		width = lerp(6, 4.5, c.d),
		latAmp = 2,
		gapScale = lerp(0.75, 0.92, c.d),
	})
	local hazards: { Hazard } = {}
	for i, n in nodes do
		if i % 2 == 1 then
			n.pushS = -lerp(6, 10, c.d)
			n.pushLat = 0
		else
			local side = if c.rng.next() < 0.5 then -1 else 1
			n.pushS = 0
			n.pushLat = side * lerp(5, 10, c.d)
			if c.d > 0.5 then
				-- a kill rail along the edge the belt carries you to
				table.insert(hazards, { kind = "killcube", s = n.s, lat = n.lat + side * (n.width / 2 - 0.3), y = n.y, len = n.len * 0.7, width = 0.6, height = 1.2 })
			end
		end
	end
	return { nodes = nodes, hazards = hazards }
end

-- Walk to a truss, climb it, walk off the top.
function Kinds.truss(c: Ctx): KindResult
	local rng = c.rng
	local nodes: { Node } = {}
	local g1 = gapFor(c, 0, lerp(0.7, 0.9, c.d))
	local walk = rng.range(8, 12)
	local a1 = node("platform", c.s0 + g1 + walk / 2, 0, 0, walk, lerp(6, 4, c.d))
	table.insert(nodes, a1)
	local trussS = a1.s + walk / 2 + 1 -- 2x2 truss glued to the end of the walkway
	local topY = c.rise - 2.5
	local t = node("truss", trussS, 0, topY, 2, 2)
	t.yBottom = 0
	table.insert(nodes, t)
	-- landing on top of the truss, then hops to the pad
	local landingStart = trussS + 1
	local landLen = lerp(5, 3.5, c.d)
	table.insert(nodes, node("platform", landingStart + landLen / 2, 0, topY, landLen, lerp(6, 4, c.d)))
	local rest = chain(c, {
		kind = "platform",
		s0 = landingStart + landLen,
		s1 = c.s1,
		y0 = topY,
		y1 = c.rise,
		desiredLen = lerp(6, 3, c.d),
		minLen = 2.6,
		width = lerp(5, 3, c.d),
		latAmp = 2,
		maxN = 5,
	})
	for _, n in rest do
		table.insert(nodes, n)
	end
	return { nodes = nodes, hazards = {} }
end

-- Bounce pad launches you up to a high ledge.
function Kinds.bounce(c: Ctx): KindResult
	local nodes: { Node } = {}
	local g1 = gapFor(c, 0, 0.8)
	local padLen = lerp(6, 4, c.d)
	local b = node("bounce", c.s0 + g1 + padLen / 2, 0, 0, padLen, lerp(6, 4, c.d))
	table.insert(nodes, b)
	-- the high ledge the bounce throws you onto, g2 past the pad, then hops to the checkpoint
	local highY = c.rise - 2.5
	local g2 = lerp(2, 5, c.d)
	local ledgeLen = lerp(7, 4, c.d)
	local ledge = node("platform", b.s + padLen / 2 + g2 + ledgeLen / 2, 0, highY, ledgeLen, lerp(6, 4, c.d))
	table.insert(nodes, ledge)
	local rest = chain(c, {
		kind = "platform",
		s0 = ledge.s + ledgeLen / 2,
		s1 = c.s1,
		y0 = highY,
		y1 = c.rise,
		desiredLen = lerp(7, 3.2, c.d),
		minLen = 2.8,
		width = lerp(5, 3.2, c.d),
		latAmp = 2,
		maxN = 6,
	})
	for _, n in rest do
		table.insert(nodes, n)
	end
	return { nodes = nodes, hazards = {} }
end

-- Platforms that fade away shortly after you touch them.
function Kinds.disappear(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "disappear",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(6, 3, c.d),
		minLen = 2.6,
		width = lerp(6, 2.8, c.d),
		latAmp = 3,
	})
	for _, n in nodes do
		n.delay = lerp(0.9, 0.45, c.d) -- floor: under ~0.45 s nobody can hop on in time
	end
	return { nodes = nodes, hazards = {} }
end

-- Platforms sliding side to side (or up and down later on).
function Kinds.moving(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "moving",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(7, 4, c.d),
		minLen = 3.6,
		width = lerp(7, 3.6, c.d),
		latAmp = 0,
		maxN = 6,
		gapScale = 0.85,
	})
	for i, n in nodes do
		local vertical = c.d > 0.4 and i % 2 == 0
		n.moveAxis = if vertical then "y" else "lat"
		n.moveAmp = if vertical then lerp(2, 3, c.d) else math.min(lerp(3.5, 6.5, c.d), Layout.MAX_LAT_EXTENT - n.width / 2)
		n.movePeriod = lerp(4.8, 2.05, c.d)
		n.movePhase = c.rng.next()
	end
	return { nodes = nodes, hazards = {} }
end

-- Wide platforms with rotating kill bars you must jump over.
function Kinds.spinner(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(18, 13, c.d),
		minLen = 11,
		width = lerp(14, 11, c.d),
		latAmp = 0,
		gapScale = lerp(0.6, 0.88, c.d), -- the easy kinds ramp too, so no kind stays a free stage late on
		maxN = 3,
	})
	local hazards: { Hazard } = {}
	for _, n in nodes do
		table.insert(hazards, {
			kind = "spinner",
			s = n.s,
			lat = n.lat,
			y = n.y + 0.9,
			len = math.min(n.len, n.width) - 0.5, -- bar length (diameter)
			width = 1,
			height = 1,
			speed = lerp(1.3, 3.4, c.d) * (if c.rng.next() < 0.5 then -1 else 1),
			bars = if c.d > 0.8 then 3 elseif c.d > 0.4 then 2 else 1,
		})
	end
	return { nodes = nodes, hazards = hazards }
end

-- Frictionless ice platforms.
function Kinds.ice(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "ice",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(7, 4, c.d),
		minLen = 3,
		width = lerp(6, 3.6, c.d),
		latAmp = 2,
		gapScale = 0.9,
	})
	return { nodes = nodes, hazards = {} }
end

-- Glass platforms that are invisible until you are close.
function Kinds.glass(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "glass",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(6, 3.4, c.d),
		minLen = 3,
		width = lerp(5, 3.0, c.d),
		latAmp = 3,
		gapScale = 0.9,
	})
	return { nodes = nodes, hazards = {} }
end

-- Platforms that drop shortly after you land.
function Kinds.falling(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "falling",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(6, 3, c.d),
		minLen = 2.6,
		width = lerp(5, 2.8, c.d),
		latAmp = 2,
	})
	for _, n in nodes do
		n.delay = lerp(0.8, 0.45, c.d)
	end
	return { nodes = nodes, hazards = {} }
end

-- Walkways crossed by laser gates that switch on and off: wait for the gap, then run.
function Kinds.laser(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(17, 13, c.d),
		minLen = 10,
		width = lerp(8, 6, c.d),
		latAmp = 0,
		gapScale = lerp(0.6, 0.88, c.d),
		maxN = 3,
	})
	local hazards: { Hazard } = {}
	local spacing = lerp(6.5, 3.6, c.d)
	local period = lerp(3.2, 1.9, c.d)
	local duty = lerp(0.45, 0.6, c.d)
	for _, n in nodes do
		-- 2.5 studs of landing room at both ends of the walkway
		local room = n.len - 5
		local gates = math.clamp(math.floor(room / spacing) + 1, 1, 4)
		for j = 1, gates do
			local offset = if gates == 1 then 0 else (j - 1) / (gates - 1) - 0.5
			table.insert(hazards, {
				kind = "laser",
				s = n.s + offset * math.min(room, spacing * (gates - 1)),
				lat = n.lat,
				y = n.y,
				len = 0.6,
				width = n.width,
				height = 7,
				period = period,
				duty = duty,
				phase = c.rng.next(),
			})
		end
	end
	return { nodes = nodes, hazards = hazards }
end

-- Staircase over a lava floor that rises on a timer.
function Kinds.lava(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(5, 3, c.d),
		minLen = 2.6,
		width = lerp(5, 2.8, c.d),
		latAmp = 3,
		gapScale = 0.88, -- the rising lava is the pressure
	})
	local lavaStart, lavaEnd = c.s0 + 1, c.s1 - 1
	return {
		nodes = nodes,
		hazards = {
			{
				kind = "lava",
				s = (lavaStart + lavaEnd) / 2,
				lat = 0,
				y = -6,
				len = lavaEnd - lavaStart,
				width = 18,
				height = 2,
				period = lerp(12, 6.5, c.d),
				maxRise = c.rise * 0.55,
			},
		},
	}
end

-- Small ledges stuck to a tall wall, climbing up (the obby "wall hop" section).
function Kinds.wallhop(c: Ctx): KindResult
	local side = if c.rng.next() < 0.5 then 1 else -1
	local ledgeW = lerp(3, 2.2, c.d)
	local nodes = chain(c, {
		kind = "ledge",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(3.5, 2.2, c.d),
		minLen = 2,
		width = ledgeW,
		latAmp = 0,
		gapScale = lerp(0.72, 0.82, c.d), -- tiny ledges at full reach were the hardest stage of each tower by far
	})
	local ledgeLat = side * 4
	for _, n in nodes do
		n.lat = ledgeLat
	end
	local wallLat = side * (4 + ledgeW / 2 + 0.5)
	return {
		nodes = nodes,
		hazards = {
			{
				kind = "wall",
				s = (c.s0 + c.s1) / 2,
				lat = wallLat,
				y = -3,
				len = c.s1 - c.s0,
				width = 1,
				height = c.rise + 9,
			},
		},
	}
end

-- Platforms in a cross-wind that pushes you sideways while you are in the air; the wind changes
-- side between zones. WIND_MAX_SHARE of WalkSpeed at most, so steering against it always works.
Layout.WIND_MAX_SHARE = 0.6
function Kinds.wind(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(7, 4, c.d),
		minLen = 3.5,
		width = lerp(7, 4.2, c.d),
		latAmp = 2,
		gapScale = lerp(0.85, 0.95, c.d),
	})
	local hazards: { Hazard } = {}
	local zones = if c.d > 0.5 then 3 else 2
	local zoneLen = (c.s1 - c.s0) / zones
	local push = math.min(lerp(4, 9, c.d), Layout.Physics.walkSpeed * Layout.WIND_MAX_SHARE)
	local side = if c.rng.next() < 0.5 then -1 else 1
	for z = 1, zones do
		table.insert(hazards, {
			kind = "wind",
			s = c.s0 + zoneLen * (z - 0.5),
			lat = 0,
			y = -4,
			len = zoneLen,
			width = Layout.MAX_LAT_EXTENT * 2,
			height = c.rise + 16,
			push = side * push,
		})
		side = -side
	end
	return { nodes = nodes, hazards = hazards }
end

-- A bit of everything: each platform of the run is a different kind (solid, fading, dropping,
-- ice, sliding), with kill cubes on the solid ones. The first and last are always solid.
function Kinds.mixed(c: Ctx): KindResult
	local nodes = chain(c, {
		kind = "platform",
		s0 = c.s0,
		s1 = c.s1,
		y0 = 0,
		y1 = c.rise,
		desiredLen = lerp(6, 3.2, c.d),
		minLen = 2.8,
		width = lerp(6, 3.1, c.d),
		latAmp = 2.5,
		gapScale = 0.9,
	})
	local hazards: { Hazard } = {}
	local cycle = { "disappear", "ice", "falling", "moving", "platform" }
	local offset = c.rng.int(0, #cycle - 1)
	local prevMoving = false
	for i, n in nodes do
		if i > 1 and i < #nodes then
			local kind = cycle[(i + offset) % #cycle + 1]
			if kind == "moving" and prevMoving then
				kind = "platform"
			end
			n.kind = kind
			if kind == "disappear" then
				n.delay = lerp(0.8, 0.3, c.d)
			elseif kind == "falling" then
				n.delay = lerp(0.7, 0.3, c.d)
			elseif kind == "moving" then
				n.moveAxis = "lat"
				n.moveAmp = math.min(lerp(2.5, 4.5, c.d), Layout.MAX_LAT_EXTENT - n.width / 2 - math.abs(n.lat))
				n.movePeriod = lerp(4.5, 2.4, c.d)
				n.movePhase = c.rng.next()
			elseif kind == "platform" and c.d > 0.5 and n.len >= 3.2 and n.width >= 3.4 then
				table.insert(hazards, killCube(n, if i % 2 == 0 then 1 else -1))
			end
			prevMoving = kind == "moving"
		end
	end
	return { nodes = nodes, hazards = hazards }
end

Layout.KindBuilders = Kinds

-- Vertical rise per kind (min, max). Every value >= 8 so the stage six steps higher on the
-- same side of the hexagon is always >= 48 studs overhead.
Layout.Rise = {
	jumps = { 8, 11 },
	killbricks = { 8, 10 },
	beam = { 8, 10 },
	conveyor = { 8, 10 },
	truss = { 14, 20 },
	bounce = { 14, 18 },
	disappear = { 8, 11 },
	moving = { 8, 10 },
	spinner = { 8, 10 },
	ice = { 8, 11 },
	glass = { 8, 11 },
	falling = { 8, 11 },
	laser = { 8, 10 },
	lava = { 10, 14 },
	wallhop = { 12, 16 },
	wind = { 8, 11 },
	mixed = { 8, 11 },
} :: { [string]: { number } }

---------------------------------------------------------------------------------------------
-- Map generation
---------------------------------------------------------------------------------------------
local function padPosition(origin: Vec, k: number, y: number): Vec
	local a = Layout.START_ANGLE + k * (2 * math.pi / Layout.SIDES)
	return { x = origin.x + Layout.RING_RADIUS * math.cos(a), y = origin.y + y, z = origin.z + Layout.RING_RADIUS * math.sin(a) }
end

local function pickKind(rng: Rng, g: number, prev1: string?, prev2: string?): string
	local fixed = Layout.Fixed[g]
	if fixed then
		return fixed
	end
	local pool = {}
	for _, k in Layout.Kinds do
		if g >= Layout.Unlock[k] and k ~= prev1 and k ~= prev2 then
			table.insert(pool, k)
		end
	end
	return pool[rng.int(1, #pool)]
end

-- Generates one tower (default: the first). The same (seed, tower) always gives the same map.
function Layout.generate(seed: number?, tower: number?): Map
	local sd = seed or Layout.DEFAULT_SEED
	local t = math.clamp(math.floor(tower or 1), 1, Layout.TOWERS)
	-- tower 1 keeps the plain seed; the others get their own stream
	local rng = Layout.newRng(sd + (t - 1) * 104729)
	local origin = Layout.towerOrigin(t)
	local pads: { [number]: Vec } = {}
	pads[0] = padPosition(origin, 0, Layout.BASE_Y)
	local stages: { Stage } = {}
	local prev1: string?, prev2: string? = nil, nil
	for i = 1, Layout.STAGES do
		local g = (t - 1) * Layout.STAGES + i
		local kind = pickKind(rng, g, prev1, prev2)
		prev2, prev1 = prev1, kind
		local r = Layout.Rise[kind]
		local rise = math.floor(rng.range(r[1], r[2]) * 2 + 0.5) / 2
		local from = pads[i - 1]
		local to = padPosition(origin, i, from.y - origin.y + rise)
		pads[i] = to
		local dx, dz = to.x - from.x, to.z - from.z
		local span = math.sqrt(dx * dx + dz * dz)
		local d = Layout.difficulty(g)
		local ctx: Ctx = {
			rng = rng,
			d = d,
			reach = Layout.reach(g),
			span = span,
			rise = rise,
			s0 = Layout.PAD_RADIUS,
			s1 = span - Layout.PAD_RADIUS,
		}
		local result = Kinds[kind](ctx)
		-- coins: 1 (2 later) above static-ish nodes
		local coins: { Coin } = {}
		local candidates = {}
		for _, n in result.nodes do
			if n.kind ~= "moving" and n.kind ~= "truss" then
				table.insert(candidates, n)
			end
		end
		if #candidates == 0 then
			candidates = table.clone(result.nodes)
		end
		local count = if d > 0.5 then 2 else 1
		for j = 1, math.min(count, #candidates) do
			local n = candidates[rng.int(1, #candidates)]
			table.insert(coins, { id = g * 10 + j, s = n.s, lat = n.lat, y = n.y + 3 })
		end
		local maxRel = rise
		for _, n in result.nodes do
			maxRel = math.max(maxRel, n.y + (if n.moveAxis == "y" then (n.moveAmp or 0) else 0))
		end
		for _, h in result.hazards do
			if h.kind ~= "wind" then
				local top = h.y + h.height
				if h.kind == "lava" then
					top = h.maxRise or top
				end
				maxRel = math.max(maxRel, top)
			end
		end
		table.insert(stages, {
			index = g,
			slot = i,
			tower = t,
			kind = kind,
			theme = Layout.themeFor(g),
			difficulty = d,
			reach = ctx.reach,
			from = from,
			to = to,
			dirX = dx / span,
			dirZ = dz / span,
			span = span,
			rise = rise,
			nodes = result.nodes,
			hazards = result.hazards,
			coins = coins,
			maxRel = maxRel + 4, -- + character/bar clearance
		})
	end
	return { seed = sd, tower = t, origin = origin, pads = pads, stages = stages }
end

-- Local stage coordinates -> world position (returns x, y, z). lat>0 points to the tower centre.
function Layout.toWorld(st: Stage, s: number, lat: number, yRel: number): (number, number, number)
	-- perpendicular pointing inward: pads go counter-clockwise, so the centre is to the left
	local px, pz = -st.dirZ, st.dirX
	-- make sure (px,pz) points toward the tower axis
	local axisX = (st.tower - 1) * Layout.TOWER_SPACING
	local mx = st.from.x + st.dirX * st.span / 2 - axisX
	local mz = st.from.z + st.dirZ * st.span / 2
	if px * -mx + pz * -mz < 0 then
		px, pz = -px, -pz
	end
	return st.from.x + st.dirX * s + px * lat, st.from.y + yRel, st.from.z + st.dirZ * s + pz * lat
end

-- Top of the highest checkpoint pad (victory room floor).
function Layout.topY(map: Map): number
	return map.pads[Layout.STAGES].y
end

return Layout
