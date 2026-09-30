-- Test harness (only in test.project.json builds). Runs inside a Studio playtest.
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local StudioTestService = game:GetService("StudioTestService")
local ServerScriptService = game:GetService("ServerScriptService")

local errors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(errors, msg)
	end
end)

-- The shared runner keeps only the first 200 output lines, so failures are printed in full as they happen and
-- passes are printed packed at the end ("[TEST] ok: name | name | ...").
local results = {}
local passed = {}
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail then " :: " .. tostring(detail) else "")
	if cond then
		table.insert(passed, name)
	else
		print("[TEST] " .. line)
	end
	table.insert(results, line)
end

local player = Players.PlayerAdded:Wait()
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local Session = require(Services.Session)
local t0 = os.clock()
while not Session.get(player) and os.clock() - t0 < 30 do task.wait(0.2) end
local s = Session.get(player)
check("session created", s ~= nil)
if s then
	check("plot assigned", s.plotIndex > 0, s.plotIndex)
	local plot = workspace.Plots:FindFirstChild("Plot_" .. s.plotIndex)
	local unlocked = 0
	for _, t in plot.Tiles:GetChildren() do if t:GetAttribute("Unlocked") then unlocked += 1 end end
	check("6 starter tiles unlocked", unlocked == 6, unlocked)
	check("starter seeds", (s.profile.seeds.carrot or 0) >= 3)
	s.profile.cash = 5000000 -- give test money
	Session.markDirty(s)
end

