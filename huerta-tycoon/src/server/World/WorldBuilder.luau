--!strict
-- Builds the whole map procedurally: terrain, lighting, market square with shops, fenced plots with a farmhouse,
-- landmarks between the plots (pond, windmill, hay field, barn, pumpkin patch, tractor) and scattered nature.
-- Everything is made of Parts and native materials: no uploaded assets.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locale = require(ReplicatedStorage.Shared.Locale)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Wild = require(ReplicatedStorage.Shared.Wild)
local Props = require(script.Parent.Props)

local WorldBuilder = {}

WorldBuilder.PLOT_COUNT = WorldLayout.PLOT_COUNT
WorldBuilder.PLOT_DISTANCE = WorldLayout.PLOT_DISTANCE
WorldBuilder.TILE_COLS = WorldLayout.TILE_COLS
WorldBuilder.TILE_ROWS = WorldLayout.TILE_ROWS
WorldBuilder.TILE_SIZE = WorldLayout.TILE_SIZE
WorldBuilder.TILE_GAP = WorldLayout.TILE_GAP
WorldBuilder.GROUND_Y = 0

local P, B, Cy, CyX = Props.P, Props.B, Props.Cy, Props.CyX
local DECOR, TINY = Props.DECOR, Props.TINY
local WOOD, WOOD_DARK, WOOD_LIGHT = Props.WOOD, Props.WOOD_DARK, Props.WOOD_LIGHT
local STONE, WHITE = Props.STONE, Props.WHITE
local rng = Props.rng

local SOIL_LOCKED = Color3.fromRGB(96, 142, 70)
local SOIL_BED = Color3.fromRGB(74, 50, 34)
local GRASS = Color3.fromRGB(98, 172, 66)
local FENCE = Color3.fromRGB(240, 232, 214)

