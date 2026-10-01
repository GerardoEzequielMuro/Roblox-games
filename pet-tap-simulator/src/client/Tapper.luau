--!strict
-- Tap anywhere (mouse / touch) to earn Taps. Taps are counted locally, batched and sent
-- every Config.TapSendInterval; the server clamps them.
--
-- Local feedback per tap: a +N that pops and floats away, a ring, a burst of sparks, a token
-- that flies into the Taps counter (which bumps when it lands), the pets hop, and a combo
-- counter that follows the taps with milestone shout-outs. The combo is feedback only: it
-- never changes what a tap is worth. Everything is pooled, so fast tapping allocates nothing.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local PetFollow = require(script.Parent.PetFollow)
local Quality = require(script.Parent.Quality)
local Shake = require(script.Parent.Shake)
local Celebrate = require(script.Parent.Celebrate)
local Theme = require(script.Parent.UI.Theme)
local Root = require(script.Parent.UI.Root)

local Tapper = {}

local tapEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tap") :: RemoteEvent

local fxGui = Theme.new("ScreenGui", {
	Name = "TapFx",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	DisplayOrder = 5,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
}) :: ScreenGui
-- everything is positioned inside this full-screen layer (input positions are converted
-- with layer.AbsolutePosition, so insets never matter)
local layer = Theme.new("Frame", { Name = "Layer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = fxGui }) :: Frame

local pending = 0
local tokens = Config.MaxTapsPerSecond
local lastRefill = os.clock()
local enabled = true

-- where flying tokens land (the HUD sets it)
local counter: GuiObject? = nil
local onCounterHit: () -> () = function() end
local onTapHook: () -> () = function() end

-- Called on every accepted tap (the HUD squashes the TAP button with it).
function Tapper.setTapHook(f: () -> ())
	onTapHook = f
end

function Tapper.setEnabled(on: boolean)
	enabled = on
end

function Tapper.setCounter(target: GuiObject, onHit: () -> ())
	counter = target
	onCounterHit = onHit
end

---------------------------------------------------------------------------
-- Combo (visual only)
---------------------------------------------------------------------------
local COMBO_WINDOW = 1.4 -- seconds without a tap before the combo drops
local COMBO_SHOW = 5
local MILESTONES: { [number]: string } = { [25] = "tap.nice", [50] = "tap.great", [100] = "tap.insane" }
local combo = 0
local lastTap = -10

Tapper.combo = 0

local function comboColor(n: number, now: number): Color3
	if n >= 100 then
		return Palette.rainbow(now * 2)
	elseif n >= 50 then
		return Theme.Pink
	elseif n >= 25 then
		return Theme.Orange
	elseif n >= 10 then
		return Theme.Yellow
	end
	return Theme.White
end

-- 1 .. 1.35: numbers and sparks grow with the combo
local function comboScale(n: number): number
	return 1 + math.min(n, 100) / 100 * 0.35
end

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------
type Num = { label: TextLabel, stroke: UIStroke, scale: UIScale }
local numPool: { Num } = {}
local ringPool: { { frame: Frame, stroke: UIStroke } } = {}
local sparkPool: { Frame } = {}
type Token = { frame: Frame, from: Vector2, ctrl: Vector2, t: number }
local tokenPool: { Frame } = {}
local flying: { Token } = {}

local function takeNum(): Num
	local n = table.remove(numPool)
	if n then
		n.label.Visible = true
		return n
	end
	local label = Theme.text({ Text = "", AnchorPoint = Vector2.new(0.5, 1), Stroke = 3, Parent = layer })
	label.AutoLocalize = false
	local scale = Theme.new("UIScale", { Parent = label }) :: UIScale
	return { label = label, stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke, scale = scale }
end

local function takeRing(): { frame: Frame, stroke: UIStroke }
	local r = table.remove(ringPool)
	if r then
		r.frame.Visible = true
		return r
	end
	local frame = Theme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = layer }, { Theme.corner(999) }) :: Frame
	local stroke = Theme.new("UIStroke", { Color = Theme.White, Parent = frame }) :: UIStroke
	return { frame = frame, stroke = stroke }
