--!strict
-- The mining tool in everyone's hand (from the replicated "Tool" attribute) and its motion:
-- the arm comes up and swings while the player mines, drill bits spin, lasers fire a beam
-- (a stretched part, so it still shows at graphics quality 1) at the planet being mined.
-- Client-side only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Palette = require(ReplicatedStorage.Shared.Palette)
local ToolModel = require(ReplicatedStorage.Shared.ToolModel)

local ToolFx = {}

type Rig = {
	toolId: string,
	char: Model,
	model: Model,
	handle: BasePart,
	grip: Weld,
	bit: Weld?,
	kind: string,
	color: Color3,
	beam: Part,
	swingAt: number,
	shoulder: Motor6D?,
}

local rigs: { [Player]: Rig } = {}
local localPlayer = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "ClientTools"
folder.Parent = Workspace

local function drop(player: Player)
	local rig = rigs[player]
	if rig then
		rig.model:Destroy()
		rig.beam:Destroy()
		rigs[player] = nil
	end
end

local function equip(player: Player)
	local char = player.Character
	local toolId = player:GetAttribute("Tool")
	if not char or type(toolId) ~= "string" or not Config.ToolById[toolId] then
		drop(player)
		return
	end
	local old = rigs[player]
	if old and old.toolId == toolId and old.char == char and old.model.Parent then
		return
	end
	drop(player)
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	if not hand then
		return
	end
	local model = ToolModel.build(toolId)
	local handle = model.PrimaryPart :: BasePart
	local r6 = hand.Name == "Right Arm"
	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = if r6 then CFrame.new(0, -1, -0.2) * CFrame.Angles(math.rad(-90), 0, 0) else CFrame.new(0, -0.15, -0.1) * CFrame.Angles(math.rad(-90), 0, 0)
	grip.Parent = handle
	-- drill bit: swap its rigid weld for one we can turn
	local bitWeld: Weld? = nil
	local bit = model:FindFirstChild("Bit") :: BasePart?
	if bit then
		local rigid = bit:FindFirstChildOfClass("WeldConstraint")
		if rigid then
			rigid:Destroy()
		end
		local w = Instance.new("Weld")
		w.Name = "Spin"
		w.Part0 = handle
		w.Part1 = bit
		w.C0 = handle.CFrame:ToObjectSpace(bit.CFrame)
		w.Parent = bit
		bitWeld = w
	end
	model.Parent = char
	local def = Config.ToolById[toolId]
	local beam = Instance.new("Part")
	beam.Name = "MiningBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Palette.rgb(def.color):Lerp(Color3.new(1, 1, 1), 0.3)
	beam.Transparency = 1
	beam.Size = Vector3.new(0.4, 0.4, 1)
	beam.Parent = folder
	local upper = char:FindFirstChild("RightUpperArm")
	rigs[player] = {
		toolId = toolId,
		char = char,
		model = model,
		handle = handle,
		grip = grip,
		bit = bitWeld,
		kind = def.kind,
		color = Palette.rgb(def.color),
		beam = beam,
		swingAt = -10,
		shoulder = if upper then upper:FindFirstChild("RightShoulder") :: Motor6D? else nil,
	}
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Tool"):Connect(function()
		equip(player)
	end)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 10)
		task.wait(0.5)
		equip(player)
	end)
	task.spawn(equip, player)
end

-- A hit by the local player: swing now.
function ToolFx.swing()
	local rig = rigs[localPlayer]
	if rig then
		rig.swingAt = os.clock()
	end
end

function ToolFx.has(player: Player?): boolean
	local rig = rigs[player or localPlayer]
	return rig ~= nil and rig.model.Parent ~= nil
end

local function targetOf(player: Player): Vector3?
	local v = player:GetAttribute("MineNode")
	if type(v) ~= "number" then
		return nil
	end
	local zone, n = v // 100, v % 100
	if not Config.Zones[zone] then
		return nil
	end
	local p = Layout.nodePosition(zone, n)
	return Vector3.new(p[1], p[2], p[3])
end

function ToolFx.init()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(drop)

	-- after the Animator: lift the tool arm towards the planet while mining
	RunService.Stepped:Connect(function()
		local now = os.clock()
		for player, rig in rigs do
			local shoulder = rig.shoulder
			if not shoulder or not shoulder.Parent then
				continue
			end
			local target = targetOf(player)
			local swingT = now - rig.swingAt
			if target or swingT < 0.5 then
				local lift = 1.35
				local swing = 0
				if rig.kind == "pick" then
					-- others: a steady chopping motion; local: one chop per hit
					swing = if player == localPlayer and swingT < 0.22 then math.sin(swingT / 0.22 * math.pi) * 0.9 else (if player ~= localPlayer then math.abs(math.sin(now * 7)) * 0.7 else 0)
				else
					swing = math.sin(now * 40) * 0.03
				end
				shoulder.Transform = CFrame.Angles(lift - swing, 0, 0)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for player, rig in rigs do
			local target = targetOf(player)
			local swingT = now - rig.swingAt
			local active = target ~= nil or swingT < 0.4
			if rig.bit and active then
				rig.bit.C0 *= CFrame.Angles(0, 0, 0.6)
			end
			local beam = rig.beam
			if rig.kind == "laser" and target and rig.handle.Parent then
				local tip = rig.handle.CFrame:PointToWorldSpace(Vector3.new(0, 0, -3.9))
				local dist = (target - tip).Magnitude
				if dist > 1 and dist < 140 then
					local w = 0.34 + math.abs(math.sin(now * 30)) * 0.22
					beam.Size = Vector3.new(w, w, dist)
					beam.CFrame = CFrame.lookAt(tip, target) * CFrame.new(0, 0, -dist / 2)
					beam.Transparency = 0.1
				else
					beam.Transparency = 1
				end
			elseif beam.Transparency < 1 then
				beam.Transparency = 1
			end
		end
	end)
end

return ToolFx
