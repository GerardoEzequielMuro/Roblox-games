--!strict
-- Which HUD buttons a player sees. Top simulators open with 2-4 buttons and add the rest as
-- the player reaches them, so the first minute reads "tap, hatch" and nothing else.
-- Pure (state in, set out): the client HUD uses it and tests/hud_unlock.luau checks it.
-- Only counters that never go down are used (hatches, zones, rebirths), so a rebirth that
-- resets Taps never hides a button again. The HUD also latches what it has shown.
-- No Roblox APIs in here.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local HudUnlock = {}

export type Snapshot = {
	totalHatched: number?,
	zones: { number }?,
	rebirths: number?,
	taps: number?,
	rebirthCost: number?,
}

-- Always there: the dock (Rewards, TAP, Pets) and the Store.
HudUnlock.ALWAYS = { "Rewards", "Pets", "Store" }

-- name -> true when it should be visible for this snapshot.
function HudUnlock.visible(s: Snapshot): { [string]: boolean }
	local hatched = s.totalHatched or 0
	local zones = if s.zones then #s.zones else 1
	local rebirths = s.rebirths or 0
	local veteran = rebirths > 0 or zones >= 2
	local out: { [string]: boolean } = {}
	for _, name in HudUnlock.ALWAYS do
		out[name] = true
	end
	-- first egg: gems start to matter, quests and auto tap show up
	out.Upgrades = hatched >= 1 or veteran
	out.Quests = hatched >= 1 or veteran
	out.AutoTap = hatched >= 1 or veteran
	-- a few eggs in: the index, the settings/codes window and the other auto switches
	out.Index = hatched >= 3 or veteran
	out.Codes = hatched >= 3 or veteran
	out.AutoHatch = hatched >= 3 or veteran
	out.AutoEquip = hatched >= 3 or veteran
	-- the objective moves on to the next zone after 5 eggs
	out.Teleport = hatched >= 5 or veteran
	out.Invite = hatched >= 10 or veteran
	-- rebirth: once it is near (zone 3+, or affordable) and forever after the first one
	local rebirthCost = s.rebirthCost or Config.RebirthBaseCost
	out.Rebirth = rebirths > 0 or zones >= 3 or (s.taps or 0) >= rebirthCost
	-- the server refuses Auto Rebirth before the first manual rebirth
	out.AutoRebirth = rebirths > 0
	return out
end

-- Every name visible() can return (the HUD asserts it builds a button for each).
HudUnlock.NAMES = { "Rewards", "Pets", "Store", "Upgrades", "Quests", "Index", "Codes", "Teleport", "Invite", "Rebirth", "AutoTap", "AutoHatch", "AutoEquip", "AutoRebirth" }

return HudUnlock
