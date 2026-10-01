--!strict
-- Game feel that needs no art: camera micro-shake and a pooled sparkle burst. Everything is
-- capped and cheap (one emitter part, one render-step connection), weaker on the lite profile
-- and off in Calm mode (Settings). Sounds go through Theme.play (existing ids only).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Juice = require(ReplicatedStorage.Shared.Juice)
local Net = require(script.Parent.Net)
local Quality = require(script.Parent.Quality)

local Feel = {}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARK_CAP = 40

local shakeAmp, shakeLife, shakeStart = 0, 0.3, 0
local lastShakeAt = 0

function Feel.calm(): boolean
	local s = Net.state
	return s ~= nil and s.settings ~= nil and s.settings.calm == true
end

-- kind: "hit" | "crit" | "break" | "big"
function Feel.shake(kind: string)
	local amp = Juice.shakeAmplitude(kind, Feel.calm(), Quality.lite)
	if amp <= 0 then
		return
	end
	local now = os.clock()
	if now - lastShakeAt < 0.08 then
		return
	end
	lastShakeAt = now
	local life = if kind == "big" then 0.5 else 0.26
	local elapsed = now - shakeStart
	local left = math.max(0, shakeLife - elapsed)
	shakeAmp, shakeLife = Juice.mergeShake(if left > 0 then shakeAmp else 0, left, amp, life)
	shakeStart = now
end

-- Sparkles -------------------------------------------------------------------------
local sparkPart: Part? = nil
local emitter: ParticleEmitter? = nil
local alive: { { at: number, n: number } } = {}

local function ensureSpark(): (Part, ParticleEmitter)
	local p = sparkPart
	local e = emitter
	if p and e and p.Parent then
		return p, e
	end
	local np = Instance.new("Part")
	np.Name = "FeelSparks"
	np.Anchored = true
	np.CanCollide = false
	np.CanQuery = false
	np.CanTouch = false
	np.Transparency = 1
	np.Size = Vector3.one
	np.Parent = Workspace
	local ne = Instance.new("ParticleEmitter")
	ne.Texture = SPARK_TEXTURE
	ne.Enabled = false
	ne.Lifetime = NumberRange.new(0.5, 0.9)
	ne.Speed = NumberRange.new(14, 30)
	ne.SpreadAngle = Vector2.new(180, 180)
	ne.Acceleration = Vector3.new(0, -24, 0)
	ne.Rate = 0
	ne.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	ne.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	ne.LightEmission = 1
	ne.Parent = np
	sparkPart, emitter = np, ne
	return np, ne
end

function Feel.sparkle(pos: Vector3, color: Color3, count: number)
	local now = os.clock()
	local live = 0
	for i = #alive, 1, -1 do
		if now - alive[i].at > 0.9 then
			table.remove(alive, i)
		else
			live += alive[i].n
		end
	end
	local n = Juice.budget(count, live, SPARK_CAP, Quality.lite)
	if n <= 0 then
		return
	end
	local part, e = ensureSpark()
	part.Position = pos
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e:Emit(n)
	table.insert(alive, { at = now, n = n })
end

-- Sparkles at the local character's chest.
function Feel.sparkleSelf(color: Color3, count: number)
	local char = Players.LocalPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root then
		Feel.sparkle(root.Position + Vector3.new(0, 2, 0), color, count)
	end
end

function Feel.init()
	RunService:BindToRenderStep("PlanetFeelShake", Enum.RenderPriority.Camera.Value + 1, function()
		if shakeAmp <= 0 then
			return
		end
		local t = os.clock() - shakeStart
		if t >= shakeLife then
			shakeAmp = 0
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local x, y = Juice.shakeOffset(shakeAmp, t, shakeLife)
		cam.CFrame = cam.CFrame * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, x * 0.01)
	end)
end

return Feel
