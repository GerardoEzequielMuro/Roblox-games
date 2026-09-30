--!strict
-- The capsule opening. Manual opens: the capsule drops in, shakes, cracks in two with a
-- flash and the pets are revealed on rarity cards (chance, NEW!, rays and a screen shake
-- for Legendary and better). Auto Open shows a compact strip instead and never blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local PetIcon = require(script.Parent.PetIcon)
local Lang = require(script.Parent.Parent.Lang)

local CapsuleCinematic = {}

local playing = false
local queue: { { capsule: string, results: { any } } } = {}
local busyCallback: ((boolean) -> ())? = nil
local skip = false

function CapsuleCinematic.isPlaying(): boolean
	return playing
end

function CapsuleCinematic.setBusyCallback(fn: (boolean) -> ())
	busyCallback = fn
end

local function capsuleColor(capsuleId: string): Color3
	local cap = Formulas.CapsuleById[capsuleId]
	if cap and cap.exclusive then
		return Color3.fromRGB(150, 90, 240)
	end
	local zone = if cap then cap.zone else 1
	local colors = { Theme.Orange, Color3.fromRGB(90, 210, 130), Color3.fromRGB(110, 190, 255), Color3.fromRGB(255, 110, 60), Color3.fromRGB(250, 220, 90), Color3.fromRGB(230, 90, 220) }
	return colors[zone] or Theme.Orange
end

-- A pet card. size in offset pixels (the overlay is not scaled, so callers pass scaled sizes).
local function card(parent: Instance, r: any, width: number, height: number): Frame
	local color = Palette.rarity(r.rarity)
	local f = Theme.new("Frame", { Name = "Card", Size = UDim2.fromOffset(width, height), BackgroundColor3 = Color3.new(1, 1, 1), Parent = parent }, {
		Theme.corner(math.floor(width * 0.09)), Theme.stroke(4), Theme.gradient(Theme.lighten(color, 0.35), Theme.darken(color, 0.5)),
	}) :: Frame
	local order = Config.RarityByName[r.rarity].order
	if order >= 5 then
		-- rays behind the pet for Legendary and better
		local rays = Theme.new("Frame", { Name = "Rays", BackgroundTransparency = 1, Size = UDim2.fromScale(1.5, 1.5), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), ClipsDescendants = false, Parent = f })
		for i = 1, 8 do
			Theme.new("Frame", { Size = UDim2.new(0.06, 0, 1, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = i * 22.5, BackgroundColor3 = Theme.lighten(color, 0.6), BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = rays })
		end
		task.spawn(function()
			while rays.Parent do
				rays.Rotation += 0.6
				task.wait()
			end
		end)
		f.ClipsDescendants = true
	end
	local vp = PetIcon.new(r.id, r.tier)
	vp.Size = UDim2.fromScale(0.92, 0.56)
	vp.Position = UDim2.fromScale(0.04, 0.1)
	vp.Parent = f
	Theme.text({ Text = Lang.pet(r.id, r.tier), Size = UDim2.fromScale(0.92, 0.13), Position = UDim2.fromScale(0.04, 0.66), MaxTextSize = math.floor(height * 0.1), Parent = f })
	Theme.text({ Text = Lang.rarity(r.rarity), TextColor3 = Theme.lighten(color, 0.5), Size = UDim2.fromScale(0.92, 0.1), Position = UDim2.fromScale(0.04, 0.79), MaxTextSize = math.floor(height * 0.08), Parent = f })
	local chanceLabel = Theme.text({ Text = Format.percent(r.chance), TextColor3 = Theme.Yellow, Size = UDim2.fromScale(0.92, 0.09), Position = UDim2.fromScale(0.04, 0.89), MaxTextSize = math.floor(height * 0.07), Parent = f })
	chanceLabel.AutoLocalize = false
	if r.deleted then
		Theme.text({ Text = "🗑️ " .. Lang.t("capsule.auto_deleted"), TextColor3 = Theme.Red, Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.01), MaxTextSize = math.floor(height * 0.07), Parent = f })
		f.BackgroundTransparency = 0.5
	elseif r.new then
		local tag = Theme.new("Frame", { Name = "New", Size = UDim2.fromScale(0.4, 0.11), Position = UDim2.fromScale(0.03, 0.02), Rotation = -8, BackgroundColor3 = Theme.Red, Parent = f }, { Theme.corner(8), Theme.stroke(3) })
		Theme.text({ Key = "capsule.new", Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), Parent = tag })
	end
	return f
