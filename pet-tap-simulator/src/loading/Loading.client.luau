--!strict
-- Short branded loading screen (ReplicatedFirst, so it shows before anything else loads).
-- Game name, a tip and a progress bar. It never traps the player: it closes as soon as the game
-- is loaded and the game's own UI exists (minimum ~1.2 s so it does not flash), with a hard cap
-- of 6 s, and a watchdog removes it at 9 s even if everything else here fails.
-- Self-contained on purpose (ReplicatedStorage may not have replicated yet).
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NAME = "Tap Pets Simulator"
local MIN_TIME, MAX_TIME, WATCHDOG = 1.2, 6, 9

local TIPS = {
	en = { "Tap anywhere to earn Taps!", "Hatch eggs to find rare pets!", "Rebirth for a permanent Taps boost.", "Equip your best pets to tap faster." },
	es = { "¡Tocá donde sea para ganar Taps!", "¡Abrí huevos para encontrar mascotas raras!", "Renacé para un bonus permanente de Taps.", "Equipá tus mejores mascotas para tapear más rápido." },
}

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 5)
if not playerGui then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "TapPetsLoading"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function fail()
	pcall(function()
		gui:Destroy()
	end)
end
-- last resort, whatever happens below
task.delay(WATCHDOG, fail)

local ok = pcall(function()
	local lang = if string.sub(LocalizationService.RobloxLocaleId, 1, 2) == "es" then "es" else "en"
	local tips = TIPS[lang]

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(86, 60, 150)
	bg.BorderSizePixel = 0
	bg.Active = true -- swallows clicks while it is up
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(120, 90, 200), Color3.fromRGB(52, 36, 100))
	grad.Rotation = 90
	grad.Parent = bg

	local function label(text: string, size: number, y: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.new(0.9, 0, 0, size + 10)
		l.Font = Enum.Font.FredokaOne
		l.Text = text
		l.TextSize = size
		l.TextScaled = false
		l.TextWrapped = true
		l.TextColor3 = color
		l.Parent = bg
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromRGB(43, 33, 64)
		st.Parent = l
		return l
	end

	local title = label(NAME, 56, 0.36, Color3.fromRGB(255, 210, 63))
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title
	TweenService:Create(titleScale, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
	label("🐾 🥚 🐾", 36, 0.2, Color3.new(1, 1, 1))
	label(tips[math.random(1, #tips)], 24, 0.62, Color3.new(1, 1, 1))

	local barBg = Instance.new("Frame")
	barBg.AnchorPoint = Vector2.new(0.5, 0.5)
	barBg.Position = UDim2.fromScale(0.5, 0.5)
	barBg.Size = UDim2.new(0.5, 0, 0, 22)
	barBg.BackgroundColor3 = Color3.fromRGB(43, 33, 64)
	barBg.Parent = bg
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(520, 22)
	sizeLimit.MinSize = Vector2.new(200, 22)
	sizeLimit.Parent = barBg
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 11)
	bc.Parent = barBg
	local bs = Instance.new("UIStroke")
	bs.Thickness = 3
	bs.Color = Color3.new(1, 1, 1)
	bs.Transparency = 0.5
	bs.Parent = barBg
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.04, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 225, 120)
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 11)
	fc.Parent = fill

	-- Real signals: the engine finished loading, the remotes exist, the game's HUD was built.
	-- Time keeps the bar moving so it never looks stuck.
	local t0 = os.clock()
	local shown = 0.04
	local closing = false
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		local elapsed = os.clock() - t0
		local real = 0.15
		if game:IsLoaded() then
			real += 0.35
		end
		if game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") then
			real += 0.15
		end
		if playerGui:FindFirstChild("TapPetsUI") then
			real += 0.35
		end
		local ready = real >= 0.999 and elapsed >= MIN_TIME
		local timeout = elapsed >= MAX_TIME
		local want = if ready or timeout then 1 else math.min(real, 0.2 + elapsed / MAX_TIME * 0.7)
		shown += (want - shown) * math.min(1, dt * 6)
		fill.Size = UDim2.fromScale(math.clamp(shown, 0.04, 1), 1)
		if (ready or timeout) and not closing then
			closing = true
			conn:Disconnect()
			fill.Size = UDim2.fromScale(1, 1)
			task.delay(0.15, function()
				local info = TweenInfo.new(0.35)
				for _, d in gui:GetDescendants() do
					if d:IsA("TextLabel") then
						TweenService:Create(d, info, { TextTransparency = 1 }):Play()
					elseif d:IsA("UIStroke") then
						TweenService:Create(d, info, { Transparency = 1 }):Play()
					elseif d:IsA("Frame") then
						TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
					end
				end
				task.delay(0.4, fail)
			end)
		end
	end)
end)

if not ok then
	fail()
end
