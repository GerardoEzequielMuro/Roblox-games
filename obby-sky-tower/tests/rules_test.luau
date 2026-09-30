--!strict
-- Pure-Luau tests for the rules of the 1,000-stage game. Run from the project root:
--   ../huerta-tycoon/tools/luau.exe tests/rules_test.luau
-- Covers Shared/Rules (checkpoints, skips, portals, spawn points, the Skip button, ranked runs),
-- Shared/Gifts (ten different gifts, one per tower), Shared/Powerups (shop purchases),
-- Shared/Perks (the free lounge) and Shared/TowerStyle (tower palettes never look like a kill brick).
local Layout = require("../src/shared/Layout")
local Rules = require("../src/shared/Rules")
local Gifts = require("../src/shared/Gifts")
local Powerups = require("../src/shared/Powerups")
local Perks = require("../src/shared/Perks")
local TowerStyle = require("../src/shared/TowerStyle")
local Ambience = require("../src/shared/Ambience")

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
local function eq(a: any, b: any, msg: string)
	check(a == b, ("%s: expected %s, got %s"):format(msg, tostring(b), tostring(a)))
end
local L = Layout :: any

-- Rules: reaching pads --------------------------------------------------------------------------
check(Rules.canReach(L, 0, 1, 3, false), "0 -> 1")
check(Rules.canReach(L, 0, 3, 3, false), "0 -> 3 (three ahead is allowed)")
check(not Rules.canReach(L, 0, 4, 3, false), "0 -> 4 is too far")
check(not Rules.canReach(L, 5, 5, 3, false) and not Rules.canReach(L, 5, 4, 3, false), "not backwards")
check(Rules.canReach(L, 99, 100, 3, false), "99 -> 100")
check(not Rules.canReach(L, 99, 101, 3, false), "99 -> 101 crosses the portal")
check(not Rules.canReach(L, 100, 101, 3, false), "100 -> 101 needs the portal")
check(Rules.canReach(L, 100, 101, 3, true), "100 -> 101 from the base of tower 2")
check(Rules.canReach(L, 100, 103, 3, true) and not Rules.canReach(L, 100, 104, 3, true), "base of tower 2: three ahead")
check(not Rules.canReach(L, 1000, 1001, 3, true), "nothing after 1000")
check(not Rules.canReach(L, 998, 1001, 3, false), "998 -> 1001 does not exist")

-- Rules: skips ----------------------------------------------------------------------------------
eq(Rules.skipTarget(L, 0, 1, false), 1, "skip from the lobby")
eq(Rules.skipTarget(L, 17, 1, false), 18, "skip 1")
eq(Rules.skipTarget(L, 17, 10, false), 27, "skip 10")
eq(Rules.skipTarget(L, 95, 10, false), 100, "skip 10 stops at the summit")
eq(Rules.skipTarget(L, 100, 1, false), nil, "on the summit: no skip before the portal")
eq(Rules.skipTarget(L, 100, 1, true), 101, "on the base of tower 2")
eq(Rules.skipTarget(L, 100, 10, true), 110, "skip 10 from the base")
eq(Rules.skipTarget(L, 195, 10, false), 200, "tower 2 summit")
eq(Rules.skipTarget(L, 999, 10, false), 1000, "last stage")
eq(Rules.skipTarget(L, 1000, 1, true), nil, "nothing after 1000")
eq(Rules.skipTarget(L, 5, 0, false), nil, "skip 0")

