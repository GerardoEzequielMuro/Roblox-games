--!strict
-- Emoji glyph -> shared icon pack name (src/shared/Icons.luau). Pure Luau: also loaded by
-- tests/glyphs_check.luau. The UI keeps using emoji everywhere; Theme.icon asks here whether
-- that glyph has an uploaded image and only then swaps the TextLabel for an ImageLabel.
-- Unmapped glyphs (and every glyph while the pack is not uploaded) stay emoji.
-- "orb" and "cloud" are left out on purpose: an orange ball with a star and a yellow flying
-- cloud read as a famous anime's props (see DESIGN.md, IP rule).
local Glyphs = {}

local VS16 = utf8.char(0xFE0F) -- emoji presentation selector ("🛡️" vs "🛡")

Glyphs.map = {
	["⚡"] = "coin", -- Sparks (the soft currency) and everything that pays in Sparks
	["💎"] = "gem",
	["👊"] = "fist",
	["💪"] = "fist",
	["🛡"] = "shield",
	["🔥"] = "flame",
	["🌟"] = "rebirth", -- ascension
	["⭐"] = "star",
	["🌠"] = "star", -- wishes
	["🏆"] = "trophy",
	["👑"] = "crown",
	["🔒"] = "lock",
	["✔"] = "check",
	["✅"] = "check",
	["❌"] = "close",
	["✖"] = "close",
	["⏳"] = "clock",
	["⏰"] = "clock",
	["📅"] = "calendar",
	["🎁"] = "gift",
	["🛒"] = "shop",
	["⚙"] = "settings",
	["📜"] = "quest",
	["📖"] = "book",
	["💌"] = "invite",
	["👥"] = "group",
	["🪐"] = "planet",
	["🧭"] = "map",
	["🗺"] = "map",
	["🚀"] = "rocket",
	["🍀"] = "luck",
	["🤖"] = "auto",
	["🌀"] = "aura",
	["✨"] = "aura", -- the Ki stat
	["🎯"] = "target",
	["👹"] = "skull",
	["💀"] = "skull",
	["⚔"] = "sword",
	["🔋"] = "bolt", -- charge ki
	["🔊"] = "sound",
	["🧲"] = "magnet",
	["❤"] = "heart",
	["🎡"] = "wheel",
	["🎟"] = "ticket",
	["⬆"] = "upgrade",
} :: { [string]: string }

-- Glyph without the emoji presentation selector (so "🛡️" and "🛡" match).
function Glyphs.normalize(glyph: string): string
	return (glyph:gsub(VS16, ""))
end

-- Icon pack name for a glyph, or nil when the glyph has no icon.
function Glyphs.name(glyph: string?): string?
	if type(glyph) ~= "string" or glyph == "" then
		return nil
	end
	return Glyphs.map[Glyphs.normalize(glyph)]
end

-- Image for a glyph via `get` (Icons.get), or nil: nil means "keep the emoji".
function Glyphs.image(glyph: string?, get: (string) -> string?): string?
	local name = Glyphs.name(glyph)
	if not name then
		return nil
	end
	return get(name)
end

-- "💎 120" -> ("💎", "120") when the text starts with a mapped glyph followed by a space;
-- nil otherwise. Used by buttons whose label is "<glyph> <price>".
function Glyphs.split(text: string?): (string?, string?)
	if type(text) ~= "string" then
		return nil, nil
	end
	local first, rest = text:match("^(%S+) (.+)$")
	if first and rest and Glyphs.name(first) then
		return first, rest
	end
	return nil, nil
end

return Glyphs