end

local function takeSpark(): Frame
	local s = table.remove(sparkPool)
	if s then
		s.Visible = true
		return s
	end
	return Theme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = layer }, { Theme.corner(3) }) :: Frame
end

local function takeToken(): Frame
	local t = table.remove(tokenPool)
	if t then
		t.Visible = true
		return t
	end
	return Theme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Yellow, ZIndex = 3, Parent = layer }, { Theme.corner(999), Theme.stroke(2) }) :: Frame
end

local SPARK_COLORS = { Theme.Yellow, Theme.White, Theme.Pink, Color3.fromRGB(140, 230, 255) }

local function fx(pos: Vector2, value: number, n: number)
	local s = Root.scale
	local now = os.clock()
	local k = comboScale(n)
	local color = comboColor(n, now)

	-- ring
	local ring = takeRing()
	ring.frame.Size = UDim2.fromOffset(20 * s, 20 * s)
	ring.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
	ring.stroke.Thickness = 5 * s
	ring.stroke.Transparency = 0
	ring.stroke.Color = color
	TweenService:Create(ring.frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(96 * s * k, 96 * s * k) }):Play()
	TweenService:Create(ring.stroke, TweenInfo.new(0.35), { Transparency = 1, Thickness = 1 }):Play()

	-- floating number: pops, then drifts up and fades
	local num = takeNum()
	local label = num.label
	label.Text = "+" .. Format.abbrev(value)
	label.Size = UDim2.fromOffset(220 * s, 46 * s * k)
	label.Position = UDim2.fromOffset(pos.X + math.random(-20, 20) * s, pos.Y - 10 * s)
	label.TextColor3 = if n >= 10 then color else SPARK_COLORS[math.random(1, #SPARK_COLORS)]
	label.TextTransparency = 0
	label.Rotation = math.random(-12, 12)
	local sizeLimit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if sizeLimit then
		sizeLimit.MaxTextSize = math.floor(40 * s * k)
	end
	num.stroke.Transparency = 0
	num.scale.Scale = 0.4
	TweenService:Create(num.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local rise = UDim2.fromOffset(label.Position.X.Offset + math.random(-30, 30) * s, pos.Y - 120 * s)
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = rise, Rotation = 0 }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45), { TextTransparency = 1 }):Play()
	TweenService:Create(num.stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45), { Transparency = 1 }):Play()

	-- sparks
	local sparks: { Frame } = {}
	local count = if Quality.lite then 3 else 5
	for i = 1, count do
		local sp = takeSpark()
		local a = (i / count + math.random() * 0.2) * math.pi * 2
		local dist = (46 + math.random() * 40) * s * k
		local size = math.random(6, 11) * s
		sp.Size = UDim2.fromOffset(size, size)
		sp.Position = UDim2.fromOffset(pos.X, pos.Y)
		sp.Rotation = math.random(0, 90)
		sp.BackgroundColor3 = if n >= 10 then color else SPARK_COLORS[(i % #SPARK_COLORS) + 1]
		sp.BackgroundTransparency = 0
		TweenService:Create(sp, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(pos.X + math.cos(a) * dist, pos.Y + math.sin(a) * dist),
			BackgroundTransparency = 1,
			Rotation = sp.Rotation + 180,
			Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		}):Play()
		table.insert(sparks, sp)
	end

	-- token that flies into the counter
	if counter and #flying < 14 then
		local token = takeToken()
		local size = 16 * s
		token.Size = UDim2.fromOffset(size, size)
		token.Position = UDim2.fromOffset(pos.X, pos.Y)
		token.BackgroundTransparency = 0
		table.insert(flying, { frame = token, from = pos, ctrl = pos + Vector2.new(math.random(-140, 140) * s, -math.random(40, 150) * s), t = 0 })
	end

	task.delay(0.4, function()
		ring.frame.Visible = false
		table.insert(ringPool, ring)
		for _, sp in sparks do
			sp.Visible = false
			table.insert(sparkPool, sp)
		end
	end)
	task.delay(0.85, function()
		label.Visible = false
		table.insert(numPool, num)
	end)
end

---------------------------------------------------------------------------
-- Combo label (follows the taps) and milestone shout
---------------------------------------------------------------------------
local comboLabel = Theme.text({ Text = "", Size = UDim2.fromOffset(240, 40), AnchorPoint = Vector2.new(0.5, 1), Stroke = 3, MaxTextSize = 30, TextTransparency = 1, ZIndex = 4, Parent = layer })
comboLabel.AutoLocalize = false
local comboStroke = comboLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
comboStroke.Transparency = 1
local comboPop = Theme.new("UIScale", { Parent = comboLabel }) :: UIScale
local comboAt = Vector2.zero
local comboShown = false

local shout = Theme.text({ Text = "", Size = UDim2.fromOffset(700, 90), Position = UDim2.fromScale(0.5, 0.24), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = 4, MaxTextSize = 80, TextTransparency = 1, ZIndex = 5, Parent = layer })
local shoutStroke = shout:FindFirstChildOfClass("UIStroke") :: UIStroke
shoutStroke.Transparency = 1
local shoutScale = Theme.new("UIScale", { Parent = shout }) :: UIScale

local function milestone(key: string, color: Color3)
	shout.Text = Lang.t(key)
	shout.TextColor3 = color
	shout.TextTransparency = 0
	shoutStroke.Transparency = 0
	shout.Rotation = math.random(-6, 6)
	shoutScale.Scale = 2.2 * Root.scale
	TweenService:Create(shoutScale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = Root.scale }):Play()
	TweenService:Create(shout, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7), { TextTransparency = 1 }):Play()
	TweenService:Create(shoutStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7), { Transparency = 1 }):Play()
	Theme.play("buy", 0.4, 1.3)
	-- big hit: camera micro-shake (off with reduced motion) and a sparkle burst
	Shake.kick(if combo >= 100 then 0.8 elseif combo >= 50 then 0.55 else 0.35, 0.3)
	Celebrate.burst(Vector2.new(shout.AbsolutePosition.X + shout.AbsoluteSize.X / 2, shout.AbsolutePosition.Y + shout.AbsoluteSize.Y / 2), color, 12)
