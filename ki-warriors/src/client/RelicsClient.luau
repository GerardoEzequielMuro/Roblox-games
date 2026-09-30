--!nonstrict
-- Astral Seals on the client: every player sees only their own seals (floating crystals with a
-- halo; a tall light beam with the Seal Compass pass), picks them up by walking / flying into
-- them, and sees the altar slots light up. Also plays the wish show.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Fx = require(script.Parent.Fx)
local CombatFx = require(script.Parent.CombatFx)

local RelicsClient = {}
local player = Players.LocalPlayer

type Seal = { i: number, pos: Vector3, parts: { BasePart }, core: BasePart, halo: BasePart, beam: BasePart? }
local seals: { [number]: Seal } = {}
local busy: { [number]: boolean } = {}
RelicsClient.seals = seals
RelicsClient.notify = nil :: any
RelicsClient.collected = 0

local folder = Instance.new("Folder")
folder.Name = "KiwSeals"
folder.Parent = workspace

local function color(i: number): Color3
	local c = Config.Relics.colors[(i - 1) % #Config.Relics.colors + 1]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(shape: string, size: Vector3, col: Color3, trans: number?): BasePart
	local p: BasePart
	if shape == "cyl" then
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Cylinder
		p = b
	else
		p = Instance.new("Part")
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = col
	p.Size = size
	p.Transparency = trans or 0
	p.Parent = folder
	return p
end

local function remove(i: number)
	local s = seals[i]
	if s then
		for _, p in s.parts do
			p:Destroy()
		end
		seals[i] = nil
	end
end

local function add(i: number, pos: Vector3, radar: boolean)
	local col = color(i)
	local core = part("block", Vector3.new(2.2, 3.4, 2.2), col)
	local inner = part("block", Vector3.new(1.2, 4.6, 1.2), col:Lerp(Color3.new(1, 1, 1), 0.6))
	local halo = part("cyl", Vector3.new(0.3, 6, 6), col, 0.45)
	local parts = { core, inner, halo }
	local beam: BasePart? = nil
	if radar then
		local b = part("cyl", Vector3.new(160, 1.6, 1.6), col, 0.5)
		b.CFrame = CFrame.new(pos + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(parts, b)
		beam = b
	end
	seals[i] = { i = i, pos = pos, parts = parts, core = core, halo = halo, beam = beam }
	;(seals[i] :: any).inner = inner
end

local function sync()
	local s = Net.state
	local r = s and s.relics
	local wanted: { [number]: any } = {}
	if s and r then
		for _, e in r.list do
			if not e.found and e.planet == s.planet then
				wanted[e.i] = e
			end
		end
	end
	for i in seals do
		if not wanted[i] then
			remove(i)
		end
	end
	local radar = s ~= nil and s.passes ~= nil and s.passes.RelicRadar == true
	for i, e in wanted do
		local cur = seals[i]
		if cur and ((cur.pos - e.pos).Magnitude > 0.5 or (cur.beam ~= nil) ~= radar) then
			remove(i)
			cur = nil
		end
		if not cur then
			add(i, e.pos, radar)
		end
	end
	-- altar slots
	local world = workspace:FindFirstChild("World")
	local altar = world and world:FindFirstChild("WishAltar")
	if altar and r then
		local found = {}
		for _, e in r.list do
			found[e.i] = e.found
		end
		for i = 1, Config.Relics.count do
			local slot = altar:FindFirstChild("SealSlot" .. i)
			if slot and slot:IsA("BasePart") then
				local on = found[i] == true
				slot.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				slot.Color = if on then color(i) else color(i):Lerp(Color3.fromRGB(30, 30, 50), 0.6)
			end
		end
	end
end

local function collect(i: number)
	if busy[i] then
		return
	end
	busy[i] = true
	task.spawn(function()
		local seal = seals[i]
		local ok, res = Net.request("CollectRelic", { i = i })
		if ok and seal then
			RelicsClient.collected += 1
			local col = color(i)
			Fx.burst(seal.pos, 2, 12, col, 0.4, 0.3)
			Fx.ring(seal.pos - Vector3.new(0, 2, 0), 2, 16, col, 0.5, 0.5)
			Fx.sparks(seal.pos, col, 12, 40, 0.5)
			Fx.sound("land", 0.5, 1.6)
			remove(i)
			if RelicsClient.notify then
				RelicsClient.notify(Lang.t("toast.seal", { n = res, total = Config.Relics.count, seal = Lang.t("item.seal") }), "success")
			end
		end
		task.wait(1)
		busy[i] = nil
	end)
end

-- The wish: a comet falls on the altar, rings and a column of light.
local function wishShow(d)
	local p: Vector3 = d.p
	local gold = Color3.fromRGB(255, 226, 110)
	local from = p + Vector3.new(60, 220, -40)
	local comet = Fx.get("ball")
	comet.Size = Vector3.one * 10
	comet.Color = Color3.fromRGB(255, 250, 220)
	comet.CFrame = CFrame.new(from)
	local tail = Fx.get("blob")
	tail.Color = gold
	tail.Transparency = 0.3
	tail.Size = Vector3.new(7, 7, 60)
	local t0 = os.clock()
	local dur = 1.1
	while os.clock() - t0 < dur do
		local a = (os.clock() - t0) / dur
		local pos = from:Lerp(p + Vector3.new(0, 14, 0), a * a)
		comet.CFrame = CFrame.new(pos)
		tail.CFrame = CFrame.lookAt(pos, from) * CFrame.new(0, 0, -30)
		RunService.RenderStepped:Wait()
	end
	Fx.release(tail)
	Fx.tween(comet, 0.5, { Size = Vector3.one * 26, Transparency = 1 })
	task.delay(0.5, Fx.release, comet)
	local pillar = Fx.get("cyl")
	pillar.Color = gold
	pillar.Transparency = 0.25
	pillar.Size = Vector3.new(300, 8, 8)
	pillar.CFrame = CFrame.new(p + Vector3.new(0, 150, 0)) * CFrame.Angles(0, 0, math.rad(90))
	Fx.tween(pillar, 1.6, { Size = Vector3.new(300, 40, 40), Transparency = 1 })
	task.delay(1.6, Fx.release, pillar)
	for i = 1, 4 do
		task.delay(i * 0.18, function()
			Fx.ring(p + Vector3.new(0, 0.5, 0), 4, 40 + i * 14, if i % 2 == 0 then gold else Color3.fromRGB(190, 120, 255), 0.8, 0.8)
		end)
	end
	Fx.burst(p + Vector3.new(0, 10, 0), 6, 50, gold, 0.8, 0.4)
	Fx.sparks(p + Vector3.new(0, 12, 0), gold, 24, 90, 1)
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - p).Magnitude < 260 then
		Fx.shake(1.2)
		Fx.sound("boom", 0.6, 0.6)
	end
end

function RelicsClient.init()
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			sync()
		end
	end)
	sync()
	CombatFx.on("wish", wishShow)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		for i, s in seals do
			local y = math.sin(now * 1.6 + i) * 0.8
			local cf = CFrame.new(s.pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, now * 1.2 + i, math.rad(20))
			s.core.CFrame = cf
			;(s :: any).inner.CFrame = cf * CFrame.Angles(0, math.rad(45), 0)
			s.halo.CFrame = CFrame.new(s.pos + Vector3.new(0, y, 0)) * CFrame.Angles(now * 0.9, now * 0.7, math.rad(90))
		end
		acc += dt
		if acc > 0.15 and root then
			acc = 0
			for i, s in seals do
				if (root.Position - s.pos).Magnitude <= Config.Relics.pickupRadius then
					collect(i)
				end
			end
		end
	end)
end

return RelicsClient
