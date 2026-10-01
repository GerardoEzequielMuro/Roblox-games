--!nonstrict
-- Objective tracker: the current story step at the top of the screen (one instruction, with a
-- progress bar and its reward), a "how" line for the first-minute tutorial steps, a guide beam
-- to the place the step points at, and the fanfare when a step is done.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Goals = require(ReplicatedStorage.Shared.Goals)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Toasts = require(script.Parent.Toasts)
local Windows = require(script.Parent.Windows)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Fx = require(script.Parent.Parent.Fx)
local StoryText = require(script.Parent.Parent.StoryText)

local QuestTracker = {}
local new = Theme.new
local touch = Root.isTouch
local player = Players.LocalPlayer

local panel: Frame
local title: TextLabel
local hint: TextLabel
local reward: TextLabel
local setBar: (number, string?) -> ()
QuestTracker.completed = 0 -- steps finished this session (playtest)

-- guide: a ribbon from the player to the target + a light pillar on it
local guidePart: Part? = nil
local guideBeam: Beam? = nil
local guideAtt: Attachment? = nil
local pillar: BasePart? = nil

local function clearGuide()
	if guideBeam then
		guideBeam:Destroy()
		guideBeam = nil
	end
	if guideAtt then
		guideAtt:Destroy()
		guideAtt = nil
	end
	if guidePart then
		guidePart:Destroy()
		guidePart = nil
	end
	if pillar then
		pillar:Destroy()
		pillar = nil
	end
end

local function setGuide(target: Vector3?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not target or not root then
		clearGuide()
		return
	end
	if guidePart and (guidePart.Position - target).Magnitude < 1 and guideAtt and guideAtt.Parent == root then
		return
	end
	clearGuide()
	local p = Instance.new("Part")
	p.Name = "KiwGuide"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(target)
	p.Parent = Fx.folder
	local a1 = Instance.new("Attachment")
	a1.Parent = p
	local a0 = Instance.new("Attachment")
	a0.Name = "KiwGuideAtt"
	a0.Position = Vector3.new(0, -2.4, 0)
	a0.Parent = root
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Width0 = 1.4
	beam.Width1 = 1.4
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 226, 90))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.15, 0.25), NumberSequenceKeypoint.new(1, 0.25) })
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Parent = p
	local pil = Instance.new("Part")
	pil.Shape = Enum.PartType.Cylinder
	pil.Anchored = true
	pil.CanCollide = false
	pil.CanQuery = false
	pil.CanTouch = false
	pil.CastShadow = false
	pil.Material = Enum.Material.Neon
	pil.Color = Color3.fromRGB(255, 226, 90)
	pil.Transparency = 0.45
	pil.Size = Vector3.new(90, 2.2, 2.2)
	pil.CFrame = CFrame.new(target + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pil.Parent = Fx.folder
	guidePart, guideBeam, guideAtt, pillar = p, beam, a0, pil
end
QuestTracker.guideTarget = function(): Vector3?
	return if guidePart then guidePart.Position else nil
end

-- HUD pointer: pulsing ring + bobbing arrow on the button the tutorial step asks for. It
-- follows the real GuiObject every frame and hides itself if that button is missing / hidden,
-- so a layout change can never leave a dangling arrow.
local pointer: Frame
local pointerArrow: TextLabel
local pointerStroke: UIStroke
local pointerName: string? = nil
local stuck = 0 -- Onboarding.stuckLevel of the current step
local tracker: Onboarding.Tracker? = nil
local skipBtn: TextButton

local cached: GuiObject? = nil
local cachedName: string? = nil
local cachedAt = 0
local function findTarget(name: string): GuiObject?
	local now = os.clock()
	-- the recursive search runs at most once a second (the HUD can be rebuilt by a language switch)
	if cachedName ~= name or not cached or not cached:IsDescendantOf(Root.gui) or now - cachedAt > 1 then
		cachedName, cachedAt = name, now
		local found = Root.gui:FindFirstChild(name, true)
		cached = if found and found:IsA("GuiObject") then found else nil
	end
	local c = cached
	if c and c.Visible and c.AbsoluteSize.X > 4 then
		return c
	end
	return nil
end

local function updatePointer()
	local target = if pointerName then findTarget(pointerName) else nil
	if not target then
		pointer.Visible = false
		return
	end
	local origin = Root.gui.AbsolutePosition
	local pos = target.AbsolutePosition - origin
	local size = target.AbsoluteSize
	local pad = 8
	pointer.Position = UDim2.fromOffset(pos.X - pad, pos.Y - pad)
	pointer.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
	pointer.Visible = true
	local t = os.clock()
	local loud = stuck >= 1
	pointerStroke.Thickness = if loud then 5 else 3.5
	pointerStroke.Transparency = 0.1 + (math.sin(t * 6) * 0.5 + 0.5) * 0.4
	-- arrow above the button (below it when the button hugs the top of the screen)
	local below = pos.Y < 70
	pointerArrow.Text = if below then "▲" else "▼"
	local bob = math.sin(t * 7) * 5
	pointerArrow.Position = if below then UDim2.new(0.5, 0, 1, 2 + bob) else UDim2.new(0.5, 0, 0, -2 - bob)
	pointerArrow.AnchorPoint = if below then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)
