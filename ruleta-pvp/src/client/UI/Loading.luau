--!strict
-- Branded loading screen: game name, a spinning wheel, a progress bar and a rotating tip.
-- Started first thing in Main.client, before the heavy modules load. It can never hang:
-- LoadingFlow caps it at a few seconds, a watchdog destroys it even if the polling loop
-- errors, and every probe is pcall'd (a stage that fails to load counts as done).
-- Self-contained on purpose (no Theme / Net / Lang): those are what is loading.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Loading = {}
Loading.active = false
Loading.dismissedAt = nil :: number?
Loading.done = {} :: { [string]: boolean }

local FALLBACK_TIPS = { "Press BRAKE to choose where the wheel stops.", "Everyone has 3 lives. Lose them all and you are out.", "Cards are free: play one before you spin.", "Win matches to climb leagues and unlock skins." }

local gui: ScreenGui? = nil

-- Called by Main when something external is ready ("ui", "data").
function Loading.mark(stage: string)
	Loading.done[stage] = true
end

local function sharedModule(name: string): any?
	local ok, mod = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 3)
		local inst = if shared then shared:WaitForChild(name, 3) else nil
		return if inst then (require :: any)(inst) else nil
	end)
	return if ok then mod else nil
end

local function destroy()
	local g = gui
	gui = nil
	Loading.active = false
	Loading.dismissedAt = os.clock()
	if g then
		pcall(function()
			g:Destroy()
		end)
	end
end

