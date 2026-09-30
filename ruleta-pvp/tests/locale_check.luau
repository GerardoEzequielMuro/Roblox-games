-- Locale checks (run with luau.exe from the repo root):
--   ../huerta-tycoon/tools/luau.exe tests/locale_check.luau
-- * every Config-driven key (modes, slots, cards, modifiers, cosmetics, passes, products,
--   leagues, events, quests, rarities...) exists in English
-- * every English key exists in every language, and every {placeholder} survives
-- * no language uses betting / casino vocabulary (this is an elimination party game)
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
for _, m in Config.Modes do
	table.insert(needed, "mode." .. m.id .. ".name")
	table.insert(needed, "mode." .. m.id .. ".desc")
end
for _, o in Config.Outcomes do
	table.insert(needed, "out." .. o.id)
	table.insert(needed, "out." .. o.id .. ".desc")
end
for _, c in Config.Cards do
	table.insert(needed, "card." .. c.id .. ".name")
	table.insert(needed, "card." .. c.id .. ".short")
	table.insert(needed, "card." .. c.id .. ".desc")
end
for _, m in Config.Modifiers do
	table.insert(needed, "mod." .. m.id .. ".name")
	table.insert(needed, "mod." .. m.id .. ".desc")
end
for _, item in Config.Cosmetics do
	table.insert(needed, "cos." .. item.id)
	table.insert(needed, "unlock." .. (if item.unlock.type == "coins" or item.unlock.type == "league" or item.unlock.type == "pass" then "default" else item.unlock.type))
end
for _, kind in Config.CosmeticKinds do
	table.insert(needed, "locker." .. kind)
end
for _, r in Config.Rarities do
	table.insert(needed, "rarity." .. r.id)
end
for _, l in Config.Leagues do
	table.insert(needed, "league." .. l.id)
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
for _, name in { "Shop", "Season", "Locker", "Rewards", "Quests", "Ranking", "Invite", "Settings" } do
	table.insert(needed, "menu." .. name)
	table.insert(needed, "win." .. name)
end
for _, key in { "music", "sfx", "shake", "flashes", "lite", "autoQueue", "autoPlay", "autoCharge", "language" } do
	table.insert(needed, "set." .. key)
end
for _, kind in { "season", "wins", "weekly" } do
	table.insert(needed, "rank." .. kind)
end
for _, k in { "title", "shop_desc", "open", "tier", "ends", "maxed", "next", "how", "fair", "claim_all", "buy_premium", "premium", "skip", "tier_up", "cannot_claim", "claimed_n" } do
	table.insert(needed, "season." .. k)
end
for _, k in { "result.season", "shop.bonus", "unlock.season", "goal.league", "goal.top_league", "goal.season" } do
	table.insert(needed, k)
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

-- Betting vocabulary that must never show up (lower-cased substring match). Spaces around
-- short Latin words avoid false hits inside other words.
local BANNED = {
	"casino", "jackpot", "gambl", "roulette", "wager", " bet ", " bets ", "betting", "lottery", "poker chip",
	"apuesta", "apostar", "ruleta", "lotería", "aposta", "roleta", "loteria", " pari ", "parier", "wette", "wetten", "glücksspiel",
	"taruhan", "judi", "rolet", "bahis", "kumar", "rulet", "ставк", "рулетк", "казино", "джекпот", "лотере",
	"賭", "ルーレット", "カジノ", "ジャックポット", "베팅", "룰렛", "카지노", "도박", "잭팟", "พนัน", "รูเล็ต", "คาสิโน", "แจ็คพอต",
	"cá cược", "đánh bạc", "sòng bạc",
}

for _, lang in Locale.Languages do
	local pack = Locale.pack(lang.code)
	if not pack then
		fail(lang.code .. ": pack missing")
		continue
	end
	local n = 0
	for key, text in en do
		local tr = pack[key]
		if tr == nil and string.sub(key, -4) == ".one" then
			-- singular forms are optional: a language without one uses the plain key
			continue
		elseif tr == nil then
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
			local lower = " " .. string.lower(tr) .. " "
			for _, word in BANNED do
				if string.find(lower, word, 1, true) then
					fail(string.format("%s: %s uses betting vocabulary (%s): %s", lang.code, key, word, tr))
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
eq("t with args", Locale.t("en", "match.round", { n = 3 }), "Round 3")
eq("fallback to key", Locale.t("en", "no.such.key"), "no.such.key")
eq("fallback to en", Locale.t("xx", "menu.Shop"), "Shop")
eq("nested message arg", Locale.t("en", "msg.league_up", { league = { key = "league.gold" } }), "New league: Gold")
eq("plural en one", Locale.t("en", "quest.win", { n = 1 }), "Win 1 match")
eq("plural en many", Locale.t("en", "quest.win", { n = 3 }), "Win 3 matches")
eq("plural es one", Locale.t("es", "goal.league", { n = 1, league = "Oro" }), "1 trofeo para Oro")
eq("plural ru 21", Locale.t("ru", "goal.league", { n = 21, league = "X" }), "21 трофей до лиги X")
eq("plural ru 11", Locale.t("ru", "goal.league", { n = 11, league = "X" }), "11 трофеев до лиги X")
eq("plural ja has none", Locale.t("ja", "goal.league", { n = 1, league = "X" }), "Xまであと1トロフィー")
eq("msg of string", Locale.msg("en", "plain"), "plain")
eq("msg of table", Locale.msg("en", Locale.m("msg.slow_down")), "Slow down")
eq("resolve es-mx", Locale.resolve("es-mx"), "es")
eq("resolve pt-br", Locale.resolve("pt-br"), "pt")
eq("resolve en_us", Locale.resolve("en_us"), "en")
eq("resolve zh-cn", Locale.resolve("zh-cn"), "en")
eq("resolve ja-jp", Locale.resolve("ja-jp"), "ja")
eq("resolve nil", Locale.resolve(nil), "en")

print(if fails == 0 then "LOCALE CHECKS PASSED" else (fails .. " LOCALE FAILURES"))
