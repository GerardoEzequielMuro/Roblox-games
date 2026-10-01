--!strict
-- Pure helpers for game feel and the loading screen (no Roblox APIs; tested in tests/unit.luau).
local Juice = {}

-- Easing -------------------------------------------------------------------
function Juice.easeOutCubic(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

function Juice.easeOutBack(t: number): number
	t = math.clamp(t, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- Counter roll-up: one frame of exponential approach; snaps when within 1.
function Juice.rollStep(shown: number, target: number, dt: number, rate: number?): number
	if math.abs(target - shown) < 1 then
		return target
	end
	local a = math.min(1, dt * (rate or 9))
	return shown + (target - shown) * a
end

-- Camera shake ---------------------------------------------------------------
Juice.SHAKE = { crit = 0.12, hit = 0.1, break_ = 0.35, big = 0.6 } :: { [string]: number }

-- Amplitude in studs for a kind of event; 0 when the player asked for calm mode, and
-- reduced on the lite profile.
function Juice.shakeAmplitude(kind: string, calm: boolean, lite: boolean): number
	if calm then
		return 0
	end
	local base = if kind == "break" then Juice.SHAKE.break_ else Juice.SHAKE[kind] or 0
	return if lite then base * 0.6 else base
end

-- Decaying offset: returns x, y for time `t` into a shake of `life` seconds.
function Juice.shakeOffset(amp: number, t: number, life: number): (number, number)
	if amp <= 0 or t >= life then
		return 0, 0
	end
	local k = (1 - t / life) ^ 2 * amp
	return math.sin(t * 61) * k, math.cos(t * 47 + 1.3) * k
end

-- Keeps the strongest of two overlapping shakes instead of stacking them.
function Juice.mergeShake(curAmp: number, curLeft: number, newAmp: number, life: number): (number, number)
	if newAmp * life >= curAmp * curLeft then
		return newAmp, life
	end
	return curAmp, curLeft
end

-- Effects budget: how many of `count` particles may be spawned given how many are alive.
function Juice.budget(count: number, alive: number, cap: number, lite: boolean): number
	local want = if lite then math.ceil(count * 0.5) else count
	return math.max(0, math.min(want, cap - alive))
end

-- Loading screen ---------------------------------------------------------------
Juice.LOAD_MIN = 1.0 -- never flash the screen for less than this
Juice.LOAD_MAX = 6.0 -- never hold the player longer than this, whatever fails

export type LoadFlags = { remotes: boolean, state: boolean, world: boolean }

function Juice.loadProgress(elapsed: number, f: LoadFlags): number
	local p = 0.08
	if f.remotes then
		p = 0.3
	end
	if f.state then
		p = 0.65
	end
	if f.world then
		p = 1
	end
	-- never sits still: a slow crawl inside the current stage, and reaches 1 at LOAD_MAX
	local crawl = math.min(elapsed / Juice.LOAD_MAX, 1) * 0.25
	return math.clamp(math.max(p, math.min(0.95, p + crawl)), 0, 1)
end

function Juice.loadDone(elapsed: number, f: LoadFlags): boolean
	if elapsed >= Juice.LOAD_MAX then
		return true
	end
	return elapsed >= Juice.LOAD_MIN and f.state and f.world
end

function Juice.tipIndex(seed: number, count: number): number
	return (math.floor(seed) % math.max(1, count)) + 1
end

return Juice
