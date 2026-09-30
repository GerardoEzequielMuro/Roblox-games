--!nonstrict
-- Story steps as text, plus where each step points in the world (for the guide beam).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)

local StoryText = {}

-- "Defeat 3 Thornlings", "Reach 150 power"...
function StoryText.text(step): string
	local args: { [string]: any } = { n = Format.abbrev(step.target) }
	if step.npc then
		args.npc = Lang.t("npc." .. step.npc)
	end
	if step.zone then
		args.zone = Lang.t("zone." .. step.zone)
	end
	if step.planet then
		args.planet = Lang.t("planet." .. Config.Planets[step.planet].id)
	end
	return Lang.t("story." .. step.kind, args)
end

-- One-line "how" for the tutorial steps, by device.
function StoryText.hint(step, touch: boolean): string?
	local key = "hint." .. step.kind .. (if touch then ".touch" else ".pc")
	local text = Lang.t(key)
	return if text ~= key then text else nil
end

-- World position the step sends the player to (nil = nowhere in particular).
function StoryText.target(step): Vector3?
	local s = Net.state
	if not s then
		return nil
	end
	local function at(planet: number, offset): Vector3
		local cx, cy, cz = Config.planetCenter(planet)
		return Vector3.new(cx + offset[1], cy + 3, cz + offset[3])
	end
	if step.guide == "camp" or step.guide == "boss" then
		local def = Config.Npcs[step.npc]
		if not def or def.planet ~= s.planet then
			return nil
		end
		local pl = Config.Planets[def.planet]
		if pl.boss.npc == step.npc then
			return at(def.planet, pl.boss.offset)
		end
		for _, c in pl.camps do
			if c.npc == step.npc then
				return at(def.planet, c.offset)
			end
		end
	elseif step.guide == "zone" then
		local z = Config.ZoneById[step.zone]
		if z and z.planet == s.planet then
			return at(z.planet, z.offset)
		end
	elseif step.guide == "relic" then
		local r = s.relics
		if r then
			local best, bestD = nil, math.huge
			local char = game:GetService("Players").LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			for _, e in r.list do
				if not e.found and e.planet == s.planet then
					local d = if root then (root.Position - e.pos).Magnitude else 0
					if d < bestD then
						best, bestD = e.pos, d
					end
				end
			end
			return best
		end
	end
	return nil
end

return StoryText