end

local function bumpCombo(pos: Vector2): number
	local now = os.clock()
	if now - lastTap > COMBO_WINDOW then
		combo = 0
	end
	combo += 1
	lastTap = now
	Tapper.combo = combo
	comboAt = pos
	if combo >= COMBO_SHOW then
		local s = Root.scale
		comboLabel.Text = Lang.t("tap.combo", { n = combo })
		comboLabel.TextColor3 = comboColor(combo, now)
		comboLabel.Size = UDim2.fromOffset(240 * s, 40 * s)
		local limit = comboLabel:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = math.floor(30 * s * comboScale(combo))
		end
		comboLabel.TextTransparency = 0
		comboStroke.Transparency = 0
		if not comboShown then
			comboLabel.Position = UDim2.fromOffset(pos.X, pos.Y - 150 * s)
		end
		comboShown = true
		comboPop.Scale = 1.25
		TweenService:Create(comboPop, TweenInfo.new(0.14), { Scale = 1 }):Play()
	end
	local key = MILESTONES[combo] or (if combo > 100 and combo % 100 == 0 then "tap.insane" else nil)
	if key then
		milestone(key, comboColor(combo, now))
	end
	return combo
end

local function tap(inputPos: Vector2)
	if not enabled or not Net.state then
		return
	end
	local now = os.clock()
	tokens = math.min(Config.MaxTapsPerSecond, tokens + (now - lastRefill) * Config.MaxTapsPerSecond)
	lastRefill = now
	if tokens < 1 then
		return
	end
	tokens -= 1
	pending += 1
	local value = (Net.state :: any).tapValue or 1
	-- optimistic local count so the HUD feels instant (server state overwrites it)
	local s = Net.state :: any
	s.taps += value
	Net.bump()
	local pos = inputPos - layer.AbsolutePosition
	local n = bumpCombo(pos)
	fx(pos, value, n)
	PetFollow.pulse()
	onTapHook()
	Theme.play("tap", 0.18, 0.9 + math.min(n, 40) * 0.012 + math.random() * 0.08)
