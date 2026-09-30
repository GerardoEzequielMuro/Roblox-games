--!strict
-- Egg panel: opens from the egg's ProximityPrompt, shows the odds (after luck) and the
-- Hatch x1 / x3 / Auto buttons (or Robux buttons for the exclusive Magic Egg).
-- Keys while open: E = x1 (re-triggers the prompt), R = x3, T = auto.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local PetIcon = require(script.Parent.PetIcon)
local Toasts = require(script.Parent.Toasts)
local HatchCinematic = require(script.Parent.HatchCinematic)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Hud = require(script.Parent.Hud)
local LiveEventClient = require(script.Parent.Parent.LiveEventClient)
local Purchase = require(script.Parent.Parent.Purchase)

local EggPanel = {}

local currentEgg: string? = nil
local eggPos: Vector3? = nil
local busy = false

-- assigned in init
EggPanel.open = function(_eggId: string, _position: Vector3) end
EggPanel.close = function() end

function EggPanel.init()
	-- PC: bottom center. Touch: top center (the bottom corners belong to the thumbstick and
	-- jump button); the HUD side columns hide while it's open.
	local panel = Theme.panel({
		Name = "EggPanel",
		Size = UDim2.fromOffset(680, 280),
		Position = if Root.isTouch then UDim2.new(0.5, 0, 0, 8) else UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = if Root.isTouch then Vector2.new(0.5, 0) else Vector2.new(0.5, 1),
		Visible = false,
		Corner = 22,
		StrokeThickness = 4,
		Parent = Root.gui,
	})
	Root.mount(panel)
	Theme.shadow(panel, 22)
	local title = Theme.text({ Text = "", Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 6), MaxTextSize = 34, TextColor3 = Theme.Ink, Stroke = false, Parent = panel })
	local luckLabel = Theme.text({ Text = "", Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 44), MaxTextSize = 20, TextColor3 = Theme.Green, Stroke = false, Parent = panel })
	local odds = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 128), Position = UDim2.fromOffset(12, 68), Parent = panel }, {
		Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center),
	})
	local buttonRow = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 66), Position = UDim2.new(0, 12, 1, -74), Parent = panel }, {
		Theme.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})

	local function hatch(count: number)
		local egg = currentEgg
		if not egg or busy then
			return
		end
		local def = Formulas.EggById[egg]
		if def.exclusive then
			Purchase.product(if count == 3 then "MagicEgg3" else "MagicEgg1")
			return
		end
		if count == 3 and not Net.owns("TripleHatch") then
			Purchase.pass("TripleHatch")
			return
		end
		if HatchCinematic.isPlaying() then
			return
		end
		busy = true
		local ok, res = Net.request("Hatch", { egg = egg, count = count })
		busy = false
		if ok then
			HatchCinematic.play(egg, res, false)
		elseif res ~= "cooldown" then
			Toasts.show(Lang.msg(res), "error")
		end
	end

	local b1 = Theme.button({ Text = "", Color = Theme.Green, Size = UDim2.fromOffset(210, 58), LayoutOrder = 1, TextSize = 24, Parent = buttonRow, OnClick = function()
		hatch(1)
	end })
	local b3 = Theme.button({ Text = "", Color = Theme.Orange, Size = UDim2.fromOffset(210, 58), LayoutOrder = 2, TextSize = 24, Parent = buttonRow, OnClick = function()
		hatch(3)
	end })
	local function toggleAuto()
		local egg = currentEgg
		if not egg or Formulas.EggById[egg].exclusive then
			return
		end
		local on = Net.get("autoHatch") == egg
		local ok, err = Net.request("SetAutoHatch", if on then {} else { egg = egg })
		if not ok and err then
			Toasts.show(Lang.msg(err), "error")
		end
	end
	local bAuto = Theme.button({ Text = "", Color = Theme.Purple, Size = UDim2.fromOffset(200, 58), LayoutOrder = 3, TextSize = 24, Parent = buttonRow, OnClick = toggleAuto })
	-- keyboard hints (PC only)
	if not Root.isTouch then
		for key, b in { E = b1, R = b3, T = bAuto } :: { [string]: TextButton } do
			local chip = Theme.new("Frame", { Name = "Key", Size = UDim2.fromOffset(28, 26), Position = UDim2.fromOffset(-8, -10), BackgroundColor3 = Theme.Ink, ZIndex = b.ZIndex + 2, Parent = b }, { Theme.corner(8), Theme.new("UIStroke", { Thickness = 2, Color = Theme.White }) })
			local t = Theme.text({ Text = key, Stroke = false, Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2), MaxTextSize = 18, Parent = chip })
			t.ZIndex = b.ZIndex + 3
			t.AutoLocalize = false
		end
	end
	Theme.button({ Text = "X", Color = Theme.Red, Size = UDim2.fromOffset(54, 54), Position = UDim2.new(1, 14, 0, -14), AnchorPoint = Vector2.new(1, 0), Corner = 27, Parent = panel, OnClick = function()
		EggPanel.close()
	end })

	local function refreshButtons()
		local egg = currentEgg
		if not egg then
			return
		end
		local def = Formulas.EggById[egg]
		local s = Net.state
		local golden = Lang.t("egg.golden", { pct = Format.chance((if s then s.goldenChance or 0 else 0) * 100):gsub("%%", "") })
		if def.exclusive then
			local p1, p3 = Config.ProductByKey.MagicEgg1, Config.ProductByKey.MagicEgg3
			local blocked = Purchase.productBlocked("MagicEgg1")
			local off = Lang.t(if blocked then "egg.restricted" else "egg.coming_soon")
			Theme.setButton(b1, if Purchase.productAvailable("MagicEgg1") then (Lang.t("egg.buy1") .. "  R$" .. p1.price) else off, if blocked then Theme.Grey else Theme.Green)
			Theme.setButton(b3, if Purchase.productAvailable("MagicEgg3") then (Lang.t("egg.buy3") .. "  R$" .. p3.price) else off, if blocked then Theme.Grey else Theme.Orange)
			b3.Visible = not blocked
			bAuto.Visible = false
			luckLabel.Text = Lang.t("egg.exclusive_note") .. "  ·  ⭐ " .. golden
			return
		end
		b3.Visible = true
		bAuto.Visible = true
		local taps = if s then s.taps else 0
		Theme.setButton(b1, Lang.t("egg.hatch1") .. "  " .. Format.abbrev(def.price), if taps >= def.price then Theme.Green else Theme.Grey)
		if Net.owns("TripleHatch") then
			Theme.setButton(b3, Lang.t("egg.hatch3") .. "  " .. Format.abbrev(def.price * 3), if taps >= def.price * 3 then Theme.Orange else Theme.Grey)
		else
			Theme.setButton(b3, "⭐ " .. Lang.t("egg.x3_locked"), Theme.Blue)
		end
		local autoOn = s and s.autoHatch == egg
		Theme.setButton(bAuto, Lang.t(if autoOn then "egg.auto_on" else "egg.auto_off"), if autoOn then Theme.Green else Theme.Purple)
		local luck = if s then s.luck else 1
		local extra = if s and (s.luckBoostLeft or 0) > 0 then ("  🍀 " .. Lang.t("egg.super_luck")) else ""
		for _, ev in LiveEventClient.active() do
			extra ..= "  ✨ " .. Lang.t("event." .. ev.id)
		end
		luckLabel.Text = Lang.t("egg.luck", { luck = string.format("%.2f", luck) }) .. "  ·  ⭐ " .. golden .. extra
	end

	local function buildOdds()
		for _, c in odds:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local egg = currentEgg
		if not egg then
			return
		end
		local s = Net.state
		local luck = if s and not Formulas.EggById[egg].exclusive then s.luck else 1
		local discovered = if s then s.discovered else {}
		-- numeric percentages that add up to exactly 100, shown before anything is spent
		for i, o in Formulas.displayOdds(egg, luck) do
			local pet = Formulas.PetById[o.pet]
			local secret = pet.rarity == "Secret"
			local rc = if secret then Color3.fromRGB(90, 50, 130) else Palette.rarity(pet.rarity)
			local cell = Theme.new("Frame", { Size = UDim2.fromOffset(100, 128), LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), Parent = odds }, {
				Theme.corner(14),
				Theme.stroke(3),
				Theme.gradient(Theme.lighten(rc, 0.55), Theme.darken(rc, 0.05)),
			})
			Theme.gloss(cell, 14, 0.7)
			local icon = PetIcon.new(o.pet, 0, secret and not discovered[o.pet])
			icon.Size = UDim2.new(1, -6, 0, 78)
			icon.Position = UDim2.fromOffset(3, 1)
			icon.Parent = cell
			local plate = Theme.new("Frame", { Size = UDim2.new(1, -8, 0, 46), Position = UDim2.new(0, 4, 1, -50), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = cell }, { Theme.corner(10) })
			local pct = Theme.text({ Name = "Chance", Text = o.text, Size = UDim2.new(1, -6, 0, 24), Position = UDim2.fromOffset(3, 1), MaxTextSize = 22, TextColor3 = Theme.Yellow, Parent = plate })
			pct.AutoLocalize = false
			pct:SetAttribute("Units", o.units)
			Theme.text({ Text = if secret and not discovered[o.pet] then Lang.t("egg.unknown") else Lang.pet(pet.id), Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 24), MaxTextSize = 16, Parent = plate })
		end
		local def = Formulas.EggById[egg]
		title.Text = Lang.egg(def.id)
	end

	EggPanel.open = function(eggId: string, position: Vector3)
		if currentEgg == eggId and panel.Visible then
			hatch(1) -- pressing E again hatches
			return
		end
		currentEgg = eggId
		eggPos = position
		buildOdds()
		refreshButtons()
		panel.Visible = true
		Hud.setDockVisible(false)
		if Root.isTouch then
			Hud.setSidesVisible(false)
		end
		Theme.pop(panel, 0.8)
	end

	EggPanel.close = function()
		currentEgg = nil
		eggPos = nil
		panel.Visible = false
		Hud.setDockVisible(true)
		if Root.isTouch then
			Hud.setSidesVisible(true)
		end
	end

	-- Paid random items policy: players PolicyService restricts (and everyone until the
	-- answer arrives) don't get the Robux-only egg at all: its prompt and sign are switched
	-- off on this client, and a stray trigger only explains why.
	local function isExclusive(eggId: any): boolean
		local def = if type(eggId) == "string" then Formulas.EggById[eggId] else nil
		return def ~= nil and def.exclusive == true
	end
	local function syncExclusive(inst: Instance)
		if inst:IsA("ProximityPrompt") and isExclusive(inst:GetAttribute("EggId")) then
			inst.Enabled = not Purchase.restricted()
		elseif inst:IsA("BillboardGui") then
			local model = inst:FindFirstAncestorOfClass("Model")
			if model and isExclusive(model:GetAttribute("EggId")) then
				inst.Enabled = not Purchase.restricted()
			end
		end
	end
	local eggsFolder: Instance? = nil
	local function syncAllExclusive()
		if eggsFolder then
			for _, d in eggsFolder:GetDescendants() do
				syncExclusive(d)
			end
		end
	end
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 60)
		local eggs = world and world:WaitForChild("Eggs", 60)
		if eggs then
			eggsFolder = eggs
			eggs.DescendantAdded:Connect(syncExclusive)
			syncAllExclusive()
		end
	end)
	local lastRestricted: boolean? = nil
	Net.Changed:Connect(function(kind)
		if kind == "full" and Purchase.restricted() ~= lastRestricted then
			lastRestricted = Purchase.restricted()
			syncAllExclusive()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= Players.LocalPlayer then
			return
		end
		local eggId = prompt:GetAttribute("EggId")
		if isExclusive(eggId) and Purchase.restricted() then
			Toasts.show(Lang.t("egg.restricted"), "info")
			return
		end
		if type(eggId) == "string" then
			local parent = prompt.Parent
			local pos = if parent and parent:IsA("BasePart") then parent.Position else Vector3.zero
			EggPanel.open(eggId, pos)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not currentEgg then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			hatch(3)
		elseif input.KeyCode == Enum.KeyCode.T then
			toggleAuto()
		end
	end)

	Lang.Changed:Connect(function()
		if currentEgg then
			buildOdds()
			refreshButtons()
		end
	end)

	Net.Changed:Connect(function(kind)
		if not currentEgg then
			return
		end
		refreshButtons()
		if kind == "full" then
			-- luck may have changed
			local luckNow = Net.get("luck")
			if luckNow ~= panel:GetAttribute("Luck") then
				panel:SetAttribute("Luck", luckNow)
				buildOdds()
			end
		end
	end)

	-- close when walking away
	task.spawn(function()
		while true do
			task.wait(0.3)
			if currentEgg and eggPos then
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root or (root.Position - eggPos).Magnitude > Config.EggRange + 2 then
					EggPanel.close()
				end
			end
		end
	end)

end

return EggPanel
