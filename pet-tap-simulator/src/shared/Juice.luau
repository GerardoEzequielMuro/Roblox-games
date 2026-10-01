--!strict
-- Pure helpers behind the "game feel" effects (camera micro-shake, capped bursts, number
-- roll-ups). The client modules do the Roblox side; the rules live here so tests/juice.luau
-- can check them. No Roblox APIs in here.
local Juice = {}

Juice.MAX_SHAKE = 0.45 -- studs of camera offset, the most any shake can ever move the view
Juice.MAX_BURST_PARTS = 24 -- UI particles alive at once (all bursts together)

-- 1 at t = 0 easing out to 0 at t = dur.
function Juice.envelope(t: number, dur: number): number
	if dur <= 0 or t >= dur then
		return 0
	end
	local k = 1 - math.max(t, 0) / dur
	return k * k
end

-- Final amplitude (studs) for a requested strength 0..1. Reduced motion turns it off,
-- lite devices get a calmer one.
function Juice.shakeAmplitude(strength: number, reducedMotion: boolean, lite: boolean): number
	if reducedMotion then
		return 0
	end
	local a = math.clamp(strength, 0, 1) * Juice.MAX_SHAKE
	if lite then
		a *= 0.6
	end
	return a
end

-- Offset (x, y) at time t of a shake of amplitude amp lasting dur. Deterministic.
function Juice.shakeOffset(t: number, dur: number, amp: number, seed: number): (number, number)
	local e = Juice.envelope(t, dur) * amp
	if e <= 0 then
		return 0, 0
	end
	return math.sin(t * 61 + seed) * e, math.cos(t * 53 + seed * 1.7) * e * 0.8
end

-- How many of `want` particles may spawn now, given how many are alive and the global cap.
function Juice.allowBurst(want: number, alive: number, cap: number, mult: number): number
	local scaled = math.floor(want * math.clamp(mult, 0, 1) + 0.5)
	return math.max(0, math.min(scaled, cap - alive))
end

-- Exponential approach used by the counters that roll up: moves cur toward target.
function Juice.roll(cur: number, target: number, dt: number, rate: number?): number
	if math.abs(target - cur) < 1 then
		return target
	end
	return cur + (target - cur) * math.min(1, dt * (rate or 9))
end

-- Scale for the squash of a button hit: >1 stretch up, <1 squash, settles on 1.
-- t in 0..1 is the progress of the animation (damped spring look without a spring).
function Juice.squash(t: number, amount: number): number
	if t >= 1 then
		return 1
	end
	return 1 + math.sin(t * math.pi * 3) * amount * (1 - t) * (1 - t)
end

return Juice
