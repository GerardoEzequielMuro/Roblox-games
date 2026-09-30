--!strict
-- "The lights go down": the tension layer. The base is a UI veil (a dark tint plus four
-- edge gradients that make a vignette) and it works on any graphics level; Lighting and
-- colour grading are added on top when the device can show them. Also the heartbeat pulse,
-- the blackout beat and the screen flashes.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local Prefs = require(script.Parent.Parent.Prefs)
local Audio = require(script.Parent.Parent.Audio)

local Mood = {}

Mood.level = 0 -- 0 = lobby light, 1 = full suspense
Mood.beats = 0 -- heartbeats played (playtest)
Mood.blackouts = 0

local tint = Theme.new("Frame", {
	Name = "Tint",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(4, 4, 16),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = Root.veil,
}) :: Frame

local edges: { Frame } = {}
local function edge(name: string, size: UDim2, pos: UDim2, anchor: Vector2, rotation: number)
	local f = Theme.new("Frame", {
		Name = name,
		Size = size,
		Position = pos,
		AnchorPoint = anchor,
		BackgroundColor3 = Color3.fromRGB(2, 2, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = Root.veil,
	}, {
		Theme.new("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 0.62), NumberSequenceKeypoint.new(1, 1) }),
		}),
	}) :: Frame
	table.insert(edges, f)
end
edge("Top", UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90)
edge("Bottom", UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270)
edge("Left", UDim2.fromScale(0.34, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0)
edge("Right", UDim2.fromScale(0.34, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180)

local flashFrame = Theme.new("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 50,
	Parent = Root.overlay,
}) :: Frame

local target = 0
local speed = 2
local edgeColor = Color3.fromRGB(2, 2, 10)
local bpm = 0
local beatClock = 0
local pulse = 0

local lastLit = -1
local baseAmbient: Color3? = nil
local baseOutdoor: Color3? = nil
local baseBrightness: number? = nil

-- level 0..1, reached in `seconds`.
function Mood.set(level: number, seconds: number?)
	target = math.clamp(level, 0, 1)
	speed = 1 / math.max(0.05, seconds or 0.6)
end

-- Vignette colour: near-black normally, deep red in sudden death.
function Mood.color(c: Color3?)
	edgeColor = c or Color3.fromRGB(2, 2, 10)
	for _, f in edges do
		f.BackgroundColor3 = edgeColor
	end
end

-- Heartbeat at `beatsPerMinute` (0 stops it).
function Mood.heartbeat(beatsPerMinute: number)
	if bpm <= 0 and beatsPerMinute > 0 then
		beatClock = 0
	end
	bpm = beatsPerMinute
end

-- The screen goes black for a beat (the moment before a deadly result shows).
function Mood.blackout(seconds: number)
	Mood.blackouts += 1
	flashFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	flashFrame.BackgroundTransparency = 0
	task.delay(seconds, function()
		TweenService:Create(flashFrame, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
	end)
end

function Mood.flash(color: Color3, alpha: number, seconds: number)
	local a = if Prefs.flashes() then alpha else alpha * 0.3
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - a
	TweenService:Create(flashFrame, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

function Mood.reset()
	Mood.set(0, 0.5)
	Mood.heartbeat(0)
	Mood.color(nil)
end

-- Darkness the veil is showing right now (0..1), for the playtest.
function Mood.darkness(): number
	return 1 - edges[1].BackgroundTransparency
end

RunService.RenderStepped:Connect(function(dt)
	if Mood.level ~= target then
		local step = speed * dt
		if math.abs(target - Mood.level) <= step then
			Mood.level = target
		else
			Mood.level += if target > Mood.level then step else -step
		end
	end
	local level = Mood.level
	if bpm > 0 then
		beatClock += dt * bpm / 60
		if beatClock >= 1 then
			beatClock -= 1
			pulse = 1
			Mood.beats += 1
			Audio.play("heartbeat", 0.35 + 0.3 * level, 0.55)
		end
		pulse = math.max(0, pulse - dt * 3.2)
	else
		pulse = 0
	end
	if level <= 0.001 and pulse <= 0.001 then
		if tint.BackgroundTransparency < 1 then
			tint.BackgroundTransparency = 1
			for _, f in edges do
				f.BackgroundTransparency = 1
			end
		end
	else
		tint.BackgroundTransparency = 1 - 0.3 * level
		local e = math.clamp(level * 0.92 + pulse * 0.18, 0, 1)
		for _, f in edges do
			f.BackgroundTransparency = 1 - e
		end
	end
	-- extras for devices that can show them (only touched while the level moves)
	if level ~= lastLit and not Prefs.lite() then
		lastLit = level
		if not baseAmbient then
			baseAmbient, baseOutdoor, baseBrightness = Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness
		end
		if baseAmbient and baseOutdoor and baseBrightness then
			local dark = Color3.fromRGB(34, 30, 60)
			Lighting.Ambient = baseAmbient:Lerp(dark, level * 0.75)
			Lighting.OutdoorAmbient = baseOutdoor:Lerp(dark, level * 0.75)
			Lighting.Brightness = baseBrightness * (1 - level * 0.5)
			local grade = Lighting:FindFirstChild("Grade") :: ColorCorrectionEffect?
			if grade then
				grade.Contrast = 0.06 + level * 0.14
				grade.Saturation = 0.12 + level * 0.1
			end
		end
	end
end)

return Mood
