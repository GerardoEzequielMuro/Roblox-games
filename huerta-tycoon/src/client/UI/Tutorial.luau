--!nonstrict
-- First-time tutorial: buy seed -> plant -> harvest -> sell. Steps are derived from state, so it can't get stuck.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)
local Toasts = require(script.Parent.Toasts)
local Tiles = require(script.Parent.Tiles)
local Teleport = require(script.Parent.Teleport)
local Layout = require(script.Parent.Layout)
local Juice = require(script.Parent.Juice)
local Perf = require(script.Parent.Perf)
local Sound = require(script.Parent.Sound)
local Onboarding = require(game:GetService("ReplicatedStorage").Shared.Onboarding)

local player = Players.LocalPlayer

local Tutorial = {}

export type Refs = {
	shopButton: GuiObject?,
	hotbar: GuiObject?,
	sellButton: GuiObject?,
}


function Tutorial.init(root: Instance, refs: Refs)
	local active = false
	local finished = false
	local baselineEarned: number? = nil
	local step = 0

	-- Instruction card. PC: above the basket bar (and above the "Teleport to Sell" button).
	-- Touch: top-center under the weather banner, away from the thumbstick/jump zones.
	local card: Frame = C.new("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -236),
		Size = UDim2.fromOffset(520, 64),
		BackgroundColor3 = Theme.C.Yellow,
		Visible = false,
		ZIndex = 6,
		Parent = root,
	})
	C.corner(card, 18)
	C.stroke(card, 4, Theme.C.PanelEdge)
	C.shade(card)
	local cardScale = C.new("UIScale", { Parent = card })
	local stepLbl = C.label(card, "1/4", UDim2.fromOffset(56, 56), {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.C.Orange,
		TextSize = 20,
		ZIndex = 7,
	})
	C.round(stepLbl)
	local text = C.label(card, "", UDim2.new(1, -176, 1, -8), {
		Position = UDim2.fromOffset(72, 4),
		TextSize = 20,
		TextColor3 = Theme.C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Outline = false,
		ZIndex = 7,
	})
	local skip = C.button({
		Parent = card,
		Text = L("tut.skip"),
		TextSize = 18,
		Color = Theme.C.Grey,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(90, 56),
	})
	skip.ZIndex = 7
	local skipGlow = C.stroke(skip, 0, Theme.C.Green)
	skipGlow.Name = "StuckGlow"
	-- small "Stuck? You can Skip" pill under the card, only after the player has been on one step for a while
	local stuckLbl = C.label(card, "", UDim2.fromOffset(300, 24), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		TextSize = 16,
		Visible = false,
		ZIndex = 7,
	})
	I18n.set(stuckLbl, "Text", L("tut.stuck"))

	Layout.onChanged(function()
		if Layout.stacked then
			-- right of the 5x2 touch menu, left of the action column, under the weather banner + event pill
			card.AnchorPoint = Vector2.new(0.5, 0)
			card.Position = UDim2.new(0.55, 0, 0, 70)
			card.Size = UDim2.fromOffset(380, 76)
			text.TextSize = 17
		else
			card.AnchorPoint = Vector2.new(0.5, 1)
			card.Position = UDim2.new(0.5, 0, 1, -236)
			card.Size = UDim2.fromOffset(520, 64)
			text.TextSize = 20
		end
	end)

	-- Bouncing GUI arrow (re-parented to the current target button)
	local guiArrow = C.label(nil, "👇", UDim2.fromOffset(60, 60), {
		Name = "TutorialArrow",
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 50,
		Outline = false,
		ZIndex = 20,
	})

	-- World arrow + beam
	local worldArrow: BillboardGui = C.new("BillboardGui", {
		Name = "TutorialWorldArrow",
		Size = UDim2.fromOffset(110, 110),
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
	})
	C.label(worldArrow, "⬇️", UDim2.fromScale(1, 1), { TextSize = 80, Outline = false })
	local targetAtt: Attachment = C.new("Attachment", { Name = "TutorialTarget" })
	local playerAtt: Attachment = C.new("Attachment", { Name = "TutorialFrom" })
	local beam: Beam = C.new("Beam", {
		Name = "TutorialBeam",
		Attachment0 = playerAtt,
		Attachment1 = targetAtt,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 80), Color3.fromRGB(120, 255, 120)),
		Transparency = NumberSequence.new(0.25),
		Width0 = 0.6,
		Width1 = 0.6,
		FaceCamera = true,
		LightEmission = 1,
		Segments = 1,
	})

	-- pulsing outline on the GUI target and a soft highlight on the world target (skipped on lite devices)
	local glow: UIStroke = C.new("UIStroke", {
		Name = "TutorialGlow",
		Color = Theme.C.Yellow,
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local worldGlow: Highlight? = nil
	if not Perf.lite then
		local ok, h = pcall(function()
			return C.new("Highlight", {
				Name = "TutorialHighlight",
				FillColor = Color3.fromRGB(255, 240, 80),
				OutlineColor = Color3.fromRGB(255, 255, 255),
				FillTransparency = 0.7,
				DepthMode = Enum.HighlightDepthMode.Occluded,
			})
		end)
		if ok then
			worldGlow = h
		end
	end

	local arrowBaseY = 6
	local guiTarget: GuiObject? = nil
	local guiSide = "top"

	local function setGuiTarget(target: GuiObject?, side: string?)
		guiTarget = target
		guiSide = side or "top"
		if target and target.Parent then
			glow.Parent = target
			guiArrow.Parent = target
			guiArrow.Text = if guiSide == "right" then "👈" else "👇"
			guiArrow.AnchorPoint = if guiSide == "right" then Vector2.new(0, 0.5) else Vector2.new(0.5, 1)
		else
			guiTarget = nil
			glow.Parent = nil
			guiArrow.Parent = nil
		end
	end

	local function setWorldTarget(part: Instance?)
		local bp: BasePart? = nil
		if part and part:IsA("BasePart") then
			bp = part
		elseif part and part:IsA("Model") then
			bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart", true)
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if worldGlow then
			worldGlow.Adornee = bp
			worldGlow.Parent = if bp then workspace.Terrain else nil
		end
		if bp then
			worldArrow.Adornee = bp
			arrowBaseY = bp.Size.Y / 2 + 5
			worldArrow.Parent = player:FindFirstChild("PlayerGui")
			targetAtt.Parent = bp
			targetAtt.Position = Vector3.new(0, bp.Size.Y / 2, 0)
			if hrp then
				playerAtt.Parent = hrp
				beam.Parent = hrp
			else
				beam.Parent = nil
			end
		else
			(worldArrow :: any).Adornee = nil
			worldArrow.Parent = nil
			beam.Parent = nil
			targetAtt.Parent = nil
		end
	end

	local function stop()
		active = false
		card.Visible = false
		setGuiTarget(nil)
		setWorldTarget(nil)
		skipGlow.Thickness = 0
		if worldGlow then
			worldGlow.Parent = nil
		end
	end

	local function finish(silent: boolean?)
		if finished then
			return
		end
		finished = true
		stop()
		Net.request("FinishTutorial", nil, { quiet = true, silentOk = true })
		if not silent then
			Toasts.show(L("tut.done"), "success")
			Juice.confetti(24)
		end
	end

	skip.Activated:Connect(function()
		finish(true)
	end)

	local function findTile(pred: (BasePart) -> boolean): BasePart?
		for _, t in Tiles.ownTiles() do
			if pred(t) then
				return t
			end
		end
		return nil
	end

	local startedAt = os.clock()
	local stepSince = os.clock()
	local function evaluate()
		local d = State.data
		if finished or not d then
			return
		end
		if d.tutorialDone then
			finished = true
			stop()
			return
		end
		if baselineEarned == nil then
			baselineEarned = d.totalEarned or 0
			startedAt = os.clock()
			-- rejoined after already selling: nothing left to teach (and never a stale step)
			if Onboarding.alreadyPlayed(baselineEarned :: number) then
				finish(true)
				return
			end
		end
		if (d.totalEarned or 0) > (baselineEarned :: number) then
			finish(false)
			return
		end
		-- safety net: a tutorial that can't progress for minutes ends by itself
		if Onboarding.giveUp(os.clock() - startedAt) then
			finish(true)
			return
		end
		active = true

		local anyCrop = findTile(function(t)
			return t:GetAttribute("HasCrop") == true
		end)
		local ripeTile = findTile(function(t)
			return t:GetAttribute("Ripe") == true
		end)
		local facts: Onboarding.Facts = {
			backpackCount = d.backpackCount or 0,
			hasCrop = anyCrop ~= nil,
			ripe = ripeTile ~= nil,
			seeds = State.totalSeeds(),
		}
		local newStep = Onboarding.step(facts)

		if newStep ~= step then
			local prev = step
			step = newStep
			stepSince = os.clock()
			card.Visible = true
			stepLbl.Text = step .. "/" .. Onboarding.STEPS
			cardScale.Scale = 0.7
			C.tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			if prev > 0 and newStep > prev then
				-- a step is done: the badge flashes green and the card pops
				Sound.play("step")
				stepLbl.BackgroundColor3 = Theme.C.Green
				task.delay(0.5, function()
					stepLbl.BackgroundColor3 = Theme.C.Orange
				end)
				if prev == 3 then
					-- first harvest: the first "wow"
					Juice.banner(I18n.t("tut.wow"), "", Theme.C.Gold, 1)
					Juice.confetti(10)
				end
			end
		end
		-- text follows the sub-state (pick a seed / tap a tile / growing / ripe)
		I18n.set(text, "Text", L(Onboarding.textKey(step, facts, State.selectedSeed ~= nil)))

		-- stuck on one step for a while: the Skip button pulses and a hint shows
		local isStuck = Onboarding.stuck(os.clock() - stepSince)
		stuckLbl.Visible = isStuck
		if not isStuck then
			skipGlow.Thickness = 0
		end

		local function pick(preferred: Instance?, fallback: Instance?): Instance?
			local mode = Onboarding.targetFallback(preferred ~= nil, fallback ~= nil)
			return if mode == 1 then preferred elseif mode == 2 then fallback else nil
		end
		local anyOwn = findTile(function()
			return true
		end)
		if step == 1 then
			setGuiTarget(refs.shopButton, "right")
			setWorldTarget(pick(Teleport.hubPart("SeedShop"), nil))
		elseif step == 2 then
			setGuiTarget(if State.selectedSeed then nil else refs.hotbar, "top")
			local free = findTile(function(t)
				return t:GetAttribute("Unlocked") == true and not t:GetAttribute("HasCrop")
			end)
			setWorldTarget(pick(free, anyOwn))
		elseif step == 3 then
			setGuiTarget(nil)
			setWorldTarget(pick(ripeTile, anyCrop))
		elseif step == 4 then
			setGuiTarget(refs.sellButton, "top")
			setWorldTarget(pick(Teleport.hubPart("SellStand"), nil))
		end
	end

	-- bounce + pulse animation
	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local t = os.clock()
		local b = math.abs(math.sin(t * 5))
		local pulse = 0.5 + 0.5 * math.sin(t * 6)
		if guiTarget then
			if guiSide == "right" then
				guiArrow.Position = UDim2.new(1, 6 + b * 14, 0.5, 0)
			else
				guiArrow.Position = UDim2.new(0.5, 0, 0, -4 - b * 14)
			end
			glow.Thickness = 3 + pulse * 3
			glow.Transparency = 0.1 + (1 - pulse) * 0.5
		end
		if worldArrow.Adornee then
			worldArrow.StudsOffsetWorldSpace = Vector3.new(0, arrowBaseY + b * 1.2, 0)
		end
		if worldGlow and worldGlow.Parent then
			worldGlow.FillTransparency = 0.55 + (1 - pulse) * 0.35
		end
		if stuckLbl.Visible then
			skipGlow.Thickness = 2 + pulse * 4
		end
	end)

	State.onChanged(function(kind)
		if kind == "state" or kind == "selected" then
			evaluate()
		end
	end)
	task.spawn(function()
		while not finished do
			-- a bad frame (missing part, destroyed target) must never kill the loop
			local ok, err = pcall(evaluate)
			if not ok then
				warn("[Tutorial]", err)
			end
			task.wait(0.5)
		end
	end)
end

return Tutorial
