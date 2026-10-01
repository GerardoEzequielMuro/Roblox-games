--!strict
-- Pure logic of the first-minute tutorial helper (no Roblox APIs, tested in tests/unit.luau).
-- The step itself lives in the profile (server); this decides what the client points at and
-- when it offers a way out, so the tutorial can never trap a player:
--   * the skip chip appears after SKIP_AFTER seconds on one step (and the Settings button
--     always works),
--   * a step whose real target cannot be done yet (nothing to sell, not enough Stardust)
--     points at the planets instead, with a short reason,
--   * a target that is missing (planet field still streaming) falls back to a fixed spot.
local TutorialFlow = {}

TutorialFlow.SKIP_AFTER = 25 -- seconds on one step before "Skip" shows up
TutorialFlow.NUDGE_AFTER = 10 -- seconds before the arrow gets louder

export type Ctx = {
	step: string,
	elapsed: number, -- seconds on this step
	cargo: number, -- ore in the cargo hold
	stardust: number,
	needDust: number?, -- Stardust the step costs (tool / capsule), if any
	targetFound: boolean, -- the live target exists in the world right now
}
export type Hint = {
	target: string, -- "planet" | "refinery" | "capsule" | "workshop" | "autoButton" | "fallback"
	reasonKey: string?, -- optional short locale key explaining a detour
	loud: boolean,
	skip: boolean,
}

local TARGET: { [string]: string } = {
	mine = "planet",
	core = "planet",
	sell = "refinery",
	capsule = "capsule",
	tool = "workshop",
	auto = "autoButton",
}

function TutorialFlow.hint(ctx: Ctx): Hint
	local target = TARGET[ctx.step]
	local reason: string? = nil
	if target == nil then
		target = "fallback"
	elseif ctx.step == "sell" and ctx.cargo <= 0 then
		target, reason = "planet", "tutorial.hint_ore"
	elseif (ctx.step == "tool" or ctx.step == "capsule") and ctx.needDust ~= nil and ctx.stardust < ctx.needDust then
		target, reason = "planet", "tutorial.hint_dust"
	end
	if target == "planet" and not ctx.targetFound then
		target = "fallback"
	end
	return {
		target = target,
		reasonKey = reason,
		loud = ctx.elapsed >= TutorialFlow.NUDGE_AFTER,
		skip = ctx.elapsed >= TutorialFlow.SKIP_AFTER,
	}
end

-- Progress bar value for the objective pill: steps done / total, clamped.
function TutorialFlow.progress(step: number, total: number): number
	if total <= 0 then
		return 0
	end
	return math.clamp((step - 1) / total, 0, 1)
end

-- Tracks time on the current step. `tick` returns seconds on the step, restarting the
-- clock whenever the step id changes (also after a rejoin: it starts from 0 again).
function TutorialFlow.newClock()
	local current: string? = nil
	local since = 0
	local clock = {}
	function clock.tick(step: string?, now: number): number
		if step ~= current then
			current, since = step, now
		end
		return now - since
	end
	return clock
end

return TutorialFlow
