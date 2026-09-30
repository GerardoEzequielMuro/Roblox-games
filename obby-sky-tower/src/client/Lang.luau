--!strict
-- Client language: saved preference (profile.lang, set with Request "SetLanguage") or the
-- Roblox account locale. Everything user-visible goes through Lang.t / Lang.msg.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local Lang = {}

Lang.auto = Locale.resolve(Players.LocalPlayer.LocaleId)
Lang.code = Lang.auto
local changed = Instance.new("BindableEvent")
Lang.changed = changed.Event -- fires (newCode)

function Lang.t(key: string, args: { [string]: any }?): string
	return Locale.t(Lang.code, key, args)
end

-- Server message (string, spec or list of specs) -> text in the current language.
function Lang.msg(m: any): string?
	return Locale.message(Lang.code, m)
end

-- `pref` = saved preference ("" = follow the account locale).
function Lang.apply(pref: string?)
	local code = if pref and Locale.isSupported(pref) then pref else Lang.auto
	if code ~= Lang.code then
		Lang.code = code
		changed:Fire(code)
	end
end

return Lang
