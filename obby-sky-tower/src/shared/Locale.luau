--!strict
-- Translations. One flat table per language in Shared/Locales/<code>.luau ({ [key] = "text {arg}" }).
-- PURE Luau apart from the default loader (Roblox `script`), so tests/locale_test.luau can run it with
-- luau.exe by calling Locale.setLoader.
--
-- Messages that travel server -> client are "specs": { key = "msg.x", args = { n = 3 } }. An arg can
-- itself be a spec (e.g. a trail name { key = "trail.fire" }), and Locale.message also accepts a list
-- of specs (joined with a space) or a plain string (returned as is).

local Locale = {}

export type Spec = { key: string, args: { [string]: any }? }
type Table = { [string]: string }

Locale.DEFAULT = "en"
Locale.LANGS = { "en", "es", "pt", "fr", "de", "id", "tr", "ru", "ja", "ko", "th", "vi" }
Locale.NATIVE = {
	en = { flag = "🇺🇸", name = "English" },
	es = { flag = "🇪🇸", name = "Español" },
	pt = { flag = "🇧🇷", name = "Português" },
	fr = { flag = "🇫🇷", name = "Français" },
	de = { flag = "🇩🇪", name = "Deutsch" },
	id = { flag = "🇮🇩", name = "Bahasa Indonesia" },
	tr = { flag = "🇹🇷", name = "Türkçe" },
	ru = { flag = "🇷🇺", name = "Русский" },
	ja = { flag = "🇯🇵", name = "日本語" },
	ko = { flag = "🇰🇷", name = "한국어" },
	th = { flag = "🇹🇭", name = "ไทย" },
	vi = { flag = "🇻🇳", name = "Tiếng Việt" },
} :: { [string]: { flag: string, name: string } }

local supported: { [string]: boolean } = {}
for _, code in Locale.LANGS do
	supported[code] = true
end

function Locale.isSupported(code: string): boolean
	return supported[code] == true
end

local cache: { [string]: Table } = {}
local loader: ((code: string) -> Table?)? = nil

-- Default loader: the ModuleScripts in Shared/Locales (Roblox only).
local function defaultLoader(code: string): Table?
	local s: any = script -- nil under the standalone luau.exe
	if typeof(s) ~= "Instance" then
		return nil
	end
	local folder = s.Parent and s.Parent:FindFirstChild("Locales")
	local mod = folder and folder:FindFirstChild(code)
	if not mod then
		return nil
	end
	return (require :: any)(mod)
end

function Locale.setLoader(fn: (code: string) -> Table?)
	loader = fn
	table.clear(cache)
end

local function tableFor(code: string): Table?
	local t = cache[code]
	if t then
		return t
	end
	local load = loader or defaultLoader
	local ok, result = pcall(load, code)
	if ok and type(result) == "table" then
		cache[code] = result
		return result
	end
	return nil
end

local function argText(lang: string, v: any): string
	if type(v) == "table" and type(v.key) == "string" then
		return Locale.t(lang, v.key, v.args)
	end
	return tostring(v)
end

-- Translated text for `key`, falling back to English and then to the key itself.
function Locale.t(lang: string, key: string, args: { [string]: any }?): string
	local tbl = tableFor(lang)
	local text = tbl and tbl[key]
	if text == nil and lang ~= Locale.DEFAULT then
		local en = tableFor(Locale.DEFAULT)
		text = en and en[key]
	end
	if text == nil then
		return key
	end
	if args then
		local a = args
		text = string.gsub(text, "{([%w_]+)}", function(name: string)
			local v = a[name]
			if v == nil then
				return "{" .. name .. "}"
			end
			return argText(lang, v)
		end)
	end
	return text
end

-- Accepts a plain string, a spec, or a list of specs.
function Locale.message(lang: string, msg: any): string?
	if msg == nil then
		return nil
	end
	if type(msg) == "string" then
		return msg
	end
	if type(msg) ~= "table" then
		return tostring(msg)
	end
	if type(msg.key) == "string" then
		return Locale.t(lang, msg.key, msg.args)
	end
	local parts = {}
	for _, m in msg do
		local s = Locale.message(lang, m)
		if s then
			table.insert(parts, s)
		end
	end
	return table.concat(parts, " ")
end

-- Roblox LocaleId ("es-es", "pt-br", "zh-cn", "en-us"...) -> a supported code (default "en").
function Locale.resolve(localeId: string?): string
	local id = string.lower(tostring(localeId or ""))
	local base = string.match(id, "^(%a%a)") or ""
	if base == "in" then
		base = "id" -- old Java-style code for Indonesian
	end
	if supported[base] then
		return base
	end
	return Locale.DEFAULT
end

function Locale.spec(key: string, args: { [string]: any }?): Spec
	return { key = key, args = args }
end

return Locale
