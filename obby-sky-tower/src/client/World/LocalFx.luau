--!strict
-- Client-side world behaviour that must act on the LOCAL character or the local view:
--   * Bounce pads: launch your own (client-owned) character upward.
--   * Wind zones: push your character sideways while it is inside one.
--   * Abilities the server has granted (player attributes AirJumps / Dash / Roam): double and
--     triple jump, dash, and the lounge's explore mode (glider, cloud).
--   * Glass: invisible until you're close (purely visual, local).
--   * Coins: spin locally, hide the ones you've collected this run.
-- (The sky / lighting per world is World/Atmos.luau; hit feedback is World/Juice.luau.)
-- The world is streamed, so every list follows CollectionService added / removed signals, and the
-- cosmetic loops only touch what is near the camera.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Net = require(script.Parent.Parent.Net)

local LocalFx = {}

local player = Players.LocalPlayer
local NEAR = 150

local function tracked(name: string, onAdded: ((BasePart) -> ())?): { BasePart }
	local list: { BasePart } = {}
	local function add(inst: Instance)
		if inst:IsA("BasePart") then
			table.insert(list, inst)
			if onAdded then
				onAdded(inst)
			end
		end
	end
	for _, inst in CollectionService:GetTagged(name) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(name):Connect(add)
	CollectionService:GetInstanceRemovedSignal(name):Connect(function(inst)
		local i = table.find(list, inst :: any)
		if i then
			list[i] = list[#list]
			list[#list] = nil
		end
	end)
	return list
end

local function parts(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hum or not root or hum.Health <= 0 then
		return nil, nil, nil
	end
	return char, hum, root
end

---------------------------------------------------------------------------------------------
-- dash (exposed for the HUD button)
---------------------------------------------------------------------------------------------
local dashUntil, dashReadyAt = 0, 0
local dashDir = Vector3.zero

-- Seconds until the dash can be used again (0 = ready). -1 = you don't have it.
function LocalFx.dashCooldown(): number
	if player:GetAttribute("Dash") ~= true then
		return -1
	end
	return math.max(0, dashReadyAt - os.clock())
end

function LocalFx.dash(): boolean
	local _, hum, root = parts()
	if not hum or not root or player:GetAttribute("Dash") ~= true or os.clock() < dashReadyAt then
		return false
	end
	local dir = hum.MoveDirection
	if dir.Magnitude < 0.1 then
		local look = root.CFrame.LookVector
		dir = Vector3.new(look.X, 0, look.Z)
	end
	if dir.Magnitude < 0.1 then
		return false
	end
	dashDir = dir.Unit
	dashUntil = os.clock() + Perks.DASH_TIME
	dashReadyAt = os.clock() + Perks.DASH_COOLDOWN
	return true
end

function LocalFx.init()
	-- Bounce pads ---------------------------------------------------------------------------
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local lastBounce = 0

	-- Wind zones ------------------------------------------------------------------------------
	local winds = tracked("Wind")

	-- Air jumps (double / triple jump) ------------------------------------------------------------
	local airUsed = 0
	local released = false -- the jump key was let go since the last jump
	local lastJumpAt = 0
	UserInputService.JumpRequest:Connect(function()
		local _, hum, root = parts()
		if not hum or not root then
			return
		end
		local allowed = player:GetAttribute("AirJumps")
		local state = hum:GetState()
		local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		if not airborne then
			lastJumpAt = os.clock()
			released = false
			return
		end
		if type(allowed) ~= "number" or airUsed >= allowed or not released or os.clock() - lastJumpAt < 0.15 then
			return
		end
		airUsed += 1
		released = false
		lastJumpAt = os.clock()
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, Config.JumpPower, v.Z)
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Q then
			LocalFx.dash()
		end
	end)

	-- Explore mode visuals (local): a glider over your head / a cloud under your feet
	local prop: BasePart? = nil
	local propKind = ""
	local function setProp(kind: string)
		if kind == propKind then
			return
		end
		propKind = kind
		if prop then
			prop:Destroy()
			prop = nil
		end
		if kind == "" then
			return
		end
		local p = Instance.new("Part")
		p.Name = "RoamProp"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		if kind == "glider" then
			p.Size = Vector3.new(9, 0.3, 3.2)
			p.Color = Color3.fromRGB(255, 110, 130)
		else
			p.Size = Vector3.new(6, 1.6, 6)
			p.Color = Color3.fromRGB(255, 255, 255)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Parent = Workspace
		prop = p
	end

	RunService.Heartbeat:Connect(function(dt)
		local char, hum, root = parts()
		if not char or not hum or not root then
			setProp("")
			return
		end
		local now = os.clock()
		local state = hum:GetState()
		local grounded = hum.FloorMaterial ~= Enum.Material.Air
		if grounded then
			airUsed = 0
		end
		if not hum.Jump then
			released = true
		end

		-- bounce
		if grounded and now - lastBounce >= 0.4 then
			params.FilterDescendantsInstances = { char }
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -5, 0), params)
			if hit and CollectionService:HasTag(hit.Instance, "Bounce") then
				lastBounce = now
				local v = root.AssemblyLinearVelocity
				local up = math.sqrt(2 * Workspace.Gravity * Config.BounceHeight)
				root.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end

		-- wind: while you are in the air inside a zone you drift with it at the wind speed (the
		-- Humanoid's air control cancels velocity nudges, so the drift is applied to the position;
		-- steering against it works because WalkSpeed is always higher than the wind)
		if not grounded then
			for _, zone in winds do
				local rel = zone.CFrame:PointToObjectSpace(root.Position)
				local half = zone.Size / 2
				if math.abs(rel.X) < half.X and math.abs(rel.Y) < half.Y and math.abs(rel.Z) < half.Z then
					local push = zone:GetAttribute("Push")
					if typeof(push) == "Vector3" then
						root.CFrame += push * math.min(dt, 0.05)
					end
					break
				end
			end
		end

		-- dash
		if now < dashUntil then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(dashDir.X * Perks.DASH_SPEED, math.max(v.Y, 2), dashDir.Z * Perks.DASH_SPEED)
		end

		-- explore mode
		local roam = player:GetAttribute("Roam")
		if roam == "glider" then
			setProp("glider")
			local v = root.AssemblyLinearVelocity
			if v.Y < -Perks.GLIDE_FALL_SPEED and state == Enum.HumanoidStateType.Freefall then
				root.AssemblyLinearVelocity = Vector3.new(v.X, -Perks.GLIDE_FALL_SPEED, v.Z)
			end
			if prop then
				prop.CFrame = root.CFrame * CFrame.new(0, 3.6, 0.4) * CFrame.Angles(math.rad(-8), 0, 0)
			end
		elseif roam == "cloud" then
			setProp("cloud")
			local move = hum.MoveDirection
			local vy = 0
			if hum.Jump then
				vy = 26
			elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.ButtonL3) then
				vy = -26
			end
			-- hover: no falling, and the ride itself is moved (same reason as the wind above)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame += Vector3.new(move.X * Perks.CLOUD_SPEED, vy, move.Z * Perks.CLOUD_SPEED) * math.min(dt, 0.05)
			if prop then
				prop.CFrame = CFrame.new(root.Position - Vector3.new(0, 3.4, 0))
			end
		else
			setProp("")
		end
	end)

	-- Glass reveal ---------------------------------------------------------------------------
	local glass = tracked("Glass", function(g)
		g.Transparency = 1
	end)
	task.spawn(function()
		while true do
			task.wait(0.12)
			local _, _, root = parts()
			if root then
				local pos = root.Position
				for _, g in glass do
					local d = (g.Position - pos).Magnitude
					if d < NEAR then
						local target = if d < Config.GlassRevealDistance then 0.3 + 0.6 * (d / Config.GlassRevealDistance) else 1
						if math.abs(g.Transparency - target) > 0.02 then
							g.Transparency = target
						end
					end
				end
			end
		end
	end)

	-- Coins -----------------------------------------------------------------------------------
	local collected: { [number]: boolean } = {}
	local homes: { [BasePart]: CFrame } = {}
	local byId: { [number]: BasePart } = {}
	local coins = tracked("Coin", function(c)
		homes[c] = c.CFrame
		local id = c:GetAttribute("CoinId")
		if type(id) == "number" then
			byId[id] = c
			if collected[id] then
				c.Transparency = 1 -- streamed back in after you took it
			end
		end
		c.Destroying:Once(function()
			homes[c] = nil
			if type(id) == "number" and byId[id] == c then
				byId[id] = nil
			end
		end)
	end)
	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local t = os.clock()
		local camPos = cam.CFrame.Position
		for _, c in coins do
			local home = homes[c]
			if home and c.Transparency < 1 then
				local d = home.Position - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z < NEAR * NEAR then
					c.CFrame = CFrame.new(home.Position + Vector3.new(0, math.sin(t * 2 + home.Position.X) * 0.3, 0)) * CFrame.Angles(0, t * 2, 0)
				end
			end
		end
	end)
	Net.on("CoinCollected", function(id: number)
		collected[id] = true
		local c = byId[id]
		if c then
			TweenService:Create(c, TweenInfo.new(0.25), { Size = c.Size * 1.6, Transparency = 1 }):Play()
		end
	end)
	Net.changed:Connect(function(new, prev)
		-- rebirth resets the run: show all coins again
		if prev.at and new.at and new.at == 0 and prev.at >= Layout.STAGES then
			table.clear(collected)
			for _, c in coins do
				c.Transparency = 0
				c.Size = Vector3.new(0.5, 2.4, 2.4)
			end
		end
	end)
end

return LocalFx
