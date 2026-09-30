--!strict
-- Pure layout math for the map (no Roblox types, so tools/luau.exe can unit-test it).
-- Convention: the hub is the origin; plot i sits on a ring and its local -Z axis points at the hub, so the
-- entrance is on the local -Z edge and "left/right" are local -X/+X when you walk in from the hub.
local WorldLayout = {}

WorldLayout.PLOT_COUNT = 6
WorldLayout.PLOT_DISTANCE = 125
WorldLayout.TILE_COLS = 6
WorldLayout.TILE_ROWS = 5
WorldLayout.TILE_SIZE = 7
WorldLayout.TILE_GAP = 1.6
WorldLayout.PLAZA_RADIUS = 46
WorldLayout.PATH_HALF_WIDTH = 5

-- Entrance: a gap in the front fence, centered, this fraction of the plot width on each side of the center.
WorldLayout.ENTRANCE_FRACTION = 0.12

-- Owner sign: stands OUTSIDE the fence, beside the entrance (never in front of it).
WorldLayout.SIGN_WIDTH = 9
WorldLayout.SIGN_HEIGHT = 3.4
WorldLayout.SIGN_GAP = 5 -- free studs between the entrance edge and the nearest sign edge
WorldLayout.SIGN_YAW_DEG = 20 -- turned a little toward the path so you read it while walking in
WorldLayout.SIGN_OUT = 3 -- studs in front of the fence line

-- "My Garden" spawn: this far inside the gate, so the camera behind you is already past the gate posts.
WorldLayout.SPAWN_INSET = 8

-- Farmhouse behind every plot (local +Z side).
WorldLayout.HOUSE_OFFSET = 15 -- from the back fence to the house center
WorldLayout.HOUSE_HALF = 12

function WorldLayout.plotSize(): (number, number)
	local step = WorldLayout.TILE_SIZE + WorldLayout.TILE_GAP
	return WorldLayout.TILE_COLS * step + 8, WorldLayout.TILE_ROWS * step + 14
end

function WorldLayout.entranceHalfWidth(): number
	local width = WorldLayout.plotSize()
	return width * WorldLayout.ENTRANCE_FRACTION
end

export type SignPlacement = { x: number, z: number, yawDeg: number, minX: number, maxX: number }

-- Plot-local position of the owner sign (center of the board) and the X span it covers once rotated.
function WorldLayout.signPlacement(): SignPlacement
	local _, depth = WorldLayout.plotSize()
	local halfGap = WorldLayout.entranceHalfWidth()
	local halfSpan = WorldLayout.SIGN_WIDTH / 2 * math.cos(math.rad(WorldLayout.SIGN_YAW_DEG)) + 0.5
	local x = -(halfGap + WorldLayout.SIGN_GAP + halfSpan)
	return {
		x = x,
		z = -depth / 2 - WorldLayout.SIGN_OUT,
		yawDeg = WorldLayout.SIGN_YAW_DEG,
		minX = x - halfSpan,
		maxX = x + halfSpan,
	}
end

-- True when any part of the sign overlaps the walk-in corridor (entrance gap + a margin on each side).
function WorldLayout.signBlocksEntrance(margin: number?): boolean
	local s = WorldLayout.signPlacement()
	local half = WorldLayout.entranceHalfWidth() + (margin or 2)
	return s.maxX > -half and s.minX < half
end

function WorldLayout.plotAngle(i: number): number
	return ((i - 1) / WorldLayout.PLOT_COUNT) * math.pi * 2 + math.pi / WorldLayout.PLOT_COUNT
end

function WorldLayout.plotCenter(i: number): (number, number)
	local a = WorldLayout.plotAngle(i)
	return math.cos(a) * WorldLayout.PLOT_DISTANCE, math.sin(a) * WorldLayout.PLOT_DISTANCE
end

