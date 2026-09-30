--!nonstrict
-- Screen-space feedback: coins flying from the basket to the cash counter, and confetti for big moments.
-- Positions are in the HUD's design pixels (Root is scaled by a UIScale), so convert from absolute pixels.
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Layout = require(script.Parent.Layout)
local Perf = require(script.Parent.Perf)
local Sound = require(script.Parent.Sound)

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

return Juice
