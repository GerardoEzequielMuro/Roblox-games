-- Client side of the gameplay test: drives the real remotes and client modules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")

local player = Players.LocalPlayer
local clientErrors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(clientErrors, msg)
	end
end)

local lines = {}
local function show(v)
	if type(v) == "table" then
		if type(v.key) == "string" then
			return v.key
		end
		return "{table}"
	end
	return (tostring(v):gsub("\n", " / "))
end
local function check(name, cond, detail)
	local line = (if cond then "PASS " else "FAIL ") .. name .. (if detail ~= nil then " :: " .. show(detail) else "")
	if not cond then
		print("[TEST] c " .. line) -- the server prints the full report at the end
	end
	table.insert(lines, line)
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request") :: RemoteFunction
local Act = Remotes:WaitForChild("Act") :: RemoteEvent
local T = ReplicatedStorage:WaitForChild("__Test", 60) :: RemoteFunction
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Net = require(Client:WaitForChild("Net"))
local Lang = require(Client:WaitForChild("Lang"))
local Fx = require(Client:WaitForChild("Fx"))
local Controls = require(Client:WaitForChild("Controls"))
local Flight = require(Client:WaitForChild("Flight"))
local CombatFx = require(Client:WaitForChild("CombatFx"))
local NpcRender = require(Client:WaitForChild("NpcRender"))
local CharFx = require(Client:WaitForChild("CharFx"))
local C = Config.Combat

local function req(action, payload)
	task.wait(0.1) -- stay under the Request rate limit
	local ok, a, b = pcall(function()
		return Request:InvokeServer(action, payload)
	end)
	if not ok then
		return false, a
	end
	return a == true, b
end
local function srv(cmd, a, b, c)
	return T:InvokeServer(cmd, a, b, c)
end
local function waitFor(cond, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 5) do
		local v = cond()
		if v then
			return v
		end
		task.wait(0.1)
	end
	return cond()
end
local function near(a, b, tol)
	return math.abs(a - b) <= (tol or 1e-3) * math.max(1, math.abs(b))
end

-- event taps
local fx = { hit = {}, shot = {}, shotEnd = {}, beam = {}, swing = {}, form = {}, telegraph = {}, shock = {}, npcDeath = {}, dash = {}, dodge = {} }
for kind, list in fx do
	CombatFx.on(kind, function(d)
		table.insert(list, d)
	end)
end
local combat = {}
Remotes:WaitForChild("Combat").OnClientEvent:Connect(function(kind, a)
	combat[kind] = combat[kind] or {}
	table.insert(combat[kind], a)
end)
local notifications = {}
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(message)
	table.insert(notifications, message)
end)

-- wait for the session
local okState, state
for _ = 1, 80 do
	okState, state = req("GetState")
	if okState then
		break
	end
	task.wait(0.5)
end
check("GetState", okState and type(state) == "table", state)
state = if type(state) == "table" then state else {}
check("state: 5 stats, power, per-rep gains", state.stats ~= nil and state.power ~= nil and state.perRep ~= nil and state.perRep.strength >= 1, state.perRep and state.perRep.strength)

local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
local hum = char:WaitForChild("Humanoid") :: Humanoid
task.wait(2)

