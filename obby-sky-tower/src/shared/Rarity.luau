--!strict
-- Rarity tiers for reveal moments (summit gifts). PURE Luau.
-- Gifts are fixed, not random, so the tier is just how far up the tower chain they sit.
local Rarity = {}

export type Tier = { id: string, rank: number, color: { number }, shake: number, sparks: number }

Rarity.Tiers = {
	common = { id = "common", rank = 1, color = { 120, 200, 255 }, shake = 0, sparks = 30 },
	rare = { id = "rare", rank = 2, color = { 90, 150, 255 }, shake = 0.15, sparks = 45 },
	epic = { id = "epic", rank = 3, color = { 180, 100, 255 }, shake = 0.25, sparks = 60 },
	legendary = { id = "legendary", rank = 4, color = { 255, 190, 40 }, shake = 0.4, sparks = 90 },
} :: { [string]: Tier }

-- gift id 1..10 (= the tower whose summit gives it) -> tier
function Rarity.ofGift(id: number): Tier
	if id >= 10 then
		return Rarity.Tiers.legendary
	elseif id >= 7 then
		return Rarity.Tiers.epic
	elseif id >= 3 then
		return Rarity.Tiers.rare
	end
	return Rarity.Tiers.common
end

return Rarity
