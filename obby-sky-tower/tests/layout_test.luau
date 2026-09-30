--!strict
-- Pure-Luau test for the tower layout. Run from the project root:
--   ../huerta-tycoon/tools/luau.exe tests/layout_test.luau
-- Checks, for every one of the 1,000 stages (10 towers x 100) of the deterministic map:
--   * the jump the map is calibrated for is the classic one (JumpPower 50) and nobody raised it;
--   * each consecutive pair of standable surfaces is reachable, measured against the REAL jump
--     physics (WalkSpeed 16, JumpPower 50, gravity 196.2): the share of the physical reach every
--     hop uses is recorded, never exceeds Layout.MAX_REACH, and no hop climbs more than MAX_STEP;
--   * the difficulty curve is real: easy first ten stages, reach growing decade by decade, platforms
--     shrinking, movers / lasers / fading platforms getting faster, more kill bricks;
--   * trusses touch their walkway and landing; bounce pads use the bounce apex;
--   * laser gates leave time and room to pass, wind can always be steered against, a kill cube
--     never covers a whole platform;
--   * every surface stays inside the lane (clear of the core pillar), with head-room to the stage
--     stacked six steps above;
--   * checkpoint spacing: every pad saves up to stage 50, then at most 1 (later 3) rest pads in a row;
--   * the map is identical for the same seed and different for another seed; 25 other seeds are valid.
local Layout = require("../src/shared/Layout")

local failures = 0
local checks = 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		if failures <= 40 then
			print("FAIL: " .. msg)
		end
	end
end

-- 1. the jump ------------------------------------------------------------------------------------
local P = Layout.Physics
check(P.jumpPower <= Layout.MAX_JUMP_POWER and Layout.MAX_JUMP_POWER == 50, ("JumpPower %s: the classic obby jump is 50, do not raise it"):format(tostring(P.jumpPower)))
check(math.abs(P.jumpHeight - P.jumpPower ^ 2 / (2 * P.gravity)) < 1e-9, "jumpHeight must be derived from JumpPower and gravity")
check(P.jumpHeight < 6.4, ("jump height %.3f studs (classic: 6.37)"):format(P.jumpHeight))
check(P.walkSpeed == 16 and P.gravity == 196.2, "default WalkSpeed / gravity")
check(Layout.MAX_REACH <= 0.93 and Layout.MAX_REACH >= 0.85, "MAX_REACH keeps a real margin below the physical limit")
check(Layout.MAX_STEP <= P.jumpHeight * 0.7 + 1e-9, "MAX_STEP is at most 70% of the jump apex")
check(math.abs(Layout.maxGap(0) - 2 * P.jumpPower / P.gravity * P.walkSpeed) < 1e-9, "flat reach = air time x WalkSpeed")

type Surf = {
	kind: string,
	s: number,
	lat: number,
	y: number,
	len: number,
	width: number,
	yBottom: number?,
	moveAxis: string?,
}

