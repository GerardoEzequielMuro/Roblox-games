--!strict
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.abbrev(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local s = if n >= 100 then string.format("%d", math.floor(n)) elseif n >= 10 then string.format("%.1f", math.floor(n * 10) / 10) else string.format("%.2f", math.floor(n * 100) / 100)
	s = s:gsub("%.?0+$", "")
	return sign .. s .. SUFFIXES[i]
end

function Format.cash(n: number): string
	return "$" .. Format.abbrev(n)
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

return Format
