--!nocheck
-- Text measurement with the same fonts the Python renderer draws with (data/metrics.json).
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local T = {}
local metrics = nil

function T.load(path: string)
	metrics = serde.decode("json", fs.readFile(path))
end

local WEIGHTS = { Thin = 100, ExtraLight = 200, Light = 300, Regular = 400, Medium = 500, SemiBold = 600, Bold = 700, ExtraBold = 800, Heavy = 900 }

function T.fontKey(font): string
	local fam = "SourceSansPro"
	local weight = "Regular"
	if font then
		local ok, f = pcall(function()
			return font.Family
		end)
		if ok and f then
			fam = string.match(f, "families/([%w]+)%.json") or f
		end
		local ok2, w = pcall(function()
			return font.Weight.Name
		end)
		if ok2 and w then
			weight = w
		end
	end
	local base = metrics and metrics.map[fam] or "sans"
	local wv = WEIGHTS[weight] or 400
	if base == "gotham" then
		return if wv <= 500 then "gotham400" elseif wv <= 700 then "gotham700" else "gotham900"
	elseif base == "sans" then
		return if wv < 600 then "sans400" else "sans700"
	end
	return base
end

local function isEmojiCp(cp: number): boolean
	return (cp >= 0x1F000 and cp <= 0x1FAFF) or (cp >= 0x2600 and cp <= 0x27BF) or (cp >= 0x2B00 and cp <= 0x2BFF) or (cp >= 0x2300 and cp <= 0x23FF)
end

-- width in ems of a string (no wrapping)
local function emWidth(key: string, s: string): number
	local fm = metrics and metrics.fonts[key]
	if not fm then
		return #s * 0.55
	end
	local w = 0
	local ok = pcall(function()
		local prevRi = false
		for _, cp in utf8.codes(s) do
			if cp == 0xFE0F or cp == 0x200D or (cp >= 0x1F3FB and cp <= 0x1F3FF) then
				continue
			end
			local ri = cp >= 0x1F1E6 and cp <= 0x1F1FF
			if ri and prevRi then
				prevRi = false
				continue
			end
			prevRi = ri
			if isEmojiCp(cp) and not fm.adv[utf8.char(cp)] then
				w += metrics.emoji
			else
				w += fm.adv[utf8.char(cp)] or fm.avg
			end
		end
	end)
	if not ok then
		w = #s * fm.avg
	end
	return w
end
T.emWidth = emWidth

local function stripRich(s: string): string
	s = string.gsub(s, "<br%s*/?>", "\n")
	s = string.gsub(s, "<[^>]->", "")
	s = string.gsub(s, "&lt;", "<")
	s = string.gsub(s, "&gt;", ">")
	s = string.gsub(s, "&amp;", "&")
	s = string.gsub(s, "&quot;", '"')
	s = string.gsub(s, "&apos;", "'")
	return s
end
T.stripRich = stripRich

-- returns lines (array of widths in px) for given size & wrap width (nil = no wrap)
function T.layout(text: string, key: string, size: number, wrapWidth: number?)
	local lines = {}
	for para in string.gmatch(text .. "\n", "(.-)\n") do
		if not wrapWidth then
			table.insert(lines, emWidth(key, para) * size)
		else
			local cur = ""
			local curW = 0
			for word in string.gmatch(para, "%S+") do
				local cand = if cur == "" then word else cur .. " " .. word
				local cw = emWidth(key, cand) * size
				if cw <= wrapWidth + 0.5 or cur == "" then
					cur, curW = cand, cw
				else
					table.insert(lines, curW)
					cur, curW = word, emWidth(key, word) * size
				end
			end
			table.insert(lines, curW)
		end
	end
	return lines
end

function T.bounds(text: string, key: string, size: number, wrapWidth: number?, lineHeight: number?)
	local lines = T.layout(text, key, size, wrapWidth)
	local w = 0
	for _, lw in lines do
		w = math.max(w, lw)
	end
	return w, #lines * size * (lineHeight or 1)
end

-- TextScaled: largest integer size <= 100 whose layout fits the box
function T.scaledSize(text: string, key: string, bw: number, bh: number, wrapped: boolean, maxSize: number?, minSize: number?)
	local hi = math.min(maxSize or 100, 100)
	local lo = math.max(minSize or 1, 1)
	local best = lo
	for s = math.floor(hi), math.ceil(lo), -1 do
		local w, h = T.bounds(text, key, s, if wrapped then bw else nil)
		if w <= bw + 0.5 and h <= bh + 0.5 then
			best = s
			break
		end
	end
	return best
end

return T
