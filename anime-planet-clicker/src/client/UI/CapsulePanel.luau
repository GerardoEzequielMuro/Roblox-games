--!strict
-- The capsule machine panel: every possible pet with its exact chance (the numbers the
-- server rolls with, after luck; they always add up to 100%), the price, and the three
-- buttons Open x1 [E] / x3 [R] / Auto [T], plus the Auto Delete switches.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Kit = require(script.Parent.Kit)
local PetIcon = require(script.Parent.PetIcon)
local CapsuleCinematic = require(script.Parent.CapsuleCinematic)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)

local CapsulePanel = {}

local window: Windows.Window
local content: Frame
local current: string? = nil
local lastOpen = 0
CapsulePanel.current = nil :: string?

-- The odds exactly as shown (tests compare them with the server's table).
function CapsulePanel.odds(capsuleId: string): { Formulas.Odd }
	local s = Net.state
	return Formulas.odds(capsuleId, if s then s.luck else 1)
end

local function open(count: number)
	local id = current
	if not id or CapsuleCinematic.isPlaying() or os.clock() - lastOpen < 0.4 then
		return
	end
	lastOpen = os.clock()
	local cap = Formulas.CapsuleById[id]
	if cap.exclusive then
		Purchase.product(if count == 3 then "QuantumCapsule3" else "QuantumCapsule1")
		return
	end
	if count == 3 and not Net.owns("TripleOpen") then
		Purchase.pass("TripleOpen")
		return
	end
	local ok, res = Net.request("Open", { capsule = id, count = count })
	if ok then
		CapsuleCinematic.play(id, res, false)
	elseif res ~= "cooldown" then
		Toasts.show(Lang.msg(res), "error")
	end
end

local function toggleAuto()
	local s = Net.state
	local id = current
	if not s or not id or Formulas.CapsuleById[id].exclusive then
		return
	end
	if s.autoOpen == id then
		Kit.request("SetAutoOpen", {})
	else
		Kit.request("SetAutoOpen", { capsule = id }, Lang.t("capsule.auto_started"))
	end
end

local function render()
	local s = Net.state
	local id = current
	if not s or not id or not Windows.isOpen("Capsule") then
		return
	end
	Kit.clear(content)
	local cap = Formulas.CapsuleById[id]
	local odds = CapsulePanel.odds(id)
	-- header line: name + price
	Theme.text({ Text = Lang.capsule(id), Size = UDim2.new(0.6, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 28, Parent = content })
	local price = if cap.exclusive then ("R$ " .. Lang.t("capsule.robux_only")) else Kit.cost("stardust", cap.price)
	Theme.text({ Text = price, Italic = true, TextColor3 = if cap.exclusive then Color3.fromRGB(220, 150, 255) else Theme.Stardust, Size = UDim2.new(0.4, 0, 0, 30), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 26, Parent = content })
	-- odds grid
	local grid = Theme.new("Frame", { Name = "Odds", BackgroundColor3 = Theme.PaperDark, Size = UDim2.new(1, 0, 0, 176), Position = UDim2.fromOffset(0, 36), Parent = content }, {
		Theme.corner(12), Theme.padding(8), Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local total = 0
	local cellW = math.min(108, math.floor((560 - 16 - 8 * (#odds - 1)) / #odds))
	for i, o in odds do
		total += o.chance
		local color = Palette.rarity(o.rarity)
		local known = s.discovered[o.id] == true
		local cell = Theme.new("Frame", { Name = "Odd_" .. o.id, Size = UDim2.fromOffset(cellW, 156), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = i, Parent = grid }, {
			Theme.corner(10), Theme.stroke(3), Theme.gradient(Theme.lighten(color, 0.25), Theme.darken(color, 0.5)),
		})
		local vp = PetIcon.new(o.id, 0, o.rarity == "Secret" and not known)
		vp.Size = UDim2.new(1, -6, 0, 78)
		vp.Position = UDim2.fromOffset(3, 4)
		vp.Parent = cell
		Theme.text({ Text = if o.rarity == "Secret" and not known then "???" else Lang.pet(o.id), Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 82), MaxTextSize = 15, TextWrapped = true, Parent = cell })
		Theme.text({ Text = Lang.rarity(o.rarity), TextColor3 = Theme.lighten(color, 0.55), Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 108), MaxTextSize = 14, Parent = cell })
		local chance = Theme.text({ Name = "Chance", Text = Format.percent(o.chance), TextColor3 = Theme.Yellow, Size = UDim2.new(1, -6, 0, 24), Position = UDim2.fromOffset(3, 126), MaxTextSize = 20, Parent = cell })
		chance.AutoLocalize = false
	end
	local golden = Formulas.goldenChance(Net.owns("GoldenCapsules"))
	Theme.text({ Name = "Total", Text = Lang.t("capsule.total", { pct = string.format("%.0f", total), luck = string.format("%.2f", s.luck), golden = Format.percent(golden * 100) }), Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 216), MaxTextSize = 16, TextColor3 = Color3.fromRGB(200, 210, 235), Parent = content })
	-- buttons
	local auto = s.autoOpen == id
	local y = 242
	local kb = UserInputService.KeyboardEnabled and not Root.isTouch
	Theme.button({ Name = "Open1", Text = Lang.t("capsule.open1") .. (if kb then "  [E]" else ""), Color = Theme.Green, Size = UDim2.fromOffset(196, 54), Position = UDim2.fromOffset(0, y), TextSize = 24, Parent = content, OnClick = function()
		open(1)
	end })
	if not (cap.exclusive and not Purchase.allowed(Config.ProductByKey.QuantumCapsule3)) then
		Theme.button({ Name = "Open3", Text = (if Net.owns("TripleOpen") or cap.exclusive then "" else "🔒 ") .. Lang.t("capsule.open3") .. (if kb then "  [R]" else ""), Color = Theme.Purple, Size = UDim2.fromOffset(176, 54), Position = UDim2.fromOffset(204, y), TextSize = 22, Parent = content, OnClick = function()
			open(3)
		end })
	end
	if not cap.exclusive then
		Theme.button({ Name = "Auto", Text = Lang.t(if auto then "capsule.auto_on" else "capsule.auto_off") .. (if kb then "  [T]" else ""), Color = if auto then Theme.Orange else Theme.Blue, Size = UDim2.fromOffset(172, 54), Position = UDim2.fromOffset(388, y), TextSize = 21, Parent = content, OnClick = toggleAuto })
		-- Auto Delete switches
		Theme.text({ Key = "capsule.auto_delete", Size = UDim2.fromOffset(150, 28), Position = UDim2.fromOffset(0, y + 62), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 17, TextColor3 = Color3.fromRGB(200, 210, 235), Parent = content })
		for i, rarity in Config.AutoDeleteRarities do
			local on = s.autoDelete[rarity] == true
			Theme.button({ Name = "Delete_" .. rarity, Text = (if on then "🗑️ " else "") .. Lang.rarity(rarity), Color = if on then Theme.Red else Theme.darken(Palette.rarity(rarity), 0.45), Size = UDim2.fromOffset(128, 30), Position = UDim2.fromOffset(156 + (i - 1) * 134, y + 61), TextSize = 16, Corner = 8, Parent = content, OnClick = function()
				Kit.request("SetAutoDelete", { rarity = rarity, on = not on })
			end })
		end
	elseif Purchase.restricted() then
		Theme.text({ Key = "msg.restricted", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, y + 62), MaxTextSize = 17, TextColor3 = Theme.Red, Parent = content })
	end
end

function CapsulePanel.open(capsuleId: string)
	if not Formulas.CapsuleById[capsuleId] then
		return
	end
	current = capsuleId
	CapsulePanel.current = capsuleId
	lastOpen = os.clock() -- the E that opened the prompt must not also open a capsule
	Windows.open("Capsule")
	render()
end

function CapsulePanel.close()
	if Windows.isOpen("Capsule") then
		Windows.close()
	end
end

function CapsulePanel.init()
	window = Windows.create("Capsule", "🧬", "win.capsule", Theme.Purple, Vector2.new(592, 440))
	content = Theme.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = window.body })
	window.onOpen = render
	window.onClose = function()
		CapsulePanel.current = nil
	end
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			render()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Windows.isOpen("Capsule") then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			open(1)
		elseif input.KeyCode == Enum.KeyCode.R then
			open(3)
		elseif input.KeyCode == Enum.KeyCode.T then
			toggleAuto()
		end
	end)
	-- walking away from the machine closes the panel
	task.spawn(function()
		local player = Players.LocalPlayer
		while true do
			task.wait(0.5)
			local id = current
			if id and Windows.isOpen("Capsule") then
				local char = player.Character
				local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
				local pos = Layout.capsulePosition(id)
				if root and pos then
					local dx, dz = root.Position.X - pos[1], root.Position.Z - pos[3]
					if dx * dx + dz * dz > (Config.OpenDistance + 8) ^ 2 then
						Windows.close()
					end
				end
			end
		end
	end)
end

return CapsulePanel
