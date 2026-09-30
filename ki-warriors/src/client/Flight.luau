--!nonstrict
-- Flight (client-side movement; the server only knows the Flying flag for other players'
-- poses). Camera-relative in 3D: move where you look, Space / jump = up, Ctrl = down,
-- Shift = boost. Speed comes from the server (FlySpeed attribute, from Agility).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Net)
local Fx = require(script.Parent.Fx)

local Flight = {}

local player = Players.LocalPlayer
Flight.active = false
Flight.boost = false -- touch toggle
Flight.descend = false -- touch hold
Flight.ascend = false -- touch hold
Flight.testMove = nil :: Vector3? -- playtest: world-space direction override

local controls = nil
task.spawn(function()
	local ok, module = pcall(function()
		return (require :: any)(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
	end)
	if ok and module then
		controls = module:GetControls()
	end
end)

local att: any = nil
local lv: any = nil
local ao: any = nil
local vel = Vector3.zero
local changed = Instance.new("BindableEvent")
Flight.Changed = changed.Event

local function parts(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Flight.stop()
	if not Flight.active then
		return
	end
	Flight.active = false
	Fx.fovBoost = 0
	local _, hum = parts()
	if lv then
		lv:Destroy()
		lv = nil
	end
	if ao then
		ao:Destroy()
		ao = nil
	end
	if att then
		att:Destroy()
		att = nil
	end
	if hum and hum.Health > 0 then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	Net.act("fly", false)
	changed:Fire(false)
end

function Flight.start()
	if Flight.active then
		return
	end
	local char, hum, root = parts()
	if not char or not hum or not root or hum.Health <= 0 then
		return
	end
	if char:GetAttribute("Charging") == true then
		return
	end
	Flight.active = true
	hum.PlatformStand = true
	att = Instance.new("Attachment")
	att.Name = "KiwFlight"
	att.Parent = root
	lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.new(0, 14, 0)
	lv.Parent = root
	ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 28
	ao.CFrame = root.CFrame
	ao.Parent = root
	vel = Vector3.new(0, 14, 0)
	Net.act("fly", true)
	Fx.ring(root.Position - Vector3.new(0, 2.6, 0), 2, 12, Color3.fromRGB(220, 240, 255), 0.35, 0.4)
	changed:Fire(true)
end

function Flight.toggle()
	if Flight.active then
		Flight.stop()
	else
		Flight.start()
	end
end

function Flight.init()
	player.CharacterAdded:Connect(function()
		Flight.active = false
		lv, ao, att = nil, nil, nil
		Fx.fovBoost = 0
		changed:Fire(false)
	end)
	RunService.RenderStepped:Connect(function(dt)
		if not Flight.active then
			return
		end
		local char, hum, root = parts()
		local cam = workspace.CurrentCamera
		if not char or not hum or not root or not cam or hum.Health <= 0 or not lv or not ao then
			Flight.stop()
			return
		end
		if char:GetAttribute("Charging") == true or char:GetAttribute("Beam") == true then
			-- hold still in the air while charging
			vel = vel:Lerp(Vector3.zero, math.min(1, dt * 10))
			lv.VectorVelocity = vel
			return
		end
		local dir = Vector3.zero
		if Flight.testMove then
			dir = Flight.testMove
		elseif controls then
			local mv = controls:GetMoveVector()
			if mv.Magnitude > 0.05 then
				dir = cam.CFrame:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z))
			end
		end
		local up = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump or Flight.ascend then
			up += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or Flight.descend then
			up -= 1
		end
		dir += Vector3.new(0, up, 0)
		local boost = Flight.boost or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		local speed = (char:GetAttribute("FlySpeed") or 72) * (if boost then 1.7 else 1)
		local want = if dir.Magnitude > 0.05 then dir.Unit * speed * math.min(1, dir.Magnitude) else Vector3.zero
		vel = vel:Lerp(want, math.min(1, dt * 5))
		lv.VectorVelocity = vel
		local flat = Vector3.new(vel.X, 0, vel.Z)
		if flat.Magnitude > 6 then
			local lean = math.clamp(flat.Magnitude / speed, 0, 1) * math.rad(68)
			ao.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * CFrame.Angles(-lean, 0, 0)
		else
			local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.05 then
				ao.CFrame = CFrame.lookAt(Vector3.zero, look.Unit)
			end
		end
		Fx.fovBoost = if boost and vel.Magnitude > speed * 0.5 then 12 else math.clamp(vel.Magnitude / 40, 0, 5)
		-- land when pushing down into the ground
		if up < 0 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char, Fx.folder }
			if workspace:Raycast(root.Position, Vector3.new(0, -4.2, 0), params) then
				Flight.stop()
			end
		end
	end)
end

return Flight
