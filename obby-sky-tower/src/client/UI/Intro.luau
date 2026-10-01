--!strict
-- Branded loading card shown when you join: game name, tagline, the ten world colours popping in,
-- a progress bar and a tip. It covers the moment the character and the first State are still
-- arriving and goes away as soon as both are here (at least MIN_HOLD, so it never flashes) and no
-- later than MAX_HOLD seconds, whatever failed to load. Never blocks input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Kit)
local Progress = require(script.Parent.Progress)
local Net = require(script.Parent.Parent.Net)

local Intro = {}

Intro.MIN_HOLD = 1.8 -- seconds on screen at least (the world dots need ~1.4 s to pop in)
Intro.MAX_HOLD = 5 -- hard cap: the card leaves even if the state or the character never arrive
Intro.FADE = 0.5
Intro.TIPS = { "intro.tip1", "intro.tip2", "intro.tip3" }

function Intro.play()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkyTowerIntro"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BorderSizePixel = 0
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.Active = false
	card.Parent = gui
	Kit.gradient(card, Color3.fromRGB(70, 150, 255), Color3.fromRGB(150, 110, 255), 90)

	local title = Kit.bold(card, string.upper(Config.GameName), UDim2.fromScale(0.84, 0.24), UDim2.fromScale(0.5, 0.4), Kit.C.yellow, Vector2.new(0.5, 0.5), 120)
	title.Name = "Title"
	title.Rotation = -2
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 5
	end
	Kit.pop(title, 0.5)
	local tagline = Kit.bold(card, "@intro.tagline", UDim2.fromScale(0.8, 0.09), UDim2.fromScale(0.5, 0.58), Kit.C.white, Vector2.new(0.5, 0.5), 44)
	tagline.Name = "Tagline"

	-- ten world dots, popping in one after another
	local row = Kit.frame(card, UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.5, 0.7), nil, Vector2.new(0.5, 0.5))
	row.Name = "Worlds"
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.02, 0)
	list.Parent = row
	for i, color in Progress.WORLD_COLORS do
		local dot = Kit.frame(row, UDim2.fromScale(0.07, 1), UDim2.new(), color)
		dot.LayoutOrder = i
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.Parent = dot
		Kit.corner(dot, 100)
		Kit.stroke(dot, Kit.C.ink, 3)
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = dot
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.25 + i * 0.09), { Scale = 1 }):Play()
	end

	-- progress bar + tip
	local track = Kit.frame(card, UDim2.fromScale(0.46, 0.03), UDim2.fromScale(0.5, 0.82), Color3.fromRGB(30, 40, 90), Vector2.new(0.5, 0.5))
	track.Name = "Track"
	track.BackgroundTransparency = 0.35
	Kit.corner(track, 100)
	Kit.stroke(track, Kit.C.ink, 2)
	local fill = Kit.frame(track, UDim2.fromScale(0, 1), UDim2.new(), Kit.C.yellow)
	fill.Name = "Fill"
	Kit.corner(fill, 100)
	Kit.gradient(fill, Kit.C.yellow, Kit.C.orange, 0)
	local tip = Kit.bold(card, "@" .. Intro.TIPS[math.random(1, #Intro.TIPS)], UDim2.fromScale(0.8, 0.06), UDim2.fromScale(0.5, 0.9), Kit.C.white, Vector2.new(0.5, 0.5), 28)
	tip.Name = "Tip"

	local stateIn = Net.state.stage ~= nil or Net.state.at ~= nil
	Net.changed:Once(function()
		stateIn = true
	end)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		local ok = pcall(function()
			local fade = TweenService:Create(card, TweenInfo.new(Intro.FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
		end)
		if not ok then
			-- tweening failed: just remove it
			card.Visible = false
		end
		gui:Destroy()
	end
	-- the hard cap is a plain delay of its own: nothing below can keep the card up
	task.delay(Intro.MAX_HOLD + Intro.FADE + 0.5, function()
		closed = true
		if gui.Parent then
			gui:Destroy()
		end
	end)
	task.delay(Intro.MAX_HOLD, close)
	task.spawn(function()
		local t0 = os.clock()
		local shown = 0.08
		while not closed and gui.Parent do
			local t = os.clock() - t0
			local player = Players.LocalPlayer
			local charIn = player.Character ~= nil and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
			local goal = 0.12 + (if stateIn then 0.5 else 0) + (if charIn then 0.3 else 0)
			-- creeps forward a little even while waiting, so it never looks frozen
			goal = math.min(goal + math.min(t / Intro.MAX_HOLD, 1) * 0.06, 0.98)
			local ready = stateIn and charIn and t >= Intro.MIN_HOLD
			if ready then
				goal = 1
			end
			shown += (goal - shown) * 0.2
			fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
			if ready and shown > 0.97 then
				break
			end
			task.wait(0.05)
		end
		fill.Size = UDim2.fromScale(1, 1)
		close()
	end)
end

return Intro
