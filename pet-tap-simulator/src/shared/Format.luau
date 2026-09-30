--!strict
-- Number / time formatting. Pure Luau.
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(s: string): string
	if s:find("%.") then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return s
end

function Format.abbrev(n: number): string
	if n ~= n or n == math.huge then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local s
	if n >= 100 then
		s = tostring(math.floor(n))
	elseif n >= 10 then
		s = trim(string.format("%.1f", math.floor(n * 10) / 10))
	else
		s = trim(string.format("%.2f", math.floor(n * 100) / 100))
	end
	return sign .. s .. SUFFIXES[i]
end

function Format.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

-- Percent chance with sensible precision ("60%", "2.4%", "0.001%", "1 in 100,000").
function Format.chance(pct: number): string
	if pct >= 10 then
		return string.format("%d%%", math.floor(pct + 0.5))
	elseif pct >= 1 then
		return trim(string.format("%.1f", pct)) .. "%"
	elseif pct >= 0.1 then
		return trim(string.format("%.2f", pct)) .. "%"
	elseif pct >= 0.01 then
		return trim(string.format("%.3f", pct)) .. "%"
	elseif pct > 0 then
		return "1 in " .. Format.commas(100 / pct)
	end
	return "0%"
end

return Format
