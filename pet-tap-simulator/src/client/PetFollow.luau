--!strict
-- Renders every player's equipped pets (from the replicated "EquippedPets" attribute).
-- Client-side only: the server stores which pets are equipped and never moves a part.
-- Walkers hop along behind the player and face where they are going, flyers hover and flap,
-- tails wag, ears flop, aura orbs orbit, and each pet drops a soft blob shadow.
-- PetFollow.pulse() makes the local player's pets hop (called on every tap).
--
-- One RenderStepped loop drives everything. Level of detail (see Quality):
--  * the local player's pets always get the full treatment
--  * other players: at most Quality.remotePets pets each, none beyond Quality.remoteCull,
--    positions updated every other frame beyond Quality.slowDistance
--  * joints and rainbow colours only animate within Quality.animDistance of the camera
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Quality = require(script.Parent.Quality)

local PetFollow = {}

type JointAnim = { weld: Weld, base: CFrame, kind: string, side: number, radius: number, height: number, phase: number }
type Pet = {
	model: Model,
	shadow: BasePart,
	joints: { JointAnim },
	pos: Vector3?,
	yaw: number,
	phase: number, -- hop cycle
	hop: number, -- current hop height (smoothed)
	tapAt: number, -- os.clock() of the last tap hop
	footY: number,
	size: number,
	flyer: boolean,
	rainbow: boolean,
	seed: number,
}
type Rig = { key: string, pets: { Pet }, isLocal: boolean, order: number }

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = Workspace

-- owner: a Player, or a BasePart standing in for another player (PetFollow.addGhost)
local rigs: { [Instance]: Rig } = {}
local connections: { [Instance]: RBXScriptConnection } = {}
local localPlayer = Players.LocalPlayer
local pulseIndex = 0
local rigCount = 0
local frame = 0

local function destroyPet(pet: Pet)
	pet.model:Destroy()
	pet.shadow:Destroy()
end

local function clear(owner: Instance)
	local rig = rigs[owner]
	if rig then
		for _, pet in rig.pets do
			destroyPet(pet)
		end
		rigs[owner] = nil
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
	p.Color = Color3.fromRGB(20, 15, 30)
	p.Transparency = 0.62
	p.Size = Vector3.new(0.08, 2, 2)
	return p
end

local function makePet(id: string, tier: number, isLocal: boolean, index: number): Pet
	local model = PetModel.build(id, tier, { lights = isLocal and Quality.petFx, fx = Quality.petFx })
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

local function rebuild(owner: Instance, force: boolean?)
	local key = owner:GetAttribute("EquippedPets")
	local keyStr = if type(key) == "string" then key else ""
	local rig = rigs[owner]
	if rig and rig.key == keyStr and not force then
		return
	end
	local isLocal = owner == localPlayer
	local limit = if isLocal then math.huge else Quality.remotePets
	local old: { Pet } = if rig then rig.pets else {}
	rigCount += 1
	local newRig: Rig = { key = keyStr, pets = {}, isLocal = isLocal, order = if rig then rig.order else rigCount }
	local index = 0
	for entry in keyStr:gmatch("[^,]+") do
		local id, tier = entry:match("^(.-):(%d)$")
		if id and index < limit then
			index += 1
			local pet = makePet(id, tonumber(tier) or 0, isLocal, index)
			-- keep walking from where the previous pet in this slot stood
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
	rigs[owner] = newRig
end

local function watch(player: Player)
	rebuild(player)
	connections[player] = player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		rebuild(player)
	end)
end

local function unwatch(owner: Instance)
	local conn = connections[owner]
	if conn then
		conn:Disconnect()
		connections[owner] = nil
	end
	clear(owner)
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

-- Renders a set of pets following an arbitrary part, as if it were another player
-- (performance tests and screenshots). key: "petId:tier,petId:tier".
function PetFollow.addGhost(part: BasePart, key: string)
	part:SetAttribute("EquippedPets", key)
	rebuild(part)
	part.Destroying:Once(function()
		unwatch(part)
	end)
end

-- Number of pet models currently parented to the world (after distance culling).
function PetFollow.visibleCount(): number
	local n = 0
	for _, rig in rigs do
		for _, pet in rig.pets do
			if pet.model.Parent then
				n += 1
			end
		end
	end
	return n
end

