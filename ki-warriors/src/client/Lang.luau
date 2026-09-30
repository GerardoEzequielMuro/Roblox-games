--!strict
-- Client language: the saved preference (profile.lang) or the account locale. Static labels
-- register with Lang.bind and re-render live when the language changes; dynamic texts are
-- rebuilt by their windows' refresh functions (Net.Changed "full" fires on a switch).
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(script.Parent.Net)

local Lang = {}

-- Studio preview: the workspace attribute ForceLanguage (e.g. "de") overrides everything.
local forced = workspace:GetAttribute("ForceLanguage")
local forcedCode: string? = if type(forced) == "string" and Locale.Supported[forced] then forced else nil

-- Account language. Live: the player's Roblox language (Player.LocaleId), then the Roblox
-- and OS locales if that one is empty or unsupported. Studio: Player.LocaleId follows the
-- Studio UI language (English for most people), so the OS locale goes first there; that is
-- why a Spanish-speaking tester used to get an English HUD in Studio.
local function accountLocale(): string
	local okRoblox, roblox = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	local okSystem, system = pcall(function()
		return LocalizationService.SystemLocaleId
	end)
	local playerId = Players.LocalPlayer.LocaleId
	local robloxId = if okRoblox then roblox else nil
	local systemId = if okSystem then system else nil
	if RunService:IsStudio() then
		return Locale.resolveFirst(systemId, playerId, robloxId)
	end
	return Locale.resolveFirst(playerId, robloxId, systemId)
end

Lang.code = forcedCode or accountLocale()
local changed = Instance.new("BindableEvent")
Lang.Changed = changed.Event

type Binding = { prop: string, key: string, args: { [string]: any }? }
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

-- Sets obj[prop] (default "Text") to the translation and keeps it updated.
function Lang.bind(obj: Instance, key: string, args: { [string]: any }?, prop: string?)
	local b: Binding = { prop = prop or "Text", key = key, args = args }
	if not bound[obj] then
		obj.Destroying:Once(function()
			bound[obj] = nil
		end)
	end
	bound[obj] = b;
	(obj :: any)[b.prop] = Lang.t(key, args)
end

function Lang.unbind(obj: Instance)
	bound[obj] = nil
end

-- Upper-cases only plain ASCII (string.upper would mangle UTF-8 letters).
function Lang.upper(s: string): string
	return if s:find("[\128-\255]") then s else s:upper()
end

-- "5 min of Sparks", "25 Gems"... for Config reward entries.
function Lang.rewardLabel(reward: { kind: string, amount: number }): string
	return Lang.t("rewardlabel." .. reward.kind, { n = reward.amount })
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
			(obj :: any)[b.prop] = Lang.t(b.key, b.args)
		end
	end
	changed:Fire(code)
	Net.refresh()
end

-- Follow the saved preference when the server state arrives or changes.
Net.Changed:Connect(function(kind)
	if kind ~= "full" then
		return
	end
	local pref = Net.get("lang")
	local want = forcedCode or (if type(pref) == "string" and Locale.Supported[pref] then pref else accountLocale())
	if want ~= Lang.code then
		Lang.set(want)
	end
end)

return Lang
