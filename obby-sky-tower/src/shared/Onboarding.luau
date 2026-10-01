--!strict
-- First-session guide: a tiny step machine. PURE Luau (tests/onboarding_test.luau).
--
-- The guide never owns the game: it only decides what ONE hint to show for the current moment,
-- from numbers the client already has. It is stateless on purpose, so it cannot get stuck:
--   * the step comes from the saved stage (`at`): rejoining at stage 1 resumes at "climb", rejoining
--     at stage 5 shows nothing;
--   * it always ends: Skip, reaching GOAL, or TIMEOUT seconds without getting there;
--   * if the target pad cannot be placed (`targetKnown` false) the hint stays as text, no arrow.
local Onboarding = {}

Onboarding.GOAL = 3 -- stages of hand holding; after that the player knows how it works
Onboarding.TIMEOUT = 300 -- seconds of session after which the climb hints give up
Onboarding.RETRY_DEATHS = 2 -- deaths since the last checkpoint before the hint turns into advice
Onboarding.SHOP_TIMEOUT = 45 -- seconds the "spend your coins" hint stays up

export type Input = {
	at: number, -- stage reached (0 = nothing yet)
	skipped: boolean, -- the player pressed Skip
	elapsed: number, -- seconds since the guide started this session
	deaths: number, -- deaths since the last checkpoint
	targetKnown: boolean, -- the next pad's position could be computed
	coins: number,
	shopCoins: number, -- cheapest thing in the shop
	shopSeen: boolean, -- the shop was opened (this session)
	crossed: boolean, -- the player reached GOAL during this session (not a rejoin)
	sinceGoal: number, -- seconds since GOAL was reached
}

export type View = {
	step: string, -- go | climb | shop | done
	textKey: string?, -- locale key of the hint
	arrow: boolean, -- show the 3D arrow / edge arrow to the next pad
	glow: string?, -- UI element to pulse: "menu"
}

local DONE: View = { step = "done", textKey = nil, arrow = false, glow = nil }

function Onboarding.view(i: Input): View
	if i.skipped then
		return DONE
	end
	if i.at < Onboarding.GOAL then
		if i.elapsed >= Onboarding.TIMEOUT then
			return DONE
		end
		local first = i.at <= 0
		local key = if i.deaths >= Onboarding.RETRY_DEATHS then "guide.retry" elseif first then "guide.go" else "guide.next"
		return { step = if first then "go" else "climb", textKey = key, arrow = i.targetKnown, glow = nil }
	end
	-- first purchase: only for somebody who just got there with enough coins and never opened the shop
	if i.crossed and not i.shopSeen and i.coins >= i.shopCoins and i.sinceGoal < Onboarding.SHOP_TIMEOUT then
		return { step = "shop", textKey = "guide.shop", arrow = false, glow = "menu" }
	end
	return DONE
end

return Onboarding
