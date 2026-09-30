--!strict
-- Progress rules for the 1,000-stage climb. PURE Luau (tests/rules_test.luau): the server
-- (Checkpoints, Towers) and the HUD both ask this module, so they can never disagree.
--
-- Vocabulary
--   stage  : the saved checkpoint (where you respawn). 0 = lobby.
--   at     : the highest pad reached since the last respawn (>= stage). Rest pads raise `at`
--            without saving.
--   summit : a multiple of 100. Its pad is the top of a tower; the next tower starts on the other
--            side of the portal, on that tower's base pad ("onBase").
local Rules = {}

-- Set once by whoever requires both modules (shared modules don't require each other).
export type LayoutLike = {
	STAGES: number,
	TOWERS: number,
	TOTAL: number,
	towerOf: (g: number) -> number,
	slotOf: (g: number) -> number,
	isSave: (g: number) -> boolean,
}

function Rules.isSummit(L: LayoutLike, stage: number): boolean
	return stage > 0 and stage % L.STAGES == 0
end

-- Can pad `g` be claimed by somebody whose highest pad is `at`? In order, at most `maxJump`
-- ahead, and never across a portal: the pads of the next tower only count once you stand on its
-- base (onBase).
function Rules.canReach(L: LayoutLike, at: number, g: number, maxJump: number, onBase: boolean): boolean
	if g <= at or g > L.TOTAL or g > at + maxJump then
		return false
	end
	if Rules.isSummit(L, at) and not onBase then
		return false -- on a summit: take the portal first
	end
	-- all pads between at+1 and g are on the same tower
	return L.towerOf(at + 1) == L.towerOf(g)
end

-- Where a skip of `n` stages lands (nil = no skip possible). A skip never crosses a portal: it
-- stops at the summit.
function Rules.skipTarget(L: LayoutLike, at: number, n: number, onBase: boolean): number?
	if at >= L.TOTAL or n < 1 then
		return nil
	end
	if Rules.isSummit(L, at) and not onBase then
		return nil
	end
	local summit = (at // L.STAGES + 1) * L.STAGES
	return math.min(at + n, summit)
end

export type Spot = { tower: number, pad: number }

-- Where the character stands for a given saved stage. nil = the lobby.
function Rules.spawn(L: LayoutLike, stage: number, inLobby: boolean, onBase: boolean): Spot?
	if inLobby or stage <= 0 then
		return nil
	end
	if Rules.isSummit(L, stage) then
		local tower = stage // L.STAGES
		if onBase and tower < L.TOWERS then
			return { tower = tower + 1, pad = 0 }
		end
		return { tower = tower, pad = L.STAGES }
	end
	return { tower = L.towerOf(stage), pad = L.slotOf(stage) }
end

-- The pad (tower, local index) that checkpoint `g` lives on when you walk onto it.
function Rules.padOf(L: LayoutLike, g: number): Spot
	if g <= 0 then
		return { tower = 1, pad = 0 }
	end
	return { tower = L.towerOf(g), pad = L.slotOf(g) }
end

-- Towers that must exist for a player: the one they stand on, and the next one from the last ten
-- stages of a tower on (so the portal never waits for a build).
function Rules.towersNeeded(L: LayoutLike, stage: number, at: number, onBase: boolean): { number }
	local set: { [number]: boolean } = {}
	local spot = Rules.spawn(L, stage, false, onBase)
	set[if spot then spot.tower else 1] = true
	local here = math.max(at, stage)
	local tower, slot = 1, 0
	if here > 0 then
		if Rules.isSummit(L, here) then
			if onBase and here < L.TOTAL then
				tower, slot = here // L.STAGES + 1, 0
			else
				tower, slot = here // L.STAGES, L.STAGES
			end
		else
			tower, slot = L.towerOf(here), L.slotOf(here)
		end
	end
	set[tower] = true
	if slot > L.STAGES - 10 and tower < L.TOWERS then
		set[tower + 1] = true
	end
	local out = {}
	for t in set do
		table.insert(out, t)
	end
	table.sort(out)
	return out
end

-- Portal at the summit of `tower`: open for anybody who has ever reached that summit.
function Rules.portalOpen(L: LayoutLike, best: number, tower: number): boolean
	return tower >= 1 and tower < L.TOWERS and best >= tower * L.STAGES
end

-- Coins for reaching stage g for the first time in a run (5 early, +2 per world, capped).
function Rules.coinsForStage(g: number): number
	return 5 + 2 * math.min(math.max(g, 0) // 10, 25)
end

---------------------------------------------------------------------------------------------
-- HUD: the Skip Stage button
---------------------------------------------------------------------------------------------
export type SkipView = {
	visible: boolean,
	title: string, -- locale key
	sub: string, -- locale key ("" = none)
	free: boolean,
}

-- `productId` = Config.Products.SkipStage (0 = not on sale). The free Studio skip exists ONLY in
-- Studio: with studio = false it is never shown, whatever Config says.
function Rules.skipButton(L: LayoutLike, at: number, onBase: boolean, freeSkips: number, productId: number, studio: boolean, studioFreeSkips: boolean): SkipView
	local possible = Rules.skipTarget(L, at, 1, onBase) ~= nil
	if possible and freeSkips > 0 then
		return { visible = true, title = "hud.free_skip", sub = "hud.skips_left", free = true }
	end
	if possible and productId ~= 0 then
		return { visible = true, title = "hud.skip", sub = "hud.robux", free = false }
	end
	if possible and studio and studioFreeSkips then
		return { visible = true, title = "hud.skip", sub = "hud.studio_test", free = true }
	end
	return { visible = false, title = "hud.skip", sub = "", free = false }
end

function Rules.skip10Visible(L: LayoutLike, at: number, onBase: boolean, productId: number, studio: boolean, studioFreeSkips: boolean): boolean
	return Rules.skipTarget(L, at, 10, onBase) ~= nil and (productId ~= 0 or (studio and studioFreeSkips))
end

---------------------------------------------------------------------------------------------
-- Ranking: a run only counts for Fastest Climb when nothing helped.
---------------------------------------------------------------------------------------------
export type Help = {
	skipped: boolean?, -- any skip (paid, free, ad, coins)
	joinedMidRun: boolean?,
	coil: boolean?, -- speed / gravity coil switched on (pass or timed)
	powerup: boolean?, -- double jump, shield hit absorbed, magnet, pocket checkpoint
	ability: boolean?, -- dash / triple jump
	roam: boolean?, -- glider / cloud
	travelled: boolean?, -- teleporter
}

function Rules.ranked(help: Help): boolean
	for _, v in help :: { [string]: any } do
		if v then
			return false
		end
	end
	return true
end

return Rules
