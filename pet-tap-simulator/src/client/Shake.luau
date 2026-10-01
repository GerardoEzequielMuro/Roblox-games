--!strict
-- Camera micro-shake through Humanoid.CameraOffset (never touches the camera itself, so it
-- cannot fight the default camera scripts). Strength 0..1; short; stops by itself.
-- Reduced motion (workspace/player attribute ReducedMotion = true, or the Roblox setting when
-- it exists) turns it off completely, and lite devices get a calmer shake.
-- Shake.reduced() is also what the flash effects check.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Juice = require(ReplicatedStorage.Shared.Juice)
local Quality = require(script.Parent.Quality)

local Shake = {}

function Shake.reduced(): boolean
	local player = Players.LocalPlayer
	if Workspace:GetAttribute("ReducedMotion") == true or (player and player:GetAttribute("ReducedMotion") == true) then
		return true
	end
	local ok, v = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).ReducedMotion
	end)
	return ok and v == true
end

local conn: RBXScriptConnection? = nil
local startT, dur, amp, seed = 0, 0, 0, 0
local lastHum: Humanoid? = nil

local function humanoid(): Humanoid?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if lastHum and lastHum.Parent then
		lastHum.CameraOffset = Vector3.zero
	end
	lastHum = nil
end

function Shake.kick(strength: number, duration: number?)
	local a = Juice.shakeAmplitude(strength, Shake.reduced(), Quality.lite)
	local hum = humanoid()
	if a <= 0 or not hum then
		return
	end
	local now = os.clock()
	-- a weaker shake never cuts a stronger one that is still running
	if conn and a < amp * Juice.envelope(now - startT, dur) then
		return
	end
	startT, dur, amp, seed = now, duration or 0.28, a, math.random() * 6
	lastHum = hum
	if conn then
		return
	end
	conn = RunService.RenderStepped:Connect(function()
		local h = lastHum
		local t = os.clock() - startT
		if not h or not h.Parent or t >= dur then
			stop()
			return
		end
		local x, y = Juice.shakeOffset(t, dur, amp, seed)
		h.CameraOffset = Vector3.new(x, y, 0)
	end)
end

return Shake
