--!strict
-- Pets inventory: grid with rarity frames + power, detail panel (equip, lock, craft,
-- delete), Equip Best and multi-delete mode.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local PetIcon = require(script.Parent.PetIcon)
local Toasts = require(script.Parent.Toasts)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)

local PetsWindow = {}
PetsWindow.selectFirst = function() end
-- icons alive, cells total (virtualization check in the playtest)
PetsWindow.iconCount = function(): (number, number)
	return 0, 0
end

type Cell = { button: TextButton, trait: Frame, traitText: TextLabel, key: string, power: TextLabel, equipped: Frame, lock: TextLabel, check: Frame, stroke: UIStroke, ring: Frame, petId: string, tier: number, icon: ViewportFrame? }

local SECRET = Color3.fromRGB(190, 90, 255)

function PetsWindow.init()
	local w = Windows.create("Pets", "🐾", "win.pets", Theme.Orange, Vector2.new(820, 520))
	local body = w.body

	local top = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 54), Parent = body })
	-- "+" next to the caps: more equip slots are an upgrade away
	Theme.button({
		Name = "MoreSlots",
		Text = "+",
		Color = Theme.Green,
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -394, 0, 5),
		Corner = 22,
		TextSize = 30,
		Parent = top,
		OnClick = function()
			Windows.open("Upgrades")
		end,
	})
	local countLabel = Theme.text({ Text = "", Size = UDim2.new(1, -404, 1, -8), Position = UDim2.fromOffset(0, 4), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 26, Parent = top })
	local deleteMode = false
	local selected: { [string]: boolean } = {}
	local selectedUid: string? = nil

	local refresh: () -> ()

	Theme.button({
		Key = "pets.equip_best",
		Color = Theme.Green,
		Size = UDim2.fromOffset(160, 54),
		Position = UDim2.new(1, -340, 0, 0),
		TextSize = 26,
		Parent = top,
		OnClick = function()
			Net.request("EquipBest")
		end,
	})
	local deleteButton: TextButton
	deleteButton = Theme.button({
		Key = "pets.delete_mode",
		Color = Theme.Red,
		Size = UDim2.fromOffset(170, 54),
		TextSize = 26,
		Position = UDim2.new(1, -170, 0, 0),
		Parent = top,
		OnClick = function()
			if deleteMode then
				local uids = {}
				for uid in selected do
					table.insert(uids, uid)
				end
				if #uids > 0 then
					local ok, res = Net.request("Delete", { uids = uids })
					Toasts.show(if ok then Lang.t("toast.deleted", { n = res }) else Lang.msg(res), if ok then "success" else "error")
				end
				deleteMode = false
				table.clear(selected)
			else
				deleteMode = true
				selectedUid = nil
			end
			refresh()
		end,
	})

	-- Grid
	local grid = Theme.new("ScrollingFrame", {
		Size = UDim2.new(1, -280, 1, -64),
		Position = UDim2.fromOffset(0, 64),
		BackgroundColor3 = Theme.PaperDark,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Ink,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = body,
	}, {
		Theme.corner(14),
		Theme.padding(10),
		Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(100, 112), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame

	-- Detail panel
	local detail = Theme.panel({ Size = UDim2.new(0, 266, 1, -64), Position = UDim2.new(1, -266, 0, 64), BackgroundColor3 = Color3.fromRGB(255, 255, 255), Parent = body })
	-- stage: rarity-coloured backdrop with turning rays behind a slowly spinning pet
	local stage = Theme.new("Frame", { Name = "Stage", Size = UDim2.new(1, -16, 0, 112), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, Parent = detail }, { Theme.corner(12), Theme.stroke(3) })
	local stageGradient = Theme.gradient(Theme.lighten(Theme.Grey, 0.55), Theme.lighten(Theme.Grey, 0.2))
	stageGradient.Parent = stage
	local stageRays = Theme.new("Frame", { Size = UDim2.fromOffset(340, 340), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = stage })
	for k = 0, 5 do
		Theme.new("Frame", { Size = UDim2.new(0, 30, 1, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = k * 30, BackgroundColor3 = Theme.White, BackgroundTransparency = 0.72, BorderSizePixel = 0, Parent = stageRays })
	end
	TweenService:Create(stageRays, TweenInfo.new(16, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
	local detailIcon = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 108), Position = UDim2.new(0.5, 0, 0, 3), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 2, Parent = stage })
	local emptyIcon = Theme.text({ Text = "🐾", Stroke = false, Size = UDim2.fromOffset(84, 84), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), TextTransparency = 0.45, ZIndex = 2, Parent = stage })
	local detailName = Theme.text({ Key = "pets.select", Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 122), TextColor3 = Theme.Ink, Stroke = false, MaxTextSize = 26, Parent = detail })
	local ribbon = Theme.new("Frame", { Size = UDim2.new(1, -60, 0, 26), Position = UDim2.fromOffset(30, 154), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, Parent = detail }, { Theme.corner(14), Theme.stroke(2) })
	local ribbonGradient = Theme.gradient(Theme.White, Theme.Grey)
	ribbonGradient.Parent = ribbon
	local detailRarity = Theme.text({ Text = "", Size = UDim2.new(1, -12, 1, -4), Position = UDim2.fromOffset(6, 2), MaxTextSize = 20, Parent = ribbon })
	local detailPower = Theme.text({ Text = "", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 181), TextColor3 = Theme.Orange, MaxTextSize = 22, Parent = detail })
	-- trait: grade + bonus, and the roll odds (numeric %, shown before rolling)
	local detailTrait = Theme.text({ Name = "Trait", Text = "", Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 205), MaxTextSize = 20, Parent = detail })
	local detailOdds = Theme.text({ Name = "TraitOdds", Text = "", Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 227), TextColor3 = Theme.Grey, Stroke = false, MaxTextSize = 14, Visible = false, Parent = detail })
	detailOdds.AutoLocalize = false
	do
		local parts = {}
		for _, g in Config.TraitGrades do
			table.insert(parts, g.name .. " " .. Format.chance(g.chance))
		end
		detailOdds.Text = table.concat(parts, "  ")
	end
	local buttons = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 122), Position = UDim2.new(0, 10, 1, -130), Parent = detail }, {
		Theme.new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 56), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local equipB = Theme.button({ Key = "pets.equip", Color = Theme.Green, LayoutOrder = 1, Parent = buttons, TextSize = 24 })
	local lockB = Theme.button({ Key = "pets.lock", Color = Theme.Blue, LayoutOrder = 2, Parent = buttons, TextSize = 24 })
	local craftB = Theme.button({ Text = "", Color = Theme.Yellow, LayoutOrder = 3, Parent = buttons, TextSize = 22 })
	-- (single deletes go through Delete Mode; this slot rolls a trait)
	local traitB = Theme.button({ Name = "RollTrait", Text = "", Color = Theme.Purple, LayoutOrder = 4, Parent = buttons, TextSize = 22 })

	local function act(action: string, payload: { [string]: any })
		local ok, res = Net.request(action, payload)
		if not ok and res then
			Toasts.show(Lang.msg(res), "error")
		end
		return ok, res
	end
	equipB.Activated:Connect(function()
		if not selectedUid then
			return
		end
		local eq = Net.get("equipped") or {}
		act(if table.find(eq, selectedUid) then "Unequip" else "Equip", { uid = selectedUid })
	end)
	lockB.Activated:Connect(function()
		local pets = Net.get("pets")
		if selectedUid and pets and pets[selectedUid] then
			act("Lock", { uid = selectedUid, locked = not pets[selectedUid].locked })
		end
	end)
	craftB.Activated:Connect(function()
		if selectedUid then
			local ok, newUid = act("Craft", { uid = selectedUid })
			if ok then
				selectedUid = newUid
			end
		end
	end)
	traitB.Activated:Connect(function()
		if selectedUid then
			local ok, grade = act("RollTrait", { uid = selectedUid })
			local g = if ok and type(grade) == "number" then Config.TraitGrades[grade] else nil
			if g then
				Toasts.show(Lang.t("pets.trait_rolled", { grade = g.name, pct = math.floor((g.mult - 1) * 100 + 0.5) }), "success")
				Theme.pop(detailTrait, 1.5)
				Theme.play("buy", 0.45, 0.9 + grade * 0.12)
			end
		end
	end)

	local cells: { [string]: Cell } = {}
	local iconKey = ""

	local function maxZone(): number
		return #(Net.get("zones") or { 1 })
	end

	local function makeCell(uid: string, pet: { id: string, tier: number, locked: boolean }): Cell
		local def = Formulas.PetById[pet.id]
		local rc = if def.rarity == "Secret" then Color3.fromRGB(60, 40, 80) else Palette.rarity(def.rarity)
		local stroke = Theme.stroke(3)
		local b = Theme.new("TextButton", {
			Name = uid,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, { Theme.corner(14), stroke, Theme.gradient(Theme.lighten(rc, 0.55), Theme.darken(rc, 0.05)) }) :: TextButton
		Theme.gloss(b, 14, 0.7)
		-- the 3D icon is created lazily, only while the cell is on screen (see updateIcons)
		-- dark plate so the power reads on any rarity colour
		local plate = Theme.new("Frame", { Size = UDim2.new(1, -8, 0, 24), Position = UDim2.new(0, 4, 1, -28), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = b }, { Theme.corner(9) })
		local power = Theme.text({ Text = "", Size = UDim2.new(1, -6, 1, -2), Position = UDim2.fromOffset(3, 1), MaxTextSize = 19, Parent = plate })
		power.AutoLocalize = false
		local ring = Theme.new("Frame", { Name = "Selected", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, Visible = false, Parent = b }, { Theme.corner(11), Theme.new("UIStroke", { Thickness = 3, Color = Theme.White }) })
		local hover = Theme.new("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			TweenService:Create(hover, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
		local equipped = Theme.new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(-6, -6), BackgroundColor3 = Theme.Green, Visible = false, Parent = b }, { Theme.corner(13), Theme.stroke(2) })
		Theme.text({ Text = "✓", Parent = equipped })
		local lock = Theme.text({ Text = "🔒", Stroke = false, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -24, 0, 2), Visible = false, Parent = b })
		local check = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Red, BackgroundTransparency = 0.45, Visible = false, Parent = b }, { Theme.corner(14) })
		Theme.text({ Text = "✕", Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), Parent = check })
		if pet.tier > 0 then
			Theme.text({ Text = if pet.tier == 1 then "★" else "🌈", Stroke = pet.tier == 1, TextColor3 = Palette.Gold, Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -26, 1, -52), Parent = b })
		end
		b.Activated:Connect(function()
			Theme.play("click", 0.3)
			if deleteMode then
				local p = (Net.get("pets") or {})[uid]
				if p and p.locked then
					Toasts.show(Lang.t("toast.pet_locked"), "error")
					return
				end
				if selected[uid] then
					selected[uid] = nil
				else
					selected[uid] = true
				end
			else
				selectedUid = uid
			end
			refresh()
		end)
		b.Parent = grid
		-- trait grade badge (top-left, under the equipped tick)
		local traitBadge = Theme.new("Frame", { Name = "TraitBadge", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 3, 1, -54), BackgroundColor3 = Theme.Grey, Visible = false, Parent = b }, { Theme.corner(8), Theme.stroke(2) }) :: Frame
		local traitText = Theme.text({ Text = "", Size = UDim2.new(1, -4, 1, -2), Position = UDim2.fromOffset(2, 1), MaxTextSize = 18, Parent = traitBadge })
		traitText.AutoLocalize = false
		return { button = b, trait = traitBadge, traitText = traitText, key = pet.id .. ":" .. pet.tier, power = power, equipped = equipped, lock = lock, check = check, stroke = stroke, ring = ring, petId = pet.id, tier = pet.tier, icon = nil }
	end

	-- Virtualized grid: a full inventory is 150 pets, and every icon is a ViewportFrame with
	-- ~40 parts. Only the cells inside the scrolling window (plus one row) keep their icon.
	local function updateIcons()
		if not Windows.isOpen("Pets") then
			return -- closing: the icons were dropped on purpose
		end
		local top = grid.AbsolutePosition.Y
		local bottom = top + grid.AbsoluteSize.Y
		local margin = 130
		for _, c in cells do
			local y = c.button.AbsolutePosition.Y
			local visible = y + c.button.AbsoluteSize.Y > top - margin and y < bottom + margin
			if visible and not c.icon then
				local icon = PetIcon.new(c.petId, c.tier)
				icon.Size = UDim2.new(1, -6, 1, -28)
				icon.Position = UDim2.fromOffset(3, 1)
				icon.Parent = c.button
				c.icon = icon
			elseif not visible and c.icon then
				c.icon:Destroy()
				c.icon = nil
			end
		end
	end
	PetsWindow.iconCount = function(): (number, number)
		local icons, total = 0, 0
		for _, c in cells do
			total += 1
			if c.icon then
				icons += 1
			end
		end
		return icons, total
	end
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(updateIcons)
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateIcons)
	local gridLayout = grid:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then
		gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateIcons)
	end

	refresh = function()
		if not Windows.isOpen("Pets") then
			return
		end
		local s = Net.state
		if not s then
			return
		end
		local pets = s.pets
		local eqSet: { [string]: boolean } = {}
		for _, uid in s.equipped do
			eqSet[uid] = true
		end
		local n = 0
		local uids = {}
		for uid, pet in pets do
			n += 1
			table.insert(uids, uid)
			local c = cells[uid]
			if c and c.key ~= pet.id .. ":" .. pet.tier then
				c.button:Destroy()
				cells[uid] = nil
			end
		end
		for uid, c in cells do
			if not pets[uid] then
				c.button:Destroy()
				cells[uid] = nil
				selected[uid] = nil
			end
		end
		local mz = maxZone()
		table.sort(uids, function(a, b)
			local ea, eb = eqSet[a] == true, eqSet[b] == true
			if ea ~= eb then
				return ea
			end
			local pa = Formulas.petPower(pets[a].id, pets[a].tier, mz, pets[a].trait)
			local pb = Formulas.petPower(pets[b].id, pets[b].tier, mz, pets[b].trait)
			if pa ~= pb then
				return pa > pb
			end
			return a < b
		end)
		for i, uid in uids do
			local pet = pets[uid]
			local c = cells[uid] or makeCell(uid, pet)
			cells[uid] = c
			c.button.LayoutOrder = i
			c.power.Text = "+" .. Format.abbrev(Formulas.petPower(pet.id, pet.tier, mz, pet.trait))
			local tg = if pet.trait then Config.TraitGrades[pet.trait] else nil
			c.trait.Visible = tg ~= nil
			if tg then
				c.traitText.Text = tg.name
				c.trait.BackgroundColor3 = Palette.rgb(tg.color)
			end
			c.equipped.Visible = eqSet[uid] == true
			c.stroke.Color = if eqSet[uid] then Theme.darken(Theme.Green, 0.35) else Theme.Ink
			c.stroke.Thickness = if eqSet[uid] then 4 else 3
			c.ring.Visible = not deleteMode and uid == selectedUid
			c.lock.Visible = pet.locked
			c.check.Visible = deleteMode and selected[uid] == true
		end
		countLabel.Text = Lang.t("pets.count", { n = n, max = s.maxInventory, eq = #s.equipped, maxEq = s.maxEquip })
		-- once the grid layout has placed the cells (new cells sit at 0,0 until then)
		task.delay(0.05, function()
			if Windows.isOpen("Pets") then
				updateIcons()
			end
		end)
		local selCount = 0
		for _ in selected do
			selCount += 1
		end
		Theme.setButton(deleteButton, if deleteMode then (if selCount > 0 then Lang.t("pets.delete_n", { n = selCount }) else Lang.t("pets.cancel")) else Lang.t("pets.delete_mode"), if deleteMode then Theme.Orange else Theme.Red)

		-- detail
		local sel = if selectedUid then pets[selectedUid] else nil
		buttons.Visible = sel ~= nil
		emptyIcon.Visible = sel == nil
		ribbon.Visible = sel ~= nil
		local key = if sel and selectedUid then (selectedUid .. sel.id .. sel.tier) else ""
		if key ~= iconKey then
			iconKey = key
			detailIcon:ClearAllChildren()
			if sel then
				PetIcon.new(sel.id, sel.tier, false, 0).Parent = detailIcon
			end
		end
		if sel and selectedUid then
			local def = Formulas.PetById[sel.id]
			Lang.unbind(detailName)
			detailName.Text = Lang.pet(def.id, sel.tier)
			local rc = if def.rarity == "Secret" then SECRET else Palette.rarity(def.rarity)
			detailRarity.Text = Lang.upper(Lang.rarity(def.rarity))
			ribbonGradient.Color = ColorSequence.new(Theme.lighten(rc, 0.3), Theme.darken(rc, 0.08))
			stageGradient.Color = ColorSequence.new(Theme.lighten(rc, 0.6), Theme.lighten(rc, 0.12))
			detailPower.Text = Lang.t("pets.power", { n = Format.abbrev(Formulas.petPower(sel.id, sel.tier, mz, sel.trait)) })
			local tg = if sel.trait then Config.TraitGrades[sel.trait] else nil
			detailTrait.Text = if tg then Lang.t("pets.trait", { grade = tg.name, pct = math.floor((tg.mult - 1) * 100 + 0.5) }) else Lang.t("pets.no_trait")
			detailTrait.TextColor3 = if tg then Palette.rgb(tg.color) else Theme.Grey
			detailOdds.Visible = true
			Theme.setButton(traitB, "🎲 " .. Lang.t("pets.roll", { n = s.dice or 0 }), if (s.dice or 0) >= Config.TraitRollCost then Theme.Purple else Theme.Grey)
			Theme.setButton(equipB, Lang.t(if eqSet[selectedUid] then "pets.unequip" else "pets.equip"), if eqSet[selectedUid] then Theme.Grey else Theme.Green)
			Theme.setButton(lockB, Lang.t(if sel.locked then "pets.unlock" else "pets.lock"))
			local same = 0
			for _, p in pets do
				if p.id == sel.id and p.tier == sel.tier and not p.locked then
					same += 1
				end
			end
			if sel.locked then
				same += 1
			end
			craftB.Visible = sel.tier < 2
			Theme.setButton(craftB, Lang.t(if sel.tier == 0 then "pets.craft_gold" else "pets.craft_rainbow", { have = math.min(same, Config.CraftCost), need = Config.CraftCost }), if same >= Config.CraftCost then Theme.Yellow else Theme.Grey)
		else
			Lang.unbind(detailName)
			detailName.Text = Lang.t(if deleteMode then "pets.select_delete" else "pets.select")
			detailRarity.Text = ""
			detailPower.Text = ""
			detailTrait.Text = ""
			detailOdds.Visible = false
			stageGradient.Color = ColorSequence.new(Theme.lighten(Theme.Grey, 0.55), Theme.lighten(Theme.Grey, 0.2))
		end
	end

	-- Selects the strongest equipped pet (screenshot showcase / tests).
	PetsWindow.selectFirst = function()
		local s = Net.state
		if s and s.equipped[1] then
			selectedUid = s.equipped[1]
			refresh()
		end
	end
	w.onOpen = refresh
	w.onClose = function()
		deleteMode = false
		table.clear(selected)
		-- closed: drop every icon (they come back for the visible rows on the next open)
		for _, c in cells do
			if c.icon then
				c.icon:Destroy()
				c.icon = nil
			end
		end
	end
	-- the selected pet turns slowly on its stage
	RunService.RenderStepped:Connect(function()
		if not Windows.isOpen("Pets") then
			return
		end
		local vp = detailIcon:FindFirstChildOfClass("ViewportFrame")
		local model = vp and vp:FindFirstChildOfClass("Model")
		if model then
			model:PivotTo(CFrame.Angles(0, os.clock() * 0.9, 0))
		end
	end)
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			refresh()
		end
	end)
end

return PetsWindow
