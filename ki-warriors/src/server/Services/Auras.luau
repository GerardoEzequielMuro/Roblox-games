--!strict
-- Auras: a spin with published odds (Config.Auras weights = percent, they add up to 100),
-- equipping, and the paid-random-items policy check. A spin always gives an aura. Spins cost
-- a banked free spin, the free daily spin, or Gems; the Gems path and the Lucky Aura pass are
-- unavailable where PolicyService says paid random items are restricted.
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local Auras = {}

local rng = Random.new()

local function today(): number
	return os.time() // 86400
end

local function lucky(player: Player): boolean
	return State.owns(player, "LuckyAura") and not State.randomRestricted[player]
end

function Auras.give(player: Player, id: string)
	local p = Data.get(player)
	if p and Config.AuraById[id] then
		p.auras[id] = (p.auras[id] or 0) + 1
		State.dirty(player)
	end
end

local function equip(player: Player, p: Data.Profile, id: string)
	p.auraEquipped = id
	local char = player.Character
	if char then
		char:SetAttribute("Aura", id)
	end
	State.dirty(player)
end

-- Test hook: mark the player as living where paid random items are restricted.
function Auras.setRestricted(player: Player, restricted: boolean): boolean
	State.randomRestricted[player] = restricted
	State.dirty(player)
	return true
end

function Auras.onReady(player: Player)
	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == true then
			State.randomRestricted[player] = true
			State.dirty(player)
		end
	end)
end

function Auras.init()
	State.extras.auraSpin = function(player, p)
		return {
			odds = Formulas.auraOdds(lucky(player)),
			freeToday = p.freeSpinDay ~= today(),
			cost = Config.AuraSpin.gems,
			lucky = lucky(player),
		}
	end

	Remotes.handle("SpinAura", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false, M("msg.error")
		end
		local paid = payload.paid == true
		if paid then
			if State.randomRestricted[player] then
				return false, M("msg.spin_restricted")
			end
			if not State.spendGems(player, Config.AuraSpin.gems) then
				return false, M("msg.need_gems")
			end
		elseif p.freeSpinDay ~= today() then
			p.freeSpinDay = today()
		elseif p.spins > 0 then
			p.spins -= 1
		else
			return false, M("msg.no_spins")
		end
		local id = Formulas.rollAura(rng:NextNumber(), lucky(player))
		local isNew = p.auras[id] == nil
		p.auras[id] = (p.auras[id] or 0) + 1
		-- first aura ever (or a better one than the equipped): equip it
		local cur = Config.AuraById[p.auraEquipped]
		local got = Config.AuraById[id]
		if not cur or got.mult > cur.mult then
			equip(player, p, id)
		end
		Hooks.fire("auraSpin", player, id)
		local rarity = Config.RarityByName[got.rarity]
		if rarity.order >= 5 then
			Remotes.fireAll("Toast", { key = "toast.aura_rare", args = { player = player.DisplayName, aura = { key = "aura." .. id }, rarity = { key = "rarity." .. got.rarity } }, color = rarity.color })
		end
		State.dirty(player)
		return true, { id = id, new = isNew, rarity = got.rarity }
	end)

	Remotes.handle("EquipAura", function(player, payload)
		local p = Data.get(player)
		local id = payload.id
		if not p or type(id) ~= "string" then
			return false, M("msg.bad_request")
		end
		if id ~= "" and not p.auras[id] then
			return false, M("msg.not_owned")
		end
		equip(player, p, id)
		return true
	end)
end

return Auras
