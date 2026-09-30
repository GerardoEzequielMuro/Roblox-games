--!nonstrict
-- Shared layout state: design-canvas size (the safe area in design pixels), UI scale and touch mode.
-- Main.client computes it; HUD modules subscribe and reposition themselves.
--
-- Touch layout rules (UserInputService.TouchEnabled and not KeyboardEnabled):
--   * the Roblox thumbstick owns the bottom-left ~35% x 40% of the screen,
--   * the jump button owns the bottom-right ~25% x 35%,
--   so bottom HUD (hotbar, basket) is kept inside x = 35%..75% and everything else moves to the top half.
local UiMath = require(script.Parent.UiMath)

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
Layout.designFor = UiMath.designFor

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

-- (scale, height) for a panel of design size w x h: never shrinks its buttons under the tap minimum;
-- a panel that is then too tall gets the returned (shorter) height and scrolls (see Panels).
function Layout.panelFit(w: number, h: number, margin: number?): (number, number)
	return UiMath.panelFit(w, h, Layout.canvas.X, Layout.canvas.Y, Layout.scale, Layout.isTouch, margin)
end

return Layout
