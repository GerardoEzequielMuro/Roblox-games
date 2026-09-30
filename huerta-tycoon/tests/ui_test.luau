--!strict
-- Pure-Luau unit tests for the HUD layout math. Run from the project root: luau tests/ui_test.luau
local UiMath = require("../src/client/UI/UiMath")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- Mirrors Main.client.updateScale: (canvas w, canvas h, root scale, compact) for a safe area.
local function screen(touch: boolean, w: number, h: number): (number, number, number, boolean)
	local dw, dh, compact = UiMath.designFor(touch, w, h)
	local s = math.clamp(math.min(w / dw, h / dh), 0.25, if touch or compact then 1.1 else 1)
	return w / s, h / s, s, compact
end

-- ===== design canvas =====
do
	local _, _, _, cTiny = screen(false, 566, 281)
	local _, _, _, cPhone = screen(true, 860, 390)
	local _, _, sPc, cPc = screen(false, 1920, 1020)
	local _, _, _, cMid = screen(false, 916, 447)
	check(cTiny and cPhone and not cPc and not cMid, "tiny screens and phones use the compact canvas, PC the regular one")
	check(sPc == 1, "1920x1080 is drawn at scale 1 (the HUD does not blow up on big screens)")
	local _, _, sPhone = screen(true, 860, 390)
	check(UiMath.BUTTON * sPhone >= 44, "54 px buttons stay >= 44 real px on a phone")
	-- a small phone in landscape (iPhone SE-class safe area)
	local _, _, sSe = screen(true, 620, 330)
	check(UiMath.BUTTON * sSe >= 44, string.format("54 px buttons >= 44 real px on a 620x330 phone (%.1f)", UiMath.BUTTON * sSe))
end

-- ===== panels never shrink their buttons under the tap minimum =====
local PANELS = {
	{ 700, 520 }, { 720, 520 }, { 680, 520 }, { 640, 500 }, { 600, 430 }, { 500, 330 },
	{ 720, 420 }, { 700, 470 }, { 560, 440 }, { 560, 500 }, { 540, 470 }, { 540, 450 },
}
local SCREENS = {
	{ false, 1920, 1020 }, { false, 1366, 710 }, { false, 916, 447 }, { false, 566, 281 },
	{ true, 860, 390 }, { true, 620, 330 }, { true, 1180, 790 }, { true, 2340, 1000 },
}
do
	local bad = 0
	for _, sc in SCREENS do
		local touch, w, h = sc[1] :: boolean, sc[2] :: number, sc[3] :: number
		local cw, ch, root = screen(touch, w, h)
		for _, p in PANELS do
			local pw, ph = p[1], p[2]
			local s, height = UiMath.panelFit(pw, ph, cw, ch, root, touch, 40)
			local minPx = if touch then UiMath.MIN_TOUCH else UiMath.MIN_MOUSE
			local realBtn = UiMath.BUTTON * root * s
			-- never smaller than the tap minimum, unless the root itself is already smaller (566x281, not a phone)
			-- or the panel is too wide for the screen
			local okBtn = realBtn >= math.min(minPx, UiMath.BUTTON * root) - 0.01 or pw * s >= cw - 40 - 0.5
			local okFit = pw * s <= cw - 40 + 0.5 and height * s <= ch - 40 + 0.5
			local okH = height <= ph and height >= 71 + 60
			if not (okBtn and okFit and okH) then
				bad += 1
				print(string.format("  %dx%d on %s %dx%d: scale %.2f height %d button %.1f px", pw, ph, if touch then "touch" else "pc", w, h, s, height, realBtn))
			end
		end
	end
	check(bad == 0, "every panel fits every screen with tap-sized buttons (" .. bad .. " bad)")
end
do
	-- big screens keep today's behaviour: full size, no scrolling
	local s, height = UiMath.panelFit(700, 520, 1920, 1020, 1, false, 40)
	check(s == 1 and height == 520, "1080p: shop panel at full size")
	-- a phone: the panel stays at scale ~1 and gets shorter instead of shrinking to half
	local cw, ch, root = screen(true, 620, 330)
	local s2, h2 = UiMath.panelFit(700, 520, cw, ch, root, true, 40)
	check(s2 > 0.9 and h2 < 520, string.format("phone: shop panel keeps scale %.2f and scrolls (height %d)", s2, h2))
end

-- ===== nearest markers =====
do
	local show = UiMath.nearest({ 10, 50, 5, 30, 90, 20 }, 3, 60)
	check(show[3] and show[1] and show[6] and not show[4] and not show[2] and not show[5], "nearest 3 of 6 inside the range")
	local far = UiMath.nearest({ 100, 120 }, 3, 60)
	check(not far[1] and not far[2], "nothing outside the range")
	local empty = UiMath.nearest({}, 3, 60)
	check(#empty == 0, "no markers, no flags")
	local tie = UiMath.nearest({ 5, 5, 5 }, 2, 60)
	check(tie[1] and tie[2] and not tie[3], "ties keep a stable order")
end

print(string.format("ui_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	error("ui_test failed")
end