-- Rules: spawn points ---------------------------------------------------------------------------
eq(Rules.spawn(L, 0, false, false), nil, "stage 0 = lobby")
eq(Rules.spawn(L, 40, true, false), nil, "lobby mode")
do
	local s = Rules.spawn(L, 40, false, false) :: Rules.Spot
	check(s.tower == 1 and s.pad == 40, "stage 40")
	s = Rules.spawn(L, 100, false, false) :: Rules.Spot
	check(s.tower == 1 and s.pad == 100, "stage 100 = summit of tower 1")
	s = Rules.spawn(L, 100, false, true) :: Rules.Spot
	check(s.tower == 2 and s.pad == 0, "stage 100 after the portal = base of tower 2")
	s = Rules.spawn(L, 101, false, false) :: Rules.Spot
	check(s.tower == 2 and s.pad == 1, "stage 101")
	s = Rules.spawn(L, 250, false, true) :: Rules.Spot
	check(s.tower == 3 and s.pad == 50, "stage 250")
	s = Rules.spawn(L, 1000, false, true) :: Rules.Spot
	check(s.tower == 10 and s.pad == 100, "stage 1000 has no next tower")
	s = Rules.padOf(L, 100)
	check(s.tower == 1 and s.pad == 100, "pad of 100")
	s = Rules.padOf(L, 101)
	check(s.tower == 2 and s.pad == 1, "pad of 101")
	s = Rules.padOf(L, 0)
	check(s.tower == 1 and s.pad == 0, "pad of 0")
end

local function list(t: { number }): string
	local parts = {}
	for _, v in t do
		table.insert(parts, tostring(v))
	end
	return table.concat(parts, ",")
end
eq(list(Rules.towersNeeded(L, 0, 0, false)), "1", "lobby needs tower 1")
eq(list(Rules.towersNeeded(L, 50, 52, false)), "1", "mid tower 1")
eq(list(Rules.towersNeeded(L, 90, 91, false)), "1,2", "last ten stages pre-build tower 2")
eq(list(Rules.towersNeeded(L, 100, 100, false)), "1,2", "summit: portal is ready")
eq(list(Rules.towersNeeded(L, 100, 100, true)), "2", "base of tower 2")
eq(list(Rules.towersNeeded(L, 150, 152, false)), "2", "mid tower 2")
eq(list(Rules.towersNeeded(L, 890, 893, false)), "9,10", "pre-build the last tower")
eq(list(Rules.towersNeeded(L, 1000, 1000, false)), "10", "the very top")
-- a player never needs more than two towers: the server holds at most 2 x players
for stage = 0, Layout.TOTAL do
	for _, base in { false, true } do
		local n = #Rules.towersNeeded(L, stage, stage, base)
		check(n >= 1 and n <= 2, ("stage %d needs %d towers"):format(stage, n))
	end
end

check(not Rules.portalOpen(L, 99, 1) and Rules.portalOpen(L, 100, 1), "portal 1 opens at 100")
check(not Rules.portalOpen(L, 150, 2) and Rules.portalOpen(L, 200, 2), "portal 2 opens at 200")
check(not Rules.portalOpen(L, 1000, 10), "no portal after the last tower")
eq(Rules.coinsForStage(1), 5, "coins stage 1")
eq(Rules.coinsForStage(10), 7, "coins stage 10")
eq(Rules.coinsForStage(100), 25, "coins stage 100")
eq(Rules.coinsForStage(1000), 55, "coins are capped")
check(Rules.isSummit(L, 100) and Rules.isSummit(L, 1000) and not Rules.isSummit(L, 0) and not Rules.isSummit(L, 150), "isSummit")

-- Rules: Skip Stage button --------------------------------------------------------------------
do
	-- published build, nothing on sale, no free skips: the button does not exist
	local v = Rules.skipButton(L, 12, false, 0, 0, false, true)
	check(not v.visible, "published build with product id 0: no Skip button")
	check(not Rules.skip10Visible(L, 12, false, 0, false, true), "published build: no Skip 10 button")
	-- and "Studio test" can never be shown outside Studio, whatever the flags
	for _, free in { 0, 2 } do
		for _, id in { 0, 123 } do
			for _, flag in { false, true } do
				local view = Rules.skipButton(L, 12, false, free, id, false, flag)
				check(view.sub ~= "hud.studio_test", "the Studio test label never shows in a published build")
			end
		end
	end
	v = Rules.skipButton(L, 12, false, 0, 0, true, true)
	check(v.visible and v.sub == "hud.studio_test" and v.free, "Studio: free test skip")
	v = Rules.skipButton(L, 12, false, 0, 0, true, false)
	check(not v.visible, "Studio with StudioFreeSkips off")
	v = Rules.skipButton(L, 12, false, 2, 0, false, false)
	check(v.visible and v.title == "hud.free_skip" and v.free, "free skips come first")
	v = Rules.skipButton(L, 12, false, 0, 555, false, false)
	check(v.visible and v.sub == "hud.robux" and not v.free, "on sale")
	v = Rules.skipButton(L, 100, false, 3, 555, true, true)
	check(not v.visible, "on a summit there is nothing to skip (take the portal)")
	v = Rules.skipButton(L, 1000, true, 3, 555, true, true)
	check(not v.visible, "at stage 1000")
	check(Rules.skip10Visible(L, 12, false, 555, false, false) and Rules.skip10Visible(L, 12, false, 0, true, true), "Skip 10 on sale / in Studio")
