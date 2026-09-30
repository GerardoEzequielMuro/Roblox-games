--!strict
-- Pure helpers for "what is my next goal?" (HUD chip) and "which crop does Instant Grow (1) finish?".
-- No Roblox APIs: tests/goals_test.luau runs this with plain Luau.
local Goals = {}

export type Candidate = { kind: string, id: string?, cost: number }
export type Goal = { kind: string, id: string?, cost: number, remaining: number, fraction: number }

-- Cheapest thing the player cannot afford yet. Returns nil when everything on the list is already affordable
-- (or the list is empty). The fraction is cash / cost, so the bar fills as they earn and the goal is always the
-- closest one, never a far-away one.
function Goals.nextGoal(cash: number, candidates: { Candidate }): Goal?
	local best: Candidate? = nil
	for _, c in candidates do
		if c.cost > cash and (best == nil or c.cost < best.cost or (c.cost == best.cost and c.kind < best.kind)) then
			best = c
		end
	end
	if not best then
		return nil
	end
	return {
		kind = best.kind,
		id = best.id,
		cost = best.cost,
		remaining = best.cost - cash,
		fraction = math.clamp(cash / best.cost, 0, 1),
	}
end

export type Growing = { tile: number, remaining: number }

-- The still-growing crop with the most time left (ties: lowest tile number). nil if nothing is growing.
function Goals.slowest(growing: { Growing }): number?
	local bestTile: number? = nil
	local bestRemaining = 0
	for _, g in growing do
		if g.remaining > 0 and (bestTile == nil or g.remaining > bestRemaining or (g.remaining == bestRemaining and g.tile < bestTile)) then
			bestTile, bestRemaining = g.tile, g.remaining
		end
	end
	return bestTile
end

return Goals
