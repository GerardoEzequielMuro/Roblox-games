--!strict
-- Lite profile: which devices get the cheaper look. PURE Luau (tests/visual_test.luau).
--
-- The game has to look good with the graphics slider at minimum: what makes a world
-- recognisable (sky colour, platform colours, shapes) never depends on post-processing. The lite
-- profile only removes what a slow device pays for and barely sees: bloom and sun rays, scenery
-- particles and point lights, half of the ambient particles, a shorter radius for cosmetic loops.
-- PC at normal quality never gets it.
local Quality = {}

Quality.LITE_MAX_LEVEL = 3 -- graphics slider 1..3 of 10 (0 = automatic)
Quality.NEAR = 170 -- studs from the camera within which cosmetic loops run
Quality.NEAR_LITE = 110
Quality.WEATHER_RATE_LITE = 0.5

-- "QualityLevel7" -> 7; "Automatic" (or anything else) -> 0
function Quality.level(savedName: string): number
	return tonumber(savedName:match("(%d+)$")) or 0
end

-- touchOnly: a phone / tablet without keyboard. level: graphics slider (0 = automatic).
-- forced: the ForceLite attribute (tests, minimum-graphics screenshots).
function Quality.isLite(touchOnly: boolean, level: number, forced: boolean): boolean
	return forced or touchOnly or (level > 0 and level <= Quality.LITE_MAX_LEVEL)
end

return Quality
