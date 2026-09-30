--!strict
-- The gift at the top of every tower: ten different, fixed rewards (nothing random, nothing to
-- buy). PURE Luau. The HUD shows the next one in advance; server/Gifts.luau grants them.
local Gifts = {}

export type Gift = {
	id: number, -- 1..10, also the tower whose summit gives it
	stage: number, -- 100, 200 ... 1000
	kind: string, -- trail | pet | coins | effect | title | dailySkip | skin | hat
	value: any, -- id of the cosmetic, or the number for coins / dailySkip
	icon: string, -- emoji for the HUD chip and the gift plinth
}

Gifts.List = {
	{ id = 1, stage = 100, kind = "trail", value = "summit", icon = "🔥" }, -- Summit Flame trail (+ the free lounge)
	{ id = 2, stage = 200, kind = "pet", value = "cloudling", icon = "☁" }, -- a little cloud that rides on your shoulder
	{ id = 3, stage = 300, kind = "coins", value = 1.5, icon = "🍀" }, -- Lucky Charm: x1.5 coins for ever
	{ id = 4, stage = 400, kind = "effect", value = "aurora", icon = "🌈" }, -- Aurora aura
	{ id = 5, stage = 500, kind = "title", value = "legend", icon = "🏅" }, -- "Halfway Legend" title in gold
	{ id = 6, stage = 600, kind = "dailySkip", value = 1, icon = "🎟" }, -- +1 free skip with every daily reward
	{ id = 7, stage = 700, kind = "skin", value = "glow_rainbow", icon = "✨" }, -- Rainbow glow skin
	{ id = 8, stage = 800, kind = "trail", value = "comet", icon = "☄" }, -- Comet trail
	{ id = 9, stage = 900, kind = "coins", value = 2, icon = "💎" }, -- Diamond Charm: x2 coins for ever
	{ id = 10, stage = 1000, kind = "hat", value = "crown", icon = "👑" }, -- Sky Crown + "Conqueror of 1000" title
} :: { Gift }

function Gifts.at(stage: number): Gift?
	for _, g in Gifts.List do
		if g.stage == stage then
			return g
		end
	end
	return nil
end

-- The next gift somebody whose best stage is `best` is climbing towards (nil = has them all).
function Gifts.next(best: number): Gift?
	for _, g in Gifts.List do
		if g.stage > best then
			return g
		end
	end
	return nil
end

-- Gifts that a player with this best stage must own (used to back-fill old profiles).
function Gifts.earned(best: number): { Gift }
	local out = {}
	for _, g in Gifts.List do
		if best >= g.stage then
			table.insert(out, g)
		end
	end
	return out
end

-- Permanent coin multiplier from the charms (the best one counts, they do not stack).
function Gifts.coinMult(owned: { [string]: boolean }): number
	local mult = 1
	for _, g in Gifts.List do
		if g.kind == "coins" and owned[tostring(g.id)] then
			mult = math.max(mult, g.value :: number)
		end
	end
	return mult
end

-- Extra free skips per daily reward.
function Gifts.dailySkips(owned: { [string]: boolean }): number
	local n = 0
	for _, g in Gifts.List do
		if g.kind == "dailySkip" and owned[tostring(g.id)] then
			n += g.value :: number
		end
	end
	return n
end

return Gifts
