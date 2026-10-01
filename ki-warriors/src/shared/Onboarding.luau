--!strict
-- First-session logic that needs no Roblox APIs (so tests/onboarding_check.luau can run it):
-- tutorial skip rules + "stuck" detection, loading-screen progress, counter roll-up easing,
-- combo tiers and the transformation timeline.
local Onboarding = {}

---------------------------------------------------------------------------
-- Tutorial: skippable, never a soft-lock
---------------------------------------------------------------------------
-- Steps that can be skipped (no reward). Rewards stay tied to doing the thing, so skipping can
-- not be farmed: it only exists to get a stuck / confused player moving.
local SKIPPABLE: { [string]: boolean } = { reps = true, charge = true, blasts = true, fly = true, defeat = true, gear = true, power = true, zone = true }
Onboarding.SKIP_EXTRA = 3 -- steps after Config.TutorialSteps that still show a "how" hint
Onboarding.STUCK_HINT = 20 -- seconds without progress: make the hint louder
Onboarding.STUCK_SKIP = 45 -- seconds without progress: offer "Skip"

function Onboarding.canSkip(index: number, kind: string, tutorialSteps: number): boolean
	return index >= 1 and index <= tutorialSteps + Onboarding.SKIP_EXTRA and SKIPPABLE[kind] == true
end

-- 0 = fine, 1 = loud hint, 2 = loud hint + Skip button.
function Onboarding.stuckLevel(idle: number): number
	if idle >= Onboarding.STUCK_SKIP then
		return 2
	elseif idle >= Onboarding.STUCK_HINT then
		return 1
	end
	return 0
end

-- Name of the HUD button the tutorial step points at (pulsing ring + arrow). nil = nothing to
-- point at (the world is the target: the guide beam handles it).
local POINTERS: { [string]: { string? } } = {
	-- kind = { pc, touch }
	reps = { "Slot_melee", "Touch_punch" },
	charge = { "Slot_charge", "Touch_charge" },
	blasts = { "Slot_blast", "Touch_blast" },
	fly = { "Slot_fly", "Touch_fly" },
	gear = { "Gear", "Gear" },
	power = { "Slot_melee", "Touch_punch" }, -- keep punching
	form = { "Slot_form", "Touch_form" },
	beam = { "Slot_beam", "Touch_beam" },
}
function Onboarding.pointerName(kind: string, touch: boolean): string?
	local p = POINTERS[kind]
	return if p then p[if touch then 2 else 1] else nil
end

export type Tracker = { step: number, progress: number, since: number }
-- Idle clock of the current step: resets whenever the step or its progress changes (so a
-- player who is punching is never "stuck", and a rejoin starts fresh at the saved step).
function Onboarding.track(t: Tracker?, step: number, progress: number, now: number): (Tracker, number)
	if not t or t.step ~= step or t.progress ~= progress then
		local fresh: Tracker = { step = step, progress = progress, since = now }
		return fresh, 0
	end
	return t, math.max(0, now - t.since)
end

---------------------------------------------------------------------------
-- Loading screen: never blocks for more than maxSeconds
---------------------------------------------------------------------------
Onboarding.LOAD_MIN = 0.7 -- shortest time on screen (so it does not flicker)
Onboarding.LOAD_MAX = 4 -- hard cap, whatever failed to load

-- stages: list of booleans (remotes ready, state received, character spawned...).
-- Returns the bar fraction (always moves forward with time) and whether to close.
function Onboarding.loadingProgress(elapsed: number, stages: { boolean }, maxSeconds: number?): (number, boolean)
	local cap = maxSeconds or Onboarding.LOAD_MAX
	local done = 0
	for _, ok in stages do
		if ok then
			done += 1
		end
	end
	local real = if #stages == 0 then 1 else done / #stages
	local timed = math.clamp(elapsed / cap, 0, 1)
	-- the bar mixes real stages and a slow clock, but only reaches 1 when we are really closing
	local frac = math.max(real * 0.92, timed * 0.8)
	local close = elapsed >= cap or (real >= 1 and elapsed >= Onboarding.LOAD_MIN)
	if close then
		frac = 1
	end
	return math.clamp(frac, 0, 1), close
end

---------------------------------------------------------------------------
-- Juice
---------------------------------------------------------------------------
-- Rolling counter: value shown t seconds after the target changed (ease out cubic).
function Onboarding.rollValue(from: number, to: number, t: number, duration: number?): number
	local d = duration or 0.5
	if t >= d or from == to then
		return to
	end
	local a = math.clamp(t / d, 0, 1)
	local e = 1 - (1 - a) ^ 3
	return from + (to - from) * e
end

export type ComboTier = { tier: number, finisher: boolean, scale: number, shake: number, key: string? }
-- n = hits in the chain, finisher = Config.Combat.comboFinisher (every Nth hit is the big one).
function Onboarding.comboTier(n: number, finisher: number): ComboTier
	local isFinisher = n >= finisher and n % finisher == 0
	local tier = if n >= finisher * 3 then 3 elseif n >= finisher * 2 then 2 elseif n >= 3 then 1 else 0
	local out: ComboTier = { tier = tier, finisher = isFinisher, scale = 1.15 + tier * 0.1, shake = 0, key = nil }
	if isFinisher then
		out.scale = 1.5 + tier * 0.1
		out.shake = 0.5 + tier * 0.15
		out.key = if tier >= 3 then "combo.t3" elseif tier == 2 then "combo.t2" else "combo.t1"
	elseif n == 3 then
		out.key = "combo.start"
	end
	return out
end

export type TransformPlan = { windup: number, zoom: number, kick: number, shake: number, bars: boolean, flash: number, shells: number, titleHold: number }
-- Timeline of the player's own transformation. reduced = shake setting off: no camera motion
-- and a softer flash. lite = phones: fewer shells, no letterbox motion cost.
function Onboarding.transformPlan(lite: boolean, reduced: boolean, first: boolean): TransformPlan
	local plan: TransformPlan = {
		windup = if first then 0.55 else 0.3,
		zoom = if first then -9 else -5,
		kick = if first then 24 else 16,
		shake = if first then 1.5 else 1.1,
		bars = first,
		flash = if first then 0.85 else 0.65,
		shells = if lite then 2 else 4,
		titleHold = if first then 1.5 else 0.9,
	}
	if reduced then
		plan.zoom = 0
		plan.kick = 0
		plan.shake = 0
		plan.flash = plan.flash * 0.4
		plan.windup = math.min(plan.windup, 0.3)
	end
	return plan
end

return Onboarding
