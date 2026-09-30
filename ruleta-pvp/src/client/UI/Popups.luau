--!strict
-- Small things that pop up: a duel challenge to answer, the server party, the first-match
-- coach lines, and the notification opt-in.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Layout = require(ReplicatedStorage.Shared.Layout)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Toasts = require(script.Parent.Toasts)
local MatchHud = require(script.Parent.MatchHud)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Audio = require(script.Parent.Parent.Audio)
local Fx = require(script.Parent.Parent.Arena.Fx)
local Director = require(script.Parent.Parent.Arena.Director)

local Popups = {}
Popups.challenges = 0
Popups.coachShown = {} :: { [string]: boolean }

-- duel challenge
local challenge = Theme.panel({ Name = "Challenge", Size = UDim2.fromOffset(420, 120), Position = UDim2.new(0.5, 0, 0, 150), AnchorPoint = Vector2.new(0.5, 0), Corner = 20, StrokeColor = Theme.Orange, StrokeThickness = 4, Visible = false, ZIndex = 35, Parent = Root.gui })
Root.mount(challenge)
local challengeScale = Theme.new("UIScale", { Parent = challenge }) :: UIScale
local challengeText = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, -24, 0, 50), Position = UDim2.fromOffset(12, 8), MaxTextSize = 22, TextWrapped = true, ZIndex = 36, Parent = challenge })
local from = 0
local function answer(accept: boolean)
	challenge.Visible = false
	local who = from
	task.spawn(function()
		local ok, err = Net.request("AnswerChallenge", { from = who, accept = accept })
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end)
end
Theme.button({ Name = "Accept", Key = "duel.accept", Prefix = "⚔️ ", Color = Theme.Green, Size = UDim2.fromOffset(190, 44), Position = UDim2.new(0, 14, 1, -54), TextSize = 20, ZIndex = 36, Parent = challenge, OnClick = function()
	answer(true)
end })
Theme.button({ Name = "Decline", Key = "duel.decline", Color = Theme.Red, Size = UDim2.fromOffset(190, 44), Position = UDim2.new(1, -14, 1, -54), AnchorPoint = Vector2.new(1, 0), TextSize = 20, ZIndex = 36, Parent = challenge, OnClick = function()
	answer(false)
end })
Popups.answer = answer

-- The first match: one short line per step, each shown once.
local COACH = { intro = "tut.intro", decide = "tut.decide", spin = "tut.spin", eliminated = "tut.eliminated", ended = "tut.ended" }
local function coach(step: string, arg: any)
	local key = COACH[step]
	if not key or Popups.coachShown[step] then
		return
	end
	Popups.coachShown[step] = true
	if step == "ended" and arg == true then
		key = "tut.won"
	end
	MatchHud.coach(Lang.t(key))
	local shown = step
	task.delay(if step == "decide" then 9 else 6, function()
		if Popups.coachShown[shown] then
			MatchHud.coach(nil)
		end
	end)
end

function Popups.init()
	Director.onTutorial = coach
	Net.event("Challenge").OnClientEvent:Connect(function(d)
		Popups.challenges += 1
		from = d.from
		challengeText.Text = "⚔️ " .. Lang.t("duel.challenged", { name = d.name })
		challenge.Visible = true
		challengeScale.Scale = 0.5
		TweenService:Create(challengeScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		Audio.play("card", 0.6)
		local mine = Popups.challenges
		task.delay(d.seconds or 20, function()
			if Popups.challenges == mine then
				challenge.Visible = false
			end
		end)
	end)
	Net.event("Party").OnClientEvent:Connect(function(name, coins)
		Toasts.show("🎉 " .. Lang.t("toast.party", { name = name, n = coins }), "success", 5)
		for i = 0, 5 do
			task.delay(i * 0.3, function()
				local a = i / 6 * math.pi * 2
				Fx.confetti(Vector3.new(math.sin(a) * 20, 18, math.cos(a) * 20) + Layout.CorePos * 0, 22, 34)
			end)
		end
	end)
	Net.event("AskNotifications").OnClientEvent:Connect(function()
		task.spawn(function()
			pcall(function()
				local service = game:GetService("ExperienceNotificationService") :: any
				if service:CanPromptOptInAsync() then
					service:PromptOptIn()
				end
			end)
		end)
	end)
end

return Popups
