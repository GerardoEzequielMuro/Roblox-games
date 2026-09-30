--!strict
-- Speedrun time formatting (pure Luau, unit-tested in tests/p0_test.luau).
local RunTime = {}

-- 754567 -> "12:34.567"; an hour or more -> "1:02:03.004". Negative / nil -> "00:00.000".
function RunTime.format(ms: number?): string
	local v = math.max(0, math.floor(tonumber(ms) or 0))
	local millis = v % 1000
	local totalSec = v // 1000
	local sec = totalSec % 60
	local totalMin = totalSec // 60
	if totalMin >= 60 then
		return ("%d:%02d:%02d.%03d"):format(totalMin // 60, totalMin % 60, sec, millis)
	end
	return ("%02d:%02d.%03d"):format(totalMin, sec, millis)
end

return RunTime