end

local function run(capsuleId: string, results: { any })
	playing = true
	skip = false
	if busyCallback then
		busyCallback(true)
	end
	local overlay = Root.overlay
	local vpSize = overlay.AbsoluteSize
	local unit = math.clamp(math.min(vpSize.X / 1100, vpSize.Y / 560), 0.5, 1.3)
	local holder = Theme.new("TextButton", { Name = "Capsule", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 20), BackgroundTransparency = 1, Parent = overlay }) :: TextButton
	holder.Activated:Connect(function()
		skip = true
	end)
	TweenService:Create(holder, TweenInfo.new(0.2), { BackgroundTransparency = 0.35 }):Play()
	local color = capsuleColor(capsuleId)
	local best = 1
	for _, r in results do
		best = math.max(best, Config.RarityByName[r.rarity].order)
	end
	-- the capsule: two halves of a rounded pill
	local size = math.floor(170 * unit)
	local capsule = Theme.new("Frame", { Name = "Shell", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Position = UDim2.new(0.5, 0, 0, -size), AnchorPoint = Vector2.new(0.5, 0.5), Parent = holder }) :: Frame
	local top = Theme.new("Frame", { Name = "Top", Size = UDim2.fromScale(1, 0.52), BackgroundColor3 = Color3.new(1, 1, 1), Parent = capsule }, { Theme.corner(size // 2), Theme.stroke(5), Theme.gradient(Theme.lighten(color, 0.45), color) }) :: Frame
	local bottom = Theme.new("Frame", { Name = "Bottom", Size = UDim2.fromScale(1, 0.52), Position = UDim2.fromScale(0, 0.48), BackgroundColor3 = Color3.new(1, 1, 1), Parent = capsule }, { Theme.corner(size // 2), Theme.stroke(5), Theme.gradient(Color3.fromRGB(245, 246, 252), Color3.fromRGB(170, 176, 200)) }) :: Frame
	Theme.new("Frame", { Name = "Band", Size = UDim2.new(1, 8, 0.1, 0), Position = UDim2.new(0, -4, 0.45, 0), BackgroundColor3 = Theme.Ink, BorderSizePixel = 0, Parent = capsule }, { Theme.corner(6) })
	local glint = Theme.new("Frame", { Size = UDim2.fromScale(0.22, 0.2), Position = UDim2.fromScale(0.18, 0.12), BackgroundColor3 = Theme.White, BackgroundTransparency = 0.3, Rotation = -25, Parent = top }, { Theme.corner(20) })
	glint.ZIndex = 2
	Theme.play("open", 0.4, 0.8)
	TweenService:Create(capsule, TweenInfo.new(0.35, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.45) }):Play()
	local function wait(seconds: number)
		local t = 0
		while t < seconds and not skip do
			t += task.wait()
		end
	end
	wait(0.4)
	-- shake, harder for rarer contents, with a glow of the best rarity building up
	local glow = Theme.new("Frame", { Name = "Glow", Size = UDim2.fromOffset(size * 2, size * 2), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Palette.rarity(results[1] and results[1].rarity or "Common"), BackgroundTransparency = 1, ZIndex = 0, Parent = holder }, { Theme.corner(size) }) :: Frame
	for _, r in results do
		if Config.RarityByName[r.rarity].order == best then
			glow.BackgroundColor3 = Palette.rarity(r.rarity)
		end
	end
	local shakeTime = if best >= 5 then 1.1 elseif best >= 4 then 0.75 else 0.5
	local t0 = os.clock()
	while os.clock() - t0 < shakeTime and not skip do
		local k = (os.clock() - t0) / shakeTime
		capsule.Rotation = math.sin(os.clock() * (30 + k * 40)) * (4 + k * 10)
		glow.BackgroundTransparency = 1 - k * (if best >= 4 then 0.6 else 0.3)
		glow.Size = UDim2.fromOffset(size * (1.6 + k), size * (1.6 + k))
		task.wait()
	end
	capsule.Rotation = 0
	-- crack: halves fly apart, flash
	Theme.play(if best >= 5 then "boom" else "hit", 0.5, 1)
	TweenService:Create(top, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, -0.9), Rotation = -25, BackgroundTransparency = 1 }):Play()
	TweenService:Create(bottom, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 1.3), Rotation = 20, BackgroundTransparency = 1 }):Play()
	local flash = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.White, BackgroundTransparency = if best >= 5 then 0 else 0.4, ZIndex = 5, Parent = holder })
	TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(glow, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	wait(0.12)
	capsule.Visible = false
	-- cards
	local n = #results
	local cw = math.floor((if n > 1 then 190 else 240) * unit)
	local ch = math.floor(cw * 1.32)
	local row = Theme.new("Frame", { Name = "Cards", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ch), Position = UDim2.fromScale(0.5, 0.46), AnchorPoint = Vector2.new(0.5, 0.5), Parent = holder }, {
		Theme.list(Enum.FillDirection.Horizontal, math.floor(18 * unit), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	for i, r in results do
		local c = card(row, r, cw, ch)
		c.LayoutOrder = i
		local sc = Theme.new("UIScale", { Scale = 0.2, Parent = c })
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		wait(0.12)
	end
	local hint = Theme.text({ Key = "capsule.tap_continue", Size = UDim2.new(1, 0, 0, math.floor(30 * unit)), Position = UDim2.new(0, 0, 0.46, ch // 2 + math.floor(16 * unit)), MaxTextSize = math.floor(24 * unit), TextColor3 = Color3.fromRGB(220, 225, 245), Parent = holder })
	hint.TextTransparency = 0.2
	skip = false
	wait(if best >= 5 then 2.6 else 1.5)
	TweenService:Create(holder, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
	holder:Destroy()
	playing = false
	if busyCallback then
		busyCallback(false)
	end
end

-- Auto Open: a strip of small cards near the top, 1.2 s, no input blocking.
local strip: Frame? = nil
local function playAuto(results: { any })
	if strip then
		strip:Destroy()
	end
	local overlay = Root.overlay
	local vpSize = overlay.AbsoluteSize
	local unit = math.clamp(math.min(vpSize.X / 1100, vpSize.Y / 560), 0.5, 1.2)
	local cw = math.floor(96 * unit)
	local f = Theme.new("Frame", { Name = "AutoStrip", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.floor(cw * 1.32)), Position = UDim2.new(0.5, 0, 0.2, 0), AnchorPoint = Vector2.new(0.5, 0), Parent = overlay }, {
		Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	}) :: Frame
	strip = f
	for i, r in results do
		local c = card(f, r, cw, math.floor(cw * 1.32))
		c.LayoutOrder = i
	end
	task.delay(1.2, function()
		if strip == f then
			strip = nil
		end
		f:Destroy()
	end)
end

function CapsuleCinematic.play(capsuleId: string, results: { any }, auto: boolean?)
	if #results == 0 then
		return
	end
	if auto then
		playAuto(results)
		return
	end
	table.insert(queue, { capsule = capsuleId, results = results })
	if playing then
		return
	end
	task.spawn(function()
		while #queue > 0 do
			local job = table.remove(queue, 1) :: { capsule: string, results: { any } }
			local ok, err = pcall(function()
				run(job.capsule, job.results)
			end)
			if not ok then
				warn("[CapsuleCinematic]", err)
				playing = false
				local leftover = Root.overlay:FindFirstChild("Capsule")
				if leftover then
					leftover:Destroy()
				end
				if busyCallback then
					busyCallback(false)
				end
			end
		end
	end)
end

function CapsuleCinematic.init()
	UserInputService.InputBegan:Connect(function(input)
		if playing and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA) then
			skip = true
		end
	end)
end

return CapsuleCinematic
