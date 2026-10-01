--!strict
-- Trophy shelf: put a Big / Giant / mutated crop from the basket on one of the plot's pedestals instead of
-- selling it. Every trophy gives luck while it stays there (rules in Shared/Trophies).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Trophies)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Validate = require(script.Parent.Parent.Security.Validate)
local Garden = require(script.Parent.Garden)

local Trophies = {}

function Trophies.exhibit(s: Session.S, key: any): (boolean, Locale.Ref?)
	local p = s.profile
	if not Validate.str(key, 96) or (p.backpack[key :: string] or 0) <= 0 then
		return false, R("err.badRequest")
	end
	local seed, mut, size = Rules.split(key)
	local verdict = Rules.canExhibit(#p.trophies, mut, size)
	if verdict == "plain" then
		return false, R("err.trophyPlain")
	elseif verdict == "full" then
		return false, R("err.trophyFull")
	end
	local left = (p.backpack[key] or 0) - 1
	(p.backpack :: any)[key] = if left > 0 then left else nil
	table.insert(p.trophies, { seed = seed, mut = mut, size = size })
	Garden.renderTrophies(s)
	Session.markDirty(s)
	return true, R("msg.exhibited", { pct = math.floor(Session.trophyLuck(s) * 100 + 0.5) })
end

function Trophies.takeBack(s: Session.S, slot: any): (boolean, Locale.Ref?)
	local p = s.profile
	local n = Validate.integer(slot, 1, Rules.SLOTS)
	if not n or not p.trophies[n] then
		return false, R("err.badRequest")
	end
	if Session.backpackCount(s) >= Session.backpackCap(s) then
		return false, R("err.basketFull")
	end
	local item = table.remove(p.trophies, n) :: any
	local key = Rules.key(item.seed, item.mut, item.size)
	p.backpack[key] = (p.backpack[key] or 0) + 1
	Garden.renderTrophies(s)
	Session.markDirty(s)
	return true, R("msg.unexhibited")
end

Remotes.handle("Exhibit", function(player, payload)
	local s = Session.get(player)
	if not s or s.plotIndex == 0 then
		return false, R("err.loading")
	end
	return Trophies.exhibit(s, payload.key)
end)

Remotes.handle("Unexhibit", function(player, payload)
	local s = Session.get(player)
	if not s or s.plotIndex == 0 then
		return false, R("err.loading")
	end
	return Trophies.takeBack(s, payload.slot)
end)

return Trophies
