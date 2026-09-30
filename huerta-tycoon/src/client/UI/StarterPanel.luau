--!nonstrict
-- One-time Starter Pack offer (first 24 h, product id ~= 0 only). Opens once after the tutorial finishes or 3 min
-- into the session; afterwards a pulsing button in the action column keeps it reachable while it's available.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local StarterPanel = {}
StarterPanel.button = nil :: TextButton?

local function product(): any
	for _, p in Config.DevProducts do
		if p.key == "StarterPack" then
			return p
		end
	end
	return nil
end

function StarterPanel.available(): boolean
	local d = State.data
	local prod = product()
	return prod ~= nil and prod.id ~= 0 and d ~= nil and type(d.starter) == "table" and d.starter.available == true
		and State.now() < (d.starter.endsAt or 0)
end

function StarterPanel.buy()
	local prod = product()
	if not prod or prod.id == 0 then
		return
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(player, prod.id)
	end)
end

function StarterPanel.build(root: Instance)
	local g = Config.StarterPackGrant
	local p = C.panel(root, {
		Name = "StarterPanel",
		Title = L("panel.starter"),
		Icon = "🎁",
		Color = Theme.C.Orange,
		Size = UDim2.fromOffset(540, 450),
	})
	local body = p.content
	local tag = C.label(p.frame, "-70%", UDim2.fromOffset(110, 56), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 20, 0, 16),
		Rotation = -12,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.C.Red,
		TextSize = 32,
		ZIndex = 6,
	})
	C.corner(tag, 14)

	C.list(body, true, 8, Enum.HorizontalAlignment.Center)
	local seedParts = {}
	for id, n in g.seeds do
		table.insert(seedParts, { key = "reward.seeds", args = { n = n, seed = { key = "seed." .. id } } })
	end
	local lines = {
		L("daily.reward", { list = { list = seedParts, sep = " + " } }, "🌱 "),
		L("reward.boostCash", { mult = g.cashBoostMult, min = math.floor(g.cashBoostSeconds / 60) }, "💰 "),
	}
	for i, line in lines do
		C.label(body, line, UDim2.new(1, -20, 0, 34), {
			TextSize = 22,
			TextColor3 = Theme.C.Ink,
			Outline = false,
			LayoutOrder = i,
		})
	end
	local was = C.label(body, "", UDim2.new(1, 0, 0, 30), {
		TextSize = 24,
		TextColor3 = Theme.C.InkSoft,
		RichText = true,
		Outline = false,
		LayoutOrder = 10,
	})
	was.Text = string.format("<s>%d R$</s>", Config.StarterPackListPrice)
	was.AutoLocalize = false
	local timer = C.label(body, "", UDim2.new(1, 0, 0, 28), {
		TextSize = 20,
		TextColor3 = Theme.C.Red,
		Outline = false,
		LayoutOrder = 11,
	})
	local prod = product()
	local buyBtn = C.button({
		Name = "Buy",
		Parent = body,
		Text = "R$ " .. tostring(prod and prod.priceHint or 15),
		TextSize = 32,
		Color = Theme.C.Green,
		Size = UDim2.fromOffset(300, 70),
		LayoutOrder = 12,
		OnClick = StarterPanel.buy,
	})
	if prod and prod.id ~= 0 then
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, prod.id, Enum.InfoType.Product)
			if ok and type(info) == "table" and info.PriceInRobux then
				C.setText(buyBtn, "R$ " .. tostring(info.PriceInRobux))
			end
		end)
	end

	-- pulsing shortcut at the top of the action column
	local actions = root:FindFirstChild("Actions")
	if actions then
		local b = C.button({
			Name = "StarterPack",
			Parent = actions,
			Text = L("starter.hud"),
			TextSize = 20,
			Color = Theme.C.Orange,
			Size = UDim2.fromOffset(176, 56),
			LayoutOrder = 0,
		})
		b.Visible = false
		StarterPanel.button = b
		local pulse = C.new("UIScale", { Parent = b })
		RunService.RenderStepped:Connect(function()
			if b.Visible then
				pulse.Scale = 1 + math.abs(math.sin(os.clock() * 3)) * 0.05
			end
		end)
	end

	local function tick()
		local d = State.data
		if d and type(d.starter) == "table" then
			timer.Text = I18n.t("starter.endsIn", { time = Format.time((d.starter.endsAt or 0) - State.now()) })
		end
	end

	return { frame = p.frame, closeButton = p.close, onOpen = tick, tick = tick }
end

-- Wires visibility + the one-time auto-open (needs Panels to avoid a require cycle).
function StarterPanel.wire(panels: any)
	local b = StarterPanel.button
	if b then
		b.Activated:Connect(function()
			panels.open("Starter")
		end)
	end
	local shown = false
	local wasTutorialDone: boolean? = nil
	local started = os.clock()
	local function check()
		local avail = StarterPanel.available()
		if b then
			b.Visible = avail
		end
		local d = State.data
		if not avail or shown or not d then
			return
		end
		local tutorialJustDone = wasTutorialDone == false and d.tutorialDone == true
		wasTutorialDone = d.tutorialDone == true
		if (tutorialJustDone or os.clock() - started >= 180) and panels.current == nil then
			shown = true
			panels.open("Starter")
		end
	end
	State.onChanged(function(kind)
		if kind == "state" then
			check()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			check()
		end
	end)
end

return StarterPanel
