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

-- "rbxassetid://<id>" when the icon is uploaded, nil otherwise.
function Icons.get(name: string): string?
	local id = Icons.ids[name]
	if id and id ~= "" then
		return "rbxassetid://" .. id
	end
	return nil
end

return Icons
