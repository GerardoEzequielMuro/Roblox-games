-- Pure-Luau locale check (run: tools/luau.exe tests/locale_test.luau).
-- Every key in en exists in every language and every "{placeholder}" of the English text appears in the translation.
local LANGS = { "es", "pt", "fr", "de", "id", "tr", "ru", "ja", "ko", "th", "vi" }
local en = require("../src/shared/Locales/en")

local function placeholders(s: string): { string }
	local out = {}
	for name in string.gmatch(s, "{([%w_]+)}") do
		table.insert(out, name)
	end
	return out
end

local fails, checks = 0, 0
local function fail(msg: string)
	fails += 1
	print("FAIL " .. msg)
end

local enCount = 0
for _ in en do
	enCount += 1
end

for _, code in LANGS do
	local ok, t = pcall(require, "../src/shared/Locales/" .. code)
	checks += 1
	if not ok or type(t) ~= "table" then
		fail(code .. ": cannot load (" .. tostring(t) .. ")")
		continue
	end
	for key, text in en do
		checks += 1
		local tr = t[key]
		if type(tr) ~= "string" or tr == "" then
			fail(code .. ": missing " .. key)
			continue
		end
		for _, ph in placeholders(text) do
			if not string.find(tr, "{" .. ph .. "}", 1, true) then
				fail(code .. ": " .. key .. " lacks {" .. ph .. "}")
			end
		end
		for _, ph in placeholders(tr) do
			if not string.find(text, "{" .. ph .. "}", 1, true) then
				fail(code .. ": " .. key .. " has unknown {" .. ph .. "}")
			end
		end
	end
	for key in t do
		if en[key] == nil then
			fail(code .. ": extra key " .. key)
		end
	end
end

print(string.format("locale_test: %d languages, %d keys in en, %d checks, %d failures", #LANGS, enCount, checks, fails))
if fails > 0 then
	error("locale_test failed")
end
