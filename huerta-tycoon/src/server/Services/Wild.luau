--!strict
-- The Wild Patch: rare seeds that regrow every hour in a corner of the map (rules in Shared/Wild).
-- The server builds the ripe plants on the patch nodes and hands out one seed per node, per player, per cycle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Wild)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local CropVisuals = require(script.Parent.Parent.World.CropVisuals)

local Wild = {}

Wild.PICK_RANGE = 24
local nodes: { Part } = {}
local builtCycle = -1
local seeds: { string } = {}

function Wild.cycle(): number
	return builtCycle
end

function Wild.seedAt(index: number): string?
	return seeds[index]
end

local function build(cycle: number)
	builtCycle = cycle
	seeds = Rules.nodes(cycle)
	for i, node in nodes do
		local old = node:FindFirstChild("Crop")
		if old then
			old:Destroy()
		end
		local seed = Config.SeedById[seeds[i]]
		if seed then
			local model = CropVisuals.buildModel(node.CFrame * CFrame.new(0, node.Size.Y / 2, 0), seed, CropVisuals.STAGES, nil)
			model.Parent = node
		end
		node:SetAttribute("SeedId", seeds[i])
	end
end

-- Gives the player the seed growing on a node (once per node per cycle).
function Wild.pick(s: Session.S, index: any): (boolean, Locale.Ref?)
	local now = os.time()
	local cycle = Rules.cycle(now)
	if cycle ~= builtCycle then
		build(cycle)
	end
	if type(index) ~= "number" or not seeds[index] then
		return false, R("err.badRequest")
	end
	if not Rules.canClaim(s.profile.wild, cycle, index) then
		return false, R("err.wildTaken", { time = Format.time(Rules.nextAt(now) - now) })
	end
	local seedId = seeds[index]
	s.profile.wild = Rules.claim(s.profile.wild, cycle, index)
	s.profile.seeds[seedId] = (s.profile.seeds[seedId] or 0) + 1
	Session.markDirty(s)
	return true, R("msg.wildPicked", { seed = Locale.seedName(seedId) })
end

function Wild.init(patchNodes: { Part })
	nodes = patchNodes
	build(Rules.cycle(os.time()))
	for i, node in nodes do
		local prompt = node:FindFirstChild("Prompt") :: ProximityPrompt?
		if prompt then
			prompt.Triggered:Connect(function(player)
				local s = Session.get(player)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not s or not root or (root.Position - node.Position).Magnitude > Wild.PICK_RANGE then
					return
				end
				local ok, msg = Wild.pick(s, i)
				if msg then
					Remotes.notify(player, msg, if ok then "success" else "error")
				end
			end)
		end
	end
end

function Wild.run()
	task.spawn(function()
		while true do
			task.wait(1)
			local cycle = Rules.cycle(os.time())
			if cycle ~= builtCycle then
				build(cycle)
				Remotes.notifyAll(R("msg.wildRegrew"), "info")
				for _, s in Session.sessions do
					Session.markDirty(s)
				end
			end
		end
	end)
end

return Wild
