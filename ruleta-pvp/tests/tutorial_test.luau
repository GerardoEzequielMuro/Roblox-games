-- Pure tests for the first-match guide and the loading flow:
--   luau tests/tutorial_test.luau   (from the game folder)
local Tutorial = require("../src/shared/Tutorial")
local LoadingFlow = require("../src/shared/LoadingFlow")

local checks, fails = 0, 0
local function check(name: string, cond: boolean, extra: any?)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL: " .. name .. (if extra ~= nil then " (" .. tostring(extra) .. ")" else ""))
	end
end

local function ctx(over: { [string]: any }?)
	local c: any = Tutorial.newContext()
	c.done = false
	for k, v in over or {} do
		c[k] = v
	end
	return c
end

-- the whole first match, step by step
check("lobby: press play", Tutorial.step(ctx()) == "play")
check("seated waiting: wait", Tutorial.step(ctx({ seated = true })) == "wait")
check("match, not my turn: watch", Tutorial.step(ctx({ seated = true, inMatch = true })) == "watch")
check("my turn, no target: target", Tutorial.step(ctx({ seated = true, inMatch = true, myTurn = true, phase = "decide" })) == "target")
check("my turn, target picked: spin", Tutorial.step(ctx({ seated = true, inMatch = true, myTurn = true, phase = "decide", targetPicked = true })) == "spin")
check("my turn, wheel turning: brake", Tutorial.step(ctx({ seated = true, inMatch = true, myTurn = true, phase = "spin" })) == "brake")
check("my turn, braked: watch", Tutorial.step(ctx({ seated = true, inMatch = true, myTurn = true, phase = "brake" })) == "watch")
check("eliminated: out", Tutorial.step(ctx({ seated = true, inMatch = true, eliminated = true })) == "out")
check("eliminated beats my turn", Tutorial.step(ctx({ inMatch = true, eliminated = true, myTurn = true, phase = "decide" })) == "out")

-- nothing to show
check("done: none", Tutorial.step(ctx({ done = true })) == "none")
check("skipped: none", Tutorial.step(ctx({ skipped = true })) == "none")
check("spectating: none", Tutorial.step(ctx({ inMatch = true, spectating = true })) == "none")
check("result screen: none", Tutorial.step(ctx({ inMatch = true, resultShown = true })) == "none")
check("done in a match: none", Tutorial.step(ctx({ done = true, inMatch = true, myTurn = true, phase = "decide" })) == "none")

-- resume after a rejoin: a fresh context with done=false lands on "play" again, whatever happened before
check("rejoin: play again", Tutorial.step(ctx()) == "play")
-- every step has a line, and pointer steps have a target name
for _, s in { "play", "wait", "target", "spin", "brake", "watch", "out" } do
	check("line for " .. s, Tutorial.keyFor[s] ~= nil)
end
for _, s in { "play", "target", "spin", "brake" } do
	check("pointer for " .. s, Tutorial.pointerFor[s] ~= nil)
end
check("no pointer for wait", Tutorial.pointerFor.wait == nil)

-- pointer availability
check("pointer when present", Tutorial.pointer("play", { play = true }) == "play")
check("no pointer when missing", Tutorial.pointer("play", {}) == nil)
check("no pointer for watch", Tutorial.pointer("watch", { play = true, targets = true, action = true }) == nil)

-- minimal HUD
check("minimal HUD for a new player", Tutorial.minimalHud(false, false) == true)
check("full HUD once done", Tutorial.minimalHud(true, false) == false)
check("full HUD once skipped", Tutorial.minimalHud(false, true) == false)

-- tracker: missing target recovery and skip
local t = Tutorial.newTracker()
check("draws when target exists", Tutorial.update(t, "play", true, 0) == true)
check("does not draw when missing", Tutorial.update(t, "play", false, 1) == false)
check("not too long yet", Tutorial.missingTooLong(t, 2) == false)
check("too long after the grace", Tutorial.missingTooLong(t, 1 + Tutorial.MISSING_GRACE + 0.1) == true)
check("target back: draws again", Tutorial.update(t, "play", true, 5) == true)
check("target back: grace reset", Tutorial.missingTooLong(t, 100) == false)
check("step change resets missing", (function()
	Tutorial.update(t, "target", false, 6)
	Tutorial.update(t, "spin", false, 8)
	return Tutorial.missingTooLong(t, 8.5) == false
end)())
check("steps without pointer never draw", Tutorial.update(t, "watch", true, 9) == false)
Tutorial.skip(t)
check("skip sticks", t.skipped == true)

