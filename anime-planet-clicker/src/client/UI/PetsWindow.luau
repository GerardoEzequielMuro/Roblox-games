--!strict
-- Pet inventory: grid of pets (equipped first, then by power), detail panel with
-- equip / lock / fuse / delete and, from the Ember Forge on, Trait rolls.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local Toasts = require(script.Parent.Toasts)
local Kit = require(script.Parent.Kit)
local PetIcon = require(script.Parent.PetIcon)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Purchase = require(script.Parent.Parent.Purchase)

local PetsWindow = {}

type Cell = { frame: TextButton, key: string, stroke: UIStroke, check: TextLabel, lock: TextLabel, power: TextLabel }

local window: Windows.Window
local grid: ScrollingFrame
local detail: GuiObject
local countLabel: TextLabel
local cells: { [string]: Cell } = {}
local selected: string? = nil
local deleteMode = false
local marked: { [string]: boolean } = {}
local deleteButton: TextButton
local spinModel: Model? = nil

local function power(s: { [string]: any }, pet: any): number
	return Formulas.petPower(pet.id, pet.tier, s.maxZone, pet.trait)
end

local function makeCell(uid: string, pet: any): Cell
	local def = Formulas.PetById[pet.id]
	local color = Palette.rarity(def.rarity)
	local b = Theme.new("TextButton", { Name = "Pet_" .. uid, Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), Parent = grid }, {
		Theme.corner(12), Theme.gradient(Theme.lighten(color, 0.25), Theme.darken(color, 0.45)),
	}) :: TextButton
	local stroke = Theme.stroke(3)
	stroke.Parent = b
	PetIcon.new(pet.id, pet.tier).Parent = b
	local powerLabel = Theme.text({ Name = "Power", Text = "", Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 1, -20), MaxTextSize = 16, ZIndex = 2, Parent = b })
	local check = Theme.text({ Name = "Equipped", Text = "✔", TextColor3 = Theme.Green, Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(2, 0), MaxTextSize = 22, ZIndex = 2, Visible = false, Parent = b })
	local lock = Theme.text({ Name = "Lock", Text = "🔒", Stroke = false, Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -22, 0, 2), ZIndex = 2, Visible = false, Parent = b })
	if pet.trait then
		local t = Config.Traits[Config.TraitIndex[pet.trait]]
		Theme.text({ Name = "Trait", Text = "🔥", Stroke = false, TextColor3 = Palette.rarity(t.rarity), Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -20, 1, -40), ZIndex = 2, Parent = b })
	end
	b.Activated:Connect(function()
		Theme.play("click", 0.3)
		if deleteMode then
			local p = Net.state and Net.state.pets[uid]
			if p and p.locked then
				Toasts.show(Lang.t("toast.pet_locked"), "error")
				return
			end
			(marked :: any)[uid] = if marked[uid] then nil else true
			PetsWindow.refresh()
		else
			selected = uid
			PetsWindow.refresh()
		end
	end)
	return { frame = b, key = pet.id .. ":" .. pet.tier .. ":" .. tostring(pet.trait), stroke = stroke, check = check, lock = lock, power = powerLabel }
end

