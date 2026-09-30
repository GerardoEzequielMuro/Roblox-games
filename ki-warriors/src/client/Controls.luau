--!nonstrict
-- Player input -> combat / training intents. Keyboard + mouse here; the touch buttons
-- (UI/TouchControls) call the same Controls.* functions. Local cooldowns mirror the server's
-- so we don't spam remotes; the server is still the authority on every action.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Fx = require(script.Parent.Fx)
local Flight = require(script.Parent.Flight)
local CharFx = require(script.Parent.CharFx)
local NpcRender = require(script.Parent.NpcRender)

local C = Config.Combat
local Controls = {}

local player = Players.LocalPlayer
local isTouch = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) or workspace:GetAttribute("ForceTouchLayout") == true
Controls.isTouch = isTouch

-- next time each action may fire (client mirror of the server cooldowns)
local nextAt: { [string]: number } = {}
Controls.nextAt = nextAt
Controls.cooldownOf = { melee = C.meleeCooldown, blast = C.blastCooldown, beam = C.beamCooldown, dash = C.dashCooldown, form = 0.8 }
for _, t in Config.Techniques do
	Controls.cooldownOf["t_" .. t.id] = t.cooldown
end
Controls.beamStartedAt = nil :: number?
Controls.charging = false
Controls.blocking = false
Controls.enabled = true -- false while a window / cinematic owns the input
Controls.heldPunch = true
Controls.autoWalking = false

local used = Instance.new("BindableEvent")
Controls.Used = used.Event -- (action: string) for the HUD, tutorial and tests

local function ready(name: string): boolean
	local now = os.clock()
	if (nextAt[name] or 0) > now then
		return false
	end
	nextAt[name] = now + Controls.cooldownOf[name]
	return true
end

