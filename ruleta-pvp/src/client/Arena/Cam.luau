--!strict
-- The cinematic camera. While a table is on screen the camera is scripted: every shot is a
-- function returning where the camera wants to be; shots blend into each other, and shake /
-- FOV punches ride on top. Cam.release() hands the camera back to the player.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Prefs = require(script.Parent.Parent.Prefs)

local Cam = {}

export type Provider = (t: number) -> (CFrame, number)

Cam.active = false
Cam.shots = 0 -- shot counter (the playtest checks the director actually cuts)
Cam.lastShot = ""

local provider: Provider? = nil
local fromCF = CFrame.new()
local fromFov = 70
local curCF = CFrame.new()
local curFov = 70
local t0 = 0
local duration = 0
local trauma = 0
local punch = 0
local shotStart = 0

-- Free orbit (spectators): yaw / pitch / distance driven by drag and wheel.
Cam.free = { enabled = false, yaw = 0, pitch = 0.5, dist = 40 }

local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- Starts a shot. duration 0 = hard cut.
function Cam.shot(name: string, p: Provider, blend: number?)
	local cam = Workspace.CurrentCamera
	if not Cam.active then
		Cam.active = true
		curCF = cam.CFrame
		curFov = cam.FieldOfView
	end
	Cam.shots += 1
	Cam.lastShot = name
	fromCF, fromFov = curCF, curFov
	provider = p
	t0 = os.clock()
	shotStart = t0
	duration = blend or 0.6
end

function Cam.static(name: string, cf: CFrame, fov: number, blend: number?)
	Cam.shot(name, function()
		return cf, fov
	end, blend)
end

function Cam.shake(amount: number)
	if Prefs.shake() then
		trauma = math.min(1, trauma + amount)
	end
end

-- Quick FOV kick (negative = punch in).
-- With "screen shake" off (reduced motion) punches still read, but much smaller.
function Cam.punch(amount: number)
	punch += if Prefs.shake() then amount else amount * 0.3
end

function Cam.release()
	if not Cam.active then
		return
	end
	Cam.active = false
	provider = nil
	Cam.free.enabled = false
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

function Cam.current(): (CFrame, number)
	return curCF, curFov
end

-- Orbit shot controlled by the player around `centre`.
function Cam.freeOrbit(name: string, centre: () -> Vector3, blend: number?)
	Cam.free.enabled = true
	Cam.shot(name, function()
		local f = Cam.free
		local c = centre()
		local dir = Vector3.new(math.sin(f.yaw) * math.cos(f.pitch), math.sin(f.pitch), math.cos(f.yaw) * math.cos(f.pitch))
		return CFrame.lookAt(c + dir * f.dist, c), 60
	end, blend)
end

local dragging = false
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not Cam.free.enabled or processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	local f = Cam.free
	if not f.enabled then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		f.dist = math.clamp(f.dist - input.Position.Z * 4, 14, 80)
	elseif dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		f.yaw -= input.Delta.X * 0.008
		f.pitch = math.clamp(f.pitch + input.Delta.Y * 0.006, 0.12, 1.35)
	end
end)

RunService:BindToRenderStep("SpinCam", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
	if not Cam.active or not provider then
		return
	end
	local cam = Workspace.CurrentCamera
	local now = os.clock()
	local targetCF, targetFov = provider(now - shotStart)
	local a = if duration <= 0 then 1 else ease((now - t0) / duration)
	curCF = fromCF:Lerp(targetCF, a)
	curFov = fromFov + (targetFov - fromFov) * a
	local cf, fov = curCF, curFov
	if trauma > 0.001 then
		local s = trauma * trauma
		local t = now * 38
		cf *= CFrame.Angles(math.noise(t, 1.3) * 0.06 * s, math.noise(t, 7.7) * 0.06 * s, math.noise(t, 13.1) * 0.09 * s)
		cf += Vector3.new(math.noise(t, 21.0), math.noise(t, 33.0), 0) * 0.9 * s
		trauma = math.max(0, trauma - dt * 1.6)
	end
	if math.abs(punch) > 0.01 then
		fov += punch
		punch *= math.exp(-dt * 7)
	else
		punch = 0
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	cam.FieldOfView = math.clamp(fov, 20, 100)
end)

return Cam
