--!strict
-- Branded loading screen: game name, a tip and a progress bar. It is the first thing the client
-- script starts and it is independent of everything else: it only reads flags through a probe,
-- is capped at Juice.LOAD_MAX seconds and removes itself even if the rest of the client
-- failed to load. Everything is wrapped in pcall so it can never be the thing that breaks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Loading = {}

Loading.flags = { remotes = false, state = false, world = false }
Loading.gui = nil :: ScreenGui?

local TIPS = { "loading.tip1", "loading.tip2", "loading.tip3", "loading.tip4" }

-- Called by Main.client once the rest of the client is wired: reports real readiness.
function Loading.setProbe(probe: () -> { remotes: boolean, state: boolean, world: boolean })
	Loading.probe = probe
end
Loading.probe = nil :: (() -> { remotes: boolean, state: boolean, world: boolean })?

local function build(Juice: any, Locale: any): (ScreenGui, TextLabel, Frame)
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui", 5) :: PlayerGui
	local code = Locale.resolve(Players.LocalPlayer.LocaleId)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlanetLoading"
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.Active = true -- swallows clicks while it is up
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(22, 14, 54), Color3.fromRGB(70, 36, 120))
	grad.Rotation = 90
	grad.Parent = bg

	local function label(name: string, text: string, size: number, y: number, color: Color3, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromScale(0.9, 0.12)
		l.Font = font
		l.Text = text
		l.TextColor3 = color
		l.TextScaled = true
		l.AutoLocalize = false
		l.Parent = bg
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.MinTextSize = 10
		c.Parent = l
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromRGB(20, 12, 40)
		st.Parent = l
		return l
	end
	local title = label("Title", "PLANET CRACKERS", 72, 0.28, Color3.fromRGB(255, 220, 70), Enum.Font.FredokaOne)
	title.Rotation = -2
	local planet = Instance.new("Frame") -- a little planet that bobs: proof the game is alive
	planet.Name = "Planet"
	planet.AnchorPoint = Vector2.new(0.5, 0.5)
	planet.Position = UDim2.fromScale(0.5, 0.46)
	planet.Size = UDim2.fromOffset(56, 56)
	planet.BackgroundColor3 = Color3.fromRGB(255, 150, 90)
	planet.Parent = bg
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = planet
	local ps = Instance.new("UIStroke")
	ps.Thickness = 3
	ps.Color = Color3.fromRGB(20, 12, 40)
	ps.Parent = planet
	TweenService:Create(planet, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.5, 0.44) }):Play()

	label("Tip", Locale.t(code, TIPS[Juice.tipIndex(os.clock() * 1000 + Players.LocalPlayer.UserId, #TIPS)]), 26, 0.62, Color3.fromRGB(235, 230, 255), Enum.Font.GothamMedium)
	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.AnchorPoint = Vector2.new(0.5, 0.5)
	barBack.Position = UDim2.fromScale(0.5, 0.78)
	barBack.Size = UDim2.new(0.5, 0, 0, 16)
	barBack.BackgroundColor3 = Color3.fromRGB(14, 8, 34)
	barBack.Parent = bg
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = barBack
	local bs = Instance.new("UIStroke")
	bs.Thickness = 2
	bs.Color = Color3.fromRGB(255, 220, 70)
	bs.Parent = barBack
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.05, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 220, 70)
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
	local lbl = label("Percent", "0%", 22, 0.86, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
	gui.Parent = pg
	return gui, lbl, fill
end

function Loading.start()
	local ok = xpcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 5)
		if not shared then
			return
		end
		local Juice = require(shared:WaitForChild("Juice", 3) :: ModuleScript) :: any
		local Locale = require(shared:WaitForChild("Locale", 3) :: ModuleScript) :: any
		local gui, pct, fill = build(Juice, Locale)
		Loading.gui = gui
		task.delay(Juice.LOAD_MAX + 3, function()
			if gui.Parent then
				gui:Destroy() -- last resort: nothing may keep the player behind this screen
			end
		end)
		local t0 = os.clock()
		local shown = 0
		task.spawn(function()
			while gui.Parent do
				local elapsed = os.clock() - t0
				local f = Loading.flags
				local probe = Loading.probe
				if probe then
					local okp, got = pcall(probe)
					if okp and type(got) == "table" then
						f = got
					end
				end
				local want = Juice.loadProgress(elapsed, f)
				shown = math.max(shown, shown + (want - shown) * 0.25)
				fill.Size = UDim2.fromScale(math.clamp(shown, 0.03, 1), 1)
				pct.Text = math.floor(shown * 100) .. "%"
				if Juice.loadDone(elapsed, f) then
					break
				end
				RunService.RenderStepped:Wait()
			end
			fill.Size = UDim2.fromScale(1, 1)
			pct.Text = "100%"
			-- fade everything out, then remove
			for _, d in gui:GetDescendants() do
				if d:IsA("Frame") then
					TweenService:Create(d, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				end
			end
			task.wait(0.45)
			gui:Destroy()
		end)
	end, function(err: any)
		warn("Loading screen skipped: " .. tostring(err))
	end)
	local _ = ok
end

return Loading
