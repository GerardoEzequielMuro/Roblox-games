--!strict
-- Title card shown for a couple of seconds when you join: game name, tagline, and the ten world
-- colours popping in. Covers the moment the character and the tower are still streaming in, then
-- fades away. Never blocks input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Kit)
local Progress = require(script.Parent.Progress)

local Intro = {}

Intro.HOLD = 2.3 -- seconds on screen before the fade
Intro.FADE = 0.6

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

	task.delay(Intro.HOLD, function()
		local fade = TweenService:Create(card, TweenInfo.new(Intro.FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		gui:Destroy()
	end)
end

return Intro
