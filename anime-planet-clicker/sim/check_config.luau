-- Sanity checks on Config (run with luau.exe from the repo root).
local Config = require("../src/shared/Config")
local F = require("../src/shared/Formulas")
local Layout = require("../src/shared/Layout")

local errors = 0
local function fail(msg)
	errors += 1
	print("FAIL: " .. msg)
end

-- capsules: raw weights sum to 100, pets exist, shown odds sum to exactly 100 at any luck
for _, cap in Config.Capsules do
	local sum = 0
	for _, e in cap.pets do
		sum += e[2]
		if not F.PetById[e[1]] then
			fail(cap.id .. " references unknown pet " .. e[1])
		end
	end
	if math.abs(sum - 100) > 1e-9 then
		fail(string.format("%s raw chances sum to %.6f", cap.id, sum))
	end
	for _, luck in { 1, 1.5, 2, 4.4, 9 } do
		local total = 0
		for _, o in F.odds(cap.id, luck) do
			total += o.chance
			if o.chance <= 0 then
				fail(cap.id .. " has a non-positive chance for " .. o.id)
			end
		end
		if math.abs(total - 100) > 1e-9 then
			fail(string.format("%s odds at luck %.1f sum to %.12f", cap.id, luck, total))
		end
	end
end
-- every pet is obtainable
for _, p in Config.Pets do
	if not Config.RarityByName[p.rarity] then
		fail(p.id .. " bad rarity")
	end
	local found = p.id == Config.SecretPet or p.id == Config.GroupGiftPet
	for _, cap in Config.Capsules do
		for _, e in cap.pets do
			if e[1] == p.id then
				found = true
			end
		end
	end
	if not found then
		fail(p.id .. " is not obtainable")
	end
end
-- rolls: distribution matches the odds
do
	local seed = 12345
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return (seed - 1) / 2147483646
	end
	local counts, n = {}, 200000
	for _ = 1, n do
		local o = F.rollCapsule("dawn", 1, rnd())
		counts[o.id] = (counts[o.id] or 0) + 1
	end
	for _, o in F.odds("dawn", 1) do
		local got = (counts[o.id] or 0) / n * 100
		if o.chance > 1 and math.abs(got - o.chance) > 0.5 then
			fail(string.format("roll distribution %s: %.2f%% vs %.2f%%", o.id, got, o.chance))
		end
	end
end
-- progression is monotonic
for i = 2, #Config.Zones do
	local a, b = Config.Zones[i - 1], Config.Zones[i]
	if b.gateHp <= a.gateHp or b.hp <= a.hp or b.value <= a.value or b.hardness <= a.hardness then
		fail("zone " .. i .. " does not increase")
	end
	if Config.Tools[b.hardness].zone ~= i then
		fail("zone " .. i .. " hardness must be the first tool sold there")
	end
end
for i = 2, #Config.Tools do
	local a, b = Config.Tools[i - 1], Config.Tools[i]
	if b.cost <= a.cost or b.power <= a.power or b.zone < a.zone then
		fail("tool " .. b.id .. " does not increase")
	end
end
local share = 0
for _, l in Config.Layers do
	share += l.share
end
if math.abs(share - 1) > 1e-9 then
	fail("layer shares sum to " .. share)
