--!strict
-- Live event schedule (pure; unit-tested with luau.exe). Times are UTC unix seconds.
--   recurring: { id, every, offset, duration } -> active while (now - offset) % every < duration
--   weekly:    { id, fromWday, toWday, allDayUTC } -> active on those UTC weekdays (wraps: 7 -> 1)
-- An admin override { id, endsAt } wins while endsAt > now.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local LiveEvents = {}

export type Active = { id: string, endsAt: number }
export type Override = { id: string, endsAt: number }

local DAY = 86400

local function inWeekRange(wday: number, from: number, to: number): boolean
	if from <= to then
		return wday >= from and wday <= to
	end
	return wday >= from or wday <= to
end

-- Every active event, override first, then recurring, then weekly.
function LiveEvents.active(now: number, override: Override?): { Active }
	local list: { Active } = {}
	local seen: { [string]: boolean } = {}
	if override and override.endsAt > now and Config.LiveEventDefs[override.id] then
		table.insert(list, { id = override.id, endsAt = override.endsAt })
		seen[override.id] = true
	end
	for _, r in Config.LiveEvents.recurring do
		local phase = (now - r.offset) % r.every
		if phase < r.duration and not seen[r.id] then
			table.insert(list, { id = r.id, endsAt = now - phase + r.duration })
			seen[r.id] = true
		end
	end
	for _, w in Config.LiveEvents.weekly do
		local wday = (os.date("!*t", now) :: any).wday :: number
		if inWeekRange(wday, w.fromWday, w.toWday) and not seen[w.id] then
			-- ends at the UTC midnight after the last day of the range
			local dayStart = now - now % DAY
			local d = wday
			local endsAt = dayStart + DAY
			while d ~= w.toWday do
				d = d % 7 + 1
				endsAt += DAY
			end
			table.insert(list, { id = w.id, endsAt = endsAt })
			seen[w.id] = true
		end
	end
	return list
end

function LiveEvents.current(now: number, override: Override?): Active?
	return LiveEvents.active(now, override)[1]
end

-- Next start time of a recurring event (strictly after now) and its id.
function LiveEvents.nextStart(now: number): (number?, string?)
	local best: number?, bestId: string? = nil, nil
	for _, r in Config.LiveEvents.recurring do
		local phase = (now - r.offset) % r.every
		local t = now - phase + r.every
		if not best or t < best then
			best, bestId = t, r.id
		end
	end
	return best, bestId
end

-- Combined multipliers of every active event.
function LiveEvents.effects(active: { Active }): { luckMult: number, goldenMult: number }
	local luck, golden = 1, 1
	for _, a in active do
		local def = Config.LiveEventDefs[a.id]
		if def then
			luck *= def.luckMult or 1
			golden *= def.goldenMult or 1
		end
	end
	return { luckMult = luck, goldenMult = golden }
end

return LiveEvents
