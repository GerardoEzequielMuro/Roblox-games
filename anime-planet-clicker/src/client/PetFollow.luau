--!strict
-- Renders every player's equipped pets (from the replicated "EquippedPets" attribute).
-- Client-side only. Pets follow in an arc behind their owner; while the owner is mining
-- (replicated "MineNode" attribute) they fly to the planet, circle it and dart in to peck.
-- Walkers hop, flyers hover and flap, tails wag, orbit gems turn, each pet drops a blob shadow.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Net = require(script.Parent.Net)
local Quality = require(script.Parent.Quality)

local PetFollow = {}

type JointAnim = { weld: Weld, base: CFrame, kind: string, side: number, radius: number, height: number, phase: number }
type Pet = {
	model: Model,
	shadow: BasePart,
	joints: { JointAnim },
	pos: Vector3?,
	yaw: number,
	phase: number,
	hop: number,
	tapAt: number,
	footY: number,
	size: number,
	flyer: boolean,
	rainbow: boolean,
	seed: number,
}
type Rig = { key: string, pets: { Pet } }

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = Workspace

local rigs: { [Player]: Rig } = {}
local CULL_DISTANCE = 240
local ANIM_DISTANCE = 100
local localPlayer = Players.LocalPlayer
local pulseIndex = 0

local function destroyPet(pet: Pet)
	pet.model:Destroy()
	pet.shadow:Destroy()
end

local function clear(player: Player)
	local rig = rigs[player]
	if rig then
		for _, pet in rig.pets do
			destroyPet(pet)
		end
		rigs[player] = nil
	end
end

local function makeShadow(): BasePart
	local p = Instance.new("Part")
	p.Name = "PetShadow"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(12, 10, 24)
	p.Transparency = 0.6
	p.Size = Vector3.new(0.08, 2, 2)
	return p
end

local function makePet(id: string, tier: number, isLocal: boolean, index: number): Pet
	local model = PetModel.build(id, tier, { lights = isLocal, lite = Quality.lite or not isLocal })
	local joints: { JointAnim } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Joint" then
			table.insert(joints, {
				weld = d,
				base = d.C0,
				kind = d:GetAttribute("Anim") :: string,
				side = (d:GetAttribute("Side") :: number?) or 1,
				radius = (d:GetAttribute("Radius") :: number?) or 0,
				height = (d:GetAttribute("Height") :: number?) or 0,
				phase = (d:GetAttribute("Phase") :: number?) or 0,
			})
		end
	end
	local shadow = makeShadow()
	shadow.Parent = folder
	model.Parent = folder
	return {
		model = model,
		shadow = shadow,
		joints = joints,
		pos = nil,
		yaw = 0,
		phase = index * 1.7,
		hop = 0,
		tapAt = -10,
		footY = (model:GetAttribute("FootY") :: number?) or -1.3,
		size = (model:GetAttribute("Size") :: number?) or 1,
		flyer = model:GetAttribute("Flyer") == true,
		rainbow = model:GetAttribute("Rainbow") == true,
		seed = index * 1.3,
	}
end

local function hidden(player: Player): boolean
	if player == localPlayer then
		return false
	end
	local s = Net.state
	return s ~= nil and s.settings ~= nil and s.settings.hidePets == true
end

local function rebuild(player: Player, force: boolean?)
	local key = player:GetAttribute("EquippedPets")
	local keyStr = if type(key) == "string" and not hidden(player) then key else ""
	local rig = rigs[player]
	if rig and rig.key == keyStr and not force then
		return
	end
	local old: { Pet } = if rig then rig.pets else {}
	local newRig: Rig = { key = keyStr, pets = {} }
	local index = 0
	for entry in keyStr:gmatch("[^,]+") do
		local id, tier = entry:match("^(.-):(%d)$")
		if id then
			index += 1
			local pet = makePet(id, tonumber(tier) or 0, player == localPlayer, index)
			local prev = old[index]
			if prev then
				pet.pos = prev.pos
				pet.yaw = prev.yaw
			end
			table.insert(newRig.pets, pet)
		end
	end
	for _, pet in old do
		destroyPet(pet)
	end
	rigs[player] = newRig
end

local function watch(player: Player)
	rebuild(player)
	player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		rebuild(player)
	end)
