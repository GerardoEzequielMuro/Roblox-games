--!strict
-- Scheduled global events: pure schedule math (UTC, no Roblox services).
--   schedule = { weekly = { {id, wday (Sunday=1..Saturday=7), hourUTC, minute, duration} },
--                recurring = { {id, every, offset, duration} } }
--   override = { id, endsAt }? (admin-triggered, honored until endsAt)
local LiveEvents = {}

export type Current = { id: string, endsAt: number }
export type Next = { id: string, startsAt: number }

local WEEK = 7 * 86400

-- Most recent start (<= now) of a weekly event.
function LiveEvents.weeklyStart(now: number, e: any): number
	local t = os.date("!*t", now) :: any
	local secOfDay = t.hour * 3600 + t.min * 60 + t.sec
	local dayDiff = (t.wday - e.wday) % 7
	local start = now - dayDiff * 86400 - secOfDay + e.hourUTC * 3600 + (e.minute or 0) * 60
	if start > now then
		start -= WEEK
	end
	return start
end

function LiveEvents.current(now: number, schedule: any, override: any?): Current?
	if override and type(override.id) == "string" and type(override.endsAt) == "number" and now < override.endsAt then
		return { id = override.id, endsAt = override.endsAt }
	end
	for _, e in schedule.weekly or {} do
		local s = LiveEvents.weeklyStart(now, e)
		if now < s + e.duration then
			return { id = e.id, endsAt = s + e.duration }
		end
	end
	for _, e in schedule.recurring or {} do
		local phase = (now - (e.offset or 0)) % e.every
		if phase < e.duration then
			return { id = e.id, endsAt = now - phase + e.duration }
		end
	end
	return nil
end

-- Next start strictly after now (weekly wins ties).
function LiveEvents.nextStart(now: number, schedule: any): Next?
	local best: Next? = nil
	for _, e in schedule.weekly or {} do
		local s = LiveEvents.weeklyStart(now, e) + WEEK
		if not best or s < best.startsAt then
			best = { id = e.id, startsAt = s }
		end
	end
	for _, e in schedule.recurring or {} do
		local phase = (now - (e.offset or 0)) % e.every
		local s = now - phase + e.every
		if not best or s < best.startsAt then
			best = { id = e.id, startsAt = s }
		end
	end
	return best
end

return LiveEvents
