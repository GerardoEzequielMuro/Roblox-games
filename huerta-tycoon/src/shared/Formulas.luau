--!strict
-- Pure math shared by server (authoritative) and client (display).
-- plain Luau (tests, sim/pacing_sim.luau) has no `script`: fall back to a relative path
local Config = if script then require(script.Parent.Config) else (require :: any)("./Config")

local Formulas = {}

function Formulas.tileCost(tilesOwned: number): number
	return math.floor(Config.TileBaseCost * Config.TileCostGrowth ^ (tilesOwned - Config.StartingTiles))
end

function Formulas.upgradeCost(id: string, level: number): number
	local u = Config.UpgradeById[id]
	return math.floor(u.baseCost * u.costGrowth ^ level)
end

function Formulas.rebirthCost(rebirths: number): number
	return math.floor(Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths)
end

function Formulas.backpackCap(backpackLevel: number, hasBigBasket: boolean): number
	local cap = Config.BackpackBase + backpackLevel * Config.UpgradeById.Backpack.perLevel
	if hasBigBasket then
		cap += Config.PassBonuses.BigBasketBonus
	end
	return cap
end

return Formulas