end

-- Same path as a real click at this input position (playtests and the screenshot showcase).
-- It goes through the same client token bucket, and the server clamps taps anyway.
function Tapper.simulate(inputPos: Vector2)
	tap(inputPos)
end

-- Screen zones the Roblox touch controls own (fractions of the viewport): the thumbstick
-- (bottom-left) and the jump button (bottom-right). A touch that starts there is movement,
-- not a tap.
local THUMBSTICK_ZONE = { x0 = -1, x1 = 0.4, y0 = 0.55, y1 = 2 }
local JUMP_ZONE = { x0 = 0.72, x1 = 2, y0 = 0.6, y1 = 2 }

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local function inZone(fx: number, fy: number, z: { x0: number, x1: number, y0: number, y1: number }): boolean
	return fx >= z.x0 and fx <= z.x1 and fy >= z.y0 and fy <= z.y1
end

-- pos: input position (below the topbar inset, like InputObject.Position).
-- True when the tap landed on UI (any button, text box or solid panel) or, for touches,
-- on the thumbstick / jump areas.
function Tapper.isBlocked(pos: Vector2, isTouch: boolean): boolean
	if isTouch then
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			local abs = pos + GuiService:GetGuiInset()
			local fx, fy = abs.X / vp.X, abs.Y / vp.Y
			if inZone(fx, fy, THUMBSTICK_ZONE) or inZone(fx, fy, JUMP_ZONE) then
				return true
			end
		end
	end
	for _, g in playerGui:GetGuiObjectsAtPosition(pos.X, pos.Y) do
		if g:IsDescendantOf(fxGui) then
			continue
		end
		if g:IsA("GuiButton") or g:IsA("TextBox") then
			return true
		end
		if g.BackgroundTransparency < 0.95 then
			return true
		end
	end
	return false
end

function Tapper.init()
	local lastTouch = -1
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		local isTouch = t == Enum.UserInputType.Touch
		if not isTouch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if isTouch then
			lastTouch = os.clock()
		elseif os.clock() - lastTouch < 0.1 then
			return -- emulated mouse click from the same touch
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if Tapper.isBlocked(pos, isTouch) then
			return
		end
		tap(pos)
	end)

	local lastHit = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		-- combo label trails the last tap and fades when the combo drops
		if comboShown then
			local s = Root.scale
			local want = UDim2.fromOffset(comboAt.X, comboAt.Y - 150 * s)
			comboLabel.Position = comboLabel.Position:Lerp(want, math.min(1, dt * 14))
			if combo >= 100 then
				comboLabel.TextColor3 = comboColor(combo, now)
			end
			if now - lastTap > COMBO_WINDOW then
				comboShown = false
				combo = 0
				Tapper.combo = 0
				TweenService:Create(comboLabel, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
				TweenService:Create(comboStroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end
		-- tokens fly along a curve into the Taps counter
		if #flying > 0 then
			local target = Vector2.zero
			local c = counter
			if c then
				target = c.AbsolutePosition + Vector2.new(c.AbsoluteSize.Y * 0.5, c.AbsoluteSize.Y * 0.5) - layer.AbsolutePosition
			end
			for i = #flying, 1, -1 do
				local f = flying[i]
				f.t += dt / 0.42
				local t = math.min(1, f.t)
				local e = t * t
				local a = f.from:Lerp(f.ctrl, e)
				local b = f.ctrl:Lerp(target, e)
				local p = a:Lerp(b, e)
				f.frame.Position = UDim2.fromOffset(p.X, p.Y)
				if t >= 1 then
					f.frame.Visible = false
					table.insert(tokenPool, f.frame)
					table.remove(flying, i)
					if now - lastHit > 0.09 then
						lastHit = now
						onCounterHit()
					end
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.TapSendInterval)
			if pending > 0 then
				tapEvent:FireServer(pending)
				pending = 0
			end
		end
	end)
end

return Tapper
