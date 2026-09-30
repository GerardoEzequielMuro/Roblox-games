--!strict
-- Earn-or-buy rules for everything that can be unlocked two ways (skins, mounts, epic auras,
-- special forms and dark techniques, Time Chamber). Pure Luau (server, client UI and tests).
--   req  = { boss = "npc_id", count = N, rebirths = N, pvpKills = N, planet = N, power = N }
--          every field present must hold (AND). Unused fields are ignored.
--   def  = { pass = "PassKey"?, earn = req? }   owned when the pass is owned OR earn holds.
local Config: any = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Collection = {}

export type Ctx = {
	passes: { [string]: boolean },
	bossKills: { [string]: number },
	rebirths: number,
	pvpKills: number,
	planet: number, -- best planet index reached
	power: number, -- best power
}

function Collection.earned(req: any, ctx: Ctx): boolean
	if req == nil then
		return false
	end
	if req.boss ~= nil and (ctx.bossKills[req.boss] or 0) < (req.count or 1) then
		return false
	end
	if req.rebirths ~= nil and ctx.rebirths < req.rebirths then
		return false
	end
	if req.pvpKills ~= nil and ctx.pvpKills < req.pvpKills then
		return false
	end
	if req.planet ~= nil and ctx.planet < req.planet then
		return false
	end
	if req.power ~= nil and ctx.power < req.power then
		return false
	end
	return true
end

-- Returns owned, via ("pass" | "earn" | nil).
function Collection.owned(def: any, ctx: Ctx): (boolean, string?)
	if def.pass ~= nil and ctx.passes[def.pass] == true then
		return true, "pass"
	end
	if Collection.earned(def.earn, ctx) then
		return true, "earn"
	end
	return false, nil
end

-- Special forms / techniques (`special = { boss, count, pass }`): the boss requirement is
-- skipped by the pass. Power and ascension requirements stay in Config and apply to both.
function Collection.specialOk(special: any, ctx: Ctx): boolean
	if special == nil then
		return true
	end
	if special.pass ~= nil and ctx.passes[special.pass] == true then
		return true
	end
	return (ctx.bossKills[special.boss] or 0) >= (special.count or 1)
end

-- Adds the passes implied by bundles (DoubleBundle -> DoubleTraining + DoubleSparks) and the
-- ones that can be earned (TimeChamber after 2 ascensions). Returns a NEW table.
function Collection.expandPasses(owned: { [string]: boolean }, ctx: Ctx?): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for k, v in owned do
		out[k] = v
	end
	for _, pass in Config.Passes do
		if out[pass.key] and pass.implies then
			for _, key in pass.implies do
				out[key] = true
			end
		end
	end
	if ctx then
		for _, pass in Config.Passes do
			if not out[pass.key] and pass.earn and Collection.earned(pass.earn, ctx) then
				out[pass.key] = true
			end
		end
	end
	return out
end

-- Everything in a list (Config.Skins / Mounts / Auras) that `ctx` owns.
function Collection.ownedIds(list: { any }, ctx: Ctx): { string }
	local ids = {}
	for _, def in list do
		if (def.pass ~= nil or def.earn ~= nil) and Collection.owned(def, ctx) then
			table.insert(ids, def.id)
		end
	end
	return ids
end

return Collection