local function label(parentPart: BasePart, text: string, face: Enum.NormalId, color: Color3?, textColor: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = parentPart
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
	t.BackgroundTransparency = if color then 0 else 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = textColor or Color3.new(1, 1, 1)
	t.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(40, 30, 20)
	stroke.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = t
	t.Parent = gui
	return t
end
WorldBuilder.label = label

-- Floating emoji marker above a shop so it reads from across the square (bobbed on the client: tag CK_Bob).
local function marker(parent: Instance, cf: CFrame, emoji: string)
	local anchor = P(parent, "Marker", Vector3.one, cf, WHITE, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local bb = Instance.new("BillboardGui")
	bb.Name = "Icon"
	bb.Size = UDim2.fromScale(6, 6)
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.Text = emoji
	t.Parent = bb
	CollectionService:AddTag(bb, "CK_Bob")
end

-- ===================================================================== shops

type StallKind = "seeds" | "sell" | "upgrades" | "store"

-- titleKey/promptKey are Locale keys: English is written here, clients re-render in their language.
local function stall(hub: Instance, name: string, kind: StallKind, titleKey: string, cf: CFrame, awningA: Color3, awningB: Color3, promptKey: string, emoji: string): Part
	local decor = Instance.new("Model")
	decor.Name = name .. "Decor"
	-- wooden deck so the stall doesn't float on the cobbles
	P(decor, "Deck", Vector3.new(17, 0.5, 9), cf * CFrame.new(0, 0.25, 1), WOOD_LIGHT, Enum.Material.WoodPlanks)
	-- counter is the interactable part
	local counter = P(hub, name, Vector3.new(14, 3.5, 4), cf * CFrame.new(0, 2.25, 0), WOOD, Enum.Material.WoodPlanks)
	P(decor, "Top", Vector3.new(14.8, 0.5, 4.8), cf * CFrame.new(0, 4.25, 0), WOOD_DARK, Enum.Material.Wood)
	P(decor, "CounterTrim", Vector3.new(14.2, 0.5, 0.3), cf * CFrame.new(0, 1, -2.1), awningA, nil, DECOR)
	for _, x in { -6.8, 6.8 } do
		for _, z in { -1.8, 3.8 } do
			P(decor, "Post", Vector3.new(0.8, 11.5, 0.8), cf * CFrame.new(x, 6.25, z), WOOD_DARK, Enum.Material.Wood)
		end
	end
	-- back wall with shelves
	P(decor, "BackWall", Vector3.new(14.4, 6, 0.4), cf * CFrame.new(0, 7.5, 4), WOOD, Enum.Material.WoodPlanks)
	P(decor, "Shelf", Vector3.new(13.6, 0.3, 1.2), cf * CFrame.new(0, 7, 3.3), WOOD_DARK, Enum.Material.Wood, DECOR)
	-- striped awning + scalloped valance
	for i = 0, 6 do
		local c = if i % 2 == 0 then awningA else awningB
		P(decor, "Awning", Vector3.new(2.2, 0.4, 8), cf * CFrame.new(-6.6 + i * 2.2, 12.1, 0.6) * CFrame.Angles(math.rad(-13), 0, 0), c, Enum.Material.Fabric, DECOR)
		B(decor, "Valance", Vector3.new(2.2, 1.5, 0.5), cf * CFrame.new(-6.6 + i * 2.2, 10.7, -3.35), c, Enum.Material.Fabric, TINY)
	end
	local sign = P(decor, "Sign", Vector3.new(12.4, 2.8, 0.5), cf * CFrame.new(0, 14.6, -1.2), awningA)
	P(decor, "SignFrame", Vector3.new(13, 3.4, 0.3), cf * CFrame.new(0, 14.6, -1.2), Props.darken(awningA, 0.45), nil, DECOR)
	Locale.stamp(label(sign, "", Enum.NormalId.Front, nil), titleKey)
	Locale.stamp(label(sign, "", Enum.NormalId.Back, nil), titleKey)
	marker(decor, cf * CFrame.new(0, 21, 0), emoji)
	-- hanging lanterns under the awning
	for _, x in { -5, 5 } do
		P(decor, "LanternCord", Vector3.new(0.1, 1.4, 0.1), cf * CFrame.new(x, 10.6, -1.4), WOOD_DARK, nil, TINY)
		local lantern = B(decor, "Lantern", Vector3.one * 0.9, cf * CFrame.new(x, 9.7, -1.4), Color3.fromRGB(255, 225, 150), Enum.Material.Neon, TINY)
		if x < 0 then
			local light = Instance.new("PointLight")
			light.Range = 14
			light.Brightness = 0.8
			light.Color = Color3.fromRGB(255, 210, 140)
			light.Parent = lantern
		end
	end

	-- goods: every shop sells something you can recognize from far away
	local function produce(x: number, y: number, z: number, color: Color3, size: number)
		B(decor, "Goods", Vector3.one * size, cf * CFrame.new(x, y, z), color, nil, TINY)
	end
	if kind == "seeds" then
		local sack = Color3.fromRGB(196, 160, 110)
		local tops = { Color3.fromRGB(255, 130, 30), Color3.fromRGB(230, 40, 40), Color3.fromRGB(255, 220, 60), Color3.fromRGB(70, 90, 230), Color3.fromRGB(90, 200, 90) }
		for i = 1, 5 do
			local x = -6 + i * 2
			B(decor, "SeedSack", Vector3.new(1.5, 1.7, 1.5), cf * CFrame.new(x, 5.3, 0.2), sack, Enum.Material.Fabric, TINY)
			B(decor, "SeedTop", Vector3.new(1.1, 0.5, 1.1), cf * CFrame.new(x, 6.1, 0.2), tops[i], nil, TINY)
		end
		for i = 1, 4 do
			local x = -6.5 + i * 2.6
			Cy(decor, "Pot", 1, 0.9, cf * CFrame.new(x, 7.6, 3.3), Color3.fromRGB(190, 100, 60), nil, TINY)
			B(decor, "Sprout", Vector3.new(0.9, 1.1, 0.9), cf * CFrame.new(x, 8.4, 3.3), Color3.fromRGB(80, 190, 80), Enum.Material.Grass, TINY)
		end
		Props.crate(decor, cf * CFrame.new(-9.4, 0.5, -1.5) * CFrame.Angles(0, 0.3, 0), 2.6, { Color3.fromRGB(255, 130, 30), Color3.fromRGB(90, 200, 90) })
		Props.sack(decor, cf * CFrame.new(9.2, 0.5, -1.2))
		Props.sack(decor, cf * CFrame.new(10.4, 0.5, 0.6))
	elseif kind == "sell" then
		local colors = { Color3.fromRGB(255, 140, 20), Color3.fromRGB(230, 40, 40), Color3.fromRGB(40, 150, 60), Color3.fromRGB(255, 220, 60) }
		for i = 1, 4 do
			local x = -6.5 + i * 2.6
			P(decor, "Tray", Vector3.new(2.2, 0.5, 2.4), cf * CFrame.new(x, 4.75, 0), WOOD_LIGHT, Enum.Material.Wood, TINY)
			for j = 0, 2 do
				produce(x - 0.6 + j * 0.6, 5.4 + (j % 2) * 0.35, (j - 1) * 0.5, colors[i], 1)
			end
		end
		-- coin stacks: this is where the money is
		for i, h in { 1.2, 2, 0.8 } do
			Cy(decor, "Coins", 1.3, h, cf * CFrame.new(4.4 + i * 0.9, 7.15 + h / 2, 3.3), Color3.fromRGB(255, 205, 50), Enum.Material.Foil, TINY)
		end
		Props.crate(decor, cf * CFrame.new(-9.4, 0.5, -1), 2.8, { Color3.fromRGB(230, 40, 40), Color3.fromRGB(255, 140, 20) })
		Props.crate(decor, cf * CFrame.new(9.6, 0.5, -1.2) * CFrame.Angles(0, -0.4, 0), 2.8, { Color3.fromRGB(40, 150, 60), Color3.fromRGB(255, 220, 60) })
		Props.barrel(decor, cf * CFrame.new(10.2, 0.5, 2.2))
	elseif kind == "upgrades" then
		-- watering cans, fertilizer bags and a big gear
		for i = 1, 3 do
			local x = -5 + (i - 1) * 2.4
			Cy(decor, "Can", 1.3, 1.5, cf * CFrame.new(x, 5.25, 0.2), Color3.fromRGB(70, 150, 235), Enum.Material.Metal, TINY)
			P(decor, "Spout", Vector3.new(0.3, 0.3, 1.3), cf * CFrame.new(x, 5.6, -0.9) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(70, 150, 235), Enum.Material.Metal, TINY)
		end
		for i = 1, 2 do
			local x = 2 + i * 2.2
			P(decor, "Fertilizer", Vector3.new(1.6, 2, 1), cf * CFrame.new(x, 5.5, 0.2) * CFrame.Angles(0, 0, math.rad(if i == 1 then 6 else -5)), Color3.fromRGB(120, 200, 90), Enum.Material.Fabric, TINY)
		end
		local gear = CyX(decor, "Gear", 3.4, 0.5, cf * CFrame.new(0, 9.4, 3.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 200, 60), Enum.Material.Metal, TINY)
		CollectionService:AddTag(gear, "CK_Spin")
		gear:SetAttribute("SpinSpeed", 0.8)
		gear:SetAttribute("SpinAxis", "X")
		Props.barrel(decor, cf * CFrame.new(-9.6, 0.5, -0.8))
		Props.crate(decor, cf * CFrame.new(9.6, 0.5, -1), 2.6, nil)
	else
		-- gems and a gold star
		local gems = { Color3.fromRGB(200, 90, 255), Color3.fromRGB(90, 230, 255), Color3.fromRGB(255, 90, 170), Color3.fromRGB(120, 255, 140), Color3.fromRGB(255, 220, 80) }
		for i = 1, 5 do
			local x = -6 + i * 2
			P(decor, "Cushion", Vector3.new(1.5, 0.4, 1.5), cf * CFrame.new(x, 4.7, 0), Color3.fromRGB(90, 40, 120), Enum.Material.Fabric, TINY)
			local gem = P(decor, "Gem", Vector3.one * 0.95, cf * CFrame.new(x, 5.75, 0) * CFrame.Angles(math.rad(45), math.rad(35), 0), gems[i], Enum.Material.Neon, TINY)
			CollectionService:AddTag(gem, "CK_Spin")
			gem:SetAttribute("SpinSpeed", 1.4)
			gem:SetAttribute("SpinAxis", "World")
		end
		for _, x in { -8.6, 8.6 } do
			for j = 1, 3 do
				local balloon = B(decor, "Balloon", Vector3.new(1.8, 2.2, 1.8), cf * CFrame.new(x + (j - 2) * 0.9, 13.5 + j * 0.9, -2.2 + (j % 2) * 0.8), gems[j + (if x < 0 then 0 else 2)], nil, TINY)
				balloon.Reflectance = 0.15
			end
			P(decor, "BalloonString", Vector3.new(0.08, 8, 0.08), cf * CFrame.new(x, 9.2, -2), WHITE, nil, TINY)
		end
		Props.crate(decor, cf * CFrame.new(-9.6, 0.5, -0.8), 2.6, { Color3.fromRGB(200, 90, 255) })
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	Locale.stamp(prompt, promptKey, nil, "ActionText")
	Locale.stamp(prompt, titleKey, nil, "ObjectText")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	decor.Parent = hub
	return counter
end

-- ===================================================================== plots

export type PlotInfo = {
	model: Model,
	tiles: { Part },
	spawn: Part,
	sign: TextLabel,
	pedestals: { Part },
	signs: { TextLabel },
	avatars: { ImageLabel },
	cframe: CFrame,
}

local HOUSE_COLORS = {
	Color3.fromRGB(214, 84, 70), -- red
	Color3.fromRGB(86, 146, 214), -- blue
	Color3.fromRGB(240, 196, 84), -- yellow
	Color3.fromRGB(110, 184, 110), -- green
	Color3.fromRGB(226, 130, 170), -- pink
	Color3.fromRGB(150, 120, 200), -- purple
}

-- Owner sign face: avatar head shot on the left, name on the right.
local function ownerFace(board: BasePart, face: Enum.NormalId): (TextLabel, ImageLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "OwnerGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local img = Instance.new("ImageLabel")
	img.Name = "Avatar"
	img.AnchorPoint = Vector2.new(0, 0.5)
	img.Position = UDim2.fromScale(0.035, 0.5)
	img.Size = UDim2.fromScale(0.29, 0.8)
	img.BackgroundColor3 = Color3.fromRGB(255, 236, 190)
	img.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = img
	local ring = Instance.new("UIStroke")
	ring.Thickness = 4
	ring.Color = Color3.fromRGB(70, 44, 24)
	ring.Parent = img
	img.Parent = gui
	local t = Instance.new("TextLabel")
	t.Name = "OwnerName"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(40, 30, 20)
	stroke.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = t
	t.Parent = gui
	return t, img
end

-- Writes the owner (or "Empty Plot") on both faces of the plot sign.
function WorldBuilder.setOwner(plot: PlotInfo, userId: number?, displayName: string?)
	for i, t in plot.signs do
		local img = plot.avatars[i]
		if userId and displayName then
			Locale.stamp(t, "world.plotSign", { name = displayName })
			img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
			img.Visible = true
			t.Position = UDim2.fromScale(0.34, 0)
			t.Size = UDim2.fromScale(0.66, 1)
		else
			Locale.stamp(t, "world.emptyPlot")
			img.Image = ""
			img.Visible = false
			t.Position = UDim2.fromScale(0, 0)
			t.Size = UDim2.fromScale(1, 1)
		end
	end
end

local function buildPlot(parent: Instance, index: number, cf: CFrame): PlotInfo
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("OwnerName", "")

	local cols, rows = WorldLayout.TILE_COLS, WorldLayout.TILE_ROWS
	local step = WorldLayout.TILE_SIZE + WorldLayout.TILE_GAP
	local width, depth = WorldLayout.plotSize()
	local halfW, halfD = width / 2, depth / 2
	local gap = WorldLayout.entranceHalfWidth()

	P(model, "Base", Vector3.new(width, 1, depth), cf * CFrame.new(0, 0.5, 0), GRASS, Enum.Material.Grass)
	-- stone curb so the lawn reads as a built plot, not a slab dropped on the field
	for _, s in { -1, 1 } do
		P(model, "Curb", Vector3.new(width + 2, 1.3, 1), cf * CFrame.new(0, 0.65, s * (halfD + 0.5)), STONE, Enum.Material.Slate, DECOR)
		P(model, "Curb", Vector3.new(1, 1.3, depth), cf * CFrame.new(s * (halfW + 0.5), 0.65, 0), STONE, Enum.Material.Slate, DECOR)
	end

	-- ===== picket fence (local -Z faces the hub; the entrance gap is centered there) =====
	local function fenceRun(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.max(1, math.floor(len / 4 + 0.5))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			P(model, "FencePost", Vector3.new(0.7, 3.8, 0.7), cf * CFrame.new(p + Vector3.new(0, 2.9, 0)), FENCE, Enum.Material.Wood)
		end
		local mid = a:Lerp(b, 0.5)
		for _, y in { 2.1, 3.5 } do
			local c = mid + Vector3.new(0, y, 0)
			P(model, "FenceRail", Vector3.new(0.3, 0.45, len), cf * CFrame.lookAt(c, c + dir), FENCE, Enum.Material.Wood)
		end
	end
	fenceRun(Vector3.new(-halfW, 0, -halfD), Vector3.new(-gap, 0, -halfD))
	fenceRun(Vector3.new(gap, 0, -halfD), Vector3.new(halfW, 0, -halfD))
	fenceRun(Vector3.new(-halfW, 0, halfD), Vector3.new(halfW, 0, halfD))
	fenceRun(Vector3.new(-halfW, 0, -halfD), Vector3.new(-halfW, 0, halfD))
	fenceRun(Vector3.new(halfW, 0, -halfD), Vector3.new(halfW, 0, halfD))

	-- gate posts with lanterns: they frame the entrance without closing it
	for _, s in { -1, 1 } do
		P(model, "GatePost", Vector3.new(1.3, 6.4, 1.3), cf * CFrame.new(s * gap, 4.2, -halfD), WOOD_DARK, Enum.Material.Wood)
		P(model, "GateCap", Vector3.new(1.8, 0.4, 1.8), cf * CFrame.new(s * gap, 7.6, -halfD), WOOD, Enum.Material.Wood, TINY)
		local lantern = B(model, "GateLantern", Vector3.one * 1.3, cf * CFrame.new(s * gap, 8.4, -halfD), Color3.fromRGB(255, 225, 150), Enum.Material.Neon, TINY)
		if s < 0 then
			local light = Instance.new("PointLight")
			light.Range = 16
			light.Brightness = 0.9
			light.Color = Color3.fromRGB(255, 210, 140)
			light.Parent = lantern
		end
	end
	-- walkway from the gate to the beds
	P(model, "Walkway", Vector3.new(gap * 2 - 2, 0.16, 12), cf * CFrame.new(0, 1.06, -halfD + 5.5), Color3.fromRGB(214, 198, 166), Enum.Material.Sandstone, DECOR)

	-- ===== garden bed: dark soil under the tile grid, framed with planks =====
	local bedW, bedD = cols * step + 1.4, rows * step + 1.4
	local bedZ = 3
	P(model, "Bed", Vector3.new(bedW, 0.4, bedD), cf * CFrame.new(0, 1.15, bedZ), SOIL_BED, Enum.Material.Ground, DECOR)
	for _, s in { -1, 1 } do
		P(model, "BedEdge", Vector3.new(bedW + 1.2, 1, 0.6), cf * CFrame.new(0, 1.45, bedZ + s * (bedD / 2 + 0.3)), WOOD, Enum.Material.WoodPlanks, DECOR)
		P(model, "BedEdge", Vector3.new(0.6, 1, bedD), cf * CFrame.new(s * (bedW / 2 + 0.3), 1.45, bedZ), WOOD, Enum.Material.WoodPlanks, DECOR)
	end

	local tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "Tiles"
	tilesFolder.Parent = model
	local tiles = {}
	local i = 0
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			i += 1
			local x = (c - (cols - 1) / 2) * step
			local z = (r - (rows - 1) / 2) * step + bedZ
			local t = P(tilesFolder, "Tile_" .. i, Vector3.new(WorldLayout.TILE_SIZE, 1, WorldLayout.TILE_SIZE), cf * CFrame.new(x, 1.3, z), SOIL_LOCKED, Enum.Material.Ground, { CanTouch = false })
			t:SetAttribute("TileIndex", i)
			t:SetAttribute("Unlocked", false)
			t:SetAttribute("HasCrop", false)
			t:SetAttribute("Ripe", false)
			t:SetAttribute("SeedId", "")
			t:SetAttribute("Progress", 0)
			tiles[i] = t
		end
	end

	local spawnPart = P(model, "Spawn", Vector3.new(6, 0.2, 6), cf * CFrame.new(0, 1.1, -halfD + WorldLayout.SPAWN_INSET), WHITE, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })

	-- ===== owner sign: BESIDE the entrance (left of the gate), outside the fence, turned toward the path =====
	local sp = WorldLayout.signPlacement()
	local signCF = cf * CFrame.new(sp.x, 0, sp.z) * CFrame.Angles(0, -math.rad(sp.yawDeg), 0)
	local sw, sh = WorldLayout.SIGN_WIDTH, WorldLayout.SIGN_HEIGHT
	local board = P(model, "SignBoard", Vector3.new(sw, sh, 0.5), signCF * CFrame.new(0, 5.6, 0), WOOD, Enum.Material.WoodPlanks)
	P(model, "SignFrame", Vector3.new(sw + 0.6, sh + 0.6, 0.3), signCF * CFrame.new(0, 5.6, 0), WOOD_DARK, Enum.Material.Wood, DECOR)
	for _, x in { -sw / 2 + 0.7, sw / 2 - 0.7 } do
		P(model, "SignPost", Vector3.new(0.7, 3.9, 0.7), signCF * CFrame.new(x, 1.95, 0), WOOD_DARK, Enum.Material.Wood)
	end
	Props.gableRoof(model, signCF * CFrame.new(0, 7.6, 0), sw + 1.6, 2.4, 0.9, Color3.fromRGB(190, 70, 60), Enum.Material.Wood, DECOR)
	local frontText, frontImg = ownerFace(board, Enum.NormalId.Front)
	local backText, backImg = ownerFace(board, Enum.NormalId.Back)
	Props.flowerPatch(model, (signCF * CFrame.new(0, 0, -1.6)).Position, 3, 6)

	-- mailbox on the other side of the gate
	local mail = cf * CFrame.new(gap + 3.5, 0, -halfD - 2.5)
	P(model, "MailPost", Vector3.new(0.5, 3.4, 0.5), mail * CFrame.new(0, 1.7, 0), WOOD_DARK, Enum.Material.Wood, DECOR)
	P(model, "Mailbox", Vector3.new(1.3, 1.2, 2), mail * CFrame.new(0, 3.9, 0), Color3.fromRGB(220, 60, 60), Enum.Material.Metal, DECOR)
	P(model, "MailFlag", Vector3.new(0.15, 1, 0.5), mail * CFrame.new(0.75, 4.4, 0.4), Color3.fromRGB(255, 220, 80), nil, TINY)

	-- trophy pedestals outside the fence, right of the gate: what you exhibit is what passers-by see
	local pedestals: { Part } = {}
	for k = 1, 3 do
		local at = cf * CFrame.new(gap + 3.5 + k * 5.4, 0, -halfD - 3.4)
		P(model, "PedestalBase", Vector3.new(3.6, 0.5, 3.6), at * CFrame.new(0, 0.25, 0), STONE, Enum.Material.Slate, { CanQuery = false })
		pedestals[k] = Cy(model, "Pedestal_" .. k, 2.8, 1.8, at * CFrame.new(0, 1.4, 0), Props.lighten(STONE, 0.3), Enum.Material.Marble, { CanQuery = false })
		Cy(model, "PedestalRim", 3.2, 0.3, at * CFrame.new(0, 2.2, 0), Color3.fromRGB(255, 205, 60), Enum.Material.Foil, TINY)
	end

	-- lamps at the front corners
	for _, s in { -1, 1 } do
		Props.lamp(model, (cf * CFrame.new(s * (halfW + 4), 0, -halfD - 4)).Position, s < 0)
	end
	-- flower borders inside the front fence and hedges along the sides
	for _, s in { -1, 1 } do
		Props.flowerPatch(model, (cf * CFrame.new(s * (gap + (halfW - gap) / 2), 1, -halfD + 2.2)).Position, 1.6, 9, (halfW - gap) / 2 - 2, cf)
		for k = 0, 3 do
			Props.bush(model, (cf * CFrame.new(s * (halfW - 2.2), 1, -halfD + 9 + k * 12.5)).Position, 1)
		end
	end

	-- things a farmer leaves lying around
	Props.barrel(model, cf * CFrame.new(-halfW + 4, 1, -halfD + 4.5))
	Props.crate(model, cf * CFrame.new(-halfW + 7.4, 1, -halfD + 3.6) * CFrame.Angles(0, 0.4, 0), 2.2, { Color3.fromRGB(255, 130, 30) })
	Props.hayBale(model, cf * CFrame.new(halfW - 5, 1, -halfD + 4.5) * CFrame.Angles(0, 0.3, 0))
	Props.wateringCan(model, cf * CFrame.new(halfW - 9, 1, -halfD + 4))
	Props.scarecrow(model, cf * CFrame.new(0, 1, halfD - 2.4))

	-- farmhouse behind the plot, door facing the beds
	Props.farmhouse(model, cf * CFrame.new(0, 0, halfD + WorldLayout.HOUSE_OFFSET), HOUSE_COLORS[(index - 1) % #HOUSE_COLORS + 1])

	model.PrimaryPart = spawnPart
	model.Parent = parent
	local info: PlotInfo = { model = model, tiles = tiles, spawn = spawnPart, pedestals = pedestals, sign = frontText, signs = { frontText, backText }, avatars = { frontImg, backImg }, cframe = cf }
	WorldBuilder.setOwner(info, nil, nil)
	return info
end

export type World = {
	plots: { PlotInfo },
	hub: Folder,
	sellStand: Part,
	seedShop: Part,
	upgradeShop: Part,
	robuxShop: Part,
	board: Part,
	wildNodes: { Part },
}

-- ===================================================================== lighting

local function effect(className: string, name: string): any
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(className)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

local function setupLighting()
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 34
	Lighting.Brightness = 2.7
	Lighting.ExposureCompensation = 0.1
	Lighting.Ambient = Color3.fromRGB(78, 84, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 156, 170)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 238, 205)
	Lighting.ShadowSoftness = 0.3
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true

	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = 0.27
	atm.Offset = 0.28
	atm.Haze = 1.3
	atm.Glare = 0.25
	atm.Color = Color3.fromRGB(206, 226, 255)
	atm.Decay = Color3.fromRGB(116, 150, 196)
	atm.Parent = Lighting

	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 10
	sky.Parent = Lighting

	local bloom: BloomEffect = effect("BloomEffect", "Bloom")
	bloom.Intensity = 0.5
	bloom.Size = 26
	bloom.Threshold = 1.5

	local cc: ColorCorrectionEffect = effect("ColorCorrectionEffect", "BaseColor")
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.Brightness = 0.01
	cc.TintColor = Color3.fromRGB(255, 250, 240)

	local rays: SunRaysEffect = effect("SunRaysEffect", "SunRays")
	rays.Intensity = 0.07
	rays.Spread = 0.7

	local dof: DepthOfFieldEffect = effect("DepthOfFieldEffect", "FarBlur")
	dof.FarIntensity = 0.1
	dof.FocusDistance = 50
	dof.InFocusRadius = 90
	dof.NearIntensity = 0

	-- volumetric clouds (the client darkens/thickens them with the weather)
	local terrain = Workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.45
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain
end

-- ===================================================================== terrain

local function setupTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 160, 68))
		terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(122, 92, 62))
		terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(82, 150, 58))
		terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(176, 138, 92))
		terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(232, 212, 160))
		terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(176, 168, 156))
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(128, 124, 122))
	end)
	terrain.WaterColor = Color3.fromRGB(38, 128, 176)
	terrain.WaterTransparency = 0.5
	terrain.WaterReflectance = 0.4
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8

	-- The smooth-terrain surface sits half a voxel (2 studs) above the last FULL cell, so a block filled up to
	-- y = 0 used to bury the garden tiles under 2 studs of grass. Stopping the block at y = -2 leaves the top
	-- voxel layer half full, which puts the visible ground exactly at y = 0 (tests raycast it).
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(1400, 12, 1400), Enum.Material.Grass)
	terrain:FillBlock(CFrame.new(0, -16, 0), Vector3.new(1400, 4, 1400), Enum.Material.Rock)
	-- darker meadow patches break up the flat green (repainted in place: flush with the ground, no bumps)
	for _ = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(70, 230)
		Props.paintDisc(Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), rng:NextNumber(12, 22), Enum.Material.LeafyGrass)
	end
	-- rolling hills around the farmland
	for i = 1, 36 do
		local a = (i / 36) * math.pi * 2
		local d = 330 + rng:NextNumber(-20, 30)
		terrain:FillBall(Vector3.new(math.cos(a) * d, -10, math.sin(a) * d), rng:NextNumber(55, 85), Enum.Material.Grass)
	end
	-- distant rocky peaks with snow caps, softened by the haze
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2 + 0.2
		local d = 520 + rng:NextNumber(-30, 40)
		local r = rng:NextNumber(90, 125)
		local pos = Vector3.new(math.cos(a) * d, -25, math.sin(a) * d)
		terrain:FillBall(pos, r, Enum.Material.Rock)
		terrain:FillBall(pos + Vector3.new(0, r * 0.62, 0), r * 0.45, Enum.Material.Snow)
		terrain:FillBall(pos + Vector3.new(rng:NextNumber(-40, 40), -r * 0.35, rng:NextNumber(-40, 40)), r * 0.8, Enum.Material.Grass)
	end

	-- dirt paths from the square to each gate, and bare earth under every plot + farmhouse
	-- (terrain grass blades would poke through the lawn part and the house floor)
	local width, depth = WorldLayout.plotSize()
	local back = depth / 2 + WorldLayout.HOUSE_OFFSET + WorldLayout.HOUSE_HALF
	for i = 1, WorldLayout.PLOT_COUNT do
		local cx, cz = WorldLayout.plotCenter(i)
		Props.paint(Vector3.new(cx, 0, cz) * 0.5, WorldLayout.PLOT_DISTANCE / 2 + 8, function(x, z, layer)
			if layer == 2 and WorldLayout.onPath(i, x, z, -3) then
				return Enum.Material.Ground, nil
			end
			return nil, nil
		end)
		Props.paint(Vector3.new(cx, 0, cz), depth + WorldLayout.HOUSE_OFFSET + 20, function(x, z, layer)
			local lx, lz = WorldLayout.toPlotLocal(i, x, z)
			if layer == 2 and math.abs(lx) <= width / 2 + 2 and lz >= -depth / 2 - 1 and lz <= back + 1 then
				return Enum.Material.Mud, nil
			end
			return nil, nil
		end)
	end

	-- market square on top: cobbles with a brick ring around the fountain
	Props.paintDisc(Vector3.zero, WorldLayout.PLAZA_RADIUS, Enum.Material.Cobblestone)
	Props.paintDisc(Vector3.zero, 20, Enum.Material.Brick)
