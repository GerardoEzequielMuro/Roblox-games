--!strict
-- Game-feel helpers for the HUD, all code-only and cheap:
--   Feel.roll(label, value, format)   counter that rolls up (eased) to its new value
--   Feel.punch(obj, power)            squash / stretch pop of a UI element
--   Feel.floatText(anchor, text, c)   "+N" that floats up from an element and fades (pooled)
-- "Visual effects" off (Settings) = reduced motion: values jump, nothing pops or floats.
-- Lite profile = fewer floating texts at once.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FeelMath = require(ReplicatedStorage.Shared.FeelMath)
local Kit = require(script.Parent.Kit)

local Feel = {}

local enabled = true
local lite = false
function Feel.setEffects(on: boolean)
	enabled = on
end
function Feel.setLite(on: boolean)
	lite = on
end
function Feel.effectsOn(): boolean
	return enabled
end

-- rolling counters ---------------------------------------------------------------------------------
type Roll = { from: number, to: number, t: number, dur: number, fmt: (number) -> string, shown: number }
local rolls: { [TextLabel]: Roll } = {}
local conn: RBXScriptConnection? = nil

local function step(dt: number)
	local any = false
	for label, r in rolls do
		if not label.Parent then
			rolls[label] = nil
		else
			r.t += dt
			local v = FeelMath.roll(r.from, r.to, r.t, r.dur)
			if v ~= r.shown then
				r.shown = v
				Kit.setRaw(label, r.fmt(v))
			end
			if r.t >= r.dur then
				rolls[label] = nil
			else
				any = true
			end
		end
	end
	if not any and conn then
		conn:Disconnect()
		conn = nil
	end
end

local current: { [TextLabel]: number } = {}
-- Shows `value` on the label, rolling from what it shows now. First call / reduced motion: instant.
function Feel.roll(label: TextLabel, value: number, fmt: (number) -> string)
	local from = current[label]
	current[label] = value
	if from == nil or from == value or not enabled then
		rolls[label] = nil
		Kit.setRaw(label, fmt(value))
		return
	end
	local active = rolls[label]
	if active then
		from = active.shown -- retarget from what is on screen
	end
	rolls[label] = { from = from, to = value, t = 0, dur = FeelMath.rollDuration(from, value), fmt = fmt, shown = from }
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
end

-- squash / stretch ---------------------------------------------------------------------------------
local punching: { [GuiObject]: boolean } = {}
function Feel.punch(obj: GuiObject, power: number?)
	if not enabled or punching[obj] then
		return
	end
	punching[obj] = true
	local scale = obj:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = obj
	local p = power or 0.25
	task.spawn(function()
		local t = 0
		while t < 0.4 and obj.Parent do
			local x = FeelMath.squash(t / 0.4, p)
			scale.Scale = x
			t += task.wait()
		end
		scale.Scale = 1
		punching[obj] = nil
	end)
end

-- floating "+N" ---------------------------------------------------------------------------------------
local POOL = 6
local floaters: { TextLabel } = {}
local nextFloat = 1
function Feel.floatText(anchor: GuiObject, text: string, color: Color3?)
	if not enabled or not anchor.Parent then
		return
	end
	local cap = if lite then 3 else POOL
	local gui = Kit.gui()
	local lab: TextLabel
	local existing = floaters[nextFloat]
	if existing and existing.Parent then
		lab = existing
	else
		lab = Kit.bold(gui, "", UDim2.fromOffset(120, 30), UDim2.new(), Kit.C.yellow, Vector2.new(0.5, 1), 26)
		lab.Name = "FloatText"
		lab.ZIndex = 40
		floaters[nextFloat] = lab
	end
	nextFloat = nextFloat % cap + 1
	Kit.setRaw(lab, text)
	lab.TextColor3 = color or Kit.C.yellow
	lab.TextTransparency = 0
	local stroke = lab:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local pos = anchor.AbsolutePosition + Vector2.new(anchor.AbsoluteSize.X / 2, 0)
	local gpos = gui.AbsolutePosition
	local start = UDim2.fromOffset(pos.X - gpos.X, pos.Y - gpos.Y + 4)
	lab.Position = start
	lab.Visible = true
	local rise = UDim2.fromOffset(pos.X - gpos.X, pos.Y - gpos.Y - 34)
	TweenService:Create(lab, TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rise }):Play()
	TweenService:Create(lab, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55), { TextTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55), { Transparency = 1 }):Play()
	end
end

return Feel
