--!strict
-- Daily quests (pure; unit-tested with luau.exe). Everyone gets the same 3 quest kinds on a
-- given UTC day; targets scale with the player's best zone.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Quests = {}

export type Quest = { kind: string, target: number, gems: number }

function Quests.today(now: number): number
	return now // 86400
end

function Quests.resetsAt(now: number): number
	return (now // 86400 + 1) * 86400
end

function Quests.forDay(day: number, zone: number?): { Quest }
	local pool = Config.QuestPool
	local order = {}
	for i = 1, #pool do
		order[i] = i
	end
	-- Park-Miller PRNG (pure Luau, so the standalone tests get the same picks as Roblox)
	local seed = (math.floor(day) % 2147483646) + 1
	local function nextInt(n: number): number
		seed = (seed * 16807) % 2147483647
		return seed % n + 1
	end
	nextInt(1)
	for i = #order, 2, -1 do
		local j = nextInt(i)
		order[i], order[j] = order[j], order[i]
	end
	local z = math.clamp(zone or 1, 1, #Config.Zones)
	local out: { Quest } = {}
	for k = 1, math.min(Config.QuestsPerDay, #pool) do
		local def = pool[order[k]]
		table.insert(out, { kind = def.kind, target = def.targetByZone[math.min(z, #def.targetByZone)], gems = def.gems })
	end
	return out
end

return Quests
