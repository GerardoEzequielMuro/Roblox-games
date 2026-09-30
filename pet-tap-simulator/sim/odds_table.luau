-- Prints the egg odds / pet power tables as Markdown (used for DESIGN.md).
local F = require("../src/shared/Formulas")
local Format = require("../src/shared/Format")
local Config = F.Config
for _, egg in Config.Eggs do
	local where = if egg.exclusive then "Spawn (Robux only)" else Config.Zones[egg.zone].name
	local price = if egg.exclusive then "Robux" else Format.abbrev(egg.price) .. " Taps"
	print(string.format("\n**%s** — %s — %s\n", egg.name, where, price))
	print("| Pet | Rarity | Chance | Power (+taps/tap) |")
	print("|---|---|---|---|")
	for _, o in F.odds(egg.id, 1) do
		local p = F.PetById[o.pet]
		local power = if (Config.ExclusivePowerFactor :: any)[p.id] then string.format("%sx best pet of your top zone", tostring((Config.ExclusivePowerFactor :: any)[p.id])) else Format.abbrev(p.power)
		print(string.format("| %s | %s | %s | %s |", p.name, p.rarity, Format.chance(o.chance), power))
	end
end
