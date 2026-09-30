--!strict
-- Server-side runtime for the tagged obstacle parts built by StageGenerator:
--   Kill (touch = death), Disappear (fade after touch), Falling (drop after touch),
--   Mover (anchored platform on a sine path; AssemblyLinearVelocity set so riders are carried),
--   Spinner (anchored kill bars), Lava (kill slab rising on a timer), Laser (timed kill gate),
--   Coin (pickup, per-player, once per run).
-- Bounce pads, glass reveal and wind are client-side (they act on the local character / view).
--
-- Towers come and go (server/Towers.luau), so obstacles are registered per tower with
-- Obstacles.add(folder) and dropped with Obstacles.remove(folder).
--
-- Only what is near a player runs: every animated obstacle knows its stage, and ONE Heartbeat
-- loop moves those of the stages inside some player's window. The rest sleep where they are, so
-- an empty stretch of tower costs neither CPU nor network.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local Obstacles = {}

-- Stages around a player that stay awake: two behind (you see them when you look down / fall
-- back), eight ahead (six stages up is the run directly overhead).
Obstacles.AWAKE_BEHIND = 2
Obstacles.AWAKE_AHEAD = 8

-- Set by server/Shops.luau: returns true when something (a shield) absorbed the hit.
Obstacles.absorb = nil :: ((player: Player) -> boolean)?

local function playerFromHit(hit: BasePart): (Player?, Humanoid?)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(model)
	return player, hum
end

-- Every lethal obstacle goes through here.
function Obstacles.kill(player: Player?, hum: Humanoid)
	if hum.Health <= 0 then
		return
	end
	if player then
		local s = Session.get(player)
		if s and os.clock() < s.shieldUntil then
			return
		end
		local absorb = Obstacles.absorb
		if absorb and absorb(player) then
			return
		end
	end
	hum.Health = 0
end

local function bindKill(part: BasePart)
	part.Touched:Connect(function(hit)
		local player, hum = playerFromHit(hit)
		if hum then
			Obstacles.kill(player, hum)
		end
	end)
end

-- The glyph painted on a platform (StageGenerator.topIcon) must vanish with it.
local function setIcon(part: BasePart, on: boolean)
	local icon = part:FindFirstChild("Icon")
	if icon and icon:IsA("SurfaceGui") then
		icon.Enabled = on
	end
end

local function bindDisappear(part: BasePart)
	local busy = false
	local baseT = part.Transparency
	local delay = (part:GetAttribute("Delay") :: number?) or 0.6
	part.Touched:Connect(function(hit)
		if busy then
			return
		end
		local player = playerFromHit(hit)
		if not player then
			return
		end
		busy = true
		TweenService:Create(part, TweenInfo.new(delay), { Transparency = 0.85 }):Play()
		task.wait(delay)
		part.CanCollide = false
		part.Transparency = 1
		setIcon(part, false)
		task.wait(2.5)
		part.CanCollide = true
		setIcon(part, true)
		TweenService:Create(part, TweenInfo.new(0.3), { Transparency = baseT }):Play()
		task.wait(0.3)
		busy = false
	end)
end

local function bindFalling(part: BasePart)
	local busy = false
	local home = part.CFrame
	local delay = (part:GetAttribute("Delay") :: number?) or 0.5
	part.Touched:Connect(function(hit)
		if busy then
			return
		end
		if not playerFromHit(hit) then
			return
		end
		busy = true
		-- shake
		local t0 = os.clock()
		while os.clock() - t0 < delay do
			part.CFrame = home * CFrame.new((math.random() - 0.5) * 0.3, 0, (math.random() - 0.5) * 0.3)
			task.wait(0.05)
		end
		part.CFrame = home
		local drop = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = home - Vector3.new(0, 45, 0),
			Transparency = 1,
		})
		drop:Play()
		drop.Completed:Wait()
		part.CanCollide = false
		setIcon(part, false)
		task.wait(2.5)
		part.CFrame = home
		part.CanCollide = true
		setIcon(part, true)
		TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 0 }):Play()
		task.wait(0.3)
		busy = false
	end)
end

