--!strict
-- Pure layout math for the HUD (no Roblox types, tested by tests/ui_test.luau).
local UiMath = {}

-- Short side of the standard HUD button, in design pixels.
UiMath.BUTTON = 54
-- Smallest real tap target we accept: 44 px on touch, 40 px with a mouse.
UiMath.MIN_TOUCH = 44
UiMath.MIN_MOUSE = 40

-- Design canvas (w, h, compact) the HUD is laid out on for a given safe-area size.
function UiMath.designFor(touchOnly: boolean, width: number, height: number): (number, number, boolean)
	local rw, rh = if touchOnly then 1000 else 1100, if touchOnly then 480 else 540
	-- compact when the regular canvas would shrink a 54 px button under the tap minimum (44 px touch, 40 px mouse).
	-- 740 x 365 keeps that button at 41 real px on a 566 x 281 safe area (the smallest we test).
	if math.min(width / rw, height / rh) * UiMath.BUTTON < (if touchOnly then UiMath.MIN_TOUCH else UiMath.MIN_MOUSE) then
		return 740, 365, true
	end
	return rw, rh, false
end

-- How to show a (w x h design px) panel on a (cw x ch) canvas drawn at rootScale.
-- Returns (scale, height): the panel's UIScale and the height to give its frame.
-- Old rule: shrink until the whole panel fits. On a phone that made a 54 px button 26 real px.
-- Now the panel never shrinks below the scale that keeps its buttons at the tap minimum; when it is
-- then too tall, it gets shorter (height < h) and its content scrolls instead.
function UiMath.panelFit(w: number, h: number, cw: number, ch: number, rootScale: number, touch: boolean, margin: number?): (number, number)
	local m = margin or 16
	local availW, availH = math.max(1, cw - m), math.max(1, ch - m)
	local minPx = if touch then UiMath.MIN_TOUCH else UiMath.MIN_MOUSE
	local sMin = math.min(1, minPx / (UiMath.BUTTON * math.max(rootScale, 1e-3)))
	local fitW, fitH = availW / w, availH / h
	-- width never scrolls: it always fits
	local s = math.min(1, fitW, math.max(fitH, sMin))
	local height = h
	if h * s > availH + 0.5 then
		height = math.floor(availH / s)
	end
	return s, height
end

-- Which of these markers to show: the `max` nearest ones inside `range` (studs). Returns a flag per index.
function UiMath.nearest(dists: { number }, max: number, range: number): { boolean }
	local order: { number } = {}
	for i, d in dists do
		if d <= range then
			table.insert(order, i)
		end
	end
	table.sort(order, function(a, b)
		if dists[a] == dists[b] then
			return a < b
		end
		return dists[a] < dists[b]
	end)
	local show: { boolean } = table.create(#dists, false)
	for rank, i in order do
		if rank > max then
			break
		end
		show[i] = true
	end
	return show
end

return UiMath
