--!strict
-- First-match guide logic. Pure: no Roblox APIs, no clocks (the caller passes `now`).
-- The guide never stores progress of its own: the step is a function of what the client
-- sees right now (is the profile's tutorial done, am I seated, is it my turn, which phase),
-- so it can not get stuck, resumes by itself after a rejoin and recovers from anything.
-- The only state is the Tracker: the session skip and "how long has the pointer pointed at
-- something that is not there", so a missing target degrades to text only.
local Tutorial = {}

export type Context = {
	done: boolean, -- profile.tutorialDone
	skipped: boolean, -- the player pressed Skip this session
	seated: boolean, -- sitting at a table (waiting or playing)
	inMatch: boolean, -- the match HUD is up and the match is on
	spectating: boolean,
	myTurn: boolean,
	phase: string, -- MatchHud phase: "idle" | "decide" | "spin" | "brake"
	targetPicked: boolean, -- a rival is already selected for this turn
	eliminated: boolean,
	resultShown: boolean,
}

export type Step = "none" | "play" | "wait" | "target" | "spin" | "brake" | "watch" | "out"

-- What each step points at (a name the Guide resolves to a GuiObject) and its short line.
-- Lines are 2-4 words on purpose.
Tutorial.pointerFor = {
	play = "play",
	target = "targets",
	spin = "action",
	brake = "action",
} :: { [string]: string }
Tutorial.keyFor = {
	play = "tut.step.play",
	wait = "tut.step.wait",
	target = "tut.step.target",
	spin = "tut.step.spin",
	brake = "tut.step.brake",
	watch = "tut.step.watch",
	out = "tut.step.out",
} :: { [string]: string }

function Tutorial.newContext(): Context
	return {
		done = true,
		skipped = false,
		seated = false,
		inMatch = false,
		spectating = false,
		myTurn = false,
		phase = "idle",
		targetPicked = false,
		eliminated = false,
		resultShown = false,
	}
end

-- The step to show. "none" = show nothing (done, skipped, spectating or the result screen).
function Tutorial.step(c: Context): Step
	if c.done or c.skipped or c.spectating or c.resultShown then
		return "none"
	end
	if not c.inMatch then
		if c.seated then
			return "wait" -- at the table, the countdown runs by itself
		end
		return "play"
	end
	if c.eliminated then
		return "out"
	end
	if c.myTurn then
		if c.phase == "decide" then
			return if c.targetPicked then "spin" else "target"
		elseif c.phase == "spin" then
			return "brake"
		end
	end
	return "watch"
end

-- Pointer target for a step, or nil when there is nothing to point at (or it is missing).
function Tutorial.pointer(step: Step, available: { [string]: boolean }): string?
	local name = Tutorial.pointerFor[step]
	if name and available[name] then
		return name
	end
	return nil
end

-- Does the game also want the HUD kept minimal for this player? (tutorial not done and not
-- skipped). The menu, goals and toggles come in after the first match.
function Tutorial.minimalHud(done: boolean, skipped: boolean): boolean
	return not done and not skipped
end

---------------------------------------------------------------------------
-- Tracker: skip + missing-target recovery
---------------------------------------------------------------------------
export type Tracker = { skipped: boolean, step: string, since: number, missingSince: number? }

-- A pointer whose target has been missing this long is dropped (the line stays).
Tutorial.MISSING_GRACE = 2.5

function Tutorial.newTracker(): Tracker
	return { skipped = false, step = "none", since = 0, missingSince = nil }
end

function Tutorial.skip(t: Tracker)
	t.skipped = true
end

-- Call every tick with the step and whether its pointer target exists right now. Returns
-- true when the pointer should be drawn.
function Tutorial.update(t: Tracker, step: string, targetExists: boolean, now: number): boolean
	if step ~= t.step then
		t.step = step
		t.since = now
		t.missingSince = nil
	end
	if step == "none" or Tutorial.pointerFor[step] == nil then
		return false
	end
	if targetExists then
		t.missingSince = nil
		return true
	end
	if t.missingSince == nil then
		t.missingSince = now
	end
	return false
end

-- True once the pointer has been gone long enough to tell the player in words instead.
function Tutorial.missingTooLong(t: Tracker, now: number): boolean
	return t.missingSince ~= nil and now - t.missingSince >= Tutorial.MISSING_GRACE
end

return Tutorial
