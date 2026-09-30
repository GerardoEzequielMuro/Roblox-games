--!strict
-- Pure-Luau test for the translations. Run from the project root:
--   ../huerta-tycoon/tools/luau.exe tests/locale_test.luau
-- Checks that every language has every English key, keeps every {placeholder} of the English
-- text, has no keys English doesn't know, and that Locale.t / message / resolve behave.
local Locale = require("../src/shared/Locale")

local tables: { [string]: { [string]: string } } = {}
for _, code in Locale.LANGS do
	tables[code] = require("../src/shared/Locales/" .. code) :: any
end
Locale.setLoader(function(code)
	return tables[code]
end)

local failures, checks = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		if failures <= 60 then
			print("FAIL: " .. msg)
		end
	end
end

local function placeholders(s: string): { [string]: boolean }
	local out = {}
	for name in string.gmatch(s, "{([%w_]+)}") do
		out[name] = true
	end
	return out
end

local en = tables.en
local enCount = 0
for _ in en do
	enCount += 1
end
print(("en has %d keys, %d languages"):format(enCount, #Locale.LANGS))

for _, code in Locale.LANGS do
	local t = tables[code]
	check(type(t) == "table", code .. ": table loads")
	for key, text in en do
		local tr = t[key]
		check(type(tr) == "string" and #tr > 0, ("%s: missing key %s"):format(code, key))
		if type(tr) == "string" then
			for name in placeholders(text) do
				check(string.find(tr, "{" .. name .. "}", 1, true) ~= nil, ("%s: %s lost {%s}"):format(code, key, name))
			end
			for name in placeholders(tr) do
				check(placeholders(text)[name] == true, ("%s: %s has unknown {%s}"):format(code, key, name))
			end
		end
	end
	for key in t do
		check(en[key] ~= nil, ("%s: extra key %s not in en"):format(code, key))
	end
	check(Locale.NATIVE[code] ~= nil, code .. ": has a native name")
end

-- behaviour
check(Locale.t("en", "celebrate.stage", { n = 7 }) == "STAGE 7!", "t fills args")
check(Locale.t("xx", "celebrate.stage", { n = 7 }) == "STAGE 7!", "unknown language falls back to en")
check(Locale.t("es", "no.such.key") == "no.such.key", "unknown key returns the key")
check(Locale.t("en", "msg.bought_trail", { name = { key = "trail.fire" } }) == "Bought the Fire trail!", "nested spec args")
check(Locale.message("en", { { key = "msg.code", args = { coins = 5 } }, { key = "msg.plus_free_skips", args = { n = 1 } } }) == "Code redeemed: +5 coins! +1 free skip!", "message joins a list")
check(Locale.message("en", "plain") == "plain", "message passes plain strings")
check(Locale.message("en", nil) == nil, "message nil")
check(Locale.resolve("es-mx") == "es" and Locale.resolve("es-es") == "es", "resolve es")
check(Locale.resolve("pt-br") == "pt" and Locale.resolve("pt-pt") == "pt", "resolve pt")
check(Locale.resolve("zh-cn") == "en" and Locale.resolve("") == "en" and Locale.resolve(nil) == "en", "resolve fallback")
check(Locale.resolve("ja-jp") == "ja" and Locale.resolve("ko-kr") == "ko" and Locale.resolve("in-id") == "id", "resolve ja/ko/in")
check(Locale.resolve("EN-US") == "en", "resolve is case-insensitive")

print(("%d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("locale test FAILED")
end
print("locale test PASSED")