-- UI built
local gui = player:WaitForChild("PlayerGui")
local mainGui = gui:WaitForChild("KiWarriorsUI", 10) :: ScreenGui
check("main UI built", mainGui ~= nil and #mainGui:GetDescendants() > 100, mainGui and #mainGui:GetDescendants())
check("main UI uses CoreUISafeInsets", mainGui and mainGui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)
check("HUD: vitals, training slots, currencies, moves, auto toggles", mainGui:FindFirstChild("Vitals", true) ~= nil and mainGui:FindFirstChild("Training", true) ~= nil and mainGui:FindFirstChild("Sparks", true) ~= nil and mainGui:FindFirstChild("Stat_jump", true) ~= nil and (mainGui:FindFirstChild("Moves", true) ~= nil or mainGui:FindFirstChild("Touch_punch", true) ~= nil) and mainGui:FindFirstChild("Auto_autoTrain", true) ~= nil and mainGui:FindFirstChild("Auto_autoFight", true) ~= nil and mainGui:FindFirstChild("Auto_autoCharge", true) ~= nil)
check("character attributes replicated (Ki, Form, FighterId)", waitFor(function()
	return char:GetAttribute("Ki") ~= nil and char:GetAttribute("Form") == 0 and char:GetAttribute("FighterId") ~= nil
end, 5) == true)
check("spawned on the home planet plaza", hrp.Position.Magnitude < 120, hrp.Position)

srv("freezeNpcs", 900)
srv("vulnerable")
srv("noCrit")

local UI = Client:WaitForChild("UI")
local Windows = require(UI:WaitForChild("Windows"))
local QuestTracker = require(UI:WaitForChild("QuestTracker"))
local Menu = require(UI:WaitForChild("Menu"))
local StoryText = require(Client:WaitForChild("StoryText"))
local RelicsClient = require(Client:WaitForChild("RelicsClient"))
local storyEvents = {}
Remotes:WaitForChild("Quests").OnClientEvent:Connect(function(d)
	if type(d) == "table" and d.storyDone then
		table.insert(storyEvents, d)
	end
end)
local banners = {}
Remotes:WaitForChild("Toast").OnClientEvent:Connect(function(d)
	table.insert(banners, d)
end)
local arenaEvents = {}
Remotes:WaitForChild("Arena").OnClientEvent:Connect(function(d)
	table.insert(arenaEvents, d)
end)

check("new player starts the story at step 1", state.story ~= nil and state.story.step == 1 and state.story.progress == 0)
check("objective tracker shows the first step", waitFor(function()
	local o = mainGui:FindFirstChild("Objective", true)
	local t = o and o:FindFirstChild("Title")
	return t ~= nil and t.Text == StoryText.text(Config.Story[1])
end, 4) == true)
check("tutorial hint shown for the first step", (function()
	local o = mainGui:FindFirstChild("Objective", true)
	local h = o and o:FindFirstChild("Hint")
	return h ~= nil and h.Visible and #h.Text > 3
end)())
check("menu starts small (no Shop during the tutorial)", Menu.buttons.Shop ~= nil and Menu.buttons.Shop.holder.Visible == false and Menu.buttons.Quests.holder.Visible == true)
-- park the story so the sections below control their own numbers; it has its own section later
srv("story", #Config.Story + 1)

---------------------------------------------------------------------------
-- Training
---------------------------------------------------------------------------
local prof = srv("profile")
local s0 = prof.stats.strength
Act:FireServer("melee")
task.wait(0.4)
prof = srv("profile")
check("a punch is one rep of the selected stat", near(prof.stats.strength - s0, prof.perRep) and prof.totalReps == 1, prof.stats.strength - s0)
-- burst: 80 reps in one frame are clamped to the bucket
local r0 = prof.totalReps
for _ = 1, 80 do
	Act:FireServer("melee")
end
task.wait(0.5)
prof = srv("profile")
local accepted = prof.totalReps - r0
check("rep burst clamped by the token bucket", accepted >= 1 and accepted <= Config.Train.manualBurst + Config.Train.manualPerSecond * 0.8 + 1, accepted)
-- sustained
r0 = prof.totalReps
local tStart = os.clock()
for _ = 1, 50 do
	Act:FireServer("melee")
	Act:FireServer("melee")
	task.wait(0.04)
end
task.wait(0.3)
prof = srv("profile")
local elapsed = os.clock() - tStart
accepted = prof.totalReps - r0
check("sustained reps capped at the manual rate", accepted > 0 and accepted <= Config.Train.manualPerSecond * (elapsed + 0.4) + Config.Train.manualBurst, string.format("%d in %.2fs", accepted, elapsed))
-- stat focus
local ok, err = req("SetStat", { stat = "ki" })
check("SetStat ki", ok, err)
local k0 = srv("profile").stats.ki
task.wait(1)
Act:FireServer("melee")
task.wait(0.4)
prof = srv("profile")
check("reps now train Ki", prof.stats.ki > k0 and prof.settings.stat == "ki", prof.stats.ki - k0)
ok = req("SetStat", { stat = "luck" })
check("unknown stat rejected", not ok)
req("SetStat", { stat = "strength" })
check("HUD highlights the selected stat", waitFor(function()
	local row = mainGui:FindFirstChild("Stat_strength", true)
	local st = row and row:FindFirstChildOfClass("UIStroke")
	return st ~= nil and st.Thickness > 3
end, 3) == true)

-- auto-train
prof = srv("profile")
check("auto-train is OFF by default", prof.settings.autoTrain == false)
r0 = prof.totalReps
task.wait(1.2)
check("no reps without input while auto is off", srv("profile").totalReps == r0)
ok = req("SetSetting", { key = "autoTrain", value = true })
check("SetSetting autoTrain", ok)
r0 = srv("profile").totalReps
tStart = os.clock()
task.wait(4)
prof = srv("profile")
elapsed = os.clock() - tStart
local autoReps = prof.totalReps - r0
check("auto-train reps at the auto rate", autoReps >= prof.autoRate * (elapsed - 1) and autoReps <= prof.autoRate * (elapsed + 0.8) + 1, string.format("%d in %.2fs (rate %.1f)", autoReps, elapsed, prof.autoRate))
check("HUD shows Auto Train ON", waitFor(function()
	local b = mainGui:FindFirstChild("Auto_autoTrain", true)
	local l = b and b:FindFirstChild("Label")
	return l ~= nil and l.Text:find(Lang.t("hud.on"), 1, true) ~= nil
end, 3) == true)
srv("pass", "TurboAuto", true)
local turbo = srv("profile").autoRate
check("TurboAuto pass doubles the auto rate", near(turbo, prof.autoRate * Config.Train.turboMult), turbo)
srv("pass", "TurboAuto", false)
req("SetSetting", { key = "autoTrain", value = false })
task.wait(0.5)
r0 = srv("profile").totalReps
task.wait(1.2)
check("auto-train stops when toggled off", srv("profile").totalReps == r0)
ok = req("SetSetting", { key = "godMode", value = true })
check("unknown setting rejected", not ok)

-- gear
srv("set", "sparks", 0)
ok, err = req("BuyGear")
check("weights need Sparks", not ok and type(err) == "table" and err.key == "msg.need_sparks", err)
srv("giveSparks", Config.Gear[2].cost)
local rep1 = srv("profile").perRep
ok = req("BuyGear")
prof = srv("profile")
check("weights tier 2 bought, Sparks spent, gain x" .. Config.Gear[2].mult, ok and prof.gear == 2 and prof.sparks == 0 and near(prof.perRep, rep1 * Config.Gear[2].mult), prof.perRep)

-- training zone
srv("place", "zone", 1)
check("zone detected but locked below the power requirement", waitFor(function()
	local s = Net.state
	return s and s.zone == "gravity_dome" and s.zoneLocked == true
end, 4) == true, Net.state and Net.state.zone)
check("locked zone gives no multiplier", near(srv("profile").perRep, rep1 * Config.Gear[2].mult))
srv("setStats", { strength = 200, defense = 100 })
check("zone unlocks at the power requirement", waitFor(function()
	local s = Net.state
	return s and s.zone == "gravity_dome" and s.zoneLocked == false
end, 4) == true)
check("zone multiplies the gain x4", near(srv("profile").perRep, rep1 * Config.Gear[2].mult * 4), srv("profile").perRep)
check("HUD shows the zone pill", waitFor(function()
	local z = mainGui:FindFirstChild("Zone", true)
	return z ~= nil and z.Visible
end, 3) == true)

-- movement stats
local f = srv("fighter")
check("walk speed follows Agility", near(f.walkSpeed, Formulas.walkSpeed(srv("profile").stats.agility), 0.02), f.walkSpeed)
srv("setStats", { agility = 100000, jump = 100000 })
f = srv("fighter")
check("more Agility / Jump = faster and higher", f.walkSpeed > 35 and f.jumpPower > 85 and f.walkSpeed <= 62, f.walkSpeed .. " / " .. f.jumpPower)
check("max HP follows Defense", near(f.maxHp, Formulas.maxHp(100)), f.maxHp)
srv("setStats", { agility = 50, jump = 50 })

---------------------------------------------------------------------------
-- Combat vs enemies (PvE)
---------------------------------------------------------------------------
srv("place", "camp", 1, 0)
task.wait(1)
local npc = srv("npc", "thornling")
check("thornlings spawned in their camp", npc ~= nil and npc.spawned and npc.hp == Config.Npcs.thornling.hp, npc and npc.hp)
check("client renders enemy models", waitFor(function()
	local n = 0
	for _ in NpcRender.visuals do
		n += 1
	end
	return n >= 6
end, 6) == true)
-- walk up to it (teleport next to it, facing it)
local function standBy(target, dist)
	-- enemies walk (home, wander, chase): teleport next to it and make sure it is still in reach
	local n = srv("npcById", target.id)
	for _ = 1, 4 do
		local pos = n.pos + Vector3.new(dist or 5, 0, 0)
		srv("teleport", Vector3.new(pos.X, 4, pos.Z))
		task.wait(0.2)
		n = srv("npcById", target.id)
		if ((n.pos - hrp.Position) * Vector3.new(1, 0, 1)).Magnitude <= (dist or 5) + 2.5 then
			break
		end
	end
	return n
end
srv("setStats", { strength = 8, ki = 8, defense = 100 })
req("SetStat", { stat = "jump" }) -- punches keep training: point the reps at Jump so Strength / Ki stay fixed
npc = standBy(npc, 5)
local function aimAt(id)
	local n = srv("npcById", id)
	return (n.pos - hrp.Position).Unit, n
end
local function flatAim(id)
	local d = aimAt(id)
	return (d * Vector3.new(1, 0, 1)).Unit
end
local hits0 = #fx.hit
Act:FireServer("melee", flatAim(npc.id))
task.wait(0.5)
local after = srv("npcById", npc.id)
local expected = Formulas.meleeDamage(8, 0)
local dealt = npc.hp - after.hp
check("melee hits the enemy in front for strength-based damage", dealt > 0 and (near(dealt, expected) or near(dealt, expected * C.critMult)), dealt .. " (want " .. expected .. ")")
check("hit effect event with the damage", #fx.hit > hits0 and fx.hit[#fx.hit].d > 0 and fx.hit[#fx.hit].a == player.UserId)
-- facing away from 9.5 studs (too far to be point blank): the arc matters
npc = standBy(npc, 9.5)
after = srv("npcById", npc.id)
Act:FireServer("melee", -flatAim(npc.id))
task.wait(0.5)
local n2 = srv("npcById", npc.id)
check("melee needs the enemy inside the arc", n2.hp == after.hp, after.hp - n2.hp)
srv("teleport", Vector3.new(n2.pos.X + 40, 4, n2.pos.Z))
task.wait(0.3)
Act:FireServer("melee", Vector3.new(-1, 0, 0))
task.wait(0.5)
check("melee out of range misses", srv("npcById", npc.id).hp == n2.hp)
-- cooldown: 10 swings in one frame = 1 attack
npc = standBy(npc, 5)
local hpA = srv("npcById", npc.id).hp
local burstAim = flatAim(npc.id)
for _ = 1, 10 do
	Act:FireServer("melee", burstAim)
end
task.wait(0.5)
local hpB = srv("npcById", npc.id).hp
check("melee cooldown: a burst of swings lands once", near(hpA - hpB, expected), (hpA - hpB) .. " hpA " .. hpA .. " str " .. srv("profile").stats.strength)
-- combo + kill on a fresh enemy: 3 hits + the finisher
srv("setStats", { strength = 4 })
npc = standBy(srv("npc", "thornling", "full"), 5)
local sparks0 = srv("profile").sparks
local kills0 = srv("profile").kills
local killed = false
for _ = 1, 14 do
	local n = srv("npcById", npc.id)
	if not n or not n.alive then
		killed = true
		break
	end
	Act:FireServer("melee", flatAim(npc.id))
	task.wait(0.34)
end
killed = killed or not srv("npcById", npc.id).alive
prof = srv("profile")
check("enemy defeated: Sparks dropped", killed and prof.sparks > sparks0, prof.sparks - sparks0)
check("kills counted (a swing can hit up to 3 enemies)", prof.kills >= kills0 + 1 and prof.kills <= kills0 + 6, prof.kills - kills0)
check("combo counter reached the finisher", combat.combo ~= nil and math.max(table.unpack(combat.combo)) >= C.comboFinisher, combat.combo and #combat.combo)
local sawFinisher = false
for _, h in fx.hit do
	if h.f then
		sawFinisher = true
	end
end
check("finisher hit flagged for the big effect", sawFinisher)
check("death effect event", #fx.npcDeath >= 1)
check("dead enemy leaves the world and respawns", waitFor(function()
	local n = srv("npcById", npc.id)
	return n and n.spawned and n.hp == n.maxHp
end, Config.Npcs.thornling.respawn + 4) == true)

-- ki blast
local target = srv("npc", "thornling")
target = standBy(target, 30)
srv("setKi", 1)
task.wait(0.3)
local shots0 = #fx.shot
local dir = aimAt(target.id)
Act:FireServer("blast", dir)
task.wait(0.7)
f = srv("fighter")
local tAfter = srv("npcById", target.id)
local blastDmg = Formulas.blastDamage(8, 0)
check("blast costs ki", f.ki < 1 - C.blastCost + 0.04 and f.ki > 1 - C.blastCost - 0.06, f.ki)
check("blast projectile event sent to clients", #fx.shot == shots0 + 1)
local blastHit = nil
for _, h in fx.hit do
	if h.k == "blast" and h.a == player.UserId then
		blastHit = h
	end
end
check("blast hits an enemy for ki-based damage", blastHit ~= nil and near(blastHit.d, blastDmg, 0.02), (blastHit and blastHit.d or "none") .. " want " .. blastDmg .. " ki " .. srv("profile").stats.ki .. " hp " .. target.hp .. "->" .. tAfter.hp)
local _ = tAfter
check("projectile ended (hit reported)", #fx.shotEnd >= 1 and srv("projectiles") == 0)
-- burst of blasts: cooldown
srv("setKi", 1)
shots0 = #fx.shot
for _ = 1, 15 do
	Act:FireServer("blast", Vector3.new(0, 1, 0))
end
task.wait(0.5)
check("blast cooldown: a burst fires once", #fx.shot - shots0 == 1, #fx.shot - shots0)
-- no ki
srv("setKi", 0)
task.wait(0.35)
shots0 = #fx.shot
Act:FireServer("blast", Vector3.new(0, 1, 0))
task.wait(0.4)
check("no ki = no blast", #fx.shot == shots0)
-- bogus payloads
Act:FireServer("blast", Vector3.new(0 / 0, 0, 0))
Act:FireServer("blast", "up")
Act:FireServer("blast", Vector3.zero)
Act:FireServer("melee", "x")
Act:FireServer("form", 0 / 0)
Act:FireServer("form", 99)
Act:FireServer("form", "big")
Act:FireServer("tech", { id = "sunfall", dir = Vector3.new(0, 0, 1) })
Act:FireServer("tech", "sunfall")
Act:FireServer(nil)
Act:FireServer({})
Act:FireServer("beamRelease", Vector3.new(0, 0, 1))
task.wait(0.5)
f = srv("fighter")
check("bogus inputs ignored (no form, no shots)", f.form == 0 and #fx.shot == shots0, f.form)

-- charge
srv("setKi", 0.2)
task.wait(0.2)
Controls.charge(true)
check("charging flag replicated (aura pose for everyone)", waitFor(function()
	return char:GetAttribute("Charging") == true
end, 2) == true)
task.wait(1.2)
f = srv("fighter")
check("charging refills ki fast", f.ki > 0.2 + C.kiChargeRegen * 0.8, f.ki)
check("charging roots the player", f.walkSpeed == 0, f.walkSpeed)
local rig = CharFx.rigs[char]
check("charging aura built from geometry", rig ~= nil and rig.auraOn == true and #rig.tongues >= 3 and rig.shell ~= nil, rig and #rig.tongues)
Controls.charge(false)
task.wait(0.6)
f = srv("fighter")
check("charge released: walking again", f.charging == false and f.walkSpeed > 10, f.walkSpeed)

-- beam
target = srv("npc", "raider") or srv("npc", "thornling")
srv("place", "camp", 2, 0)
task.wait(1)
target = srv("npc", "raider")
target = standBy(target, 40)
srv("setKi", 1)
task.wait(0.3)
Act:FireServer("beamRelease", aimAt(target.id))
task.wait(0.3)
check("beam release without charging does nothing", #fx.beam == 0 and srv("fighter").ki > 0.97)
Act:FireServer("beamStart")
task.wait(0.1)
Act:FireServer("beamRelease", aimAt(target.id))
task.wait(0.3)
check("beam tapped (under the minimum charge) is cancelled for free", #fx.beam == 0 and srv("fighter").ki > 0.95, srv("fighter").ki)
Controls.beamBegin()
check("beam charging flag", waitFor(function()
	return char:GetAttribute("Beam") == true
end, 2) == true)
task.wait(1.3)
local beamDir, tBefore = aimAt(target.id)
Act:FireServer("beamRelease", beamDir)
Controls.beamStartedAt = nil
task.wait(0.4)
f = srv("fighter")
tAfter = srv("npcById", target.id)
local spent = 1 - f.ki
check("beam fired: ki cost scales with the charge", #fx.beam == 1 and spent > C.beamCostMin and spent < C.beamCostMax + 0.02, spent)
local charge = fx.beam[1] and fx.beam[1].c or 0
check("beam damage scales with the charge", tBefore.hp - tAfter.hp > 0 and near(tBefore.hp - tAfter.hp, Formulas.beamDamage(8, 0, charge), 0.02), (tBefore.hp - tAfter.hp) .. " charge " .. charge)
Act:FireServer("beamStart")
task.wait(0.4)
check("beam cooldown blocks an immediate second beam", char:GetAttribute("Beam") ~= true)

-- block
srv("heal")
srv("vulnerable")
task.wait(0.2)
local d1 = srv("npcHit", "raider", 40)
Controls.block(true)
task.wait(0.4)
srv("heal")
local fb = srv("fighter")
local d2 = srv("npcHit", "raider", 40)
Controls.block(false)
check("unblocked enemy hit does full damage", near(d1, 40), d1)
check("blocking cuts damage by " .. C.blockReduction * 100 .. "%", near(d2, 40 * (1 - C.blockReduction)), d2 .. " blocking=" .. tostring(fb.blocking) .. " inv=" .. tostring(fb.invulnerable) .. " hp=" .. fb.hp)
task.wait(0.3)
check("block released", srv("fighter").blocking == false)

-- dash
srv("setKi", 1)
srv("heal")
task.wait(0.3)
srv("teleport", Vector3.new(0, 5, 45)) -- open ground in the plaza
task.wait(0.5)
srv("vulnerable")
local p0 = hrp.Position
local dashKi = char:GetAttribute("Ki")
Controls.dash()
task.wait(0.15)
local moved = (hrp.Position - p0).Magnitude
local d3 = srv("npcHit", "thornling", 40)
local fd = srv("fighter")
task.wait(0.3)
f = srv("fighter")
check("dash moves the character", moved > C.dashDistance * 0.5, moved)
check("dash costs ki", fd.ki < 1 and fd.ki > 1 - C.dashCost - 0.06, fd.ki .. " attr " .. tostring(dashKi) .. " inv=" .. tostring(fd.invulnerable))
check("dash gives invulnerability frames", d3 == 0, d3)
check("dash effect event", #fx.dash >= 1)
task.wait(0.4)
local d4 = srv("npcHit", "thornling", 40)
check("invulnerability ends", d4 > 0, d4)

-- flight
srv("heal")
local y0 = hrp.Position.Y
Controls.toggleFly()
check("flight flag reaches the server", waitFor(function()
	return srv("fighter").flying == true and char:GetAttribute("Flying") == true
end, 3) == true)
Flight.testMove = Vector3.new(0, 1, 0)
task.wait(1.2)
check("flying gains altitude", hrp.Position.Y - y0 > 25, hrp.Position.Y - y0)
Flight.testMove = Vector3.new(1, 0, 0)
local px = hrp.Position
task.wait(1)
local speed = ((hrp.Position - px) * Vector3.new(1, 0, 1)).Magnitude
check("flying moves at the fly speed", speed > 35 and speed < (char:GetAttribute("FlySpeed") or 72) * 1.2, speed)
Flight.testMove = nil
task.wait(0.8)
local hoverY = hrp.Position.Y
task.wait(0.8)
check("hovering holds altitude", math.abs(hrp.Position.Y - hoverY) < 4, (hrp.Position.Y - hoverY) .. " vy=" .. hrp.AssemblyLinearVelocity.Y .. " active=" .. tostring(Flight.active) .. " ps=" .. tostring(hum.PlatformStand))
Controls.toggleFly()
check("landing clears the flag", waitFor(function()
	return srv("fighter").flying == false
end, 3) == true)
task.wait(1.5)

-- transformations
srv("place", "camp", 2, 0)
task.wait(0.8)
srv("heal")
srv("setStats", { strength = 8, ki = 8, defense = 100 }, "exact")
srv("set", "forms", 0)
srv("setKi", 1)
Act:FireServer("form", 1)
task.wait(0.5)
check("form locked below its power requirement", srv("fighter").form == 0 and char:GetAttribute("Form") == 0)
srv("setStats", { strength = 1500, ki = 600, defense = 600 })
check("form unlock announced", waitFor(function()
	return combat.formUnlocked ~= nil
end, 3) == true and srv("profile").forms == 1, srv("profile").forms)
Act:FireServer("form", 2)
task.wait(0.6)
check("cannot skip to a form that is not unlocked", srv("fighter").form == 0)
local forms0 = #fx.form
Controls.transform()
check("transformed: Form attribute + effect event", waitFor(function()
	return char:GetAttribute("Form") == 1 and #fx.form > forms0
end, 3) == true, char:GetAttribute("Form"))
task.wait(0.6)
srv("setStats", { strength = 20 })
rig = CharFx.rigs[char]
check("transformation look: aura, crest, outline", rig ~= nil and rig.auraOn and #rig.crest >= 3 and rig.highlight ~= nil, rig and #rig.crest)
target = srv("npc", "raider")
target = standBy(target, 5)
srv("set", "upgrades", { trainPower = 0, sparkGain = 0, autoSpeed = 0, kiRegen = 0, critChance = 0 })
local hpBefore = srv("npcById", target.id).hp
Act:FireServer("melee", flatAim(target.id))
task.wait(0.5)
local formHit = hpBefore - srv("npcById", target.id).hp
local want = Formulas.meleeDamage(20, 1)
check("form multiplies damage x" .. Config.Forms[1].mult, near(formHit, math.min(want, hpBefore)) or near(formHit, math.min(want * C.critMult, hpBefore)), formHit .. " (want " .. want .. ")")
local ki1 = srv("fighter").ki
task.wait(2)
local ki2 = srv("fighter").ki
check("form drains ki (no passive regen while transformed)", ki1 - ki2 >= Config.Forms[1].drain * 1.5, ki1 - ki2)
srv("setKi", 0.01)
check("out of ki: form drops", waitFor(function()
	return srv("fighter").form == 0 and char:GetAttribute("Form") == 0
end, 4) == true)
task.wait(0.5)
rig = CharFx.rigs[char]
check("form look removed", rig ~= nil and #rig.crest == 0 and rig.highlight == nil)

---------------------------------------------------------------------------
-- Auto helpers (server-driven)
---------------------------------------------------------------------------
srv("teleport", Vector3.new(0, 5, 40))
task.wait(0.6)
srv("setKi", 0.1)
req("SetSetting", { key = "autoCharge", value = true })
check("auto-charge starts when ki is low and you stand still", waitFor(function()
	return srv("fighter").charging == true
end, 3) == true)
check("auto-charge refills and stops by itself", waitFor(function()
	local ff = srv("fighter")
	return ff.ki >= Config.Auto.chargeUntil - 0.05 and ff.charging == false
end, 8) == true, srv("fighter").ki)
req("SetSetting", { key = "autoCharge", value = false })

srv("setStats", { strength = 8, ki = 8, defense = 400 })
srv("place", "camp", 1, 20)
task.wait(0.8)
srv("setKi", 1)
srv("heal")
local attacks0 = srv("autoAttacks")
kills0 = srv("profile").kills
req("SetSetting", { key = "autoFight", value = true })
tStart = os.clock()
check("auto-fight picks a target (walk target replicated)", waitFor(function()
	return typeof(char:GetAttribute("AutoTarget")) == "Vector3"
end, 3) == true)
task.wait(7)
elapsed = os.clock() - tStart
local attacks = srv("autoAttacks") - attacks0
check("auto-fight attacks without any client input", attacks >= 3, attacks)
check("auto-fight rate is capped by the server", attacks <= Config.Auto.fightPerSecond * elapsed + 2, string.format("%d in %.1fs", attacks, elapsed))
check("auto-fight defeats enemies", waitFor(function()
	return srv("profile").kills > kills0
end, 14) == true, srv("profile").kills - kills0)
req("SetSetting", { key = "autoFight", value = false })
task.wait(0.6)
attacks0 = srv("autoAttacks")
task.wait(2)
check("auto-fight stops when toggled off", srv("autoAttacks") == attacks0 and char:GetAttribute("AutoTarget") == nil)

---------------------------------------------------------------------------
-- Boss
---------------------------------------------------------------------------
srv("freezeNpcs", 0)
srv("setStats", { strength = 150, ki = 150, defense = 3000 })
srv("place", "boss", 1, 30)
task.wait(1.2)
local boss = srv("npc", "bramble_king")
check("boss waits in its arena", boss ~= nil and boss.spawned and boss.hp == Config.Npcs.bramble_king.hp, boss and boss.hp)
srv("setKi", 1)
srv("heal")
srv("vulnerable")
local tele0 = #fx.telegraph
local gems0 = srv("profile").gems
local bossDead = false
local t1 = os.clock()
local hurt = false
while os.clock() - t1 < 45 do
	local b = srv("npcById", boss.id)
	if not b or not b.alive then
		bossDead = true
		break
	end
	local me = srv("fighter")
	if me.hp < me.maxHp then
		hurt = true
	end
	if me.hp < me.maxHp * 0.4 then
		srv("heal")
	end
	-- stay in its face and punch; throw a blast now and then
	local to = b.pos - hrp.Position
	if to.Magnitude > 9 then
		srv("teleport", Vector3.new(b.pos.X + 6, 4, b.pos.Z))
	end
	Act:FireServer("melee", (to * Vector3.new(1, 0, 1)).Unit)
	if me.ki > 0.5 then
		Act:FireServer("blast", to.Unit)
	end
	task.wait(0.32)
end
check("boss uses telegraphed patterns", #fx.telegraph > tele0, #fx.telegraph - tele0)
check("boss can hurt the player", hurt)
check("boss defeated", bossDead)
prof = srv("profile")
check("boss rewards: gems + boss kill recorded", prof.gems - gems0 == Config.Npcs.bramble_king.gems and prof.bossKills.bramble_king == 1, prof.gems - gems0)

---------------------------------------------------------------------------
-- ROUND 2 SYSTEMS
---------------------------------------------------------------------------
srv("freezeNpcs", 900)
srv("heal")
srv("teleport", Vector3.new(0, 5, 45))
srv("setKi", 1)
local function st()
	return Net.state or {}
end
local function refreshState()
	local okS, snap = req("GetState")
	if okS then
		Net.state = snap
	end
	return snap
end

-- Story: the first steps through the real hooks
srv("setStats", { strength = 5, ki = 5, defense = 200, agility = 5, jump = 5 }, "exact")
srv("set", "sparks", 0)
srv("set", "gems", 0)
req("SetStat", { stat = "jump" })
srv("story", 1)
local done0 = #storyEvents
for _ = 1, 12 do
	Act:FireServer("melee")
	task.wait(0.14)
end
check("story step 1 (punch 10 times) completes and pays", waitFor(function()
	return #storyEvents > done0
end, 4) == true and srv("profile").story.step == 2 and srv("profile").sparks == Config.Story[1].sparks, srv("profile").sparks)
Controls.charge(true)
task.wait(0.5)
Controls.charge(false)
check("story step 2 (charge)", waitFor(function()
	return srv("profile").story.step == 3
end, 3) == true)
srv("setKi", 1)
for _ = 1, 3 do
	Act:FireServer("blast", Vector3.new(0, 1, 0))
	task.wait(0.35)
end
check("story step 3 (3 blasts)", waitFor(function()
	return srv("profile").story.step == 4
end, 3) == true)
Controls.toggleFly()
task.wait(0.6)
Controls.toggleFly()
check("story step 4 (fly)", waitFor(function()
	return srv("profile").story.step == 5
end, 3) == true)
check("step 5 points at the thornling camp (guide beam + pillar)", waitFor(function()
	local target = QuestTracker.guideTarget()
	if not target then
		return false
	end
	local cx, _, cz = Config.planetCenter(1)
	local o = Config.Planets[1].camps[1].offset
	return ((target - Vector3.new(cx + o[1], target.Y, cz + o[3]))).Magnitude < 2
end, 4) == true)
check("story rewards so far", srv("profile").sparks == Config.Story[1].sparks + Config.Story[2].sparks + Config.Story[3].sparks + Config.Story[4].sparks, srv("profile").sparks)
srv("story", 7) -- "reach 150 power": evaluated against the current state
srv("setStats", { strength = 200 })
Act:FireServer("melee")
check("a 'reach N power' step completes as soon as the power is there", waitFor(function()
	return srv("profile").story.step == 8
end, 3) == true)
check("Shop button appears once the tutorial is over", waitFor(function()
	return Menu.buttons.Shop.holder.Visible == true
end, 8) == true)
srv("story", #Config.Story + 1)
task.wait(0.6)
check("finished story hides the tracker", (function()
	local o = mainGui:FindFirstChild("Objective", true)
	return o ~= nil and o.Visible == false
end)())

-- Daily quests
local forced = srv("service", "QuestService", "force", { "reps", "defeat", "blasts" })
check("3 daily quests", forced ~= nil and #forced.list == 3 and forced.list[1].kind == "reps", forced and #forced.list)
for _ = 1, 3 do
	Act:FireServer("melee")
	task.wait(0.15)
end
task.wait(0.4)
local q = refreshState().quests
check("daily quest progress from real punches", q.list[1].progress >= 3, q.list[1].progress)
ok = req("ClaimQuest", { i = 1 })
check("unfinished quest cannot be claimed", not ok)
srv("completeQuests")
local g0 = srv("profile").gems
ok = req("ClaimQuest", { i = 1 })
check("quest claimed: gems", ok and srv("profile").gems == g0 + forced.list[1].gems, srv("profile").gems - g0)
ok = req("ClaimQuest", { i = 1 })
check("quest cannot be claimed twice", not ok)
ok = req("ClaimQuestBonus")
check("bonus needs all three", not ok)
req("ClaimQuest", { i = 2 })
req("ClaimQuest", { i = 3 })
g0 = srv("profile").gems
ok = req("ClaimQuestBonus")
check("quest bonus", ok and srv("profile").gems == g0 + Config.QuestBonusGems)

-- Rewards: daily, gifts, codes
local sp0 = srv("profile").sparks
ok = req("ClaimDaily")
check("daily reward day 1", ok and srv("profile").sparks > sp0, srv("profile").sparks - sp0)
ok, err = req("ClaimDaily")
check("daily reward only once a day", not ok and type(err) == "table" and err.key == "msg.daily_wait")
ok, err = req("ClaimGift", { index = 3 })
check("play-time gift not ready", not ok and type(err) == "table" and err.key == "msg.not_ready", err)
srv("skipSession", 11 * 60)
ok = req("ClaimGift", { index = 3 })
check("play-time gift after 10 minutes: x2 boost", ok and srv("profile").boostLeft > 0, srv("profile").boostLeft)
ok = req("ClaimGift", { index = 3 })
check("gift cannot be claimed twice", not ok)
srv("set", "boostLeft", 0)
g0 = srv("profile").gems
ok = req("RedeemCode", { code = " release " })
check("code redeemed (case and spaces ignored)", ok and srv("profile").gems == g0 + Config.Codes.RELEASE.amount)
ok = req("RedeemCode", { code = "RELEASE" })
check("code only once", not ok)
ok = req("RedeemCode", { code = "NOPE123" })
check("unknown code rejected", not ok)

-- Seals and the wish
srv("service", "Relics", "skipCooldown")
local relics = refreshState().relics
check("6 seals on the unlocked planets", relics ~= nil and #relics.list == Config.Relics.count and relics.found == 0, relics and #relics.list)
ok, err = req("CollectRelic", { i = 1 })
check("a seal cannot be collected from far away", not ok and type(err) == "table" and err.key == "msg.too_far", err)
check("the client renders my seals", waitFor(function()
	local n = 0
	for _ in RelicsClient.seals do
		n += 1
	end
	return n == Config.Relics.count
end, 4) == true)
local sealPos = srv("relicSpot", 1)
srv("teleport", sealPos + Vector3.new(0, 1, 0))
check("walking into a seal collects it", waitFor(function()
	return (refreshState().relics or {}).found == 1
end, 5) == true, RelicsClient.collected)
ok, err = req("Wish", { id = "gems" })
check("a wish needs all the seals", not ok and type(err) == "table" and err.key == "msg.need_seals", err)
srv("service", "Relics", "completeSet")
ok, err = req("Wish", { id = "gems" })
check("the wish is made at the altar", not ok and type(err) == "table" and err.key == "msg.go_to_altar", err)
srv("teleport", srv("altar"))
g0 = srv("profile").gems
local wish0 = 0
for _, h in fx.hit do
	wish0 += 0
end
ok, err = req("Wish", { id = "gems" })
prof = srv("profile")
check("wish granted: gems", ok and prof.gems == g0 + 60 and prof.wishes == 1, prof.gems - g0)
relics = refreshState().relics
check("after the wish the seals are gone until the cooldown", #relics.list == 0 and relics.nextAt > relics.serverTime, #relics.list)
ok = req("Wish", { id = "gems" })
check("no second wish without a new set", not ok)
srv("service", "Relics", "completeSet")
local repBefore = srv("profile").perRep
ok = req("Wish", { id = "power" })
check("permanent wish: +5% training", ok and near(srv("profile").perRep, repBefore * 1.05, 0.005), srv("profile").perRep / repBefore)
ok = req("Wish", { id = "everything" })
check("unknown wish rejected", not ok)

-- Auras: published odds, free and paid spins, policy restriction
local spin = refreshState().auraSpin
local total, positive = 0, true
for _, o in spin.odds do
	total += o.pct
	positive = positive and o.pct > 0
end
check("aura odds add up to 100% and nothing is 0", math.abs(total - 100) < 1e-6 and positive and #spin.odds == 11, total)
srv("set", "spins", 1)
srv("set", "freeSpinDay", 0)
srv("set", "gems", 0)
local res
ok, res = req("SpinAura", { paid = false })
check("free daily spin gives an aura", ok and type(res) == "table" and Config.AuraById[res.id] ~= nil, res)
prof = srv("profile")
check("first aura is equipped and multiplies training", prof.auras[res.id] == 1 and st() ~= nil and refreshState().auraEquipped == res.id)
ok = req("SpinAura", { paid = false })
check("banked free spin", ok and srv("profile").spins == 0)
ok, err = req("SpinAura", { paid = false })
check("no free spins left", not ok and type(err) == "table" and err.key == "msg.no_spins", err)
ok, err = req("SpinAura", { paid = true })
check("paid spin needs gems", not ok and type(err) == "table" and err.key == "msg.need_gems", err)
srv("giveGems", 100)
ok = req("SpinAura", { paid = true })
check("paid spin costs gems", ok and srv("profile").gems == 100 - Config.AuraSpin.gems, srv("profile").gems)
srv("service", "Auras", "setRestricted", true)
ok, err = req("SpinAura", { paid = true })
check("paid spin blocked where paid random items are restricted", not ok and type(err) == "table" and err.key == "msg.spin_restricted" and srv("profile").gems == 100 - Config.AuraSpin.gems, err)
srv("pass", "LuckyAura", true)
check("luck pass does not change the odds when restricted", refreshState().auraSpin.lucky == false)
Windows.open("Auras")
task.wait(0.5)
check("restricted: the paid spin button is hidden, free spin stays", mainGui:FindFirstChild("SpinPaid", true) == nil and mainGui:FindFirstChild("SpinFree", true) ~= nil)
local oddsRows = 0
for _, d in mainGui:GetDescendants() do
	if d.Name:sub(1, 5) == "Odds_" then
		oddsRows += 1
		local pct = d:FindFirstChild("Pct")
		if not pct or not pct.Text:find("%%") then
			oddsRows = -100
		end
	end
end
check("the odds of every aura are on screen as percentages", oddsRows == 11, oddsRows)
Windows.close()
srv("service", "Auras", "setRestricted", false)
local lucky = refreshState().auraSpin
local rareBefore, rareAfter = 0, 0
for i, o in spin.odds do
	if Config.RarityByName[Config.AuraById[o.id].rarity].order >= 3 then
		rareBefore += o.pct
		rareAfter += lucky.odds[i].pct
	end
end
local luckyTotal = 0
for _, o in lucky.odds do
	luckyTotal += o.pct
end
check("Lucky Aura raises Rare+ chances and the shown odds still add up to 100", lucky.lucky == true and rareAfter > rareBefore * 1.5 and math.abs(luckyTotal - 100) < 1e-6, rareAfter)
srv("pass", "LuckyAura", false)
ok = req("EquipAura", { id = "starlight_fake" })
check("cannot equip an aura you do not own", not ok)
ok = req("EquipAura", { id = "" })
local noAura = srv("profile").perRep
req("EquipAura", { id = res.id })
check("aura multiplies training", near(srv("profile").perRep, noAura * Config.AuraById[res.id].mult, 0.005), srv("profile").perRep / noAura)
check("aura replicated on the character", waitFor(function()
	return char:GetAttribute("Aura") == res.id
end, 3) == true)
req("EquipAura", { id = "" })

-- Techniques, upgrades, race
srv("setStats", { strength = 5, ki = 5, defense = 200 }, "exact")
srv("set", "sparks", 0)
ok, err = req("BuyTechnique", { id = "pulse_volley" })
check("technique needs power", not ok and type(err) == "table" and err.key == "msg.need_power", err)
srv("setStats", { strength = 3000 })
ok, err = req("BuyTechnique", { id = "pulse_volley" })
check("technique needs Sparks", not ok and type(err) == "table" and err.key == "msg.need_sparks", err)
srv("giveSparks", Config.TechniqueById.pulse_volley.cost)
ok = req("BuyTechnique", { id = "pulse_volley" })
check("technique learned", ok and srv("profile").techniques.pulse_volley == true and srv("profile").sparks == 0)
srv("setKi", 1)
task.wait(0.3)
local shotsT = #fx.shot
Act:FireServer("tech", { id = "pulse_volley", dir = Vector3.new(0, 1, 0) })
task.wait(1.2)
check("Pulse Volley fires its 5 shots and costs ki", #fx.shot - shotsT == Config.TechniqueById.pulse_volley.shots and srv("fighter").ki < 0.95, #fx.shot - shotsT)
shotsT = #fx.shot
Act:FireServer("tech", { id = "pulse_volley", dir = Vector3.new(0, 1, 0) })
task.wait(0.8)
check("technique cooldown", #fx.shot == shotsT)
Act:FireServer("tech", { id = "sunfall", dir = Vector3.new(0, 1, 0) })
task.wait(0.5)
check("a technique you do not own does nothing", #fx.shot == shotsT)
srv("set", "gems", 0)
ok, err = req("BuyUpgrade", { id = "trainPower" })
check("upgrade needs gems", not ok and type(err) == "table" and err.key == "msg.need_gems", err)
srv("giveGems", 10)
repBefore = srv("profile").perRep
ok = req("BuyUpgrade", { id = "trainPower" })
check("upgrade bought: +10% training", ok and srv("profile").gems == 0 and near(srv("profile").perRep, repBefore * 1.1, 0.005))
ok = req("SetRace", { id = "voltari" })
check("first race change is free", ok and waitFor(function()
	return char:GetAttribute("Race") == "voltari"
end, 3) == true)
ok, err = req("SetRace", { id = "lumen" })
check("the next race change costs gems", not ok and type(err) == "table" and err.key == "msg.need_gems")
ok = req("SetRace", { id = "dragonborn" })
check("unknown race rejected", not ok)

-- Passes (toggled on the server: no Robux in a playtest)
req("SetStat", { stat = "jump" })
repBefore = srv("profile").perRep
srv("pass", "DoubleTraining", true)
check("x2 Training pass", near(srv("profile").perRep, repBefore * 2, 0.005))
srv("pass", "DoubleTraining", false)
srv("pass", "VIP", true)
check("VIP pass: +20% training", near(srv("profile").perRep, repBefore * (1 + Config.VipTrainBonus), 0.005))
srv("pass", "VIP", false)
local fly0 = char:GetAttribute("FlySpeed")
srv("pass", "FastFlight", true)
check("Fast Flight pass", waitFor(function()
	return near(char:GetAttribute("FlySpeed"), fly0 * Config.FastFlightMult, 0.01)
end, 3) == true, char:GetAttribute("FlySpeed"))
srv("pass", "FastFlight", false)
g0 = srv("profile").gems
srv("service", "Monetization", "grantProduct", "Gems1")
check("gem product grants its gems", srv("profile").gems == g0 + Config.ProductByKey.Gems1.amount)
g0 = srv("profile").gems
local d1r = srv("receipt", "Gems2", "test-purchase-1")
local d2r = srv("receipt", "Gems2", "test-purchase-1")
check("ProcessReceipt grants once per purchase id", srv("profile").gems == g0 + Config.ProductByKey.Gems2.amount, d1r .. " / " .. d2r)
srv("service", "Monetization", "grantProduct", "StarterPack")
prof = srv("profile")
check("Starter Pack: gems, boost and its fixed aura (nothing random)", prof.auras[Config.StarterPack.aura] == 1 and prof.boostLeft >= Config.StarterPack.boostMinutes * 60)
srv("set", "boostLeft", 0)

-- Live events
repBefore = srv("profile").perRep
srv("liveOverride", "AdminRage", 120)
check("a live event multiplies training (x3)", waitFor(function()
	return near(srv("profile").perRep, repBefore * 3, 0.005)
end, 3) == true)
check("event chip on screen", waitFor(function()
	local c = mainGui:FindFirstChild("Chip_live", true)
	return c ~= nil and c.Visible
end, 4) == true)
srv("liveOverride", "AdminRage", -5)
check("the event ends", waitFor(function()
	return near(srv("profile").perRep, repBefore, 0.005)
end, 4) == true)
local okCmd = srv("eventCommand", "/event AdminRage 5")
check("/event is admin only", okCmd == false)
srv("makeAdmin")
okCmd = srv("eventCommand", "/event AdminRage 5")
check("/event from an admin starts the event", okCmd == true and waitFor(function()
	return near(srv("profile").perRep, repBefore * 3, 0.005)
end, 3) == true)
srv("liveOverride", "AdminRage", -5)
task.wait(1.5)

-- Offline training
local off = srv("service", "Offline", "fake", 3600)
local stat = srv("profile").settings.stat
check("offline training = auto rate x 25% x time", off ~= nil and off.pending ~= nil and near(off.pending[stat], off.perRep * off.rate * off.offlineRate * 3600, 0.01), off and off.seconds)
off = srv("service", "Offline", "fake", 100 * 3600)
check("offline time is capped", off.seconds == off.cap and off.cap >= Config.Offline.capSeconds)
local sBefore = srv("profile").stats[stat]
ok = req("ClaimOffline")
check("offline gain claimed into the stat", ok and near(srv("profile").stats[stat], sBefore + off.pending[stat], 0.001))
ok = req("ClaimOffline")
check("nothing left to claim", not ok)
task.wait(2.6) -- the offline popup opens by itself: close it
Windows.close()

-- Referral
g0 = srv("profile").gems
srv("setPlayTime", 30)
local applied = srv("service", "Social", "applyReferral", "ref:123456")
check("referral: invitee gift", applied == true and srv("profile").gems == g0 + Config.ReferralInviteeGift.amount)
check("referral only once", srv("service", "Social", "applyReferral", "ref:999") == false)

-- Travel and planets
srv("setStats", { strength = 5, ki = 5, defense = 200 }, "exact")
srv("set", "sparks", 0)
ok, err = req("Travel", { planet = 2 })
check("planet 2 needs power", not ok and type(err) == "table" and err.key == "msg.need_power", err)
srv("setStats", { strength = 30000 })
ok, err = req("Travel", { planet = 2 })
check("planet 2 needs Sparks", not ok and type(err) == "table" and err.key == "msg.need_sparks", err)
srv("giveSparks", Config.Planets[2].cost)
ok = req("Travel", { planet = 2 })
local c2x, _, c2z = Config.planetCenter(2)
check("planet unlocked and the player is teleported there", ok and waitFor(function()
	return (hrp.Position - Vector3.new(c2x, hrp.Position.Y, c2z)).Magnitude < 80
end, 8) == true and srv("profile").planet == 2, hrp.Position)
check("enemies follow the players: planet 2 spawned, planet 1 despawned", waitFor(function()
	local n = srv("npc", "cinder_imp")
	return n ~= nil and n.spawned and srv("npc", "thornling") == nil
end, 5) == true and srv("activeNpcs") == 12, srv("activeNpcs"))
check("sky changes with the planet", waitFor(function()
	return game:GetService("Lighting").ClockTime > 16
end, 4) == true, game:GetService("Lighting").ClockTime)
task.wait(3.5)
ok = req("Travel", { planet = 1 })
check("travel back is free", ok and waitFor(function()
	return hrp.Position.Magnitude < 120
end, 8) == true)
ok = req("Travel", { planet = 9 })
check("unknown planet rejected", not ok)
task.wait(1)

-- Movement guard
local corr0 = srv("service", "Guard", "count") or 0
check("normal play (dash, flight, knockback, gates) never trips the movement guard", corr0 == 0, corr0)
task.wait(3.2)
local before = hrp.Position
hrp.CFrame = hrp.CFrame + Vector3.new(3000, 0, 0)
check("a warp no mechanic can do is snapped back", waitFor(function()
	return (srv("service", "Guard", "count") or 0) > corr0 and (hrp.Position - before).Magnitude < 60
end, 5) == true, (hrp.Position - before).Magnitude)
task.wait(1)

-- PvP arena (simulated rival: a server dummy that uses the same Combat code)
srv("setStats", { strength = 300, ki = 300, defense = 300, agility = 5, jump = 5 }, "exact")
srv("setPlayTime", 30)
srv("set", "protectionOff", false)
srv("heal")
local arenaC = srv("arenaCenter")
-- 1) outside the arena: safe zone
srv("teleport", Vector3.new(0, 5, 45))
srv("dummy", "RivalOut", hrp.Position + Vector3.new(5, 0, 0), { strength = 300, ki = 300, defense = 300, agility = 5, jump = 5 })
task.wait(0.4)
local dOut = srv("dummyInfo", "RivalOut")
Act:FireServer("melee", Vector3.new(1, 0, 0))
task.wait(0.4)
check("safe zone: a player cannot be hit outside the arena", srv("dummyInfo", "RivalOut").hp == dOut.hp)
local took = srv("dummyAttack", "RivalOut", "melee")
check("safe zone: and cannot be hit by others", took == 0, took)
srv("dummyRemove", "RivalOut")
-- 2) inside, protected newcomer
srv("teleport", arenaC + Vector3.new(0, 3, 0))
check("arena detected (flag replicated)", waitFor(function()
	return char:GetAttribute("InArena") == true and srv("fighter").inArena == true
end, 4) == true)
local rivalPos = hrp.Position + Vector3.new(5, 0, 0)
local function faceRival()
	srv("teleport", rivalPos - Vector3.new(5, 0, 0))
end
srv("dummy", "Rival", rivalPos, { strength = 300, ki = 300, defense = 300, agility = 5, jump = 5 })
task.wait(0.5)
check("new player is protected", refreshState().arena.protected == true)
local dIn = srv("dummyInfo", "Rival")
Act:FireServer("melee", Vector3.new(1, 0, 0))
task.wait(0.4)
check("protected: you cannot hit others", srv("dummyInfo", "Rival").hp == dIn.hp)
took = srv("dummyAttack", "Rival", "melee")
check("protected: others cannot hit you", took == 0, took)
check("shield chip on screen", waitFor(function()
	local c = mainGui:FindFirstChild("Chip_pvp", true)
	return c ~= nil and c.Visible
end, 3) == true)
-- 3) protection off: real PvP with the normalised damage
ok, err = req("SetProtection", { off = true })
check("shield can be switched off", ok and refreshState().arena.protected == false)
srv("heal")
srv("vulnerable")
task.wait(0.4)
dIn = srv("dummyInfo", "Rival")
Act:FireServer("melee", Vector3.new(1, 0, 0))
task.wait(0.4)
local pvpHit = dIn.hp - srv("dummyInfo", "Rival").hp
local wantPvp = Formulas.pvpDamage("melee", 1, 1, dIn.maxHp)
check("PvP melee = 4% of the rival's HP at equal power", near(pvpHit, wantPvp, 0.02), pvpHit .. " (want " .. wantPvp .. ")")
faceRival()
srv("heal")
took = srv("dummyAttack", "Rival", "melee")
check("the rival hits back through the same rules", near(took, Formulas.pvpDamage("melee", 1, 1, srv("fighter").maxHp), 0.02), took)
faceRival()
srv("heal")
Controls.block(true)
task.wait(0.3)
local blockedHit = srv("dummyAttack", "Rival", "melee")
Controls.block(false)
faceRival()
check("blocking works in PvP", near(blockedHit, took * (1 - C.blockReduction), 0.03), blockedHit)
srv("setKi", 1)
task.wait(0.3)
dIn = srv("dummyInfo", "Rival")
Act:FireServer("blast", Vector3.new(1, 0, 0))
task.wait(0.6)
check("ki blast hits the rival", dIn.hp - srv("dummyInfo", "Rival").hp > 0, dIn.hp - srv("dummyInfo", "Rival").hp)
-- a much stronger rival does not one-shot: the power ratio is clamped
srv("dummySet", "Rival", { dstats = { strength = 3e9, ki = 3e9, defense = 300, agility = 5, jump = 5 } })
faceRival()
srv("heal")
took = srv("dummyAttack", "Rival", "melee")
local maxHpMe = srv("fighter").maxHp
check("no one-shots: a far stronger rival deals at most 10% per punch", took > 0 and took <= maxHpMe * C.pvp.melee * C.pvp.ratioMax + 0.01, took / maxHpMe)
srv("dummySet", "Rival", { dstats = { strength = 300, ki = 300, defense = 300, agility = 5, jump = 5 } })
faceRival()
-- autos are off in PvP
req("SetSetting", { key = "autoFight", value = true })
req("SetSetting", { key = "autoCharge", value = true })
srv("setKi", 0.05)
local auto0 = srv("autoAttacks")
task.wait(2)
check("no auto-fight and no auto-charge inside the arena", srv("autoAttacks") == auto0 and srv("fighter").charging == false and char:GetAttribute("AutoTarget") == nil)
req("SetSetting", { key = "autoFight", value = false })
req("SetSetting", { key = "autoCharge", value = false })
-- knock-out: rating, Sparks from the system, no farming
srv("service", "Arena", "forceRush", 120)
task.wait(1.5)
local pvp0 = srv("profile").pvp
sp0 = srv("profile").sparks
faceRival()
srv("dummyHp", "Rival", 1)
Act:FireServer("melee", Vector3.new(1, 0, 0))
check("knock-out: rating up, kill counted, Sparks paid by the system", waitFor(function()
	local pp = srv("profile")
	return pp.pvp.kills == pvp0.kills + 1 and pp.pvp.rating == pvp0.rating + Config.Pvp.winRating and pp.sparks > sp0
end, 4) == true, srv("profile").pvp.rating)
check("K.O. announced to the winner", waitFor(function()
	return combat.arenaKill ~= nil
end, 3) == true)
check("Arena Rush scoreboard counts the K.O.", waitFor(function()
	local last = arenaEvents[#arenaEvents]
	return last ~= nil and last.rush == true and #last.top == 1 and last.top[1].score == 1
end, 4) == true)
srv("dummyRemove", "Rival")
faceRival()
srv("dummy", "Rival", rivalPos, { strength = 300, ki = 300, defense = 300, agility = 5, jump = 5 })
task.wait(0.5)
srv("dummyHp", "Rival", 1)
Act:FireServer("melee", Vector3.new(1, 0, 0))
task.wait(0.8)
local pvp1 = srv("profile").pvp
check("the same rival again gives no rating (no farming)", pvp1.kills == pvp0.kills + 2 and pvp1.rating == pvp0.rating + Config.Pvp.winRating, pvp1.rating)
g0 = srv("profile").gems
srv("service", "Arena", "endRushNow")
check("Arena Rush prize for first place", waitFor(function()
	return srv("profile").gems == g0 + Config.Pvp.rush.prizes[1].gems
end, 3) == true, srv("profile").gems - g0)
-- losing: rating down, respawn
srv("dummyRemove", "Rival")
faceRival()
srv("dummy", "Bully", rivalPos, { strength = 300, ki = 300, defense = 300, agility = 5, jump = 5 })
task.wait(0.5)
srv("vulnerable")
local ratingBefore = srv("profile").pvp.rating
srv("setHp", 1)
srv("dummyAttack", "Bully", "melee")
check("losing a fight: rating down, death counted", waitFor(function()
	local pp = srv("profile").pvp
	return pp.deaths == 1 and pp.rating == ratingBefore - Config.Pvp.lossRating
end, 4) == true, srv("profile").pvp.rating)
srv("dummyRemove", "Bully")
char = player.CharacterAdded:Wait()
hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
hum = char:WaitForChild("Humanoid") :: Humanoid
task.wait(2.5)
check("after a K.O. you respawn in the plaza (outside the arena)", srv("fighter").inArena == false and hrp.Position.Magnitude < 150)
ok, err = req("SetProtection", { off = false })
check("shield back on outside the arena", ok)

-- World boss
srv("freezeNpcs", 900)
srv("setStats", { strength = 400, ki = 400, defense = 2000 }, "exact")
local wb = srv("service", "WorldBoss", "force", 90)
check("world boss spawns, scaled to the strongest player", wb ~= nil and wb.hp == Formulas.worldBossHp(Formulas.meleeDamage(400, 0), 1), wb and wb.hp)
check("world boss announced + chip", waitFor(function()
	local c = mainGui:FindFirstChild("Chip_boss", true)
	return c ~= nil and c.Visible
end, 4) == true)
srv("freezeNpcs", 900)
srv("teleport", wb.pos + Vector3.new(9, 2, 0))
srv("heal")
srv("vulnerable")
task.wait(0.6)
local wbTook = srv("npcHit", "astral_titan", 1)
check("the world boss can hurt you", wbTook > 0)
Act:FireServer("melee", Vector3.new(-1, 0, 0))
task.wait(0.5)
local wbi = srv("service", "WorldBoss", "info")
check("you can hurt the world boss", wbi ~= nil and wbi.hp < wbi.maxHp, wbi and wbi.hp)
g0 = srv("profile").gems
srv("npcSetHp", wbi.id, 1)
Act:FireServer("melee", Vector3.new(-1, 0, 0))
check("world boss down: top contribution tier pays gems", waitFor(function()
	return srv("profile").gems == g0 + Config.WorldBoss.tiers[1].gems
end, 4) == true, srv("profile").gems - g0)
check("world boss leaves after dying", waitFor(function()
	return srv("service", "WorldBoss", "info") == nil
end, 3) == true)

-- Ascension (rebirth)
srv("teleport", Vector3.new(0, 5, 45))
ok, err = req("Rebirth")
check("ascension needs power", not ok and type(err) == "table" and err.key == "msg.need_power", err)
srv("setStats", { strength = Config.Rebirth.basePower })
srv("set", "forms", 3)
g0 = srv("profile").gems
local beforeAsc = srv("profile")
ok = req("Rebirth")
prof = srv("profile")
check("ascended: stats, Sparks, weights and planets reset", ok and prof.rebirths == 1 and prof.stats.strength == Config.StartStat and prof.gear == 1 and #prof.planets == 1 and prof.sparks == 0)
check("ascension keeps forms, techniques, gems (+25)", prof.forms == 3 and prof.techniques.pulse_volley == true and prof.gems == g0 + Config.Rebirth.gems)
check("ascension doubles training", near(prof.perRep, beforeAsc.perRep / Formulas.gearMult(beforeAsc.gear) * 2, 0.005) and waitFor(function()
	return (refreshState().rebirthReq or 0) == Formulas.rebirthRequirement(1)
end, 3) == true)

-- Leaderboards
check("leaderstats show the power", srv("leaderstats") ~= nil)
local okB, boards = req("GetBoards")
check("ranking request returns the three boards", okB and type(boards) == "table" and boards.power ~= nil and boards.rebirths ~= nil and boards.arena ~= nil)

-- Every window opens and draws
for _, name in { "Warrior", "Forms", "Moves", "Auras", "Upgrades", "Ascend", "Travel", "Quests", "Rewards", "Shop", "Ranking", "Invite", "Settings", "Wish" } do
	Windows.open(name)
	task.wait(0.25)
	local frame = mainGui:FindFirstChild(name .. "Window", true)
	local body = frame and frame:FindFirstChild("Body")
	check("window draws: " .. name, frame ~= nil and frame.Visible and body ~= nil and #body:GetDescendants() > 6, body and #body:GetDescendants())
end
check("a window blocks combat input (no punching through menus)", Controls.enabled == false)
Windows.close()
task.wait(0.3)
check("closing the window gives input back", Controls.enabled == true)

-- Languages: switch live, every language has every key
-- (the saved preference is restored at the end: this test used to leave "en" saved in the
-- Studio profile, so the HUD stayed English afterwards even for a Spanish tester)
local langBefore = Net.get("lang")
ok = req("SetLanguage", { lang = "es" })
check("language switch re-renders the HUD", ok and waitFor(function()
	return Lang.code == "es" and (function()
		for _, d in mainGui:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == Locale.t("es", "hud.power") then
				return true
			end
		end
		return false
	end)()
end, 4) == true, Lang.code)
local allLang = true
for _, l in Locale.Languages do
	local pack = Locale.pack(l.code)
	if not pack or not pack["hud.power"] or not pack["msg.arena_enter"] then
		allLang = false
	end
end
check("12 language packs loaded on the client", allLang and #Locale.Languages == 12)
check("proper names come from Names in every language", Locale.t("ja", "form.kindled") == "Kindled" and Locale.t("es", "planet.kaldera") == "Kaldera")
ok = req("SetLanguage", { lang = "xx" })
check("unknown language rejected", not ok)
req("SetLanguage", { lang = if type(langBefore) == "string" then langBefore else "" })
task.wait(0.6)

---------------------------------------------------------------------------
-- Death and respawn
---------------------------------------------------------------------------
srv("setStats", { strength = 150, ki = 150, defense = 3000 })
srv("freezeNpcs", 900)
srv("vulnerable")
srv("setStats", { defense = 5 })
task.wait(0.6)
srv("place", "camp", 2, 0)
task.wait(0.5)
srv("vulnerable")
local lethal = srv("npcHit", "raider", 1e6)
check("lethal hit kills the player", lethal > 0 and waitFor(function()
	return hum.Health <= 0
end, 3) == true, lethal)
local newChar = player.CharacterAdded:Wait()
char = newChar
hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
hum = char:WaitForChild("Humanoid") :: Humanoid
task.wait(2.5)
f = srv("fighter")
check("respawned at the planet plaza with full ki", f.alive and f.ki > 0.9 and hrp.Position.Magnitude < 150, hrp.Position)
check("respawn shield active", f.invulnerable == true)
check("stats survive death", srv("profile").stats.strength == 150 + Config.StartStat or srv("profile").stats.strength == 150)

---------------------------------------------------------------------------
-- Round 2: seeds (hourly stock), battle pass, cosmetics, special forms / dark attacks
---------------------------------------------------------------------------
srv("set", "sparks", 1e13)
ok = req("BuySeed", { id = "vigor_seed" })
check("seed bought with Sparks", ok and srv("profile").items.vigor_seed == 1 and srv("profile").sparks < 1e13)
for _ = 1, Config.SeedById.vigor_seed.stockPerHour - 1 do
	req("BuySeed", { id = "vigor_seed" })
end
ok, err = req("BuySeed", { id = "vigor_seed" })
check("seed stock runs out for the hour", not ok and type(err) == "table" and err.key == "msg.seed_stock", err)
srv("setHp", 5)
ok = req("UseSeed", { id = "vigor_seed" })
check("Vigor Seed heals to full", ok and srv("fighter").hp >= srv("fighter").maxHp - 1, srv("fighter").hp)
ok, err = req("UseSeed", { id = "vigor_seed" })
check("Vigor Seed has a cooldown", not ok and type(err) == "table" and err.key == "msg.seed_cooldown", err)
ok = req("BuySeed", { id = "titan_seed" })
ok = req("UseSeed", { id = "titan_seed" }) and ok
check("Titan Seed buff is on", ok and srv("profile").buffs.titan > os.time())
ok, err = req("UseSeed", { id = "spark_seed" })
check("cannot use a seed you do not have", not ok and type(err) == "table" and err.key == "msg.no_seed", err)
local pk = srv("receipt", "SeedSampler", "test-seed-1")
check("Seed Sampler receipt gives one of each (no cap, no stock)", pk == "PurchaseGranted" and srv("profile").items.spark_seed == 1 and srv("profile").items.titan_seed == 1, pk)

srv("service", "Season", "forceActive")
srv("service", "Season", "addXp", Config.BattlePass.xpPerTier * 3)
check("battle pass reaches tier 3", waitFor(function()
	return Net.state and Net.state.season and Net.state.season.tier == 3
end, 4) == true)
ok = req("ClaimPass", { track = "free", tier = 3 })
check("free tier claimed", ok and srv("profile").bp.s1.free["3"] == true)
ok = req("ClaimPass", { track = "free", tier = 3 })
check("a tier cannot be claimed twice", not ok)
ok, err = req("ClaimPass", { track = "premium", tier = 1 })
check("premium track needs the premium product", not ok and type(err) == "table" and err.key == "msg.bp_need_premium", err)
ok = req("ClaimPass", { track = "free", tier = 4 })
check("locked tier refused", not ok)
pk = srv("receipt", "BattlePassS1", "test-bp-1")
check("premium receipt processed", pk == "PurchaseGranted" and srv("profile").bp.s1.premium == true, pk)
ok = req("ClaimPass", { track = "premium", tier = 1 })
check("premium tier claimed after buying", ok)
pk = srv("receipt", "TierSkip", "test-skip-1")
check("tier skip gives one tier", pk == "PurchaseGranted" and waitFor(function()
	return Net.state ~= nil and Net.state.season ~= nil and Net.state.season.tier == 4
end, 4) == true, pk)

srv("set", "bossKills", { bramble_king = 1 })
srv("service", "Cosmetics", "sync")
check("first boss earns the Wanderer skin and Zephyr Puff", srv("profile").skins.wanderer == true and srv("profile").mounts.zephyr_puff == true)
ok = req("EquipSkin", { id = "wanderer" })
check("skin equipped and replicated", ok and waitFor(function()
	return char:GetAttribute("Skin") == "wanderer"
end, 3) == true)
check("skin pieces are built on the avatar", waitFor(function()
	return char:FindFirstChild("KiwSkin") ~= nil
end, 4) == true)
ok = req("EquipSkin", { id = "timewalker" })
check("cannot equip a skin you do not own", not ok)
ok = req("EquipMount", { id = "zephyr_puff" })
check("mount equipped", ok and srv("profile").mount == "zephyr_puff")
srv("pass", "SkinPack", true)
srv("service", "Cosmetics", "sync")
check("SkinPack unlocks every skin", srv("profile").skins.silent_titan == true)
srv("pass", "SkinPack", false)

local tech0 = srv("profile").techniques
srv("setStats", { strength = 3_000_000, ki = 3_000_000 })
ok, err = req("BuyTechnique", { id = "umbral_volley" })
check("dark attack needs the boss kills or the pass", not ok and type(err) == "table" and err.key == "msg.need_special", err)
srv("pass", "DarkArts", true)
ok = req("BuyTechnique", { id = "umbral_volley" })
check("DarkArts lets you learn it (Sparks and power still apply)", ok and srv("profile").techniques.umbral_volley == true)
srv("pass", "DarkArts", false)
tech0.umbral_volley = nil
srv("set", "techniques", tech0)

srv("set", "bossKills", {})
srv("set", "rebirths", 3)
srv("setStats", { strength = 1e14, ki = 1e14 })
local unboundIndex = Config.FormById.unbound.index
check("Unbound stays locked without Korrath kills or the pass", srv("service", "Combat", "refreshForms") == unboundIndex - 1)
srv("pass", "UnboundForm", true)
check("Unbound form unlocks with the pass (power and ascensions still required)", srv("service", "Combat", "refreshForms") == unboundIndex)
srv("pass", "UnboundForm", false)

---------------------------------------------------------------------------
-- Budgets / errors
---------------------------------------------------------------------------
check("pooled effect parts within budget", Fx.alive <= Config.Budget.clientFxParts, Fx.alive .. " alive / " .. Fx.created .. " created")
-- Lua heap of this client VM (gcinfo is per VM; the Stats tags are process-wide in Studio)
local luaMb = gcinfo() / 1024
check("client Lua heap within budget", luaMb < Config.Budget.luaHeapMb, string.format("%.1f MB", luaMb))
check("no stuck projectiles", srv("projectiles") == 0 and CombatFx.shotCount() <= 1, CombatFx.shotCount())
check("locale: every HUD key resolves in English", Locale.t("en", "hud.power") == "POWER" and Locale.t("en", "planet.verdia") == "Verdia" and Locale.t("en", "msg.need_sparks") == "Not enough Sparks!")
task.wait(0.5)
check("no client errors", #clientErrors == 0, table.concat(clientErrors, " || "))

srv("report", table.concat(lines, "\n"))
