--!strict
-- Pure maths for the "game feel" helpers (client/UI/Feel.luau). PURE Luau.
local FeelMath = {}

function FeelMath.easeOutCubic(a: number): number
	a = math.clamp(a, 0, 1)
	return 1 - (1 - a) ^ 3
end

-- Overshoots 1 a little and settles: the "pop" of a number or a button.
function FeelMath.easeOutBack(a: number): number
	a = math.clamp(a, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end

-- Value of a counter that rolls from `from` to `to` over `duration` seconds; always a whole number
-- and always exactly `to` at the end (a rolling counter must never end on a wrong value).
function FeelMath.roll(from: number, to: number, t: number, duration: number): number
	if duration <= 0 or t >= duration then
		return math.floor(to)
	end
	return math.floor(from + (to - from) * FeelMath.easeOutCubic(t / duration) + 0.5)
end

-- Roll time grows with the size of the jump but is capped, so big payouts never feel slow.
function FeelMath.rollDuration(from: number, to: number): number
	local d = math.abs(to - from)
	if d <= 0 then
		return 0
	end
	return math.clamp(0.25 + math.log10(d + 1) * 0.18, 0.25, 0.8)
end

-- Squash and stretch of a pressed / popped element: x and y scale at progress a (0..1). The
-- element squashes wide then springs tall and settles at 1.
function FeelMath.squash(a: number, power: number): (number, number)
	a = math.clamp(a, 0, 1)
	local wave = math.sin(a * math.pi * 2.5) * (1 - a)
	return 1 + wave * power, 1 - wave * power * 0.8
end

-- How many of `want` effects may start when `active` are already running (cap `cap`).
function FeelMath.budget(active: number, want: number, cap: number): number
	return math.max(0, math.min(want, cap - active))
end

-- Camera shake offset magnitude at time t of a shake of `power` lasting `duration`.
function FeelMath.shake(power: number, t: number, duration: number): number
	if duration <= 0 or t >= duration or t < 0 then
		return 0
	end
	return power * (1 - t / duration)
end

return FeelMath
