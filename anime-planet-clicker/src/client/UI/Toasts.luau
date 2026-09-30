--!strict
-- Notifications (personal), server-wide announcements (rare pets, gates) and the big
-- milestone card in the middle of the screen ("GALAXY UNLOCKED!", "REBIRTH!").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Format)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local Toasts = {}

local stack = Theme.new("Frame", {
	Name = "Toasts",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(520, 240),
	Position = UDim2.new(0.5, 0, 0, if Root.isTouch then 96 else 132),
	AnchorPoint = Vector2.new(0.5, 0),
	ZIndex = 40,
	Parent = Root.gui,
}, { Theme.list(Enum.FillDirection.Vertical, 6) })
Root.mount(stack)

local KIND_COLORS = {
	info = Theme.Blue,
	success = Theme.Green,
	error = Theme.Red,
}

local order = 0
local lastText, lastAt = "", 0
function Toasts.show(text: string, kind: string?, duration: number?)
	-- the same line twice in a row (spam clicking) only shows once
	if text == lastText and os.clock() - lastAt < 1.2 then
		return
	end
	lastText, lastAt = text, os.clock()
	order += 1
	local color = KIND_COLORS[kind or "info"] or Theme.Blue
	local f = Theme.new("Frame", {
		Size = UDim2.fromOffset(480, 42),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		ZIndex = 40,
		Parent = stack,
	}, { Theme.corner(21), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.15), Theme.darken(color, 0.15)) })
	local sc = Theme.new("UIScale", { Scale = 0.5, Parent = f })
	Theme.text({ Text = text, Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), MaxTextSize = 24, ZIndex = 41, Parent = f })
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	if kind == "error" then
		Theme.play("error", 0.3, 0.7)
	end
	task.delay(duration or 2.6, function()
		local t = TweenService:Create(sc, TweenInfo.new(0.2), { Scale = 0 })
		t:Play()
		t.Completed:Wait()
		f:Destroy()
	end)
	local frames = {}
	for _, c in stack:GetChildren() do
		if c:IsA("Frame") then
			table.insert(frames, c)
		end
	end
	if #frames > 4 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end
end

-- Banner across the top for things that happen to other players.
local banner = Theme.new("Frame", {
	Name = "Announce",
	Size = UDim2.fromOffset(620, 54),
	Position = UDim2.new(0.5, 0, 0, if Root.isTouch then 40 else 74),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
	ZIndex = 45,
	Parent = Root.gui,
}, { Theme.corner(16), Theme.stroke(3) })
Root.mount(banner).ClipsDescendants = false
local HIDDEN = UDim2.new(0.5, 0, 0.5, -170)
local SHOWN = UDim2.new(0.5, 0, 0.5, 0)
banner.Position = HIDDEN
local bannerGradient = Theme.new("UIGradient", { Rotation = 90, Parent = banner })
local bannerText = Theme.text({ Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), MaxTextSize = 26, RichText = true, Stroke = 3, ZIndex = 46, Parent = banner })
local queue: { { text: string, color: Color3 } } = {}
local busy = false

local function nextBanner()
	if busy or #queue == 0 then
		return
	end
	busy = true
	local item = table.remove(queue, 1) :: { text: string, color: Color3 }
	bannerText.Text = item.text
	bannerGradient.Color = ColorSequence.new(Theme.lighten(item.color, 0.2), Theme.darken(item.color, 0.2))
	banner.Visible = true
	banner.Position = HIDDEN
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = SHOWN }):Play()
	task.delay(3.4, function()
		local t = TweenService:Create(banner, TweenInfo.new(0.25), { Position = HIDDEN })
		t:Play()
		t.Completed:Wait()
		banner.Visible = false
		busy = false
		nextBanner()
	end)
end

function Toasts.banner(text: string, color: Color3)
	table.insert(queue, { text = text, color = color })
	while #queue > 5 do
		table.remove(queue, 1)
	end
	nextBanner()
end

-- Milestone card: big slanted title in the middle for ~1.6 s.
local mile = Theme.new("Frame", { Name = "Milestone", BackgroundTransparency = 1, Size = UDim2.fromOffset(820, 150), Position = UDim2.fromScale(0.5, 0.3), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 50, Parent = Root.gui })
Root.mount(mile)
local mileTitle = Theme.text({ Name = "Title", Text = "", Size = UDim2.new(1, 0, 0.62, 0), MaxTextSize = 78, Stroke = 5, ZIndex = 51, Parent = mile })
mileTitle.Rotation = -3
local mileSub = Theme.text({ Name = "Sub", Text = "", Size = UDim2.new(1, 0, 0.3, 0), Position = UDim2.fromScale(0, 0.68), MaxTextSize = 34, Stroke = 3, ZIndex = 51, Parent = mile })
local mileScale = Theme.new("UIScale", { Parent = mile }) :: UIScale
local mileToken = 0
function Toasts.milestone(title: string, sub: string?, color: Color3?)
	mileToken += 1
	local my = mileToken
	mileTitle.Text = title
	mileTitle.TextColor3 = color or Theme.Yellow
	mileSub.Text = sub or ""
	mile.Visible = true
	mileScale.Scale = 0.3
	TweenService:Create(mileScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Theme.play("boom", 0.35, 1.3)
	task.delay(1.7, function()
		if my ~= mileToken then
			return
		end
		local t = TweenService:Create(mileScale, TweenInfo.new(0.18), { Scale = 0 })
		t:Play()
		t.Completed:Wait()
		if my == mileToken then
			mile.Visible = false
		end
	end)
end

-- Announcements from the server. Translated per recipient: the server only sends ids.
function Toasts.announce(data: { [string]: any })
	if data.kind == "gate" then
		Toasts.banner("🚀 " .. Lang.t("announce.gate", { player = data.player, zone = Lang.zone(data.zone) }), Theme.Purple)
		return
	end
	local c = Palette.rarity(data.rarity)
	local hex = c:Lerp(Color3.new(1, 1, 1), 0.5):ToHex()
	local chance = if type(data.chanceText) == "string" then data.chanceText else Format.chance(tonumber(data.chance) or 0)
	local petText = string.format('<font color="#%s">%s %s</font>', hex, Lang.rarity(data.rarity), Lang.pet(data.pet, data.tier))
	Toasts.banner((if data.global then "🌍 " else "✨ ") .. Lang.t(if data.global then "announce.global" else "announce.pet", { player = data.player, pet = petText, chance = chance }), if data.global then Theme.Orange else c)
end

function Toasts.init()
	Net.event("Notify").OnClientEvent:Connect(function(message, kind)
		Toasts.show(Lang.msg(message), kind)
	end)
	Net.event("Toast").OnClientEvent:Connect(function(data)
		Toasts.announce(data)
	end)
end

return Toasts
