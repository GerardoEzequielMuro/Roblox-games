--!strict
-- First-session guide: ONE short hint at a time (3-6 words), an arrow over the next pad and a Skip
-- button. The decision of what to show is Shared/Onboarding (pure, tested); this file only draws it.
--   * hint pill under the timer: pulses, never blocks input, Skip always there;
--   * a bobbing arrow over the next pad (placed from the layout, so it works even while that pad is
--     still streaming in) and, when the pad is off screen, an arrow on the screen edge pointing to it;
--   * after the first few stages: if the player can afford something and has not opened the shop,
--     the Menu button pulses and the pill says where to go (first purchase).
-- Everything is soft: if the target can't be computed the arrow is skipped and the text stays.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Sfx = require(script.Parent.Parent.Sfx)
local Kit = require(script.Parent.Kit)
local Progress = require(script.Parent.Progress)
local Juice = require(script.Parent.Parent.World.Juice)

local Guide = {}

local started = os.clock()
local skipped = false
local deaths = 0
local lastAt = -1
local crossedAt: number? = nil -- os.clock() when GOAL was reached during this session
local shopSeen = false
local effects = true
local lastKey: string? = nil

function Guide.setEffects(on: boolean)
	effects = on
end

-- the pad the player should go to next, from the layout (nil if it can't be worked out)
local function targetPos(at: number): Vector3?
	local nextStage = at + 1
	if nextStage > Layout.TOTAL or not Rules.canReach(Layout :: any, at, nextStage, 1, Net.state.base == true) then
		return nil
	end
	local found: Vector3? = nil
	pcall(function()
		found = Juice.padTop(nextStage)
	end)
	return found
end

local function findButton(name: string): GuiObject?
	local gui = Kit.gui()
	local b = gui:FindFirstChild(name, true)
	if b and b:IsA("GuiObject") then
		return b
	end
	return nil
end

function Guide.init()
	local player = Players.LocalPlayer
	local region = Kit.region("Guide", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2), Vector2.new(430, 56))
	region.Visible = false
	-- PC: under the timer. Touch: the free band above the level bar, between the thumbstick and the
	-- action column (the top-left corner block owns the top of the screen there).
	local skipBtn: TextButton? = nil
	Kit.onLayout(function(touch, area, scale)
		if skipBtn then
			skipBtn.Size = UDim2.fromOffset(64, if touch then 76 else 56) -- >= 44 px on a phone
		end
		if touch then
			local ls = math.min(scale, area.X * 0.4 / 420)
			region.AnchorPoint = Vector2.new(0.5, 1)
			region.Position = UDim2.new(0.46, 0, 0, area.Y - math.floor((Progress.LEVEL_H + 24) * ls))
			Kit.setScale(region, math.min(scale, area.X * 0.4 / 430))
		else
			region.AnchorPoint = Vector2.new(0.5, 0)
			region.Position = UDim2.fromScale(0.5, 0.2)
			Kit.setScale(region, scale)
		end
	end)
	local pill = Kit.frame(region, UDim2.new(1, -72, 1, 0), UDim2.new(), Color3.fromRGB(24, 28, 44))
	pill.Name = "Pill"
	pill.BackgroundTransparency = 0.2
	Kit.corner(pill, 28)
	local pst = Kit.stroke(pill, Kit.C.yellow, 3)
	pst.Transparency = 0.1
	local text = Kit.bold(pill, "", UDim2.new(1, -28, 1, -14), UDim2.fromOffset(14, 7), Kit.C.white, nil, 28)
	text.Name = "Hint"
	local skip = Kit.button(region, "@guide.skip", UDim2.fromOffset(64, 56), UDim2.fromScale(1, 0.5), Kit.C.grey, function()
		skipped = true
		Guide.refresh()
	end, Vector2.new(1, 0.5), 22)
	skip.Name = "Skip"
	skipBtn = skip
	Kit.relayout()
	local pulse = Instance.new("UIScale")
	pulse.Parent = pill

	-- 3D arrow over the next pad -----------------------------------------------------------------
	local anchor = Instance.new("Part")
	anchor.Name = "GuideAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(0, -500, 0)
	anchor.Parent = Workspace
	local board = Instance.new("BillboardGui")
	board.Name = "GuideArrow"
	board.Adornee = anchor
	board.AlwaysOnTop = true
	board.Size = UDim2.fromOffset(84, 110)
	board.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	board.LightInfluence = 0
	board.MaxDistance = 600
	board.Enabled = false
	board.ResetOnSpawn = false
	board.Parent = player:WaitForChild("PlayerGui")
	local arrow = Kit.bold(board, "▼", UDim2.new(1, 0, 0, 70), UDim2.new(), Kit.C.yellow, nil, 70)
	arrow.TextScaled = false
	arrow.TextSize = 64
	local dist = Kit.bold(board, "", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 72), Kit.C.white, nil, 24)
	dist.TextScaled = false
	dist.TextSize = 22
	local bob = TweenService:Create(arrow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 12) })
	local bobbing = false

	-- edge arrow: where to look when the pad is off screen
	local edgeGui = Instance.new("ScreenGui")
	edgeGui.Name = "SkyTowerGuideEdge"
	edgeGui.IgnoreGuiInset = true
	edgeGui.ResetOnSpawn = false
	edgeGui.DisplayOrder = 5
	edgeGui.Parent = player:WaitForChild("PlayerGui")
	local edge = Kit.bold(edgeGui, "►", UDim2.fromOffset(52, 52), UDim2.new(), Kit.C.yellow, Vector2.new(0.5, 0.5), 44)
	edge.TextScaled = false
	edge.TextSize = 44
	edge.Visible = false
	edge.Active = false

	-- glow on a UI element (the Menu button for the first purchase) --------------------------------
	local glows: { Frame } = {}
	local function clearGlows()
		for _, g in glows do
			g:Destroy()
		end
		table.clear(glows)
	end
	local function glowOn(target: GuiObject?)
		if not target then
			return
		end
		local g = Instance.new("Frame")
		g.Name = "GuideGlow"
		g.Size = UDim2.new(1, 8, 1, 8)
		g.Position = UDim2.fromOffset(-4, -4)
		g.BackgroundTransparency = 1
		g.ZIndex = target.ZIndex + 5
		g.Active = false
		g.Parent = target
		Kit.corner(g, 16)
		local st = Kit.stroke(g, Kit.C.yellow, 5)
		if effects then
			TweenService:Create(st, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.7 }):Play()
		end
		table.insert(glows, g)
	end

	local glowKey: string? = nil
	local view: Onboarding.View = Onboarding.view({
		at = 0, skipped = true, elapsed = 0, deaths = 0, targetKnown = false, coins = 0, shopCoins = 0, shopSeen = true, crossed = false, sinceGoal = 0,
	})

	local function at(): number
		local s = Net.state
		return if type(s.at) == "number" then s.at elseif type(s.stage) == "number" then s.stage else 0
	end

	function Guide.refresh()
		local s = Net.state
		local now = os.clock()
		local a = at()
		if a ~= lastAt then
			if lastAt >= 0 and a > lastAt then
				deaths = 0
			end
			if lastAt >= 0 and lastAt < Onboarding.GOAL and a >= Onboarding.GOAL then
				crossedAt = now
			end
			lastAt = a
		end
		local pos = targetPos(a)
		view = Onboarding.view({
			at = a,
			skipped = skipped,
			elapsed = now - started,
			deaths = deaths,
			targetKnown = pos ~= nil,
			coins = tonumber(s.coins) or 0,
			shopCoins = Economy.TrailPrice.white,
			shopSeen = shopSeen,
			crossed = crossedAt ~= nil,
			sinceGoal = if crossedAt then now - crossedAt else 0,
		})
		-- nothing to say before the first State arrives (the loading card is still up)
		local ready = s.stage ~= nil or s.at ~= nil
		local on = view.textKey ~= nil and ready
		region.Visible = on
		if on and view.textKey then
			if view.textKey ~= lastKey then
				lastKey = view.textKey
				Kit.setText(text, view.textKey)
				Sfx.play("hint")
				if effects then
					Kit.pop(pill, 0.7)
				end
			end
		else
			lastKey = nil
		end
		-- arrow
		local arrowOn = on and view.arrow and pos ~= nil
		if arrowOn and pos then
			anchor.CFrame = CFrame.new(pos)
		else
			anchor.CFrame = CFrame.new(0, -500, 0)
		end
		board.Enabled = arrowOn
		if arrowOn and effects and not bobbing then
			bobbing = true
			bob:Play()
		elseif (not arrowOn or not effects) and bobbing then
			bobbing = false
			bob:Cancel()
			arrow.Position = UDim2.new()
		end
		if not arrowOn then
			edge.Visible = false
		end
		-- glow
		local wantGlow = if on then view.glow else nil
		if wantGlow ~= glowKey then
			glowKey = wantGlow
			clearGlows()
			if wantGlow == "menu" then
				glowOn(findButton("MenuButton"))
			end
		end
	end

	-- distance label + off-screen arrow, a few times a second and only while the arrow is up
	task.spawn(function()
		while true do
			task.wait(0.2)
			if board.Enabled then
				local cam = Workspace.CurrentCamera
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					dist.Text = ("%d m"):format(math.floor((anchor.Position - root.Position).Magnitude))
				end
				if cam then
					local ok = pcall(function()
						local v, onScreen = cam:WorldToViewportPoint(anchor.Position + Vector3.new(0, 8, 0))
						if onScreen and v.Z > 0 then
							edge.Visible = false
							return
						end
						local size = cam.ViewportSize
						local c = size / 2
						local dir = Vector2.new(v.X - c.X, v.Y - c.Y)
						if v.Z < 0 then
							dir = -dir
						end
						if dir.Magnitude < 1 then
							dir = Vector2.new(0, 1)
						end
						dir = dir.Unit
						local k = math.min((c.X - 50) / math.max(math.abs(dir.X), 1e-3), (c.Y - 70) / math.max(math.abs(dir.Y), 1e-3))
						local p = c + dir * k
						edge.Position = UDim2.fromOffset(p.X, p.Y)
						edge.Rotation = math.deg(math.atan2(dir.Y, dir.X))
						edge.Visible = true
					end)
					if not ok then
						edge.Visible = false
					end
				end
			end
			Guide.refresh()
		end
	end)

	-- soft pulse of the pill (reduced motion: static)
	task.spawn(function()
		while true do
			if region.Visible and effects then
				TweenService:Create(pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1.05 }):Play()
				task.wait(0.55)
				TweenService:Create(pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1 }):Play()
				task.wait(0.55)
			else
				pulse.Scale = 1
				task.wait(0.5)
			end
		end
	end)

	-- deaths since the last checkpoint (turns the hint into advice)
	local function onCharacter(char: Model)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Once(function()
				deaths += 1
				Guide.refresh()
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	Kit.panelChanged:Connect(function(name)
		if name == "shop" then
			shopSeen = true
		end
		Guide.refresh()
	end)
	Net.changed:Connect(Guide.refresh)
	Lang.changed:Connect(function()
		lastKey = nil
		Guide.refresh()
	end)
	RunService.Heartbeat:Wait()
	Guide.refresh()
end

function Guide.refresh() end

return Guide
