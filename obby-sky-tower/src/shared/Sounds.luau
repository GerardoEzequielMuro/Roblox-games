--!strict
-- Sound hooks. The game ships WITHOUT uploaded audio: every id is empty and every hook is a
-- silent no-op until a real asset id (from the Creator Dashboard) is pasted here. Do not invent ids.
-- PURE Luau; client/Sfx.luau plays them.
local Sounds = {}

Sounds.ids = {
	click = "", -- button press
	coin = "", -- coin pickup
	checkpoint = "", -- pad reached
	worldUp = "", -- new world / level-up fanfare
	rare = "", -- rare gift reveal
	win = "", -- summit
	death = "", -- fell
	hint = "", -- guide hint appears
} :: { [string]: string }

Sounds.volume = {} :: { [string]: number } -- optional per-sound volume, default 0.6

-- "rbxassetid://123" or nil while the id is empty / not a number
function Sounds.assetFor(name: string): string?
	local id = Sounds.ids[name]
	if id == nil or id == "" then
		return nil
	end
	local n = tonumber((id:gsub("^rbxassetid://", "")))
	if not n or n <= 0 then
		return nil
	end
	return "rbxassetid://" .. tostring(math.floor(n))
end

return Sounds
