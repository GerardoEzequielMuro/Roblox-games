--!strict
-- Client side of the first-session tutorial (pure rules: shared/Onboarding.luau).
--  * Onboarding.evaluate(state): the current step for the HUD objective (text, beam, pulse)
--  * a pulsing ring on the TAP button while the step is "tap"; wider and faster when idle
--  * a Skip button next to the objective (session only: the step is derived from the saved
--    profile, so rejoining resumes by itself and a skipped tutorial never traps anybody)
--  * the "new buttons unlocked" celebration when a HudUnlock button appears for the first time
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local HudUnlock = require(ReplicatedStorage.Shared.HudUnlock)
local Core = require(ReplicatedStorage.Shared.Onboarding)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Celebrate = require(script.Parent.Celebrate)
local Guide = require(script.Parent.Guide)
local Theme = require(script.Parent.UI.Theme)

local Onboarding = {}

local skipped = false
local tracker = Core.newTracker(os.clock())
local ring: Frame? = nil
local ringStroke: UIStroke? = nil
local ringTween: Tween? = nil
local skipButton: TextButton? = nil
local ringMode = "" -- "", "tap", "help"
local changedHooks: { () -> () } = {}
local setRing: (mode: string) -> ()

local function rootPart(): BasePart?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The step for this snapshot. Safe to call every refresh.
function Onboarding.evaluate(s: { [string]: any }): Core.Step
	local root = rootPart()
	local egg = Guide.firstEggPosition()
	local near = root ~= nil and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(egg.X, 0, egg.Z)).Magnitude <= Config.EggRange + 2
	local base = Core.step(s, { skipped = skipped, nearEgg = near, targetOk = root ~= nil })
	local idle = Core.idle(tracker, base.id, Core.progressOf(s), os.clock())
	local step = if idle >= Core.HELP_AFTER then Core.step(s, { skipped = skipped, nearEgg = near, targetOk = root ~= nil, idle = idle }) else base
	Onboarding.syncUi(step)
	return step
end

function Onboarding.skip()
	skipped = true
	setRing("")
	if skipButton then
		skipButton.Visible = false
	end
	for _, f in changedHooks do
		f()
	end
end

function Onboarding.onChanged(f: () -> ())
	table.insert(changedHooks, f)
end

function Onboarding.skipped(): boolean
	return skipped
end

---------------------------------------------------------------------------
-- UI: pulse ring on the TAP button, Skip button
---------------------------------------------------------------------------
function Onboarding.attach(tapB: GuiObject, objective: GuiObject)
	local r = Theme.new("Frame", {
		Name = "TutorialRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = (tapB.ZIndex or 1) + 4,
		Parent = tapB,
	}, { Theme.corner(34) }) :: Frame
	ringStroke = Theme.new("UIStroke", { Color = Theme.Yellow, Thickness = 5, Transparency = 0.1, Parent = r }) :: UIStroke
	ring = r

	-- 120x56 hit area (>=44 px after the phone UIScale) (touch friendly) with a small chip drawn inside it, under the bar
	local b = Theme.new("TextButton", {
		Name = "SkipTutorial",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(120, 56),
		Visible = false,
		ZIndex = 6,
		Parent = objective,
	}) :: TextButton
	local chip = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(72, 26),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.4,
		ZIndex = 6,
		Parent = b,
	}, { Theme.corner(13), Theme.stroke(2) })
	local label = Theme.text({ Text = "", Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), MaxTextSize = 16, Parent = chip })
	label.ZIndex = 7
	Lang.bind(label, "ftue.skip")
	b.Activated:Connect(function()
		Theme.play("click", 0.3, 1)
		Onboarding.skip()
	end)
	skipButton = b
end

setRing = function(mode: string)
	if mode == ringMode then
		return
	end
	ringMode = mode
	if ringTween then
		ringTween:Cancel()
		ringTween = nil
	end
	local r, st = ring, ringStroke
	if not r or not st then
		return
	end
	if mode == "" then
		r.Visible = false
		return
	end
	r.Visible = true
	local big = mode == "help"
	r.Size = UDim2.new(1, 8, 1, 8)
	st.Transparency = 0.1
	-- one looping tween on the ring size; the stroke fades with the same timing
	local info = TweenInfo.new(if big then 0.55 else 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, false)
	local grow = if big then 34 else 20
	ringTween = TweenService:Create(r, info, { Size = UDim2.new(1, 8 + grow, 1, 8 + grow) })
	;(ringTween :: Tween):Play()
	TweenService:Create(st, info, { Transparency = 0.95 }):Play()
end

function Onboarding.syncUi(step: Core.Step)
	setRing(if step.pulse == "tap" then (if step.help then "help" else "tap") else "")
	if skipButton then
		skipButton.Visible = step.skippable
	end
end

---------------------------------------------------------------------------
-- Unlock celebration
---------------------------------------------------------------------------
local prevVisible: { [string]: boolean }? = nil
local prevZones = 0

function Onboarding.init()
	Net.Changed:Connect(function(kind)
		local s = Net.state
		if not s or kind ~= "full" then
			return
		end
		local vis = HudUnlock.visible(s)
		-- the first snapshot of a session only sets the baseline (no replay on rejoin)
		local new = Core.newlyUnlocked(prevVisible, vis)
		local latched = prevVisible or {}
		for k, v in vis do
			if v then
				latched[k] = true
			end
		end
		prevVisible = latched
		if #new > 0 then
			Celebrate.unlock(new)
		end
		local zones = #(s.zones or { 1 })
		if prevZones > 0 and zones > prevZones then
			Celebrate.burst(nil, Theme.Teal, 16)
		end
		prevZones = zones
	end)
end

return Onboarding