end

-- ===================================================================== world

function WorldBuilder.build(): World
	setupTerrain()
	setupLighting()

	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") or child.Name == "Baseplate" then
			child:Destroy()
		end
	end

	local hub = Instance.new("Folder")
	hub.Name = "Hub"

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, -26)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = hub
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	Props.fountain(hub, CFrame.new(0, 0, 0))

	-- shops around the square, facing the center
	local function around(angleDeg: number, dist: number): CFrame
		local a = math.rad(angleDeg)
		local pos = Vector3.new(math.sin(a) * dist, 0, math.cos(a) * dist)
		return CFrame.lookAt(pos, Vector3.new(0, 0, 0)) * CFrame.Angles(0, math.pi, 0)
	end
	local cream = Color3.fromRGB(250, 246, 234)
	local seedShop = stall(hub, "SeedShop", "seeds", "world.seedsSign", around(-40, 34), Color3.fromRGB(70, 180, 80), cream, "world.promptSeeds", "🌱")
	local sellStand = stall(hub, "SellStand", "sell", "world.sellSign", around(40, 34), Color3.fromRGB(240, 180, 40), cream, "world.promptSell", "💰")
	local upgradeShop = stall(hub, "UpgradeShop", "upgrades", "world.upgradesSign", around(-140, 34), Color3.fromRGB(60, 130, 230), cream, "world.promptUpgrades", "⚡")
	local robuxShop = stall(hub, "RobuxShop", "store", "world.storeSign", around(140, 34), Color3.fromRGB(200, 70, 220), Color3.fromRGB(255, 220, 90), "world.promptStore", "💎")

	-- global leaderboard: east side of the square (no path starts there), facing the fountain
	local boardCF = CFrame.lookAt(Vector3.new(41, 0, 0), Vector3.new(0, 0, 0))
	local board = P(hub, "Leaderboard", Vector3.new(18, 20, 1), boardCF * CFrame.new(0, 13, 0), WOOD_DARK, Enum.Material.WoodPlanks)
	for _, x in { -9.4, 9.4 } do
		P(hub, "BoardLeg", Vector3.new(1.3, 24, 1.3), boardCF * CFrame.new(x, 12, 0), WOOD, Enum.Material.Wood)
	end
	P(hub, "BoardFoot", Vector3.new(21, 1, 3), boardCF * CFrame.new(0, 0.5, 0), STONE, Enum.Material.Slate)
	Props.gableRoof(hub, boardCF * CFrame.new(0, 23.5, 0), 23, 5, 2.6, Color3.fromRGB(190, 70, 60), Enum.Material.Wood, DECOR)
	for _, x in { -8, 8 } do
		B(hub, "BoardLamp", Vector3.one * 1.2, boardCF * CFrame.new(x, 24.6, -2.4), Color3.fromRGB(255, 225, 150), Enum.Material.Neon, TINY)
	end

	-- west side: the giant carrot, the kingdom's mascot statue
	Props.carrotStatue(hub, CFrame.lookAt(Vector3.new(-40, 0, 0), Vector3.new(0, 0, 0)))

	-- lamps with bunting between them, benches and planters
	local lampCount = 12
	local lampTops: { Vector3 } = {}
	for i = 1, lampCount do
		local a = ((i - 0.5) / lampCount) * math.pi * 2
		local pos = Vector3.new(math.cos(a) * 44, 0, math.sin(a) * 44)
		Props.lamp(hub, pos, i % 2 == 0)
		lampTops[i] = pos + Vector3.new(0, 8.8, 0)
	end
	local flagColors = { Color3.fromRGB(240, 80, 80), Color3.fromRGB(255, 200, 60), Color3.fromRGB(90, 190, 100), Color3.fromRGB(80, 150, 240), Color3.fromRGB(230, 110, 200) }
	for i = 1, lampCount do
		Props.bunting(hub, lampTops[i], lampTops[i % lampCount + 1], flagColors, i)
	end
	for _, deg in { 0, 60, 120, 180, 240, 300 } do
		local a = math.rad(deg + 15)
		local pos = Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25)
		Props.bench(hub, CFrame.lookAt(pos, Vector3.new(0, 0, 0)))
	end
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2 + math.rad(7)
		local pos = Vector3.new(math.cos(a) * 47.5, 0, math.sin(a) * 47.5)
		-- keep the six path mouths open
		local open = true
		for p = 1, WorldLayout.PLOT_COUNT do
			if WorldLayout.onPath(p, pos.X, pos.Z, 1.5) then
				open = false
			end
		end
		if open then
			Props.planter(hub, CFrame.lookAt(pos, Vector3.new(0, 0, 0)))
		end
	end

	hub.Parent = Workspace

	-- plots in a ring, each facing the hub
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	local plots = {}
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "Decoration"
	local _, depth = WorldLayout.plotSize()
	for i = 1, WorldLayout.PLOT_COUNT do
		local cx, cz = WorldLayout.plotCenter(i)
		local pos = Vector3.new(cx, 0, cz)
		-- local -Z must face the hub
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		plots[i] = buildPlot(plotsFolder, i, cf)
		-- stones and flowers along the path edges
		local dir = pos.Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local from, to = WorldLayout.PLAZA_RADIUS + 3, WorldLayout.PLOT_DISTANCE - depth / 2 - 6
		local n = 5
		for k = 0, n do
			local along = from + (to - from) * (k / n)
			for _, s in { -1, 1 } do
				local p = dir * along + side * (s * (WorldLayout.PATH_HALF_WIDTH + 1.2))
				if (k + (if s > 0 then 1 else 0)) % 2 == 0 then
					Props.rock(decoFolder, p, rng:NextNumber(0.9, 1.5))
				else
					Props.flowerPatch(decoFolder, p, 1.4, 4)
				end
			end
		end
	end
	plotsFolder.Parent = Workspace

	local wildFolder = Instance.new("Folder")
	wildFolder.Name = "WildPatch"
	local wildNodes: { Part } = {}

	-- landmarks in the gaps between plots
	for _, f in WorldLayout.Features do
		local fx, fz = WorldLayout.featureCenter(f)
		local cf = CFrame.lookAt(Vector3.new(fx, 0, fz), Vector3.new(0, 0, 0))
		local m = Instance.new("Model")
		m.Name = f.id
		if f.id == "Pond" then
			Props.pond(m, cf, f.radius)
		elseif f.id == "Windmill" then
			Props.windmill(m, cf)
		elseif f.id == "HayField" then
			Props.hayField(m, cf)
		elseif f.id == "Barn" then
			Props.barn(m, cf)
		elseif f.id == "PumpkinPatch" then
			Props.pumpkinPatch(m, cf)
			-- the Wild Patch lives here: six mounds where rare seeds regrow every hour (Services/Wild)
			for k = 1, Wild.NODES do
				local a = (k / Wild.NODES) * math.pi * 2 + 0.2
				local node = P(wildFolder, "WildNode_" .. k, Vector3.new(6, 0.5, 6), cf * CFrame.new(math.cos(a) * 16, 0.25, math.sin(a) * 16), Color3.fromRGB(74, 50, 34), Enum.Material.Ground, { CanCollide = false })
				node:SetAttribute("Index", k)
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "Prompt"
				Locale.stamp(prompt, "wild.prompt", nil, "ActionText")
				Locale.stamp(prompt, "wild.sign", nil, "ObjectText")
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = node
				wildNodes[k] = node
			end
			local signCF = cf * CFrame.new(0, 0, -21)
			local sign = P(wildFolder, "WildSign", Vector3.new(11, 2.6, 0.5), signCF * CFrame.new(0, 6.2, 0), Color3.fromRGB(86, 150, 78), nil, { CanQuery = false })
			P(wildFolder, "WildSignFrame", Vector3.new(11.6, 3.2, 0.3), signCF * CFrame.new(0, 6.2, 0), WOOD_DARK, Enum.Material.Wood, DECOR)
			for _, x in { -4.6, 4.6 } do
				P(wildFolder, "WildSignPost", Vector3.new(0.7, 5, 0.7), signCF * CFrame.new(x, 2.5, 0), WOOD_DARK, Enum.Material.Wood, { CanQuery = false })
			end
			Locale.stamp(label(sign, "", Enum.NormalId.Front, nil), "wild.sign")
			Locale.stamp(label(sign, "", Enum.NormalId.Back, nil), "wild.sign")
			local clock = Instance.new("BillboardGui")
			clock.Name = "ClockGui"
			clock.Size = UDim2.fromScale(26, 1.8)
			clock.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
			clock.LightInfluence = 0
			clock.MaxDistance = 140
			local clockText = Instance.new("TextLabel")
			clockText.Name = "Clock"
			clockText.Size = UDim2.fromScale(1, 1)
			clockText.BackgroundTransparency = 1
			clockText.TextScaled = true
			clockText.Font = Enum.Font.FredokaOne
			clockText.TextColor3 = Color3.fromRGB(255, 240, 150)
			clockText.Text = ""
			local clockStroke = Instance.new("UIStroke")
			clockStroke.Thickness = 2.5
			clockStroke.Color = Color3.fromRGB(40, 30, 20)
			clockStroke.Parent = clockText
			clockText.Parent = clock
			clock.Parent = sign
		elseif f.id == "Tractor" then
			Props.tractorYard(m, cf)
		end
		m.Parent = decoFolder
	end

	-- nature: trees, bushes, rocks and flower patches wherever the layout says the ground is free
	local placedTrees = 0
	for _ = 1, 260 do
		if placedTrees >= 120 then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		-- bias toward the outer ring so the farmland stays open and the horizon looks wooded
		local d = 62 + (300 - 62) * math.sqrt(rng:NextNumber())
		local x, z = math.cos(a) * d, math.sin(a) * d
		if WorldLayout.isClear(x, z, 6) then
			Props.tree(decoFolder, Vector3.new(x, 0, z), rng:NextNumber(0.85, 1.5))
			placedTrees += 1
		end
	end
	local placedSmall = 0
	for _ = 1, 300 do
		if placedSmall >= 110 then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(52, 230)
		local x, z = math.cos(a) * d, math.sin(a) * d
		if WorldLayout.isClear(x, z, 2.5) then
			local roll = rng:NextNumber()
			local pos = Vector3.new(x, 0, z)
			if roll < 0.4 then
				Props.bush(decoFolder, pos, rng:NextNumber(0.9, 1.6))
			elseif roll < 0.62 then
				Props.rock(decoFolder, pos, rng:NextNumber(1.4, 3))
			elseif roll < 0.72 then
				Props.log(decoFolder, pos)
			else
				Props.flowerPatch(decoFolder, pos, 3.2, 8)
			end
			placedSmall += 1
		end
	end

	-- hot-air balloons drifting over the hills (bobbed on the client: tag CK_Float)
	Props.balloon(decoFolder, Vector3.new(190, 120, -150), Color3.fromRGB(240, 80, 80), Color3.fromRGB(255, 240, 220))
	Props.balloon(decoFolder, Vector3.new(-230, 150, 120), Color3.fromRGB(80, 150, 240), Color3.fromRGB(255, 210, 80))
	Props.balloon(decoFolder, Vector3.new(40, 170, 270), Color3.fromRGB(160, 100, 230), Color3.fromRGB(120, 230, 160))

	decoFolder.Parent = Workspace
	wildFolder.Parent = Workspace

	return {
		wildNodes = wildNodes,
		plots = plots,
		hub = hub,
		sellStand = sellStand,
		seedShop = seedShop,
		upgradeShop = upgradeShop,
		robuxShop = robuxShop,
		board = board,
	}
end

return WorldBuilder
