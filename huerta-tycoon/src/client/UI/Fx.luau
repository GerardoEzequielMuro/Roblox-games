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
-- a Harvest All used to float up to 12 "+$" numbers at once, piled on each other: now the first few float on
-- their own and the rest of the burst adds up into one bigger "+$total  xN" number
Fx.SOLO_NUMBERS = 3
Fx.BURST_WINDOW = 0.45
local live = 0
local burst = { last = -math.huge, n = 0, sum = 0, count = 0, label = nil :: TextLabel?, sub = nil :: TextLabel? }

-- Floating "+$" billboard at an attachment; returns the amount and sub labels.
local function floatNumber(att: Attachment, amountText: string, color: Color3, subText: string, subColor: Color3, big: boolean, life: number): (TextLabel, TextLabel)
	-- a little sideways jitter so numbers of the same burst don't sit on the same spot
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
	local amount = C.label(bb, amountText, UDim2.new(1, 0, 0, 52), {
		TextSize = if big then 46 else 38,
		TextColor3 = color,
		TextWrapped = false,
		Outline = 3,
	})
	local sub = C.label(bb, subText, UDim2.new(1, 0, 0, 30), {
		Position = UDim2.fromOffset(0, 50),
		TextSize = if big then 26 else 20,
		TextColor3 = subColor,
		TextWrapped = false,
		Outline = 2,
	})
	local sc = C.new("UIScale", { Scale = 0.3, Parent = amount })
	C.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	C.tween(bb, life, { StudsOffsetWorldSpace = Vector3.new(jx, 6, jz) }, Enum.EasingStyle.Quad)
	task.delay(life - 0.6, function()
		if bb.Parent then
			C.fadeOut(bb, 0.6)
		end
	end)
	return amount, sub
end

function Fx.harvest(position: any, seedId: any, mutation: any, value: any, size: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local seed = Config.SeedById[seedId]
	local mut = if type(mutation) == "string" then Config.MutationById[mutation] else nil
	local sizeDef = if type(size) == "string" then TrophyRules.SizeById[size] else nil
	local special = mut ~= nil or sizeDef ~= nil
	local amountValue = tonumber(value) or 0

	-- burst bookkeeping (plain crops only: a rare one always gets its own number)
	local now = os.clock()
	if now - burst.last > Fx.BURST_WINDOW then
		burst.n, burst.sum, burst.count, burst.label, burst.sub = 0, 0, 0, nil, nil
	end
	burst.last = now
	local merged = false
	if not special then
		burst.n += 1
		if burst.n > Fx.SOLO_NUMBERS then
			burst.sum += amountValue
			burst.count += 1
			merged = true
			local lbl, sub = burst.label, burst.sub
			if lbl and lbl.Parent and sub then
				lbl.Text = "+" .. Format.cash(burst.sum)
				sub.Text = "x" .. tostring(burst.count)
				local sc = lbl:FindFirstChildOfClass("UIScale")
				if sc then
					sc.Scale = 1.15
					C.tween(sc, 0.15, { Scale = 1 })
				end
			else
				burst.label, burst.sub = nil, nil -- faded away: a long burst starts a new total
			end
		end
	end

	-- a Harvest All of 30 tiles pops the first dozen; rare mutations always show
	if live >= Fx.MAX_LIVE and not special and not (merged and burst.label == nil) then
		return
	end
	live += 1
	task.delay(2.2, function()
		live -= 1
	end)
	local color = if mut then mut.color else Theme.C.Cash

	local att: Attachment = C.new("Attachment", { Name = "HarvestFx", Parent = workspace.Terrain })
	att.WorldPosition = position

	Sound.play(if special then "harvestRare" else "harvest")
	if merged then
		if burst.label == nil then
			-- the running total of the burst, a bit bigger and a bit longer on screen
			local lbl, sub = floatNumber(att, "+" .. Format.cash(burst.sum), Theme.C.Gold, "x" .. tostring(burst.count), Theme.C.White, true, 2)
			burst.label, burst.sub = lbl, sub
		end
	else
		local sub = if mut
			then I18n.t("fx.mutation", { mutation = { key = "mutation." .. mut.id }, mult = tostring(mut.multiplier) })
			else (Theme.seedEmoji(seedId) .. " " .. (if seed then I18n.t("seed." .. seed.id) else ""))
		if sizeDef then
			sub = "⭐ " .. I18n.t("size." .. sizeDef.id) .. "  " .. sub
		end
		floatNumber(att, "+" .. Format.cash(amountValue), color, sub, if mut then color else Theme.C.White, mut ~= nil, 1.4)
	end

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

	Debris:AddItem(att, 2.2)
end

return Fx
