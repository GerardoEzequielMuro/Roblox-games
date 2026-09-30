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

local function format(lang: string, template: string, args: { [string]: any }?): string
	if not args then
		return template
	end
	return (template:gsub("{(%w+)}", function(name: string): string
		local v = (args :: any)[name]
		if v == nil then
			return "{" .. name .. "}"
		elseif type(v) == "table" and type(v.key) == "string" then
			return Locale.t(lang, v.key, v.args)
		end
		return tostring(v)
	end))
end

-- Singular forms: when args.n is "one" in the language (1 in en/de/es/fr/pt; 1, 21, 31... but
-- not 11 in ru) the key "<key>.one" is used if the language has it, otherwise the plain key.
-- ja/ko/th/vi/id/tr have no plural and never need a ".one" key.
local function isOne(lang: string, n: number): boolean
	if lang == "ru" then
		return n % 10 == 1 and n % 100 ~= 11
	end
	return n == 1
end

-- Translated text for key; falls back to English, then to the key itself.
function Locale.t(lang: string, key: string, args: { [string]: any }?): string
	local pack = load(lang)
	if args and pack then
		local n = (args :: any).n
		if type(n) == "number" and isOne(lang, n) then
			local one = pack[key .. ".one"]
			if one then
				return format(lang, one, args)
			end
		end
	end
	local s = pack and pack[key]
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
