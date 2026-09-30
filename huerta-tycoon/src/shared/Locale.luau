--!strict
-- Tiny i18n: flat string tables per language (Shared/Locales/<code>), "{name}" placeholders.
-- Args may be plain values, nested refs ({key=..., args=...}, translated in the same language) or
-- lists ({list = {...}, sep = ", "}). Numbers/cash are formatted by Format before they get here.
local Locale = {}

export type Ref = { key: string, args: { [string]: any }? }

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

local folder = script.Parent:WaitForChild("Locales")
local cache: { [string]: { [string]: string } } = {}

local function tableFor(code: string): { [string]: string }?
	local t = cache[code]
	if t then
		return t
	end
	if not Locale.Supported[code] then
		return nil
	end
	local mod = folder:FindFirstChild(code)
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, mod)
	if ok and type(res) == "table" then
		cache[code] = res :: any
		return res :: any
	end
	warn("[Locale] failed to load", code, res)
	return nil
end

function Locale.ref(key: string, args: { [string]: any }?): Ref
	return { key = key, args = args }
end

function Locale.isRef(v: any): boolean
	return type(v) == "table" and type(v.key) == "string"
end

-- Is this string key present in English?
function Locale.has(key: string): boolean
	local en = tableFor(Locale.Default)
	return en ~= nil and en[key] ~= nil
end

function Locale.value(lang: string, v: any): string
	if type(v) == "table" then
		if type(v.key) == "string" then
			return Locale.t(lang, v.key, v.args)
		elseif type(v.list) == "table" then
			local parts = {}
			for _, item in v.list do
				table.insert(parts, Locale.value(lang, item))
			end
			return table.concat(parts, if type(v.sep) == "string" then v.sep else ", ")
		end
	end
	return tostring(v)
end

-- Translate key into lang; falls back to English, then to the key itself.
function Locale.t(lang: string, key: string, args: { [string]: any }?): string
	local tbl = tableFor(lang)
	local s = (tbl and tbl[key]) or (tableFor(Locale.Default) or {})[key] or key
	if args then
		s = string.gsub(s, "{([%w_]+)}", function(name: string): string
			local v = args[name]
			if v == nil then
				return "{" .. name .. "}"
			end
			return Locale.value(lang, v)
		end)
	end
	return s
end

-- Translate a ref or pass a plain string through.
function Locale.tr(lang: string, v: any): string?
	if v == nil then
		return nil
	end
	if Locale.isRef(v) then
		return Locale.t(lang, v.key, v.args)
	end
	return tostring(v)
end

-- Roblox LocaleId ("es-es", "es-mx", "pt-br", "zh-cn", "en_us"...) -> supported code, default "en".
function Locale.resolve(localeId: string?): string
	if type(localeId) ~= "string" or localeId == "" then
		return Locale.Default
	end
	local id = string.lower(localeId)
	if Locale.Supported[id] then
		return id
	end
	local base = string.match(id, "^(%a+)[-_]") or id
	if Locale.Supported[base] then
		return base
	end
	return Locale.Default
end

-- World text (SurfaceGui/BillboardGui labels, ProximityPrompts): the server writes English and tags the instance;
-- each client re-renders it in its own language (see client UI/WorldText).
function Locale.stamp(inst: Instance, key: string, args: { [string]: any }?, prop: string?)
	local p = prop or "Text"
	;(inst :: any)[p] = Locale.t(Locale.Default, key, args)
	inst:SetAttribute("LocArgs" .. (if p == "Text" then "" else "_" .. p), if args then game:GetService("HttpService"):JSONEncode(args) else "")
	inst:SetAttribute("LocKey" .. (if p == "Text" then "" else "_" .. p), key)
end

-- Convenience refs for Config content.
function Locale.seedName(seedId: string): Ref
	return { key = "seed." .. seedId }
end

return Locale
