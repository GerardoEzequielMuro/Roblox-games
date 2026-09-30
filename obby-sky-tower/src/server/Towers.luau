--!strict
-- The ten towers, built on demand. 1,000 stages never sit in Workspace at once: tower 1 (the one
-- over the lobby) is always there, and towers 2..10 exist only while somebody is climbing them or
-- is about to arrive (the last ten stages of the tower before, or its summit). A tower nobody
-- needs is destroyed after Config.TowerIdleSeconds.
--
-- Rules.towersNeeded decides who needs what; a player never needs more than two towers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Data = require(script.Parent.Data)
local Session = require(script.Parent.Session)
local StageGenerator = require(script.Parent.StageGenerator)
local Obstacles = require(script.Parent.Obstacles)

local Towers = {}

Towers.IDLE_SECONDS = 75
Towers.SWEEP_SECONDS = 15

local built: { [number]: StageGenerator.Tower } = {}
local building: { [number]: boolean } = {}
local lastNeeded: { [number]: number } = {}
local onBuilt: { (StageGenerator.Tower) -> () } = {}
local builtCount, releasedCount = 0, 0

-- Called for every tower right after it is built (Checkpoints wires pads, prompts and the portal).
function Towers.onBuilt(fn: (StageGenerator.Tower) -> ())
	table.insert(onBuilt, fn)
	for _, tower in built do
		fn(tower)
	end
end

function Towers.get(t: number): StageGenerator.Tower?
	return built[t]
end

-- Returns the tower, building it first if needed (yields a few frames while it builds).
function Towers.ensure(t: number): StageGenerator.Tower
	t = math.clamp(math.floor(t), 1, Layout.TOWERS)
	lastNeeded[t] = os.clock()
	while building[t] do
		task.wait()
	end
	local existing = built[t]
	if existing then
		return existing
	end
	building[t] = true
	local ok, result = pcall(StageGenerator.buildTower, t)
	building[t] = nil
	if not ok then
		error(("tower %d failed to build: %s"):format(t, tostring(result)))
	end
	local tower = result :: StageGenerator.Tower
	built[t] = tower
	builtCount += 1
	Obstacles.add(tower.folder)
	for _, fn in onBuilt do
		fn(tower)
	end
	return tower
end

local function release(t: number)
	local tower = built[t]
	if not tower or t == 1 then
		return
	end
	built[t] = nil
	releasedCount += 1
	Obstacles.remove(tower.folder)
	tower.folder:Destroy()
end

-- The checkpoint pad of global stage g, if its tower is built.
function Towers.pad(g: number): BasePart?
	local spot = Rules.padOf(Layout :: any, g)
	local tower = built[spot.tower]
	return if tower then tower.pads[g] else nil
end

-- Where a character stands for a spawn spot (Rules.spawn). Builds the tower if needed (yields).
function Towers.standing(spot: Rules.Spot): CFrame
	local tower = Towers.ensure(spot.tower)
	if spot.pad == 0 then
		return tower.baseCFrame
	end
	return tower.padCFrames[(spot.tower - 1) * Layout.STAGES + spot.pad] or tower.baseCFrame
end

function Towers.needed(player: Player): { number }
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return { 1 }
	end
	return Rules.towersNeeded(Layout :: any, p.stage, math.max(s.at, p.stage), p.base)
end

-- Towers currently in Workspace, how many were built and released so far (performance probe).
function Towers.stats(): ({ number }, number, number)
	local list = {}
	for t in built do
		table.insert(list, t)
	end
	table.sort(list)
	return list, builtCount, releasedCount
end

function Towers.sweep()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		for _, t in Towers.needed(player) do
			lastNeeded[t] = now
			if not built[t] and not building[t] then
				task.spawn(Towers.ensure, t)
			end
		end
	end
	for t in built do
		if t ~= 1 and now - (lastNeeded[t] or 0) > Towers.IDLE_SECONDS then
			release(t)
		end
	end
end

function Towers.init()
	Towers.ensure(1)
	task.spawn(function()
		while true do
			task.wait(Towers.SWEEP_SECONDS)
			Towers.sweep()
		end
	end)
end

return Towers
