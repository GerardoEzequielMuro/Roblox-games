-- Sanity checks on Config (run with luau.exe): odds sum to 100, pets referenced exist,
-- every zone has an egg, prices increase, rarity names valid.
local F = require("../src/shared/Formulas")
local Config = F.Config
local errors = 0
local function fail(msg) errors += 1 print("FAIL: " .. msg) end
for _, egg in Config.Eggs do
	local sum = 0
	for _, e in egg.entries do
		sum += e.chance
		if not F.PetById[e.pet] then fail(egg.id .. " references unknown pet " .. e.pet) end
	end
	if math.abs(sum - 100) > 1e-6 then fail(string.format("%s odds sum to %.6f", egg.id, sum)) end
end
for _, p in Config.Pets do
	if not Config.RarityByName[p.rarity] then fail(p.id .. " bad rarity") end
	local inEgg = false
	for _, egg in Config.Eggs do for _, e in egg.entries do if e.pet == p.id then inEgg = true end end end
	if not inEgg and not p.giftOnly then fail(p.id .. " is not in any egg") end
end
for z = 1, #Config.Zones do
	local has = false
	for _, egg in Config.Eggs do if egg.zone == z then has = true end end
	if not has then fail("zone " .. z .. " has no egg") end
	if z > 1 and Config.Zones[z].cost <= Config.Zones[z - 1].cost then fail("zone costs not increasing at " .. z) end
end
-- rebirth-gated eggs: whole rebirth counts, a real zone, and no two eggs closer than 34 studs (pedestals are 15 wide)
for _, egg in Config.Eggs do
	if egg.minRebirths ~= nil and (egg.minRebirths < 1 or egg.minRebirths ~= math.floor(egg.minRebirths) or egg.exclusive) then fail(egg.id .. " bad minRebirths") end
	for _, other in Config.Eggs do
		if other.id < egg.id and (other.zone == egg.zone or (other.zone == 0 and egg.zone == 1) or (egg.zone == 0 and other.zone == 1)) then
			local dx, dz = egg.offsetX - other.offsetX, egg.offsetZ - other.offsetZ
			if (egg.zone == other.zone) and math.sqrt(dx * dx + dz * dz) < 34 then fail(egg.id .. " is too close to " .. other.id) end
		end
	end
end
print(string.format("%d pets, %d eggs, %d zones, %d passes, %d products -> %s", #Config.Pets, #Config.Eggs, #Config.Zones, #Config.Passes, #Config.Products, if errors == 0 then "ALL CHECKS PASSED" else errors .. " FAILURES"))