-- ===== World + visuals (visual round) =====
local function worldTests()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Lighting = game:GetService("Lighting")
	local Config = require(ReplicatedStorage.Shared.Config)
	local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
	local CropVisuals = require(ServerScriptService.Server.World.CropVisuals)
	local _, depth = WorldLayout.plotSize()
	local halfD, gap = depth / 2, WorldLayout.entranceHalfWidth()

	-- 1. nothing stands in the entrance of any plot (owner feedback: the farm sign used to block it)
	local SKIP = { Base = true, Curb = true, Walkway = true, Spawn = true }
	local blockers, signsOk, signCount = {}, 0, 0
	for i = 1, WorldLayout.PLOT_COUNT do
		local plot = workspace.Plots:FindFirstChild("Plot_" .. i)
		local spawn = plot and plot:FindFirstChild("Spawn")
		if not spawn then
			table.insert(blockers, "plot " .. i .. " missing")
			continue
		end
		local plotCF = spawn.CFrame * CFrame.new(0, -1.1, halfD - WorldLayout.SPAWN_INSET)
		for _, d in plot:GetDescendants() do
			if not d:IsA("BasePart") or SKIP[d.Name] or d.Transparency >= 1 then continue end
			-- plot-local bounding box of the part
			local minV, maxV = Vector3.one * math.huge, Vector3.one * -math.huge
			for _, sx in { -0.5, 0.5 } do for _, sy in { -0.5, 0.5 } do for _, sz in { -0.5, 0.5 } do
				local c = plotCF:PointToObjectSpace(d.CFrame * (d.Size * Vector3.new(sx, sy, sz)))
				minV, maxV = minV:Min(c), maxV:Max(c)
			end end end
			-- corridor: the gap (minus the gate posts), from 12 studs outside to the garden bed, walking height
			local inX = maxV.X > -(gap - 1) and minV.X < gap - 1
			local inZ = maxV.Z > -halfD - 12 and minV.Z < -halfD + 8
			local inY = maxV.Y > 1.4 and minV.Y < 12
			if inX and inZ and inY then
				table.insert(blockers, string.format("plot %d %s x[%.1f,%.1f]", i, d.Name, minV.X, maxV.X))
			end
			if d.Name == "SignBoard" then
				signCount += 1
				if maxV.X < -gap - 2 and minV.Z < -halfD then signsOk += 1 end
			end
		end
	end
	check("entrance corridor is clear on all plots", #blockers == 0, table.concat(blockers, " | "))
	check("owner sign stands beside the gate, outside the fence (6 plots)", signsOk == 6 and signCount == 6, signsOk .. "/" .. signCount)
	check("layout: sign does not block the entrance", not WorldLayout.signBlocksEntrance(3))

	-- 1b. the ground is flat and nothing buries the garden: rays cast straight down must hit the tile, the lawn
	-- and (outside the gate) path terrain at ground level
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local buried = {}
	local function probe(plotCF: CFrame, lx: number, lz: number): (Instance?, number, Enum.Material?)
		local from = (plotCF * CFrame.new(lx, 60, lz)).Position
		local hit = workspace:Raycast(from, Vector3.new(0, -120, 0), params)
		return hit and hit.Instance, if hit then hit.Position.Y else -999, hit and hit.Material
	end
	local width = WorldLayout.plotSize()
	for i = 1, WorldLayout.PLOT_COUNT do
		local plot = workspace.Plots["Plot_" .. i]
		local plotCF = plot.Spawn.CFrame * CFrame.new(0, -1.1, halfD - WorldLayout.SPAWN_INSET)
		local tile = plot.Tiles.Tile_30
		local tl = plotCF:PointToObjectSpace(tile.Position)
		local hitTile, yTile = probe(plotCF, tl.X, tl.Z)
		if hitTile ~= tile then table.insert(buried, string.format("plot %d tile: hit %s at y=%.1f", i, hitTile and hitTile:GetFullName() or "nothing", yTile)) end
		local hitLawn, yLawn = probe(plotCF, -(width / 2 - 7), -halfD + 8.5)
		if not hitLawn or hitLawn.Name ~= "Base" then table.insert(buried, string.format("plot %d lawn: hit %s at y=%.1f", i, hitLawn and hitLawn:GetFullName() or "nothing", yLawn)) end
		local hitPath, yPath, matPath = probe(plotCF, 0, -halfD - 8)
		if hitPath ~= workspace.Terrain or math.abs(yPath) > 0.75 or matPath ~= Enum.Material.Ground then
			table.insert(buried, string.format("plot %d path: hit %s at y=%.1f %s", i, hitPath and hitPath.Name or "nothing", yPath, tostring(matPath)))
		end
	end
	check("garden beds, lawns and paths are not buried (terrain is flat)", #buried == 0, table.concat(buried, " | "))

	-- 2. owner sign shows the player on both faces
	if s then
		local plot = workspace.Plots:FindFirstChild("Plot_" .. s.plotIndex)
		local board = plot and plot:FindFirstChild("SignBoard")
		local named, avatars, faces = 0, 0, 0
		if board then
			for _, g in board:GetChildren() do
				if g:IsA("SurfaceGui") then
					faces += 1
					local t, img = g:FindFirstChild("OwnerName"), g:FindFirstChild("Avatar")
					if t and string.find(t.Text, player.DisplayName, 1, true) then named += 1 end
					if img and img.Visible and string.find(img.Image, tostring(player.UserId), 1, true) then avatars += 1 end
				end
			end
		end
		check("owner sign shows name + avatar on both faces", faces == 2 and named == 2 and avatars == 2, string.format("faces %d names %d avatars %d", faces, named, avatars))
	end

	-- 3. landmarks, lighting rig, budgets
	local deco = workspace:FindFirstChild("Decoration")
	local missing = {}
	for _, f in WorldLayout.Features do
		local m = deco and deco:FindFirstChild(f.id)
		if not m or #m:GetChildren() < 5 then table.insert(missing, f.id) end
	end
	check("all 6 landmarks built", #missing == 0, table.concat(missing, ","))
	local rig = {}
	if not Lighting:FindFirstChildOfClass("Atmosphere") then table.insert(rig, "Atmosphere") end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then table.insert(rig, "Bloom") end
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then table.insert(rig, "SunRays") end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then table.insert(rig, "ColorCorrection") end
	if not workspace.Terrain:FindFirstChildOfClass("Clouds") then table.insert(rig, "Clouds") end
	check("lighting rig present (atmosphere, bloom, sun rays, color, clouds)", #rig == 0, table.concat(rig, ","))
	local parts, lights, emitters, colliding, loose = 0, 0, 0, 0, {}
	local character = player.Character
	for _, d in workspace:GetDescendants() do
		if character and d:IsDescendantOf(character) then continue end
		if d:IsA("BasePart") and not d:IsA("Terrain") then
			parts += 1
			if d.CanCollide then colliding += 1 end
			if not d.Anchored and #loose < 5 then table.insert(loose, d:GetFullName()) end
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	check("every world part is anchored", #loose == 0, table.concat(loose, ", "))
	check("world part budget (phones): <= 6000 parts", parts <= 6000, parts .. " parts, " .. colliding .. " colliding")
	local okStream, streaming = pcall(function() return workspace.StreamingEnabled end)
	check("instance streaming is on", okStream and streaming == true, streaming)
	check("world light budget: <= 40 lights", lights <= 40, lights)
	check("world emitter budget: <= 40 emitters", emitters <= 40, emitters)

	-- 4. every crop x stage x mutation builds, within the per-tile part budget
	local top = CFrame.new(0, 500, 0)
	local built, bad, maxParts, maxName = 0, {}, 0, ""
	for _, seed in Config.Seeds do
		for stage = 0, CropVisuals.STAGES do
			local muts = { false }
			if stage == CropVisuals.STAGES then
				for _, m in Config.Mutations do table.insert(muts, m.id) end
			end
			for _, mut in muts do
				local okB, model = pcall(CropVisuals.buildModel, top, seed, stage, if mut then mut else nil)
				local tag = seed.id .. ":" .. stage .. ":" .. tostring(mut)
				if not okB then
					table.insert(bad, tag .. " error " .. tostring(model))
					continue
				end
				built += 1
				local n = CropVisuals.partCount(model)
				if n > maxParts then maxParts, maxName = n, tag end
				if n == 0 or n > CropVisuals.MAX_PARTS then table.insert(bad, tag .. " parts " .. n) end
				if model:GetAttribute("Parts") ~= n then table.insert(bad, tag .. " Parts attr") end
				if (model:GetPivot().Position - top.Position).Magnitude > 0.01 then table.insert(bad, tag .. " pivot") end
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and (not d.Anchored or d.CanCollide) then
						table.insert(bad, tag .. " " .. d.Name .. " not anchored / collides")
						break
					end
				end
				model:Destroy()
			end
		end
	end
	check("all crop models build (12 seeds x 6 stages + 5 mutations each)", #bad == 0 and built == 12 * 11, built .. " built; " .. table.concat(bad, " | "))
	check("crop part budget per tile <= " .. CropVisuals.MAX_PARTS, maxParts <= CropVisuals.MAX_PARTS, maxParts .. " (" .. maxName .. ")")
	-- ripe fruit must look different from unripe fruit, and a mutation must change the look again
	local function fruitOf(stage, mut)
		local model = CropVisuals.buildModel(top, Config.SeedById.tomato, stage, mut)
		local f = model:FindFirstChild("Fruit")
		local color, material = f and f.Color, f and f.Material
		model:Destroy()
		return color, material
	end
	local cUnripe = fruitOf(3, nil)
	local cRipe = fruitOf(5, nil)
	local cGold, mGold = fruitOf(5, "Golden")
	check("unripe vs ripe vs mutated fruit are visually distinct", cUnripe ~= nil and cRipe ~= nil and cUnripe ~= cRipe and cGold ~= cRipe and mGold == Enum.Material.Foil)

	-- 5. locked tiles look like lawn, unlocked ones like soil
	if s then
		local tiles = workspace.Plots["Plot_" .. s.plotIndex].Tiles
		check("locked tile is lawn, unlocked tile is soil", tiles.Tile_30.Material == Enum.Material.LeafyGrass and tiles.Tile_1.Material == Enum.Material.Ground)
	end
end
local okWorld, errWorld = pcall(worldTests)
check("world/visual tests ran", okWorld, errWorld)

-- client attributes don't replicate, so the client talks back through this event
local ev = Instance.new("RemoteEvent")
ev.Name = "__Test"
ev.Parent = game:GetService("ReplicatedStorage")
-- Server-side flags live in plain Lua state (the handler runs on its own thread; the wait loop below polls them).
local growNow, weatherNow, p0Now, perfNow, clientDone, clientReport = false, false, false, false, false, ""
ev.OnServerEvent:Connect(function(p, kind, arg)
	if p ~= player then return end
	if kind == "GrowNow" then
		growNow = true
	elseif kind == "Weather" then
		weatherNow = true
	elseif kind == "P0" then
		p0Now = true
	elseif kind == "Perf" then
		perfNow = true
	elseif kind == "Done" then
		clientReport = if type(arg) == "string" then arg else tostring(arg)
		clientDone = true
	end
end)

-- Weather event + growth while it's active (runs when the client asks, so the client can check the banner).
local function weatherTest()
	local Weather = require(Services.Weather)
	local Garden = require(Services.Garden)
	local okStart, err = pcall(Weather.start, "Rain", 20)
	check("Weather.start Rain", okStart, err)
	check("weather is Rain", Weather.id() == "Rain", Weather.id())
	check("rain boosts growth", Weather.growthMult() >= 1, Weather.growthMult())
	if not s then return end
	s.profile.seeds.carrot = (s.profile.seeds.carrot or 0) + 1
	s.profile.tiles["1"] = nil
	local okPlant, msg = Garden.plant(s, 1, "carrot")
	check("plant during weather", okPlant, msg)
	local t = s.profile.tiles["1"]
	local p0 = t and t.progress or -1
	task.wait(3.5)
	t = s.profile.tiles["1"]
	local p1 = t and t.progress or -1
	check("crop grows during weather", p1 > p0 and p0 >= 0, string.format("%.3f -> %.3f", p0, p1))
end


-- ===== Performance: measure a normal late-game moment (30 tiles growing) and hold the budgets =====
local function perfTest()
	local RunService = game:GetService("RunService")
	local HttpService = game:GetService("HttpService")
	local Stats = game:GetService("Stats")
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local Remotes = require(Services.Remotes)
	local Garden = require(Services.Garden)
	if not s then return end
	local p = s.profile
	p.tilesOwned = Config.MaxTiles
	table.clear(p.tiles)
	for i = 1, Config.MaxTiles do
		p.tiles[tostring(i)] = { seed = Config.Seeds[(i - 1) % #Config.Seeds + 1].id, progress = 0.1 + (i % 7) * 0.1 }
	end
	Garden.renderAll(s)
	Session.markDirty(s)
	task.wait(1.5)

	local plot = workspace.Plots["Plot_" .. s.plotIndex]
	local attrChanges = 0
	local conns = {}
	for _, tile in plot.Tiles:GetChildren() do
		table.insert(conns, tile.AttributeChanged:Connect(function() attrChanges += 1 end))
	end
	local sentBefore, reqBefore = 0, Remotes.requests
	for _, n in Remotes.sent do sentBefore += n end
	local frames, total, worst = 0, 0, 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		frames += 1
		total += dt
		worst = math.max(worst, dt)
	end))
	local WINDOW = 6
	task.wait(WINDOW)
	for _, c in conns do c:Disconnect() end
	local sentAfter = 0
	for _, n in Remotes.sent do sentAfter += n end
	local remotesPerSec = (sentAfter - sentBefore) / WINDOW
	local requestsPerSec = (Remotes.requests - reqBefore) / WINDOW
	local attrPerSec = attrChanges / WINDOW
	local stateBytes = #HttpService:JSONEncode(Session.buildState(s))

	local instances, parts, cropParts, guis = 0, 0, 0, 0
	for _, d in workspace:GetDescendants() do
		instances += 1
		if d:IsA("BasePart") and not d:IsA("Terrain") then
			parts += 1
			if d:FindFirstAncestor("Crop") then cropParts += 1 end
		elseif d:IsA("LayerCollector") then
			guis += 1
		end
	end
	local memory = Stats:GetTotalMemoryUsageMb()
	local avgMs, worstMs = total / math.max(frames, 1) * 1000, worst * 1000
	print(string.format("[TEST] PERF server: workspace %d instances, %d parts (%d in 30 crops), %d world guis | heartbeat %.1f ms avg, %.1f ms worst | memory %.0f MB (Studio: server+client share a process)", instances, parts, cropParts, guis, avgMs, worstMs, memory))
	print(string.format("[TEST] PERF network: %.2f remote events/s, %.2f requests/s, %.1f tile attribute changes/s, state snapshot %d bytes", remotesPerSec, requestsPerSec, attrPerSec, stateBytes))
	-- budgets: these fail the playtest when someone blows them
	check("budget: workspace parts with a full plot <= 5200", parts <= 5200, parts)
	check("budget: a full plot of 30 crops <= 480 parts", cropParts <= 480, cropParts)
	check("budget: idle remote traffic <= 1 event/s", remotesPerSec <= 1, remotesPerSec)
	check("budget: tile attribute replication <= 20 changes/s per plot", attrPerSec <= 20, attrPerSec)
	check("budget: state snapshot <= 6000 bytes", stateBytes <= 6000, stateBytes)
	check("budget: server heartbeat <= 25 ms avg while 30 crops grow", avgMs <= 25, string.format("%.1f", avgMs))
end

-- Answer the client handshake with a remote (client attributes don't replicate server-side).
player:SetAttribute("ServerReady", true)
local deadline = os.clock() + 150
while not clientDone and os.clock() < deadline do
	if growNow and s then
		growNow = false
		for _, t in s.profile.tiles do t.progress = 0.999 end
	end
	if p0Now and s then
		-- fake a long session (all play-time gifts ready) and a complete Tomato Index row for the client checks
		p0Now = false
		s.sessionStart = os.time() - 3600
		table.clear(s.giftsClaimed)
		local row = {}
		for _, v in { "Normal", "Rainbow", "Shocked", "Golden", "Frozen", "Wet" } do row[v] = true end
		s.profile.index.tomato = row
		s.profile.indexClaimed.tomato = nil
		Session.markDirty(s)
		task.wait(0.4)
		ev:FireClient(player, "P0Ready")
	end
	if perfNow then
		perfNow = false
		local okPerf, errPerf = pcall(perfTest)
		check("performance test ran", okPerf, errPerf)
		ev:FireClient(player, "PerfDone")
	end
	if weatherNow then
		weatherNow = false
		local ok, err = pcall(weatherTest)
		check("weather test ran", ok, err)
		ev:FireClient(player, "WeatherDone")
	end
	task.wait(0.25)
end
check("client finished", clientDone)

-- ===== P0 systems (server side) =====
local function p0Tests()
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local Social = require(Services.Social)
	local Events = require(Services.Events)
	local Weather = require(Services.Weather)
	if not s then return end
	-- Index is recorded on harvest (the client harvested carrots through HarvestAll)
	check("index recorded Normal carrot on harvest", s.profile.index.carrot ~= nil and s.profile.index.carrot.Normal == true)
	-- referral: bad/self LaunchData rejected, a fake invite accepted once with the invitee gift
	local cornBefore = s.profile.seeds.corn or 0
	check("referral rejects bad LaunchData", not Social.onJoin(s, "ref:abc") and not Social.onJoin(s, "ref:" .. player.UserId) and not Social.onJoin(s, nil))
	s.profile.referredBy = 0
	local okRef = Social.onJoin(s, "ref:123456")
	check("referral invitee gift", okRef and s.profile.referredBy == 123456 and (s.profile.seeds.corn or 0) == cornBefore + Config.ReferralInviteeGift.seeds.corn, s.profile.referredBy)
	check("referral only once", not Social.onJoin(s, "ref:654321") and s.profile.referredBy == 123456)
	check("inviter not credited before 10 min", not Social.creditInviter(s) or s.profile.playTime >= 600)
	s.profile.playTime = 700
	check("inviter credited after 10 min (no store in Studio)", Social.creditInviter(s) and s.profile.referralPaid)
	-- notification opt-in: fires once per cooldown
	s.profile.notifAskedAt = 0
	Social.happyMoment(s)
	local askedAt = s.profile.notifAskedAt
	Social.happyMoment(s)
	check("notification ask throttled", askedAt > 0 and s.profile.notifAskedAt == askedAt)
	-- Starter Pack is hidden while its product id is 0
	check("starter pack hidden with id 0", Session.starterInfo(s).available == false)
	-- live event override: Harvest Festival forces Golden Hour, boosts, rare restock; clearing restores
	local okEv, errEv = pcall(Events.setOverride, { id = "HarvestFestival", endsAt = os.time() + 120 })
	check("event override applied", okEv and Events.id() == "HarvestFestival", errEv or Events.id())
	check("festival forces Golden Hour", Weather.forced and Weather.id() == "GoldenHour", Weather.id())
	check("festival multipliers", Events.mutationMult() == 3 and Events.growthMult() == 2)
	local mythic = 0
	for _, seed in Config.Seeds do
		if (seed.rarity == "Mythic" or seed.rarity == "Divine") and (s.stock[seed.id] or 0) > 0 then mythic += 1 end
	end
	check("festival guarantees a Mythic+ seed in stock", mythic >= 1, mythic)
	check("bad admin command rejected", Events.parseCommand("/event Nope 5") == nil and Events.parseCommand("/event LuckyHour 999") == nil)
	local parsed = Events.parseCommand("/event LuckyHour 10")
	check("admin command parsed", parsed ~= nil and parsed.id == "LuckyHour" and parsed.endsAt > os.time())
	Events.setOverride(nil)
	check("override cleared restores weather cycle", Events.id() ~= "HarvestFestival" and not Weather.forced and Weather.id() == nil, tostring(Events.id()) .. "/" .. tostring(Weather.id()))
end

-- ===== Auto-farm (server is the authority; tests drive the rounds directly so they don't depend on wall time) =====
local function autoFarmTests()
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local Rules = require(game:GetService("ReplicatedStorage").Shared.AutoFarm)
	local AutoFarm = require(Services.AutoFarm)
	local Data = require(Services.Data)
	if not s then return end
	local p = s.profile
	local function setup(level, pass, ripe, empty)
		p.upgrades.Farmhand = level
		s.passes.AutoHarvest = pass
		p.auto = { harvest = true, plant = true, sell = true, seed = "carrot" }
		p.tilesOwned = ripe + empty
		table.clear(p.tiles)
		for i = 1, ripe do p.tiles[tostring(i)] = { seed = "carrot", progress = 1 } end
		table.clear(p.backpack)
		table.clear(p.seeds)
		p.seeds.carrot = 50
		s.autoAt = 0
	end
	local function filled()
		local n = 0
		for _ in p.tiles do n += 1 end
		return n
	end

	setup(0, false, 4, 2)
	local r = AutoFarm.step(s)
	check("auto-farm locked: nothing happens without the upgrade or the pass", r.harvested == 0 and r.planted == 0 and r.sold == 0 and Session.backpackCount(s) == 0)
	check("auto-farm locked: paced tick does nothing either", AutoFarm.tick(s, 1000) == nil)

	setup(1, false, 4, 2)
	r = AutoFarm.step(s)
	check("auto-farm Lv1 harvests by itself, 2 tiles per round, nothing else", r.harvested == 2 and r.planted == 0 and r.sold == 0 and Session.backpackCount(s) == 2, string.format("h%d p%d s%d", r.harvested, r.planted, r.sold))

	setup(1, false, 6, 0)
	local t1 = AutoFarm.tick(s, 2000)
	local t2 = AutoFarm.tick(s, 2001)
	local t3 = AutoFarm.tick(s, 2004.9)
	local t4 = AutoFarm.tick(s, 2005)
	check("auto-farm respects its pace (Lv1: one round every 5 s)", t1 ~= nil and t1.harvested == 2 and t2 == nil and t3 == nil and t4 ~= nil and t4.harvested == 2 and Session.backpackCount(s) == 4, Session.backpackCount(s))

	setup(2, false, 0, 6)
	r = AutoFarm.step(s)
	check("auto-farm Lv2 replants with the chosen seed, 3 tiles per round", r.planted == 3 and filled() == 3 and p.seeds.carrot == 47 and p.tiles["1"].seed == "carrot", string.format("planted %d filled %d", r.planted, filled()))
	p.auto.seed = ""
	r = AutoFarm.step(s)
	check("auto-plant needs a chosen seed", r.planted == 0)
	p.auto.seed = "carrot"
	p.seeds.carrot = 1
	r = AutoFarm.step(s)
	check("auto-plant stops when the seeds run out", r.planted == 1 and (p.seeds.carrot or 0) == 0)

	setup(3, false, 0, 6)
	local cap = Session.backpackCap(s)
	p.backpack[Session.basketKey("carrot", nil)] = cap - 1
	local cashBefore = p.cash
	r = AutoFarm.step(s)
	check("auto-sell waits until the basket is full", r.sold == 0 and p.cash == cashBefore and Session.backpackCount(s) == cap - 1)
	p.backpack[Session.basketKey("carrot", nil)] = cap
	r = AutoFarm.step(s)
	check("auto-farm Lv3 sells a full basket from anywhere", r.sold == cap and p.cash > cashBefore and Session.backpackCount(s) == 0, r.sold)

	setup(3, false, 3, 0)
	p.auto.harvest = false
	r = AutoFarm.step(s)
	check("a switched-off mode does not run even when unlocked", r.harvested == 0 and Session.backpackCount(s) == 0)

	setup(0, true, 12, 0)
	local info = Session.autoInfo(s)
	r = AutoFarm.step(s)
	check("the Auto Harvest pass unlocks everything at full speed", info.allowed.harvest and info.allowed.plant and info.allowed.sell and info.interval == 1 and info.batch == 30 and r.harvested == 12, string.format("interval %d batch %d harvested %d", info.interval, info.batch, r.harvested))
	s.passes.AutoHarvest = false

	-- state + persistence
	setup(2, false, 0, 1)
	p.auto = { harvest = false, plant = true, sell = true, seed = "corn" }
	local st = Session.buildState(s).auto
	check("state carries the auto-farm status", st.level == 2 and st.wanted.plant and st.on.plant and not st.on.harvest and not st.on.sell and not st.allowed.sell and st.seed == "corn" and st.interval == 4 and st.batch == 3)
	local def = Data.defaultProfile()
	check("new profiles save the auto-farm switches", type(def.auto) == "table" and def.auto.harvest == true and def.auto.plant == false and def.auto.seed == "")
	p.auto = nil :: any
	local legacy = Session.autoInfo(s)
	check("saves from before auto-farm load with safe defaults", legacy.wanted.harvest == true and legacy.wanted.plant == false and legacy.seed == "")
	check("Farmhand is kept through a rebirth (config)", Config.UpgradeById.Farmhand.keepOnRebirth == true and Config.UpgradeById.GrowSpeed.keepOnRebirth ~= true)
	check("auto-farm never beats the pass", Rules.batch(Config.AutoFarm, 3, false) / Rules.interval(Config.AutoFarm, 3, false) < Rules.batch(Config.AutoFarm, 0, true) / Rules.interval(Config.AutoFarm, 0, true))
	p.auto = { harvest = false, plant = false, sell = false, seed = "" }
end

local okP0, errP0 = pcall(p0Tests)
check("P0 server tests ran", okP0, errP0)

-- ===== Published chances = rolled chances (paid random items rules) =====
local function oddsTests()
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config)
	local Odds = require(RS.Shared.Odds)
	local Rewards = require(Services.Rewards)
	local Garden = require(Services.Garden)
	local Weather = require(Services.Weather)
	local Events = require(Services.Events)
	if not s then return end
	local pool = {}
	for _, r in Odds.luckyTable() do pool[r.id] = r.pct end
	table.clear(s.profile.seeds)
	local ids = Rewards.luckyPack(s, 1)
	local okPack, got = #ids == Odds.LuckyPerPack, 0
	for _, id in ids do
		local seed = Config.SeedById[id]
		if not pool[id] or not seed or seed.rarity == "Common" or seed.rarity == "Uncommon" then okPack = false end
	end
	for _, n in s.profile.seeds do got += n end
	check("Lucky Seed Pack always gives 3 seeds, Rare or better, from the published pool", okPack and got == 3, table.concat(ids, ","))
	local N, counts = 30000, {}
	for _ = 1, N do
		local id = Rewards.luckySeed()
		counts[id] = (counts[id] or 0) + 1
	end
	local off = {}
	for id, pct in pool do
		local f = (counts[id] or 0) / N * 100
		if math.abs(f - pct) > 1.2 then table.insert(off, string.format("%s %.1f%% vs %.1f%%", id, f, pct)) end
	end
	check("Lucky Seed Pack rolls match the published percentages (30k rolls)", #off == 0, table.concat(off, " | "))

	local ctx = { luck = Session.luckMult(s), weather = Weather.id(), goldenMult = Weather.goldenMult(), eventMult = Events.mutationMult() }
	local published = {}
	local total = 0
	for _, r in Odds.mutationTable(Config.Mutations, ctx) do
		published[r.id] = r.pct
		total += r.pct
	end
	check("mutation chances add up to 100%", math.abs(total - 100) < 1e-6, total)
	local mc = {}
	for _ = 1, N do
		local m = Garden.rollMutation(s) or "Normal"
		mc[m] = (mc[m] or 0) + 1
	end
	off = {}
	for id, pct in published do
		local f = (mc[id] or 0) / N * 100
		if math.abs(f - pct) > 0.6 then table.insert(off, string.format("%s %.2f%% vs %.2f%%", id, f, pct)) end
	end
	check("mutation rolls match the published percentages (30k rolls, luck " .. tostring(ctx.luck) .. ")", #off == 0, table.concat(off, " | "))

	check("Starter Pack has fixed contents (no random item inside)", (Config.StarterPackGrant :: any).luckyPack == nil and Config.StarterPackGrant.seeds.apple == 1)
	s.paidRandomAllowed = false
	local hidden = Session.buildState(s).policy.paidRandom
	s.paidRandomAllowed = true
	local shown = Session.buildState(s).policy.paidRandom
	check("state tells the client whether paid random items may be offered", hidden == false and shown == true)
	check("restricted players are not offered the Lucky Pack nor the luck pass", not Odds.canOffer("LuckyPack", false) and not Odds.canOffer("SuperLuck", false) and Odds.canOffer("VIP", false))
	Session.markDirty(s)
end

local okAuto, errAuto = pcall(autoFarmTests)
check("auto-farm server tests ran", okAuto, errAuto)

-- ===== Wild Patch =====
local function wildTests()
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config)
	local Rules = require(RS.Shared.Wild)
	local Wild = require(Services.Wild)
	if not s then return end
	local folder = workspace:FindFirstChild("WildPatch")
	local built, prompts = 0, 0
	if folder then
		for i = 1, Rules.NODES do
			local node = folder:FindFirstChild("WildNode_" .. i)
			local crop = node and node:FindFirstChild("Crop")
			if crop and crop:GetAttribute("Stage") == 5 and node:GetAttribute("SeedId") == Wild.seedAt(i) and Config.SeedById[Wild.seedAt(i) :: string] then built += 1 end
			if node and node:FindFirstChild("Prompt") then prompts += 1 end
		end
	end
	check("Wild Patch: 6 ripe rare plants with a pick prompt", built == 6 and prompts == 6, built .. "/" .. prompts)
	local expected = Rules.nodes(Rules.cycle(os.time()))
	check("Wild Patch grows what the clock says (same on every server)", Wild.seedAt(1) == expected[1] and Wild.seedAt(6) == expected[6])
	s.profile.wild = { cycle = 0, claimed = {} }
	local seed1 = Wild.seedAt(1) :: string
	local before = s.profile.seeds[seed1] or 0
	local ok1 = Wild.pick(s, 1)
	check("picking a wild node gives its seed", ok1 and (s.profile.seeds[seed1] or 0) == before + 1)
	local ok2 = Wild.pick(s, 1)
	check("the same node can't be picked twice in a cycle", not ok2 and (s.profile.seeds[seed1] or 0) == before + 1)
	check("bad wild node rejected", not Wild.pick(s, 99) and not Wild.pick(s, "1") and not Wild.pick(s, nil))
	local st = Session.buildState(s).wild
	check("state carries the Wild Patch clock and picks", st.left == 5 and #st.claimed == 1 and st.claimed[1] == 1 and st.nextAt > os.time() and st.nextAt - os.time() <= 3600, st.left)
	check("wild picks are saved in the profile", s.profile.wild.cycle == Rules.cycle(os.time()) and s.profile.wild.claimed["1"] == true)
	s.profile.wild.cycle -= 1
	check("the next hour resets the patch for the player", Session.buildState(s).wild.left == 6 and Wild.pick(s, 1))
	local a, b = Session.buildState(s).rev, Session.buildState(s).rev
	check("state snapshots are numbered", type(a) == "number" and b == a + 1)
	s.profile.wild = { cycle = 0, claimed = {} }
	Session.markDirty(s)
end

local okOdds, errOdds = pcall(oddsTests)
check("odds tests ran", okOdds, errOdds)

-- ===== Crop sizes, trophy shelf, save pacing, offline growth =====
local function round6Tests()
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config)
	local Rules = require(RS.Shared.Trophies)
	local Trophies = require(Services.Trophies)
	local Garden = require(Services.Garden)
	local Data = require(Services.Data)
	local CropVisuals = require(ServerScriptService.Server.World.CropVisuals)
	if not s then return end
	local p = s.profile
	p.tilesOwned = 6
	table.clear(p.tiles)
	table.clear(p.backpack)
	p.trophies = {}
	p.tiles["1"] = { seed = "carrot", progress = 1, size = "Giant" }
	p.tiles["2"] = { seed = "carrot", progress = 1 }
	p.tiles["3"] = { seed = "tomato", progress = 1, mut = "Golden", size = "Big" }
	Garden.renderAll(s)
	local plot = workspace.Plots["Plot_" .. s.plotIndex]
	local giant = plot.Tiles.Tile_1:FindFirstChild("Crop")
	local normal = plot.Tiles.Tile_2:FindFirstChild("Crop")
	check("a Giant crop is visibly bigger on its tile", giant ~= nil and normal ~= nil and giant:GetAttribute("BaseScale") == Rules.scale("Giant") and giant:GetExtentsSize().Y > normal:GetExtentsSize().Y * 1.3, giant and giant:GetExtentsSize().Y)
	check("harvest keeps the size", Garden.harvest(s, 1) and Garden.harvest(s, 2) and Garden.harvest(s, 3) and p.backpack["carrot||Giant"] == 1 and p.backpack["carrot|"] == 1 and p.backpack["tomato|Golden|Big"] == 1)
	local plain = Session.itemValue(s, "carrot", nil, nil)
	-- (values are floored after the cash multiplier, so compare with a rounding margin)
	local giantV, bigV, goldV = Session.itemValue(s, "carrot", nil, "Giant"), Session.itemValue(s, "tomato", "Golden", "Big"), Session.itemValue(s, "tomato", "Golden", nil)
	check("a Giant crop sells for 3x, a Big one for 1.5x", math.abs(giantV - plain * 3) <= 3 and math.abs(bigV - goldV * 1.5) <= 2, string.format("%d vs %d, %d vs %d", giantV, plain * 3, bigV, goldV * 1.5))
	p.backpack["tomato|Wet"] = 2
	check("baskets saved before sizes still count", Session.backpackValue(s) == giantV + plain + bigV + 2 * Session.itemValue(s, "tomato", "Wet", nil), Session.backpackValue(s))
	local st = Session.buildState(s)
	local sized = false
	for _, it in st.backpack do
		if it.key == "carrot||Giant" and it.size == "Giant" and it.count == 1 then sized = true end
	end
	check("state lists the basket with keys and sizes", sized)

	local luckBefore = Session.luckMult(s)
	check("a plain crop can't go on a pedestal", not Trophies.exhibit(s, "carrot|"))
	check("a crop you don't have can't be exhibited", not Trophies.exhibit(s, "pumpkin||Giant") and not Trophies.exhibit(s, 5) and not Trophies.exhibit(s, nil))
	check("exhibit a Giant crop", Trophies.exhibit(s, "carrot||Giant") and #p.trophies == 1 and p.backpack["carrot||Giant"] == nil)
	check("the trophy gives luck (+15%)", math.abs(Session.trophyLuck(s) - 0.15) < 1e-9 and math.abs(Session.luckMult(s) - luckBefore * 1.15) < 1e-9, Session.luckMult(s))
	check("the trophy stands on the plot's pedestal", plot:FindFirstChild("Pedestal_1") ~= nil and plot.Pedestal_1:FindFirstChild("Crop") ~= nil and plot.Pedestal_2:FindFirstChild("Crop") == nil)
	check("exhibit a Big Golden crop and a Wet one", Trophies.exhibit(s, "tomato|Golden|Big") and Trophies.exhibit(s, "tomato|Wet") and #p.trophies == 3)
	check("trophy luck adds up", math.abs(Session.trophyLuck(s) - (0.15 + 0.15 + 0.02)) < 1e-9, Session.trophyLuck(s))
	check("the 4th trophy is refused (3 pedestals)", not Trophies.exhibit(s, "tomato|Wet") and p.backpack["tomato|Wet"] == 1)
	local st2 = Session.buildState(s)
	check("state carries the trophies and their luck", #st2.trophies == 3 and st2.trophies[1].size == "Giant" and math.abs(st2.trophyLuck - 0.32) < 1e-9)
	check("take a trophy back", Trophies.takeBack(s, 1) and #p.trophies == 2 and p.backpack["carrot||Giant"] == 1)
	check("bad pedestal slot rejected", not Trophies.takeBack(s, 9) and not Trophies.takeBack(s, "1") and not Trophies.takeBack(s, 1.5))
	local cap = Session.backpackCap(s)
	p.backpack["carrot|"] = cap
	check("a full basket can't take a trophy back", not Trophies.takeBack(s, 1) and #p.trophies == 2)
	table.clear(p.backpack)
	p.trophies = {}
	Garden.renderAll(s)
	check("an emptied shelf clears the pedestals and the luck", plot.Pedestal_1:FindFirstChild("Crop") == nil and Session.trophyLuck(s) == 0)

	-- offline growth is counted so the player can be told
	table.clear(p.tiles)
	p.tiles["1"] = { seed = "carrot", progress = 0 }
	p.tiles["2"] = { seed = "carrot", progress = 0.5 }
	p.tiles["3"] = { seed = "carrot", progress = 1 }
	local savedAt = p.savedAt
	p.savedAt = os.time() - 3600
	local grew = Garden.applyOffline(s)
	p.savedAt = savedAt
	check("offline growth reports how many crops ripened", grew == 2 and p.tiles["1"].progress >= 1, grew)
	table.clear(p.tiles)
	Garden.renderAll(s)

	check("autosave is spread across the interval", Data.autosaveGap(90, 6) == 15 and Data.autosaveGap(90, 1) == 90 and Data.autosaveGap(90, 0) == 90)
	local silent, noSeedProducts = true, true
	for _, id in Config.Sounds do if id ~= 0 then silent = false end end
	for _, id in Config.SeedProducts do if id ~= 0 then noSeedProducts = false end end
	check("audio and seed-product IDs ship empty", silent and noSeedProducts)
	local model = CropVisuals.buildModel(CFrame.new(0, 600, 0), Config.SeedById.pumpkin, 5, "Golden", "Giant", 0.7)
	check("trophy models are built scaled", math.abs(model:GetAttribute("BaseScale") - 1.6 * 0.7) < 1e-6)
	model:Destroy()
	Session.markDirty(s)
end

local okWild, errWild = pcall(wildTests)
check("wild patch tests ran", okWild, errWild)
local okR6, errR6 = pcall(round6Tests)
check("sizes / trophies / saves tests ran", okR6, errR6)
for line in string.gmatch(clientReport, "[^\n]+") do
	if line:sub(1, 4) == "FAIL" then
		print("[TEST] client " .. line)
	else
		local name = line:gsub("^PASS ", ""):gsub(" :: .*$", "")
		table.insert(passed, "c:" .. name)
	end
	table.insert(results, "client " .. line)
end
check("no server errors", #errors == 0, table.concat(errors, " || "))
local fails = 0
for _, r in results do if r:sub(1, 4) == "FAIL" or r:find("client FAIL") then fails += 1 end end
do
	local buf, len = {}, 0
	for _, name in passed do
		if len + #name > 420 and #buf > 0 then
			print("[TEST] ok: " .. table.concat(buf, " | "))
			buf, len = {}, 0
		end
		table.insert(buf, name)
		len += #name + 3
	end
	if #buf > 0 then
		print("[TEST] ok: " .. table.concat(buf, " | "))
	end
end
print("[TEST SUMMARY] " .. #results .. " checks, " .. fails .. " failures")
task.wait(1)
StudioTestService:EndTest(fails)
