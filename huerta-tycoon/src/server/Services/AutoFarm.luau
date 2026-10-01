--!strict
-- Auto-farm: the server harvests, replants and sells for players who unlocked and switched it on.
-- One loop for every player (1 Hz); each player's work rounds are paced by AutoFarm.interval/batch, so it keeps
-- going while they are AFK and no client can make it run faster.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.AutoFarm)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Validate = require(script.Parent.Parent.Security.Validate)
local Garden = require(script.Parent.Garden)

local AutoFarm = {}

export type Result = { harvested: number, planted: number, sold: number }

-- One work round right now (no pacing): harvest up to a batch of ripe tiles, sell a full basket, replant up to a
-- batch of empty tiles with the chosen seed.
function AutoFarm.step(s: Session.S): Result
	local res: Result = { harvested = 0, planted = 0, sold = 0 }
	if s.plotIndex == 0 then
		return res
	end
	local info = Session.autoInfo(s)
	local p = s.profile
	local tiles = p.tiles :: any
	if info.on.harvest then
		for i = 1, p.tilesOwned do
			if res.harvested >= info.batch then
				break
			end
			local t = tiles[tostring(i)]
			if t and t.progress >= 1 then
				if Garden.harvest(s, i, true) then
					res.harvested += 1
				else
					break -- basket full
				end
			end
		end
	end
	if info.on.sell then
		local count = Session.backpackCount(s)
		if Rules.shouldSell(count, Session.backpackCap(s), Config.AutoFarm) and Garden.sell(s, true) then
			res.sold = count
		end
	end
	if info.on.plant and info.seed ~= "" and Config.SeedById[info.seed] then
		for i = 1, p.tilesOwned do
			if res.planted >= info.batch or (p.seeds[info.seed] or 0) <= 0 then
				break
			end
			if not tiles[tostring(i)] and Garden.plant(s, i, info.seed) then
				res.planted += 1
			end
		end
	end
	if res.harvested > 0 or res.planted > 0 or res.sold > 0 then
		Session.markDirty(s)
	end
	return res
end

-- Paced work round: does nothing until the player's interval has passed since their last round.
function AutoFarm.tick(s: Session.S, now: number): Result?
	local info = Session.autoInfo(s)
	if not Rules.any(info.on) or not Rules.due(s.autoAt, now, info.interval) then
		return nil
	end
	s.autoAt = now
	return AutoFarm.step(s)
end

function AutoFarm.run()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, s in Session.sessions do
				local ok, err = pcall(AutoFarm.tick, s, now)
				if not ok then
					warn("[AutoFarm]", err)
				end
			end
		end
	end)
end

Remotes.handle("SetAuto", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	if not Rules.isMode(payload.mode) or Validate.bool(payload.on) == nil then
		return false, R("err.badRequest")
	end
	local mode = payload.mode :: string
	local info = Session.autoInfo(s)
	if payload.on and not (info.allowed :: any)[mode] then
		return false, R("err.autoLocked", { n = Rules.requiredLevel(Config.AutoFarm, mode) })
	end
	local saved = Rules.sanitize(s.profile.auto);
	(saved :: any)[mode] = payload.on
	s.profile.auto = saved
	Session.markDirty(s)
	return true
end)

Remotes.handle("SetAutoSeed", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	if not Validate.key(payload.seedId, Config.SeedById) then
		return false, R("err.unknownSeed")
	end
	local saved = Rules.sanitize(s.profile.auto)
	if saved.seed ~= payload.seedId then
		saved.seed = payload.seedId
		s.profile.auto = saved
		Session.markDirty(s)
	end
	return true
end)

return AutoFarm