local function renderDetail(s: { [string]: any })
	Kit.clear(detail)
	spinModel = nil
	local uid = selected
	local pet = if uid then s.pets[uid] else nil
	if not uid or not pet then
		Theme.text({ Key = "pets.pick", TextWrapped = true, Size = UDim2.new(1, -20, 0, 80), Position = UDim2.fromOffset(10, 120), MaxTextSize = 22, TextColor3 = Color3.fromRGB(190, 200, 230), Parent = detail })
		return
	end
	local def = Formulas.PetById[pet.id]
	local color = Palette.rarity(def.rarity)
	local touch = Kit.touch
	-- touch: a shorter stage and 56-unit buttons; the panel scrolls
	local stageH = if touch then 84 else 120
	local textY = stageH + 12
	local btnH = if touch then Kit.TOUCH_BTN else 36
	local stage = Theme.new("Frame", { Size = UDim2.new(1, -16, 0, stageH), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1), Parent = detail }, { Theme.corner(12), Theme.stroke(2), Theme.gradient(Theme.lighten(color, 0.3), Theme.darken(color, 0.5)) })
	local vp = PetIcon.new(pet.id, pet.tier, false, 0)
	vp.Parent = stage
	spinModel = vp:FindFirstChildOfClass("Model")
	Theme.text({ Text = Lang.pet(pet.id, pet.tier), Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, textY), MaxTextSize = 22, Parent = detail })
	Theme.text({ Text = Lang.rarity(def.rarity), TextColor3 = color, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, textY + 26), MaxTextSize = 18, Parent = detail })
	Theme.text({ Text = "💪 +" .. Format.abbrev(power(s, pet) * 100) .. "%", TextColor3 = Theme.Power, Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, textY + 48), MaxTextSize = 20, Parent = detail })
	local y = textY + 74
	if pet.trait then
		local t = Config.Traits[Config.TraitIndex[pet.trait]]
		Theme.text({ Text = "🔥 " .. Lang.t("trait." .. pet.trait) .. " x" .. t.mult, TextColor3 = Palette.rarity(t.rarity), Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, y), MaxTextSize = 18, Parent = detail })
		y += 22
	end
	local equipped = table.find(s.equipped, uid) ~= nil
	local function btn(name: string, text: string, c: Color3, onClick: () -> ())
		Theme.button({ Name = name, Text = text, Color = c, Size = UDim2.new(1, -16, 0, btnH), Position = UDim2.fromOffset(8, y), TextSize = 19, Parent = detail, OnClick = onClick })
		y += btnH + 4
	end
	btn("Equip", Lang.t(if equipped then "pets.unequip" else "pets.equip"), if equipped then Theme.Grey else Theme.Green, function()
		Kit.request(if equipped then "Unequip" else "Equip", { uid = uid })
	end)
	if pet.tier < 2 then
		local have = 0
		for _, other in s.pets do
			if other.id == pet.id and other.tier == pet.tier then
				have += 1
			end
		end
		btn("Fuse", Lang.t(if pet.tier == 0 then "pets.fuse_gold" else "pets.fuse_prism", { have = math.min(have, Config.FuseCount), need = Config.FuseCount }), if have >= Config.FuseCount then Theme.Yellow else Theme.Grey, function()
			local ok, res = Kit.request("Fuse", { uid = uid })
			if ok and type(res) == "string" then
				selected = res
			end
		end)
	end
	local traitSystem = Config.SystemById.traits
	if table.find(s.zones, traitSystem.zone) then
		local maxed = pet.trait ~= nil and Config.TraitIndex[pet.trait] >= #Config.Traits
		btn("RollTrait", if maxed then Lang.t("upgrades.max") else (Lang.t("pets.roll_trait") .. " " .. Kit.cost("embers", Config.TraitCost)), if maxed then Theme.Grey else Theme.Orange, function()
			local ok, res = Net.request("RollTrait", { uid = uid })
			if not ok then
				Toasts.show(Lang.msg(res), "error")
			else
				Toasts.show(Lang.t(if res.kept then "pets.trait_new" else "pets.trait_same", { trait = Lang.t("trait." .. res.trait), n = res.refund }), if res.kept then "success" else "info")
			end
		end)
	end
	btn("Lock", Lang.t(if pet.locked then "pets.unlock" else "pets.lock"), Theme.Blue, function()
		Kit.request("Lock", { uid = uid, locked = not pet.locked })
	end)
	if detail:IsA("ScrollingFrame") then
		detail.CanvasSize = UDim2.fromOffset(0, y + 8)
	end
end

