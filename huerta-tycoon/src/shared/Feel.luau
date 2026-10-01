--!strict
-- Pure game-feel rules (no Roblox services): camera shake budget, rarity tiers for reveals, number-pop scale,
-- effect caps. Tested by tests/onboarding_test.luau.
local Feel = {}

-- Camera micro-shake: returns (amplitude in studs, seconds). 0 = no shake (reduced motion, or too weak to matter).
function Feel.shake(power: number, lite: boolean, reduced: boolean): (number, number)
	if reduced or power <= 0 then
		return 0, 0
	end
	local p = math.clamp(power, 0, 1)
	local amp = 0.05 + p * 0.22
	if lite then
		amp *= 0.6
	end
	return amp, 0.18 + p * 0.22
end

-- Rarity tier of a drop from its mutation multiplier and whether it is a Giant size.
-- 0 = plain, 1 = nice, 2 = rare, 3 = legendary.
function Feel.tier(multiplier: number?, giant: boolean?): number
	local m = multiplier or 1
	if m >= 20 then
		return 3
	elseif m >= 8 or giant == true then
		return 2
	elseif m > 1 then
		return 1
	end
	return 0
end

-- Only tier 2+ gets the banner, shake and fanfare.
function Feel.bigMoment(tier: number): boolean
	return tier >= 2
end

-- Shake power for a tier.
function Feel.tierPower(tier: number): number
	return if tier >= 3 then 1 elseif tier == 2 then 0.55 else 0
end

-- Scale of a number "pop" that grows with the amount relative to the usual one (clamped so it never explodes).
function Feel.popScale(amount: number, typical: number): number
	if typical <= 0 or amount <= 0 then
		return 1.1
	end
	return math.clamp(1.1 + math.log10(1 + amount / typical) * 0.25, 1.1, 1.6)
end

-- Counter roll-up: the displayed value moves a fraction of the gap per second (frame-rate independent).
function Feel.roll(shown: number, target: number, dt: number, rate: number?): number
	local diff = target - shown
	local k = 1 - math.exp(-(rate or 7) * math.max(dt, 0))
	local nxt = shown + diff * k
	if math.abs(target - nxt) < math.max(1, math.abs(target) * 0.0005) then
		return target
	end
	return nxt
end

-- Concurrent-effect cap: how many new effects may start given `live` already running.
function Feel.room(live: number, cap: number, want: number): number
	return math.max(0, math.min(want, cap - live))
end

return Feel
