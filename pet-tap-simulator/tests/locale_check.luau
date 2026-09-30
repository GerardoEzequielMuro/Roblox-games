-- Locale checks (run with luau.exe from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/locale_check.luau
-- * every Config-driven key (pets, eggs, zones, rarities, tiers, upgrades, passes, products,
--   events, quests, reward kinds) exists in English
-- * every English key exists in every language, and every {placeholder} survives
-- * Locale.t fallbacks and Locale.resolve mappings
local Locale = require("../src/shared/Locale")
local Config = require("../src/shared/Config")

local fails = 0
local function fail(msg: string)
	fails += 1
	if fails <= 60 then
		print("FAIL: " .. msg)
	end
end

local en = Locale.pack("en")
assert(en, "en pack missing")

-- Config-driven keys
local needed = {}
for _, p in Config.Pets do
	table.insert(needed, "pet." .. p.id)
end
for _, e in Config.Eggs do
	table.insert(needed, "egg." .. e.id)
end
for _, z in Config.Zones do
	table.insert(needed, "zone." .. z.id)
end
for _, r in Config.Rarities do
	table.insert(needed, "rarity." .. r.name)
end
for t in Config.Tiers do
	table.insert(needed, "tier." .. t)
end
for _, u in Config.Upgrades do
	table.insert(needed, "upgrade." .. u.id .. ".name")
	table.insert(needed, "upgrade." .. u.id .. ".desc")
end
for _, p in Config.Passes do
	table.insert(needed, "pass." .. p.key .. ".name")
	table.insert(needed, "pass." .. p.key .. ".desc")
end
for _, p in Config.Products do
	table.insert(needed, "product." .. p.key .. ".name")
	table.insert(needed, "product." .. p.key .. ".desc")
end
for id in Config.LiveEventDefs do
	table.insert(needed, "event." .. id)
end
for _, q in Config.QuestPool do
	table.insert(needed, "quest." .. q.kind)
end
for _, list in { Config.DailyRewards, Config.Gifts } do
	for _, r in list :: { any } do
		local reward = r.reward or r
		table.insert(needed, "rewardlabel." .. reward.kind)
	end
end
for _, k in needed do
	if not en[k] then
		fail("en missing Config key " .. k)
	end
end

local function placeholders(s: string): { [string]: boolean }
	local set = {}
	for name in s:gmatch("{(%w+)}") do
		set[name] = true
	end
	return set
end

local enCount = 0
for _ in en do
	enCount += 1
end

for _, lang in Locale.Languages do
	local pack = Locale.pack(lang.code)
	if not pack then
		fail(lang.code .. ": pack missing")
		continue
	end
	local n = 0
	for key, text in en do
		local tr = pack[key]
		if tr == nil then
			fail(lang.code .. ": missing " .. key)
		elseif type(tr) ~= "string" or tr == "" then
			fail(lang.code .. ": empty " .. key)
		else
			n += 1
			local want = placeholders(text)
			local got = placeholders(tr)
			for name in want do
				if not got[name] then
					fail(string.format("%s: %s lost {%s}", lang.code, key, name))
				end
			end
			for name in got do
				if not want[name] then
					fail(string.format("%s: %s has unknown {%s}", lang.code, key, name))
				end
			end
		end
	end
	for key in pack do
		if en[key] == nil then
			fail(lang.code .. ": extra key " .. key)
		end
	end
	print(string.format("%-3s %-18s %d/%d keys", lang.code, lang.name, n, enCount))
end

-- API behaviour
local function eq(name: string, got: any, want: any)
	if got ~= want then
		fail(string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end
eq("t with args", Locale.t("en", "hud.per_tap", { n = "5K" }), "+5K per tap")
eq("fallback to key", Locale.t("en", "no.such.key"), "no.such.key")
eq("fallback to en", Locale.t("xx", "menu.Pets"), "Pets")
eq("nested message arg", Locale.t("en", "msg.unlock_first", { zone = { key = "zone.candy" } }), "Unlock Candy Land first!")
eq("msg of string", Locale.msg("en", "plain"), "plain")
eq("msg of table", Locale.msg("en", Locale.m("msg.slow_down")), "Slow down!")
eq("resolve es-mx", Locale.resolve("es-mx"), "es")
eq("resolve pt-br", Locale.resolve("pt-br"), "pt")
eq("resolve en_us", Locale.resolve("en_us"), "en")
eq("resolve zh-cn", Locale.resolve("zh-cn"), "en")
eq("resolve ja-jp", Locale.resolve("ja-jp"), "ja")
eq("resolve nil", Locale.resolve(nil), "en")

print(if fails == 0 then "LOCALE CHECKS PASSED" else (fails .. " LOCALE FAILURES"))
