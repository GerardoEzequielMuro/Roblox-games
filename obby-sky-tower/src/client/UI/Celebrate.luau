--!strict
-- Stage-reached celebration: big pop-up text, UI confetti rain and a 3D particle burst.
-- No sounds (no uploaded assets); everything is tween/particle based.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Kit = require(script.Parent.Kit)
local Lang = require(script.Parent.Parent.Lang)

local Celebrate = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local CONFETTI_COLORS = {
	Kit.C.pink,
	Kit.C.yellow,
	Kit.C.blue,
	Kit.C.green,
	Kit.C.purple,
	Kit.C.orange,
}

local region: Frame? = nil
local confettiLayer: Frame? = nil

local function ensure(): (Frame, Frame)
	if region and confettiLayer then
		return region, confettiLayer
	end
	local r = Kit.region("Celebrate", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.36), Vector2.new(700, 260))
	r.ZIndex = 30
	local layer = Kit.frame(Kit.gui(), UDim2.fromScale(1, 1), UDim2.new(), nil)
	layer.Name = "Confetti"
	layer.ZIndex = 29
	layer.ClipsDescendants = true
	region, confettiLayer = r, layer
	return r, layer
end

local function confetti(count: number)
	local _, layer = ensure()
	local h = layer.AbsoluteSize.Y
	for _ = 1, count do
		local size = math.random(8, 16)
		local piece = Kit.frame(layer, UDim2.fromOffset(size, size * 0.6), UDim2.new(math.random(), 0, 0, -20), CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)])
		piece.ZIndex = 29
		piece.Rotation = math.random(0, 360)
		local duration = 1.6 + math.random() * 1.2
		local drift = (math.random() - 0.5) * 0.25
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + drift, 0, 0, h + 30),
			Rotation = piece.Rotation + math.random(-540, 540),
		}):Play()
		task.delay(duration + 0.05, function()
			piece:Destroy()
		end)
	end
end

local function burst3D()
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLES
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(18, 30)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Size = NumberSequence.new(0.7, 0.1)
	e.LightEmission = 0.8
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Kit.C.pink),
		ColorSequenceKeypoint.new(0.33, Kit.C.yellow),
		ColorSequenceKeypoint.new(0.66, Kit.C.blue),
		ColorSequenceKeypoint.new(1, Kit.C.green),
	})
	e.Parent = root
	e:Emit(45)
	task.delay(2, function()
		e:Destroy()
	end)
end

local showing = 0
-- `ribbon` = two colours: the subtitle sits on a banner in those colours (new world, win).
function Celebrate.show(title: string, subtitle: string?, big: boolean?, ribbon: { Color3 }?)
	local r = ensure()
	showing += 1
	local my = showing
	for _, c in r:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local t = Kit.bold(r, title, UDim2.new(1, 0, 0, if big then 130 else 100), UDim2.fromScale(0.5, 0), Kit.C.yellow, Vector2.new(0.5, 0), if big then 110 else 84)
	t.Rotation = -3
	Kit.pop(t, 0.2)
	if subtitle then
		local y = if big then 140 else 108
		if ribbon then
			local band = Kit.frame(r, UDim2.new(0.94, 0, 0, 68), UDim2.new(0.5, 0, 0, y - 6), Color3.new(1, 1, 1), Vector2.new(0.5, 0))
			band.Name = "Ribbon"
			band.ClipsDescendants = true
			Kit.corner(band, 18)
			Kit.stroke(band, Kit.C.ink, 4)
			Kit.gradient(band, ribbon[1], ribbon[2] or ribbon[1], 0)
			Kit.pop(band, 0.2)
			-- a bright sweep across the banner
			local shine = Kit.frame(band, UDim2.new(0.16, 0, 1.6, 0), UDim2.fromScale(-0.25, -0.3), Color3.new(1, 1, 1))
			shine.BackgroundTransparency = 0.6
			shine.Rotation = 14
			TweenService:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.25), { Position = UDim2.fromScale(1.15, -0.3) }):Play()
		end
		local s = Kit.bold(r, subtitle, UDim2.new(if ribbon then 0.88 else 1, 0, 0, 56), UDim2.new(0.5, 0, 0, y), Kit.C.white, Vector2.new(0.5, 0), 44)
		Kit.pop(s, 0.4)
	end
	confetti(if big then 110 else 45)
	burst3D()
	task.delay(if big then 4 else 2.2, function()
		if showing ~= my then
			return
		end
		for _, c in r:GetChildren() do
			if c:IsA("TextLabel") then
				TweenService:Create(c, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				local st = c:FindFirstChildOfClass("UIStroke")
				if st then
					TweenService:Create(st, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				end
			elseif c:IsA("Frame") then
				c:Destroy() -- ribbon
			end
		end
	end)
end

function Celebrate.stage(data: { [string]: any })
	local stage = tonumber(data.stage) or 0
	local coins = tonumber(data.coins) or 0
	local sub = if coins > 0 then Lang.t("celebrate.coins", { n = coins }) else nil
	local title = Lang.t("celebrate.stage", { n = stage })
	if data.world and data.style then
		-- first pad of a new world: its number (1..100) and its look (1..10) in this tower's colours
		local theme = Config.theme(Layout.towerOf(stage + 1), data.style :: number)
		Celebrate.show(title, Lang.t("celebrate.world", { n = data.world, name = { key = "world." .. data.style } }), true, { theme.platform:Lerp(Kit.C.ink, 0.3), theme.accent:Lerp(Kit.C.ink, 0.3) })
		return
	end
	if stage % Layout.STAGES == 0 then
		return -- a summit: the Win event shows its own celebration
	end
	Celebrate.show(title, sub, false)
end

return Celebrate