end
-- layout: nodes stay on the station and clear of each other and of the plaza
for z = 1, #Config.Zones do
	local c = Layout.zoneCenter(z)
	local pts = {}
	for n = 0, Config.NodeGate do
		local p = Layout.nodePosition(z, n)
		local d = math.sqrt((p[1] - c[1]) ^ 2 + (p[3] - c[3]) ^ 2)
		if n ~= Config.NodeGate and d > Config.ZoneRadius - 8 then
			fail(string.format("zone %d node %d is off the station (%.1f)", z, n, d))
		end
		if Layout.zoneAt(p[1], p[3]) ~= z then
			fail(string.format("zone %d node %d: zoneAt mismatch", z, n))
		end
		for m, q in pts do
			local dd = math.sqrt((p[1] - q[1]) ^ 2 + (p[3] - q[3]) ^ 2)
			if dd < 20 then
				fail(string.format("zone %d nodes %d and %d are %.1f studs apart", z, m - 1, n, dd))
			end
		end
		table.insert(pts, p)
	end
	local s = Layout.spawnPoint(z)
	if Layout.zoneAt(s[1], s[3]) ~= z then
		fail("zone " .. z .. " spawn point is outside the zone")
	end
	-- from somewhere reachable, at least 2 regular planets are within the base range (AFK auto mine)
	local best = 0
	for n = 1, Config.NodesPerZone do
		local p = Layout.nodePosition(z, n)
		local inRange = 0
		for m = 1, Config.NodesPerZone do
			local q = Layout.nodePosition(z, m)
			local mid = { (p[1] + q[1]) / 2, (p[3] + q[3]) / 2 }
			local cnt = 0
			for k = 1, Config.NodesPerZone do
				local r = Layout.nodePosition(z, k)
				if math.sqrt((r[1] - mid[1]) ^ 2 + (r[3] - mid[2]) ^ 2) <= Config.BaseRange then
					cnt += 1
				end
			end
			inRange = math.max(inRange, cnt)
		end
		best = math.max(best, inRange)
	end
	if best < 2 then
		fail("zone " .. z .. ": no standing spot reaches 2 planets")
	end
end
local a = Layout.arenaCenter()
if Layout.zoneAt(a[1], a[3]) ~= nil or not Layout.inArena(a[1], a[3]) then
	fail("arena overlaps a galaxy")
end
local sp = Layout.arenaSpawn()
if Layout.inArena(sp[1], sp[3]) then
	fail("arena spawn is inside the PvP circle")
end
-- pvp damage bounds
if F.pvpDamage(1e12, 1) > Config.Pvp.baseDamage * Config.Pvp.maxRatio + 1 or F.pvpDamage(1, 1e12) < Config.Pvp.baseDamage * Config.Pvp.minRatio - 1 then
	fail("pvp damage escapes its clamp")
end
for _, code in { "LAUNCH" } do
	if not Config.Codes[code] then
		fail("missing code " .. code)
	end
end
-- relic / trait tables sum to 100
for name, list in { relics = Config.RelicGrades, traits = Config.Traits } do
	local sum = 0
	for _, e in list do
		sum += e.chance
	end
	if math.abs(sum - 100) > 1e-9 then
		fail(name .. " chances sum to " .. sum)
	end
end
for _, u in Config.Upgrades do
	if not Config.SystemById[u.system] then
		fail("upgrade " .. u.id .. " has an unknown system")
	end
	local cur = u.currency
	if cur ~= "stardust" and cur ~= "crystals" and not Config.MaterialZone[cur] then
		fail("upgrade " .. u.id .. " has an unknown currency")
	end
end
-- refinery / workshop / capsule spots do not overlap
for z = 1, #Config.Zones do
	local spots = { Layout.refineryPosition(z), Layout.workshopPosition(z), Layout.portalPosition(z), Layout.spawnPoint(z), Layout.systemPosition(z) }
	for _, cap in Config.Capsules do
		if cap.zone == z and not cap.exclusive then
			table.insert(spots, Layout.capsulePosition(cap.id))
		end
	end
	for i = 1, #spots do
		for j = i + 1, #spots do
			local d = math.sqrt((spots[i][1] - spots[j][1]) ^ 2 + (spots[i][3] - spots[j][3]) ^ 2)
			if d < 14 then
				fail(string.format("zone %d plaza spots %d and %d are %.1f studs apart", z, i, j, d))
			end
		end
	end
end
print(if errors == 0 then "CONFIG OK" else (errors .. " CONFIG ERRORS"))
