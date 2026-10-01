--!nonstrict
-- Branded loading screen: game name, one tip and a progress bar. It is only an overlay (the
-- game keeps loading under it) and it closes by itself after Onboarding.LOAD_MAX seconds no
-- matter what failed to load. Everything is pcall'd: this module can never stop the client.
-- It depends on nothing but Locale / Config / Onboarding (not on Net or Lang, which wait for the
-- server remotes), so it appears at once.
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)

local Loading = {}

local TIPS = { "load.tip1", "load.tip2", "load.tip3", "load.tip4" }
local GOLD = Color3.fromRGB(255, 214, 80)

local function languageCode(): string
	local player = Players.LocalPlayer
	local okRoblox, roblox = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	return Locale.resolveFirst(player.LocaleId, if okRoblox then roblox else nil)
end

local function build(lang: string): (ScreenGui, TextLabel, Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "KiWarriorsLoading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.Active = true -- eats clicks while it is up
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(34, 20, 70), Color3.fromRGB(12, 10, 28))
	grad.Rotation = 90
	grad.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.8, 0, 0.22, 0)
	title.Position = UDim2.fromScale(0.5, 0.34)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Font = Enum.Font.Bangers
	title.Text = string.upper(Config.GameName)
	title.TextColor3 = GOLD
	title.TextScaled = true
	title.Parent = bg
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 96
	cap.MinTextSize = 24
	cap.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Color3.fromRGB(60, 24, 20)
	stroke.Parent = title
	local pulse = Instance.new("UIScale")
	pulse.Parent = title
	TweenService:Create(pulse, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.04 }):Play()

	local tip = Instance.new("TextLabel")
	tip.Name = "Tip"
	tip.BackgroundTransparency = 1
	tip.Size = UDim2.new(0.7, 0, 0.08, 0)
	tip.Position = UDim2.fromScale(0.5, 0.56)
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Font = Enum.Font.GothamMedium
	tip.Text = Locale.t(lang, TIPS[(os.time() % #TIPS) + 1])
	tip.TextColor3 = Color3.fromRGB(235, 235, 255)
	tip.TextScaled = true
	tip.TextWrapped = true
	tip.Parent = bg
	local tipCap = Instance.new("UITextSizeConstraint")
	tipCap.MaxTextSize = 26
	tipCap.MinTextSize = 13
	tipCap.Parent = tip

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(0.42, 0, 0, 14)
	track.Position = UDim2.fromScale(0.5, 0.7)
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.BackgroundColor3 = Color3.fromRGB(10, 8, 24)
	track.BorderSizePixel = 0
	track.Parent = bg
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 7)
	trackCorner.Parent = track
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 2
	trackStroke.Color = Color3.fromRGB(255, 255, 255)
	trackStroke.Transparency = 0.6
	trackStroke.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.02, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 7)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.42, 0, 0, 24)
	label.Position = UDim2.new(0.5, 0, 0.7, 24)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Font = Enum.Font.GothamBold
	label.Text = Locale.t(lang, "load.loading")
	label.TextColor3 = Color3.fromRGB(190, 190, 225)
	label.TextScaled = true
	label.Parent = bg
	local labelCap = Instance.new("UITextSizeConstraint")
	labelCap.MaxTextSize = 18
	labelCap.MinTextSize = 11
	labelCap.Parent = label

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, label, fill, bg
end

function Loading.start()
	local okBuild, gui, _status, fill, bg = pcall(function()
		local g, l, f, b = build(languageCode())
		return g, l, f, b
	end)
	if not okBuild then
		return -- no loading screen is better than a broken client
	end
	local player = Players.LocalPlayer
	local netModule: any = nil
	local t0 = os.clock()
	local shown = 0
	local closing = false
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if closing then
			return
		end
		local elapsed = os.clock() - t0
		-- stages are plain checks, each guarded: a missing piece only delays the bar, the
		-- hard cap still closes the screen
		if not netModule and ReplicatedStorage:FindFirstChild("Remotes") then
			local ok, m = pcall(function()
				return require(script.Parent.Net)
			end)
			if ok then
				netModule = m
			end
		end
		local char = player.Character
		local stages = {
			ReplicatedStorage:FindFirstChild("Remotes") ~= nil,
			netModule ~= nil and netModule.state ~= nil,
			char ~= nil and char:FindFirstChild("HumanoidRootPart") ~= nil,
		}
		local frac, close = Onboarding.loadingProgress(elapsed, stages)
		shown += (frac - shown) * math.min(1, dt * 8)
		if fill.Parent then
			fill.Size = UDim2.fromScale(math.max(0.02, shown), 1)
		end
		if close then
			closing = true
			conn:Disconnect()
			fill.Size = UDim2.fromScale(1, 1)
			local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad)
			pcall(function()
				TweenService:Create(bg, info, { BackgroundTransparency = 1 }):Play()
				for _, d in bg:GetDescendants() do
					if d:IsA("TextLabel") then
						TweenService:Create(d, info, { TextTransparency = 1 }):Play()
					elseif d:IsA("Frame") then
						TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
					elseif d:IsA("UIStroke") then
						TweenService:Create(d, info, { Transparency = 1 }):Play()
					end
				end
			end)
			task.delay(0.45, function()
				gui:Destroy()
			end)
		end
	end)
	-- belt and braces: even if Heartbeat never ran, the screen is gone after the cap
	task.delay(Onboarding.LOAD_MAX + 2, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

return Loading
