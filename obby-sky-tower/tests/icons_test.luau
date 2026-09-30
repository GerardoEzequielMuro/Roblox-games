--!strict
-- Pure-Luau tests for Shared/Icons (the shared icon pack). Run from the project root:
--   luau tests/icons_test.luau
-- Checks: every emoji glyph the UI maps points at an icon of the pack; with no ids uploaded every
-- lookup is nil (the UI keeps its emoji); an uploaded id becomes "rbxassetid://<id>".
local Icons = require("../src/shared/Icons")
local Powerups = require("../src/shared/Powerups")

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

for glyph, name in Icons.GLYPHS do
	check(Icons.ids[name] ~= nil, ("glyph %s -> '%s' is an icon of the pack"):format(glyph, name))
end
-- the HUD's glyphs
for _, glyph in { "🏆", "🎁", "🛍", "💎", "⚙", "👋", "⭐" } do
	check(Icons.forGlyph(glyph) ~= nil, "HUD glyph " .. glyph .. " has an icon")
end
-- power-up chips: the ones the pack draws
for _, item in Powerups.List do
	if item.id == "speed" or item.id == "shield" or item.id == "magnet" or item.id == "pocket" or item.id == "doublejump" then
		check(Icons.forGlyph(item.icon) ~= nil, "power-up " .. item.id .. " has an icon")
	end
end
-- glyphs without a drawn icon stay emoji
check(Icons.forGlyph("⏭") == nil and Icons.forGlyph("🔗") == nil, "unmapped glyphs -> nil")
check(Icons.forGlyph("⚙\u{FE0F}") == "settings", "variation selector ignored")

-- nothing uploaded in the repo yet: every lookup is nil, so the UI shows its emoji
local anyId = false
for _, id in Icons.ids do
	if id ~= "" then
		anyId = true
	end
end
if not anyId then
	for glyph in Icons.GLYPHS do
		check(Icons.forGlyphImage(glyph) == nil, "no id -> emoji fallback for " .. glyph)
	end
	check(Icons.get("coin") == nil, "no coin id -> drawn coin")
end

-- an uploaded id is used (restored afterwards)
local saved = Icons.ids.trophy
Icons.ids.trophy = "123"
check(Icons.get("trophy") == "rbxassetid://123", "id -> rbxassetid")
check(Icons.forGlyphImage("🏆") == "rbxassetid://123", "glyph -> uploaded image")
Icons.ids.trophy = saved
check(Icons.get("nope") == nil, "unknown name -> nil")

print(("icons_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("icons_test failed")
end
print("icons test PASSED")
