--!strict
-- Pure-Luau unit tests for the map layout. Run from the project root: tools/luau.exe tests/world_test.luau
local WorldLayout = require("../src/shared/WorldLayout")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local width, depth = WorldLayout.plotSize()
local halfGap = WorldLayout.entranceHalfWidth()

-- ===== owner sign: beside the entrance, never in it =====
do
	local s = WorldLayout.signPlacement()
	check(not WorldLayout.signBlocksEntrance(), "sign must not overlap the entrance corridor")
	check(not WorldLayout.signBlocksEntrance(4), "sign keeps at least 4 studs of extra walking room")
	check(s.maxX < -halfGap, string.format("sign right edge %.1f is left of the gap edge %.1f", s.maxX, -halfGap))
	check(s.minX > -width / 2 - 1, "sign stays in front of its own plot (not past the corner)")
	check(s.z < -depth / 2, "sign stands outside the fence, on the hub side")
	check(s.z > -depth / 2 - 8, "sign stays close to the fence")
	-- the old layout (a 14-wide board centered on the gate) must be detected as blocking
	local oldMin, oldMax = -7, 7
	check(oldMax > -(halfGap + 2) and oldMin < halfGap + 2, "sanity: the old centered board was inside the corridor")
	-- regression guard for the guard itself: widening the board until it reaches the gap must flip the check
	local saved = WorldLayout.SIGN_GAP
	WorldLayout.SIGN_GAP = -3
	check(WorldLayout.signBlocksEntrance(), "a sign pushed into the gap is reported as blocking")
	WorldLayout.SIGN_GAP = saved
end

-- ===== plot geometry =====
do
	for i = 1, WorldLayout.PLOT_COUNT do
		local cx, cz = WorldLayout.plotCenter(i)
		local lx, lz = WorldLayout.toPlotLocal(i, cx, cz)
		check(math.abs(lx) < 1e-6 and math.abs(lz) < 1e-6, "plot center maps to local origin " .. i)
		-- a point halfway to the hub is on the hub side (negative local z) and on the path
		local hx, hz = cx * 0.5, cz * 0.5
		local _, hlz = WorldLayout.toPlotLocal(i, hx, hz)
		check(hlz < 0, "hub side is local -Z for plot " .. i)
		check(WorldLayout.onPath(i, hx, hz, 0), "path runs from the hub to plot " .. i)
		check(not WorldLayout.isClear(hx, hz, 1), "nothing may be scattered on the path of plot " .. i)
		check(not WorldLayout.isClear(cx, cz, 1), "nothing may be scattered inside plot " .. i)
		-- farmhouse spot behind the plot is reserved
		local a = WorldLayout.plotAngle(i)
		local back = WorldLayout.PLOT_DISTANCE + depth / 2 + WorldLayout.HOUSE_OFFSET
		check(not WorldLayout.isClear(math.cos(a) * back, math.sin(a) * back, 1), "farmhouse spot is reserved for plot " .. i)
	end
	check(not WorldLayout.isClear(0, 0, 1), "plaza is reserved")
	check(not WorldLayout.isClear(WorldLayout.PLAZA_RADIUS, 0, 1), "plaza edge is reserved")
	check(WorldLayout.isClear(260, 0, 3), "open field far from everything is clear")
end

-- ===== landmarks fit in the gaps =====
do
	local seen: { [string]: boolean } = {}
	for _, f in WorldLayout.Features do
		check(not seen[f.id], "unique landmark id " .. f.id)
		seen[f.id] = true
		check(WorldLayout.featureFits(f), "landmark fits between plots: " .. f.id)
		local fx, fz = WorldLayout.featureCenter(f)
		check(not WorldLayout.isClear(fx, fz, 1), "landmark area is reserved: " .. f.id)
		check(math.sqrt(fx * fx + fz * fz) - f.radius > WorldLayout.PLAZA_RADIUS + 10, "landmark is outside the plaza: " .. f.id)
	end
	check(#WorldLayout.Features == 6, "one landmark per gap")
end

print(string.format("world_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("world_test failed")
end
