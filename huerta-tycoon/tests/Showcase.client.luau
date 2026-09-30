-- Visual showcase (showcase.project.json): every time the runner resizes the Studio window (it takes a screenshot
-- 7 s later) the camera moves to the next scene. Narrow windows (tablet / phone sizes) always show plain gameplay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local camera = workspace.CurrentCamera
local UI = script.Parent:WaitForChild("Client"):WaitForChild("UI")
local State = require(UI:WaitForChild("State"))
local Panels = require(UI:WaitForChild("Panels"))
local Fx = require(UI:WaitForChild("Fx"))
local Juice = require(UI:WaitForChild("Juice"))
local Ambience = require(UI:WaitForChild("Ambience"))
local WorldLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldLayout"))
local Config = require(ReplicatedStorage.Shared.Config)
local ev = ReplicatedStorage:WaitForChild("__Showcase") :: RemoteEvent

while not State.data or not State.data.plotIndex do
	task.wait(0.2)
end
local plot = workspace:WaitForChild("Plots"):WaitForChild("Plot_" .. State.data.plotIndex)
local _, depth = WorldLayout.plotSize()
local halfD = depth / 2
local spawnPart = plot:WaitForChild("Spawn") :: BasePart
local plotCF = spawnPart.CFrame * CFrame.new(0, -1.1, halfD - WorldLayout.SPAWN_INSET)

local function look(from: Vector3, at: Vector3): CFrame
	return CFrame.lookAt(from, at)
end
local function inPlot(from: Vector3, at: Vector3): CFrame
	return look((plotCF * CFrame.new(from)).Position, (plotCF * CFrame.new(at)).Position)
end

type Scene = { name: string, cam: CFrame?, enter: (() -> ())?, leave: (() -> ())?, loop: (() -> ())? }
local scenes: { Scene } = {
	{ name = "entrance from the path", cam = inPlot(Vector3.new(7, 8, -halfD - 34), Vector3.new(-5, 4, -halfD)) },
	{ name = "plot overview", cam = inPlot(Vector3.new(-40, 36, -44), Vector3.new(0, 2, 6)) },
	{ name = "crops close-up", cam = inPlot(Vector3.new(-16, 11, -halfD + 4), Vector3.new(2, 2, -8)) },
	{ name = "growth stages", cam = inPlot(Vector3.new(0, 17, -14), Vector3.new(0, 2, 10)) },
	{ name = "market square", cam = look(Vector3.new(58, 40, 62), Vector3.new(0, 5, 0)) },
	{ name = "shops", cam = look(Vector3.new(-2, 9, 15.5), Vector3.new(-21, 7, 27)) },
	{ name = "sell stand + board", cam = look(Vector3.new(-14, 11, -10), Vector3.new(30, 9, 16)) },
	{ name = "whole map", cam = look(Vector3.new(250, 190, 250), Vector3.new(0, 0, 0)) },
}
for _, f in WorldLayout.Features do
	local fx, fz = WorldLayout.featureCenter(f)
	local cf = CFrame.lookAt(Vector3.new(fx, 0, fz), Vector3.new(0, 0, 0))
	table.insert(scenes, { name = "landmark " .. f.id, cam = look((cf * CFrame.new(20, 16, -50)).Position, (cf * CFrame.new(0, 6, 0)).Position) })
