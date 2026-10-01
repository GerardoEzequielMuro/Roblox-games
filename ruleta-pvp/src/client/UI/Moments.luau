--!strict
-- The two "you got something" moments: level up and a cosmetic unlock. One reusable card
-- (no stacking: a new moment replaces the old one) with a Back-ease pop, a rarity-coloured
-- rim and a particle burst through the pooled Fx (which already honours the lite profile
-- and its part cap). Reduced motion (shake off) swaps the overshoot for a plain fade and
-- the screen flash needs the flashes setting. Sound goes through the Audio hooks (the "win"
-- cue plays once the owner has filled its id in; nothing is invented here).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Lang = require(script.Parent.Parent.Lang)
local Audio = require(script.Parent.Parent.Audio)
local Prefs = require(script.Parent.Parent.Prefs)
local Fx = require(script.Parent.Parent.Arena.Fx)

local Moments = {}
Moments.shown = 0
Moments.lastKind = ""

-- Burst size, hold time and card scale per rarity tier.
local TIER = {
	common = { burst = 0, hold = 2.2, scale = 1 },
	rare = { burst = 12, hold = 2.6, scale = 1 },
	epic = { burst = 24, hold = 3, scale = 1.06 },
	legendary = { burst = 44, hold = 3.6, scale = 1.14 },
} :: { [string]: { burst: number, hold: number, scale: number } }

local card = Theme.panel({ Name = "Moment", Size = UDim2.fromOffset(340, 104), Position = UDim2.fromScale(0.5, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Corner = 22, StrokeThickness = 5, Visible = false, ZIndex = 50, Parent = Root.overlay })
local cardScale = Theme.new("UIScale", { Parent = card }) :: UIScale
local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
local icon = Theme.text({ Name = "Icon", Text = "", Stroke = false, Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(12, 17), ZIndex = 51, Parent = card })
local head = Theme.text({ Name = "Head", Text = "", Title = true, Size = UDim2.new(1, -108, 0, 38), Position = UDim2.fromOffset(92, 10), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 32, ZIndex = 51, Parent = card })
local sub = Theme.text({ Name = "Sub", Text = "", Size = UDim2.new(1, -108, 0, 40), Position = UDim2.fromOffset(92, 52), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, TextWrapped = true, ZIndex = 51, Parent = card })

local token = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function burstPos(): Vector3?
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		return hrp.Position + Vector3.new(0, 4, 0)
	end
	return nil
end

local function show(kind: string, ic: string, title: string, subtitle: string, color: Color3, tier: { burst: number, hold: number, scale: number })
	token += 1
	local mine = token
	Moments.shown += 1
	Moments.lastKind = kind
	icon.Text = ic
	head.Text = title
	head.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	sub.Text = subtitle
	cardStroke.Color = color
	card.Visible = true
	local calm = not Prefs.shake()
	cardScale.Scale = if calm then tier.scale else 0.3
	card.Rotation = if calm then 0 else -4
	TweenService:Create(cardScale, TweenInfo.new(0.3, if calm then Enum.EasingStyle.Quad else Enum.EasingStyle.Back), { Scale = tier.scale }):Play()
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
	task.delay(tier.hold, function()
		if token ~= mine then
			return
		end
		local t = TweenService:Create(cardScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		t:Play()
		t.Completed:Once(function()
			if token == mine then
				card.Visible = false
			end
		end)
	end)
	local pos = burstPos()
	if pos and tier.burst > 0 then
		Fx.shards(pos, color, tier.burst, 26, { life = 1.4, size = 0.5, up = 1 })
		Fx.ring(pos - Vector3.new(0, 3.5, 0), color, 2, 9 + tier.burst / 6, 0.7)
	end
end

function Moments.levelUp(level: number, coins: number)
	Audio.play("win", 0.6, 1.1)
	Audio.play("heal", 0.5, 1.4)
	show("level", "⬆️", Lang.t("hud.level_up"), Lang.t("toast.level_up", { n = level, coins = coins }), Theme.Yellow, TIER.epic)
	local pos = burstPos()
	if pos then
		Fx.confetti(pos, 26, 30)
	end
end

-- Rare and better get the card and a bigger burst; commons stay a toast (the caller shows it).
function Moments.unlock(id: string): boolean
	local item = Config.CosmeticById[id]
	if not item then
		return false
	end
	local tier = TIER[item.rarity]
	if not tier or tier.burst == 0 then
		return false
	end
	local def = Config.RarityById[item.rarity]
	local color = if def then rgb(def.color) else Theme.Cyan
	Audio.play("win", 0.7, if item.rarity == "legendary" then 0.9 else 1.15)
	show("unlock", item.icon, Lang.t("reveal.new"), Lang.t("cos." .. id) .. "\n" .. Lang.t("rarity." .. item.rarity), color, tier)
	return true
end

return Moments
