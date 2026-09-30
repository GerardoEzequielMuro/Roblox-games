--!strict
-- Trails, effects, coils (speed / gravity) and the coins shop. All prices and ownership are
-- checked on the server; the client only asks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local Cosmetics = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local trailById: { [string]: Config.Trail } = {}
for _, t in Config.Trails do
	trailById[t.id] = t
end
local effectById: { [string]: Config.Effect } = {}
for _, e in Config.Effects do
	effectById[e.id] = e
end

local function colorSeq(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	for i, c in colors do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(kps)
end

local function clearTagged(char: Model, name: string)
	for _, d in char:GetDescendants() do
		if d.Name == name then
			d:Destroy()
		end
	end
end

local function trailColors(player: Player, p: Data.Profile): { Color3 }?
	local id = p.equippedTrail
	if id == "rebirth" then
		if p.wins <= 0 then
			return nil
		end
		local c = Config.RebirthColors[((p.wins - 1) % #Config.RebirthColors) + 1]
		return { c, c:Lerp(Color3.new(1, 1, 1), 0.5) }
	end
	local t = trailById[id]
	if not t then
		return nil
	end
	if t.pass and not Session.hasPass(player, t.pass) then
		return nil
	end
	if not t.pass and not p.trails[id] then
		return nil
	end
	return t.colors
end

function Cosmetics.applyTrail(player: Player)
	local char = player.Character
	local p = Data.get(player)
	if not char or not p then
		return
	end
	clearTagged(char, "SkyTrail")
	clearTagged(char, "SkyTrailA0")
	clearTagged(char, "SkyTrailA1")
	local colors = trailColors(player, p)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not colors or not root then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "SkyTrailA0"
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "SkyTrailA1"
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SkyTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = colorSeq(colors)
	trail.Lifetime = 0.6
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.FaceCamera = true
	trail.Parent = root
end

function Cosmetics.applyEffect(player: Player)
	local char = player.Character
	local p = Data.get(player)
	if not char or not p then
		return
	end
	clearTagged(char, "SkyEffect")
	local e = effectById[p.equippedEffect]
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not e or not root or not p.effects[e.id] then
		return
	end
	local inst: Instance
	if e.kind == "Sparkles" then
		local s = Instance.new("Sparkles")
		s.SparkleColor = e.color
		inst = s
	elseif e.kind == "Smoke" then
		local s = Instance.new("Smoke")
		s.Color = e.color
		s.Opacity = 0.15
		s.RiseVelocity = 2
		s.Size = 0.8
		inst = s
	elseif e.kind == "Fire" then
		local f = Instance.new("Fire")
		f.Color = e.color
		f.SecondaryColor = Color3.fromRGB(255, 230, 90)
		f.Size = 3
		f.Heat = 6
		inst = f
	else
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = SPARKLES
		pe.Color = ColorSequence.new(e.color)
		pe.Rate = 14
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.5, 0)
		pe.LightEmission = 1
		inst = pe
	end
	inst.Name = "SkyEffect"
	inst.Parent = root
end

-- Speed coil: WalkSpeed. Gravity coil: a VectorForce cancelling part of gravity.
-- (The character is simulated by its owner's client; forces/properties created here replicate.)
function Cosmetics.applyCoils(player: Player)
	local char = player.Character
	local p = Data.get(player)
	if not char or not p then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	-- the classic obby jump, whatever the avatar or the place defaults say
	hum.UseJumpPower = true
	hum.JumpPower = Config.JumpPower
	hum.WalkSpeed = if Session.speedOn(player, p) then Config.SpeedCoilWalkSpeed else Config.WalkSpeed
	-- abilities run on the owner's client; these attributes tell it what it may do
	player:SetAttribute("AirJumps", Session.airJumps(player, p))
	player:SetAttribute("Dash", Perks.unlocked(p.best) and p.perks.dash == true)
	clearTagged(char, "GravityCoil")
	if Session.gravityOn(player, p) then
		local att = Instance.new("Attachment")
		att.Name = "GravityCoil"
		att.Parent = root
		local vf = Instance.new("VectorForce")
		vf.Name = "GravityCoil"
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		local mass = root.AssemblyMass
		vf.Force = Vector3.new(0, mass * Workspace.Gravity * (1 - Config.GravityCoilFactor), 0)
		vf.Parent = root
	end
end

local function weldTo(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local function bit(parent: Instance, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, to: BasePart): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- weld (unanchored, massless, no collision) BEFORE it enters the character: a bare Part in a
	-- character for even one physics step can push or trip the avatar
	weldTo(p, to)
	p.Parent = parent
	return p
end

-- Gift cosmetics worn by the character: the shoulder cloud (stage 200), the crown (stage 1000)
-- and the body glow picked in the Winner's Lounge (or the rainbow glow of stage 700).
function Cosmetics.applyExtras(player: Player)
	local char = player.Character
	local p = Data.get(player)
	if not char or not p then
		return
	end
	for _, name in { "SkyPet", "SkyCrown", "SkyGlow" } do
		local old = char:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	local head = char:FindFirstChild("Head") :: BasePart?
	if p.gifts["2"] and torso then
		local pet = Instance.new("Model")
		pet.Name = "SkyPet"
		pet.Parent = char
		local at = torso.CFrame * CFrame.new(1.7, 1.7, 0.2)
		local white = Color3.fromRGB(255, 255, 255)
		bit(pet, Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), at, white, Enum.Material.SmoothPlastic, torso)
		bit(pet, Enum.PartType.Ball, Vector3.new(0.8, 0.8, 0.8), at * CFrame.new(-0.5, -0.12, 0), white, Enum.Material.SmoothPlastic, torso)
		bit(pet, Enum.PartType.Ball, Vector3.new(0.8, 0.8, 0.8), at * CFrame.new(0.5, -0.12, 0), white, Enum.Material.SmoothPlastic, torso)
		for _, x in { -0.2, 0.2 } do
			bit(pet, Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), at * CFrame.new(x, 0.08, -0.52), Color3.fromRGB(40, 40, 60), Enum.Material.SmoothPlastic, torso)
		end
	end
	if p.gifts["10"] and head then
		local crown = Instance.new("Model")
		crown.Name = "SkyCrown"
		crown.Parent = char
		local gold = Color3.fromRGB(255, 205, 70)
		local at = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0)
		bit(crown, Enum.PartType.Cylinder, Vector3.new(0.35, 1.5, 1.5), at * CFrame.Angles(0, 0, math.pi / 2), gold, Enum.Material.Neon, head)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			bit(crown, Enum.PartType.Block, Vector3.new(0.26, 0.6, 0.26), at * CFrame.new(math.cos(a) * 0.62, 0.42, math.sin(a) * 0.62), gold, Enum.Material.Neon, head)
		end
	end
	local glow = Perks.get(tostring(p.perks.glow or ""))
	if glow and glow.kind == "glow" and Perks.unlocked(p.best) and (not glow.gift or p.gifts[tostring(glow.gift)]) then
		local c = glow.color or { 255, 255, 255 }
		local h = Instance.new("Highlight")
		h.Name = "SkyGlow"
		h.FillColor = Color3.fromRGB(c[1], c[2], c[3])
		h.OutlineColor = Color3.fromRGB(c[1], c[2], c[3])
		h.FillTransparency = 0.72
		h.OutlineTransparency = 0.05
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h:SetAttribute("Rainbow", glow.id == "glow_rainbow") -- clients cycle the hue
		h.Parent = char
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetAttribute("JumpFx", if Perks.unlocked(p.best) then tostring(p.perks.jumpfx or "") else "")
	end
end

function Cosmetics.applyAll(player: Player)
	Cosmetics.applyTrail(player)
	Cosmetics.applyEffect(player)
	Cosmetics.applyCoils(player)
	Cosmetics.applyExtras(player)
	player:SetAttribute("VIP", Session.hasPass(player, "VIP"))
end

function Cosmetics.init()
	Remotes.handle("BuyTrail", function(player, payload)
		local p = Data.get(player)
		local t = trailById[tostring(payload.id)]
		if not p or not t or t.pass or t.exclusive then
			return false, Remotes.M("err.not_for_sale")
		end
		if p.trails[t.id] then
			return false, Remotes.M("err.already_owned")
		end
		if p.coins < t.price then
			return false, Remotes.M("err.not_enough_coins")
		end
		p.coins -= t.price
		p.trails[t.id] = true
		p.equippedTrail = t.id
		Cosmetics.applyTrail(player)
		Session.push(player)
		return true, Remotes.M("msg.bought_trail", { name = Remotes.M("trail." .. t.id) })
	end)
	Remotes.handle("EquipTrail", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		local id = tostring(payload.id or "")
		if id ~= "" and id ~= "rebirth" then
			local t = trailById[id]
			if not t then
				return false, Remotes.M("err.unknown_trail")
			end
			if t.pass and not Session.hasPass(player, t.pass) then
				return false, Remotes.M("err.requires_pass", { pass = Remotes.M("store." .. t.pass .. ".name") })
			end
			if not t.pass and not p.trails[id] then
				return false, Remotes.M("err.not_owned")
			end
		elseif id == "rebirth" and p.wins <= 0 then
			return false, Remotes.M("err.win_once")
		end
		p.equippedTrail = if p.equippedTrail == id then "" else id
		Cosmetics.applyTrail(player)
		Session.push(player)
		return true
	end)
	Remotes.handle("BuyEffect", function(player, payload)
		local p = Data.get(player)
		local e = effectById[tostring(payload.id)]
		if not p or not e or e.exclusive then
			return false, Remotes.M("err.not_for_sale")
		end
		if p.effects[e.id] then
			return false, Remotes.M("err.already_owned")
		end
		if p.coins < e.price then
			return false, Remotes.M("err.not_enough_coins")
		end
		p.coins -= e.price
		p.effects[e.id] = true
		p.equippedEffect = e.id
		Cosmetics.applyEffect(player)
		Session.push(player)
		return true, Remotes.M("msg.bought", { name = Remotes.M("effect." .. e.id) })
	end)
	Remotes.handle("EquipEffect", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		local id = tostring(payload.id or "")
		if id ~= "" and not p.effects[id] then
			return false, Remotes.M("err.not_owned")
		end
		p.equippedEffect = if p.equippedEffect == id then "" else id
		Cosmetics.applyEffect(player)
		Session.push(player)
		return true
	end)
	Remotes.handle("SetLanguage", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		local lang = tostring(payload.lang or "")
		if lang ~= "" and not Locale.isSupported(lang) then
			return false, Remotes.M("err.bad_language")
		end
		p.lang = lang
		Session.push(player)
		return true
	end)
	Remotes.handle("SetSetting", function(player, payload)
		local p = Data.get(player)
		if not p then
			return false
		end
		local key = payload.key
		-- "effects" (glow, particles, camera kicks) is applied by each client from the State push
		if key ~= "speedCoil" and key ~= "gravityCoil" and key ~= "effects" then
			return false, Remotes.M("err.unknown_setting")
		end
		(p.settings :: any)[key] = payload.value == true
		Cosmetics.applyCoils(player)
		Session.refreshHelp(player) -- a coil switched on mid-run makes the run assisted
		Session.push(player)
		return true
	end)
end

return Cosmetics
