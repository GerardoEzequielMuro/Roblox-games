--!strict
-- The table / turn rules around a match that are not the match itself: how many bots fill
-- a table, how long a countdown is, who stays seated after a match, and the AFK bookkeeping
-- (when a human's turns start being played for them, and how they get them back).
-- Pure: no Roblox APIs, no clocks. Tables and MatchRunner call it; tests/unit_core.luau
-- drives it.
local MatchFlow = {}

export type ModeDef = { maxPlayers: number, fillTo: number }

-- How many entrants a match starts with. Bots fill public tables (and private ones with
-- fill on) up to the mode's fillTo; duels never get bots unless a duelist walked off.
function MatchFlow.entrants(humans: number, mode: ModeDef, fill: boolean): number
	if humans <= 0 then
		return 0
	end
	local want = if fill then math.max(humans, mode.fillTo) else humans
	return math.clamp(math.max(want, 2), 2, mode.maxPlayers)
end

-- Countdown when someone sits at an open public table. A brand-new player gets a short one.
function MatchFlow.countdownFor(tutorialDone: boolean, normal: number): number
	return if tutorialDone then normal else 4
end

-- New countdown end after a sit: a full table starts sooner, never later.
function MatchFlow.countdownAfterSit(currentEnds: number, now: number, humans: number, maxPlayers: number, fullSeconds: number): number
	if humans >= maxPlayers then
		return math.min(currentEnds, now + fullSeconds)
	end
	return currentEnds
end

-- After a match: does this seated human stay for the next one?
-- "gone" = no longer at this table; "stay" = keeps the seat; "leave" = stands up.
function MatchFlow.afterMatch(stillHere: boolean, private: boolean, duel: boolean, autoQueue: boolean): string
	if not stillHere then
		return "gone"
	end
	if private or (autoQueue and not duel) then
		return "stay"
	end
	return "leave"
end

---------------------------------------------------------------------------
-- AFK
---------------------------------------------------------------------------
-- The server plays a human's turn when their Auto-play toggle is on, or after
-- AFK_TURNS turns in a row where a timer ran out on them.
MatchFlow.AFK_TURNS = 2

export type Afk = { idle: { [string]: number }, counted: { [string]: string } }

function MatchFlow.newAfk(): Afk
	return { idle = {}, counted = {} }
end

function MatchFlow.isAuto(afk: Afk, id: string, toggle: boolean): boolean
	return toggle or (afk.idle[id] or 0) >= MatchFlow.AFK_TURNS
end

-- A timer ran out on `id` during turn `turnKey` (decide or brake). Counts once per turn, so
-- one idle turn (decide timeout + brake timeout) is one strike, not two.
function MatchFlow.timedOut(afk: Afk, id: string, turnKey: string)
	if afk.counted[id] == turnKey then
		return
	end
	afk.counted[id] = turnKey
	afk.idle[id] = (afk.idle[id] or 0) + 1
end

-- The player did something (played a card, aimed, spun, braked, or pressed "I'm back").
function MatchFlow.active(afk: Afk, id: string)
	afk.idle[id] = 0
	afk.counted[id] = nil
end

return MatchFlow
