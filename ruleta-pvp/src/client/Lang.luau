--!strict
-- Client language: the saved preference (profile.lang) or the account locale. Static labels
-- register with Lang.bind and re-render live when the language changes; dynamic texts are
-- rebuilt by the refresh functions of their windows (Net.Changed fires on a switch).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(script.Parent.Net)

local Lang = {}

-- Studio preview: the workspace attribute ForceLanguage (e.g. "de") overrides everything.
local forced = workspace:GetAttribute("ForceLanguage")
local forcedCode: string? = if type(forced) == "string" and Locale.Supported[forced] then forced else nil

Lang.code = forcedCode or Locale.resolve(Players.LocalPlayer.LocaleId)
local changed = Instance.new("BindableEvent")
Lang.Changed = changed.Event

type Binding = { prop: string, key: string, args: { [string]: any }?, prefix: string? }
-- Strong keys on purpose: Instance proxies in weak tables can be collected while the
-- Instance is still alive. Entries are dropped when the object is destroyed.
local bound: { [Instance]: Binding } = {}

function Lang.t(key: string, args: { [string]: any }?): string
	return Locale.t(Lang.code, key, args)
end

-- Server messages ({ key, args }) or plain strings.
function Lang.msg(m: any): string
	return Locale.msg(Lang.code, m)
end

local function render(obj: Instance, b: Binding)
	(obj :: any)[b.prop] = (b.prefix or "") .. Lang.t(b.key, b.args)
end

-- Sets obj[prop] (default "Text") to the translation and keeps it updated.
function Lang.bind(obj: Instance, key: string, args: { [string]: any }?, prop: string?, prefix: string?)
	local b: Binding = { prop = prop or "Text", key = key, args = args, prefix = prefix }
	if not bound[obj] then
		obj.Destroying:Once(function()
			bound[obj] = nil
		end)
	end
	bound[obj] = b
	render(obj, b)
end

function Lang.unbind(obj: Instance)
	bound[obj] = nil
end

-- Upper-cases only plain ASCII (string.upper would mangle UTF-8 letters).
function Lang.upper(s: string): string
	return if s:find("[\128-\255]") then s else s:upper()
end

function Lang.set(code: string)
	if not Locale.Supported[code] then
		code = Locale.Default
	end
	if code == Lang.code then
		return
	end
	Lang.code = code
	for obj, b in bound do
		if obj.Parent then
			render(obj, b)
		end
	end
	changed:Fire(code)
	Net.refresh()
end

-- Follow the saved preference when the server state arrives or changes.
Net.Changed:Connect(function()
	local pref = Net.get("lang")
	local want = forcedCode or (if type(pref) == "string" and Locale.Supported[pref] then pref else Locale.resolve(Players.LocalPlayer.LocaleId))
	if want ~= Lang.code then
		Lang.set(want)
	end
end)

return Lang
