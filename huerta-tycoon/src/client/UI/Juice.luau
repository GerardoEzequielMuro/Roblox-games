--!nonstrict
-- Screen-space feedback: coins flying from the basket to the cash counter, and confetti for big moments.
-- Positions are in the HUD's design pixels (Root is scaled by a UIScale), so convert from absolute pixels.
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Layout = require(script.Parent.Layout)
local Perf = require(script.Parent.Perf)
local Sound = require(script.Parent.Sound)
local Feel = require(game:GetService("ReplicatedStorage").Shared.Feel)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Juice = {}

local layer: Frame? = nil
local rng = Random.new()

Juice.MAX_COINS = 14
Juice.MAX_CONFETTI = 40
local liveConfetti = 0

function Juice.init(root: Instance)
	layer = C.new("Frame", {
		Name = "Juice",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 45,
		Parent = root,
	})
	;(layer :: Frame).Active = false
end

-- Center of a GuiObject in the layer's design pixels.
local function centerOf(g: GuiObject): Vector2
	local l = layer :: Frame
	local scale = math.max(Layout.scale, 0.01)
	return (g.AbsolutePosition + g.AbsoluteSize / 2 - l.AbsolutePosition) / scale
end

-- How many coins a sale of `count` items shows (pure, so the test can check the cap).
function Juice.coinCount(count: number): number
	return math.clamp(math.floor(4 + count / 2), 4, math.min(Juice.MAX_COINS, Perf.budget(Perf.lite).coins))
end

