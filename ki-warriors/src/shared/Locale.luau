--!strict
-- Localization. Pure Luau (also loaded by tests/locale_check.luau with luau.exe).
-- Locales/<code>.luau return flat { [key] = "text with {name} placeholders" }.
-- Message values sent by the server are { key = string, args = { ... }? }; any arg that is
-- itself such a table is translated too (e.g. a zone name inside an error message).
local Locale = {}

export type Message = { key: string, args: { [string]: any }? }

Locale.Default = "en"
Locale.Languages = {
	{ code = "en", name = "English", flag = "🇺🇸" },
	{ code = "es", name = "Español", flag = "🇪🇸" },
	{ code = "pt", name = "Português", flag = "🇧🇷" },
	{ code = "fr", name = "Français", flag = "🇫🇷" },
	{ code = "de", name = "Deutsch", flag = "🇩🇪" },
	{ code = "id", name = "Bahasa Indonesia", flag = "🇮🇩" },
	{ code = "tr", name = "Türkçe", flag = "🇹🇷" },
	{ code = "ru", name = "Русский", flag = "🇷🇺" },
	{ code = "ja", name = "日本語", flag = "🇯🇵" },
	{ code = "ko", name = "한국어", flag = "🇰🇷" },
	{ code = "th", name = "ไทย", flag = "🇹🇭" },
	{ code = "vi", name = "Tiếng Việt", flag = "🇻🇳" },
}
Locale.Supported = {} :: { [string]: boolean }
for _, l in Locale.Languages do
	Locale.Supported[l.code] = true
end

local packs: { [string]: { [string]: string } } = {}
local function load(code: string): { [string]: string }?
	local pack = packs[code]
	if pack then
		return pack
	end
	if not Locale.Supported[code] then
		return nil
	end
	local ok, result = pcall(function()
		if script then
			return (require :: any)((script :: any).Parent.Locales[code])
		end
		return (require :: any)("./Locales/" .. code)
	end)
	if ok and type(result) == "table" then
		packs[code] = result
		return result
	end
	return nil
end
Locale.pack = load

-- Proper names (planets, forms, techniques, enemies, currencies...) live in ONE file,
-- Names.luau, shared by every language; a locale pack may still override a key.
local names: { [string]: string }? = nil
local function properName(key: string): string?
	if names == nil then
		local ok, result = pcall(function()
			if script then
				return (require :: any)((script :: any).Parent.Names)
			end
			return (require :: any)("./Names")
		end)
		names = if ok and type(result) == "table" then result else {}
	end
	return (names :: { [string]: string })[key]
end
Locale.properName = properName

-- Placeholders every text may use without passing an argument: they resolve to a proper name.
Locale.AutoArgs = { sparks = "currency.sparks", gems = "currency.gems" } :: { [string]: string }

local function format(lang: string, template: string, args: { [string]: any }?): string
	if not template:find("{", 1, true) then
		return template
	end
	return (template:gsub("{(%w+)}", function(name: string): string
		local v = if args then (args :: any)[name] else nil
		if v == nil then
			local auto = Locale.AutoArgs[name]
			if auto then
				return Locale.t(lang, auto)
			end
			return "{" .. name .. "}"
		elseif type(v) == "table" and type(v.key) == "string" then
			return Locale.t(lang, v.key, v.args)
		end
		return tostring(v)
	end))
end

-- Translated text for key; falls back to English, then to the key itself.
function Locale.t(lang: string, key: string, args: { [string]: any }?): string
	local pack = load(lang)
	local s = (pack and pack[key]) or properName(key)
	if not s and lang ~= Locale.Default then
		local en = load(Locale.Default)
		s = en and en[key]
	end
	return format(lang, s or key, args)
end

-- Renders a server message ({ key, args }) or passes a plain string through.
function Locale.msg(lang: string, m: any): string
	if type(m) == "table" and type(m.key) == "string" then
		return Locale.t(lang, m.key, m.args)
	end
	return if m == nil then "" else tostring(m)
end

-- Roblox LocaleId ("es-es", "pt-br", "zh-cn", "en_us"...) -> supported code (default "en").
function Locale.resolve(localeId: string?): string
	if type(localeId) ~= "string" then
		return Locale.Default
	end
	local base = localeId:lower():match("^(%a+)") or ""
	if base == "in" then
		base = "id" -- legacy Indonesian code
	end
	return if Locale.Supported[base] then base else Locale.Default
end

-- Server helper: a message the client translates.
function Locale.m(key: string, args: { [string]: any }?): Message
	return { key = key, args = args }
end

return Locale