-- Hardest hop of a stage as a share of the physical reach (pad -> nodes -> pad). Also verifies
-- every hop. `strict` = full set of checks (default seed); otherwise reachability only.
local function verifyStage(st: Layout.Stage, label: string, strict: boolean): number
	local seq: { Surf } = {}
	table.insert(seq, { kind = "pad", s = 0, lat = 0, y = 0, len = 2 * Layout.PAD_RADIUS, width = 8 })
	for _, n in st.nodes do
		table.insert(seq, n :: any)
	end
	table.insert(seq, { kind = "pad", s = st.span, lat = 0, y = st.rise, len = 2 * Layout.PAD_RADIUS, width = 8 })
	local worst = 0
	for j = 1, #seq - 1 do
		local a, b = seq[j], seq[j + 1]
		local where = ("%s (%s) step %d->%d [%s->%s]"):format(label, st.kind, j - 1, j, a.kind, b.kind)
		local ds = (b.s - b.len / 2) - (a.s + a.len / 2)
		check(ds > -0.01, where .. (" surfaces overlap along s (%.2f)"):format(ds))
		local dl = math.max(0, math.abs(b.lat - a.lat) - (a.width + b.width) / 2)
		local gap = math.sqrt(math.max(ds, 0) ^ 2 + dl ^ 2)
		local dh = b.y - a.y
		if b.kind == "truss" then
			-- walk into the truss: must be touching and start at/below the walkway
			check(gap <= 1.5, where .. (" truss not touching walkway (gap %.2f)"):format(gap))
			check((b.yBottom or 0) <= a.y + 0.01, where .. " truss starts above walkway")
		elseif a.kind == "truss" then
			check(gap <= 1.5, where .. (" landing not touching truss (gap %.2f)"):format(gap))
			check(math.abs(dh) <= 0.01, where .. " landing not at truss top")
		else
			local jumpH = if a.kind == "bounce" then P.bounceHeight else nil
			local limit = Layout.maxGap(dh, jumpH)
			check(limit > 0, where .. (" rise %.2f is higher than the jump"):format(dh))
			if limit > 0 then
				local ratio = gap / limit
				check(ratio <= Layout.MAX_REACH + 1e-6, where .. (" gap %.2f is %.0f%% of the physical reach %.2f (dh %.2f)"):format(gap, ratio * 100, limit, dh))
				if a.kind ~= "bounce" then
					check(dh <= Layout.MAX_STEP + 1e-6, where .. (" rise %.2f > MAX_STEP"):format(dh))
					worst = math.max(worst, ratio)
				end
			end
			if strict then
				check(gap >= 1, where .. (" gap %.2f: surfaces nearly touching"):format(gap))
			end
		end
	end
	return worst
end

local kindCount: { [string]: number } = {}
local stageWorst: { [number]: number } = {} -- global stage -> hardest hop share
local stageSize: { [number]: number } = {} -- global stage -> smallest standable dimension
local worstRatio, worstWhere = 0, ""
local lasers, winds, cubes = 0, 0, 0
local totalHeight = 0

