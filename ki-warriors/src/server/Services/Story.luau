--!strict
-- Story: one linear chain of objectives (Config.Story). The first steps are the first-minute
-- tutorial. Progress comes from gameplay hooks; finishing a step pays its reward on the spot
-- and moves on. The client shows the current step in the tracker (p.story + Config.Story).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Hooks = require(script.Parent.Hooks)

local Story = {}

local dirty: { [Player]: boolean } = {}

local function current(p: Data.Profile): any
	return Config.Story[p.story.step]
end

local complete: (Player, Data.Profile) -> ()

-- Steps that are "reach a value" are checked against the current state.
local function evaluate(player: Player, p: Data.Profile)
	local step = current(p)
	if not step then
		return
	end
	local value: number? = nil
	if step.kind == "power" then
		value = math.max(State.power(p), p.bestPower)
	elseif step.kind == "gear" then
		value = p.gear
	elseif step.kind == "technique" then
		local n = 0
		for _ in p.techniques do
			n += 1
		end
		value = n
	elseif step.kind == "travel" then
		value = if table.find(p.planets, step.planet) then 1 else 0
	elseif step.kind == "rebirth" then
		value = p.rebirths
	elseif step.kind == "form" then
		-- needs actually transforming; handled by the hook
		value = nil
	end
	if value and value ~= p.story.progress then
		p.story.progress = math.min(value, step.target)
		dirty[player] = true
	end
	if p.story.progress >= step.target then
		complete(player, p)
	end
end

complete = function(player: Player, p: Data.Profile)
	local step = current(p)
	if not step then
		return
	end
	local index = p.story.step
	if step.sparks and step.sparks > 0 then
		State.addSparks(player, step.sparks, false)
	end
	if step.gems and step.gems > 0 then
		State.addGems(player, step.gems)
	end
	p.story.step = index + 1
	p.story.progress = 0
	Remotes.fire("Quests", player, { storyDone = index, sparks = step.sparks or 0, gems = step.gems or 0 })
	Hooks.fire("storyStep", player, index)
	State.dirty(player)
	-- the next step may already be satisfied (e.g. "reach 150 power")
	evaluate(player, p)
end

local function add(player: Player, kind: string, amount: number, match: ((any) -> boolean)?)
	local p = Data.get(player)
	if not p then
		return
	end
	local step = current(p)
	if not step or step.kind ~= kind or (match and not match(step)) then
		return
	end
	p.story.progress = math.min(step.target, p.story.progress + amount)
	dirty[player] = true
	if p.story.progress >= step.target then
		complete(player, p)
	end
end
Story.add = add

function Story.onJoin(player: Player)
	local p = Data.get(player)
	if p then
		evaluate(player, p)
	end
end

function Story.init()
	Hooks.on("reps", function(player: Player, n: number, _stat: string, zone: string)
		add(player, "reps", n)
		add(player, "zone", n, function(step)
			return step.zone == zone
		end)
		local p = Data.get(player)
		if p and current(p) and current(p).kind == "power" then
			evaluate(player, p)
		end
	end)
	Hooks.on("blast", function(player: Player)
		add(player, "blasts", 1)
	end)
	Hooks.on("charge", function(player: Player)
		add(player, "charge", 1)
	end)
	Hooks.on("fly", function(player: Player)
		add(player, "fly", 1)
	end)
	Hooks.on("beam", function(player: Player)
		add(player, "beam", 1)
	end)
	Hooks.on("dash", function(player: Player)
		add(player, "dash", 1)
	end)
	Hooks.on("form", function(player: Player)
		add(player, "form", 1)
	end)
	Hooks.on("relic", function(player: Player)
		add(player, "relic", 1)
	end)
	Hooks.on("npcKilled", function(player: Player, npcId: string, def: any)
		add(player, if def.boss then "boss" else "defeat", 1, function(step)
			return step.npc == npcId
		end)
	end)
	for _, name in { "gear", "techniqueBought", "travel", "rebirth" } do
		Hooks.on(name, function(player: Player)
			local p = Data.get(player)
			if p then
				evaluate(player, p)
			end
		end)
	end

	-- progress pushes (throttled: reps update it several times a second)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				if dirty[player] and State.ready[player] then
					dirty[player] = nil
					local p = Data.get(player)
					if p then
						Remotes.fire("Quests", player, { story = { step = p.story.step, progress = p.story.progress } })
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

return Story
