--!nonstrict
-- Short branded loading screen: game name, a tip and a progress bar. Never blocks longer than Onboarding.LOAD_MAX
-- seconds (whatever fails to load, it fades out and the game's own "Loading..." label takes over).
--   Loading.show()      call first thing in Main.client
--   Loading.stage()     call when a load stage is done (UI built, remotes wired, handshake answered)
--   Loading.skip()      dismiss now (e.g. the handshake answered)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)

local Loading = {}

Loading.STAGES = 3
Loading.GAME_NAME = "Crop Kingdom"
local TIPS = { "load.tip1", "load.tip2", "load.tip3" }

local gui: any = nil
local fill: any = nil
local stages = 0
local ready = false
local startedAt = 0
local conn: RBXScriptConnection? = nil
local dismissed = false

function Loading.stage()
	stages += 1
	if stages >= Loading.STAGES then
		ready = true
	end
end

local function dismiss()
	if dismissed then
		return
	end
	dismissed = true
	if conn then
		conn:Disconnect()
		conn = nil
	end
	local g = gui
	if not g then
		return
	end
	local bg = g:FindFirstChild("Bg")
	if bg and bg:IsA("GuiObject") then
		for _, d in bg:GetDescendants() do
			if d:IsA("TextLabel") then
				C.tween(d, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
			elseif d:IsA("Frame") then
				C.tween(d, 0.35, { BackgroundTransparency = 1 })
			end
		end
		local t = C.tween(bg, 0.4, { BackgroundTransparency = 1 })
		t.Completed:Once(function()
			g:Destroy()
		end)
	end
	task.delay(1.5, function()
		if g.Parent then
			g:Destroy() -- never leave it behind if a tween was cancelled
		end
	end)
end

function Loading.skip()
	ready = true
	stages = Loading.STAGES
	if os.clock() - startedAt >= Onboarding.LOAD_MIN then
		dismiss()
	end
end

function Loading.show()
	local ok, err = pcall(function()
		startedAt = os.clock()
		local pg = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
		if not pg then
			return
		end
		gui = C.new("ScreenGui", {
			Name = "CropKingdomLoading",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 100,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		local bg = C.new("Frame", {
			Name = "Bg",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(34, 78, 44),
			BorderSizePixel = 0,
			Parent = gui,
		})
		C.gradient(bg, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 175, 150), 90)
		local title = C.label(bg, "🌱 " .. Loading.GAME_NAME, UDim2.fromOffset(640, 90), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.38),
			TextSize = 60,
			TextColor3 = Theme.C.Yellow,
			Outline = 4,
		})
		local sc = C.new("UIScale", { Parent = title })
		C.label(bg, I18n.t("main.loading"), UDim2.fromOffset(560, 36), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextSize = 24,
		})
		local track = C.new("Frame", {
			Name = "Track",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.58),
			Size = UDim2.fromOffset(360, 18),
			BackgroundColor3 = Color3.fromRGB(20, 40, 26),
			BorderSizePixel = 0,
			Parent = bg,
		})
		C.round(track)
		C.stroke(track, 2, Color3.fromRGB(10, 22, 14))
		fill = C.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Theme.C.Green,
			BorderSizePixel = 0,
			Parent = track,
		})
		C.round(fill)
		local tipKey = TIPS[math.random(1, #TIPS)]
		C.label(bg, "💡 " .. I18n.t(tipKey), UDim2.fromOffset(560, 40), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.68),
			TextSize = 20,
			TextColor3 = Color3.fromRGB(220, 240, 215),
			Outline = 2,
		})
		gui.Parent = pg

		conn = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - startedAt
			local p = Onboarding.loadProgress(stages, Loading.STAGES, elapsed)
			if fill and fill.Parent then
				fill.Size = UDim2.fromScale(p, 1)
			end
			sc.Scale = 1 + math.sin(elapsed * 3) * 0.02
			if Onboarding.loadDone(ready, elapsed) then
				if fill and fill.Parent then
					fill.Size = UDim2.fromScale(1, 1)
				end
				dismiss()
			end
		end)
	end)
	if not ok then
		warn("[Loading]", err)
		dismissed = true
	end
end

return Loading