-- World (x, z) -> plot-local (lx, lz). lz < 0 is toward the hub.
function WorldLayout.toPlotLocal(i: number, x: number, z: number): (number, number)
	local a = WorldLayout.plotAngle(i)
	local cx, cz = WorldLayout.plotCenter(i)
	local dx, dz = x - cx, z - cz
	-- right = (sin a, -cos a); outward (local +Z) = (cos a, sin a)
	return dx * math.sin(a) - dz * math.cos(a), dx * math.cos(a) + dz * math.sin(a)
end

export type Feature = { id: string, angleDeg: number, dist: number, radius: number }

-- Landmarks in the gaps between plots (plots sit at 30, 90, ... degrees; the gaps are at 0, 60, ...).
WorldLayout.Features = {
	{ id = "Pond", angleDeg = 0, dist = 152, radius = 30 },
	{ id = "Windmill", angleDeg = 60, dist = 150, radius = 22 },
	{ id = "HayField", angleDeg = 120, dist = 146, radius = 26 },
	{ id = "Barn", angleDeg = 180, dist = 156, radius = 32 },
	{ id = "PumpkinPatch", angleDeg = 240, dist = 146, radius = 24 },
	{ id = "Tractor", angleDeg = 300, dist = 146, radius = 22 },
} :: { Feature }

function WorldLayout.featureCenter(f: Feature): (number, number)
	local a = math.rad(f.angleDeg)
	return math.cos(a) * f.dist, math.sin(a) * f.dist
end

-- Is the point inside plot i's reserved rectangle (fence + entrance apron + farmhouse), grown by r?
function WorldLayout.inPlotArea(i: number, x: number, z: number, r: number): boolean
	local width, depth = WorldLayout.plotSize()
	local lx, lz = WorldLayout.toPlotLocal(i, x, z)
	local back = depth / 2 + WorldLayout.HOUSE_OFFSET + WorldLayout.HOUSE_HALF
	return math.abs(lx) < width / 2 + 7 + r and lz > -depth / 2 - 12 - r and lz < back + r
end

-- Is the point on the path from the plaza to plot i's entrance, grown by r?
function WorldLayout.onPath(i: number, x: number, z: number, r: number): boolean
	local a = WorldLayout.plotAngle(i)
	local along = x * math.cos(a) + z * math.sin(a)
	local side = math.abs(-x * math.sin(a) + z * math.cos(a))
	return along > 0 and along < WorldLayout.PLOT_DISTANCE and side < WorldLayout.PATH_HALF_WIDTH + 3 + r
end

-- Can a decoration of radius r stand at (x, z) without touching the plaza, a plot, a path or a landmark?
function WorldLayout.isClear(x: number, z: number, r: number): boolean
	if math.sqrt(x * x + z * z) < WorldLayout.PLAZA_RADIUS + 6 + r then
		return false
	end
	for i = 1, WorldLayout.PLOT_COUNT do
		if WorldLayout.inPlotArea(i, x, z, r) or WorldLayout.onPath(i, x, z, r) then
			return false
		end
	end
	for _, f in WorldLayout.Features do
		local fx, fz = WorldLayout.featureCenter(f)
		local dx, dz = x - fx, z - fz
		if math.sqrt(dx * dx + dz * dz) < f.radius + r then
			return false
		end
	end
	return true
end

-- Landmarks must not overlap plots, paths or each other (checked by the unit test).
function WorldLayout.featureFits(f: Feature): boolean
	local fx, fz = WorldLayout.featureCenter(f)
	for i = 1, WorldLayout.PLOT_COUNT do
		if WorldLayout.inPlotArea(i, fx, fz, f.radius - 7) or WorldLayout.onPath(i, fx, fz, f.radius) then
			return false
		end
	end
	for _, other in WorldLayout.Features do
		if other ~= f then
			local ox, oz = WorldLayout.featureCenter(other)
			local dx, dz = fx - ox, fz - oz
			if math.sqrt(dx * dx + dz * dz) < f.radius + other.radius then
				return false
			end
		end
	end
	return true
end

return WorldLayout
