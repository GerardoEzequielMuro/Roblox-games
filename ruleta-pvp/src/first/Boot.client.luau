--!strict
-- ReplicatedFirst: runs before the game finishes loading. Replaces Roblox's default loading
-- screen with a plain branded cover so there is no flash of the world while the client
-- scripts start; UI/Loading (started by Main.client) takes over with the progress bar and
-- the tip. The cover removes itself after a few seconds no matter what, so a failed load
-- can never leave the player staring at it.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local MAX_SECONDS = 7

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
if not playerGui then
	return
end

local cover = Instance.new("ScreenGui")
cover.Name = "SpinBoot"
cover.ResetOnSpawn = false
cover.IgnoreGuiInset = true
cover.ScreenInsets = Enum.ScreenInsets.None
cover.DisplayOrder = 100
cover.Parent = playerGui

local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = Color3.new(1, 1, 1)
back.BorderSizePixel = 0
back.Parent = cover
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(44, 30, 96), Color3.fromRGB(10, 10, 28))
grad.Rotation = 90
grad.Parent = back

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.new(0.9, 0, 0, 78)
title.BackgroundTransparency = 1
title.Text = "SPIN SHOWDOWN"
title.TextScaled = true
title.Font = Enum.Font.LuckiestGuy
title.TextColor3 = Color3.fromRGB(255, 205, 60)
title.Parent = back
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(620, 78)
limit.Parent = title
local stroke = Instance.new("UIStroke")
stroke.Thickness = 5
stroke.Color = Color3.fromRGB(255, 70, 190)
stroke.Parent = title

task.delay(MAX_SECONDS, function()
	if cover.Parent then
		cover:Destroy()
	end
end)
