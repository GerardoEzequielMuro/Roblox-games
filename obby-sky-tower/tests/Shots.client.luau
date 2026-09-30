-- Screenshot camera tour (shots.project.json / shotslow.project.json only). Every time the runner
-- resizes the window (it passes near-identical sizes, one per view) the camera moves to the next
-- view. Views, in order (38):
--   1      lobby as the player sees it on spawn (HUD on)
--   2      lobby + tower base, wide
--   3..12  one wide view per world of tower 1
--   13..22 one player-height view per world of tower 1 (standing on pad 4 of the world)
--   23..27 close-ups: spinner, lava, moving, laser, wind
--   28     a shop deck on the route (pedestals with prices)
--   29     summit of tower 1: gift preview + portal
--   30     the Winner's Lounge (free items)
--   31     base island of tower 2 (where the portal drops you)
--   32..34 wide view of towers 2, 5 and 10 (their own sky)
--   35..37 player-height view in towers 2, 5 and 10
--   38     a checkpoint being reached (pads 1..3 done, celebration on screen, HUD on)
-- With the Workspace attribute ShotsLow the same tour runs the way a player on minimum graphics
-- sees it: quality level 1 when Studio allows it, and in any case no shadows, no post effects,
-- no atmosphere, no clouds, plus the game's own lite profile (ForceLite).
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local towers = workspace:WaitForChild("Towers")
local SPACING = 2400
local STAGES = 100

local function towerFolder(t: number): Instance
	return towers:WaitForChild("Tower_" .. t, 60) :: Instance
end
local function axisOf(t: number): Vector3
	return Vector3.new((t - 1) * SPACING, 0, 0)
end
-- pad of global stage g
local function pad(g: number): Vector3
	local t = math.clamp((g - 1) // STAGES + 1, 1, 10)
	local cps = towerFolder(t):WaitForChild("Checkpoints")
	return (cps:WaitForChild("Checkpoint_" .. g, 30) :: BasePart).Position
end
local function stageModel(t: number, kind: string): Model?
	for _, m in towerFolder(t):GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Kind") == kind and ((m:GetAttribute("Slot") or m:GetAttribute("Stage") or 0) :: number) > 10 then
			return m
		end
	end
	return nil
end
local function around(t: number, target: Vector3, dist: number, up: number): CFrame
	local out = Vector3.new(target.X, 0, target.Z) - axisOf(t)
	out = if out.Magnitude > 1 then out.Unit else Vector3.new(0, 0, 1)
	return CFrame.lookAt(target + out * dist + Vector3.new(0, up, 0), target)
end
-- third-person camera of a player standing on pad g and facing pad g + 1
local function playerView(g: number): CFrame
	local a, b = pad(g), pad(g + 1)
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local eye = a + Vector3.new(0, 9, 0) - dir * 15
	return CFrame.lookAt(eye, a + dir * 26 + Vector3.new(0, (b.Y - a.Y) * 0.4 + 3, 0))
end
local function modelView(t: number, name: string, dist: number, up: number, fallback: number): CFrame
	local m = towerFolder(t):FindFirstChild(name, true)
	local c = if m and m:IsA("Model") then m:GetBoundingBox().Position elseif m and m:IsA("BasePart") then m.Position else pad(fallback)
	return around(t, c, dist, up)
end

-- the character never plays during the tour: it stays frozen in the lobby (so no screenshot shows
-- a body that fell off), except in the last view, which really walks pads 1..3
local function hold(on: boolean)
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	root.Anchored = on
end

local views = {}
local function add(hud: boolean, fn: () -> CFrame, before: (() -> ())?)
	table.insert(views, { hud = hud, fn = fn, before = before })
end
add(true, function() return CFrame.lookAt(Vector3.new(0, 11, 131), Vector3.new(0, 16, 60)) end)
add(false, function() return CFrame.lookAt(Vector3.new(-105, 58, 225), Vector3.new(0, 38, 20)) end)
for w = 1, 10 do
	add(false, function() return around(1, pad((w - 1) * 10 + 5), 120, 30) end)
end
for w = 1, 10 do
	add(false, function() return playerView((w - 1) * 10 + 4) end)
end
for _, kind in { "spinner", "lava", "moving", "laser", "wind" } do
	add(false, function()
		local m = stageModel(1, kind)
		local c = if m then m:GetBoundingBox().Position else pad(50)
		return around(1, c, 40, 16)
	end)
end
add(false, function() return modelView(1, "Shop", 30, 14, 25) end)
add(false, function()
	-- the summit room as you walk into it from pad 100: gift preview and portal ahead
	local p = pad(100)
	local out = Vector3.new(p.X, 0, p.Z).Unit
	return CFrame.lookAt(p - out * 16 + Vector3.new(0, 15, 0), p + out * 36 + Vector3.new(0, 7, 0))
end)
add(false, function() return modelView(1, "Lounge", 46, 26, 100) end)
add(false, function() return modelView(2, "Base", 44, 22, 101) end)
for _, t in { 2, 5, 10 } do
	add(false, function() return around(t, pad((t - 1) * STAGES + 35), 125, 30) end)
end
for _, t in { 2, 5, 10 } do
	add(false, function() return playerView((t - 1) * STAGES + 64) end)
end
add(true, function() return playerView(3) end, function()
	-- really reach pads 1..3 so the flags, green pads, beacon and celebration are on screen
	local char = player.Character
	if char then
		hold(false)
		for k = 1, 3 do
			char:PivotTo(CFrame.new(pad(k) + Vector3.new(0, 4, 0)))
			task.wait(1.1)
		end
	end
end)

if workspace:GetAttribute("ShotsLow") then
	local okReal, err = pcall(function()
		(settings() :: any).Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	print("[TEST] low graphics: settings().Rendering.QualityLevel " .. (if okReal then "applied" else "not allowed (" .. tostring(err) .. "), simulated by hand"))
	workspace:SetAttribute("ForceLite", true)
	task.spawn(function()
		while true do
			Lighting.GlobalShadows = false
			for _, fx in Lighting:GetChildren() do
				if fx:IsA("PostEffect") then
					fx.Enabled = false
				elseif fx:IsA("Atmosphere") then
					fx.Density = 0
					fx.Haze = 0
					fx.Glare = 0
				end
			end
			local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
			if clouds then
				clouds.Enabled = false
			end
			task.wait(0.25)
		end
	end)
end

local i = 0
local busy = false
local function nextView()
	if busy then
		return
	end
	busy = true
	i += 1
	local v = views[((i - 1) % #views) + 1]
	local gui = player.PlayerGui:FindFirstChild("SkyTowerUI")
	if gui then gui.Enabled = v.hud end
	local ok, err = pcall(function()
		if v.before then v.before() end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = v.fn()
		-- the sky follows the camera; the character stays where it is
		camera.Focus = camera.CFrame * CFrame.new(0, 0, -30)
	end)
	print(("[TEST] shot view %d of %d%s"):format(i, #views, if ok then "" else " FAILED: " .. tostring(err)))
	busy = false
end
task.wait(3)
hold(true)
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	task.spawn(nextView)
end)
