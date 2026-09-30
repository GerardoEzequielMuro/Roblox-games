-- Gameplay test harness (only in test.project.json builds). Runs inside a real Studio playtest.
-- The client (AutoTestClient) drives the run through the real remotes and HUD code; this script
-- checks the server side, answers the client's queries through __TestRF (including "put me on
-- pad N", which also waits for that stretch of tower to stream in), measures performance against
-- the budgets and ends the test.
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")
local DataStoreService = game:GetService("DataStoreService")
local Stats = game:GetService("Stats")

local errors, warns = {}, {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(errors, msg)
	elseif kind == Enum.MessageType.MessageWarning then
		table.insert(warns, msg)
	end
end)

local results = {}
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail ~= nil then " :: " .. tostring(detail) else "")
	print("[TEST] " .. line)
	table.insert(results, line)
end

local Server = ServerScriptService:WaitForChild("Server")
local Data = require(Server:WaitForChild("Data"))
local Session = require(Server:WaitForChild("Session"))
local Checkpoints = require(Server:WaitForChild("Checkpoints"))
local Towers = require(Server:WaitForChild("Towers"))
local Obstacles = require(Server:WaitForChild("Obstacles"))
local Shops = require(Server:WaitForChild("Shops"))
local Referrals = require(Server:WaitForChild("Referrals"))
local Events = require(Server:WaitForChild("Events"))
local Monetization = require(Server:WaitForChild("Monetization"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

-- Pricing: every item of the intended price list has a slot for its Dashboard ID in Config
do
	local Pricing = require(Shared:WaitForChild("Pricing"))
	local missing = {}
	for key in Pricing.Products do
		if Config.Products[key] == nil then table.insert(missing, "Products." .. key) end
	end
	for key in Pricing.Passes do
		if Config.Passes[key] == nil then table.insert(missing, "Passes." .. key) end
	end
	check("every priced product/pass has a Config ID slot", #missing == 0, table.concat(missing, ","))
	check("starter anchor matches list prices", Config.StarterPackAnchorPrice == Pricing.starterValue(Config.StarterPackSkips, Config.StarterPackCoins), Config.StarterPackAnchorPrice)
end
local Layout = require(Shared:WaitForChild("Layout"))
local Rules = require(Shared:WaitForChild("Rules"))
local Powerups = require(Shared:WaitForChild("Powerups"))
local Perks = require(Shared:WaitForChild("Perks"))

-- Budgets. The playtest fails if somebody goes over.
local BUDGET = {
	towerParts = 7200, -- parts of one tower (stages + pads + shops + summit + scenery)
	lobbyParts = 700,
	sceneryParts = 4200, -- scenery of tower 1 + lobby dressing
	lights = 110,
	emitters = 110,
	worldGuis = 560, -- SurfaceGui + BillboardGui per tower (icons, captions, numbers)
	awakeObstacles = 90, -- animated obstacles running for one player
	serverHeartbeatMs = 20,
	clientPartsLobby = 5200, -- what a client standing in the lobby has loaded (streaming)
	stateBytes = 2600,
}

-- 1. the first tower ---------------------------------------------------------------------------
local towersFolder = workspace:WaitForChild("Towers", 90)
check("Towers folder built", towersFolder ~= nil)
local t0w = os.clock()
while not Towers.get(1) and os.clock() - t0w < 60 do task.wait(0.2) end
local tower1 = Towers.get(1)
check("tower 1 built", tower1 ~= nil)
if not tower1 then
	print("[TEST SUMMARY] tower 1 never built - aborting")
	StudioTestService:EndTest(1)
	return
end
local padCount, missing = 0, {}
for k = 0, 100 do
	if tower1.pads[k] then padCount += 1 else table.insert(missing, k) end
end
check("101 checkpoint pads (0..100)", padCount == 101, padCount .. " missing:" .. table.concat(missing, ","))
local stageModels, kinds = 0, {}
for _, m in tower1.folder:GetChildren() do
	if m:IsA("Model") and m.Name:match("^Stage_%d+") then
		stageModels += 1
		local k = m:GetAttribute("Kind")
		kinds[k] = (kinds[k] or 0) + 1
	end
end
check("100 stage models", stageModels == 100, stageModels)
local kindList = {}
for k, n in kinds do table.insert(kindList, k .. "=" .. n) end
table.sort(kindList)
print("[TEST] INFO kinds " .. table.concat(kindList, " "))
check("all 17 obstacle kinds used in tower 1", #kindList == #Layout.Kinds, #kindList)
for _, tagName in { "Kill", "Mover", "Spinner", "Disappear", "Falling", "Lava", "Coin", "Glass", "Bounce", "Conveyor", "Laser", "Wind", "Flag", "BeltArrow", "PadDot" } do
	check("tagged " .. tagName .. " present", #CollectionService:GetTagged(tagName) > 0, #CollectionService:GetTagged(tagName))
end
local saves, rests = 0, 0
for g = 1, 100 do
	local pad = tower1.pads[g]
	if pad:GetAttribute("Save") then saves += 1 else rests += 1 end
	if pad:GetAttribute("Save") ~= Layout.isSave(g) then check("pad " .. g .. " save flag", false) end
end
check("saving pads 1-50 + every other after, rest pads in between", saves == 75 and rests == 25, saves .. " / " .. rests)
check("a flag on every saving pad", #CollectionService:GetTagged("Flag") == saves, #CollectionService:GetTagged("Flag"))

-- 1b. scenery: looks only, never in the way ------------------------------------------------------
local function census(root)
	local c = { instances = 0, parts = 0, emitters = 0, lights = 0, guis = 0, solid = 0, shadows = 0, unanchored = 0 }
	for _, d in root:GetDescendants() do
		c.instances += 1
		if d:IsA("BasePart") then
			c.parts += 1
			if d.CanCollide then c.solid += 1 end
			if d.CastShadow then c.shadows += 1 end
			if not d.Anchored then c.unanchored += 1 end
		elseif d:IsA("ParticleEmitter") then
			c.emitters += 1
		elseif d:IsA("Light") then
			c.lights += 1
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			c.guis += 1
		end
	end
	return c
end
local decor = workspace:WaitForChild("Decor", 10)
local lobbyScenery = decor and decor:FindFirstChild("LobbyScenery")
local scenery = tower1.folder:FindFirstChild("Decor") and tower1.folder.Decor:FindFirstChild("Scenery")
check("scenery folders built", scenery ~= nil and lobbyScenery ~= nil)
if scenery and lobbyScenery then
	local sceneryParts, unanchored, solid, inLane, worstLane = 0, 0, {}, 0, ""
	local LANE_INNER, LANE_OUTER = 42.4, 69.6 -- Shared/DecorPlan.lane()
	for _, folder in { scenery, lobbyScenery } do
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				sceneryParts += 1
				if not d.Anchored then unanchored += 1 end
				if d.CanCollide or d.CanTouch then table.insert(solid, d.Name) end
				if folder == scenery then
					local dist = Vector3.new(d.Position.X, 0, d.Position.Z).Magnitude
					local reach = d.Size.Magnitude / 2
					if dist + reach > LANE_INNER and dist - reach < LANE_OUTER then
						inLane += 1
						worstLane = d:GetFullName()
					end
				end
			end
		end
	end
	print("[TEST] INFO scenery parts: " .. sceneryParts)
	check("scenery within the part budget", sceneryParts > 600 and sceneryParts < BUDGET.sceneryParts, sceneryParts)
	check("scenery is anchored", unanchored == 0, unanchored)
	-- the two plinth steps around the core and the gift-preview pedestal are the only solid pieces
	check("scenery has no collisions / touches", #solid <= 3, table.concat(solid, ","))
	check("tower scenery stays out of the lanes", inLane == 0, inLane .. " " .. worstLane)
end
local dressSolid, skirts, caps, capSolid = 0, 0, 0, 0
for _, m in tower1.folder:GetChildren() do
	if m:IsA("Model") and m.Name:match("^Stage_") then
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "Skirt" or d.Name == "Rail" or d.Name == "RailStop" or d.Name == "LaserPost" or d.Name == "WindArrow") then
				skirts += 1
				if d.CanCollide or d.CanTouch or d.CanQuery then dressSolid += 1 end
			elseif d:IsA("BasePart") and d.Name == "Cap" then
				caps += 1
				if d.CanCollide or d.CanTouch or d.CanQuery then capSolid += 1 end
			end
		end
	end
end
check("platform dressing (skirts, rails, laser posts, wind arrows) is non-solid", skirts > 100 and dressSolid == 0, skirts .. " / solid " .. dressSolid)
check("platform top layers are non-solid", caps > 60 and capSolid == 0, caps .. " / solid " .. capSolid)
local noIcon = 0
for _, tagName in { "Mover", "Disappear", "Falling", "Bounce" } do
	for _, inst in CollectionService:GetTagged(tagName) do
		if not inst:FindFirstChild("Icon") then noIcon += 1 end
	end
end
check("special platforms carry their icon", noIcon == 0, noIcon)
check("conveyor / wind chevrons tagged for the running light", #CollectionService:GetTagged("BeltArrow") > 50, #CollectionService:GetTagged("BeltArrow"))

-- shops, summit, lounge, portal
local shops, shopPrompts, loungePrompts, portalPrompts = 0, 0, 0, 0
for _, m in tower1.folder:GetChildren() do
	if m.Name == "Shop" then shops += 1 end
end
for _, pr in tower1.prompts do
	if pr.kind == "shop" then shopPrompts += 1 elseif pr.kind == "lounge" then loungePrompts += 1 elseif pr.kind == "portal" then portalPrompts += 1 end
end
check("a shop at every world entrance (9 per tower)", shops == 9, shops)
check("7 pedestals per shop", shopPrompts == 9 * #Powerups.List and #Powerups.List == 7, shopPrompts)
check("lounge: one pedestal per free item", loungePrompts == #Perks.List, loungePrompts)
check("portal at the summit of tower 1", portalPrompts == 1 and tower1.portal ~= nil)
check("victory room dressed", tower1.folder:FindFirstChild("VictoryScenery") ~= nil and tower1.folder:FindFirstChild("Lounge") ~= nil)
check("only tower 1 exists at start (1,000 stages are not all in Workspace)", #towersFolder:GetChildren() == 1, #towersFolder:GetChildren())

-- 1c. performance: what the server holds --------------------------------------------------------
-- (the built world: the player's character is not part of it)
local worldCensus = census(towersFolder)
local towerCensus = census(tower1.folder)
for _, extra in { census(workspace.Lobby), census(workspace.Decor) } do
	for k, v in extra do worldCensus[k] += v end
end
local lobbyCensus = census(workspace.Lobby)
print(("[TEST] PERF server world: %d instances, %d parts (%d solid, %d casting shadows, %d unanchored), %d emitters, %d lights, %d world GUIs, memory %.0f MB"):format(
	worldCensus.instances, worldCensus.parts, worldCensus.solid, worldCensus.shadows, worldCensus.unanchored, worldCensus.emitters, worldCensus.lights, worldCensus.guis, Stats:GetTotalMemoryUsageMb()))
print(("[TEST] PERF tower 1: %d parts (%d casting shadows), %d emitters, %d lights, %d GUIs; lobby %d parts"):format(towerCensus.parts, towerCensus.shadows, towerCensus.emitters, towerCensus.lights, towerCensus.guis, lobbyCensus.parts))
check("BUDGET tower parts <= " .. BUDGET.towerParts, towerCensus.parts <= BUDGET.towerParts, towerCensus.parts)
check("BUDGET lobby parts <= " .. BUDGET.lobbyParts, lobbyCensus.parts <= BUDGET.lobbyParts, lobbyCensus.parts)
check("BUDGET lights <= " .. BUDGET.lights, worldCensus.lights <= BUDGET.lights, worldCensus.lights)
check("BUDGET particle emitters <= " .. BUDGET.emitters, worldCensus.emitters <= BUDGET.emitters, worldCensus.emitters)
check("BUDGET world GUIs <= " .. BUDGET.worldGuis, worldCensus.guis <= BUDGET.worldGuis, worldCensus.guis)
check("everything static is anchored", worldCensus.unanchored == 0, worldCensus.unanchored)
check("shadows only where they matter (< 25% of parts cast one)", worldCensus.shadows < worldCensus.parts * 0.25, ("%d of %d"):format(worldCensus.shadows, worldCensus.parts))

-- 2. player joins ---------------------------------------------------------------------------
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local t0 = os.clock()
while not (Session.get(player) and Session.get(player).loaded and Data.get(player)) and os.clock() - t0 < 40 do task.wait(0.2) end
local s = Session.get(player)
local p = Data.get(player)
check("session + profile loaded", s ~= nil and p ~= nil)
if not (s and p) then
	print("[TEST SUMMARY] server never loaded the player - aborting")
	StudioTestService:EndTest(1)
	return
end
print("[TEST] INFO datastore persistent: " .. tostring(Data.isPersistent(player)))
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
task.wait(2)
local lobbyCf = Checkpoints.spawnCFrame(player)
check("spawned in lobby", p.stage == 0 and (root.Position - lobbyCf.Position).Magnitude < 12, ("stage %d dist %.1f"):format(p.stage, (root.Position - lobbyCf.Position).Magnitude))
local ls = player:FindFirstChild("leaderstats")
check("leaderstats Stage/Wins", ls and ls:FindFirstChild("Stage") and ls:FindFirstChild("Wins"))
do
	-- the classic jump, and nothing switched on for a new player
	local hum = char:FindFirstChildOfClass("Humanoid")
	check("classic jump: JumpPower 50 (6.37 studs), WalkSpeed 16", hum.UseJumpPower == true and hum.JumpPower == 50 and hum.WalkSpeed == 16 and Config.JumpPower == Layout.Physics.jumpPower, ("power %s speed %s"):format(tostring(hum.JumpPower), tostring(hum.WalkSpeed)))
	check("no coil / extra jump for a new player", p.settings.speedCoil == false and p.settings.gravityCoil == false and root:FindFirstChild("GravityCoil") == nil and player:GetAttribute("AirJumps") == 0 and player:GetAttribute("Dash") == false)
	check("Studio does not hand out passes by default", Config.StudioOwnsPasses == false and not Session.hasPass(player, "SpeedCoil") and not Session.hasPass(player, "DoubleJump"))
end

-- 3. test channel -----------------------------------------------------------------------------
local function padPos(g)
	local pad = Towers.pad(g)
	return pad and pad.Position
end
local function standing(g)
	local spot = Rules.padOf(Layout, g)
	local tower = Towers.ensure(spot.tower)
	return tower.padCFrames[g]
end
local function moveTo(plr, cf)
	pcall(function() plr:RequestStreamAroundAsync(cf.Position, 4) end)
	local c = plr.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if r then
		r.AssemblyLinearVelocity = Vector3.zero
		c:PivotTo(cf)
	end
	return r ~= nil
end
local function snapshot()
	local pr = Data.get(player)
	local ss = Session.get(player)
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local st = pr and pr.stage or -1
	local at = ss and math.max(ss.at, st) or -1
	local padAt = padPos(math.max(st, 0))
	local built = {}
	for _, f in towersFolder:GetChildren() do table.insert(built, f:GetAttribute("Tower")) end
	table.sort(built)
	return {
		stage = st, at = at, best = pr and pr.best, base = pr and pr.base,
		coins = pr and pr.coins, wins = pr and pr.wins, freeSkips = pr and pr.freeSkips, codes = pr and pr.codes,
		leaderStage = ls.Stage.Value, leaderWins = ls.Wins.Value,
		inLobby = ss and ss.inLobby, persistent = Data.isPersistent(player),
		lobbyDist = r and (r.Position - lobbyCf.Position).Magnitude,
		spawnDist = r and (r.Position - Checkpoints.spawnCFrame(player).Position).Magnitude,
		padDist = r and padAt and (r.Position - padAt).Magnitude,
		rootPos = r and r.Position, health = hum and hum.Health, walkSpeed = hum and hum.WalkSpeed,
		runStart = ss and ss.run.start, runValid = ss and ss.run.valid, runFinalMs = ss and ss.run.finalMs,
		bestRunMs = pr and pr.bestRunMs, notifAskedAt = pr and pr.notifAskedAt,
		referredBy = pr and pr.referredBy, referralRewards = pr and pr.referralRewards,
		trails = pr and pr.trails, effects = pr and pr.effects, equippedTrail = pr and pr.equippedTrail, equippedEffect = pr and pr.equippedEffect,
		boostEndsAt = pr and pr.boostEndsAt, deaths = ss and ss.deaths.count,
		gifts = pr and pr.gifts, boosts = pr and pr.boosts, charges = pr and pr.charges, perks = pr and pr.perks,
		roam = ss and ss.roam, pocket = pr and pr.pocket ~= nil, help = ss and ss.help, towers = built,
		gravityCoil = r and r:FindFirstChild("GravityCoil") ~= nil,
		pet = c and c:FindFirstChild("SkyPet") ~= nil, crown = c and c:FindFirstChild("SkyCrown") ~= nil, glow = c and c:FindFirstChild("SkyGlow") ~= nil,
		jumpFx = hum and hum:GetAttribute("JumpFx"),
	}
end

local rf = Instance.new("RemoteFunction")
rf.Name = "__TestRF"
local clientDone, clientReport = false, ""
rf.OnServerInvoke = function(plr, kind, arg)
	local pr = Data.get(plr)
	local ss = Session.get(plr)
	if kind == "state" then
		return snapshot()
	elseif kind == "standOn" then
		-- onto pad `arg` (the tower is built and streamed in first)
		return moveTo(plr, standing(arg))
	elseif kind == "moveTo" then
		return moveTo(plr, arg)
	elseif kind == "padTop" then
		local pos = padPos(arg)
		return pos and pos + Vector3.new(0, Towers.pad(arg).Size.X / 2, 0)
	elseif kind == "warp" then
		-- test shortcut: as if the player had climbed to stage `arg` (a saving pad)
		pr.stage = arg
		pr.base = false
		pr.pocket = nil
		pr.best = math.max(pr.best, arg)
		ss.at = arg
		ss.coinStage = math.max(ss.coinStage, arg)
		ss.inLobby = false
		Session.assist(plr, "travelled")
		Checkpoints.teleport(plr)
		Session.push(plr)
		return true
	elseif kind == "coins" then
		pr.coins = arg
		Session.push(plr)
		return true
	elseif kind == "rewind" then
		ss.joined -= arg
		return true
	elseif kind == "killPart" then
		-- a plain kill strip on the lowest killbricks stage: a spot right on top of it
		local best, bestY = nil, math.huge
		for _, k in CollectionService:GetTagged("Kill") do
			if k.Name == "Kill" and k.Size.X > 6 and k.Position.Y < bestY then best, bestY = k, k.Position.Y end
		end
		return best and CFrame.new(best.Position + Vector3.new(0, best.Size.Y / 2 + 3, 0))
	elseif kind == "killMe" then
		local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 0 end
		return hum ~= nil
	elseif kind == "touch" then
		-- stand on the lowest part tagged `arg` (Disappear / Falling) and report what it does
		local best, bestY = nil, math.huge
		for _, k in CollectionService:GetTagged(arg) do
			if k:IsA("BasePart") and k.Position.Y < bestY then best, bestY = k, k.Position.Y end
		end
		if not best then return nil end
		local y0 = best.Position.Y
		moveTo(plr, CFrame.new(best.Position + Vector3.new(0, best.Size.Y / 2 + 3, 0)))
		local gone, back = false, false
		local t = os.clock()
		while os.clock() - t < 5 and not gone do
			gone = best.CanCollide == false or best.Position.Y < y0 - 10
			task.wait(0.1)
		end
		local iconOff = best:FindFirstChild("Icon") and best.Icon.Enabled == false
		t = os.clock()
		while os.clock() - t < 7 and not back do
			back = best.CanCollide == true and math.abs(best.Position.Y - y0) < 0.5
			task.wait(0.1)
		end
		return { gone = gone, back = back, iconHidden = iconOff }
	elseif kind == "obstacle" then
		-- does the lowest obstacle of a tag move / switch over `arg.seconds`? (nil = none built)
		local best, bestStage = nil, math.huge
		for _, k in CollectionService:GetTagged(arg.tag) do
			local st = k:GetAttribute("Stage")
			if k:IsA("BasePart") and type(st) == "number" and st < bestStage and st >= (arg.from or 0) then best, bestStage = k, st end
		end
		if not best then return nil end
		local p0, look0, t0x = best.Position, best.CFrame.LookVector, best.Transparency
		local moved, turned, switched, sizeMin, sizeMax = 0, 1, false, math.huge, -math.huge
		local t = os.clock()
		while os.clock() - t < arg.seconds do
			task.wait(0.1)
			moved = math.max(moved, (best.Position - p0).Magnitude)
			turned = math.min(turned, look0:Dot(best.CFrame.LookVector))
			switched = switched or math.abs(best.Transparency - t0x) > 0.2
			sizeMin, sizeMax = math.min(sizeMin, best.Size.Y), math.max(sizeMax, best.Size.Y)
		end
		return { stage = bestStage, moved = moved, turned = turned, switched = switched, grew = sizeMax - sizeMin, awake = Obstacles.isAwake(bestStage), cf = best.CFrame, size = best.Size, transparency = best.Transparency }
	elseif kind == "coinNear" then
		-- a coin of the stage after the player's pad, and a spot `arg` studs away from it
		local st = math.max(ss.at, pr.stage) + 1
		local coin = Obstacles.coinsOf(st)[1]
		if not coin then return nil end
		return { id = coin:GetAttribute("CoinId"), spot = CFrame.new(coin.Position + Vector3.new(arg, 0, 0)), collected = ss.collected[coin:GetAttribute("CoinId")] == true }
	elseif kind == "coinTaken" then
		return ss.collected[arg] == true
	elseif kind == "hold" then
		-- keeps the character still at `arg` (nil = let go)
		local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if r and arg then
			moveTo(plr, arg)
			r.Anchored = true
		elseif r then
			r.Anchored = false
		end
		return r ~= nil
	elseif kind == "census" then
		local total, running = Obstacles.census()
		local list, builtCount, released = Towers.stats()
		return { obstacles = total, running = running, towers = list, built = builtCount, released = released, parts = census(workspace).parts }
	elseif kind == "sweep" then
		-- shorten the idle time so the test doesn't wait 75 s for an empty tower to go
		Towers.IDLE_SECONDS = arg
		Towers.sweep()
		return true
	elseif kind == "invite" then
		return Referrals.applyInvite(plr, arg)
	elseif kind == "grantInviter" then
		return Referrals.grantInviter(plr, arg)
	elseif kind == "setReferralRewards" then
		pr.referralRewards = arg
		return true
	elseif kind == "resetSkips" then
		pr.freeSkips = 0
		Session.push(plr)
		return true
	elseif kind == "weekend" then
		-- 2x Coins Weekend through the admin override path; returns multipliers (off, on)
		local natural = Session.eventActive("DoubleCoinsWeekend")
		Events.setOverride("SkipSaleHour", os.time() + 600) -- some other event -> weekend only if scheduled
		local off = Session.bonusMult(pr)
		Events.setOverride("DoubleCoinsWeekend", os.time() + 600)
		local on = Session.bonusMult(pr)
		local gained = Session.addCoins(plr, 10)
		return { off = off, on = on, natural = natural, gained = gained }
	elseif kind == "weekendOff" then
		Events.setOverride("DoubleCoinsWeekend", 0)
		return true
	elseif kind == "starter" then
		local before = pr.freeSkips
		Monetization.grantStarter(plr, pr)
		Session.push(plr)
		return { skips = pr.freeSkips - before, trail = pr.trails.starter == true, boost = pr.boostEndsAt - os.time(), mult = Session.bonusMult(pr) }
	elseif kind == "clearBoosts" then
		pr.boosts = {}
		pr.charges = {}
		pr.boostEndsAt = 0
		Shops.SHIELD_SECONDS = 1.6
		require(Server.Cosmetics).applyCoils(plr)
		Session.push(plr)
		return true
	elseif kind == "nametag" then
		local c = plr.Character
		local head = c and c:FindFirstChild("Head")
		local tag = head and head:FindFirstChild("SkyTag")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local stageLine = tag and tag:FindFirstChild("StageLine")
		local titleLine = tag and tag:FindFirstChild("TitleLine")
		return {
			exists = tag ~= nil,
			hidden = hum ~= nil and hum.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None,
			stageKey = stageLine and stageLine:GetAttribute("LocKey"),
			stage = stageLine and stageLine:GetAttribute("S"),
			titleKey = titleLine and titleLine:GetAttribute("LocKey"),
		}
	elseif kind == "Done" then
		clientReport = arg
		clientDone = true
		return true
	end
	return nil
end
rf.Parent = ReplicatedStorage
player:SetAttribute("ServerReady", true)

-- 4. wait for the client run ----------------------------------------------------------------
local deadline = os.clock() + 840
while not clientDone and os.clock() < deadline do task.wait(0.25) end
check("client finished", clientDone)
for line in string.gmatch(clientReport, "[^\n]+") do
	if line:sub(1, 4) == "FAIL" then print("[TEST] client " .. line) end -- PASS lines were already printed by the client
	table.insert(results, "client " .. line)
end

-- 5. persistence ------------------------------------------------------------------------------
if Data.isPersistent(player) then
	Data.save(player)
	local ok, saved = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName):GetAsync("u_" .. player.UserId)
	end)
	local pr = Data.get(player)
	check("profile saved to DataStore", ok and saved and saved.stage == pr.stage and saved.wins == pr.wins and saved.best == pr.best and saved.gifts ~= nil and saved.boosts ~= nil, ok and saved and ("saved stage %s wins %s best %s"):format(tostring(saved.stage), tostring(saved.wins), tostring(saved.best)) or tostring(saved))
else
	print("[TEST] INFO DataStore not available in this Studio session: profile checked in memory only")
	local pr = Data.get(player)
	-- what would be saved: every new field is plain data (numbers, strings, booleans, tables of them)
	local function plain(v, depth)
		local t = type(v)
		if t == "number" or t == "string" or t == "boolean" then return true end
		if t ~= "table" or depth > 4 then return false end
		for k, x in v do
			if (type(k) ~= "string" and type(k) ~= "number") or not plain(x, depth + 1) then return false end
		end
		return true
	end
	check("new profile fields are saveable plain data", plain(pr.gifts, 0) and plain(pr.boosts, 0) and plain(pr.charges, 0) and plain(pr.perks, 0) and (pr.pocket == nil or plain(pr.pocket, 0)) and type(pr.base) == "boolean")
end

-- 6. perf: 10 s of heartbeat with the obstacles around the player running ------------------------
local n, sum, worst = 0, 0, 0
local conn = RunService.Heartbeat:Connect(function(dt)
	n += 1
	sum += dt
	worst = math.max(worst, dt)
end)
task.wait(10)
conn:Disconnect()
local avg = sum / math.max(n, 1)
-- towers nobody needs any more are released (the idle time is shortened so the test doesn't wait)
Towers.IDLE_SECONDS = 1
Towers.sweep()
task.wait(2.5)
Towers.sweep()
task.wait(0.5)
local total, running = Obstacles.census()
local list, builtCount, released = Towers.stats()
print(("[TEST] PERF server end of run: heartbeat avg %.2f ms (%.1f fps), worst %.1f ms, memory %.0f MB, %d parts in workspace, towers in workspace {%s} (built %d, released %d), animated obstacles %d running of %d"):format(
	avg * 1000, 1 / avg, worst * 1000, Stats:GetTotalMemoryUsageMb(), census(workspace).parts, table.concat(list, ","), builtCount, released, running, total))
check("BUDGET server heartbeat avg < " .. BUDGET.serverHeartbeatMs .. " ms", avg * 1000 < BUDGET.serverHeartbeatMs, ("%.2f ms"):format(avg * 1000))
check("BUDGET animated obstacles running <= " .. BUDGET.awakeObstacles, running <= BUDGET.awakeObstacles, running .. " of " .. total)
check("at most 2 towers per player in Workspace once the idle ones are released", #list <= 2 and list[1] == 1, table.concat(list, ","))
check("BUDGET parts in Workspace with one player <= 2 towers + lobby", census(workspace).parts <= 2 * BUDGET.towerParts + BUDGET.lobbyParts + BUDGET.sceneryParts, census(workspace).parts)

for i = 1, math.min(10, #warns) do print("[TEST] INFO warn: " .. warns[i]) end
check("no server errors", #errors == 0, table.concat(errors, " || "))
local fails = 0
for _, r in results do
	if r:sub(1, 4) == "FAIL" or r:find("^client FAIL") then fails += 1 end
end
print("[TEST SUMMARY] " .. #results .. " checks, " .. fails .. " failures")
task.wait(1)
StudioTestService:EndTest(fails)
