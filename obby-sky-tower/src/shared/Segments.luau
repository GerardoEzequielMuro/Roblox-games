--!strict
-- Keypoint maths for the world-coloured progress bar. PURE Luau (tests/visual_test.luau).
-- Roblox ColorSequence / NumberSequence rules: first keypoint at 0, last at 1, times strictly
-- increasing, at most 20 keypoints.
local Segments = {}

Segments.EPS = 0.001
Segments.MAX_KEYPOINTS = 20

export type ColorStop = { t: number, index: number }
export type ValueStop = { t: number, value: number }

-- n equal hard-edged segments: two keypoints per segment (start and end share segment `index`).
function Segments.colorStops(n: number): { ColorStop }
	n = math.clamp(math.floor(n), 1, Segments.MAX_KEYPOINTS // 2)
	local out: { ColorStop } = {}
	for i = 1, n do
		local a = (i - 1) / n
		local b = i / n
		table.insert(out, { t = a, index = i })
		table.insert(out, { t = if i == n then 1 else b - Segments.EPS, index = i })
	end
	return out
end

-- Transparency that shows the first fraction `p` of a bar and hides the rest, with a hard edge.
function Segments.revealStops(p: number): { ValueStop }
	if p ~= p or p <= Segments.EPS then
		return { { t = 0, value = 1 }, { t = 1, value = 1 } }
	elseif p >= 1 - Segments.EPS then
		return { { t = 0, value = 0 }, { t = 1, value = 0 } }
	end
	p = math.clamp(p, 2 * Segments.EPS, 1 - 2 * Segments.EPS)
	return {
		{ t = 0, value = 0 },
		{ t = p - Segments.EPS, value = 0 },
		{ t = p, value = 1 },
		{ t = 1, value = 1 },
	}
end

return Segments
