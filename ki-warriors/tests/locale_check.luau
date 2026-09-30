-- Locale checks (run with luau.exe from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/locale_check.luau
-- * every Config-driven key exists in English or in Names.luau
-- * every English key exists in every language, and every
--   {placeholder} survives
-- * Locale.t fallbacks, proper names, automatic currency placeholders, Locale.resolve
local Locale = require("../src/shared/Locale")
local Config = require("../src/shared/Config")
local Names = require("../src/shared/Names")

local only: { [string]: boolean } = {}
local filter = false

local fails = 0
local function fail(msg: string)
	fails += 1
	if fails <= 80 then
		print("FAIL: " .. msg)
	end
end

local en = Locale.pack("en")
assert(en, "en pack missing")

-- Config-driven keys: text keys must be in en, name keys in Names
local texts, names = {}, {}
for _, s in Config.Stats do
	table.insert(texts, "stat." .. s)
end
for _, pl in Config.Planets do
	table.insert(names, "planet." .. pl.id)
	for _, z in pl.zones do
		table.insert(names, "zone." .. z.id)
	end
end
for id in Config.Npcs do
	table.insert(names, "npc." .. id)
end
for _, f in Config.Forms do
	table.insert(names, "form." .. f.id)
end
for _, t in Config.Techniques do
	table.insert(names, "tech." .. t.id)
	table.insert(texts, "tech." .. t.id .. ".desc")
end
for _, a in Config.Auras do
	table.insert(names, "aura." .. a.id)
end
for _, r in Config.Races do
	table.insert(names, "race." .. r.id)
	table.insert(texts, "race.bonus." .. r.bonus)
end
for _, r in Config.Rarities do
	table.insert(texts, "rarity." .. r.name)
end
for _, u in Config.Upgrades do
	table.insert(texts, "upgrade." .. u.id .. ".name")
	table.insert(texts, "upgrade." .. u.id .. ".desc")
end
for _, p in Config.Passes do
	table.insert(texts, "pass." .. p.key .. ".name")
	table.insert(texts, "pass." .. p.key .. ".desc")
end
for _, p in Config.Products do
	table.insert(texts, "product." .. p.key .. ".name")
	table.insert(texts, "product." .. p.key .. ".desc")
end
for _, sk in Config.Skins do
	table.insert(names, "skin." .. sk.id)
	table.insert(names, "arc." .. sk.arc)
end
for _, m in Config.Mounts do
	table.insert(names, "mount." .. m.id)
end
for _, sd in Config.Seeds do
	table.insert(names, "item." .. sd.id)
	table.insert(texts, "seed." .. sd.id .. ".desc")
end
for _, season in Config.BattlePass.seasons do
	table.insert(names, "season." .. season.id)
end
for _, kind in { "seed", "skin", "mount", "aura" } do
	table.insert(texts, "rewardlabel." .. kind)
	table.insert(texts, "reward." .. kind)
end
for id in Config.LiveEventDefs do
	table.insert(texts, "event." .. id)
end
for _, q in Config.QuestPool do
	table.insert(texts, "quest." .. q.kind)
end
for _, w in Config.Wishes do
	table.insert(texts, "wish." .. w.id)
end
for _, s in Config.Story do
	table.insert(texts, "story." .. s.kind)
end
for _, list in { Config.DailyRewards, Config.Gifts } do
	for _, r in list :: { any } do
		local reward = r.reward or r
		table.insert(texts, "rewardlabel." .. reward.kind)
		table.insert(texts, "rewardicon." .. reward.kind)
	end
end
for _, k in texts do
	if not en[k] then
		fail("en missing Config key " .. k)
	end
end
for _, k in names do
	if not Names[k] then
		fail("Names missing " .. k)
	end
end
for k in Names do
	if en[k] then
		fail("name key also in en (keep names in Names.luau only): " .. k)
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
	if filter and not only[lang.code] then
		continue
	end
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
		if en[key] == nil and Names[key] == nil then
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
eq("t with args", Locale.t("en", "forms.need", { power = "5K" }), "5K power")
eq("fallback to key", Locale.t("en", "no.such.key"), "no.such.key")
eq("fallback to en", Locale.t("xx", "hud.power"), "POWER")
eq("proper name", Locale.t("en", "planet.verdia"), "Verdia")
eq("proper name in another language", Locale.t("ja", "npc.bramble_king"), "Bramble King")
eq("auto currency placeholder", Locale.t("en", "msg.need_sparks"), "Not enough Sparks!")
eq("nested message arg", Locale.t("en", "msg.zone_locked", { zone = { key = "zone.gravity_dome" }, power = "150" }), "Gravity Dome needs 150 power to boost your training.")
eq("msg of string", Locale.msg("en", "plain"), "plain")
eq("msg of table", Locale.msg("en", Locale.m("msg.slow_down")), "Slow down!")
eq("resolve es-mx", Locale.resolve("es-mx"), "es")
eq("resolve pt-br", Locale.resolve("pt-br"), "pt")
eq("resolve en_us", Locale.resolve("en_us"), "en")
eq("resolve zh-cn", Locale.resolve("zh-cn"), "en")
eq("resolve ja-jp", Locale.resolve("ja-jp"), "ja")
eq("resolve nil", Locale.resolve(nil), "en")
eq("resolveFirst first supported", Locale.resolveFirst("es-ar", "en-us"), "es")
eq("resolveFirst skips unsupported", Locale.resolveFirst("zh-cn", "", nil, "es-419"), "es")
eq("resolveFirst english wins when first", Locale.resolveFirst("en-us", "es-es"), "en")
eq("resolveFirst nothing", Locale.resolveFirst(nil, ""), "en")
eq("resolveFirst legacy id", Locale.resolveFirst("in-id"), "id")

print(if fails == 0 then "LOCALE CHECKS PASSED" else (fails .. " LOCALE FAILURES"))
