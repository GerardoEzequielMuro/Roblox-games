--!strict
-- Scheduled live events (pure Luau, unit-tested). All times are UTC unix seconds.
--   weekly: { id, kind = "weekly", fromWday, toWday, allDayUTC = true }  (wday: Sunday = 1 ... Saturday = 7,
--           as in os.date("!*t")); active from fromWday 00:00 through toWday 23:59:59, wrapping the week.
--   daily:  { id, kind = "daily", hourUTC, duration }  active for `duration` s from hourUTC:00 every day.
-- An override { id, endsAt } (admin /event command) wins while it lasts.
local LiveEvents = {}

export type EventDef = {
	id: string,
	kind: string,
	fromWday: number?,
	toWday: number?,
	allDayUTC: boolean?,
	hourUTC: number?,
	duration: number?,
}
export type Active = { id: string, endsAt: number }
export type Upcoming = { id: string, startsAt: number }

local DAY = 86400

local function dayStart(t: number): number
	return t - (t % DAY)
end

local function wdayOf(t: number): number
	-- 1970-01-01 was a Thursday (wday 5)
	return ((t // DAY + 4) % 7) + 1
end
LiveEvents.wdayOf = wdayOf

-- If `def` is active at `now`, returns when it ends; else nil.
local function activeUntil(def: EventDef, now: number): number?
	if def.kind == "weekly" then
		local from, to = def.fromWday or 7, def.toWday or 1
		local span = ((to - from) % 7) + 1 -- days in the window
		local wd = wdayOf(now)
		local into = (wd - from) % 7 -- days since the window's first day
		if into < span then
			return dayStart(now) + (span - into) * DAY
		end
		return nil
	elseif def.kind == "daily" then
		local startH = (def.hourUTC or 0) * 3600
		local dur = def.duration or 3600
		local sinceStart = (now - dayStart(now) - startH) % DAY
		if sinceStart < dur then
			return now - sinceStart + dur
		end
		return nil
	end
	return nil
end

-- Next start strictly after `now` (or now's window start if already active is NOT returned).
local function nextStartOf(def: EventDef, now: number): number?
	if def.kind == "weekly" then
		local from = def.fromWday or 7
		local wd = wdayOf(now)
		local days = (from - wd) % 7
		local t = dayStart(now) + days * DAY
		if t <= now then
			t += 7 * DAY
		end
		return t
	elseif def.kind == "daily" then
		local t = dayStart(now) + (def.hourUTC or 0) * 3600
		if t <= now then
			t += DAY
		end
		return t
	end
	return nil
end

function LiveEvents.current(now: number, defs: { EventDef }, override: Active?): Active?
	if override and override.endsAt > now then
		return { id = override.id, endsAt = override.endsAt }
	end
	for _, def in defs do
		local ends = activeUntil(def, now)
		if ends then
			return { id = def.id, endsAt = ends }
		end
	end
	return nil
end

-- Is event `id` active now (scheduled or overridden)?
function LiveEvents.isActive(id: string, now: number, defs: { EventDef }, override: Active?): boolean
	if override and override.endsAt > now and override.id == id then
		return true
	end
	for _, def in defs do
		if def.id == id and activeUntil(def, now) then
			return true
		end
	end
	return false
end

function LiveEvents.nextStart(now: number, defs: { EventDef }): Upcoming?
	local best: Upcoming? = nil
	for _, def in defs do
		local t = nextStartOf(def, now)
		if t and (best == nil or t < best.startsAt) then
			best = { id = def.id, startsAt = t }
		end
	end
	return best
end

return LiveEvents