end

-- Slot i of n: arc behind the player, second row when > 6 pets.
local function slotOffset(i: number, n: number): Vector3
	local perRow = 6
	local row = (i - 1) // perRow
	local inRow = math.min(perRow, n - row * perRow)
	local idx = (i - 1) % perRow
	local spread = math.rad(32)
	local angle = (idx - (inRow - 1) / 2) * spread
	local radius = 6.5 + row * 4
	return Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- The local player's pets peck, one after another, on every hit.
function PetFollow.pulse()
	local rig = rigs[localPlayer]
	if not rig or #rig.pets == 0 then
		return
	end
	pulseIndex = pulseIndex % #rig.pets + 1
	rig.pets[pulseIndex].tapAt = os.clock()
end

function PetFollow.count(player: Player?): number
	local rig = rigs[player or localPlayer]
	return if rig then #rig.pets else 0
end

local PECK = 0.28

local function animateJoints(pet: Pet, now: number, moving: boolean)
	for _, j in pet.joints do
		if j.kind == "Wing" then
			local a = if pet.flyer then math.sin(now * 11 + pet.seed) * 0.55 elseif moving or pet.hop > 0.1 then math.sin(now * 16 + pet.seed) * 0.5 else math.sin(now * 2 + pet.seed) * 0.06
			j.weld.C0 = j.base * CFrame.Angles(0, 0, j.side * a)
		elseif j.kind == "Tail" then
			j.weld.C0 = j.base * CFrame.Angles(0, math.sin(now * (if moving then 11 else 5) + pet.seed) * 0.38, 0)
		elseif j.kind == "Ear" then
			j.weld.C0 = j.base * CFrame.Angles(0, 0, j.side * (math.sin(now * 3 + pet.seed) * 0.06 + pet.hop * 0.22))
		elseif j.kind == "Orbit" then
			j.weld.C0 = CFrame.Angles(0, now * 2.2 + j.phase, 0) * CFrame.new(j.radius, j.height + math.sin(now * 3 + j.phase) * 0.15, 0) * CFrame.Angles(now * 3, now * 2, 0)
		elseif j.kind == "Rotor" then
			j.weld.C0 = j.base * CFrame.Angles(0, now * 30, 0)
		elseif j.kind == "Spin" then
			j.weld.C0 = j.base * CFrame.Angles(if moving then now * 12 else 0, 0, 0)
		end
	end
end

-- Planet the player is mining, from the replicated attribute.
local function mineTarget(player: Player): (Vector3?, number)
	local v = player:GetAttribute("MineNode")
	if type(v) ~= "number" then
		return nil, 0
	end
	local zone, n = v // 100, v % 100
	if not Config.Zones[zone] then
		return nil, 0
	end
	local p = Layout.nodePosition(zone, n)
	local radius = (if n == Config.NodeTitan then 12 elseif n == Config.NodeGate then 15 elseif n == Config.NodeAnomaly then 7.5 else 5.5)
	return Vector3.new(p[1], p[2], p[3]), radius
end

