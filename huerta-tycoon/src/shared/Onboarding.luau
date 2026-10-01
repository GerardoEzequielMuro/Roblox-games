--!strict
-- Pure first-session logic (no Roblox services): tutorial step machine, soft-lock recovery, progressive menu
-- tiers and loading-screen progress. Tested by tests/onboarding_test.luau.
local Onboarding = {}

Onboarding.STEPS = 4
-- seconds on the same step before "Stuck? You can Skip" shows and the Skip button pulses
Onboarding.STUCK_AFTER = 40
-- seconds since the tutorial started after which it ends by itself (no reward: nothing was sold)
Onboarding.GIVE_UP_AFTER = 300

export type Facts = {
	backpackCount: number,
	hasCrop: boolean, -- any planted crop on an own tile
	ripe: boolean, -- any of them is ready
	seeds: number, -- seeds in the bag
}

-- Which step the player is on, derived only from state (so a rejoin or a lost target resumes in the right place).
function Onboarding.step(f: Facts): number
	if f.backpackCount > 0 then
		return 4
	elseif f.hasCrop then
		return 3
	elseif f.seeds > 0 then
		return 2
	end
	return 1
end

-- Text key for a step. Step 2 splits in "pick a seed" / "tap a tile"; step 3 in "wait" / "tap it".
function Onboarding.textKey(step: number, f: Facts, seedSelected: boolean): string
	if step == 2 then
		return if seedSelected then "tut.2b" else "tut.2"
	elseif step == 3 then
		return if f.ripe then "tut.3" else "tut.3w"
	end
	return "tut." .. tostring(step)
end

-- What to do when the player already has progress at the first evaluation (rejoin after selling):
-- the tutorial is over for them, silently.
function Onboarding.alreadyPlayed(totalEarned: number): boolean
	return totalEarned > 0
end

function Onboarding.stuck(secondsOnStep: number): boolean
	return secondsOnStep >= Onboarding.STUCK_AFTER
end

function Onboarding.giveUp(secondsSinceStart: number): boolean
	return secondsSinceStart >= Onboarding.GIVE_UP_AFTER
end

-- A step whose world target is gone (no free tile, shop part missing) still has a text + GUI target; this just
-- picks the fallback world target index: 1 = preferred, 2 = any own tile, 0 = none.
function Onboarding.targetFallback(hasPreferred: boolean, hasAnyTile: boolean): number
	if hasPreferred then
		return 1
	elseif hasAnyTile then
		return 2
	end
	return 0
end

-- ===== progressive menu =====
-- tier 0: brand-new player (nothing sold, tutorial not done) -> Shop + Daily
-- tier 1: first sale or tutorial done -> + Upgrades, Gifts, Index, Codes
-- tier 2: earned TIER2_EARNED or a rebirth -> everything
Onboarding.TIER2_EARNED = 250
Onboarding.MENU_TIER = {
	Shop = 0,
	Daily = 0,
	Upgrades = 1,
	Gifts = 1,
	Index = 1,
	Codes = 1,
	Rebirth = 2,
	Store = 2,
	Invite = 2,
	Trophies = 2,
}

function Onboarding.menuTier(totalEarned: number, rebirths: number, tutorialDone: boolean): number
	if rebirths > 0 or totalEarned >= Onboarding.TIER2_EARNED then
		return 2
	elseif totalEarned > 0 or tutorialDone then
		return 1
	end
	return 0
end

function Onboarding.menuVisible(name: string, tier: number): boolean
	local need = Onboarding.MENU_TIER[name]
	return need == nil or tier >= need
end

-- ===== loading screen =====
Onboarding.LOAD_MAX = 6 -- never on screen longer than this, whatever fails to load
Onboarding.LOAD_MIN = 0.8 -- avoid a one-frame flash

-- Fraction shown on the bar: stages done push it forward, time creeps it so it never looks frozen.
function Onboarding.loadProgress(stagesDone: number, stagesTotal: number, elapsed: number): number
	local real = math.clamp(stagesDone / math.max(1, stagesTotal), 0, 1)
	local creep = math.clamp(elapsed / Onboarding.LOAD_MAX, 0, 1) * 0.85
	return math.max(real * 0.95, math.min(creep, 0.9))
end

function Onboarding.loadDone(ready: boolean, elapsed: number): boolean
	if elapsed >= Onboarding.LOAD_MAX then
		return true
	end
	return ready and elapsed >= Onboarding.LOAD_MIN
end

return Onboarding
