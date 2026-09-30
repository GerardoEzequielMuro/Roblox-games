--!strict
-- Skins, mounts and the epic / legendary exclusive auras. Everything here is unlocked two
-- ways (Shared/Collection): by progression (`earn`) or by owning the matching pass. The
-- sync runs on join, after boss kills / ascensions / arena wins, when a pass changes and every
-- 20 s as a safety net. Purely cosmetic: no stats except the aura's training multiplier that
-- already existed for every aura.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Collection = require(ReplicatedStorage.Shared.Collection)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)
local M = Locale.m

local Cosmetics = {}

-- Adds everything the player now qualifies for. Returns how many items were new.
function Cosmetics.sync(player: Player, silent: boolean?): number
	local p = Data.get(player)
	if not p or not State.ready[player] then
		return 0
	end
	State.refreshPasses(player)
	local ctx = State.collectionCtx(player, p)
	local added = 0
	local function give(kind: string, id: string)
		added += 1
		if not silent then
			Remotes.notify(player, M("msg.cosmetic_unlocked", { name = M(kind .. "." .. id) }), "success")
		end
	end
	for _, id in Collection.ownedIds(Config.Skins, ctx) do
		if not p.skins[id] then
			p.skins[id] = true
			give("skin", id)
		end
	end
	for _, id in Collection.ownedIds(Config.Mounts, ctx) do
		if not p.mounts[id] then
			p.mounts[id] = true
			give("mount", id)
		end
	end
	for _, def in Config.Auras do
		if def.exclusive and (def.pass ~= nil or def.earn ~= nil) and not p.auras[def.id] and Collection.owned(def, ctx) then
			p.auras[def.id] = 1
			give("aura", def.id)
		end
	end
	if added > 0 then
		State.dirty(player)
	end
	return added
end

function Cosmetics.applyAttributes(player: Player)
	local p = Data.get(player)
	local char = player.Character
	if p and char then
		char:SetAttribute("Skin", p.skin)
		char:SetAttribute("Mount", p.mount)
	end
end

function Cosmetics.init()
	State.extras.cosmetics = function(_player, p)
		return { skins = p.skins, skin = p.skin, mounts = p.mounts, mount = p.mount }
	end

	local function equipHandler(field: string, ownedField: string, known: { [string]: any })
		return function(player: Player, payload: any): (boolean, any?)
			local p = Data.get(player)
			local id = payload.id
			if not p or type(id) ~= "string" then
				return false, M("msg.bad_request")
			end
			if id ~= "" and (not known[id] or not (p :: any)[ownedField][id]) then
				return false, M("msg.not_owned")
			end
			(p :: any)[field] = id
			Cosmetics.applyAttributes(player)
			State.dirty(player)
			return true, nil
		end
	end
	Remotes.handle("EquipSkin", equipHandler("skin", "skins", Config.SkinById))
	Remotes.handle("EquipMount", equipHandler("mount", "mounts", Config.MountById))

	for _, hook in { "npcKilled", "rebirth", "arenaWin", "travel" } do
		Hooks.on(hook, function(player: Player)
			task.defer(Cosmetics.sync, player)
		end)
	end
	task.spawn(function()
		while true do
			task.wait(20)
			for _, player in Players:GetPlayers() do
				Cosmetics.sync(player)
			end
		end
	end)
end

function Cosmetics.onReady(player: Player)
	Cosmetics.sync(player, true)
	Cosmetics.applyAttributes(player)
end

return Cosmetics