function Juice.coins(from: GuiObject, to: GuiObject, count: number)
	local l = layer
	if not l or not from.Parent or not to.Parent then
		return
	end
	local a, b = centerOf(from), centerOf(to)
	for i = 1, Juice.coinCount(count) do
		local coin: Frame = C.new("Frame", {
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(a.X, a.Y),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Theme.C.Gold,
			ZIndex = 46,
			Parent = l,
		})
		C.round(coin)
		C.stroke(coin, 2.5, Theme.darken(Theme.C.Gold, 0.5))
		C.gradient(coin, Color3.new(1, 1, 1), Color3.fromRGB(215, 190, 140), 60)
		C.label(coin, "$", UDim2.fromScale(1, 1), { TextSize = 18, TextColor3 = Color3.fromRGB(255, 250, 210), Outline = 1.5, ZIndex = 47, NoFit = true })
		local burst = Vector2.new(rng:NextNumber(-90, 90), rng:NextNumber(-70, 10))
		task.delay((i - 1) * 0.035, function()
			if not coin.Parent then
				return
			end
			local out = C.tween(coin, 0.2, { Position = UDim2.fromOffset(a.X + burst.X, a.Y + burst.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			out.Completed:Once(function()
				local fly = C.tween(coin, rng:NextNumber(0.4, 0.6), { Position = UDim2.fromOffset(b.X, b.Y), Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				fly.Completed:Once(function()
					coin:Destroy()
				end)
			end)
		end)
		-- never leave a coin behind if a tween is cancelled (resize, respawn...)
		task.delay(2, function()
			if coin.Parent then
				coin:Destroy()
			end
		end)
	end
end

local CONFETTI = { Theme.C.Red, Theme.C.Yellow, Theme.C.Green, Theme.C.Blue, Theme.C.Purple, Theme.C.Pink, Theme.C.Orange }

function Juice.confetti(amount: number?)
	local l = layer
	if not l then
		return
	end
	Sound.play("fanfare")
	local n = math.min(amount or 28, math.min(Juice.MAX_CONFETTI, Perf.budget(Perf.lite).confetti) - liveConfetti)
	local w, h = Layout.canvas.X, Layout.canvas.Y
	for _ = 1, n do
		liveConfetti += 1
		local x = rng:NextNumber(0.1, 0.9) * w
		local piece: Frame = C.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, -20),
			Size = UDim2.fromOffset(rng:NextInteger(8, 12), rng:NextInteger(12, 18)),
			Rotation = rng:NextNumber(0, 360),
			BackgroundColor3 = CONFETTI[rng:NextInteger(1, #CONFETTI)],
			BorderSizePixel = 0,
			ZIndex = 46,
			Parent = l,
		})
		C.corner(piece, 3)
		local time = rng:NextNumber(1.3, 2.2)
		local fall = C.tween(piece, time, {
			Position = UDim2.fromOffset(x + rng:NextNumber(-120, 120), h + 30),
			Rotation = piece.Rotation + rng:NextNumber(-540, 540),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local done = false
		local function finish()
			if not done then
				done = true
				liveConfetti -= 1
				piece:Destroy()
			end
		end
		fall.Completed:Once(finish)
		task.delay(time + 0.5, finish)
	end
end

-- ===== camera micro-shake (Humanoid.CameraOffset: cheap, never fights the camera script) =====
-- Players who set the "ReducedMotion" attribute on themselves (a future settings toggle) get none.
local shakeUntil, shakeAmp, shakeStart = 0, 0, 0
local shakeConn: RBXScriptConnection? = nil

local function reduced(): boolean
	return Players.LocalPlayer ~= nil and Players.LocalPlayer:GetAttribute("ReducedMotion") == true
end

function Juice.shake(power: number)
	local amp, dur = Feel.shake(power, Perf.lite, reduced())
	if amp <= 0 then
		return
	end
	local now = os.clock()
	if now + dur < shakeUntil and amp <= shakeAmp then
		return -- a stronger shake is already running
	end
	shakeStart, shakeUntil, shakeAmp = now, now + dur, amp
	if shakeConn then
		return
	end
	shakeConn = RunService.RenderStepped:Connect(function()
		local char = Players.LocalPlayer and Players.LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local t = os.clock()
		if t >= shakeUntil or not hum then
			if hum then
				hum.CameraOffset = Vector3.zero
			end
			if shakeConn then
				shakeConn:Disconnect()
				shakeConn = nil
			end
			return
		end
		local fade = 1 - (t - shakeStart) / math.max(shakeUntil - shakeStart, 0.01)
		local a = shakeAmp * fade
		hum.CameraOffset = Vector3.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0)
	end)
end

-- ===== banners: rarity reveal and unlock =====
-- One banner at a time (a new one replaces the old), pooled as a single Frame: cheap on phones.
local banner: Frame? = nil
local bannerTitle: TextLabel? = nil
local bannerSub: TextLabel? = nil
local bannerScale: UIScale? = nil
local bannerToken = 0

local function ensureBanner()
	if banner and banner.Parent then
		return
	end
	local l = layer :: Frame
	local f: Frame = C.new("Frame", {
		Name = "RevealBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(440, 84),
		BackgroundColor3 = Theme.C.Dark,
		Visible = false,
		ZIndex = 48,
		Parent = l,
	})
	C.corner(f, 20)
	local stroke = C.stroke(f, 4, Theme.C.Gold)
	stroke.Name = "Edge"
	bannerScale = C.new("UIScale", { Parent = f })
	bannerTitle = C.label(f, "", UDim2.new(1, -20, 0, 44), { Position = UDim2.fromOffset(10, 6), TextSize = 34, ZIndex = 49, Outline = 3 })
	bannerSub = C.label(f, "", UDim2.new(1, -20, 0, 28), { Position = UDim2.fromOffset(10, 48), TextSize = 22, ZIndex = 49, Outline = 2 })
	banner = f
end

-- title/sub are already-translated strings. tier 0..3 sets the intensity.
function Juice.banner(title: string, sub: string, color: Color3, tier: number)
	if not layer then
		return
	end
	ensureBanner()
	local f, sc = banner :: Frame, bannerScale :: UIScale
	bannerToken += 1
	local token = bannerToken
	;(bannerTitle :: TextLabel).Text = title
	;(bannerTitle :: TextLabel).TextColor3 = color
	;(bannerSub :: TextLabel).Text = sub
	;(bannerSub :: TextLabel).TextColor3 = Theme.C.White
	local edge = f:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = color
	end
	f.BackgroundTransparency = 0.1
	f.Visible = true
	sc.Scale = 0.4
	C.tween(sc, 0.35, { Scale = 1 + tier * 0.05 }, Enum.EasingStyle.Back)
	task.delay(1.9 + tier * 0.2, function()
		if token ~= bannerToken or not f.Parent then
			return
		end
		local out = C.tween(sc, 0.25, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		out.Completed:Once(function()
			if token == bannerToken then
				f.Visible = false
			end
		end)
	end)
end

-- Rare drop: rarity-colored banner + shake + fanfare. tier from Feel.tier.
function Juice.reveal(title: string, sub: string, color: Color3, tier: number)
	if not Feel.bigMoment(tier) then
		return
	end
	Sound.play("reveal")
	Juice.banner(title, sub, color, tier)
	Juice.shake(Feel.tierPower(tier))
	if tier >= 3 then
		Juice.confetti(18)
	end
end

-- Unlock / level-up moment: gold banner, small confetti, sound.
function Juice.unlock(title: string, sub: string)
	Sound.play("unlock")
	Juice.banner(title, sub, Theme.C.Gold, 1)
	Juice.confetti(14)
end

-- Quick squash-and-pop on any GuiObject that has (or gets) a UIScale named "Pop". Used for counters and cards.
function Juice.pop(target: GuiObject, scale: number?)
	local sc = target:FindFirstChild("Pop")
	if not sc then
		sc = C.new("UIScale", { Name = "Pop", Parent = target })
	end
	;(sc :: UIScale).Scale = scale or 1.15
	C.tween(sc :: UIScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

return Juice