function PetFollow.init()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)
	Quality.Changed:Connect(function()
		for p in rigs do
			rebuild(p, true)
		end
	end)
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			for _, p in Players:GetPlayers() do
				rebuild(p)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local follow = 1 - math.exp(-dt * 7)
		local turn = 1 - math.exp(-dt * 10)
		local settle = 1 - math.exp(-dt * 12)
		for player, rig in rigs do
			local char = player.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			local dist = if root then (root.Position - camPos).Magnitude else math.huge
			if not root or dist > CULL_DISTANCE then
				for _, pet in rig.pets do
					if pet.model.Parent then
						pet.model.Parent = nil
						pet.shadow.Parent = nil
					end
					pet.pos = nil
				end
				continue
			end
			local base = root.CFrame
			local playerYaw = math.atan2(-base.LookVector.X, -base.LookVector.Z)
			local flat = CFrame.new(base.Position) * CFrame.Angles(0, playerYaw, 0)
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			local groundY = base.Position.Y - (if hum then hum.HipHeight + root.Size.Y / 2 else 3)
			local detailed = dist < ANIM_DISTANCE
			local n = #rig.pets
			local planet, planetR = mineTarget(player)
			for i, pet in rig.pets do
				if not pet.model.Parent then
					pet.model.Parent = folder
					pet.shadow.Parent = folder
				end
				local prev = pet.pos
				local cur: Vector3
				local lift = 0
				local rest = -pet.footY
				local wantYaw = playerYaw
				local pitch = 0
				local moving = false
				local tapT = now - pet.tapAt
				if planet then
					-- mining: hold a spot around the planet, dart in on every peck
					local a = i / n * math.pi * 2 + now * 0.5
					local r = planetR + 2.2
					if tapT < PECK then
						r -= math.sin(tapT / PECK * math.pi) * 2.2
					end
					local spot = planet + Vector3.new(math.cos(a) * r, math.sin(now * 2 + pet.seed) * 0.5 + (i % 3 - 1) * planetR * 0.35, math.sin(a) * r)
					cur = if prev then prev:Lerp(spot, 1 - math.exp(-dt * 9)) else spot
					pet.pos = cur
					local toPlanet = planet - cur
					wantYaw = math.atan2(-toPlanet.X, -toPlanet.Z)
					pet.yaw = lerpAngle(pet.yaw, wantYaw, turn)
					pitch = math.clamp(toPlanet.Y * 0.04, -0.5, 0.5)
					moving = true
					pet.model:PivotTo(CFrame.new(cur) * CFrame.Angles(0, pet.yaw, 0) * CFrame.Angles(pitch, 0, 0))
					local d = pet.size * 1.4
					pet.shadow.Size = Vector3.new(0.08, d, d)
					pet.shadow.CFrame = CFrame.new(cur.X, groundY + 0.07, cur.Z) * CFrame.Angles(0, 0, math.rad(90))
				else
					local slot = (flat * CFrame.new(slotOffset(i, n))).Position
					local target = Vector3.new(slot.X, groundY, slot.Z)
					if not prev or (Vector3.new(prev.X, groundY, prev.Z) - target).Magnitude > 60 then
						cur = target
						pet.yaw = playerYaw
					else
						cur = Vector3.new(prev.X, prev.Y, prev.Z):Lerp(target + Vector3.new(0, prev.Y - groundY, 0), follow)
						-- come back down from a planet smoothly
						cur = Vector3.new(cur.X, prev.Y + (groundY - prev.Y) * follow, cur.Z)
					end
					pet.pos = cur
					local move = if prev then Vector3.new(cur.X - prev.X, 0, cur.Z - prev.Z) else Vector3.zero
					local speed = if dt > 0 then move.Magnitude / dt else 0
					moving = speed > 1.5
					pet.yaw = lerpAngle(pet.yaw, if moving then math.atan2(-move.X, -move.Z) else playerYaw, turn)
					if pet.flyer then
						lift = 1.4 + math.sin(now * 2.6 + pet.seed) * 0.3
						pet.hop = 0
					else
						local want = 0
						if moving then
							pet.phase += dt * (7 + math.min(speed, 30) * 0.22)
							want = math.abs(math.sin(pet.phase)) * (0.55 + math.min(speed, 24) * 0.02)
						end
						pet.hop += (want - pet.hop) * settle
						lift = pet.hop + math.sin(now * 2.2 + pet.seed) * 0.04
					end
					if tapT < PECK then
						lift += math.sin(tapT / PECK * math.pi) * 0.85
					end
					pitch = -math.clamp(speed * 0.012, 0, 0.28)
					local roll = math.sin(now * 2 + pet.seed) * 0.05
					local above = math.max(0, cur.Y - groundY)
					pet.model:PivotTo(CFrame.new(cur.X, groundY + above + rest + lift, cur.Z) * CFrame.Angles(0, pet.yaw, 0) * CFrame.Angles(pitch, 0, roll))
					local d = pet.size * 2.3 * (1 - math.clamp((lift + above) / 7, 0, 0.45))
					pet.shadow.Size = Vector3.new(0.08, d, d)
					pet.shadow.CFrame = CFrame.new(cur.X, groundY + 0.07, cur.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
				if detailed then
					animateJoints(pet, now, moving)
					if pet.rainbow then
						PetModel.updateRainbow(pet.model, now)
					end
				end
			end
		end
	end)
end

return PetFollow