end

local function refresh()
	local s = Net.state
	if not s or not s.story then
		return
	end
	local step = Config.Story[s.story.step]
	if not step then
		-- story done: the closest power goal (next form / planet / ascension) stays on screen
		local goal = Goals.next(math.max(s.power or 0, s.bestPower or 0), s.forms or 0, s.planets or { 1 }, s.rebirths or 0)
		panel.Visible = true
		local name = if goal.kind == "rebirth" then "" else Lang.t(goal.kind .. "." .. goal.id)
		title.Text = Lang.t("goal." .. goal.kind, { name = name, power = Format.abbrev(goal.need), n = goal.id })
		setBar(goal.frac, Format.abbrev(goal.have) .. " / " .. Format.abbrev(goal.need))
		reward.Text = ""
		hint.Visible = false
		pointerName = nil
		skipBtn.Visible = false
		clearGuide()
		return
	end
	panel.Visible = true
	title.Text = StoryText.text(step)
	setBar(s.story.progress / step.target, Format.abbrev(math.floor(s.story.progress)) .. " / " .. Format.abbrev(step.target))
	local parts = {}
	if step.sparks and step.sparks > 0 then
		table.insert(parts, "⚡" .. Format.abbrev(step.sparks))
	end
	if step.gems and step.gems > 0 then
		table.insert(parts, "💎" .. step.gems)
	end
	reward.Text = table.concat(parts, " ")
	local h = if s.story.step <= Config.TutorialSteps + 3 then StoryText.hint(step, touch) else nil
	hint.Text = h or ""
	hint.Visible = h ~= nil
	pointerName = if h ~= nil then Onboarding.pointerName(step.kind, touch) else nil
	-- idle clock: resets on any progress, so only a really stuck player sees the Skip button
	local idle
	tracker, idle = Onboarding.track(tracker, s.story.step, s.story.progress, os.clock())
	stuck = Onboarding.stuckLevel(idle)
	skipBtn.Visible = stuck >= 2 and Onboarding.canSkip(s.story.step, step.kind, Config.TutorialSteps)
	if stuck >= 1 and h ~= nil then
		hint.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		hint.TextColor3 = Theme.Yellow
	end
	setGuide(StoryText.target(step))
end

