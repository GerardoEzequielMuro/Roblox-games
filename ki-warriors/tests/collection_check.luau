-- Earn-or-buy rules (Shared/Collection), special forms and pass bundles. Pure.
local Collection = require("../src/shared/Collection")
local Formulas = require("../src/shared/Formulas")
local Config = require("../src/shared/Config")

local fails = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		fails += 1
		print("FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

local function ctx(over: any?): any
	local c: any = { passes = {}, bossKills = {}, rebirths = 0, pvpKills = 0, planet = 1, power = 0 }
	for k, v in over or {} do
		c[k] = v
	end
	return c
end

-- earned: every present field must hold
check("no req never earned", not Collection.earned(nil, ctx()))
check("boss req unmet", not Collection.earned({ boss = "glutt", count = 5 }, ctx({ bossKills = { glutt = 4 } })))
check("boss req met", Collection.earned({ boss = "glutt", count = 5 }, ctx({ bossKills = { glutt = 5 } })))
check("boss count defaults to 1", Collection.earned({ boss = "x" }, ctx({ bossKills = { x = 1 } })))
check("rebirths met", Collection.earned({ rebirths = 2 }, ctx({ rebirths = 2 })))
check("rebirths unmet", not Collection.earned({ rebirths = 2 }, ctx({ rebirths = 1 })))
check("pvp kills", Collection.earned({ pvpKills = 5 }, ctx({ pvpKills = 7 })))
check("all fields must hold (AND)", not Collection.earned({ boss = "a", rebirths = 1 }, ctx({ bossKills = { a = 1 } })))

-- owned: pass OR earn
local def = { pass = "SkinPack", earn = { boss = "bramble_king", count = 1 } }
check("owned by pass", select(1, Collection.owned(def, ctx({ passes = { SkinPack = true } }))))
check("owned via pass", select(2, Collection.owned(def, ctx({ passes = { SkinPack = true } }))) == "pass")
check("owned by earning", select(1, Collection.owned(def, ctx({ bossKills = { bramble_king = 1 } }))))
check("owned via earn", select(2, Collection.owned(def, ctx({ bossKills = { bramble_king = 1 } }))) == "earn")
check("not owned", not select(1, Collection.owned(def, ctx())))

-- special (forms / dark techniques): pass skips only the boss requirement
local special = { boss = "korrath", count = 3, pass = "UnboundForm" }
check("special: nothing", not Collection.specialOk(special, ctx()))
check("special: 2 kills", not Collection.specialOk(special, ctx({ bossKills = { korrath = 2 } })))
check("special: 3 kills", Collection.specialOk(special, ctx({ bossKills = { korrath = 3 } })))
check("special: pass", Collection.specialOk(special, ctx({ passes = { UnboundForm = true } })))
check("special: none required", Collection.specialOk(nil, ctx()))

-- Formulas.bestForm keeps the power / ascension requirement for special forms
local prim = Config.FormById.primordial
local unb = Config.FormById.unbound
check("unbound is the last form", Config.Forms[#Config.Forms].id == "unbound")
check("unbound needs at least Primordial's power and ascensions", unb.reqPower >= prim.reqPower and (unb.reqRebirths or 0) >= (prim.reqRebirths or 0))
check("no ctx: special form locked", Formulas.bestForm(unb.reqPower, 3) == prim.index)
check("ctx without kills: locked", Formulas.bestForm(unb.reqPower, 3, ctx()) == prim.index)
check("with 3 Korrath kills: unlocked", Formulas.bestForm(unb.reqPower, 3, ctx({ bossKills = { korrath = 3 } })) == unb.index)
check("with the pass: unlocked", Formulas.bestForm(unb.reqPower, 3, ctx({ passes = { UnboundForm = true } })) == unb.index)
check("pass does NOT skip power", Formulas.bestForm(unb.reqPower - 1, 3, ctx({ passes = { UnboundForm = true } })) == (Formulas.bestForm(unb.reqPower - 1, 3)))
check("pass does NOT skip ascensions", Formulas.bestForm(unb.reqPower, 2, ctx({ passes = { UnboundForm = true } })) < unb.index)
check("regular forms unchanged", Formulas.bestForm(1_000, 0) == 1 and Formulas.bestForm(50_000, 0) == 2)

-- expandPasses: bundle implies parts; TimeChamber is earned with ascensions
local owned = Collection.expandPasses({ DoubleBundle = true })
check("bundle -> x2 training", owned.DoubleTraining == true)
check("bundle -> x2 sparks", owned.DoubleSparks == true)
check("bundle keeps itself", owned.DoubleBundle == true)
check("no bundle: nothing implied", Collection.expandPasses({ VIP = true }).DoubleTraining == nil)
check("expand returns a new table", Collection.expandPasses({}) ~= nil)
check("TimeChamber not earned at 1 ascension", Collection.expandPasses({}, ctx({ rebirths = 1 })).TimeChamber == nil)
check("TimeChamber earned at 2 ascensions", Collection.expandPasses({}, ctx({ rebirths = 2 })).TimeChamber == true)

-- ownedIds over the real Config
local ids = Collection.ownedIds(Config.Skins, ctx({ bossKills = { bramble_king = 1, glutt = 5 } }))
check("skins earned by bosses", table.find(ids, "wanderer") ~= nil and table.find(ids, "glutt_hood") ~= nil and #ids == 2, #ids)
local all = Collection.ownedIds(Config.Skins, ctx({ passes = { SkinPack = true } }))
check("SkinPack gives every skin", #all == #Config.Skins, #all)
check("MountPack gives every mount", #Collection.ownedIds(Config.Mounts, ctx({ passes = { MountPack = true } })) == #Config.Mounts)
check("first mount is earned at the first boss", table.find(Collection.ownedIds(Config.Mounts, ctx({ bossKills = { bramble_king = 1 } })), "zephyr_puff") ~= nil)
local auras = Collection.ownedIds(Config.Auras, ctx({ rebirths = 3, passes = {} }))
check("Nebula + Gilded earned by ascending", table.find(auras, "nebula") ~= nil and table.find(auras, "gilded") ~= nil)
check("Umbral needs Mordrak x5 or DarkArts", table.find(Collection.ownedIds(Config.Auras, ctx({ passes = { DarkArts = true } })), "umbral") ~= nil and table.find(auras, "umbral") == nil)

if fails == 0 then
	print("COLLECTION CHECKS PASSED")
else
	error(fails .. " collection check(s) failed")
end