for t = 1, Layout.TOWERS do
	local map = Layout.generate(Layout.DEFAULT_SEED, t)
	check(#map.stages == Layout.STAGES, ("tower %d stage count"):format(t))
	check(map.tower == t and map.origin.x == (t - 1) * Layout.TOWER_SPACING, ("tower %d origin"):format(t))
	local axisX = map.origin.x

	for i, st in map.stages do
		local g = (t - 1) * Layout.STAGES + i
		local label = ("stage %d"):format(g)
		check(st.index == g and st.slot == i and st.tower == t, label .. " numbering")
		check(st.theme >= 1 and st.theme <= 10 and st.theme == Layout.themeFor(g), label .. " theme")
		kindCount[st.kind] = (kindCount[st.kind] or 0) + 1
		check(g >= Layout.Unlock[st.kind], label .. (" uses %s before it unlocks"):format(st.kind))
		check(math.abs(st.span - 60) < 0.01, label .. (" span %.2f"):format(st.span))
		check(st.rise >= 8, label .. (" rise %.1f < 8"):format(st.rise))
		check(math.abs(st.reach - Layout.reach(g)) < 1e-9 and math.abs(st.difficulty - Layout.difficulty(g)) < 1e-9, label .. " difficulty fields")

		local worst = verifyStage(st, label, true)
		stageWorst[g] = worst
		if worst > worstRatio then
			worstRatio, worstWhere = worst, label .. " (" .. st.kind .. ")"
		end

		local smallest = math.huge
		for _, n in st.nodes do
			check(math.abs(n.lat) + n.width / 2 <= Layout.MAX_LAT_EXTENT + 0.01, label .. " node out of lane")
			check(n.len >= 1.9 and n.width >= 1, label .. (" node too small (%.2f x %.2f)"):format(n.len, n.width))
			local x, _, z = Layout.toWorld(st, n.s, n.lat, n.y)
			check(math.sqrt((x - axisX) ^ 2 + z * z) > Layout.CORE_RADIUS + 5, label .. " node hits the core pillar")
			if n.kind ~= "truss" then
				smallest = math.min(smallest, n.len, n.width)
			end
			if n.kind == "moving" then
				local amp = n.moveAmp or 0
				check((n.movePeriod or 0) >= 2, label .. " mover faster than a 2 s cycle")
				if n.moveAxis == "lat" then
					check(math.abs(n.lat) + amp + n.width / 2 <= Layout.MAX_LAT_EXTENT + 0.01, label .. " mover leaves the lane")
				else
					check(amp <= Layout.MAX_STEP - 1, label .. " vertical mover travels too far")
				end
			elseif n.kind == "disappear" or n.kind == "falling" then
				check((n.delay or 0) >= 0.25, label .. " platform vanishes in under 0.25 s")
			elseif n.kind == "conveyor" then
				check(math.abs(n.pushS or 0) <= 10 and math.abs(n.pushLat or 0) <= 10, label .. " belt faster than 10 studs/s")
			end
		end
		-- only the kinds built from plain small platforms (walkways, belts and beams have their own sizes)
		if st.kind == "jumps" or st.kind == "disappear" or st.kind == "falling" or st.kind == "glass" or st.kind == "lava" or st.kind == "mixed" then
			stageSize[g] = smallest
		end

		local gates: { [number]: { number } } = {} -- node index -> gate positions
		for _, h in st.hazards do
			if h.kind == "lava" then
				check((h.maxRise or 0) < st.rise - 2, label .. " lava reaches the exit pad")
				check((h.period or 0) >= 6, label .. " lava cycle under 6 s")
			elseif h.kind == "laser" then
				lasers += 1
				local period, duty = h.period or 0, h.duty or 1
				check(period * (1 - duty) >= 0.65, label .. (" laser is off for only %.2f s"):format(period * (1 - duty)))
				check(duty >= 0.3 and duty <= 0.65, label .. " laser duty")
				-- the walkway it stands on, and the room on both sides
				local host: Layout.Node? = nil
				for ni, n in st.nodes do
					if math.abs(h.s - n.s) <= n.len / 2 and math.abs(h.y - n.y) < 0.01 then
						host = n
						gates[ni] = gates[ni] or {}
						table.insert(gates[ni], h.s)
					end
				end
				check(host ~= nil, label .. " laser not on a walkway")
				if host then
					local room = math.min(h.s - (host.s - host.len / 2), (host.s + host.len / 2) - h.s)
					check(room >= 2.4, label .. (" laser %.2f studs from the walkway end"):format(room))
					check(h.width >= host.width - 0.01, label .. " laser does not span the walkway")
				end
			elseif h.kind == "wind" then
				winds += 1
				check(math.abs(h.push or 0) <= P.walkSpeed * Layout.WIND_MAX_SHARE + 1e-9 and math.abs(h.push or 0) >= 3, label .. " wind speed")
			elseif h.kind == "killcube" then
				cubes += 1
				-- the platform it sits on keeps a free strip to walk past it
				for _, n in st.nodes do
					if math.abs(h.s - n.s) <= n.len / 2 and math.abs(h.y - n.y) < 0.01 and math.abs(h.lat - n.lat) <= n.width / 2 then
						local left = (h.lat - h.width / 2) - (n.lat - n.width / 2)
						local right = (n.lat + n.width / 2) - (h.lat + h.width / 2)
						check(math.max(left, right) >= 1.5, label .. (" kill cube leaves only %.2f studs"):format(math.max(left, right)))
					end
				end
			elseif h.kind == "spinner" then
				check(math.abs(h.speed or 0) <= 3.5 and (h.bars or 1) <= 3, label .. " spinner speed / bars")
			end
		end
		for _, list in gates do
			table.sort(list)
			for j = 2, #list do
				check(list[j] - list[j - 1] >= 3.5, label .. (" laser gates %.2f apart"):format(list[j] - list[j - 1]))
			end
		end
		if st.kind == "wind" then
			for _, n in st.nodes do
				check(n.width >= 3.5, label .. " wind platform narrower than 3.5")
			end
		end
		check(#st.coins >= 1, label .. " has no coin")

		-- head-room vs the stage stacked six steps above (same hexagon side)
		local above = map.stages[i + Layout.SIDES]
		if above then
			local m = 0
			for _, n in above.nodes do
				m = math.min(m, n.y - n.thick)
			end
			for _, h in above.hazards do
				if h.kind ~= "lava" and h.kind ~= "wind" then
					m = math.min(m, h.y)
				end
			end
			local headroom = above.from.y + m - (st.from.y + st.maxRel)
			check(headroom >= 20, label .. (" head-room %.1f < 20"):format(headroom))
		end
	end

	for k = 1, Layout.STAGES do
		check(map.pads[k].y > map.pads[k - 1].y, ("tower %d pad %d not above pad %d"):format(t, k, k - 1))
	end
	check(math.abs(map.pads[0].y - Layout.BASE_Y) < 1e-9, ("tower %d starts at BASE_Y"):format(t))
	totalHeight += map.pads[Layout.STAGES].y - map.pads[0].y
end

-- 2. the difficulty curve ----------------------------------------------------------------------
local function decadeMean(tbl: { [number]: number }, d: number): number
	local sum = 0
	for g = (d - 1) * 10 + 1, d * 10 do
		sum += tbl[g]
	end
	return sum / 10
end
for g = 1, 10 do
	check(stageWorst[g] <= 0.64, ("tutorial stage %d uses %.0f%% of the jump reach (max 64%%)"):format(g, stageWorst[g] * 100))
end
check(decadeMean(stageWorst, 1) <= 0.55, ("first ten stages average %.0f%% of the reach"):format(decadeMean(stageWorst, 1) * 100))
check(decadeMean(stageWorst, 5) >= 0.64, ("stages 41-50 average %.0f%% of the reach (must be >= 64%%)"):format(decadeMean(stageWorst, 5) * 100))
check(decadeMean(stageWorst, 10) >= 0.72, ("stages 91-100 average %.0f%% of the reach (must be >= 72%%)"):format(decadeMean(stageWorst, 10) * 100))
-- reach(g) itself never goes down, and quarter by quarter the measured hops get harder
for g = 2, Layout.TOTAL do
	check(Layout.reach(g) >= Layout.reach(g - 1) - 1e-9, ("reach(%d) dips"):format(g))
	check(Layout.reach(g) <= Layout.MAX_REACH, ("reach(%d) above MAX_REACH"):format(g))
end
local function blockMean(tbl: { [number]: number }, a: number, b: number): number
	local sum, n = 0, 0
	for g = a, b do
		if tbl[g] then
			sum += tbl[g]
			n += 1
		end
	end
	return sum / math.max(n, 1)
end
local q1, q2, q3, q4 = blockMean(stageWorst, 1, 25), blockMean(stageWorst, 26, 50), blockMean(stageWorst, 51, 75), blockMean(stageWorst, 76, 100)
check(q1 < q2 and q2 < q3 and q3 < q4, ("tower 1 quarters must get harder: %.2f %.2f %.2f %.2f"):format(q1, q2, q3, q4))
local prevTower = blockMean(stageWorst, 1, 100)
for t = 2, Layout.TOWERS do
	local m = blockMean(stageWorst, (t - 1) * 100 + 1, t * 100)
	-- (the mix of obstacle kinds moves a tower's average a few points: walkways with spinners or
	-- lasers use short hops on purpose)
	check(m >= 0.76, ("tower %d averages %.0f%% of the reach (must be >= 76%%)"):format(t, m * 100))
	check(m >= prevTower - 0.04, ("tower %d (%.3f) is easier than tower %d (%.3f)"):format(t, m, t - 1, prevTower))
	prevTower = m
end
-- platforms shrink: smallest standable dimension, averaged
local s1, s2, s3 = blockMean(stageSize, 1, 20), blockMean(stageSize, 81, 100), blockMean(stageSize, 901, 1000)
check(s1 > s2 + 1.2 and s2 > s3 + 0.2 and s3 <= 3.3, ("platforms must shrink: %.2f -> %.2f -> %.2f studs"):format(s1, s2, s3))
check(Layout.difficulty(1) == 0 and Layout.difficulty(Layout.TOTAL) == 1, "difficulty spans 0..1")
for g = 11, Layout.TOTAL, 10 do
	check(Layout.difficulty(g + 9) > Layout.difficulty(g), ("world starting at %d ends harder than it starts"):format(g))
end
check(lasers >= 40 and winds >= 40 and cubes >= 250, ("new hazards in play: %d lasers, %d wind zones, %d kill cubes"):format(lasers, winds, cubes))

-- 3. checkpoint spacing ------------------------------------------------------------------------
local run, longestEarly, longestLate = 0, 0, 0
for g = 1, Layout.TOTAL do
	if g <= 50 or g % 10 == 0 then
		check(Layout.isSave(g), ("stage %d must be a saving checkpoint"):format(g))
	end
	if Layout.isSave(g) then
		run = 0
	else
		run += 1
		if g <= 300 then
			longestEarly = math.max(longestEarly, run)
		else
			longestLate = math.max(longestLate, run)
		end
	end
end
check(longestEarly == 1, ("stages 51-300: %d rest pads in a row (expected 1)"):format(longestEarly))
check(longestLate == 3, ("stages 301-1000: %d rest pads in a row (expected 3)"):format(longestLate))
check(Layout.towerOf(1) == 1 and Layout.towerOf(100) == 1 and Layout.towerOf(101) == 2 and Layout.towerOf(1000) == 10, "towerOf")
check(Layout.slotOf(100) == 100 and Layout.slotOf(101) == 1 and Layout.worldSlot(101) == 1 and Layout.worldSlot(200) == 10, "slotOf / worldSlot")
do
	-- every tower opens with a different world look and plays all ten
	local opens = {}
	for t = 1, Layout.TOWERS do
		local seen = {}
		for w = 1, 10 do
			seen[Layout.themeFor((t - 1) * 100 + (w - 1) * 10 + 1)] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		check(n == 10, ("tower %d uses %d of the 10 world looks"):format(t, n))
		opens[Layout.themeFor((t - 1) * 100 + 1)] = true
	end
	local n = 0
	for _ in opens do
		n += 1
	end
	check(n == 10, "each tower opens with a different world")
	check(Layout.themeFor(1) == 1 and Layout.themeFor(95) == 10, "tower 1 plays the worlds in order")
end

-- 4. determinism -------------------------------------------------------------------------------
for _, t in { 1, 7 } do
	local a, b = Layout.generate(Layout.DEFAULT_SEED, t), Layout.generate(Layout.DEFAULT_SEED, t)
	local same = true
	for i, st in a.stages do
		local o = b.stages[i]
		if o.kind ~= st.kind or o.rise ~= st.rise or #o.nodes ~= #st.nodes then
			same = false
		else
			for j, n in st.nodes do
				if n.s ~= o.nodes[j].s or n.lat ~= o.nodes[j].lat or n.y ~= o.nodes[j].y then
					same = false
				end
			end
		end
	end
	check(same, ("tower %d: same seed must give the same map"):format(t))
end
do
	local a, b = Layout.generate(Layout.DEFAULT_SEED, 1), Layout.generate(Layout.DEFAULT_SEED + 1, 1)
	local differs = false
	for i, st in a.stages do
		if b.stages[i].kind ~= st.kind or b.stages[i].rise ~= st.rise then
			differs = true
		end
	end
	check(differs, "different seed should give a different map")
	local c = Layout.generate(Layout.DEFAULT_SEED, 2)
	differs = false
	for i, st in a.stages do
		if i > 10 and (c.stages[i].kind ~= st.kind or c.stages[i].rise ~= st.rise) then
			differs = true
		end
	end
	check(differs, "tower 2 is not a copy of tower 1")
	check(Layout.generate().tower == 1, "generate() defaults to tower 1")
end

-- 5. other seeds must also be valid (generator robustness), reachability only -------------------
for seed = 1, 25 do
	for _, t in { 1, (seed % 9) + 2 } do
		local m = Layout.generate(seed * 7919, t)
		for _, st in m.stages do
			verifyStage(st, ("seed %d stage %d"):format(seed * 7919, st.index), false)
		end
	end
end

-- shop decks never touch the route ------------------------------------------------------------------
-- (a deck is a rectangle on the outer side of pads 10, 20 .. 90; nothing of any stage - platform,
-- hazard - may be inside it or in the head-room over it, in any of the ten towers)
do
	local shops, closest = 0, math.huge
	for t = 1, Layout.TOWERS do
		local map = Layout.generate(nil, t)
		for slot = 1, Layout.STAGES do
			if Layout.hasShop(slot) then
				shops += 1
				local pad = map.pads[slot]
				local ox, oz = pad.x - map.origin.x, pad.z - map.origin.z
				local om = math.sqrt(ox * ox + oz * oz)
				ox, oz = ox / om, oz / om -- outward
				local tx, tz = -oz, ox -- along the deck
				local yLow, yHigh = pad.y - 1, pad.y + Layout.SHOP_HEADROOM
				local function clear(what: string, wx: number, wy0: number, wy1: number, wz: number, radius: number)
					if wy1 < yLow or wy0 > yHigh then
						return
					end
					local dOut = (wx - pad.x) * ox + (wz - pad.z) * oz
					local dTan = (wx - pad.x) * tx + (wz - pad.z) * tz
					-- distance from the deck rectangle (0 = inside)
					local a = math.max(Layout.SHOP_NEAR - dOut, 0, dOut - (Layout.SHOP_NEAR + Layout.SHOP_DEPTH))
					local b = math.max(math.abs(dTan) - Layout.SHOP_WIDTH / 2, 0)
					local dist = math.sqrt(a * a + b * b) - radius
					closest = math.min(closest, dist)
					check(dist > 0, ("tower %d shop at pad %d: %s is inside the deck (%.1f studs in)"):format(t, slot, what, -dist))
				end
				for _, st in map.stages do
					for i, n in st.nodes do
						local wx, wy, wz = Layout.toWorld(st, n.s, n.lat, n.y)
						local amp = if n.kind == "moving" and n.moveAxis == "lat" then (n.moveAmp or 0) else 0
						local ampY = if n.kind == "moving" and n.moveAxis == "y" then (n.moveAmp or 0) else 0
						clear(("stage %d node %d (%s)"):format(st.index, i, n.kind), wx, wy - n.thick - ampY, wy + ampY, wz, math.sqrt((n.len / 2) ^ 2 + (n.width / 2 + amp) ^ 2))
					end
					for i, h in st.hazards do
						local wx, wy, wz = Layout.toWorld(st, h.s, h.lat, h.y)
						local top = wy + math.max(h.height, (h.maxRise or 0) - h.y)
						clear(("stage %d hazard %d (%s)"):format(st.index, i, h.kind), wx, wy, top, wz, math.sqrt((h.len / 2) ^ 2 + (h.width / 2) ^ 2))
					end
				end
			end
		end
	end
	check(shops == Layout.TOWERS * 9, ("9 shop decks per tower (got %d in all)"):format(shops))
	print(("shop decks: %d, closest any obstacle gets to one: %.1f studs"):format(shops, closest))
end

local kinds = {}
for k, n in kindCount do
	table.insert(kinds, k .. "=" .. n)
end
table.sort(kinds)
print("kinds used (" .. #kinds .. "): " .. table.concat(kinds, ", "))
print(("jump: power %d = %.2f studs high, %.2f studs flat reach; climb per tower ~%.0f studs"):format(P.jumpPower, P.jumpHeight, Layout.maxGap(0), totalHeight / Layout.TOWERS))
print(("reach used per decade of tower 1: %s"):format((function()
	local parts = {}
	for d = 1, 10 do
		table.insert(parts, ("%.0f%%"):format(decadeMean(stageWorst, d) * 100))
	end
	return table.concat(parts, " ")
end)()))
print(("reach used per tower: %s"):format((function()
	local parts = {}
	for t = 1, Layout.TOWERS do
		table.insert(parts, ("%.0f%%"):format(blockMean(stageWorst, (t - 1) * 100 + 1, t * 100) * 100))
	end
	return table.concat(parts, " ")
end)()))
print(("smallest platform side: %.1f studs (stages 1-20) -> %.1f (81-100) -> %.1f (901-1000)"):format(s1, s2, s3))
print(("hardest jump uses %.1f%% of the physical reach at %s"):format(worstRatio * 100, worstWhere))
check(#kinds == #Layout.Kinds, ("all %d obstacle kinds must appear (got %d)"):format(#Layout.Kinds, #kinds))
print(("%d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("layout test FAILED")
end
print("layout test PASSED")