-- Owners being tracked and live attribute connections (leak check in the playtest).
function PetFollow.tracked(): (number, number)
	local r, c = 0, 0
	for _ in rigs do
		r += 1
	end
	for _ in connections do
		c += 1
	end
	return r, c
end

-- The local player's pets hop, one after another, on every tap.
function PetFollow.pulse()
	local rig = rigs[localPlayer]
	if not rig or #rig.pets == 0 then
		return
	end
	pulseIndex = pulseIndex % #rig.pets + 1
	rig.pets[pulseIndex].tapAt = os.clock()
end

local TAP_HOP = 0.3

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
			j.weld.C0 = CFrame.Angles(0, now * 2.2 + j.phase, 0) * CFrame.new(j.radius, j.height + math.sin(now * 3 + j.phase) * 0.15, 0)
		end
	end
end

function PetFollow.init()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)
	-- the profile changed (phone <-> PC preview, graphics slider): rebuild with the new detail
	Quality.Changed:Connect(function()
		for owner in rigs do
			rebuild(owner, true)
		end
	end)

	RunService.RenderStepped:Connect(function(frameDt: number)
		frame += 1
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for owner, rig in rigs do
			local char = if owner:IsA("Player") then owner.Character else nil
			local root = if owner:IsA("BasePart") then owner else (char and char:FindFirstChild("HumanoidRootPart") :: BasePart?)
			local dist = if root then (root.Position - camPos).Magnitude else math.huge
			if not root or (not rig.isLocal and dist > Quality.remoteCull) then
				for _, pet in rig.pets do
					if pet.model.Parent then
						pet.model.Parent = nil
						pet.shadow.Parent = nil
					end
					pet.pos = nil
				end
				continue
			end
			-- far rigs of other players move every other frame (staggered between rigs)
			local dt = frameDt
			if not rig.isLocal and dist > Quality.slowDistance then
				if (frame + rig.order) % 2 == 0 then
					continue
				end
				dt = frameDt * 2
			end
			local follow = 1 - math.exp(-dt * 7)
			local turn = 1 - math.exp(-dt * 10)
			local settle = 1 - math.exp(-dt * 12)
			local base = (root :: BasePart).CFrame
			local playerYaw = math.atan2(-base.LookVector.X, -base.LookVector.Z)
			local flat = CFrame.new(base.Position) * CFrame.Angles(0, playerYaw, 0)
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local groundY = base.Position.Y - (if hum then hum.HipHeight + (root :: BasePart).Size.Y / 2 else 3)
			local detailed = dist < Quality.animDistance
			local n = #rig.pets
			for i, pet in rig.pets do
				if not pet.model.Parent then
					pet.model.Parent = folder
					pet.shadow.Parent = folder
				end
				local slot = (flat * CFrame.new(slotOffset(i, n))).Position
				local target = Vector3.new(slot.X, 0, slot.Z)
				local prev = pet.pos
				local cur: Vector3
				if not prev or (Vector3.new(prev.X, 0, prev.Z) - target).Magnitude > 60 then
					cur = target
					pet.yaw = playerYaw
				else
					cur = prev:Lerp(target, follow)
				end
				pet.pos = cur
				local move = if prev then cur - prev else Vector3.zero
				local speed = if dt > 0 then move.Magnitude / dt else 0
				local moving = speed > 1.5
				pet.yaw = lerpAngle(pet.yaw, if moving then math.atan2(-move.X, -move.Z) else playerYaw, turn)

				-- height above the ground
				local rest = -pet.footY
				local lift: number
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
				local tapT = now - pet.tapAt
				if tapT < TAP_HOP then
					lift += math.sin(tapT / TAP_HOP * math.pi) * 0.85
				end
				local pitch = -math.clamp(speed * 0.012, 0, 0.28)
				if tapT < TAP_HOP then
					pitch += math.sin(tapT / TAP_HOP * math.pi) * 0.25
				end
				local roll = math.sin(now * 2 + pet.seed) * 0.05
				pet.model:PivotTo(CFrame.new(cur.X, groundY + rest + lift, cur.Z) * CFrame.Angles(0, pet.yaw, 0) * CFrame.Angles(pitch, 0, roll))

				local d = pet.size * 2.3 * (1 - math.clamp(lift / 7, 0, 0.45))
				pet.shadow.Size = Vector3.new(0.08, d, d)
				pet.shadow.CFrame = CFrame.new(cur.X, groundY + 0.07, cur.Z) * CFrame.Angles(0, 0, math.rad(90))

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
