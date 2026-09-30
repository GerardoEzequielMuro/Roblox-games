--!strict
-- The "what do I do next" line at the top of the screen, with a progress bar, plus a beam
-- of light from the player to the thing they should walk to (first egg, next gate).
-- Guide.current is pure (state in, objective out) so the playtest can check every step.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local Guide = {}

export type Objective = {
	key: string, -- translation key
	args: { [string]: any },
	zoneArg: number?, -- args.zone is filled with this zone's translated name
	progress: number, -- 0..1
	target: Vector3?, -- where the beam points
	window: string?, -- window opened when the objective is clicked
}

local FIRST_EGG = Config.Eggs[1]
local HATCH_GOAL = 5

local function eggPosition(egg: typeof(Config.Eggs[1])): Vector3
	local zone = if egg.zone == 0 then 1 else egg.zone
	return Vector3.new(egg.offsetX, 6, (zone - 1) * Config.ZoneLength + egg.offsetZ)
end

local function gatePosition(zone: number): Vector3
	return Vector3.new(0, 6, (zone - 1) * Config.ZoneLength - Config.ZoneLength / 2)
end

function Guide.current(s: { [string]: any }): Objective
	local hatched = s.totalHatched or 0
	local taps = s.taps or 0
	if hatched < 1 then
		if taps < FIRST_EGG.price then
			return { key = "goal.earn", args = { n = Format.abbrev(FIRST_EGG.price) }, progress = taps / FIRST_EGG.price }
		end
		return { key = "goal.hatch1", args = {}, progress = 1, target = eggPosition(FIRST_EGG) }
	end
	if hatched < HATCH_GOAL then
		return { key = "goal.hatchN", args = { n = HATCH_GOAL, have = hatched }, progress = hatched / HATCH_GOAL, target = if taps >= FIRST_EGG.price then eggPosition(FIRST_EGG) else nil }
	end
	-- next gate or rebirth, whichever is cheaper
	local nextZone = #(s.zones or { 1 }) + 1
	local zone = Config.Zones[nextZone]
	local rebirthCost = s.rebirthCost or Formulas.rebirthCost(s.rebirths or 0)
	if zone and zone.cost <= rebirthCost then
		if taps >= zone.cost then
			return { key = "goal.gate", args = {}, zoneArg = nextZone, progress = 1, target = gatePosition(nextZone), window = "Teleport" }
		end
		return { key = "goal.zone", args = {}, zoneArg = nextZone, progress = taps / zone.cost, window = "Teleport" }
	end
	if taps >= rebirthCost then
		return { key = "goal.rebirth_ready", args = {}, progress = 1, window = "Rebirth" }
	end
	return { key = "goal.rebirth", args = { mult = tostring(Formulas.rebirthMult((s.rebirths or 0) + 1)) }, progress = taps / rebirthCost, window = "Rebirth" }
end

---------------------------------------------------------------------------
-- Beam to the target
---------------------------------------------------------------------------
local anchor: BasePart? = nil
local beam: Beam? = nil
local a0: Attachment? = nil

local function ensure()
	if anchor then
		return
	end
	local p = Instance.new("Part")
	p.Name = "GuideTarget"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Parent = Workspace
	anchor = p
	local at = Instance.new("Attachment")
	at.Parent = p
	local b = Instance.new("Beam")
	b.Name = "GuideBeam"
	b.Color = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 255, 255))
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(1, 0.15) })
	b.Width0 = 1.2
	b.Width1 = 2.2
	b.FaceCamera = true
	b.LightEmission = 0.6
	b.Segments = 1
	b.Attachment1 = at
	b.Enabled = false
	b.Parent = p
	beam = b
end

-- Points the beam at target (nil hides it). Hidden when the player is already there.
function Guide.point(target: Vector3?)
	ensure()
	local b = beam :: Beam
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not target or not root or (root.Position - target).Magnitude < 20 then
		b.Enabled = false
		return
	end
	if not a0 or a0.Parent ~= root then
		if a0 then
			a0:Destroy()
		end
		local at = Instance.new("Attachment")
		at.Name = "GuideFrom"
		at.Parent = root
		a0 = at
		b.Attachment0 = at
	end
	(anchor :: BasePart).Position = target
	b.Enabled = true
end

function Guide.beamOn(): boolean
	return beam ~= nil and beam.Enabled
end

return Guide