function QuestTracker.init()
	-- PC: top centre. Touch: top right (the left column is vitals + auto toggles, the centre
	-- is the training dock), two-line title over the bar, 54 px tall so it is a real button.
	panel = Theme.panel({
		Name = "Objective",
		Size = if touch then UDim2.fromOffset(184, 64) else UDim2.fromOffset(400, 46),
		Position = if touch then UDim2.new(1, -8, 0, 6) else UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0),
		Accent = Theme.Yellow,
		Corner = 12,
		Parent = Root.gui,
	})
	new("UIScale", { Parent = panel })
	local holder = Root.mount(panel)
	local _ = holder
	if touch then
		title = Theme.text({ Name = "Title", Text = "", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 7), MaxTextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = panel })
		reward = Theme.text({ Name = "Reward", Text = "", Font = Theme.Display, Size = UDim2.fromOffset(70, 20), Position = UDim2.new(1, -6, 1, -7), AnchorPoint = Vector2.new(1, 1), MaxTextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow, Parent = panel })
		local _bar
		_bar, setBar = Theme.bar({ Name = "Progress", Size = UDim2.fromOffset(98, 20), Position = UDim2.new(0, 8, 1, -7), AnchorPoint = Vector2.new(0, 1), Color = Theme.Yellow, TextSize = 13, Stroke = 1.5, Corner = 6, Parent = panel })
		hint = Theme.text({ Name = "Hint", Text = "", Size = UDim2.fromOffset(200, 28), Position = UDim2.new(1, 0, 1, 4), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 20, Stroke = 3, TextColor3 = Theme.Yellow, TextXAlignment = Enum.TextXAlignment.Right, Parent = panel })
	else
		title = Theme.text({ Name = "Title", Text = "", Size = UDim2.new(1, -90, 0, 20), Position = UDim2.fromOffset(10, 8), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
		reward = Theme.text({ Name = "Reward", Text = "", Font = Theme.Display, Size = UDim2.fromOffset(76, 20), Position = UDim2.new(1, -8, 0, 8), AnchorPoint = Vector2.new(1, 0), MaxTextSize = 17, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Yellow, Parent = panel })
		local _bar
		_bar, setBar = Theme.bar({ Name = "Progress", Size = UDim2.new(1, -20, 0, 12), Position = UDim2.new(0, 10, 1, -16), Color = Theme.Yellow, TextSize = 10, Stroke = 1.5, Corner = 5, Parent = panel })
		hint = Theme.text({ Name = "Hint", Text = "", Size = UDim2.fromOffset(560, 30), Position = UDim2.new(0.5, 0, 1, 6), AnchorPoint = Vector2.new(0.5, 0), MaxTextSize = 22, Stroke = 3, TextColor3 = Theme.Yellow, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
	end
	-- pointer ring over the HUD button the step wants (starts hidden)
	pointer = new("Frame", { Name = "TutorialPointer", BackgroundTransparency = 1, Visible = false, ZIndex = 40, Parent = Root.gui }, { Theme.corner(14) })
	pointerStroke = new("UIStroke", { Color = Theme.Yellow, Thickness = 3.5, Parent = pointer })
	pointerArrow = Theme.text({ Name = "Arrow", Text = "▼", Size = UDim2.fromOffset(40, 30), Position = UDim2.new(0.5, 0, 0, -2), AnchorPoint = Vector2.new(0.5, 1), MaxTextSize = 30, Stroke = 3, TextColor3 = Theme.Yellow, ZIndex = 41, Parent = pointer })
	-- "Skip": only appears after a while without progress on a first-minute step
	skipBtn = Theme.button({ Name = "SkipStep", Key = "tut.skip", Color = Theme.Grey, Size = if touch then UDim2.fromOffset(110, 44) else UDim2.fromOffset(100, 32), Position = if touch then UDim2.new(1, 0, 1, 36) else UDim2.new(0.5, 0, 1, 40), AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0), TextSize = 16, ZIndex = 45, Parent = panel, OnClick = function()
		skipBtn.Visible = false
		local ok = Net.request("SkipStep")
		if not ok then
			tracker = nil -- try again later
		end
	end })
	skipBtn.Visible = false
	local click = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = panel })
	click.Activated:Connect(function()
		Windows.toggle("Quests")
	end)

	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
	Lang.Changed:Connect(refresh)
	player.CharacterAdded:Connect(function()
		clearGuide()
		task.delay(1, refresh)
	end)

	Net.event("Quests").OnClientEvent:Connect(function(d)
		local s = Net.state
		if type(d) ~= "table" or not s then
			return
		end
		if d.story then
			s.story = d.story
			refresh()
		end
		if d.daily then
			s.quests = d.daily
		end
		if d.storyDone then
			QuestTracker.completed += 1
			local step = Config.Story[d.storyDone]
			local parts = {}
			if d.sparks > 0 then
				table.insert(parts, "+" .. Format.abbrev(d.sparks) .. " ⚡")
			end
			if d.gems > 0 then
				table.insert(parts, "+" .. d.gems .. " 💎")
			end
			if d.skipped then
				tracker = nil
			end
			Toasts.banner("✔ " .. (if step then StoryText.text(step) else "") .. "   " .. table.concat(parts, "  "), Theme.Green)
			Theme.pop(panel, 1.15)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				Fx.ring(root.Position - Vector3.new(0, 2.6, 0), 2, 14, Color3.fromRGB(255, 226, 90), 0.45, 0.5)
				Fx.sparks(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 226, 90), 10, 36, 0.5)
			end
		end
	end)

	-- hint wiggle + guide upkeep
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if hint.Visible then
			hint.Rotation = math.sin(os.clock() * 3) * (if stuck >= 1 then 3 else 1.5)
		end
		updatePointer()
		if acc > 1 then
			acc = 0
			refresh()
		end
	end)
	local tween = TweenService
	local _2 = tween
	refresh()
end

return QuestTracker
