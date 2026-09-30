--!nonstrict
-- World-space effects: floating "+$value" on harvest, colored by mutation, with a sparkle burst.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local I18n = require(script.Parent.I18n)
local Perf = require(script.Parent.Perf)
local Sound = require(script.Parent.Sound)
local TrophyRules = require(ReplicatedStorage.Shared.Trophies)

local Fx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
-- particle budget per harvest (a Harvest All fires up to 30 of these at once)
Fx.POP_PARTICLES = 9
Fx.LEAF_PARTICLES = 5

Fx.MAX_LIVE = 12
local live = 0

function Fx.harvest(position: any, seedId: any, mutation: any, value: any, size: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	-- a Harvest All of 30 tiles shows the first dozen; rare mutations always show
	if live >= Fx.MAX_LIVE and not (type(mutation) == "string" and Config.MutationById[mutation]) and size == nil then
		return
	end
	live += 1
	task.delay(2, function()
		live -= 1
	end)
	local seed = Config.SeedById[seedId]
	local mut = if type(mutation) == "string" then Config.MutationById[mutation] else nil
	local color = if mut then mut.color else Theme.C.Cash

	local att: Attachment = C.new("Attachment", { Name = "HarvestFx", Parent = workspace.Terrain })
	att.WorldPosition = position

	-- a little sideways jitter so a Harvest All doesn't stack every number on the same spot
	local jx, jz = math.random() * 2.4 - 1.2, math.random() * 2.4 - 1.2
	local bb: BillboardGui = C.new("BillboardGui", {
		Size = UDim2.fromOffset(260, 100),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 180,
		StudsOffsetWorldSpace = Vector3.new(jx, 1.5, jz),
		Adornee = att,
		Parent = att,
	})
	local amount = C.label(bb, "+" .. Format.cash(tonumber(value) or 0), UDim2.new(1, 0, 0, 52), {
		TextSize = if mut then 46 else 38,
		TextColor3 = color,
		TextWrapped = false,
		Outline = 3,
	})
	local sizeDef = if type(size) == "string" then TrophyRules.SizeById[size] else nil
	Sound.play(if mut or sizeDef then "harvestRare" else "harvest")
	local sub = if mut
		then I18n.t("fx.mutation", { mutation = { key = "mutation." .. mut.id }, mult = tostring(mut.multiplier) })
		else (Theme.seedEmoji(seedId) .. " " .. (if seed then I18n.t("seed." .. seed.id) else ""))
	if sizeDef then
		sub = "⭐ " .. I18n.t("size." .. sizeDef.id) .. "  " .. sub
	end
	C.label(bb, sub, UDim2.new(1, 0, 0, 30), {
		Position = UDim2.fromOffset(0, 50),
		TextSize = if mut then 26 else 20,
		TextColor3 = if mut then color else Theme.C.White,
		TextWrapped = false,
		Outline = 2,
	})
	local sc = C.new("UIScale", { Scale = 0.3, Parent = amount })
	C.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	C.tween(bb, 1.4, { StudsOffsetWorldSpace = Vector3.new(jx, 6, jz) }, Enum.EasingStyle.Quad)
	task.delay(0.8, function()
		if bb.Parent then
			C.fadeOut(bb, 0.6)
		end
	end)

	-- every harvest pops: juice in the fruit's color plus a few leaf bits
	local fruitColor = if mut then color elseif seed then seed.fruitColor else Theme.C.Cash
	local pop: ParticleEmitter = C.new("ParticleEmitter", {
		Texture = SPARKLE,
		Color = ColorSequence.new(fruitColor, Theme.lighten(fruitColor, 0.4)),
		LightEmission = 0.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(7, 12),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -28, 0),
		Drag = 2,
		Enabled = false,
		Parent = att,
	})
	pop:Emit(math.min(Fx.POP_PARTICLES, Perf.budget(Perf.lite).harvestPop))
	local bits: ParticleEmitter = C.new("ParticleEmitter", {
		Texture = SQUARE,
		Color = ColorSequence.new(if seed then seed.stemColor else Theme.C.Green),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 11),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -32, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-260, 260),
		Enabled = false,
		Parent = att,
	})
	bits:Emit(math.min(Fx.LEAF_PARTICLES, Perf.budget(Perf.lite).harvestLeaves))

	if mut then
		if mut.multiplier >= 8 then
			-- rare mutation: one expanding shock ring
			local ring: ParticleEmitter = C.new("ParticleEmitter", {
				Texture = RING,
				Color = ColorSequence.new(color),
				LightEmission = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 9) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.55),
				Speed = NumberRange.new(0),
				Enabled = false,
				Parent = att,
			})
			ring:Emit(1)
		end
		local e: ParticleEmitter = C.new("ParticleEmitter", {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(color),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(180, 180),
			Enabled = false,
			Parent = att,
		})
		e:Emit(if mut.multiplier >= 8 then 40 else 18)
	end

	Debris:AddItem(att, 2)
end

return Fx
