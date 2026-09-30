-- Glyph -> icon mapping checks (run from the game folder: luau tests/glyphs_check.luau)
-- * every mapped icon name exists in the shared pack (Icons.ids)
-- * IP rule: no "orb" / "cloud" icons in this game
-- * emoji presentation selector is ignored; split() only splits mapped glyphs
-- * with the pack not uploaded (empty ids) every glyph keeps its emoji (image == nil)
local Glyphs = require("../src/shared/Glyphs")
local Icons = require("../src/shared/Icons")
local Config = require("../src/shared/Config")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local n = 0
for glyph, name in Glyphs.map do
	n += 1
	check("icon exists for " .. glyph, Icons.ids[name] ~= nil, name)
	check("no IP-risky icon for " .. glyph, name ~= "orb" and name ~= "cloud", name)
	check("map keys are normalized " .. glyph, Glyphs.normalize(glyph) == glyph)
end
check("map is not empty", n > 20, n)

check("VS16 ignored", Glyphs.name("🛡️") == "shield" and Glyphs.name("🛡") == "shield")
check("gear glyph", Glyphs.name("⚙️") == "settings")
check("unmapped glyph", Glyphs.name("🦘") == nil)
check("nil / empty", Glyphs.name(nil) == nil and Glyphs.name("") == nil)

local g, rest = Glyphs.split("💎 120")
check("split mapped", g == "💎" and rest == "120", tostring(g) .. "|" .. tostring(rest))
g, rest = Glyphs.split("🦘 12")
check("split unmapped", g == nil and rest == nil)
g, rest = Glyphs.split("Claim")
check("split plain text", g == nil and rest == nil)
g, rest = Glyphs.split("⚡ 1.2K")
check("split sparks price", g == "⚡" and rest == "1.2K")

-- today: nothing uploaded, so every lookup falls back to the emoji
local uploaded = 0
for _, id in Icons.ids do
	if id ~= "" then
		uploaded += 1
	end
end
if uploaded == 0 then
	check("no image while the pack is not uploaded", Glyphs.image("💎", Icons.get) == nil)
end
local fake = function(name: string): string?
	return "rbxassetid://1#" .. name
end
check("image through getter", Glyphs.image("💎", fake) == "rbxassetid://1#gem")
check("unmapped image is nil", Glyphs.image("🦘", fake) == nil)

-- Config icons: report coverage (unmapped ones simply stay emoji)
local covered, total = 0, 0
local function see(icon: string?)
	if icon then
		total += 1
		if Glyphs.name(icon) then
			covered += 1
		end
	end
end
for _, info in Config.StatInfo do
	see(info.icon)
end
for _, list in { Config.Techniques, Config.Upgrades, Config.Passes, Config.Products } do
	for _, e in list :: any do
		see(e.icon)
	end
end
check("most Config icons have an image", covered * 2 >= total, covered .. "/" .. total)

if fails == 0 then
	print(string.format("GLYPH CHECKS PASSED (%d glyphs mapped, Config icons covered %d/%d)", n, covered, total))
else
	error(fails .. " glyph check(s) failed")
end