end

-- Rules: ranked runs ---------------------------------------------------------------------------
check(Rules.ranked({}), "a clean run is ranked")
check(Rules.ranked({ skipped = false, coil = false }), "false flags keep it ranked")
for _, key in { "skipped", "joinedMidRun", "coil", "powerup", "ability", "roam", "travelled" } do
	local help: any = {}
	help[key] = true
	check(not Rules.ranked(help), key .. " makes the run assisted")
end

-- Layout.isSave against the rules --------------------------------------------------------------
for g = 100, Layout.TOTAL, 100 do
	check(Layout.isSave(g), ("summit %d saves"):format(g))
end

-- Gifts ---------------------------------------------------------------------------------------
eq(#Gifts.List, Layout.TOWERS, "one gift per tower")
do
	local seen: { [string]: boolean } = {}
	for i, g in Gifts.List do
		eq(g.id, i, "gift id")
		eq(g.stage, i * Layout.STAGES, "gift stage")
		local sig = g.kind .. ":" .. tostring(g.value)
		check(not seen[sig], ("gift %d repeats %s"):format(i, sig))
		seen[sig] = true
		check(#g.icon > 0, "gift icon")
		check(Gifts.at(g.stage) == g, "Gifts.at")
	end
	eq(Gifts.at(150), nil, "no gift at 150")
	eq((Gifts.next(0) :: Gifts.Gift).id, 1, "next gift for a new player")
	eq((Gifts.next(100) :: Gifts.Gift).id, 2, "next gift after the first tower")
	eq((Gifts.next(999) :: Gifts.Gift).id, 10, "last gift")
	eq(Gifts.next(1000), nil, "nothing after the last gift")
	eq(#Gifts.earned(0), 0, "earned at 0")
	eq(#Gifts.earned(350), 3, "earned at 350")
	eq(#Gifts.earned(1000), 10, "earned at 1000")
	eq(Gifts.coinMult({}), 1, "no charm")
	eq(Gifts.coinMult({ ["3"] = true }), 1.5, "Lucky Charm")
	eq(Gifts.coinMult({ ["3"] = true, ["9"] = true }), 2, "charms do not stack")
	eq(Gifts.dailySkips({}), 0, "no daily skip gift")
	eq(Gifts.dailySkips({ ["6"] = true }), 1, "daily skip gift")
end

-- Powerups ------------------------------------------------------------------------------------
do
	local ids: { [string]: boolean } = {}
	for _, item in Powerups.List do
		check(not ids[item.id], "unique powerup id " .. item.id)
		ids[item.id] = true
		check(item.price > 0 and item.price == math.floor(item.price), item.id .. " has a whole coin price")
		check(item.kind == "timed" or item.kind == "charge" or item.kind == "instant", item.id .. " kind")
		check(item.kind ~= "timed" or (item.seconds or 0) >= 60, item.id .. " lasts at least a minute")
		check(item.kind ~= "charge" or (item.max or 0) >= 1, item.id .. " max charges")
		-- nothing in the shop is random (Roblox paid-random-item rules do not apply)
		check((item :: any).chance == nil and (item :: any).odds == nil and (item :: any).random == nil, item.id .. " is not a random item")
	end
	for _, id in { "speed", "gravity", "doublejump", "shield", "magnet", "skip", "pocket" } do
		check(Powerups.get(id) ~= nil, "catalogue has " .. id)
	end
	local now = 1000
	local state: Powerups.State = { coins = 100, boosts = {}, charges = {} }
	local ok, err = Powerups.buy(state, "nope", now)
	check(not ok and err == "err.not_for_sale", "unknown item")
	ok, err = Powerups.buy(state, "skip", now)
	check(not ok and err == "err.not_enough_coins" and state.coins == 100, "too expensive: nothing charged")
	ok = Powerups.buy(state, "speed", now)
	check(ok and state.coins == 40 and state.boosts.speed == now + 180, "speed coil for 3 minutes")
	check(Powerups.active(state.boosts, "speed", now + 179) and not Powerups.active(state.boosts, "speed", now + 180), "boost expiry")
	eq(Powerups.remaining(state.boosts, "speed", now + 100), 80, "remaining")
	state.coins = 1000
	ok = Powerups.buy(state, "speed", now + 100)
	check(ok and state.boosts.speed == now + 360, "buying again adds time to what is left")
	-- time is capped
	local bought = 0
	for _ = 1, 30 do
		state.coins = 1000
		if Powerups.buy(state, "speed", now + 100) then
			bought += 1
		end
	end
	check(state.boosts.speed - (now + 100) <= Powerups.MAX_TIMED and bought >= 7 and bought < 30, ("timed boosts are capped (%d more)"):format(bought))
	ok, err = Powerups.buy(state, "speed", now + 100)
	check(not ok and err == "err.boost_full", "boost full")
	-- charges
	state = { coins = 1000, boosts = {}, charges = {} }
	for i = 1, 3 do
		check(Powerups.buy(state, "shield", now), ("shield %d"):format(i))
	end
	ok, err = Powerups.buy(state, "shield", now)
	check(not ok and err == "err.max_charges" and state.charges.shield == 3 and state.coins == 1000 - 120, "max 3 shields, the 4th is not charged")
	check(Powerups.use(state, "shield") and state.charges.shield == 2, "a hit spends a shield")
	check(Powerups.use(state, "shield") and Powerups.use(state, "shield") and not Powerups.use(state, "shield"), "no shield left")
	check(not Powerups.use(state, "pocket"), "no pocket checkpoint")
	-- instant
	local before = state.coins
	ok = Powerups.buy(state, "skip", now)
	check(ok and state.coins == before - 150, "skip is paid at once")
	-- sweep
	state.boosts = { speed = now - 1, magnet = now + 50 }
	eq(Powerups.sweep(state.boosts, now), 1, "sweep removes the expired boost")
	check(state.boosts.speed == nil and state.boosts.magnet ~= nil, "sweep keeps live boosts")
end

-- Perks ---------------------------------------------------------------------------------------
check(not Perks.unlocked(99) and Perks.unlocked(100) and Perks.unlocked(640), "the lounge opens at stage 100")
eq(Perks.airJumps(false, false), 0, "no air jump")
eq(Perks.airJumps(false, true), 1, "double jump")
eq(Perks.airJumps(true, false), 2, "triple jump")
eq(Perks.airJumps(true, true), 2, "they do not stack")
eq(list(Perks.travelTargets(0)), "0", "teleporter: lobby only")
eq(list(Perks.travelTargets(35)), "0,10,20,30", "teleporter up to the last world reached")
eq(#Perks.travelTargets(1000), 101, "teleporter: all 100 worlds + lobby")
check(Perks.canTravel(250, 200) and Perks.canTravel(250, 0) and Perks.canTravel(250, 250), "travel to reached worlds")
check(not Perks.canTravel(250, 260) and not Perks.canTravel(250, 205) and not Perks.canTravel(50, 10) and not Perks.canTravel(250, -10), "no travel ahead / off-grid / before the lounge")
do
	local kinds: { [string]: number } = {}
	local ids: { [string]: boolean } = {}
	for _, p in Perks.List do
		check(not ids[p.id], "unique perk id " .. p.id)
		ids[p.id] = true
		kinds[p.kind] = (kinds[p.kind] or 0) + 1
	end
	check(kinds.travel == 1 and kinds.roam == 2 and kinds.ability == 2 and (kinds.glow or 0) >= 4 and (kinds.jumpfx or 0) >= 2 and (kinds.trail or 0) >= 2 and (kinds.effect or 0) >= 1, "lounge has travel, roam, abilities and skins")
	check(Perks.DASH_COOLDOWN >= 1 and Perks.GLIDE_FALL_SPEED > 0 and Perks.CLOUD_SPEED > Layout.Physics.walkSpeed, "perk tunables")
end

-- TowerStyle ---------------------------------------------------------------------------------
eq(#TowerStyle.Worlds, 10, "ten world palettes")
eq(#TowerStyle.Moods, Layout.TOWERS, "one mood per tower")
check(TowerStyle.isDanger(TowerStyle.KILL), "the kill colour is 'danger'")
check(not TowerStyle.isDanger({ 255, 150, 40 }) and not TowerStyle.isDanger({ 120, 60, 60 }) and not TowerStyle.isDanger({ 255, 200, 205 }), "orange / dark / pale reds are fine")
do
	local keys: { [string]: boolean } = {}
	for t = 1, Layout.TOWERS do
		local mood = TowerStyle.mood(t)
		check(not keys[mood.key], "unique tower key")
		keys[mood.key] = true
		check(not TowerStyle.isDanger(mood.core), ("tower %d core colour reads as a kill brick"):format(t))
		for style = 1, 10 do
			local pal = TowerStyle.palette(t, style)
			for _, field in { "platform", "alt", "accent", "pad" } do
				local c = (pal :: any)[field] :: { number }
				check(#c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255, "rgb range")
				check(not TowerStyle.isDanger(c), ("tower %d world %d %s (%d,%d,%d) reads as a kill brick"):format(t, style, field, c[1], c[2], c[3]))
			end
		end
	end
	-- tower 1 is the original palette, untouched
	for style = 1, 10 do
		local pal, base = TowerStyle.palette(1, style), TowerStyle.Worlds[style]
		for _, field in { "platform", "alt", "accent", "pad", "sky" } do
			local a, b = (pal :: any)[field], (base :: any)[field]
			check(math.abs(a[1] - b[1]) <= 1 and math.abs(a[2] - b[2]) <= 1 and math.abs(a[3] - b[3]) <= 1, ("tower 1 world %d %s unchanged"):format(style, field))
		end
	end
	-- the towers really look different: the same world in two towers is a different colour
	local distinct = 0
	for t = 2, Layout.TOWERS do
		local a, b = TowerStyle.palette(1, 2).platform, TowerStyle.palette(t, 2).platform
		if math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3]) > 40 then
			distinct += 1
		end
	end
	check(distinct >= 8, ("%d of 9 towers recolour Candy Land visibly"):format(distinct))
	-- hsv round trip
	for _, c in { { 255, 0, 0 }, { 12, 200, 99 }, { 40, 30, 70 }, { 255, 255, 255 }, { 0, 0, 0 }, { 128, 128, 128 } } do
		local h, s, v = TowerStyle.toHSV(c)
		local back = TowerStyle.fromHSV(h, s, v)
		check(math.abs(back[1] - c[1]) <= 1 and math.abs(back[2] - c[2]) <= 1 and math.abs(back[3] - c[3]) <= 1, "hsv round trip")
	end
	-- lighting grade: never too dark to read the obstacles, neutral on tower 1
	for t = 1, Layout.TOWERS do
		for w, prof in Ambience.Profiles do
			local g = Ambience.grade(prof, TowerStyle.mood(t) :: any)
			if t == 1 then
				check(g == prof, "tower 1 keeps the world profile (same table)")
			end
			check(g.brightness >= Ambience.MIN_BRIGHTNESS - 1e-9, ("tower %d world %d brightness %.2f"):format(t, w, g.brightness))
			check(g.ambient[1] + g.ambient[2] + g.ambient[3] >= Ambience.MIN_AMBIENT_SUM - 45, ("tower %d world %d ambient"):format(t, w))
			check(g.density >= 0.12 and g.density <= 0.5 and g.clock >= 0 and g.clock < 24, ("tower %d world %d density / clock"):format(t, w))
			check(g.stars <= 10000 and g.saturation <= 0.5 and g.saturation >= -0.3, ("tower %d world %d stars / saturation"):format(t, w))
		end
	end
end

print(("rules_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("rules_test failed")
end
print("rules test PASSED")