-- exhaustive: every combination yields a valid step (never errors, never nil)
local valid = { none = true, play = true, wait = true, target = true, spin = true, brake = true, watch = true, out = true }
local n = 0
for _, done in { false, true } do
	for _, skipped in { false, true } do
		for _, seated in { false, true } do
			for _, inMatch in { false, true } do
				for _, myTurn in { false, true } do
					for _, phase in { "idle", "decide", "spin", "brake" } do
						for _, picked in { false, true } do
							for _, out in { false, true } do
								local s = Tutorial.step({ done = done, skipped = skipped, seated = seated, inMatch = inMatch, spectating = false, myTurn = myTurn, phase = phase, targetPicked = picked, eliminated = out, resultShown = false })
								n += 1
								if not valid[s] then
									check("valid step", false, s)
								end
								-- never a stuck state: with done or skipped, the guide is always off
								if (done or skipped) and s ~= "none" then
									check("done/skipped is silent", false, s)
								end
							end
						end
					end
				end
			end
		end
	end
end
check("exhaustive ran", n == 2 * 2 * 2 * 2 * 2 * 4 * 2 * 2)

---------------------------------------------------------------------------
-- LoadingFlow
---------------------------------------------------------------------------
local none: { [string]: boolean } = {}
local all: { [string]: boolean } = {}
for _, s in LoadingFlow.Stages do
	all[s.id] = true
end
local wsum = 0
for _, s in LoadingFlow.Stages do
	wsum += s.weight
end
check("weights add to 1", math.abs(wsum - 1) < 1e-9, wsum)
check("progress starts at 0", LoadingFlow.progress(none, 0) == 0)
check("progress 1 when all done", LoadingFlow.progress(all, 0.1) == 1)
check("progress capped below 1 until done", LoadingFlow.progress(none, 100) <= 0.92)
check("progress creeps with time", LoadingFlow.progress(none, 3) > LoadingFlow.progress(none, 1))
local half = { game = true, world = true }
check("progress grows with stages", LoadingFlow.progress(half, 0) > LoadingFlow.progress({ game = true }, 0))
-- monotonic over time for a fixed set
local prev = -1
local mono = true
for i = 0, 60 do
	local p = LoadingFlow.progress(half, i / 10)
	mono = mono and p >= prev
	prev = p
end
check("progress monotonic in time", mono)

check("not dismissed before the minimum", LoadingFlow.shouldDismiss(all, 0.5) == false)
check("dismissed when done after the minimum", LoadingFlow.shouldDismiss(all, LoadingFlow.MIN_SECONDS) == true)
check("waits while stages are pending", LoadingFlow.shouldDismiss(half, 3) == false)
check("hard cap: dismissed whatever is pending", LoadingFlow.shouldDismiss(none, LoadingFlow.MAX_SECONDS) == true)
check("hard cap is a few seconds", LoadingFlow.MAX_SECONDS <= 8)
check("a failed stage counts as done", LoadingFlow.shouldDismiss({ game = true, world = true, ui = true, data = true }, 2) == true)

for seed = 0, 7 do
	for e = 0, 12, 0.5 do
		local i = LoadingFlow.tipIndex(seed, e)
		if i < 1 or i > LoadingFlow.TipCount or i ~= math.floor(i) then
			check("tip index in range", false, i)
		end
	end
end
check("tip rotates", LoadingFlow.tipIndex(0, 0) ~= LoadingFlow.tipIndex(0, LoadingFlow.TIP_SECONDS + 0.1))

print(string.format("%d checks, %d failures", checks, fails))
if fails > 0 then
	print("TUTORIAL TEST FAILED")
	error("failed")
end
print("TUTORIAL TEST PASSED")
