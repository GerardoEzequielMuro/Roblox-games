-- Screenshot showcase: every time the runner resizes the window, move on to the next scene.
-- Workspace attributes: ShowcaseFrom (first scene), ShowcaseLow (minimum-graphics preview),
-- ShowcaseSet (2 = the short set used for the touch layout).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(Client:WaitForChild("Net"))
local Controls = require(Client:WaitForChild("Controls"))
local Flight = require(Client:WaitForChild("Flight"))
local CharFx = require(Client:WaitForChild("CharFx"))
local Show = ReplicatedStorage:WaitForChild("__Show", 60) :: RemoteFunction

local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
player.CharacterAdded:Connect(function(c)
	char = c
	hrp = c:WaitForChild("HumanoidRootPart")
end)

local function srv(...)
	return Show:InvokeServer(...)
end

local camCF: CFrame? = nil
local camFollow: ((Vector3) -> CFrame)? = nil
RunService:BindToRenderStep("KiwShowcase", Enum.RenderPriority.Camera.Value + 2, function()
	local cam = workspace.CurrentCamera
	if camFollow then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camFollow(hrp.Position)
	elseif camCF then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCF
	end
end)

-- Minimum graphics preview: switches off everything graphics level 1 drops (shadows, bloom, sun rays, colour grade, atmosphere,
-- lights) so the screenshots show the worst case.
if workspace:GetAttribute("ShowcaseLow") then
	-- (scripts cannot change the real quality level: it needs RobloxScript capability)
	workspace:SetAttribute("ForceLite", true)
	local Lighting = game:GetService("Lighting")
	task.spawn(function()
		while true do
			Lighting.GlobalShadows = false
			for _, fx in Lighting:GetChildren() do
				if fx:IsA("PostEffect") then
					fx.Enabled = false
				elseif fx:IsA("Atmosphere") then
					fx.Density = 0
					fx.Haze = 0
					fx.Glare = 0
				end
			end
			for _, d in workspace:GetDescendants() do
				if d:IsA("Light") or d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
			task.wait(0.5)
		end
	end)
end

local function at(offset, dx, dz, y)
	local cx, _, cz = Config.planetCenter(Net.get("planet") or 1)
	return Vector3.new(cx + offset[1] + (dx or 0), y or 4, cz + offset[3] + (dz or 0))
end
local function place(pos: Vector3, look: Vector3)
	srv("tp", CFrame.lookAt(pos, pos + look))
end
local P1 = Config.Planets[1]

local looping = 0
local function loop(seconds: number, every: number, fn: () -> ())
	looping += 1
	local my = looping
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds and my == looping do
			fn()
			task.wait(every)
		end
	end)
end

local function reset()
	looping += 1
	camFollow = nil
	Controls.charge(false)
	Controls.block(false)
	if Flight.active then
		Flight.stop()
	end
	Flight.testMove = nil
	srv("frozen", true)
	srv("heal")
end

local function faceNpc(kind: string): (Vector3?, Vector3)
	local n = srv("npc", kind)
	if not n then
		return nil, hrp.CFrame.LookVector
	end
	return n.pos, (n.pos - hrp.Position).Unit
end

