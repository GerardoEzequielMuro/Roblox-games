--!strict
-- First-session tutorial as a pure step machine: (profile snapshot, context) -> the one thing
-- the player should do right now. Nothing is stored: the step is derived from counters that
-- are saved with the profile (hatches, zones, rebirths, taps), so it resumes by itself after a
-- rejoin and a veteran never sees it. It cannot soft-lock:
--   * "skipped" (the Skip button) ends it at any time,
--   * the first egg is never required to walk anywhere: if the beam target is missing
--     (targetOk == false) the step falls back to a text-only "find the egg",
--   * a player who stays idle on a step gets the "help" variant (bigger pulse, clearer text).
-- Used by src/client/Onboarding.luau; tests/onboarding.luau checks it. No Roblox APIs here.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")
local HudUnlock: typeof(require(script.Parent.HudUnlock)) = if script then require(script.Parent.HudUnlock) :: any else (require :: any)("./HudUnlock")

local Onboarding = {}

Onboarding.HATCH_GOAL = 5 -- eggs hatched before the tutorial hands over to the normal objectives
Onboarding.HELP_AFTER = 14 -- seconds without progress on a step before the help variant shows

export type Snapshot = {
	totalHatched: number?,
	zones: { number }?,
	rebirths: number?,
	taps: number?,
}

export type Context = {
	skipped: boolean?, -- the player pressed Skip this session
	nearEgg: boolean?, -- the player is within reach of the first egg
	targetOk: boolean?, -- the first egg's position is known (false = it could not be found)
	idle: number?, -- seconds without progress on the current step
}

export type Step = {
	id: string, -- "tap" | "walk" | "find" | "hatch" | "more" | "done"
	key: string, -- translation key (3-6 words)
	args: { [string]: any },
	pulse: string, -- "tap" (pulse the TAP button) | "egg" (pulse the egg prompt) | "none"
	beam: boolean, -- show the beam to the first egg
	help: boolean,
	skippable: boolean,
}

local function done(): Step
	return { id = "done", key = "", args = {}, pulse = "none", beam = false, help = false, skippable = false }
end

function Onboarding.price(): number
	return Config.Eggs[1].price
end

function Onboarding.isVeteran(s: Snapshot): boolean
	return (s.rebirths or 0) > 0 or (if s.zones then #s.zones else 1) >= 2
end

function Onboarding.step(s: Snapshot, ctx: Context?): Step
	local c: Context = ctx or {}
	local hatched = s.totalHatched or 0
	if c.skipped or Onboarding.isVeteran(s) or hatched >= Onboarding.HATCH_GOAL then
		return done()
	end
	local taps = s.taps or 0
	local help = (c.idle or 0) >= Onboarding.HELP_AFTER
	local canBuy = taps >= Onboarding.price()
	if hatched < 1 then
		if not canBuy then
			return { id = "tap", key = if help then "ftue.tap_help" else "ftue.tap", args = {}, pulse = "tap", beam = false, help = help, skippable = true }
		end
		if c.nearEgg then
			return { id = "hatch", key = "ftue.hatch", args = {}, pulse = "egg", beam = false, help = help, skippable = true }
		end
		if c.targetOk == false then
			return { id = "find", key = "ftue.find_egg", args = {}, pulse = "none", beam = false, help = help, skippable = true }
		end
		return { id = "walk", key = "ftue.walk", args = {}, pulse = "none", beam = true, help = help, skippable = true }
	end
	-- first pet owned: a few more hatches, then the normal objectives take over
	local beam = canBuy and not c.nearEgg and c.targetOk ~= false
	return {
		id = "more",
		key = "ftue.more",
		args = { have = hatched, n = Onboarding.HATCH_GOAL },
		pulse = if canBuy and c.nearEgg then "egg" else "none",
		beam = beam,
		help = help,
		skippable = true,
	}
end

---------------------------------------------------------------------------
-- Idle tracker: seconds since the step or its progress last changed
---------------------------------------------------------------------------
export type Tracker = { id: string, progress: number, since: number }

function Onboarding.newTracker(now: number): Tracker
	return { id = "", progress = -1, since = now }
end

-- Call every refresh; returns the idle seconds. Any change of step or progress resets it.
function Onboarding.idle(t: Tracker, id: string, progress: number, now: number): number
	if t.id ~= id or t.progress ~= progress then
		t.id, t.progress, t.since = id, progress, now
		return 0
	end
	return math.max(0, now - t.since)
end

-- Progress number to feed Onboarding.idle for the current step: taps while tapping, hatches after.
function Onboarding.progressOf(s: Snapshot): number
	local hatched = s.totalHatched or 0
	if hatched < 1 then
		return (s.taps or 0) + hatched * 1e9
	end
	return hatched * 1e9
end

---------------------------------------------------------------------------
-- HUD unlock moments
---------------------------------------------------------------------------
-- Names that became visible between two HudUnlock.visible() results, in HUD order.
-- prev == nil is the first snapshot of the session: nothing is "new" then (no replay on rejoin).
function Onboarding.newlyUnlocked(prev: { [string]: boolean }?, now: { [string]: boolean }): { string }
	local out: { string } = {}
	if not prev then
		return out
	end
	for _, name in HudUnlock.NAMES do
		if now[name] and not prev[name] then
			table.insert(out, name)
		end
	end
	return out
end

return Onboarding
