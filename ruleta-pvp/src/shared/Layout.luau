--!strict
-- Where things are. Shared by the server (which builds the lobby and seats players) and the
-- client (which builds the wheels, the cameras and the effects on top of it).
-- Table-local polar coordinates: angle 0 points at the lobby centre (where the pointer and
-- the entrance are), angles grow clockwise seen from above.
local Layout = {}

Layout.TableRing = 118 -- distance from the lobby centre to each table
Layout.IslandRadius = 156
Layout.StageRadius = 27
Layout.StageTop = 1
Layout.SeatRadius = 17
Layout.PodiumTop = 1.7
Layout.RootHeight = 3 -- HumanoidRootPart centre above the podium
Layout.WheelRadius = 9.5
Layout.WheelY = 3.35 -- centre of the wheel disc above the table origin
Layout.WheelThickness = 0.5
Layout.DrumRadius = 10.4
Layout.DrumTop = 3.05
Layout.TrussRadius = 21
Layout.TrussY = 21
Layout.ScreenY = 17
Layout.CorePos = Vector3.new(0, 11, 0)
Layout.CoreRadius = 4.5
Layout.SpawnRadius = 30

function Layout.polar(theta: number, r: number, y: number): Vector3
	return Vector3.new(math.sin(theta) * r, y, -math.cos(theta) * r)
end

-- Table i of n around the lobby, facing the centre.
function Layout.tableCFrame(index: number, count: number): CFrame
	local a = (index - 1) / count * math.pi * 2
	local pos = Vector3.new(math.sin(a) * Layout.TableRing, 0, math.cos(a) * Layout.TableRing)
	return CFrame.lookAt(pos, Vector3.new(0, 0, 0))
end

function Layout.seatAngle(seat: number, seats: number): number
	return (seat - 0.5) / seats * math.pi * 2
end

-- Podium floor centre (world), looking at the wheel.
function Layout.podiumCFrame(origin: CFrame, seat: number, seats: number): CFrame
	local p = origin:PointToWorldSpace(Layout.polar(Layout.seatAngle(seat, seats), Layout.SeatRadius, Layout.PodiumTop))
	local centre = origin:PointToWorldSpace(Vector3.new(0, Layout.PodiumTop, 0))
	return CFrame.lookAt(p, centre)
end

-- Where a seated character's root part goes.
function Layout.seatCFrame(origin: CFrame, seat: number, seats: number): CFrame
	return Layout.podiumCFrame(origin, seat, seats) + Vector3.new(0, Layout.RootHeight, 0)
end

-- Behind the podium: where eliminated players watch from.
function Layout.benchCFrame(origin: CFrame, seat: number, seats: number): CFrame
	local p = origin:PointToWorldSpace(Layout.polar(Layout.seatAngle(seat, seats), Layout.SeatRadius + 7, Layout.StageTop + Layout.RootHeight))
	local centre = origin:PointToWorldSpace(Vector3.new(0, Layout.StageTop + Layout.RootHeight, 0))
	return CFrame.lookAt(p, centre)
end

-- Where a player who leaves the table lands (the lobby side of the entrance).
function Layout.exitCFrame(origin: CFrame, k: number): CFrame
	local p = origin:PointToWorldSpace(Vector3.new((k % 5 - 2) * 4, 4, -(Layout.StageRadius + 9)))
	return CFrame.lookAt(p, origin.Position + Vector3.new(0, 4, 0))
end

function Layout.wheelCFrame(origin: CFrame): CFrame
	return origin * CFrame.new(0, Layout.WheelY, 0)
end

-- Wheel rotation (radians about +Y of the table) for a wheel angle in slots: slot
-- floor(R mod N) + 1 sits under the pointer at table angle 0.
function Layout.wheelYaw(angleSlots: number, n: number): number
	return angleSlots / n * math.pi * 2
end

-- Centre of slot k (1-based) in wheel-local space, at radius r.
function Layout.slotLocal(k: number, n: number, r: number): Vector3
	return Layout.polar((k - 0.5) / n * math.pi * 2, r, 0)
end

return Layout
