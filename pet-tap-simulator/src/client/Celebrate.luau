--!strict
-- Code-only celebration effects: a pooled burst of sparkles (built-in rbxasset:// texture),
-- the "new button unlocked" moment and the level-up style banner. Cheap on purpose: one pool
-- of at most Juice.MAX_BURST_PARTS image labels shared by every burst, counts scaled by the
-- graphics profile (Quality.particles), nothing flashes, and it all goes through the existing
-- Theme.play sound hooks (no sound ids invented here).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Juice = require(ReplicatedStorage.Shared.Juice)
local Quality = require(script.Parent.Quality)
local Shake = require(script.Parent.Shake)
local Lang = require(script.Parent.Lang)
local Theme = require(script.Parent.UI.Theme)
local Root = require(script.Parent.UI.Root)
local Toasts = require(script.Parent.UI.Toasts)

local Celebrate = {}

local TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local gui = Theme.new("ScreenGui", {
	Name = "CelebrateFx",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None,
	DisplayOrder = 6,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
}) :: ScreenGui

local free: { ImageLabel } = {}
local alive = 0

local function take(): ImageLabel
	local p = table.remove(free)
	if p then
		p.Visible = true
		return p
	end
	return Theme.new("ImageLabel", {
		Image = TEXTURE,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = gui,
	}) :: ImageLabel
end

-- pos: screen pixels (nil = a bit above the middle of the screen). color: tint of the sparkles.
function Celebrate.burst(pos: Vector2?, color: Color3, want: number?)
	local n = Juice.allowBurst(want or 12, alive, Juice.MAX_BURST_PARTS, Quality.particles)
	if n <= 0 then
		return
	end
	local origin = pos or (gui.AbsoluteSize * Vector2.new(0.5, 0.4))
	local s = Root.scale
	for i = 1, n do
		local p = take()
		alive += 1
		local a = (i / n + math.random() * 0.15) * math.pi * 2
		local dist = (70 + math.random() * 70) * s
		local size = (26 + math.random() * 22) * s
		p.ImageColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else color
		p.ImageTransparency = 0
		p.Rotation = math.random(0, 180)
		p.Size = UDim2.fromOffset(size * 0.3, size * 0.3)
		p.Position = UDim2.fromOffset(origin.X, origin.Y)
		TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(origin.X + math.cos(a) * dist, origin.Y + math.sin(a) * dist),
			Rotation = p.Rotation + 120,
		}):Play()
		TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.28), { ImageTransparency = 1 }):Play()
		task.delay(0.62, function()
			p.Visible = false
			alive -= 1
			table.insert(free, p)
		end)
	end
end

-- The "you unlocked something" moment: names are HudUnlock names (menu.<Name> translations).
function Celebrate.unlock(names: { string })
	if #names == 0 then
		return
	end
	local labels: { string } = {}
	for i, name in names do
		if i > 3 then
			break
		end
		table.insert(labels, Lang.t("menu." .. name))
	end
	Toasts.banner("✨ " .. Lang.t("ftue.unlocked", { names = table.concat(labels, ", ") }), Theme.Purple)
	Theme.play("open", 0.4, 1.4)
	Theme.play("buy", 0.35, 1.5)
	Shake.kick(0.35, 0.25)
	Celebrate.burst(nil, Theme.Yellow, 14)
end

return Celebrate
