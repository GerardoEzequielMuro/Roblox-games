--!strict
-- The "auto" toggles: Auto Tap, Auto Equip Best and Auto Rebirth. (Auto Hatch lives in Eggs,
-- because it is bound to the egg the player stands next to.)
--
-- Everything runs on the server and at the server's pace: the client only flips a saved
-- switch with SetAuto (rate limited like every Request) and the loops in Tapping / Eggs do
-- the work, so it keeps going while the player is AFK and no remote is ever spammed.
--
--  * Auto Tap    free, 1 tap/s while the player isn't tapping (the same rate as offline
--                earnings), +1/s per "Auto Tap" gem upgrade level, +5/s always with the pass.
--  * Auto Equip  re-runs Equip Best whenever the inventory changes.
--  * Auto Rebirth rebirths as soon as it is affordable. Unlocks after the first manual one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local Pets = require(script.Parent.Pets)
local Progression = require(script.Parent.Progression)

local Auto = {}

local KEYS = { tap = "autoTap", equip = "autoEquip", rebirth = "autoRebirth" }

function Auto.rebirthUnlocked(p: Data.Profile): boolean
	return p.rebirths >= Config.AutoRebirthMinRebirths
end

-- Returns ok, message.
function Auto.set(player: Player, key: string, on: boolean): (boolean, Locale.Message?)
	local p = Data.get(player)
	local field = KEYS[key]
	if not p or not field then
		return false, M("msg.bad_request")
	end
	if key == "rebirth" and on and not Auto.rebirthUnlocked(p) then
		return false, M("msg.autorebirth_locked")
	end
	local settings = p.settings :: { [string]: boolean }
	settings[field] = on
	if key == "equip" and on then
		Pets.equipBest(player)
	end
	State.dirty(player)
	return true
end

function Auto.init()
	Remotes.handle("SetAuto", function(player, payload)
		if type(payload.key) ~= "string" then
			return false, M("msg.bad_request")
		end
		return Auto.set(player, payload.key, payload.on == true)
	end)

	-- Auto Equip: a hatch or a craft may have produced something stronger
	local function reequip(player: Player)
		local p = Data.get(player)
		if p and p.settings.autoEquip then
			Pets.equipBest(player)
		end
	end
	Hooks.on("hatched", reequip)
	Hooks.on("crafted", reequip)

	-- Auto Rebirth: checked once a second by the Tapping loop
	Hooks.on("second", function(player: Player, p: Data.Profile)
		if p.settings.autoRebirth and Auto.rebirthUnlocked(p) and p.taps >= Formulas.rebirthCost(p.rebirths) then
			Progression.rebirth(player)
		end
	end)

	State.extras.auto = function(player, p)
		local idle = Formulas.autoTapRate(p.upgrades.AutoTap or 0, State.owns(player, "AutoTap"), true)
		return {
			tap = p.settings.autoTap,
			equip = p.settings.autoEquip,
			rebirth = p.settings.autoRebirth,
			rebirthUnlocked = Auto.rebirthUnlocked(p),
			tapRate = idle, -- taps per second while idle
			hatchFast = State.owns(player, "AutoHatch"),
		}
	end
end

return Auto