-- Gives a coin to a player who is really next to it. Used by the touch and by the coin magnet.
function Obstacles.collectCoin(player: Player, part: BasePart, reach: number): boolean
	local coinId = part:GetAttribute("CoinId")
	local s = Session.get(player)
	local p = Data.get(player)
	if type(coinId) ~= "number" or not s or not p or s.collected[coinId] then
		return false
	end
	local root = (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not root or (root.Position - part.Position).Magnitude > reach then
		return false -- touch spoof / far away
	end
	s.collected[coinId] = true
	local got = Session.addCoins(player, Config.CoinPickupValue)
	Remotes.fire("CoinCollected", player, coinId, got)
	Session.push(player)
	return true
end

local function bindCoin(part: BasePart)
	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			Obstacles.collectCoin(player, part, 12)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- animated obstacles, grouped by stage
---------------------------------------------------------------------------------------------
type Mover = { part: BasePart, home: CFrame, axis: Vector3, amp: number, period: number, phase: number }
type Spinner = { part: BasePart, center: Vector3, speed: number, angle0: number }
type Lava = { part: BasePart, bottom: number, minTop: number, maxTop: number, period: number, cf: CFrame }
type Laser = { part: BasePart, period: number, duty: number, phase: number, state: number }
type StageSet = { movers: { Mover }, spinners: { Spinner }, lavas: { Lava }, lasers: { Laser }, coins: { BasePart } }

local stages: { [number]: StageSet } = {}
local owner: { [number]: Instance } = {} -- stage -> the tower folder it came from

local function setFor(stage: number, root: Instance): StageSet
	local set = stages[stage]
	if not set then
		set = { movers = {}, spinners = {}, lavas = {}, lasers = {}, coins = {} }
		stages[stage] = set
		owner[stage] = root
	end
	return set
end

-- Laser states: 0 off, 1 warming up (it is about to fire), 2 on.
Obstacles.LASER_WARN = 0.35
local LASER_LOOK = { [0] = 0.94, [1] = 0.72, [2] = 0.3 }

local function laserState(l: Laser, t: number): number
	local f = (t / l.period + l.phase) % 1
	if f < l.duty then
		return 2
	elseif f > 1 - Obstacles.LASER_WARN / l.period then
		return 1
	end
	return 0
end

-- Coins of a stage (for the magnet).
function Obstacles.coinsOf(stage: number): { BasePart }
	local set = stages[stage]
	return if set then set.coins else {}
end

-- Registers every tagged obstacle under `root` (a tower folder).
function Obstacles.add(root: Instance)
	for _, inst in root:GetDescendants() do
		if not inst:IsA("BasePart") then
			continue
		end
		local stage = (inst:GetAttribute("Stage") :: number?) or 0
		if CollectionService:HasTag(inst, "Kill") then
			bindKill(inst)
		end
		if CollectionService:HasTag(inst, "Disappear") then
			bindDisappear(inst)
		elseif CollectionService:HasTag(inst, "Falling") then
			bindFalling(inst)
		elseif CollectionService:HasTag(inst, "Coin") then
			bindCoin(inst)
			table.insert(setFor(stage, root).coins, inst)
		elseif CollectionService:HasTag(inst, "Mover") then
			table.insert(setFor(stage, root).movers, {
				part = inst,
				home = inst.CFrame,
				axis = (inst:GetAttribute("Axis") :: Vector3?) or Vector3.xAxis,
				amp = (inst:GetAttribute("Amp") :: number?) or 4,
				period = (inst:GetAttribute("Period") :: number?) or 4,
				phase = (inst:GetAttribute("Phase") :: number?) or 0,
			})
		elseif CollectionService:HasTag(inst, "Laser") then
			table.insert(setFor(stage, root).lasers, {
				part = inst,
				period = (inst:GetAttribute("Period") :: number?) or 3,
				duty = (inst:GetAttribute("Duty") :: number?) or 0.5,
				phase = (inst:GetAttribute("Phase") :: number?) or 0,
				state = 2,
			})
		end
		if CollectionService:HasTag(inst, "Spinner") then
			table.insert(setFor(stage, root).spinners, {
				part = inst,
				center = (inst:GetAttribute("Center") :: Vector3?) or inst.Position,
				speed = (inst:GetAttribute("Speed") :: number?) or 2,
				angle0 = (inst:GetAttribute("Angle0") :: number?) or 0,
			})
		elseif CollectionService:HasTag(inst, "Lava") then
			table.insert(setFor(stage, root).lavas, {
				part = inst,
				bottom = (inst:GetAttribute("Bottom") :: number?) or inst.Position.Y,
				minTop = (inst:GetAttribute("MinTop") :: number?) or inst.Position.Y,
				maxTop = (inst:GetAttribute("MaxTop") :: number?) or inst.Position.Y,
				period = (inst:GetAttribute("Period") :: number?) or 10,
				cf = inst.CFrame,
			})
		end
	end
end

-- Forgets the obstacles of a tower that is about to be destroyed.
function Obstacles.remove(root: Instance)
	for stage, from in owner do
		if from == root then
			stages[stage] = nil
			owner[stage] = nil
		end
	end
end

-- Stage numbers that currently have somebody close enough to matter.
local awake: { number } = {}
local awakeSet: { [number]: boolean } = {}

local function refreshAwake()
	table.clear(awakeSet)
	table.clear(awake)
	for _, player in Players:GetPlayers() do
		local s = Session.get(player)
		local p = Data.get(player)
		if s and p then
			local here = if s.inLobby then 0 else math.max(s.at, p.stage)
			for g = math.max(1, here - Obstacles.AWAKE_BEHIND), here + Obstacles.AWAKE_AHEAD do
				if stages[g] and not awakeSet[g] then
					awakeSet[g] = true
					table.insert(awake, g)
				end
			end
		end
	end
end
Obstacles.refreshAwake = refreshAwake

function Obstacles.isAwake(stage: number): boolean
	return awakeSet[stage] == true
end

-- How many animated obstacles exist / are running (for the performance probe and its budget).
function Obstacles.census(): (number, number)
	local total, running = 0, 0
	for stage, set in stages do
		local n = #set.movers + #set.spinners + #set.lavas + #set.lasers
		total += n
		if awakeSet[stage] then
			running += n
		end
	end
	return total, running
end

-- Root position inside the box of `part` (grown by `margin` sideways)?
local function inside(part: BasePart, pos: Vector3, margin: number): boolean
	local rel = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	return math.abs(rel.X) < half.X + margin and math.abs(rel.Z) < half.Z + margin and rel.Y > -half.Y - 3 and rel.Y < half.Y + 3
end

function Obstacles.init()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local sinceAwake = 1
	RunService.Heartbeat:Connect(function(dt)
		sinceAwake += dt
		if sinceAwake >= 0.5 then
			sinceAwake = 0
			refreshAwake()
		end
		local t = Workspace:GetServerTimeNow()
		table.clear(parts)
		table.clear(cframes)
		for _, stage in awake do
			local set = stages[stage]
			if not set then
				continue
			end
			for _, m in set.movers do
				local w = 2 * math.pi / m.period
				local x = t * w + m.phase * 2 * math.pi
				table.insert(parts, m.part)
				table.insert(cframes, m.home + m.axis * (math.sin(x) * m.amp))
				-- velocity = derivative of the path, so humanoids standing on it ride along
				m.part.AssemblyLinearVelocity = m.axis * (math.cos(x) * m.amp * w)
			end
			for _, sp in set.spinners do
				table.insert(parts, sp.part)
				-- wrap in double precision first: CFrame.Angles takes float32, and t (~1.7e9 s) * speed
				-- would otherwise lose all sub-radian precision and the bars would barely move
				table.insert(cframes, CFrame.new(sp.center) * CFrame.Angles(0, (sp.angle0 + t * sp.speed) % (2 * math.pi), 0))
			end
			for _, l in set.lavas do
				-- cycle: 35% low, 40% rising, 10% at peak, 15% draining
				local phase = (t % l.period) / l.period
				local k
				if phase < 0.35 then
					k = 0
				elseif phase < 0.75 then
					k = (phase - 0.35) / 0.4
				elseif phase < 0.85 then
					k = 1
				else
					k = 1 - (phase - 0.85) / 0.15
				end
				local top = l.minTop + (l.maxTop - l.minTop) * k
				local height = math.max(0.5, top - l.bottom)
				local size = l.part.Size
				if math.abs(size.Y - height) > 0.02 then
					l.part.Size = Vector3.new(size.X, height, size.Z)
					local c = l.cf
					l.part.CFrame = CFrame.new(c.Position.X, l.bottom + height / 2, c.Position.Z) * c.Rotation
				end
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)

	-- Slow loop (10 Hz): laser gates switch on and off (a property change only when the state
	-- changes), and the kill checks that Touched cannot do: a laser that fires while you stand in
	-- it, lava that rises into a standing character.
	task.spawn(function()
		while true do
			task.wait(0.1)
			local t = Workspace:GetServerTimeNow()
			for _, stage in awake do
				local set = stages[stage]
				if not set or (#set.lasers == 0 and #set.lavas == 0) then
					continue
				end
				for _, l in set.lasers do
					local state = laserState(l, t)
					if state ~= l.state then
						l.state = state
						l.part.Transparency = LASER_LOOK[state]
					end
				end
				for _, player in Players:GetPlayers() do
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if not root or not hum or hum.Health <= 0 then
						continue
					end
					for _, l in set.lasers do
						if l.state == 2 and inside(l.part, root.Position, 0.9) then
							Obstacles.kill(player, hum)
						end
					end
					for _, l in set.lavas do
						local top = l.part.Position.Y + l.part.Size.Y / 2
						local rel = l.part.CFrame:PointToObjectSpace(root.Position)
						local half = l.part.Size / 2
						if math.abs(rel.X) < half.X and math.abs(rel.Z) < half.Z and root.Position.Y - 2.5 < top and root.Position.Y > l.bottom - 3 then
							Obstacles.kill(player, hum)
						end
					end
				end
			end
		end
	end)
end

return Obstacles
