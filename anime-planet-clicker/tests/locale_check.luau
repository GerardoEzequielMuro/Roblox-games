-- Locale checks (run with luau.exe from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/locale_check.luau
-- * every Config-driven key (pets, capsules, galaxies, planets, tools, systems, upgrades,
--   passes, products, events, quests, autos, tutorial, reward kinds) exists in English
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
for _, c in Config.Capsules do
	table.insert(needed, "capsule." .. c.id)
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
for _, k in Config.PlanetKinds do
	table.insert(needed, "planet." .. k.id)
end
for id in Config.Buffs do
	table.insert(needed, "buff." .. id)
end
for _, t in Config.Tools do
	table.insert(needed, "tool." .. t.id)
end
for _, m in Config.Materials do
	table.insert(needed, "material." .. m)
end
for _, s in Config.RelicStats do
	table.insert(needed, "stat." .. s)
end
for _, t in Config.Traits do
	table.insert(needed, "trait." .. t.id)
end
for _, s in Config.Systems do
	table.insert(needed, "system." .. s.id .. ".name")
	table.insert(needed, "system." .. s.id .. ".short")
	table.insert(needed, "system." .. s.id .. ".desc")
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
for _, key in Config.AutoKeys do
	table.insert(needed, "auto." .. key .. ".name")
	table.insert(needed, "auto." .. key .. ".short")
	table.insert(needed, "auto." .. key .. ".desc")
end
for _, step in Config.Tutorial do
	table.insert(needed, "tutorial." .. step.id)
	table.insert(needed, "tutorial.done_" .. step.id)
	table.insert(needed, "rewardlabel." .. step.reward.kind)
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
eq("t with args", Locale.t("en", "hud.galaxy_n", { n = 3 }), "Galaxy 3")
eq("fallback to key", Locale.t("en", "no.such.key"), "no.such.key")
eq("fallback to en", Locale.t("xx", "menu.Pets"), "Pets")
eq("nested message arg", Locale.t("en", "msg.unlock_first", { zone = { key = "zone.frost" } }), "Unlock Frost Halo first!")
eq("msg of string", Locale.msg("en", "plain"), "plain")
eq("msg of table", Locale.msg("en", Locale.m("msg.slow_down")), "Slow down!")
eq("resolve es-mx", Locale.resolve("es-mx"), "es")
eq("resolve pt-br", Locale.resolve("pt-br"), "pt")
eq("resolve en_us", Locale.resolve("en_us"), "en")
eq("resolve zh-cn", Locale.resolve("zh-cn"), "en")
eq("resolve ja-jp", Locale.resolve("ja-jp"), "ja")
eq("resolve nil", Locale.resolve(nil), "en")

print(if fails == 0 then "LOCALE CHECKS PASSED" else (fails .. " LOCALE FAILURES"))
