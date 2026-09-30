--!nonstrict
-- Shared layout state: design-canvas size (the safe area in design pixels), UI scale and touch mode.
-- Main.client computes it; HUD modules subscribe and reposition themselves.
--
-- Touch layout rules (UserInputService.TouchEnabled and not KeyboardEnabled):
--   * the Roblox thumbstick owns the bottom-left ~35% x 40% of the screen,
--   * the jump button owns the bottom-right ~25% x 35%,
--   so bottom HUD (hotbar, basket) is kept inside x = 35%..75% and everything else moves to the top half.
local Layout = {}

Layout.isTouch = false
-- compact: the screen is too small for the regular canvas (phones, tiny windows). The HUD then uses a smaller
-- design canvas, so every button stays at least 40 real px, and the menu collapses behind a "More" button.
Layout.compact = false
-- stacked: touch or compact. Actions go to the top-right, timers under them, the bottom corners stay free.
Layout.stacked = false
Layout.canvas = Vector2.new(1100, 540)
Layout.scale = 1

local listeners: { () -> () } = {}

-- fn runs now and on every change.
function Layout.onChanged(fn: () -> ())
	table.insert(listeners, fn)
	task.spawn(fn)
end

-- Pure: design canvas (w, h) the HUD is laid out on for a given safe-area size.
function Layout.designFor(touchOnly: boolean, width: number, height: number): (number, number, boolean)
	local rw, rh = if touchOnly then 1000 else 1100, if touchOnly then 480 else 540
	-- compact when the regular canvas would shrink a 54 px button under the tap minimum (44 px touch, 40 px mouse).
	-- 740 x 365 keeps that button at 41 real px on a 566 x 281 safe area (the smallest we test).
	if math.min(width / rw, height / rh) * 54 < (if touchOnly then 44 else 40) then
		return 740, 365, true
	end
	return rw, rh, false
end

function Layout.set(isTouch: boolean, canvas: Vector2, scale: number, compact: boolean?)
	local c = compact == true
	if isTouch == Layout.isTouch and c == Layout.compact and (canvas - Layout.canvas).Magnitude < 0.5 and math.abs(scale - Layout.scale) < 1e-4 then
		return
	end
	Layout.isTouch = isTouch
	Layout.compact = c
	Layout.stacked = isTouch or c
	Layout.canvas = canvas
	Layout.scale = scale
	for _, fn in listeners do
		task.spawn(fn)
	end
end

-- Largest scale (<= 1) at which a design-size box fits in the canvas with a margin.
function Layout.fit(w: number, h: number, margin: number?): number
	local m = margin or 16
	return math.min(1, (Layout.canvas.X - m) / w, (Layout.canvas.Y - m) / h)
end

return Layout