function Loading.start()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	if not playerGui or Loading.active then
		return
	end
	Loading.active = true
	local startedAt = os.clock()

	local screen = Instance.new("ScreenGui")
	screen.Name = "SpinLoading"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.DisplayOrder = 100
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	gui = screen

	-- the ReplicatedFirst cover (same look) is no longer needed
	local cover = playerGui:FindFirstChild("SpinBoot")
	if cover then
		cover:Destroy()
	end

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.Parent = screen
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(44, 30, 96), Color3.fromRGB(10, 10, 28))
	grad.Rotation = 90
	grad.Parent = back

	local centre = Instance.new("Frame")
	centre.Name = "Centre"
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.new(0.9, 0, 0, 330)
	centre.BackgroundTransparency = 1
	centre.Parent = back
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 330)
	limit.Parent = centre

	local wheel = Instance.new("TextLabel")
	wheel.Name = "Wheel"
	wheel.BackgroundTransparency = 1
	wheel.AnchorPoint = Vector2.new(0.5, 0)
	wheel.Position = UDim2.fromScale(0.5, 0)
	wheel.Size = UDim2.fromOffset(110, 110)
	wheel.Text = "🎡"
	wheel.TextScaled = true
	wheel.Font = Enum.Font.FredokaOne
	wheel.Parent = centre

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 112)
	title.Size = UDim2.new(1, 0, 0, 78)
	title.Text = "SPIN SHOWDOWN"
	title.TextScaled = true
	title.Font = Enum.Font.LuckiestGuy
	title.TextColor3 = Color3.fromRGB(255, 205, 60)
	title.Parent = centre
	local ts = Instance.new("UIStroke")
	ts.Thickness = 5
	ts.Color = Color3.fromRGB(255, 70, 190)
	ts.Parent = title

	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.Position = UDim2.new(0.1, 0, 0, 206)
	barBack.Size = UDim2.new(0.8, 0, 0, 16)
	barBack.BackgroundColor3 = Color3.fromRGB(10, 10, 28)
	barBack.BorderSizePixel = 0
	barBack.Parent = centre
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = barBack
	local bs = Instance.new("UIStroke")
	bs.Thickness = 3
	bs.Color = Color3.fromRGB(76, 84, 170)
	bs.Parent = barBack
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(0, 210, 245)
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 8)
	fc.Parent = fill

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0.1, 0, 0, 228)
	status.Size = UDim2.new(0.8, 0, 0, 24)
	status.Text = "Loading..."
	status.TextScaled = true
	status.Font = Enum.Font.FredokaOne
	status.TextColor3 = Color3.fromRGB(176, 182, 220)
	status.Parent = centre

	local tip = Instance.new("TextLabel")
	tip.Name = "Tip"
	tip.BackgroundTransparency = 1
	tip.Position = UDim2.new(0.05, 0, 0, 262)
	tip.Size = UDim2.new(0.9, 0, 0, 58)
	tip.Text = ""
	tip.TextWrapped = true
	tip.TextScaled = true
	tip.Font = Enum.Font.FredokaOne
	tip.TextColor3 = Color3.new(1, 1, 1)
	tip.Parent = centre
	local tsz = Instance.new("UITextSizeConstraint")
	tsz.MaxTextSize = 24
	tsz.MinTextSize = 12
	tsz.Parent = tip

	-- watchdog: whatever happens below, the screen is gone shortly after the hard cap
	local Flow = sharedModule("LoadingFlow")
	local Locale = sharedModule("Locale")
	local maxSeconds = if Flow then Flow.MAX_SECONDS else 6
	task.delay(maxSeconds + 1.5, function()
		if gui == screen then
			destroy()
		end
	end)

	local lang = "en"
	pcall(function()
		if Locale then
			lang = Locale.resolve(player.LocaleId)
		end
	end)
	local function line(key: string, fallback: string): string
		local ok, text = pcall(function()
			return if Locale then Locale.t(lang, key) else fallback
		end)
		if ok and type(text) == "string" and text ~= "" and text ~= key then
			return text
		end
		return fallback
	end
	status.Text = line("loading.loading", "Loading...")
	local seed = math.floor(os.clock() * 1000) % 97
	local shownTip = 0
	local function setTip(i: number)
		if i == shownTip then
			return
		end
		shownTip = i
		tip.Text = line("loading.tip." .. i, FALLBACK_TIPS[i] or FALLBACK_TIPS[1])
	end
	setTip(if Flow then Flow.tipIndex(seed, 0) else 1)

	local conn: RBXScriptConnection? = nil
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		if conn then
			conn:Disconnect()
		end
		pcall(function()
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 1) }):Play()
			local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(back, info, { BackgroundTransparency = 1 }):Play()
			for _, o in screen:GetDescendants() do
				if o:IsA("TextLabel") then
					TweenService:Create(o, info, { TextTransparency = 1 }):Play()
				elseif o:IsA("UIStroke") then
					TweenService:Create(o, info, { Transparency = 1 }):Play()
				elseif o:IsA("Frame") and o ~= back then
					TweenService:Create(o, info, { BackgroundTransparency = 1 }):Play()
				end
			end
		end)
		task.delay(0.4, function()
			if gui == screen then
				destroy()
			end
		end)
	end

	local shownProgress = 0
	local lastProbe = 0
	conn = RunService.Heartbeat:Connect(function(dt: number)
		local ok = pcall(function()
			local elapsed = os.clock() - startedAt
			if elapsed - lastProbe >= 0.1 then
				lastProbe = elapsed
				local done = Loading.done
				if not done.game then
					done.game = game:IsLoaded()
				end
				if not done.world then
					local w = Workspace:FindFirstChild("World")
					done.world = w ~= nil and #game:GetService("CollectionService"):GetTagged("PowerCore") > 0
				end
				if not done.ui then
					local g = playerGui:FindFirstChild("SpinUI")
					done.ui = g ~= nil and g:FindFirstChild("LobbyHud") ~= nil
				end
			end
			local target = if Flow then Flow.progress(Loading.done, elapsed) else math.min(0.9, elapsed / 6)
			shownProgress += (target - shownProgress) * math.min(1, dt * 8)
			fill.Size = UDim2.fromScale(math.clamp(shownProgress, 0, 1), 1)
			wheel.Rotation = (elapsed * 220) % 360
			if Flow then
				setTip(Flow.tipIndex(seed, elapsed))
			end
			if (Flow and Flow.shouldDismiss(Loading.done, elapsed)) or (not Flow and elapsed >= 4) then
				finish()
			end
		end)
		if not ok then
			-- anything unexpected: get out of the way
			finish()
		end
	end)
end

return Loading