end
table.insert(scenes, {
	name = "seed shop panel",
	enter = function()
		Panels.open("Shop")
	end,
	leave = function()
		Panels.close()
	end,
})
table.insert(scenes, {
	name = "harvest fx + coins + confetti",
	cam = inPlot(Vector3.new(-3, 9, -halfD + 2), Vector3.new(0, 3, -6)),
	enter = function()
		task.delay(5.6, function()
			ev:FireServer("sell")
			Juice.confetti(30)
		end)
	end,
	loop = function()
		local tiles = plot.Tiles:GetChildren()
		local tile = tiles[math.random(1, 12)]
		local seed = Config.Seeds[math.random(1, #Config.Seeds)]
		local muts = { nil, nil, "Golden", "Rainbow", "Shocked", nil }
		Fx.harvest(tile.Position + Vector3.new(0, 4, 0), seed.id, muts[math.random(1, 6)], seed.sellValue)
	end,
	leave = function()
		ev:FireServer("refill")
	end,
})
table.insert(scenes, {
	name = "thunderstorm",
	cam = inPlot(Vector3.new(-40, 36, -44), Vector3.new(0, 2, 6)),
	enter = function()
		ev:FireServer("weather", "Thunderstorm")
	end,
})
table.insert(scenes, {
	name = "golden hour",
	cam = inPlot(Vector3.new(7, 8, -halfD - 34), Vector3.new(-5, 4, -halfD)),
	enter = function()
		ev:FireServer("weather", "GoldenHour")
	end,
	leave = function()
		ev:FireServer("weather", nil)
	end,
})

-- ===== lowest graphics quality: try the real Studio setting, and also switch off by hand everything that
-- quality level 1 drops (shadows, post-processing, clouds) so the capture is honest either way =====
local Lighting = game:GetService("Lighting")
local lowOn = false
local savedLevel: any = nil
local function lowQuality(on: boolean)
	if on == lowOn then
		return
	end
	lowOn = on
	local okSet, errSet = pcall(function()
		local rendering = (settings() :: any).Rendering
		if on then
			savedLevel = rendering.QualityLevel
			rendering.QualityLevel = Enum.QualityLevel.Level01
		elseif savedLevel ~= nil then
			rendering.QualityLevel = savedLevel
		end
	end)
	print("[TEST] showcase low quality " .. tostring(on) .. ": settings().Rendering " .. (if okSet then "applied" else "not allowed (" .. tostring(errSet) .. ")") .. "; simulating by hand")
	Lighting.GlobalShadows = not on
	for _, e in Lighting:GetChildren() do
		if e:IsA("PostEffect") then
			e.Enabled = not on
		end
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Enabled = not on
	end
end
for _, low in {
	{ "entrance", inPlot(Vector3.new(7, 8, -halfD - 34), Vector3.new(-5, 4, -halfD)) },
	{ "plot overview", inPlot(Vector3.new(-40, 36, -44), Vector3.new(0, 2, 6)) },
	{ "crops", inPlot(Vector3.new(-16, 11, -halfD + 4), Vector3.new(2, 2, -8)) },
	{ "market square", look(Vector3.new(58, 40, 62), Vector3.new(0, 5, 0)) },
	{ "whole map", look(Vector3.new(250, 190, 250), Vector3.new(0, 0, 0)) },
} do
	table.insert(scenes, {
		name = "LOW " .. low[1],
		cam = low[2],
		enter = function()
			lowQuality(true)
		end,
	})
end

local current: Scene? = nil
local index = 0
local maxY = if camera.ViewportSize.X >= 1250 then camera.ViewportSize.Y else 0

local function apply(scene: Scene?)
	if current and current.leave then
		current.leave()
	end
	current = scene
	if scene and scene.cam then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = scene.cam
	else
		camera.CameraType = Enum.CameraType.Custom
	end
	if scene and scene.enter then
		scene.enter()
	end
end

RunService.RenderStepped:Connect(function()
	if current and current.cam then
		camera.CFrame = current.cam
	end
end)
task.spawn(function()
	while true do
		task.wait(0.45)
		if current and current.loop then
			current.loop()
		end
	end
end)

print("[TEST] showcase client ready, " .. #scenes .. " scenes; ambience spins=" .. Ambience.counts.spins .. " bobs=" .. Ambience.counts.bobs .. " floats=" .. Ambience.counts.floats)

local token = 0
local started = os.clock()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	if os.clock() - started < 4 then
		return
	end
	token += 1
	local my = token
	task.delay(0.4, function()
		if my ~= token then
			return
		end
		local vp = camera.ViewportSize
		if vp.X < 1250 then
			-- tablet / phone sized window: plain gameplay view at the plot
			lowQuality(false)
			apply(nil)
			ev:FireServer("home")
			print(string.format("[TEST] showcase gameplay view at %dx%d", vp.X, vp.Y))
			return
		end
		-- the runner shrinks the window 1 px per shot: the scene is how far we are below the tallest size seen
		-- (so the first, tallest size is always the plain gameplay view, whatever size Studio opened with)
		maxY = math.max(maxY, vp.Y)
		index = math.round(maxY - vp.Y)
		local scene = scenes[index]
		if not scene or string.sub(scene.name, 1, 3) ~= "LOW" then
			lowQuality(false)
		end
		apply(scene)
		print(string.format("[TEST] showcase scene %d: %s (pops so far %d)", index, if scene then scene.name else "gameplay", Ambience.counts.pops))
	end)
end)
