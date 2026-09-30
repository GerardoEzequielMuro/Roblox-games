--!strict
-- Pure-Luau tests for the visual layer's logic. Run from the project root:
--   ../huerta-tycoon/tools/luau.exe tests/visual_test.luau
-- Checks:
--   * Ambience: one complete, sane lighting profile per world; the sky blends continuously with
--     height (no jumps), is fully "world N" away from the boundaries, and the clock takes the
--     short way round midnight;
--   * DecorPlan: every scenery piece stays out of the playable lane (+ clearance), inside its
--     world's height band, within the part budget, and the plan is deterministic;
--   * Segments: the progress-bar gradients obey the Roblox keypoint rules for every progress value.
local Layout = require("../src/shared/Layout")
local Ambience = require("../src/shared/Ambience")
local DecorPlan = require("../src/shared/DecorPlan")
local Quality = require("../src/shared/Quality")
local Segments = require("../src/shared/Segments")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		if failures <= 40 then
			print("FAIL: " .. msg)
		end
	end
end

local map = Layout.generate(Layout.DEFAULT_SEED)
local padY: { [number]: number } = {}
for k, p in map.pads do
	padY[k] = p.y
end
local WORLDS = Layout.STAGES // 10

-- Ambience ---------------------------------------------------------------------------------------
check(#Ambience.Profiles == WORLDS, ("one profile per world: %d"):format(#Ambience.Profiles))
local NUMERIC = { "clock", "brightness", "exposure", "density", "haze", "glare", "saturation", "contrast", "bloom", "bloomSize", "bloomThreshold", "rays", "stars" }
local COLORS = { "ambient", "outdoor", "atmColor", "atmDecay", "tint" }
for w, p in Ambience.Profiles do
	local prof = p :: any
	for _, f in NUMERIC do
		check(type(prof[f]) == "number" and prof[f] == prof[f], ("world %d: %s is a number"):format(w, f))
	end
	for _, f in COLORS do
		local c = prof[f]
		local ok = type(c) == "table" and #c == 3
		if ok then
			for i = 1, 3 do
				ok = ok and type(c[i]) == "number" and c[i] >= 0 and c[i] <= 255
			end
		end
		check(ok, ("world %d: %s is an RGB triple"):format(w, f))
	end
	check(p.clock >= 0 and p.clock < 24, ("world %d clock"):format(w))
	check(p.brightness >= 1 and p.brightness <= 4, ("world %d brightness %.2f keeps obstacles readable"):format(w, p.brightness))
	check(p.density >= 0 and p.density <= 0.55, ("world %d atmosphere density %.2f (higher hides the next pads)"):format(w, p.density))
	check(p.haze >= 0 and p.haze <= 3, ("world %d haze"):format(w))
	check(p.saturation >= -0.3 and p.saturation <= 0.5 and p.contrast >= -0.2 and p.contrast <= 0.3, ("world %d colour grading range"):format(w))
	check(p.bloom >= 0 and p.bloom <= 1.5 and p.bloomThreshold >= 0.8, ("world %d bloom"):format(w))
	check(p.stars >= 0 and p.stars <= 10000, ("world %d stars"):format(w))
	-- the ambient light must never drop so low that dark platforms vanish
	local a = p.ambient[1] + p.ambient[2] + p.ambient[3]
	check(a >= 200, ("world %d ambient sum %d"):format(w, a))
end

local bounds = Ambience.bounds(padY)
check(#bounds == WORLDS - 1, ("%d boundaries"):format(#bounds))
for i = 2, #bounds do
	check(bounds[i] - bounds[i - 1] > Ambience.BLEND_BELOW + Ambience.BLEND_ABOVE, ("boundaries %d and %d don't overlap their blend zones"):format(i - 1, i))
end

-- lobby = world 1, top = world 10, each pad k sees the world it belongs to
do
	local a, b, t = Ambience.blend(0, bounds)
	check(a == 1 and b == 1 and t == 0, "lobby is world 1")
	a, b, t = Ambience.blend(padY[Layout.STAGES] + 30, bounds)
	check(a == WORLDS and t == 0, "victory room is world 10")
	check(Ambience.sample(-500, bounds) == Ambience.Profiles[1], "far below = profile 1 (same table: no per-frame work)")
end
for k = 1, Layout.STAGES do
	-- eye height while standing on pad k (pads 10, 20... are the first pad of the NEXT world's look)
	local world = Ambience.worldAt(padY[k] + 5, bounds)
	local expected = math.min(WORLDS, k // 10 + 1)
	if k % 10 == 9 then
		-- the last pad before a boundary may already be inside the blend zone
		check(world == expected or world == expected + 1, ("pad %d world %d"):format(k, world))
	else
		check(world == expected, ("pad %d shows world %d, expected %d"):format(k, world, expected))
	end
end
-- mid-world heights are exactly one profile (the client then stops touching Lighting)
for w = 1, WORLDS do
	local y0 = padY[(w - 1) * 10]
	local y1 = padY[w * 10]
	local mid = (y0 + y1) / 2
	check(Ambience.sample(mid, bounds) == Ambience.Profiles[w], ("middle of world %d is its own profile"):format(w))
end

-- continuity: a 0.5-stud step never moves any value by more than a small fraction of its range
local function clockDist(a: number, b: number): number
	local d = math.abs(a - b) % 24
	return math.min(d, 24 - d)
end
local prev = Ambience.sample(-10, bounds)
local worstClock, worstBright, worstColor = 0, 0, 0
local top = padY[Layout.STAGES] + 40
local y = -10
while y < top do
	y += 0.5
	local p = Ambience.sample(y, bounds)
	worstClock = math.max(worstClock, clockDist(p.clock, prev.clock))
	worstBright = math.max(worstBright, math.abs(p.brightness - prev.brightness))
	for _, f in COLORS do
		local a, b = (p :: any)[f], (prev :: any)[f]
		for i = 1, 3 do
			worstColor = math.max(worstColor, math.abs(a[i] - b[i]))
		end
	end
	check(p.clock >= 0 and p.clock < 24, ("clock in range at y=%.1f"):format(y))
	prev = p
end
check(worstClock < 0.5, ("clock moves smoothly (worst step %.3f h)"):format(worstClock))
check(worstBright < 0.08, ("brightness moves smoothly (worst step %.3f)"):format(worstBright))
check(worstColor < 8, ("colours move smoothly (worst step %.1f / 255)"):format(worstColor))

-- clock wrap
check(math.abs(Ambience.lerpClock(23, 1, 0.5) - 0) < 1e-6 or math.abs(Ambience.lerpClock(23, 1, 0.5) - 24) < 1e-6, "23h -> 1h passes midnight")
check(math.abs(Ambience.lerpClock(1, 23, 0.5) - 0) < 1e-6 or math.abs(Ambience.lerpClock(1, 23, 0.5) - 24) < 1e-6, "1h -> 23h passes midnight")
check(math.abs(Ambience.lerpClock(10, 14, 0.25) - 11) < 1e-6, "10h -> 14h is linear")
check(Ambience.mix(Ambience.Profiles[1], Ambience.Profiles[2], 0) == Ambience.Profiles[1], "mix t=0 returns a")
check(Ambience.mix(Ambience.Profiles[1], Ambience.Profiles[2], 1) == Ambience.Profiles[2], "mix t=1 returns b")
do
	local m = Ambience.mix(Ambience.Profiles[1], Ambience.Profiles[9], 0.5)
	check(math.abs(m.brightness - (Ambience.Profiles[1].brightness + Ambience.Profiles[9].brightness) / 2) < 1e-9, "mix is a lerp")
end

-- DecorPlan --------------------------------------------------------------------------------------
local pieces = DecorPlan.generate(Layout.DEFAULT_SEED, padY, Layout)
local inner, outer = DecorPlan.lane(Layout)
check(inner > Layout.CORE_RADIUS + 10 and outer < DecorPlan.RING_RADIUS - DecorPlan.RING_TUBE - DecorPlan.CLEARANCE + 0.01, ("lane %.1f..%.1f leaves room for the core ornaments and the halo"):format(inner, outer))
local perWorld: { [number]: { [string]: number } } = {}
for i, p in pieces do
	check(p.world >= 1 and p.world <= WORLDS, ("piece %d world"):format(i))
	check(DecorPlan.clearOfLane(p, Layout), ("piece %d (%s, world %d) reaches the lane: dist %.1f size %.1f"):format(i, p.kind, p.world, p.dist, p.size))
	check(math.abs(math.sqrt(p.x * p.x + p.z * p.z) - (if p.kind == "ring" then 0 else p.dist)) < 0.01, ("piece %d position matches its distance"):format(i))
	local y0 = padY[(p.world - 1) * 10]
	local y1 = padY[p.world * 10]
	if p.kind == "ring" then
		check(math.abs(p.y - (y0 + 16)) < 0.01, ("ring of world %d sits on the boundary"):format(p.world))
	else
		check(p.y >= y0 - 6 and p.y <= y1 + 6, ("piece %d (%s) inside the height band of world %d"):format(i, p.kind, p.world))
	end
	check(p.variant >= 1 and p.variant <= 3, ("piece %d variant"):format(i))
	perWorld[p.world] = perWorld[p.world] or {}
	perWorld[p.world][p.kind] = (perWorld[p.world][p.kind] or 0) + 1
end
for w = 1, WORLDS do
	local c = perWorld[w] or {}
	check(c.outer == DecorPlan.OUTER_PER_WORLD, ("world %d has %d outer pieces"):format(w, c.outer or 0))
	check(c.core == DecorPlan.CORE_PER_WORLD, ("world %d has %d core pieces"):format(w, c.core or 0))
	check((c.ring or 0) == (if w == 1 then 0 else 1), ("world %d ring count"):format(w))
end
check(#pieces == WORLDS * (DecorPlan.OUTER_PER_WORLD + DecorPlan.CORE_PER_WORLD) + WORLDS - 1, ("piece count %d"):format(#pieces))
-- nothing floats into the lobby / base island, nor into the summit room and the lounge
local summitAngle = DecorPlan.summitAngle(Layout)
for t = 1, Layout.TOWERS do
	local m = Layout.generate(Layout.DEFAULT_SEED, t)
	local py: { [number]: number } = {}
	for k, p in m.pads do
		py[k] = p.y
	end
	local list = DecorPlan.generate(Layout.DEFAULT_SEED, py, Layout, { tower = t, outer = if t == 1 then nil else 6, core = if t == 1 then nil else 8 })
	local outerCount = 0
	for _, p in list do
		check(DecorPlan.clearOfLane(p, Layout), ("tower %d: %s piece in the lane"):format(t, p.kind))
		if p.kind == "outer" then
			outerCount += 1
			check(p.y >= py[0] + DecorPlan.GROUND_CLEARANCE - 0.01, ("tower %d: outer piece at y %.1f sits in the ground level"):format(t, p.y))
			if p.world == WORLDS and p.y > py[Layout.STAGES] - DecorPlan.SUMMIT_DEPTH then
				check(DecorPlan.angleDistance(p.angle, summitAngle) >= DecorPlan.SUMMIT_WEDGE - 1e-6, ("tower %d: outer piece in front of the summit room"):format(t))
			end
		end
	end
	check(outerCount == (if t == 1 then DecorPlan.OUTER_PER_WORLD else 6) * WORLDS, ("tower %d outer pieces %d"):format(t, outerCount))
end
do
	-- the summit room really is on that side: pad 100 sits at summitAngle
	local p100, p0 = map.pads[Layout.STAGES], map.pads[0]
	check(DecorPlan.angleDistance(math.atan2(p100.z, p100.x) % (2 * math.pi), summitAngle) < 1e-6, "pad 100 is at the summit angle")
	check(DecorPlan.angleDistance(math.atan2(p0.z, p0.x), Layout.START_ANGLE) < 1e-6, "pad 0 is at the start angle")
end
-- budget: the biggest builders use ~50 parts per outer piece and ~8 per core piece
check(#pieces <= 260, "piece budget")
-- outer pieces are spread around the tower, not bunched on one side
for w = 1, WORLDS do
	local quadrants = {}
	for _, p in pieces do
		if p.world == w and p.kind == "outer" then
			quadrants[math.floor((p.angle % (2 * math.pi)) / (math.pi / 2))] = true
		end
	end
	local n = 0
	for _ in quadrants do
		n += 1
	end
	check(n >= 3, ("world %d outer pieces cover %d quadrants"):format(w, n))
end
-- deterministic
local again = DecorPlan.generate(Layout.DEFAULT_SEED, padY, Layout)
local same = #again == #pieces
for i, p in pieces do
	local q = again[i]
	same = same and q ~= nil and q.x == p.x and q.y == p.y and q.z == p.z and q.variant == p.variant and q.seed == p.seed
end
check(same, "same seed => same scenery")
local other = DecorPlan.generate(Layout.DEFAULT_SEED + 1, padY, Layout)
check(other[1].x ~= pieces[1].x, "another seed => different scenery")
-- other seeds keep the lane clear too
for seed = 1, 25 do
	local m = Layout.generate(seed)
	local py: { [number]: number } = {}
	for k, p in m.pads do
		py[k] = p.y
	end
	for _, p in DecorPlan.generate(seed, py, Layout) do
		check(DecorPlan.clearOfLane(p, Layout), ("seed %d: %s piece in the lane"):format(seed, p.kind))
	end
end

-- Segments ---------------------------------------------------------------------------------------
local function validStops(stops: { any }, what: string)
	check(#stops >= 2 and #stops <= Segments.MAX_KEYPOINTS, ("%s: %d keypoints"):format(what, #stops))
	check(stops[1].t == 0, what .. ": starts at 0")
	check(stops[#stops].t == 1, what .. ": ends at 1")
	for i = 2, #stops do
		check(stops[i].t > stops[i - 1].t, ("%s: keypoint %d time %.4f not after %.4f"):format(what, i, stops[i].t, stops[i - 1].t))
	end
end
for n = 1, 10 do
	local stops = Segments.colorStops(n)
	validStops(stops, ("colorStops(%d)"):format(n))
	check(#stops == 2 * n, ("colorStops(%d) has two keypoints per segment"):format(n))
	for i, s in stops do
		check(s.index == (i + 1) // 2, ("colorStops(%d) keypoint %d index"):format(n, i))
	end
end
check(#Segments.colorStops(50) <= Segments.MAX_KEYPOINTS, "colorStops caps at 20 keypoints")
for stage = 0, 100 do
	local p = stage / 100
	local stops = Segments.revealStops(p)
	validStops(stops, ("revealStops(%.2f)"):format(p))
	check(stops[1].value == (if stage == 0 then 1 else 0), ("revealStops(%.2f) start"):format(p))
	check(stops[#stops].value == (if stage == 100 then 0 else 1), ("revealStops(%.2f) end"):format(p))
	for _, s in stops do
		check(s.value == 0 or s.value == 1, "reveal is a hard edge")
	end
end
for _, p in { -1, 0.0001, 0.9999, 2, 0 / 0 } do
	validStops(Segments.revealStops(p), ("revealStops(%s)"):format(tostring(p)))
end

-- lite profile rule ---------------------------------------------------------------------------
check(Quality.isLite(false, 0, false) == false, "lite: PC at automatic quality is not lite")
check(Quality.isLite(false, 10, false) == false, "lite: PC at quality 10 is not lite")
check(Quality.isLite(false, 4, false) == false, "lite: PC at quality 4 is not lite")
for level = 1, 3 do
	check(Quality.isLite(false, level, false) == true, "lite: graphics slider at " .. level .. " is lite")
end
check(Quality.isLite(true, 0, false) and Quality.isLite(true, 10, false), "lite: phones are lite at any quality")
check(Quality.isLite(false, 10, true) == true, "lite: ForceLite wins")
check(Quality.level("QualityLevel7") == 7 and Quality.level("QualityLevel10") == 10 and Quality.level("Automatic") == 0, "lite: level names")
check(Quality.NEAR_LITE < Quality.NEAR and Quality.WEATHER_RATE_LITE < 1 and Quality.WEATHER_RATE_LITE > 0, "lite: shorter cosmetic radius, fewer ambient particles")

print(("visual_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("visual_test failed")
end
