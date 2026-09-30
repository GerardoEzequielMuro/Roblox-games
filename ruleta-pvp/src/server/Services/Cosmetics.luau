--!strict
-- Cosmetics: what a player owns (bought / granted items plus everything their level, wins,
-- league and passes unlock), buying with coins, equipping, and the replicated attributes
-- other clients render from. Cosmetics never change a match.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local M = Locale.m

local Cosmetics = {}

local known: { [Player]: { [string]: boolean } } = {}

local function ctx(player: Player, p: Data.Profile): Progression.UnlockCtx
	return { level = p.level, wins = p.wins, bestStreak = p.bestStreak, bestTrophies = p.bestTrophies, passes = State.passes[player] or {} }
end

function Cosmetics.owns(player: Player, id: string): boolean
	local p = Data.get(player)
	local item = Config.CosmeticById[id]
	if not p or not item then
		return false
	end
	return p.owned[id] == true or Progression.unlocked(item.unlock, ctx(player, p))
end

function Cosmetics.ownedSet(player: Player): { [string]: boolean }
	local p = Data.get(player)
	local set: { [string]: boolean } = {}
	if not p then
		return set
	end
	local c = ctx(player, p)
	for _, item in Config.Cosmetics do
		if p.owned[item.id] or Progression.unlocked(item.unlock, c) then
			set[item.id] = true
		end
	end
	return set
end

-- Grants an item outright (codes, starter pack, daily, events). False if already owned.
function Cosmetics.grant(player: Player, id: string): boolean
	local p = Data.get(player)
	if not p or not Config.CosmeticById[id] or Cosmetics.owns(player, id) then
		return false
	end
	p.owned[id] = true
	State.dirty(player)
	return true
end

-- Attributes on the Player: other clients draw the wheel skin, title, aura... from these.
function Cosmetics.replicate(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	for kind, id in p.equipped do
		player:SetAttribute("Cos_" .. kind, id)
	end
	player:SetAttribute("Level", p.level)
	player:SetAttribute("League", Progression.league(p.trophies).id)
	player:SetAttribute("VIP", State.owns(player, "VIP"))
end

-- Tells the player about items that just became theirs through progress.
function Cosmetics.refresh(player: Player, silent: boolean?)
	local set = Cosmetics.ownedSet(player)
	local before = known[player]
	known[player] = set
	if before and not silent then
		for id in set do
			if not before[id] then
				Remotes.fire("Unlock", player, id)
			end
		end
	end
	Cosmetics.replicate(player)
end

function Cosmetics.forget(player: Player)
	known[player] = nil
end

function Cosmetics.init()
	State.extras.owned = function(player)
		return Cosmetics.ownedSet(player)
	end
	table.insert(State.onProgress, function(player)
		Cosmetics.refresh(player)
		State.dirty(player)
	end)

	Remotes.handle("Buy", function(player, payload)
		local p = Data.get(player)
		local item = if type(payload.id) == "string" then Config.CosmeticById[payload.id] else nil
		if not p or not item then
			return false, M("msg.bad_request")
		end
		if Cosmetics.owns(player, item.id) then
			return false, M("msg.already_owned")
		end
		if item.unlock.type ~= "coins" then
			return false, M("msg.not_for_sale")
		end
		if not State.spendCoins(player, item.unlock.n or 0) then
			return false, M("msg.not_enough_coins")
		end
		p.owned[item.id] = true
		Cosmetics.refresh(player, true)
		State.dirty(player)
		return true, M("msg.bought", { item = M("cos." .. item.id) })
	end)

	Remotes.handle("Equip", function(player, payload)
		local p = Data.get(player)
		local item = if type(payload.id) == "string" then Config.CosmeticById[payload.id] else nil
		if not p or not item or item.kind == "emote" then
			return false, M("msg.bad_request")
		end
		if not Cosmetics.owns(player, item.id) then
			return false, M("msg.locked")
		end
		p.equipped[item.kind] = item.id
		Cosmetics.replicate(player)
		State.dirty(player)
		return true
	end)

	-- The emote wheel: an ordered list of owned emotes.
	Remotes.handle("SetEmotes", function(player, payload)
		local p = Data.get(player)
		local list = payload.ids
		if not p or type(list) ~= "table" then
			return false, M("msg.bad_request")
		end
		local slots = if State.owns(player, "EmotePack") then Config.EmoteSlotsPack else Config.EmoteSlots
		local out = {}
		for i = 1, math.min(#list, slots) do
			local id = list[i]
			local item = if type(id) == "string" then Config.CosmeticById[id] else nil
			if item and item.kind == "emote" and Cosmetics.owns(player, id) and not table.find(out, id) then
				table.insert(out, id)
			end
		end
		if #out == 0 then
			return false, M("msg.bad_request")
		end
		p.emotes = out
		State.dirty(player)
		return true
	end)

	-- Emotes are shown by every client; rate limited here.
	Remotes.handle("Emote", function(player, payload)
		local p = Data.get(player)
		local id = payload.id
		if not p or type(id) ~= "string" or not table.find(p.emotes, id) or not Cosmetics.owns(player, id) then
			return false, M("msg.locked")
		end
		local now = os.clock()
		if now - (State.lastEmote[player] or 0) < Config.EmoteCooldown then
			return false, M("msg.slow_down")
		end
		State.lastEmote[player] = now
		Remotes.fireAll("Emote", player.UserId, id)
		return true
	end)
end

return Cosmetics
