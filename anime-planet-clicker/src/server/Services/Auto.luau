--!strict
-- The one server loop behind every "auto" and every per-player timer. Runs every
-- Config.AutoTick: Auto Mine, respawns, the Cargo Drone and hand sales, Auto Open; and once
-- a second: buffs, play time, walk speed, Auto Upgrade, Auto Rebirth and the anti-trespass
-- check. Everything is decided here on the server, so autos keep working while the player
-- is AFK and no client can speed them up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local M = Locale.m
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Mining = require(script.Parent.Mining)
local Capsules = require(script.Parent.Capsules)
local Progression = require(script.Parent.Progression)
local Hooks = require(script.Parent.Hooks)

local Auto = {}

-- Test hook: counts loop iterations so the playtest can prove there is exactly one loop.
Auto.ticks = 0

local function second(player: Player, p: Data.Profile)
	p.playTime += 1
	State.giftElapsed(player, p) -- keeps today's played time in the profile
	-- timed buffs
	local ended = false
	for id, left in p.buffs do
		if left > 0 then
			local now = left - 1
			p.buffs[id] = math.max(0, now)
			if now <= 0 then
				ended = true
				Remotes.notify(player, M("msg.buff_ended", { buff = M("buff." .. id) }), "info")
			end
		end
	end
	if ended then
		State.dirty(player)
	end
	Progression.applyWalkSpeed(player)
	if p.auto.upgrade then
		Progression.autoUpgrade(player, p)
	end
	if p.auto.rebirth then
		Progression.autoRebirth(player, p)
	end
	-- nobody stands in a galaxy they have not unlocked
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root then
		local zone = Layout.zoneAt(root.Position.X, root.Position.Z)
		if zone and not State.hasZone(p, zone) then
			Progression.teleportTo(player, Layout.spawnPoint(State.maxZone(p)))
			Remotes.notify(player, M("msg.zone_locked", { zone = M("zone." .. Config.Zones[zone].id) }), "error")
		end
	end
	Hooks.fire("second", player)
end

function Auto.step(dt: number, wholeSecond: boolean)
	Auto.ticks += 1
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p and State.ready[player] then
			local ok, err = pcall(function()
				Mining.autoStep(player, p, dt)
				Mining.step(player, p, dt)
				Capsules.autoStep(player, p)
				if wholeSecond then
					second(player, p)
				end
			end)
			if not ok then
				warn("[Auto]", player.Name, err)
			end
		end
	end
end

function Auto.init()
	task.spawn(function()
		local acc = 0
		local last = os.clock()
		while true do
			task.wait(Config.AutoTick)
			local now = os.clock()
			local dt = math.min(now - last, 1)
			last = now
			acc += dt
			local whole = acc >= 1
			if whole then
				acc -= 1
			end
			Auto.step(dt, whole)
		end
	end)
end

return Auto