local scenes = {
	function() -- 1: plaza overview (base form, HUD)
		reset()
		srv("form", 0)
		place(Vector3.new(14, 4, 40), Vector3.new(-0.3, 0, -1))
		task.wait(1)
		camCF = CFrame.lookAt(Vector3.new(34, 17, 76), Vector3.new(-4, 12, 0))
	end,
	function() -- 2: training in the Gravity Dome, charging aura
		reset()
		local z = P1.zones[1]
		local pos = at(z.offset, 0, 0, 5)
		place(pos, Vector3.new(1, 0, 0.4))
		task.wait(1.2)
		camCF = CFrame.lookAt(pos + Vector3.new(15, 7, 10), pos + Vector3.new(0, 3, 0))
		task.wait(0.5)
		srv("ki", 0.3)
		Controls.charge(true)
		loop(9, 1.5, function()
			srv("ki", 0.3)
		end)
	end,
	function() -- 3: transformation burst next to the thornling camp
		reset()
		local c = P1.camps[1]
		local pos = at(c.offset, -34, 30, 4)
		place(pos, Vector3.new(1, 0, -0.8))
		task.wait(1.2)
		camCF = CFrame.lookAt(pos + Vector3.new(-13, 6, 15), pos + Vector3.new(3, 5, -3))
		srv("form", 2)
		task.wait(1)
		Controls.charge(true)
		loop(9, 0.75, function()
			srv("ki", 0.5)
			local rig = CharFx.rigs[char]
			if rig then
				CharFx.transformBurst(rig, 2)
			end
		end)
	end,
	function() -- 4: lightning form firing the beam across the raider camp
		reset()
		srv("form", 3)
		local c = P1.camps[2]
		local pos = at(c.offset, 50, 40, 4)
		local target = at(c.offset, 0, 0, 4)
		place(pos, (target - pos).Unit)
		task.wait(1.2)
		local dirT = (target - pos).Unit
		local side = dirT:Cross(Vector3.yAxis)
		camCF = CFrame.lookAt(pos - dirT * 12 + side * 22 + Vector3.new(0, 9, 0), pos + dirT * 30 + Vector3.new(0, 2, 0))
		loop(10, 0.62, function()
			local npcPos = faceNpc("raider")
			local dir = ((npcPos or target) - hrp.Position).Unit
			srv("beam", dir, 1)
		end)
	end,
	function() -- 5: boss fight (telegraphs, blasts)
		reset()
		srv("form", 1)
		srv("stats", { strength = 60, ki = 60, defense = 9000 })
		local b = P1.boss
		local pos = at(b.offset, 0, -22, 4)
		place(pos, Vector3.new(0, 0, 1))
		task.wait(1)
		srv("frozen", false)
		camFollow = function(p)
			local bossPos = at(b.offset, 0, 0, 8)
			local dir = (bossPos - p) * Vector3.new(1, 0, 1)
			dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(0, 0, 1)
			return CFrame.lookAt(p - dir * 20 + Vector3.new(9, 11, 0), p + dir * 12 + Vector3.new(0, 5, 0))
		end
		loop(11, 0.31, function()
			local npcPos, dir = faceNpc("bramble_king")
			if npcPos then
				Net.act("melee", (dir * Vector3.new(1, 0, 1)).Unit)
				Net.act("blast", dir)
			end
			srv("heal")
		end)
	end,
	function() -- 6: flying over Verdia in the shadow form
		reset()
		srv("stats", { strength = 8400, ki = 12500 })
		srv("form", 4)
		place(Vector3.new(40, 6, 120), Vector3.new(-0.4, 0, -1))
		task.wait(0.8)
		Flight.start()
		Flight.testMove = Vector3.new(0, 1, 0)
		task.wait(0.55)
		Flight.testMove = Vector3.new(-0.5, 0.02, -1).Unit * 0.35
		camFollow = function(p)
			return CFrame.lookAt(p + Vector3.new(14, 12, 22), p + Vector3.new(-8, -10, -22))
		end
		loop(9, 1, function()
			srv("ki", 1)
		end)
	end,
	function() -- 7: Kaldera (volcano planet) plaza
		reset()
		srv("form", 2)
		srv("planet", 2)
		task.wait(2)
		local cx, _, cz = Config.planetCenter(2)
		camCF = CFrame.lookAt(Vector3.new(cx + 40, 22, cz + 84), Vector3.new(cx - 6, 12, cz))
	end,
	function() -- 8: The Rift (void planet) with the top form
		reset()
		srv("form", 6)
		srv("planet", 5)
		task.wait(2)
		local cx, _, cz = Config.planetCenter(5)
		camCF = CFrame.lookAt(Vector3.new(cx + 22, 12, cz + 50), Vector3.new(cx - 2, 8, cz + 16))
		Controls.charge(true)
		loop(9, 1.2, function()
			srv("ki", 0.4)
		end)
	end,
	function() -- 9: back home, default camera (HUD check at the next sizes)
		reset()
		srv("form", 1)
		srv("planet", 1)
		task.wait(1.5)
		camCF = nil
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end,
	function() -- 10: small viewport, fighting thornlings with the default camera
		reset()
		local c = P1.camps[1]
		place(at(c.offset, 14, -10, 4), Vector3.new(-1, 0, 0.6))
		task.wait(1)
		loop(9, 0.32, function()
			local npcPos, dir = faceNpc("thornling")
			if npcPos then
				Net.act("melee", (dir * Vector3.new(1, 0, 1)).Unit)
			end
		end)
	end,
}

-- Short set (touch layout): plaza, transformed fight, flying.
local scenes2 = { scenes[1], scenes[3], scenes[10], scenes[6] }

if tonumber(workspace:GetAttribute("ShowcaseSet")) == 2 then
	scenes = scenes2
end

local index = math.max(0, (tonumber(workspace:GetAttribute("ShowcaseFrom")) or 1) - 1)
local token = 0
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	token += 1
	local my = token
	task.delay(0.4, function()
		if my ~= token then
			return
		end
		index += 1
		local fn = scenes[index]
		if fn then
			print("[TEST] showcase scene " .. index)
			task.spawn(fn)
		end
	end)
end)
