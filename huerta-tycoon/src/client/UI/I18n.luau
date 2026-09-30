--!nonstrict
-- Client-side language state on top of Shared.Locale.
--   I18n.t(key, args)        -> string in the current language
--   I18n.L(key, args)        -> a "loc" value; C.label/C.button/C.setText/I18n.set accept it and re-render it live
--   I18n.set(inst, prop, v)  -> sets inst[prop] from a loc value (bound) or a plain string (unbound)
--   I18n.setLang(code)       -> switches language and re-renders every bound text + fires State refreshes
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local I18n = {}

I18n.Locale = Locale
I18n.lang = Locale.resolve(Players.LocalPlayer and Players.LocalPlayer.LocaleId or nil)
I18n.autoLang = I18n.lang

export type Loc = { key: string, args: { [string]: any }?, prefix: string?, suffix: string?, __loc: boolean }

function I18n.t(key: string, args: { [string]: any }?): string
	return Locale.t(I18n.lang, key, args)
end

function I18n.L(key: string, args: { [string]: any }?, prefix: string?, suffix: string?): Loc
	return { key = key, args = args, prefix = prefix, suffix = suffix, __loc = true }
end

function I18n.isLoc(v: any): boolean
	return type(v) == "table" and v.__loc == true
end

-- Resolve a loc value or pass a string through.
function I18n.str(v: any): string
	if I18n.isLoc(v) then
		return (v.prefix or "") .. Locale.t(I18n.lang, v.key, v.args) .. (v.suffix or "")
	end
	return if v == nil then "" else tostring(v)
end

-- inst -> { [prop] = loc }. Strong keys (Roblox can collect the Lua wrapper of a live Instance held only by a weak
-- table, which silently dropped bindings); entries are removed when the instance is destroyed.
local bound: { [Instance]: { [string]: Loc } } = {}

function I18n.set(inst: Instance, prop: string, v: any)
	local map = bound[inst]
	if I18n.isLoc(v) then
		if not map then
			map = {}
			bound[inst] = map
			inst.Destroying:Once(function()
				bound[inst] = nil
			end)
		end
		map[prop] = v
	elseif map then
		map[prop] = nil
	end
	(inst :: any)[prop] = I18n.str(v)
end

local listeners: { () -> () } = {}

-- fn runs on every language change (after bound texts are refreshed).
function I18n.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function I18n.setLang(code: string)
	if not Locale.Supported[code] or code == I18n.lang then
		return
	end
	I18n.lang = code
	for inst, map in bound do
		for prop, v in map do
			pcall(function()
				(inst :: any)[prop] = I18n.str(v)
			end)
		end
	end
	for _, fn in listeners do
		task.spawn(fn)
	end
end

return I18n
