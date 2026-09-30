--!nonstrict
-- "Get notified when big events start?" card, shown when the server fires AskNotifications (a happy moment) and
-- Roblox says we may prompt. Yes -> ExperienceNotificationService:PromptOptIn().
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L

local NotifyCard = {}
NotifyCard.frame = nil :: Frame?

function NotifyCard.build(root: Instance)
	local f: Frame = C.new("Frame", {
		Name = "NotifyCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(420, 190),
		BackgroundColor3 = Theme.C.Panel,
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	C.corner(f, 22)
	C.stroke(f, 5, Theme.C.PanelEdge)
	C.label(f, L("notify.question"), UDim2.new(1, -30, 0, 90), {
		Position = UDim2.fromOffset(15, 12),
		TextSize = 24,
		TextColor3 = Theme.C.Ink,
		Outline = false,
	})
	C.button({
		Name = "Yes",
		Parent = f,
		Text = L("notify.yes"),
		TextSize = 24,
		Color = Theme.C.Green,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -16),
		Size = UDim2.fromOffset(180, 56),
		OnClick = function()
			f.Visible = false
			pcall(function()
				ExperienceNotificationService:PromptOptIn()
			end)
		end,
	})
	C.button({
		Name = "No",
		Parent = f,
		Text = L("notify.no"),
		TextSize = 24,
		Color = Theme.C.Grey,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -16),
		Size = UDim2.fromOffset(180, 56),
		OnClick = function()
			f.Visible = false
		end,
	})
	NotifyCard.frame = f
end

-- Called on AskNotifications; only shows the card when Roblox allows the opt-in prompt.
function NotifyCard.ask()
	local ok, can = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if ok and can and NotifyCard.frame then
		NotifyCard.frame.Visible = true
	end
end

return NotifyCard
