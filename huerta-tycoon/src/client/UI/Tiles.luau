--!nonstrict
-- Tile interaction on your own plot: click/tap to harvest, plant, check progress or buy the next tile.
-- Also: PC hover highlight, ripe-tile glow, small progress bars over growing crops, "unlock" tag on the next tile.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local L = I18n.L
local State = require(script.Parent.State)
local Net = require(script.Parent.Net)
local Toasts = require(script.Parent.Toasts)
local Teleport = require(script.Parent.Teleport)
local Juice = require(script.Parent.Juice)

local player = Players.LocalPlayer

local Tiles = {}

local GREEN = Color3.fromRGB(90, 255, 110)
local YELLOW = Color3.fromRGB(255, 220, 60)
local GRAY = Color3.fromRGB(160, 160, 160)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- ========== helpers ==========

function Tiles.myPlot(): Instance?
	return Teleport.myPlot()
end

function Tiles.ownTiles(): { BasePart }
	local out = {}
	local plot = Tiles.myPlot()
	local folder = plot and plot:FindFirstChild("Tiles")
	if folder then
		for _, t in folder:GetChildren() do
			if t:IsA("BasePart") then
				table.insert(out, t)
			end
		end
	end
	table.sort(out, function(a, b)
		return Tiles.index(a) < Tiles.index(b)
	end)
	return out
end

function Tiles.index(tile: Instance): number
	local i = tile:GetAttribute("TileIndex")
	if type(i) == "number" then
		return i
	end
	return tonumber(tile.Name:match("^Tile_(%d+)$")) or 0
end

-- Walk up from whatever was hit to the Tile_<i> part (crop models are parented to the tile part).
local function tileFrom(inst: Instance?): BasePart?
	while inst and inst ~= workspace do
		if inst:IsA("BasePart") and inst.Name:match("^Tile_%d+$") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local function isOwn(tile: BasePart): boolean
	local plot = Tiles.myPlot()
	return plot ~= nil and tile:IsDescendantOf(plot)
end

local function raycast(ray: Ray): RaycastResult?
	local filter: { Instance } = {}
	if player.Character then
		table.insert(filter, player.Character)
	end
	rayParams.FilterDescendantsInstances = filter
	return workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
end

local function tileAtScreen(x: number, y: number, viewport: boolean): BasePart?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local ray = if viewport then cam:ViewportPointToRay(x, y) else cam:ScreenPointToRay(x, y)
	local hit = raycast(ray)
	return hit and tileFrom(hit.Instance)
end

-- ========== buy-tile confirm popup ==========

local popup: Frame? = nil
local popupText: TextLabel? = nil
local popupBuy: TextButton? = nil

local function buildPopup(root: Instance)
	local f: Frame = C.new("Frame", {
		Name = "TileConfirm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 200),
		BackgroundColor3 = Theme.C.Panel,
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	C.corner(f, 22)
	C.stroke(f, 5, Theme.C.PanelEdge)
	local sc = C.new("UIScale", { Name = "PopScale", Parent = f })
	C.label(f, L("tiles.unlockTitle"), UDim2.new(1, 0, 0, 44), {
		Position = UDim2.fromOffset(0, 12),
		TextSize = 30,
		TextColor3 = Theme.C.Purple,
		Outline = 2,
	})
	popupText = C.label(f, "", UDim2.new(1, -30, 0, 40), {
		Position = UDim2.fromOffset(15, 58),
		TextSize = 22,
		TextColor3 = Theme.C.Ink,
		Outline = false,
	})
	popupBuy = C.button({
		Parent = f,
		Text = L("tiles.unlock"),
		TextSize = 24,
		Color = Theme.C.Green,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -18),
		Size = UDim2.fromOffset(160, 56),
		OnClick = function()
			f.Visible = false
			if Net.request("BuyTile") then
				Juice.confetti(16)
			end
		end,
	})
	C.button({
		Parent = f,
		Text = L("tiles.cancel"),
		TextSize = 24,
		Color = Theme.C.Red,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -18),
		Size = UDim2.fromOffset(160, 56),
		OnClick = function()
			f.Visible = false
		end,
	})
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		if f.Visible then
			sc.Scale = 0.6
			C.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	popup = f
end

local function askBuyTile(idx: number)
	local d = State.data
	if not d or not popup then
		return
	end
	local cost = d.tileCost or 0
	;(popupText :: TextLabel).Text = I18n.t("tiles.popup", { n = idx, cash = Format.cash(cost) })
	C.setEnabled(popupBuy :: TextButton, (d.cash or 0) >= cost)
	C.setText(popupBuy :: TextButton, if (d.cash or 0) >= cost then L("tiles.unlock") else L("tiles.needCash"))
	;(popup :: Frame).Visible = true
