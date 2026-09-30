--!strict
-- Where the scenery goes. PURE Luau (no Roblox APIs) so tests/visual_test.luau can prove that no
-- decoration ever reaches into the playable lane. server/Scenery.luau turns each piece into parts.
--
-- Three kinds of piece per world:
--   outer : a floating set piece (island, planet, smokestack...) far outside the spiral
--   core  : an ornament stuck to the core pillar (vine, icicle, pipe, crystal...)
--   ring  : one big halo around the whole tower at the world boundary ("gate" to the next world)
local DecorPlan = {}

-- The caller passes the Layout module (shared modules don't require each other, so this file runs
-- unchanged under Roblox and under the standalone luau.exe).
export type LayoutLike = {
	STAGES: number,
	SIDES: number,
	START_ANGLE: number,
	RING_RADIUS: number,
	MAX_LAT_EXTENT: number,
	CORE_RADIUS: number,
	newRng: (seed: number) -> { next: () -> number, range: (a: number, b: number) -> number, int: (a: number, b: number) -> number },
}

export type Piece = {
	kind: string, -- outer | core | ring
	world: number, -- 1..10
	x: number,
	y: number,
	z: number,
	angle: number, -- around the tower axis (radians)
	dist: number, -- distance from the tower axis
	size: number, -- bounding radius of everything the piece may build
	variant: number, -- 1..3, picks one of the world's prop shapes
	seed: number, -- for the builder's own small random details
}

DecorPlan.OUTER_PER_WORLD = 9
DecorPlan.CORE_PER_WORLD = 12
DecorPlan.RING_RADIUS = 86
DecorPlan.RING_TUBE = 3 -- half thickness of the halo

-- The lane: every surface of a stage lies within MAX_LAT_EXTENT of the straight line between two
-- pads, and the pads sit at RING_RADIUS.
DecorPlan.CLEARANCE = 8 -- studs kept free on both sides of the lane

-- (inner, outer) distance of the lane from the tower axis: ~42.5 and ~69.5 studs.
function DecorPlan.lane(Layout: LayoutLike): (number, number)
	local apothem = Layout.RING_RADIUS * math.cos(math.pi / Layout.SIDES)
	return apothem - Layout.MAX_LAT_EXTENT, Layout.RING_RADIUS + Layout.MAX_LAT_EXTENT
end

-- Outer pieces keep clear of two built-up places:
--   * the ground under the first world (the lobby island / a tower's base island): nothing floats
--     lower than GROUND_CLEARANCE above pad 0;
--   * the summit room and the lounge beyond it, which stick out from the last pad: the top of the
--     last world is kept free on that side of the tower (SUMMIT_WEDGE radians each way).
DecorPlan.GROUND_CLEARANCE = 38
DecorPlan.SUMMIT_WEDGE = 0.8
DecorPlan.SUMMIT_DEPTH = 55

function DecorPlan.summitAngle(Layout: LayoutLike): number
	return (Layout.START_ANGLE + Layout.STAGES * 2 * math.pi / Layout.SIDES) % (2 * math.pi)
end

local function angleDistance(a: number, b: number): number
	local d = math.abs(a - b) % (2 * math.pi)
	return math.min(d, 2 * math.pi - d)
end
DecorPlan.angleDistance = angleDistance

export type Options = {
	tower: number?, -- 1..10: each tower gets its own arrangement
	outer: number?, -- outer pieces per world (default OUTER_PER_WORLD)
	core: number?, -- core ornaments per world (default CORE_PER_WORLD)
}

-- padY[k] = height of the top of checkpoint pad k (0..STAGES) of one tower. Positions are
-- relative to that tower's axis.
function DecorPlan.generate(seed: number, padY: { [number]: number }, Layout: LayoutLike, options: Options?): { Piece }
	local opts: Options = options or {}
	local rng = Layout.newRng(seed + 4242 + ((opts.tower or 1) - 1) * 977)
	local pieces: { Piece } = {}
	local worlds = Layout.STAGES // 10
	local _, laneOuter = DecorPlan.lane(Layout)
	local summit = DecorPlan.summitAngle(Layout)
	for w = 1, worlds do
		local y0 = padY[(w - 1) * 10]
		local y1 = padY[w * 10]
		local band = y1 - y0

		local nOuter = opts.outer or DecorPlan.OUTER_PER_WORLD
		local a0 = rng.range(0, math.pi * 2)
		for i = 1, nOuter do
			local size = rng.range(13, 24)
			local minDist = laneOuter + DecorPlan.CLEARANCE + size
			local dist = minDist + rng.range(6, 58)
			-- golden-angle steps: consecutive heights end up on different sides of the tower
			local angle = a0 + i * 2.399963 + rng.range(-0.25, 0.25)
			local y = y0 + band * ((i - 0.5) / nOuter) + rng.range(-5, 5)
			if w == 1 then
				local floor = y0 + DecorPlan.GROUND_CLEARANCE
				y = floor + (y1 - floor) * ((i - 0.5) / nOuter) + rng.range(0, 4)
			end
			if w == worlds and y > y1 - DecorPlan.SUMMIT_DEPTH and angleDistance(angle, summit) < DecorPlan.SUMMIT_WEDGE then
				angle += math.pi -- the other side of the tower
			end
			table.insert(pieces, {
				kind = "outer",
				world = w,
				x = math.cos(angle) * dist,
				y = y,
				z = math.sin(angle) * dist,
				angle = angle,
				dist = dist,
				size = size,
				variant = rng.int(1, 3),
				seed = rng.int(1, 1000000),
			})
		end

		local nCore = opts.core or DecorPlan.CORE_PER_WORLD
		local c0 = rng.range(0, math.pi * 2)
		for i = 1, nCore do
			local size = rng.range(4, 7.5)
			local angle = c0 + i * 2.399963 + rng.range(-0.3, 0.3)
			local y = y0 + band * ((i - 0.5) / nCore) + rng.range(-3, 3)
			local dist = Layout.CORE_RADIUS
			table.insert(pieces, {
				kind = "core",
				world = w,
				x = math.cos(angle) * dist,
				y = y,
				z = math.sin(angle) * dist,
				angle = angle,
				dist = dist,
				size = size,
				variant = rng.int(1, 3),
				seed = rng.int(1, 1000000),
			})
		end

		if w < worlds then
			-- a little above the boundary pad so the halo frames the milestone banner
			table.insert(pieces, {
				kind = "ring",
				world = w + 1,
				x = 0,
				y = y1 + 16,
				z = 0,
				angle = 0,
				dist = DecorPlan.RING_RADIUS,
				size = DecorPlan.RING_TUBE,
				variant = 1,
				seed = rng.int(1, 1000000),
			})
		end
	end
	return pieces
end

-- True when the piece (with its whole bounding radius) stays out of the lane + clearance.
function DecorPlan.clearOfLane(p: Piece, Layout: LayoutLike): boolean
	local inner, outer = DecorPlan.lane(Layout)
	if p.kind == "core" then
		return p.dist + p.size <= inner - DecorPlan.CLEARANCE
	end
	return p.dist - p.size >= outer + DecorPlan.CLEARANCE
end

return DecorPlan
