--!strict
-- The wheel of one table, built on this client: a pie of wedge parts welded to an anchored
-- hub (spinning = setting one CFrame), an icon + name on every slot, pegs on the rim and a
-- fixed pointer with a flapper that ticks against the pegs. Skins recolour it; the lite
-- profile halves the part count. It only ever shows what the server already decided.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Lang = require(script.Parent.Parent.Lang)

local Wheel = {}
Wheel.__index = Wheel

export type Wheel = typeof(setmetatable(
	{} :: {
		origin: CFrame,
		folder: Folder,
		hub: Part,
		wedges: { { Part } }, -- per slot
		labels: { TextLabel },
		names: { TextLabel },
		plates: { Part },
		pegs: { Part },
		flapper: Part,
		flapperBase: CFrame,
		slots: { string },
		skin: string,
		lite: boolean,
		hidden: boolean,
		angle: number,
		lastTick: number,
		kick: number,
		highlight: number?,
		parts: number,
	},
	Wheel
))

local R = Layout.WheelRadius
local THICK = Layout.WheelThickness

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function newPart(parent: Instance, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function weld(hub: BasePart, p: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = hub
	w.Part1 = p
	w.Parent = p
end

-- One right-triangle wedge lying flat: right angle at the chord midpoint M, one leg to the
-- centre, the other along the chord (dir = +1 / -1).
local function wedgeCFrame(base: CFrame, phi: number, h: number, b: number, dir: number): CFrame
	local u = Vector3.new(math.sin(phi), 0, -math.cos(phi)) -- outward
	local t = Vector3.new(math.cos(phi), 0, math.sin(phi)) * dir -- along the chord
	local centre = u * (h / 2) + t * (b / 2)
	local x = t:Cross(u)
	return base * CFrame.fromMatrix(centre, x, t, u)
end

function Wheel.skinLook(skinId: string): { [string]: any }
	local item = Config.CosmeticById[skinId] or Config.CosmeticById.w_classic
	return (item.look or Config.CosmeticById.w_classic.look) :: { [string]: any }
end

-- Colour of a slot under a skin (alternate slots are a touch lighter so neighbours read apart).
function Wheel.slotColor(outcome: string, skinId: string, index: number): Color3
	local look = Wheel.skinLook(skinId)
	local def = Config.OutcomeById[outcome]
	local c = if def then rgb(def.color) else Color3.fromRGB(80, 80, 110)
	c = c:Lerp(rgb(look.tint), look.mix)
	if index % 2 == 0 then
		c = c:Lerp(Color3.new(1, 1, 1), 0.1)
	end
	return c
end

function Wheel.new(origin: CFrame, parent: Instance, name: string): Wheel
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.CastShadow = false
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(THICK + 0.5, 3.4, 3.4)
	hub.Material = Enum.Material.SmoothPlastic
	hub.CFrame = Layout.wheelCFrame(origin) * CFrame.Angles(0, 0, math.rad(90))
	hub.Parent = folder
	local self = setmetatable({
		origin = origin,
		folder = folder,
		hub = hub,
		wedges = {},
		labels = {},
		names = {},
		plates = {},
		pegs = {},
		flapper = nil :: any,
		flapperBase = CFrame.new(),
		slots = {},
		skin = "",
		lite = false,
		hidden = false,
		angle = 0,
		lastTick = 0,
		kick = 0,
		highlight = nil,
		parts = 1,
	}, Wheel)
	self:buildPointer()
	return self
end

function Wheel.buildPointer(self: Wheel)
	local origin = self.origin
	local function fixed(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
		local p = newPart(self.folder, name)
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		self.parts += 1
		return p
	end
	local rimPos = Layout.polar(0, R + 1.5, Layout.WheelY)
	fixed("PointerPost", Vector3.new(1.1, 3.4, 1.1), origin * CFrame.new(rimPos + Vector3.new(0, 0.4, 0)), Color3.fromRGB(240, 240, 250))
	fixed("PointerCap", Vector3.new(1.7, 0.6, 1.7), origin * CFrame.new(rimPos + Vector3.new(0, 2.3, 0)), Color3.fromRGB(255, 205, 60), Enum.Material.Neon)
	-- the flapper: a wedge pointing at the wheel, hinged on the post
	local flap = Instance.new("WedgePart")
	flap.Name = "Flapper"
	flap.Anchored = true
	flap.CanCollide = false
	flap.CanQuery = false
	flap.CanTouch = false
	flap.CastShadow = false
	flap.Material = Enum.Material.Neon
	flap.Color = Color3.fromRGB(255, 70, 70)
	flap.Size = Vector3.new(0.7, 1.5, 2.6)
	-- wedge slope faces down; its thin edge points at the wheel centre (+Z of the table)
	self.flapperBase = origin * CFrame.new(Layout.polar(0, R + 0.2, Layout.WheelY + 1.35)) * CFrame.Angles(0, math.pi, 0)
	flap.CFrame = self.flapperBase
	flap.Parent = self.folder
	self.flapper = flap :: any
	self.parts += 1
end

-- (Re)builds the pie for a slot list. Cheap when nothing structural changed.
function Wheel.setSlots(self: Wheel, slots: { string }, skinId: string, lite: boolean, hidden: boolean)
	local n = #slots
	local rebuild = n ~= #self.slots or lite ~= self.lite or #self.wedges == 0
	self.slots = table.clone(slots)
	self.hidden = hidden
	local look = Wheel.skinLook(skinId)
	if rebuild then
		for _, c in self.folder:GetChildren() do
			if c ~= self.hub and c.Name ~= "PointerPost" and c.Name ~= "PointerCap" and c.Name ~= "Flapper" then
				c:Destroy()
			end
		end
		self.wedges, self.labels, self.names, self.plates, self.pegs = {}, {}, {}, {}, {}
		self.parts = 4
		self.lite = lite
		local saved = self.angle
		self:setAngle(0)
		local base = Layout.wheelCFrame(self.origin)
		-- rim disc under the pie
		local rim = newPart(self.folder, "Rim")
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(THICK - 0.1, (R + 0.55) * 2, (R + 0.55) * 2)
		rim.CFrame = base * CFrame.new(0, -0.06, 0) * CFrame.Angles(0, 0, math.rad(90))
		weld(self.hub, rim)
		self.parts += 1
		local sub = if lite then 1 else 2
		local alpha = math.pi / (n * sub)
		local h, b = R * math.cos(alpha), R * math.sin(alpha)
		for k = 1, n do
			local list = {}
			for j = 1, sub do
				local phi = ((k - 1) + (j - 0.5) / sub) / n * math.pi * 2
				for dir = -1, 1, 2 do
					local w = Instance.new("WedgePart")
					w.Name = "Slot" .. k
					w.Anchored = false
					w.CanCollide = false
					w.CanQuery = false
					w.CanTouch = false
					w.CastShadow = false
					w.Massless = true
					w.Size = Vector3.new(THICK, b, h)
					w.CFrame = wedgeCFrame(base, phi, h, b, dir)
					w.Parent = self.folder
					weld(self.hub, w)
					table.insert(list, w :: any)
					self.parts += 1
				end
			end
			self.wedges[k] = list
			-- icon plate on top of the slot
			local mid = (k - 0.5) / n * math.pi * 2
			local plate = newPart(self.folder, "Plate" .. k)
			plate.Transparency = 1
			plate.Size = Vector3.new(3.4, 0.05, 4.4)
			-- plate -Z points at the rim so the icon reads upright from outside the wheel
			plate.CFrame = base * CFrame.new(Layout.polar(mid, R * 0.64, THICK / 2 + 0.04)) * CFrame.Angles(0, -mid, 0)
			weld(self.hub, plate)
			self.plates[k] = plate
			self.parts += 1
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 36
			gui.LightInfluence = 0
			gui.Brightness = 1.4
			gui.Parent = plate
			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromScale(1, 0.62)
			icon.Position = UDim2.fromScale(0, 0.04)
			icon.Font = Enum.Font.FredokaOne
			icon.TextScaled = true
			icon.TextColor3 = Color3.new(1, 1, 1)
			icon.Parent = gui
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.BackgroundTransparency = 1
			nameLabel.Size = UDim2.fromScale(1, 0.3)
			nameLabel.Position = UDim2.fromScale(0, 0.68)
			nameLabel.Font = Enum.Font.LuckiestGuy
			nameLabel.TextScaled = true
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.Parent = gui
			local st = Instance.new("UIStroke")
			st.Thickness = 3
			st.Color = Color3.fromRGB(10, 10, 28)
			st.Parent = nameLabel
			self.labels[k] = icon
			self.names[k] = nameLabel
			-- peg on the boundary before this slot
			local peg = newPart(self.folder, "Peg" .. k)
			peg.Shape = Enum.PartType.Ball
			peg.Size = Vector3.new(0.7, 0.7, 0.7)
			peg.Material = Enum.Material.Neon
			peg.CFrame = base * CFrame.new(Layout.polar((k - 1) / n * math.pi * 2, R + 0.05, THICK / 2 + 0.25))
			weld(self.hub, peg)
			self.pegs[k] = peg
			self.parts += 1
		end
		-- cap
		local cap = newPart(self.folder, "Cap")
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(2.6, 2.6, 2.6)
		cap.Material = Enum.Material.Neon
		cap.CFrame = base * CFrame.new(0, THICK / 2 + 0.3, 0)
		weld(self.hub, cap)
		self.parts += 1
		self:setAngle(saved)
	end
	self.skin = skinId
	self.highlight = nil
	-- colours
	local material = (Enum.Material :: any)[look.material] or Enum.Material.SmoothPlastic
	self.hub.Color = rgb(look.hub)
	for _, c in self.folder:GetChildren() do
		if c.Name == "Rim" and c:IsA("BasePart") then
			c.Color = rgb(look.rim)
		elseif c.Name == "Cap" and c:IsA("BasePart") then
			c.Color = rgb(look.hub)
		end
	end
	for k = 1, n do
		local color = if hidden then (if k % 2 == 0 then Color3.fromRGB(44, 40, 78) else Color3.fromRGB(34, 30, 62)) else Wheel.slotColor(slots[k], skinId, k)
		for _, w in self.wedges[k] do
			w.Color = color
			w.Material = if hidden then Enum.Material.SmoothPlastic else material
			w.Transparency = if material == Enum.Material.ForceField or material == Enum.Material.Glass then 0.1 else 0
		end
		self.pegs[k].Color = rgb(look.trim)
		local def = Config.OutcomeById[slots[k]]
		self.labels[k].Text = if hidden then "❓" else (if def then def.icon else "?")
		self.names[k].Text = if hidden then "" else Lang.upper(Lang.t("out." .. slots[k]))
	end
end

-- Wheel angle in slots (see Layout.wheelYaw).
function Wheel.setAngle(self: Wheel, angle: number)
	self.angle = angle
	local n = math.max(1, #self.slots)
	self.hub.CFrame = Layout.wheelCFrame(self.origin) * CFrame.Angles(0, Layout.wheelYaw(angle, n), 0) * CFrame.Angles(0, 0, math.rad(90))
end

-- 1-based slot under the pointer for the current angle.
function Wheel.slotAtPointer(self: Wheel): number
	local n = math.max(1, #self.slots)
	return math.floor(self.angle % n) + 1
end

-- Geometric check used by the playtest: which slot's plate is nearest the pointer.
function Wheel.nearestPlate(self: Wheel): number
	local pointer = self.origin:PointToWorldSpace(Layout.polar(0, R * 0.64, Layout.WheelY))
	local best, bestD = 1, math.huge
	for k, plate in self.plates do
		local d = (plate.Position - pointer).Magnitude
		if d < bestD then
			best, bestD = k, d
		end
	end
	return best
end

-- Returns how many peg boundaries were crossed since the last call (for ticks).
function Wheel.ticksSince(self: Wheel): number
	local now = math.floor(self.angle)
	local d = now - self.lastTick
	self.lastTick = now
	return math.max(0, d)
end

function Wheel.resetTicks(self: Wheel)
	self.lastTick = math.floor(self.angle)
end

-- The flapper gets knocked by a peg and springs back.
function Wheel.kickFlapper(self: Wheel, strength: number)
	self.kick = math.min(1, self.kick + strength)
end

function Wheel.stepFlapper(self: Wheel, dt: number)
	if self.kick > 0.001 then
		self.kick *= math.exp(-dt * 14)
		self.flapper.CFrame = self.flapperBase * CFrame.Angles(0, 0, 0) * CFrame.new(0, 0, 0) * CFrame.Angles(-self.kick * 0.5, self.kick * 0.35, 0)
	elseif self.kick ~= 0 then
		self.kick = 0
		self.flapper.CFrame = self.flapperBase
	end
end

-- Lights one slot up and dims the rest (nil restores).
function Wheel.setHighlight(self: Wheel, slot: number?)
	if self.highlight == slot then
		return
	end
	self.highlight = slot
	for k, list in self.wedges do
		local base = if self.hidden then Color3.fromRGB(38, 34, 70) else Wheel.slotColor(self.slots[k], self.skin, k)
		local color = base
		if slot then
			color = if k == slot then base:Lerp(Color3.new(1, 1, 1), 0.35) else base:Lerp(Color3.fromRGB(8, 8, 20), 0.72)
		end
		for _, w in list do
			w.Color = color
			if slot then
				w.Material = if k == slot then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
	if not slot then
		-- restore materials
		local look = Wheel.skinLook(self.skin)
		local material = (Enum.Material :: any)[look.material] or Enum.Material.SmoothPlastic
		for _, list in self.wedges do
			for _, w in list do
				w.Material = if self.hidden then Enum.Material.SmoothPlastic else material
			end
		end
	end
end

-- Blackout: reveal what the slots were hiding.
function Wheel.reveal(self: Wheel)
	if self.hidden then
		self:setSlots(self.slots, self.skin, self.lite, false)
	end
end

function Wheel.slotWorld(self: Wheel, slot: number): Vector3
	local plate = self.plates[slot]
	return if plate then plate.Position else self.hub.Position
end

function Wheel.destroy(self: Wheel)
	self.folder:Destroy()
end

return Wheel