local function me(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil, nil, nil
	end
	return char, hum, char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Controls.ki(): number
	local char = player.Character
	return (char and char:GetAttribute("Ki")) or 0
end

---------------------------------------------------------------------------
-- Aim
---------------------------------------------------------------------------
-- Living things we may aim at: enemy roots, server dummies, other players.
local function targets(): { Vector3 }
	local list = {}
	for root in NpcRender.visuals do
		table.insert(list, root.Position)
	end
	local dummies = workspace:FindFirstChild("Dummies")
	if dummies then
		for _, m in dummies:GetChildren() do
			local r = m:FindFirstChild("HumanoidRootPart")
			if r then
				table.insert(list, r.Position)
			end
		end
	end
	local myChar = player.Character
	if myChar and myChar:GetAttribute("InArena") == true then
		for _, plr in Players:GetPlayers() do
			if plr ~= player and plr.Character and plr.Character:GetAttribute("InArena") == true then
				local r = plr.Character:FindFirstChild("HumanoidRootPart")
				if r then
					table.insert(list, r.Position)
				end
			end
		end
	end
	return list
end

-- Direction of the next shot: mouse ray (PC) or camera look (touch), snapped to the enemy
-- closest to that ray; falls back to the server's auto-fight target, then to the ray itself.
function Controls.aim(): Vector3
	local _, _, root = me()
	local cam = workspace.CurrentCamera
	if not root or not cam then
		return Vector3.new(0, 0, -1)
	end
	local origin = root.Position + Vector3.new(0, 0.6, 0)
	local rayO, rayD
	if isTouch then
		rayO, rayD = cam.CFrame.Position, cam.CFrame.LookVector
	else
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		rayO, rayD = ray.Origin, ray.Direction
	end
	local best, bestScore = nil, if isTouch then 26 else 11
	for _, p in targets() do
		local t = (p - rayO):Dot(rayD)
		if t > 0 and (p - origin).Magnitude < 230 then
			local off = (p - (rayO + rayD * t)).Magnitude
			-- allow more slack far away
			local score = off - t * 0.02
			if score < bestScore then
				best, bestScore = p, score
			end
		end
	end
	local point = best
	if not point then
		local hit = workspace:Raycast(rayO, rayD * 600)
		point = if hit then hit.Position else rayO + rayD * 400
	end
	local dir = point - origin
	if dir.Magnitude < 1 then
		return root.CFrame.LookVector
	end
	dir = dir.Unit
	-- on the ground, don't shoot into the floor at your feet
	if not Flight.active and dir.Y < -0.5 then
		dir = (dir * Vector3.new(1, 0, 1) + Vector3.new(0, -0.5, 0)).Unit
	end
	return dir
end

local function faceDir(dir: Vector3)
	local _, _, root = me()
	if root and not Flight.active then
		local flat = dir * Vector3.new(1, 0, 1)
		if flat.Magnitude > 0.05 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function Controls.punch()
	local _, _, root = me()
	if not root or not Controls.enabled or Controls.blocking then
		return
	end
	if not ready("melee") then
		return
	end
	-- face the nearest enemy in reach so the hit connects where the player expects
	local near = NpcRender.nearest(root.Position, C.meleeRange + 8)
	local aim: any = nil
	if near then
		local flat = (near.Position - root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude > 0.1 then
			aim = flat.Unit
			faceDir(aim)
		end
	end
	CharFx.punchNow()
	Net.act("melee", aim)
	used:Fire("melee")
end

function Controls.blast()
	local _, _, root = me()
	if not root or not Controls.enabled or Controls.blocking then
		return
	end
	if Controls.ki() < C.blastCost then
		used:Fire("noKi")
		return
	end
	if not ready("blast") then
		return
	end
	local dir = Controls.aim()
	faceDir(dir)
	Net.act("blast", dir)
	used:Fire("blast")
end

function Controls.beamBegin()
	local _, _, root = me()
	if not root or not Controls.enabled or Controls.blocking or Controls.beamStartedAt then
		return
	end
	if (nextAt.beam or 0) > os.clock() then
		return
	end
	if Controls.ki() < C.beamCostMin then
		used:Fire("noKi")
		return
	end
	Controls.beamStartedAt = os.clock()
	Net.act("beamStart")
	used:Fire("beamStart")
end

function Controls.beamEnd()
	local started = Controls.beamStartedAt
	if not started then
		return
	end
	Controls.beamStartedAt = nil
	local _, _, root = me()
	if not root then
		Net.act("beamRelease", nil)
		return
	end
	local dir = Controls.aim()
	faceDir(dir)
	if os.clock() - started >= C.beamMinCharge then
		nextAt.beam = os.clock() + C.beamCooldown
		used:Fire("beam")
	end
	Net.act("beamRelease", dir)
end

function Controls.block(on: boolean)
	if on and not Controls.enabled then
		return
	end
	if Controls.blocking ~= on then
		Controls.blocking = on
		Net.act("block", on)
		if on then
			used:Fire("block")
		end
	end
end

function Controls.charge(on: boolean)
	if on and (not Controls.enabled or not me()) then
		return
	end
	if Controls.charging ~= on then
		Controls.charging = on
		Net.act("charge", on)
		if on then
			used:Fire("charge")
		end
	end
end

function Controls.dash()
	local _, hum, root = me()
	if not root or not hum or not Controls.enabled then
		return
	end
	if Controls.ki() < C.dashCost then
		used:Fire("noKi")
		return
	end
	if not ready("dash") then
		return
	end
	local cam = workspace.CurrentCamera
	local dir = hum.MoveDirection
	if Flight.active and cam then
		dir = if dir.Magnitude > 0.05 then cam.CFrame.LookVector else root.CFrame.LookVector
	elseif dir.Magnitude < 0.05 then
		dir = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, Fx.folder }
	local dist = C.dashDistance
	local hit = workspace:Raycast(root.Position, dir * dist, params)
	if hit then
		dist = math.max(0, (hit.Position - root.Position).Magnitude - 3)
	end
	Net.act("dash")
	root.CFrame = root.CFrame + dir * dist
	root.AssemblyLinearVelocity = dir * 30
	Fx.kick(9)
	Fx.sound("swing", 0.3, 1.2)
	used:Fire("dash")
end

function Controls.toggleFly()
	if not Controls.enabled and not Flight.active then
		return
	end
	Flight.toggle()
	if Flight.active then
		used:Fire("fly")
	end
end

-- Transform into the best unlocked form, or drop back to base.
function Controls.transform(index: number?)
	local char = me()
	if not char or not Controls.enabled then
		return
	end
	local current = char:GetAttribute("Form") or 0
	local want = index
	if want == nil then
		local best = Net.get("forms") or 0
		local preferred = Controls.preferredForm
		if preferred and preferred >= 1 and preferred <= best then
			best = preferred
		end
		want = if current > 0 then 0 else best
	end
	if want == current then
		return
	end
	if want > 0 and not ready("form") then
		return
	end
	Net.act("form", want)
	used:Fire("form")
end
Controls.preferredForm = nil :: number?

function Controls.technique(id: string)
	local _, _, root = me()
	local t = Config.TechniqueById[id]
	if not root or not t or not Controls.enabled then
		return
	end
	local owned = Net.get("techniques")
	if not owned or not owned[id] then
		return
	end
	if Controls.ki() < t.kiCost then
		used:Fire("noKi")
		return
	end
	if not ready("t_" .. id) then
		return
	end
	local dir = Controls.aim()
	faceDir(dir)
	if id == "meteor_dive" then
		-- hop up, then the server slams
		root.AssemblyLinearVelocity = Vector3.new(0, 70, 0)
		task.delay(0.22, function()
			local _, _, r = me()
			if r then
				r.AssemblyLinearVelocity = Vector3.new(0, -150, 0)
			end
		end)
	end
	Net.act("tech", { id = id, dir = dir })
	used:Fire("tech")
end

function Controls.setStat(stat: string)
	local s = Net.state
	if s and s.settings and s.settings.stat ~= stat then
		s.settings.stat = stat -- optimistic
		Net.refresh()
		task.spawn(Net.request, "SetStat", { stat = stat })
	end
end

function Controls.toggleSetting(key: string)
	local s = Net.state
	if s and s.settings then
		local value = not s.settings[key]
		s.settings[key] = value
		Net.refresh()
		task.spawn(Net.request, "SetSetting", { key = key, value = value })
	end
end

---------------------------------------------------------------------------
-- Keyboard / mouse
---------------------------------------------------------------------------
local lastSpace = 0
local function overGui(pos: Vector3): boolean
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return false
	end
	local inset = GuiService:GetGuiInset()
	for _, o in gui:GetGuiObjectsAtPosition(pos.X, pos.Y - inset.Y) do
		if o:IsA("GuiButton") or o:GetAttribute("BlocksClicks") == true then
			return true
		end
	end
	return false
end

function Controls.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not processed and not overGui(input.Position) then
				Controls.punch()
			end
			return
		end
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Q then
			Controls.blast()
		elseif key == Enum.KeyCode.R then
			Controls.beamBegin()
		elseif key == Enum.KeyCode.F then
			Controls.block(true)
		elseif key == Enum.KeyCode.E then
			Controls.dash()
		elseif key == Enum.KeyCode.C then
			Controls.charge(true)
		elseif key == Enum.KeyCode.G then
			Controls.transform()
		elseif key == Enum.KeyCode.H then
			Controls.toggleFly()
		elseif key == Enum.KeyCode.T then
			Controls.toggleSetting("autoTrain")
		elseif key == Enum.KeyCode.Space then
			local _, hum = me()
			local now = os.clock()
			if hum then
				if Flight.active then
					if now - lastSpace < 0.28 then
						Flight.stop()
					end
				elseif hum.FloorMaterial == Enum.Material.Air then
					Controls.toggleFly()
				end
			end
			lastSpace = now
		elseif key == Enum.KeyCode.Z or key == Enum.KeyCode.X or key == Enum.KeyCode.V then
			for _, t in Config.Techniques do
				if Enum.KeyCode[t.key] == key then
					Controls.technique(t.id)
				end
			end
		else
			local n = key.Value - Enum.KeyCode.One.Value + 1
			if n >= 1 and n <= #Config.Stats then
				Controls.setStat(Config.Stats[n])
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.R then
			Controls.beamEnd()
		elseif key == Enum.KeyCode.F then
			Controls.block(false)
		elseif key == Enum.KeyCode.C then
			Controls.charge(false)
		end
	end)
	-- hold left mouse to keep punching
	RunService.Heartbeat:Connect(function()
		if not isTouch and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not UserInputService:GetFocusedTextBox() then
			local m = UserInputService:GetMouseLocation()
			if (nextAt.melee or 0) <= os.clock() and not overGui(Vector3.new(m.X, m.Y, 0)) and Controls.heldPunch then
				Controls.punch()
			end
		end
		-- auto-fight: walk towards the target the server picked (unless the player steers)
		local char, hum, root = me()
		if char and hum and root then
			local target = char:GetAttribute("AutoTarget")
			if typeof(target) == "Vector3" and not Flight.active then
				local flat = (target - root.Position) * Vector3.new(1, 0, 1)
				if flat.Magnitude > C.meleeRange - 3.5 then
					hum:MoveTo(root.Position + flat.Unit * math.min(flat.Magnitude, 12))
				end
				Controls.autoWalking = true
			elseif Controls.autoWalking then
				Controls.autoWalking = false
				hum:MoveTo(root.Position)
			end
		end
	end)
	-- reset held states on respawn
	player.CharacterAdded:Connect(function()
		Controls.charging = false
		Controls.blocking = false
		Controls.beamStartedAt = nil
	end)
end

return Controls
