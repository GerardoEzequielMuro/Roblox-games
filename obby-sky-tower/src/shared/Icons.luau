--!strict
-- HUD icon images (shared pack in assets/icons, drawn by tools/icons/make_icons.py at the repo root).
-- The ids between the GENERATED markers are written by tools/icons/upload_assets.py; do not edit by hand.
-- An empty id means "not uploaded yet": callers must fall back to their emoji glyph, so the game
-- keeps working before the upload.
local Icons = {}

Icons.ids = {
	-- BEGIN GENERATED
	aura = "",
	auto = "",
	bolt = "",
	book = "",
	calendar = "",
	cash = "",
	check = "",
	clock = "",
	close = "",
	cloud = "",
	coin = "",
	crown = "",
	egg = "",
	fist = "",
	flame = "",
	gem = "",
	gift = "",
	group = "",
	heart = "",
	invite = "",
	lock = "",
	luck = "",
	magnet = "",
	map = "",
	orb = "",
	paw = "",
	pickaxe = "",
	planet = "",
	quest = "",
	rebirth = "",
	rocket = "",
	settings = "",
	shield = "",
	shop = "",
	skull = "",
	sound = "",
	sprout = "",
	star = "",
	sword = "",
	tap = "",
	target = "",
	teleport = "",
	ticket = "",
	trophy = "",
	upgrade = "",
	wheel = "",
	-- END GENERATED
} :: { [string]: string }

-- The emoji glyphs this game uses in its UI, and the drawn icon that replaces each one once it is
-- uploaded (UI/Kit.icon). A glyph without an entry (or whose icon has no id yet) stays an emoji.
Icons.GLYPHS = {
	["🏆"] = "trophy",
	["🎁"] = "gift",
	["🛍"] = "shop",
	["🛒"] = "shop",
	["💎"] = "gem",
	["⚙"] = "settings",
	["👋"] = "invite",
	["⭐"] = "star",
	["🌟"] = "star",
	["🚀"] = "rocket",
	["👑"] = "crown",
	["⚡"] = "bolt",
	["🪐"] = "planet",
	["📍"] = "map",
	["💰"] = "cash",
	["🛡"] = "shield",
	["🧲"] = "magnet",
	["⏫"] = "upgrade",
	["🌀"] = "teleport",
	["☁"] = "cloud",
	["🔥"] = "flame",
	["🍀"] = "luck",
	["🎟"] = "ticket",
	["🔒"] = "lock",
	["✅"] = "check",
	["❌"] = "close",
	["⏱"] = "clock",
	["🕐"] = "clock",
	["📅"] = "calendar",
	["👥"] = "group",
	["💀"] = "skull",
	["🔄"] = "rebirth",
} :: { [string]: string }

-- Icon name for an emoji glyph (a trailing variation selector U+FE0F is ignored), nil if none.
function Icons.forGlyph(glyph: string): string?
	local name = Icons.GLYPHS[glyph]
	if name then
		return name
	end
	local stripped = string.gsub(glyph, "\u{FE0F}", "")
	return Icons.GLYPHS[stripped]
end

-- Image for an emoji glyph: "rbxassetid://..." once its icon is uploaded, nil otherwise.
function Icons.forGlyphImage(glyph: string): string?
	local name = Icons.forGlyph(glyph)
	return if name then Icons.get(name) else nil
end

-- "rbxassetid://<id>" when the icon is uploaded, nil otherwise.
function Icons.get(name: string): string?
	local id = Icons.ids[name]
	if id and id ~= "" then
		return "rbxassetid://" .. id
	end
	return nil
end

return Icons
