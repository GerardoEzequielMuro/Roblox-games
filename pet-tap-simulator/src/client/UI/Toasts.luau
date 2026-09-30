--!strict
-- Notifications (personal) and server-wide rare-hatch announcements.
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
	Size = UDim2.fromOffset(560, 300),
	-- PC: below the currency bar and the banner; touch: between the HUD columns
	Position = if Root.isTouch then UDim2.new(0.5, 0, 0, 84) else UDim2.new(0.5, 0, 0, 176),
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
function Toasts.show(text: string, kind: string?, duration: number?)
	order += 1
	local color = KIND_COLORS[kind or "info"] or Theme.Blue
	local f = Theme.new("Frame", {
		Size = UDim2.fromOffset(520, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = stack,
	}, { Theme.corner(22), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.2), color) })
	local sc = Theme.new("UIScale", { Scale = 0.5, Parent = f })
	Theme.text({ Text = text, Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), MaxTextSize = 26, Parent = f })
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
	-- keep the stack short
	local frames = {}
	for _, c in stack:GetChildren() do
		if c:IsA("Frame") then
			table.insert(frames, c)
		end
	end
	if #frames > 5 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end
end

-- Big banner for Legendary+ hatches from anyone in the server.
local banner = Theme.new("Frame", {
	Name = "Announce",
	Size = UDim2.fromOffset(640, 64),
	Position = if Root.isTouch then UDim2.new(0.5, 0, 0, 8) else UDim2.new(0.5, 0, 0, 100),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
	ZIndex = 45,
	Parent = Root.gui,
}, { Theme.corner(18), Theme.stroke(4) })
Root.mount(banner).ClipsDescendants = false
local HIDDEN = UDim2.new(0.5, 0, 0.5, -160)
local SHOWN = UDim2.new(0.5, 0, 0.5, 0)
banner.Position = HIDDEN
local bannerGradient = Theme.new("UIGradient", { Rotation = 0, Parent = banner })
local bannerText = Theme.text({ Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), MaxTextSize = 30, RichText = true, Stroke = 3, Parent = banner })
local queue: { { text: string, color: Color3 } } = {}
local busy = false

local function nextBanner()
	if busy or #queue == 0 then
		return
	end
	busy = true
	local item = table.remove(queue, 1) :: { text: string, color: Color3 }
	bannerText.Text = item.text
	bannerGradient.Color = ColorSequence.new(Theme.lighten(item.color, 0.3), item.color)
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

-- Big top banner (rare hatches, live events). Keeps at most 5 waiting.
function Toasts.banner(text: string, color: Color3)
	table.insert(queue, { text = text, color = color })
	while #queue > 5 do
		table.remove(queue, 1)
	end
	nextBanner()
end

-- Rare hatch from this server, or from another server (data.global, gold banner).
-- Translated per recipient: the server only sends ids.
function Toasts.announce(data: { [string]: any })
	local c = Palette.rarity(data.rarity)
	if data.rarity == "Secret" then
		c = Color3.fromRGB(170, 60, 255)
	end
	local hex = c:Lerp(Color3.new(1, 1, 1), 0.5):ToHex()
	local chance = if type(data.chanceText) == "string" then data.chanceText else Format.chance(tonumber(data.chance) or 0)
	if data.global then
		local petText = string.format('<font color="#%s">%s</font>', hex, Lang.pet(data.pet, data.tier))
		Toasts.banner("🌍 " .. Lang.t("announce.global", { player = data.player, pet = petText, chance = chance }), Color3.fromRGB(255, 190, 40))
		return
	end
	local petText = string.format('<font color="#%s">%s %s</font>', hex, Lang.rarity(data.rarity), Lang.pet(data.pet, data.tier))
	Toasts.banner(Lang.t("announce.hatch", { player = data.player, pet = petText, chance = chance }), c)
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