end

-- ========== actions ==========

local function interact(tile: BasePart)
	local d = State.data
	if not d then
		return
	end
	if not isOwn(tile) then
		Toasts.show(L("tiles.notYours"), "info")
		return
	end
	local idx = Tiles.index(tile)
	if tile:GetAttribute("HasCrop") then
		if tile:GetAttribute("Ripe") then
			Net.request("Harvest", { tile = idx }, { silentOk = true })
		else
			local sid = tile:GetAttribute("SeedId")
			local seed = if type(sid) == "string" then Config.SeedById[sid] else nil
			local p = tonumber(tile:GetAttribute("Progress")) or 0
			local seedName = if seed then { key = "seed." .. seed.id } else { key = "tiles.crop" }
			Toasts.show(L("tiles.grown", { seed = seedName, pct = math.floor(p * 100) }, Theme.seedEmoji(seed and seed.id) .. " "), "info")
		end
	elseif tile:GetAttribute("Unlocked") then
		local seed = State.selectedSeed
		if not seed or State.seedCount(seed) <= 0 then
			Toasts.show(L("tiles.selectSeed"), "error")
			return
		end
		Net.request("Plant", { tile = idx, seedId = seed }, { silentOk = true })
	else
		local nextIdx = (d.tilesOwned or 0) + 1
		if idx == nextIdx and nextIdx <= Config.MaxTiles then
			askBuyTile(idx)
		else
			Toasts.show(L("tiles.order", { n = nextIdx }), "info")
		end
	end
end

-- ========== visuals: hover, ripe glow, progress bars ==========

local hoverBox: SelectionBox? = nil
local markers: { [BasePart]: { glow: SelectionBox?, bb: BillboardGui?, kind: string, fill: Frame?, text: TextLabel? } } = {}
local markerFolder: Folder? = nil

local function clearMarker(tile: BasePart)
	local m = markers[tile]
	if m then
		if m.glow then
			m.glow:Destroy()
		end
		if m.bb then
			m.bb:Destroy()
		end
		markers[tile] = nil
	end
end

local function makeGlow(tile: BasePart): SelectionBox
	local box: SelectionBox = C.new("SelectionBox", {
		Adornee = tile,
		Color3 = GREEN,
		SurfaceColor3 = GREEN,
		LineThickness = 0.09,
		SurfaceTransparency = 0.93,
		Transparency = 0.15,
		Parent = markerFolder,
	})
	-- a soft breathing outline: the soil must stay soil-colored under a full plot of ripe crops
	TweenService:Create(box, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { SurfaceTransparency = 0.8 }):Play()
	return box
end

-- Markers are sized in STUDS (they shrink with distance, so neighbours never pile up on screen) and only show
-- near the player: growing crops get a small progress bar, ripe ones a "READY!" tag.
Tiles.MAX_READY_TAGS = 3
Tiles.BAR_RANGE = 46
Tiles.TAG_RANGE = 80
local function makeBillboard(tile: BasePart, withBar: boolean): (BillboardGui, Frame?, TextLabel)
	local bb: BillboardGui = C.new("BillboardGui", {
		Name = if withBar then "GrowBar" else "TileTag",
		Adornee = tile,
		Size = if withBar then UDim2.fromScale(3.6, 0.55) else UDim2.fromScale(4.4, 1.2),
		StudsOffsetWorldSpace = Vector3.new(0, if withBar then 1.1 else 4.5, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = if withBar then Tiles.BAR_RANGE else Tiles.TAG_RANGE,
		-- closer than this the tag stops growing (it would fill the screen when you stand on the tile)
		DistanceLowerLimit = 26,
		Parent = markerFolder,
	})
	local text = C.label(bb, "", UDim2.fromScale(1, 1), { TextSize = 60, TextWrapped = false, Visible = not withBar })
	local fill: Frame? = nil
	if withBar then
		local back: Frame = C.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(40, 36, 32),
			BackgroundTransparency = 0.15,
			Parent = bb,
		})
		C.round(back)
		fill = C.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = YELLOW, Parent = back })
		C.round(fill :: Frame)
	end
	return bb, fill, text
end

