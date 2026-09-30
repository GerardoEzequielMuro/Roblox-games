--!strict
-- Where things are. Pure math shared by the server (validation, world building) and the
-- client (planets are rendered locally), so no positions ever travel over the network.
-- Points are { x, y, z } tables; Layout.v3 converts inside Roblox.
local Config: typeof(require(script.Parent.Config)) = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")

local Layout = {}

export type Point = { number }

Layout.GroundY = 0

function Layout.zoneCenter(zone: number): Point
	return { (zone - 1) * Config.ZoneSpacing, 0, 0 }
end

-- Node 0 = the Titan in the middle; 1..NodesPerZone = regular planets on two arcs that
-- leave the south side (the plaza) free; NodeAnomaly = the hourly Anomaly, between the plaza
-- and the Titan; NodeGate = the Gate Planet hanging off the north edge.
function Layout.nodePosition(zone: number, node: number): Point
	local c = Layout.zoneCenter(zone)
	if node == Config.NodeTitan then
		return { c[1], 24, c[3] + 8 }
	elseif node == Config.NodeAnomaly then
		return { c[1], 18, c[3] - 26 }
	elseif node == Config.NodeGate then
		return { c[1], 26, c[3] + Config.ZoneRadius + 8 }
	end
	local inner = 5
	local radius, idx, count, arc
	if node <= inner then
		radius, idx, count, arc = 44, node, inner, 250
	else
		radius, idx, count, arc = 76, node - inner, Config.NodesPerZone - inner, 240
	end
	local a = math.rad(-arc / 2 + arc * (idx - 1) / (count - 1))
	-- angle 0 = north (+Z)
	local x = c[1] + math.sin(a) * radius
	local z = c[3] + math.cos(a) * radius + 6
	local y = 11 + ((node * 7 + zone * 3) % 5) * 0.9
	return { x, y, z }
end

function Layout.spawnPoint(zone: number): Point
	local c = Layout.zoneCenter(zone)
	return { c[1], 4, c[3] - 72 }
end

function Layout.capsulePosition(capsuleId: string): Point?
	for _, cap in Config.Capsules do
		if cap.id == capsuleId then
			local c = Layout.zoneCenter(cap.zone)
			if (cap :: any).exclusive then
				return { c[1] + 40, 0, c[3] - 52 }
			end
			return { c[1] - 40, 0, c[3] - 52 }
		end
	end
	return nil
end

-- Refinery pad: stand on it to sell your cargo by hand.
function Layout.refineryPosition(zone: number): Point
	local c = Layout.zoneCenter(zone)
	return { c[1] - 24, 0, c[3] - 82 }
end

-- Workshop stand (opens Upgrades) in every plaza.
function Layout.workshopPosition(zone: number): Point
	local c = Layout.zoneCenter(zone)
	return { c[1] + 24, 0, c[3] - 82 }
end

-- The galaxy's own system station (Relic altar, Cryo forge...) from galaxy 2 on.
function Layout.systemPosition(zone: number): Point
	local c = Layout.zoneCenter(zone)
	return { c[1] + 40, 0, c[3] - 52 }
end

-- Warp pad in each plaza (opens the Teleport menu).
function Layout.portalPosition(zone: number): Point
	local c = Layout.zoneCenter(zone)
	return { c[1], 0, c[3] - 90 }
end

-- Leaderboards in the Dawn Belt plaza (slot 1, 2) and the arena lobby (slot 3).
function Layout.boardPosition(slot: number): Point
	if slot == 3 then
		local a = Config.ArenaCenter
		return { a[1] + 22, 0, a[3] - Config.ArenaLobbyRadius + 6 }
	end
	local c = Layout.zoneCenter(1)
	return { c[1] + (if slot == 1 then -52 else 52), 0, c[3] - 72 }
end

function Layout.arenaCenter(): Point
	return Config.ArenaCenter
end

function Layout.arenaSpawn(): Point
	local c = Config.ArenaCenter
	return { c[1], 4, c[3] - (Config.ArenaRadius + Config.ArenaLobbyRadius) / 2 }
end

-- Galaxy index whose station contains the point (nil in the arena or off the map).
function Layout.zoneAt(x: number, z: number): number?
	local i = math.floor(x / Config.ZoneSpacing + 0.5) + 1
	if i < 1 or i > #Config.Zones then
		return nil
	end
	local c = Layout.zoneCenter(i)
	local dx, dz = x - c[1], z - c[3]
	if dx * dx + dz * dz <= (Config.ZoneRadius + 30) ^ 2 then
		return i
	end
	return nil
end

function Layout.inArena(x: number, z: number): boolean
	local c = Config.ArenaCenter
	local dx, dz = x - c[1], z - c[3]
	return dx * dx + dz * dz <= Config.ArenaRadius ^ 2
end

function Layout.onArenaPlatform(x: number, z: number): boolean
	local c = Config.ArenaCenter
	local dx, dz = x - c[1], z - c[3]
	return dx * dx + dz * dz <= (Config.ArenaLobbyRadius + 20) ^ 2
end

function Layout.v3(p: Point): any
	return (Vector3 :: any).new(p[1], p[2], p[3])
end

return Layout