function PetsWindow.refresh()
	local s = Net.state
	if not s or not Windows.isOpen("Pets") then
		return
	end
	local n = 0
	local uids = {}
	for uid in s.pets do
		n += 1
		table.insert(uids, uid)
	end
	table.sort(uids, function(a, b)
		local ea, eb = table.find(s.equipped, a) ~= nil, table.find(s.equipped, b) ~= nil
		if ea ~= eb then
			return ea
		end
		local pa, pb = power(s, s.pets[a]), power(s, s.pets[b])
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	for uid, cell in cells do
		local pet = s.pets[uid]
		if not pet or cell.key ~= pet.id .. ":" .. pet.tier .. ":" .. tostring(pet.trait) then
			cell.frame:Destroy()
			cells[uid] = nil
		end
	end
	for i, uid in uids do
		local pet = s.pets[uid]
		local cell = cells[uid]
		if not cell then
			cell = makeCell(uid, pet)
			cells[uid] = cell
		end
		cell.frame.LayoutOrder = i
		local equipped = table.find(s.equipped, uid) ~= nil
		cell.check.Visible = equipped
		cell.lock.Visible = pet.locked == true
		cell.power.Text = "+" .. Format.abbrev(power(s, pet) * 100) .. "%"
		cell.stroke.Color = if marked[uid] then Theme.Red elseif uid == selected then Theme.Yellow elseif equipped then Theme.Green else Theme.Ink
		cell.stroke.Thickness = if marked[uid] or uid == selected or equipped then 4 else 3
	end
	if selected and not s.pets[selected] then
		selected = nil
	end
	countLabel.Text = Lang.t("pets.count", { n = n, max = s.maxInventory, eq = #s.equipped, maxEq = s.maxEquip })
	local markedCount = 0
	for uid in marked do
		if s.pets[uid] then
			markedCount += 1
		else
			marked[uid] = nil
		end
	end
	Theme.setButton(deleteButton, if deleteMode then Lang.t("pets.delete_n", { n = markedCount }) else ("🗑️ " .. Lang.t("pets.delete_mode")), if deleteMode then Theme.Red else Theme.Grey)
	renderDetail(s)
end

-- Showcase / tests: select the strongest pet.
function PetsWindow.selectFirst()
	local s = Net.state
	if s and s.equipped[1] then
		selected = s.equipped[1]
		PetsWindow.refresh()
	end
end

function PetsWindow.init()
	window = Windows.create("Pets", "🐾", "win.pets", Theme.Pink, Vector2.new(780, 490))
	local body = window.body
	local touch = Kit.touch
	-- top bar height: the grid and detail panel start below it
	local barH = if touch then Kit.TOUCH_BTN else 34
	local topH = barH + 8
	countLabel = Theme.text({ Name = "Count", Text = "", Size = UDim2.fromOffset(if touch then 214 else 250, 30), Position = UDim2.fromOffset(2, (barH - 30) // 2), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 19, Parent = body })
	Theme.button({ Name = "EquipBest", Key = "pets.equip_best", Color = Theme.Green, Size = UDim2.fromOffset(if touch then 150 else 130, barH), Position = UDim2.fromOffset(if touch then 222 else 258, 0), TextSize = 18, Parent = body, OnClick = function()
		Kit.request("EquipBest")
	end })
	Theme.button({ Name = "FuseAll", Key = "pets.fuse_all", Color = Theme.Yellow, Size = UDim2.fromOffset(if touch then 126 else 110, barH), Position = UDim2.fromOffset(if touch then 378 else 394, 0), TextSize = 18, Parent = body, OnClick = function()
		local ok, res = Net.request("FuseAll")
		Toasts.show(if ok then Lang.t("pets.fused_n", { n = res }) else Lang.msg(res), if ok then "success" else "error")
	end })
	deleteButton = Theme.button({ Name = "DeleteMode", Text = "", Color = Theme.Grey, Size = UDim2.fromOffset(if touch then 162 else 150, barH), Position = UDim2.fromOffset(if touch then 510 else 510, 0), TextSize = 17, Parent = body, OnClick = function()
		if deleteMode then
			local uids = {}
			for uid in marked do
				table.insert(uids, uid)
			end
			if #uids > 0 then
				local ok, res = Net.request("Delete", { uids = uids })
				Toasts.show(if ok then Lang.t("toast.deleted", { n = res }) else Lang.msg(res), if ok then "info" else "error")
			end
			marked = {}
			deleteMode = false
		else
			deleteMode = true
		end
		PetsWindow.refresh()
	end })
	-- "+" next to the equip cap: sells the hole (Pet Slots pass)
	Theme.button({ Name = "MoreSlots", Text = "+", Color = Theme.Robux, Size = UDim2.fromOffset(barH, barH), Position = UDim2.fromOffset(if touch then 678 else 666, 0), TextSize = 26, Parent = body, OnClick = function()
		Purchase.pass("PetSlots")
	end })
	grid = Kit.grid(body, UDim2.new(1, -226, 1, -topH), UDim2.fromOffset(0, topH), Vector2.new(82, 82), 6)
	if touch then
		detail = Theme.new("ScrollingFrame", {
			Name = "Detail",
			Size = UDim2.new(0, 218, 1, -topH),
			Position = UDim2.new(1, -218, 0, topH),
			BackgroundColor3 = Theme.PaperDark,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = body,
		}, { Theme.corner(12), Theme.stroke(2) })
	else
		detail = Theme.panel({ Name = "Detail", Size = UDim2.new(0, 218, 1, -topH), Position = UDim2.new(1, -218, 0, topH), BackgroundColor3 = Theme.PaperDark, Corner = 12, StrokeThickness = 2, Parent = body })
	end
	window.onOpen = function()
		PetsWindow.refresh()
	end
	window.onClose = function()
		deleteMode = false
		marked = {}
	end
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			PetsWindow.refresh()
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local m = spinModel
		if m and m.Parent and Windows.isOpen("Pets") then
			m:PivotTo(m:GetPivot() * CFrame.Angles(0, dt * 1.2, 0))
		end
	end)
end

return PetsWindow