local function updateMarkers()
	local d = State.data
	local seen: { [BasePart]: boolean } = {}
	if d then
		local nextIdx = (d.tilesOwned or 0) + 1
		for _, tile in Tiles.ownTiles() do
			seen[tile] = true
			local kind = "none"
			if tile:GetAttribute("HasCrop") then
				kind = if tile:GetAttribute("Ripe") then "ripe" else "grow"
			elseif not tile:GetAttribute("Unlocked") and Tiles.index(tile) == nextIdx then
				kind = "buy"
			end
			local m = markers[tile]
			if m and m.kind ~= kind then
				clearMarker(tile)
				m = nil
			end
			if kind ~= "none" and not m then
				m = { kind = kind }
				if kind == "ripe" then
					m.glow = makeGlow(tile)
					local bb, _, text = makeBillboard(tile, false)
					I18n.set(text, "Text", L("tiles.ready"))
					text.TextColor3 = GREEN
					m.bb = bb
				elseif kind == "grow" then
					local bb, fill, text = makeBillboard(tile, true)
					m.bb, m.fill, m.text = bb, fill, text
				elseif kind == "buy" then
					local bb, _, text = makeBillboard(tile, false)
					bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
					m.bb, m.text = bb, text
				end
				markers[tile] = m
			end
			if m and kind == "grow" then
				local p = math.clamp(tonumber(tile:GetAttribute("Progress")) or 0, 0, 1)
				if m.fill then
					m.fill.Size = UDim2.fromScale(p, 1)
				end
			elseif m and kind == "buy" and m.text then
				m.text.Text = "🔒 " .. Format.cash(d.tileCost or 0)
				m.text.TextColor3 = if (d.cash or 0) >= (d.tileCost or math.huge) then GREEN else Theme.C.White
			end
		end
	end
	for tile in markers do
		if not seen[tile] or not tile.Parent then
			clearMarker(tile)
		end
	end
	-- "READY!" only on the few ripe crops nearest to you: a whole ripe plot used to be a wall of text
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local ripe: { { bb: BillboardGui, d: number } } = {}
	for tile, m in markers do
		if m.kind == "ripe" and m.bb then
			table.insert(ripe, { bb = m.bb, d = if rootPart then (tile.Position - rootPart.Position).Magnitude else 0 })
		end
	end
	table.sort(ripe, function(a, b)
		return a.d < b.d
	end)
	for i, r in ripe do
		r.bb.Enabled = i <= Tiles.MAX_READY_TAGS
		-- stud-sized tags balloon when you stand next to them: shrink them with proximity
		local k = math.clamp(r.d / 26, 0.35, 1)
		r.bb.Size = UDim2.fromScale(4.4 * k, 1.2 * k)
	end
end

local function updateHover()
	local box = hoverBox
	if not box then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local tile = tileAtScreen(mouse.X, mouse.Y, true)
	if not tile or not isOwn(tile) then
		box.Adornee = nil
		return
	end
	local d = State.data
	local color = GRAY
	if tile:GetAttribute("HasCrop") then
		color = if tile:GetAttribute("Ripe") then GREEN else YELLOW
	elseif tile:GetAttribute("Unlocked") then
		color = if State.seedCount(State.selectedSeed) > 0 then GREEN else YELLOW
	elseif d and Tiles.index(tile) == (d.tilesOwned or 0) + 1 then
		color = GREEN
	end
	box.Color3 = color
	box.SurfaceColor3 = color
	box.Adornee = tile
end

-- ========== init ==========

function Tiles.init(root: Instance)
	buildPopup(root)
	markerFolder = C.new("Folder", { Name = "CropKingdomTileMarkers", Parent = player:WaitForChild("PlayerGui") })

	hoverBox = C.new("SelectionBox", {
		Name = "TileHover",
		LineThickness = 0.08,
		SurfaceTransparency = 0.85,
		Transparency = 0,
		Parent = markerFolder,
	})

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local tile = tileAtScreen(input.Position.X, input.Position.Y, false)
		if tile then
			interact(tile)
		end
	end)

	UserInputService.TouchTap:Connect(function(positions, gameProcessed)
		if gameProcessed or not positions[1] then
			return
		end
		local pos = positions[1]
		local tile = tileAtScreen(pos.X, pos.Y, false)
		if tile then
			interact(tile)
		end
	end)

	local acc = 0
	local frame = 0
	RunService.RenderStepped:Connect(function(dt)
		frame += 1
		if frame % 3 == 0 and UserInputService.MouseEnabled then
			updateHover()
		end
		acc += dt
		if acc >= 0.3 then
			acc = 0
			updateMarkers()
		end
	end)
end

return Tiles
